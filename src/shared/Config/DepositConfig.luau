--[[
	Deposit bins: the only way to earn Cash. Get an object into any bin and it leaves the room
	and pays its CashValue. The matching bin pays double, a long throw that drops straight in
	(no bounce first) is a SWISH, and deposits in quick succession build a streak.

	Rooms place bins by Type (see RoomConfigs.*.DepositBins). Final art for a bin:
	ServerStorage.Props.<PropKey> (visual only; the placeholder walls keep the collision).
]]

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
	Trash = { Type = "Trash", Name = "TRASH CAN", Short = "TRASH", PropKey = "Bin_Trash", Color = C(110, 210, 120), Categories = { "Junk", "Electronics" }, IconKey = "Bin_Trash" },
	Donation = { Type = "Donation", Name = "DONATION BOX", Short = "DONATE", PropKey = "Bin_Donation", Color = C(200, 150, 100), Categories = { "Box", "Container" }, HeavyWeight = 4, IconKey = "Bin_Donation" },
}

local DepositConfig = {
	Types = Types,
	Order = { "Laundry", "Toys", "Books", "Trash", "Donation" },
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

-- The bin type an object belongs in (nil = none; any bin still pays the base value).
function DepositConfig.MatchingType(category: string?, weight: number?): string?
	for _, key in ipairs(DepositConfig.Order) do
		local t = Types[key]
		if t.HeavyWeight and (weight or 0) >= t.HeavyWeight then
			return key
		end
	end
	for _, key in ipairs(DepositConfig.Order) do
		if category and table.find(Types[key].Categories, category) then
			return key
		end
	end
	return nil
end

function DepositConfig.StreakMultiplier(streak: number): number
	return math.min(1 + math.max(0, streak - 1) * DepositConfig.StreakStep, DepositConfig.StreakMax)
end

return DepositConfig
