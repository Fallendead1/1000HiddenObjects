--[[
	Lobby HUD and Match HUD. Reads replicated player attributes and MatchState attributes.
	Match HUD: Cash + max weight + deposit streak (top left), room / target / ROOM CLEANED %
	(top centre), UPGRADES / SHOP / HINT / SETTINGS (right), boosts, team, hot/cold, and on
	touch a big GRAB / THROW button plus a DROP button driven by GrabController.
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
local mobileActionButton: TextButton
local mobileDropButton: TextButton
local streakFrame: Frame
local streakLabel: TextLabel
local streakBar
local hotColdFrame: Frame
local hotColdLabel: TextLabel
local timerLabel: TextLabel
local boostsFrame: Frame
local teamFrame: Frame
local cashLabel: TextLabel
local cashGlow: Instance
local shownCash = 0
local weightLabel: TextLabel
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

local touch = UI.IsTouch()

local function attr(name: string, default: any)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local function sideButton(parent: Instance, text: string, color: Color3, order: number, icon: string, iconKey: string): TextButton
	local h = touch and 54 or 46
	local b = UI.Button({ Text = "", Color = color, Size = UDim2.fromOffset(160, h), TextSize = 18, LayoutOrder = order }, parent)
	local badge = UI.Frame({ Size = UDim2.fromOffset(h - 14, h - 14), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.65 }, b)
	UI.Corner(badge, 8)
	UI.Icon(badge, iconKey, icon, { TextSize = 14 })
	UI.Label({ Text = text, TextSize = 16, TextWrapped = false, Size = UDim2.new(1, -(h - 2), 1, 0), Position = UDim2.fromOffset(h - 2, 0), TextXAlignment = Enum.TextXAlignment.Left }, b)
	UI.Shine(b, 5 + order * 0.9)
	return b
end

local function buildLobbyHUD()
	lobbyFrame = UI.Frame({ Name = "LobbyHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)
	local top = UI.Panel({ Size = UDim2.fromOffset(340, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), BackgroundTransparency = 0.1 }, lobbyFrame)
	UI.Stroke(top, UI.Colors.Gold, 2)
	UI.Label({ Text = "OBJECTS FOUND", TextSize = 15, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 6) }, top)
	objectsLabel = UI.Label({ Text = "0 / 1000", TextSize = 32, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 28) }, top)
	finderLabel = UI.Label({ Text = "Finder Wins: 0", TextSize = 16, TextColor3 = UI.Colors.TextDim, Size = UDim2.fromOffset(340, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86) }, lobbyFrame)

	local buttons = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 320), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.45, 0) }, lobbyFrame)
	UI.ListLayout(buttons, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	HUDController.Buttons.Collection = sideButton(buttons, "COLLECTION", UI.Colors.Gold, 1, "1K", "Icon_Collection")
	HUDController.Buttons.Challenges = sideButton(buttons, "CHALLENGES", UI.Colors.Cyan, 2, "!", "Icon_Challenges")
	HUDController.Buttons.LobbyShop = sideButton(buttons, "SHOP", UI.Colors.Purple, 3, "$", "Icon_Shop")
	HUDController.Buttons.Invite = sideButton(buttons, "INVITE", UI.Colors.Green, 4, "+", "Icon_Invite")
	HUDController.Buttons.LobbySettings = sideButton(buttons, "SETTINGS", UI.Colors.PanelLight, 5, "*", "Icon_Settings")
	HUDController.Buttons.Collection.Activated:Connect(function()
		Controllers.CollectionController.Open()
	end)
	HUDController.Buttons.Challenges.Activated:Connect(function()
		Controllers.ProgressionController.OpenChallenges()
	end)
	HUDController.Buttons.Invite.Activated:Connect(function()
		Controllers.ProgressionController.Invite()
	end)
	HUDController.Buttons.LobbyShop.Activated:Connect(function()
		Controllers.ShopController.Open()
	end)
	HUDController.Buttons.LobbySettings.Activated:Connect(function()
		Controllers.SettingsController.Open()
	end)

	resumeFrame = UI.Panel({ Size = UDim2.fromOffset(380, 80), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Visible = false, BackgroundTransparency = 0.05 }, lobbyFrame)
	UI.Stroke(resumeFrame, UI.Colors.Cyan, 2)
	resumeLabel = UI.Label({ Text = "", TextSize = 18, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 4) }, resumeFrame)
	UI.Label({ Text = "Step into a circle to resume", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -140, 0, 26), Position = UDim2.fromOffset(10, 46), TextXAlignment = Enum.TextXAlignment.Left }, resumeFrame)
	local fresh = UI.Button({ Text = "START FRESH", Color = UI.Colors.Red, Size = UDim2.fromOffset(124, 32), Position = UDim2.new(1, -132, 1, -38), TextSize = 14 }, resumeFrame)
	fresh.Activated:Connect(function()
		Remotes.Event("DiscardCheckpoint"):FireServer()
	end)
end

local function buildMatchHUD()
	matchFrame = UI.Frame({ Name = "MatchHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)

	local top = UI.Panel({ Size = UDim2.fromOffset(440, 100), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0.1 }, matchFrame)
	roomTitleLabel = UI.Label({ Text = "ROOM #001", TextSize = 20, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 5) }, top)
	roomTargetLabel = UI.Label({ Text = "Find the Golden Key", TextSize = 19, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 27) }, top)
	UI.Glow(top, UI.Colors.Gold, 18, 0.75)
	progressBar = UI.ProgressBar(top, UDim2.new(1, -32, 0, 22), UDim2.fromOffset(16, 52), UI.Colors.Green)
	UI.Shine(progressBar.Fill, 2.6)
	progressLabel = UI.Label({ Text = "ROOM CLEANED: 0%", TextSize = 14, Font = UI.FontBody, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 }, progressBar.Frame)
	UI.Stroke(progressLabel, Color3.new(0, 0, 0), 1, 0.4)
	timerLabel = UI.Label({ Text = "00:00", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 78) }, top)

	local left = UI.Panel({ Size = UDim2.fromOffset(210, 80), Position = UDim2.fromOffset(12, 10), BackgroundTransparency = 0.1 }, matchFrame)
	cashGlow = UI.Glow(left, UI.Colors.Cash, 16, 0.9)
	local cashBadge = UI.Frame({ Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(12, 10), BackgroundColor3 = UI.Colors.Cash }, left)
	UI.Corner(cashBadge, 15)
	UI.Icon(cashBadge, "Icon_Cash", "$", { TextSize = 20, TextColor3 = UI.Colors.PanelDark })
	cashLabel = UI.Label({ Text = "$0", TextSize = 30, TextColor3 = UI.Colors.Cash, Size = UDim2.new(1, -56, 0, 40), Position = UDim2.fromOffset(50, 5), TextXAlignment = Enum.TextXAlignment.Left }, left)
	local weightIcon = UI.Frame({ Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(12, 51), BackgroundTransparency = 1 }, left)
	UI.Icon(weightIcon, "Icon_Weight", "", {})
	weightLabel = UI.Label({ Text = "MAX WEIGHT: 2", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -44, 0, 22), Position = UDim2.fromOffset(UI.Asset("Icon_Weight") and 36 or 12, 50), TextXAlignment = Enum.TextXAlignment.Left }, left)

	-- Deposit streak: shows while deposits keep coming within the streak window.
	streakFrame = UI.Panel({ Size = UDim2.fromOffset(210, 30), Position = UDim2.fromOffset(12, 96), BackgroundTransparency = 0.1, Visible = false }, matchFrame)
	UI.Stroke(streakFrame, UI.Colors.Gold, 2)
	local streakIcon = UI.Frame({ Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(6, 4), BackgroundTransparency = 1 }, streakFrame)
	UI.Icon(streakIcon, "Icon_Streak", "", {})
	streakLabel = UI.Label({ Text = "STREAK x2", TextSize = 15, TextColor3 = UI.Colors.Gold, Size = UDim2.new(0, 110, 1, 0), Position = UDim2.fromOffset(32, 0), TextXAlignment = Enum.TextXAlignment.Left }, streakFrame)
	streakBar = UI.ProgressBar(streakFrame, UDim2.new(0, 56, 0, 8), UDim2.new(1, -64, 0.5, -4), UI.Colors.Gold)
	UI.Glow(streakFrame, UI.Colors.Orange, 14, 0.5)
	UI.Pulse(streakFrame, 0.035, 7)

	local buttons = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(170, 260), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10) }, matchFrame)
	UI.ListLayout(buttons, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
	HUDController.Buttons.Upgrades = sideButton(buttons, "UPGRADES", UI.Colors.Green, 1, "UP", "Icon_Upgrades")
	HUDController.Buttons.Shop = sideButton(buttons, "SHOP", UI.Colors.Purple, 2, "$", "Icon_Shop")
	HUDController.Buttons.Hint = sideButton(buttons, "HINT", UI.Colors.Cyan, 3, "?", "Icon_Hint")
	HUDController.Buttons.Settings = sideButton(buttons, "SETTINGS", UI.Colors.PanelLight, 4, "*", "Icon_Settings")
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

	boostsFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(180, 80), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, touch and 270 or 240) }, matchFrame)
	UI.ListLayout(boostsFrame, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)
	teamFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(210, 120), Position = UDim2.fromOffset(12, 134) }, matchFrame)
	UI.ListLayout(teamFrame, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)

	hotColdFrame = UI.Panel({ Size = UDim2.fromOffset(220, 46), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -122), Visible = false, BackgroundTransparency = 0.15 }, matchFrame)
	hotColdLabel = UI.Label({ Text = "", TextSize = 26, TextColor3 = UI.Colors.Orange }, hotColdFrame)

	-- Touch: one big button above the jump button, clear of the thumbstick.
	mobileActionButton = UI.Button({ Text = "GRAB", Color = UI.Colors.Green, Size = UDim2.fromOffset(112, 112), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -140), TextSize = 28, Corner = 56 }, matchFrame)
	UI.Stroke(mobileActionButton, Color3.new(1, 1, 1), 3, 0.5)
	UI.Glow(mobileActionButton, Color3.new(1, 1, 1), 14, 0.6)
	UI.Pulse(mobileActionButton, 0.04, 4)
	mobileActionButton.Visible = false
	-- Touch: smaller DROP button beside it while holding something.
	mobileDropButton = UI.Button({ Text = "DROP", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(72, 72), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -146, 1, -150), TextSize = 18, Corner = 36 }, matchFrame)
	UI.Stroke(mobileDropButton, Color3.new(1, 1, 1), 2, 0.5)
	mobileDropButton.Visible = false
end

local function refreshLobby()
	objectsLabel.Text = string.format("%d / %d", attr("ObjectsFound", 0), GameConfig.TotalObjects)
	finderLabel.Text = string.format("Finder Wins: %d", attr("FinderWins", 0))
	local cpRoom, cpPercent = attr("CheckpointRoomId", 0), attr("CheckpointPercent", 0)
	resumeFrame.Visible = cpRoom > 0 and cpPercent > 0
	if resumeFrame.Visible then
		resumeLabel.Text = string.format("RESUME ROOM %s - %d%% CHECKPOINT", FormatUtil.RoomNumber(cpRoom), math.floor(cpPercent * 100))
	end
end

local function refreshMatchStatic()
	roomTitleLabel.Text = "ROOM " .. FormatUtil.RoomNumber(matchState:GetAttribute("RoomId") or 1)
	roomTargetLabel.Text = "Find the " .. (matchState:GetAttribute("TargetName") or "")
end

local function refreshProgress()
	local p = matchState:GetAttribute("Progress") or 0
	progressBar.Set(p, true)
	progressLabel.Text = "ROOM CLEANED: " .. FormatUtil.Percent(p)
end

local function refreshCash()
	local cash = attr("RoomCash", 0)
	if cash ~= shownCash then
		local from = shownCash
		shownCash = cash
		UI.CountUp(cashLabel, from, cash, FormatUtil.CashExact, 0.45)
		-- Flash the cash panel's glow when money comes in.
		if cash > from and cashGlow then
			local prop = cashGlow:IsA("UIStroke") and "Transparency" or "ImageTransparency"
			;(cashGlow :: any)[prop] = 0.05
			UI.Tween(cashGlow, { [prop] = 0.9 }, 0.7)
		end
	end
	weightLabel.Text = string.format("MAX WEIGHT: %d", attr("MaxWeight", 2))
end

local function refreshVisibility()
	local inMatch = attr("InMatch", false)
	lobbyFrame.Visible = not inMatch
	matchFrame.Visible = inMatch
	if inMatch then
		refreshMatchStatic()
		refreshProgress()
		refreshCash()
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
	local list = {}
	for name in string.gmatch(matchState:GetAttribute("PlayerNames") or "", "[^,]+") do
		local p = Players:FindFirstChild(name)
		table.insert(list, { Name = name, Moved = p and (p:GetAttribute("ObjectsCleaned") or 0) or 0, Me = p == player })
	end
	table.sort(list, function(a, b)
		return a.Moved > b.Moved
	end)
	if #list <= 1 then
		return
	end
	for i, entry in ipairs(list) do
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.3, LayoutOrder = i }, teamFrame)
		UI.Corner(row, 6)
		UI.Label({ Text = entry.Name, TextSize = 14, Font = UI.FontBody, TextColor3 = entry.Me and UI.Colors.Gold or UI.Colors.Text, Size = UDim2.new(0.62, 0, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		UI.Label({ Text = tostring(entry.Moved), TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.38, -8, 1, 0), Position = UDim2.new(0.62, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
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
	local st = attr("StrengthBoostExpires", 0)
	if st > now then
		table.insert(entries, { Text = "2X STRENGTH  " .. FormatUtil.Time(st - now), Color = UI.Colors.Red })
	end
	local cb = attr("CashBoostExpires", 0)
	if cb > now then
		table.insert(entries, { Text = "2X CASH  " .. FormatUtil.Time(cb - now), Color = UI.Colors.Cash })
	end
	local tm = matchState:GetAttribute("TeamMuscleExpires") or 0
	if tm > now then
		table.insert(entries, { Text = "TEAM MUSCLE  " .. FormatUtil.Time(tm - now), Color = UI.Colors.Purple })
	end
	for i, e in ipairs(entries) do
		local row = UI.Frame({ Size = UDim2.fromOffset(170, 22), BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.2, LayoutOrder = i }, boostsFrame)
		UI.Corner(row, 6)
		UI.Stroke(row, e.Color, 1)
		UI.Label({ Text = e.Text, TextSize = 14, Font = UI.FontBody, TextColor3 = e.Color }, row)
	end
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
	player:GetAttributeChangedSignal("MaxWeight"):Connect(refreshCash)
	player:GetAttributeChangedSignal("HotCold"):Connect(refreshHotCold)
	matchState:GetAttributeChangedSignal("Progress"):Connect(refreshProgress)
	matchState:GetAttributeChangedSignal("RoomId"):Connect(refreshMatchStatic)
	matchState:GetAttributeChangedSignal("TargetName"):Connect(refreshMatchStatic)
	matchState:GetAttributeChangedSignal("PlayerNames"):Connect(refreshTeam)
	local function watch(p: Player)
		p:GetAttributeChangedSignal("ObjectsCleaned"):Connect(refreshTeam)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	refreshVisibility()
end

function HUDController.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		if not matchFrame.Visible then
			return
		end
		-- Streak meter (every frame so the timer bar drains smoothly).
		local now = workspace:GetServerTimeNow()
		local streak, expires = attr("Streak", 0), attr("StreakExpires", 0)
		local streakOn = streak >= 2 and expires > now
		streakFrame.Visible = streakOn
		if streakOn then
			streakLabel.Text = string.format("STREAK x%d  +%d%%", streak, math.floor((math.min(1 + (streak - 1) * 0.1, 1.5) - 1) * 100 + 0.5))
			streakBar.Set((expires - now) / 3)
		end
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local start, finish = matchState:GetAttribute("StartTime") or 0, matchState:GetAttribute("EndTime") or 0
		timerLabel.Text = start > 0 and FormatUtil.Time((finish > 0 and finish or workspace:GetServerTimeNow()) - start) or "00:00"
		refreshBoosts()
	end)
	task.delay(1, refreshTeam)
end

function HUDController.GetMobileActionButton(): TextButton
	return mobileActionButton
end

function HUDController.GetMobileDropButton(): TextButton
	return mobileDropButton
end

-- "GRAB", "THROW" or nil (hidden). Touch devices only. DROP shows alongside THROW.
function HUDController.SetMobileAction(text: string?)
	if not touch then
		return
	end
	mobileDropButton.Visible = text == "THROW"
	mobileActionButton.Visible = text ~= nil
	if text and mobileActionButton.Text ~= text then
		mobileActionButton.Text = text
		mobileActionButton.BackgroundColor3 = text == "THROW" and UI.Colors.Orange or UI.Colors.Green
	end
end

function HUDController.PulseCash()
	UI.Tween(cashLabel, { TextSize = 36 }, 0.08).Completed:Once(function()
		UI.Tween(cashLabel, { TextSize = 30 }, 0.2)
	end)
end

-- Screen-space centre of the cash label (for coin fly-to effects), in scaled GUI space.
function HUDController.GetCashLabelPosition(): UDim2
	local absPos, absSize = cashLabel.AbsolutePosition, cashLabel.AbsoluteSize
	return UDim2.fromOffset((absPos.X + 20) / UI.Scale, (absPos.Y + absSize.Y / 2) / UI.Scale)
end

function HUDController.GetMatchFrame(): Frame
	return matchFrame
end

function HUDController.GetLobbyFrame(): Frame
	return lobbyFrame
end

return HUDController
