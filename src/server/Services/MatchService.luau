--[[
	Server-authoritative match state machine. One match per server (reserved match servers
	hold exactly one party; the Combined dev server runs one local match at a time).

	States: Loading -> Countdown -> Searching -> TargetFound -> Results -> Returning -> Ended

	The Golden Key is revealed ONLY when nothing physically covers its socket: every original
	blocker has been moved away (or is being held) and no other object lies on the spot.
	Room progress = ROOM CLEANED (objects deposited in bins / every real object in the room,
	packed junk included). It drives hints and checkpoints, never the reveal.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
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

-- Random hiding spot, weighted toward DEEP ones (more junk on top, packed chunks count triple):
-- finding the key should take real digging, while shallow lucky finds stay possible but rare.
local function selectTarget()
	local maxWeight = UpgradeConfig.GetValue("Strength", UpgradeConfig.GetMaxLevel("Strength"))
	local eligible, total = {}, 0
	for _, socket in ipairs(match.Runtime.SocketList) do
		local ok = #socket.Blockers > 0
		local depth = 0
		for _, b in ipairs(socket.Blockers) do
			if (b:GetAttribute("Weight") or 1) > maxWeight then
				ok = false
			end
			depth += b:GetAttribute("IsChunk") and 3 or 1
		end
		if ok then
			table.insert(eligible, { Socket = socket, Weight = depth })
			total += depth
		end
	end
	assert(#eligible > 0, "Room has no exposable target sockets")
	local roll = match.Rng:NextNumber() * total
	for _, e in ipairs(eligible) do
		roll -= e.Weight
		if roll <= 0 then
			match.TargetSocket = e.Socket
			break
		end
	end
	match.TargetSocket = match.TargetSocket or eligible[#eligible].Socket
	-- The lowest packed junk on the spot secretly holds the key: breaking it open releases it.
	local keyChunk, lowest = nil, math.huge
	for _, b in ipairs(match.TargetSocket.Blockers) do
		if b:GetAttribute("IsChunk") and b.Position.Y < lowest then
			keyChunk, lowest = b, b.Position.Y
		end
	end
	match.KeyChunk = keyChunk
end

-- Silently clean objects as if deposited, no Cash (checkpoint resume + dev tools).
local function preClean(fraction: number, clearTarget: boolean?)
	local runtime = match.Runtime
	local socket = match.TargetSocket
	local list = {}
	if clearTarget then
		list = MatchService.GetCoveringObjects()
	else
		local want = math.floor(runtime.TotalObjects * math.clamp(fraction, 0, 0.95)) - runtime.DepositedCount
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
		if not root.Anchored then
			root.AssemblyLinearVelocity += Vector3.new(rattleRng:NextNumber(-1.2, 1.2), rattleRng:NextNumber(2.5, 4), rattleRng:NextNumber(-1.2, 1.2))
			root.AssemblyAngularVelocity += Vector3.new(rattleRng:NextNumber(-3, 3), rattleRng:NextNumber(-3, 3), rattleRng:NextNumber(-3, 3))
		end
	end
	for _, player in ipairs(near) do
		Remotes.Event("FXEvent"):FireClient(player, "KeyRattle", { Position = socket })
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
	Remotes.Event("TutorialComplete").OnServerEvent:Connect(function(player)
		Services.DataService.Update(player, function(data)
			data.TutorialCompleted = true
		end)
	end)
	Remotes.Event("UpdateSettings").OnServerEvent:Connect(function(player, settings)
		if type(settings) ~= "table" then
			return
		end
		Services.DataService.Update(player, function(data)
			for _, key in ipairs({ "Music", "SFX", "ReduceVFX", "CameraShake" }) do
				if type(settings[key]) == "boolean" then
					data.Settings[key] = settings[key]
				end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
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
				end
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
	MatchService.BeginMatch({
		Players = partyPlayers,
		RoomId = roomId,
		PartySize = partySize,
		ResumePercent = tonumber(data.ResumePercent) or 0,
		Seed = tonumber(data.Seed) or Random.new():NextInteger(1, 2 ^ 30),
		MatchId = tostring(data.MatchId or "local"),
	}, CFrame.new(GameConfig.CombinedRoomOffset))
end

function MatchService.BeginMatch(params: LaunchParams, origin: CFrame): boolean
	local config = RoomRegistry.Get(params.RoomId)
	if not config then
		warn("[MatchService] Unknown room", params.RoomId)
		return false
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
	-- Hand every object to real physics and let the room settle before anyone enters.
	local settled = Services.RoomService.SettleAndSnapshot(runtime, GameConfig.RoomSettleSeconds)
	print(string.format("[MatchService] %d objects released to physics, settled in %.1fs", #runtime.Objects, settled))
	local ok, report = RoomValidator.Validate(runtime, config)
	if RunService:IsStudio() or not ok then
		print(report)
	end

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
	}

	selectTarget()
	-- Treasures in the room (loose + packed in junk) for the "every treasure" mastery star.
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
	if match.ResumePercent > 0 then
		preClean(match.ResumePercent)
	end

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
	publishProgress()
	setState("Loading")

	for _, player in ipairs(players) do
		Services.PlayerSessionService.Reset(player)
		local cp = Services.CheckpointService.GetCheckpoint(player, config.Id)
		if cp and match.ResumePercent > 0 then
			Services.PlayerSessionService.RestoreFromCheckpoint(player, cp)
		end
		player:SetAttribute("InMatch", true)
		player:SetAttribute("MatchId", match.Id)
		Services.PlayerSessionService.RecomputeDerived(player)
		local spawnCF = getSpawnCFrame()
		if spawnCF and player.Character then
			moveCharacterTo(player, spawnCF)
		end
	end

	Services.HintService.ResetForMatch(match)
	Services.HintService.ApplyStagesForProgress(match, match.Progress)

	fireMatch("Intro", {
		RoomNumber = config.DisplayNumber,
		RoomName = config.Name,
		TargetName = config.TargetName,
		TargetId = config.TargetId,
		ResumePercent = match.ResumePercent,
	})
	Services.AnalyticsService.Log("match_start", players[1], { RoomId = config.Id, PartySize = params.PartySize, Resume = match.ResumePercent, Objects = runtime.TotalObjects })

	task.spawn(function()
		local thisMatch = match
		task.wait(1.5)
		if match ~= thisMatch then
			return
		end
		setState("Countdown")
		task.wait(GameConfig.IntroSequenceSeconds - 1.5)
		if match ~= thisMatch then
			return
		end
		match.StartTime = now()
		stateConfig:SetAttribute("StartTime", match.StartTime)
		setState("Searching")
		fireMatch("Started", {})
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
	Services.HintService.OnProgress(match, progress)
	Services.CheckpointService.OnProgress(match, old, progress)
	checkTargetExposure()
end

-- Blasts whatever is still piled on the key's spot outward so the key lies in plain sight.
local function blastFromKey()
	local socket = match.TargetSocket.Position
	for _, root in ipairs(MatchService.GetCoveringObjects()) do
		local away = Vector3.new(root.Position.X - socket.X, 0, root.Position.Z - socket.Z)
		if away.Magnitude < 0.1 then
			local a = match.Rng:NextNumber(0, math.pi * 2)
			away = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		-- Heavier junk moves less.
		local k = 1 / math.sqrt(math.max(1, root:GetAttribute("Weight") or 1))
		Services.ObjectService.Activate(root)
		-- Passes through players while flying (ObjectService restores the group once it settles).
		root.CollisionGroup = "ClutterFlying"
		root.AssemblyLinearVelocity = away.Unit * GameConfig.KeyBurstSpeed * k + Vector3.new(0, GameConfig.KeyBurstLift * k, 0)
		root.AssemblyAngularVelocity = Vector3.new(match.Rng:NextNumber(-5, 5), match.Rng:NextNumber(-5, 5), match.Rng:NextNumber(-5, 5))
	end
end

-- The packed junk hiding the key was broken open: the key bursts out of it.
function MatchService.OnChunkBurst(chunk: Instance, position: Vector3)
	if not match or match.State ~= "Searching" or match.TargetRevealed or chunk ~= match.KeyChunk then
		return
	end
	blastFromKey()
	-- A second push clears what the first wave's own junk kept from leaving.
	local thisMatch = match
	task.delay(0.5, function()
		if match == thisMatch and match.State == "Searching" then
			blastFromKey()
		end
	end)
	fireMatch("KeyBurst", { Position = position })
	MatchService.RevealTarget()
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
		if match.State == "Searching" then
			Services.AnalyticsService.Log("room_quit", player, { RoomId = match.RoomId, Progress = match.Progress })
		end
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
	Services.AnalyticsService.Log("target_revealed", match.Players[1], { RoomId = match.RoomId, Progress = match.Progress })
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
			if not match.DevCompleted and elapsed >= GameConfig.MinimumLegitimateRoomTime and (not data.BestTimes[key] or elapsed < data.BestTimes[key]) then
				data.BestTimes[key] = math.floor(elapsed)
				newBestByUser[tostring(player.UserId)] = true
			end
		end)
		Services.CheckpointService.ClearForRoom(player, roomId)
		starsByUser[tostring(player.UserId)] = Services.ProgressionService.OnRoomComplete(player, match, player == finder, firstClear)
		Services.DataService.Save(player)
		local data = Services.DataService.Get(player)
		if data then
			Services.LeaderboardService.SubmitObjectsFound(player, data.ObjectsFound)
			Services.LeaderboardService.SubmitMostCleaned(player, data.TotalMessCleared)
			if not match.DevCompleted then
				Services.LeaderboardService.SubmitRoomTime(player, roomId, elapsed)
			end
		end
		Services.MonetizationService.CheckBadges(player)
		Services.AnalyticsService.Log("room_complete", player, { RoomId = roomId, PartySize = match.PartySize, ElapsedTime = math.floor(elapsed), FirstClear = firstClear, Progress = match.Progress })
	end
	Services.AnalyticsService.Log("target_found", finder, { RoomId = roomId, ElapsedTime = math.floor(elapsed) })

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
			TreasuresTotal = match.TreasuresTotal,
			TreasuresCleaned = match.TreasuresCleaned,
			NextRoomAvailable = RoomRegistry.Exists(roomId + 1),
			TotalObjects = GameConfig.TotalObjects,
		})
	end)
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
		Services.HintService.OnProgress(match, progress)
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
	for _, b in ipairs(match.TargetSocket.Blockers) do
		table.insert(ids, b:GetAttribute("ObjectId"))
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
	}
end

function MatchService.GetStateConfig(): Configuration
	return stateConfig
end

return MatchService
