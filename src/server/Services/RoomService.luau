--[[
	Builds a room (final model from ServerStorage.Rooms or placeholder geometry) and
	parses it into a runtime table that gameplay services operate on. Owns mess bookkeeping
	per cluster and the replicated cluster attributes (CurrentMess, MaxMess, VisualStage).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)

local Builders = script.Parent.Parent.Builders
local PlaceholderRoomBuilder = require(Builders.PlaceholderRoomBuilder)

local RoomService = {}

export type ClusterRuntime = {
	Id: string,
	RegionId: string,
	Config: any,
	Model: Model,
	Volume: BasePart,
	Center: Vector3,
	Weight: number,
	TargetEligible: boolean,
	MaxMess: number,
	CurrentMess: number,
	ChunkCount: number,
	Chunks: { BasePart },
	Stage: number,
}

export type SocketRuntime = {
	Id: string,
	ClusterId: string,
	RegionId: string,
	Part: BasePart,
	Difficulty: number,
}

export type RoomRuntime = {
	Config: any,
	Model: Model,
	Origin: CFrame,
	Clusters: { [string]: ClusterRuntime },
	ClusterList: { ClusterRuntime },
	Sockets: { [string]: SocketRuntime },
	SocketList: { SocketRuntime },
	Regions: { [string]: { Part: BasePart, Name: string } },
	SpawnPart: BasePart?,
	TrashChute: Model?,
	TrashChuteZone: BasePart?,
	TrashChuteRadius: number,
	StructureParts: { BasePart },
	FloorY: number,
}

local function findTaggedIn(model: Instance, tag: string): { Instance }
	local result = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsDescendantOf(model) then
			table.insert(result, inst)
		end
	end
	return result
end

local function parseCluster(model: Model, configById): ClusterRuntime?
	local id = model:GetAttribute("ClusterId") or model.Name
	local volume = model:FindFirstChild("SearchVolume")
	if not volume or not volume:IsA("BasePart") then
		volume = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	end
	if not volume then
		warn("[RoomService] Cluster without a SearchVolume:", model:GetFullName())
		return nil
	end
	volume.CanQuery = true
	volume.CanCollide = false

	local chunks = {}
	local chunksFolder = model:FindFirstChild("Chunks")
	if chunksFolder then
		for _, c in ipairs(chunksFolder:GetChildren()) do
			if c:IsA("BasePart") then
				c.CanCollide = false
				c.CanQuery = false
				c.Anchored = true
				table.insert(chunks, c)
			elseif c:IsA("Model") then
				for _, d in ipairs(c:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanQuery = false
						d.Anchored = true
					end
				end
				table.insert(chunks, c :: any)
			end
		end
	end
	table.sort(chunks, function(a, b)
		local oa = a:GetAttribute("RemovalOrder") or tonumber(a.Name:match("%d+")) or 0
		local ob = b:GetAttribute("RemovalOrder") or tonumber(b.Name:match("%d+")) or 0
		return oa < ob
	end)

	local cfg = configById[id]
	return {
		Id = id,
		RegionId = model:GetAttribute("RegionId") or (cfg and cfg.RegionId) or "",
		Config = cfg,
		Model = model,
		Volume = volume,
		Center = volume.Position,
		Weight = model:GetAttribute("Weight") or (cfg and cfg.Weight) or 1,
		TargetEligible = model:GetAttribute("TargetEligible") ~= false,
		MaxMess = 0,
		CurrentMess = 0,
		ChunkCount = #chunks,
		Chunks = chunks,
		Stage = 0,
	}
end

function RoomService.Init() end

function RoomService.Build(config, origin: CFrame): RoomRuntime
	local roomsFolder = ServerStorage:FindFirstChild("Rooms")
	local prebuilt = roomsFolder and roomsFolder:FindFirstChild("Room" .. config.DisplayNumber)
	local model: Model
	if prebuilt and prebuilt:IsA("Model") and #prebuilt:GetChildren() > 0 then
		model = prebuilt:Clone()
		if model.PrimaryPart then
			model:PivotTo(origin)
		end
	else
		model = PlaceholderRoomBuilder.Build(config, origin)
	end
	model.Name = "Room" .. config.DisplayNumber
	model:SetAttribute("RoomId", config.Id)
	model.Parent = workspace

	local configById = {}
	for _, c in ipairs(config.Clusters) do
		configById[c.Id] = c
	end

	local runtime: RoomRuntime = {
		Config = config,
		Model = model,
		Origin = origin,
		Clusters = {},
		ClusterList = {},
		Sockets = {},
		SocketList = {},
		Regions = {},
		SpawnPart = nil,
		TrashChute = nil,
		TrashChuteZone = nil,
		TrashChuteRadius = GameConfig.TrashChuteRadius,
		StructureParts = {},
		FloorY = origin.Position.Y,
	}

	for _, inst in ipairs(findTaggedIn(model, "ClutterCluster")) do
		if inst:IsA("Model") then
			local cluster = parseCluster(inst, configById)
			if cluster then
				runtime.Clusters[cluster.Id] = cluster
				table.insert(runtime.ClusterList, cluster)
			end
		end
	end
	table.sort(runtime.ClusterList, function(a, b)
		return a.Id < b.Id
	end)

	for _, inst in ipairs(findTaggedIn(model, "TargetSocket")) do
		if inst:IsA("BasePart") then
			local socket: SocketRuntime = {
				Id = inst:GetAttribute("SocketId") or inst.Name,
				ClusterId = inst:GetAttribute("ClusterId") or "",
				RegionId = inst:GetAttribute("RegionId") or "",
				Part = inst,
				Difficulty = inst:GetAttribute("Difficulty") or 1,
			}
			runtime.Sockets[socket.Id] = socket
			table.insert(runtime.SocketList, socket)
		end
	end
	table.sort(runtime.SocketList, function(a, b)
		return a.Id < b.Id
	end)

	for _, inst in ipairs(findTaggedIn(model, "SearchRegion")) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("RegionId") or inst.Name
			runtime.Regions[id] = { Part = inst, Name = inst:GetAttribute("RegionName") or id }
		end
	end

	local spawns = findTaggedIn(model, "RoomSpawn")
	if spawns[1] and spawns[1]:IsA("BasePart") then
		runtime.SpawnPart = spawns[1]
	end

	local chutes = findTaggedIn(model, "TrashChute")
	if chutes[1] then
		local chute = chutes[1]
		if chute:IsA("Model") then
			runtime.TrashChute = chute
			runtime.TrashChuteZone = chute.PrimaryPart or chute:FindFirstChildWhichIsA("BasePart")
		elseif chute:IsA("BasePart") then
			runtime.TrashChuteZone = chute
		end
		runtime.TrashChuteRadius = chute:GetAttribute("Radius") or GameConfig.TrashChuteRadius
	end

	local structure = model:FindFirstChild("Structure")
	if structure then
		for _, p in ipairs(structure:GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(runtime.StructureParts, p)
			end
		end
	end

	return runtime
end

function RoomService.Destroy(runtime: RoomRuntime)
	if runtime.Model then
		runtime.Model:Destroy()
	end
end

-- Distribute the room's logical mess across clusters by weight. Returns total.
function RoomService.ApplyMess(runtime: RoomRuntime, partySize: number): number
	local config = runtime.Config
	local multiplier = GameConfig.PartyMessMultiplier[math.clamp(partySize, 1, GameConfig.MaxPartySize)] or 1
	local totalTarget = config.BaseMessUnits * multiplier

	local weightSum = 0
	for _, cluster in ipairs(runtime.ClusterList) do
		weightSum += cluster.Weight
	end
	if weightSum <= 0 then
		weightSum = 1
	end

	local total = 0
	for _, cluster in ipairs(runtime.ClusterList) do
		local mess = math.floor(totalTarget * cluster.Weight / weightSum + 0.5)
		cluster.MaxMess = mess
		cluster.CurrentMess = mess
		cluster.Stage = 0
		total += mess
		cluster.Model:SetAttribute("MaxMess", mess)
		cluster.Model:SetAttribute("CurrentMess", mess)
		cluster.Model:SetAttribute("VisualStage", 0)
		cluster.Model:SetAttribute("ChunkCount", cluster.ChunkCount)
	end
	return total
end

function RoomService.GetClearedFraction(cluster: ClusterRuntime): number
	if cluster.MaxMess <= 0 then
		return 1
	end
	return 1 - cluster.CurrentMess / cluster.MaxMess
end

-- Sets cluster mess and updates the replicated visual stage. Returns amount actually removed.
function RoomService.SetClusterMess(cluster: ClusterRuntime, newMess: number): number
	newMess = math.clamp(math.floor(newMess + 0.5), 0, cluster.MaxMess)
	local removed = cluster.CurrentMess - newMess
	cluster.CurrentMess = newMess
	cluster.Model:SetAttribute("CurrentMess", newMess)

	local fraction = RoomService.GetClearedFraction(cluster)
	local stage = math.floor(fraction * cluster.ChunkCount + 1e-6)
	if newMess <= 0 then
		stage = cluster.ChunkCount
	end
	if stage ~= cluster.Stage then
		cluster.Stage = stage
		cluster.Model:SetAttribute("VisualStage", stage)
	end
	return removed
end

function RoomService.RemoveMess(cluster: ClusterRuntime, amount: number): number
	return RoomService.SetClusterMess(cluster, cluster.CurrentMess - amount)
end

-- Hide the chunks physically overlapping a socket so a revealed target is actually visible.
function RoomService.ExposeSocket(cluster: ClusterRuntime, socket: SocketRuntime)
	local names = {}
	local pos = socket.Part.Position
	for _, chunk in ipairs(cluster.Chunks) do
		local cf, size
		if chunk:IsA("BasePart") then
			cf, size = chunk.CFrame, chunk.Size
		else
			cf, size = (chunk :: any):GetBoundingBox()
		end
		local localPos = cf:PointToObjectSpace(pos)
		local half = size / 2 + Vector3.new(1.2, 1.2, 1.2)
		if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z then
			table.insert(names, chunk.Name)
		end
	end
	cluster.Model:SetAttribute("ForceHiddenChunks", table.concat(names, ","))
end

function RoomService.GetTotalMess(runtime: RoomRuntime): number
	local total = 0
	for _, cluster in ipairs(runtime.ClusterList) do
		total += cluster.CurrentMess
	end
	return total
end

return RoomService
