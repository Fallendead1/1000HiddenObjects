--[[
	Lasting progression that is NOT a currency (nothing here can be spent):
	  Cleaner XP -> Cleaner Level + title (shown over your head and in the HUD)
	  Room mastery stars (3 per room)
	  Daily challenges (3 per player per UTC day, rewarded automatically)
]]

local ProgressionConfig = {
	XP = {
		Deposit = 2, -- every object cleaned into a bin
		DepositMatch = 1, -- bonus for the matching bin
		Swish = 2,
		Treasure = 15,
		ChunkBurst = 1,
		RoomComplete = 75, -- everyone in the party
		KeyFound = 150, -- the finder
		FirstClear = 200,
		Star = 50, -- per newly earned mastery star
		Challenge = 100,
	},

	MaxLevel = 100,

	-- { level reached, title }
	Titles = {
		{ 1, "Messy Beginner" },
		{ 5, "Tidy Rookie" },
		{ 10, "Sock Hunter" },
		{ 15, "Clutter Crusher" },
		{ 20, "Junk Digger" },
		{ 30, "Mess Master" },
		{ 40, "Clean Machine" },
		{ 50, "Legendary Cleaner" },
		{ 75, "Dust Destroyer" },
		{ 100, "The Golden Broom" },
	},

	-- Room mastery stars (bitmask).
	Stars = {
		{ Key = "Key", Bit = 1, Text = "Find the object" },
		{ Key = "Clean", Bit = 2, Text = "Clean 25% of the room", Fraction = 0.25 },
		{ Key = "Treasure", Bit = 4, Text = "Clean 10 treasures into bins in one run", Count = 10 },
	},

	DailyCount = 3,
	-- Stat names are tracked by ProgressionService. Max = the best single value counts (not a sum).
	-- MinRoom = only offered once that room is unlocked (its bins only stand in that room).
	Challenges = {
		{ Id = "Clean40", Text = "Clean %d objects into bins", Stat = "Deposit", Goal = 40 },
		{ Id = "Laundry15", Text = "Clean %d clothes into the Laundry Basket", Stat = "Match_Laundry", Goal = 15 },
		{ Id = "Books15", Text = "Clean %d books or papers into the Book Cart", Stat = "Match_Books", Goal = 15 },
		{ Id = "Toys10", Text = "Clean %d toys into the Toy Bin", Stat = "Match_Toys", Goal = 10 },
		{ Id = "Trash15", Text = "Clean %d cans, cups or cables into the Trash Can", Stat = "Match_Trash", Goal = 15 },
		{ Id = "Heavy5", Text = "Haul %d heavy things to the Donation Box", Stat = "Match_Donation", Goal = 5 },
		{ Id = "Swish5", Text = "Land %d swishes", Stat = "Swish", Goal = 5 },
		{ Id = "Streak5", Text = "Reach a x%d deposit streak", Stat = "StreakMax", Goal = 5, Max = true },
		{ Id = "Treasure2", Text = "Find %d treasures", Stat = "Treasure", Goal = 2 },
		{ Id = "Chunks10", Text = "Break open %d packed junk", Stat = "ChunkBurst", Goal = 10 },
		{ Id = "Room1", Text = "Complete %d room", Stat = "RoomComplete", Goal = 1 },
		{ Id = "Dishes20", Text = "Wash %d dishes in the Dish Rack", Stat = "Match_DishRack", Goal = 20, MinRoom = 2 },
		{ Id = "Pantry15", Text = "Stock the pantry with %d foods", Stat = "Match_Pantry", Goal = 15, MinRoom = 2 },
		{ Id = "Recycle15", Text = "Recycle %d things", Stat = "Match_Recycling", Goal = 15, MinRoom = 2 },
		{ Id = "Games5", Text = "Put away %d games on the Game Shelf", Stat = "Match_GameShelf", Goal = 5, MinRoom = 3 },
		{ Id = "Tools15", Text = "Put away %d tools in the Toolbox", Stat = "Match_Toolbox", Goal = 15, MinRoom = 4 },
		{ Id = "Sports10", Text = "Clean %d sports things into the Sports Bin", Stat = "Match_SportsBin", Goal = 10, MinRoom = 4 },
	},

	-- Daily login rewards: a 7-day cycle; missing a day starts over at day 1. Hints and boosts are
	-- saved for your next room (a boost never ticks away in the lobby). Never a currency.
	LoginRewards = {
		{ Kind = "XP", XP = 150, Text = "+150 XP" },
		{ Kind = "Hint", Hint = "QuickHint", Text = "Free Quick Hint" },
		{ Kind = "Boost", Boost = "CashBoost", Seconds = 600, Text = "10 min 2X Cash" },
		{ Kind = "XP", XP = 300, Text = "+300 XP" },
		{ Kind = "Hint", Hint = "SuperHint", Text = "Free Super Hint" },
		{ Kind = "Boost", Boost = "StrengthBoost", Seconds = 600, Text = "10 min 2X Strength" },
		{ Kind = "Bundle", XP = 600, Boost = "CashBoost", Seconds = 900, Text = "+600 XP & 15 min 2X Cash" },
	},

	-- Challenge rewards rotate by day and slot (never a currency).
	Rewards = {
		{ Kind = "Boost", Attribute = "CashBoostExpires", Seconds = 300, Text = "5 min 2X Cash" },
		{ Kind = "Hint", Text = "Free Quick Hint" },
		{ Kind = "Boost", Attribute = "StrengthBoostExpires", Seconds = 300, Text = "5 min 2X Strength" },
	},
}

-- XP needed to go from `level` to `level + 1`.
function ProgressionConfig.XPForLevel(level: number): number
	return 100 + (level - 1) * 40
end

-- Level, XP into that level, XP needed for the next one.
function ProgressionConfig.LevelFor(totalXP: number): (number, number, number)
	local level, remaining = 1, totalXP
	while level < ProgressionConfig.MaxLevel do
		local need = ProgressionConfig.XPForLevel(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return ProgressionConfig.MaxLevel, 0, 0
end

function ProgressionConfig.TitleFor(level: number): string
	local title = ProgressionConfig.Titles[1][2]
	for _, t in ipairs(ProgressionConfig.Titles) do
		if level >= t[1] then
			title = t[2]
		end
	end
	return title
end

function ProgressionConfig.Challenge(id: string)
	for _, c in ipairs(ProgressionConfig.Challenges) do
		if c.Id == id then
			return c
		end
	end
	return nil
end

return ProgressionConfig
