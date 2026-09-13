--[[
	Clutter asset catalog. Every movable clutter object in every room references one AssetKey.

	Placeholder look = Shape/Size/Colors/Material (+ optional Extras welded to the root).
	Final art: drop a Model or BasePart named exactly <AssetKey> into ServerStorage.ClutterAssets.
	The builder then swaps visuals for every object with that key, in every room, keeping the
	object's CFrame, size, ObjectId and all gameplay attributes.

	Weight gates grabbing (player Strength). CashValue is paid when the object is deposited in a
	bin (double in its matching bin, see DepositConfig).

	Special categories:
	  Chunk    - "packed junk": one physics body that bursts into 5-8 real objects when grabbed
	             (its Contents). Lower pile layers are made of these so rooms can be deep.
	  Treasure - rare lost items worth a lot of Cash; they sparkle once uncovered.
]]

local C = Color3.fromRGB

export type Extra = { Offset: CFrame, Size: Vector3, Shape: string?, Color: Color3?, Material: Enum.Material? }
export type AssetDef = {
	Key: string,
	DisplayName: string,
	Category: string,
	Weight: number,
	CashValue: number,
	Shape: string, -- "Block" | "Ball" | "Cylinder" | "Wedge"
	Size: Vector3,
	Colors: { Color3 },
	Material: Enum.Material,
	Extras: { Extra }?,
}

local Assets: { [string]: AssetDef } = {}

local function add(def)
	Assets[def.Key] = def
end

local FabricColors = { C(230, 90, 120), C(90, 150, 230), C(250, 250, 250), C(60, 60, 80), C(120, 200, 120), C(250, 170, 60), C(170, 100, 255) }
local BookColors = { C(200, 60, 60), C(60, 100, 200), C(60, 170, 90), C(240, 200, 60), C(150, 80, 200), C(240, 240, 240), C(40, 40, 60) }
local ToyColors = { C(255, 80, 80), C(80, 200, 255), C(255, 220, 60), C(120, 255, 120), C(255, 120, 220), C(255, 140, 40) }
local TechColors = { C(40, 40, 50), C(70, 70, 80), C(200, 200, 205), C(30, 60, 90) }

-- Weight 1
add({ Key = "Paper_A", DisplayName = "PAPER", Category = "Paper", Weight = 1, CashValue = 1, Shape = "Block", Size = Vector3.new(1.4, 0.15, 1.9), Colors = { C(250, 250, 250), C(245, 240, 220), C(235, 235, 250) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Magazine_A", DisplayName = "MAGAZINE", Category = "Paper", Weight = 1, CashValue = 1, Shape = "Block", Size = Vector3.new(1.6, 0.2, 2.1), Colors = { C(250, 120, 60), C(90, 200, 250), C(250, 90, 170), C(120, 250, 130) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Notebook_A", DisplayName = "NOTEBOOK", Category = "Book", Weight = 1, CashValue = 1, Shape = "Block", Size = Vector3.new(1.2, 0.2, 1.6), Colors = { C(255, 200, 40), C(90, 200, 250), C(250, 90, 90) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Pencil_A", DisplayName = "PENCIL", Category = "School", Weight = 1, CashValue = 1, Shape = "Cylinder", Size = Vector3.new(1.3, 0.2, 0.2), Colors = { C(255, 210, 40) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Sock_A", DisplayName = "SOCK", Category = "Clothes", Weight = 1, CashValue = 1, Shape = "Cylinder", Size = Vector3.new(1.1, 0.45, 0.45), Colors = { C(250, 250, 250), C(40, 40, 40), C(250, 220, 60), C(255, 120, 200) }, Material = Enum.Material.Fabric })
add({ Key = "Shirt_A", DisplayName = "SHIRT", Category = "Clothes", Weight = 1, CashValue = 1, Shape = "Block", Size = Vector3.new(2.2, 0.35, 1.8), Colors = FabricColors, Material = Enum.Material.Fabric })
add({ Key = "Cup_A", DisplayName = "CUP", Category = "Junk", Weight = 1, CashValue = 1, Shape = "Cylinder", Size = Vector3.new(0.9, 0.7, 0.7), Colors = { C(250, 250, 250), C(80, 160, 230), C(230, 80, 80) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Can_A", DisplayName = "SODA CAN", Category = "Junk", Weight = 1, CashValue = 1, Shape = "Cylinder", Size = Vector3.new(0.9, 0.5, 0.5), Colors = { C(220, 40, 40), C(40, 80, 200), C(40, 160, 90) }, Material = Enum.Material.Metal })
add({ Key = "Cable_A", DisplayName = "CHARGER", Category = "Electronics", Weight = 1, CashValue = 1, Shape = "Cylinder", Size = Vector3.new(2.4, 0.2, 0.2), Colors = { C(30, 30, 30), C(240, 240, 240) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "ToyBlock_A", DisplayName = "TOY BLOCK", Category = "Toy", Weight = 1, CashValue = 2, Shape = "Block", Size = Vector3.new(1, 1, 1), Colors = ToyColors, Material = Enum.Material.SmoothPlastic })
add({ Key = "Remote_A", DisplayName = "TV REMOTE", Category = "Electronics", Weight = 1, CashValue = 2, Shape = "Block", Size = Vector3.new(0.5, 0.25, 1.6), Colors = TechColors, Material = Enum.Material.SmoothPlastic })
add({ Key = "ToyDuck_A", DisplayName = "RUBBER DUCK", Category = "Toy", Weight = 1, CashValue = 3, Shape = "Ball", Size = Vector3.new(1.1, 1.1, 1.1), Colors = { C(255, 220, 40) }, Material = Enum.Material.SmoothPlastic,
	Extras = {
		{ Offset = CFrame.new(0, 0.55, -0.25), Size = Vector3.new(0.7, 0.7, 0.7), Shape = "Ball" },
		{ Offset = CFrame.new(0, 0.5, -0.65), Size = Vector3.new(0.35, 0.18, 0.35), Color = C(255, 140, 30) },
	} })

-- Weight 2
add({ Key = "Book_A", DisplayName = "BOOK", Category = "Book", Weight = 2, CashValue = 2, Shape = "Block", Size = Vector3.new(1.6, 0.4, 1.2), Colors = BookColors, Material = Enum.Material.SmoothPlastic })
add({ Key = "Book_B", DisplayName = "BIG BOOK", Category = "Book", Weight = 2, CashValue = 2, Shape = "Block", Size = Vector3.new(2.0, 0.5, 1.4), Colors = BookColors, Material = Enum.Material.SmoothPlastic })
add({ Key = "Book_C", DisplayName = "TEXTBOOK", Category = "Book", Weight = 2, CashValue = 2, Shape = "Block", Size = Vector3.new(1.5, 0.6, 1.9), Colors = BookColors, Material = Enum.Material.SmoothPlastic })
add({ Key = "Shoe_A", DisplayName = "SHOE", Category = "Shoes", Weight = 2, CashValue = 2, Shape = "Block", Size = Vector3.new(1.9, 0.75, 0.8), Colors = { C(40, 40, 40), C(250, 250, 250), C(200, 50, 50), C(60, 90, 160), C(255, 140, 40) }, Material = Enum.Material.SmoothPlastic,
	Extras = { { Offset = CFrame.new(0.45, 0.4, 0), Size = Vector3.new(0.8, 0.35, 0.72) } } })
add({ Key = "Hoodie_A", DisplayName = "HOODIE", Category = "Clothes", Weight = 2, CashValue = 2, Shape = "Block", Size = Vector3.new(2.6, 0.6, 2.2), Colors = FabricColors, Material = Enum.Material.Fabric })
add({ Key = "Bottle_A", DisplayName = "WATER BOTTLE", Category = "Junk", Weight = 2, CashValue = 2, Shape = "Cylinder", Size = Vector3.new(1.6, 0.55, 0.55), Colors = { C(120, 200, 255), C(200, 240, 255) }, Material = Enum.Material.Glass })
add({ Key = "PizzaBox_A", DisplayName = "PIZZA BOX", Category = "Junk", Weight = 2, CashValue = 2, Shape = "Block", Size = Vector3.new(2.6, 0.3, 2.6), Colors = { C(220, 170, 110) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Plush_A", DisplayName = "PLUSH TOY", Category = "Toy", Weight = 2, CashValue = 3, Shape = "Ball", Size = Vector3.new(1.4, 1.4, 1.4), Colors = { C(255, 190, 210), C(200, 200, 210), C(255, 230, 120) }, Material = Enum.Material.Fabric })
add({ Key = "ToyCar_A", DisplayName = "TOY CAR", Category = "Toy", Weight = 2, CashValue = 3, Shape = "Block", Size = Vector3.new(1.7, 0.5, 0.9), Colors = { C(230, 40, 40), C(40, 120, 230), C(250, 200, 30) }, Material = Enum.Material.Metal,
	Extras = { { Offset = CFrame.new(-0.1, 0.42, 0), Size = Vector3.new(0.8, 0.35, 0.8) } } })
add({ Key = "Controller_A", DisplayName = "CONTROLLER", Category = "Electronics", Weight = 2, CashValue = 4, Shape = "Block", Size = Vector3.new(1.4, 0.3, 0.8), Colors = TechColors, Material = Enum.Material.SmoothPlastic,
	Extras = {
		{ Offset = CFrame.new(-0.6, -0.02, 0.3), Size = Vector3.new(0.45, 0.28, 0.6) },
		{ Offset = CFrame.new(0.6, -0.02, 0.3), Size = Vector3.new(0.45, 0.28, 0.6) },
	} })
add({ Key = "Headphones_A", DisplayName = "HEADPHONES", Category = "Electronics", Weight = 2, CashValue = 4, Shape = "Block", Size = Vector3.new(1.6, 0.25, 0.4), Colors = TechColors, Material = Enum.Material.SmoothPlastic,
	Extras = {
		{ Offset = CFrame.new(-0.8, -0.35, 0), Size = Vector3.new(0.35, 0.8, 0.8), Shape = "Cylinder" },
		{ Offset = CFrame.new(0.8, -0.35, 0), Size = Vector3.new(0.35, 0.8, 0.8), Shape = "Cylinder" },
	} })
add({ Key = "Camera_A", DisplayName = "CAMERA", Category = "Electronics", Weight = 2, CashValue = 4, Shape = "Block", Size = Vector3.new(1.3, 0.8, 0.6), Colors = { C(40, 40, 45), C(200, 200, 205) }, Material = Enum.Material.SmoothPlastic,
	Extras = { { Offset = CFrame.new(0, 0, -0.45), Size = Vector3.new(0.35, 0.55, 0.55), Shape = "Cylinder", Color = C(20, 20, 20) } } })

-- Weight 3
add({ Key = "Pillow_A", DisplayName = "PILLOW", Category = "Bedding", Weight = 3, CashValue = 2, Shape = "Block", Size = Vector3.new(2.8, 0.9, 1.9), Colors = { C(250, 250, 255), C(200, 220, 255), C(255, 210, 220), C(220, 255, 220) }, Material = Enum.Material.Fabric })
add({ Key = "Blanket_A", DisplayName = "BLANKET", Category = "Bedding", Weight = 3, CashValue = 3, Shape = "Block", Size = Vector3.new(3.4, 0.7, 2.8), Colors = { C(90, 130, 220), C(230, 120, 90), C(120, 200, 150) }, Material = Enum.Material.Fabric })
add({ Key = "TeddyBear_A", DisplayName = "TEDDY BEAR", Category = "Toy", Weight = 3, CashValue = 3, Shape = "Ball", Size = Vector3.new(1.6, 1.6, 1.6), Colors = { C(170, 120, 80), C(210, 160, 110) }, Material = Enum.Material.Fabric,
	Extras = {
		{ Offset = CFrame.new(0, 1.05, 0), Size = Vector3.new(1.1, 1.1, 1.1), Shape = "Ball" },
		{ Offset = CFrame.new(-0.4, 1.55, 0), Size = Vector3.new(0.4, 0.4, 0.4), Shape = "Ball" },
		{ Offset = CFrame.new(0.4, 1.55, 0), Size = Vector3.new(0.4, 0.4, 0.4), Shape = "Ball" },
	} })
add({ Key = "Basketball_A", DisplayName = "BASKETBALL", Category = "Toy", Weight = 3, CashValue = 3, Shape = "Ball", Size = Vector3.new(2, 2, 2), Colors = { C(230, 120, 50) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "Backpack_A", DisplayName = "BACKPACK", Category = "Bag", Weight = 3, CashValue = 7, Shape = "Block", Size = Vector3.new(1.8, 2.2, 1.0), Colors = { C(230, 60, 60), C(60, 120, 230), C(60, 60, 70), C(120, 200, 120) }, Material = Enum.Material.Fabric,
	Extras = { { Offset = CFrame.new(0, -0.4, -0.6), Size = Vector3.new(1.3, 0.9, 0.3) } } })
add({ Key = "Laptop_A", DisplayName = "LAPTOP", Category = "Electronics", Weight = 3, CashValue = 6, Shape = "Block", Size = Vector3.new(2.2, 0.15, 1.5), Colors = { C(190, 190, 200), C(50, 50, 60) }, Material = Enum.Material.Metal,
	Extras = { { Offset = CFrame.new(0, 0.65, 0.72) * CFrame.Angles(math.rad(-15), 0, 0), Size = Vector3.new(2.2, 1.4, 0.1) } } })
add({ Key = "CardboardBox_A", DisplayName = "SMALL BOX", Category = "Box", Weight = 3, CashValue = 5, Shape = "Block", Size = Vector3.new(2, 1.6, 2), Colors = { C(190, 140, 90), C(170, 120, 75), C(210, 160, 110) }, Material = Enum.Material.SmoothPlastic })

-- Weight 4+
add({ Key = "CardboardBox_B", DisplayName = "MEDIUM BOX", Category = "Box", Weight = 4, CashValue = 8, Shape = "Block", Size = Vector3.new(2.6, 2.2, 2.6), Colors = { C(190, 140, 90), C(170, 120, 75) }, Material = Enum.Material.SmoothPlastic,
	Extras = { { Offset = CFrame.new(0, 1.12, 0), Size = Vector3.new(0.5, 0.05, 2.62), Color = C(230, 210, 150) } } })
add({ Key = "Basket_A", DisplayName = "LAUNDRY BASKET", Category = "Container", Weight = 4, CashValue = 8, Shape = "Block", Size = Vector3.new(2.6, 1.8, 2.0), Colors = { C(230, 230, 240), C(120, 190, 240) }, Material = Enum.Material.SmoothPlastic })
add({ Key = "StorageBin_A", DisplayName = "STORAGE BIN", Category = "Container", Weight = 5, CashValue = 12, Shape = "Block", Size = Vector3.new(3, 2, 2.2), Colors = { C(80, 140, 220), C(230, 230, 240), C(120, 200, 120) }, Material = Enum.Material.SmoothPlastic,
	Extras = { { Offset = CFrame.new(0, 1.05, 0), Size = Vector3.new(3.1, 0.15, 2.3), Color = C(60, 60, 70) } } })
add({ Key = "HeavyBox_A", DisplayName = "HEAVY BOX", Category = "Box", Weight = 6, CashValue = 15, Shape = "Block", Size = Vector3.new(3, 2.6, 3), Colors = { C(150, 105, 65) }, Material = Enum.Material.WoodPlanks,
	Extras = { { Offset = CFrame.new(0, 1.32, 0), Size = Vector3.new(0.6, 0.05, 3.02), Color = C(220, 60, 60) } } })

-- Packed junk (bursts into its Contents when grabbed; never deposited itself)
local JunkColors = { C(150, 130, 110), C(125, 115, 105), C(165, 140, 115) }
local function junkExtras(size: Vector3)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	return {
		{ Offset = CFrame.new(-hx * 0.45, hy + 0.12, -hz * 0.3) * CFrame.Angles(0, 0.4, 0.15), Size = Vector3.new(1.2, 0.3, 0.9), Color = C(230, 90, 120) },
		{ Offset = CFrame.new(hx * 0.35, hy + 0.1, hz * 0.25) * CFrame.Angles(0.1, -0.3, 0), Size = Vector3.new(1.0, 0.25, 1.3), Color = C(90, 150, 230) },
		{ Offset = CFrame.new(hx * 0.9, 0, -hz * 0.2) * CFrame.Angles(0, 0, 0.3), Size = Vector3.new(0.3, 0.9, 1.1), Color = C(250, 250, 250) },
		{ Offset = CFrame.new(-hx * 0.9, -hy * 0.2, hz * 0.4), Size = Vector3.new(0.3, 0.7, 0.9), Color = C(255, 200, 60) },
		{ Offset = CFrame.new(0, hy * 0.2, hz * 0.95) * CFrame.Angles(0, 0, 0.5), Size = Vector3.new(0.9, 0.35, 0.3), Color = C(120, 200, 120) },
	}
end
add({ Key = "JunkChunk_A", DisplayName = "PACKED JUNK", Category = "Chunk", Weight = 2, CashValue = 0, Shape = "Block", Size = Vector3.new(2.6, 1.3, 2.2), Colors = JunkColors, Material = Enum.Material.Fabric, Extras = junkExtras(Vector3.new(2.6, 1.3, 2.2)) })
add({ Key = "JunkChunk_B", DisplayName = "PACKED JUNK", Category = "Chunk", Weight = 2, CashValue = 0, Shape = "Block", Size = Vector3.new(3.0, 1.5, 2.4), Colors = JunkColors, Material = Enum.Material.Fabric, Extras = junkExtras(Vector3.new(3.0, 1.5, 2.4)) })
add({ Key = "JunkChunk_C", DisplayName = "BIG PACKED JUNK", Category = "Chunk", Weight = 3, CashValue = 0, Shape = "Block", Size = Vector3.new(3.4, 1.7, 2.8), Colors = JunkColors, Material = Enum.Material.Fabric, Extras = junkExtras(Vector3.new(3.4, 1.7, 2.8)) })

-- Treasures (rare; any bin pays their full value)
add({ Key = "Treasure_Coin", DisplayName = "GOLD COIN", Category = "Treasure", Weight = 1, CashValue = 20, Shape = "Cylinder", Size = Vector3.new(0.2, 1.0, 1.0), Colors = { C(255, 205, 50) }, Material = Enum.Material.Metal })
add({ Key = "Treasure_Phone", DisplayName = "LOST PHONE", Category = "Treasure", Weight = 1, CashValue = 25, Shape = "Block", Size = Vector3.new(0.7, 0.12, 1.4), Colors = { C(30, 30, 40), C(240, 240, 245) }, Material = Enum.Material.SmoothPlastic,
	Extras = { { Offset = CFrame.new(0, 0.065, 0), Size = Vector3.new(0.6, 0.02, 1.2), Color = C(90, 200, 255) } } })
add({ Key = "Treasure_Watch", DisplayName = "WRISTWATCH", Category = "Treasure", Weight = 1, CashValue = 15, Shape = "Cylinder", Size = Vector3.new(0.3, 0.9, 0.9), Colors = { C(220, 220, 230) }, Material = Enum.Material.Metal,
	Extras = { { Offset = CFrame.new(0, 0, 0.75), Size = Vector3.new(0.25, 0.08, 0.6), Color = C(60, 40, 30) }, { Offset = CFrame.new(0, 0, -0.75), Size = Vector3.new(0.25, 0.08, 0.6), Color = C(60, 40, 30) } } })
add({ Key = "Treasure_Trophy", DisplayName = "GOLD TROPHY", Category = "Treasure", Weight = 2, CashValue = 30, Shape = "Cylinder", Size = Vector3.new(0.5, 1.2, 1.2), Colors = { C(255, 200, 40) }, Material = Enum.Material.Metal,
	Extras = { { Offset = CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90)), Size = Vector3.new(1.0, 0.8, 0.8), Shape = "Cylinder" } } })

local ClutterConfig = {
	Assets = Assets,
	TreasureKeys = { "Treasure_Coin", "Treasure_Phone", "Treasure_Watch", "Treasure_Trophy" },
	ChunkKeys = { "JunkChunk_A", "JunkChunk_B", "JunkChunk_C" },
	TreasureChance = 1 / 150, -- per generated object (and per chunk content)
	-- Objects at or above this weight collide with players (big boxes/bins); lighter ones don't,
	-- so the room never traps anyone.
	PlayerCollisionWeight = 4,
	MaxReasonableWeight = 10,
}

function ClutterConfig.Get(key: string): AssetDef?
	return Assets[key]
end

function ClutterConfig.Keys(): { string }
	local keys = {}
	for k in pairs(Assets) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

return ClutterConfig
