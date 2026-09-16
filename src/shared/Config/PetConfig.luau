--[[
	Helper pets (PetService, PetController, PetShopController).

	Pets follow their owner everywhere. In a room, each equipped pet picks up loose junk near its
	owner, carries it to a bin and pays the owner (room Cash, and the usual wallet share). The rules
	that keep pets helpers, never finders:
	  - never the hidden object, the junk covering it, or anything near its hiding spot
	  - only the top of a pile (nothing resting on it), so pets never dig or cause avalanches
	  - only what the pet can lift (MaxWeight)
	  - all of a player's pets together clean at most MaxPerMinute objects (well under a third of
	    an active player's pace), and they stop when the player stops playing (AFK)
	  - their cleaning counts toward ROOM CLEANED

	Pets are owned per kind (a duplicate hatch levels the pet up). Eggs cost wallet Cash, which
	can't be bought with Robux; every egg still shows its exact odds. Two pets are also sold
	directly (a game pass each), which is not random.

	Final art: ReplicatedStorage.GameAssets.Pets.<Kind> and GameAssets.Eggs.<Egg> (see
	docs/CODEX_PROMPT_7_BUILD.md and client UI/PetModels). Without it, simple placeholder shapes
	are used.
]]

local C = Color3.fromRGB

export type PetDef = {
	Key: string,
	Name: string,
	Rarity: string,
	Interval: number, -- seconds between trips at level 1
	MaxWeight: number,
	Carry: number?, -- objects per trip (2 = a second, light object too)
	CarryWeight: number?, -- the second object's weight limit
	CashBonus: number?, -- extra room Cash on what this pet cleans
	RightBin: boolean?, -- always the matching bin (x2)
	Loves: string?, -- a category it goes for first (and always takes to its matching bin)
	TreasureFirst: boolean?,
	BurstEvery: number?, -- bursts one packed junk this often (never the one hiding the object)
	Flies: boolean?,
	Pass: string?, -- sold directly as this game pass
	Color: Color3, -- placeholder body colour
	Accent: Color3,
	Shape: string, -- placeholder: "Bunny" | "Puppy" | "Slime" | "Bird" | "Frog" | "Cat" | "Turtle" | "Dragon"
	Size: number, -- studs (placeholder body)
	Blurb: string,
}

local Rarities = {
	Common = { Order = 1, Color = C(200, 206, 222), Name = "COMMON" },
	Uncommon = { Order = 2, Color = C(70, 220, 90), Name = "UNCOMMON" },
	Rare = { Order = 3, Color = C(40, 150, 255), Name = "RARE" },
	Epic = { Order = 4, Color = C(190, 70, 255), Name = "EPIC" },
	Legendary = { Order = 5, Color = C(255, 196, 0), Name = "LEGENDARY" },
}

local List: { PetDef } = {
	{ Key = "DustBunny", Name = "Dust Bunny", Rarity = "Common", Interval = 12, MaxWeight = 1, Color = C(215, 210, 220), Accent = C(255, 170, 190), Shape = "Bunny", Size = 1.6, Blurb = "Your first helper. Small, fluffy and always busy." },
	{ Key = "SockPuppy", Name = "Sock Puppy", Rarity = "Common", Interval = 12, MaxWeight = 1, Loves = "Clothes", Color = C(250, 250, 250), Accent = C(230, 70, 90), Shape = "Puppy", Size = 1.7, Blurb = "Loves clothes: always takes them to the Laundry (x2)." },
	{ Key = "SoapSlime", Name = "Soap Slime", Rarity = "Common", Interval = 11, MaxWeight = 1, Color = C(120, 220, 255), Accent = C(255, 255, 255), Shape = "Slime", Size = 1.6, Blurb = "Bubbly and a little quicker." },
	{ Key = "MopPup", Name = "Mop Pup", Rarity = "Uncommon", Interval = 10, MaxWeight = 2, CashBonus = 0.05, Color = C(245, 230, 190), Accent = C(90, 160, 255), Shape = "Puppy", Size = 1.9, Blurb = "+5% Cash on everything it cleans." },
	{ Key = "BroomBird", Name = "Broom Bird", Rarity = "Uncommon", Interval = 10, MaxWeight = 2, Flies = true, Color = C(255, 200, 60), Accent = C(180, 120, 60), Shape = "Bird", Size = 1.7, Blurb = "Flies over the piles to reach the top." },
	{ Key = "LaundryFrog", Name = "Laundry Frog", Rarity = "Rare", Interval = 8, MaxWeight = 2, RightBin = true, Color = C(90, 210, 110), Accent = C(255, 240, 120), Shape = "Frog", Size = 1.9, Blurb = "Always picks the right bin (x2)." },
	{ Key = "VacuumCat", Name = "Vacuum Cat", Rarity = "Rare", Interval = 8, MaxWeight = 2, Carry = 2, CarryWeight = 1, Pass = "PetVacuumCat", Color = C(150, 150, 165), Accent = C(255, 90, 90), Shape = "Cat", Size = 2, Blurb = "Picks up a second small object on every trip." },
	{ Key = "DusterParrot", Name = "Duster Parrot", Rarity = "Epic", Interval = 7, MaxWeight = 3, CashBonus = 0.1, TreasureFirst = true, Flies = true, Color = C(230, 60, 80), Accent = C(60, 200, 255), Shape = "Bird", Size = 2, Blurb = "+10% Cash, and goes for treasures first." },
	{ Key = "RoombaTurtle", Name = "Roomba Turtle", Rarity = "Epic", Interval = 7, MaxWeight = 3, Carry = 2, CarryWeight = 3, Color = C(60, 70, 90), Accent = C(90, 255, 160), Shape = "Turtle", Size = 2.2, Blurb = "Two objects on every trip." },
	{ Key = "GoldenBroomDragon", Name = "Golden Broom Dragon", Rarity = "Legendary", Interval = 6, MaxWeight = 4, BurstEvery = 30, Flies = true, Pass = "PetGoldenDragon", Color = C(255, 200, 40), Accent = C(255, 110, 40), Shape = "Dragon", Size = 2.6, Blurb = "Bursts open a packed junk every 30 s (never the one hiding the object)." },
}

local ByKey: { [string]: PetDef } = {}
for _, def in ipairs(List) do
	ByKey[def.Key] = def
end

local PetConfig = {
	Rarities = Rarities,
	List = List,
	ByKey = ByKey,
	StarterPet = "DustBunny",

	-- Eggs, bought with wallet Cash. Odds are exact weights (shown to players as percentages).
	EggOrder = { "Dusty", "Shiny", "Royal" },
	Eggs = {
		Dusty = { Key = "Dusty", Name = "DUSTY EGG", Price = 500, Color = C(200, 170, 130), Odds = { SockPuppy = 38, SoapSlime = 38, MopPup = 12, BroomBird = 12 } },
		Shiny = { Key = "Shiny", Name = "SHINY EGG", Price = 2000, Color = C(90, 200, 255), Odds = { MopPup = 30, BroomBird = 30, LaundryFrog = 22, VacuumCat = 15, DusterParrot = 3 } },
		Royal = { Key = "Royal", Name = "ROYAL EGG", Price = 6000, Color = C(200, 90, 255), Odds = { LaundryFrog = 30, VacuumCat = 25, DusterParrot = 22, RoombaTurtle = 20, GoldenBroomDragon = 3 } },
		-- Never sold: the guaranteed Rare-or-better egg for a Mega room's first clear.
		Attic = { Key = "Attic", Name = "ATTIC EGG", Price = 0, Hidden = true, Color = C(190, 140, 80), Odds = { LaundryFrog = 35, VacuumCat = 30, DusterParrot = 20, RoombaTurtle = 13, GoldenBroomDragon = 2 } },
	},

	-- Slots: 1, +1 at Cleaner level SlotLevel, +1 with the Pet Slot pass.
	BaseSlots = 1,
	SlotLevel = 10,
	MaxLevel = 10,
	LevelSpeedup = 0.03, -- each level makes trips this much shorter
	XPPerLevel = 25, -- objects cleaned to go from level n to n + 1: XPPerLevel * n

	-- The helper rules (see the header).
	MaxPerMinute = 12,
	FasterPetsMultiplier = 1.25, -- the Faster Pets pass: shorter trips and a higher cap
	SnackMultiplier = 2, -- Pet Snack: twice as fast (and twice the cap) for SnackSeconds
	SnackSeconds = 300,
	ActiveWindow = 60, -- pets rest after this long without the player playing
	Reach = 26, -- studs from the owner a pet looks for junk
	SafeRadius = 7, -- never this close (XZ) to the hidden object's spot
	RightBinChance = 0.5, -- other pets find the right bin this often
	PetBurstSafeRadius = 8,

	-- The index: finding every pet pays this and a title.
	IndexReward = 1000,
	IndexTitle = "Pet Whisperer",
}

function PetConfig.Get(key: string): PetDef?
	return ByKey[key]
end

-- Trip time for a pet at a level (before passes and snacks).
function PetConfig.Interval(key: string, level: number): number
	local def = ByKey[key]
	return def.Interval * (1 - PetConfig.LevelSpeedup * (math.clamp(level, 1, PetConfig.MaxLevel) - 1))
end

function PetConfig.XPToNext(level: number): number
	return PetConfig.XPPerLevel * level
end

-- An egg's odds as { { Key, Chance (0-1) } }, rarest last.
function PetConfig.EggOdds(eggKey: string): { { Key: string, Chance: number } }
	local egg = PetConfig.Eggs[eggKey]
	local total = 0
	for _, w in pairs(egg.Odds) do
		total += w
	end
	local list = {}
	for key, w in pairs(egg.Odds) do
		table.insert(list, { Key = key, Chance = w / total })
	end
	table.sort(list, function(a, b)
		if a.Chance ~= b.Chance then
			return a.Chance > b.Chance
		end
		return a.Key < b.Key
	end)
	return list
end

return PetConfig
