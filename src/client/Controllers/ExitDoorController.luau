--[[
	The room's way out. The exit door (tagged ExitDoor by RoomService) gets a RETURN TO LOBBY sign
	above it. Walk into the door and a red "RETURN BACK TO LOBBY?" button appears (the mouse is
	freed so it can be clicked in first person; E or gamepad X work too). It sends you to a lobby
	server; walking away hides it. The spawn is further from the door than the zone, so it never
	pops up on arrival.
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
local BUTTON_TEXT = "RETURN BACK TO LOBBY?"

type Door = { Normal: Vector3, Across: Vector3 }
local doors: { [BasePart]: Door } = {}
local button: TextButton
local note: TextLabel
local showing = false
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
	local panel = UI.Frame({ Size = UDim2.new(1, -8, 1, -8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = WHITE }, gui)
	UI.Corner(panel, 16)
	UI.Gradient(panel, UI.Colors.Red:Lerp(WHITE, 0.15), UI.Colors.Red:Lerp(BLACK, 0.25))
	UI.Stroke(panel, BLACK, 4)
	UI.Label({ Text = "RETURN TO LOBBY", TextScaled = true, TextWrapped = false, Size = UDim2.new(0.92, 0, 0.72, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, panel)
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
	button.Visible = on
	note.Visible = on
	Controllers.CameraController.SetCursorFree("ExitDoor", on)
	if on then
		note.Text = UI.IsTouch() and "Walk away to stay" or (UI.IsGamepad() and "Press X  -  walk away to stay" or "Click or press E  -  walk away to stay")
		UI.PopIn(button, 0.25, 0.3)
	end
end

local function leave()
	if not showing or pending then
		return
	end
	pending = true
	button.Text = "RETURNING..."
	Remotes.Event("LeaveRoom"):FireServer()
	task.delay(8, function()
		pending = false
		button.Text = BUTTON_TEXT
	end)
end

function ExitDoorController.Init()
	button = UI.Button({ Name = "ExitDoorButton", Text = BUTTON_TEXT, Color = UI.Colors.Red, Size = UDim2.fromOffset(360, 66), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), TextSize = 24 }, UI.Layers.HUD)
	button.Visible = false
	note = UI.Label({ Name = "ExitDoorNote", Text = "", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.Text, Size = UDim2.fromOffset(360, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 40) }, UI.Layers.HUD)
	note.Visible = false
	button.Activated:Connect(leave)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and showing and (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX) then
			leave()
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
		setShowing(next(doors) ~= nil and nearDoor())
	end)
end

return ExitDoorController
