--[[
	Lobby HUD and Match HUD. Reads replicated player attributes and MatchState attributes.
	Lobby: the collection counter (top), square studded menu tiles (right), the resume card.
	Match: Cash + max weight + deposit streak (top left), room / target / ROOM CLEANED % (top
	centre), UPGRADES / SHOP / HINT / SETTINGS tiles (right), boosts, team, hot/cold, and on
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
local sideStack: Frame? = nil
local cashLabel: TextLabel
local cashGlow: Instance
local shownCash = 0
local weightLabel: TextLabel
local progressBar
local progressLabel: TextLabel
local objectsLabel: TextLabel
local finderLabel: TextLabel
local counterGroup: Frame
local resumeFrame: Frame
local resumeLabel: TextLabel
local roomTitleLabel: TextLabel
local roomTargetLabel: TextLabel
local hotColdPulseThread: thread? = nil

HUDController.Buttons = {}

local touch = UI.IsTouch()
local TILE = touch and 74 or 66

local function attr(name: string, default: any)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

-- A square studded menu tile with a big icon and its name underneath (the pack's side menu).
local function menuTile(parent: Instance, text: string, color: Color3, order: number, glyph: string, iconKey: string): TextButton
	local cell = UI.Frame({ Name = text .. "Cell", BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local b = UI.Button({ Name = text, Text = "", Color = color, Size = UDim2.fromOffset(TILE, TILE), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Corner = 14 }, cell)
	local icon = UI.Icon(b, iconKey, glyph, { TextSize = 26 })
	icon.Size = UDim2.fromScale(0.7, 0.62)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	local name = UI.Label({ Text = text, TextScaled = true, TextWrapped = false, Size = UDim2.new(1, 2, 0, 15), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0) }, cell)
	UI.New("UITextSizeConstraint", { MaxTextSize = 13 }, name)
	UI.Shine(b, 5 + order * 0.9)
	return b
end

local function tileGrid(parent: Instance, rows: number, props: { [string]: any }): Frame
	local p = { BackgroundTransparency = 1, Size = UDim2.fromOffset(2 * (TILE + 10) + 6, rows * (TILE + 24) + (rows - 1) * 6) }
	for k, v in pairs(props) do
		p[k] = v
	end
	local frame = UI.Frame(p, parent)
	local grid = UI.GridLayout(frame, UDim2.fromOffset(TILE + 10, TILE + 24), 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	return frame
end

local function buildLobbyHUD()
	lobbyFrame = UI.Frame({ Name = "LobbyHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)

	-- The collection counter: the one number that matters, in gold. Grouped so a panel that
	-- covers the top of the screen (party setup) can tuck it away.
	counterGroup = UI.Frame({ Name = "Counter", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, lobbyFrame)
	local top = UI.Panel({ Size = UDim2.fromOffset(300, 78), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0.08 }, counterGroup)
	UI.Stroke(top, UI.Colors.Gold, 2.5)
	UI.Glow(top, UI.Colors.Gold, 16, 0.8)
	UI.Label({ Text = "OBJECTS FOUND", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 7) }, top)
	objectsLabel = UI.Label({ Text = "0 / 1000", TextSize = 38, TextWrapped = false, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 26) }, top)
	UI.TextGradient(objectsLabel, UI.Colors.Gold)
	local finderPill = UI.Surface3D({ Size = UDim2.fromOffset(196, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 94) }, counterGroup, UI.Colors.Gold, 15, 0.14)
	-- The trophy is the Collection icon (an emoji inside outlined text renders as a smudge).
	local trophy = UI.Icon(finderPill, "Icon_Collection", "★", { TextSize = 16 })
	trophy.Size = UDim2.fromOffset(22, 22)
	trophy.AnchorPoint = Vector2.new(0, 0.5)
	trophy.Position = UDim2.new(0, 10, 0.43, 0)
	finderLabel = UI.Label({ Text = "Finder Wins: 0", TextSize = 15, TextWrapped = false, Size = UDim2.new(1, -44, 0.86, 0), Position = UDim2.fromOffset(34, 0) }, finderPill)

	local buttons = tileGrid(lobbyFrame, 3, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.46, 0) })
	HUDController.Buttons.Collection = menuTile(buttons, "COLLECTION", UI.Colors.Gold, 1, "1K", "Icon_Collection")
	HUDController.Buttons.Challenges = menuTile(buttons, "CHALLENGES", UI.Colors.Cyan, 2, "!", "Icon_Challenges")
	HUDController.Buttons.LobbyShop = menuTile(buttons, "SHOP", UI.Colors.Purple, 3, "$", "Icon_Shop")
	HUDController.Buttons.Invite = menuTile(buttons, "INVITE", UI.Colors.Green, 4, "+", "Icon_Invite")
	HUDController.Buttons.LobbySettings = menuTile(buttons, "SETTINGS", UI.Colors.Locked, 5, "*", "Icon_Settings")
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

	resumeFrame = UI.Panel({ Size = UDim2.fromOffset(400, 84), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Visible = false, BackgroundTransparency = 0.06 }, lobbyFrame)
	UI.Stroke(resumeFrame, UI.Colors.Cyan, 2.5)
	resumeLabel = UI.Label({ Text = "", TextSize = 18, TextWrapped = false, Size = UDim2.new(1, -150, 0, 40), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left }, resumeFrame)
	UI.TextGradient(resumeLabel, UI.Colors.Cyan)
	UI.Label({ Text = "Step into a circle to resume", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -150, 0, 26), Position = UDim2.fromOffset(12, 48), TextXAlignment = Enum.TextXAlignment.Left }, resumeFrame)
	local fresh = UI.Button({ Text = "START FRESH", Color = UI.Colors.Red, Size = UDim2.fromOffset(128, 46), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), TextSize = 14 }, resumeFrame)
	fresh.Activated:Connect(function()
		Remotes.Event("DiscardCheckpoint"):FireServer()
	end)
end

local function buildMatchHUD()
	matchFrame = UI.Frame({ Name = "MatchHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)

	-- Room, what to find, how much is cleaned, time.
	local top = UI.Panel({ Size = UDim2.fromOffset(440, 104), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0.08 }, matchFrame)
	UI.Stroke(top, UI.Colors.Gold, 2.5)
	UI.Glow(top, UI.Colors.Gold, 18, 0.8)
	roomTitleLabel = UI.Label({ Text = "ROOM #001", TextSize = 20, TextWrapped = false, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 6) }, top)
	roomTargetLabel = UI.Label({ Text = "Find the Golden Key", TextSize = 19, TextWrapped = false, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 30) }, top)
	UI.TextGradient(roomTargetLabel, UI.Colors.Gold)
	progressBar = UI.ProgressBar(top, UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 56), UI.Colors.Green)
	progressLabel = UI.Label({ Text = "ROOM CLEANED: 0%", TextSize = 14, TextWrapped = false, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 }, progressBar.Frame)
	timerLabel = UI.Label({ Text = "00:00", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 83) }, top)

	-- Cash (money is lime everywhere) and how heavy you can lift.
	local left = UI.Panel({ Size = UDim2.fromOffset(236, 84), Position = UDim2.fromOffset(12, 10), BackgroundTransparency = 0.08 }, matchFrame)
	cashGlow = UI.Glow(left, UI.Colors.Cash, 16, 0.9)
	local cashBadge = UI.Surface3D({ Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(10, 8) }, left, UI.Colors.Green, 20, 0.12)
	local cashIcon = UI.Icon(cashBadge, "Icon_Cash", "$", { TextSize = 22 })
	cashIcon.Size = UDim2.fromScale(0.7, 0.62)
	cashIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	cashIcon.Position = UDim2.fromScale(0.5, 0.45)
	cashLabel = UI.Label({ Text = "$0", TextSize = 32, TextWrapped = false, Size = UDim2.new(1, -64, 0, 42), Position = UDim2.fromOffset(58, 7), TextXAlignment = Enum.TextXAlignment.Left }, left)
	UI.TextGradient(cashLabel, UI.Colors.Cash)
	local weightIcon = UI.Frame({ Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(14, 56), BackgroundTransparency = 1 }, left)
	UI.Icon(weightIcon, "Icon_Weight", "", {})
	weightLabel = UI.Label({ Text = "MAX WEIGHT: 2", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -44, 0, 22), Position = UDim2.fromOffset(UI.Asset("Icon_Weight") and 40 or 14, 55), TextXAlignment = Enum.TextXAlignment.Left }, left)

	-- Touch: the right side belongs to the GRAB button, so the streak, boosts, challenge tracker
	-- and team stack down the left under the cash panel (empty ones take no room).
	if touch then
		sideStack = UI.Frame({ Name = "SideStack", BackgroundTransparency = 1, Size = UDim2.new(0, 250, 1, -112), Position = UDim2.fromOffset(12, 100) }, matchFrame)
		UI.ListLayout(sideStack :: Frame, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	end

	-- Deposit streak: shows while deposits keep coming within the streak window.
	streakFrame = UI.Panel({ Size = UDim2.fromOffset(236, 32), Position = UDim2.fromOffset(12, 100), BackgroundTransparency = 0.08, Visible = false, LayoutOrder = 1 }, sideStack or matchFrame)
	UI.Stroke(streakFrame, UI.Colors.Orange, 2.5)
	local streakIcon = UI.Frame({ Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(6, 5), BackgroundTransparency = 1 }, streakFrame)
	UI.Icon(streakIcon, "Icon_Streak", "", {})
	streakLabel = UI.Label({ Text = "STREAK x2", TextSize = 15, TextWrapped = false, Size = UDim2.new(0, 130, 1, 0), Position = UDim2.fromOffset(32, 0), TextXAlignment = Enum.TextXAlignment.Left }, streakFrame)
	UI.TextGradient(streakLabel, UI.Colors.Orange)
	streakBar = UI.ProgressBar(streakFrame, UDim2.new(0, 60, 0, 12), UDim2.new(1, -70, 0.5, -6), UI.Colors.Orange)
	UI.Glow(streakFrame, UI.Colors.Orange, 14, 0.5)
	UI.Pulse(streakFrame, 0.035, 7)

	local buttons = tileGrid(matchFrame, 2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10) })
	HUDController.Buttons.Upgrades = menuTile(buttons, "UPGRADES", UI.Colors.Green, 1, "UP", "Icon_Upgrades")
	HUDController.Buttons.Shop = menuTile(buttons, "SHOP", UI.Colors.Purple, 2, "$", "Icon_Shop")
	HUDController.Buttons.Hint = menuTile(buttons, "HINT", UI.Colors.Cyan, 3, "?", "Icon_Hint")
	HUDController.Buttons.Settings = menuTile(buttons, "SETTINGS", UI.Colors.Locked, 4, "*", "Icon_Settings")
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

	local gridHeight = 2 * (TILE + 24) + 6
	if sideStack then
		boostsFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, sideStack)
		UI.ListLayout(boostsFrame, Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Left)
		teamFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(236, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 }, sideStack)
	else
		boostsFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(190, 84), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 18 + gridHeight) }, matchFrame)
		UI.ListLayout(boostsFrame, Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Right)
		teamFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(236, 120), Position = UDim2.fromOffset(12, 140) }, matchFrame)
	end
	UI.ListLayout(teamFrame, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)

	hotColdFrame = UI.Panel({ Size = UDim2.fromOffset(230, 50), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -122), Visible = false, BackgroundTransparency = 0.1 }, matchFrame)
	hotColdLabel = UI.Label({ Text = "", TextSize = 28, TextWrapped = false }, hotColdFrame)

	-- Touch: one big button above the jump button, clear of the thumbstick.
	mobileActionButton = UI.Button({ Text = "GRAB", Color = UI.Colors.Green, Size = UDim2.fromOffset(112, 112), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -140), TextSize = 28, Corner = 56 }, matchFrame)
	UI.Glow(mobileActionButton, Color3.new(1, 1, 1), 14, 0.6)
	UI.Pulse(mobileActionButton, 0.04, 4)
	mobileActionButton.Visible = false
	-- Touch: smaller DROP button beside it while holding something.
	mobileDropButton = UI.Button({ Text = "DROP", Color = UI.Colors.Locked, Size = UDim2.fromOffset(74, 74), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -146, 1, -150), TextSize = 18, Corner = 37 }, matchFrame)
	mobileDropButton.Visible = false
end

local function refreshLobby()
	objectsLabel.Text = string.format("%d / %d", attr("ObjectsFound", 0), GameConfig.TotalObjects)
	finderLabel.Text = string.format("Finder Wins: %d", attr("FinderWins", 0))
	local cpRoom, cpPercent = attr("CheckpointRoomId", 0), attr("CheckpointPercent", 0)
	resumeFrame.Visible = cpRoom > 0 and cpPercent > 0
	if resumeFrame.Visible then
		resumeLabel.Text = string.format("RESUME ROOM %s - %d%%", FormatUtil.RoomNumber(cpRoom), math.floor(cpPercent * 100))
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
		local row = UI.Panel({ Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 0.2, LayoutOrder = i }, teamFrame)
		UI.Stroke(row, entry.Me and UI.Colors.Gold or UI.Colors.Stroke, entry.Me and 2 or 1.5)
		UI.Label({ Text = entry.Name, TextSize = 14, Font = UI.FontBody, TextColor3 = entry.Me and UI.Colors.Gold or UI.Colors.Text, Size = UDim2.new(0.62, 0, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		UI.Label({ Text = tostring(entry.Moved), TextSize = 14, TextWrapped = false, Size = UDim2.new(0.38, -8, 1, 0), Position = UDim2.new(0.62, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
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
		local row = UI.Panel({ Size = UDim2.fromOffset(186, 24), BackgroundTransparency = 0.15, LayoutOrder = i }, boostsFrame)
		UI.Stroke(row, e.Color, 2)
		local label = UI.Label({ Text = e.Text, TextSize = 13, TextWrapped = false }, row)
		UI.TextGradient(label, e.Color)
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
	UI.TextGradient(hotColdLabel, style.Color)
	UI.Stroke(hotColdFrame, style.Color, 2.5)
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
		mobileActionButton.BackgroundColor3 = (text == "THROW" and UI.Colors.Orange) or (text == "HEAVY" and UI.Colors.Red) or UI.Colors.Green
	end
end

function HUDController.PulseCash()
	UI.Tween(cashLabel, { TextSize = 38 }, 0.08).Completed:Once(function()
		UI.Tween(cashLabel, { TextSize = 32 }, 0.2)
	end)
end

-- Where the cash label sits (for coin fly-to effects), as an offset in the full-screen layers.
function HUDController.GetCashLabelPosition(): UDim2
	local absPos, absSize = cashLabel.AbsolutePosition, cashLabel.AbsoluteSize
	return UI.FromAbsolute(Vector2.new(absPos.X + 20, absPos.Y + absSize.Y / 2))
end

function HUDController.GetMatchFrame(): Frame
	return matchFrame
end

-- Touch only: the left-side column for match info (nil on desktop). See buildMatchHUD.
function HUDController.GetSideStack(): Frame?
	return sideStack
end

function HUDController.GetLobbyFrame(): Frame
	return lobbyFrame
end

-- Party setup covers the top of the screen; the lobby counter steps aside meanwhile.
function HUDController.SetCounterVisible(visible: boolean)
	if counterGroup then
		counterGroup.Visible = visible
	end
end

return HUDController
