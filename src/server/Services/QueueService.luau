--[[
	Room-aware lobby matchmaking. Every part tagged `QueueZone` inside Workspace.Lobby is an
	independent queue (Queue01..Queue04 today). One service drives them all.

	Flow per queue:
	  Empty -> first player steps in, becomes owner -> Selecting (owner picks a room)
	        -> CountingDown (others may join the selected room, max 4)
	        -> Locked -> Teleporting (party + RoomId + MatchId + Seed sent to a fresh match)
	        -> Resetting -> Empty

	Zone attributes (read by clients): QueueId, State, Count, MaxPlayers, Countdown, RoomId,
	RoomNumber, RoomName, TargetName, OwnerUserId, OwnerName, SelectionDeadline, ResumePercent.
	Player attribute: QueueId ("" when not queued).
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local QueueService = {}

type Queue = {
	Id: string,
	Zone: BasePart,
	State: string,
	Players: { Player },
	Owner: Player?,
	RoomId: number,
	CountdownEnd: number,
	SelectionDeadline: number,
	Busy: boolean,
}

local queues: { Queue } = {}
local byId: { [string]: Queue } = {}
local serverRole = "Combined"
local selectLimiter = RateLimiter.new(3, 5)
local lockedNoticeAt: { [Player]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function setAttr(q: Queue, name: string, value: any)
	q.Zone:SetAttribute(name, value)
end

local function isInside(q: Queue, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local radius = q.Zone:GetAttribute("Radius") or GameConfig.QueueRadius
	local delta = root.Position - q.Zone.Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius and math.abs(delta.Y) <= 10
end

local function highestCompleted(player: Player): number
	local data = Services.DataService.Get(player)
	return data and data.HighestRoomCompleted or 0
end

-- Unlocked = any existing room up to (and including) the player's next required room.
function QueueService.CanPlayRoom(player: Player, roomId: number): boolean
	return RoomRegistry.Exists(roomId) and roomId <= highestCompleted(player) + 1
end

local function defaultRoomFor(player: Player): number
	local target = math.min(highestCompleted(player) + 1, RoomRegistry.GetHighestAvailable())
	while target > 1 and not RoomRegistry.Exists(target) do
		target -= 1
	end
	return math.max(1, target)
end

local function updateDisplay(q: Queue)
	setAttr(q, "State", q.State)
	setAttr(q, "Count", #q.Players)
	setAttr(q, "MaxPlayers", GameConfig.MaxPartySize)
	setAttr(q, "OwnerUserId", q.Owner and q.Owner.UserId or 0)
	setAttr(q, "OwnerName", q.Owner and q.Owner.DisplayName or "")
	setAttr(q, "SelectionDeadline", q.State == "Selecting" and q.SelectionDeadline or 0)

	local config = q.RoomId > 0 and RoomRegistry.Get(q.RoomId) or nil
	setAttr(q, "RoomId", q.RoomId)
	setAttr(q, "RoomNumber", config and config.DisplayNumber or "")
	setAttr(q, "RoomName", config and config.Name or "")
	setAttr(q, "TargetName", config and config.TargetName or "")

	if q.State == "CountingDown" then
		setAttr(q, "Countdown", math.max(0, math.ceil(q.CountdownEnd - os.clock())))
		setAttr(q, "ResumePercent", Services.CheckpointService.ResolveResumePercent(q.Players, q.RoomId))
	else
		setAttr(q, "Countdown", 0)
		if q.State == "Empty" then
			setAttr(q, "ResumePercent", 0)
		end
	end
end

local function removePlayer(q: Queue, index: number)
	local player = table.remove(q.Players, index)
	if player and player.Parent then
		player:SetAttribute("QueueId", "")
	end
	if q.Owner == player then
		q.Owner = nil
	end
	return player
end

local function reset(q: Queue)
	for i = #q.Players, 1, -1 do
		removePlayer(q, i)
	end
	q.State = "Empty"
	q.Owner = nil
	q.RoomId = 0
	q.CountdownEnd = 0
	q.SelectionDeadline = 0
	q.Busy = false
	updateDisplay(q)
end

local function notifyLocked(player: Player, roomId: number)
	local now = os.clock()
	if (lockedNoticeAt[player] or 0) > now then
		return
	end
	lockedNoticeAt[player] = now + 5
	Services.NotificationService.Send(player, "Warning", string.format("Room #%03d is locked for you. Try another circle!", roomId))
end

local function selectRoom(q: Queue, roomId: number)
	q.RoomId = roomId
	q.State = "CountingDown"
	-- Anyone who joined while the owner was choosing but hasn't unlocked this room drops out.
	for i = #q.Players, 1, -1 do
		local player = q.Players[i]
		if not QueueService.CanPlayRoom(player, roomId) then
			removePlayer(q, i)
			notifyLocked(player, roomId)
		end
	end
	local full = #q.Players >= GameConfig.MaxPartySize
	q.CountdownEnd = os.clock() + (full and GameConfig.FullQueueCountdown or GameConfig.QueueCountdown)
	updateDisplay(q)
	Services.AnalyticsService.Log("queue_room_selected", q.Owner or q.Players[1], { QueueId = q.Id, RoomId = roomId })
end

local function launch(q: Queue)
	q.Busy = true
	q.State = "Locked"
	updateDisplay(q)

	local party = {}
	for _, player in ipairs(q.Players) do
		if player.Parent and isInside(q, player) and not Services.MatchService.IsPlayerInMatch(player) then
			table.insert(party, player)
		end
	end
	if #party == 0 then
		reset(q)
		return
	end

	q.State = "Teleporting"
	setAttr(q, "Count", #party)
	updateDisplay(q)
	local roomId = q.RoomId
	local resume = Services.CheckpointService.ResolveResumePercent(party, roomId)
	for _, player in ipairs(party) do
		player:SetAttribute("Teleporting", true)
	end
	Services.AnalyticsService.Log("queue_start", party[1], { QueueId = q.Id, PartySize = #party, RoomId = roomId })
	task.wait(0.8)

	local ok = Services.TeleportServiceWrapper.TeleportParty({
		Players = party,
		RoomId = roomId,
		ResumePercent = resume,
		QueueId = q.Id,
	})
	for _, player in ipairs(party) do
		if player.Parent then
			player:SetAttribute("Teleporting", false)
			player:SetAttribute("QueueId", "")
		end
	end
	q.Players = {}
	q.Owner = nil
	q.State = "Resetting"
	updateDisplay(q)
	task.wait(ok and 3 or 1.5)
	reset(q)
end

local function step(q: Queue)
	if q.Busy then
		return
	end

	-- Drop players who walked out, left, or entered a match.
	for i = #q.Players, 1, -1 do
		local player = q.Players[i]
		if not player.Parent or not isInside(q, player) or Services.MatchService.IsPlayerInMatch(player) then
			removePlayer(q, i)
			Services.AnalyticsService.Log("queue_leave", player, { QueueId = q.Id })
		end
	end

	-- Add newcomers (never someone already in another queue).
	for _, player in ipairs(Players:GetPlayers()) do
		if #q.Players >= GameConfig.MaxPartySize then
			break
		end
		if (player:GetAttribute("QueueId") or "") == ""
			and player:GetAttribute("DataLoaded")
			and not player:GetAttribute("Teleporting")
			and not Services.MatchService.IsPlayerInMatch(player)
			and isInside(q, player)
		then
			if q.RoomId > 0 and not QueueService.CanPlayRoom(player, q.RoomId) then
				notifyLocked(player, q.RoomId)
			else
				table.insert(q.Players, player)
				player:SetAttribute("QueueId", q.Id)
				Services.AnalyticsService.Log("queue_join", player, { QueueId = q.Id })
				if q.State == "CountingDown" and #q.Players >= GameConfig.MaxPartySize then
					q.CountdownEnd = math.min(q.CountdownEnd, os.clock() + GameConfig.FullQueueCountdown)
				end
			end
		end
	end

	if #q.Players == 0 then
		if q.State ~= "Empty" then
			reset(q)
		else
			updateDisplay(q)
		end
		return
	end

	if q.State == "Empty" then
		q.State = "Selecting"
		q.Owner = q.Players[1]
		q.SelectionDeadline = serverNow() + GameConfig.QueueSelectionTimeout
	end

	if q.State == "Selecting" then
		if not q.Owner then
			-- Owner walked out while choosing: the next player in line takes over.
			q.Owner = q.Players[1]
			q.SelectionDeadline = serverNow() + GameConfig.QueueSelectionTimeout
		end
		if serverNow() >= q.SelectionDeadline then
			selectRoom(q, defaultRoomFor(q.Owner :: Player))
		end
	elseif q.State == "CountingDown" and os.clock() >= q.CountdownEnd then
		task.spawn(launch, q)
		return
	end

	updateDisplay(q)
end

function QueueService.Init(role: string)
	serverRole = role
	Remotes.Event("SelectRoom").OnServerEvent:Connect(function(player, queueId, roomId)
		if not selectLimiter:Allow(player) or type(queueId) ~= "string" then
			return
		end
		local q = byId[queueId]
		roomId = tonumber(roomId)
		if not q or q.Busy or q.State ~= "Selecting" or q.Owner ~= player or not roomId then
			return
		end
		if not QueueService.CanPlayRoom(player, roomId) then
			Services.NotificationService.Send(player, "Error", "That room is locked.")
			return
		end
		selectRoom(q, roomId)
	end)
end

-- Registers every QueueZone under the lobby. Zones are data: QueueId + Radius attributes.
function QueueService.DiscoverZones(lobby: Instance?)
	if not lobby then
		return
	end
	local found = {}
	for _, inst in ipairs(CollectionService:GetTagged("QueueZone")) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(lobby) then
			found[inst] = true
		end
	end
	for _, inst in ipairs(lobby:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == "QueueZone" then
			found[inst] = true
		end
	end
	for zone in pairs(found) do
		local id = zone:GetAttribute("QueueId") or (zone.Parent and zone.Parent.Name) or zone.Name
		if byId[id] then
			id = id .. "_" .. #queues + 1
		end
		zone:SetAttribute("QueueId", id)
		zone.CanCollide = false
		zone.CanTouch = false
		local q: Queue = {
			Id = id,
			Zone = zone,
			State = "Empty",
			Players = {},
			Owner = nil,
			RoomId = 0,
			CountdownEnd = 0,
			SelectionDeadline = 0,
			Busy = false,
		}
		table.insert(queues, q)
		byId[id] = q
		updateDisplay(q)
	end
	table.sort(queues, function(a, b)
		return a.Id < b.Id
	end)
	print(string.format("[QueueService] %d matchmaking queues registered", #queues))
end

function QueueService.Start(role: string)
	if role == "Match" then
		return
	end
	task.spawn(function()
		while true do
			task.wait(GameConfig.QueuePollInterval)
			for _, q in ipairs(queues) do
				local ok, err = pcall(step, q)
				if not ok then
					warn("[QueueService]", q.Id, err)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lockedNoticeAt[player] = nil
		for _, q in ipairs(queues) do
			local idx = table.find(q.Players, player)
			if idx then
				table.remove(q.Players, idx)
				if q.Owner == player then
					q.Owner = nil
				end
			end
		end
	end)
end

function QueueService.GetQueues(): { Queue }
	return queues
end

return QueueService
