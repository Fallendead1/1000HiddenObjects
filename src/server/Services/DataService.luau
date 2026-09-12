--[[
	Persistent player profiles. Loads on join, caches for the session, saves on important
	events, on leave and on server close. Falls back to memory when DataStores are unavailable
	(e.g. Studio without API access) so the game stays testable.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local TableUtil = require(Shared.Utility.TableUtil)

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
		SearchPowerLevel = 1,
		SearchSpeedLevel = 1,
		BagLevel = 1,
		MoveSpeedLevel = 1,
		UpdatedAt = 0,
	},
	Settings = {
		Music = true,
		SFX = true,
		ReduceVFX = false,
		CameraShake = true,
	},
	Boosts = {
		SearchPowerExpiresAt = 0,
		CashExpiresAt = 0,
	},
	PurchaseHistory = {},
}

DataService.Template = Template

local profiles: { [Player]: { Data: any, Dirty: boolean, Loaded: boolean, UsingFallback: boolean } } = {}
local store: DataStore? = nil
local storeAvailable = false
local loadedEvent = Instance.new("BindableEvent")

local function keyFor(player: Player): string
	return "u_" .. player.UserId
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
		local attempts = 0
		local ok, result
		repeat
			attempts += 1
			ok, result = pcall(function()
				return store:GetAsync(keyFor(player))
			end)
			if not ok then
				if type(result) == "string" and result:find("Studio access to APIs is not allowed") then
					storeAvailable = false
					break
				end
				task.wait(1)
			end
		until ok or attempts >= 3
		if ok then
			data = result
		else
			warn("[DataService] Failed to load profile for", player.Name, result)
			usingFallback = true
		end
	end
	if type(data) ~= "table" then
		data = TableUtil.DeepCopy(Template)
	end
	migrate(data)

	if not player.Parent then
		return
	end
	profiles[player] = { Data = data, Dirty = false, Loaded = true, UsingFallback = usingFallback }
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
	local snapshot = TableUtil.DeepCopy(profile.Data)
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			-- Protect against an older server overwriting newer forward progress.
			if type(old) == "table" and (old.HighestRoomCompleted or 0) > snapshot.HighestRoomCompleted then
				snapshot.HighestRoomCompleted = old.HighestRoomCompleted
				snapshot.ObjectsFound = math.max(snapshot.ObjectsFound, old.ObjectsFound or 0)
			end
			return snapshot
		end)
	end)
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
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
			for player, profile in pairs(profiles) do
				if profile.Dirty then
					saveProfile(player)
				end
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
	player:SetAttribute("CheckpointRoomId", data.Checkpoint.RoomId or 0)
	player:SetAttribute("CheckpointPercent", data.Checkpoint.Percent or 0)
	player:SetAttribute("Setting_Music", data.Settings.Music)
	player:SetAttribute("Setting_SFX", data.Settings.SFX)
	player:SetAttribute("Setting_ReduceVFX", data.Settings.ReduceVFX)
	player:SetAttribute("Setting_CameraShake", data.Settings.CameraShake)
	local best = data.BestTimes["1"]
	player:SetAttribute("BestTimeRoom1", best or 0)
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
