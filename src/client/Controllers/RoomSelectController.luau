--[[
	Room selector shown to the owner of a matchmaking circle while it is in the Selecting
	state. Lists every existing room the player has unlocked (<= HighestRoomCompleted + 1),
	defaulting to their next required room. Walking out of the circle cancels.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local RoomRegistry = require(Shared.Config.RoomConfigs)
local Remotes = require(Shared.Utility.Remotes)
local TargetData = require(Shared.Data.TargetData)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local RoomSelectController = {}

local panel: Frame
local numberLabel: TextLabel
local nameLabel: TextLabel
local targetLabel: TextLabel
local iconFrame: Frame
local iconGlyph: TextLabel
local statusLabel: TextLabel
local footerLabel: TextLabel
local prevButton: TextButton
local nextButton: TextButton
local playButton: TextButton

local rooms: { number } = {}
local index = 1
local activeZone: BasePart? = nil
local sent = false

local function findZone(queueId: string): BasePart?
	for _, zone in ipairs(CollectionService:GetTagged("QueueZone")) do
		if zone:GetAttribute("QueueId") == queueId then
			return zone
		end
	end
	return nil
end

local function unlockedRooms(): { number }
	local highest = player:GetAttribute("HighestRoomCompleted") or 0
	local list = {}
	for id in pairs(RoomRegistry.GetAll()) do
		if id <= highest + 1 then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

local function render()
	local roomId = rooms[index]
	local config = roomId and RoomRegistry.Get(roomId)
	if not config then
		return
	end
	local def = TargetData.Get(roomId)
	numberLabel.Text = "ROOM #" .. config.DisplayNumber
	nameLabel.Text = config.Name
	targetLabel.Text = config.TargetName
	iconFrame.BackgroundColor3 = def and def.Color or UI.Colors.Gold
	iconGlyph.Text = string.upper(string.sub(config.TargetName, 1, 1))

	local highest = player:GetAttribute("HighestRoomCompleted") or 0
	local cpRoom = player:GetAttribute("CheckpointRoomId") or 0
	local cpPercent = player:GetAttribute("CheckpointPercent") or 0
	if cpRoom == roomId and cpPercent > 0 then
		statusLabel.Text = string.format("RESUME FROM %d%% CHECKPOINT", math.floor(cpPercent * 100))
		statusLabel.TextColor3 = UI.Colors.Cyan
	elseif roomId <= highest then
		statusLabel.Text = "COMPLETED ✓  -  REPLAY FOR A BETTER TIME"
		statusLabel.TextColor3 = UI.Colors.Green
	else
		statusLabel.Text = "NEW OBJECT TO FIND!"
		statusLabel.TextColor3 = UI.Colors.Gold
	end
	UI.SetButtonEnabled(prevButton, index > 1)
	UI.SetButtonEnabled(nextButton, index < #rooms)
end

local function close()
	panel.Visible = false
	activeZone = nil
	sent = false
end

local function open(zone: BasePart)
	if activeZone == zone and panel.Visible then
		return
	end
	activeZone = zone
	sent = false
	rooms = unlockedRooms()
	local highest = player:GetAttribute("HighestRoomCompleted") or 0
	index = #rooms
	for i, id in ipairs(rooms) do
		if id == highest + 1 then
			index = i
		end
	end
	render()
	UI.CloseAllMenus()
	panel.Visible = true
	local s = panel:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, panel)
	s.Scale = 0.85
	UI.Tween(s, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
end

local function evaluate()
	local queueId = player:GetAttribute("QueueId") or ""
	local zone = queueId ~= "" and findZone(queueId) or nil
	if zone and zone:GetAttribute("State") == "Selecting" and zone:GetAttribute("OwnerUserId") == player.UserId then
		open(zone)
	elseif panel.Visible then
		close()
	end
end

function RoomSelectController.Init()
	panel = UI.Panel({ Size = UDim2.fromOffset(440, 360), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Visible = false }, UI.Layers.Menus)
	UI.Stroke(panel, UI.Colors.Gold, 3)
	UI.Label({ Text = "CHOOSE A ROOM", TextSize = 30, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10) }, panel)

	local card = UI.Frame({ Size = UDim2.new(1, -150, 0, 180), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), BackgroundColor3 = UI.Colors.PanelLight }, panel)
	UI.Corner(card, 12)
	numberLabel = UI.Label({ Text = "ROOM #001", TextSize = 30, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 8) }, card)
	nameLabel = UI.Label({ Text = "The Messy Bedroom", TextSize = 20, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 44) }, card)
	iconFrame = UI.Frame({ Size = UDim2.fromOffset(56, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), BackgroundColor3 = UI.Colors.Gold }, card)
	UI.Corner(iconFrame, 12)
	UI.Stroke(iconFrame, Color3.new(1, 1, 1), 2)
	iconGlyph = UI.Label({ Text = "G", TextSize = 32, TextColor3 = UI.Colors.PanelDark }, iconFrame)
	targetLabel = UI.Label({ Text = "Golden Key", TextSize = 20, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 138) }, card)

	prevButton = UI.Button({ Text = "<", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(52, 72), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0, 146), TextSize = 32 }, panel)
	nextButton = UI.Button({ Text = ">", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(52, 72), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0, 146), TextSize = 32 }, panel)

	statusLabel = UI.Label({ Text = "", TextSize = 15, Font = UI.FontBody, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 242) }, panel)
	playButton = UI.Button({ Text = "PLAY", Color = UI.Colors.Green, Size = UDim2.new(1, -60, 0, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 266), TextSize = 30 }, panel)
	footerLabel = UI.Label({ Text = "", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 330) }, panel)

	prevButton.Activated:Connect(function()
		if index > 1 then
			index -= 1
			render()
		end
	end)
	nextButton.Activated:Connect(function()
		if index < #rooms then
			index += 1
			render()
		end
	end)
	playButton.Activated:Connect(function()
		if sent or not activeZone or not rooms[index] then
			return
		end
		sent = true
		Remotes.Event("SelectRoom"):FireServer(activeZone:GetAttribute("QueueId"), rooms[index])
		Controllers.AudioController.Play("QueueEnter")
	end)

	player:GetAttributeChangedSignal("QueueId"):Connect(evaluate)
	local function watchZone(zone: Instance)
		if zone:IsA("BasePart") then
			zone:GetAttributeChangedSignal("State"):Connect(evaluate)
			zone:GetAttributeChangedSignal("OwnerUserId"):Connect(evaluate)
		end
	end
	for _, zone in ipairs(CollectionService:GetTagged("QueueZone")) do
		watchZone(zone)
	end
	CollectionService:GetInstanceAddedSignal("QueueZone"):Connect(watchZone)
end

function RoomSelectController.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not panel.Visible or not activeZone then
			return
		end
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local deadline = activeZone:GetAttribute("SelectionDeadline") or 0
		local remaining = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		footerLabel.Text = string.format("Auto-start in %ds  •  Walk out of the circle to cancel", remaining)
	end)
	evaluate()
end

return RoomSelectController
