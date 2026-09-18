--[[
	Lobby HUD and Match HUD. Reads replicated player attributes and MatchState attributes.
	Lobby: square studded menu tiles (right), the saved Cash wallet (left, under the level badge),
	and PLAY NOW with the checkpoint line (bottom centre). Objects found and Finder Wins are on
	each player's overhead tag instead (ProgressionService.RefreshTag).
	Match: Cash + max weight + deposit streak (top left), room / target / ROOM CLEANED % (top
	centre), UPGRADES / SHOP / HINT / SETTINGS tiles (right), boosts, team, hot/cold, and on
	touch a big GRAB / THROW button plus a DROP button driven by GrabController.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local FormatUtil = require(Shared.Utility.FormatUtil)
local RoomRegistry = require(Shared.Config.RoomConfigs)
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
local rightStack: Frame? = nil -- desktop: boosts, then the challenge tracker, under the tiles
local cashLabel: TextLabel
local cashGlow: Instance
local shownCash = 0
local weightLabel: TextLabel
local progressBar
local progressLabel: TextLabel
local resumeFrame: Frame
local resumeLabel: TextLabel
local roomTitleLabel: TextLabel
local roomTargetLabel: TextLabel
local hotColdPulseThread: thread? = nil
local matchTop: Frame
local topY = 10 -- where the top panels sit (HUD-layer units); see placeTop
local walletLabel: TextLabel
local walletPanel: Frame
local shownWallet = 0
local walletHoldUntil = 0
local playFrame: Frame
local playButton: TextButton
local playBusyUntil = 0

HUDController.Buttons = {}
local tileLabels: { [TextButton]: TextLabel } = {}

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
	tileLabels[b] = UI.Label({ Text = text, FitText = 13, Size = UDim2.new(1, 2, 0, 15), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0) }, cell)
	UI.Shine(b, 5 + order * 0.9)
	return b
end

-- A pulsing red dot on a tile while `isOn` says so (re-checked when any of `attributes` change).
local function tileDot(button: TextButton, attributes: { string }, isOn: () -> boolean)
	local dot = UI.Frame({ Name = "Dot", Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), BackgroundColor3 = UI.Colors.Red, Visible = false, ZIndex = 20 }, button)
	UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
	UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, dot)
	UI.Pulse(dot, 0.15, 1.6)
	local function refresh()
		dot.Visible = isOn()
	end
	for _, name in ipairs(attributes) do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
	return refresh
end

-- Controllers: a D-pad direction opens a tile's menu (the tile wears that button's badge).
local padShortcuts: { { Key: Enum.KeyCode, Button: TextButton, Frame: Frame, Open: () -> () } } = {}
local function padShortcut(button: TextButton, key: Enum.KeyCode, frame: Frame, open: () -> ())
	UI.PadBadge(button, key)
	table.insert(padShortcuts, { Key = key, Button = button, Frame = frame, Open = open })
end

local function tileGrid(parent: Instance, columns: number, rows: number, props: { [string]: any }): Frame
	local p = { BackgroundTransparency = 1, Size = UDim2.fromOffset(columns * (TILE + 10) + (columns - 1) * 6, rows * (TILE + 24) + (rows - 1) * 6) }
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

	-- Objects found and Finder Wins ride on every player's overhead tag in the lobby
	-- (ProgressionService.RefreshTag), where everyone can see them.

	-- Phones: hung from the top so the bottom row clears the jump button.
	local buttons = tileGrid(lobbyFrame, 3, 3, touch and { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8) } or { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.46, 0) })
	HUDController.Buttons.Collection = menuTile(buttons, "COLLECTION", UI.Colors.Gold, 1, "1K", "Icon_Collection")
	HUDController.Buttons.Challenges = menuTile(buttons, "CHALLENGES", UI.Colors.Cyan, 2, "!", "Icon_Challenges")
	HUDController.Buttons.LobbyShop = menuTile(buttons, "SHOP", UI.Colors.Purple, 3, "$", "Icon_Shop")
	HUDController.Buttons.Invite = menuTile(buttons, "INVITE", UI.Colors.Green, 4, "+", "Icon_Invite")
	HUDController.Buttons.LobbySettings = menuTile(buttons, "SETTINGS", UI.Colors.Locked, 5, "*", "Icon_Settings")
	HUDController.Buttons.Daily = menuTile(buttons, "DAILY", UI.Colors.Orange, 6, "7", "Icon_Streak")
	HUDController.Buttons.Spin = menuTile(buttons, "SPIN", UI.Colors.Pink, 7, "@", "Icon_Spin")
	HUDController.Buttons.LobbyGifts = menuTile(buttons, "GIFTS", UI.Colors.Gold, 8, "G", "Icon_Gift")
	HUDController.Buttons.Pets = menuTile(buttons, "PETS", UI.Colors.Pink, 9, "P", "Icon_Pets")
	tileDot(HUDController.Buttons.Pets, { "PetWelcomed" }, function()
		return player:GetAttribute("PetWelcomed") == false
	end)
	HUDController.Buttons.Pets.Activated:Connect(function()
		Controllers.PetShopController.Open()
	end)
	-- Red dots: today's login reward, today's free spin, and a playtime gift ready to open.
	tileDot(HUDController.Buttons.Daily, { "LoginClaimable" }, function()
		return player:GetAttribute("LoginClaimable") == true
	end)
	tileDot(HUDController.Buttons.Spin, { "SpinReady" }, function()
		return player:GetAttribute("SpinReady") == true
	end)
	HUDController.Buttons.Spin.Activated:Connect(function()
		Controllers.SpinController.Open()
	end)
	HUDController.Buttons.LobbyGifts.Activated:Connect(function()
		Controllers.GiftController.Open()
	end)
	HUDController.Buttons.Daily.Activated:Connect(function()
		Controllers.DailyRewardController.Open()
	end)
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
	padShortcut(HUDController.Buttons.Challenges, Enum.KeyCode.DPadLeft, lobbyFrame, function()
		Controllers.ProgressionController.OpenChallenges()
	end)
	padShortcut(HUDController.Buttons.LobbyShop, Enum.KeyCode.ButtonY, lobbyFrame, function()
		Controllers.ShopController.Open()
	end)
	padShortcut(HUDController.Buttons.Daily, Enum.KeyCode.DPadRight, lobbyFrame, function()
		Controllers.DailyRewardController.Open()
	end)

	-- The saved Cash wallet, under the level badge (ProgressionController: 12, 12, 254 x 50).
	walletPanel = UI.Panel({ Name = "Wallet", Size = UDim2.fromOffset(200, 40), Position = UDim2.fromOffset(12, 68), BackgroundTransparency = 0.08 }, lobbyFrame)
	UI.Stroke(walletPanel, UI.Colors.Cash, 2.5)
	UI.Glow(walletPanel, UI.Colors.Cash, 12, 0.85)
	local walletBadge = UI.Surface3D({ Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 4) }, walletPanel, UI.Colors.Green, 16, 0.12)
	local walletIcon = UI.Icon(walletBadge, "Icon_Cash", "$", { TextSize = 18 })
	walletIcon.Size = UDim2.fromScale(0.7, 0.62)
	walletIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	walletIcon.Position = UDim2.fromScale(0.5, 0.45)
	walletLabel = UI.Label({ Text = "$0", TextSize = 24, TextWrapped = false, Size = UDim2.new(1, -48, 1, -4), Position = UDim2.fromOffset(42, 1), TextXAlignment = Enum.TextXAlignment.Left }, walletPanel)
	UI.TextGradient(walletLabel, UI.Colors.Cash)
	shownWallet = attr("Wallet", 0)
	walletLabel.Text = FormatUtil.CashExact(shownWallet)

	-- PLAY NOW: a solo run of your next room in one tap (circles are for parties). The checkpoint
	-- line above it says when that run resumes.
	playFrame = UI.Frame({ Name = "PlayNow", BackgroundTransparency = 1, Size = UDim2.fromOffset(400, 140), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14) }, lobbyFrame)
	playButton = UI.Button({ Name = "PlayNowButton", Text = "PLAY NOW", RichText = true, Color = UI.Colors.Green, Size = UDim2.fromOffset(300, 78), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), TextSize = 34, Shine = 2.2, Corner = 18 }, playFrame)
	UI.Glow(playButton, UI.Colors.Green, 18, 0.55)
	UI.PadBadge(playButton, Enum.KeyCode.ButtonX)
	playButton.Activated:Connect(HUDController.PlayNow)

	resumeFrame = UI.Panel({ Size = UDim2.fromOffset(380, 44), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Visible = false, BackgroundTransparency = 0.06 }, playFrame)
	UI.Stroke(resumeFrame, UI.Colors.Cyan, 2.5)
	resumeLabel = UI.Label({ Text = "", FitText = 16, TextWrapped = false, Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(12, 0), TextXAlignment = Enum.TextXAlignment.Left }, resumeFrame)
	UI.TextGradient(resumeLabel, UI.Colors.Cyan)
	local fresh = UI.Button({ Text = "START FRESH", Color = UI.Colors.Red, Size = UDim2.fromOffset(118, 34), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -5, 0.5, 0), FitText = 13 }, resumeFrame)
	fresh.Activated:Connect(function()
		Remotes.Event("DiscardCheckpoint"):FireServer()
	end)
end

-- The room PLAY NOW would start (the server decides: QueueService.QuickPlayRoom).
local function playRoom(): (number, number)
	local cpRoom, cpPercent = attr("CheckpointRoomId", 0), attr("CheckpointPercent", 0)
	if cpRoom > 0 and cpPercent > 0 then
		return cpRoom, cpPercent
	end
	return math.min(attr("HighestRoomCompleted", 0) + 1, RoomRegistry.GetHighestAvailable()), 0
end

local function refreshPlay()
	if not playButton then
		return
	end
	local queued = attr("QueueId", "") ~= ""
	playFrame.Visible = not queued and not attr("Teleporting", false)
	local room, percent = playRoom()
	local sub = percent > 0 and string.format("RESUME ROOM %s · %d%%", FormatUtil.RoomNumber(room), math.floor(percent * 100)) or string.format("ROOM %s · SOLO", FormatUtil.RoomNumber(room))
	if os.clock() < playBusyUntil then
		playButton.Text = "STARTING..."
	else
		playButton.Text = string.format('PLAY NOW<br/><font size="15">%s</font>', sub)
	end
end

function HUDController.PlayNow()
	if os.clock() < playBusyUntil or attr("InMatch", false) or attr("QueueId", "") ~= "" then
		return
	end
	playBusyUntil = os.clock() + 4
	refreshPlay()
	Remotes.Event("QuickPlay"):FireServer()
	task.delay(4.1, refreshPlay)
end

local function refreshWallet()
	local wallet = attr("Wallet", 0)
	if wallet == shownWallet or os.clock() < walletHoldUntil then
		return
	end
	local from = shownWallet
	shownWallet = wallet
	UI.CountUp(walletLabel, from, wallet, FormatUtil.CashExact, 0.6)
	if wallet > from then
		UI.PopIn(walletPanel, 0.9, 0.25)
	end
end

-- The spin wheel reveals its own prize: the wallet waits until it has.
function HUDController.HoldWallet(seconds: number)
	walletHoldUntil = os.clock() + seconds
	task.delay(seconds + 0.05, refreshWallet)
end

function HUDController.AddTileDot(button: TextButton, attributes: { string }, isOn: () -> boolean)
	return tileDot(button, attributes, isOn)
end

function HUDController.SetTileText(button: TextButton, text: string)
	local label = tileLabels[button]
	if label and label.Text ~= text then
		label.Text = text
	end
end

function HUDController.GetWalletPanel(): Frame
	return walletPanel
end

function HUDController.GetPlayButton(): TextButton
	return playButton
end

local function buildMatchHUD()
	matchFrame = UI.Frame({ Name = "MatchHUD", BackgroundTransparency = 1, Visible = false }, UI.Layers.HUD)

	-- Room, what to find, how much is cleaned, time.
	local top = UI.Panel({ Size = UDim2.fromOffset(440, 104), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0.08 }, matchFrame)
	matchTop = top
	UI.Stroke(top, UI.Colors.Gold, 2.5)
	UI.Glow(top, UI.Colors.Gold, 18, 0.8)
	roomTitleLabel = UI.Label({ Text = "ROOM #001", TextSize = 20, TextWrapped = false, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 6) }, top)
	roomTargetLabel = UI.Label({ Text = "Find the Golden Key", TextSize = 19, TextWrapped = false, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 30) }, top)
	UI.TextGradient(roomTargetLabel, UI.Colors.Gold)
	progressBar = UI.ProgressBar(top, UDim2.new(1, -32, 0, 24), UDim2.fromOffset(16, 56), UI.Colors.Green)
	progressLabel = UI.Label({ Text = "ROOM CLEANED: 0%", TextSize = 14, TextWrapped = false, Size = UDim2.new(1, 0, 1, 0), ZIndex = 3 }, progressBar.Frame)
	timerLabel = UI.Label({ Text = "00:00", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, RichText = true, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 83) }, top)

	-- Cash (money is lime everywhere) and how heavy you can lift. ProgressionController's slim
	-- level strip sits right under it (y 98-122), so the left column below starts at 128.
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
		sideStack = UI.Frame({ Name = "SideStack", BackgroundTransparency = 1, Size = UDim2.new(0, 250, 1, -140), Position = UDim2.fromOffset(12, 128) }, matchFrame)
		UI.ListLayout(sideStack :: Frame, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Left)
	end

	-- Deposit streak: shows while deposits keep coming within the streak window.
	streakFrame = UI.Panel({ Size = UDim2.fromOffset(236, 32), Position = UDim2.fromOffset(12, 128), BackgroundTransparency = 0.08, Visible = false, LayoutOrder = 1 }, sideStack or matchFrame)
	UI.Stroke(streakFrame, UI.Colors.Orange, 2.5)
	local streakIcon = UI.Frame({ Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(6, 5), BackgroundTransparency = 1 }, streakFrame)
	UI.Icon(streakIcon, "Icon_Streak", "", {})
	streakLabel = UI.Label({ Text = "STREAK x2", TextSize = 15, TextWrapped = false, Size = UDim2.new(0, 130, 1, 0), Position = UDim2.fromOffset(32, 0), TextXAlignment = Enum.TextXAlignment.Left }, streakFrame)
	UI.TextGradient(streakLabel, UI.Colors.Orange)
	streakBar = UI.ProgressBar(streakFrame, UDim2.new(0, 60, 0, 12), UDim2.new(1, -70, 0.5, -6), UI.Colors.Orange)
	UI.Glow(streakFrame, UI.Colors.Orange, 14, 0.5)
	UI.Pulse(streakFrame, 0.035, 7)

	local buttons = tileGrid(matchFrame, 3, 2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10) })
	HUDController.Buttons.Upgrades = menuTile(buttons, "UPGRADES", UI.Colors.Green, 1, "UP", "Icon_Upgrades")
	HUDController.Buttons.Shop = menuTile(buttons, "SHOP", UI.Colors.Purple, 2, "$", "Icon_Shop")
	HUDController.Buttons.Hint = menuTile(buttons, "HINT", UI.Colors.Cyan, 3, "?", "Icon_Hint")
	HUDController.Buttons.Settings = menuTile(buttons, "SETTINGS", UI.Colors.Locked, 4, "*", "Icon_Settings")
	HUDController.Buttons.Gifts = menuTile(buttons, "GIFTS", UI.Colors.Gold, 5, "G", "Icon_Gift")
	HUDController.Buttons.Gifts.Activated:Connect(function()
		Controllers.GiftController.Open()
	end)
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
	padShortcut(HUDController.Buttons.Upgrades, Enum.KeyCode.DPadLeft, matchFrame, function()
		Controllers.UpgradeController.Open()
	end)
	padShortcut(HUDController.Buttons.Shop, Enum.KeyCode.ButtonY, matchFrame, function()
		Controllers.ShopController.Open()
	end)
	padShortcut(HUDController.Buttons.Hint, Enum.KeyCode.DPadRight, matchFrame, function()
		Controllers.ShopController.Open("Help")
	end)

	local gridHeight = 2 * (TILE + 24) + 6
	if sideStack then
		boostsFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, sideStack)
		UI.ListLayout(boostsFrame, Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Left)
		teamFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(236, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4 }, sideStack)
	else
		rightStack = UI.Frame({ Name = "RightStack", BackgroundTransparency = 1, Size = UDim2.new(0, 250, 1, -(30 + gridHeight)), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 18 + gridHeight) }, matchFrame)
		UI.ListLayout(rightStack :: Frame, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
		boostsFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, rightStack)
		UI.ListLayout(boostsFrame, Enum.FillDirection.Vertical, 5, Enum.HorizontalAlignment.Right)
		teamFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(236, 120), Position = UDim2.fromOffset(12, 168) }, matchFrame)
	end
	UI.ListLayout(teamFrame, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left)

	hotColdFrame = UI.Panel({ Size = UDim2.fromOffset(230, 50), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -122), Visible = false, BackgroundTransparency = 0.1 }, matchFrame)
	hotColdLabel = UI.Label({ Text = "", TextSize = 28, TextWrapped = false }, hotColdFrame)

	-- Touch: one big button above the jump button, clear of the thumbstick. Its word (GRAB / HEAVY /
	-- THROW) always fits on one line, a size smaller than the button so it reads at a glance.
	mobileActionButton = UI.Button({ Text = "GRAB", Color = UI.Colors.Green, Size = UDim2.fromOffset(112, 112), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -140), FitText = 22, Corner = 56 }, matchFrame)
	UI.Glow(mobileActionButton, Color3.new(1, 1, 1), 14, 0.6)
	UI.Pulse(mobileActionButton, 0.04, 4)
	mobileActionButton.Visible = false
	-- Touch: smaller DROP button beside it while holding something.
	mobileDropButton = UI.Button({ Text = "DROP", Color = UI.Colors.Locked, Size = UDim2.fromOffset(74, 74), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -146, 1, -150), FitText = 15, Corner = 37 }, matchFrame)
	mobileDropButton.Visible = false
end

local function refreshLobby()
	local cpRoom, cpPercent = attr("CheckpointRoomId", 0), attr("CheckpointPercent", 0)
	resumeFrame.Visible = cpRoom > 0 and cpPercent > 0
	if resumeFrame.Visible then
		resumeLabel.Text = string.format("CHECKPOINT: ROOM %s · %d%%", FormatUtil.RoomNumber(cpRoom), math.floor(cpPercent * 100))
	end
	refreshPlay()
	refreshWallet()
end

local function refreshMatchStatic()
	local hard = matchState:GetAttribute("Hard") == true
	roomTitleLabel.Text = "ROOM " .. FormatUtil.RoomNumber(matchState:GetAttribute("RoomId") or 1) .. (hard and "  ·  HARD MODE" or "")
	if hard then
		UI.TextGradient(roomTitleLabel, UI.Colors.Red)
	else
		UI.Gradient(roomTitleLabel, Color3.new(1, 1, 1), Color3.new(1, 1, 1))
	end
	roomTargetLabel.Text = "Find the " .. (matchState:GetAttribute("TargetName") or "")
end

-- ROOM CLEANED with two decimals, rolled in hundredths of a percent, so every object that goes
-- into a bin visibly moves it (1.20% -> 1.23%). Never shows 100% before the room is done.
local shownHundredths = 0
local function cleanedText(hundredths: number): string
	if hundredths >= 10000 then
		return "ROOM CLEANED: 100%"
	end
	return string.format("ROOM CLEANED: %.2f%%", hundredths / 100)
end

local function refreshProgress(instant: boolean?)
	local p = matchState:GetAttribute("Progress") or 0
	progressBar.Set(p, true)
	local target = math.floor(p * 10000 + 1e-6)
	UI.CountUp(progressLabel, instant and target or shownHundredths, target, cleanedText, 0.35)
	shownHundredths = target
end

-- Deposit pay flies to you as bills first (FXController): gains wait until it lands.
local cashHoldUntil = 0

local function refreshCash()
	local cash = attr("RoomCash", 0)
	if cash ~= shownCash and not (cash > shownCash and os.clock() < cashHoldUntil) then
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
		refreshProgress(true)
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
	local sp = attr("SpeedBoostExpires", 0)
	if sp > now then
		table.insert(entries, { Text = "2X SPEED  " .. FormatUtil.Time(sp - now), Color = UI.Colors.Cyan })
	end
	local xp = attr("XPBoostExpires", 0)
	if xp > now then
		table.insert(entries, { Text = "2X XP  " .. FormatUtil.Time(xp - now), Color = UI.Colors.Pink })
	end
	local lift = attr("LiftExpires", 0)
	if lift > now then
		table.insert(entries, { Text = string.format("LIFT %d  %s", attr("LiftWeight", 0), FormatUtil.Time(lift - now)), Color = UI.Colors.Orange })
	end
	if attr("TreasureRadar", "") ~= "" and attr("TreasureRadar", "") == attr("MatchId", "") then
		table.insert(entries, { Text = "TREASURE RADAR", Color = UI.Colors.Gold })
	end
	if attr("FriendBonus", false) then
		table.insert(entries, { Text = "FRIEND BONUS +25%", Color = UI.Colors.Green })
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

-- The room panel moves up into the middle of the Roblox top bar when it's free there (Roblox keeps
-- its own buttons on the left), so it covers less of the view; otherwise it sits just under it.
local TOP_MARGIN = 6
local function placeTop()
	local camera = workspace.CurrentCamera
	local ok, inset = pcall(function()
		return GuiService.TopbarInset
	end)
	local fits = false
	if ok and camera and inset.Height > 0 then
		local centre, half = camera.ViewportSize.X / 2, 440 * UI.Scale / 2 + 8
		fits = centre - half >= inset.Min.X and centre + half <= inset.Max.X
	end
	topY = fits and (TOP_MARGIN - UI.SafeTop) or 10
	matchTop.Position = UDim2.new(0.5, 0, 0, topY)
end

function HUDController.Init()
	buildLobbyHUD()
	buildMatchHUD()
	placeTop()
	local function replace()
		task.defer(placeTop)
	end
	UI.ScaleObject:GetPropertyChangedSignal("Scale"):Connect(replace)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(replace)
	end)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(replace)
	end
	player:GetAttributeChangedSignal("InMatch"):Connect(refreshVisibility)
	player:GetAttributeChangedSignal("Wallet"):Connect(refreshWallet)
	for _, name in ipairs({ "QueueId", "Teleporting", "HighestRoomCompleted" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshPlay)
	end
	-- Controllers: a D-pad direction opens its tile's menu, unless it is steering a selection.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or GuiService.SelectedObject ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonX and lobbyFrame.Visible and playFrame.Visible and not UI.GetOpenMenu() then
			HUDController.PlayNow()
			return
		end
		for _, s in ipairs(padShortcuts) do
			if s.Key == input.KeyCode and s.Frame.Visible and s.Button.Visible then
				s.Open()
				return
			end
		end
	end)
	for _, name in ipairs({ "CheckpointRoomId", "CheckpointPercent" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if lobbyFrame.Visible then
				refreshLobby()
			end
		end)
	end
	player:GetAttributeChangedSignal("RoomCash"):Connect(function()
		-- A moment's grace: the deposit's flying pay arrives right after and holds the counter.
		task.delay(0.1, refreshCash)
	end)
	player:GetAttributeChangedSignal("MaxWeight"):Connect(refreshCash)
	player:GetAttributeChangedSignal("HotCold"):Connect(refreshHotCold)
	matchState:GetAttributeChangedSignal("Progress"):Connect(refreshProgress)
	matchState:GetAttributeChangedSignal("RoomId"):Connect(refreshMatchStatic)
	matchState:GetAttributeChangedSignal("TargetName"):Connect(refreshMatchStatic)
	matchState:GetAttributeChangedSignal("Hard"):Connect(refreshMatchStatic)
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
		if cashHoldUntil > 0 and os.clock() >= cashHoldUntil then
			cashHoldUntil = 0
			refreshCash()
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
		local clock = start > 0 and FormatUtil.Time((finish > 0 and finish or workspace:GetServerTimeNow()) - start) or "00:00"
		-- Clues arrive on a timer (cleaning brings them sooner): count down to the next one.
		local nextClue = matchState:GetAttribute("NextClueAt") or 0
		if nextClue > 0 and matchState:GetAttribute("State") == "Searching" then
			local left = math.max(0, math.ceil(nextClue - workspace:GetServerTimeNow()))
			clock ..= string.format("   <font color=\"#5AD2FF\">NEXT CLUE %d:%02d</font>", left // 60, left % 60)
		end
		timerLabel.Text = clock
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
	-- One button does it all on touch (hold to grab, slide to aim, let go to throw): no DROP.
	mobileDropButton.Visible = false
	mobileActionButton.Visible = text ~= nil
	if text and mobileActionButton.Text ~= text then
		mobileActionButton.Text = text
		mobileActionButton.BackgroundColor3 = (text == "THROW" and UI.Colors.Orange) or (text == "HEAVY" and UI.Colors.Red) or UI.Colors.Green
	end
end

-- Pay is flying to you: cash gains show once it lands (at most 1.5 s later).
function HUDController.HoldCash(seconds: number)
	if os.clock() >= cashHoldUntil then
		cashHoldUntil = os.clock() + math.clamp(seconds, 0, 1.5)
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

-- Desktop only: the right-side column under the tiles (boosts first).
function HUDController.GetRightStack(): Frame?
	return rightStack
end

-- The room panel at the top (the gift bar hangs under it).
function HUDController.GetMatchTop(): Frame
	return matchTop
end

function HUDController.GetLobbyFrame(): Frame
	return lobbyFrame
end

-- Where the free space under the top panel starts (HUD-layer units): the clue banner and the
-- tutorial line stack from here. The lobby has no top panel; starting under the level badge
-- (12 + 50, ProgressionController) keeps the line clear of it on narrow phones.
function HUDController.TopClear(): number
	if matchFrame and matchFrame.Visible then
		return topY + 104 + 36 -- the panel and the gift bar under it
	end
	return 68 + 40 -- under the wallet
end

return HUDController
