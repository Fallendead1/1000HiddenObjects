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
local matchState = ReplicatedStorage:WaitForChild("MatchState")

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
	local frame = UI.Panel({ Size = UDim2.fromOffset(254, 50), AnchorPoint = anchor, Position = position, BackgroundTransparency = 0.08 }, parent)
	UI.Stroke(frame, UI.Colors.Cyan, 2.5)
	UI.Glow(frame, UI.Colors.Cyan, 14, 0.8)
	local circle = UI.Surface3D({ Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(3, 3) }, frame, UI.Colors.Cyan, 22, 0.12)
	local level = UI.Label({ Text = "1", TextSize = 20, TextWrapped = false, Size = UDim2.new(1, 0, 0.88, 0) }, circle)
	local title = UI.Label({ Text = "", TextSize = 14, TextWrapped = false, Size = UDim2.new(1, -62, 0, 18), Position = UDim2.fromOffset(54, 5), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, frame)
	local bar = UI.ProgressBar(frame, UDim2.new(1, -62, 0, 17), UDim2.fromOffset(54, 26), UI.Colors.Cyan)
	UI.Shine(bar.Fill, 3.4)
	local xpText = UI.Label({ Text = "", TextSize = 11, TextWrapped = false, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, bar.Frame)
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

-- In rooms the level is a slim strip tucked under the Cash panel (HUDController leaves room for
-- it): just the level and the XP bar, out of the middle of the screen.
local function makeStrip(parent: Instance, position: UDim2)
	local frame = UI.Panel({ Size = UDim2.fromOffset(236, 24), Position = position, BackgroundTransparency = 0.12 }, parent)
	UI.Stroke(frame, UI.Colors.Cyan, 2)
	local level = UI.Label({ Text = "LV 1", TextSize = 14, TextWrapped = false, Size = UDim2.new(0, 56, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left }, frame)
	UI.TextGradient(level, UI.Colors.Cyan)
	local bar = UI.ProgressBar(frame, UDim2.new(1, -74, 0, 10), UDim2.new(0, 66, 0.5, -5), UI.Colors.Cyan)
	local hit = UI.New("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 }, frame) :: TextButton
	hit.Activated:Connect(function()
		ProgressionController.OpenChallenges()
	end)

	local badge = { Frame = frame }
	function badge.Update()
		local into, need = player:GetAttribute("CleanerXP") or 0, player:GetAttribute("CleanerXPNext") or 0
		level.Text = "LV " .. tostring(player:GetAttribute("CleanerLevel") or 1)
		bar.Set(need > 0 and into / need or 1, true)
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
			local pos = UI.FromAbsolute(Vector2.new(abs.X + size.X / 2, abs.Y + size.Y + 34))
			Controllers.FXController.FloatingText(string.format("+%d XP", pendingXP), UI.Colors.Cyan, pos, 22)
		end
		pendingXP = 0
	end)
end

-- Big centred two-line banner (level up, challenge complete) that pops in and fades (yields).
local function showBanner(big: string, small: string, color: Color3, hold: number)
	local holder = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(640, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3) }, UI.Layers.Overlay)
	local top = UI.Label({ Text = big, TextSize = 56, TextWrapped = false, Size = UDim2.new(1, 0, 0, 70) }, holder)
	UI.Stroke(top, Color3.new(0, 0, 0), 4.5, 0)
	UI.TextGradient(top, color)
	local bottom = UI.Label({ Text = small, TextSize = 24, TextWrapped = false, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 72) }, holder)
	UI.Stroke(bottom, Color3.new(0, 0, 0), 3, 0)
	UI.TextGradient(bottom, UI.Colors.Gold)
	UI.PopIn(holder, 0.4, 0.35)
	task.wait(hold)
	UI.Tween(top, { TextTransparency = 1 }, 0.4)
	UI.Tween(bottom, { TextTransparency = 1 }, 0.4)
	task.wait(0.45)
	holder:Destroy()
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

-- The key-found moment belongs to its own sound and ceremony: what the finder's XP brings (a
-- level up) waits until you're back in the lobby.
local function roomFinished(): boolean
	return player:GetAttribute("InMatch") == true and matchState:GetAttribute("TargetFound") == true
end

-- Banners never stack: a challenge's XP often levels you up in the same instant, so each one
-- (with its sound and celebration) waits for the one before it.
local bannerQueue = {}
local bannerRunning = false
local function banner(big: string, small: string, color: Color3, sound: string?)
	table.insert(bannerQueue, { Big = big, Small = small, Color = color, Sound = sound })
	if bannerRunning then
		return
	end
	bannerRunning = true
	task.spawn(function()
		while #bannerQueue > 0 do
			while roomFinished() do
				task.wait(0.5)
			end
			local b = table.remove(bannerQueue, 1)
			if b.Sound then
				Controllers.AudioController.Play(b.Sound)
			end
			celebrate(b.Color)
			-- Shorter while another one is waiting.
			showBanner(b.Big, b.Small, b.Color, #bannerQueue > 0 and 1.6 or 2.6)
		end
		bannerRunning = false
	end)
end

-- Other controllers' big moments (first-time rewards) share the same queue.
function ProgressionController.Banner(big: string, small: string, color: Color3, sound: string?)
	banner(big, small, color, sound)
end

-- ===== Daily challenges =====

local function challengeRow(parent: Instance, c, order: number)
	local done = c.Done == true
	local row = UI.Panel({ Size = UDim2.new(1, 0, 0, 92), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, parent)
	UI.Stroke(row, done and UI.Colors.Green or UI.Colors.Stroke, 2.5)
	if done then
		UI.Glow(row, UI.Colors.Green, 12, 0.7)
	end
	UI.Label({ Text = c.Text or "", TextSize = 17, TextWrapped = true, Size = UDim2.new(1, -190, 0, 44), Position = UDim2.fromOffset(14, 5), TextXAlignment = Enum.TextXAlignment.Left }, row)
	-- The reward on a studded chip (gold while open, green once done).
	local chip = UI.Surface3D({ Size = UDim2.fromOffset(164, 38), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8) }, row, done and UI.Colors.Green or UI.Colors.Gold, 10, 0.12)
	UI.Label({ Text = done and "DONE ✓" or (c.Reward or ""), TextSize = 13, TextWrapped = true, Size = UDim2.new(1, -10, 0.88, 0), Position = UDim2.fromOffset(5, 0) }, chip)
	local bar = UI.ProgressBar(row, UDim2.new(1, -28, 0, 24), UDim2.fromOffset(14, 56), done and UI.Colors.Green or UI.Colors.Cyan)
	bar.Set(math.clamp((c.Progress or 0) / math.max(1, c.Goal or 1), 0, 1))
	UI.Label({ Text = string.format("%d / %d   ·   +100 XP", c.Progress or 0, c.Goal or 0), TextSize = 13, TextWrapped = false, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, bar.Frame)
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
	Controllers.AnalyticsController.Track("invite")
	local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, player)
	if ok and can then
		pcall(SocialService.PromptGameInvite, SocialService, player)
	else
		Controllers.FXController.FloatingText("Invites aren't available right now", UI.Colors.TextDim, nil, 22)
	end
end

function ProgressionController.Init()
	makeBadge(Controllers.HUDController.GetLobbyFrame(), Vector2.new(0, 0), UDim2.fromOffset(12, 12))
	makeStrip(Controllers.HUDController.GetMatchFrame(), UDim2.fromOffset(12, 98))

	menu = UI.Menu("Challenges", "DAILY CHALLENGES", UDim2.fromOffset(560, 440), UI.Colors.Cyan)
	menuHeader = UI.Label({ Text = "", TextSize = 17, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, 0, 0, 24) }, menu.Content)
	menuRows = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 30) }, menu.Content)
	UI.ListLayout(menuRows, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	menuFooter = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -22) }, menu.Content)
	menu.OnOpen(refreshChallenges)

	-- In-match tracker: right side under the boosts, or on touch in the left-side stack (the right
	-- side belongs to the GRAB button there). Tap it for the full menu.
	local stack = Controllers.HUDController.GetSideStack() or Controllers.HUDController.GetRightStack()
	tracker = UI.Panel({ Size = UDim2.fromOffset(250, 94), AnchorPoint = stack and Vector2.zero or Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 300), BackgroundTransparency = 0.12, Visible = false, LayoutOrder = 3 }, stack or Controllers.HUDController.GetMatchFrame())
	UI.Stroke(tracker, UI.Colors.Cyan, 2)
	local trackerTitle = UI.Label({ Text = "DAILY CHALLENGES", TextSize = 13, TextWrapped = false, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left }, tracker)
	UI.TextGradient(trackerTitle, UI.Colors.Cyan)
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
			-- A challenge's XP is on its banner already, and the room's end has its own screens.
			if payload.Reason ~= "Challenge" and not roomFinished() then
				showXP(payload.Amount or 0)
			end
		elseif name == "LevelUp" then
			-- A moment later, so a challenge that caused it shows first.
			task.delay(0.1, banner, "LEVEL " .. tostring(payload.Level or "?") .. "!", (payload.NewTitle and "NEW TITLE: " or "") .. string.upper(payload.Title or ""), UI.Colors.Cyan, "LevelUp")
		elseif name == "ChallengeDone" then
			local saved = (payload.Cash or 0) > 0 and string.format("   +$%d SAVED", payload.Cash) or ""
			banner("CHALLENGE COMPLETE!", "+" .. (payload.Reward or "") .. "   +100 XP" .. saved, UI.Colors.Green, "CashAward")
		end
	end)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName, payload)
		if eventName == "KeyBurst" and payload and payload.Position then
			Controllers.AudioController.PlayAt("ChunkBurst", payload.Position)
			Controllers.FXController.Burst(payload.Position + Vector3.new(0, 1, 0), UI.Colors.Gold, 40, 0.55)
			Controllers.FXController.CameraShake(0.4)
			Controllers.FXController.ScreenFlash(UI.Colors.Gold, 0.5)
			Controllers.FXController.FloatingText(string.format("THE %s BURST OUT!", string.upper(matchState:GetAttribute("TargetName") or "KEY")), UI.Colors.Gold, UDim2.fromScale(0.5, 0.4), 40)
		end
	end)

	updateBadges()
	refreshChallenges()
end

-- Your own overhead tag (made by the server for everyone to see): you see it in the lobby, where its
-- stats pill is there to flex; in rooms it's hidden on your screen, since the first-person camera
-- sits inside your head.
local ownHead: Instance? = nil

local function syncOwnTag()
	local tag = ownHead and ownHead:FindFirstChild("PlayerTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = player:GetAttribute("InMatch") ~= true
	end
end

local function watchOwnTag(character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or character ~= player.Character then
		return
	end
	ownHead = head
	head.ChildAdded:Connect(function(child)
		if child.Name == "PlayerTag" then
			syncOwnTag()
		end
	end)
	syncOwnTag()
end

function ProgressionController.Start()
	if player.Character then
		task.spawn(watchOwnTag, player.Character)
	end
	player.CharacterAdded:Connect(watchOwnTag)
	player:GetAttributeChangedSignal("InMatch"):Connect(syncOwnTag)
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
