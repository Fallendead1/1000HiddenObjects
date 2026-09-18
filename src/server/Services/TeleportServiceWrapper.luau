--[[
	Teleports a locked party to a fresh reserved match server (a reserved server of the lobby
	place itself, GameConfig.MatchInLobbyPlace), or in Combined (development) mode starts the
	match locally without a teleport. Never blocks the queue on failure: a failed teleport is
	retried once, then the player is told (and their loading screen clears, TeleportFailed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)

local Services = require(script.Parent)

local TeleportServiceWrapper = {}

local serverRole = "Combined"
local retried: { [Player]: boolean } = {}

-- Where rooms are played.
local function matchPlaceId(): number
	return if GameConfig.MatchInLobbyPlace then GameConfig.LobbyPlaceId else GameConfig.MatchPlaceId
end

-- The player's loading screen clears and the error toast underneath shows (LoadingController).
local function markFailed(player: Player)
	player:SetAttribute("TeleportFailed", (player:GetAttribute("TeleportFailed") or 0) + 1)
end

function TeleportServiceWrapper.Init(role: string)
	serverRole = role
	TeleportService.TeleportInitFailed:Connect(function(player, result, message, placeId, options)
		warn("[Teleport] Init failed for", player.Name, result, message)
		-- One quiet retry: most failures are a busy moment on Roblox's side.
		if not retried[player] and player.Parent and placeId then
			retried[player] = true
			local ok = pcall(function()
				TeleportService:TeleportAsync(placeId, { player }, options)
			end)
			if ok then
				return
			end
		end
		retried[player] = nil
		Services.DataService.Reclaim(player)
		Services.AnalyticsService.ClearTeleport(player)
		Services.AnalyticsService.Event(player, "teleport_failed", 1, "init", tostring(result))
		player:SetAttribute("Leaving", nil)
		player:SetAttribute("Teleporting", false)
		player:SetAttribute("QueueId", "")
		markFailed(player)
		Services.NotificationService.Send(player, "Error", "Teleport failed. Please try again.")
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		retried[player] = nil
	end)
end

-- TeleportAsync with one retry a second later.
local function teleport(placeId: number, players: { Player }, options: TeleportOptions?): (boolean, any)
	local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, players, options)
	if not ok then
		task.wait(1)
		ok, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, players, options)
	end
	return ok, err
end

export type PartyLaunch = {
	Players: { Player },
	RoomId: number,
	ResumePercent: number,
	QueueId: string?,
	Hard: boolean?,
	Easy: boolean?,
}

-- Hands the players' data over cleanly: a final save that lets go of each profile, so the
-- server they land on loads the newest data straight away (DataService session locks).
local function handOver(players: { Player })
	local pending = #players
	for _, p in ipairs(players) do
		Services.AnalyticsService.MarkTeleport(p)
		task.spawn(function()
			Services.DataService.Release(p)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 6
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
end

-- The teleport didn't happen: whoever is still here takes their data back.
local function takeBack(players: { Player })
	for _, p in ipairs(players) do
		if p.Parent then
			Services.DataService.Reclaim(p)
			Services.AnalyticsService.ClearTeleport(p)
		end
	end
end

-- Returns true when the party is on its way (or a local match started).
function TeleportServiceWrapper.TeleportParty(launch: PartyLaunch): boolean
	local seed = Random.new():NextInteger(1, 2 ^ 30)
	local matchId = HttpService:GenerateGUID(false)
	local partySize = #launch.Players

	if serverRole == "Combined" then
		return Services.MatchService.StartLocalMatch({
			Players = launch.Players,
			RoomId = launch.RoomId,
			PartySize = partySize,
			ResumePercent = launch.ResumePercent,
			Seed = seed,
			MatchId = matchId,
			Hard = launch.Hard == true,
			Easy = launch.Easy == true,
		})
	end

	local placeId = matchPlaceId()
	local okReserve, accessCode = pcall(TeleportService.ReserveServer, TeleportService, placeId)
	if not okReserve then
		task.wait(1)
		okReserve, accessCode = pcall(TeleportService.ReserveServer, TeleportService, placeId)
	end
	if not okReserve then
		warn("[Teleport] ReserveServer failed:", accessCode)
		for _, p in ipairs(launch.Players) do
			Services.AnalyticsService.Event(p, "teleport_failed", 1, "to room", "reserve failed")
			markFailed(p)
		end
		Services.NotificationService.SendMany(launch.Players, "Error", "Teleport failed. Please try again.")
		return false
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		MatchId = matchId,
		QueueId = launch.QueueId,
		RoomId = launch.RoomId,
		PartySize = partySize,
		ResumePercent = launch.ResumePercent,
		Seed = seed,
		Hard = launch.Hard == true,
		Easy = launch.Easy == true,
		LaunchedAt = os.time(),
		PartySessions = Services.AnalyticsService.PartySessions(launch.Players),
		ExpectedUserIds = (function()
			local ids = {}
			for _, p in ipairs(launch.Players) do
				table.insert(ids, p.UserId)
			end
			return ids
		end)(),
	})

	handOver(launch.Players)
	local okTeleport, err = teleport(placeId, launch.Players, options)
	if not okTeleport then
		warn("[Teleport] TeleportAsync failed:", err)
		takeBack(launch.Players)
		for _, p in ipairs(launch.Players) do
			Services.AnalyticsService.Event(p, "teleport_failed", 1, "to room", "teleport failed")
			markFailed(p)
		end
		Services.NotificationService.SendMany(launch.Players, "Error", "Teleport failed. Please try again.")
		return false
	end
	return true
end

function TeleportServiceWrapper.ReturnToLobby(player: Player)
	if serverRole ~= "Match" then
		Services.MatchService.MovePlayerToLobby(player)
		return
	end
	if GameConfig.LobbyPlaceId == 0 then
		return
	end
	handOver({ player })
	local ok, err = teleport(GameConfig.LobbyPlaceId, { player })
	if not ok then
		warn("[Teleport] Return to lobby failed:", err)
		takeBack({ player })
		Services.AnalyticsService.Event(player, "teleport_failed", 1, "to lobby", "teleport failed")
		player:SetAttribute("Leaving", nil)
		markFailed(player)
		Services.NotificationService.Send(player, "Error", "Couldn't get back to the lobby. Please try again.")
	end
end

return TeleportServiceWrapper
