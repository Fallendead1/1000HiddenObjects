--[[
	Physical grab / hold / throw input. One strict state machine for every platform:

	  Idle --press on an object--> Requesting --server says ok--> Holding --release--> Idle

	  PC:      press Left Mouse on an object, keep holding to carry, release to throw.
	  Gamepad: same with R2.
	  Mobile:  tap GRAB to pick up, tap THROW to throw (camera stays free in between).

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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

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

local function throwHeld()
	if state ~= "Holding" or not heldId then
		return
	end
	local direction = usesCenterAim() and workspace.CurrentCamera.CFrame.LookVector or aimRay().Direction.Unit
	Remotes.Event("ThrowObject"):FireServer(heldId, direction)
	Controllers.AudioController.Play("Throw")
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
	if isGrabInput(input) and not gameProcessed then
		pressAction()
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

local function actionText(): string
	if UI.IsTouch() then
		return "TAP GRAB"
	elseif UI.IsGamepad() then
		return "HOLD R2 TO GRAB"
	end
	return "HOLD LEFT MOUSE TO GRAB"
end

local function updateVisuals()
	local target = heldRoot or hovered
	highlight.Adornee = target
	local crosshair = "idle"
	if heldRoot then
		highlight.OutlineColor = UI.Colors.Green
		crosshair = "hold"
		card.Visible = true
		cardName.Text = heldRoot:GetAttribute("DisplayName") or "OBJECT"
		cardStats.Text = "Aim where you want it to go"
		cardAction.Text = UI.IsTouch() and "TAP THROW" or (UI.IsGamepad() and "RELEASE R2 TO THROW" or "RELEASE LEFT MOUSE TO THROW")
		cardAction.TextColor3 = UI.Colors.Green
	elseif hovered then
		local weight = hovered:GetAttribute("Weight") or 1
		local tooHeavy = weight > maxWeight()
		highlight.OutlineColor = tooHeavy and UI.Colors.Red or Color3.new(1, 1, 1)
		crosshair = tooHeavy and "heavy" or "hover"
		card.Visible = true
		cardName.Text = hovered:GetAttribute("DisplayName") or "OBJECT"
		if hovered:GetAttribute("MovedBefore") then
			cardStats.Text = string.format("Weight: %d   •   Already moved", weight)
		else
			cardStats.Text = string.format("Weight: %d   •   Value: $%d", weight, hovered:GetAttribute("CashValue") or 0)
		end
		if tooHeavy then
			cardAction.Text = string.format("TOO HEAVY - Requires Strength Lv. %d", UpgradeConfig.StrengthLevelFor(weight) or 99)
			cardAction.TextColor3 = UI.Colors.Red
		else
			cardAction.Text = actionText()
			cardAction.TextColor3 = UI.Colors.Gold
		end
	else
		card.Visible = os.clock() < tooHeavyUntil
	end
	Controllers.CameraController.SetCrosshair(crosshair)
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

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	Remotes.Event("GrabResult").OnClientEvent:Connect(onGrabResult)
	player:GetAttributeChangedSignal("HeldObjectId"):Connect(onHeldAttribute)

	Controllers.HUDController.GetMobileActionButton().Activated:Connect(tapAction)

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
		hovered = (state == "Idle") and findAimed() or nil
		updateVisuals()
		Controllers.HUDController.SetMobileAction(state == "Holding" and "THROW" or (hovered and "GRAB" or nil))
	end)
end

function GrabController.GetHeld(): BasePart?
	return heldRoot
end

function GrabController.GetState(): string
	return state
end

return GrabController
