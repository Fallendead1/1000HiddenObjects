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
}

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
		ExpectedUserIds = (function()
			local ids = {}
			for _, p in ipairs(launch.Players) do
				table.insert(ids, p.UserId)
			end
			return ids
		end)(),
	})

	local okTeleport, err = pcall(function()
		TeleportService:TeleportAsync(GameConfig.MatchPlaceId, launch.Players, options)
	end)
	if not okTeleport then
		warn("[Teleport] TeleportAsync failed:", err)
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
	pcall(function()
		TeleportService:TeleportAsync(GameConfig.LobbyPlaceId, { player })
	end)
end

return TeleportServiceWrapper
