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
local DepositConfig = require(ReplicatedStorage.Shared.Config.DepositConfig)

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
	ExitDoor: BasePart?, -- walk into it to go back to the lobby (config ExitDoor, tagged "ExitDoor")
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

-- One upright part of a bin, scaled about the bin's base point (X = Z scale, so its turn about
-- the vertical doesn't matter; the size axis that points up takes the height scale).
local function scaleBinPart(part: BasePart, base: Vector3, scale: Vector3)
	local rotation = part.CFrame - part.Position
	part.CFrame = CFrame.new(base + (part.Position - base) * scale) * rotation
	local function along(dir: Vector3): number
		return math.abs(dir.Y) > 0.99 and scale.Y or scale.X
	end
	local axes = Vector3.new(along(part.CFrame.RightVector), along(part.CFrame.UpVector), along(part.CFrame.LookVector))
	part.Size *= axes
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.FileMesh then
		mesh.Scale *= axes
	end
end

-- Bins are built bigger than authored (DepositConfig.BinScale) so they stand out in the mess:
-- the mouth, the collision walls around it (Structure Bin* parts) and the prop model on it.
local function scaleBins(model: Model)
	local scale = DepositConfig.BinScale
	if not scale or scale == Vector3.one then
		return
	end
	local structure = model:FindFirstChild("Structure")
	local props = model:FindFirstChild("Props")
	for _, mouth in ipairs(model:GetDescendants()) do
		if mouth:IsA("BasePart") and CollectionService:HasTag(mouth, "DepositBin") then
			local def = DepositConfig.Types[mouth:GetAttribute("BinType") or ""]
			local reach = math.max(mouth.Size.X, mouth.Size.Z) / 2 + 1.5
			local parts = { mouth }
			for _, part in ipairs(structure and structure:GetDescendants() or {}) do
				if part:IsA("BasePart") and string.sub(part.Name, 1, 3) == "Bin" and ((part.Position - mouth.Position) * Vector3.new(1, 0, 1)).Magnitude < reach then
					table.insert(parts, part)
				end
			end
			for _, prop in ipairs(props and props:GetChildren() or {}) do
				if def and prop.Name == def.PropKey and ((prop:GetPivot().Position - mouth.Position) * Vector3.new(1, 0, 1)).Magnitude < 3 then
					for _, p in ipairs(prop:GetDescendants()) do
						if p:IsA("BasePart") then
							table.insert(parts, p)
						end
					end
				end
			end
			local floorY = math.huge
			for _, p in ipairs(parts) do
				floorY = math.min(floorY, p.Position.Y - p.Size.Y / 2)
			end
			local base = Vector3.new(mouth.Position.X, floorY, mouth.Position.Z)
			for _, p in ipairs(parts) do
				scaleBinPart(p, base, scale)
			end
		end
	end
end

-- Solid blocks a room adds to its shell (config.Fills), e.g. closing the gap under a bed so
-- nothing can hide where players can't reach. LookLike copies an existing part's colour.
local function addFills(model: Model, config, origin: CFrame)
	local structure = model:FindFirstChild("Structure")
	if not structure or not config.Fills then
		return
	end
	for _, fill in ipairs(config.Fills) do
		local part = Instance.new("Part")
		part.Name = fill.Name
		part.Anchored = true
		part.CanCollide = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = fill.Size
		part.CFrame = origin * CFrame.new(fill.Center)
		local look = fill.LookLike and structure:FindFirstChild(fill.LookLike, true)
		if look and look:IsA("BasePart") then
			part.Color = look.Color
			part.Material = look.Material
			part.MaterialVariant = look.MaterialVariant
		end
		part.Parent = structure
	end
end

-- Shell parts whose faces sit exactly on top of each other flicker (z-fighting): a baseboard
-- flush with the wainscot, layers of a poster, a cap on a headboard... For every such pair with
-- different looks, the smaller part moves out through the shared face, a hair toward the room,
-- so it clearly draws in front. Only faces seen from inside the room count, and only boxes
-- square to the world axes are checked (walls, trim, panels).
local COPLANAR_TOLERANCE = 0.02
local COPLANAR_NUDGE = 0.05
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

local function on(v: Vector3, axis: number): number
	return if axis == 1 then v.X elseif axis == 2 then v.Y else v.Z
end

local function separateCoplanar(model: Model, centre: Vector3): number
	local boxes = {}
	for _, folderName in ipairs({ "Structure", "Decor", "Props" }) do
		local folder = model:FindFirstChild(folderName)
		for _, p in ipairs(folder and folder:GetDescendants() or {}) do
			if p:IsA("BasePart") and p.Transparency < 0.95 then
				local square = true
				for _, v in ipairs({ p.CFrame.RightVector, p.CFrame.UpVector, p.CFrame.LookVector }) do
					if math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) < 0.999 then
						square = false
						break
					end
				end
				if square then
					table.insert(boxes, { Part = p, Volume = p.Size.X * p.Size.Y * p.Size.Z })
				end
			end
		end
	end
	local fixed = 0
	for _ = 1, 3 do
		for _, box in ipairs(boxes) do
			local h = box.Part.CFrame:VectorToWorldSpace(box.Part.Size / 2)
			h = Vector3.new(math.abs(h.X), math.abs(h.Y), math.abs(h.Z))
			box.Min, box.Max = box.Part.Position - h, box.Part.Position + h
		end
		local nudges: { [BasePart]: Vector3 } = {}
		for i = 1, #boxes do
			local a = boxes[i]
			for j = i + 1, #boxes do
				local b = boxes[j]
				local t = COPLANAR_TOLERANCE
				if (a.Part.Color ~= b.Part.Color or a.Part.Material ~= b.Part.Material)
					and a.Min.X <= b.Max.X + t and b.Min.X <= a.Max.X + t
					and a.Min.Y <= b.Max.Y + t and b.Min.Y <= a.Max.Y + t
					and a.Min.Z <= b.Max.Z + t and b.Min.Z <= a.Max.Z + t
				then
					for axis = 1, 3 do
						local u, w = axis % 3 + 1, (axis + 1) % 3 + 1
						local overlapU = math.min(on(a.Max, u), on(b.Max, u)) - math.max(on(a.Min, u), on(b.Min, u))
						local overlapW = math.min(on(a.Max, w), on(b.Max, w)) - math.max(on(a.Min, w), on(b.Min, w))
						if overlapU > 0.05 and overlapW > 0.05 then
							-- Check both shared faces (a baseboard can be flush with the wainscot on
							-- its hidden back too); fix the one that looks into the room.
							for _, normal in ipairs({ 1, -1 }) do
								local fa = if normal == 1 then on(a.Max, axis) else on(a.Min, axis)
								local fb = if normal == 1 then on(b.Max, axis) else on(b.Min, axis)
								if math.abs(fa - fb) < t and (on(centre, axis) - fa) * normal > 0 then
									local small = if a.Volume <= b.Volume then a.Part else b.Part
									nudges[small] = (nudges[small] or Vector3.zero) + AXES[axis] * normal * COPLANAR_NUDGE
									break
								end
							end
						end
					end
				end
			end
		end
		if next(nudges) == nil then
			break
		end
		for part, offset in pairs(nudges) do
			part.CFrame += offset
			fixed += 1
		end
	end
	return fixed
end

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
	scaleBins(model)
	addFills(model, config, origin)
	local fixedFaces = separateCoplanar(model, origin.Position + Vector3.new(0, config.Size.Y / 2, 0))
	if fixedFaces > 0 then
		print(string.format("[RoomService] %s: moved %d parts off flickering shared faces", config.Name, fixedFaces))
	end

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

	-- A prebuilt shell can carry regions and sockets its config has since dropped (e.g. the old
	-- under-bed spots): the config decides which are real.
	local configRegions, configSockets = {}, {}
	for _, r in ipairs(config.Regions or {}) do
		configRegions[r.Id] = true
	end
	for _, s in ipairs(config.Sockets or {}) do
		configSockets[s.Id] = true
	end

	for _, inst in ipairs(taggedIn(model, "SearchRegion")) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("RegionId") or inst.Name
			if next(configRegions) and not configRegions[id] then
				inst:Destroy()
			else
				runtime.Regions[id] = { Part = inst, Name = inst:GetAttribute("RegionName") or id }
			end
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
		if inst:IsA("BasePart") and next(configSockets) and not configSockets[inst:GetAttribute("SocketId") or inst.Name] then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
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

	-- The way out: the client puts a RETURN TO LOBBY sign and button on it (ExitDoorController).
	local structure = runtime.Model:FindFirstChild("Structure")
	local doorName = runtime.Config.ExitDoor
	local door = doorName and structure and structure:FindFirstChild(doorName, true)
	if door and door:IsA("BasePart") then
		CollectionService:AddTag(door, "ExitDoor")
		runtime.ExitDoor = door
	end

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

-- Put an object that left the room back inside it, just above the floor (it drops from there).
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

-- Release every clutter object to real physics (unanchored, server-owned so no client can shove
-- things around). The room then settles (FinishSettle) and is anchored where it came to rest
-- (ObjectService.FreezeRoom).
function RoomService.Release(runtime: RoomRuntime)
	for _, obj in ipairs(runtime.Objects) do
		obj.Anchored = false
		pcall(function()
			obj:SetNetworkOwner(nil)
		end)
	end
end

--[[
	Wait for a released room to settle (at most maxSeconds after startedAt), then record where
	everything actually came to rest. OriginalCFrame and the key's blocker groups are taken from
	the settled room, so natural settling never counts as a player moving something. Returns the
	seconds since startedAt and the objects it put back by hand (they still have to drop).
]]
function RoomService.FinishSettle(runtime: RoomRuntime, startedAt: number, maxSeconds: number): (number, { [BasePart]: boolean })
	-- Wait until the piles stop sliding: under 1% of objects still going anywhere (net movement,
	-- so junk that only jitters in place doesn't hold the room up). The room is anchored right
	-- after; whatever is still moving stays loose until it lands (ObjectService.FreezeRoom).
	task.wait(math.max(0, 0.5 - (os.clock() - startedAt)))
	local objects = runtime.Objects
	local last = {}
	for i, obj in ipairs(objects) do
		last[i] = obj.Position
	end
	local loose = {}
	while true do
		task.wait(0.25)
		local moving = {}
		for i, obj in ipairs(objects) do
			local p = obj.Position
			-- Faster than 1 stud/s.
			if (p - last[i]).Magnitude > 0.25 then
				table.insert(moving, obj)
			end
			last[i] = p
		end
		if #moving <= #objects * 0.01 or os.clock() - startedAt >= maxSeconds then
			for _, obj in ipairs(moving) do
				loose[obj] = true
			end
			break
		end
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
						loose[root] = true
					end
				end
			end
		end
	end
	for _, obj in ipairs(runtime.Objects) do
		if RoomService.IsOutOfRoom(runtime, obj) then
			RoomService.RecoverObject(runtime, obj)
			loose[obj] = true
		end
		obj:SetAttribute("OriginalCFrame", obj.CFrame)
	end
	RoomService.ComputeBlockers(runtime)
	return os.clock() - startedAt, loose
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
