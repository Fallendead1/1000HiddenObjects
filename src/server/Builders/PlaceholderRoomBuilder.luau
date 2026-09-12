--[[
	Builds placeholder room geometry from a room config. Output follows the room model
	contract that RoomService parses (also the contract for final art):

	RoomModel
	  Structure/        anchored, collidable, raycast-blocking parts (floor, walls, furniture)
	  RoomSpawn         Part tagged RoomSpawn
	  TrashChute        Model tagged TrashChute (PrimaryPart = sell zone, attr Radius)
	  Regions/          Part per region tagged SearchRegion, attr RegionId, RegionName
	  Clusters/         Model per cluster tagged ClutterCluster (attrs ClusterId, RegionId,
	                    Weight, TargetEligible) with SearchVolume Part + Chunks/ folder
	  Sockets/          Part per socket tagged TargetSocket (attrs SocketId, ClusterId, RegionId, Difficulty)
]]

local CollectionService = game:GetService("CollectionService")

local RoomBuilder = {}

local Palettes = {
	Books = {
		Colors = { Color3.fromRGB(200, 60, 60), Color3.fromRGB(60, 100, 200), Color3.fromRGB(60, 170, 90), Color3.fromRGB(240, 200, 60), Color3.fromRGB(150, 80, 200), Color3.fromRGB(240, 240, 240) },
		Sizes = { Vector3.new(1.6, 0.4, 1.2), Vector3.new(1.4, 0.5, 1.0), Vector3.new(2.0, 0.35, 1.4) },
		Material = Enum.Material.SmoothPlastic,
	},
	Clothes = {
		Colors = { Color3.fromRGB(230, 90, 120), Color3.fromRGB(90, 150, 230), Color3.fromRGB(250, 250, 250), Color3.fromRGB(60, 60, 80), Color3.fromRGB(120, 200, 120), Color3.fromRGB(250, 170, 60) },
		Sizes = { Vector3.new(2.2, 1.0, 1.8), Vector3.new(1.8, 0.8, 2.4), Vector3.new(2.6, 1.2, 2.0) },
		Material = Enum.Material.Fabric,
		Rounded = true,
	},
	Pillows = {
		Colors = { Color3.fromRGB(250, 250, 255), Color3.fromRGB(200, 220, 255), Color3.fromRGB(255, 210, 220), Color3.fromRGB(220, 255, 220) },
		Sizes = { Vector3.new(3, 1.2, 2), Vector3.new(2.4, 1.0, 2.4) },
		Material = Enum.Material.Fabric,
		Rounded = true,
	},
	Boxes = {
		Colors = { Color3.fromRGB(190, 140, 90), Color3.fromRGB(170, 120, 75), Color3.fromRGB(210, 160, 110) },
		Sizes = { Vector3.new(2.2, 2.2, 2.2), Vector3.new(3, 1.6, 2), Vector3.new(1.6, 1.6, 1.6) },
		Material = Enum.Material.SmoothPlastic,
	},
	Toys = {
		Colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 120, 220) },
		Sizes = { Vector3.new(1.4, 1.4, 1.4), Vector3.new(1.0, 1.6, 1.0), Vector3.new(1.8, 1.0, 1.2) },
		Material = Enum.Material.SmoothPlastic,
		Balls = true,
	},
	Paper = {
		Colors = { Color3.fromRGB(250, 250, 250), Color3.fromRGB(240, 240, 220), Color3.fromRGB(230, 230, 250) },
		Sizes = { Vector3.new(2.0, 0.15, 1.5), Vector3.new(1.6, 0.2, 2.2), Vector3.new(2.4, 0.12, 1.8) },
		Material = Enum.Material.SmoothPlastic,
	},
	Electronics = {
		Colors = { Color3.fromRGB(40, 40, 50), Color3.fromRGB(70, 70, 80), Color3.fromRGB(200, 200, 205), Color3.fromRGB(30, 60, 90) },
		Sizes = { Vector3.new(1.8, 0.6, 1.2), Vector3.new(1.2, 1.2, 0.6), Vector3.new(2.6, 0.4, 1.0) },
		Material = Enum.Material.SmoothPlastic,
	},
	Shoes = {
		Colors = { Color3.fromRGB(40, 40, 40), Color3.fromRGB(250, 250, 250), Color3.fromRGB(200, 50, 50), Color3.fromRGB(60, 90, 160) },
		Sizes = { Vector3.new(1.8, 0.8, 0.8), Vector3.new(1.6, 0.7, 0.7) },
		Material = Enum.Material.SmoothPlastic,
	},
}
Palettes.Mixed = {
	Mixed = { "Books", "Clothes", "Boxes", "Toys", "Paper", "Electronics", "Shoes" },
}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function hashString(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function buildStructure(config, origin: CFrame, parent: Folder)
	local size = config.Size
	local halfX, halfZ = size.X / 2, size.Z / 2
	local wallT = 1

	part({ Name = "Floor", Size = Vector3.new(size.X + 2, 1, size.Z + 2), CFrame = origin * CFrame.new(0, -0.5, 0), Color = config.FloorColor, Material = Enum.Material.WoodPlanks }, parent)
	part({ Name = "Ceiling", Size = Vector3.new(size.X + 2, 1, size.Z + 2), CFrame = origin * CFrame.new(0, size.Y + 0.5, 0), Color = Color3.fromRGB(240, 240, 245), Material = Enum.Material.SmoothPlastic }, parent)
	part({ Name = "WallBack", Size = Vector3.new(size.X + 2, size.Y, wallT), CFrame = origin * CFrame.new(0, size.Y / 2, -halfZ - 0.5), Color = config.WallColor, Material = Enum.Material.SmoothPlastic }, parent)
	part({ Name = "WallFront", Size = Vector3.new(size.X + 2, size.Y, wallT), CFrame = origin * CFrame.new(0, size.Y / 2, halfZ + 0.5), Color = config.WallColor, Material = Enum.Material.SmoothPlastic }, parent)
	part({ Name = "WallLeft", Size = Vector3.new(wallT, size.Y, size.Z + 2), CFrame = origin * CFrame.new(-halfX - 0.5, size.Y / 2, 0), Color = config.WallColor, Material = Enum.Material.SmoothPlastic }, parent)
	part({ Name = "WallRight", Size = Vector3.new(wallT, size.Y, size.Z + 2), CFrame = origin * CFrame.new(halfX + 0.5, size.Y / 2, 0), Color = config.WallColor, Material = Enum.Material.SmoothPlastic }, parent)
	part({ Name = "Baseboard", Size = Vector3.new(size.X + 2, 1.2, 0.3), CFrame = origin * CFrame.new(0, 0.6, -halfZ + 0.15), Color = Color3.fromRGB(250, 250, 250), Material = Enum.Material.SmoothPlastic }, parent)

	-- Ceiling lights so the enclosed room is bright and readable.
	for _, x in ipairs({ -halfX * 0.6, 0, halfX * 0.6 }) do
		for _, z in ipairs({ -halfZ * 0.55, halfZ * 0.55 }) do
			local lamp = part({ Name = "CeilingLight", Size = Vector3.new(6, 0.4, 6), CFrame = origin * CFrame.new(x, size.Y - 0.2, z), Color = Color3.fromRGB(255, 250, 230), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false }, parent)
			local light = Instance.new("PointLight")
			light.Brightness = 1.6
			light.Range = 48
			light.Color = Color3.fromRGB(255, 245, 225)
			light.Shadows = false
			light.Parent = lamp
		end
	end

	for _, f in ipairs(config.Furniture or {}) do
		local p = part({
			Name = f.Name,
			Size = f.Size,
			CFrame = origin * CFrame.new(f.Position),
			Color = f.Color,
			Material = f.Material or Enum.Material.SmoothPlastic,
			Shape = f.Shape or Enum.PartType.Block,
		}, parent)
		if f.Material == Enum.Material.Glass then
			p.Transparency = 0.4
		end
		if f.Hollow then
			p.CanCollide = false
		end
	end
end

local function buildRegions(config, origin: CFrame, parent: Folder)
	for _, r in ipairs(config.Regions) do
		local p = part({
			Name = "Region_" .. r.Id,
			Size = r.Size,
			CFrame = origin * CFrame.new(r.Center),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, parent)
		p:SetAttribute("RegionId", r.Id)
		p:SetAttribute("RegionName", r.Name)
		CollectionService:AddTag(p, "SearchRegion")
	end
end

local function buildChunks(cluster, rng: Random, origin: CFrame, chunksFolder: Folder)
	local paletteName = cluster.Palette or "Mixed"
	local center = cluster.Center
	local size = cluster.Size
	local count = cluster.ChunkCount or 20
	local flat = cluster.Flat == true

	local chunks = {}
	for i = 1, count do
		local pName = paletteName
		if pName == "Mixed" then
			pName = pick(rng, Palettes.Mixed.Mixed)
		end
		local palette = Palettes[pName]

		-- Sample a point inside a dome-shaped pile: denser and taller toward the middle.
		local u = rng:NextNumber()
		local ang = rng:NextNumber(0, math.pi * 2)
		local radial = math.sqrt(u)
		local px = math.cos(ang) * radial * size.X * 0.45
		local pz = math.sin(ang) * radial * size.Z * 0.45
		local heightFactor = math.max(0, 1 - radial * radial)
		local maxY = flat and size.Y * 0.8 or size.Y * heightFactor
		local py = rng:NextNumber(0.3, math.max(0.6, maxY))

		local baseSize = pick(rng, palette.Sizes)
		local scale = rng:NextNumber(0.8, 1.35)
		local chunkSize = baseSize * scale
		if flat then
			chunkSize = Vector3.new(chunkSize.X, math.min(chunkSize.Y, 1.2), chunkSize.Z)
		end

		local localPos = center + Vector3.new(px, py + chunkSize.Y / 2, pz)
		local rot = CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-12, 12)))

		local chunk = part({
			Name = string.format("Chunk%02d", i),
			Size = chunkSize,
			CFrame = origin * CFrame.new(localPos) * rot,
			Color = pick(rng, palette.Colors),
			Material = palette.Material,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, chunksFolder)
		if palette.Balls and rng:NextNumber() < 0.4 then
			chunk.Shape = Enum.PartType.Ball
			local d = math.max(chunkSize.X, chunkSize.Y, chunkSize.Z)
			chunk.Size = Vector3.new(d, d, d)
		elseif palette.Rounded then
			chunk.Shape = Enum.PartType.Block
		end
		table.insert(chunks, { Part = chunk, Score = py * 2 + radial * 3 })
	end

	-- Removal order: highest / outermost first so the pile visibly shrinks inward and down.
	table.sort(chunks, function(a, b)
		return a.Score > b.Score
	end)
	for order, entry in ipairs(chunks) do
		entry.Part:SetAttribute("RemovalOrder", order)
	end
end

local function buildClusters(config, origin: CFrame, parent: Folder)
	for _, c in ipairs(config.Clusters) do
		local rng = Random.new(hashString(config.Name .. c.Id))
		local model = Instance.new("Model")
		model.Name = c.Id
		model:SetAttribute("ClusterId", c.Id)
		model:SetAttribute("RegionId", c.RegionId)
		model:SetAttribute("Weight", c.Weight)
		model:SetAttribute("TargetEligible", c.TargetEligible ~= false)
		CollectionService:AddTag(model, "ClutterCluster")

		local volume = part({
			Name = "SearchVolume",
			Size = Vector3.new(c.Size.X, c.Size.Y, c.Size.Z),
			CFrame = origin * CFrame.new(c.Center + Vector3.new(0, c.Size.Y / 2, 0)),
			Transparency = 1,
			CanCollide = false,
			CanQuery = true,
			CanTouch = false,
		}, model)
		volume:SetAttribute("ClusterId", c.Id)
		model.PrimaryPart = volume

		local chunks = Instance.new("Folder")
		chunks.Name = "Chunks"
		chunks.Parent = model
		buildChunks(c, rng, origin, chunks)

		model.Parent = parent
	end
end

local function buildSockets(config, origin: CFrame, parent: Folder)
	local clusterById = {}
	for _, c in ipairs(config.Clusters) do
		clusterById[c.Id] = c
	end
	for _, s in ipairs(config.Sockets) do
		local cluster = clusterById[s.ClusterId]
		local basePos = cluster and cluster.Center or Vector3.zero
		local p = part({
			Name = s.Id,
			Size = Vector3.new(1, 1, 1),
			CFrame = origin * CFrame.new(basePos + s.Offset) * CFrame.Angles(0, math.rad((hashString(s.Id) % 360)), 0),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, parent)
		p:SetAttribute("SocketId", s.Id)
		p:SetAttribute("ClusterId", s.ClusterId)
		p:SetAttribute("RegionId", cluster and cluster.RegionId or "")
		p:SetAttribute("Difficulty", s.Difficulty or 1)
		CollectionService:AddTag(p, "TargetSocket")
	end
end

local function buildTrashChute(config, origin: CFrame, parent: Model)
	local model = Instance.new("Model")
	model.Name = "TrashChute"
	local pos = config.TrashChutePosition
	local body = part({ Name = "Body", Size = Vector3.new(6, 7, 5), CFrame = origin * CFrame.new(pos + Vector3.new(0, 3.5, 0)), Color = Color3.fromRGB(70, 210, 110), Material = Enum.Material.SmoothPlastic }, model)
	part({ Name = "Mouth", Size = Vector3.new(4.5, 3, 1), CFrame = origin * CFrame.new(pos + Vector3.new(0, 4.5, -2.6)), Color = Color3.fromRGB(20, 25, 35), Material = Enum.Material.SmoothPlastic }, model)
	part({ Name = "Lip", Size = Vector3.new(5, 0.6, 2.5), CFrame = origin * CFrame.new(pos + Vector3.new(0, 3.0, -3.4)), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.SmoothPlastic }, model)
	part({ Name = "Pipe", Size = Vector3.new(3, 8, 3), CFrame = origin * CFrame.new(pos + Vector3.new(0, 11, 0)), Color = Color3.fromRGB(90, 100, 130), Material = Enum.Material.Metal }, model)
	local zone = part({
		Name = "SellZone",
		Size = Vector3.new(14, 8, 14),
		CFrame = origin * CFrame.new(pos + Vector3.new(0, 4, -4)),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	}, model)
	zone:SetAttribute("Radius", 7)
	model.PrimaryPart = zone
	model:SetAttribute("Radius", 7)
	CollectionService:AddTag(model, "TrashChute")
	model.Parent = parent
	return model
end

function RoomBuilder.Build(config, origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Room" .. config.DisplayNumber

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = model
	buildStructure(config, origin, structure)

	local spawn = part({
		Name = "RoomSpawn",
		Size = Vector3.new(8, 1, 6),
		CFrame = origin * CFrame.new(config.SpawnPosition - Vector3.new(0, config.SpawnPosition.Y - 0.5, 0)),
		Color = Color3.fromRGB(80, 90, 130),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 0.6,
	}, model)
	CollectionService:AddTag(spawn, "RoomSpawn")

	buildTrashChute(config, origin, model)

	local regions = Instance.new("Folder")
	regions.Name = "Regions"
	regions.Parent = model
	buildRegions(config, origin, regions)

	local clusters = Instance.new("Folder")
	clusters.Name = "Clusters"
	clusters.Parent = model
	buildClusters(config, origin, clusters)

	local sockets = Instance.new("Folder")
	sockets.Name = "Sockets"
	sockets.Parent = model
	buildSockets(config, origin, sockets)

	return model
end

return RoomBuilder
