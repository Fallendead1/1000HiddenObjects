--[[
	Keeps a session going (RetentionConfig):
	  Playtime gifts  active minutes today (UTC) fill a ladder of gifts the player opens (ClaimGift)
	  Gift bar        every few objects cleaned into bins pays a small gift, straight away
	  Firsts          first-time moments pay once per player
	  Daily spin      one free spin a day (SpinWheel); the odds are shown on the wheel
	  Streak freeze   one missed day a week keeps the login streak (ProgressionService asks)
	  Friend bonus    more room Cash with a friend in the party (MatchService sets it up)
	  Notify question asked once, after the first room (NotifyAnswered)
	  Paid helpers    Lift It Now, Junk Blaster and Treasure Radar (MonetizationService grants)

	Attributes: PlaytimeSeconds, GiftsClaimed, PlaytimeResetAt, GiftBarCount, GiftBarNeed,
	  SpinReady, SpinResetAt, Firsts (comma list), FriendBonus, LiftWeight, LiftExpires,
	  TreasureRadar (match id), BlasterCharges.
	FX events: GiftOpened { Index, Text, Color }, GiftBar { Text, Level }, FirstReward { Key,
	  Title, Text }, SpinResult { Index, Text }, Blasted { Count }.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local GameConfig = require(Shared.Config.GameConfig)
local RetentionConfig = require(Shared.Config.RetentionConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)
local TableUtil = require(Shared.Utility.TableUtil)

local Services = require(script.Parent)

local RetentionService = {}

type State = { LastActive: number, LastPos: Vector3? }

local states: { [Player]: State } = {}
local lastTooHeavy: { [Player]: number } = {}
local limiter = RateLimiter.new(2, 3)
local rng = Random.new()

local FirstsByKey = {}
for _, def in ipairs(RetentionConfig.Firsts) do
	FirstsByKey[def.Key] = def
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function today(): number
	return math.floor(now() / 86400)
end

-- Weeks start on Monday (UTC day 0 was a Thursday).
function RetentionService.Week(day: number): number
	return (day + 3) // 7
end

-- ===== Rewards =====

-- A reward's words, e.g. "$50 Cash + 100 XP".
function RetentionService.RewardText(reward): string
	local parts = {}
	if reward.Cash then
		table.insert(parts, string.format("$%d Cash", reward.Cash))
	end
	if reward.XP then
		table.insert(parts, string.format("+%d XP", reward.XP))
	end
	if reward.Hint then
		table.insert(parts, reward.Hint == "SuperHint" and "Super Hint" or "Quick Hint")
	end
	if reward.Boost then
		table.insert(parts, string.format("%d min 2X %s", math.floor((reward.Seconds or 0) / 60), reward.Boost == "CashBoost" and "Cash" or "Strength"))
	end
	if reward.Egg then
		table.insert(parts, reward.Egg .. " Egg")
	end
	return table.concat(parts, " + ")
end

-- Gives a reward (see RetentionConfig). Hints and boosts are saved for the room (and used at
-- once when the player is already searching one). `quietCash` skips the wallet count-up (the
-- spin wheel reveals its own result).
function RetentionService.Grant(player: Player, reward, source: string, sku: string, quietCash: boolean?)
	if reward.Cash then
		Services.WalletService.Add(player, reward.Cash, source, sku, quietCash)
	end
	if reward.XP then
		Services.ProgressionService.GiveXP(player, reward.XP, "Gift")
	end
	if reward.Hint or reward.Boost then
		Services.DataService.Update(player, function(data)
			if reward.Hint then
				data.Banked[reward.Hint] = (data.Banked[reward.Hint] or 0) + 1
			end
			if reward.Boost then
				data.Banked[reward.Boost] = (data.Banked[reward.Boost] or 0) + (reward.Seconds or 0)
			end
		end)
		local match = Services.MatchService.GetMatchForPlayer(player)
		if match and match.State == "Searching" then
			Services.MonetizationService.ApplyBanked(player)
		end
	end
	if reward.Egg and script.Parent:FindFirstChild("PetService") then
		Services.PetService.GrantEgg(player, reward.Egg, sku)
	end
end

-- ===== Attributes =====

local function giftNeed(level: number): number
	local bar = RetentionConfig.GiftBar
	return math.min(bar.FirstNeed + level * bar.NeedStep, bar.MaxNeed)
end

function RetentionService.Publish(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local day = today()
	player:SetAttribute("PlaytimeSeconds", data.Playtime.Seconds)
	player:SetAttribute("GiftsClaimed", data.Playtime.Claimed)
	player:SetAttribute("PlaytimeResetAt", (day + 1) * 86400)
	player:SetAttribute("GiftBarCount", data.GiftBar.Count)
	player:SetAttribute("GiftBarNeed", giftNeed(data.GiftBar.Level))
	player:SetAttribute("SpinReady", data.Spin.Day ~= day)
	player:SetAttribute("SpinResetAt", (day + 1) * 86400)
	player:SetAttribute("BlasterCharges", data.Banked.JunkBlaster or 0)
	local firsts = TableUtil.Keys(data.Firsts)
	table.sort(firsts)
	player:SetAttribute("Firsts", table.concat(firsts, ","))
end

-- ===== Playtime gifts =====

-- A new UTC day: yesterday's ready-but-unopened gifts are given, then the ladder starts over.
local function rollDay(player: Player, data)
	local day = today()
	local pt = data.Playtime
	if pt.Day == day then
		return
	end
	if pt.Day ~= 0 then
		for i = pt.Claimed + 1, #RetentionConfig.PlaytimeGifts do
			local gift = RetentionConfig.PlaytimeGifts[i]
			if pt.Seconds >= gift.Minutes * 60 then
				RetentionService.Grant(player, gift.Reward, "TimedReward", "PlaytimeGift" .. i)
			end
		end
	end
	data.Playtime = { Day = day, Seconds = 0, Claimed = 0 }
	Services.DataService.MarkDirty(player)
	RetentionService.Publish(player)
end

-- Anything the player does keeps them active for the playtime gifts.
function RetentionService.Touch(player: Player)
	local st = states[player]
	if st then
		st.LastActive = os.clock()
	end
end

local function claimGift(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	rollDay(player, data)
	local index = data.Playtime.Claimed + 1
	local gift = RetentionConfig.PlaytimeGifts[index]
	if not gift or data.Playtime.Seconds < gift.Minutes * 60 then
		return
	end
	Services.DataService.Update(player, function(d)
		d.Playtime.Claimed = index
	end)
	RetentionService.Grant(player, gift.Reward, "TimedReward", "PlaytimeGift" .. index)
	Remotes.Event("FXEvent"):FireClient(player, "GiftOpened", { Index = index, Text = gift.Text, Color = gift.Color })
	Services.AnalyticsService.Event(player, "gift_opened", index, string.format("%d min", gift.Minutes), player:GetAttribute("InMatch") and "room" or "lobby")
	RetentionService.Publish(player)
	task.spawn(Services.DataService.Save, player)
end

-- ===== Gift bar and firsts =====

function RetentionService.OnDeposit(player: Player, info: { Swish: boolean, Streak: number, Treasure: boolean })
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	RetentionService.Touch(player)
	RetentionService.First(player, "Deposit")
	if info.Swish then
		RetentionService.First(player, "Swish")
	end
	if info.Treasure then
		RetentionService.First(player, "Treasure")
	end
	if (info.Streak or 0) >= 5 then
		RetentionService.First(player, "Streak5")
	end
	local bar = RetentionConfig.GiftBar
	local level = data.GiftBar.Level
	local count = data.GiftBar.Count + 1
	if count >= giftNeed(level) then
		count = 0
		level += 1
		local cash = math.min(bar.CashBase + (level - 1) * bar.CashStep, bar.MaxCash)
		Services.DataService.Update(player, function(d)
			d.GiftBar = { Count = 0, Level = level }
		end)
		RetentionService.Grant(player, { Cash = cash, XP = bar.XP }, "Gameplay", "GiftBar")
		Remotes.Event("FXEvent"):FireClient(player, "GiftBar", { Text = string.format("$%d Cash", cash), Level = level })
		Services.AnalyticsService.Event(player, "gift_bar", level, string.format("$%d", cash))
	else
		data.GiftBar.Count = count
		Services.DataService.MarkDirty(player)
	end
	player:SetAttribute("GiftBarCount", count)
	player:SetAttribute("GiftBarNeed", giftNeed(level))
end

-- A first-time moment (RetentionConfig.Firsts): rewarded once per player.
function RetentionService.First(player: Player, key: string)
	local def = FirstsByKey[key]
	local data = Services.DataService.Get(player)
	if not def or not data or data.Firsts[key] then
		return
	end
	Services.DataService.Update(player, function(d)
		d.Firsts[key] = true
	end)
	RetentionService.Grant(player, def.Reward, "Onboarding", "First" .. key)
	Remotes.Event("FXEvent"):FireClient(player, "FirstReward", { Key = key, Title = def.Title, Text = RetentionService.RewardText(def.Reward) })
	Services.AnalyticsService.Event(player, "first_reward", 1, key)
	RetentionService.Publish(player)
end

-- ===== Daily spin =====

function RetentionService.SpinOdds(): { number }
	local total = 0
	for _, s in ipairs(RetentionConfig.Spin) do
		total += s.Weight
	end
	local odds = {}
	for i, s in ipairs(RetentionConfig.Spin) do
		odds[i] = s.Weight / total
	end
	return odds
end

local function spin(player: Player)
	local data = Services.DataService.Get(player)
	local day = today()
	if not data or data.Spin.Day == day then
		return
	end
	local total = 0
	for _, s in ipairs(RetentionConfig.Spin) do
		total += s.Weight
	end
	local roll = rng:NextNumber() * total
	local index = #RetentionConfig.Spin
	for i, s in ipairs(RetentionConfig.Spin) do
		roll -= s.Weight
		if roll <= 0 then
			index = i
			break
		end
	end
	local segment = RetentionConfig.Spin[index]
	Services.DataService.Update(player, function(d)
		d.Spin.Day = day
	end)
	RetentionService.Grant(player, segment.Reward, "TimedReward", "DailySpin", true)
	Remotes.Event("FXEvent"):FireClient(player, "SpinResult", { Index = index, Text = segment.Text })
	Services.AnalyticsService.Event(player, "daily_spin", index, segment.Text)
	RetentionService.Publish(player)
	task.spawn(Services.DataService.Save, player)
end

-- ===== Streak freeze (ProgressionService) =====

function RetentionService.FreezeReady(data, day: number): boolean
	return (data.Login.FreezeWeek or 0) ~= RetentionService.Week(day)
end

function RetentionService.UseFreeze(data, day: number)
	data.Login.FreezeWeek = RetentionService.Week(day)
end

-- ===== Friend bonus =====

-- Everyone with a friend in the party earns EconomyConfig.FriendBonus more room Cash.
function RetentionService.SetupFriendBonus(players: { Player })
	for _, player in ipairs(players) do
		player:SetAttribute("FriendBonus", false)
	end
	if #players < 2 then
		return
	end
	for _, player in ipairs(players) do
		task.spawn(function()
			for _, other in ipairs(players) do
				if other ~= player then
					local ok, friends = pcall(player.IsFriendsWith, player, other.UserId)
					if ok and friends then
						player:SetAttribute("FriendBonus", true)
						Services.NotificationService.Send(player, "Success", string.format("Playing with a friend: +%d%% Cash!", math.floor(EconomyConfig.FriendBonus * 100 + 0.5)))
						return
					end
				end
			end
		end)
	end
end

function RetentionService.CashMultiplier(player: Player): number
	return player:GetAttribute("FriendBonus") == true and (1 + EconomyConfig.FriendBonus) or 1
end

-- ===== Paid helpers =====

-- A grab was refused as too heavy: Lift It Now (bought now, or saved from before) lifts it.
function RetentionService.NoteTooHeavy(player: Player, weight: number)
	lastTooHeavy[player] = weight
	local data = Services.DataService.Get(player)
	if data and (data.Banked.LiftItNow or 0) > 0 and weight <= GameConfig.MaxWeightCap then
		Services.DataService.Update(player, function(d)
			d.Banked.LiftItNow -= 1
		end)
		RetentionService.ActivateLift(player)
		Services.NotificationService.Send(player, "Premium", "Your saved LIFT IT NOW is on - grab it!")
	end
end

function RetentionService.ActivateLift(player: Player)
	local maxWeight = player:GetAttribute("MaxWeight") or 2
	local weight = math.clamp(math.max(lastTooHeavy[player] or 0, maxWeight + 1), 1, GameConfig.MaxWeightCap)
	local t = now()
	if (player:GetAttribute("LiftExpires") or 0) > t then
		weight = math.max(weight, player:GetAttribute("LiftWeight") or 0)
	end
	player:SetAttribute("LiftWeight", weight)
	player:SetAttribute("LiftExpires", t + RetentionConfig.LiftItNowSeconds)
	Services.PlayerSessionService.RecomputeDerived(player)
end

local function xzDistance(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Bursts the packed junk around the player. Never the junk near the hidden object, and the same
-- amount is left around a few other hiding spots, so what stays packed gives nothing away.
-- Returns how many burst (nil: not searching a room right now).
function RetentionService.Blast(player: Player): number?
	local match = Services.MatchService.GetMatchForPlayer(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not match or match.State ~= "Searching" or not root then
		return nil
	end
	local offer = RetentionConfig.Offers.JunkBlaster
	local here = root.Position
	local keep: { Vector3 } = {}
	if match.TargetSocket and not match.TargetRevealed then
		table.insert(keep, match.TargetSocket.Position)
	end
	local nearby = {}
	for _, socket in ipairs(match.Runtime.SocketList or {}) do
		if socket ~= match.TargetSocket and xzDistance(socket.Position, here) <= offer.Radius + RetentionConfig.BlasterSafeRadius then
			table.insert(nearby, socket)
		end
	end
	TableUtil.Shuffle(nearby, rng)
	for i = 1, math.min(RetentionConfig.BlasterDecoys, #nearby) do
		table.insert(keep, nearby[i].Position)
	end
	local chunks = {}
	for _, obj in ipairs(match.Runtime.Objects) do
		if obj.Parent and obj:GetAttribute("IsChunk") and obj ~= match.KeyChunk and not Services.ObjectService.IsBusy(obj) then
			local d = xzDistance(obj.Position, here)
			if d <= offer.Radius and math.abs(obj.Position.Y - here.Y) <= 10 then
				local safe = false
				for _, p in ipairs(keep) do
					if xzDistance(obj.Position, p) < RetentionConfig.BlasterSafeRadius then
						safe = true
						break
					end
				end
				if not safe then
					table.insert(chunks, { Root = obj, Distance = d })
				end
			end
		end
	end
	table.sort(chunks, function(a, b)
		return a.Distance < b.Distance
	end)
	local count = math.min(#chunks, RetentionConfig.BlasterMaxBursts)
	task.spawn(function()
		for i = 1, count do
			local chunk = chunks[i].Root
			if chunk.Parent and not Services.ObjectService.IsBusy(chunk) then
				Services.ChunkService.Burst(chunk, player)
			end
			task.wait(0.08)
		end
	end)
	Remotes.Event("FXEvent"):FireClient(player, "Blasted", { Count = count, Position = here })
	Services.AnalyticsService.Event(player, "junk_blaster", count)
	return count
end

-- Treasure Radar for the player's current room.
function RetentionService.ActivateRadar(player: Player): boolean
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match then
		return false
	end
	player:SetAttribute("TreasureRadar", match.Id)
	return true
end

-- ===== Lifecycle =====

function RetentionService.Init()
	Remotes.Event("ClaimGift").OnServerEvent:Connect(function(player)
		if limiter:Allow(player) then
			RetentionService.Touch(player)
			claimGift(player)
		end
	end)
	Remotes.Event("SpinWheel").OnServerEvent:Connect(function(player)
		if limiter:Allow(player) then
			RetentionService.Touch(player)
			spin(player)
		end
	end)
	Remotes.Event("UseBlaster").OnServerEvent:Connect(function(player)
		local data = Services.DataService.Get(player)
		if not limiter:Allow(player) or not data or (data.Banked.JunkBlaster or 0) <= 0 then
			return
		end
		if RetentionService.Blast(player) then
			Services.DataService.Update(player, function(d)
				d.Banked.JunkBlaster -= 1
			end)
			RetentionService.Publish(player)
		end
	end)
	Remotes.Event("NotifyAnswered").OnServerEvent:Connect(function(player, answer)
		local data = Services.DataService.Get(player)
		if not limiter:Allow(player) or not data or data.NotifyAsked then
			return
		end
		if type(answer) ~= "string" or not table.find({ "allowed", "denied", "no" }, answer) then
			return
		end
		Services.DataService.Update(player, function(d)
			d.NotifyAsked = true
		end)
		Services.AnalyticsService.Event(player, "notify_optin", 1, answer)
	end)

	local function onPlayer(player: Player)
		states[player] = { LastActive = os.clock() }
		task.spawn(function()
			local data = Services.DataService.WaitFor(player, 15)
			if data then
				rollDay(player, data)
				RetentionService.Publish(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		lastTooHeavy[player] = nil
	end)
end

function RetentionService.Start()
	-- Active playtime: a second counts while the player moved or did something recently.
	task.spawn(function()
		while true do
			task.wait(1)
			local clock = os.clock()
			for player, st in pairs(states) do
				local data = Services.DataService.Get(player)
				if data then
					rollDay(player, data)
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root then
						local pos = root.Position
						if st.LastPos and (pos - st.LastPos).Magnitude > 1 then
							st.LastActive = clock
						end
						st.LastPos = pos
					end
					if clock - st.LastActive <= RetentionConfig.ActiveWindow then
						data.Playtime.Seconds += 1
						Services.DataService.MarkDirty(player)
						player:SetAttribute("PlaytimeSeconds", data.Playtime.Seconds)
					end
				end
			end
		end
	end)
end

return RetentionService
