--[[
	Party setup panel for the host of a matchmaking circle (the first player in, while the
	circle is in the Selecting state): pick a room (any unlocked one, defaulting to the next
	required room), a party size (1 = solo run, closed to everyone else) and, once the room has
	been cleared, HARD MODE; then CREATE. BACK (under the panel) teleports you out of the circle,
	and so does not creating a party in time.
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
local dim: Frame
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
local hardButton: TextButton
local hardLock: Frame
local hardHint: TextLabel
local createButton: TextButton
local footerLabel: TextLabel

local PANEL_HEIGHT = 510
local ROOT_HEIGHT = PANEL_HEIGHT + 18 + 56 -- the BACK button hangs under the panel

local rooms: { number } = {}
local index = 1
local partySize = 1 -- remembered between parties this session
local hard = false
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

-- Hard Mode for a room unlocks once its object has been found (the server checks too).
local function hardUnlocked(roomId: number?): boolean
	return roomId ~= nil and (player:GetAttribute("HighestRoomCompleted") or 0) >= roomId
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

	local unlocked = hardUnlocked(roomId)
	if not unlocked then
		hard = false
	end
	hardLock.Visible = not unlocked
	if not unlocked then
		hardButton.Text = "HARD MODE"
		hardButton.BackgroundColor3 = UI.Colors.Locked
		hardHint.Text = "Find the key in this room to unlock"
		hardHint.TextColor3 = UI.Colors.TextDim
	elseif hard then
		hardButton.Text = "HARD MODE: ON"
		hardButton.BackgroundColor3 = UI.Colors.Red
		hardHint.Text = "Way more junk to dig through  ·  no Fastest record"
		hardHint.TextColor3 = UI.Colors.Red
	else
		hardButton.Text = "HARD MODE: OFF"
		hardButton.BackgroundColor3 = UI.Colors.PanelLight
		hardHint.Text = "Unlocked! Tap to turn it on"
		hardHint.TextColor3 = UI.Colors.Gold
	end
end

local function close()
	root.Visible = false
	activeZone = nil
	sent = false
	Controllers.HUDController.SetCounterVisible(true)
	UI.Tween(dim, { BackgroundTransparency = 1 }, 0.15).Completed:Once(function()
		if not root.Visible then
			dim.Visible = false
		end
	end)
end

local function open(zone: BasePart)
	if activeZone == zone and root.Visible then
		return
	end
	activeZone = zone
	sent = false
	hard = false
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
	UI.FitScale(root, Vector2.new(400, ROOT_HEIGHT)) -- phones: the whole panel shrinks to fit under the top bar
	UI.PopIn(root, 0.85, 0.22)
	dim.Visible = true
	UI.Tween(dim, { BackgroundTransparency = 0.5 }, 0.2)
	Controllers.HUDController.SetCounterVisible(false)
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

-- A small padlock drawn with two shapes (a ring over a body), for the locked Hard Mode button.
local function makeLock(parent: Instance): Frame
	local lock = UI.Frame({ Name = "Lock", BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 24), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.45, 0), ZIndex = 10 }, parent)
	local shackle = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 16), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 10 }, lock)
	UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, shackle)
	UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }, shackle)
	local body = UI.Frame({ BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(22, 14), Position = UDim2.fromOffset(0, 10), ZIndex = 11 }, lock)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 4) }, body)
	UI.New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2 }, body)
	return lock
end

function RoomSelectController.Init()
	-- Dims the world and HUD behind the panel like a menu does (clicks still pass through).
	dim = UI.Frame({ Name = "PartyDim", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -200), Size = UDim2.new(1, 0, 1, 200), Visible = false, ZIndex = 0 }, UI.Layers.Menus)

	-- The panel, with the BACK button hanging under it.
	root = UI.Frame({ Name = "PartySetup", BackgroundTransparency = 1, Size = UDim2.fromOffset(400, ROOT_HEIGHT), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Visible = false }, UI.Layers.Menus)
	local panel = UI.Panel({ Size = UDim2.new(1, 0, 0, PANEL_HEIGHT), BackgroundTransparency = 0.03 }, root)
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

	-- Hard Mode: locked (padlock) until this room's object has been found once.
	hardButton = UI.Button({ Name = "HardModeButton", Text = "HARD MODE", Color = UI.Colors.Locked, Size = UDim2.fromOffset(250, 42), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 352), TextSize = 20 }, panel)
	hardLock = makeLock(hardButton)
	hardHint = UI.Label({ Text = "", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -40, 0, 16), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 398) }, panel)

	createButton = UI.Button({ Name = "CreateButton", Text = "CREATE", Color = UI.Colors.Green, Size = UDim2.fromOffset(250, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 424), TextSize = 30, Shine = 2.4 }, panel)
	UI.Pulse(createButton, 0.03, 3)
	footerLabel = UI.Label({ Text = "", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 486) }, panel)

	local backButton = UI.Button({ Name = "BackButton", Text = "BACK", Color = UI.Colors.Red, Size = UDim2.fromOffset(190, 56), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), TextSize = 30 }, root)

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
	hardButton.Activated:Connect(function()
		local roomId = rooms[index]
		if not roomId then
			return
		end
		if not hardUnlocked(roomId) then
			local config = RoomRegistry.Get(roomId)
			Controllers.NotificationController.Show("Info", string.format("Hard Mode unlocks after you find the %s in Room #%s.", config and config.TargetName or "object", config and config.DisplayNumber or ""))
			UI.Shake(hardButton, 5, 0.3)
			return
		end
		hard = not hard
		render()
	end)
	createButton.Activated:Connect(function()
		if sent or not activeZone or not rooms[index] then
			return
		end
		sent = true
		createButton.Text = "CREATING..."
		UI.SetButtonEnabled(createButton, false, "CREATING...")
		Remotes.Event("CreateParty"):FireServer(activeZone:GetAttribute("QueueId"), rooms[index], partySize, hard)
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
		footerLabel.Text = string.format("Create a party within %ds or you'll leave the circle", remaining)
	end)
	evaluate()
end

-- The CREATE button while the party panel is up (the tutorial points at it), else nil.
function RoomSelectController.GetCreateButton(): TextButton?
	return root and root.Visible and createButton or nil
end

return RoomSelectController
