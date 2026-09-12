--[[
	Builds the small placeholder lobby from primitives. Everything gameplay-relevant is
	tagged/attributed so a final art pass can replace the geometry without code changes.

	Tags: QueueZone, CollectionBoard, ShopStand, Leaderboard (attr Kind), LobbySpawn,
	      FutureDoor, LobbyKeyDeco (client rotates), QueueLight (client pulses)
]]

local CollectionService = game:GetService("CollectionService")

local LobbyBuilder = {}

local C = Color3.fromRGB

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

local function deco(props, parent)
	props.CanCollide = props.CanCollide == nil and false or props.CanCollide
	props.CanQuery = false
	props.CanTouch = false
	return part(props, parent)
end

local function frameBoard(parent: Instance, name: string, cframe: CFrame, width: number, height: number, faceAxis: string)
	-- Board with gold frame. faceAxis "Z" = faces along Z (front/back), "X" = faces along X.
	local depth = 1
	local size = faceAxis == "Z" and Vector3.new(width, height, depth) or Vector3.new(depth, height, width)
	local board = part({ Name = name, Size = size, CFrame = cframe, Color = C(24, 30, 48), Material = Enum.Material.SmoothPlastic }, parent)
	local frameSize = faceAxis == "Z" and Vector3.new(width + 1.2, height + 1.2, depth * 0.8) or Vector3.new(depth * 0.8, height + 1.2, width + 1.2)
	deco({ Name = name .. "Frame", Size = frameSize, CFrame = cframe * CFrame.new(faceAxis == "Z" and Vector3.new(0, 0, 0.15) or Vector3.new(0.15, 0, 0)), Color = C(255, 200, 40), Material = Enum.Material.SmoothPlastic }, parent)
	return board
end

function LobbyBuilder.Build(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Lobby"

	local navy = C(34, 40, 62)
	local tileA = C(58, 66, 98)
	local tileB = C(50, 58, 88)
	local gold = C(255, 200, 40)
	local green = C(70, 210, 110)

	-- Tiled floor (8 x 7 tiles of 10 studs)
	for ix = 0, 7 do
		for iz = 0, 6 do
			local x = -35 + ix * 10
			local z = -30 + iz * 10
			part({ Name = "FloorTile", Size = Vector3.new(10, 2, 10), CFrame = origin * CFrame.new(x, -1, z), Color = (ix + iz) % 2 == 0 and tileA or tileB, Material = Enum.Material.SmoothPlastic }, model)
		end
	end

	-- Walls with an accent band
	local wallH = 12
	for _, w in ipairs({
		{ "WallN", Vector3.new(82, wallH, 2), CFrame.new(0, wallH / 2, -36) },
		{ "WallS", Vector3.new(82, wallH, 2), CFrame.new(0, wallH / 2, 36) },
		{ "WallE", Vector3.new(2, wallH, 72), CFrame.new(41, wallH / 2, 0) },
		{ "WallW", Vector3.new(2, wallH, 72), CFrame.new(-41, wallH / 2, 0) },
	}) do
		part({ Name = w[1], Size = w[2], CFrame = origin * w[3], Color = navy, Material = Enum.Material.SmoothPlastic }, model)
	end
	for _, b in ipairs({
		{ Vector3.new(82, 0.8, 0.3), CFrame.new(0, 9.5, -34.85) },
		{ Vector3.new(82, 0.8, 0.3), CFrame.new(0, 9.5, 34.85) },
		{ Vector3.new(0.3, 0.8, 72), CFrame.new(39.85, 9.5, 0) },
		{ Vector3.new(0.3, 0.8, 72), CFrame.new(-39.85, 9.5, 0) },
	}) do
		deco({ Name = "AccentBand", Size = b[1], CFrame = origin * b[2], Color = gold, Material = Enum.Material.Neon }, model)
	end

	-- Spawn pad facing the queue circle (-Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = origin * CFrame.new(0, 0.5, 22)
	spawn.Anchored = true
	spawn.Color = C(80, 90, 130)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = model
	CollectionService:AddTag(spawn, "LobbySpawn")
	deco({ Name = "SpawnGlow", Size = Vector3.new(13, 0.2, 13), CFrame = origin * CFrame.new(0, 1.05, 22), Color = C(90, 190, 255), Material = Enum.Material.Neon, Transparency = 0.8 }, model)
	deco({ Name = "SpawnArrow", Size = Vector3.new(2.5, 0.25, 4), CFrame = origin * CFrame.new(0, 1.15, 15.5), Color = gold, Material = Enum.Material.Neon }, model)

	-- Queue circle
	local queue = part({
		Name = "QueueZone",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 18, 18),
		CFrame = origin * CFrame.new(0, 0.25, -8) * CFrame.Angles(0, 0, math.rad(90)),
		Color = green,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.35,
	}, model)
	queue:SetAttribute("Radius", 9)
	queue:SetAttribute("State", "Empty")
	queue:SetAttribute("Count", 0)
	queue:SetAttribute("MaxPlayers", 4)
	queue:SetAttribute("Countdown", 0)
	queue:SetAttribute("Message", "STEP INSIDE TO PLAY")
	queue:SetAttribute("RoomId", 1)
	CollectionService:AddTag(queue, "QueueZone")
	deco({ Name = "QueueRingOuter", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 20, 20), CFrame = origin * CFrame.new(0, 0.15, -8) * CFrame.Angles(0, 0, math.rad(90)), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic }, model)
	deco({ Name = "QueueRingInner", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 6, 6), CFrame = origin * CFrame.new(0, 0.3, -8) * CFrame.Angles(0, 0, math.rad(90)), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic }, model)
	-- Light posts around the ring (client pulses these)
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		local x, z = math.cos(ang) * 10.5, -8 + math.sin(ang) * 10.5
		deco({ Name = "QueuePost", Size = Vector3.new(0.8, 3, 0.8), CFrame = origin * CFrame.new(x, 1.5, z), Color = C(80, 90, 130), Material = Enum.Material.SmoothPlastic }, model)
		local light = deco({ Name = "QueueLight", Size = Vector3.new(1, 1, 1), CFrame = origin * CFrame.new(x, 3.5, z), Color = green, Material = Enum.Material.Neon, Shape = Enum.PartType.Ball }, model)
		CollectionService:AddTag(light, "QueueLight")
	end
	deco({ Name = "QueueSignAnchor", Size = Vector3.new(1, 1, 1), CFrame = origin * CFrame.new(0, 8.5, -8), Transparency = 1 }, model)

	-- Giant rotating Golden Key high above the queue (client rotates)
	local keyModel = Instance.new("Model")
	keyModel.Name = "LobbyKeyDeco"
	local gk = C(255, 200, 40)
	local kOrigin = origin * CFrame.new(0, 24, -14)
	local head = deco({ Name = "Head", Size = Vector3.new(4.5, 4.5, 1.2), CFrame = kOrigin * CFrame.new(-2.8, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Color = gk, Material = Enum.Material.Metal, Shape = Enum.PartType.Cylinder }, keyModel)
	deco({ Name = "Hole", Size = Vector3.new(1.8, 1.8, 1.4), CFrame = kOrigin * CFrame.new(-2.8, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Color = C(120, 90, 20), Material = Enum.Material.Metal, Shape = Enum.PartType.Cylinder }, keyModel)
	deco({ Name = "Shaft", Size = Vector3.new(6.5, 1.1, 1.1), CFrame = kOrigin * CFrame.new(2, 0, 0), Color = gk, Material = Enum.Material.Metal }, keyModel)
	deco({ Name = "Tooth1", Size = Vector3.new(1, 1.8, 1.1), CFrame = kOrigin * CFrame.new(4.4, -1.2, 0), Color = gk, Material = Enum.Material.Metal }, keyModel)
	deco({ Name = "Tooth2", Size = Vector3.new(1, 1.3, 1.1), CFrame = kOrigin * CFrame.new(2.8, -1, 0), Color = gk, Material = Enum.Material.Metal }, keyModel)
	keyModel.PrimaryPart = head
	local keyLight = Instance.new("PointLight")
	keyLight.Color = gk
	keyLight.Brightness = 1
	keyLight.Range = 18
	keyLight.Parent = head
	CollectionService:AddTag(keyModel, "LobbyKeyDeco")
	keyModel.Parent = model

	-- Collection board (left wall) with gold frame
	local board = frameBoard(model, "CollectionBoard", origin * CFrame.new(-38.5, 6.5, 0), 20, 11, "X")
	CollectionService:AddTag(board, "CollectionBoard")
	deco({ Name = "BoardSpot", Size = Vector3.new(1, 1, 1), CFrame = origin * CFrame.new(-34, 11, 0), Transparency = 1 }, model)

	-- Shop stand (right wall) with counter and striped awning
	local shop = part({ Name = "ShopStand", Size = Vector3.new(6, 4, 8), CFrame = origin * CFrame.new(34, 2, 8), Color = C(150, 90, 230), Material = Enum.Material.SmoothPlastic }, model)
	CollectionService:AddTag(shop, "ShopStand")
	deco({ Name = "ShopCounter", Size = Vector3.new(7, 0.5, 9), CFrame = origin * CFrame.new(34, 4.25, 8), Color = C(230, 230, 240), Material = Enum.Material.SmoothPlastic }, model)
	for _, dz in ipairs({ -4, 4 }) do
		deco({ Name = "ShopPole", Size = Vector3.new(0.5, 6, 0.5), CFrame = origin * CFrame.new(31, 7.5, 8 + dz), Color = C(230, 230, 240), Material = Enum.Material.Metal }, model)
	end
	for i = 0, 5 do
		deco({ Name = "Awning", Size = Vector3.new(8, 0.4, 1.5), CFrame = origin * CFrame.new(34, 10.6, 3.75 + i * 1.5) * CFrame.Angles(0, 0, math.rad(-12)), Color = i % 2 == 0 and C(170, 100, 255) or C(250, 250, 250), Material = Enum.Material.SmoothPlastic }, model)
	end
	deco({ Name = "ShopCoin", Size = Vector3.new(2.2, 2.2, 0.4), CFrame = origin * CFrame.new(34, 13, 8) * CFrame.Angles(0, math.rad(90), 0), Color = gold, Material = Enum.Material.Neon, Shape = Enum.PartType.Cylinder }, model)

	-- Leaderboards (back wall) with frames
	local lbA = frameBoard(model, "Leaderboard_TopFinders", origin * CFrame.new(-16, 7, -33.5), 14, 10, "Z")
	lbA:SetAttribute("Kind", "TopFinders")
	CollectionService:AddTag(lbA, "Leaderboard")
	local lbB = frameBoard(model, "Leaderboard_Fastest", origin * CFrame.new(16, 7, -33.5), 14, 10, "Z")
	lbB:SetAttribute("Kind", "Fastest")
	CollectionService:AddTag(lbB, "Leaderboard")

	-- Locked future portal (right wall, forward)
	local door = part({ Name = "FutureDoor", Size = Vector3.new(1, 9, 7), CFrame = origin * CFrame.new(38.5, 4.5, -18), Color = C(60, 66, 90), Material = Enum.Material.Metal }, model)
	door:SetAttribute("Label", "MORE ROOMS COMING SOON")
	CollectionService:AddTag(door, "FutureDoor")
	deco({ Name = "FutureDoorFrame", Size = Vector3.new(1.2, 10, 8), CFrame = origin * CFrame.new(38.4, 5, -18), Color = gold, Material = Enum.Material.SmoothPlastic }, model)
	deco({ Name = "FutureDoorLock", Size = Vector3.new(0.6, 1.6, 1.6), CFrame = origin * CFrame.new(37.6, 4.5, -18), Color = gold, Material = Enum.Material.Metal, Shape = Enum.PartType.Cylinder }, model)
	deco({ Name = "FutureDoorChain", Size = Vector3.new(0.3, 0.4, 8), CFrame = origin * CFrame.new(37.7, 5.5, -18) * CFrame.Angles(0, 0, math.rad(20)), Color = C(120, 120, 130), Material = Enum.Material.Metal }, model)

	-- Pillars with lights
	for _, x in ipairs({ -30, 30 }) do
		for _, z in ipairs({ -28, 28 }) do
			part({ Name = "Pillar", Size = Vector3.new(2.4, 12, 2.4), CFrame = origin * CFrame.new(x, 6, z), Color = C(80, 90, 130), Material = Enum.Material.SmoothPlastic }, model)
			local cap = deco({ Name = "PillarCap", Size = Vector3.new(3, 0.6, 3), CFrame = origin * CFrame.new(x, 12.3, z), Color = gold, Material = Enum.Material.Neon }, model)
			local light = Instance.new("PointLight")
			light.Color = C(255, 235, 190)
			light.Brightness = 0.8
			light.Range = 26
			light.Parent = cap
		end
	end

	return model
end

return LobbyBuilder
