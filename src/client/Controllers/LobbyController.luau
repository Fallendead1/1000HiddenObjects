--[[
	Lobby world GUIs and ambient motion: queue sign + ring/light colours by state, big
	countdown, collection board, shop stand, leaderboards, future door, rotating key.
	All geometry is server-built and tagged; this controller only attaches GUIs and animates.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local FormatUtil = require(Shared.Utility.FormatUtil)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local LobbyController = {}

local attached: { [Instance]: boolean } = {}
local queueZone: BasePart? = nil
local lastCountdown = -1

local StateColors = {
	Empty = UI.Colors.Green,
	Waiting = UI.Colors.Green,
	CountingDown = UI.Colors.Gold,
	Locked = UI.Colors.Red,
	Teleporting = UI.Colors.Red,
	Resetting = UI.Colors.Locked,
}

local function setQueueColor(color: Color3)
	if queueZone then
		TweenService:Create(queueZone, TweenInfo.new(0.3), { Color = color }):Play()
	end
	for _, light in ipairs(CollectionService:GetTagged("QueueLight")) do
		if light:IsA("BasePart") then
			TweenService:Create(light, TweenInfo.new(0.3), { Color = color }):Play()
		end
	end
end

local function attachQueueSign(zone: BasePart)
	queueZone = zone
	local anchor = zone.Parent and zone.Parent:FindFirstChild("QueueSignAnchor") or zone
	local bb = UI.Billboard(anchor :: BasePart, UDim2.fromOffset(340, 240), Vector3.new(0, 1, 0), 150)
	bb.Name = "QueueSign"
	local panel = UI.Panel({ BackgroundTransparency = 0.1 }, bb)
	UI.Stroke(panel, UI.Colors.Green, 3)
	local play = UI.Label({ Text = "PLAY", TextSize = 70, TextColor3 = UI.Colors.Green, Size = UDim2.new(1, 0, 0, 78), Position = UDim2.fromOffset(0, 2) }, panel)
	UI.Label({ Text = "1 - 4 PLAYERS", TextSize = 22, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 78) }, panel)
	local status = UI.Label({ Text = "STEP INSIDE TO PLAY", TextSize = 26, Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 108) }, panel)
	local countdown = UI.Label({ Text = "", TextSize = 56, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 150) }, panel)
	local sub = UI.Label({ Text = "", TextSize = 16, Font = UI.FontBody, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(8, 214) }, panel)
	local stroke = panel:FindFirstChildOfClass("UIStroke")

	local lastCount = 0
	local function refresh()
		local state = zone:GetAttribute("State") or "Empty"
		local count = zone:GetAttribute("Count") or 0
		local max = zone:GetAttribute("MaxPlayers") or GameConfig.MaxPartySize
		local cd = zone:GetAttribute("Countdown") or 0
		local msg = zone:GetAttribute("Message") or ""
		local color = StateColors[state] or UI.Colors.Green
		if stroke then
			stroke.Color = color
		end
		play.TextColor3 = color
		setQueueColor(color)
		if state == "Empty" or count == 0 then
			status.Text = "STEP INSIDE TO PLAY"
			countdown.Text = ""
			sub.Text = ""
		elseif state == "CountingDown" then
			status.Text = string.format("%d / %d PLAYERS", count, max)
			countdown.Text = count >= max and "GO!" or tostring(cd)
			sub.Text = (count >= max and "FULL PARTY - STARTING" or "STARTING IN") .. (msg ~= "" and ("  |  " .. msg) or "")
			if cd ~= lastCountdown then
				lastCountdown = cd
				local s = countdown:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, countdown)
				s.Scale = 1.35
				UI.Tween(s, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
				if cd <= 3 and player:GetAttribute("Queued") then
					Controllers.AudioController.Play("Countdown")
				end
			end
		else
			status.Text = string.format("%d / %d PLAYERS", count, max)
			countdown.Text = "GO!"
			sub.Text = "STARTING..."
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

	task.spawn(function()
		while zone.Parent do
			local state = zone:GetAttribute("State")
			if state == "CountingDown" then
				UI.Tween(zone, { Transparency = 0.05 }, 0.4)
				task.wait(0.4)
				UI.Tween(zone, { Transparency = 0.5 }, 0.4)
				task.wait(0.4)
			else
				UI.Tween(zone, { Transparency = 0.3 }, 1.2)
				task.wait(1.2)
				UI.Tween(zone, { Transparency = 0.5 }, 1.2)
				task.wait(1.2)
			end
		end
	end)
end

local function attachCollectionBoard(part: BasePart)
	local sg = UI.Surface(part, Enum.NormalId.Right, 30)
	sg.Name = "CollectionBoardGui"
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	UI.Label({ Text = "YOUR COLLECTION", TextSize = 44, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0.2, 0) }, panel)
	local count = UI.Label({ Text = "0 / 1000", TextSize = 100, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.18) }, panel)
	local bar = UI.ProgressBar(panel, UDim2.new(0.8, 0, 0.06, 0), UDim2.fromScale(0.1, 0.6), UI.Colors.Gold)
	local button = UI.Button({ Text = "VIEW COLLECTION", Color = UI.Colors.Gold, Size = UDim2.new(0.6, 0, 0.16, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.72), TextSize = 40 }, panel)
	button.Activated:Connect(function()
		Controllers.CollectionController.Open()
	end)
	local function refresh()
		local found = player:GetAttribute("ObjectsFound") or 0
		count.Text = string.format("%d / %d", found, GameConfig.TotalObjects)
		bar.Set(found / GameConfig.TotalObjects)
	end
	player:GetAttributeChangedSignal("ObjectsFound"):Connect(refresh)
	refresh()
end

local function attachShopStand(part: BasePart)
	local bb = UI.Billboard(part, UDim2.fromOffset(220, 80), Vector3.new(0, 12, 0), 90)
	local panel = UI.Panel({ BackgroundTransparency = 0.1 }, bb)
	UI.Stroke(panel, UI.Colors.Purple, 3)
	UI.Label({ Text = "SHOP", TextSize = 44, TextColor3 = UI.Colors.Purple }, panel)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		local sg = UI.Surface(part, face, 30)
		local b = UI.Button({ Text = "OPEN SHOP", Color = UI.Colors.Purple, Size = UDim2.new(0.8, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextSize = 30 }, sg)
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
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = i == 1 and UI.Colors.GoldDark or UI.Colors.PanelLight, LayoutOrder = i }, list)
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
	local bb = UI.Billboard(part, UDim2.fromOffset(280, 64), Vector3.new(0, 6, 0), 80)
	local panel = UI.Panel({ BackgroundTransparency = 0.1 }, bb)
	UI.Stroke(panel, UI.Colors.Gold, 2)
	UI.Label({ Text = part:GetAttribute("Label") or "MORE ROOMS COMING SOON", TextSize = 22, TextColor3 = UI.Colors.Gold }, panel)
end

local function spinKey(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local base = model:GetPivot()
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function()
		if not model.Parent then
			return
		end
		local t = os.clock() - t0
		model:PivotTo(base * CFrame.new(0, math.sin(t * 1.5) * 0.6, 0) * CFrame.Angles(0, t * 0.8, math.sin(t * 0.7) * 0.15))
	end)
end

local handlers = {
	QueueZone = attachQueueSign,
	CollectionBoard = attachCollectionBoard,
	ShopStand = attachShopStand,
	Leaderboard = attachLeaderboard,
	FutureDoor = attachFutureDoor,
	LobbyKeyDeco = spinKey,
}

local function tryAttach(tag: string, inst: Instance)
	if attached[inst] then
		return
	end
	if tag ~= "LobbyKeyDeco" and not inst:IsA("BasePart") then
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
