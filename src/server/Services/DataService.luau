--[[
	Persistent player profiles. Loads on join, caches for the session, saves on important
	events, on leave and on server close. Falls back to memory when DataStores are unavailable
	(e.g. Studio without API access) so the game stays testable.

	Session-locked: the server using a profile marks it and lets go on its final save (on leave,
	on close, or just before a teleport). The next server waits for that, so moving between the
	lobby and a match server never loads stale data or writes over newer data.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local TableUtil = require(Shared.Utility.TableUtil)

local Services = require(script.Parent)

local DataService = {}

local SCHEMA_VERSION = 1

local Template = {
	SchemaVersion = SCHEMA_VERSION,
	HighestRoomCompleted = 0,
	ObjectsFound = 0,
	FinderWins = 0,
	TotalMessCleared = 0,
	BestTimes = {},
	TutorialCompleted = false,
	Checkpoint = {
		RoomId = 0,
		Percent = 0,
		RoomCash = 0,
		StrengthLevel = 1,
		ThrowPowerLevel = 1,
		MoveSpeedLevel = 1,
		UpdatedAt = 0,
	},
	Settings = {
		Music = true,
		SFX = true,
		ReduceVFX = false,
		CameraShake = true,
	},
	-- Paid timed boosts (server-time expiry) survive room changes and server hops.
	Boosts = {
		StrengthBoostExpires = 0,
		CashBoostExpires = 0,
		SpeedBoostExpires = 0,
		XPBoostExpires = 0,
		PetSnackExpires = 0,
	},
	-- Hints (paid or rewarded) and reward boosts (seconds) waiting for the next room.
	Banked = {
		QuickHint = 0,
		SuperHint = 0,
		CashBoost = 0,
		StrengthBoost = 0,
		-- Paid one-shot helpers bought outside a room (used in the next one).
		LiftItNow = 0,
		JunkBlaster = 0,
		TreasureRadar = 0,
	},
	-- Daily login reward: the last UTC day claimed and the streak up to it.
	-- FreezeWeek: the last week (see RetentionService) whose free streak freeze was used.
	Login = { Day = 0, Streak = 0, FreezeWeek = 0 },
	-- The lasting Cash wallet (WalletService): saved from rooms, spent on eggs.
	Wallet = 0,
	WalletEarned = 0,
	-- Retention (RetentionService): today's active playtime and gifts, the gift bar, firsts,
	-- the free daily spin, the one-time Starter Pack and the notification question.
	Playtime = { Day = 0, Seconds = 0, Claimed = 0 },
	GiftBar = { Count = 0, Level = 0 },
	Firsts = {},
	Spin = { Day = 0 },
	StarterPack = false,
	NotifyAsked = false,
	-- Helper pets (PetService): owned per kind, the equipped list, the welcome pet, the index reward.
	Pets = { Owned = {}, Equipped = {}, Welcomed = false, IndexRewarded = false },
	-- Lasting progression (not a currency): Cleaner XP, room mastery stars, daily challenges.
	CleanerXP = 0,
	Stars = {}, -- [tostring(roomId)] = bitmask: 1 object found, 2 cleaned 25%, 4 ten treasures
	Daily = { Day = 0, Ids = {}, Progress = {}, Done = {} },
	Stats = { Swishes = 0, Treasures = 0, Chunks = 0, Keys = 0, Rooms = 0, PlaySeconds = 0 }, -- PlaySeconds: all-time active play
	-- UTC day this profile was created (0 = before analytics existed); brand-new players are
	-- tracked through the onboarding funnel for their first days.
	FirstJoinDay = 0,
	PurchaseHistory = {},
}

DataService.Template = Template

local profiles: { [Player]: { Data: any, Dirty: boolean, Loaded: boolean, UsingFallback: boolean, Released: boolean } } = {}
local store: DataStore? = nil
local storeAvailable = false
local loadedEvent = Instance.new("BindableEvent")

-- The claim a server puts on the profiles it is using (Session = { Id, Time } in the saved data).
local SESSION_ID = game.JobId ~= "" and game.JobId or HttpService:GenerateGUID(false)
local LOCK_STALE = 300 -- seconds without a refresh (autosave refreshes it): that server has died
local LOCK_WAIT = 20 -- how long to wait for a live claim to be let go before taking over anyway

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

local function heldByOther(old: any): boolean
	local session = type(old) == "table" and old.Session
	return type(session) == "table" and session.Id ~= SESSION_ID and os.time() - (tonumber(session.Time) or 0) < LOCK_STALE
end

-- Lets go of this server's claim without touching the data (a player who left mid-load).
local function releaseLock(player: Player)
	pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			if type(old) == "table" and type(old.Session) == "table" and old.Session.Id == SESSION_ID then
				old.Session = nil
				return old
			end
			return nil
		end)
	end)
end

local function migrate(data)
	if data.SchemaVersion == nil then
		data.SchemaVersion = SCHEMA_VERSION
	end
	-- Future schema migrations go here, keyed on data.SchemaVersion.
	TableUtil.Reconcile(data, Template)
	data.SchemaVersion = SCHEMA_VERSION
	return data
end

local function tryStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
		storeAvailable = true
	else
		warn("[DataService] DataStore unavailable, using memory fallback:", result)
		storeAvailable = false
	end
end

local function loadProfile(player: Player)
	local data
	local usingFallback = not storeAvailable
	if storeAvailable and store then
		-- Claim the profile. If another server still holds it (its player is on the way here),
		-- wait for it to let go; after LOCK_WAIT take it over anyway.
		local deadline = os.clock() + LOCK_WAIT
		local failures = 0
		while true do
			local force = os.clock() >= deadline
			local locked = false
			local ok, result = pcall(function()
				return (store :: DataStore):UpdateAsync(keyFor(player), function(old)
					if heldByOther(old) and not force then
						locked = true
						return nil
					end
					local profile = type(old) == "table" and old or TableUtil.DeepCopy(Template)
					if type(old) ~= "table" then
						profile.FirstJoinDay = math.floor(os.time() / 86400)
					end
					profile.Session = { Id = SESSION_ID, Time = os.time() }
					return profile
				end)
			end)
			if ok and not locked then
				data = result
				if force then
					warn("[DataService] Took over the profile of", player.Name, "from a server that never let go")
					Services.AnalyticsService.Event(player, "data_problem", 1, "took over a locked profile")
				end
				break
			elseif not ok then
				if type(result) == "string" and result:find("Studio access to APIs is not allowed") then
					storeAvailable = false
					usingFallback = true
					break
				end
				failures += 1
				if failures >= 3 then
					warn("[DataService] Failed to load profile for", player.Name, result)
					Services.AnalyticsService.Event(player, "data_problem", 1, "load failed")
					usingFallback = true
					break
				end
			end
			if not player.Parent then
				return
			end
			task.wait(1)
		end
	end
	if type(data) ~= "table" then
		data = TableUtil.DeepCopy(Template)
	end
	data.Session = nil
	migrate(data)

	if not player.Parent then
		-- Left while loading: let go of the claim straight away.
		if not usingFallback and storeAvailable and store then
			releaseLock(player)
		end
		return
	end
	profiles[player] = { Data = data, Dirty = false, Loaded = true, UsingFallback = usingFallback, Released = false }
	DataService.UpdateReplicatedSummary(player)
	loadedEvent:Fire(player)
end

local function saveProfile(player: Player, isFinal: boolean?)
	local profile = profiles[player]
	if not profile or not profile.Loaded then
		return false
	end
	if profile.UsingFallback or not storeAvailable or not store then
		profile.Dirty = false
		return true
	end
	if profile.Released and not isFinal then
		-- Handed over for a teleport: only the final save may still go out.
		return false
	end
	local snapshot = TableUtil.DeepCopy(profile.Data)
	local lost = false
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old)
			-- Another server has this profile now (it loaded it after we let go): never write over it.
			if heldByOther(old) then
				lost = true
				return nil
			end
			-- Protect against an older server overwriting newer forward progress.
			if type(old) == "table" and (old.HighestRoomCompleted or 0) > snapshot.HighestRoomCompleted then
				snapshot.HighestRoomCompleted = old.HighestRoomCompleted
				snapshot.ObjectsFound = math.max(snapshot.ObjectsFound, old.ObjectsFound or 0)
			end
			snapshot.Session = if isFinal then nil else { Id = SESSION_ID, Time = os.time() }
			return snapshot
		end)
	end)
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
		return false
	end
	if lost then
		warn("[DataService] Not saving", player.Name, "- another server has their profile now")
		Services.AnalyticsService.Event(player, "data_problem", 1, "save refused: profile moved on")
		return false
	end
	profile.Dirty = false
	return true
end

function DataService.Init()
	tryStore()

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadProfile, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadProfile, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		saveProfile(player, true)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and not storeAvailable then
			return
		end
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function DataService.Start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveInterval)
			-- Everyone is saved each round, which also keeps this server's claim on them fresh.
			for player in pairs(profiles) do
				task.spawn(saveProfile, player)
			end
		end
	end)
end

function DataService.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService.IsLoaded(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Loaded
end

function DataService.WaitFor(player: Player, timeout: number?)
	local data = DataService.Get(player)
	if data then
		return data
	end
	local deadline = os.clock() + (timeout or 15)
	while os.clock() < deadline and player.Parent do
		local loaded = loadedEvent.Event:Wait()
		if loaded == player then
			return DataService.Get(player)
		end
	end
	return DataService.Get(player)
end

function DataService.MarkDirty(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Dirty = true
	end
end

-- Mutate the profile through a callback, mark dirty and refresh replicated attributes.
function DataService.Update(player: Player, fn: (any) -> ())
	local data = DataService.Get(player)
	if not data then
		return false
	end
	fn(data)
	DataService.MarkDirty(player)
	DataService.UpdateReplicatedSummary(player)
	return true
end

function DataService.Save(player: Player): boolean
	return saveProfile(player)
end

-- Saves soon, once, however many times it's asked in the meantime (DataStores throttle
-- writes to one key to one every few seconds).
local saveSoon: { [Player]: boolean } = {}
function DataService.SaveSoon(player: Player)
	if saveSoon[player] then
		return
	end
	saveSoon[player] = true
	task.delay(6, function()
		saveSoon[player] = nil
		if player.Parent then
			saveProfile(player)
		end
	end)
end

-- A teleport is about to take this player to another server: save now and let go of the
-- profile, so that server can load the newest data straight away.
function DataService.Release(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	profile.Released = true
	return saveProfile(player, true)
end

-- The teleport failed and the player stays: take the profile back.
function DataService.Reclaim(player: Player)
	local profile = profiles[player]
	if profile and profile.Released then
		profile.Released = false
		saveProfile(player)
	end
end

-- Persistent values the client is allowed to read live as player attributes.
function DataService.UpdateReplicatedSummary(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("ObjectsFound", data.ObjectsFound)
	player:SetAttribute("HighestRoomCompleted", data.HighestRoomCompleted)
	player:SetAttribute("FinderWins", data.FinderWins)
	player:SetAttribute("TotalMessCleared", data.TotalMessCleared)
	player:SetAttribute("TutorialCompleted", data.TutorialCompleted)
	player:SetAttribute("Wallet", data.Wallet)
	player:SetAttribute("StarterPackOwned", data.StarterPack == true)
	player:SetAttribute("NotifyAsked", data.NotifyAsked == true)
	player:SetAttribute("CheckpointRoomId", data.Checkpoint.RoomId or 0)
	player:SetAttribute("CheckpointPercent", data.Checkpoint.Percent or 0)
	player:SetAttribute("Setting_Music", data.Settings.Music)
	player:SetAttribute("Setting_SFX", data.Settings.SFX)
	player:SetAttribute("Setting_ReduceVFX", data.Settings.ReduceVFX)
	player:SetAttribute("Setting_CameraShake", data.Settings.CameraShake)
	for key, best in pairs(data.BestTimes) do
		player:SetAttribute("BestTimeRoom" .. key, best or 0)
	end
end

function DataService.ResetProfile(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Data = TableUtil.DeepCopy(Template)
	profile.Dirty = true
	DataService.UpdateReplicatedSummary(player)
	saveProfile(player)
end

return DataService
