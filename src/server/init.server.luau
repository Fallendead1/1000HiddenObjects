--[[
	Server bootstrap. Determines the server role, creates remotes and starts every service.

	Roles:
	  Combined - single-place development server: lobby + local matches (no teleports)
	  Lobby    - production lobby place (queues and teleports parties)
	  Match    - production reserved match server (loads one room for one party)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Services)

local function determineRole(): string
	if GameConfig.MatchPlaceId == 0 or GameConfig.LobbyPlaceId == 0 then
		return "Combined"
	end
	if RunService:IsStudio() and GameConfig.DevelopmentMode then
		return "Combined"
	end
	if game.PlaceId == GameConfig.MatchPlaceId then
		return "Match"
	end
	return "Lobby"
end

local role = determineRole()

local serverInfo = Instance.new("Configuration")
serverInfo.Name = "ServerInfo"
serverInfo:SetAttribute("Role", role)
serverInfo:SetAttribute("DevelopmentMode", GameConfig.DevelopmentMode)
serverInfo:SetAttribute("IsStudio", RunService:IsStudio())
serverInfo.Parent = ReplicatedStorage

Remotes.Init()

local startOrder = {
	"AnalyticsService",
	"DataService",
	"PlayerSessionService",
	"NotificationService",
	"MonetizationService",
	"LeaderboardService",
	"CheckpointService",
	"RoomService",
	"MatchService",
	"ObjectService",
	"ChunkService",
	"DepositService",
	"ProgressionService",
	"EconomyService",
	"UpgradeService",
	"HintService",
	"QueueService",
	"TeleportServiceWrapper",
	"DevService",
}

for _, name in ipairs(startOrder) do
	local service = Services[name]
	if service.Init then
		service.Init(role)
	end
end

for _, name in ipairs(startOrder) do
	local service = Services[name]
	if service.Start then
		task.spawn(service.Start, role)
	end
end

print(string.format("[1000 Hidden Objects] Server started. Role=%s DevelopmentMode=%s", role, tostring(GameConfig.DevelopmentMode)))
