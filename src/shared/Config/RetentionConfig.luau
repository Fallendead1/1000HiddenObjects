--[[
	Everything that keeps a session going (RetentionService, GiftController, SpinController,
	OfferController). Rewards never include anything bought with Robux, and nothing here ever
	opens a purchase prompt by itself.

	Reward shapes (RetentionService.Grant):
	  { Cash = n }                         saved to the wallet
	  { XP = n }                           Cleaner XP
	  { Hint = "QuickHint" | "SuperHint" } saved for your next room (clue rules still apply)
	  { Boost = "CashBoost" | "StrengthBoost", Seconds = n }  starts in your next room
	  { Egg = "Dusty" | "Shiny" | "Royal" } hatched on the spot (once pets exist)
	Several keys can be combined. Text is what the player reads.
]]

return {
	-- Playtime gifts: the ladder counts ACTIVE minutes today (UTC) across lobby and rooms. A
	-- player counts as active for ActiveWindow seconds after moving or doing anything.
	ActiveWindow = 60,
	PlaytimeGifts = {
		{ Minutes = 1, Text = "$50 Cash", Reward = { Cash = 50 }, Color = "Cash" },
		{ Minutes = 3, Text = "+100 XP", Reward = { XP = 100 }, Color = "Cyan" },
		{ Minutes = 5, Text = "$100 Cash", Reward = { Cash = 100 }, Color = "Cash" },
		{ Minutes = 8, Text = "Free Quick Hint", Reward = { Hint = "QuickHint" }, Color = "Purple" },
		{ Minutes = 12, Text = "$150 Cash", Reward = { Cash = 150 }, Color = "Cash" },
		{ Minutes = 16, Text = "10 min 2X Cash", Reward = { Boost = "CashBoost", Seconds = 600 }, Color = "Green" },
		{ Minutes = 20, Text = "$250 Cash", Reward = { Cash = 250 }, Color = "Cash" },
		{ Minutes = 25, Text = "$400 Cash", Reward = { Cash = 400 }, Color = "Gold" },
		{ Minutes = 30, Text = "$300 Cash + 10 min 2X Strength", Reward = { Cash = 300, Boost = "StrengthBoost", Seconds = 600 }, Color = "Orange" },
	},

	-- "Next gift in N objects": every Need(level) objects cleaned into bins pays a small gift.
	GiftBar = {
		FirstNeed = 10,
		NeedStep = 5,
		MaxNeed = 30,
		CashBase = 20,
		CashStep = 10,
		MaxCash = 100,
		XP = 20,
	},

	-- First-time moments, once per player. Order = the order they usually happen.
	Firsts = {
		{ Key = "Deposit", Title = "FIRST CLEAN!", Reward = { Cash = 25 } },
		{ Key = "Chunk", Title = "FIRST PACKED JUNK!", Reward = { Cash = 25 } },
		{ Key = "Upgrade", Title = "FIRST UPGRADE!", Reward = { Cash = 25 } },
		{ Key = "Swish", Title = "FIRST SWISH!", Reward = { Cash = 50 } },
		{ Key = "Treasure", Title = "FIRST TREASURE!", Reward = { Cash = 50 } },
		{ Key = "Streak5", Title = "FIRST x5 STREAK!", Reward = { Cash = 50 } },
		{ Key = "LevelUp", Title = "FIRST LEVEL UP!", Reward = { Cash = 50 } },
		{ Key = "Room", Title = "FIRST ROOM CLEARED!", Reward = { Cash = 100 } },
	},

	-- The free daily spin (free spins only, never sold). Weights are shown to players as odds.
	-- The order is the order of the slices on the wheel's face (UIImages Spin_Wheel, drawn by
	-- art/make_ui_images.ps1: first slice at the top, clockwise), so keep the two in step.
	-- Short = the few characters on the slice; Pet = a helper pet as the prize.
	Spin = {
		{ Text = "$50", Short = "$50", Reward = { Cash = 50 }, Weight = 24, Color = "Cash" },
		{ Text = "+200 XP", Short = "+200", Reward = { XP = 200 }, Weight = 15, Color = "Cyan" },
		{ Text = "$100", Short = "$100", Reward = { Cash = 100 }, Weight = 19, Color = "Green" },
		{ Text = "Quick Hint", Short = "HINT", Reward = { Hint = "QuickHint" }, Weight = 12, Color = "Purple" },
		{ Text = "Mop Pup (pet)", Short = "PET", Reward = { Pet = "MopPup" }, Weight = 3, Color = "Gold" },
		{ Text = "$250", Short = "$250", Reward = { Cash = 250 }, Weight = 8, Color = "Orange" },
		{ Text = "10 min 2X Cash", Short = "2X", Reward = { Boost = "CashBoost", Seconds = 600 }, Weight = 9, Color = "Pink" },
		{ Text = "Super Hint", Short = "SUPER", Reward = { Hint = "SuperHint" }, Weight = 7, Color = "Red" },
		{ Text = "$1,000", Short = "$1,000", Reward = { Cash = 1000 }, Weight = 2, Color = "Gold" },
		{ Text = "Golden Broom Dragon (pet)", Short = "DRAGON", Reward = { Pet = "GoldenBroomDragon" }, Weight = 1, Color = "Gold" },
	},

	-- One missed day a week keeps the daily login streak (used automatically).
	StreakFreezePerWeek = 1,

	-- Results screen: the next room starts by itself after this many seconds (cancel stops it).
	AutoNextSeconds = 10,
	-- How long the room waits for the rest of the party to choose NEXT ROOM.
	NextRoomVoteSeconds = 12,

	-- Contextual offers (OfferController). A chip appears next to the problem; tapping it opens
	-- Roblox's purchase prompt. Seconds = how long a chip stays, Cooldown = before it may show again.
	Offers = {
		LiftItNow = { Seconds = 7, Cooldown = 45 },
		JunkBlaster = { Seconds = 8, Cooldown = 90, Radius = 12, NearChunks = 3, ChipRadius = 10 },
		SpeedBoost10Min = { Seconds = 8, AfterSearchSeconds = 90 },
		TreasureRadar = { Seconds = 8 },
		DoubleXP15Min = { Seconds = 8, AtFraction = 0.75 },
		PetSnack = { Seconds = 8, Cooldown = 300 },
	},
	-- Junk Blaster never bursts packed junk this close to the hidden object, and leaves as
	-- much junk around a few other hiding spots so what's left says nothing.
	BlasterSafeRadius = 8,
	BlasterDecoys = 3,
	BlasterMaxBursts = 8,
	LiftItNowSeconds = 60,
}
