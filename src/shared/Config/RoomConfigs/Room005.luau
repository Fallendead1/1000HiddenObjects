--[[
	ROOM #005 - THE GIANT ATTIC (MEGA ROOM)
	Great-Grandpa's Treasure Map is somewhere up here. Two levels under a sloped roof: the
	ground floor, and a loft along the back reached by ramps on both side walls. Old trunks
	on both floors are the deepest digs.
	Room-local studs: origin = floor centre at y = 0, X [-55, 55], Z [-43, 43], door on +Z.
	The loft floor is at y = 10.5 (z -43 to -17), with a rail along its front edge.
	Mega rooms keep the same physics budget as a standard room: the depth comes from more and
	fuller packed junk, not from more loose objects.
]]

local Kit = require(script.Parent.Kit)

local C = Color3.fromRGB
local V = Vector3.new
local V2 = Vector2.new
local solid, deco = Kit.solid, Kit.deco

local LOFT = 10.5 -- the loft floor's top

local Room = {
	Id = 5,
	DisplayNumber = "005",
	Name = "The Giant Attic",
	ObjectPrefix = "Attic",
	Mega = true,
	-- The first clear of a Mega room hatches a guaranteed Rare-or-better egg (PetConfig.Eggs).
	FirstClearEgg = "Attic",
	FirstClearTitle = "Attic Explorer",

	TargetId = "TreasureMap",
	TargetName = "Treasure Map",

	MinimumTargetSockets = 40,
	SocketBlockerRadius = 1.4,
	RequiredBlockerDisplacement = 1.4,
	-- A Mega room is about twice as big: its clues come slower than GameConfig.ClueTimes.
	ClueTimes = { 90, 210, 330, 450, 570 },
	ExitDoor = "Door",
	LayoutVariants = { 1 },

	CountMultiplier = 1.7,
	ChunkFraction = 0.45,
	ChunkContents = { 10, 14 },
	FloorHeapHeightBonus = 4,
	HardMode = { ChunkFraction = 0.6, ChunkContents = { 12, 16 } },
	TreasureKeys = { "Treasure_PocketWatch", "Treasure_OldCoin", "Treasure_Coin", "Treasure_Trophy" },

	Size = V(110, 32, 86),
	SpawnPosition = V(0, 3, 37),

	FloorColor = C(150, 110, 75),
	WallColor = C(175, 140, 105),
	WallMaterial = Enum.Material.WoodPlanks,
	CeilingColor = C(140, 105, 75),
	LampColor = C(255, 215, 160),
	LampBrightness = 0.55,
}

Room.Regions = {
	{ Id = "LoftLeft", Name = "LOFT LEFT", Center = V(-38, LOFT + 4, -30), Size = V(34, 8, 26) },
	{ Id = "LoftCenter", Name = "LOFT MIDDLE", Center = V(0, LOFT + 4, -30), Size = V(40, 8, 26) },
	{ Id = "LoftRight", Name = "LOFT RIGHT", Center = V(38, LOFT + 4, -30), Size = V(34, 8, 26) },
	{ Id = "UnderLoft", Name = "UNDER THE LOFT", Center = V(0, 5, -30), Size = V(110, 10, 26) },
	{ Id = "TrunkLeft", Name = "OLD TRUNK (LEFT)", Center = V(-30, 3, 4), Size = V(16, 6, 12) },
	{ Id = "TrunkRight", Name = "OLD TRUNK (RIGHT)", Center = V(26, 3, 10), Size = V(16, 6, 12) },
	{ Id = "Wardrobe", Name = "WARDROBE", Center = V(-45, 5, 20), Size = V(18, 10, 16) },
	{ Id = "CoveredSofa", Name = "COVERED SOFA", Center = V(0, 3, 12), Size = V(22, 6, 14) },
	{ Id = "Dollhouse", Name = "DOLLHOUSE", Center = V(44, 4, 26), Size = V(20, 8, 18) },
	{ Id = "FrontLeft", Name = "FRONT LEFT", Center = V(-30, 3, 30), Size = V(20, 6, 14) },
	{ Id = "FrontCenter", Name = "FRONT", Center = V(0, 3, 27), Size = V(24, 6, 14) },
	{ Id = "LeftFloor", Name = "LEFT FLOOR", Center = V(-38, 3, -6), Size = V(16, 6, 16) },
	{ Id = "RightFloor", Name = "RIGHT FLOOR", Center = V(38, 3, -4), Size = V(16, 6, 16) },
}

Room.HintAreas = {
	{ Label = "UPSTAIRS: THE LOFT", Regions = { "LoftLeft", "LoftCenter", "LoftRight" } },
	{ Label = "UNDER THE LOFT", Regions = { "UnderLoft" } },
	{ Label = "LEFT: TRUNK / WARDROBE / FRONT LEFT", Regions = { "TrunkLeft", "Wardrobe", "FrontLeft", "LeftFloor" } },
	{ Label = "RIGHT: DOLLHOUSE / TRUNK / SOFA / FRONT", Regions = { "Dollhouse", "TrunkRight", "CoveredSofa", "FrontCenter", "RightFloor" } },
}

Room.SideSigns = {
	LEFT = { Z = 26, Width = 16, Landmarks = "TRUNK · WARDROBE" },
	RIGHT = { Z = 12, Width = 16, Landmarks = "DOLLHOUSE · TRUNK" },
}

Room.DepositBins = {
	{ Type = "Laundry", Center = V(-20, 0, 38), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Toys", Center = V(20, 0, 38), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Books", Center = V(38, 0, 16), Size = V(4.2, 2.4, 4.2) },
	{ Type = "Trash", Center = V(-12, 0, -10), Size = V(4.2, 2.8, 4.2) },
	{ Type = "Donation", Center = V(9, 0, 39), Size = V(6.5, 1.4, 5) },
	-- Upstairs, so loft treasures don't all have to come down the ramps.
	{ Type = "Keepsakes", Center = V(0, LOFT, -22), Size = V(5, 2.4, 4.2) },
}

-- Old trunks you dig down into, on both floors.
Room.Containers = {
	{ Id = "TrunkLeft", Center = V(-30, 0, 4), Size = V(8.6, 3.4, 5.6), Color = C(120, 75, 40) },
	{ Id = "TrunkRight", Center = V(26, 0, 10), Size = V(8.6, 3.4, 5.6), Color = C(120, 75, 40) },
	{ Id = "TrunkLoftL", Center = V(-28, LOFT, -32), Size = V(8.6, 3.4, 5.6), Color = C(100, 65, 35) },
	{ Id = "TrunkLoftR", Center = V(26, LOFT, -34), Size = V(8.6, 3.4, 5.6), Color = C(100, 65, 35) },
}

-- ===== Furniture =====
local wood, woodDark, beam = C(160, 115, 75), C(115, 80, 50), C(95, 65, 40)
local F = {}
local function add(f)
	table.insert(F, f)
end
-- The loft: floor, supports, front rail, ramps up both side walls, and lights underneath.
add(solid("LoftFloor", V(110, 1, 26), V(0, LOFT - 0.5, -30), wood, Enum.Material.WoodPlanks))
for _, x in ipairs({ -30, 0, 30 }) do
	add(solid("LoftPost", V(1.5, LOFT - 1, 1.5), V(x, (LOFT - 1) / 2, -18), beam, Enum.Material.Wood))
	add(deco("UnderLoftLamp", V(3, 0.3, 3), V(x, LOFT - 1.15, -30), C(255, 220, 160), Enum.Material.Neon, { Light = { Range = 20, Brightness = 0.8 } }))
end
add(solid("LoftRail", V(86, 1.4, 0.6), V(0, LOFT + 0.7, -17.3), beam, Enum.Material.Wood))
for _, side in ipairs({ -1, 1 }) do
	add(solid("Ramp", V(8, LOFT, 24), V(side * 51, LOFT / 2, -5), wood, Enum.Material.WoodPlanks, { Shape = Enum.PartType.Wedge, Yaw = 180 }))
	add(deco("RampRail", V(0.4, 1.4, 24), V(side * 46.8, LOFT / 2 + 1, -5), beam, Enum.Material.Wood))
end
-- Roof beams and a dusty window with light shafts over the loft.
for i = -2, 2 do
	add(deco("RoofBeam", V(1.2, 1.2, 86), V(i * 22, 30.5, 0), beam, Enum.Material.Wood))
end
add(deco("AtticWindow", V(10, 7, 0.4), V(0, 22, -42.6), C(220, 235, 255), Enum.Material.Glass, { Transparency = 0.3, Light = { Range = 30, Brightness = 1.1, Color = C(255, 240, 210) } }))
add(deco("LightShaft", V(8, 0.2, 22), V(0, 18, -33), C(255, 240, 200), Enum.Material.Neon, { Transparency = 0.85 }))
-- Ground floor: wardrobe, the sheet-covered sofa, the dollhouse and a rocking chair.
add(solid("Wardrobe", V(4, 12, 10), V(-52.5, 6, 20), woodDark, Enum.Material.Wood))
add(deco("WardrobeDoor", V(0.3, 10, 4.4), V(-50.4, 6, 17.6), wood, Enum.Material.Wood))
add(solid("CoveredSofa", V(10, 4, 6), V(0, 2, 12), C(230, 225, 210), Enum.Material.Fabric))
add(solid("Dollhouse", V(8, 6, 5), V(48, 3, 30), C(240, 200, 210), Enum.Material.SmoothPlastic))
add(deco("DollhouseRoof", V(8.6, 0.4, 5.6), V(48, 6.3, 30), C(200, 90, 100)))
add(deco("RockingChair", V(3, 4, 3.6), V(-44, 2, -38), woodDark, Enum.Material.Wood))
add(deco("DressForm", V(1.6, 5, 1.6), V(-50, 2.5, 6), C(220, 200, 180), Enum.Material.Fabric))
add(deco("Cobweb", V(6, 6, 0.1), V(-52, 26, -42.6), C(230, 230, 235), nil, { Transparency = 0.6 }))
add(deco("CobwebB", V(6, 6, 0.1), V(52, 26, -42.6), C(230, 230, 235), nil, { Transparency = 0.6 }))
Kit.door(F, C(120, 85, 55), C(200, 170, 130), 43)
Room.Furniture = F

-- ===== Clutter =====
local Mix = {
	Keepsakes = { OldLetter_A = 4, PhotoAlbum_A = 3, Lantern_A = 2, Book_A = 2, Magazine_A = 2, Paper_A = 2 },
	Boxes = { HolidayBox_A = 3, Suitcase_A = 2, CardboardBox_A = 4, CardboardBox_B = 2, StorageBin_A = 1, HeavyBox_A = 1 },
	Linens = { Quilt_A = 3, Blanket_A = 3, Pillow_A = 2, Shirt_A = 3, Hoodie_A = 2, Sock_A = 2, Shoe_A = 1 },
	OldToys = { RockingHorse_A = 1, TeddyBear_A = 2, Plush_A = 3, ToyBlock_A = 3, ToyCar_A = 2, ToyDuck_A = 1, BoardGame_A = 1, PuzzlePiece_A = 2 },
	Trunk = { OldLetter_A = 3, PhotoAlbum_A = 2, Quilt_A = 2, Lantern_A = 1, TeddyBear_A = 1, Book_B = 2, Shirt_A = 2, ToyCar_A = 1 },
	AtticFloor = { HolidayBox_A = 2, Suitcase_A = 1, CardboardBox_A = 3, Quilt_A = 2, OldLetter_A = 2, PhotoAlbum_A = 1, Lantern_A = 1, TeddyBear_A = 1, RockingHorse_A = 1, Book_A = 2, Blanket_A = 1, Shoe_A = 1, PictureFrame_A = 1 },
	Scatter = { OldLetter_A = 3, Sock_A = 2, PuzzlePiece_A = 2, Paper_A = 3, ToyBlock_A = 2, Magazine_A = 2 },
	Carpet = { Quilt_A = 2, Blanket_A = 3, Magazine_A = 3, OldLetter_A = 3, PizzaBox_A = 1, Paper_A = 2, Shirt_A = 2, BoardGame_A = 1 },
}

local heap, row, carpet = Kit.Piles(Mix)
local _ = row

Room.Piles = {
	-- Ground floor.
	heap("TrunkL_Inside", "TrunkLeft", "Trunk", V(-30, 0, 4), V2(8, 5), 60, 3),
	heap("TrunkR_Inside", "TrunkRight", "Trunk", V(26, 0, 10), V2(8, 5), 60, 3),
	heap("TrunkL_Around", "TrunkLeft", "AtticFloor", V(-30, 0, 11), V2(12, 5), 40, 4.5),
	heap("TrunkR_Around", "TrunkRight", "AtticFloor", V(26, 0, 3), V2(12, 5), 40, 4.5),
	heap("Wardrobe_Front", "Wardrobe", "Linens", V(-45, 0, 20), V2(8, 10), 55, 5.5),
	heap("Sofa_Top", "CoveredSofa", "Linens", V(0, 4, 12), V2(9.4, 5.4), 30, 2.5),
	heap("Sofa_Left", "CoveredSofa", "AtticFloor", V(-9, 0, 12), V2(6, 8), 40, 5),
	heap("Sofa_Right", "CoveredSofa", "OldToys", V(9, 0, 12), V2(6, 8), 40, 5),
	heap("Doll_Main", "Dollhouse", "OldToys", V(40, 0, 24), V2(8, 8), 50, 5),
	heap("Doll_Top", "Dollhouse", "OldToys", V(48, 6.5, 30), V2(7, 4.4), 16, 1.8),
	heap("FrontLeft_A", "FrontLeft", "Boxes", V(-32, 0, 29), V2(10, 8), 60, 5.5),
	heap("Front_Center", "FrontCenter", "AtticFloor", V(0, 0, 25), V2(12, 7), 60, 5),
	heap("Left_Floor", "LeftFloor", "Linens", V(-38, 0, -6), V2(10, 10), 55, 5),
	heap("Right_Floor", "RightFloor", "Boxes", V(38, 0, -4), V2(10, 10), 55, 5),
	heap("Mound_Front", "FrontCenter", "Keepsakes", V(-12, 0, 30), V2(6, 5), 30, 4),
	heap("Mound_Right", "RightFloor", "OldToys", V(20, 0, 22), V2(6, 6), 30, 4),
	-- Under the loft (the loft floor is 10 above: floor heaps stay under 8 with the bonus).
	heap("Under_Left", "UnderLoft", "Boxes", V(-36, 0, -31), V2(12, 10), 60, 4),
	heap("Under_Center", "UnderLoft", "AtticFloor", V(0, 0, -33), V2(14, 10), 60, 4),
	heap("Under_Right", "UnderLoft", "Linens", V(36, 0, -31), V2(12, 10), 60, 4),
	-- The loft.
	heap("Loft_TrunkL", "LoftLeft", "Trunk", V(-28, LOFT, -32), V2(8, 5), 55, 3, true),
	heap("Loft_TrunkR", "LoftRight", "Trunk", V(26, LOFT, -34), V2(8, 5), 55, 3, true),
	heap("Loft_Left", "LoftLeft", "AtticFloor", V(-44, LOFT, -30), V2(10, 12), 60, 2, true),
	heap("Loft_Center", "LoftCenter", "Keepsakes", V(-7, LOFT, -36), V2(14, 8), 55, 1.5, true),
	heap("Loft_Boxes", "LoftCenter", "Boxes", V(9, LOFT, -32), V2(8, 8), 50, 3, true),
	heap("Loft_Right", "LoftRight", "OldToys", V(42, LOFT, -27), V2(10, 12), 60, 2, true),
	-- Scatter and carpets on both floors.
	heap("Scatter_Mid", "FrontCenter", "Scatter", V(0, 0, 16), V2(40, 26), 90, 1.2),
	heap("Scatter_Left", "LeftFloor", "Scatter", V(-40, 0, 6), V2(10, 14), 45, 1.2),
	heap("Scatter_Right", "RightFloor", "Scatter", V(38, 0, 6), V2(10, 12), 45, 1.2),
	heap("Scatter_Loft", "LoftCenter", "Scatter", V(0, LOFT, -26), V2(70, 8), 60, 1.2),
	carpet("Carpet", "Carpet", V(0, 0, 0), V2(108, 84), 0.12, 1.8, {
		{ Center = V2(0, 39.5), Size = V2(6, 5) },
	}, 1.6),
	carpet("LoftCarpet", "Carpet", V(0, LOFT, -30), V2(108, 25), 0.12, 1.6),
}

local socket = Kit.socket
Room.Sockets = {
	socket("A_TrunkL_01", "TrunkL_Inside", 0, 0, 3), socket("A_TrunkL_02", "TrunkL_Inside", -2.5, 1, 3), socket("A_TrunkL_03", "TrunkL_Inside", 2.5, -1, 3),
	socket("A_TrunkR_01", "TrunkR_Inside", 0, 0, 3), socket("A_TrunkR_02", "TrunkR_Inside", -2.5, -1, 3), socket("A_TrunkR_03", "TrunkR_Inside", 2.5, 1, 3),
	socket("A_TrunkLA_01", "TrunkL_Around", -4, 0), socket("A_TrunkLA_02", "TrunkL_Around", 4, 0.5),
	socket("A_TrunkRA_01", "TrunkR_Around", -4, 0), socket("A_TrunkRA_02", "TrunkR_Around", 4, -0.5),
	socket("A_Wardrobe_01", "Wardrobe_Front", 0, 0), socket("A_Wardrobe_02", "Wardrobe_Front", -2, 3), socket("A_Wardrobe_03", "Wardrobe_Front", 2, -3),
	socket("A_Sofa_01", "Sofa_Top", -2.5, 0), socket("A_Sofa_02", "Sofa_Top", 2.5, 0.5),
	socket("A_SofaL_01", "Sofa_Left", 0, 0), socket("A_SofaL_02", "Sofa_Left", 0.5, 2.5),
	socket("A_SofaR_01", "Sofa_Right", 0, 0), socket("A_SofaR_02", "Sofa_Right", -0.5, -2.5),
	socket("A_Doll_01", "Doll_Main", 0, 0), socket("A_Doll_02", "Doll_Main", -2, 2), socket("A_Doll_03", "Doll_Main", 2, -2),
	socket("A_DollTop_01", "Doll_Top", 0, 0),
	socket("A_FrontL_01", "FrontLeft_A", -2, 0), socket("A_FrontL_02", "FrontLeft_A", 2.5, -1.5), socket("A_FrontL_03", "FrontLeft_A", 0, 2),
	socket("A_Front_01", "Front_Center", -3, 0, 1), socket("A_Front_02", "Front_Center", 3, 1, 1), socket("A_Front_03", "Front_Center", 0, -2, 1),
	socket("A_Left_01", "Left_Floor", 0, 0), socket("A_Left_02", "Left_Floor", -2, 3), socket("A_Left_03", "Left_Floor", 2.5, -2.5),
	socket("A_Right_01", "Right_Floor", 0, 0), socket("A_Right_02", "Right_Floor", 2, 3), socket("A_Right_03", "Right_Floor", -2.5, -2.5),
	socket("A_MoundF_01", "Mound_Front", 0, 0), socket("A_MoundR_01", "Mound_Right", 0, 0),
	socket("A_UnderL_01", "Under_Left", 0, 0), socket("A_UnderL_02", "Under_Left", -3, 3), socket("A_UnderL_03", "Under_Left", 3, -3),
	socket("A_UnderC_01", "Under_Center", 0, 0), socket("A_UnderC_02", "Under_Center", -4, 2), socket("A_UnderC_03", "Under_Center", 4, -2),
	socket("A_UnderR_01", "Under_Right", 0, 0), socket("A_UnderR_02", "Under_Right", -3, -3), socket("A_UnderR_03", "Under_Right", 3, 3),
	socket("A_LoftTL_01", "Loft_TrunkL", 0, 0, 3), socket("A_LoftTL_02", "Loft_TrunkL", -2.5, 1, 3), socket("A_LoftTL_03", "Loft_TrunkL", 2.5, -1, 3),
	socket("A_LoftTR_01", "Loft_TrunkR", 0, 0, 3), socket("A_LoftTR_02", "Loft_TrunkR", -2.5, -1, 3), socket("A_LoftTR_03", "Loft_TrunkR", 2.5, 1, 3),
	socket("A_LoftL_01", "Loft_Left", 0, 0), socket("A_LoftL_02", "Loft_Left", -2, 3.5), socket("A_LoftL_03", "Loft_Left", 2, -3.5),
	socket("A_LoftC_01", "Loft_Center", -4, 0), socket("A_LoftC_02", "Loft_Center", 0, 1.5), socket("A_LoftC_03", "Loft_Center", 4, -1.5),
	socket("A_LoftB_01", "Loft_Boxes", 0, 0, 3), socket("A_LoftB_02", "Loft_Boxes", -2, 2, 3),
	socket("A_LoftR_01", "Loft_Right", 0, 0), socket("A_LoftR_02", "Loft_Right", 2, 3.5), socket("A_LoftR_03", "Loft_Right", -2, -3.5),
}

return Room
