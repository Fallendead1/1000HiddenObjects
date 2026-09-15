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
	DepositedCount: number, -- objects cleaned into bins
	TotalObjects: number, -- every real object, including the ones still packed in junk chunks
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

-- XZ distance from a point to an object's footprint on the floor. 0 when the point is under
-- it. Uses the world-aligned box the object covers, so it stays right however the object has
-- tumbled (loose physics lays things on their side; the object's own Y is not always up).
function RoomService.FootprintDistanceXZ(root: BasePart, cframe: CFrame, point: Vector3): number
	local s = root.Size
	local r, u, l = cframe.RightVector, cframe.UpVector, cframe.LookVector
	local ex = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2
	local ez = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2
	local dx = math.max(0, math.abs(point.X - cframe.Position.X) - ex)
	local dz = math.max(0, math.abs(point.Z - cframe.Position.Z) - ez)
	return math.sqrt(dx * dx + dz * dz)
end

-- ===== Wayfinding =====
-- Big LEFT SIDE / RIGHT SIDE signs on the side walls and a CENTER sign hanging over the middle,
-- so "left / right side" clues read the same way from the door (you walk in facing -Z, so -X is
-- your left). Visual only: no collision, invisible to queries and throws.
local SIGN_COLORS = {
	LEFT = Color3.fromRGB(0, 180, 255),
	RIGHT = Color3.fromRGB(255, 150, 0),
	CENTER = Color3.fromRGB(255, 196, 0),
}

local function signPart(parent: Instance, name: string, cframe: CFrame, size: Vector3, side: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cframe
	p:SetAttribute("Side", side)
	p.Parent = parent
	return p
end

local function signGui(part: BasePart, face: Enum.NormalId, title: string, subtitle: string?, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui_" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
	panel.BackgroundTransparency = 0.08
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 28)
	corner.Parent = panel
	local border = Instance.new("UIStroke")
	border.Name = "Border"
	border.Color = color
	border.Thickness = 10
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = panel
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -48, subtitle and 0.56 or 0.78, 0)
	label.Position = UDim2.new(0, 24, subtitle and 0.08 or 0.11, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = title
	label.Parent = panel
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Thickness = 5
	outline.Parent = label
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	gradient.Parent = label
	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.new(1, -48, 0.24, 0)
		sub.Position = UDim2.new(0, 24, 0.68, 0)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.TextColor3 = color
		sub.Text = subtitle
		sub.Parent = panel
	end
end

local function addWayfinding(model: Model, config, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Wayfinding"
	folder.Parent = model
	local size = config.Size
	local signs = config.SideSigns or {}
	local height = 5
	local y = math.min(21, size.Y - height / 2 - 1.5)
	for _, side in ipairs({ "LEFT", "RIGHT" }) do
		local def = signs[side] or {}
		local inward = side == "LEFT" and 1 or -1
		local pos = Vector3.new(-inward * (size.X / 2 - 0.2), y, def.Z or 0)
		local part = signPart(folder, "SideSign_" .. side, origin * CFrame.lookAt(pos, pos + Vector3.new(inward, 0, 0)), Vector3.new(def.Width or 16, height, 0.2), side)
		signGui(part, Enum.NormalId.Front, side .. " SIDE", def.Landmarks, SIGN_COLORS[side])
	end
	-- CENTER hangs from the ceiling over the middle of the room, readable from both ends.
	local centerPos = Vector3.new(0, math.min(21.5, size.Y - 4.5), 0)
	local board = signPart(folder, "CenterSign", origin * CFrame.lookAt(centerPos, centerPos + Vector3.zAxis), Vector3.new(12, 3.6, 0.3), "CENTER")
	board.Transparency = 0
	board.Material = Enum.Material.SmoothPlastic
	board.Color = Color3.fromRGB(20, 22, 34)
	signGui(board, Enum.NormalId.Front, "CENTER", nil, SIGN_COLORS.CENTER)
	signGui(board, Enum.NormalId.Back, "CENTER", nil, SIGN_COLORS.CENTER)
	local top, bottom = size.Y, centerPos.Y + 1.8
	for _, dx in ipairs({ -4.5, 4.5 }) do
		local cord = signPart(folder, "SignCord", origin * CFrame.new(dx, (top + bottom) / 2, 0), Vector3.new(0.12, top - bottom, 0.12), "")
		cord.Transparency = 0
		cord.Material = Enum.Material.Metal
		cord.Color = Color3.fromRGB(40, 40, 50)
	end
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
	addWayfinding(model, config, origin)

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
		DepositedCount = 0,
		TotalObjects = 0,
	}

	for _, inst in ipairs(taggedIn(model, "Clutter")) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("ObjectId") or inst.Name
			table.insert(runtime.Objects, inst)
			runtime.ObjectsById[id] = inst
			if inst:GetAttribute("IsChunk") then
				runtime.TotalObjects += #string.split(inst:GetAttribute("Contents") or "", ",")
			else
				runtime.TotalObjects += 1
			end
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
	-- Anything that slid into a bin while settling goes back on the pile beside it (otherwise
	-- it would be cleaned for free the moment the search starts).
	local clutter = runtime.Model:FindFirstChild("Clutter")
	local bins = runtime.Model:FindFirstChild("Bins")
	if clutter and bins then
		local inParams = OverlapParams.new()
		inParams.FilterType = Enum.RaycastFilterType.Include
		inParams.FilterDescendantsInstances = { clutter }
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Include
		downParams.FilterDescendantsInstances = { clutter, runtime.Model:FindFirstChild("Structure") }
		for _, mouth in ipairs(bins:GetChildren()) do
			if mouth:IsA("BasePart") then
				local moved = {}
				for _, part in ipairs(workspace:GetPartBoundsInBox(mouth.CFrame, mouth.Size, inParams)) do
					local root = CollectionService:HasTag(part, "Clutter") and part or part.Parent
					if root:IsA("BasePart") and not moved[root] then
						moved[root] = true
						local side = (#moved % 2 == 0) and 1 or -1
						local spot = mouth.Position + Vector3.new(0, 0, side * (mouth.Size.Z / 2 + 2.5))
						local hit = workspace:Raycast(spot + Vector3.new(0, 15, 0), Vector3.new(0, -30, 0), downParams)
						local y = hit and hit.Position.Y or runtime.FloorY
						root.CFrame = CFrame.new(spot.X, y + root.Size.Y / 2 + 0.05, spot.Z)
						root.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
		end
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

-- Add an object created during play (junk chunk pieces) to the room.
function RoomService.Register(runtime: RoomRuntime, root: BasePart)
	table.insert(runtime.Objects, root)
	runtime.ObjectsById[root:GetAttribute("ObjectId") or root.Name] = root
	root:SetAttribute("OriginalCFrame", root.CFrame)
end

function RoomService.Destroy(runtime: RoomRuntime)
	if runtime.Model then
		runtime.Model:Destroy()
	end
end

-- Room cleaned: share of every real object (packed ones included) deposited in bins.
function RoomService.GetProgress(runtime: RoomRuntime): number
	if runtime.TotalObjects == 0 then
		return 0
	end
	return math.min(1, runtime.DepositedCount / runtime.TotalObjects)
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
