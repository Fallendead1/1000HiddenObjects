--[[
	Server-authoritative match state machine. One match per server (reserved match servers
	hold exactly one party; the Combined dev server runs one local match at a time).

	States: Loading -> Countdown -> Searching -> TargetFound -> Results -> Returning -> Ended
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Remotes = require(Shared.Utility.Remotes)
local TargetData = require(Shared.Data.TargetData)

local Services = require(script.Parent)
local Builders = script.Parent.Parent.Builders
local TargetBuilder = require(Builders.TargetBuilder)
local PlaceholderLobbyBuilder = require(Builders.PlaceholderLobbyBuilder)
local RoomValidator = require(script.Parent.Parent.RoomValidator)

local MatchService = {}

local serverRole = "Combined"
local match = nil
local stateConfig: Configuration
local lobbyModel: Model? = nil
local lobbySpawn: BasePart? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fireMatch(eventName: string, payload: any, players: { Player }?)
	local list = players or (match and match.Players) or {}
	for _, player in ipairs(list) do
		if player.Parent then
			Remotes.Event("MatchUpdate"):FireClient(player, eventName, payload)
		end
	end
end

local function setState(newState: string)
	if not match then
		return
	end
	match.State = newState
	stateConfig:SetAttribute("State", newState)
end

local function resetStateConfig()
	stateConfig:SetAttribute("State", "None")
	stateConfig:SetAttribute("RoomId", 0)
	stateConfig:SetAttribute("RoomName", "")
	stateConfig:SetAttribute("RoomNumber", "")
	stateConfig:SetAttribute("TargetName", "")
	stateConfig:SetAttribute("TargetId", "")
	stateConfig:SetAttribute("PartySize", 0)
	stateConfig:SetAttribute("StartTime", 0)
	stateConfig:SetAttribute("EndTime", 0)
	stateConfig:SetAttribute("InitialMess", 0)
	stateConfig:SetAttribute("CurrentMess", 0)
	stateConfig:SetAttribute("Progress", 0)
	stateConfig:SetAttribute("HintStage", 0)
	stateConfig:SetAttribute("TargetRevealed", false)
	stateConfig:SetAttribute("TargetFound", false)
	stateConfig:SetAttribute("FinderName", "")
	stateConfig:SetAttribute("OutlinedClusterId", "")
	stateConfig:SetAttribute("TeamSurgeExpires", 0)
	stateConfig:SetAttribute("PlayerNames", "")
	stateConfig:SetAttribute("ResumePercent", 0)
end

local function moveCharacterTo(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
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

-- Pre-clear non-target clusters so the room roughly matches a resumed checkpoint.
local function preClearForResume(resumePercent: number)
	if resumePercent <= 0 then
		return
	end
	local target = match.InitialMess * resumePercent
	local candidates = {}
	for _, cluster in ipairs(match.Runtime.ClusterList) do
		if cluster.Id ~= match.TargetCluster.Id then
			table.insert(candidates, cluster)
		end
	end
	match.Rng:NextNumber()
	for i = #candidates, 2, -1 do
		local j = match.Rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local cleared = 0
	for _, cluster in ipairs(candidates) do
		if cleared >= target then
			break
		end
		local remaining = target - cleared
		local take = math.min(cluster.CurrentMess, remaining)
		if take >= cluster.CurrentMess * 0.95 then
			take = cluster.CurrentMess
		end
		Services.RoomService.RemoveMess(cluster, take)
		cleared += take
	end
	match.CurrentMess = Services.RoomService.GetTotalMess(match.Runtime)
	match.Progress = 1 - match.CurrentMess / match.InitialMess
	stateConfig:SetAttribute("CurrentMess", match.CurrentMess)
	stateConfig:SetAttribute("Progress", match.Progress)
end

local function selectTarget()
	local eligible = {}
	for _, socket in ipairs(match.Runtime.SocketList) do
		local cluster = match.Runtime.Clusters[socket.ClusterId]
		if cluster and cluster.TargetEligible and cluster.MaxMess > 0 then
			table.insert(eligible, socket)
		end
	end
	assert(#eligible > 0, "Room has no eligible target sockets")
	local socket = eligible[match.Rng:NextInteger(1, #eligible)]
	match.TargetSocket = socket
	match.TargetCluster = match.Runtime.Clusters[socket.ClusterId]
	match.TargetDepth = match.Rng:NextNumber(match.Config.TargetDepthMin, match.Config.TargetDepthMax)
end

local function checkTargetReveal()
	if match.TargetRevealed or not match.TargetCluster then
		return
	end
	local fraction = Services.RoomService.GetClearedFraction(match.TargetCluster)
	if fraction + 1e-6 >= match.TargetDepth then
		MatchService.RevealTarget()
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

function MatchService.Start(role: string)
	if role == "Combined" or role == "Lobby" then
		lobbyModel = PlaceholderLobbyBuilder.Build(CFrame.new(0, 0, 0))
		lobbyModel.Parent = workspace
		lobbySpawn = lobbyModel:FindFirstChild("LobbySpawn") :: BasePart
		local zone = lobbyModel:FindFirstChild("QueueZone")
		if zone then
			Services.QueueService.SetZone(zone :: BasePart)
		end
	end
	if role == "Match" then
		task.spawn(MatchService.StartFromTeleport)
	end

	-- Fall protection + keep players inside the room during a match.
	task.spawn(function()
		while true do
			task.wait(1)
			if match and match.Runtime then
				local floorY = match.Runtime.FloorY
				for _, player in ipairs(match.Players) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if root and root.Position.Y < floorY - GameConfig.FallProtectionDepth then
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
	local origin = CFrame.new(GameConfig.CombinedRoomOffset)
	return MatchService.BeginMatch(params, origin)
end

function MatchService.StartFromTeleport()
	-- Wait for the first player to read teleport data.
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
	}, CFrame.new(0, 0, 0))
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
	local initialMess = Services.RoomService.ApplyMess(runtime, params.PartySize)

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
		OriginalPlayers = table.clone(players),
		State = "Loading",
		StartTime = 0,
		EndTime = 0,
		InitialMess = initialMess,
		CurrentMess = initialMess,
		Progress = 0,
		Runtime = runtime,
		TargetSocket = nil,
		TargetCluster = nil,
		TargetDepth = 0,
		TargetRevealed = false,
		TargetFound = false,
		FinderUserId = 0,
		TargetModel = nil,
		HintStage = 0,
		TeamSurgeExpires = 0,
		ResumePercent = params.ResumePercent or 0,
		FirstSaleLogged = false,
		ClaimLock = false,
	}

	selectTarget()
	preClearForResume(match.ResumePercent)

	resetStateConfig()
	stateConfig:SetAttribute("RoomId", config.Id)
	stateConfig:SetAttribute("RoomName", config.Name)
	stateConfig:SetAttribute("RoomNumber", config.DisplayNumber)
	stateConfig:SetAttribute("TargetName", config.TargetName)
	stateConfig:SetAttribute("TargetId", config.TargetId)
	stateConfig:SetAttribute("PartySize", params.PartySize)
	stateConfig:SetAttribute("InitialMess", initialMess)
	stateConfig:SetAttribute("CurrentMess", match.CurrentMess)
	stateConfig:SetAttribute("Progress", match.Progress)
	stateConfig:SetAttribute("PlayerNames", playerNamesString(players))
	stateConfig:SetAttribute("ResumePercent", match.ResumePercent)
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
		if spawnCF then
			if player.Character then
				moveCharacterTo(player, spawnCF)
			end
		end
	end

	Services.HintService.ResetForMatch(match)
	Services.HintService.ApplyStagesForProgress(match, match.Progress, true)

	fireMatch("Intro", {
		RoomNumber = config.DisplayNumber,
		RoomName = config.Name,
		TargetName = config.TargetName,
		TargetId = config.TargetId,
		ResumePercent = match.ResumePercent,
	})
	Services.AnalyticsService.Log("match_start", players[1], { RoomId = config.Id, PartySize = params.PartySize, Resume = match.ResumePercent })

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
	end)

	return true
end

function MatchService.RemovePlayer(player: Player)
	if not match then
		return
	end
	local idx = table.find(match.Players, player)
	if idx then
		table.remove(match.Players, idx)
		Services.SearchService.StopSearch(player)
		Services.EconomyService.ClearPlayer(player)
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

-- Remove `amount` mess from a cluster on behalf of a player (or nil for system actions
-- like Trash Bomb). Returns actual removed amount.
function MatchService.RemoveMess(clusterId: string, amount: number, player: Player?): number
	if not match or match.State ~= "Searching" then
		return 0
	end
	local cluster = match.Runtime.Clusters[clusterId]
	if not cluster or cluster.CurrentMess <= 0 or amount <= 0 then
		return 0
	end
	local removed = Services.RoomService.RemoveMess(cluster, amount)
	if removed <= 0 then
		return 0
	end
	local oldProgress = match.Progress
	match.CurrentMess -= removed
	match.Progress = 1 - match.CurrentMess / match.InitialMess
	stateConfig:SetAttribute("CurrentMess", match.CurrentMess)
	stateConfig:SetAttribute("Progress", match.Progress)

	if player then
		player:SetAttribute("ContributionMess", (player:GetAttribute("ContributionMess") or 0) + removed)
	end

	Services.HintService.OnProgress(match, oldProgress, match.Progress)
	Services.CheckpointService.OnProgress(match, oldProgress, match.Progress)
	checkTargetReveal()
	return removed
end

function MatchService.RevealTarget()
	if not match or match.TargetRevealed then
		return
	end
	match.TargetRevealed = true
	local socket = match.TargetSocket
	Services.RoomService.ExposeSocket(match.TargetCluster, socket)

	local model = TargetBuilder.Get(match.Config.TargetId)
	model.Name = "HiddenTarget"
	local pivot = socket.Part.CFrame
	if model.PrimaryPart then
		model:PivotTo(pivot * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(20)))
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
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		MatchService.OnTargetClaim(player)
	end)

	model.Parent = match.Runtime.Model
	match.TargetModel = model
	stateConfig:SetAttribute("TargetRevealed", true)
	fireMatch("TargetRevealed", { Position = model.PrimaryPart and model.PrimaryPart.Position })
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
	if not root or not targetPart then
		return
	end
	if (root.Position - targetPart.Position).Magnitude > 14 then
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
		Services.SearchService.StopSearch(player)
	end

	local targetDef = TargetData.Get(match.RoomId)
	local roomId = match.RoomId

	-- Save FIRST, then celebrate.
	for _, player in ipairs(match.Players) do
		local firstClear = false
		Services.DataService.Update(player, function(data)
			local contribution = player:GetAttribute("ContributionMess") or 0
			data.TotalMessCleared += contribution
			if data.HighestRoomCompleted < roomId then
				data.HighestRoomCompleted = roomId
				data.ObjectsFound = math.max(data.ObjectsFound, roomId)
				firstClear = true
			end
			if player == finder then
				data.FinderWins += 1
			end
			local key = tostring(roomId)
			if elapsed >= GameConfig.MinimumLegitimateRoomTime then
				if not data.BestTimes[key] or elapsed < data.BestTimes[key] then
					data.BestTimes[key] = math.floor(elapsed)
				end
			end
		end)
		Services.CheckpointService.ClearForRoom(player, roomId)
		Services.DataService.Save(player)

		local data = Services.DataService.Get(player)
		if data then
			Services.LeaderboardService.SubmitObjectsFound(player, data.ObjectsFound)
			Services.LeaderboardService.SubmitRoomTime(player, roomId, elapsed)
		end
		Services.MonetizationService.CheckBadges(player, firstClear, player == finder)
		Services.AnalyticsService.Log("room_complete", player, { RoomId = roomId, PartySize = match.PartySize, ElapsedTime = math.floor(elapsed), FirstClear = firstClear })
	end
	Services.AnalyticsService.Log("target_found", finder, { RoomId = roomId, ElapsedTime = math.floor(elapsed) })

	local contributions = {}
	for _, player in ipairs(match.Players) do
		table.insert(contributions, { Name = player.Name, UserId = player.UserId, Mess = player:GetAttribute("ContributionMess") or 0 })
	end
	table.sort(contributions, function(a, b)
		return a.Mess > b.Mess
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
		local nextRoomExists = RoomRegistry.Exists(roomId + 1)
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
			NextRoomAvailable = nextRoomExists,
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
	if match then
		local idx = table.find(match.Players, player)
		if idx then
			table.remove(match.Players, idx)
		end
	end
	Services.SearchService.StopSearch(player)
	Services.EconomyService.ClearPlayer(player)
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
	for _, player in ipairs(match.Players) do
		Services.SearchService.StopSearch(player)
	end
	local runtime = match.Runtime
	local remaining = table.clone(match.Players)
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
	if not match or match.State ~= "Searching" then
		return
	end
	fraction = math.clamp(fraction, 0, 0.999)
	local targetRemaining = match.InitialMess * (1 - fraction)
	local toRemove = match.CurrentMess - targetRemaining
	if toRemove <= 0 then
		return
	end
	for _, cluster in ipairs(match.Runtime.ClusterList) do
		if toRemove <= 0 then
			break
		end
		if cluster.Id ~= match.TargetCluster.Id and cluster.CurrentMess > 0 then
			local take = math.min(cluster.CurrentMess, toRemove)
			toRemove -= MatchService.RemoveMess(cluster.Id, take, nil)
		end
	end
	if toRemove > 0 then
		local cap = math.floor(match.TargetCluster.MaxMess * (match.TargetDepth - 0.05))
		local allowed = match.TargetCluster.CurrentMess - (match.TargetCluster.MaxMess - cap)
		if allowed > 0 then
			MatchService.RemoveMess(match.TargetCluster.Id, math.min(allowed, toRemove), nil)
		end
	end
end

function MatchService.ForceReveal()
	if not match or match.State ~= "Searching" or match.TargetRevealed then
		return
	end
	local cluster = match.TargetCluster
	local needed = math.ceil(cluster.MaxMess * match.TargetDepth) - (cluster.MaxMess - cluster.CurrentMess)
	if needed > 0 then
		MatchService.RemoveMess(cluster.Id, needed + 1, nil)
	end
	if not match.TargetRevealed then
		MatchService.RevealTarget()
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
	match.FinderUserId = player.UserId
	MatchService.CompleteMatch(player)
end

function MatchService.GetTargetInfo()
	if not match then
		return nil
	end
	return {
		SocketId = match.TargetSocket and match.TargetSocket.Id,
		ClusterId = match.TargetCluster and match.TargetCluster.Id,
		RegionId = match.TargetCluster and match.TargetCluster.RegionId,
		Depth = match.TargetDepth,
		Revealed = match.TargetRevealed,
	}
end

function MatchService.GetStateConfig(): Configuration
	return stateConfig
end

return MatchService
