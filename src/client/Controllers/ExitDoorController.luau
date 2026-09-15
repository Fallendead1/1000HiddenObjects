--[[
	The room's way out. The exit door (tagged ExitDoor by RoomService) gets a RETURN TO LOBBY sign
	above it. Walk into the door and a small panel asks "RETURN TO LOBBY?": the green RETURN TO LOBBY
	button sends you to a lobby server, the red CANCEL closes it (it stays closed until you step away
	from the door and come back). Walking away closes it too. On a computer the mouse is freed so the
	buttons can be clicked in first person and E returns; on a gamepad X returns and B cancels; phones
	just tap (the thumbstick and camera keep working). The spawn is further from the door than the
	zone, so it never pops up on arrival.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local ExitDoorController = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local SIGN_SIZE = Vector2.new(8, 1.6) -- studs
local SIGN_GAP = 1.2 -- above the top of the door (clear of its frame)
local ZONE_DEPTH = 2.4 -- how close to the door's face counts as walking into it
local RETURN_TEXT = "RETURN TO LOBBY"

type Door = { Normal: Vector3, Across: Vector3 }
local doors: { [BasePart]: Door } = {}
local panel: Frame
local returnButton: TextButton
local cancelButton: TextButton
local keyHint: TextLabel
local showing = false
local dismissed = false -- CANCEL pressed: stays closed until the player steps away from the door
local pending = false

-- The door's thin horizontal axis (pointing into the room) and its width axis.
local function doorAxes(part: BasePart): (Vector3, Vector3)
	local cf, size = part.CFrame, part.Size
	local normal, across = cf.ZVector, cf.XVector
	if size.X < size.Z then
		normal, across = cf.XVector, cf.ZVector
	end
	local room = part:FindFirstAncestorOfClass("Model")
	local centre = room and room:GetPivot().Position or part.Position
	if (centre - part.Position):Dot(normal) < 0 then
		normal = -normal
	end
	return normal, across
end

local function makeSign(part: BasePart, normal: Vector3)
	local top = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
	local at = top + Vector3.new(0, SIGN_GAP + SIGN_SIZE.Y / 2, 0) + normal * 2
	-- Flush against the wall above the door.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part.Parent :: Instance }
	local hit = workspace:Raycast(at, -normal * 6, params)
	local centre = (hit and hit.Position or (at - normal * 2)) + normal * 0.08
	local board = Instance.new("Part")
	board.Name = "ExitSign"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.CastShadow = false
	board.Transparency = 1
	board.Size = Vector3.new(SIGN_SIZE.X, SIGN_SIZE.Y, 0.1)
	board.CFrame = CFrame.lookAt(centre, centre + normal)
	local gui = UI.New("SurfaceGui", {
		Name = "ExitSignGui",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(400, 80),
		LightInfluence = 0,
		MaxDistance = 250,
		ResetOnSpawn = false,
	}, board)
	local sign = UI.Frame({ Size = UDim2.new(1, -8, 1, -8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = WHITE }, gui)
	UI.Corner(sign, 16)
	UI.Gradient(sign, UI.Colors.Red:Lerp(WHITE, 0.15), UI.Colors.Red:Lerp(BLACK, 0.25))
	UI.Stroke(sign, BLACK, 4)
	UI.Label({ Text = "RETURN TO LOBBY", TextScaled = true, TextWrapped = false, Size = UDim2.new(0.92, 0, 0.72, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, sign)
	board.Parent = part -- client-only, and it goes away with the room
end

local function addDoor(part: Instance)
	if doors[part :: BasePart] or not part:IsA("BasePart") then
		return
	end
	local normal, across = doorAxes(part)
	doors[part] = { Normal = normal, Across = across }
	makeSign(part, normal)
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			doors[part] = nil
		end
	end)
end

local function nearDoor(): boolean
	if player:GetAttribute("InMatch") ~= true or matchState:GetAttribute("State") ~= "Searching" then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for part, door in pairs(doors) do
		local rel = root.Position - part.Position
		local front = rel:Dot(door.Normal) - math.min(part.Size.X, part.Size.Z) / 2
		local halfWidth = math.max(part.Size.X, part.Size.Z) / 2
		if front > -1 and front < ZONE_DEPTH and math.abs(rel:Dot(door.Across)) < halfWidth + 1.2 and math.abs(rel.Y) < part.Size.Y then
			return true
		end
	end
	return false
end

local function setShowing(on: boolean)
	if on == showing then
		return
	end
	showing = on
	panel.Visible = on
	Controllers.CameraController.SetCursorFree("ExitDoor", on)
	if on then
		keyHint.Text = UI.IsGamepad() and "X  return      B  cancel" or "Press E to return"
		UI.PopIn(panel, 0.8, 0.25)
	end
end

local function leave()
	if not showing or pending then
		return
	end
	pending = true
	returnButton.Text = "RETURNING..."
	Remotes.Event("LeaveRoom"):FireServer()
	task.delay(8, function()
		pending = false
		returnButton.Text = RETURN_TEXT
	end)
end

local function cancel()
	if not showing or pending then
		return
	end
	dismissed = true
	setShowing(false)
end

function ExitDoorController.Init()
	-- Phones tap the buttons, so they get no key hint line.
	local keys = not UI.IsTouch()
	panel = UI.Panel({ Name = "ExitDoorPanel", Size = UDim2.fromOffset(440, keys and 164 or 144), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58), BackgroundTransparency = 0.06, Visible = false }, UI.Layers.HUD)
	UI.Stroke(panel, UI.Colors.Red, 2.5)
	UI.Label({ Text = "RETURN TO LOBBY?", TextSize = 26, TextWrapped = false, Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 12) }, panel)
	UI.Label({ Text = "You'll leave this room.", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 46) }, panel)
	cancelButton = UI.Button({ Name = "ExitDoorCancel", Text = "CANCEL", Color = UI.Colors.Red, Size = UDim2.fromOffset(140, 56), Position = UDim2.fromOffset(20, 78), FitText = 20 }, panel)
	returnButton = UI.Button({ Name = "ExitDoorReturn", Text = RETURN_TEXT, Color = UI.Colors.Green, Size = UDim2.fromOffset(250, 56), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 78), FitText = 20, Shine = 3 }, panel)
	keyHint = UI.Label({ Text = "", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 140), Visible = keys }, panel)
	cancelButton.Activated:Connect(cancel)
	returnButton.Activated:Connect(leave)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not showing then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			leave()
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			cancel()
		end
	end)

	for _, part in ipairs(CollectionService:GetTagged("ExitDoor")) do
		addDoor(part)
	end
	CollectionService:GetInstanceAddedSignal("ExitDoor"):Connect(function(part)
		task.defer(addDoor, part)
	end)
end

function ExitDoorController.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		local near = next(doors) ~= nil and nearDoor()
		if not near then
			dismissed = false
		end
		setShowing(near and not dismissed)
	end)
end

return ExitDoorController
