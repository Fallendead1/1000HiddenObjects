--[[
	Lobby world GUIs: queue sign, collection board, shop stand, leaderboards, future door.
	All geometry is server-built and tagged; this controller only attaches GUIs.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local FormatUtil = require(Shared.Utility.FormatUtil)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local LobbyController = {}

local attached: { [Instance]: boolean } = {}

local function attachQueueSign(zone: BasePart)
	local anchor = zone.Parent and zone.Parent:FindFirstChild("QueueSignAnchor") or zone
	local bb = UI.Billboard(anchor :: BasePart, UDim2.fromOffset(360, 200), Vector3.new(0, 2, 0), 150)
	bb.Name = "QueueSign"
	local panel = UI.Panel({ BackgroundTransparency = 0.15 }, bb)
	UI.Label({ Text = "PLAY", TextSize = 64, TextColor3 = UI.Colors.Green, Size = UDim2.new(1, 0, 0, 74), Position = UDim2.fromOffset(0, 4) }, panel)
	UI.Label({ Text = "1 - 4 PLAYERS", TextSize = 22, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 76) }, panel)
	local status = UI.Label({ Text = "STEP INSIDE TO PLAY", TextSize = 26, Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 108) }, panel)
	local countdown = UI.Label({ Text = "", TextSize = 22, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 150) }, panel)

	local lastCount = 0
	local function refresh()
		local state = zone:GetAttribute("State") or "Empty"
		local count = zone:GetAttribute("Count") or 0
		local max = zone:GetAttribute("MaxPlayers") or GameConfig.MaxPartySize
		local cd = zone:GetAttribute("Countdown") or 0
		local msg = zone:GetAttribute("Message") or ""
		if state == "Empty" or count == 0 then
			status.Text = "STEP INSIDE TO PLAY"
			status.TextColor3 = UI.Colors.Text
			countdown.Text = ""
		elseif state == "CountingDown" then
			status.Text = string.format("%d / %d PLAYERS", count, max)
			status.TextColor3 = UI.Colors.Text
			countdown.Text = count >= max and "STARTING..." or string.format("STARTING IN %d", cd)
			if msg ~= "" then
				countdown.Text = countdown.Text .. "\n" .. msg
			end
		else
			status.Text = string.format("%d / %d PLAYERS", count, max)
			countdown.Text = "STARTING..."
		end
		if count ~= lastCount then
			if player:GetAttribute("Queued") then
				Controllers.AudioController.Play(count > lastCount and "QueueEnter" or "QueueLeave")
			end
			lastCount = count
		end
	end
	for _, name in ipairs({ "State", "Count", "Countdown", "Message", "MaxPlayers" }) do
		zone:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()

	-- Glow pulse while counting down
	task.spawn(function()
		while zone.Parent do
			local state = zone:GetAttribute("State")
			if state == "CountingDown" then
				UI.Tween(zone, { Transparency = 0.05 }, 0.5)
				task.wait(0.5)
				UI.Tween(zone, { Transparency = 0.4 }, 0.5)
				task.wait(0.5)
			else
				zone.Transparency = 0.25
				task.wait(0.5)
			end
		end
	end)
end

local function attachCollectionBoard(part: BasePart)
	local sg = UI.Surface(part, Enum.NormalId.Right, 30)
	sg.Name = "CollectionBoardGui"
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	UI.Label({ Text = "YOUR COLLECTION", TextSize = 44, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0.22, 0) }, panel)
	local count = UI.Label({ Text = "0 / 1000", TextSize = 96, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.2) }, panel)
	local button = UI.Button({ Text = "VIEW COLLECTION", Color = UI.Colors.Gold, Size = UDim2.new(0.6, 0, 0.16, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.68), TextSize = 40 }, panel)
	button.Activated:Connect(function()
		Controllers.CollectionController.Open()
	end)
	local function refresh()
		count.Text = string.format("%d / %d", player:GetAttribute("ObjectsFound") or 0, GameConfig.TotalObjects)
	end
	player:GetAttributeChangedSignal("ObjectsFound"):Connect(refresh)
	refresh()
end

local function attachShopStand(part: BasePart)
	local bb = UI.Billboard(part, UDim2.fromOffset(200, 70), Vector3.new(0, 5, 0), 80)
	local panel = UI.Panel({ BackgroundTransparency = 0.15 }, bb)
	UI.Label({ Text = "SHOP", TextSize = 40, TextColor3 = UI.Colors.Purple }, panel)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sg = UI.Surface(part, face, 30)
		local b = UI.Button({ Text = "OPEN SHOP", Color = UI.Colors.Purple, Size = UDim2.new(0.8, 0, 0.4, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextSize = 30 }, sg)
		b.Activated:Connect(function()
			Controllers.ShopController.Open()
		end)
	end
end

local function attachLeaderboard(part: BasePart)
	local kind = part:GetAttribute("Kind") or "TopFinders"
	local sg = UI.Surface(part, Enum.NormalId.Front, 30)
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	UI.Label({ Text = kind == "Fastest" and "FASTEST ROOM #001" or "TOP OBJECT FINDERS", TextSize = 40, TextColor3 = kind == "Fastest" and UI.Colors.Cyan or UI.Colors.Gold, Size = UDim2.new(1, 0, 0.14, 0) }, panel)
	local list = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0.84, 0), Position = UDim2.new(0, 10, 0.15, 0) }, panel)
	UI.ListLayout(list, Enum.FillDirection.Vertical, 4)

	local data = ReplicatedStorage:WaitForChild("LeaderboardData")
	local attrName = kind == "Fastest" and "Fastest" or "TopFinders"
	local function refresh()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local ok, entries = pcall(function()
			return HttpService:JSONDecode(data:GetAttribute(attrName) or "[]")
		end)
		if not ok or type(entries) ~= "table" then
			return
		end
		if #entries == 0 then
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, list)
			UI.Label({ Text = "No entries yet - be the first!", TextSize = 22, TextColor3 = UI.Colors.TextDim }, row)
		end
		for i, e in ipairs(entries) do
			if i > 10 then
				break
			end
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, list)
			UI.Corner(row, 6)
			UI.Label({ Text = string.format("%d. %s", i, e.Name or "?"), TextSize = 22, Font = UI.FontBody, Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = e.UserId == player.UserId and UI.Colors.Gold or UI.Colors.Text }, row)
			local valueText = kind == "Fastest" and FormatUtil.Time(e.Value or 0) or tostring(e.Value or 0)
			UI.Label({ Text = valueText, TextSize = 22, Font = UI.FontBody, Size = UDim2.new(0.3, -10, 1, 0), Position = UDim2.new(0.7, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.TextDim }, row)
		end
	end
	data:GetAttributeChangedSignal(attrName):Connect(refresh)
	refresh()
end

local function attachFutureDoor(part: BasePart)
	local bb = UI.Billboard(part, UDim2.fromOffset(260, 60), Vector3.new(0, 6, 0), 80)
	local panel = UI.Panel({ BackgroundTransparency = 0.15 }, bb)
	UI.Label({ Text = part:GetAttribute("Label") or "MORE ROOMS COMING SOON", TextSize = 22, TextColor3 = UI.Colors.Gold }, panel)
end

local handlers = {
	QueueZone = attachQueueSign,
	CollectionBoard = attachCollectionBoard,
	ShopStand = attachShopStand,
	Leaderboard = attachLeaderboard,
	FutureDoor = attachFutureDoor,
}

local function tryAttach(tag: string, inst: Instance)
	if attached[inst] or not inst:IsA("BasePart") then
		return
	end
	attached[inst] = true
	task.spawn(handlers[tag], inst)
end

function LobbyController.Init()
	for tag, _ in pairs(handlers) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			tryAttach(tag, inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			tryAttach(tag, inst)
		end)
	end
end

return LobbyController
