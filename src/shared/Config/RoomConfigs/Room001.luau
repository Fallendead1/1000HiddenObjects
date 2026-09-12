--[[
	ROOM #001 - THE MESSY BEDROOM
	Data-driven room definition. Positions are room-local studs; the room origin is the
	center of the floor at y = 0. X spans [-45, 45], Z spans [-35, 35]. The door/entrance
	is on the +Z wall.

	A pre-built room model placed at ServerStorage.Rooms.Room001 (tagged per the docs)
	overrides the placeholder geometry described in Layout, but the gameplay data below
	(clusters, sockets, regions, hints) is always the source of truth.
]]

local Room = {
	Id = 1,
	DisplayNumber = "001",
	Name = "The Messy Bedroom",

	TargetId = "GoldenKey",
	TargetName = "Golden Key",

	-- Simulation-tuned: solo median ~75-90 real minutes with an efficient player.
	BaseMessUnits = 100000,

	TargetDepthMin = 0.65,
	TargetDepthMax = 0.90,

	MinimumTargetSockets = 30,

	-- Side / area / region / hot-cold / outline. Earlier than the design draft so a solo
	-- player has a useful clue by ~40 minutes instead of ~50.
	HintMilestones = { 0.20, 0.40, 0.60, 0.80, 0.95 },

	LayoutVariants = { 1 },

	-- Multiplies every cluster's ChunkCount for the placeholder builder (visual density only).
	-- 30 clusters x ~21 avg x 1.6 = ~1,000 anchored, non-collidable props.
	ChunkDensity = 1.6,

	Size = Vector3.new(90, 26, 70),

	SpawnPosition = Vector3.new(0, 3, 27),
	TrashChutePosition = Vector3.new(9, 0, 30),
	DoorPosition = Vector3.new(0, 0, 35),

	AmbientColor = Color3.fromRGB(150, 160, 190),
	FloorColor = Color3.fromRGB(180, 140, 100),
	WallColor = Color3.fromRGB(120, 170, 220),
}

-- Regions used by hints, validation and highlight volumes.
Room.Regions = {
	{ Id = "BedPile", Name = "BED", Center = Vector3.new(-30, 5, -18), Size = Vector3.new(22, 10, 26) },
	{ Id = "UnderBed", Name = "UNDER THE BED", Center = Vector3.new(-30, 1, -18), Size = Vector3.new(16, 3, 22) },
	{ Id = "Desk", Name = "DESK", Center = Vector3.new(30, 5, -26), Size = Vector3.new(22, 10, 16) },
	{ Id = "Closet", Name = "CLOSET", Center = Vector3.new(-38, 6, 10), Size = Vector3.new(12, 14, 26) },
	{ Id = "Bookshelf", Name = "BOOKSHELF", Center = Vector3.new(38, 6, -6), Size = Vector3.new(12, 12, 18) },
	{ Id = "LaundryCorner", Name = "LAUNDRY CORNER", Center = Vector3.new(-32, 4, 24), Size = Vector3.new(20, 8, 18) },
	{ Id = "ToyCorner", Name = "TOY CORNER", Center = Vector3.new(32, 4, 22), Size = Vector3.new(20, 8, 20) },
	{ Id = "Dresser", Name = "DRESSER", Center = Vector3.new(-2, 5, -28), Size = Vector3.new(26, 10, 12) },
	{ Id = "WindowArea", Name = "WINDOW", Center = Vector3.new(14, 5, -24), Size = Vector3.new(14, 10, 14) },
	{ Id = "CenterFloor", Name = "CENTER FLOOR", Center = Vector3.new(0, 3, 0), Size = Vector3.new(20, 6, 22) },
	{ Id = "LeftFloor", Name = "LEFT FLOOR", Center = Vector3.new(-19, 3, 2), Size = Vector3.new(16, 6, 26) },
	{ Id = "RightFloor", Name = "RIGHT FLOOR", Center = Vector3.new(20, 3, 4), Size = Vector3.new(16, 6, 26) },
}

-- Broad area groups used for the 50% clue ("Search around the BED / CLOSET side").
Room.HintAreas = {
	{ Label = "BED / UNDER BED / CLOSET", Regions = { "BedPile", "UnderBed", "Closet" } },
	{ Label = "DESK / BOOKSHELF / WINDOW", Regions = { "Desk", "Bookshelf", "WindowArea" } },
	{ Label = "LAUNDRY / LEFT FLOOR / DRESSER", Regions = { "LaundryCorner", "LeftFloor", "Dresser" } },
	{ Label = "TOYS / RIGHT FLOOR / CENTER", Regions = { "ToyCorner", "RightFloor", "CenterFloor" } },
}

-- Placeholder furniture. Each entry becomes an anchored Part (or a small set of parts).
Room.Furniture = {
	{ Name = "BedFrame", Position = Vector3.new(-30, 1.5, -18), Size = Vector3.new(14, 3, 22), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.Wood },
	{ Name = "Mattress", Position = Vector3.new(-30, 3.5, -18), Size = Vector3.new(13, 1.5, 21), Color = Color3.fromRGB(230, 230, 240), Material = Enum.Material.Fabric },
	{ Name = "Blanket", Position = Vector3.new(-30, 4.4, -14), Size = Vector3.new(13.2, 0.4, 12), Color = Color3.fromRGB(90, 130, 220), Material = Enum.Material.Fabric },
	{ Name = "Pillow", Position = Vector3.new(-30, 4.8, -26), Size = Vector3.new(6, 1.2, 3), Color = Color3.fromRGB(250, 250, 255), Material = Enum.Material.Fabric },
	{ Name = "Nightstand", Position = Vector3.new(-40, 1.5, -30), Size = Vector3.new(4, 3, 4), Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood },
	{ Name = "Lamp", Position = Vector3.new(-40, 4.2, -30), Size = Vector3.new(1.5, 2.4, 1.5), Color = Color3.fromRGB(255, 240, 180), Material = Enum.Material.Neon },
	{ Name = "Desk", Position = Vector3.new(30, 3, -30), Size = Vector3.new(16, 0.8, 7), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.Wood },
	{ Name = "DeskLegL", Position = Vector3.new(23, 1.3, -30), Size = Vector3.new(1, 2.6, 6), Color = Color3.fromRGB(130, 95, 60), Material = Enum.Material.Wood },
	{ Name = "DeskLegR", Position = Vector3.new(37, 1.3, -30), Size = Vector3.new(1, 2.6, 6), Color = Color3.fromRGB(130, 95, 60), Material = Enum.Material.Wood },
	{ Name = "Monitor", Position = Vector3.new(30, 5.2, -32), Size = Vector3.new(6, 3.5, 0.5), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.SmoothPlastic },
	{ Name = "Chair", Position = Vector3.new(30, 1.6, -22), Size = Vector3.new(3.5, 3.2, 3.5), Color = Color3.fromRGB(60, 60, 80), Material = Enum.Material.Plastic },
	{ Name = "Bookshelf", Position = Vector3.new(43, 6, -6), Size = Vector3.new(3, 12, 16), Color = Color3.fromRGB(140, 100, 60), Material = Enum.Material.Wood },
	{ Name = "Closet", Position = Vector3.new(-43, 7, 10), Size = Vector3.new(4, 14, 22), Color = Color3.fromRGB(235, 235, 235), Material = Enum.Material.SmoothPlastic },
	{ Name = "Dresser", Position = Vector3.new(-2, 3, -32), Size = Vector3.new(14, 6, 5), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood },
	{ Name = "Rug", Position = Vector3.new(0, 0.1, 2), Size = Vector3.new(26, 0.2, 22), Color = Color3.fromRGB(200, 80, 90), Material = Enum.Material.Fabric },
	{ Name = "Window", Position = Vector3.new(14, 12, -34.6), Size = Vector3.new(12, 10, 0.4), Color = Color3.fromRGB(180, 230, 255), Material = Enum.Material.Glass },
	{ Name = "WindowFrame", Position = Vector3.new(14, 12, -34.4), Size = Vector3.new(12.8, 10.8, 0.3), Color = Color3.fromRGB(250, 250, 250), Material = Enum.Material.SmoothPlastic, Hollow = true },
	{ Name = "Door", Position = Vector3.new(0, 6, 34.6), Size = Vector3.new(7, 12, 0.6), Color = Color3.fromRGB(150, 100, 60), Material = Enum.Material.Wood },
	{ Name = "Poster", Position = Vector3.new(-14, 12, -34.6), Size = Vector3.new(8, 6, 0.2), Color = Color3.fromRGB(255, 120, 60), Material = Enum.Material.SmoothPlastic },
	{ Name = "Skateboard", Position = Vector3.new(38, 0.6, 30), Size = Vector3.new(6, 0.6, 2), Color = Color3.fromRGB(60, 200, 120), Material = Enum.Material.SmoothPlastic },
	{ Name = "Basketball", Position = Vector3.new(-12, 1.2, 30), Size = Vector3.new(2.4, 2.4, 2.4), Color = Color3.fromRGB(230, 120, 50), Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Ball },
	{ Name = "Guitar", Position = Vector3.new(44, 3.5, 14), Size = Vector3.new(0.8, 7, 2.6), Color = Color3.fromRGB(200, 60, 60), Material = Enum.Material.SmoothPlastic },
	{ Name = "Plant", Position = Vector3.new(-44, 2.5, 30), Size = Vector3.new(2.5, 5, 2.5), Color = Color3.fromRGB(60, 160, 70), Material = Enum.Material.Grass },
}

--[[
	ClutterClusters. Weight controls how much of the room's logical mess lands in this
	pile. ChunkCount is the number of visible placeholder props. Palette drives the
	placeholder look. Base is the y of the pile's bottom (e.g. on top of the bed).
]]
Room.Clusters = {
	-- Bed
	{ Id = "Bed_01", RegionId = "BedPile", Center = Vector3.new(-30, 5.2, -14), Size = Vector3.new(12, 6, 12), Weight = 3.6, ChunkCount = 24, Palette = "Mixed", TargetEligible = true },
	{ Id = "Bed_02", RegionId = "BedPile", Center = Vector3.new(-30, 5.2, -25), Size = Vector3.new(12, 5, 8), Weight = 2.6, ChunkCount = 18, Palette = "Pillows", TargetEligible = true },
	{ Id = "Bed_03", RegionId = "BedPile", Center = Vector3.new(-20, 0, -12), Size = Vector3.new(6, 5, 12), Weight = 2.4, ChunkCount = 18, Palette = "Clothes", TargetEligible = true },
	-- Under bed (low and wide)
	{ Id = "UnderBed_01", RegionId = "UnderBed", Center = Vector3.new(-30, 0, -26), Size = Vector3.new(12, 2.6, 6), Weight = 2.2, ChunkCount = 16, Palette = "Shoes", TargetEligible = true, Flat = true },
	{ Id = "UnderBed_02", RegionId = "UnderBed", Center = Vector3.new(-30, 0, -9), Size = Vector3.new(12, 2.6, 6), Weight = 2.2, ChunkCount = 16, Palette = "Boxes", TargetEligible = true, Flat = true },
	-- Desk
	{ Id = "Desk_01", RegionId = "Desk", Center = Vector3.new(26, 3.4, -30), Size = Vector3.new(7, 4, 6), Weight = 2.0, ChunkCount = 16, Palette = "Paper", TargetEligible = true },
	{ Id = "Desk_02", RegionId = "Desk", Center = Vector3.new(22, 0, -23), Size = Vector3.new(8, 5, 8), Weight = 3.0, ChunkCount = 22, Palette = "Electronics", TargetEligible = true },
	{ Id = "Desk_03", RegionId = "Desk", Center = Vector3.new(38, 0, -22), Size = Vector3.new(8, 5, 8), Weight = 2.8, ChunkCount = 20, Palette = "Books", TargetEligible = true },
	-- Closet
	{ Id = "Closet_01", RegionId = "Closet", Center = Vector3.new(-37, 0, 2), Size = Vector3.new(8, 7, 8), Weight = 3.2, ChunkCount = 22, Palette = "Clothes", TargetEligible = true },
	{ Id = "Closet_02", RegionId = "Closet", Center = Vector3.new(-37, 0, 11), Size = Vector3.new(8, 8, 8), Weight = 3.6, ChunkCount = 24, Palette = "Clothes", TargetEligible = true },
	{ Id = "Closet_03", RegionId = "Closet", Center = Vector3.new(-37, 0, 20), Size = Vector3.new(8, 6, 8), Weight = 3.0, ChunkCount = 20, Palette = "Boxes", TargetEligible = true },
	-- Bookshelf
	{ Id = "Bookshelf_01", RegionId = "Bookshelf", Center = Vector3.new(38, 0, -12), Size = Vector3.new(7, 6, 8), Weight = 2.8, ChunkCount = 22, Palette = "Books", TargetEligible = true },
	{ Id = "Bookshelf_02", RegionId = "Bookshelf", Center = Vector3.new(38, 0, -2), Size = Vector3.new(7, 6, 8), Weight = 2.8, ChunkCount = 22, Palette = "Books", TargetEligible = true },
	-- Laundry corner
	{ Id = "Laundry_01", RegionId = "LaundryCorner", Center = Vector3.new(-36, 0, 29), Size = Vector3.new(10, 7, 8), Weight = 3.4, ChunkCount = 24, Palette = "Clothes", TargetEligible = true },
	{ Id = "Laundry_02", RegionId = "LaundryCorner", Center = Vector3.new(-26, 0, 30), Size = Vector3.new(8, 5, 6), Weight = 2.4, ChunkCount = 18, Palette = "Clothes", TargetEligible = true },
	{ Id = "Laundry_03", RegionId = "LaundryCorner", Center = Vector3.new(-30, 0, 20), Size = Vector3.new(8, 5, 8), Weight = 2.6, ChunkCount = 18, Palette = "Mixed", TargetEligible = true },
	-- Toy corner
	{ Id = "Toy_01", RegionId = "ToyCorner", Center = Vector3.new(34, 0, 28), Size = Vector3.new(10, 6, 8), Weight = 3.2, ChunkCount = 24, Palette = "Toys", TargetEligible = true },
	{ Id = "Toy_02", RegionId = "ToyCorner", Center = Vector3.new(24, 0, 28), Size = Vector3.new(8, 5, 6), Weight = 2.4, ChunkCount = 18, Palette = "Toys", TargetEligible = true },
	{ Id = "Toy_03", RegionId = "ToyCorner", Center = Vector3.new(36, 0, 16), Size = Vector3.new(8, 5, 8), Weight = 2.8, ChunkCount = 20, Palette = "Boxes", TargetEligible = true },
	-- Dresser
	{ Id = "Dresser_01", RegionId = "Dresser", Center = Vector3.new(-2, 6.2, -32), Size = Vector3.new(12, 3.5, 4.5), Weight = 2.0, ChunkCount = 16, Palette = "Mixed", TargetEligible = true },
	{ Id = "Dresser_02", RegionId = "Dresser", Center = Vector3.new(-12, 0, -26), Size = Vector3.new(8, 5, 8), Weight = 2.8, ChunkCount = 20, Palette = "Clothes", TargetEligible = true },
	{ Id = "Dresser_03", RegionId = "Dresser", Center = Vector3.new(6, 0, -25), Size = Vector3.new(8, 5, 8), Weight = 2.8, ChunkCount = 20, Palette = "Paper", TargetEligible = true },
	-- Window
	{ Id = "Window_01", RegionId = "WindowArea", Center = Vector3.new(14, 0, -24), Size = Vector3.new(9, 6, 8), Weight = 3.0, ChunkCount = 22, Palette = "Mixed", TargetEligible = true },
	-- Center floor
	{ Id = "Center_01", RegionId = "CenterFloor", Center = Vector3.new(0, 0, 0), Size = Vector3.new(10, 7, 10), Weight = 4.0, ChunkCount = 28, Palette = "Mixed", TargetEligible = true },
	{ Id = "Center_02", RegionId = "CenterFloor", Center = Vector3.new(6, 0, -9), Size = Vector3.new(8, 5, 8), Weight = 2.8, ChunkCount = 20, Palette = "Toys", TargetEligible = true },
	{ Id = "Center_03", RegionId = "CenterFloor", Center = Vector3.new(-5, 0, 10), Size = Vector3.new(8, 5, 8), Weight = 2.8, ChunkCount = 20, Palette = "Paper", TargetEligible = true },
	-- Left floor
	{ Id = "Left_01", RegionId = "LeftFloor", Center = Vector3.new(-20, 0, 2), Size = Vector3.new(9, 6, 9), Weight = 3.2, ChunkCount = 22, Palette = "Boxes", TargetEligible = true },
	{ Id = "Left_02", RegionId = "LeftFloor", Center = Vector3.new(-19, 0, 13), Size = Vector3.new(8, 5, 8), Weight = 2.6, ChunkCount = 18, Palette = "Clothes", TargetEligible = true },
	-- Right floor
	{ Id = "Right_01", RegionId = "RightFloor", Center = Vector3.new(20, 0, 4), Size = Vector3.new(9, 6, 9), Weight = 3.2, ChunkCount = 22, Palette = "Electronics", TargetEligible = true },
	{ Id = "Right_02", RegionId = "RightFloor", Center = Vector3.new(19, 0, 15), Size = Vector3.new(8, 5, 8), Weight = 2.6, ChunkCount = 18, Palette = "Shoes", TargetEligible = true },
}

--[[
	TargetSockets. Offset is relative to the owning cluster's Center (bottom-center of the
	pile). Every socket sits inside its cluster's footprint so it is exposed as that pile
	shrinks. Difficulty is informational for now (future rooms may weight selection).
]]
Room.Sockets = {
	{ Id = "S_Bed_01a", ClusterId = "Bed_01", Offset = Vector3.new(-2, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Bed_01b", ClusterId = "Bed_01", Offset = Vector3.new(3, 0.6, -3), Difficulty = 2 },
	{ Id = "S_Bed_02a", ClusterId = "Bed_02", Offset = Vector3.new(0, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Bed_03a", ClusterId = "Bed_03", Offset = Vector3.new(0.5, 0.6, -2), Difficulty = 2 },
	{ Id = "S_UnderBed_01a", ClusterId = "UnderBed_01", Offset = Vector3.new(-3, 0.5, 0), Difficulty = 3 },
	{ Id = "S_UnderBed_01b", ClusterId = "UnderBed_01", Offset = Vector3.new(3, 0.5, 0.5), Difficulty = 3 },
	{ Id = "S_UnderBed_02a", ClusterId = "UnderBed_02", Offset = Vector3.new(0, 0.5, 0), Difficulty = 3 },
	{ Id = "S_Desk_01a", ClusterId = "Desk_01", Offset = Vector3.new(0, 0.5, 0.5), Difficulty = 2 },
	{ Id = "S_Desk_02a", ClusterId = "Desk_02", Offset = Vector3.new(-1.5, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Desk_02b", ClusterId = "Desk_02", Offset = Vector3.new(2, 0.6, -2), Difficulty = 2 },
	{ Id = "S_Desk_03a", ClusterId = "Desk_03", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Closet_01a", ClusterId = "Closet_01", Offset = Vector3.new(1, 0.6, -1), Difficulty = 2 },
	{ Id = "S_Closet_02a", ClusterId = "Closet_02", Offset = Vector3.new(-1, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Closet_02b", ClusterId = "Closet_02", Offset = Vector3.new(2, 0.6, 2), Difficulty = 2 },
	{ Id = "S_Closet_03a", ClusterId = "Closet_03", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Bookshelf_01a", ClusterId = "Bookshelf_01", Offset = Vector3.new(0, 0.6, -1), Difficulty = 2 },
	{ Id = "S_Bookshelf_02a", ClusterId = "Bookshelf_02", Offset = Vector3.new(-1, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Laundry_01a", ClusterId = "Laundry_01", Offset = Vector3.new(-2, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Laundry_01b", ClusterId = "Laundry_01", Offset = Vector3.new(2.5, 0.6, -1), Difficulty = 2 },
	{ Id = "S_Laundry_02a", ClusterId = "Laundry_02", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Laundry_03a", ClusterId = "Laundry_03", Offset = Vector3.new(1, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Toy_01a", ClusterId = "Toy_01", Offset = Vector3.new(-2, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Toy_01b", ClusterId = "Toy_01", Offset = Vector3.new(2, 0.6, -1), Difficulty = 2 },
	{ Id = "S_Toy_02a", ClusterId = "Toy_02", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Toy_03a", ClusterId = "Toy_03", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Dresser_01a", ClusterId = "Dresser_01", Offset = Vector3.new(-3, 0.5, 0), Difficulty = 2 },
	{ Id = "S_Dresser_02a", ClusterId = "Dresser_02", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Dresser_03a", ClusterId = "Dresser_03", Offset = Vector3.new(1, 0.6, -1), Difficulty = 2 },
	{ Id = "S_Window_01a", ClusterId = "Window_01", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
	{ Id = "S_Window_01b", ClusterId = "Window_01", Offset = Vector3.new(-2.5, 0.6, 2), Difficulty = 2 },
	{ Id = "S_Center_01a", ClusterId = "Center_01", Offset = Vector3.new(-2, 0.6, -2), Difficulty = 1 },
	{ Id = "S_Center_01b", ClusterId = "Center_01", Offset = Vector3.new(2.5, 0.6, 2), Difficulty = 1 },
	{ Id = "S_Center_02a", ClusterId = "Center_02", Offset = Vector3.new(0, 0.6, 0), Difficulty = 1 },
	{ Id = "S_Center_03a", ClusterId = "Center_03", Offset = Vector3.new(0, 0.6, 0), Difficulty = 1 },
	{ Id = "S_Left_01a", ClusterId = "Left_01", Offset = Vector3.new(0, 0.6, -2), Difficulty = 2 },
	{ Id = "S_Left_02a", ClusterId = "Left_02", Offset = Vector3.new(1, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Right_01a", ClusterId = "Right_01", Offset = Vector3.new(-2, 0.6, 1), Difficulty = 2 },
	{ Id = "S_Right_02a", ClusterId = "Right_02", Offset = Vector3.new(0, 0.6, 0), Difficulty = 2 },
}

return Room
