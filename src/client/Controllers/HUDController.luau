--[[
	Lobby HUD and Match HUD. Reads replicated player attributes and MatchState attributes.
	Layout is thumb-friendly on touch: side buttons are taller, the SEARCH button sits above
	the default jump button, and nothing overlaps the left thumbstick zone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local FormatUtil = require(Shared.Utility.FormatUtil)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local HUDController = {}

local lobbyFrame: Frame
local matchFrame: Frame
local promptLabel: TextLabel
local mobileSearchButton: TextButton
local trashBombButton: TextButton
local cancelBombButton: TextButton
local hotColdFrame: Frame
local hotColdLabel: TextLabel
local timerLabel: TextLabel
local boostsFrame: Frame
local teamFrame: Frame
local bagLabel: TextLabel
local bagBar
local cashLabel: TextLabel
local progressBar
local progressLabel: TextLabel
local objectsLabel: TextLabel
local finderLabel: TextLabel
local resumeFrame: Frame
local resumeLabel: TextLabel
local roomTitleLabel: TextLabel
local roomTargetLabel: TextLabel
local hotColdPulseThread: thread? = nil

HUDController.Buttons = {}

local function attr(name: string, default: any)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local touch = UI.IsTouch()

local function sideButton(parent: Instance, text: string, color: Color3, order: number, icon: string?): TextButton
	local h = touch and 54 or 46
	local b = UI.Button({ Text = "", Color = color, Size = UDim2.fromOffset(160, h), TextSize = 18, LayoutOrder = order }, parent)
	if icon then
		local badge = UI.Frame({ Size = UDim2.fromOffset(h - 14, h - 14), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.65 }, b)
		UI.Corner(badge, 8)
		UI.Label({ Text = icon, TextSize = 14 }, badge)
		UI.Label({ Text = text, TextSize = 16, TextWrapped = false, Size = UDim2.new(1, -(h - 2), 1, 0), Position = UDim2.fromOffset(h - 2, 0), TextXAlignment = Enum.TextXAlignment.Left }, b)
	else
		b.Text = text
	end
	return b
end

local function buildLobbyHUD()
	lobbyFrame = UI.Frame({ Name = "LobbyHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)

	local top = UI.Panel({ Size = UDim2.fromOffset(340, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), BackgroundTransparency = 0.1 }, lobbyFrame)
	UI.Stroke(top, UI.Colors.Gold, 2)
	UI.Label({ Text = "OBJECTS FOUND", TextSize = 15, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 6) }, top)
	objectsLabel = UI.Label({ Text = "0 / 1000", TextSize = 32, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 28) }, top)

	finderLabel = UI.Label({ Text = "Finder Wins: 0", TextSize = 16, TextColor3 = UI.Colors.TextDim, Size = UDim2.fromOffset(340, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86) }, lobbyFrame)

	local buttons = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 220), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.45, 0) }, lobbyFrame)
	UI.ListLayout(buttons, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	HUDController.Buttons.Collection = sideButton(buttons, "COLLECTION", UI.Colors.Gold, 1, "1K")
	HUDController.Buttons.LobbyShop = sideButton(buttons, "SHOP", UI.Colors.Purple, 2, "$")
	HUDController.Buttons.LobbySettings = sideButton(buttons, "SETTINGS", UI.Colors.PanelLight, 3, "*")

	HUDController.Buttons.Collection.Activated:Connect(function()
		Controllers.CollectionController.Open()
	end)
	HUDController.Buttons.LobbyShop.Activated:Connect(function()
		Controllers.ShopController.Open()
	end)
	HUDController.Buttons.LobbySettings.Activated:Connect(function()
		Controllers.SettingsController.Open()
	end)

	resumeFrame = UI.Panel({ Size = UDim2.fromOffset(380, 80), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Visible = false, BackgroundTransparency = 0.05 }, lobbyFrame)
	UI.Stroke(resumeFrame, UI.Colors.Cyan, 2)
	resumeLabel = UI.Label({ Text = "RESUME ROOM #001 - 50% CHECKPOINT", TextSize = 18, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 4) }, resumeFrame)
	local hint = UI.Label({ Text = "Step into the circle to resume", TextSize = 14, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -140, 0, 26), Position = UDim2.fromOffset(10, 46), TextXAlignment = Enum.TextXAlignment.Left }, resumeFrame)
	hint.Font = UI.FontBody
	local fresh = UI.Button({ Text = "START FRESH", Color = UI.Colors.Red, Size = UDim2.fromOffset(124, 32), Position = UDim2.new(1, -132, 1, -38), TextSize = 14 }, resumeFrame)
	fresh.Activated:Connect(function()
		Remotes.Event("DiscardCheckpoint"):FireServer()
	end)
end

local function buildMatchHUD()
	matchFrame = UI.Frame({ Name = "MatchHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)

	-- Top center: room / target / progress
	local top = UI.Panel({ Size = UDim2.fromOffset(440, 100), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0.1 }, matchFrame)
	roomTitleLabel = UI.Label({ Text = "ROOM #001", TextSize = 20, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 5) }, top)
	roomTargetLabel = UI.Label({ Text = "Find the Golden Key", TextSize = 19, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 27) }, top)
	progressBar = UI.ProgressBar(top, UDim2.new(1, -32, 0, 22), UDim2.fromOffset(16, 52), UI.Colors.Green)
	progressLabel = UI.Label({ Text = "ROOM SEARCHED: 0%", TextSize = 14, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 }, progressBar.Frame)
	progressLabel.Font = UI.FontBody
	UI.Stroke(progressLabel, Color3.new(0, 0, 0), 1, 0.4)
	timerLabel = UI.Label({ Text = "00:00", TextSize = 15, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 78) }, top)
	timerLabel.Font = UI.FontBody

	-- Top left: cash and bag
	local left = UI.Panel({ Size = UDim2.fromOffset(210, 116), Position = UDim2.fromOffset(12, 10), BackgroundTransparency = 0.1 }, matchFrame)
	local cashBadge = UI.Frame({ Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(12, 10), BackgroundColor3 = UI.Colors.Cash }, left)
	UI.Corner(cashBadge, 15)
	UI.Label({ Text = "$", TextSize = 20, TextColor3 = UI.Colors.PanelDark }, cashBadge)
	cashLabel = UI.Label({ Text = "$0", TextSize = 30, TextColor3 = UI.Colors.Cash, Size = UDim2.new(1, -56, 0, 40), Position = UDim2.fromOffset(50, 5), TextXAlignment = Enum.TextXAlignment.Left }, left)
	local bagBadge = UI.Frame({ Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(12, 52), BackgroundColor3 = UI.Colors.Orange }, left)
	UI.Corner(bagBadge, 8)
	UI.Label({ Text = "BAG", TextSize = 11, TextColor3 = UI.Colors.PanelDark }, bagBadge)
	bagLabel = UI.Label({ Text = "0 / 40", TextSize = 20, Size = UDim2.new(1, -56, 0, 30), Position = UDim2.fromOffset(50, 52), TextXAlignment = Enum.TextXAlignment.Left }, left)
	bagBar = UI.ProgressBar(left, UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 92), UI.Colors.Orange)

	-- Right side buttons
	local buttons = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 320), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10) }, matchFrame)
	UI.ListLayout(buttons, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	HUDController.Buttons.Upgrades = sideButton(buttons, "UPGRADES", UI.Colors.Green, 1, "UP")
	HUDController.Buttons.Shop = sideButton(buttons, "SHOP", UI.Colors.Purple, 2, "$")
	HUDController.Buttons.Hint = sideButton(buttons, "HINT", UI.Colors.Cyan, 3, "?")
	HUDController.Buttons.Settings = sideButton(buttons, "SETTINGS", UI.Colors.PanelLight, 4, "*")
	trashBombButton = sideButton(buttons, "USE BOMB", UI.Colors.Orange, 5, "TB")
	trashBombButton.Visible = false
	cancelBombButton = sideButton(buttons, "CANCEL", UI.Colors.Red, 6, "X")
	cancelBombButton.Visible = false

	HUDController.Buttons.Upgrades.Activated:Connect(function()
		Controllers.UpgradeController.Open()
	end)
	HUDController.Buttons.Shop.Activated:Connect(function()
		Controllers.ShopController.Open()
	end)
	HUDController.Buttons.Hint.Activated:Connect(function()
		Controllers.ShopController.Open("Help")
	end)
	HUDController.Buttons.Settings.Activated:Connect(function()
		Controllers.SettingsController.Open()
	end)
	trashBombButton.Activated:Connect(function()
		Controllers.SearchController.EnterTrashBombMode()
	end)
	cancelBombButton.Activated:Connect(function()
		Controllers.SearchController.ExitTrashBombMode()
	end)

	boostsFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(180, 80), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, touch and 380 or 340) }, matchFrame)
	UI.ListLayout(boostsFrame, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)

	teamFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 120), Position = UDim2.fromOffset(12, 134) }, matchFrame)
	UI.ListLayout(teamFrame, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)

	-- Hot / cold indicator
	hotColdFrame = UI.Panel({ Size = UDim2.fromOffset(220, 46), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -118), Visible = false, BackgroundTransparency = 0.15 }, matchFrame)
	hotColdLabel = UI.Label({ Text = "", TextSize = 26, TextColor3 = UI.Colors.Orange }, hotColdFrame)

	-- Bottom prompt
	promptLabel = UI.Label({ Text = "", TextSize = 22, Size = UDim2.fromOffset(340, 36), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -66), Visible = false }, matchFrame)
	UI.Stroke(promptLabel, Color3.new(0, 0, 0), 2, 0.3)

	-- Mobile search button: above the default jump button, clear of the thumbstick.
	mobileSearchButton = UI.Button({ Text = "SEARCH", Color = UI.Colors.Green, Size = UDim2.fromOffset(112, 112), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -140), TextSize = 26, Corner = 56 }, matchFrame)
	UI.Stroke(mobileSearchButton, Color3.new(1, 1, 1), 3, 0.5)
	mobileSearchButton.Visible = touch
end

local function refreshLobby()
	local found = attr("ObjectsFound", 0)
	objectsLabel.Text = string.format("%d / %d", found, GameConfig.TotalObjects)
	finderLabel.Text = string.format("Finder Wins: %d", attr("FinderWins", 0))
	local cpRoom = attr("CheckpointRoomId", 0)
	local cpPercent = attr("CheckpointPercent", 0)
	if cpRoom > 0 and cpPercent > 0 then
		resumeFrame.Visible = true
		resumeLabel.Text = string.format("RESUME ROOM %s - %d%% CHECKPOINT", FormatUtil.RoomNumber(cpRoom), math.floor(cpPercent * 100))
	else
		resumeFrame.Visible = false
	end
end

local function refreshMatchStatic()
	roomTitleLabel.Text = "ROOM " .. FormatUtil.RoomNumber(matchState:GetAttribute("RoomId") or 1)
	roomTargetLabel.Text = "Find the " .. (matchState:GetAttribute("TargetName") or "")
end

local function refreshProgress()
	local p = matchState:GetAttribute("Progress") or 0
	progressBar.Set(p, true)
	progressLabel.Text = "ROOM SEARCHED: " .. FormatUtil.Percent(p)
end

local function refreshCash()
	cashLabel.Text = FormatUtil.CashExact(attr("RoomCash", 0))
end

local lastBag = 0
local function refreshBag()
	local cur = attr("BagCurrent", 0)
	local cap = attr("BagCapacity", 40)
	bagLabel.Text = string.format("%d / %d", cur, cap)
	local frac = cap > 0 and cur / cap or 0
	bagBar.Set(frac, true)
	if frac >= 1 then
		bagLabel.TextColor3 = UI.Colors.Red
		bagBar.Fill.BackgroundColor3 = UI.Colors.Red
	elseif frac >= 0.75 then
		bagLabel.TextColor3 = UI.Colors.Orange
		bagBar.Fill.BackgroundColor3 = UI.Colors.Orange
	else
		bagLabel.TextColor3 = UI.Colors.Text
		bagBar.Fill.BackgroundColor3 = UI.Colors.Orange
	end
	if cur > lastBag then
		Controllers.AudioController.Play("BagTick")
	end
	lastBag = cur
end

local function refreshVisibility()
	local inMatch = attr("InMatch", false)
	lobbyFrame.Visible = not inMatch
	matchFrame.Visible = inMatch
	if inMatch then
		refreshMatchStatic()
		refreshProgress()
		refreshCash()
		refreshBag()
	else
		refreshLobby()
		Controllers.FXController.SetVignette(nil, 1, 0.3)
	end
	Controllers.AudioController.SetMusic(inMatch and "RoomAmbience" or "LobbyAmbience")
end

local function refreshTeam()
	for _, c in ipairs(teamFrame:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local names = matchState:GetAttribute("PlayerNames") or ""
	local list = {}
	for name in string.gmatch(names, "[^,]+") do
		local p = Players:FindFirstChild(name)
		table.insert(list, { Name = name, Mess = p and (p:GetAttribute("ContributionMess") or 0) or 0, Me = p == player })
	end
	table.sort(list, function(a, b)
		return a.Mess > b.Mess
	end)
	if #list <= 1 then
		return
	end
	for i, entry in ipairs(list) do
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.3, LayoutOrder = i }, teamFrame)
		UI.Corner(row, 6)
		UI.Label({ Text = entry.Name, TextSize = 14, Font = UI.FontBody, TextColor3 = entry.Me and UI.Colors.Gold or UI.Colors.Text, Size = UDim2.new(0.65, 0, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		UI.Label({ Text = FormatUtil.Compact(entry.Mess), TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.35, -8, 1, 0), Position = UDim2.new(0.65, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
	end
end

local function refreshBoosts()
	for _, c in ipairs(boostsFrame:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local now = workspace:GetServerTimeNow()
	local entries = {}
	local sp = attr("SearchBoostExpires", 0)
	if sp > now then
		table.insert(entries, { Text = "2X SEARCH  " .. FormatUtil.Time(sp - now), Color = UI.Colors.Green })
	end
	local cb = attr("CashBoostExpires", 0)
	if cb > now then
		table.insert(entries, { Text = "2X CASH  " .. FormatUtil.Time(cb - now), Color = UI.Colors.Cash })
	end
	local ts = matchState:GetAttribute("TeamSurgeExpires") or 0
	if ts > now then
		table.insert(entries, { Text = "TEAM SURGE  " .. FormatUtil.Time(ts - now), Color = UI.Colors.Purple })
	end
	for i, e in ipairs(entries) do
		local row = UI.Frame({ Size = UDim2.fromOffset(170, 22), BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.2, LayoutOrder = i }, boostsFrame)
		UI.Corner(row, 6)
		UI.Stroke(row, e.Color, 1)
		UI.Label({ Text = e.Text, TextSize = 14, Font = UI.FontBody, TextColor3 = e.Color }, row)
	end
	local bombs = attr("PendingTrashBombs", 0)
	trashBombButton.Visible = bombs > 0 and not Controllers.SearchController.IsTrashBombMode()
end

local HotColdStyle = {
	COLD = { Color = UI.Colors.Cyan, Vignette = 1, Pulse = 0 },
	WARM = { Color = UI.Colors.Orange, Vignette = 0.85, Pulse = 1.2 },
	HOT = { Color = UI.Colors.Red, Vignette = 0.7, Pulse = 2.2 },
	["VERY HOT"] = { Color = UI.Colors.Gold, Vignette = 0.55, Pulse = 4 },
}

local function refreshHotCold()
	local state = attr("HotCold", "")
	if hotColdPulseThread then
		task.cancel(hotColdPulseThread)
		hotColdPulseThread = nil
	end
	if state == "" then
		hotColdFrame.Visible = false
		Controllers.FXController.SetVignette(nil, 1, 0.4)
		return
	end
	local style = HotColdStyle[state] or HotColdStyle.COLD
	hotColdFrame.Visible = true
	hotColdLabel.Text = state
	hotColdLabel.TextColor3 = style.Color
	local stroke = hotColdFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = style.Color
	end
	Controllers.FXController.SetVignette(style.Color, style.Vignette, 0.5)
	if state == "HOT" or state == "VERY HOT" then
		Controllers.AudioController.Play("HotColdPing")
	end
	if style.Pulse > 0 then
		hotColdPulseThread = task.spawn(function()
			local s = hotColdFrame:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, hotColdFrame)
			while hotColdFrame.Visible do
				UI.Tween(s, { Scale = 1.08 }, 0.5 / style.Pulse)
				task.wait(0.5 / style.Pulse)
				UI.Tween(s, { Scale = 1 }, 0.5 / style.Pulse)
				task.wait(0.5 / style.Pulse)
			end
			s.Scale = 1
		end)
	end
end

function HUDController.Init()
	buildLobbyHUD()
	buildMatchHUD()

	player:GetAttributeChangedSignal("InMatch"):Connect(refreshVisibility)
	for _, name in ipairs({ "ObjectsFound", "FinderWins", "CheckpointRoomId", "CheckpointPercent" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if lobbyFrame.Visible then
				refreshLobby()
			end
		end)
	end
	player:GetAttributeChangedSignal("RoomCash"):Connect(refreshCash)
	player:GetAttributeChangedSignal("BagCurrent"):Connect(refreshBag)
	player:GetAttributeChangedSignal("BagCapacity"):Connect(refreshBag)
	player:GetAttributeChangedSignal("HotCold"):Connect(refreshHotCold)
	matchState:GetAttributeChangedSignal("Progress"):Connect(refreshProgress)
	matchState:GetAttributeChangedSignal("RoomId"):Connect(refreshMatchStatic)
	matchState:GetAttributeChangedSignal("TargetName"):Connect(refreshMatchStatic)
	matchState:GetAttributeChangedSignal("PlayerNames"):Connect(refreshTeam)
	Players.PlayerAdded:Connect(function(p)
		p:GetAttributeChangedSignal("ContributionMess"):Connect(refreshTeam)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p:GetAttributeChangedSignal("ContributionMess"):Connect(refreshTeam)
	end

	refreshVisibility()
end

function HUDController.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not matchFrame.Visible then
			return
		end
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local start = matchState:GetAttribute("StartTime") or 0
		local finish = matchState:GetAttribute("EndTime") or 0
		if start > 0 then
			local endT = finish > 0 and finish or workspace:GetServerTimeNow()
			timerLabel.Text = FormatUtil.Time(endT - start)
		else
			timerLabel.Text = "00:00"
		end
		refreshBoosts()
	end)
	task.delay(1, refreshTeam)
end

function HUDController.SetPrompt(text: string?)
	if text then
		promptLabel.Text = text
		promptLabel.Visible = true
	else
		promptLabel.Visible = false
	end
end

function HUDController.GetMobileSearchButton(): TextButton
	return mobileSearchButton
end

function HUDController.SetSearchButtonActive(active: boolean)
	if not mobileSearchButton.Visible then
		return
	end
	mobileSearchButton.BackgroundTransparency = active and 0 or 0.45
end

function HUDController.SetTrashBombModeUI(active: boolean)
	cancelBombButton.Visible = active
	trashBombButton.Visible = not active and (attr("PendingTrashBombs", 0) > 0)
	if active then
		mobileSearchButton.Text = "BOMB"
		mobileSearchButton.BackgroundColor3 = UI.Colors.Orange
	else
		mobileSearchButton.Text = "SEARCH"
		mobileSearchButton.BackgroundColor3 = UI.Colors.Green
	end
end

function HUDController.PulseCash()
	UI.Tween(cashLabel, { TextSize = 36 }, 0.08).Completed:Once(function()
		UI.Tween(cashLabel, { TextSize = 30 }, 0.2)
	end)
end

-- Screen-space centre of the cash label (for coin fly-to effects), in scaled GUI space.
function HUDController.GetCashLabelPosition(): UDim2
	local absPos = cashLabel.AbsolutePosition
	local absSize = cashLabel.AbsoluteSize
	local scale = UI.Scale
	return UDim2.fromOffset((absPos.X + 20) / scale, (absPos.Y + absSize.Y / 2) / scale)
end

function HUDController.FlashBagFull()
	UI.Flash(bagBar.Frame, UI.Colors.Red, 0.6)
	UI.Shake(bagLabel, 3, 0.3)
end

function HUDController.GetMatchFrame(): Frame
	return matchFrame
end

function HUDController.GetLobbyFrame(): Frame
	return lobbyFrame
end

return HUDController
