--[[
	Physical grab / hold / throw input. One strict state machine for every platform:

	  Idle --press on an object--> Requesting --server says ok--> Holding --release--> Idle

	  PC:      press Left Mouse on an object, keep holding to carry, release to throw.
	           Q (or Right Mouse in first person) sets it down gently.
	  Gamepad: same with R2; B drops.
	  Mobile:  tap GRAB to pick up, tap THROW to throw, DROP to set down.

	While holding, a dotted arc + landing ring predicts the throw (gold = it lands in a bin).
	We simulate our own held object, so a throw launches locally with zero delay; the server
	validates it.

	Guarantees:
	  - One press = at most one grab request (a second press is ignored until release).
	  - Clicks that land on UI never reach the world (gameProcessed input is ignored).
	  - The object requested is the one under the aim at the instant of the press.
	  - A release only ever throws the object that request returned; any hold the client did
	    not ask for (stale reply, server-side oddity) is dropped immediately.

	The server owns everything; this steers the held object's AlignPosition target (the held
	object is our network-owned part) and sends the aim direction on release.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local DepositConfig = require(Shared.Config.DepositConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local GrabController = {}

type State = "Idle" | "Requesting" | "Holding"
local state: State = "Idle"
local requestId = 0
local requestedObjectId: string? = nil
local heldId: string? = nil
local heldRoot: BasePart? = nil
local pressDown = false
local releaseQueued = false
local toggleMode = false

local hovered: BasePart? = nil
local highlight: Highlight
local card: Frame
local cardName: TextLabel
local cardStats: TextLabel
local cardAction: TextLabel
local tooHeavyUntil = 0

-- Throw preview
local ARC_DOTS = 22
local arcDots: { BasePart } = {}
local ring: BasePart
local arcBin: BasePart? = nil
-- Recently thrown object (for bin magnetism while we still simulate it) and fade state.
local lastThrown: BasePart? = nil
local lastThrownAt = 0
local fadedRoot: BasePart? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local arcParams = RaycastParams.new()
arcParams.FilterType = Enum.RaycastFilterType.Exclude

local function inSearching(): boolean
	return player:GetAttribute("InMatch") == true and matchState:GetAttribute("State") == "Searching"
end

local function characterRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function roomClutter(): Instance?
	local room = workspace:FindFirstChild("Room" .. (matchState:GetAttribute("RoomNumber") or ""))
	return room and room:FindFirstChild("Clutter")
end

local function clutterRootOf(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if CollectionService:HasTag(inst, "Clutter") then
		return inst :: BasePart
	end
	local parent = inst.Parent
	if parent and parent:IsA("BasePart") and CollectionService:HasTag(parent, "Clutter") then
		return parent
	end
	return nil
end

local forceCenterAim = false -- Studio test hook only

local function usesCenterAim(): boolean
	return forceCenterAim or UI.IsTouch() or UI.IsGamepad() or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function aimRay(): Ray
	local camera = workspace.CurrentCamera
	if usesCenterAim() then
		local vp = camera.ViewportSize
		return camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	end
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

local function closestDistance(root: BasePart, point: Vector3): number
	local lp = root.CFrame:PointToObjectSpace(point)
	local half = root.Size / 2
	local clamped = Vector3.new(math.clamp(lp.X, -half.X, half.X), math.clamp(lp.Y, -half.Y, half.Y), math.clamp(lp.Z, -half.Z, half.Z))
	return (lp - clamped).Magnitude
end

-- The exact clutter object under the aim right now (first thing the aim ray hits).
local function findAimed(): BasePart?
	local hrp = characterRoot()
	if not hrp then
		return nil
	end
	local ignore = { player.Character, workspace.CurrentCamera }
	if heldRoot then
		table.insert(ignore, heldRoot)
	end
	rayParams.FilterDescendantsInstances = ignore
	local ray = aimRay()
	local result = workspace:Raycast(ray.Origin, ray.Direction * 120, rayParams)
	local root = result and clutterRootOf(result.Instance)
	if root and root:GetAttribute("State") ~= "Held" and closestDistance(root, hrp.Position) <= GameConfig.GrabDistance then
		return root
	end
	return nil
end

local function maxWeight(): number
	return player:GetAttribute("MaxWeight") or 2
end

-- The lowest Strength level that lifts `weight`, counting passes and boosts (the server publishes
-- what each level would lift as LiftByLevel).
local function strengthLevelFor(weight: number): number?
	local list = player:GetAttribute("LiftByLevel")
	if type(list) == "string" and list ~= "" then
		for level, lift in ipairs(string.split(list, ",")) do
			if (tonumber(lift) or 0) >= weight then
				return level
			end
		end
	end
	return UpgradeConfig.StrengthLevelFor(weight)
end

local function setIdle()
	state = "Idle"
	requestedObjectId = nil
	heldId = nil
	heldRoot = nil
	releaseQueued = false
	toggleMode = false
end

local function dropStray(objectId: string)
	Remotes.Event("DropObject"):FireServer(objectId)
end

local function requestGrab(fromToggle: boolean)
	if state ~= "Idle" or not inSearching() or Controllers.CameraController.IsCursorFree() then
		return
	end
	local root = findAimed()
	if not root then
		return
	end
	local weight = root:GetAttribute("Weight") or 1
	if weight > maxWeight() then
		tooHeavyUntil = os.clock() + 1.5
		UI.Shake(card, 5, 0.3)
		Controllers.AudioController.Play("TooHeavy")
		return
	end
	requestId += 1
	local myRequest = requestId
	state = "Requesting"
	requestedObjectId = root:GetAttribute("ObjectId")
	releaseQueued = false
	toggleMode = fromToggle
	Remotes.Event("GrabObject"):FireServer(root, myRequest)
	task.delay(2, function()
		if state == "Requesting" and requestId == myRequest then
			setIdle()
		end
	end)
end

local function throwDirection(): Vector3
	return usesCenterAim() and workspace.CurrentCamera.CFrame.LookVector or aimRay().Direction.Unit
end

-- Same formula as ObjectService.ThrowVelocity, using the replicated ThrowSpeed.
local function predictedVelocity(root: BasePart, direction: Vector3): Vector3
	local weight = root:GetAttribute("Weight") or 1
	local speed = (player:GetAttribute("ThrowSpeed") or 50) * math.clamp(1.3 - weight * GameConfig.ThrowWeightFalloff, 0.55, 1.2)
	return (direction + Vector3.new(0, GameConfig.ThrowUpwardBias, 0)).Unit * speed
end

local function unfade()
	if fadedRoot then
		fadedRoot.LocalTransparencyModifier = 0
		for _, d in ipairs(fadedRoot:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
		fadedRoot = nil
	end
end

local function throwHeld()
	if state ~= "Holding" or not heldId then
		return
	end
	local root = heldRoot
	local direction = throwDirection()
	Remotes.Event("ThrowObject"):FireServer(heldId, direction)
	if root and root.Parent then
		-- We already simulate our held object: launch it now so it leaves the hand instantly.
		for _, c in ipairs(root:GetChildren()) do
			if c:IsA("AlignPosition") or c:IsA("AlignOrientation") then
				c.Enabled = false
			end
		end
		root.AssemblyLinearVelocity = predictedVelocity(root, direction)
		-- Reduced-gravity lift from the very first frame, so the flight matches the arc preview.
		-- The server's FlightLift replaces it as soon as it arrives.
		local att = Instance.new("Attachment")
		att.Name = "LocalLiftAttachment"
		att.Parent = root
		local lift = Instance.new("VectorForce")
		lift.Name = "LocalLift"
		lift.Attachment0 = att
		lift.RelativeTo = Enum.ActuatorRelativeTo.World
		lift.ApplyAtCenterOfMass = true
		lift.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * (1 - GameConfig.ThrowGravityScale), 0)
		lift.Parent = root
		local conn
		local function removeLocalLift()
			if conn then
				conn:Disconnect()
			end
			lift:Destroy()
			att:Destroy()
		end
		conn = root.ChildAdded:Connect(function(child)
			if child.Name == "FlightLift" then
				removeLocalLift()
			end
		end)
		task.delay(0.6, removeLocalLift)
		lastThrown = root
		lastThrownAt = os.clock()
	end
	unfade()
	Controllers.AudioController.Play("Throw")
	Controllers.FXController.FovPunch(2)
	setIdle()
end

-- Set the held object down gently in front of you.
local function dropHeld()
	if state ~= "Holding" or not heldId then
		return
	end
	Remotes.Event("DropObject"):FireServer(heldId)
	unfade()
	pressDown = false
	setIdle()
end

local function onGrabResult(replyId: number, ok: boolean, objectId: string?, reason: string?)
	if replyId ~= requestId or state ~= "Requesting" then
		-- A reply for a press we already gave up on: never keep that object.
		if ok and objectId then
			dropStray(objectId)
		end
		return
	end
	if not ok then
		setIdle()
		return
	end
	if objectId ~= requestedObjectId then
		if objectId then
			dropStray(objectId)
		end
		setIdle()
		return
	end
	state = "Holding"
	heldId = objectId
	local folder = roomClutter()
	heldRoot = folder and folder:FindFirstChild(objectId) :: BasePart?
	Controllers.AudioController.Play("Grab")
	-- Button already released while the request was in flight: throw straight away.
	if not toggleMode and (releaseQueued or not pressDown) then
		throwHeld()
	end
end

local function isGrabInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2
end

local function pressAction()
	if pressDown then
		return
	end
	pressDown = true
	requestGrab(false)
end

local function releaseAction()
	if not pressDown then
		return
	end
	pressDown = false
	if state == "Holding" and not toggleMode then
		throwHeld()
	elseif state == "Requesting" then
		releaseQueued = true
	end
end

local function tapAction()
	if state == "Holding" then
		throwHeld()
	elseif state == "Idle" then
		requestGrab(true)
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if isGrabInput(input) then
		pressAction()
	elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB
		or (input.UserInputType == Enum.UserInputType.MouseButton2 and Controllers.CameraController.IsFirstPerson()) then
		dropHeld()
	end
end

local function onInputEnded(input: InputObject)
	if isGrabInput(input) then
		releaseAction()
	end
end

-- The server is the authority on what we hold; resync if it disagrees.
local function onHeldAttribute()
	local id = player:GetAttribute("HeldObjectId") or ""
	if id == "" then
		if state == "Holding" then
			setIdle()
		end
	elseif state == "Idle" then
		dropStray(id)
	end
end

local function steerHeld()
	local root = heldRoot
	local hrp = characterRoot()
	if not root or not hrp then
		return
	end
	local alignPos = root:FindFirstChildOfClass("AlignPosition")
	local alignOri = root:FindFirstChildOfClass("AlignOrientation")
	if not alignPos then
		return
	end
	local camera = workspace.CurrentCamera
	local dir = usesCenterAim() and camera.CFrame.LookVector or aimRay().Direction.Unit
	local radius = math.max(root.Size.X, root.Size.Y, root.Size.Z) / 2
	local target
	if Controllers.CameraController.IsFirstPerson() then
		-- Held low and to the right of view, like it's in your hands.
		target = camera.CFrame.Position + dir * (GameConfig.HoldDistance * 0.8 + radius) + camera.CFrame.RightVector * 0.9 - camera.CFrame.UpVector * 0.8
	else
		target = hrp.Position + Vector3.new(0, 1.6, 0) + dir * (GameConfig.HoldDistance + radius)
	end
	target = Vector3.new(target.X, math.max(target.Y, hrp.Position.Y - 2 + radius), target.Z)
	alignPos.Position = target
	if alignOri then
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then
			alignOri.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		end
	end
end

local function actionText(chunk: boolean): string
	local verb = chunk and "BREAK IT OPEN" or "GRAB"
	if UI.IsTouch() then
		return "TAP " .. (chunk and "GRAB TO BREAK IT" or "GRAB")
	elseif UI.IsGamepad() then
		return "HOLD R2 TO " .. verb
	end
	return "HOLD LEFT MOUSE TO " .. verb
end

-- "$2 in any bin  •  $4 in the LAUNDRY BASKET"
local function valueText(root: BasePart): string
	local value = root:GetAttribute("CashValue") or 0
	local matchType = DepositConfig.MatchingType(root:GetAttribute("Category"), root:GetAttribute("Weight"))
	local bin = matchType and DepositConfig.Types[matchType]
	if bin then
		return string.format("$%d   •   $%d in the %s", value, value * DepositConfig.MatchMultiplier, bin.Name)
	end
	return string.format("$%d in any bin", value)
end

-- The card grows to fit its longest line, so bin names and "Requires Strength Lv. N" never clip.
local TextService = game:GetService("TextService")
local cardFitFor = ""
local function fitCard()
	local key = cardName.Text .. "|" .. cardStats.Text .. "|" .. cardAction.Text
	if key == cardFitFor then
		return
	end
	cardFitFor = key
	local width = 300
	for _, label in ipairs({ cardName, cardStats, cardAction }) do
		width = math.max(width, TextService:GetTextSize(label.Text, label.TextSize, label.Font, Vector2.new(2000, 100)).X + 30)
	end
	card.Size = UDim2.fromOffset(math.min(width, 560), 86)
end

local function updateVisuals()
	local target = heldRoot or hovered
	highlight.Adornee = target
	local crosshair = "idle"
	if heldRoot then
		highlight.OutlineColor = arcBin and UI.Colors.Gold or UI.Colors.Green
		crosshair = "hold"
		card.Visible = true
		cardName.Text = heldRoot:GetAttribute("DisplayName") or "OBJECT"
		if arcBin then
			-- Where it will land and what it pays there: the right bin doubles it.
			local matchType = DepositConfig.MatchingType(heldRoot:GetAttribute("Category"), heldRoot:GetAttribute("Weight"))
			local right = matchType == nil or arcBin:GetAttribute("BinType") == matchType
			local payout = matchType == nil and "x1" or (right and "x2 PAY!" or ("x1  -  the " .. DepositConfig.Types[matchType].Name .. " pays x2"))
			cardStats.Text = string.format("IN THE %s!   %s", arcBin:GetAttribute("BinName") or "BIN", payout)
			cardStats.TextColor3 = right and UI.Colors.Gold or UI.Colors.Text
		else
			cardStats.Text = valueText(heldRoot)
			cardStats.TextColor3 = UI.Colors.TextDim
		end
		cardAction.Text = UI.IsTouch() and "TAP THROW  •  DROP" or (UI.IsGamepad() and "RELEASE R2 TO THROW  •  B DROP" or "RELEASE TO THROW  •  [Q] DROP")
		cardAction.TextColor3 = UI.Colors.Green
	elseif hovered then
		local weight = hovered:GetAttribute("Weight") or 1
		local tooHeavy = weight > maxWeight()
		local chunk = hovered:GetAttribute("IsChunk") == true
		highlight.OutlineColor = tooHeavy and UI.Colors.Red or Color3.new(1, 1, 1)
		crosshair = tooHeavy and "heavy" or "hover"
		card.Visible = true
		cardName.Text = hovered:GetAttribute("DisplayName") or "OBJECT"
		cardStats.TextColor3 = UI.Colors.TextDim
		if chunk then
			cardStats.Text = string.format("Weight: %d   •   Packed with junk - grab to break it open", weight)
		else
			cardStats.Text = string.format("Weight: %d   •   %s", weight, valueText(hovered))
		end
		if tooHeavy then
			cardAction.Text = string.format("TOO HEAVY - Requires Strength Lv. %d", strengthLevelFor(weight) or UpgradeConfig.GetMaxLevel("Strength"))
			cardAction.TextColor3 = UI.Colors.Red
		else
			cardAction.Text = actionText(chunk)
			cardAction.TextColor3 = UI.Colors.Gold
		end
	else
		card.Visible = os.clock() < tooHeavyUntil
	end
	if card.Visible then
		fitCard()
	end
	Controllers.CameraController.SetCrosshair(crosshair)
end

-- ===== Throw preview, fade, bin magnetism =====

local function makeArc()
	local folder = Instance.new("Folder")
	folder.Name = "ThrowArc"
	folder.Parent = workspace.CurrentCamera
	local function visual(shape: Enum.PartType, size: Vector3): Part
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Parent = folder
		return p
	end
	for i = 1, ARC_DOTS do
		arcDots[i] = visual(Enum.PartType.Ball, Vector3.new(0.22, 0.22, 0.22))
	end
	ring = visual(Enum.PartType.Cylinder, Vector3.new(0.06, 2.4, 2.4))
end

local function hideArc()
	for _, dot in ipairs(arcDots) do
		dot.Transparency = 1
	end
	if ring then
		ring.Transparency = 1
	end
	arcBin = nil
end

local function binAt(pos: Vector3): BasePart?
	for _, mouth in ipairs(Controllers.BinController.GetMouths()) do
		local lp = mouth.CFrame:PointToObjectSpace(pos)
		local h = mouth.Size / 2
		if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z then
			return mouth
		end
	end
	return nil
end

local function drawArc()
	local root = heldRoot
	if not root or not root.Parent or Controllers.CameraController.IsCursorFree() then
		hideArc()
		return
	end
	local v = predictedVelocity(root, throwDirection())
	local g = Vector3.new(0, -workspace.Gravity * GameConfig.ThrowGravityScale, 0)
	local pos = root.Position
	arcParams.FilterDescendantsInstances = { player.Character, workspace.CurrentCamera, root }
	local points = {}
	local hitPos, hitNormal, bin = nil, nil, nil
	local dt = 0.045
	-- Sweep a sphere roughly the object's size: a thin ray misses pile edges the object clips.
	local radius = math.clamp(math.max(root.Size.X, root.Size.Y, root.Size.Z) * 0.25, 0.3, 1)
	for _ = 1, 90 do
		local nextPos = pos + v * dt + g * (0.5 * dt * dt)
		v += g * dt
		-- Walls and piles first, so a path through a bin's side never counts as "in".
		local result = workspace:Spherecast(pos, radius, nextPos - pos, arcParams)
		if result then
			hitPos, hitNormal = result.Position, result.Normal
			break
		end
		-- In = dropping into a bin's mouth through its top opening.
		local mouth = binAt(nextPos)
		if mouth and pos.Y >= mouth.Position.Y + mouth.Size.Y / 2 - 0.8 then
			bin = mouth
			hitPos, hitNormal = nextPos, Vector3.yAxis
			break
		end
		table.insert(points, nextPos)
		pos = nextPos
	end
	arcBin = bin
	-- Gold into the bin that pays most (the right one, or any when nothing is special about it),
	-- pale blue into another bin.
	local matchType = DepositConfig.MatchingType(root:GetAttribute("Category"), root:GetAttribute("Weight"))
	local best = bin ~= nil and (matchType == nil or bin:GetAttribute("BinType") == matchType)
	local color = bin and (best and UI.Colors.Gold or Color3.fromRGB(150, 220, 255)) or Color3.new(1, 1, 1)
	for i, dot in ipairs(arcDots) do
		local idx = math.floor(i * #points / ARC_DOTS)
		if idx >= 1 then
			dot.CFrame = CFrame.new(points[idx])
			dot.Color = color
			dot.Transparency = 0.2 + 0.55 * (i / ARC_DOTS)
		else
			dot.Transparency = 1
		end
	end
	if hitPos and hitNormal then
		local side = math.abs(hitNormal.Z) < 0.9 and hitNormal:Cross(Vector3.zAxis).Unit or hitNormal:Cross(Vector3.xAxis).Unit
		ring.CFrame = CFrame.fromMatrix(hitPos + hitNormal * 0.05, hitNormal, side)
		ring.Color = bin and UI.Colors.Gold or UI.Colors.Green
		ring.Transparency = 0.3
	else
		ring.Transparency = 1
	end
end

-- The held object is see-through in first person so it never blocks what you're aiming at.
local function updateFade()
	local want = (heldRoot and Controllers.CameraController.IsFirstPerson()) and heldRoot or nil
	if want ~= fadedRoot then
		unfade()
		if want then
			fadedRoot = want
		end
	end
	if fadedRoot then
		fadedRoot.LocalTransparencyModifier = 0.55
		for _, d in ipairs(fadedRoot:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0.55
			end
		end
	end
end

-- While we still simulate a fresh throw, a near miss over a bin gets nudged in.
local function binMagnet()
	local root = lastThrown
	if not root or not root.Parent or os.clock() - lastThrownAt > GameConfig.OwnedFlightTime then
		lastThrown = nil
		return
	end
	local v = root.AssemblyLinearVelocity
	if v.Y > 0 then
		return
	end
	for _, mouth in ipairs(Controllers.BinController.GetMouths()) do
		local lp = mouth.CFrame:PointToObjectSpace(root.Position)
		local h = mouth.Size / 2
		if lp.Y > -h.Y and lp.Y < h.Y + 3 and math.abs(lp.X) <= h.X + 1.5 and math.abs(lp.Z) <= h.Z + 1.5 then
			local flat = Vector3.new(mouth.Position.X - root.Position.X, 0, mouth.Position.Z - root.Position.Z)
			root.AssemblyLinearVelocity = Vector3.new(v.X * 0.5 + flat.X * 3, v.Y, v.Z * 0.5 + flat.Z * 3)
			return
		end
	end
end

function GrabController.Init()
	highlight = Instance.new("Highlight")
	highlight.Name = "GrabHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0.05
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = workspace.CurrentCamera

	card = UI.Panel({ Size = UDim2.fromOffset(300, 86), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Visible = false, BackgroundTransparency = 0.12 }, UI.Layers.HUD)
	cardName = UI.Label({ Text = "", TextSize = 22, Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 4) }, card)
	cardStats = UI.Label({ Text = "", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 32) }, card)
	cardAction = UI.Label({ Text = "", TextSize = 17, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 56) }, card)

	makeArc()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	Remotes.Event("GrabResult").OnClientEvent:Connect(onGrabResult)
	player:GetAttributeChangedSignal("HeldObjectId"):Connect(onHeldAttribute)

	Controllers.HUDController.GetMobileActionButton().Activated:Connect(tapAction)
	Controllers.HUDController.GetMobileDropButton().Activated:Connect(dropHeld)

	-- Studio-only test hook: drives the exact same press/release/tap paths as real input,
	-- so the state machine can be tested without touching anyone's mouse.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableEvent")
		hook.Name = "GrabDevInput"
		hook.Event:Connect(function(action: string)
			if action == "press" then
				pressAction()
			elseif action == "release" then
				releaseAction()
			elseif action == "tap" then
				tapAction()
			elseif action == "drop" then
				dropHeld()
			elseif action == "centerAimOn" then
				forceCenterAim = true
			elseif action == "centerAimOff" then
				forceCenterAim = false
			end
		end)
		hook.Parent = script
	end

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if name == "TooHeavy" then
			tooHeavyUntil = os.clock() + 1.5
			Controllers.NotificationController.Show("Warning", string.format("%s is too heavy! Requires Strength Lv. %d", payload.Name or "That", payload.RequiredLevel or 0), 2.5)
		end
	end)

	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		if not player:GetAttribute("InMatch") then
			pressDown = false
			setIdle()
		end
	end)
end

function GrabController.Start()
	RunService.RenderStepped:Connect(function()
		if not inSearching() then
			hovered = nil
			highlight.Adornee = nil
			card.Visible = false
			hideArc()
			unfade()
			Controllers.BinController.SetHeld(nil)
			Controllers.CameraController.SetCrosshair("idle")
			Controllers.HUDController.SetMobileAction(nil)
			return
		end
		if heldRoot and not heldRoot.Parent then
			heldRoot = nil
		end
		if state == "Holding" and not heldRoot and heldId then
			local folder = roomClutter()
			heldRoot = folder and folder:FindFirstChild(heldId) :: BasePart?
		end
		steerHeld()
		drawArc()
		updateFade()
		binMagnet()
		Controllers.BinController.SetHeld(heldRoot)
		hovered = (state == "Idle") and findAimed() or nil
		updateVisuals()
		-- Touch: the button says HEAVY (red) while aiming at something you can't lift yet.
		local hoverAction = hovered and ((hovered:GetAttribute("Weight") or 1) > maxWeight() and "HEAVY" or "GRAB") or nil
		Controllers.HUDController.SetMobileAction(state == "Holding" and "THROW" or hoverAction)
	end)
end

function GrabController.GetHeld(): BasePart?
	return heldRoot
end

function GrabController.GetState(): string
	return state
end

return GrabController
