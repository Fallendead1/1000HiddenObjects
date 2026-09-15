--[[
	Teleports a locked party to a fresh reserved Match server, or in Combined (development)
	mode starts the match locally without a teleport. Never blocks the queue on failure.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)

local Services = require(script.Parent)

local TeleportServiceWrapper = {}

local serverRole = "Combined"

function TeleportServiceWrapper.Init(role: string)
	serverRole = role
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn("[Teleport] Init failed for", player.Name, result, message)
		Services.DataService.Reclaim(player)
		player:SetAttribute("Leaving", nil)
		player:SetAttribute("Teleporting", false)
		player:SetAttribute("QueueId", "")
		Services.NotificationService.Send(player, "Error", "Teleport failed. Please try again.")
	end)
end

export type PartyLaunch = {
	Players: { Player },
	RoomId: number,
	ResumePercent: number,
	QueueId: string?,
	Hard: boolean?,
}

-- Hands the players' data over cleanly: a final save that lets go of each profile, so the
-- server they land on loads the newest data straight away (DataService session locks).
local function handOver(players: { Player })
	local pending = #players
	for _, p in ipairs(players) do
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
		})
	end

	local okReserve, accessCode = pcall(function()
		return TeleportService:ReserveServer(GameConfig.MatchPlaceId)
	end)
	if not okReserve then
		warn("[Teleport] ReserveServer failed:", accessCode)
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
		ExpectedUserIds = (function()
			local ids = {}
			for _, p in ipairs(launch.Players) do
				table.insert(ids, p.UserId)
			end
			return ids
		end)(),
	})

	handOver(launch.Players)
	local okTeleport, err = pcall(function()
		TeleportService:TeleportAsync(GameConfig.MatchPlaceId, launch.Players, options)
	end)
	if not okTeleport then
		warn("[Teleport] TeleportAsync failed:", err)
		takeBack(launch.Players)
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
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(GameConfig.LobbyPlaceId, { player })
	end)
	if not ok then
		warn("[Teleport] Return to lobby failed:", err)
		takeBack({ player })
		player:SetAttribute("Leaving", nil)
		Services.NotificationService.Send(player, "Error", "Couldn't get back to the lobby. Please try again.")
	end
end

return TeleportServiceWrapper
