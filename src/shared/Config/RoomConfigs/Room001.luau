--[[
	ROOM #001 - THE MESSY BEDROOM
	Room-local studs: origin = floor centre at y = 0, X [-45, 45], Z [-35, 35], door on +Z.

	Piles are LAYOUT metadata only: they tell the builder where to physically stack individual
	clutter objects, which AssetKeys to use and how many. Players never interact with a pile -
	only with the individual objects in it.
	  Layout "Heap": objects stacked with a height map (heavier items tend to sit lower).
	  Layout "Row":  objects standing upright in a line (books on shelves, clothes on a rail).

	Target sockets sit at the base of a pile. Their blockers are the real objects the builder
	stacked over the socket; the Golden Key appears only once those objects are moved away.
]]

local Room = {
	Id = 1,
	DisplayNumber = "001",
	Name = "The Messy Bedroom",
	ObjectPrefix = "Bedroom", -- ObjectIds look like Bedroom_Book_0042

	TargetId = "GoldenKey",
	TargetName = "Golden Key",

	MinimumTargetSockets = 30,
	SocketBlockerRadius = 1.4, -- XZ radius around a socket that must be clear of clutter
	-- A blocker stops covering the key once its footprint is this far (XZ) from the socket: the
	-- same test that made it a blocker. Loose piles slump, so anything stricter keeps the key
	-- hidden under objects that have already slid off it.
	RequiredBlockerDisplacement = 1.4,

	-- Unique-object progress milestones: side / area / region / hot-cold / blocker outline.
	-- Fractions of the room CLEANED (deposited in bins). ~4,500 objects: 2% is ~90 deposits.
	HintMilestones = { 0.02, 0.045, 0.08, 0.12, 0.17 },

	LayoutVariants = { 1 },

	-- Density knobs for the builder (tune against the performance test, not per pile).
	-- Every object is loose physics; ~1,800 loose bodies settle at 60 Hz, so depth comes from
	-- packed junk chunks (below) rather than thousands more bodies.
	CountMultiplier = 2.4, -- more candidate objects per heap
	-- Share of every floor heap built from packed junk chunks (bottom layers). Each chunk bursts
	-- into ChunkContents real objects when grabbed: depth without thousands of live bodies.
	ChunkFraction = 0.28,
	ChunkContents = { 5, 8 },
	FloorHeapHeightBonus = 4, -- taller floor heaps (light clutter never blocks players)

	Size = Vector3.new(90, 26, 70),
	SpawnPosition = Vector3.new(0, 3, 29),

	FloorColor = Color3.fromRGB(180, 140, 100),
	WallColor = Color3.fromRGB(120, 170, 220),
}

Room.Regions = {
	{ Id = "BedPile", Name = "BED", Center = Vector3.new(-30, 6, -18), Size = Vector3.new(16, 8, 24) },
	{ Id = "UnderBed", Name = "UNDER THE BED", Center = Vector3.new(-30, 1, -18), Size = Vector3.new(16, 3, 24) },
	{ Id = "Desk", Name = "DESK", Center = Vector3.new(30, 5, -26), Size = Vector3.new(24, 10, 18) },
	{ Id = "Closet", Name = "CLOSET", Center = Vector3.new(-38, 7, 10), Size = Vector3.new(14, 14, 28) },
	{ Id = "Bookshelf", Name = "BOOKSHELF", Center = Vector3.new(39, 7, -6), Size = Vector3.new(12, 14, 20) },
	{ Id = "LaundryCorner", Name = "LAUNDRY CORNER", Center = Vector3.new(-32, 4, 25), Size = Vector3.new(22, 8, 18) },
	{ Id = "ToyCorner", Name = "TOY CORNER", Center = Vector3.new(32, 4, 23), Size = Vector3.new(22, 8, 20) },
	{ Id = "Dresser", Name = "DRESSER", Center = Vector3.new(-3, 5, -28), Size = Vector3.new(26, 10, 14) },
	{ Id = "WindowArea", Name = "WINDOW", Center = Vector3.new(14, 4, -25), Size = Vector3.new(14, 8, 14) },
	{ Id = "CenterFloor", Name = "CENTER FLOOR", Center = Vector3.new(0, 3, 0), Size = Vector3.new(22, 6, 24) },
	{ Id = "LeftFloor", Name = "LEFT FLOOR", Center = Vector3.new(-19, 3, 5), Size = Vector3.new(16, 6, 26) },
	{ Id = "RightFloor", Name = "RIGHT FLOOR", Center = Vector3.new(20, 3, 6), Size = Vector3.new(16, 6, 26) },
}

Room.HintAreas = {
	{ Label = "BED / UNDER BED / CLOSET", Regions = { "BedPile", "UnderBed", "Closet" } },
	{ Label = "DESK / BOOKSHELF / WINDOW", Regions = { "Desk", "Bookshelf", "WindowArea" } },
	{ Label = "LAUNDRY / LEFT FLOOR / DRESSER", Regions = { "LaundryCorner", "LeftFloor", "Dresser" } },
	{ Label = "TOYS / RIGHT FLOOR / CENTER", Regions = { "ToyCorner", "RightFloor", "CenterFloor" } },
}

-- Where cleaned objects go (see DepositConfig). Center = floor centre of the bin, Size = inner
-- width / wall height / depth. Clutter never spawns in or right around a bin.
Room.DepositBins = {
	{ Type = "Laundry", Center = Vector3.new(-17.5, 0, 30), Size = Vector3.new(4.6, 2.6, 4.6) },
	{ Type = "Toys", Center = Vector3.new(17.5, 0, 30), Size = Vector3.new(4.6, 2.6, 4.6) },
	{ Type = "Books", Center = Vector3.new(31, 0, 5), Size = Vector3.new(4.2, 2.4, 4.2) },
	{ Type = "Trash", Center = Vector3.new(-5, 0, -17), Size = Vector3.new(4.2, 2.8, 4.2) },
	{ Type = "Donation", Center = Vector3.new(9, 0, 31), Size = Vector3.new(6.5, 1.4, 5) },
}

-- Big open-top boxes that keep their piles tall instead of slumping flat (the deepest digs).
Room.Containers = {
	{ Id = "MovingBox", Center = Vector3.new(-19, 0, 2), Size = Vector3.new(8.6, 3.6, 8.6), Color = Color3.fromRGB(196, 150, 100) },
	{ Id = "ToyChest", Center = Vector3.new(34, 0, 28), Size = Vector3.new(11.6, 3.2, 8.6), Color = Color3.fromRGB(150, 95, 60) },
	{ Id = "Hamper", Center = Vector3.new(-36, 0, 29), Size = Vector3.new(10.6, 3.4, 8.6), Color = Color3.fromRGB(235, 235, 240) },
}

-- AssetKey mixes (key = relative frequency).
local Mix = {
	Bed = { Pillow_A = 4, Blanket_A = 3, Shirt_A = 6, Hoodie_A = 3, Sock_A = 4, Book_A = 3, Plush_A = 2, TeddyBear_A = 1, Laptop_A = 1, Headphones_A = 1, Controller_A = 1, Magazine_A = 2, Backpack_A = 1 },
	UnderBed = { Shoe_A = 4, Sock_A = 3, Magazine_A = 3, Book_A = 3, Paper_A = 2, PizzaBox_A = 2, ToyCar_A = 2, Controller_A = 1, Remote_A = 1, Can_A = 2, Notebook_A = 2 },
	Desk = { Paper_A = 5, Notebook_A = 4, Book_A = 3, Book_C = 2, Pencil_A = 4, Cup_A = 2, Can_A = 2, Bottle_A = 2, Remote_A = 1, Controller_A = 1, Headphones_A = 1, Camera_A = 1, Cable_A = 2, Laptop_A = 1 },
	DeskFloor = { CardboardBox_A = 3, StorageBin_A = 1, Book_B = 3, Paper_A = 3, Backpack_A = 1, Cable_A = 2, PizzaBox_A = 2, Bottle_A = 2, Controller_A = 1, Shirt_A = 2 },
	Closet = { Shirt_A = 6, Hoodie_A = 5, Sock_A = 3, Shoe_A = 4, CardboardBox_A = 2, CardboardBox_B = 1, StorageBin_A = 1, Basket_A = 1, Backpack_A = 1, Blanket_A = 1 },
	Books = { Book_A = 5, Book_B = 4, Book_C = 3, Magazine_A = 3, Notebook_A = 2, CardboardBox_A = 1, Paper_A = 2 },
	Laundry = { Shirt_A = 6, Hoodie_A = 4, Sock_A = 5, Blanket_A = 1, Basket_A = 1, Shoe_A = 2, Pillow_A = 1 },
	Toys = { ToyBlock_A = 6, ToyCar_A = 3, ToyDuck_A = 2, Plush_A = 3, TeddyBear_A = 2, Basketball_A = 1, CardboardBox_A = 1, StorageBin_A = 1, Controller_A = 1 },
	DresserTop = { Sock_A = 3, Shirt_A = 3, Cup_A = 2, Bottle_A = 1, Book_A = 2, Remote_A = 1, Camera_A = 1, Headphones_A = 1, Plush_A = 1, Magazine_A = 2, Can_A = 1 },
	Floor = { CardboardBox_A = 2, CardboardBox_B = 1, HeavyBox_A = 1, StorageBin_A = 1, Shirt_A = 3, Book_A = 3, ToyBlock_A = 2, Shoe_A = 2, PizzaBox_A = 1, Backpack_A = 1, Basketball_A = 1, Paper_A = 2, Can_A = 1, Hoodie_A = 1 },
	Scatter = { Paper_A = 4, Sock_A = 3, Shirt_A = 2, Magazine_A = 2, Can_A = 2, Cup_A = 1, Pencil_A = 2, ToyBlock_A = 2, Book_A = 1, Remote_A = 1 },
	ShelfBooks = { Book_A = 3, Book_B = 2, Book_C = 2, Notebook_A = 1 },
	Hanging = { Shirt_A = 3, Hoodie_A = 1 },
	-- Big, flat, light junk that buries the whole floor with as few physics bodies as possible
	-- (never blocks walking). Small pieces cost the same physics per body but cover far less.
	Carpet = { Shirt_A = 6, Hoodie_A = 4, Blanket_A = 2, PizzaBox_A = 3, Magazine_A = 3, Paper_A = 2, Book_B = 2, Notebook_A = 1, Shoe_A = 1, ToyCar_A = 1, Controller_A = 1 },
}

local function heap(id, region, mix, center, size, count, maxHeight)
	return { Id = id, RegionId = region, Layout = "Heap", Mix = Mix[mix], Center = center, Size = size, Count = count, MaxHeight = maxHeight }
end

local function row(id, region, mix, from, to, baseY, depthX)
	return { Id = id, RegionId = region, Layout = "Row", Mix = Mix[mix], From = from, To = to, BaseY = baseY, DepthX = depthX }
end

-- Tiles a floor rectangle with layered flat junk. Density = candidate objects per square stud.
local function carpet(id, mix, center, size, density, maxHeight, exclusions, scaleMax)
	return { Id = id, Layout = "Carpet", Mix = Mix[mix], Center = center, Size = size, Tile = 8, Density = density, MaxHeight = maxHeight, ScaleMin = 1.0, ScaleMax = scaleMax or 1.5, Exclusions = exclusions }
end

-- Center = base centre (y is the surface the pile rests on). Size = XZ footprint.
Room.Piles = {
	heap("Bed_Top", "BedPile", "Bed", Vector3.new(-30, 4.2, -16), Vector2.new(12, 18), 95, 5.5),
	heap("Bed_Side", "BedPile", "Laundry", Vector3.new(-20.5, 0, -14), Vector2.new(5, 14), 40, 4.5),
	heap("UnderBed_A", "UnderBed", "UnderBed", Vector3.new(-30, 0, -22), Vector2.new(11, 9), 38, 1.5),
	heap("UnderBed_B", "UnderBed", "UnderBed", Vector3.new(-30, 0, -12), Vector2.new(11, 8), 34, 1.5),
	heap("Desk_Top", "Desk", "Desk", Vector3.new(27.5, 3.4, -28.6), Vector2.new(9, 3.4), 45, 2.8),
	heap("Desk_Floor_L", "Desk", "DeskFloor", Vector3.new(21, 0, -22), Vector2.new(8, 8), 40, 4.5),
	heap("Desk_Floor_R", "Desk", "DeskFloor", Vector3.new(38, 0, -21), Vector2.new(8, 7), 36, 4.5),
	heap("Closet_Floor", "Closet", "Closet", Vector3.new(-41, 0, 10), Vector2.new(5, 19), 95, 7.5),
	heap("Closet_Front", "Closet", "Closet", Vector3.new(-35, 0, 4), Vector2.new(6, 8), 40, 4.5),
	heap("Bookshelf_Floor_A", "Bookshelf", "Books", Vector3.new(38, 0, -11), Vector2.new(6, 7), 40, 4),
	heap("Bookshelf_Floor_B", "Bookshelf", "Books", Vector3.new(38, 0, -1), Vector2.new(6, 7), 38, 4),
	heap("Laundry_Main", "LaundryCorner", "Laundry", Vector3.new(-36, 0, 29), Vector2.new(10, 8), 70, 6),
	heap("Laundry_B", "LaundryCorner", "Laundry", Vector3.new(-26, 0, 30), Vector2.new(8, 6), 38, 4.5),
	heap("Laundry_C", "LaundryCorner", "Floor", Vector3.new(-30, 0, 21), Vector2.new(8, 7), 36, 4.5),
	heap("Toy_Main", "ToyCorner", "Toys", Vector3.new(34, 0, 28), Vector2.new(11, 8), 80, 5.5),
	heap("Toy_B", "ToyCorner", "Toys", Vector3.new(25, 0, 29), Vector2.new(8, 6), 38, 4),
	heap("Toy_C", "ToyCorner", "Floor", Vector3.new(37, 0, 17), Vector2.new(8, 7), 36, 4.5),
	heap("Dresser_Top", "Dresser", "DresserTop", Vector3.new(-2, 6, -32), Vector2.new(12, 4), 35, 3),
	heap("Dresser_Floor_L", "Dresser", "Floor", Vector3.new(-13, 0, -26), Vector2.new(8, 8), 40, 4.5),
	heap("Dresser_Floor_R", "Dresser", "Laundry", Vector3.new(6, 0, -25), Vector2.new(7, 7), 34, 4),
	heap("Window_Pile", "WindowArea", "Floor", Vector3.new(15, 0, -25), Vector2.new(9, 8), 45, 5),
	heap("Center_Main", "CenterFloor", "Floor", Vector3.new(0, 0, -3), Vector2.new(10, 10), 70, 5.5),
	heap("Center_B", "CenterFloor", "Toys", Vector3.new(8, 0, -12), Vector2.new(7, 7), 34, 4),
	heap("Center_C", "CenterFloor", "Books", Vector3.new(-7, 0, 8), Vector2.new(7, 7), 34, 4),
	heap("Left_A", "LeftFloor", "Floor", Vector3.new(-19, 0, 2), Vector2.new(8, 8), 42, 5),
	heap("Left_B", "LeftFloor", "Laundry", Vector3.new(-18, 0, 14), Vector2.new(7, 7), 34, 4),
	heap("Right_A", "RightFloor", "Floor", Vector3.new(19, 0, 3), Vector2.new(8, 8), 42, 5),
	heap("Right_B", "RightFloor", "DeskFloor", Vector3.new(19, 0, 14), Vector2.new(7, 7), 34, 4),
	heap("Scatter_Mid", "CenterFloor", "Scatter", Vector3.new(0, 0, 2), Vector2.new(36, 30), 90, 1.2),
	heap("Scatter_Back", "Dresser", "Scatter", Vector3.new(0, 0, -20), Vector2.new(30, 8), 40, 1.2),
	heap("Scatter_Left", "LeftFloor", "Scatter", Vector3.new(-22, 0, -4), Vector2.new(10, 12), 45, 1.2),
	heap("Scatter_Right", "RightFloor", "Scatter", Vector3.new(24, 0, -6), Vector2.new(10, 12), 45, 1.2),
	-- Extra mounds in what used to be open floor.
	heap("Mound_MidLeft", "LeftFloor", "Floor", Vector3.new(-12, 0, -10), Vector2.new(8, 8), 45, 4.5),
	heap("Mound_MidRight", "RightFloor", "Toys", Vector3.new(11, 0, 7), Vector2.new(7, 7), 40, 4),
	heap("Mound_Closetside", "LeftFloor", "Laundry", Vector3.new(-27, 0, -2), Vector2.new(7, 7), 40, 4),
	heap("Mound_Shelfside", "RightFloor", "Books", Vector3.new(29, 0, -12), Vector2.new(7, 7), 40, 4),
	-- The whole floor, buried: layered flat junk everywhere the heaps and furniture aren't.
	-- A small doormat by the entrance stays clear so the spawn reads as a doorway.
	carpet("Carpet", "Carpet", Vector3.new(0, 0, 0), Vector2.new(88, 68), 0.55, 1.8, {
		{ Center = Vector2.new(0, 31.5), Size = Vector2.new(6, 5) },
	}, 1.6),
	-- Bookshelf rows (shelf tops) and clothes hanging on the closet rail.
	row("Shelf_1", "Bookshelf", "ShelfBooks", Vector3.new(43, 0, -13.6), Vector3.new(43, 0, 1.6), 3.7, 43),
	row("Shelf_2", "Bookshelf", "ShelfBooks", Vector3.new(43, 0, -13.6), Vector3.new(43, 0, 1.6), 6.7, 43),
	row("Shelf_3", "Bookshelf", "ShelfBooks", Vector3.new(43, 0, -13.6), Vector3.new(43, 0, 1.6), 9.7, 43),
	row("Shelf_4", "Bookshelf", "ShelfBooks", Vector3.new(43, 0, -13.6), Vector3.new(43, 0, 1.6), 12.7, 43),
	row("Closet_Rail", "Closet", "Hanging", Vector3.new(-42.2, 0, 0.5), Vector3.new(-42.2, 0, 19.5), 8.9, -42.2),
}

-- Golden Key hiding places. Offset is XZ from the pile's Center, on the pile's surface.
local function socket(id, pile, x, z, difficulty)
	return { Id = id, PileId = pile, Offset = Vector2.new(x, z), Difficulty = difficulty or 2 }
end

Room.Sockets = {
	socket("S_Bed_01", "Bed_Top", -3, -5), socket("S_Bed_02", "Bed_Top", 2.5, 3), socket("S_Bed_03", "Bed_Top", 0, -1),
	socket("S_BedSide_01", "Bed_Side", 0, -3),
	socket("S_UnderBed_01", "UnderBed_A", -3, 0, 3), socket("S_UnderBed_02", "UnderBed_A", 3, 1, 3), socket("S_UnderBed_03", "UnderBed_B", 0, 0, 3),
	socket("S_Desk_01", "Desk_Top", -1.5, 0), socket("S_Desk_02", "Desk_Floor_L", 0, 1), socket("S_Desk_03", "Desk_Floor_R", 0, 0),
	socket("S_Closet_01", "Closet_Floor", 0, -5), socket("S_Closet_02", "Closet_Floor", 0, 3), socket("S_Closet_03", "Closet_Front", 0, 0),
	socket("S_Books_01", "Bookshelf_Floor_A", 0, 0), socket("S_Books_02", "Bookshelf_Floor_B", 0.5, -0.5),
	socket("S_Laundry_01", "Laundry_Main", -2, 0), socket("S_Laundry_02", "Laundry_Main", 2.5, -1), socket("S_Laundry_03", "Laundry_B", 0, 0), socket("S_Laundry_04", "Laundry_C", 0, 0),
	socket("S_Toy_01", "Toy_Main", -2.5, 0.5), socket("S_Toy_02", "Toy_Main", 2.5, -1), socket("S_Toy_03", "Toy_B", 0, 0), socket("S_Toy_04", "Toy_C", 0, 0),
	socket("S_Dresser_01", "Dresser_Top", -3, 0), socket("S_Dresser_02", "Dresser_Floor_L", 0, 0), socket("S_Dresser_03", "Dresser_Floor_R", 0, 0),
	socket("S_Window_01", "Window_Pile", 0, 0), socket("S_Window_02", "Window_Pile", -2.5, 2),
	socket("S_Center_01", "Center_Main", -2, -2, 1), socket("S_Center_02", "Center_Main", 2.5, 2, 1), socket("S_Center_03", "Center_B", 0, 0, 1), socket("S_Center_04", "Center_C", 0, 0, 1),
	socket("S_Left_01", "Left_A", 0, -1), socket("S_Left_02", "Left_B", 0, 0),
	socket("S_Right_01", "Right_A", 0, 1), socket("S_Right_02", "Right_B", 0, 0),
}

return Room
