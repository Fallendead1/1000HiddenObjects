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

	Clutter piles are generated in three layers (base / middle / top) from a small library of
	primitive "props" so every pile reads as a real layered heap. Every chunk is anchored,
	non-collidable and non-queryable so players can never get stuck in clutter.
]]

local CollectionService = game:GetService("CollectionService")

local RoomBuilder = {}

-- ===== Prop library (primitive placeholder props) =====

local C = Color3.fromRGB

local Props = {
	Book = { Shape = "Block", Size = { Vector3.new(1.6, 0.4, 1.2), Vector3.new(2.0, 0.5, 1.4), Vector3.new(1.3, 0.35, 1.0) }, Colors = { C(200, 60, 60), C(60, 100, 200), C(60, 170, 90), C(240, 200, 60), C(150, 80, 200), C(240, 240, 240), C(40, 40, 60) }, Material = Enum.Material.SmoothPlastic },
	OpenBook = { Shape = "Wedge", Size = { Vector3.new(1.4, 0.35, 1.2) }, Colors = { C(250, 250, 240), C(240, 235, 220) }, Material = Enum.Material.SmoothPlastic },
	Magazine = { Shape = "Block", Size = { Vector3.new(1.6, 0.12, 2.1) }, Colors = { C(250, 120, 60), C(90, 200, 250), C(250, 90, 170), C(120, 250, 130) }, Material = Enum.Material.SmoothPlastic },
	Paper = { Shape = "Block", Size = { Vector3.new(1.4, 0.06, 1.9), Vector3.new(1.7, 0.06, 2.2) }, Colors = { C(250, 250, 250), C(245, 240, 220), C(235, 235, 250) }, Material = Enum.Material.SmoothPlastic },
	Shirt = { Shape = "Block", Size = { Vector3.new(2.4, 0.8, 2.0), Vector3.new(2.8, 0.9, 1.8) }, Colors = { C(230, 90, 120), C(90, 150, 230), C(250, 250, 250), C(60, 60, 80), C(120, 200, 120), C(250, 170, 60), C(170, 100, 255) }, Material = Enum.Material.Fabric },
	RolledCloth = { Shape = "Cylinder", Size = { Vector3.new(2.2, 1.0, 1.0), Vector3.new(1.8, 0.8, 0.8) }, Colors = { C(230, 90, 120), C(90, 150, 230), C(250, 250, 250), C(60, 60, 80), C(250, 170, 60) }, Material = Enum.Material.Fabric },
	Sock = { Shape = "Cylinder", Size = { Vector3.new(1.0, 0.45, 0.45) }, Colors = { C(250, 250, 250), C(40, 40, 40), C(250, 220, 60), C(255, 120, 200) }, Material = Enum.Material.Fabric },
	Pillow = { Shape = "Block", Size = { Vector3.new(3.0, 1.1, 2.0), Vector3.new(2.4, 1.0, 2.4) }, Colors = { C(250, 250, 255), C(200, 220, 255), C(255, 210, 220), C(220, 255, 220) }, Material = Enum.Material.Fabric },
	Box = { Shape = "Block", Size = { Vector3.new(2.2, 2.2, 2.2), Vector3.new(3.0, 1.6, 2.0), Vector3.new(1.6, 1.6, 1.6), Vector3.new(2.6, 1.2, 2.6) }, Colors = { C(190, 140, 90), C(170, 120, 75), C(210, 160, 110) }, Material = Enum.Material.SmoothPlastic },
	Bin = { Shape = "Block", Size = { Vector3.new(2.4, 2.0, 1.8) }, Colors = { C(80, 140, 220), C(230, 230, 240), C(120, 200, 120) }, Material = Enum.Material.SmoothPlastic },
	Ball = { Shape = "Ball", Size = { Vector3.new(1.4, 1.4, 1.4), Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.0, 2.0, 2.0) }, Colors = { C(255, 80, 80), C(80, 200, 255), C(255, 220, 60), C(120, 255, 120), C(255, 120, 220), C(255, 140, 40) }, Material = Enum.Material.SmoothPlastic },
	Block = { Shape = "Block", Size = { Vector3.new(1.0, 1.0, 1.0), Vector3.new(1.4, 0.7, 0.7) }, Colors = { C(255, 80, 80), C(80, 120, 255), C(255, 220, 60), C(120, 220, 120) }, Material = Enum.Material.SmoothPlastic },
	Plush = { Shape = "Ball", Size = { Vector3.new(1.6, 1.6, 1.6), Vector3.new(1.2, 1.2, 1.2) }, Colors = { C(170, 120, 80), C(255, 190, 210), C(200, 200, 210), C(255, 230, 120) }, Material = Enum.Material.Fabric },
	ToyCar = { Shape = "Block", Size = { Vector3.new(1.6, 0.6, 0.8) }, Colors = { C(230, 40, 40), C(40, 120, 230), C(250, 200, 30) }, Material = Enum.Material.Metal },
	Can = { Shape = "Cylinder", Size = { Vector3.new(0.9, 0.5, 0.5) }, Colors = { C(220, 40, 40), C(40, 80, 200), C(200, 200, 200), C(40, 160, 90) }, Material = Enum.Material.Metal },
	Bottle = { Shape = "Cylinder", Size = { Vector3.new(1.6, 0.55, 0.55) }, Colors = { C(120, 200, 255), C(200, 240, 255) }, Material = Enum.Material.Glass },
	Gadget = { Shape = "Block", Size = { Vector3.new(1.8, 0.5, 1.2), Vector3.new(1.2, 1.2, 0.6), Vector3.new(2.6, 0.4, 1.0) }, Colors = { C(40, 40, 50), C(70, 70, 80), C(200, 200, 205), C(30, 60, 90) }, Material = Enum.Material.SmoothPlastic },
	Cable = { Shape = "Cylinder", Size = { Vector3.new(2.6, 0.2, 0.2) }, Colors = { C(30, 30, 30), C(240, 240, 240) }, Material = Enum.Material.SmoothPlastic },
	Shoe = { Shape = "Block", Size = { Vector3.new(1.9, 0.8, 0.8), Vector3.new(1.6, 0.7, 0.7) }, Colors = { C(40, 40, 40), C(250, 250, 250), C(200, 50, 50), C(60, 90, 160), C(255, 140, 40) }, Material = Enum.Material.SmoothPlastic },
	PizzaBox = { Shape = "Block", Size = { Vector3.new(2.6, 0.3, 2.6) }, Colors = { C(220, 170, 110) }, Material = Enum.Material.SmoothPlastic },
	Cup = { Shape = "Cylinder", Size = { Vector3.new(0.9, 0.7, 0.7) }, Colors = { C(250, 250, 250), C(80, 160, 230), C(230, 80, 80) }, Material = Enum.Material.SmoothPlastic },
	Wrapper = { Shape = "Block", Size = { Vector3.new(0.9, 0.08, 1.3) }, Colors = { C(250, 200, 40), C(230, 60, 60), C(60, 200, 120) }, Material = Enum.Material.Foil },
}

-- Palettes: weighted prop lists per layer.
local Palettes = {
	Books = { Base = { "Box", "Book", "Book" }, Mid = { "Book", "Book", "Magazine", "OpenBook" }, Top = { "Book", "Paper", "OpenBook", "Magazine" } },
	Clothes = { Base = { "Pillow", "Shirt", "Bin" }, Mid = { "Shirt", "RolledCloth", "Shirt" }, Top = { "Sock", "Shirt", "RolledCloth", "Sock" } },
	Pillows = { Base = { "Pillow", "Pillow" }, Mid = { "Pillow", "Shirt", "Plush" }, Top = { "Plush", "Sock", "Book" } },
	Boxes = { Base = { "Box", "Box", "Bin" }, Mid = { "Box", "Box", "Paper" }, Top = { "Paper", "Cable", "Book", "Wrapper" } },
	Toys = { Base = { "Box", "Plush", "Ball" }, Mid = { "Ball", "Block", "Plush", "ToyCar" }, Top = { "Block", "ToyCar", "Ball", "Block" } },
	Paper = { Base = { "Box", "PizzaBox", "Magazine" }, Mid = { "Paper", "Magazine", "Book", "Paper" }, Top = { "Paper", "Paper", "Wrapper", "Cup" } },
	Electronics = { Base = { "Box", "Gadget", "Bin" }, Mid = { "Gadget", "Gadget", "Cable" }, Top = { "Cable", "Gadget", "Can", "Cup" } },
	Shoes = { Base = { "Box", "Shoe", "Shoe" }, Mid = { "Shoe", "Shoe", "Sock" }, Top = { "Sock", "Shoe", "Wrapper" } },
	Mixed = { Base = { "Box", "Pillow", "Shirt", "Bin", "PizzaBox" }, Mid = { "Shirt", "Book", "Ball", "Gadget", "Shoe", "Magazine" }, Top = { "Paper", "Sock", "Can", "Cup", "Wrapper", "Block", "Cable" } },
}

-- ===== helpers =====

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

local function wedge(props: { [string]: any }, parent: Instance): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function deco(props, parent)
	props.CanCollide = props.CanCollide == nil and false or props.CanCollide
	props.CanQuery = props.CanQuery == nil and false or props.CanQuery
	props.CanTouch = false
	return part(props, parent)
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

-- ===== structure & furniture =====

local function buildStructure(config, origin: CFrame, parent: Folder)
	local size = config.Size
	local halfX, halfZ = size.X / 2, size.Z / 2
	local wallT = 1
	local wall = config.WallColor
	local wallLower = Color3.new(math.min(1, wall.R * 0.82), math.min(1, wall.G * 0.82), math.min(1, wall.B * 0.82))

	part({ Name = "Floor", Size = Vector3.new(size.X + 2, 1, size.Z + 2), CFrame = origin * CFrame.new(0, -0.5, 0), Color = config.FloorColor, Material = Enum.Material.WoodPlanks }, parent)
	part({ Name = "Ceiling", Size = Vector3.new(size.X + 2, 1, size.Z + 2), CFrame = origin * CFrame.new(0, size.Y + 0.5, 0), Color = C(245, 245, 250), Material = Enum.Material.SmoothPlastic }, parent)

	local walls = {
		{ "WallBack", Vector3.new(size.X + 2, size.Y, wallT), CFrame.new(0, size.Y / 2, -halfZ - 0.5) },
		{ "WallFront", Vector3.new(size.X + 2, size.Y, wallT), CFrame.new(0, size.Y / 2, halfZ + 0.5) },
		{ "WallLeft", Vector3.new(wallT, size.Y, size.Z + 2), CFrame.new(-halfX - 0.5, size.Y / 2, 0) },
		{ "WallRight", Vector3.new(wallT, size.Y, size.Z + 2), CFrame.new(halfX + 0.5, size.Y / 2, 0) },
	}
	for _, w in ipairs(walls) do
		part({ Name = w[1], Size = w[2], CFrame = origin * w[3], Color = wall, Material = Enum.Material.SmoothPlastic }, parent)
	end
	-- Wainscot band + baseboards on every wall (decorative, non-collidable)
	local bands = {
		{ Vector3.new(size.X + 2, 5, 0.3), CFrame.new(0, 2.5, -halfZ + 0.15) },
		{ Vector3.new(size.X + 2, 5, 0.3), CFrame.new(0, 2.5, halfZ - 0.15) },
		{ Vector3.new(0.3, 5, size.Z + 2), CFrame.new(-halfX + 0.15, 2.5, 0) },
		{ Vector3.new(0.3, 5, size.Z + 2), CFrame.new(halfX - 0.15, 2.5, 0) },
	}
	for _, b in ipairs(bands) do
		deco({ Name = "Wainscot", Size = b[1], CFrame = origin * b[2], Color = wallLower, Material = Enum.Material.SmoothPlastic }, parent)
		deco({ Name = "Baseboard", Size = Vector3.new(b[1].X == 0.3 and 0.4 or b[1].X, 0.9, b[1].Z == 0.3 and 0.4 or b[1].Z), CFrame = origin * (b[2] - Vector3.new(0, 2.05, 0)), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic }, parent)
	end

	-- Ceiling lamps with fixtures
	for _, x in ipairs({ -halfX * 0.6, 0, halfX * 0.6 }) do
		for _, z in ipairs({ -halfZ * 0.55, halfZ * 0.55 }) do
			local fixture = deco({ Name = "LampFixture", Size = Vector3.new(7, 0.5, 7), CFrame = origin * CFrame.new(x, size.Y - 0.25, z), Color = C(90, 100, 130), Material = Enum.Material.Metal }, parent)
			local lamp = deco({ Name = "CeilingLight", Size = Vector3.new(6, 0.3, 6), CFrame = origin * CFrame.new(x, size.Y - 0.6, z), Color = C(255, 250, 230), Material = Enum.Material.Neon }, parent)
			local light = Instance.new("PointLight")
			light.Brightness = 0.7
			light.Range = 44
			light.Color = C(255, 245, 225)
			light.Shadows = false
			light.Parent = lamp
			fixture.Transparency = 0
		end
	end
end

local function buildFurniture(origin: CFrame, parent: Folder)
	local wood = C(140, 95, 60)
	local woodDark = C(110, 75, 45)
	local F = function(props) return part(props, parent) end
	local D = function(props) return deco(props, parent) end

	-- Bed (left-back)
	F({ Name = "BedFrame", Size = Vector3.new(14, 2.4, 22), CFrame = origin * CFrame.new(-30, 1.2, -18), Color = woodDark, Material = Enum.Material.Wood })
	F({ Name = "Mattress", Size = Vector3.new(13, 1.6, 21), CFrame = origin * CFrame.new(-30, 3.2, -18), Color = C(235, 235, 245), Material = Enum.Material.Fabric })
	D({ Name = "Blanket", Size = Vector3.new(13.4, 0.5, 13), CFrame = origin * CFrame.new(-30, 4.2, -13.5), Color = C(90, 130, 220), Material = Enum.Material.Fabric })
	D({ Name = "BlanketFold", Size = Vector3.new(13.4, 0.5, 2), CFrame = origin * CFrame.new(-30, 4.7, -7.5), Color = C(70, 105, 190), Material = Enum.Material.Fabric })
	D({ Name = "PillowL", Size = Vector3.new(5.5, 1.3, 3), CFrame = origin * CFrame.new(-33, 4.6, -26.5) * CFrame.Angles(0, math.rad(6), 0), Color = C(250, 250, 255), Material = Enum.Material.Fabric })
	D({ Name = "PillowR", Size = Vector3.new(5.5, 1.3, 3), CFrame = origin * CFrame.new(-27, 4.6, -26.5) * CFrame.Angles(0, math.rad(-8), 0), Color = C(250, 250, 255), Material = Enum.Material.Fabric })
	F({ Name = "Headboard", Size = Vector3.new(14.4, 7, 0.8), CFrame = origin * CFrame.new(-30, 3.5, -29.4), Color = wood, Material = Enum.Material.Wood })
	for _, dx in ipairs({ -6.5, 6.5 }) do
		for _, dz in ipairs({ -10.5, 10.5 }) do
			D({ Name = "BedLeg", Size = Vector3.new(0.8, 1.2, 0.8), CFrame = origin * CFrame.new(-30 + dx, 0.6, -18 + dz), Color = woodDark, Material = Enum.Material.Wood })
		end
	end

	-- Nightstand + lamp
	F({ Name = "Nightstand", Size = Vector3.new(4, 3.2, 4), CFrame = origin * CFrame.new(-41, 1.6, -30), Color = wood, Material = Enum.Material.Wood })
	D({ Name = "NightstandDrawer", Size = Vector3.new(3.2, 1, 0.2), CFrame = origin * CFrame.new(-41, 2.2, -27.9), Color = woodDark, Material = Enum.Material.Wood })
	D({ Name = "LampBase", Size = Vector3.new(1.2, 0.4, 1.2), CFrame = origin * CFrame.new(-41, 3.4, -30), Color = C(60, 60, 70), Material = Enum.Material.Metal })
	D({ Name = "LampPole", Size = Vector3.new(0.3, 2.4, 0.3), CFrame = origin * CFrame.new(-41, 4.8, -30), Color = C(60, 60, 70), Material = Enum.Material.Metal })
	local shade = D({ Name = "LampShade", Size = Vector3.new(2.4, 1.8, 2.4), CFrame = origin * CFrame.new(-41, 6.6, -30), Color = C(255, 235, 170), Material = Enum.Material.Neon })
	local lampLight = Instance.new("PointLight")
	lampLight.Brightness = 0.8
	lampLight.Range = 14
	lampLight.Color = C(255, 220, 150)
	lampLight.Parent = shade

	-- Desk (right-back) with drawers, monitor, keyboard, chair
	F({ Name = "DeskTop", Size = Vector3.new(16, 0.8, 7), CFrame = origin * CFrame.new(30, 3, -30), Color = C(160, 118, 76), Material = Enum.Material.Wood })
	F({ Name = "DeskDrawers", Size = Vector3.new(4.5, 2.6, 6), CFrame = origin * CFrame.new(35.5, 1.3, -30), Color = wood, Material = Enum.Material.Wood })
	for i = 0, 1 do
		D({ Name = "DrawerFront", Size = Vector3.new(3.8, 0.9, 0.2), CFrame = origin * CFrame.new(35.5, 0.8 + i * 1.1, -26.9), Color = woodDark, Material = Enum.Material.Wood })
		D({ Name = "DrawerKnob", Size = Vector3.new(0.4, 0.4, 0.3), CFrame = origin * CFrame.new(35.5, 0.8 + i * 1.1, -26.7), Color = C(220, 190, 90), Material = Enum.Material.Metal })
	end
	D({ Name = "DeskLeg", Size = Vector3.new(0.8, 2.6, 6), CFrame = origin * CFrame.new(22.6, 1.3, -30), Color = wood, Material = Enum.Material.Wood })
	D({ Name = "MonitorStand", Size = Vector3.new(1.4, 0.9, 1.4), CFrame = origin * CFrame.new(30, 3.85, -32), Color = C(40, 40, 50), Material = Enum.Material.SmoothPlastic })
	D({ Name = "Monitor", Size = Vector3.new(6.5, 3.8, 0.5), CFrame = origin * CFrame.new(30, 6.2, -32.2), Color = C(30, 30, 40), Material = Enum.Material.SmoothPlastic })
	local screen = D({ Name = "Screen", Size = Vector3.new(6, 3.3, 0.1), CFrame = origin * CFrame.new(30, 6.2, -31.9), Color = C(90, 170, 255), Material = Enum.Material.Neon })
	screen.Transparency = 0.1
	D({ Name = "Keyboard", Size = Vector3.new(4.5, 0.25, 1.6), CFrame = origin * CFrame.new(30, 3.55, -28.5), Color = C(60, 60, 70), Material = Enum.Material.SmoothPlastic })
	F({ Name = "ChairSeat", Size = Vector3.new(3.5, 0.6, 3.5), CFrame = origin * CFrame.new(30, 2.1, -22), Color = C(60, 60, 90), Material = Enum.Material.Fabric })
	D({ Name = "ChairBack", Size = Vector3.new(3.5, 3.6, 0.6), CFrame = origin * CFrame.new(30, 4.2, -20.3), Color = C(60, 60, 90), Material = Enum.Material.Fabric })
	D({ Name = "ChairPole", Size = Vector3.new(0.5, 1.8, 0.5), CFrame = origin * CFrame.new(30, 0.9, -22), Color = C(40, 40, 50), Material = Enum.Material.Metal })
	D({ Name = "ChairBase", Size = Vector3.new(3, 0.3, 3), CFrame = origin * CFrame.new(30, 0.15, -22), Color = C(40, 40, 50), Material = Enum.Material.Metal })

	-- Bookshelf (right wall) with static book rows on upper shelves
	F({ Name = "BookshelfBack", Size = Vector3.new(0.5, 13, 16), CFrame = origin * CFrame.new(44.2, 6.5, -6), Color = wood, Material = Enum.Material.Wood })
	F({ Name = "BookshelfSideA", Size = Vector3.new(3.2, 13, 0.5), CFrame = origin * CFrame.new(42.9, 6.5, -14), Color = wood, Material = Enum.Material.Wood })
	F({ Name = "BookshelfSideB", Size = Vector3.new(3.2, 13, 0.5), CFrame = origin * CFrame.new(42.9, 6.5, 2), Color = wood, Material = Enum.Material.Wood })
	local rng = Random.new(42)
	for i = 0, 3 do
		local y = 3.5 + i * 3
		F({ Name = "Shelf", Size = Vector3.new(3.2, 0.4, 16), CFrame = origin * CFrame.new(42.9, y, -6), Color = woodDark, Material = Enum.Material.Wood })
		if i >= 1 then
			local z = -13.2
			while z < 1.2 do
				local w = rng:NextNumber(0.5, 1.0)
				local h = rng:NextNumber(1.6, 2.4)
				D({ Name = "ShelfBook", Size = Vector3.new(2.0, h, w), CFrame = origin * CFrame.new(43.0, y + 0.2 + h / 2, z + w / 2), Color = pick(rng, Props.Book.Colors), Material = Enum.Material.SmoothPlastic })
				z += w + rng:NextNumber(0.05, 0.4)
			end
		end
	end

	-- Closet (left wall) with open doors and a rail of hanging clothes
	F({ Name = "ClosetBack", Size = Vector3.new(0.5, 14, 22), CFrame = origin * CFrame.new(-44.2, 7, 10), Color = C(235, 235, 235), Material = Enum.Material.SmoothPlastic })
	F({ Name = "ClosetTop", Size = Vector3.new(4.5, 0.5, 22), CFrame = origin * CFrame.new(-42.2, 14, 10), Color = C(235, 235, 235), Material = Enum.Material.SmoothPlastic })
	F({ Name = "ClosetSideA", Size = Vector3.new(4.5, 14, 0.5), CFrame = origin * CFrame.new(-42.2, 7, -1), Color = C(235, 235, 235), Material = Enum.Material.SmoothPlastic })
	F({ Name = "ClosetSideB", Size = Vector3.new(4.5, 14, 0.5), CFrame = origin * CFrame.new(-42.2, 7, 21), Color = C(235, 235, 235), Material = Enum.Material.SmoothPlastic })
	D({ Name = "ClosetDoorA", Size = Vector3.new(0.4, 13, 6), CFrame = origin * CFrame.new(-40, 6.5, -0.5) * CFrame.Angles(0, math.rad(70), 0), Color = C(245, 245, 245), Material = Enum.Material.SmoothPlastic })
	D({ Name = "ClosetDoorB", Size = Vector3.new(0.4, 13, 6), CFrame = origin * CFrame.new(-40, 6.5, 20.5) * CFrame.Angles(0, math.rad(-70), 0), Color = C(245, 245, 245), Material = Enum.Material.SmoothPlastic })
	D({ Name = "ClosetRail", Size = Vector3.new(0.3, 0.3, 20), CFrame = origin * CFrame.new(-42.2, 11.5, 10), Color = C(150, 150, 160), Material = Enum.Material.Metal })
	for i = 0, 8 do
		local z = 1.5 + i * 2.1
		D({ Name = "Hanger", Size = Vector3.new(0.2, 1.2, 1.6), CFrame = origin * CFrame.new(-42.2, 10.9, z), Color = C(120, 120, 130), Material = Enum.Material.Metal })
		D({ Name = "HangingShirt", Size = Vector3.new(0.6, 4.5, 1.8), CFrame = origin * CFrame.new(-42.2, 8.2, z), Color = pick(rng, Props.Shirt.Colors), Material = Enum.Material.Fabric })
	end

	-- Dresser (back wall center) with drawer fronts and knobs
	F({ Name = "Dresser", Size = Vector3.new(14, 6, 5), CFrame = origin * CFrame.new(-2, 3, -32), Color = wood, Material = Enum.Material.Wood })
	for row = 0, 2 do
		for col = 0, 1 do
			D({ Name = "DresserDrawer", Size = Vector3.new(6.2, 1.5, 0.25), CFrame = origin * CFrame.new(-2 + (col == 0 and -3.4 or 3.4), 1.2 + row * 1.9, -29.4), Color = woodDark, Material = Enum.Material.Wood })
			D({ Name = "DresserKnob", Size = Vector3.new(0.5, 0.5, 0.3), CFrame = origin * CFrame.new(-2 + (col == 0 and -3.4 or 3.4), 1.2 + row * 1.9, -29.2), Color = C(220, 190, 90), Material = Enum.Material.Metal })
		end
	end
	D({ Name = "DresserTopDrawerOpen", Size = Vector3.new(6.2, 1.5, 2.5), CFrame = origin * CFrame.new(1.4, 5.0, -28.4), Color = woodDark, Material = Enum.Material.Wood })

	-- Rug (two-tone)
	D({ Name = "Rug", Size = Vector3.new(28, 0.2, 24), CFrame = origin * CFrame.new(0, 0.1, 2), Color = C(200, 80, 90), Material = Enum.Material.Fabric })
	D({ Name = "RugInner", Size = Vector3.new(22, 0.22, 18), CFrame = origin * CFrame.new(0, 0.12, 2), Color = C(225, 110, 120), Material = Enum.Material.Fabric })

	-- Window (back wall) + sill + curtains + daylight
	local glass = D({ Name = "Window", Size = Vector3.new(12, 10, 0.4), CFrame = origin * CFrame.new(14, 12, -34.6), Color = C(200, 235, 255), Material = Enum.Material.Glass })
	glass.Transparency = 0.35
	D({ Name = "WindowFrameTop", Size = Vector3.new(13.2, 0.6, 0.6), CFrame = origin * CFrame.new(14, 17.3, -34.4), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "WindowFrameBottom", Size = Vector3.new(13.2, 0.6, 1.4), CFrame = origin * CFrame.new(14, 6.7, -34.0), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "WindowFrameL", Size = Vector3.new(0.6, 10.6, 0.6), CFrame = origin * CFrame.new(7.7, 12, -34.4), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "WindowFrameR", Size = Vector3.new(0.6, 10.6, 0.6), CFrame = origin * CFrame.new(20.3, 12, -34.4), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "WindowCross", Size = Vector3.new(0.4, 10, 0.5), CFrame = origin * CFrame.new(14, 12, -34.3), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "CurtainL", Size = Vector3.new(2.6, 12, 0.6), CFrame = origin * CFrame.new(6.2, 11.5, -34.0), Color = C(255, 205, 90), Material = Enum.Material.Fabric })
	D({ Name = "CurtainR", Size = Vector3.new(2.6, 12, 0.6), CFrame = origin * CFrame.new(21.8, 11.5, -34.0), Color = C(255, 205, 90), Material = Enum.Material.Fabric })
	local sun = Instance.new("SurfaceLight")
	sun.Face = Enum.NormalId.Front
	sun.Brightness = 1.2
	sun.Range = 30
	sun.Angle = 110
	sun.Color = C(255, 245, 220)
	sun.Parent = glass

	-- Door (front wall) + frame + knob
	F({ Name = "Door", Size = Vector3.new(7, 12, 0.6), CFrame = origin * CFrame.new(0, 6, 34.6), Color = C(150, 100, 60), Material = Enum.Material.Wood })
	D({ Name = "DoorFrameL", Size = Vector3.new(0.6, 12.6, 0.9), CFrame = origin * CFrame.new(-3.8, 6.3, 34.5), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "DoorFrameR", Size = Vector3.new(0.6, 12.6, 0.9), CFrame = origin * CFrame.new(3.8, 6.3, 34.5), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "DoorFrameTop", Size = Vector3.new(8.2, 0.6, 0.9), CFrame = origin * CFrame.new(0, 12.6, 34.5), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic })
	D({ Name = "DoorKnob", Size = Vector3.new(0.6, 0.6, 0.6), CFrame = origin * CFrame.new(2.6, 5.6, 34.1), Color = C(220, 190, 90), Material = Enum.Material.Metal, Shape = Enum.PartType.Ball })
	D({ Name = "DoorPanelA", Size = Vector3.new(5, 4, 0.2), CFrame = origin * CFrame.new(0, 8.5, 34.2), Color = C(135, 90, 55), Material = Enum.Material.Wood })
	D({ Name = "DoorPanelB", Size = Vector3.new(5, 4, 0.2), CFrame = origin * CFrame.new(0, 3.2, 34.2), Color = C(135, 90, 55), Material = Enum.Material.Wood })

	-- Wall décor: posters, clock, shelf
	D({ Name = "PosterA", Size = Vector3.new(8, 6, 0.2), CFrame = origin * CFrame.new(-14, 12, -34.6), Color = C(255, 120, 60), Material = Enum.Material.SmoothPlastic })
	D({ Name = "PosterAInner", Size = Vector3.new(6.5, 4.5, 0.1), CFrame = origin * CFrame.new(-14, 12, -34.4), Color = C(255, 200, 40), Material = Enum.Material.SmoothPlastic })
	D({ Name = "PosterB", Size = Vector3.new(0.2, 5, 7), CFrame = origin * CFrame.new(-44.6, 14, 28), Color = C(80, 200, 255), Material = Enum.Material.SmoothPlastic })
	D({ Name = "PosterC", Size = Vector3.new(0.2, 6, 5), CFrame = origin * CFrame.new(44.6, 14, 22), Color = C(170, 100, 255), Material = Enum.Material.SmoothPlastic })
	D({ Name = "ClockFace", Size = Vector3.new(3, 3, 0.3), CFrame = origin * CFrame.new(28, 18, -34.6) * CFrame.Angles(0, 0, math.rad(90)), Color = C(250, 250, 250), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder })
	D({ Name = "ClockHand", Size = Vector3.new(0.2, 1.2, 0.1), CFrame = origin * CFrame.new(28, 18.5, -34.4), Color = C(30, 30, 30), Material = Enum.Material.SmoothPlastic })
	D({ Name = "WallShelf", Size = Vector3.new(10, 0.4, 2), CFrame = origin * CFrame.new(-18, 15, 33.8), Color = wood, Material = Enum.Material.Wood })
	for i = 0, 3 do
		D({ Name = "ShelfTrophy", Size = Vector3.new(1, 1.6, 1), CFrame = origin * CFrame.new(-21.5 + i * 2.4, 16, 33.8), Color = i % 2 == 0 and C(255, 200, 40) or C(200, 200, 210), Material = Enum.Material.Metal })
	end

	-- Floor props
	D({ Name = "Skateboard", Size = Vector3.new(6, 0.5, 2), CFrame = origin * CFrame.new(38, 0.9, 30), Color = C(60, 200, 120), Material = Enum.Material.SmoothPlastic })
	for _, dx in ipairs({ -2, 2 }) do
		D({ Name = "Wheel", Size = Vector3.new(0.5, 0.7, 0.7), CFrame = origin * CFrame.new(38 + dx, 0.4, 30) * CFrame.Angles(0, 0, math.rad(90)), Color = C(30, 30, 30), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder })
	end
	D({ Name = "Basketball", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = origin * CFrame.new(-12, 1.2, 30), Color = C(230, 120, 50), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Ball })
	D({ Name = "GuitarBody", Size = Vector3.new(0.8, 3.4, 2.8), CFrame = origin * CFrame.new(44, 1.7, 14), Color = C(200, 60, 60), Material = Enum.Material.SmoothPlastic })
	D({ Name = "GuitarNeck", Size = Vector3.new(0.5, 4.5, 0.6), CFrame = origin * CFrame.new(44, 5.5, 14), Color = C(110, 75, 45), Material = Enum.Material.Wood })
	D({ Name = "PlantPot", Size = Vector3.new(2.5, 2.2, 2.5), CFrame = origin * CFrame.new(-42, 1.1, 30), Color = C(200, 110, 70), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder })
	D({ Name = "PlantLeaves", Size = Vector3.new(3.2, 3.2, 3.2), CFrame = origin * CFrame.new(-42, 3.8, 30), Color = C(60, 160, 70), Material = Enum.Material.Grass, Shape = Enum.PartType.Ball })
	D({ Name = "Beanbag", Size = Vector3.new(4, 2.2, 4), CFrame = origin * CFrame.new(40, 1.1, 4), Color = C(120, 90, 220), Material = Enum.Material.Fabric, Shape = Enum.PartType.Ball })
end

-- ===== clutter piles =====

local function makeChunk(rng: Random, propName: string, cframe: CFrame, scale: number, parent: Instance): BasePart
	local prop = Props[propName]
	local baseSize = pick(rng, prop.Size) * scale
	local color = pick(rng, prop.Colors)
	local p: BasePart
	if prop.Shape == "Wedge" then
		p = wedge({ Size = baseSize, CFrame = cframe, Color = color, Material = prop.Material }, parent)
	else
		local block = part({ Size = baseSize, CFrame = cframe, Color = color, Material = prop.Material }, parent)
		if prop.Shape == "Ball" then
			block.Shape = Enum.PartType.Ball
			local d = math.max(baseSize.X, baseSize.Y, baseSize.Z)
			block.Size = Vector3.new(d, d, d)
		elseif prop.Shape == "Cylinder" then
			block.Shape = Enum.PartType.Cylinder
		end
		p = block
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Anchored = true
	p:SetAttribute("Prop", propName)
	return p
end

local function buildChunks(cluster, rng: Random, origin: CFrame, chunksFolder: Folder, density: number)
	local palette = Palettes[cluster.Palette or "Mixed"] or Palettes.Mixed
	local center = cluster.Center
	local size = cluster.Size
	local count = math.max(8, math.floor((cluster.ChunkCount or 20) * density + 0.5))
	local flat = cluster.Flat == true

	local chunks = {}
	local baseCount = math.floor(count * 0.35)
	local midCount = math.floor(count * 0.4)

	for i = 1, count do
		local layer, list, scale
		if i <= baseCount then
			layer, list, scale = 0, palette.Base, rng:NextNumber(1.0, 1.45)
		elseif i <= baseCount + midCount then
			layer, list, scale = 1, palette.Mid, rng:NextNumber(0.85, 1.25)
		else
			layer, list, scale = 2, palette.Top, rng:NextNumber(0.7, 1.1)
		end
		local propName = pick(rng, list)
		local prop = Props[propName]

		-- Radial placement: base spreads to the edge (and slightly beyond = overflow), top stays central.
		local maxRadial = ({ 1.08, 0.85, 0.6 })[layer + 1]
		local radial = math.sqrt(rng:NextNumber()) * maxRadial
		local ang = rng:NextNumber(0, math.pi * 2)
		local px = math.cos(ang) * radial * size.X * 0.5
		local pz = math.sin(ang) * radial * size.Z * 0.5
		local dome = math.max(0, 1 - (radial / 1.08) ^ 2)
		local layerBase = ({ 0, size.Y * 0.28, size.Y * 0.55 })[layer + 1]
		local py = layerBase + rng:NextNumber(0, 0.35) * size.Y * dome
		if flat then
			py = math.min(py, size.Y * 0.5)
		end
		local approxHeight = pick(rng, prop.Size).Y * scale
		local localPos = center + Vector3.new(px, py + approxHeight / 2 + 0.05, pz)

		local rot
		if prop.Shape == "Cylinder" then
			rot = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-10, 10)))
		else
			local tilt = layer == 0 and 6 or (layer == 1 and 14 or 25)
			rot = CFrame.Angles(math.rad(rng:NextNumber(-tilt, tilt)), rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-tilt, tilt)))
		end
		local chunk = makeChunk(rng, propName, origin * CFrame.new(localPos) * rot, scale, chunksFolder)
		table.insert(chunks, { Part = chunk, Score = py * 2 + radial * 3 + layer * 0.5 })
	end

	-- Removal order: highest / outermost first so the pile visibly shrinks inward and down.
	table.sort(chunks, function(a, b)
		return a.Score > b.Score
	end)
	for order, entry in ipairs(chunks) do
		entry.Part.Name = string.format("Chunk%03d", order)
		entry.Part:SetAttribute("RemovalOrder", order)
	end
end

local function buildRegions(config, origin: CFrame, parent: Folder)
	for _, r in ipairs(config.Regions) do
		local p = part({ Name = "Region_" .. r.Id, Size = r.Size, CFrame = origin * CFrame.new(r.Center), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, parent)
		p:SetAttribute("RegionId", r.Id)
		p:SetAttribute("RegionName", r.Name)
		CollectionService:AddTag(p, "SearchRegion")
	end
end

local function buildClusters(config, origin: CFrame, parent: Folder)
	local density = config.ChunkDensity or 1
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
		buildChunks(c, rng, origin, chunks, density)

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
		local p = part({ Name = s.Id, Size = Vector3.new(1, 1, 1), CFrame = origin * CFrame.new(basePos + s.Offset) * CFrame.Angles(0, math.rad((hashString(s.Id) % 360)), 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, parent)
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
	local green = C(70, 210, 110)
	local dark = C(24, 30, 48)
	local yellow = C(255, 200, 40)
	local P = function(props) return part(props, model) end
	local D = function(props) return deco(props, model) end

	P({ Name = "Body", Size = Vector3.new(7, 8, 5.5), CFrame = origin * CFrame.new(pos + Vector3.new(0, 4, 0)), Color = green, Material = Enum.Material.SmoothPlastic })
	D({ Name = "BodyPanel", Size = Vector3.new(6, 3, 0.2), CFrame = origin * CFrame.new(pos + Vector3.new(0, 7.2, -2.85)), Color = dark, Material = Enum.Material.SmoothPlastic })
	D({ Name = "Mouth", Size = Vector3.new(5, 3.2, 1.2), CFrame = origin * CFrame.new(pos + Vector3.new(0, 4.4, -2.9)), Color = dark, Material = Enum.Material.SmoothPlastic })
	D({ Name = "MouthLipTop", Size = Vector3.new(5.6, 0.5, 2.4), CFrame = origin * CFrame.new(pos + Vector3.new(0, 6.2, -3.6)), Color = yellow, Material = Enum.Material.SmoothPlastic })
	D({ Name = "MouthLipBottom", Size = Vector3.new(5.6, 0.6, 3.4), CFrame = origin * CFrame.new(pos + Vector3.new(0, 2.7, -4.1)), Color = yellow, Material = Enum.Material.SmoothPlastic })
	for i = 0, 3 do
		D({ Name = "Stripe", Size = Vector3.new(0.9, 1.1, 0.2), CFrame = origin * CFrame.new(pos + Vector3.new(-2.6 + i * 1.75, 0.8, -2.85)) * CFrame.Angles(0, 0, math.rad(35)), Color = i % 2 == 0 and yellow or dark, Material = Enum.Material.SmoothPlastic })
	end
	D({ Name = "Pipe", Size = Vector3.new(3, 9, 3), CFrame = origin * CFrame.new(pos + Vector3.new(0, 12.5, 0)), Color = C(90, 100, 130), Material = Enum.Material.Metal })
	D({ Name = "PipeRing", Size = Vector3.new(3.6, 0.6, 3.6), CFrame = origin * CFrame.new(pos + Vector3.new(0, 9, 0)), Color = C(70, 80, 110), Material = Enum.Material.Metal })
	D({ Name = "PipeRing2", Size = Vector3.new(3.6, 0.6, 3.6), CFrame = origin * CFrame.new(pos + Vector3.new(0, 14, 0)), Color = C(70, 80, 110), Material = Enum.Material.Metal })
	D({ Name = "SidePipeL", Size = Vector3.new(1.2, 4, 1.2), CFrame = origin * CFrame.new(pos + Vector3.new(-3.2, 9, 1)), Color = C(90, 100, 130), Material = Enum.Material.Metal })
	D({ Name = "SidePipeR", Size = Vector3.new(1.2, 4, 1.2), CFrame = origin * CFrame.new(pos + Vector3.new(3.2, 9, 1)), Color = C(90, 100, 130), Material = Enum.Material.Metal })
	local beacon = D({ Name = "Beacon", Size = Vector3.new(1.2, 1.2, 1.2), CFrame = origin * CFrame.new(pos + Vector3.new(0, 8.6, -2.2)), Color = yellow, Material = Enum.Material.Neon, Shape = Enum.PartType.Ball })
	local light = Instance.new("PointLight")
	light.Color = yellow
	light.Brightness = 1.2
	light.Range = 14
	light.Parent = beacon
	D({ Name = "Sign", Size = Vector3.new(8, 2.4, 0.4), CFrame = origin * CFrame.new(pos + Vector3.new(0, 18.2, -1.6)), Color = dark, Material = Enum.Material.SmoothPlastic })
	local signBoard = model:FindFirstChild("Sign") :: Part
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Parent = signBoard
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = yellow
	label.Text = "DUMP MESS HERE"
	label.Parent = sg
	D({ Name = "SignPost", Size = Vector3.new(0.5, 2, 0.5), CFrame = origin * CFrame.new(pos + Vector3.new(0, 16, -1.6)), Color = C(70, 80, 110), Material = Enum.Material.Metal })
	D({ Name = "FloorPad", Size = Vector3.new(12, 0.15, 10), CFrame = origin * CFrame.new(pos + Vector3.new(0, 0.08, -5)), Color = C(60, 180, 100), Material = Enum.Material.SmoothPlastic })

	local zone = part({ Name = "SellZone", Size = Vector3.new(14, 8, 14), CFrame = origin * CFrame.new(pos + Vector3.new(0, 4, -4)), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, model)
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
	buildFurniture(origin, structure)

	local spawn = part({
		Name = "RoomSpawn",
		Size = Vector3.new(8, 0.3, 6),
		CFrame = origin * CFrame.new(config.SpawnPosition.X, 0.15, config.SpawnPosition.Z),
		Color = C(80, 90, 130),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Transparency = 0.5,
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
