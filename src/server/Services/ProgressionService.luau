--[[
	Lasting progression (see ProgressionConfig): Cleaner XP / level / title, room mastery stars
	and daily challenges. Everything lives in the player's profile and replicates as attributes:
	  CleanerLevel, CleanerXP (into the level), CleanerXPNext, CleanerTitle,
	  DailyChallenges (JSON list), DailyResetAt (server time), Stars_<roomId> (bitmask).
	FX events to the player: XP, LevelUp, ChallengeDone.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)

local ProgressionService = {}

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
	for i = 1, #ProgressionConfig.Challenges do
		pool[i] = i
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

function ProgressionService.RefreshTag(player: Player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("VIPTag")
	if old then
		old:Destroy()
	end
	local tag = head:FindFirstChild("PlayerTag")
	local label: TextLabel
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name = "PlayerTag"
		tag.Size = UDim2.fromOffset(220, 30)
		tag.StudsOffset = Vector3.new(0, 2.6, 0)
		tag.MaxDistance = 80
		tag.LightInfluence = 0
		label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextStrokeTransparency = 0.25
		label.Parent = tag
		tag.Parent = head
	else
		label = tag:FindFirstChild("Text") :: TextLabel
	end
	local level = player:GetAttribute("CleanerLevel") or 1
	local vip = Services.MonetizationService.OwnsPass(player, "VIP")
	label.Text = string.format("%sLV %d · %s", vip and "VIP · " or "", level, string.upper(player:GetAttribute("CleanerTitle") or ProgressionConfig.TitleFor(level)))
	label.TextColor3 = vip and Color3.fromRGB(255, 205, 50) or Color3.fromRGB(235, 240, 255)
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
	local before = ProgressionConfig.LevelFor(data.CleanerXP)
	data.CleanerXP += amount
	Services.DataService.MarkDirty(player)
	local after = ProgressionConfig.LevelFor(data.CleanerXP)
	Remotes.Event("FXEvent"):FireClient(player, "XP", { Amount = amount, Reason = reason })
	if after > before then
		local title = ProgressionConfig.TitleFor(after)
		Remotes.Event("FXEvent"):FireClient(player, "LevelUp", { Level = after, Title = title, NewTitle = title ~= ProgressionConfig.TitleFor(before) })
		Services.AnalyticsService.Log("level_up", player, { Level = after })
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
	Remotes.Event("FXEvent"):FireClient(player, "ChallengeDone", { Text = string.format(challenge.Text, challenge.Goal), Reward = reward.Text })
	Services.AnalyticsService.Log("daily_done", player, { Id = challenge.Id })
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
end

-- Called for every party member when a room is completed. Returns { Earned, New } star masks.
function ProgressionService.OnRoomComplete(player: Player, match, isFinder: boolean, firstClear: boolean)
	local data = Services.DataService.Get(player)
	if not data then
		return { Earned = 0, New = 0 }
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
	return { Earned = earned, New = new }
end

function ProgressionService.Init()
	local function onPlayer(player: Player)
		task.spawn(function()
			if Services.DataService.WaitFor(player, 15) then
				ProgressionService.Publish(player)
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
