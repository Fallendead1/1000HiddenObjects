--[[
	ROOM #004 - THE DUSTY GARAGE
	Years of family junk around a covered car. The heaviest room yet: Strength upgrades and
	the Donation box matter here.
	Room-local studs: origin = floor centre at y = 0, X [-45, 45], Z [-35, 35], door on +Z.
	The covered car stands in the middle in front of the roll-up garage door (back wall), the
	workbench and tool wall are on the left, tall storage shelves on the right. Box heaps by the
	shelves come tumbling down when a low box is pulled.
]]

local Kit = require(script.Parent.Kit)

local C = Color3.fromRGB
local V = Vector3.new
local V2 = Vector2.new
local solid, deco = Kit.solid, Kit.deco

local Room = {
	Id = 4,
	DisplayNumber = "004",
	Name = "The Dusty Garage",
	ObjectPrefix = "Garage",

	TargetId = "GoldenWrench",
	TargetName = "Golden Wrench",

	MinimumTargetSockets = 30,
	SocketBlockerRadius = 1.4,
	RequiredBlockerDisplacement = 1.4,
	HintMilestones = { 0.25, 0.275, 0.31, 0.35, 0.4 },
	ExitDoor = "Door",
	LayoutVariants = { 1 },

	CountMultiplier = 2.4,
	ChunkFraction = 0.35,
	ChunkContents = { 5, 8 },
	FloorHeapHeightBonus = 4,
	HardMode = { ChunkFraction = 0.55, ChunkContents = { 12, 16 } },
	TreasureKeys = { "Treasure_ToyCarGold", "Treasure_Watch", "Treasure_Coin", "Treasure_Trophy" },

	Size = V(90, 30, 70),
	SpawnPosition = V(0, 3, 29),

	FloorColor = C(150, 150, 155),
	FloorMaterial = Enum.Material.Concrete,
	WallColor = C(190, 175, 150),
	CeilingColor = C(210, 210, 215),
	LampColor = C(255, 240, 210),
	LampBrightness = 0.8,
}

Room.Regions = {
	{ Id = "Car", Name = "COVERED CAR", Center = V(0, 4, -14), Size = V(20, 8, 24) },
	{ Id = "Workbench", Name = "WORKBENCH", Center = V(-30, 5, -28), Size = V(22, 10, 14) },
	{ Id = "ToolWall", Name = "TOOL WALL", Center = V(-37, 5, -6), Size = V(16, 10, 18) },
	{ Id = "Shelves", Name = "TALL SHELVES", Center = V(37, 8, -8), Size = V(16, 16, 24) },
	{ Id = "BikeRack", Name = "BIKE RACK", Center = V(24, 4, -28), Size = V(14, 8, 14) },
	{ Id = "PaintCorner", Name = "PAINT CORNER", Center = V(-35, 4, 26), Size = V(20, 8, 16) },
	{ Id = "SportsCorner", Name = "SPORTS CORNER", Center = V(34, 4, 25), Size = V(22, 8, 18) },
	{ Id = "Freezer", Name = "FREEZER CORNER", Center = V(38, 4, 8), Size = V(14, 8, 10) },
	{ Id = "GarageDoor", Name = "GARAGE DOOR", Center = V(-12, 4, -30), Size = V(8, 8, 10) },
	{ Id = "CenterFloor", Name = "CENTER FLOOR", Center = V(0, 3, 12), Size = V(26, 6, 20) },
	{ Id = "LeftFloor", Name = "LEFT FLOOR", Center = V(-22, 3, 10), Size = V(14, 6, 16) },
	{ Id = "RightFloor", Name = "RIGHT FLOOR", Center = V(20, 3, 6), Size = V(14, 6, 20) },
}

Room.HintAreas = {
	{ Label = "WORKBENCH / TOOL WALL / GARAGE DOOR", Regions = { "Workbench", "ToolWall", "GarageDoor" } },
	{ Label = "CAR / CENTER FLOOR", Regions = { "Car", "CenterFloor" } },
	{ Label = "SHELVES / BIKES / FREEZER / RIGHT FLOOR", Regions = { "Shelves", "BikeRack", "Freezer", "RightFloor" } },
	{ Label = "PAINT / SPORTS / LEFT FLOOR", Regions = { "PaintCorner", "SportsCorner", "LeftFloor" } },
}

Room.SideSigns = {
	LEFT = { Z = 14, Width = 16, Landmarks = "WORKBENCH · TOOLS · PAINT" },
	RIGHT = { Z = 16, Width = 16, Landmarks = "SHELVES · BIKES · SPORTS" },
}

Room.DepositBins = {
	{ Type = "Toolbox", Center = V(-17.5, 0, 30), Size = V(4.6, 2.6, 4.6) },
	{ Type = "SportsBin", Center = V(17.5, 0, 30), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Recycling", Center = V(28, 0, 14), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Trash", Center = V(-26, 0, -12), Size = V(4.2, 2.8, 4.2) },
	{ Type = "Donation", Center = V(9, 0, 31), Size = V(6.5, 1.4, 5) },
}

Room.Containers = {
	{ Id = "PaintCrate", Center = V(-36, 0, 27), Size = V(11.6, 3.2, 8.6), Color = C(170, 170, 175) },
	{ Id = "SportsCrate", Center = V(36, 0, 26), Size = V(11.6, 3.4, 8.6), Color = C(60, 110, 200) },
	{ Id = "JunkBox", Center = V(-14, 0, 10), Size = V(8.6, 3.6, 8.6), Color = C(196, 150, 100) },
}

-- ===== Furniture =====
local metal, metalDark = C(120, 125, 135), C(80, 85, 95)
local wood = C(170, 125, 80)
local F = {}
local function add(f)
	table.insert(F, f)
end
-- The covered car: body, cabin, tarp and tyres.
add(solid("CarBody", V(9, 4.2, 16), V(0, 2.1, -14), C(90, 110, 140), Enum.Material.Fabric))
add(solid("CarCabin", V(8, 2.6, 8), V(0, 5.5, -15), C(90, 110, 140), Enum.Material.Fabric))
add(deco("Tarp", V(9.6, 0.1, 17), V(0, 6.9, -14), C(110, 130, 160), Enum.Material.Fabric))
for _, x in ipairs({ -4.6, 4.6 }) do
	for _, z in ipairs({ -19.5, -8.5 }) do
		add(deco("Tyre", V(1.2, 2.6, 2.6), V(x, 1.3, z), C(25, 25, 28), nil, { Shape = Enum.PartType.Cylinder }))
	end
end
-- Roll-up garage door on the back wall.
add(deco("GarageDoorPanel", V(26, 14, 0.4), V(0, 7, -34.6), C(215, 215, 220), Enum.Material.Metal))
for i = 0, 5 do
	add(deco("GarageDoorRib", V(26.2, 0.3, 0.5), V(0, 1.5 + i * 2.4, -34.3), C(180, 180, 190), Enum.Material.Metal))
end
-- Workbench and the pegboard tool wall on the left.
add(solid("Workbench", V(18, 3.4, 5), V(-30, 1.7, -32), wood, Enum.Material.WoodPlanks))
add(deco("Pegboard", V(20, 8, 0.3), V(-30, 9, -34.6), C(200, 170, 120), Enum.Material.WoodPlanks))
add(deco("PegboardSide", V(0.3, 8, 18), V(-44.6, 9, -6), C(200, 170, 120), Enum.Material.WoodPlanks))
for i = 0, 4 do
	add(deco("HangingTool", V(0.3, 2.4, 0.6), V(-44.3, 9, -13 + i * 3.5), metal, Enum.Material.Metal))
end
add(deco("WorkLamp", V(4, 0.6, 1.4), V(-30, 14, -33), C(255, 240, 200), Enum.Material.Neon, { Light = { Range = 18, Brightness = 0.9 } }))
-- Tall storage shelves on the right wall (boxes on them are real clutter).
Kit.shelves(F, "Storage", 1, -20, 4, 16, 4, { 4, 8, 12 }, metal, metalDark)
-- Bike rack and bikes (looks only) in the back right.
add(deco("BikeRack", V(10, 1, 1), V(24, 0.5, -33.5), metalDark, Enum.Material.Metal))
for i = 0, 2 do
	add(deco("BikeFrame", V(0.4, 3, 5), V(20 + i * 4, 2.5, -32), C(220, 60, 60), Enum.Material.Metal))
end
-- Chest freezer.
add(solid("Freezer", V(9, 3.4, 5), V(38.5, 1.7, 8), C(235, 240, 245), Enum.Material.SmoothPlastic))
-- Light strips and an old poster.
add(deco("PosterCar", V(0.2, 6, 8), V(-44.6, 16, 28), C(60, 60, 70)))
add(deco("PosterCarInner", V(0.1, 5, 7), V(-44.4, 16, 28), C(255, 120, 40)))
add(deco("OilStain", V(6, 0.05, 8), V(0, 0.03, -14), C(70, 70, 75)))
Kit.door(F, C(120, 120, 130), C(210, 210, 215))
Room.Furniture = F

-- ===== Clutter =====
local Mix = {
	Tools = { Hammer_A = 4, Wrench_A = 4, Screwdriver_A = 4, TapeRoll_A = 3, GardenHose_A = 1, Cable_A = 2, PaintCan_A = 1, OilyRag_A = 2 },
	Bench = { Hammer_A = 3, Wrench_A = 3, Screwdriver_A = 3, TapeRoll_A = 2, OilyRag_A = 2, Can_A = 1, Cup_A = 1, Paper_A = 1 },
	Boxes = { CardboardBox_A = 5, CardboardBox_B = 3, HeavyBox_A = 1, StorageBin_A = 2, OldToolbox_A = 1, Basket_A = 1 },
	ShelfBoxes = { CardboardBox_A = 3, Book_B = 1, PaintCan_A = 1 },
	Sports = { Helmet_A = 3, Skateboard_A = 2, BaseballBat_A = 2, SoccerBall_A = 3, Basketball_A = 2, Shoe_A = 2, BikeWheel_A = 1 },
	Paint = { PaintCan_A = 5, OilyRag_A = 3, TapeRoll_A = 2, Paper_A = 2, Bottle_A = 2, Can_A = 2 },
	GarageFloor = { CarTire_A = 2, BikeWheel_A = 1, CardboardBox_A = 3, CardboardBox_B = 1, OldToolbox_A = 1, PaintCan_A = 2, GardenHose_A = 1, Hammer_A = 1, Wrench_A = 1, Helmet_A = 1, OilyRag_A = 2, Bottle_A = 2, StorageBin_A = 1 },
	CarSide = { OilyRag_A = 4, Wrench_A = 2, Screwdriver_A = 2, TapeRoll_A = 1, CarTire_A = 1, PaintCan_A = 1, Bottle_A = 2, Can_A = 2 },
	Freezer = { Can_A = 3, Bottle_A = 3, PizzaBox_A = 2, CardboardBox_A = 1, SoccerBall_A = 1, OilyRag_A = 1 },
	Scatter = { Screwdriver_A = 3, OilyRag_A = 4, TapeRoll_A = 2, Can_A = 2, Paper_A = 2, Bottle_A = 2, Wrench_A = 1 },
	Carpet = { OilyRag_A = 4, PizzaBox_A = 3, Paper_A = 3, CardboardBox_A = 1, Skateboard_A = 1, Magazine_A = 2, BikeWheel_A = 1, GardenHose_A = 1, Blanket_A = 1 },
}

local heap, row, carpet = Kit.Piles(Mix)

Room.Piles = {
	heap("Bench_Top", "Workbench", "Bench", V(-30, 3.4, -32), V2(17, 4.4), 45, 2.8),
	heap("Bench_Floor", "Workbench", "Tools", V(-30, 0, -25), V2(12, 6), 50, 5),
	heap("Door_Pile", "GarageDoor", "GarageFloor", V(-12, 0, -29), V2(7, 8), 45, 5),
	heap("ToolWall_A", "ToolWall", "Tools", V(-39, 0, -10), V2(8, 8), 50, 5),
	heap("ToolWall_B", "ToolWall", "GarageFloor", V(-39, 0, 0), V2(8, 7), 45, 5.5),
	heap("Car_Left", "Car", "CarSide", V(-8, 0, -14), V2(5, 14), 50, 4.5),
	heap("Car_Right", "Car", "CarSide", V(8, 0, -14), V2(5, 14), 50, 4.5),
	heap("Car_Front", "Car", "GarageFloor", V(0, 0, -3), V2(12, 5), 45, 5),
	heap("Car_Roof", "Car", "Freezer", V(0, 6.8, -15), V2(7, 7), 20, 1.5),
	heap("Shelf_AvalancheA", "Shelves", "Boxes", V(37, 0, -15), V2(7, 7), 50, 4),
	heap("Shelf_AvalancheB", "Shelves", "Boxes", V(37, 0, -3), V2(7, 7), 50, 4),
	heap("Bikes_Floor", "BikeRack", "Sports", V(24, 0, -26), V2(10, 6), 45, 5),
	heap("Freezer_Top", "Freezer", "Freezer", V(38.5, 3.4, 8), V2(8.4, 4.4), 25, 2),
	heap("Paint_Crate", "PaintCorner", "Paint", V(-36, 0, 27), V2(11, 8), 75, 6),
	heap("Paint_Side", "PaintCorner", "Paint", V(-27, 0, 20), V2(6, 6), 35, 4),
	heap("Sports_Crate", "SportsCorner", "Sports", V(36, 0, 26), V2(11, 8), 75, 6),
	heap("Sports_Side", "SportsCorner", "Sports", V(26, 0, 24), V2(5, 5), 30, 4),
	heap("Junk_Box", "LeftFloor", "GarageFloor", V(-14, 0, 10), V2(8, 8), 60, 6),
	heap("Left_A", "LeftFloor", "Tools", V(-25, 0, 6), V2(6, 8), 40, 5),
	heap("Center_Main", "CenterFloor", "GarageFloor", V(2, 0, 11), V2(10, 10), 70, 5.5),
	heap("Center_B", "CenterFloor", "Sports", V(11, 0, 20), V2(6, 6), 34, 4),
	heap("Center_C", "CenterFloor", "Tools", V(-6, 0, 21), V2(6, 6), 34, 4),
	heap("Right_A", "RightFloor", "GarageFloor", V(20, 0, -6), V2(8, 8), 45, 5),
	heap("Right_B", "RightFloor", "Boxes", V(20, 0, 5), V2(6, 6), 34, 4),
	heap("Scatter_Mid", "CenterFloor", "Scatter", V(0, 0, 8), V2(36, 20), 90, 1.2),
	heap("Scatter_Back", "Car", "Scatter", V(0, 0, -27), V2(20, 6), 40, 1.2),
	heap("Scatter_Left", "ToolWall", "Scatter", V(-32, 0, 8), V2(8, 10), 45, 1.2),
	heap("Scatter_Right", "RightFloor", "Scatter", V(28, 0, -12), V2(8, 10), 45, 1.2),
	carpet("Carpet", "Carpet", V(0, 0, 0), V2(88, 68), 0.2, 1.8, {
		{ Center = V2(0, 31.5), Size = V2(6, 5) },
	}, 1.6),
	row("Storage_1", "Shelves", "ShelfBoxes", V(42.45, 0, -19.6), V(42.45, 0, 3.6), 4, 42.45),
	row("Storage_2", "Shelves", "ShelfBoxes", V(42.45, 0, -19.6), V(42.45, 0, 3.6), 8, 42.45),
	row("Storage_3", "Shelves", "ShelfBoxes", V(42.45, 0, -19.6), V(42.45, 0, 3.6), 12, 42.45),
}

local socket = Kit.socket
Room.Sockets = {
	socket("G_Bench_01", "Bench_Top", -5, 0), socket("G_Bench_02", "Bench_Top", 0, 0.5), socket("G_Bench_03", "Bench_Top", 5, -0.5),
	socket("G_BenchF_01", "Bench_Floor", -3, 0), socket("G_BenchF_02", "Bench_Floor", 3, 1), socket("G_BenchF_03", "Bench_Floor", 0, -1.5),
	socket("G_Door_01", "Door_Pile", 0, 0), socket("G_Door_02", "Door_Pile", 1.5, 2),
	socket("G_ToolA_01", "ToolWall_A", 0, 0), socket("G_ToolA_02", "ToolWall_A", -2, 2), socket("G_ToolA_03", "ToolWall_A", 2, -2),
	socket("G_ToolB_01", "ToolWall_B", 0, 0), socket("G_ToolB_02", "ToolWall_B", 1.5, -2),
	-- Behind the car's wheels, under rags.
	socket("G_CarL_01", "Car_Left", 0, -5), socket("G_CarL_02", "Car_Left", 0, 0), socket("G_CarL_03", "Car_Left", 0.5, 5),
	socket("G_CarR_01", "Car_Right", 0, -5), socket("G_CarR_02", "Car_Right", 0, 0), socket("G_CarR_03", "Car_Right", -0.5, 5),
	socket("G_CarF_01", "Car_Front", -3, 0), socket("G_CarF_02", "Car_Front", 3, 0.5),
	socket("G_Roof_01", "Car_Roof", 0, 0),
	-- At the base of a tall shelf (the box avalanche).
	socket("G_ShelfA_01", "Shelf_AvalancheA", 0, 0, 3), socket("G_ShelfA_02", "Shelf_AvalancheA", -2, 2, 3),
	socket("G_ShelfB_01", "Shelf_AvalancheB", 0, 0, 3), socket("G_ShelfB_02", "Shelf_AvalancheB", -2, -2, 3),
	socket("G_Bikes_01", "Bikes_Floor", -3, 0), socket("G_Bikes_02", "Bikes_Floor", 3, 0.5),
	socket("G_Freezer_01", "Freezer_Top", -2, 0), socket("G_Freezer_02", "Freezer_Top", 2, 0.5),
	socket("G_Paint_01", "Paint_Crate", -2.5, 0.5, 3), socket("G_Paint_02", "Paint_Crate", 2.5, -1, 3), socket("G_Paint_03", "Paint_Crate", 0, 2, 3),
	socket("G_PaintS_01", "Paint_Side", 0, 0), socket("G_PaintS_02", "Paint_Side", 1.5, 1.5),
	-- Inside the sports-corner pile.
	socket("G_Sports_01", "Sports_Crate", -2.5, 0.5, 3), socket("G_Sports_02", "Sports_Crate", 2.5, -1, 3), socket("G_Sports_03", "Sports_Crate", 0, 2, 3),
	socket("G_SportsS_01", "Sports_Side", 0, 0),
	socket("G_Junk_01", "Junk_Box", 0, 0, 3), socket("G_Junk_02", "Junk_Box", -2, 2, 3), socket("G_Junk_03", "Junk_Box", 2, -2, 3),
	socket("G_Left_01", "Left_A", 0, 0), socket("G_Left_02", "Left_A", 1, 2.5),
	socket("G_Center_01", "Center_Main", -2, -2, 1), socket("G_Center_02", "Center_Main", 2.5, 2, 1), socket("G_Center_03", "Center_Main", 3, -3, 1),
	socket("G_CenterB_01", "Center_B", 0, 0, 1), socket("G_CenterC_01", "Center_C", 0, 0, 1),
	socket("G_Right_01", "Right_A", 0, 1), socket("G_Right_02", "Right_A", -2, -2),
	socket("G_RightB_01", "Right_B", 0, 0), socket("G_RightB_02", "Right_B", 1.5, -1.5),
}

return Room
