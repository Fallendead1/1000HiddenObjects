--[[
	ROOM #002 - THE BUSY KITCHEN
	The morning after a big family party. Grandma took her ring off to bake and now it's
	somewhere under the dishes.
	Room-local studs: origin = floor centre at y = 0, X [-45, 45], Z [-35, 35], door on +Z.
	Counters run along the back wall (sink, stove), the fridge and a walk-in pantry are on the
	left, the dining table and breakfast nook on the right, the island in the middle. Plate
	towers on the island clatter down when a plate near the bottom is pulled.
]]

local Kit = require(script.Parent.Kit)

local C = Color3.fromRGB
local V = Vector3.new
local V2 = Vector2.new
local solid, deco = Kit.solid, Kit.deco

local Room = {
	Id = 2,
	DisplayNumber = "002",
	Name = "The Busy Kitchen",
	ObjectPrefix = "Kitchen",

	TargetId = "GrandmasRing",
	TargetName = "Diamond Ring", -- "Find the Diamond Ring"; the album calls it Grandma's Diamond Ring

	MinimumTargetSockets = 30,
	SocketBlockerRadius = 1.4,
	RequiredBlockerDisplacement = 1.4,
	ExitDoor = "Door",
	LayoutVariants = { 1 },

	-- Kitchen things are small: fewer per heap and a lighter carpet keep it near 1,800 bodies.
	CountMultiplier = 1.6,
	ChunkFraction = 0.28,
	ChunkContents = { 5, 8 },
	FloorHeapHeightBonus = 4,
	HardMode = { ChunkFraction = 0.5, ChunkContents = { 12, 16 } },
	TreasureKeys = { "Treasure_SilverSpoon", "Treasure_Coin", "Treasure_Watch", "Treasure_Phone" },

	Size = V(90, 26, 70),
	SpawnPosition = V(0, 3, 29),

	FloorColor = C(236, 232, 222),
	FloorMaterial = Enum.Material.SmoothPlastic,
	WallColor = C(170, 222, 200),
	LampColor = C(255, 248, 235),
}

Room.Regions = {
	{ Id = "Island", Name = "KITCHEN ISLAND", Center = V(-6, 5, -8), Size = V(22, 10, 12) },
	{ Id = "Sink", Name = "SINK", Center = V(-20, 5, -30), Size = V(30, 10, 10) },
	{ Id = "Stove", Name = "STOVE", Center = V(4, 5, -30), Size = V(18, 10, 10) },
	{ Id = "Fridge", Name = "FRIDGE CORNER", Center = V(-37, 6, -24), Size = V(16, 12, 20) },
	{ Id = "Pantry", Name = "PANTRY", Center = V(-37, 6, -3), Size = V(16, 12, 22) },
	{ Id = "Dining", Name = "DINING TABLE", Center = V(22, 4, -4), Size = V(20, 8, 20) },
	{ Id = "Nook", Name = "BREAKFAST NOOK", Center = V(36, 3, 14), Size = V(18, 6, 14) },
	{ Id = "Recycling", Name = "RECYCLING CORNER", Center = V(34, 3, 28), Size = V(22, 6, 14) },
	{ Id = "BackCounter", Name = "BACK COUNTER", Center = V(30, 5, -28), Size = V(22, 10, 14) },
	{ Id = "CenterFloor", Name = "CENTER FLOOR", Center = V(0, 3, 12), Size = V(26, 6, 22) },
	{ Id = "LeftFloor", Name = "LEFT FLOOR", Center = V(-24, 3, 14), Size = V(16, 6, 26) },
}

-- Colour zones (Shared/Utility/Zones): clues name one ("the TEAL zone: HAMPER CORNER"), a sign
-- hangs over each and the map in the corner draws them. Names never reuse a bin's word.
Room.Zones = {
	{ Id = "Fridge", Name = "FRIDGE CORNER", Short = "FRIDGE", Color = "Blue", Regions = { "Fridge", "Pantry" } },
	{ Id = "Sink", Name = "SINK & STOVE", Short = "SINK", Color = "Red", Regions = { "Sink", "Stove" } },
	{ Id = "Island", Name = "KITCHEN ISLAND", Short = "ISLAND", Color = "Yellow", Regions = { "Island" } },
	{ Id = "Dining", Name = "DINING TABLE", Short = "DINING", Color = "Green", Regions = { "Dining", "BackCounter" } },
	{ Id = "Nook", Name = "BREAKFAST NOOK", Short = "NOOK", Color = "Teal", Regions = { "Nook", "Recycling" } },
	{ Id = "Middle", Name = "MIDDLE", Color = "Orange", Regions = { "CenterFloor", "LeftFloor" } },
}

Room.SideSigns = {
	LEFT = { Z = 18, Width = 16, Landmarks = "FRIDGE · PANTRY" },
	RIGHT = { Z = -2, Width = 17, Landmarks = "DINING · NOOK · RECYCLING" },
}

Room.DepositBins = {
	{ Type = "DishRack", Center = V(-17.5, 0, 30), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Recycling", Center = V(17.5, 0, 30), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Pantry", Center = V(-33, 0, 24), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Trash", Center = V(14, 0, -16), Size = V(4.2, 2.8, 4.2) },
	{ Type = "Donation", Center = V(9, 0, 31), Size = V(6.5, 1.4, 5) },
}

Room.Containers = {
	-- The sink basin sits on the counter: its rim keeps the dirty dishes piled up.
	{ Id = "SinkBasin", Center = V(-20, 3.6, -32), Size = V(7.2, 1.4, 3.8), Color = C(200, 205, 215) },
	{ Id = "PantryCrate", Center = V(-30, 0, -4), Size = V(7.6, 3.4, 7.6), Color = C(196, 150, 100) },
	{ Id = "RecycleCrate", Center = V(36, 0, 28), Size = V(11.6, 3.4, 8.6), Color = C(70, 150, 230) },
}

-- ===== Furniture =====
local wood, woodDark = C(200, 160, 110), C(150, 110, 70)
local counterTop, cabinet = C(245, 245, 240), C(240, 232, 214)
local F = {}
local function add(f)
	table.insert(F, f)
end
-- Back counters: left run with the sink, the stove, a short run, then the back counter.
add(solid("CounterABase", V(30, 3.2, 5), V(-20, 1.6, -32), cabinet))
add(solid("CounterATop", V(30.5, 0.4, 5.5), V(-20, 3.4, -32), counterTop, Enum.Material.Marble))
add(solid("Stove", V(6, 3.6, 5), V(-2, 1.8, -32), C(60, 62, 70), Enum.Material.Metal))
for i, x in ipairs({ -3.4, -0.6 }) do
	for _, z in ipairs({ -33.2, -30.8 }) do
		add(deco("Burner" .. i, V(1.8, 0.08, 1.8), V(x, 3.64, z), C(30, 30, 34), Enum.Material.Metal))
	end
end
add(deco("StoveHood", V(8, 2, 4), V(-2, 12, -33), C(190, 190, 200), Enum.Material.Metal))
add(solid("CounterBBase", V(12, 3.2, 5), V(7, 1.6, -32), cabinet))
add(solid("CounterBTop", V(12.5, 0.4, 5.5), V(7, 3.4, -32), counterTop, Enum.Material.Marble))
add(solid("BackCounterBase", V(20, 3.2, 5), V(30, 1.6, -32), cabinet))
add(solid("BackCounterTop", V(20.5, 0.4, 5.5), V(30, 3.4, -32), counterTop, Enum.Material.Marble))
add(deco("UpperCabinetsA", V(30, 4, 2.4), V(-20, 11, -33.6), cabinet))
add(deco("UpperCabinetsB", V(12, 4, 2.4), V(7, 11, -33.6), cabinet))
add(deco("UpperCabinetsC", V(20, 4, 2.4), V(30, 11, -33.6), cabinet))
local glass = deco("Window", V(10, 6, 0.4), V(-20, 17, -34.6), C(200, 235, 255), Enum.Material.Glass, { Transparency = 0.35 })
add(glass)
add(deco("Faucet", V(0.4, 1.8, 0.4), V(-20, 4.5, -34), C(200, 200, 210), Enum.Material.Metal))
-- Fridge.
add(solid("Fridge", V(6, 11, 6), V(-41, 5.5, -30), C(225, 230, 235), Enum.Material.Metal))
add(deco("FridgeHandle", V(0.3, 4, 0.3), V(-38.2, 6, -27.8), C(150, 150, 160), Enum.Material.Metal))
-- The walk-in pantry: tall shelves against the left wall (the food on them is real clutter).
Kit.shelves(F, "Pantry", -1, -13, 5, 12, 3.2, { 3.2, 6.2, 9.2 }, wood, woodDark)
-- Kitchen island.
add(solid("IslandBase", V(18, 3.2, 8), V(-6, 1.6, -8), C(120, 170, 200)))
add(solid("IslandTop", V(19, 0.4, 9), V(-6, 3.4, -8), counterTop, Enum.Material.Marble))
-- Dining table (a closed block so nothing hides where hands can't reach) and chairs.
add(solid("DiningTable", V(14, 3.25, 8), V(22, 1.625, -4), wood, Enum.Material.Wood))
add(deco("Tablecloth", V(14.4, 0.06, 8.4), V(22, 3.28, -4), C(250, 250, 245), Enum.Material.Fabric))
for _, x in ipairs({ 17, 22, 27 }) do
	for _, z in ipairs({ -10, 2 }) do
		add(deco("ChairBack", V(3, 3.6, 0.5), V(x, 3.2, z + (z < 0 and -1.2 or 1.2)), woodDark, Enum.Material.Wood))
	end
end
-- Breakfast nook: table and bench by the right wall.
add(solid("NookTable", V(8, 3, 6), V(34, 1.5, 12), wood, Enum.Material.Wood))
add(solid("NookBench", V(3, 2, 10), V(42.5, 1, 12), C(230, 110, 90), Enum.Material.Fabric))
add(deco("NookBenchBack", V(0.8, 3, 10), V(44.2, 3.5, 12), C(230, 110, 90), Enum.Material.Fabric))
-- Decor: a clock, a fruit poster, checkered mats and lamps over the island.
add(deco("ClockFace", V(0.3, 3, 3), V(-34, 18, -34.6), C(250, 250, 250), nil, { Shape = Enum.PartType.Cylinder, Yaw = 90 }))
add(deco("PosterFruit", V(8, 6, 0.2), V(18, 14, -34.6), C(255, 160, 60)))
add(deco("MatA", V(10, 0.12, 6), V(-20, 0.06, -26), C(80, 150, 200), Enum.Material.Fabric))
add(deco("MatB", V(20, 0.12, 14), V(0, 0.06, 10), C(230, 120, 110), Enum.Material.Fabric))
for _, x in ipairs({ -12, -6, 0 }) do
	add(deco("PendantLamp", V(1.6, 1.2, 1.6), V(x, 14, -8), C(255, 230, 160), Enum.Material.Neon, { Light = { Range = 16, Brightness = 0.6 } }))
end
Kit.door(F, C(150, 100, 60), C(250, 250, 250))
Room.Furniture = F

-- ===== Clutter =====
local Mix = {
	Dishes = { Plate_A = 6, Bowl_A = 4, Mug_A = 4, Cup_A = 3, Fork_A = 3, Spoon_A = 3, FryingPan_A = 1, CookingPot_A = 1, CuttingBoard_A = 1 },
	PlateStack = { Plate_A = 10, Bowl_A = 2 },
	Food = { CerealBox_A = 4, Apple_A = 3, Banana_A = 3, Bread_A = 3, EggCarton_A = 2, MilkJug_A = 1, Can_A = 2, GroceryBag_A = 1 },
	PantryShelf = { CerealBox_A = 4, Bread_A = 2, EggCarton_A = 1 },
	Recycle = { Bottle_A = 4, Can_A = 4, PizzaBox_A = 2, MilkJug_A = 2, GroceryBag_A = 2, Paper_A = 3, Magazine_A = 2 },
	Counter = { Plate_A = 3, Bowl_A = 2, Mug_A = 3, Cup_A = 2, Spoon_A = 2, Fork_A = 2, Wrapper_A = 2, Apple_A = 1, Banana_A = 1, Bread_A = 1, CuttingBoard_A = 1, Toaster_A = 1, Blender_A = 1 },
	KitchenFloor = { GroceryBag_A = 3, CardboardBox_A = 2, Microwave_A = 1, Toaster_A = 1, CookingPot_A = 2, FryingPan_A = 2, MilkJug_A = 2, Bottle_A = 2, CerealBox_A = 2, Wrapper_A = 2, Plate_A = 2, PizzaBox_A = 1, CardboardBox_B = 1 },
	Scatter = { Wrapper_A = 4, Fork_A = 3, Spoon_A = 3, Paper_A = 2, Can_A = 2, Apple_A = 2, Banana_A = 2, Cup_A = 2 },
	Carpet = { PizzaBox_A = 4, Magazine_A = 3, CuttingBoard_A = 3, Paper_A = 2, Plate_A = 1, GroceryBag_A = 1, FryingPan_A = 2, Blanket_A = 2 },
}

local heap, row, carpet = Kit.Piles(Mix)

Room.Piles = {
	-- The plate towers go first so the rest of the island top fills around them.
	heap("Island_TowerA", "Island", "PlateStack", V(-11, 3.6, -8), V2(2, 2), 24, 5.5),
	heap("Island_TowerB", "Island", "PlateStack", V(-1, 3.6, -9), V2(2, 2), 24, 5.5),
	heap("Island_Top", "Island", "Counter", V(-6, 3.6, -8), V2(17, 7), 60, 2.5),
	heap("Sink_Basin", "Sink", "Dishes", V(-20, 3.6, -32), V2(6.6, 3.2), 40, 3.2),
	heap("CounterA_Left", "Sink", "Counter", V(-30, 3.6, -32), V2(8, 4.4), 30, 2.5),
	heap("CounterA_Right", "Sink", "Counter", V(-10, 3.6, -32), V2(8, 4.4), 30, 2.5),
	heap("Stove_Top", "Stove", "Dishes", V(-2, 3.6, -32), V2(5.4, 4.4), 18, 2.5),
	heap("CounterB_Top", "Stove", "Counter", V(7, 3.6, -32), V2(11, 4.4), 35, 2.5),
	heap("BackCounter_Top", "BackCounter", "Counter", V(30, 3.6, -32), V2(19, 4.4), 50, 2.5),
	heap("Sink_Floor", "Sink", "KitchenFloor", V(-22, 0, -24), V2(10, 7), 50, 5),
	heap("Stove_Floor", "Stove", "Dishes", V(4, 0, -24), V2(8, 7), 40, 4.5),
	heap("Fridge_Heap", "Fridge", "KitchenFloor", V(-38, 0, -20), V2(8, 8), 55, 6),
	heap("Fridge_Side", "Fridge", "Food", V(-33, 0, -26), V2(5, 5), 30, 4.5),
	heap("Pantry_FloorA", "Pantry", "Food", V(-37, 0, -9), V2(6, 7), 50, 5),
	heap("Pantry_FloorB", "Pantry", "Food", V(-37, 0, 2), V2(6, 6), 45, 5),
	heap("Pantry_Crate", "Pantry", "Food", V(-30, 0, -4), V2(7, 7), 60, 6),
	heap("Island_FloorL", "Island", "KitchenFloor", V(-20, 0, -8), V2(6, 8), 35, 4.5),
	heap("Island_FloorR", "Island", "Dishes", V(7, 0, -8), V2(6, 8), 35, 4.5),
	heap("Island_Front", "Island", "KitchenFloor", V(-6, 0, -1), V2(12, 5), 40, 4.5),
	heap("Dining_Top", "Dining", "Counter", V(22, 3.25, -4), V2(12.5, 6.5), 50, 3),
	heap("Dining_FloorN", "Dining", "KitchenFloor", V(24, 0, -13), V2(10, 4), 35, 4.5),
	heap("Dining_FloorS", "Dining", "KitchenFloor", V(22, 0, 4.5), V2(12, 4), 40, 4.5),
	heap("Nook_Top", "Nook", "Counter", V(34, 3, 12), V2(7, 5), 25, 2.5),
	heap("Nook_Floor", "Nook", "Food", V(34, 0, 19), V2(8, 5), 35, 4.5),
	heap("Recycling_Main", "Recycling", "Recycle", V(36, 0, 28), V2(11, 8), 70, 6),
	heap("Recycling_B", "Recycling", "Recycle", V(26, 0, 23), V2(6, 5), 35, 4.5),
	heap("BackCounter_Floor", "BackCounter", "KitchenFloor", V(30, 0, -24), V2(12, 6), 45, 5),
	heap("Center_Main", "CenterFloor", "KitchenFloor", V(0, 0, 10), V2(10, 10), 70, 5.5),
	heap("Center_B", "CenterFloor", "Dishes", V(10, 0, 16), V2(7, 7), 34, 4),
	heap("Center_C", "CenterFloor", "Recycle", V(-9, 0, 15), V2(7, 7), 34, 4),
	heap("Left_A", "LeftFloor", "KitchenFloor", V(-22, 0, 9), V2(8, 8), 42, 5),
	heap("Left_B", "LeftFloor", "Food", V(-23, 0, 19), V2(6, 5), 34, 4),
	heap("Mound_A", "CenterFloor", "Dishes", V(-8, 0, 22), V2(6, 5), 30, 4),
	heap("Mound_B", "CenterFloor", "Recycle", V(9, 0, 22), V2(6, 5), 30, 4),
	heap("Scatter_Mid", "CenterFloor", "Scatter", V(0, 0, 6), V2(36, 22), 90, 1.2),
	heap("Scatter_Back", "Stove", "Scatter", V(-6, 0, -19), V2(30, 6), 40, 1.2),
	heap("Scatter_Left", "LeftFloor", "Scatter", V(-26, 0, -14), V2(8, 12), 45, 1.2),
	heap("Scatter_Right", "Dining", "Scatter", V(32, 0, -12), V2(10, 8), 45, 1.2),
	carpet("Carpet", "Carpet", V(0, 0, 0), V2(88, 68), 0.18, 1.8, {
		{ Center = V2(0, 31.5), Size = V2(6, 5) },
	}, 1.6),
	row("Pantry_Shelf1", "Pantry", "PantryShelf", V(-42.9, 0, -12.6), V(-42.9, 0, 4.6), 3.2, -42.9),
	row("Pantry_Shelf2", "Pantry", "PantryShelf", V(-42.9, 0, -12.6), V(-42.9, 0, 4.6), 6.2, -42.9),
	row("Pantry_Shelf3", "Pantry", "PantryShelf", V(-42.9, 0, -12.6), V(-42.9, 0, 4.6), 9.2, -42.9),
}

local socket = Kit.socket
Room.Sockets = {
	socket("K_Tower_01", "Island_TowerA", 0, 0, 3), socket("K_Tower_02", "Island_TowerB", 0, 0, 3),
	socket("K_Island_01", "Island_Top", -5, 1), socket("K_Island_02", "Island_Top", 4, 1.5), socket("K_Island_03", "Island_Top", 1, -2),
	socket("K_Sink_01", "Sink_Basin", 0, 0, 3), socket("K_Sink_02", "Sink_Basin", -2, 0.5, 3), socket("K_Sink_03", "Sink_Basin", 2, -0.5, 3),
	socket("K_CounterA_01", "CounterA_Left", 0, 0), socket("K_CounterA_02", "CounterA_Right", 1, 0),
	socket("K_Stove_01", "Stove_Top", 0, 0),
	socket("K_CounterB_01", "CounterB_Top", -3, 0), socket("K_CounterB_02", "CounterB_Top", 3, 0),
	socket("K_Back_01", "BackCounter_Top", -5, 0), socket("K_Back_02", "BackCounter_Top", 5, 0),
	socket("K_SinkFloor_01", "Sink_Floor", 0, 0), socket("K_SinkFloor_02", "Sink_Floor", -3, 2), socket("K_SinkFloor_03", "Sink_Floor", 3, -2),
	socket("K_StoveFloor_01", "Stove_Floor", 0, 0), socket("K_StoveFloor_02", "Stove_Floor", 2, 2),
	socket("K_Fridge_01", "Fridge_Heap", 0, 0), socket("K_Fridge_02", "Fridge_Heap", -2, 2), socket("K_Fridge_03", "Fridge_Heap", 2, -2),
	socket("K_FridgeSide_01", "Fridge_Side", 0, 0),
	socket("K_Pantry_01", "Pantry_FloorA", 0, 0), socket("K_Pantry_02", "Pantry_FloorA", 1, -2),
	socket("K_Pantry_03", "Pantry_FloorB", 0, 0), socket("K_Pantry_04", "Pantry_FloorB", -1, 2),
	socket("K_Crate_01", "Pantry_Crate", 0, 0, 3), socket("K_Crate_02", "Pantry_Crate", -2, 2, 3), socket("K_Crate_03", "Pantry_Crate", 2, -2, 3),
	socket("K_IslandL_01", "Island_FloorL", 0, 0), socket("K_IslandL_02", "Island_FloorL", 1, 2),
	socket("K_IslandR_01", "Island_FloorR", 0, 0), socket("K_IslandR_02", "Island_FloorR", -1, -2),
	socket("K_IslandF_01", "Island_Front", -3, 0), socket("K_IslandF_02", "Island_Front", 3, 0),
	socket("K_Dining_01", "Dining_Top", -3, -1), socket("K_Dining_02", "Dining_Top", 3, 1), socket("K_Dining_03", "Dining_Top", 0, 0),
	socket("K_DiningN_01", "Dining_FloorN", -2, 0), socket("K_DiningN_02", "Dining_FloorN", 3, 0),
	socket("K_DiningS_01", "Dining_FloorS", -3, 0), socket("K_DiningS_02", "Dining_FloorS", 3, 0.5),
	socket("K_Nook_01", "Nook_Top", 0, 0),
	socket("K_NookFloor_01", "Nook_Floor", 0, 0), socket("K_NookFloor_02", "Nook_Floor", 2, 1),
	socket("K_Recycle_01", "Recycling_Main", -2, 0, 3), socket("K_Recycle_02", "Recycling_Main", 2.5, -1, 3), socket("K_Recycle_03", "Recycling_Main", 0, 2, 3),
	socket("K_RecycleB_01", "Recycling_B", 0, 0), socket("K_RecycleB_02", "Recycling_B", 1.5, 1),
	socket("K_BackFloor_01", "BackCounter_Floor", -3, 0), socket("K_BackFloor_02", "BackCounter_Floor", 3, 0),
	socket("K_Center_01", "Center_Main", -2, -2, 1), socket("K_Center_02", "Center_Main", 2.5, 2, 1), socket("K_Center_03", "Center_Main", 3, -3, 1),
	socket("K_CenterB_01", "Center_B", 0, 0, 1), socket("K_CenterC_01", "Center_C", 0, 0, 1),
	socket("K_Left_01", "Left_A", 0, -1), socket("K_Left_02", "Left_A", 2, 2.5),
	socket("K_LeftB_01", "Left_B", 0, 0),
	socket("K_Mound_01", "Mound_A", 0, 0), socket("K_Mound_02", "Mound_B", 0, 0),
}

return Room
