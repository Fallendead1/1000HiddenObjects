--[[
	Daily login rewards (ProgressionConfig.LoginRewards): a 7-day cycle, and missing a day starts
	it over. The menu opens by itself in the lobby when today's reward is waiting (the DAILY tile
	shows a red dot); CLAIM asks the server, which grants it. Hints and boosts wait for your next
	room so they never tick away in the lobby.
	Server attributes: LoginDay (1-7), LoginClaimable, LoginStreak, LoginResetAt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConfig = require(ReplicatedStorage.Shared.Config.ProgressionConfig)
local RewardInfo = require(ReplicatedStorage.Shared.Config.RewardInfo)
local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local DailyRewardController = {}


local menu
local cards: { { Card: Frame, State: TextLabel, Pulsing: boolean } } = {}
local claimButton: TextButton
local streakLabel: TextLabel
local footerLabel: TextLabel
local freezeLabel: TextLabel
local busy = false
local autoShown = false

local function timeLeft(): string
	local seconds = math.max(0, (player:GetAttribute("LoginResetAt") or 0) - workspace:GetServerTimeNow())
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function refresh()
	if not menu then
		return
	end
	local today = player:GetAttribute("LoginDay") or 1
	local claimable = player:GetAttribute("LoginClaimable") == true
	local streak = player:GetAttribute("LoginStreak") or 0
	if claimable then
		streakLabel.Text = streak > 0 and string.format("%d-DAY STREAK  ·  CLAIM DAY %d!", streak, today) or "YOUR DAILY REWARD IS READY!"
	else
		streakLabel.Text = string.format("LOGIN STREAK: %d DAY%s", streak, streak == 1 and "" or "S")
	end
	-- The weekly streak freeze: one missed day a week doesn't break the streak.
	if claimable and player:GetAttribute("LoginFrozen") == true then
		freezeLabel.Text = "You missed a day - your weekly STREAK FREEZE keeps your streak!"
		freezeLabel.TextColor3 = UI.Colors.Cyan
	elseif player:GetAttribute("LoginFreezeReady") == true then
		freezeLabel.Text = "STREAK FREEZE READY: miss one day this week and keep your streak."
		freezeLabel.TextColor3 = UI.Colors.TextDim
	else
		freezeLabel.Text = "Streak freeze used this week - a new one comes on Monday."
		freezeLabel.TextColor3 = UI.Colors.TextDim
	end
	for day, c in ipairs(cards) do
		local done = day < today or (day == today and not claimable)
		local isToday = day == today and claimable
		UI.Stroke(c.Card, isToday and UI.Colors.Gold or (done and UI.Colors.Green or Color3.new(0, 0, 0)), isToday and 3.5 or 2.5)
		c.Card.BackgroundTransparency = (done or isToday) and 0.05 or 0.45
		c.State.Text = done and "CLAIMED" or (isToday and "TODAY" or "")
		c.State.TextColor3 = done and UI.Colors.Green or UI.Colors.Gold
		if isToday and not c.Pulsing then
			c.Pulsing = true
			UI.Pulse(c.Card, 0.04, 2.2)
		elseif not isToday and c.Pulsing then
			c.Pulsing = false
			UI.StopPulse(c.Card)
		end
	end
	if claimable and not busy then
		UI.SetButtonEnabled(claimButton, true)
		claimButton.Text = "CLAIM DAY " .. today
		local reward = ProgressionConfig.LoginRewards[today]
		footerLabel.Text = (reward and (reward.Hint or reward.Boost)) and "Hints and boosts start in your next room." or "Come back tomorrow for an even better reward!"
	elseif not claimable then
		UI.SetButtonEnabled(claimButton, false, "CLAIMED")
		footerLabel.Text = "Next reward in " .. timeLeft()
	end
end

local function claim()
	if busy or player:GetAttribute("LoginClaimable") ~= true then
		return
	end
	busy = true
	UI.SetButtonEnabled(claimButton, false, "CLAIMING...")
	Remotes.Event("ClaimDailyReward"):FireServer()
	task.delay(4, function()
		if busy then
			busy = false
			refresh()
		end
	end)
end

function DailyRewardController.Init()
	menu = UI.Menu("Daily", "DAILY REWARDS", UDim2.fromOffset(720, 420), UI.Colors.Gold)
	streakLabel = UI.Label({ Text = "", TextSize = 22, TextWrapped = false, Size = UDim2.new(1, 0, 0, 28) }, menu.Content)
	UI.TextGradient(streakLabel, UI.Colors.Gold)
	freezeLabel = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 30) }, menu.Content)

	local row = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), Position = UDim2.fromOffset(0, 58) }, menu.Content)
	UI.ListLayout(row, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	for day, reward in ipairs(ProgressionConfig.LoginRewards) do
		local card = UI.Panel({ Size = UDim2.new(1 / 7, -8, 1, 0), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = day }, row)
		UI.Label({ Text = "DAY " .. day, TextSize = 14, TextWrapped = false, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 6) }, card)
		-- The icon is what the day gives (XP, a hint, a boost), so it matches its words. Day 7 is gold.
		local inside = RewardInfo.Of(reward)
		local badgeColor = if day == #ProgressionConfig.LoginRewards then UI.Colors.Gold else (UI.Colors[inside.Color] or UI.Colors.Gold)
		local badge = UI.Surface3D({ Size = UDim2.fromOffset(50, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30) }, card, badgeColor, 14, 0.12)
		local icon = UI.Icon(badge, inside.Icon, inside.Glyph, { TextSize = 18 })
		icon.Size = UDim2.fromScale(0.74, 0.66)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.45)
		UI.Label({ Text = reward.Text, TextSize = 12, Font = UI.FontBody, Size = UDim2.new(1, -8, 0, 46), Position = UDim2.fromOffset(4, 86), TextYAlignment = Enum.TextYAlignment.Top }, card)
		local state = UI.Label({ Text = "", TextSize = 12, TextWrapped = false, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -22) }, card)
		cards[day] = { Card = card, State = state, Pulsing = false }
	end

	claimButton = UI.Button({ Text = "CLAIM", Color = UI.Colors.Green, Size = UDim2.fromOffset(260, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 244), TextSize = 26, Shine = 2.5 }, menu.Content)
	footerLabel = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 308) }, menu.Content)
	claimButton.Activated:Connect(claim)
	menu.Primary = claimButton -- controllers: A claims straight away
	menu.OnOpen(refresh)

	for _, name in ipairs({ "LoginDay", "LoginClaimable", "LoginStreak", "LoginFrozen", "LoginFreezeReady" }) do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if name ~= "DailyClaimed" or type(payload) ~= "table" then
			return
		end
		busy = false
		local c = cards[payload.Day or 0]
		if c then
			UI.Flash(c.Card, UI.Colors.Gold, 0.8)
		end
		Controllers.AudioController.Play("UpgradePurchase")
		local reward = ProgressionConfig.LoginRewards[payload.Day or 0]
		local info = RewardInfo.Of(reward)
		if payload.Later then
			info.Explain ..= " It starts in your next room."
		end
		menu.Close()
		Controllers.GiftController.Reveal(string.format("DAY %d REWARD!", payload.Day or 0), payload.Reward or "", UI.Colors[info.Color] or UI.Colors.Gold, nil, info)
		refresh()
	end)
end

function DailyRewardController.Start()
	-- Opens by itself once per session, in the lobby, when today's reward is waiting. Not on a
	-- brand-new player's first visit: the tutorial's welcome goes first (the red dot still shows).
	local function tryAutoOpen()
		if autoShown or player:GetAttribute("LoginClaimable") ~= true or player:GetAttribute("InMatch") then
			return
		end
		if player:GetAttribute("TutorialCompleted") ~= true then
			return
		end
		if (player:GetAttribute("QueueId") or "") ~= "" or UI.GetOpenMenu() then
			return
		end
		autoShown = true
		menu.Open()
	end
	task.delay(3, tryAutoOpen)
	player:GetAttributeChangedSignal("LoginClaimable"):Connect(function()
		task.delay(1, tryAutoOpen)
	end)
end

function DailyRewardController.Open()
	menu.Open()
end

return DailyRewardController
