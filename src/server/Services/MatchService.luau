--[[
	Server-authoritative match state machine. One match per server (reserved match servers
	hold exactly one party; the Combined dev server runs one local match at a time).

	States: Loading -> Countdown -> Searching -> TargetFound -> Results -> Returning -> Ended

	The Golden Key is revealed ONLY when nothing physically covers its socket: every original
	blocker has been moved away (or is being held) and no other object lies on the spot.
	Room progress = ROOM CLEANED (objects deposited in bins / every real object in the room,
	packed junk included). It drives checkpoints, never the reveal; clues run on a timer
	(HintService).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RetentionConfig = require(Shared.Config.RetentionConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)
local Builders = script.Parent.Parent.Builders
local TargetBuilder = require(Builders.TargetBuilder)
local RoomValidator = require(script.Parent.Parent.RoomValidator)

local MatchService = {}

local serverRole = "Combined"
local match = nil
local stateConfig: Configuration
local lobbyModel: Instance? = nil
local lobbySpawn: BasePart? = nil
local coverParams = OverlapParams.new()
coverParams.FilterType = Enum.RaycastFilterType.Include
-- Players whose game has finished loading (ClientReady): a match server waits for them.
local readyClients: { [Player]: boolean } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fireMatch(eventName: string, payload: any, players: { Player }?)
	for _, player in ipairs(players or (match and match.Players) or {}) do
		if player.Parent then
			Remotes.Event("MatchUpdate"):FireClient(player, eventName, payload)
		end
	end
end

local function setState(newState: string)
	if match then
		match.State = newState
		stateConfig:SetAttribute("State", newState)
	end
end

local function resetStateConfig()
	for name, value in pairs({
		State = "None", RoomId = 0, RoomName = "", RoomNumber = "", TargetName = "", TargetId = "",
		PartySize = 0, StartTime = 0, EndTime = 0, TotalObjects = 0, CleanedObjects = 0, Progress = 0,
		HintStage = 0, TargetRevealed = false, TargetFound = false, FinderName = "", OutlinedObjects = "",
		TeamMuscleExpires = 0, PlayerNames = "", ResumePercent = 0, TreasuresTotal = 0, TreasuresCleaned = 0,
		Hard = false, Easy = false, NextClueAt = 0,
		ClueSide = "", ClueZone = "", ClueSpotRadius = 0, PilesCleared = "",
	}) do
		stateConfig:SetAttribute(name, value)
	end
end

local function moveCharacterTo(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cframe + Vector3.new(0, 3, 0))
	end
end

local function getSpawnCFrame(): CFrame?
	if match and match.Runtime.SpawnPart then
		return match.Runtime.SpawnPart.CFrame * CFrame.new(0, 2, 0)
	end
	return nil
end

local function playerNamesString(players: { Player }): string
	local names = {}
	for _, p in ipairs(players) do
		table.insert(names, p.Name)
	end
	return table.concat(names, ",")
end

local function clutterRootOf(part: Instance): BasePart?
	if CollectionService:HasTag(part, "Clutter") then
		return part :: BasePart
	end
	local parent = part.Parent
	if parent and parent:IsA("BasePart") and CollectionService:HasTag(parent, "Clutter") then
		return parent
	end
	return nil
end

local function isBlockerClear(root: BasePart): boolean
	if (root:GetAttribute("HeldByUserId") or 0) ~= 0 then
		return true
	end
	local distance = Services.RoomService.FootprintDistanceXZ(root, root.CFrame, match.TargetSocket.Position)
	return distance >= (match.Config.RequiredBlockerDisplacement or 3)
end

-- Everything physically covering the key right now (never includes held objects).
function MatchService.GetCoveringObjects(): { BasePart }
	if not match or not match.TargetSocket then
		return {}
	end
	local socket = match.TargetSocket
	local result, seen = {}, {}
	for _, root in ipairs(socket.Blockers) do
		if root.Parent and not isBlockerClear(root) then
			seen[root] = true
			table.insert(result, root)
		end
	end
	local folder = match.Runtime.Model:FindFirstChild("Clutter")
	if folder then
		local r = match.Config.SocketBlockerRadius or 1.4
		coverParams.FilterDescendantsInstances = { folder }
		for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(socket.Position + Vector3.new(0, 3, 0)), Vector3.new(r * 2, 6.5, r * 2), coverParams)) do
			local root = clutterRootOf(part)
			if root and not seen[root] and (root:GetAttribute("HeldByUserId") or 0) == 0 then
				seen[root] = true
				table.insert(result, root)
			end
		end
	end
	return result
end

local function checkTargetExposure()
	if not match or match.State ~= "Searching" or match.TargetRevealed then
		return
	end
	if #MatchService.GetCoveringObjects() == 0 then
		MatchService.RevealTarget()
	end
end

-- Where the key hides. Normal runs: a random spot, weighted toward deeper ones (packed chunks
-- count triple), under junk the first Strength upgrade can lift (Hard Mode: anything liftable).
-- A brand-new player's easy first run (match.Easy): a shallow spot under light junk close to
-- where they start (it glints through the pile, see glintKey).
local function selectTarget()
	local maxStrength = UpgradeConfig.GetValue("Strength", UpgradeConfig.GetMaxLevel("Strength"))
	local limit = if match.Hard then maxStrength else math.min(GameConfig.KeyMaxBlockerWeight or maxStrength, maxStrength)
	local starterWeight = UpgradeConfig.GetValue("Strength", 1)
	local spawnCF = getSpawnCFrame()
	local function collect(maxWeight: number)
		local list, total = {}, 0
		for _, socket in ipairs(match.Runtime.SocketList) do
			local depth, heaviest = 0, 0
			for _, b in ipairs(socket.Blockers) do
				heaviest = math.max(heaviest, b:GetAttribute("Weight") or 1)
				depth += b:GetAttribute("IsChunk") and 3 or 1
			end
			if #socket.Blockers > 0 and heaviest <= maxWeight then
				local weight = math.sqrt(depth)
				local distance = if spawnCF then Vector2.new(socket.Position.X - spawnCF.X, socket.Position.Z - spawnCF.Z).Magnitude else 0
				table.insert(list, { Socket = socket, Weight = weight, Depth = depth, Light = heaviest <= starterWeight, Distance = distance })
				total += weight
			end
		end
		return list, total
	end
	local eligible, total = collect(limit)
	if #eligible == 0 then
		eligible, total = collect(maxStrength)
	end
	assert(#eligible > 0, "Room has no exposable target sockets")
	if match.Easy then
		local pool = {}
		for _, e in ipairs(eligible) do
			if e.Light and e.Distance <= (GameConfig.EasySpotMaxDistance or math.huge) then
				table.insert(pool, e)
			end
		end
		if #pool == 0 then
			for _, e in ipairs(eligible) do
				if e.Light then
					table.insert(pool, e)
				end
			end
		end
		if #pool == 0 then
			pool = eligible
		end
		-- Closest and shallowest first.
		table.sort(pool, function(a, b)
			return a.Distance + a.Depth * 1.5 < b.Distance + b.Depth * 1.5
		end)
		match.TargetSocket = pool[match.Rng:NextInteger(1, math.min(3, #pool))].Socket
	else
		local roll = match.Rng:NextNumber() * total
		for _, e in ipairs(eligible) do
			roll -= e.Weight
			if roll <= 0 then
				match.TargetSocket = e.Socket
				break
			end
		end
	end
	match.TargetSocket = match.TargetSocket or eligible[#eligible].Socket
	-- The key is never inside packed junk: it shows only once its spot is dug clear, so opening
	-- packed junk everywhere can't find it (packed junk pays a reward instead, ChunkService).
	match.KeyChunk = nil
end

-- Silently clean objects as if deposited, no Cash (checkpoint resume + dev tools).
local function preClean(fraction: number, clearTarget: boolean?)
	local runtime = match.Runtime
	local socket = match.TargetSocket
	local list = {}
	if clearTarget then
		list = MatchService.GetCoveringObjects()
	else
		-- Rounded up, so "25%" really reaches 25% (checkpoints and the mastery star sit there).
		local want = math.ceil(runtime.TotalObjects * math.clamp(fraction, 0, 0.95)) - runtime.DepositedCount
		if want <= 0 then
			return
		end
		local protected = {}
		for _, b in ipairs(socket.Blockers) do
			protected[b] = true
		end
		local candidates = {}
		for _, root in ipairs(runtime.Objects) do
			if root.Parent and not protected[root] and not root:GetAttribute("IsChunk") and not Services.ObjectService.IsBusy(root)
				and Services.RoomService.FootprintDistanceXZ(root, root.CFrame, socket.Position) > 4 then
				table.insert(candidates, root)
			end
		end
		-- Highest objects first keeps every remaining stack physically supported.
		table.sort(candidates, function(a, b)
			return a.Position.Y > b.Position.Y
		end)
		for i = 1, math.min(want, #candidates) do
			list[i] = candidates[i]
		end
	end
	for _, root in ipairs(list) do
		if root.Parent then
			-- A packed chunk counts as every object inside it.
			runtime.DepositedCount += root:GetAttribute("IsChunk") and #string.split(root:GetAttribute("Contents") or "", ",") or 1
			if root:GetAttribute("Category") == "Treasure" then
				match.TreasuresCleaned = (match.TreasuresCleaned or 0) + 1
			end
			Services.ObjectService.Forget(root)
			root:Destroy()
		end
	end
end

local function publishProgress()
	local progress = Services.RoomService.GetProgress(match.Runtime)
	local old = match.Progress
	match.Progress = progress
	stateConfig:SetAttribute("Progress", progress)
	stateConfig:SetAttribute("CleanedObjects", match.Runtime.DepositedCount)
	return old, progress
end

-- The junk over the key shivers when a player's hands are close: a physical "you're warm".
local lastRattle = 0
local rattleRng = Random.new()
local function rattleKey()
	if match.State ~= "Searching" or match.TargetRevealed or os.clock() - lastRattle < GameConfig.KeyRattleInterval then
		return
	end
	local socket = match.TargetSocket.Position
	local near = {}
	for _, player in ipairs(match.Players) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and Vector2.new(root.Position.X - socket.X, root.Position.Z - socket.Z).Magnitude <= GameConfig.KeyRattleDistance then
			table.insert(near, player)
		end
	end
	if #near == 0 then
		return
	end
	lastRattle = os.clock()
	for _, root in ipairs(MatchService.GetCoveringObjects()) do
		if not Services.ObjectService.GetHolder(root) then
			-- Resting junk is anchored: it hops loose and goes dead again once it lands.
			if root.Anchored then
				Services.ObjectService.Activate(root)
			end
			root.AssemblyLinearVelocity += Vector3.new(rattleRng:NextNumber(-1.2, 1.2), rattleRng:NextNumber(2.5, 4), rattleRng:NextNumber(-1.2, 1.2))
			root.AssemblyAngularVelocity += Vector3.new(rattleRng:NextNumber(-3, 3), rattleRng:NextNumber(-3, 3), rattleRng:NextNumber(-3, 3))
		end
	end
	for _, player in ipairs(near) do
		Remotes.Event("FXEvent"):FireClient(player, "KeyRattle", { Position = socket })
	end
end

-- The easy first run: something shiny glints on top of the pile over the key.
local glintParams = RaycastParams.new()
glintParams.FilterType = Enum.RaycastFilterType.Include
local lastGlint = 0
local function glintKey()
	if not match.Easy or match.State ~= "Searching" or match.TargetRevealed or os.clock() - lastGlint < (GameConfig.KeyGlintInterval or 3) then
		return
	end
	lastGlint = os.clock()
	local socket = match.TargetSocket.Position
	local top = socket
	local folder = match.Runtime.Model:FindFirstChild("Clutter")
	if folder then
		glintParams.FilterDescendantsInstances = { folder }
		local hit = workspace:Raycast(socket + Vector3.new(0, 30, 0), Vector3.new(0, -32, 0), glintParams)
		if hit then
			top = hit.Position
		end
	end
	for _, player in ipairs(match.Players) do
		if player.Parent then
			Remotes.Event("FXEvent"):FireClient(player, "KeyGlint", { Position = top + Vector3.new(0, 0.4, 0) })
		end
	end
end

-- One snapshot per minute of searching. Roblox drops events sent while a player is leaving, so
-- a player's last snapshot is how we know how long they stayed and how far they got.
local function logRoomMinute()
	if match.State ~= "Searching" or match.StartTime <= 0 then
		return
	end
	local minute = math.floor((now() - match.StartTime) / 60)
	if minute > (match.LoggedMinute or 0) and minute <= 30 then
		match.LoggedMinute = minute
		Services.AnalyticsService.RoomMinute(match, minute)
	end
end

function MatchService.Init(role: string)
	serverRole = role
	stateConfig = Instance.new("Configuration")
	stateConfig.Name = "MatchState"
	stateConfig.Parent = ReplicatedStorage
	resetStateConfig()

	Remotes.Event("ReturnToLobby").OnServerEvent:Connect(function(player)
		if match and (match.State == "Results" or match.State == "Returning") then
			MatchService.ReturnPlayer(player)
		end
	end)
	Remotes.Event("PlayNext").OnServerEvent:Connect(function(player)
		MatchService.RequestNext(player)
	end)
	-- The room's exit door (ExitDoorController): back to a lobby server at any time.
	Remotes.Event("LeaveRoom").OnServerEvent:Connect(function(player)
		if not match or not table.find(match.Players, player) or match.State == "Ended" or player:GetAttribute("Leaving") then
			return
		end
		local door = match.Runtime and match.Runtime.ExitDoor
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not door or not root or (root.Position - door.Position).Magnitude > 14 then
			return
		end
		player:SetAttribute("Leaving", true)
		task.delay(10, function()
			if player.Parent then
				player:SetAttribute("Leaving", nil)
			end
		end)
		Services.AnalyticsService.RoomEnded(player, "exit_door", match)
		MatchService.ReturnPlayer(player)
	end)
	Remotes.Event("TutorialComplete").OnServerEvent:Connect(function(player)
		Services.DataService.Update(player, function(data)
			data.TutorialCompleted = true
		end)
		Services.AnalyticsService.TutorialFinished(player)
	end)
	Remotes.Event("UpdateSettings").OnServerEvent:Connect(function(player, settings)
		if type(settings) ~= "table" then
			return
		end
		local changed = {}
		Services.DataService.Update(player, function(data)
			for _, key in ipairs({ "Music", "SFX", "ReduceVFX", "CameraShake" }) do
				if type(settings[key]) == "boolean" then
					if data.Settings[key] ~= settings[key] then
						table.insert(changed, key)
					end
					data.Settings[key] = settings[key]
				end
			end
		end)
		for _, key in ipairs(changed) do
			Services.AnalyticsService.Event(player, "setting_changed", 1, key, settings[key] and "on" or "off")
		end
	end)
	-- A player's game finished loading its controllers (init.client).
	Remotes.Event("ClientReady").OnServerEvent:Connect(function(player)
		readyClients[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player)
		readyClients[player] = nil
		MatchService.RemovePlayer(player)
	end)
end

-- Invisible walls around the lobby's footprint, rising well above its tallest point, so nobody
-- walks or jumps off the edge. Fully transparent, so the camera never zooms in because of them.
local function buildLobbyBounds(lobby: Model)
	local box, size = lobby:GetBoundingBox()
	local thickness = 2
	local height = size.Y + 40
	local centerY = box.Position.Y - size.Y / 2 + height / 2
	local folder = Instance.new("Folder")
	folder.Name = "LobbyBounds"
	local function wall(x: number, z: number, sizeX: number, sizeZ: number)
		local part = Instance.new("Part")
		part.Name = "LobbyWall"
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(sizeX, height, sizeZ)
		part.CFrame = CFrame.new(x, centerY, z)
		part.Parent = folder
	end
	local cx, cz, hx, hz = box.Position.X, box.Position.Z, size.X / 2, size.Z / 2
	wall(cx + hx + thickness / 2, cz, thickness, size.Z + thickness * 2)
	wall(cx - hx - thickness / 2, cz, thickness, size.Z + thickness * 2)
	wall(cx, cz + hz + thickness / 2, size.X + thickness * 2, thickness)
	wall(cx, cz - hz - thickness / 2, size.X + thickness * 2, thickness)
	folder.Parent = workspace
end

function MatchService.Start(role: string)
	if role == "Combined" or role == "Lobby" then
		-- Workspace.Lobby is authored in Studio and is the only lobby; nothing is generated.
		lobbyModel = workspace:FindFirstChild("Lobby")
		if lobbyModel then
			for _, inst in ipairs(CollectionService:GetTagged("LobbySpawn")) do
				if inst:IsA("BasePart") and inst:IsDescendantOf(lobbyModel) then
					lobbySpawn = inst
				end
			end
			lobbySpawn = lobbySpawn or lobbyModel:FindFirstChild("LobbySpawn", true) :: BasePart?
			Services.QueueService.DiscoverZones(lobbyModel)
			buildLobbyBounds(lobbyModel :: Model)
		else
			warn("[MatchService] Workspace.Lobby not found - matchmaking circles disabled (DEV panel can still start rooms).")
		end
	end
	if role == "Match" then
		task.spawn(MatchService.StartFromTeleport)
	end

	-- Fall protection, plus a regular exposure check: loose piles can shift on their own.
	task.spawn(function()
		while true do
			task.wait(1)
			if match and match.Runtime then
				checkTargetExposure()
				Services.HintService.RefreshOutline(match)
				if match.TargetSocket then
					rattleKey()
					glintKey()
				end
				logRoomMinute()
				for _, player in ipairs(match.Players) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and root.Position.Y < match.Runtime.FloorY - GameConfig.FallProtectionDepth then
						local spawnCF = getSpawnCFrame()
						if spawnCF then
							moveCharacterTo(player, spawnCF)
						end
					end
				end
			end
		end
	end)
end

function MatchService.GetMatch()
	return match
end

function MatchService.GetMatchForPlayer(player: Player)
	if match and table.find(match.Players, player) then
		return match
	end
	return nil
end

function MatchService.IsPlayerInMatch(player: Player): boolean
	return MatchService.GetMatchForPlayer(player) ~= nil
end

function MatchService.OnCharacterAdded(player: Player, character: Model)
	if MatchService.IsPlayerInMatch(player) then
		task.defer(function()
			local spawnCF = getSpawnCFrame()
			if spawnCF and character.Parent then
				moveCharacterTo(player, spawnCF)
			end
		end)
	end
end

export type LaunchParams = {
	Players: { Player },
	RoomId: number,
	PartySize: number,
	ResumePercent: number,
	Seed: number,
	MatchId: string,
	Hard: boolean?,
	Easy: boolean?, -- a brand-new player's first run: the object sits in a shallow spot
	PartySessions: { [string]: string }?, -- analytics party ids by UserId (from the teleport)
}

function MatchService.StartLocalMatch(params: LaunchParams): boolean
	if match and match.State ~= "Ended" then
		Services.NotificationService.SendMany(params.Players, "Warning", "A test match is already running. Wait for it to finish.")
		return false
	end
	return MatchService.BeginMatch(params, CFrame.new(GameConfig.CombinedRoomOffset))
end

function MatchService.StartFromTeleport()
	local firstPlayer = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local joinData = firstPlayer:GetJoinData()
	local data = joinData and joinData.TeleportData or {}
	local roomId = tonumber(data.RoomId) or 1
	if not RoomRegistry.Exists(roomId) then
		roomId = 1
	end
	local expected = data.ExpectedUserIds or {}
	local partySize = math.clamp(tonumber(data.PartySize) or math.max(1, #expected), 1, GameConfig.MaxPartySize)
	local deadline = os.clock() + GameConfig.MatchWaitForPartySeconds
	while os.clock() < deadline do
		local present = 0
		for _, uid in ipairs(expected) do
			if Players:GetPlayerByUserId(uid) then
				present += 1
			end
		end
		if #expected == 0 or present >= #expected then
			break
		end
		task.wait(0.5)
	end
	local partyPlayers = Players:GetPlayers()
	for _, p in ipairs(partyPlayers) do
		Services.DataService.WaitFor(p, 10)
	end
	-- Everyone's game must have loaded before the intro starts, or slow phones miss the intro
	-- and countdown (and sit behind the loading screen while the others search).
	local readyBy = os.clock() + (GameConfig.ClientReadyWaitSeconds or 20)
	while os.clock() < readyBy do
		local waiting = false
		for _, p in ipairs(partyPlayers) do
			if p.Parent and not readyClients[p] then
				waiting = true
			end
		end
		if not waiting then
			break
		end
		task.wait(0.2)
	end
	-- From pressing PLAY to ready here: the whole trip, teleport included.
	local launchedAt = tonumber(data.LaunchedAt)
	if launchedAt then
		for _, p in ipairs(partyPlayers) do
			Services.AnalyticsService.Event(p, "match_ready_seconds", math.max(0, os.time() - launchedAt), readyClients[p] and "loaded" or "timed out")
		end
	end
	MatchService.BeginMatch({
		Players = partyPlayers,
		RoomId = roomId,
		PartySize = partySize,
		ResumePercent = tonumber(data.ResumePercent) or 0,
		Seed = tonumber(data.Seed) or Random.new():NextInteger(1, 2 ^ 30),
		MatchId = tostring(data.MatchId or "local"),
		Hard = data.Hard == true,
		Easy = data.Easy == true,
		PartySessions = type(data.PartySessions) == "table" and data.PartySessions or nil,
	}, CFrame.new(GameConfig.CombinedRoomOffset))
end

-- Hard Mode: the same room with its HardMode overrides (more packed junk). Records don't count.
local function hardVariant(config)
	local hard = table.clone(config)
	for key, value in pairs(config.HardMode or {}) do
		hard[key] = value
	end
	return hard
end

function MatchService.BeginMatch(params: LaunchParams, origin: CFrame): boolean
	local config = RoomRegistry.Get(params.RoomId)
	if not config then
		warn("[MatchService] Unknown room", params.RoomId)
		return false
	end
	if params.Hard then
		config = hardVariant(config)
	end
	local players = {}
	for _, p in ipairs(params.Players) do
		if p.Parent then
			table.insert(players, p)
		end
	end
	if #players == 0 then
		return false
	end

	local runtime = Services.RoomService.Build(config, origin)
	Services.ObjectService.SetRoom(runtime)
	-- Hand every object to real physics. The room settles behind the intro (the loading screen
	-- stays up), is anchored where it came to rest, and the key goes in: see the start sequence.
	Services.RoomService.Release(runtime)
	local releasedAt = os.clock()

	match = {
		Id = params.MatchId,
		RoomId = params.RoomId,
		Config = config,
		Seed = params.Seed,
		Rng = Random.new(params.Seed),
		PartySize = params.PartySize,
		Players = players,
		State = "Loading",
		StartTime = 0,
		EndTime = 0,
		Progress = 0,
		Runtime = runtime,
		TargetSocket = nil,
		TargetRevealed = false,
		TargetFound = false,
		FinderUserId = 0,
		TargetModel = nil,
		HintStage = 0,
		TeamMuscleExpires = 0,
		ResumePercent = params.ResumePercent or 0,
		ClaimLock = false,
		Hard = params.Hard == true,
		Easy = params.Easy == true and not params.Hard,
		PartySessions = params.PartySessions,
	}

	-- Treasures in the room (loose + packed in junk) for the treasure mastery star.
	local treasures = 0
	for _, obj in ipairs(runtime.Objects) do
		if obj:GetAttribute("Category") == "Treasure" then
			treasures += 1
		elseif obj:GetAttribute("IsChunk") then
			for _, key in ipairs(string.split(obj:GetAttribute("Contents") or "", ",")) do
				if string.sub(key, 1, 9) == "Treasure_" then
					treasures += 1
				end
			end
		end
	end
	match.TreasuresTotal = treasures
	match.TreasuresCleaned = 0

	resetStateConfig()
	stateConfig:SetAttribute("RoomId", config.Id)
	stateConfig:SetAttribute("RoomName", config.Name)
	stateConfig:SetAttribute("RoomNumber", config.DisplayNumber)
	stateConfig:SetAttribute("TargetName", config.TargetName)
	stateConfig:SetAttribute("TargetId", config.TargetId)
	stateConfig:SetAttribute("PartySize", params.PartySize)
	stateConfig:SetAttribute("TotalObjects", runtime.TotalObjects)
	stateConfig:SetAttribute("PlayerNames", playerNamesString(players))
	stateConfig:SetAttribute("ResumePercent", match.ResumePercent)
	stateConfig:SetAttribute("TreasuresTotal", match.TreasuresTotal)
	stateConfig:SetAttribute("TreasuresCleaned", match.TreasuresCleaned)
	stateConfig:SetAttribute("Hard", match.Hard)
	stateConfig:SetAttribute("Easy", match.Easy)
	-- Where the room sits, so the map can place things (room-local = origin space).
	stateConfig:SetAttribute("RoomOrigin", origin)
	publishProgress()
	setState("Loading")

	for _, player in ipairs(players) do
		Services.PlayerSessionService.Reset(player)
		local cp = Services.CheckpointService.GetCheckpoint(player, config.Id)
		if cp and match.ResumePercent > 0 then
			Services.PlayerSessionService.RestoreFromCheckpoint(player, cp)
		end
		-- A player's very first room (the tutorial) gets one upgrade free (see UpgradeService).
		local data = Services.DataService.Get(player)
		player:SetAttribute("FreeUpgrade", data ~= nil and data.TutorialCompleted ~= true)
		player:SetAttribute("InMatch", true)
		player:SetAttribute("MatchId", match.Id)
		Services.PlayerSessionService.RecomputeDerived(player)
		Services.WalletService.ResetRoom(player)
		local spawnCF = getSpawnCFrame()
		if spawnCF and player.Character then
			moveCharacterTo(player, spawnCF)
		end
	end
	Services.RetentionService.SetupFriendBonus(players)

	fireMatch("Intro", {
		RoomNumber = config.DisplayNumber,
		RoomName = config.Name,
		TargetName = config.TargetName,
		TargetId = config.TargetId,
		ResumePercent = match.ResumePercent,
		Hard = match.Hard,
	})
	task.spawn(function()
		local thisMatch = match
		-- The room settles behind the intro and goes dead (anchored); then the key goes in and the
		-- 3, 2, 1 starts.
		local settled, loose = Services.RoomService.FinishSettle(runtime, releasedAt, GameConfig.RoomSettleSeconds)
		if match ~= thisMatch then
			return
		end
		local falling = Services.ObjectService.FreezeRoom(loose)
		print(string.format("[MatchService] %d objects settled in %.1fs and anchored (%d still falling)", #runtime.Objects, settled, falling))
		selectTarget()
		if match.ResumePercent > 0 then
			preClean(match.ResumePercent)
			stateConfig:SetAttribute("TreasuresCleaned", match.TreasuresCleaned)
		end
		publishProgress()
		Services.HintService.ResetForMatch(match)
		local ok, report = RoomValidator.Validate(runtime, config)
		if RunService:IsStudio() or not ok then
			print(report)
		end
		-- The room name and the object reveal always get their moment.
		task.wait(math.max(0, GameConfig.IntroMinSeconds - (os.clock() - releasedAt)))
		if match ~= thisMatch then
			return
		end
		setState("Countdown")
		task.wait(GameConfig.CountdownSeconds)
		if match ~= thisMatch then
			return
		end
		match.StartTime = now()
		stateConfig:SetAttribute("StartTime", match.StartTime)
		-- The room's heaps become goals (after a resumed room's pre-clean).
		Services.PileService.Setup(match)
		setState("Searching")
		fireMatch("Started", {})
		match.LoggedMinute = 0
		Services.HintService.StartClock(match)
		Services.AnalyticsService.RoomStarted(match, os.clock() - releasedAt)
		checkTargetExposure()
		-- Hints bought while they couldn't be used are delivered now.
		for _, player in ipairs(match.Players) do
			Services.MonetizationService.ApplyBanked(player)
		end
	end)
	return true
end

-- ===== ObjectService callbacks =====

function MatchService.OnObjectDeposited(_player: Player?, treasure: boolean?)
	if not match then
		return
	end
	match.Runtime.DepositedCount += 1
	if treasure then
		match.TreasuresCleaned = (match.TreasuresCleaned or 0) + 1
		stateConfig:SetAttribute("TreasuresCleaned", match.TreasuresCleaned)
	end
	local old, progress = publishProgress()
	Services.HintService.OnDeposit(match)
	Services.CheckpointService.OnProgress(match, old, progress)
	checkTargetExposure()
end

-- Packed junk was broken open: if it lay on the key's spot, the spot may be clear now.
function MatchService.OnChunkBurst(_chunk: Instance, _position: Vector3)
	checkTargetExposure()
end

function MatchService.OnObjectSettled(_root: BasePart)
	if match then
		checkTargetExposure()
		Services.HintService.RefreshOutline(match)
	end
end

function MatchService.OnObjectGrabbed(_root: BasePart)
	if match then
		checkTargetExposure()
		Services.HintService.RefreshOutline(match)
	end
end

-- ===== Players =====

function MatchService.RemovePlayer(player: Player)
	if not match then
		return
	end
	local idx = table.find(match.Players, player)
	if idx then
		table.remove(match.Players, idx)
		Services.ObjectService.Drop(player)
		stateConfig:SetAttribute("PlayerNames", playerNamesString(match.Players))
		-- No-op if their run already ended (key found, exit door).
		Services.AnalyticsService.RoomEnded(player, "left_game", match)
	end
	if #match.Players == 0 and match.State ~= "Ended" then
		task.delay(3, function()
			if match and #match.Players == 0 then
				MatchService.EndMatch()
			end
		end)
	end
end

-- ===== Target =====

local function verticalHalfExtent(part: BasePart): number
	local cf, size = part.CFrame, part.Size
	return (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
end

-- Top of the floor/furniture directly under a point, rugs included (they are decor, so a
-- raycast would miss them).
local function surfaceBelow(point: Vector3): number
	local best = match.Runtime.FloorY
	for _, part in ipairs(match.Runtime.StructureParts) do
		local lp = part.CFrame:PointToObjectSpace(point)
		if math.abs(lp.X) <= part.Size.X / 2 and math.abs(lp.Z) <= part.Size.Z / 2 then
			local top = part.Position.Y + verticalHalfExtent(part)
			if top <= point.Y + 0.05 and top > best then
				best = top
			end
		end
	end
	return best
end

function MatchService.RevealTarget()
	if not match or match.TargetRevealed then
		return
	end
	match.TargetRevealed = true
	local socket = match.TargetSocket
	local model = TargetBuilder.Get(match.Config.TargetId)
	model.Name = "HiddenTarget"
	if model.PrimaryPart then
		-- Target models are authored standing in the XY plane. Spin around the world's vertical
		-- axis first, then lay it down, so it always lies flat with a random heading.
		local yaw = match.Rng:NextNumber(0, math.pi * 2)
		model:PivotTo(CFrame.new(socket.Position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(90), 0, 0))
		-- Rest its lowest point on the real surface, whatever the model's shape.
		local lowest = math.huge
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				lowest = math.min(lowest, d.Position.Y - verticalHalfExtent(d))
			end
		end
		if lowest < math.huge then
			model:PivotTo(model:GetPivot() + Vector3.new(0, surfaceBelow(socket.Position) + 0.02 - lowest, 0))
		end
	end
	model:SetAttribute("IsTarget", true)
	CollectionService:AddTag(model, "HiddenTarget")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FindPrompt"
	prompt.ActionText = "Find"
	prompt.ObjectText = match.Config.TargetName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Custom -- drawn by the client's PromptController
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		MatchService.OnTargetClaim(player)
	end)

	model.Parent = match.Runtime.Model
	match.TargetModel = model
	stateConfig:SetAttribute("TargetRevealed", true)
	stateConfig:SetAttribute("OutlinedObjects", "")
	fireMatch("TargetRevealed", { Position = model.PrimaryPart and model.PrimaryPart.Position })
	Services.AnalyticsService.KeyUncovered(match, match.StartTime > 0 and math.max(0, now() - match.StartTime) or 0)
end

function MatchService.OnTargetClaim(player: Player)
	if not match or match.State ~= "Searching" or not match.TargetRevealed or match.TargetFound or match.ClaimLock then
		return
	end
	if not table.find(match.Players, player) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local targetPart = match.TargetModel and match.TargetModel.PrimaryPart
	if not root or not targetPart or (root.Position - targetPart.Position).Magnitude > 14 then
		return
	end
	match.ClaimLock = true
	match.TargetFound = true
	match.FinderUserId = player.UserId
	MatchService.CompleteMatch(player)
end

function MatchService.CompleteMatch(finder: Player)
	local thisMatch = match
	setState("TargetFound")
	match.EndTime = now()
	local elapsed = math.max(0, match.EndTime - match.StartTime)
	stateConfig:SetAttribute("EndTime", match.EndTime)
	stateConfig:SetAttribute("TargetFound", true)
	stateConfig:SetAttribute("FinderName", finder.Name)
	for _, player in ipairs(match.Players) do
		Services.ObjectService.Drop(player)
	end
	local roomId = match.RoomId

	-- Save FIRST, then celebrate.
	local starsByUser = {}
	local newBestByUser = {} -- runs that set a best time (the results screen says NEW BEST only for these)
	local canNextByUser = {} -- who has the next room unlocked (their results screen counts down to it)
	for _, player in ipairs(match.Players) do
		local firstClear = false
		Services.DataService.Update(player, function(data)
			data.TotalMessCleared += player:GetAttribute("ObjectsCleaned") or 0
			-- Collection progress is strictly sequential: only the player's next required room counts.
			if data.HighestRoomCompleted + 1 == roomId then
				data.HighestRoomCompleted = roomId
				data.ObjectsFound = math.max(data.ObjectsFound, roomId)
				firstClear = true
			end
			if player == finder then
				data.FinderWins += 1
			end
			local key = tostring(roomId)
			if not match.DevCompleted and not match.Hard and elapsed >= GameConfig.MinimumLegitimateRoomTime and (not data.BestTimes[key] or elapsed < data.BestTimes[key]) then
				data.BestTimes[key] = math.floor(elapsed)
				newBestByUser[tostring(player.UserId)] = true
			end
		end)
		Services.CheckpointService.ClearForRoom(player, roomId)
		starsByUser[tostring(player.UserId)] = Services.ProgressionService.OnRoomComplete(player, match, player == finder, firstClear)
		canNextByUser[tostring(player.UserId)] = Services.QueueService.CanPlayRoom(player, roomId + 1)
		task.defer(Services.RetentionService.First, player, "Room")
		-- A Mega room's first clear: a guaranteed Rare-or-better egg (hatched after the results).
		if firstClear and match.Config.FirstClearEgg then
			local eggKey = match.Config.FirstClearEgg
			task.delay(GameConfig.CeremonySeconds + 1.5, function()
				if player.Parent then
					Services.PetService.GrantEgg(player, eggKey, "MegaRoom")
					Services.ProgressionService.RefreshTag(player)
				end
			end)
		end
		Services.DataService.Save(player)
		local data = Services.DataService.Get(player)
		if data then
			Services.LeaderboardService.SubmitObjectsFound(player, data.ObjectsFound)
			Services.LeaderboardService.SubmitMostCleaned(player, data.TotalMessCleared)
			if not match.DevCompleted and not match.Hard then
				Services.LeaderboardService.SubmitRoomTime(player, roomId, elapsed)
			end
		end
		Services.MonetizationService.CheckBadges(player)
	end
	Services.AnalyticsService.KeyFound(match, finder, elapsed)

	local contributions = {}
	for _, player in ipairs(match.Players) do
		table.insert(contributions, { Name = player.Name, UserId = player.UserId, Objects = player:GetAttribute("ObjectsCleaned") or 0 })
	end
	table.sort(contributions, function(a, b)
		return a.Objects > b.Objects
	end)

	fireMatch("TargetFound", {
		FinderName = finder.Name,
		FinderUserId = finder.UserId,
		TargetName = match.Config.TargetName,
		TargetId = match.Config.TargetId,
		ObjectNumber = roomId,
		TargetPosition = match.TargetModel and match.TargetModel.PrimaryPart and match.TargetModel.PrimaryPart.Position,
	})

	task.delay(GameConfig.CeremonySeconds, function()
		if match ~= thisMatch then
			return
		end
		setState("Results")
		fireMatch("Results", {
			RoomNumber = match.Config.DisplayNumber,
			RoomName = match.Config.Name,
			TargetName = match.Config.TargetName,
			TargetId = match.Config.TargetId,
			ObjectNumber = roomId,
			FinderName = finder.Name,
			Elapsed = elapsed,
			TeamSize = match.PartySize,
			Contributions = contributions,
			RoomSearched = match.Progress,
			Stars = starsByUser,
			NewBest = newBestByUser,
			Hard = match.Hard,
			TreasuresTotal = match.TreasuresTotal,
			TreasuresCleaned = match.TreasuresCleaned,
			NextRoomAvailable = RoomRegistry.Exists(roomId + 1),
			CanNext = canNextByUser,
			AutoNextSeconds = RetentionConfig.AutoNextSeconds,
			TotalObjects = GameConfig.TotalObjects,
		})
	end)
end

-- ===== Next room =====

-- Everyone who chose NEXT ROOM goes on together to a fresh room (a new match server, or here in
-- Studio); the rest stay on the results screen.
local function launchNext(thisMatch)
	if match ~= thisMatch or thisMatch.NextLaunched then
		return
	end
	thisMatch.NextLaunched = true
	local party = {}
	for _, p in ipairs(thisMatch.Players) do
		if p.Parent and thisMatch.NextVotes[p] then
			table.insert(party, p)
		end
	end
	if #party == 0 then
		return
	end
	local nextId = thisMatch.RoomId + 1
	local launch = {
		Players = party,
		RoomId = nextId,
		ResumePercent = Services.CheckpointService.ResolveResumePercent(party, nextId),
		QueueId = "NextRoom",
		Hard = false,
	}
	if serverRole == "Match" then
		for _, p in ipairs(party) do
			p:SetAttribute("Teleporting", true)
		end
		if not Services.TeleportServiceWrapper.TeleportParty(launch) then
			for _, p in ipairs(party) do
				p:SetAttribute("Teleporting", false)
			end
			thisMatch.NextLaunched, thisMatch.NextVotes, thisMatch.NextTimer = false, {}, false
		end
		return
	end
	-- Studio (Combined): this room ends and the next one is built here.
	MatchService.EndMatch()
	for _, p in ipairs(party) do
		p:SetAttribute("Teleporting", true)
	end
	task.wait(0.5)
	Services.TeleportServiceWrapper.TeleportParty(launch)
	for _, p in ipairs(party) do
		if p.Parent then
			p:SetAttribute("Teleporting", false)
		end
	end
end

function MatchService.RequestNext(player: Player)
	if not match or match.State ~= "Results" or not table.find(match.Players, player) or match.NextLaunched then
		return
	end
	local nextId = match.RoomId + 1
	if not RoomRegistry.Exists(nextId) then
		return
	end
	if not Services.QueueService.CanPlayRoom(player, nextId) then
		Services.NotificationService.Send(player, "Warning", string.format("Room #%03d unlocks once you find the object in Room #%03d.", nextId, nextId - 1))
		return
	end
	match.NextVotes = match.NextVotes or {}
	if match.NextVotes[player] then
		return
	end
	match.NextVotes[player] = true
	Services.AnalyticsService.Event(player, "next_room", nextId, #match.Players <= 1 and "solo" or "party")
	local waiting = 0
	for _, p in ipairs(match.Players) do
		if not match.NextVotes[p] then
			waiting += 1
		end
	end
	local thisMatch = match
	if waiting == 0 then
		task.spawn(launchNext, thisMatch)
	else
		Services.NotificationService.Send(player, "Info", string.format("Waiting for your party (%ds)...", RetentionConfig.NextRoomVoteSeconds))
		if not match.NextTimer then
			match.NextTimer = true
			task.delay(RetentionConfig.NextRoomVoteSeconds, launchNext, thisMatch)
		end
	end
end

function MatchService.ReturnPlayer(player: Player)
	if not match then
		return
	end
	if serverRole == "Match" then
		Services.TeleportServiceWrapper.ReturnToLobby(player)
		return
	end
	MatchService.MovePlayerToLobby(player)
end

function MatchService.MovePlayerToLobby(player: Player)
	local wasInMatch = match and table.find(match.Players, player)
	if match and wasInMatch then
		table.remove(match.Players, wasInMatch)
	end
	Services.ObjectService.Drop(player)
	Services.PlayerSessionService.Reset(player)
	player:SetAttribute("InMatch", false)
	player:SetAttribute("MatchId", "")
	Remotes.Event("MatchUpdate"):FireClient(player, "ReturnedToLobby", {})
	if lobbySpawn and player.Character then
		moveCharacterTo(player, lobbySpawn.CFrame * CFrame.new(0, 2, 0))
	end
	if wasInMatch and match and #match.Players == 0 then
		MatchService.EndMatch()
	end
end

function MatchService.EndMatch()
	if not match then
		return
	end
	setState("Ended")
	local runtime = match.Runtime
	local remaining = table.clone(match.Players)
	Services.ObjectService.ClearRoom()
	match = nil
	resetStateConfig()
	Services.HintService.ResetForMatch(nil)
	Services.PileService.Reset()
	for _, player in ipairs(remaining) do
		if serverRole ~= "Match" then
			MatchService.MovePlayerToLobby(player)
		end
	end
	if runtime then
		Services.RoomService.Destroy(runtime)
	end
end

-- ===== Developer helpers =====

function MatchService.ForceProgress(fraction: number)
	if match and match.State == "Searching" then
		preClean(fraction)
		local old, progress = publishProgress()
		Services.CheckpointService.OnProgress(match, old, progress)
	end
end

function MatchService.ForceReveal()
	if match and match.State == "Searching" and not match.TargetRevealed then
		preClean(0, true)
		publishProgress()
		checkTargetExposure()
		if not match.TargetRevealed then
			MatchService.RevealTarget()
		end
	end
end

function MatchService.ForceComplete(player: Player)
	if not match or match.State ~= "Searching" then
		return
	end
	if not match.TargetRevealed then
		MatchService.ForceReveal()
	end
	match.ClaimLock = true
	match.TargetFound = true
	match.DevCompleted = true -- a dev shortcut never counts as a best time or a Fastest entry
	match.FinderUserId = player.UserId
	MatchService.CompleteMatch(player)
end

function MatchService.GetTargetInfo()
	if not match or not match.TargetSocket then
		return nil
	end
	local ids = {}
	local depth, heaviest = 0, 0
	for _, b in ipairs(match.TargetSocket.Blockers) do
		table.insert(ids, b:GetAttribute("ObjectId"))
		depth += b:GetAttribute("IsChunk") and 3 or 1
		heaviest = math.max(heaviest, b:GetAttribute("Weight") or 1)
	end
	return {
		SocketId = match.TargetSocket.Id,
		RegionId = match.TargetSocket.RegionId,
		Position = match.TargetSocket.Position,
		Blockers = #match.TargetSocket.Blockers,
		KeyChunk = match.KeyChunk and match.KeyChunk.Parent and match.KeyChunk.Position or nil,
		BlockerIds = ids,
		Covering = #MatchService.GetCoveringObjects(),
		Revealed = match.TargetRevealed,
		Depth = depth,
		Heaviest = heaviest,
		Easy = match.Easy == true,
	}
end

function MatchService.GetStateConfig(): Configuration
	return stateConfig
end

return MatchService
