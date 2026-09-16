--[[
	Deposit bins: the only way to earn Cash. Get an object into any bin and it leaves the room
	and pays its CashValue. The matching bin pays double, a long throw that drops straight in
	(no bounce first) is a SWISH, and deposits in quick succession build a streak.

	Rooms place bins by Type (see RoomConfigs.*.DepositBins). Final art for a bin:
	ServerStorage.Props.<PropKey> (visual only; the placeholder walls keep the collision).

	An object's right bin depends on the room: its category goes to the first bin type in Order
	that lists it AND stands in this room (paper is BOOKS in the bedroom, RECYCLING in the
	kitchen). Trash is last, so it takes whatever no other bin in the room wants.
]]

local CollectionService = game:GetService("CollectionService")

export type BinType = {
	Type: string,
	Name: string,
	Short: string, -- the one word on the sign over the bin
	PropKey: string,
	Color: Color3,
	Categories: { string },
	HeavyWeight: number?, -- anything at least this heavy also matches this bin
	IconKey: string, -- UI image key (ReplicatedStorage.GameAssets.UIImages)
}

local C = Color3.fromRGB

local Types: { [string]: BinType } = {
	Laundry = { Type = "Laundry", Name = "LAUNDRY BASKET", Short = "LAUNDRY", PropKey = "Bin_Laundry", Color = C(90, 160, 255), Categories = { "Clothes", "Shoes", "Bedding", "Bag" }, IconKey = "Bin_Laundry" },
	Toys = { Type = "Toys", Name = "TOY BIN", Short = "TOYS", PropKey = "Bin_Toys", Color = C(255, 120, 200), Categories = { "Toy" }, IconKey = "Bin_Toys" },
	Books = { Type = "Books", Name = "BOOK CART", Short = "BOOKS", PropKey = "Bin_Books", Color = C(255, 180, 60), Categories = { "Book", "Paper", "School" }, IconKey = "Bin_Books" },
	DishRack = { Type = "DishRack", Name = "DISH RACK", Short = "DISHES", PropKey = "Bin_DishRack", Color = C(120, 220, 255), Categories = { "Dishes" }, IconKey = "Bin_DishRack" },
	Pantry = { Type = "Pantry", Name = "PANTRY SHELF", Short = "PANTRY", PropKey = "Bin_Pantry", Color = C(255, 210, 90), Categories = { "Food" }, IconKey = "Bin_Pantry" },
	Recycling = { Type = "Recycling", Name = "RECYCLING BIN", Short = "RECYCLE", PropKey = "Bin_Recycling", Color = C(70, 170, 255), Categories = { "Recyclable", "Paper", "Book" }, IconKey = "Bin_Recycling" },
	GameShelf = { Type = "GameShelf", Name = "GAME SHELF", Short = "GAMES", PropKey = "Bin_GameShelf", Color = C(170, 110, 255), Categories = { "Game", "Electronics" }, IconKey = "Bin_GameShelf" },
	Toolbox = { Type = "Toolbox", Name = "TOOLBOX", Short = "TOOLS", PropKey = "Bin_Toolbox", Color = C(230, 70, 60), Categories = { "Tools", "Electronics" }, IconKey = "Bin_Toolbox" },
	SportsBin = { Type = "SportsBin", Name = "SPORTS BIN", Short = "SPORTS", PropKey = "Bin_SportsBin", Color = C(255, 140, 40), Categories = { "Sports", "Toy", "Shoes" }, IconKey = "Bin_SportsBin" },
	Trash = { Type = "Trash", Name = "TRASH CAN", Short = "TRASH", PropKey = "Bin_Trash", Color = C(110, 210, 120), Categories = { "Junk", "Electronics", "Recyclable", "Dishes", "Food", "Game", "Tools", "Sports" }, IconKey = "Bin_Trash" },
	Donation = { Type = "Donation", Name = "DONATION BOX", Short = "DONATE", PropKey = "Bin_Donation", Color = C(200, 150, 100), Categories = { "Box", "Container", "Appliance", "Decor", "Tire" }, HeavyWeight = 4, IconKey = "Bin_Donation" },
}

local DepositConfig = {
	Types = Types,
	-- Preference order (see the header). Trash comes last on purpose.
	Order = { "Laundry", "Toys", "Books", "DishRack", "Pantry", "Recycling", "GameShelf", "Toolbox", "SportsBin", "Donation", "Trash" },
	MatchMultiplier = 2,
	SwishMultiplier = 1.5,
	SwishMinDistance = 10, -- studs (XZ) from where it was thrown
	StreakWindow = 3, -- seconds between deposits to keep a streak alive
	StreakStep = 0.1, -- +10% per deposit in a streak
	StreakMax = 1.5,
	MaxDepositsPerSecond = 8, -- per player
	-- Every room's bins are built this much bigger (width, height, depth; about their base) so
	-- they stand out in the mess. Keep X = Z. 1.15 wide keeps the closest bins in Room #001 apart.
	BinScale = Vector3.new(1.15, 1.5, 1.15),
}

-- The bin types standing in the room right now (the one room a server or client has built).
local presentCache: { [string]: boolean }? = nil
local presentAt = -math.huge
function DepositConfig.PresentTypes(): { [string]: boolean }
	if presentCache and os.clock() - presentAt < 1 then
		return presentCache
	end
	local present = {}
	for _, mouth in ipairs(CollectionService:GetTagged("DepositBin")) do
		local t = mouth:GetAttribute("BinType")
		if type(t) == "string" and mouth:IsDescendantOf(workspace) then
			present[t] = true
		end
	end
	presentCache, presentAt = present, os.clock()
	return present
end

-- The bin type an object belongs in, among the bins in `present` (default: the room's own).
-- nil = none; any bin still pays the base value.
function DepositConfig.MatchingType(category: string?, weight: number?, present: { [string]: boolean }?): string?
	local here = present or DepositConfig.PresentTypes()
	-- With no bins around (menus, tests) every type counts.
	local any = next(here) == nil
	for _, key in ipairs(DepositConfig.Order) do
		local t = Types[key]
		if t.HeavyWeight and (weight or 0) >= t.HeavyWeight and (any or here[key]) then
			return key
		end
	end
	for _, key in ipairs(DepositConfig.Order) do
		if (any or here[key]) and category and table.find(Types[key].Categories, category) then
			return key
		end
	end
	return nil
end

function DepositConfig.StreakMultiplier(streak: number): number
	return math.min(1 + math.max(0, streak - 1) * DepositConfig.StreakStep, DepositConfig.StreakMax)
end

return DepositConfig
