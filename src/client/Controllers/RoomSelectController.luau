--[[
	Party setup panel for the host of a matchmaking circle (the first player in, while the
	circle is in the Selecting state): pick a room (any unlocked one, defaulting to the next
	required room) and a party size (1 = solo run, closed to everyone else), then CREATE.
	BACK (under the panel) leaves the circle; walking out does too.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local Remotes = require(Shared.Utility.Remotes)
local TargetData = require(Shared.Data.TargetData)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local RoomSelectController = {}

local root: Frame
local titleLabel: TextLabel
local nameLabel: TextLabel
local targetLabel: TextLabel
local starsLabel: TextLabel
local iconFrame: Frame
local iconGlyph: TextLabel
local iconImage: ImageLabel
local prevButton: TextButton
local nextButton: TextButton
local sizeLabel: TextLabel
local sizeHint: TextLabel
local minusButton: TextButton
local plusButton: TextButton
local createButton: TextButton
local footerLabel: TextLabel

local rooms: { number } = {}
local index = 1
local partySize = 1 -- remembered between parties this session
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
	titleLabel.Text = "ROOM #" .. config.DisplayNumber
	nameLabel.Text = string.upper(config.Name)
	targetLabel.Text = "Find the " .. config.TargetName
	iconFrame.BackgroundColor3 = def and def.Color or UI.Colors.Gold
	iconGlyph.Text = string.upper(string.sub(config.TargetName, 1, 1))
	local art = def and UI.Asset(def.IconKey or "")
	iconImage.Image = art or ""
	iconImage.Visible = art ~= nil
	iconGlyph.Visible = art == nil
	local mask, count, stars = player:GetAttribute("Stars_" .. roomId) or 0, 0, ""
	for _, bitValue in ipairs({ 1, 2, 4 }) do
		local has = bit32.band(mask, bitValue) ~= 0
		count += has and 1 or 0
		stars ..= has and "★" or "☆"
	end
	local cpRoom, cpPercent = player:GetAttribute("CheckpointRoomId") or 0, player:GetAttribute("CheckpointPercent") or 0
	starsLabel.Text = string.format("%s  %d/3", stars, count) .. ((cpRoom == roomId and cpPercent > 0) and string.format("   ·   RESUME %d%%", math.floor(cpPercent * 100)) or "")
	UI.SetButtonEnabled(prevButton, index > 1)
	UI.SetButtonEnabled(nextButton, index < #rooms)

	sizeLabel.Text = tostring(partySize)
	sizeHint.Text = partySize == 1 and "Solo run - nobody else can join" or string.format("Up to %d more %s can join", partySize - 1, partySize == 2 and "player" or "players")
	UI.SetButtonEnabled(minusButton, partySize > 1)
	UI.SetButtonEnabled(plusButton, partySize < GameConfig.MaxPartySize)
end

local function close()
	root.Visible = false
	activeZone = nil
	sent = false
end

local function open(zone: BasePart)
	if activeZone == zone and root.Visible then
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
	createButton.Text = "CREATE"
	UI.SetButtonEnabled(createButton, true)
	render()
	UI.CloseAllMenus()
	root.Visible = true
	UI.PopIn(root, 0.85, 0.22)
end

local function evaluate()
	local queueId = player:GetAttribute("QueueId") or ""
	local zone = queueId ~= "" and findZone(queueId) or nil
	if zone and zone:GetAttribute("State") == "Selecting" and zone:GetAttribute("OwnerUserId") == player.UserId then
		open(zone)
	elseif root.Visible then
		close()
	end
end

local function stepButton(text: string, parent: Instance, x: number): TextButton
	return UI.Button({ Text = text, Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(58, 58), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 262), TextSize = 34 }, parent)
end

function RoomSelectController.Init()
	-- The panel, with the BACK button hanging under it.
	root = UI.Frame({ Name = "PartySetup", BackgroundTransparency = 1, Size = UDim2.fromOffset(400, 530), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Visible = false }, UI.Layers.Menus)
	local panel = UI.Panel({ Size = UDim2.new(1, 0, 0, 456), BackgroundTransparency = 0.08 }, root)
	UI.Stroke(panel, UI.Colors.Gold, 3)
	UI.Glow(panel, UI.Colors.Gold, 26, 0.55)

	titleLabel = UI.Label({ Text = "ROOM #001", TextSize = 38, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 12) }, panel)
	UI.Stroke(titleLabel, Color3.new(0, 0, 0), 2, 0.3)
	UI.Label({ Text = "CREATE PARTY", TextSize = 24, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 56) }, panel)
	UI.Frame({ Size = UDim2.new(0.84, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 94), BackgroundColor3 = UI.Colors.Text, BackgroundTransparency = 0.35 }, panel)

	-- Room picker.
	iconFrame = UI.Frame({ Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 106), BackgroundColor3 = UI.Colors.Gold }, panel)
	UI.Corner(iconFrame, 12)
	UI.Stroke(iconFrame, Color3.new(1, 1, 1), 2)
	iconGlyph = UI.Label({ Text = "G", TextSize = 30, TextColor3 = UI.Colors.PanelDark }, iconFrame)
	iconImage = UI.Image({ Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), Visible = false }, iconFrame)
	nameLabel = UI.Label({ Text = "", TextSize = 19, Size = UDim2.new(1, -150, 0, 24), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 162), TextTruncate = Enum.TextTruncate.AtEnd }, panel)
	targetLabel = UI.Label({ Text = "", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, -150, 0, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 186) }, panel)
	starsLabel = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -40, 0, 18), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 206) }, panel)
	prevButton = UI.Button({ Text = "<", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(46, 64), Position = UDim2.fromOffset(18, 124), TextSize = 30 }, panel)
	nextButton = UI.Button({ Text = ">", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(46, 64), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 124), TextSize = 30 }, panel)

	-- Party size stepper.
	UI.Label({ Text = "Party Size:", TextSize = 26, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 228) }, panel)
	minusButton = stepButton("-", panel, -72)
	local sizeBox = UI.Frame({ Size = UDim2.fromOffset(58, 58), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 262), BackgroundColor3 = UI.Colors.PanelDark }, panel)
	UI.Corner(sizeBox, 10)
	sizeLabel = UI.Label({ Text = "1", TextSize = 34 }, sizeBox)
	plusButton = stepButton("+", panel, 72)
	sizeHint = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -40, 0, 18), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 326) }, panel)

	createButton = UI.Button({ Text = "CREATE", Color = UI.Colors.Green, Size = UDim2.fromOffset(250, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 356), TextSize = 30, Shine = 2.4 }, panel)
	UI.Pulse(createButton, 0.03, 3)
	footerLabel = UI.Label({ Text = "", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 426) }, panel)

	local backButton = UI.Button({ Text = "BACK", Color = UI.Colors.Red, Size = UDim2.fromOffset(190, 56), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), TextSize = 30 }, root)

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
	minusButton.Activated:Connect(function()
		partySize = math.max(1, partySize - 1)
		render()
	end)
	plusButton.Activated:Connect(function()
		partySize = math.min(GameConfig.MaxPartySize, partySize + 1)
		render()
	end)
	createButton.Activated:Connect(function()
		if sent or not activeZone or not rooms[index] then
			return
		end
		sent = true
		createButton.Text = "CREATING..."
		UI.SetButtonEnabled(createButton, false, "CREATING...")
		Remotes.Event("CreateParty"):FireServer(activeZone:GetAttribute("QueueId"), rooms[index], partySize)
		Controllers.AudioController.Play("QueueEnter")
	end)
	backButton.Activated:Connect(function()
		if activeZone then
			Remotes.Event("LeaveQueue"):FireServer(activeZone:GetAttribute("QueueId"))
		end
		close()
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
		if not root.Visible or not activeZone then
			return
		end
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local deadline = activeZone:GetAttribute("SelectionDeadline") or 0
		local remaining = math.max(0, math.ceil(deadline - workspace:GetServerTimeNow()))
		footerLabel.Text = string.format("Auto-creates a 4-player party in %ds", remaining)
	end)
	evaluate()
end

return RoomSelectController
