--[[
	Lasting progression (see ProgressionConfig): Cleaner XP / level / title, room mastery stars
	and daily challenges. Everything lives in the player's profile and replicates as attributes:
	  CleanerLevel, CleanerXP (into the level), CleanerXPNext, CleanerTitle,
	  DailyChallenges (JSON list), DailyResetAt (server time), Stars_<roomId> (bitmask).
	FX events to the player: XP, LevelUp, ChallengeDone.
	Also the overhead PlayerTag: the level line for everyone, plus a stats pill (objects found,
	Finder Wins) while the player is in the lobby.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PetConfig = require(Shared.Config.PetConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local ProgressionService = {}

local claimLimiter = RateLimiter.new(1, 2)

local function today(): number
	return math.floor(workspace:GetServerTimeNow() / 86400)
end

-- New UTC day: roll this player's 3 challenges (deterministic per player per day).
local function ensureDaily(player: Player, data): boolean
	local day = today()
	if data.Daily.Day == day and #data.Daily.Ids > 0 then
		return false
	end
	local rng = Random.new(player.UserId * 31 + day)
	local pool = {}
	local reach = (data.HighestRoomCompleted or 0) + 1
	for i, c in ipairs(ProgressionConfig.Challenges) do
		if not c.MinRoom or reach >= c.MinRoom then
			table.insert(pool, i)
		end
	end
	local ids = {}
	for _ = 1, math.min(ProgressionConfig.DailyCount, #pool) do
		table.insert(ids, ProgressionConfig.Challenges[table.remove(pool, rng:NextInteger(1, #pool))].Id)
	end
	data.Daily = { Day = day, Ids = ids, Progress = {}, Done = {} }
	Services.DataService.MarkDirty(player)
	return true
end

local function rewardFor(day: number, slot: number)
	return ProgressionConfig.Rewards[(day + slot - 1) % #ProgressionConfig.Rewards + 1]
end

-- Daily login: today's reward in the 7-day cycle (1-7), whether it can still be claimed, the
-- streak it counts as, and whether that streak needs this week's streak freeze. Missing a day
-- starts the streak (and the cycle) over, unless the weekly freeze covers it.
local function loginStatus(data): (number, boolean, number, boolean)
	local day = today()
	local login = data.Login
	local count = #ProgressionConfig.LoginRewards
	if login.Day == day then
		return (login.Streak - 1) % count + 1, false, login.Streak, false
	end
	local streak, frozen = 1, false
	if login.Day == day - 1 then
		streak = login.Streak + 1
	elseif login.Day == day - 2 and login.Streak > 0 and Services.RetentionService.FreezeReady(data, day) then
		streak, frozen = login.Streak + 1, true
	end
	return (streak - 1) % count + 1, true, streak, frozen
end

-- ===== Overhead tag =====
-- Everyone sees "LV 12 · SOCK HUNTER" (gold with a VIP prefix for VIP pass owners) and, in the lobby
-- only, a small pill to flex with: the key + objects found and the trophy + Finder Wins. The tag
-- grows upward from its bottom edge, so the pill sits just over the head with the level line on top.
local TAG_WIDTH = 200
local LEVEL_HEIGHT = 26
local STATS_HEIGHT = 22
local STATS_TEXT = 15

local function uiImage(key: string): string?
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	local images = assets and assets:FindFirstChild("UIImages")
	local id = images and images:GetAttribute(key)
	return if type(id) == "string" and id ~= "" then id else nil
end

-- One stat in the pill: its icon (when the art exists) and its number.
local function addStat(parent: Frame, name: string, iconKey: string, color: Color3, order: number)
	local id = uiImage(iconKey)
	if id then
		local icon = Instance.new("ImageLabel")
		icon.Name = name .. "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(16, 16)
		icon.Image = id
		icon.LayoutOrder = order
		icon.Parent = parent
	end
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, STATS_HEIGHT)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = STATS_TEXT
	label.TextColor3 = color
	label.LayoutOrder = order + 1
	label:SetAttribute("Icon", id ~= nil)
	-- Roblox's Text Size setting would push the numbers out of the pill.
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = STATS_TEXT
	cap.Parent = label
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 1.5
	outline.Parent = label
	label.Parent = parent
end

local function buildTag(head: BasePart): BillboardGui
	local tag = Instance.new("BillboardGui")
	tag.Name = "PlayerTag"
	tag.Size = UDim2.fromOffset(TAG_WIDTH, LEVEL_HEIGHT)
	tag.StudsOffset = Vector3.new(0, 2.1, 0)
	tag.SizeOffset = Vector2.new(0, 0.5) -- anchored by its bottom edge
	tag.MaxDistance = 80
	tag.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, LEVEL_HEIGHT)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 2
	outline.Parent = label
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Gradient"
	gradient.Rotation = 90
	gradient.Parent = label
	label.Parent = tag

	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.AnchorPoint = Vector2.new(0.5, 1)
	stats.Position = UDim2.fromScale(0.5, 1)
	stats.AutomaticSize = Enum.AutomaticSize.X
	stats.Size = UDim2.fromOffset(0, STATS_HEIGHT)
	stats.BackgroundColor3 = Color3.new(0, 0, 0)
	stats.BackgroundTransparency = 0.4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = stats
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = stats
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = stats
	addStat(stats, "Found", "Icon_Key", Color3.fromRGB(255, 214, 70), 1)
	local gap = Instance.new("Frame")
	gap.Name = "Gap"
	gap.BackgroundTransparency = 1
	gap.Size = UDim2.fromOffset(6, 1)
	gap.LayoutOrder = 3
	gap.Parent = stats
	addStat(stats, "Wins", "Icon_Collection", Color3.new(1, 1, 1), 4)
	stats.Parent = tag

	tag.Parent = head
	return tag
end

function ProgressionService.RefreshTag(player: Player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local old = head:FindFirstChild("VIPTag")
	if old then
		old:Destroy()
	end
	local tag = head:FindFirstChild("PlayerTag")
	if tag and not tag:FindFirstChild("Stats") then
		tag:Destroy() -- an older tag without the stats pill
		tag = nil
	end
	if not tag then
		tag = buildTag(head)
	end
	local label = tag:FindFirstChild("Text") :: TextLabel
	local level = player:GetAttribute("CleanerLevel") or 1
	local vip = Services.MonetizationService.OwnsPass(player, "VIP")
	-- Completing the Pet Index adds its title.
	local data = Services.DataService.Get(player)
	local petTitle = data and data.Pets and data.Pets.IndexRewarded and (" · " .. string.upper(PetConfig.IndexTitle)) or ""
	label.Text = string.format("%sLV %d · %s%s", vip and "VIP · " or "", level, string.upper(player:GetAttribute("CleanerTitle") or ProgressionConfig.TitleFor(level)), petTitle)
	-- Gold gradient for VIP pass owners, a cool white for everyone else.
	local gradient = label:FindFirstChild("Gradient")
	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = vip and ColorSequence.new(Color3.fromRGB(255, 236, 110), Color3.fromRGB(255, 160, 0))
			or ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 225, 255))
	end
	-- The stats pill is for the lobby; in a room the tag is just the level line.
	local lobby = player:GetAttribute("InMatch") ~= true
	local stats = tag:FindFirstChild("Stats") :: Frame
	stats.Visible = lobby
	;(tag :: BillboardGui).Size = UDim2.fromOffset(TAG_WIDTH, if lobby then LEVEL_HEIGHT + 2 + STATS_HEIGHT else LEVEL_HEIGHT)
	local found = stats:FindFirstChild("Found") :: TextLabel
	local wins = stats:FindFirstChild("Wins") :: TextLabel
	found.Text = string.format("%d/%d%s", player:GetAttribute("ObjectsFound") or 0, GameConfig.TotalObjects, if found:GetAttribute("Icon") then "" else " FOUND")
	wins.Text = string.format("%d%s", player:GetAttribute("FinderWins") or 0, if wins:GetAttribute("Icon") then "" else " WINS")
end

function ProgressionService.Publish(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	ensureDaily(player, data)
	local level, into, need = ProgressionConfig.LevelFor(data.CleanerXP)
	player:SetAttribute("CleanerLevel", level)
	player:SetAttribute("CleanerXP", into)
	player:SetAttribute("CleanerXPNext", need)
	player:SetAttribute("CleanerTitle", ProgressionConfig.TitleFor(level))
	local list = {}
	for slot, id in ipairs(data.Daily.Ids) do
		local c = ProgressionConfig.Challenge(id)
		if c then
			table.insert(list, {
				Id = id,
				Text = string.format(c.Text, c.Goal),
				Goal = c.Goal,
				Progress = math.min(data.Daily.Progress[id] or 0, c.Goal),
				Done = data.Daily.Done[id] == true,
				Reward = rewardFor(data.Daily.Day, slot).Text,
			})
		end
	end
	player:SetAttribute("DailyChallenges", HttpService:JSONEncode(list))
	player:SetAttribute("DailyResetAt", (data.Daily.Day + 1) * 86400)
	local loginDay, claimable, streak, frozen = loginStatus(data)
	player:SetAttribute("LoginFrozen", frozen)
	player:SetAttribute("LoginFreezeReady", Services.RetentionService.FreezeReady(data, today()))
	player:SetAttribute("LoginDay", loginDay)
	player:SetAttribute("LoginClaimable", claimable)
	player:SetAttribute("LoginStreak", claimable and streak - 1 or streak) -- days claimed in a row so far
	player:SetAttribute("LoginResetAt", (today() + 1) * 86400)
	for roomId, mask in pairs(data.Stars) do
		player:SetAttribute("Stars_" .. roomId, mask)
	end
	ProgressionService.RefreshTag(player)
end

-- Adds XP without publishing (callers publish once at the end).
local function addXP(player: Player, data, amount: number, reason: string)
	if amount <= 0 then
		return
	end
	-- 2x XP boost: everything earned in rooms (gifts and daily rewards stay as they are).
	if reason ~= "Daily" and reason ~= "Gift" then
		amount = math.floor(amount * Services.PlayerSessionService.GetXPMultiplier(player) + 0.5)
	end
	local before = ProgressionConfig.LevelFor(data.CleanerXP)
	data.CleanerXP += amount
	Services.DataService.MarkDirty(player)
	local after = ProgressionConfig.LevelFor(data.CleanerXP)
	Remotes.Event("FXEvent"):FireClient(player, "XP", { Amount = amount, Reason = reason })
	Services.AnalyticsService.XP(player, amount, reason, data.CleanerXP)
	if after > before then
		local title = ProgressionConfig.TitleFor(after)
		Remotes.Event("FXEvent"):FireClient(player, "LevelUp", { Level = after, Title = title, NewTitle = title ~= ProgressionConfig.TitleFor(before) })
		Services.AnalyticsService.LevelUp(player, after, title)
		task.defer(Services.RetentionService.First, player, "LevelUp")
	end
end

-- XP from outside the game hooks (gifts, the spin): added and published at once.
function ProgressionService.GiveXP(player: Player, amount: number, reason: string)
	local data = Services.DataService.Get(player)
	if data then
		addXP(player, data, amount, reason)
		ProgressionService.Publish(player)
	end
end

local function grantReward(player: Player, data, reward, challenge)
	if reward.Kind == "Boost" then
		Services.PlayerSessionService.ExtendBoost(player, reward.Attribute, reward.Seconds)
	elseif reward.Kind == "Hint" then
		if not Services.HintService.GrantQuickHint(player) then
			data.Banked.QuickHint = (data.Banked.QuickHint or 0) + 1
		end
	end
	addXP(player, data, ProgressionConfig.XP.Challenge, "Challenge")
	task.defer(Services.WalletService.Add, player, EconomyConfig.Challenge, "Gameplay", "Challenge", true)
	Remotes.Event("FXEvent"):FireClient(player, "ChallengeDone", { Text = string.format(challenge.Text, challenge.Goal), Reward = reward.Text, Cash = EconomyConfig.Challenge })
	Services.AnalyticsService.Event(player, "challenge_done", 1, challenge.Id, reward.Kind)
end

-- Daily login reward: XP now; hints and boosts are banked for the next room.
local function grantLoginReward(player: Player, data, reward)
	if reward.XP then
		addXP(player, data, reward.XP, "Daily")
	end
	if reward.Hint then
		data.Banked[reward.Hint] = (data.Banked[reward.Hint] or 0) + 1
	end
	if reward.Boost then
		data.Banked[reward.Boost] = (data.Banked[reward.Boost] or 0) + (reward.Seconds or 0)
	end
end

local function track(player: Player, data, stat: string, amount: number)
	ensureDaily(player, data)
	for slot, id in ipairs(data.Daily.Ids) do
		local c = ProgressionConfig.Challenge(id)
		if c and c.Stat == stat and not data.Daily.Done[id] then
			local p = data.Daily.Progress[id] or 0
			p = c.Max and math.max(p, amount) or p + amount
			data.Daily.Progress[id] = p
			if p >= c.Goal then
				data.Daily.Done[id] = true
				grantReward(player, data, rewardFor(data.Daily.Day, slot), c)
			end
		end
	end
	Services.DataService.MarkDirty(player)
end

-- ===== Game hooks =====

function ProgressionService.OnDeposit(player: Player, info: { Match: boolean, BinType: string, Swish: boolean, Streak: number, Treasure: boolean })
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local xp = ProgressionConfig.XP.Deposit
	track(player, data, "Deposit", 1)
	if info.Match then
		xp += ProgressionConfig.XP.DepositMatch
		track(player, data, "Match_" .. info.BinType, 1)
	end
	if info.Swish then
		xp += ProgressionConfig.XP.Swish
		data.Stats.Swishes += 1
		track(player, data, "Swish", 1)
	end
	if info.Treasure then
		xp += ProgressionConfig.XP.Treasure
		data.Stats.Treasures += 1
		track(player, data, "Treasure", 1)
	end
	track(player, data, "StreakMax", info.Streak or 0)
	addXP(player, data, xp, "Deposit")
	ProgressionService.Publish(player)
end

function ProgressionService.OnChunkBurst(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	data.Stats.Chunks += 1
	track(player, data, "ChunkBurst", 1)
	addXP(player, data, ProgressionConfig.XP.ChunkBurst, "Chunk")
	ProgressionService.Publish(player)
	Services.RetentionService.First(player, "Chunk")
end

-- Called for every party member when a room is completed. Returns { Earned, New } star masks
-- and Saved: what the room paid into the wallet (deposits and the completion rewards).
function ProgressionService.OnRoomComplete(player: Player, match, isFinder: boolean, firstClear: boolean)
	local data = Services.DataService.Get(player)
	if not data then
		return { Earned = 0, New = 0, Saved = 0 }
	end
	local earned = 1
	if (match.Progress or 0) >= ProgressionConfig.Stars[2].Fraction then
		earned = bit32.bor(earned, 2)
	end
	if (match.TreasuresTotal or 0) > 0 and (match.TreasuresCleaned or 0) >= match.TreasuresTotal then
		earned = bit32.bor(earned, 4)
	end
	local key = tostring(match.RoomId)
	local old = data.Stars[key] or 0
	local new = bit32.band(earned, bit32.bnot(old))
	data.Stars[key] = bit32.bor(old, earned)
	local newCount = 0
	for _, s in ipairs(ProgressionConfig.Stars) do
		if bit32.band(new, s.Bit) ~= 0 then
			newCount += 1
		end
	end
	local xp = ProgressionConfig.XP.RoomComplete + newCount * ProgressionConfig.XP.Star
	if isFinder then
		xp += ProgressionConfig.XP.KeyFound
		data.Stats.Keys += 1
	end
	if firstClear then
		xp += ProgressionConfig.XP.FirstClear
	end
	track(player, data, "RoomComplete", 1)
	addXP(player, data, xp, "Room")
	ProgressionService.Publish(player)
	local bonus = EconomyConfig.RoomComplete + newCount * EconomyConfig.Star
		+ (match.Hard and EconomyConfig.RoomCompleteHardBonus or 0)
		+ (isFinder and EconomyConfig.KeyFound or 0)
		+ (firstClear and EconomyConfig.FirstClear or 0)
	Services.WalletService.Add(player, bonus, "Gameplay", "RoomComplete", true)
	return { Earned = earned, New = new, Saved = Services.WalletService.RoomSaved(player) + bonus, Bonus = bonus }
end

function ProgressionService.Init()
	Remotes.Event("ClaimDailyReward").OnServerEvent:Connect(function(player)
		if not claimLimiter:Allow(player) then
			return
		end
		local data = Services.DataService.Get(player)
		if not data then
			return
		end
		local cycleDay, claimable, streak, frozen = loginStatus(data)
		if not claimable then
			return
		end
		local reward = ProgressionConfig.LoginRewards[cycleDay]
		data.Login.Day = today()
		data.Login.Streak = streak
		if frozen then
			Services.RetentionService.UseFreeze(data, today())
			Services.NotificationService.Send(player, "Success", string.format("Your weekly Streak Freeze kept your %d-day streak!", streak), 5)
			Services.AnalyticsService.Event(player, "streak_freeze", streak)
		end
		grantLoginReward(player, data, reward)
		Services.DataService.MarkDirty(player)
		Services.DataService.Save(player)
		Remotes.Event("FXEvent"):FireClient(player, "DailyClaimed", { Day = cycleDay, Streak = streak, Reward = reward.Text, Later = reward.Hint ~= nil or reward.Boost ~= nil })
		Services.AnalyticsService.DailyStep(player, "Claimed", "day " .. tostring(cycleDay))
		Services.AnalyticsService.Event(player, "daily_claim", cycleDay, streak >= 7 and "7+ days" or (tostring(streak) .. " days"), reward.Kind or "reward")
		ProgressionService.Publish(player)
	end)

	local function onPlayer(player: Player)
		-- The overhead tag follows the collection, Finder Wins and moves between lobby and room.
		for _, name in ipairs({ "ObjectsFound", "FinderWins", "InMatch" }) do
			player:GetAttributeChangedSignal(name):Connect(function()
				ProgressionService.RefreshTag(player)
			end)
		end
		task.spawn(function()
			if Services.DataService.WaitFor(player, 15) then
				ProgressionService.Publish(player)
				if player:GetAttribute("LoginClaimable") == true then
					Services.AnalyticsService.DailyStep(player, "Waiting")
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
end

function ProgressionService.Start()
	-- Roll the next day's challenges for everyone online when the UTC day changes.
	task.spawn(function()
		local lastDay = today()
		while true do
			task.wait(30)
			if today() ~= lastDay then
				lastDay = today()
				for _, p in ipairs(Players:GetPlayers()) do
					ProgressionService.Publish(p)
				end
			end
		end
	end)
end

return ProgressionService
