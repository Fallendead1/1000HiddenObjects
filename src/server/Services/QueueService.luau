--[[
	Physical lobby queue. Players inside the QueueZone radius are queued; the first player
	starts a countdown, a full queue shortens it, walking out leaves. At zero the queue
	locks, snapshots the party and hands it to the teleport wrapper.

	States: Empty, Waiting, CountingDown, Locked, Teleporting, Resetting
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local FormatUtil = require(Shared.Utility.FormatUtil)

local Services = require(script.Parent)

local QueueService = {}

local zone: BasePart? = nil
local state = "Empty"
local queued: { Player } = {}
local countdownEnd = 0
local serverRole = "Combined"

local function setAttr(name: string, value: any)
	if zone then
		zone:SetAttribute(name, value)
	end
end

local function setState(newState: string)
	state = newState
	setAttr("State", newState)
end

local function isInside(player: Player): boolean
	if not zone then
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local radius = zone:GetAttribute("Radius") or GameConfig.QueueRadius
	local delta = root.Position - zone.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	return flat.Magnitude <= radius and math.abs(delta.Y) < 12
end

-- The room a party will play: the lowest next-required room among the party, capped to
-- the rooms that exist. Players who have finished everything replay the highest room.
local function resolveRoomId(players: { Player }): number
	local highestAvailable = RoomRegistry.GetHighestAvailable()
	local lowestNext = math.huge
	for _, player in ipairs(players) do
		local data = Services.DataService.Get(player)
		local nextRoom = ((data and data.HighestRoomCompleted) or 0) + 1
		lowestNext = math.min(lowestNext, nextRoom)
	end
	if lowestNext == math.huge then
		lowestNext = 1
	end
	return math.clamp(lowestNext, 1, highestAvailable)
end

local function updateDisplay()
	local count = #queued
	setAttr("Count", count)
	local roomId = resolveRoomId(queued)
	setAttr("RoomId", roomId)
	if state == "Empty" then
		setAttr("Countdown", 0)
		setAttr("Message", "STEP INSIDE TO PLAY")
	elseif state == "CountingDown" then
		local remaining = math.max(0, countdownEnd - os.clock())
		setAttr("Countdown", math.ceil(remaining))
		local resume = Services.CheckpointService.ResolveResumePercent(queued, roomId)
		if resume > 0 then
			setAttr("Message", string.format("RESUME ROOM %s - %d%% CHECKPOINT", FormatUtil.RoomNumber(roomId), math.floor(resume * 100)))
		else
			setAttr("Message", string.format("ROOM %s", FormatUtil.RoomNumber(roomId)))
		end
	elseif state == "Locked" or state == "Teleporting" then
		setAttr("Countdown", 0)
		setAttr("Message", "STARTING...")
	end
end

local function launch()
	setState("Locked")
	local party = {}
	for _, player in ipairs(queued) do
		if player.Parent and isInside(player) then
			table.insert(party, player)
		end
	end
	queued = {}
	updateDisplay()
	if #party == 0 then
		setState("Empty")
		updateDisplay()
		return
	end
	for _, player in ipairs(party) do
		if Services.MatchService.IsPlayerInMatch(player) then
			setState("Empty")
			updateDisplay()
			return
		end
	end

	setState("Teleporting")
	local roomId = resolveRoomId(party)
	local resume = Services.CheckpointService.ResolveResumePercent(party, roomId)
	for _, player in ipairs(party) do
		player:SetAttribute("Queued", false)
		player:SetAttribute("Teleporting", true)
	end
	Services.AnalyticsService.Log("queue_start", party[1], { PartySize = #party, RoomId = roomId })

	local ok = Services.TeleportServiceWrapper.TeleportParty({
		Players = party,
		RoomId = roomId,
		ResumePercent = resume,
	})
	for _, player in ipairs(party) do
		player:SetAttribute("Teleporting", false)
	end
	if not ok then
		-- Failure: players stay in the lobby and may queue again immediately.
		task.wait(1)
	end
	setState("Resetting")
	task.wait(serverRole == "Combined" and 2 or 4)
	setState("Empty")
	updateDisplay()
end

function QueueService.Init(role: string)
	serverRole = role
end

function QueueService.SetZone(part: BasePart)
	zone = part
	setAttr("MaxPlayers", GameConfig.MaxPartySize)
	setState("Empty")
	updateDisplay()
end

function QueueService.Start(role: string)
	if role == "Match" then
		return
	end
	task.spawn(function()
		while true do
			task.wait(GameConfig.QueuePollInterval)
			if zone then
				QueueService.Step()
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local idx = table.find(queued, player)
		if idx then
			table.remove(queued, idx)
		end
	end)
end

function QueueService.Step()
	if state == "Locked" or state == "Teleporting" or state == "Resetting" then
		return
	end

	local changed = false
	-- Remove players who left the circle.
	for i = #queued, 1, -1 do
		local player = queued[i]
		if not player.Parent or not isInside(player) or Services.MatchService.IsPlayerInMatch(player) then
			table.remove(queued, i)
			player:SetAttribute("Queued", false)
			changed = true
			Services.AnalyticsService.Log("queue_leave", player)
		end
	end
	-- Add players who entered.
	if #queued < GameConfig.MaxPartySize then
		for _, player in ipairs(Players:GetPlayers()) do
			if #queued >= GameConfig.MaxPartySize then
				break
			end
			if not table.find(queued, player) and isInside(player) and not Services.MatchService.IsPlayerInMatch(player) and player:GetAttribute("DataLoaded") then
				table.insert(queued, player)
				player:SetAttribute("Queued", true)
				changed = true
				Services.AnalyticsService.Log("queue_join", player)
			end
		end
	end

	if #queued == 0 then
		if state ~= "Empty" then
			setState("Empty")
		end
		updateDisplay()
		return
	end

	if state == "Empty" or state == "Waiting" then
		setState("CountingDown")
		countdownEnd = os.clock() + GameConfig.QueueCountdown
	end

	if changed and #queued >= GameConfig.MaxPartySize then
		countdownEnd = math.min(countdownEnd, os.clock() + GameConfig.FullQueueCountdown)
	end

	updateDisplay()

	if os.clock() >= countdownEnd then
		launch()
	end
end

function QueueService.GetState(): string
	return state
end

return QueueService
