--[[
	Server-authoritative searching. Clients only say "I am searching cluster X" / "I stopped".
	The server runs the tick loop, validates distance + line of sight every tick, computes
	power/interval from upgrades and boosts, and applies mess removal to cluster and bag.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local SearchService = {}

type Searcher = {
	Player: Player,
	ClusterId: string,
	NextTick: number,
	BlockedByBag: boolean,
}

local searchers: { [Player]: Searcher } = {}
local remoteLimiter = RateLimiter.new(GameConfig.SearchRemoteRateLimit, GameConfig.SearchRemoteRateLimit * 2)
local trashBombLimiter = RateLimiter.new(2, 2)

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.IgnoreWater = true

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Distance from the player to the closest point on the cluster's search volume.
local function distanceToVolume(root: BasePart, volume: BasePart): number
	local localPos = volume.CFrame:PointToObjectSpace(root.Position)
	local half = volume.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - clamped).Magnitude
end

local function hasLineOfSight(match, root: BasePart, volume: BasePart): boolean
	if not GameConfig.SearchLineOfSight then
		return true
	end
	if #match.Runtime.StructureParts == 0 then
		return true
	end
	raycastParams.FilterDescendantsInstances = match.Runtime.StructureParts
	local from = root.Position + Vector3.new(0, 1, 0)
	local localPos = volume.CFrame:PointToObjectSpace(from)
	local half = volume.Size / 2
	local closest = volume.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	))
	local dir = closest - from
	if dir.Magnitude < 0.5 then
		return true
	end
	local result = workspace:Raycast(from, dir, raycastParams)
	-- Furniture inside a pile's footprint (a bed under a bed pile) is fine; only reject when
	-- the blocking hit is clearly between the player and the pile.
	if result and (result.Position - from).Magnitude < dir.Magnitude - 1.5 then
		local hitLocal = volume.CFrame:PointToObjectSpace(result.Position)
		local inside = math.abs(hitLocal.X) <= half.X + 1 and math.abs(hitLocal.Y) <= half.Y + 1 and math.abs(hitLocal.Z) <= half.Z + 1
		return inside
	end
	return true
end

local function validate(player: Player, match, cluster): (boolean, string?)
	if match.State ~= "Searching" then
		return false, "MatchState"
	end
	local root = getRoot(player)
	if not root then
		return false, "NoCharacter"
	end
	if cluster.CurrentMess <= 0 then
		return false, "Empty"
	end
	local reach = Services.PlayerSessionService.GetReach(player) + GameConfig.SearchLeniencyDistance
	if distanceToVolume(root, cluster.Volume) > reach then
		return false, "TooFar"
	end
	if not hasLineOfSight(match, root, cluster.Volume) then
		return false, "Blocked"
	end
	return true, nil
end

function SearchService.Init()
	Remotes.Event("SearchStart").OnServerEvent:Connect(function(player, clusterId)
		if not remoteLimiter:Allow(player) then
			return
		end
		if type(clusterId) ~= "string" then
			return
		end
		SearchService.StartSearch(player, clusterId)
	end)

	Remotes.Event("SearchStop").OnServerEvent:Connect(function(player)
		if not remoteLimiter:Allow(player) then
			return
		end
		SearchService.StopSearch(player)
	end)

	Remotes.Event("RequestTrashBomb").OnServerEvent:Connect(function(player, clusterId)
		if not trashBombLimiter:Allow(player) then
			return
		end
		if type(clusterId) ~= "string" then
			return
		end
		SearchService.UseTrashBomb(player, clusterId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		searchers[player] = nil
	end)
end

function SearchService.Start()
	RunService.Heartbeat:Connect(function()
		local match = Services.MatchService.GetMatch()
		if not match or match.State ~= "Searching" then
			return
		end
		local now = os.clock()
		for player, searcher in pairs(searchers) do
			if now >= searcher.NextTick then
				SearchService.Tick(player, searcher, match, now)
			end
		end
	end)
end

function SearchService.StartSearch(player: Player, clusterId: string)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" then
		return
	end
	local cluster = match.Runtime.Clusters[clusterId]
	if not cluster then
		return
	end
	local ok = validate(player, match, cluster)
	if not ok then
		return
	end
	local existing = searchers[player]
	if existing and existing.ClusterId == clusterId then
		return
	end
	searchers[player] = {
		Player = player,
		ClusterId = clusterId,
		NextTick = os.clock() + 0.1,
		BlockedByBag = false,
	}
	player:SetAttribute("IsSearching", true)
	player:SetAttribute("SearchingCluster", clusterId)
end

function SearchService.StopSearch(player: Player)
	if searchers[player] then
		searchers[player] = nil
	end
	if player.Parent then
		player:SetAttribute("IsSearching", false)
		player:SetAttribute("SearchingCluster", "")
	end
end

function SearchService.OnBagChanged(player: Player)
	local searcher = searchers[player]
	if searcher then
		searcher.BlockedByBag = false
	end
end

function SearchService.Tick(player: Player, searcher: Searcher, match, now: number)
	local cluster = match.Runtime.Clusters[searcher.ClusterId]
	if not cluster then
		SearchService.StopSearch(player)
		return
	end
	local ok, reason = validate(player, match, cluster)
	if not ok then
		if reason == "Empty" or reason == "NoCharacter" or reason == "MatchState" then
			SearchService.StopSearch(player)
			Remotes.Event("FXEvent"):FireClient(player, "SearchStopped", { Reason = reason })
		else
			-- Out of range/blocked: pause but keep the intent, client keeps holding.
			searcher.NextTick = now + 0.25
		end
		return
	end

	local interval = Services.PlayerSessionService.GetSearchInterval(player)
	searcher.NextTick = now + interval

	local capacity = player:GetAttribute("BagCapacity") or 40
	local bag = player:GetAttribute("BagCurrent") or 0
	local room = capacity - bag
	if room <= 0 then
		if not searcher.BlockedByBag then
			searcher.BlockedByBag = true
			Services.EconomyService.OnBagFull(player, match)
		end
		return
	end

	local power = Services.PlayerSessionService.GetSearchPower(player, match.TeamSurgeExpires)
	local amount = math.max(1, math.floor(power + 0.5))
	amount = math.min(amount, room, cluster.CurrentMess)

	local removed = Services.MatchService.RemoveMess(cluster.Id, amount, player)
	if removed <= 0 then
		return
	end
	local newBag = bag + removed
	player:SetAttribute("BagCurrent", newBag)
	Remotes.Event("FXEvent"):FireClient(player, "SearchTick", { ClusterId = cluster.Id, Amount = removed })
	if newBag >= capacity then
		searcher.BlockedByBag = true
		Services.EconomyService.OnBagFull(player, match)
	end
end

function SearchService.UseTrashBomb(player: Player, clusterId: string)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" then
		return
	end
	local pending = player:GetAttribute("PendingTrashBombs") or 0
	if pending <= 0 then
		Services.NotificationService.Send(player, "Error", "You do not have a Trash Bomb.")
		return
	end
	local cluster = match.Runtime.Clusters[clusterId]
	local root = getRoot(player)
	if not cluster or not root then
		return
	end
	if distanceToVolume(root, cluster.Volume) > MonetizationConfig.Effects.TrashBombMaxDistance then
		Services.NotificationService.Send(player, "Warning", "Get closer to that pile.")
		return
	end
	player:SetAttribute("PendingTrashBombs", pending - 1)

	local budget = math.floor(match.InitialMess * MonetizationConfig.Effects.TrashBombRoomFraction)
	local removed = Services.MatchService.RemoveMess(cluster.Id, math.min(budget, cluster.CurrentMess), player)
	budget -= removed
	if budget > 0 then
		-- Spill into neighbouring piles by distance.
		local others = {}
		for _, other in ipairs(match.Runtime.ClusterList) do
			if other.Id ~= cluster.Id and other.CurrentMess > 0 then
				table.insert(others, other)
			end
		end
		table.sort(others, function(a, b)
			return (a.Center - cluster.Center).Magnitude < (b.Center - cluster.Center).Magnitude
		end)
		for _, other in ipairs(others) do
			if budget <= 0 then
				break
			end
			budget -= Services.MatchService.RemoveMess(other.Id, math.min(budget, other.CurrentMess), player)
		end
	end

	for _, p in ipairs(match.Players) do
		Remotes.Event("FXEvent"):FireClient(p, "TrashBomb", { Position = cluster.Center, ClusterId = cluster.Id, PlayerName = player.Name })
	end
	Services.AnalyticsService.Log("trash_bomb", player, { RoomId = match.RoomId })
end

return SearchService
