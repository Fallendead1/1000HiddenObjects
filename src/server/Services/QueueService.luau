--[[
	Room-aware lobby matchmaking. Every part tagged `QueueZone` inside Workspace.Lobby is an
	independent queue (Queue01..Queue04 today). One service drives them all.

	Circles are walled: you can't walk in or out. Touching the ring teleports you inside if you
	may join (the party panel or the queue bar shows); BACK / LEAVE teleports you out. Anyone who
	touches a circle they may not join is moved just outside it and told why.

	Flow per queue:
	  Empty -> first player in becomes the host -> Selecting (the host sets up the party: room,
	        party size 1-4 and, once unlocked, Hard Mode; nobody else can enter meanwhile). A host
	        who hasn't created a party after QueueSelectionTimeout is moved out and it resets.
	        -> CountingDown (others may join until the party size is reached; size 1 is a solo
	           run, closed to everyone else; the host can start early)
	        -> Locked -> Teleporting (party + RoomId + Hard + MatchId + Seed sent to a fresh match)
	        -> Resetting -> Empty

	Zone attributes (read by clients): QueueId, State, Count, MaxPlayers (party size), Joinable,
	Countdown, RoomId, RoomNumber, RoomName, TargetName, OwnerUserId, OwnerName,
	SelectionDeadline, ResumePercent, Hard.
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
	MaxPlayers: number,
	Hard: boolean,
	CountdownEnd: number,
	SelectionDeadline: number,
	Busy: boolean,
}

local queues: { Queue } = {}
local byId: { [string]: Queue } = {}
local serverRole = "Combined"
local partyLimiter = RateLimiter.new(3, 5)
local lockedNoticeAt: { [Player]: number } = {}
local blockedNoticeAt: { [Player]: number } = {}
local rejoinBlockedUntil: { [Player]: number } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function setAttr(q: Queue, name: string, value: any)
	q.Zone:SetAttribute(name, value)
end

-- In the circle or touching its ring (the walls stop you at the ring; touching it pulls you in).
local function isTouching(q: Queue, player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local radius = (q.Zone:GetAttribute("Radius") or GameConfig.QueueRadius) + GameConfig.QueueTouchMargin
	local delta = root.Position - q.Zone.Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius and math.abs(delta.Y) <= 10
end

local function isJoinable(q: Queue): boolean
	return q.State == "CountingDown" and #q.Players < q.MaxPlayers
end

local function highestCompleted(player: Player): number
	local data = Services.DataService.Get(player)
	return data and data.HighestRoomCompleted or 0
end

-- Unlocked = any existing room up to (and including) the player's next required room.
function QueueService.CanPlayRoom(player: Player, roomId: number): boolean
	return RoomRegistry.Exists(roomId) and roomId <= highestCompleted(player) + 1
end

-- Hard Mode for a room unlocks once the player has completed it (found its object).
function QueueService.CanPlayHard(player: Player, roomId: number): boolean
	return RoomRegistry.Exists(roomId) and highestCompleted(player) >= roomId
end

local function updateDisplay(q: Queue)
	setAttr(q, "State", q.State)
	setAttr(q, "Count", #q.Players)
	setAttr(q, "MaxPlayers", q.MaxPlayers)
	setAttr(q, "Joinable", isJoinable(q))
	setAttr(q, "OwnerUserId", q.Owner and q.Owner.UserId or 0)
	setAttr(q, "OwnerName", q.Owner and q.Owner.DisplayName or "")
	setAttr(q, "SelectionDeadline", q.State == "Selecting" and q.SelectionDeadline or 0)
	setAttr(q, "Hard", q.Hard)

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
	q.MaxPlayers = GameConfig.MaxPartySize
	q.Hard = false
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

-- Why a player may not step into this circle right now.
local function blockedReason(q: Queue): string
	if q.State == "Selecting" then
		return string.format("%s is setting up this party.", q.Owner and q.Owner.DisplayName or "The host")
	elseif q.State == "CountingDown" and q.MaxPlayers == 1 then
		return "This is a solo run - try another circle!"
	elseif q.State == "CountingDown" then
		return "This party is full - try another circle!"
	end
	return "This party is starting - try another circle!"
end

-- Moves a player just outside the circle (optionally telling them why). They can't be pulled
-- back in for a moment, so standing at the ring doesn't bounce them in and out.
local function pushOut(q: Queue, player: Player, reason: string?)
	rejoinBlockedUntil[player] = os.clock() + GameConfig.QueueRejoinCooldown
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local radius = q.Zone:GetAttribute("Radius") or GameConfig.QueueRadius
	local delta = Vector3.new(root.Position.X - q.Zone.Position.X, 0, root.Position.Z - q.Zone.Position.Z)
	local dir = delta.Magnitude > 0.1 and delta.Unit or Vector3.zAxis
	local spot = q.Zone.Position + dir * (radius + GameConfig.QueueTouchMargin + 1.5)
	local at = Vector3.new(spot.X, root.Position.Y, spot.Z)
	character:PivotTo(CFrame.lookAt(at, at + dir))
	if reason then
		local now = os.clock()
		if (blockedNoticeAt[player] or 0) <= now then
			blockedNoticeAt[player] = now + 4
			Services.NotificationService.Send(player, "Warning", reason)
		end
	end
end

-- Teleports someone who touched the ring into the circle, spread out a little so a party doesn't
-- stack on one spot, facing the way they were.
local function pullIn(q: Queue, player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local radius = q.Zone:GetAttribute("Radius") or GameConfig.QueueRadius
	local slot = #q.Players
	local angle = slot * math.pi * 2 / GameConfig.MaxPartySize
	local offset = slot > 1 and Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.4 or Vector3.zero
	local at = Vector3.new(q.Zone.Position.X, root.Position.Y, q.Zone.Position.Z) + offset
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.zAxis
	end
	character:PivotTo(CFrame.lookAt(at, at + look.Unit))
end

local function selectRoom(q: Queue, roomId: number)
	q.RoomId = roomId
	q.State = "CountingDown"
	-- Anyone in line who hasn't unlocked this room drops out.
	for i = #q.Players, 1, -1 do
		local player = q.Players[i]
		if not QueueService.CanPlayRoom(player, roomId) then
			removePlayer(q, i)
			notifyLocked(player, roomId)
			pushOut(q, player)
		end
	end
	local full = #q.Players >= q.MaxPlayers
	q.CountdownEnd = os.clock() + (full and GameConfig.FullQueueCountdown or GameConfig.QueueCountdown)
	updateDisplay(q)
	Services.AnalyticsService.Log("queue_room_selected", q.Owner or q.Players[1], { QueueId = q.Id, RoomId = roomId, PartySize = q.MaxPlayers, Hard = q.Hard })
end

local function launch(q: Queue)
	q.Busy = true
	q.State = "Locked"
	updateDisplay(q)

	local party = {}
	for _, player in ipairs(q.Players) do
		if player.Parent and isTouching(q, player) and not Services.MatchService.IsPlayerInMatch(player) then
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
	local roomId, hard = q.RoomId, q.Hard
	local resume = hard and 0 or Services.CheckpointService.ResolveResumePercent(party, roomId)
	for _, player in ipairs(party) do
		player:SetAttribute("Teleporting", true)
	end
	Services.AnalyticsService.Log("queue_start", party[1], { QueueId = q.Id, PartySize = #party, RoomId = roomId, Hard = hard })
	task.wait(0.3) -- a beat for the loading screen to come up

	local ok = Services.TeleportServiceWrapper.TeleportParty({
		Players = party,
		RoomId = roomId,
		ResumePercent = resume,
		QueueId = q.Id,
		Hard = hard,
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

	-- Drop players who left, died, got out somehow, or entered a match.
	for i = #q.Players, 1, -1 do
		local player = q.Players[i]
		if not player.Parent or not isTouching(q, player) or Services.MatchService.IsPlayerInMatch(player) then
			removePlayer(q, i)
			Services.AnalyticsService.Log("queue_leave", player, { QueueId = q.Id })
		end
	end

	-- Touching the ring: pulled in while the circle is free or the party has room; anyone else is
	-- moved out (never someone already in another queue).
	for _, player in ipairs(Players:GetPlayers()) do
		if (player:GetAttribute("QueueId") or "") == ""
			and player:GetAttribute("DataLoaded")
			and not player:GetAttribute("Teleporting")
			and not Services.MatchService.IsPlayerInMatch(player)
			and (rejoinBlockedUntil[player] or 0) <= os.clock()
			and isTouching(q, player)
		then
			if not ((q.State == "Empty" and #q.Players == 0) or isJoinable(q)) then
				pushOut(q, player, blockedReason(q))
			elseif q.RoomId > 0 and not QueueService.CanPlayRoom(player, q.RoomId) then
				notifyLocked(player, q.RoomId)
				pushOut(q, player)
			else
				table.insert(q.Players, player)
				player:SetAttribute("QueueId", q.Id)
				pullIn(q, player)
				Services.AnalyticsService.Log("queue_join", player, { QueueId = q.Id })
				if q.State == "Empty" then
					-- The first one in hosts: the circle closes while they set up the party.
					q.State = "Selecting"
					q.Owner = player
					q.SelectionDeadline = serverNow() + GameConfig.QueueSelectionTimeout
				elseif q.State == "CountingDown" and #q.Players >= q.MaxPlayers then
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

	if not q.Owner then
		-- The host left: the next player in line takes over.
		q.Owner = q.Players[1]
		if q.State == "Selecting" then
			q.SelectionDeadline = serverNow() + GameConfig.QueueSelectionTimeout
		end
	end

	if q.State == "Selecting" then
		-- An idle host doesn't hold the circle: once the time is up they're moved out of it.
		if serverNow() >= q.SelectionDeadline then
			local host = q.Owner :: Player
			local index = table.find(q.Players, host)
			if index then
				removePlayer(q, index)
			end
			pushOut(q, host)
			Services.NotificationService.Send(host, "Warning", "No party was created in time, so you left the circle.")
			Services.AnalyticsService.Log("queue_timeout", host, { QueueId = q.Id })
			if #q.Players == 0 then
				reset(q)
				return
			end
			q.Owner = q.Players[1]
			q.SelectionDeadline = serverNow() + GameConfig.QueueSelectionTimeout
		end
	elseif q.State == "CountingDown" and os.clock() >= q.CountdownEnd then
		task.spawn(launch, q)
		return
	end

	updateDisplay(q)
end

local function hostedQueue(player: Player, queueId: any, state: string): Queue?
	local q = type(queueId) == "string" and byId[queueId] or nil
	if not q or q.Busy or q.State ~= state or q.Owner ~= player then
		return nil
	end
	return q
end

function QueueService.Init(role: string)
	serverRole = role

	-- The host sets up the party: room + party size (1 = solo, closed to everyone else) + Hard Mode.
	Remotes.Event("CreateParty").OnServerEvent:Connect(function(player, queueId, roomId, partySize, hard)
		if not partyLimiter:Allow(player) then
			return
		end
		local q = hostedQueue(player, queueId, "Selecting")
		roomId, partySize = tonumber(roomId), tonumber(partySize)
		if not q or not roomId or not partySize then
			return
		end
		if not QueueService.CanPlayRoom(player, roomId) then
			Services.NotificationService.Send(player, "Error", "That room is locked.")
			return
		end
		if hard == true and not QueueService.CanPlayHard(player, roomId) then
			Services.NotificationService.Send(player, "Error", "Hard Mode unlocks after you find this room's object.")
			return
		end
		q.MaxPlayers = math.clamp(math.floor(partySize), 1, GameConfig.MaxPartySize)
		q.Hard = hard == true
		selectRoom(q, roomId)
	end)

	-- BACK / LEAVE: teleports you out of the circle.
	Remotes.Event("LeaveQueue").OnServerEvent:Connect(function(player, queueId)
		if not partyLimiter:Allow(player) then
			return
		end
		local q = type(queueId) == "string" and byId[queueId] or nil
		local index = q and not q.Busy and table.find(q.Players, player)
		if not q or not index then
			return
		end
		removePlayer(q, index)
		pushOut(q, player)
		Services.AnalyticsService.Log("queue_leave", player, { QueueId = q.Id })
		if #q.Players == 0 then
			reset(q)
		else
			q.Owner = q.Owner or q.Players[1]
			updateDisplay(q)
		end
	end)

	-- The host starts without waiting for the countdown.
	Remotes.Event("StartParty").OnServerEvent:Connect(function(player, queueId)
		if not partyLimiter:Allow(player) then
			return
		end
		local q = hostedQueue(player, queueId, "CountingDown")
		if q then
			q.CountdownEnd = math.min(q.CountdownEnd, os.clock() + GameConfig.FullQueueCountdown)
			updateDisplay(q)
		end
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
			MaxPlayers = GameConfig.MaxPartySize,
			Hard = false,
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
		blockedNoticeAt[player] = nil
		rejoinBlockedUntil[player] = nil
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
