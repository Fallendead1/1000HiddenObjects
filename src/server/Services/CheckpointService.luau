--[[
	Coarse long-run protection. Saves a per-player checkpoint at configured room
	percentages and resolves the resume percentage for a party.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)

local CheckpointService = {}

function CheckpointService.Init()
	Remotes.Event("DiscardCheckpoint").OnServerEvent:Connect(function(player)
		if Services.MatchService.IsPlayerInMatch(player) then
			return
		end
		Services.DataService.Update(player, function(data)
			data.Checkpoint.RoomId = 0
			data.Checkpoint.Percent = 0
		end)
		Services.NotificationService.Send(player, "Info", "Checkpoint discarded. Next room starts fresh.")
	end)
end

-- Lowest checkpoint among the party for this room (players without one count as 0).
function CheckpointService.ResolveResumePercent(players: { Player }, roomId: number): number
	local lowest = math.huge
	for _, player in ipairs(players) do
		local data = Services.DataService.Get(player)
		local percent = 0
		if data and data.Checkpoint.RoomId == roomId then
			percent = data.Checkpoint.Percent or 0
		end
		lowest = math.min(lowest, percent)
	end
	if lowest == math.huge then
		lowest = 0
	end
	return lowest
end

function CheckpointService.GetCheckpoint(player: Player, roomId: number)
	local data = Services.DataService.Get(player)
	if data and data.Checkpoint.RoomId == roomId and (data.Checkpoint.Percent or 0) > 0 then
		return data.Checkpoint
	end
	return nil
end

function CheckpointService.SaveCheckpoint(player: Player, match, percent: number)
	local updated = Services.DataService.Update(player, function(data)
		local cp = data.Checkpoint
		local sameRoom = cp.RoomId == match.RoomId
		if sameRoom and (cp.Percent or 0) >= percent then
			return -- never overwrite a higher personal checkpoint downward
		end
		cp.RoomId = match.RoomId
		cp.Percent = percent
		cp.RoomCash = player:GetAttribute("RoomCash") or 0
		cp.StrengthLevel = player:GetAttribute("StrengthLevel") or 1
		cp.ThrowPowerLevel = player:GetAttribute("ThrowPowerLevel") or 1
		cp.MoveSpeedLevel = player:GetAttribute("MoveSpeedLevel") or 1
		cp.ArmfulLevel = player:GetAttribute("ArmfulLevel") or 1
		cp.UpdatedAt = os.time()
	end)
	if updated then
		Services.DataService.Save(player)
	end
end

-- Called by MatchService whenever room progress changes.
function CheckpointService.OnProgress(match, oldProgress: number, newProgress: number)
	for i, threshold in ipairs(GameConfig.Checkpoints) do
		if oldProgress < threshold and newProgress >= threshold then
			for _, player in ipairs(match.Players) do
				CheckpointService.SaveCheckpoint(player, match, threshold)
			end
			Services.NotificationService.SendMany(match.Players, "Info", string.format("Room checkpoint saved (%d%%)!", math.floor(threshold * 100)))
			for _, player in ipairs(match.Players) do
				Services.AnalyticsService.Event(player, "room_milestone", math.floor(threshold * 100 + 0.5), (match.PartySize or 1) <= 1 and "solo" or ("party of " .. tostring(match.PartySize)))
			end
		end
	end
end

function CheckpointService.ClearForRoom(player: Player, roomId: number)
	Services.DataService.Update(player, function(data)
		if data.Checkpoint.RoomId == roomId then
			data.Checkpoint.RoomId = 0
			data.Checkpoint.Percent = 0
			data.Checkpoint.RoomCash = 0
			data.Checkpoint.StrengthLevel = 1
			data.Checkpoint.ThrowPowerLevel = 1
			data.Checkpoint.MoveSpeedLevel = 1
			data.Checkpoint.ArmfulLevel = 1
		end
	end)
end

return CheckpointService
