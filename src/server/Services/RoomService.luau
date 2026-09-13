--[[
	Builds a room (final model from ServerStorage.Rooms or placeholder geometry) and parses it
	into a runtime table: every individual clutter object, target sockets with their physical
	blocker groups, regions, spawn and structure.

	Blocker group of a socket = the clutter objects whose footprint covers the socket (within
	SocketBlockerRadius) at build time. The Golden Key can only appear there once those exact
	objects have been moved away and nothing else is lying on the spot.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Builders = script.Parent.Parent.Builders
local PlaceholderRoomBuilder = require(Builders.PlaceholderRoomBuilder)
local ClutterBuilder = require(Builders.ClutterBuilder)

local _ = ReplicatedStorage

local RoomService = {}

-- Surfaces clutter rests ON rather than must avoid (everything else in Structure is an obstacle).
local SURFACE_NAMES = { Floor = true, Ceiling = true, Rug = true, RugInner = true, Sheet = true, CeilingLight = true, LampFixture = true }

export type SocketRuntime = {
	Id: string,
	PileId: string,
	RegionId: string,
	Part: BasePart,
	Position: Vector3,
	Difficulty: number,
	Blockers: { BasePart },
}

export type RoomRuntime = {
	Config: any,
	Model: Model,
	Origin: CFrame,
	Objects: { BasePart },
	ObjectsById: { [string]: BasePart },
	Sockets: { [string]: SocketRuntime },
	SocketList: { SocketRuntime },
	Regions: { [string]: { Part: BasePart, Name: string } },
	SpawnPart: BasePart?,
	StructureParts: { BasePart },
	FloorY: number,
	BoundsCFrame: CFrame,
	BoundsSize: Vector3,
	MovedCount: number,
}

local function taggedIn(model: Instance, tag: string): { Instance }
	local result = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsDescendantOf(model) then
			table.insert(result, inst)
		end
	end
	return result
end

-- XZ distance from a point to an object's (rotated) footprint. 0 when the point is under it.
function RoomService.FootprintDistanceXZ(root: BasePart, cframe: CFrame, point: Vector3): number
	local lp = cframe:PointToObjectSpace(point)
	local half = root.Size / 2
	local dx = math.max(0, math.abs(lp.X) - half.X)
	local dz = math.max(0, math.abs(lp.Z) - half.Z)
	-- Balls/cylinders and tilted parts: good enough as a box approximation.
	return math.sqrt(dx * dx + dz * dz)
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

	-- The shell must be in Workspace first: clutter placement queries it to avoid clipping.
	model.Parent = workspace

	-- Final room shells may ship without clutter: generate it from the room config.
	local clutterFolder = model:FindFirstChild("Clutter")
	if not clutterFolder then
		clutterFolder = Instance.new("Folder")
		clutterFolder.Name = "Clutter"
		clutterFolder.Parent = model
	end
	if #clutterFolder:GetChildren() == 0 then
		local solids = {}
		local shell = model:FindFirstChild("Structure")
		for _, part in ipairs(shell and shell:GetDescendants() or {}) do
			if part:IsA("BasePart") and not SURFACE_NAMES[part.Name] then
				table.insert(solids, part)
			end
		end
		ClutterBuilder.Build(config, origin, clutterFolder, config.LayoutVariants and config.LayoutVariants[1] or 1, solids)
	end

	local runtime: RoomRuntime = {
		Config = config,
		Model = model,
		Origin = origin,
		Objects = {},
		ObjectsById = {},
		Sockets = {},
		SocketList = {},
		Regions = {},
		SpawnPart = nil,
		StructureParts = {},
		FloorY = origin.Position.Y,
		BoundsCFrame = origin * CFrame.new(0, config.Size.Y / 2, 0),
		BoundsSize = config.Size,
		MovedCount = 0,
	}

	for _, inst in ipairs(taggedIn(model, "Clutter")) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("ObjectId") or inst.Name
			table.insert(runtime.Objects, inst)
			runtime.ObjectsById[id] = inst
		end
	end

	for _, inst in ipairs(taggedIn(model, "SearchRegion")) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("RegionId") or inst.Name
			runtime.Regions[id] = { Part = inst, Name = inst:GetAttribute("RegionName") or id }
		end
	end

	local spawns = taggedIn(model, "RoomSpawn")
	if spawns[1] and spawns[1]:IsA("BasePart") then
		runtime.SpawnPart = spawns[1]
	end

	local structure = model:FindFirstChild("Structure")
	if structure then
		for _, p in ipairs(structure:GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(runtime.StructureParts, p)
			end
		end
	end

	for _, inst in ipairs(taggedIn(model, "TargetSocket")) do
		if inst:IsA("BasePart") then
			local socket: SocketRuntime = {
				Id = inst:GetAttribute("SocketId") or inst.Name,
				PileId = inst:GetAttribute("PileId") or "",
				RegionId = inst:GetAttribute("RegionId") or "",
				Part = inst,
				Position = inst.Position,
				Difficulty = inst:GetAttribute("Difficulty") or 1,
				Blockers = {},
			}
			runtime.Sockets[socket.Id] = socket
			table.insert(runtime.SocketList, socket)
		end
	end
	table.sort(runtime.SocketList, function(a, b)
		return a.Id < b.Id
	end)
	RoomService.ComputeBlockers(runtime)

	return runtime
end

-- Blocker group of each socket = the objects whose footprint covers it at their OriginalCFrame.
function RoomService.ComputeBlockers(runtime: RoomRuntime)
	local radius = runtime.Config.SocketBlockerRadius or 1.4
	for _, socket in ipairs(runtime.SocketList) do
		socket.Blockers = {}
		local ids = {}
		for _, obj in ipairs(runtime.Objects) do
			local original: CFrame = obj:GetAttribute("OriginalCFrame") or obj.CFrame
			if original.Position.Y > socket.Position.Y - 0.5 and RoomService.FootprintDistanceXZ(obj, original, socket.Position) <= radius then
				table.insert(socket.Blockers, obj)
				table.insert(ids, obj:GetAttribute("ObjectId"))
			end
		end
		socket.Part:SetAttribute("BlockerGroup", table.concat(ids, ","))
	end
end

-- Put an object that left the room back inside it, on the floor, at rest.
function RoomService.RecoverObject(runtime: RoomRuntime, obj: BasePart)
	local inset = math.max(obj.Size.X, obj.Size.Y, obj.Size.Z) / 2 + 0.5
	local pos = obj.Position
	obj.CFrame = CFrame.new(RoomService.ClampInsideRoom(runtime, Vector3.new(pos.X, runtime.FloorY + inset + 1, pos.Z), inset))
	obj.AssemblyLinearVelocity = Vector3.zero
	obj.AssemblyAngularVelocity = Vector3.zero
end

function RoomService.IsOutOfRoom(runtime: RoomRuntime, obj: BasePart): boolean
	local pos = obj.Position
	return pos.Y < runtime.FloorY - 5 or not RoomService.IsInsideRoom(runtime, pos, 1)
end

--[[
	Release every clutter object to real physics (unanchored, server-owned so no client can
	shove things around), let the room settle, then record where everything actually came to
	rest. OriginalCFrame and the key's blocker groups are taken from the settled room, so
	natural settling never counts as a player moving something. Yields up to maxSeconds.
]]
function RoomService.SettleAndSnapshot(runtime: RoomRuntime, maxSeconds: number): number
	local started = os.clock()
	for _, obj in ipairs(runtime.Objects) do
		obj.Anchored = false
		pcall(function()
			obj:SetNetworkOwner(nil)
		end)
	end
	task.wait(0.75)
	while os.clock() - started < maxSeconds do
		local moving = 0
		for _, obj in ipairs(runtime.Objects) do
			if obj.AssemblyLinearVelocity.Magnitude > 0.6 then
				moving += 1
			end
		end
		if moving <= #runtime.Objects * 0.01 then
			break
		end
		task.wait(0.5)
	end
	for _, obj in ipairs(runtime.Objects) do
		if RoomService.IsOutOfRoom(runtime, obj) then
			RoomService.RecoverObject(runtime, obj)
		end
		obj:SetAttribute("OriginalCFrame", obj.CFrame)
	end
	RoomService.ComputeBlockers(runtime)
	return os.clock() - started
end

function RoomService.Destroy(runtime: RoomRuntime)
	if runtime.Model then
		runtime.Model:Destroy()
	end
end

function RoomService.GetProgress(runtime: RoomRuntime): number
	if #runtime.Objects == 0 then
		return 0
	end
	return runtime.MovedCount / #runtime.Objects
end

-- True when the point lies inside the room's playable box.
function RoomService.IsInsideRoom(runtime: RoomRuntime, point: Vector3, margin: number?): boolean
	local lp = runtime.BoundsCFrame:PointToObjectSpace(point)
	local half = runtime.BoundsSize / 2 + Vector3.one * (margin or 0)
	return math.abs(lp.X) <= half.X and math.abs(lp.Y) <= half.Y + 20 and math.abs(lp.Z) <= half.Z
end

-- Clamp a point back inside the room (used to recover objects thrown out of bounds).
function RoomService.ClampInsideRoom(runtime: RoomRuntime, point: Vector3, inset: number): Vector3
	local lp = runtime.BoundsCFrame:PointToObjectSpace(point)
	local half = runtime.BoundsSize / 2 - Vector3.one * inset
	local clamped = Vector3.new(math.clamp(lp.X, -half.X, half.X), math.clamp(lp.Y, -half.Y + inset, half.Y), math.clamp(lp.Z, -half.Z, half.Z))
	return runtime.BoundsCFrame:PointToWorldSpace(clamped)
end

return RoomService
