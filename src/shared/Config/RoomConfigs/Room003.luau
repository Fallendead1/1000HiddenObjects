--[[
	ROOM #003 - THE COZY LIVING ROOM
	A sleepover movie night gone wild, and nobody can find the remote.
	Room-local studs: origin = floor centre at y = 0, X [-45, 45], Z [-35, 35], door on +Z.
	The TV wall is at the back, the big sofa faces it, the fireplace is on the left and the
	bookcase on the right. The blanket fort (front left) is the deepest dig in the room.
]]

local Kit = require(script.Parent.Kit)

local C = Color3.fromRGB
local V = Vector3.new
local V2 = Vector2.new
local solid, deco = Kit.solid, Kit.deco

local Room = {
	Id = 3,
	DisplayNumber = "003",
	Name = "The Cozy Living Room",
	ObjectPrefix = "Living",

	TargetId = "GoldenRemote",
	TargetName = "Golden TV Remote",

	MinimumTargetSockets = 30,
	SocketBlockerRadius = 1.4,
	RequiredBlockerDisplacement = 1.4,
	ExitDoor = "Door",
	LayoutVariants = { 1 },

	CountMultiplier = 2.4,
	ChunkFraction = 0.3,
	ChunkContents = { 5, 8 },
	FloorHeapHeightBonus = 4,
	HardMode = { ChunkFraction = 0.5, ChunkContents = { 12, 16 } },
	TreasureKeys = { "Treasure_MovieTicket", "Treasure_Coin", "Treasure_Phone", "Treasure_Trophy" },

	Size = V(90, 26, 70),
	SpawnPosition = V(0, 3, 29),

	FloorColor = C(165, 115, 75),
	WallColor = C(235, 205, 170),
	LampColor = C(255, 225, 180),
	LampBrightness = 0.6,
}

Room.Regions = {
	{ Id = "Sofa", Name = "BIG SOFA", Center = V(0, 4, -12), Size = V(34, 8, 12) },
	{ Id = "TVWall", Name = "TV WALL", Center = V(0, 5, -30), Size = V(38, 10, 10) },
	{ Id = "CoffeeTable", Name = "COFFEE TABLE", Center = V(0, 3, -22), Size = V(14, 6, 6) },
	{ Id = "Fireplace", Name = "FIREPLACE", Center = V(-36, 5, -18), Size = V(18, 10, 16) },
	{ Id = "Bookcase", Name = "BOOKCASE", Center = V(39, 7, -6), Size = V(12, 14, 20) },
	{ Id = "BlanketFort", Name = "BLANKET FORT", Center = V(-20, 5, 13), Size = V(16, 10, 16) },
	{ Id = "GameCorner", Name = "GAME CORNER", Center = V(32, 4, 25), Size = V(22, 8, 18) },
	{ Id = "WindowSeat", Name = "WINDOW SEAT", Center = V(34, 4, -28), Size = V(20, 8, 14) },
	{ Id = "ToyRug", Name = "TOY RUG", Center = V(1, 3, 6), Size = V(22, 6, 18) },
	{ Id = "PlantCorner", Name = "PLANT CORNER", Center = V(-36, 4, 27), Size = V(18, 8, 16) },
	{ Id = "LeftFloor", Name = "LEFT FLOOR", Center = V(-33, 3, 3), Size = V(14, 6, 16) },
	{ Id = "RightFloor", Name = "RIGHT FLOOR", Center = V(19, 3, -1), Size = V(14, 6, 14) },
}

Room.HintAreas = {
	{ Label = "FIREPLACE / LEFT FLOOR / PLANTS", Regions = { "Fireplace", "LeftFloor", "PlantCorner" } },
	{ Label = "TV WALL / COFFEE TABLE / SOFA", Regions = { "TVWall", "CoffeeTable", "Sofa" } },
	{ Label = "BOOKCASE / WINDOW SEAT / RIGHT FLOOR", Regions = { "Bookcase", "WindowSeat", "RightFloor" } },
	{ Label = "BLANKET FORT / TOY RUG / GAMES", Regions = { "BlanketFort", "ToyRug", "GameCorner" } },
}

Room.SideSigns = {
	LEFT = { Z = 2, Width = 16, Landmarks = "FIREPLACE · FORT · PLANTS" },
	RIGHT = { Z = 12, Width = 16, Landmarks = "BOOKCASE · GAMES" },
}

Room.DepositBins = {
	{ Type = "Laundry", Center = V(-17.5, 0, 30), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Toys", Center = V(17.5, 0, 30), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Books", Center = V(30, 0, 8), Size = V(4.2, 2.4, 4.2) },
	{ Type = "GameShelf", Center = V(24, 0, 18), Size = V(4.6, 2.6, 4.6) },
	{ Type = "Trash", Center = V(-30, 0, -8), Size = V(4.2, 2.8, 4.2) },
	{ Type = "Donation", Center = V(9, 0, 31), Size = V(6.5, 1.4, 5) },
}

Room.Containers = {
	-- The blanket fort: sheet walls around the deepest pile in the room.
	{ Id = "BlanketFort", Center = V(-20, 0, 13), Size = V(12, 4, 10), Color = C(120, 170, 230) },
	{ Id = "GameChest", Center = V(36, 0, 27), Size = V(11.6, 3.2, 8.6), Color = C(150, 95, 60) },
	{ Id = "PlantBox", Center = V(-37, 0, 26), Size = V(9.6, 2.6, 8.6), Color = C(120, 90, 60) },
}

-- ===== Furniture =====
local wood, woodDark = C(150, 100, 60), C(110, 72, 42)
local sofa, sofaDark = C(90, 110, 170), C(70, 88, 140)
local F = {}
local function add(f)
	table.insert(F, f)
end
-- The big sofa facing the TV: seat, back and arms. The seat is where the cushions pile up.
add(solid("SofaSeat", V(22, 2.2, 7), V(0, 1.1, -12), sofa, Enum.Material.Fabric))
add(solid("SofaBack", V(22, 3.8, 2), V(0, 3.1, -8), sofaDark, Enum.Material.Fabric))
add(solid("SofaArmL", V(2, 3.2, 9), V(-12, 1.6, -11), sofaDark, Enum.Material.Fabric))
add(solid("SofaArmR", V(2, 3.2, 9), V(12, 1.6, -11), sofaDark, Enum.Material.Fabric))
-- TV wall: the console, the TV and speakers.
add(solid("TVConsole", V(20, 2.6, 4), V(0, 1.3, -32.5), wood, Enum.Material.Wood))
add(deco("TV", V(16, 9, 0.6), V(0, 9.5, -34.2), C(25, 25, 30)))
add(deco("TVScreen", V(15, 8, 0.1), V(0, 9.5, -33.85), C(80, 150, 255), Enum.Material.Neon, { Transparency = 0.2 }))
add(deco("SpeakerL", V(2, 6, 2), V(-12, 3, -33), C(30, 30, 35)))
add(deco("SpeakerR", V(2, 6, 2), V(12, 3, -33), C(30, 30, 35)))
-- Coffee table.
add(solid("CoffeeTable", V(10, 1.8, 5), V(0, 0.9, -22), wood, Enum.Material.Wood))
-- Fireplace on the left wall, with a glow.
add(solid("Fireplace", V(4, 8, 12), V(-43, 4, -18), C(170, 90, 70), Enum.Material.Brick))
add(solid("Mantel", V(5, 0.6, 14), V(-42.5, 8.2, -18), woodDark, Enum.Material.Wood))
add(deco("Fire", V(0.4, 2.4, 5), V(-40.8, 1.6, -18), C(255, 140, 40), Enum.Material.Neon, { Light = { Range = 18, Brightness = 1, Color = C(255, 160, 80) } }))
add(deco("Chimney", V(1.4, 14, 8), V(-44.3, 15.5, -18), C(170, 90, 70), Enum.Material.Brick))
-- Bookcase on the right wall (its books are real clutter).
Kit.shelves(F, "Shelving", 1, -16, 4, 13, 3.2, { 3.5, 6.5, 9.5, 12.5 }, wood, woodDark)
-- Window seat in the back right corner.
add(solid("WindowSeat", V(12, 2.4, 4), V(34, 1.2, -32.5), C(230, 220, 200), Enum.Material.Fabric))
add(deco("Window", V(12, 10, 0.4), V(34, 11, -34.6), C(200, 235, 255), Enum.Material.Glass, { Transparency = 0.35 }))
add(deco("CurtainL", V(2.4, 12, 0.6), V(26.8, 10.5, -34), C(200, 80, 90), Enum.Material.Fabric))
add(deco("CurtainR", V(2.4, 12, 0.6), V(41.2, 10.5, -34), C(200, 80, 90), Enum.Material.Fabric))
-- The blanket fort's roof and poles (looks only; the walls come from its container).
add(deco("FortRoof", V(13, 0.2, 11), V(-20, 7.5, 13), C(240, 200, 120), Enum.Material.Fabric, { Transparency = 0.15 }))
for _, x in ipairs({ -26, -14 }) do
	for _, z in ipairs({ 8, 18 }) do
		add(deco("FortPole", V(0.3, 7.5, 0.3), V(x, 3.75, z), C(250, 250, 250)))
	end
end
-- Fairy lights along the back wall, lamps, the toy rug and a poster.
for i = 0, 8 do
	add(deco("FairyLight", V(0.4, 0.4, 0.4), V(-24 + i * 6, 20, -34.3), C(255, 220, 140), Enum.Material.Neon, { Shape = Enum.PartType.Ball }))
end
add(deco("FloorLampL", V(1, 9, 1), V(-16, 4.5, -18), C(60, 60, 70), Enum.Material.Metal))
add(deco("FloorLampShade", V(2.6, 2, 2.6), V(-16, 9.5, -18), C(255, 230, 170), Enum.Material.Neon, { Light = { Range = 16, Brightness = 0.7 } }))
add(deco("Rug", V(22, 0.2, 16), V(1, 0.1, 6), C(90, 170, 120), Enum.Material.Fabric))
add(deco("RugInner", V(18, 0.22, 12), V(1, 0.12, 6), C(120, 200, 150), Enum.Material.Fabric))
add(deco("PosterMovie", V(0.2, 7, 5), V(44.6, 15, 22), C(40, 40, 60)))
add(deco("PosterMovieInner", V(0.1, 6, 4), V(44.4, 15, 22), C(255, 200, 40)))
Kit.door(F, C(130, 85, 50), C(250, 245, 235))
Room.Furniture = F

-- ===== Clutter =====
local Mix = {
	SofaSeat = { Cushion_A = 5, Blanket_A = 2, Pillow_A = 3, Remote_A = 2, Controller_A = 2, SnackBag_A = 3, PopcornBucket_A = 2, Sock_A = 2, Plush_A = 1, Magazine_A = 1 },
	Snacks = { SnackBag_A = 5, PopcornBucket_A = 4, Can_A = 3, Cup_A = 3, Bottle_A = 2, PizzaBox_A = 2, Wrapper_A = 3, Remote_A = 1 },
	Games = { BoardGame_A = 4, PuzzlePiece_A = 4, GameDisc_A = 4, GameConsole_A = 1, Controller_A = 3, Remote_A = 2, Headphones_A = 1, Cable_A = 2 },
	LivingFloor = { Cushion_A = 3, Blanket_A = 2, SleepingBag_A = 2, BoardGame_A = 2, Beanbag_A = 1, PictureFrame_A = 1, FloorLamp_A = 1, CardboardBox_A = 1, Book_A = 2, Plush_A = 2, SnackBag_A = 2, Sock_A = 2 },
	Fort = { Blanket_A = 4, Pillow_A = 3, Cushion_A = 3, SleepingBag_A = 2, Plush_A = 3, TeddyBear_A = 2, SnackBag_A = 3, PopcornBucket_A = 2, BoardGame_A = 2, GameDisc_A = 2, ToyBlock_A = 2, Controller_A = 1 },
	Toys = { ToyBlock_A = 6, ToyCar_A = 3, ToyDuck_A = 2, Plush_A = 3, TeddyBear_A = 2, Basketball_A = 1, PuzzlePiece_A = 3, BoardGame_A = 1 },
	Books = { Book_A = 5, Book_B = 4, Book_C = 3, Magazine_A = 3, Notebook_A = 2, PictureFrame_A = 1 },
	Plants = { PlantPot_A = 3, PictureFrame_A = 2, FloorLamp_A = 1, Magazine_A = 2, Blanket_A = 1, Book_B = 2, CardboardBox_A = 1 },
	Fireside = { SleepingBag_A = 2, Blanket_A = 3, Pillow_A = 2, Book_A = 2, Magazine_A = 2, PictureFrame_A = 1, Sock_A = 3, Mug_A = 2, Cushion_A = 2 },
	Scatter = { PuzzlePiece_A = 4, Sock_A = 3, SnackBag_A = 3, Magazine_A = 2, GameDisc_A = 2, Remote_A = 1, ToyBlock_A = 2, Can_A = 2 },
	ShelfBooks = { Book_A = 3, Book_B = 2, Book_C = 2, Notebook_A = 1 },
	Carpet = { Blanket_A = 3, Cushion_A = 2, Magazine_A = 3, PizzaBox_A = 3, BoardGame_A = 2, SleepingBag_A = 1, Shirt_A = 2, Paper_A = 2, SnackBag_A = 2, Book_B = 1 },
}

local heap, row, carpet = Kit.Piles(Mix)

Room.Piles = {
	-- Between the sofa cushions (the classic).
	heap("Sofa_Seat", "Sofa", "SofaSeat", V(0, 2.2, -13), V2(20, 4.6), 70, 3.5),
	heap("Sofa_FloorL", "Sofa", "LivingFloor", V(-17.5, 0, -12), V2(7, 8), 45, 5),
	heap("Sofa_FloorR", "Sofa", "LivingFloor", V(17, 0, -13), V2(6, 7), 40, 5),
	heap("Coffee_Top", "CoffeeTable", "Snacks", V(0, 1.8, -22), V2(9.4, 4.4), 40, 3),
	heap("Coffee_Floor", "CoffeeTable", "Snacks", V(0, 0, -27.8), V2(14, 3.6), 40, 4),
	heap("TV_Top", "TVWall", "Games", V(0, 2.6, -32.5), V2(18, 3.4), 35, 2.5),
	heap("TV_FloorL", "TVWall", "Games", V(-16, 0, -28), V2(8, 7), 40, 5),
	heap("TV_FloorR", "TVWall", "LivingFloor", V(16, 0, -28), V2(8, 7), 40, 5),
	heap("Fire_Main", "Fireplace", "Fireside", V(-35, 0, -19), V2(8, 10), 55, 6),
	heap("Fire_Mantel", "Fireplace", "Books", V(-42.2, 8.5, -18), V2(3, 12), 18, 1.8),
	heap("Books_FloorA", "Bookcase", "Books", V(38, 0, -12), V2(6, 7), 40, 4),
	heap("Books_FloorB", "Bookcase", "Books", V(38, 0, -1), V2(6, 6), 36, 4),
	-- Floor heaps get +4 height (FloorHeapHeightBonus): 3 keeps the fort's pile under its roof.
	heap("Fort_Inside", "BlanketFort", "Fort", V(-20, 0, 13), V2(11.2, 9.2), 120, 3),
	heap("Fort_Front", "BlanketFort", "Fort", V(-20, 0, 21), V2(10, 3.5), 30, 4),
	heap("Game_Chest", "GameCorner", "Games", V(36, 0, 27), V2(11, 8), 75, 6),
	heap("Game_Side", "GameCorner", "Games", V(26, 0, 27), V2(6, 6), 35, 4),
	heap("Window_Top", "WindowSeat", "SofaSeat", V(34, 2.4, -32.5), V2(11, 3.4), 25, 2.5),
	heap("Window_Floor", "WindowSeat", "LivingFloor", V(33, 0, -26), V2(10, 5), 40, 5),
	heap("Rug_Main", "ToyRug", "Toys", V(1, 0, 6), V2(10, 10), 70, 5.5),
	heap("Rug_B", "ToyRug", "Toys", V(9, 0, 14), V2(6, 6), 34, 4),
	heap("Rug_C", "ToyRug", "Games", V(-6, 0, -1), V2(7, 6), 34, 4),
	heap("Plant_Box", "PlantCorner", "Plants", V(-37, 0, 26), V2(9, 8), 60, 5.5),
	heap("Left_A", "LeftFloor", "Fireside", V(-34, 0, 4), V2(8, 8), 42, 5),
	heap("Right_A", "RightFloor", "LivingFloor", V(18, 0, -1), V2(7, 8), 42, 5),
	heap("Mound_Front", "ToyRug", "LivingFloor", V(-6, 0, 20), V2(6, 5), 30, 4),
	heap("Mound_Back", "Sofa", "Snacks", V(-24, 0, -4), V2(6, 6), 34, 4),
	heap("Scatter_Mid", "ToyRug", "Scatter", V(0, 0, 4), V2(36, 22), 90, 1.2),
	heap("Scatter_Back", "TVWall", "Scatter", V(0, 0, -18), V2(30, 6), 40, 1.2),
	heap("Scatter_Left", "LeftFloor", "Scatter", V(-30, 0, -6), V2(10, 10), 45, 1.2),
	heap("Scatter_Right", "RightFloor", "Scatter", V(26, 0, -14), V2(10, 10), 45, 1.2),
	carpet("Carpet", "Carpet", V(0, 0, 0), V2(88, 68), 0.55, 1.8, {
		{ Center = V2(0, 31.5), Size = V2(6, 5) },
	}, 1.6),
	row("Shelf_1", "Bookcase", "ShelfBooks", V(42.9, 0, -15.6), V(42.9, 0, 3.6), 3.5, 42.9),
	row("Shelf_2", "Bookcase", "ShelfBooks", V(42.9, 0, -15.6), V(42.9, 0, 3.6), 6.5, 42.9),
	row("Shelf_3", "Bookcase", "ShelfBooks", V(42.9, 0, -15.6), V(42.9, 0, 3.6), 9.5, 42.9),
	row("Shelf_4", "Bookcase", "ShelfBooks", V(42.9, 0, -15.6), V(42.9, 0, 3.6), 12.5, 42.9),
}

local socket = Kit.socket
Room.Sockets = {
	socket("L_Sofa_01", "Sofa_Seat", -6, 0, 3), socket("L_Sofa_02", "Sofa_Seat", 0, 0.5, 3), socket("L_Sofa_03", "Sofa_Seat", 6, -0.5, 3), socket("L_Sofa_04", "Sofa_Seat", -2.5, -1, 3),
	socket("L_SofaL_01", "Sofa_FloorL", 0, 0), socket("L_SofaL_02", "Sofa_FloorL", 1, -2.5),
	socket("L_SofaR_01", "Sofa_FloorR", 0, 0), socket("L_SofaR_02", "Sofa_FloorR", -1, 2),
	socket("L_Coffee_01", "Coffee_Top", -2, 0), socket("L_Coffee_02", "Coffee_Top", 2.5, 0.5),
	socket("L_CoffeeF_01", "Coffee_Floor", -4, 0), socket("L_CoffeeF_02", "Coffee_Floor", 4, 0),
	socket("L_TV_01", "TV_Top", -5, 0), socket("L_TV_02", "TV_Top", 5, 0),
	socket("L_TVL_01", "TV_FloorL", 0, 0), socket("L_TVL_02", "TV_FloorL", -2, 2),
	socket("L_TVR_01", "TV_FloorR", 0, 0), socket("L_TVR_02", "TV_FloorR", 2, -2),
	socket("L_Fire_01", "Fire_Main", 0, 0), socket("L_Fire_02", "Fire_Main", -2, 3), socket("L_Fire_03", "Fire_Main", 2, -3),
	socket("L_Mantel_01", "Fire_Mantel", 0, 3),
	socket("L_BooksA_01", "Books_FloorA", 0, 0), socket("L_BooksA_02", "Books_FloorA", -1.5, 1.5),
	socket("L_BooksB_01", "Books_FloorB", 0, 0), socket("L_BooksB_02", "Books_FloorB", -1, 1.5),
	socket("L_Fort_01", "Fort_Inside", 0, 0, 3), socket("L_Fort_02", "Fort_Inside", -3, 2, 3), socket("L_Fort_03", "Fort_Inside", 3, -2, 3), socket("L_Fort_04", "Fort_Inside", -3, -2.5, 3), socket("L_Fort_05", "Fort_Inside", 3, 2.5, 3),
	socket("L_FortF_01", "Fort_Front", -2, 0), socket("L_FortF_02", "Fort_Front", 2.5, 0),
	socket("L_Game_01", "Game_Chest", -2.5, 0.5, 3), socket("L_Game_02", "Game_Chest", 2.5, -1, 3), socket("L_Game_03", "Game_Chest", 0, 2, 3),
	socket("L_GameS_01", "Game_Side", 0, 0), socket("L_GameS_02", "Game_Side", 1.5, 1.5),
	socket("L_Window_01", "Window_Top", -3, 0), socket("L_Window_02", "Window_Top", 3, 0),
	socket("L_WindowF_01", "Window_Floor", -3, 0), socket("L_WindowF_02", "Window_Floor", 3, 0.5),
	socket("L_Rug_01", "Rug_Main", -2, -2, 1), socket("L_Rug_02", "Rug_Main", 2.5, 2, 1), socket("L_Rug_03", "Rug_Main", 3, -3, 1),
	socket("L_RugB_01", "Rug_B", 0, 0, 1), socket("L_RugC_01", "Rug_C", 0, 0, 1),
	socket("L_Plant_01", "Plant_Box", -2, 0), socket("L_Plant_02", "Plant_Box", 2, 1.5), socket("L_Plant_03", "Plant_Box", 0, -2),
	socket("L_Left_01", "Left_A", 0, -1), socket("L_Left_02", "Left_A", 2, 2.5),
	socket("L_Right_01", "Right_A", 0, 1), socket("L_Right_02", "Right_A", -2, -2),
	socket("L_Mound_01", "Mound_Front", 0, 0), socket("L_Mound_02", "Mound_Back", 0, 0),
}

return Room
