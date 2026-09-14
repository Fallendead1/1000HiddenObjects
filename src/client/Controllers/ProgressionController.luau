--[[
	Lasting progression on the client: Cleaner Level badge + XP bar (lobby and match HUD),
	+XP popups, the level-up celebration, the Daily Challenges menu and in-match tracker,
	the key bursting out of its packed junk, and the Invite Friends prompt.
	All data comes from player attributes published by ProgressionService.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local ProgressionController = {}

local badges: { { Frame: Frame, Update: () -> () } } = {}
local menu
local menuHeader: TextLabel
local menuRows: Frame
local menuFooter: TextLabel
local tracker: Frame
local trackerRows: Frame
local pendingXP = 0
local xpFlushQueued = false

local touch = UI.IsTouch()

local function challenges(): { any }
	local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("DailyChallenges") or "[]")
	return (ok and type(list) == "table") and list or {}
end

local function resetText(): string
	local left = math.max(0, (player:GetAttribute("DailyResetAt") or 0) - workspace:GetServerTimeNow())
	return string.format("New challenges in %dh %02dm", math.floor(left / 3600), math.floor(left % 3600 / 60))
end

local function clearFrames(parent: Instance)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

-- ===== Level badge =====

local function makeBadge(parent: Instance, anchor: Vector2, position: UDim2)
	local frame = UI.Panel({ Size = UDim2.fromOffset(240, 44), AnchorPoint = anchor, Position = position, BackgroundTransparency = 0.1 }, parent)
	UI.Stroke(frame, UI.Colors.Cyan, 2)
	UI.Glow(frame, UI.Colors.Cyan, 14, 0.8)
	local circle = UI.Frame({ Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = UI.Colors.Cyan }, frame)
	UI.Corner(circle, 18)
	UI.Stroke(circle, Color3.new(1, 1, 1), 2)
	local level = UI.Label({ Text = "1", TextSize = 18, TextColor3 = UI.Colors.PanelDark }, circle)
	local title = UI.Label({ Text = "", TextSize = 14, Size = UDim2.new(1, -52, 0, 18), Position = UDim2.fromOffset(46, 4), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, frame)
	local bar = UI.ProgressBar(frame, UDim2.new(1, -54, 0, 13), UDim2.fromOffset(46, 25), UI.Colors.Cyan)
	UI.Shine(bar.Fill, 3.4)
	local xpText = UI.Label({ Text = "", TextSize = 11, Font = UI.FontBody, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, bar.Frame)
	UI.Stroke(xpText, Color3.new(0, 0, 0), 1, 0.4)
	-- Tap the badge to open the challenges.
	local hit = UI.New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, frame) :: TextButton
	hit.Activated:Connect(function()
		ProgressionController.OpenChallenges()
	end)

	local badge = { Frame = frame }
	function badge.Update()
		local into, need = player:GetAttribute("CleanerXP") or 0, player:GetAttribute("CleanerXPNext") or 0
		level.Text = tostring(player:GetAttribute("CleanerLevel") or 1)
		title.Text = "LV " .. level.Text .. " · " .. string.upper(player:GetAttribute("CleanerTitle") or "")
		bar.Set(need > 0 and into / need or 1, true)
		xpText.Text = need > 0 and string.format("%d / %d XP", into, need) or "MAX LEVEL"
	end
	table.insert(badges, badge)
	return badge
end

local function updateBadges()
	for _, b in ipairs(badges) do
		b.Update()
	end
end

local function visibleBadge(): Frame?
	for _, b in ipairs(badges) do
		if b.Frame.Parent and (b.Frame.Parent :: GuiObject).Visible then
			return b.Frame
		end
	end
	return nil
end

-- Deposits come fast: gather XP for a moment, then show one "+12 XP".
local function showXP(amount: number)
	pendingXP += amount
	if xpFlushQueued then
		return
	end
	xpFlushQueued = true
	task.delay(0.6, function()
		xpFlushQueued = false
		local frame = visibleBadge()
		if frame and pendingXP > 0 then
			local abs, size = frame.AbsolutePosition, frame.AbsoluteSize
			local pos = UDim2.fromOffset((abs.X + size.X / 2) / UI.Scale, (abs.Y + size.Y + 34) / UI.Scale)
			Controllers.FXController.FloatingText(string.format("+%d XP", pendingXP), UI.Colors.Cyan, pos, 22)
		end
		pendingXP = 0
	end)
end

-- Big centred two-line banner (level up, challenge complete) that pops in and fades.
local function banner(big: string, small: string, color: Color3)
	local holder = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(640, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3) }, UI.Layers.Overlay)
	local top = UI.Label({ Text = big, TextSize = 56, TextColor3 = color, Size = UDim2.new(1, 0, 0, 70) }, holder)
	UI.Stroke(top, Color3.new(0, 0, 0), 3, 0.2)
	local bottom = UI.Label({ Text = small, TextSize = 24, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 72) }, holder)
	UI.Stroke(bottom, Color3.new(0, 0, 0), 2, 0.2)
	UI.PopIn(holder, 0.4, 0.35)
	task.delay(2.6, function()
		UI.Tween(top, { TextTransparency = 1 }, 0.4)
		UI.Tween(bottom, { TextTransparency = 1 }, 0.4)
		task.wait(0.45)
		holder:Destroy()
	end)
end

local function celebrate(color: Color3)
	Controllers.FXController.ScreenFlash(color, 0.6)
	Controllers.FXController.FovPunch(5)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Controllers.FXController.Confetti(root.Position)
	end
	for _, b in ipairs(badges) do
		UI.PopIn(b.Frame, 0.8, 0.3)
	end
end

-- ===== Daily challenges =====

local function challengeRow(parent: Instance, c, order: number)
	local done = c.Done == true
	local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, parent)
	UI.Corner(row, 10)
	UI.Stroke(row, done and UI.Colors.Green or UI.Colors.Cyan, 2, done and 0 or 0.5)
	if done then
		UI.Glow(row, UI.Colors.Green, 12, 0.7)
	end
	UI.Label({ Text = c.Text or "", TextSize = 18, TextWrapped = true, Size = UDim2.new(1, -170, 0, 40), Position = UDim2.fromOffset(14, 4), TextXAlignment = Enum.TextXAlignment.Left }, row)
	UI.Label({ Text = done and "DONE ✓" or ("REWARD\n" .. (c.Reward or "")), TextSize = 14, Font = UI.FontBody, TextWrapped = true, TextColor3 = done and UI.Colors.Green or UI.Colors.Gold, Size = UDim2.new(0, 150, 0, 40), Position = UDim2.new(1, -160, 0, 4), TextXAlignment = Enum.TextXAlignment.Right }, row)
	local bar = UI.ProgressBar(row, UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 52), done and UI.Colors.Green or UI.Colors.Cyan)
	bar.Set(math.clamp((c.Progress or 0) / math.max(1, c.Goal or 1), 0, 1))
	local text = UI.Label({ Text = string.format("%d / %d   ·   +100 XP", c.Progress or 0, c.Goal or 0), TextSize = 13, Font = UI.FontBody, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, bar.Frame)
	UI.Stroke(text, Color3.new(0, 0, 0), 1, 0.4)
end

local function refreshChallenges()
	local list = challenges()
	if menu and menu.IsOpen() then
		clearFrames(menuRows)
		for i, c in ipairs(list) do
			challengeRow(menuRows, c, i)
		end
		menuHeader.Text = string.format("LV %d · %s   ·   %d / %d XP", player:GetAttribute("CleanerLevel") or 1, string.upper(player:GetAttribute("CleanerTitle") or ""), player:GetAttribute("CleanerXP") or 0, player:GetAttribute("CleanerXPNext") or 0)
		menuFooter.Text = resetText()
	end
	if tracker then
		clearFrames(trackerRows)
		for i, c in ipairs(list) do
			local done = c.Done == true
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = i }, trackerRows)
			UI.Label({ Text = (done and "✓ " or "") .. (c.Text or ""), TextSize = 13, Font = UI.FontBody, TextColor3 = done and UI.Colors.Green or UI.Colors.Text, Size = UDim2.new(1, -52, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
			UI.Label({ Text = done and "DONE" or string.format("%d/%d", c.Progress or 0, c.Goal or 0), TextSize = 13, Font = UI.FontBody, TextColor3 = done and UI.Colors.Green or UI.Colors.Cyan, Size = UDim2.new(0, 50, 1, 0), Position = UDim2.new(1, -50, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
		end
		tracker.Visible = #list > 0
	end
end

function ProgressionController.OpenChallenges()
	if menu then
		menu.Open()
	end
end

function ProgressionController.Invite()
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then
		pcall(SocialService.PromptGameInvite, SocialService, player)
	else
		Controllers.FXController.FloatingText("Invites aren't available right now", UI.Colors.TextDim, nil, 22)
	end
end

function ProgressionController.Init()
	makeBadge(Controllers.HUDController.GetLobbyFrame(), Vector2.new(0, 0), UDim2.fromOffset(12, 12))
	makeBadge(Controllers.HUDController.GetMatchFrame(), Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 116))

	menu = UI.Menu("Challenges", "DAILY CHALLENGES", UDim2.fromOffset(560, 440))
	menuHeader = UI.Label({ Text = "", TextSize = 17, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, 0, 0, 24) }, menu.Content)
	menuRows = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 30) }, menu.Content)
	UI.ListLayout(menuRows, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	menuFooter = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22) }, menu.Content)
	menu.OnOpen(refreshChallenges)

	-- In-match tracker (right side, under the boosts). Tap it for the full menu.
	tracker = UI.Panel({ Size = UDim2.fromOffset(250, 92), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, touch and 360 or 330), BackgroundTransparency = 0.15, Visible = false }, Controllers.HUDController.GetMatchFrame())
	UI.Stroke(tracker, UI.Colors.Cyan, 1, 0.3)
	UI.Label({ Text = "DAILY CHALLENGES", TextSize = 13, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left }, tracker)
	trackerRows = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, -26), Position = UDim2.fromOffset(8, 23) }, tracker)
	UI.ListLayout(trackerRows, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left)
	local hit = UI.New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, tracker) :: TextButton
	hit.Activated:Connect(ProgressionController.OpenChallenges)

	for _, name in ipairs({ "CleanerLevel", "CleanerXP", "CleanerXPNext", "CleanerTitle" }) do
		player:GetAttributeChangedSignal(name):Connect(updateBadges)
	end
	player:GetAttributeChangedSignal("DailyChallenges"):Connect(refreshChallenges)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		payload = payload or {}
		if name == "XP" then
			showXP(payload.Amount or 0)
		elseif name == "LevelUp" then
			Controllers.AudioController.Play("LevelUp")
			celebrate(UI.Colors.Cyan)
			banner("LEVEL " .. tostring(payload.Level or "?") .. "!", (payload.NewTitle and "NEW TITLE: " or "") .. string.upper(payload.Title or ""), UI.Colors.Cyan)
		elseif name == "ChallengeDone" then
			Controllers.AudioController.Play("CashAward")
			celebrate(UI.Colors.Green)
			banner("CHALLENGE COMPLETE!", "+" .. (payload.Reward or "") .. "  ·  +100 XP", UI.Colors.Green)
		end
	end)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName, payload)
		if eventName == "KeyBurst" and payload and payload.Position then
			Controllers.AudioController.PlayAt("ChunkBurst", payload.Position)
			Controllers.FXController.Burst(payload.Position + Vector3.new(0, 1, 0), UI.Colors.Gold, 40, 0.55)
			Controllers.FXController.CameraShake(0.4)
			Controllers.FXController.ScreenFlash(UI.Colors.Gold, 0.5)
			Controllers.FXController.FloatingText("THE KEY BURST OUT!", UI.Colors.Gold, UDim2.fromScale(0.5, 0.4), 40)
		end
	end)

	updateBadges()
	refreshChallenges()
end

function ProgressionController.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 then
			return
		end
		acc = 0
		if menu.IsOpen() then
			menuFooter.Text = resetText()
		end
	end)
end

return ProgressionController
