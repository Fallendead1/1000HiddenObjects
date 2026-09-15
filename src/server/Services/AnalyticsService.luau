--[[
	Game analytics: every event the game sends to Roblox goes through here. Roblox only records
	events sent by a server of the published game (never from Studio or a client), so in Studio
	each one is printed instead ("[Analytics] ..."), and UI-only moments (menus opened, shop tabs,
	frame rate, invites) come from the client over the whitelisted Track remote.

	Where it shows in Creator Hub > Analytics (charts fill in within about 24 hours):
	  Funnels      Onboarding (brand-new players), Tutorial, RoomRun, Party, Shop, DailyReward
	  Economy      Cash (earned per bin, spent per upgrade) and XP (earned per reason), batched
	  Progression  Rooms (started / finished / abandoned) and CleanerLevel (level ups)
	  Explore      custom events with up to 3 detail fields each
	Nothing here can break gameplay: every call to Roblox is guarded.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxAnalytics = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local AnalyticsConfig = require(Shared.Config.AnalyticsConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local AnalyticsService = {}

local STUDIO = RunService:IsStudio()
local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}

type Room = { MatchId: string, RoomId: number, RoomName: string, Started: number, Counts: { [string]: number }, BestStreak: number, Cash: number, FirstDeposit: boolean, Ended: boolean }
type Session = { Joined: number, New: boolean, Tutorial: boolean, ShopId: string?, PartyId: string?, Room: Room?, Teleporting: boolean, Onboarding: { [number]: boolean }, FpsReports: number }

local serverRole = "Combined"
local sessions: { [Player]: Session } = {}
local economy: { [Player]: { [string]: any } } = {}
local trackLimiter = RateLimiter.new(1, 12)
local warned: { [string]: boolean } = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

local function fields(a: any?, b: any?, c: any?): { [string]: string }?
	local t = {}
	if a ~= nil then
		t[FIELD_KEYS[1]] = tostring(a)
	end
	if b ~= nil then
		t[FIELD_KEYS[2]] = tostring(b)
	end
	if c ~= nil then
		t[FIELD_KEYS[3]] = tostring(c)
	end
	return if next(t) ~= nil then t else nil
end

local function describe(a: any?, b: any?, c: any?): string
	local parts = {}
	for _, v in ipairs({ a == nil and "" or tostring(a), b == nil and "" or tostring(b), c == nil and "" or tostring(c) }) do
		if v ~= "" then
			table.insert(parts, v)
		end
	end
	return #parts > 0 and ("[" .. table.concat(parts, " | ") .. "]") or ""
end

-- Sends one event to Roblox (prints it in Studio instead). Never throws.
local function send(kind: string, text: string, fn: () -> ())
	if STUDIO then
		print("[Analytics] " .. kind .. ": " .. text)
		return
	end
	local ok, err = pcall(fn)
	if not ok and not warned[kind] then
		warned[kind] = true
		warn("[Analytics] " .. kind .. " failed: " .. tostring(err))
	end
end

-- ===== Low-cardinality detail values (dashboards group by them) =====

local function percentBucket(p: number?): string
	local pct = (p or 0) * 100
	if pct < 5 then
		return "0-5%"
	elseif pct < 10 then
		return "5-10%"
	elseif pct < 25 then
		return "10-25%"
	elseif pct < 50 then
		return "25-50%"
	elseif pct < 75 then
		return "50-75%"
	end
	return "75-100%"
end

local function timeBucket(seconds: number): string
	local m = seconds / 60
	if m < 2 then
		return "under 2 min"
	elseif m < 5 then
		return "2-5 min"
	elseif m < 10 then
		return "5-10 min"
	elseif m < 20 then
		return "10-20 min"
	end
	return "20+ min"
end

local function streakBucket(n: number): string
	if n <= 1 then
		return "no streak"
	elseif n <= 3 then
		return "streak 2-3"
	elseif n <= 5 then
		return "streak 4-5"
	end
	return "streak 6+"
end

local function partyLabel(n: number?): string
	return (n or 1) <= 1 and "solo" or ("party of " .. tostring(n))
end

local function where(player: Player): string
	return player:GetAttribute("InMatch") == true and "room" or "lobby"
end

-- ===== The five kinds of event =====

-- A custom event (Explore page): one number plus up to 3 detail fields.
function AnalyticsService.Event(player: Player?, name: string, value: number?, a: any?, b: any?, c: any?)
	if not player or not player.Parent then
		return
	end
	local v = tonumber(value) or 1
	send("event", string.format("%s  %s = %s  %s", name, player.Name, tostring(v), describe(a, b, c)), function()
		RobloxAnalytics:LogCustomEvent(player, name, v, fields(a, b, c))
	end)
end

-- The new-player funnel: brand-new players only, each step once.
function AnalyticsService.Onboarding(player: Player, key: string)
	local s = sessions[player]
	local step = AnalyticsConfig.Onboarding.Index[key]
	if not s or not s.New or not step or s.Onboarding[step] then
		return
	end
	s.Onboarding[step] = true
	local name = AnalyticsConfig.Onboarding.Steps[step].Name
	send("onboarding", string.format("%s  step %d  %s", player.Name, step, name), function()
		RobloxAnalytics:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- A step in one of the recurring funnels.
function AnalyticsService.Funnel(player: Player, funnel: string, sessionId: string?, key: string, a: any?, b: any?, c: any?)
	local def = AnalyticsConfig.Funnels[funnel]
	local step = def and def.Index[key]
	if not step or not sessionId or not player.Parent then
		return
	end
	local name = def.Steps[step].Name
	send("funnel", string.format("%s  %s  step %d  %s  %s", funnel, player.Name, step, name, describe(a, b, c)), function()
		RobloxAnalytics:LogFunnelStepEvent(player, funnel, sessionId, step, name, fields(a, b, c))
	end)
end

-- Cash / XP earned (Source) or spent (Sink). The same kind of transaction is summed per player and
-- sent every EconomyFlushSeconds, and when they finish a room or leave the server.
function AnalyticsService.Economy(player: Player, flow: string, currency: string, amount: number, balance: number, transaction: string, sku: string, a: any?, b: any?, c: any?)
	if not amount or amount <= 0 then
		return
	end
	local bucket = economy[player]
	if not bucket then
		bucket = {}
		economy[player] = bucket
	end
	local key = table.concat({ flow, currency, transaction, sku, tostring(a), tostring(b), tostring(c) }, "|")
	local e = bucket[key]
	if e then
		e.Amount += amount
		e.Balance = balance
	else
		bucket[key] = { Flow = flow, Currency = currency, Amount = amount, Balance = balance, Transaction = transaction, Sku = sku, A = a, B = b, C = c }
	end
end

local function flushEconomy(player: Player)
	local bucket = economy[player]
	economy[player] = nil
	if not bucket or not player.Parent then
		return
	end
	for _, e in pairs(bucket) do
		send("economy", string.format("%s  %s %s %s  %s via %s  balance %s  %s", player.Name, e.Flow, tostring(e.Amount), e.Currency, e.Sku, e.Transaction, tostring(e.Balance), describe(e.A, e.B, e.C)), function()
			RobloxAnalytics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType[e.Flow], e.Currency, e.Amount, e.Balance, Enum.AnalyticsEconomyTransactionType[e.Transaction].Name, e.Sku, fields(e.A, e.B, e.C))
		end)
	end
end

-- Progression paths: Rooms (Start / Complete / Fail) and CleanerLevel (Complete per level).
function AnalyticsService.Progression(player: Player, path: string, status: string, level: number, levelName: string?, a: any?, b: any?, c: any?)
	if not player.Parent then
		return
	end
	send("progression", string.format("%s  %s %s  level %s %s  %s", player.Name, path, status, tostring(level), tostring(levelName), describe(a, b, c)), function()
		RobloxAnalytics:LogProgressionEvent(player, path, Enum.AnalyticsProgressionType[status], level, levelName, fields(a, b, c))
	end)
end

function AnalyticsService.NewId(): string
	return HttpService:GenerateGUID(false)
end

-- ===== Rooms =====

local function activeRoom(player: Player): Room?
	local s = sessions[player]
	local r = s and s.Room
	return if r and not r.Ended then r else nil
end

local function count(player: Player, key: string, n: number?)
	local r = activeRoom(player)
	if r then
		r.Counts[key] = (r.Counts[key] or 0) + (n or 1)
	end
end

local function tutorialStep(player: Player, key: string)
	local s = sessions[player]
	if s and s.Tutorial then
		AnalyticsService.Funnel(player, "Tutorial", "tutorial", key)
	end
end

-- SEARCH! Everyone in the room starts a run.
function AnalyticsService.RoomStarted(match, loadSeconds: number)
	local party = partyLabel(match.PartySize)
	local hard = match.Hard and "hard" or "normal"
	local resume = (match.ResumePercent or 0) > 0 and ("resumed " .. percentBucket(match.ResumePercent)) or "fresh"
	for _, player in ipairs(match.Players) do
		local s = sessions[player]
		if s then
			s.Room = { MatchId = match.Id, RoomId = match.RoomId, RoomName = match.Config.Name, Started = os.clock(), Counts = {}, BestStreak = 0, Cash = 0, FirstDeposit = false, Ended = false }
			AnalyticsService.Funnel(player, "RoomRun", match.Id, "Started", "room " .. tostring(match.RoomId), party, hard)
			AnalyticsService.Progression(player, "Rooms", "Start", match.RoomId, match.Config.Name, party, hard, resume)
			AnalyticsService.Event(player, "room_start", match.RoomId, party, hard, resume)
			AnalyticsService.Event(player, "room_load_seconds", math.floor(loadSeconds * 10 + 0.5) / 10, party, serverRole)
			AnalyticsService.Onboarding(player, "RoomLoaded")
			tutorialStep(player, "RoomLoaded")
			local partyId = (match.PartySessions and match.PartySessions[tostring(player.UserId)]) or s.PartyId
			if partyId then
				AnalyticsService.Funnel(player, "Party", partyId, "Arrived", party)
			end
			s.PartyId = nil
			-- Rooms started, ever: a second one completes the new-player funnel.
			local rooms = 0
			Services.DataService.Update(player, function(d)
				d.Stats.Rooms = (d.Stats.Rooms or 0) + 1
				rooms = d.Stats.Rooms
			end)
			if rooms >= 2 then
				AnalyticsService.Onboarding(player, "SecondRoom")
			end
		end
	end
end

-- A player is done with a room: why, how long, how clean, and everything they did in it.
-- reason: found / exit_door / left_game.
function AnalyticsService.RoomEnded(player: Player, reason: string, match)
	local s = sessions[player]
	local r = s and s.Room
	if not r or r.Ended then
		return
	end
	r.Ended = true
	local progress = match and match.Progress or 0
	local party = partyLabel(match and match.PartySize)
	AnalyticsService.Event(player, "room_end", math.floor((os.clock() - r.Started) / 6) / 10, reason, percentBucket(progress), party)
	AnalyticsService.Event(player, "room_cleaned_percent", math.floor(progress * 1000 + 0.5) / 10, reason, party)
	for _, key in ipairs(AnalyticsConfig.RoomCounts) do
		AnalyticsService.Event(player, "room_" .. key, r.Counts[key] or 0, reason)
	end
	AnalyticsService.Event(player, "room_best_streak", r.BestStreak, reason)
	AnalyticsService.Event(player, "room_cash_earned", r.Cash, reason)
	if reason ~= "found" then
		AnalyticsService.Progression(player, "Rooms", "Fail", r.RoomId, r.RoomName, reason, percentBucket(progress))
	end
	flushEconomy(player)
end

function AnalyticsService.KeyUncovered(match, seconds: number)
	for _, player in ipairs(match.Players) do
		AnalyticsService.Funnel(player, "RoomRun", match.Id, "KeyUncovered")
		AnalyticsService.Event(player, "key_uncovered", math.floor(seconds), partyLabel(match.PartySize), "hint stage " .. tostring(match.HintStage or 0), percentBucket(match.Progress))
	end
end

function AnalyticsService.KeyFound(match, finder: Player, seconds: number)
	for _, player in ipairs(match.Players) do
		AnalyticsService.Funnel(player, "RoomRun", match.Id, "KeyFound")
		AnalyticsService.Progression(player, "Rooms", "Complete", match.RoomId, match.Config.Name, player == finder and "finder" or "teammate", timeBucket(seconds), partyLabel(match.PartySize))
		AnalyticsService.Onboarding(player, "FoundKey")
		AnalyticsService.RoomEnded(player, "found", match)
	end
	AnalyticsService.Event(finder, "key_found", math.floor(seconds), partyLabel(match.PartySize), "hint stage " .. tostring(match.HintStage or 0), percentBucket(match.Progress))
end

-- ===== Room actions =====

function AnalyticsService.Grabbed(player: Player)
	count(player, "grabs")
	AnalyticsService.Onboarding(player, "FirstGrab")
	tutorialStep(player, "Grab")
end

function AnalyticsService.Threw(player: Player)
	count(player, "throws")
	AnalyticsService.Onboarding(player, "FirstThrow")
end

-- One object into a bin: tallies, Cash earned, the first-deposit steps.
function AnalyticsService.Deposited(player: Player, info: { Amount: number, BinType: string, Match: boolean, Swish: boolean, Streak: number, Treasure: boolean, Balance: number })
	count(player, "deposits")
	if info.Swish then
		count(player, "swishes")
	end
	if info.Treasure then
		count(player, "treasures")
	end
	local r = activeRoom(player)
	if r then
		r.BestStreak = math.max(r.BestStreak, info.Streak or 0)
		r.Cash += info.Amount or 0
		if not r.FirstDeposit then
			r.FirstDeposit = true
			AnalyticsService.Funnel(player, "RoomRun", r.MatchId, "FirstDeposit")
		end
	end
	AnalyticsService.Onboarding(player, "FirstDeposit")
	tutorialStep(player, "Deposit")
	AnalyticsService.Economy(player, "Source", "Cash", info.Amount or 0, info.Balance or 0, "Gameplay", info.Treasure and "Treasure" or ("Bin_" .. tostring(info.BinType)),
		info.Match and "right bin (x2)" or "other bin (x1)", info.Swish and "swish" or "normal", streakBucket(info.Streak or 1))
end

function AnalyticsService.ChunkBurst(player: Player)
	count(player, "chunks")
end

function AnalyticsService.Upgraded(player: Player, key: string, level: number, cost: number, free: boolean, balance: number)
	count(player, "upgrades")
	AnalyticsService.Event(player, "upgrade_bought", level, key, free and "free" or "paid")
	if not free then
		AnalyticsService.Economy(player, "Sink", "Cash", cost, balance, "Shop", "Upgrade_" .. key, "Lv" .. tostring(level))
	end
	tutorialStep(player, "Upgrade")
end

-- A clue given: free milestone clues reach the whole team, paid ones count for the buyer.
function AnalyticsService.Clue(players: { Player }, stage: number, source: string, progress: number?)
	for _, player in ipairs(players) do
		count(player, "hints")
		AnalyticsService.Event(player, "hint_clue", stage, source, percentBucket(progress))
	end
end

-- ===== Lobby: parties, shop, rewards, progression =====

function AnalyticsService.PartyStep(player: Player, partyId: string?, key: string, a: any?, b: any?, c: any?)
	if not partyId then
		return
	end
	local s = sessions[player]
	if s then
		s.PartyId = partyId
	end
	AnalyticsService.Funnel(player, "Party", partyId, key, a, b, c)
	if key == "EnteredCircle" then
		AnalyticsService.Onboarding(player, "EnteredCircle")
		tutorialStep(player, "Circle")
	elseif key == "Ready" then
		AnalyticsService.Onboarding(player, "PartyReady")
		tutorialStep(player, "Party")
	end
end

-- The party ids travel with the teleport so the match server can finish each Party funnel.
function AnalyticsService.PartySessions(players: { Player }): { [string]: string }
	local map = {}
	for _, p in ipairs(players) do
		local s = sessions[p]
		if s and s.PartyId then
			map[tostring(p.UserId)] = s.PartyId
		end
	end
	return map
end

function AnalyticsService.ShopOpened(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	s.ShopId = HttpService:GenerateGUID(false)
	AnalyticsService.Funnel(player, "Shop", s.ShopId, "Opened", where(player))
end

function AnalyticsService.PurchasePrompted(player: Player, key: string, kind: string)
	local s = sessions[player]
	if s and not s.ShopId then
		s.ShopId = HttpService:GenerateGUID(false)
	end
	AnalyticsService.Funnel(player, "Shop", s and s.ShopId, "Prompted", key, kind, where(player))
	AnalyticsService.Event(player, "purchase_prompt", 1, key, kind, where(player))
end

function AnalyticsService.Purchased(player: Player, key: string, kind: string, robux: number?)
	local s = sessions[player]
	AnalyticsService.Funnel(player, "Shop", s and s.ShopId, "Bought", key, kind, where(player))
	AnalyticsService.Event(player, "purchase_done", robux or 0, key, kind, where(player))
end

function AnalyticsService.PurchaseCancelled(player: Player, key: string, kind: string)
	AnalyticsService.Event(player, "purchase_cancel", 1, key, kind, where(player))
end

function AnalyticsService.DailyStep(player: Player, key: string, a: any?)
	AnalyticsService.Funnel(player, "DailyReward", "day " .. tostring(today()), key, a)
end

function AnalyticsService.XP(player: Player, amount: number, reason: string, total: number)
	AnalyticsService.Economy(player, "Source", "XP", amount, total, reason == "Daily" and "TimedReward" or "Gameplay", reason)
end

function AnalyticsService.LevelUp(player: Player, level: number, title: string)
	AnalyticsService.Progression(player, "CleanerLevel", "Complete", level, title)
	AnalyticsService.Event(player, "level_up", level, title, where(player))
end

function AnalyticsService.TutorialFinished(player: Player)
	local s = sessions[player]
	if s and s.Tutorial then
		AnalyticsService.Funnel(player, "Tutorial", "tutorial", "Finished")
		s.Tutorial = false
	end
end

-- Teleports end the server's copy of a session without the player leaving the game.
function AnalyticsService.MarkTeleport(player: Player)
	local s = sessions[player]
	if s then
		s.Teleporting = true
	end
end

function AnalyticsService.ClearTeleport(player: Player)
	local s = sessions[player]
	if s then
		s.Teleporting = false
	end
end

-- Older call sites: a plain custom event without detail fields.
function AnalyticsService.Log(eventName: string, player: Player?, params: { [string]: any }?)
	AnalyticsService.Event(player, eventName, params and tonumber(params.Value) or 1)
end

-- ===== Sessions =====

local function onPlayer(player: Player)
	local data = Services.DataService.WaitFor(player, 20)
	if not player.Parent then
		return
	end
	local firstDay = data and data.FirstJoinDay or 0
	local s: Session = {
		Joined = os.clock(),
		-- Studio-only: workspace attribute DevNewPlayer tests the new-player funnel.
		New = (STUDIO and workspace:GetAttribute("DevNewPlayer") == true) or (firstDay > 0 and today() - firstDay <= AnalyticsConfig.OnboardingDays),
		Tutorial = data ~= nil and data.TutorialCompleted ~= true,
		Teleporting = false,
		Onboarding = {},
		FpsReports = 0,
	}
	sessions[player] = s
	-- A match server continues the session the lobby started.
	if serverRole ~= "Match" then
		AnalyticsService.Onboarding(player, "Joined")
		if s.Tutorial then
			AnalyticsService.Funnel(player, "Tutorial", "tutorial", "Started")
		end
	end
end

local function onLeaving(player: Player)
	local s = sessions[player]
	if s then
		if s.Room and not s.Room.Ended then
			AnalyticsService.RoomEnded(player, s.Teleporting and "back_to_lobby" or "left_game", Services.MatchService.GetMatch())
		end
		if not s.Teleporting then
			AnalyticsService.Event(player, "left_game", math.floor((os.clock() - s.Joined) / 6) / 10, where(player), s.Tutorial and "in tutorial" or "after tutorial", s.New and "new player" or "returning")
		end
	end
	flushEconomy(player)
	sessions[player] = nil
	trackLimiter:Clear(player)
end

function AnalyticsService.Init(role: string)
	serverRole = role
	-- UI-only moments from the client (AnalyticsController). Whitelisted and rate limited.
	Remotes.Event("Track").OnServerEvent:Connect(function(player, kind, value, extra)
		if type(kind) ~= "string" or not trackLimiter:Allow(player) then
			return
		end
		local s = sessions[player]
		if kind == "menu" and type(value) == "string" and #value <= 24 and value:match("^%a+$") then
			AnalyticsService.Event(player, "menu_open", 1, value, where(player))
			if value == "Shop" then
				AnalyticsService.ShopOpened(player)
			elseif value == "Daily" and player:GetAttribute("LoginClaimable") == true then
				AnalyticsService.DailyStep(player, "Opened")
			end
		elseif kind == "shop_tab" and type(value) == "string" and AnalyticsConfig.ShopTabs[value] then
			AnalyticsService.Event(player, "shop_tab", 1, value, where(player))
		elseif kind == "fps" and type(value) == "number" and value == value and s and s.FpsReports < AnalyticsConfig.FpsReportsPerSession then
			s.FpsReports += 1
			local device = type(extra) == "string" and AnalyticsConfig.Platforms[extra] and extra or "unknown"
			AnalyticsService.Event(player, "fps", math.clamp(math.floor(value + 0.5), 1, 240), device, where(player))
		elseif kind == "invite" then
			AnalyticsService.Event(player, "invite_prompt", 1, where(player))
		end
	end)
end

function AnalyticsService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayer, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(onLeaving)
	task.spawn(function()
		while true do
			task.wait(AnalyticsConfig.EconomyFlushSeconds)
			for player in pairs(economy) do
				flushEconomy(player)
			end
		end
	end)
end

return AnalyticsService
