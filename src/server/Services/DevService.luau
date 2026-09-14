--[[
	Studio/development-only commands driven by the client Test Panel. Never available to
	normal players in production.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)
local RoomValidator = require(script.Parent.Parent.RoomValidator)

local DevService = {}

function DevService.IsAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if GameConfig.DevelopmentMode and table.find(GameConfig.DeveloperUserIds, player.UserId) then
		return true
	end
	return false
end

local commands: { [string]: (Player, ...any) -> () } = {}

commands.StartRoom = function(player, partySize, roomId)
	partySize = math.clamp(tonumber(partySize) or 1, 1, GameConfig.MaxPartySize)
	roomId = tonumber(roomId) or 1
	if not RoomRegistry.Exists(roomId) then
		roomId = 1
	end
	if Services.MatchService.GetMatch() then
		Services.MatchService.EndMatch()
		task.wait(0.5)
	end
	Services.MatchService.StartLocalMatch({
		Players = { player },
		RoomId = roomId,
		PartySize = partySize,
		ResumePercent = Services.CheckpointService.ResolveResumePercent({ player }, roomId),
		Seed = Random.new():NextInteger(1, 2 ^ 30),
		MatchId = HttpService:GenerateGUID(false),
	})
end

commands.AddCash = function(player, amount)
	if Services.MatchService.IsPlayerInMatch(player) then
		Services.EconomyService.AddCash(player, tonumber(amount) or 10000)
	end
end

commands.SetProgress = function(player, fraction)
	Services.MatchService.ForceProgress(tonumber(fraction) or 0.25)
end

commands.RevealTarget = function(player)
	Services.MatchService.ForceReveal()
end

commands.CompleteRoom = function(player)
	Services.MatchService.ForceComplete(player)
end

commands.ResetRoom = function(player)
	if Services.MatchService.GetMatch() then
		Services.MatchService.EndMatch()
	end
end

commands.ValidateRoom = function(player, roomId)
	roomId = tonumber(roomId) or 1
	local match = Services.MatchService.GetMatch()
	local report
	if match and match.RoomId == roomId then
		local _, r = RoomValidator.Validate(match.Runtime, match.Config)
		report = r
	else
		local config = RoomRegistry.Get(roomId)
		if not config then
			report = "Unknown room " .. tostring(roomId)
		else
			-- Built off to the side (not near FallenPartsDestroyHeight) and never released to physics.
			local runtime = Services.RoomService.Build(config, CFrame.new(-700, 0, 0))
			local _, r = RoomValidator.Validate(runtime, config)
			report = r
			Services.RoomService.Destroy(runtime)
		end
	end
	print(report)
	Services.NotificationService.Send(player, "Info", report, 12)
end

commands.ResetData = function(player)
	if Services.MatchService.IsPlayerInMatch(player) then
		return
	end
	Services.DataService.ResetProfile(player)
	Services.NotificationService.Send(player, "Info", "[DEV] Save data reset.")
end

commands.MockPurchase = function(player, key)
	if type(key) == "string" then
		Services.MonetizationService.MockGrant(player, key)
	end
end

commands.ForceCheckpoint = function(player, percent)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if match then
		Services.CheckpointService.SaveCheckpoint(player, match, tonumber(percent) or 0.25)
		Services.NotificationService.Send(player, "Info", "[DEV] Checkpoint saved.")
	end
end

-- Breaks open the packed junk that secretly holds the key (same path as grabbing it).
commands.BurstKeyChunk = function(player)
	local match = Services.MatchService.GetMatch()
	local chunk = match and match.KeyChunk
	if chunk and chunk.Parent then
		Services.ChunkService.Burst(chunk, player)
	else
		print("[DEV] No key chunk on this spot")
	end
end

commands.TargetInfo = function(player)
	local info = Services.MatchService.GetTargetInfo()
	if info then
		local text = string.format("[DEV] Target: %s (%s) at %s | %d covering / %d blockers | revealed=%s | keyChunk=%s | blockers: %s", tostring(info.SocketId), tostring(info.RegionId), tostring(info.Position), info.Covering or 0, info.Blockers or 0, tostring(info.Revealed), tostring(info.KeyChunk), table.concat(info.BlockerIds or {}, ","))
		print(text)
		Services.NotificationService.Send(player, "Info", text, 8)
	end
end

function DevService.Init()
	Remotes.Event("DevCommand").OnServerEvent:Connect(function(player, command, ...)
		if not DevService.IsAuthorized(player) then
			return
		end
		local fn = type(command) == "string" and commands[command]
		if fn then
			local ok, err = pcall(fn, player, ...)
			if not ok then
				warn("[DevService]", command, err)
			end
		end
	end)
end

return DevService
