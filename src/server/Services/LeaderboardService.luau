--[[
	OrderedDataStore leaderboards: Top Object Finders (ObjectsFound, higher is better)
	and Fastest Room #001 (seconds, lower is better). Results are published as JSON
	attributes on ReplicatedStorage.LeaderboardData for lobby boards.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)

local LeaderboardService = {}

local finderStore: OrderedDataStore? = nil
local fastestStores: { [number]: OrderedDataStore } = {}
local available = false
local dataFolder: Configuration

local memoryFinders: { [number]: number } = {}
local memoryFastest: { [number]: { [number]: number } } = {}

local function getFastestStore(roomId: number): OrderedDataStore?
	if not available then
		return nil
	end
	if fastestStores[roomId] then
		return fastestStores[roomId]
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(GameConfig.LeaderboardFastestPrefix .. roomId)
	end)
	if ok then
		fastestStores[roomId] = store
		return store
	end
	return nil
end

local function resolveName(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return ok and name or ("User" .. userId)
end

local function fetchTop(store: OrderedDataStore?, memory: { [number]: number }, ascending: boolean, count: number)
	local entries = {}
	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(ascending, count)
		end)
		if ok then
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(entries, { UserId = userId, Name = resolveName(userId), Value = entry.value })
				end
			end
			return entries
		end
	end
	for userId, value in pairs(memory) do
		table.insert(entries, { UserId = userId, Name = resolveName(userId), Value = value })
	end
	table.sort(entries, function(a, b)
		if ascending then
			return a.Value < b.Value
		end
		return a.Value > b.Value
	end)
	while #entries > count do
		table.remove(entries)
	end
	return entries
end

function LeaderboardService.Init()
	dataFolder = Instance.new("Configuration")
	dataFolder.Name = "LeaderboardData"
	dataFolder:SetAttribute("TopFinders", "[]")
	dataFolder:SetAttribute("Fastest", "[]")
	dataFolder:SetAttribute("FastestRoomId", 1)
	dataFolder.Parent = ReplicatedStorage

	local ok, store = pcall(function()
		local s = DataStoreService:GetOrderedDataStore(GameConfig.LeaderboardTopFinders)
		-- Probe once so Studio without API access falls back to memory silently.
		s:GetSortedAsync(false, 1)
		return s
	end)
	if ok then
		finderStore = store
		available = true
	else
		warn("[LeaderboardService] OrderedDataStore unavailable, using memory fallback")
	end

	Remotes.Function("GetLeaderboards").OnServerInvoke = function()
		return {
			TopFinders = HttpService:JSONDecode(dataFolder:GetAttribute("TopFinders") or "[]"),
			Fastest = HttpService:JSONDecode(dataFolder:GetAttribute("Fastest") or "[]"),
		}
	end
end

function LeaderboardService.Start(role: string)
	if role == "Match" then
		return
	end
	task.spawn(function()
		while true do
			LeaderboardService.Refresh()
			task.wait(GameConfig.LeaderboardRefreshInterval)
		end
	end)
end

function LeaderboardService.Refresh()
	local finders = fetchTop(finderStore, memoryFinders, false, 10)
	local fastest = fetchTop(getFastestStore(1), memoryFastest[1] or {}, true, 10)
	dataFolder:SetAttribute("TopFinders", HttpService:JSONEncode(finders))
	dataFolder:SetAttribute("Fastest", HttpService:JSONEncode(fastest))
end

function LeaderboardService.SubmitObjectsFound(player: Player, objectsFound: number)
	memoryFinders[player.UserId] = objectsFound
	if finderStore then
		task.spawn(function()
			pcall(function()
				finderStore:SetAsync(tostring(player.UserId), objectsFound)
			end)
		end)
	end
end

function LeaderboardService.SubmitRoomTime(player: Player, roomId: number, seconds: number)
	seconds = math.floor(seconds)
	if seconds < GameConfig.MinimumLegitimateRoomTime or seconds > 24 * 3600 then
		return
	end
	memoryFastest[roomId] = memoryFastest[roomId] or {}
	local prev = memoryFastest[roomId][player.UserId]
	if not prev or seconds < prev then
		memoryFastest[roomId][player.UserId] = seconds
	end
	local store = getFastestStore(roomId)
	if store then
		task.spawn(function()
			pcall(function()
				store:UpdateAsync(tostring(player.UserId), function(old)
					if old and old <= seconds then
						return nil
					end
					return seconds
				end)
			end)
		end)
	end
end

return LeaderboardService
