--[[
	All monetization IDs and effect values. IDs are 0 until created on Creator Hub.
	With an ID of 0 the product is hidden in production and mocked in Studio/dev mode.
	Suggested prices are design recommendations only; the live price comes from MarketplaceService.
]]

export type ProductDef = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	SuggestedPrice: number,
	Tab: string, -- "Permanent" | "Boosts" | "Help"
	MatchOnly: boolean?,
	Icon: string,
}

local MonetizationConfig = {
	Gamepasses = {
		DoubleCash = 0, -- suggested 149 R$
		StrongerHands = 0, -- suggested 149 R$
		FastHands = 0, -- suggested 99 R$
		ThrowBoost = 0, -- suggested 99 R$
		VIP = 0, -- suggested 299 R$
	},

	Products = {
		QuickHint = 0, -- suggested 19 R$
		SuperHint = 0, -- suggested 39 R$
		Strength10Min = 0, -- suggested 49 R$
		Cash10Min = 0, -- suggested 29 R$
		TeamMuscleBoost = 0, -- suggested 129 R$
	},

	Badges = {
		FirstObject = 0,
		TenObjects = 0,
		HundredObjects = 0,
		FiveHundredObjects = 0,
		ThousandObjects = 0,
		FirstFinderWin = 0,
		Room001Speed = 0,
	},

	Effects = {
		DoubleCashMultiplier = 2,
		StrongerHandsWeightBonus = 1, -- +1 max weight, permanent
		FastHandsMultiplier = 1.3, -- grab responsiveness
		ThrowBoostMultiplier = 1.15,
		VIPWalkSpeedMultiplier = 1.1,
		VIPFreeSuperHintsPerMatch = 1,

		BoostDurationSeconds = 600,
		StrengthBoostMultiplier = 2, -- 2x max weight while active
		CashBoostMultiplier = 2,
		TeamMuscleStrengthMultiplier = 1.5,
		TeamMuscleThrowMultiplier = 1.25,

		SuperHintDuration = 15,
		RegionHighlightDuration = 8,
	},
}

local GamepassDefs: { ProductDef } = {
	{ Key = "DoubleCash", Id = 0, Name = "2X CASH", Description = "Double Cash from every newly moved object. Forever.", SuggestedPrice = 149, Tab = "Permanent", Icon = "$$" },
	{ Key = "StrongerHands", Id = 0, Name = "STRONGER HANDS", Description = "Lift one weight class heavier than your Strength. Forever.", SuggestedPrice = 149, Tab = "Permanent", Icon = "SH" },
	{ Key = "FastHands", Id = 0, Name = "FAST HANDS", Description = "Heavy objects feel lighter to handle. Forever.", SuggestedPrice = 99, Tab = "Permanent", Icon = "FH" },
	{ Key = "ThrowBoost", Id = 0, Name = "THROW BOOST", Description = "+15% throw power. Forever.", SuggestedPrice = 99, Tab = "Permanent", Icon = "TB" },
	{ Key = "VIP", Id = 0, Name = "VIP SEARCHER", Description = "Gold tag, +10% speed in rooms and a free Super Hint every room.", SuggestedPrice = 299, Tab = "Permanent", Icon = "VIP" },
}

local ProductDefs: { ProductDef } = {
	{ Key = "Strength10Min", Id = 0, Name = "2X STRENGTH", Description = "Lift twice the weight for 10 minutes.", SuggestedPrice = 49, Tab = "Boosts", MatchOnly = true, Icon = "2X" },
	{ Key = "Cash10Min", Id = 0, Name = "2X CASH BOOST", Description = "Double Cash from moved objects for 10 minutes.", SuggestedPrice = 29, Tab = "Boosts", MatchOnly = true, Icon = "$2" },
	{ Key = "TeamMuscleBoost", Id = 0, Name = "TEAM MUSCLE BOOST", Description = "Everyone in your room gets +50% Strength and +25% throw power for 10 minutes.", SuggestedPrice = 129, Tab = "Boosts", MatchOnly = true, Icon = "TM" },
	{ Key = "QuickHint", Id = 0, Name = "QUICK HINT", Description = "Instantly receive the next clue.", SuggestedPrice = 19, Tab = "Help", MatchOnly = true, Icon = "?" },
	{ Key = "SuperHint", Id = 0, Name = "SUPER HINT", Description = "Highlight the correct search region for 15 seconds.", SuggestedPrice = 39, Tab = "Help", MatchOnly = true, Icon = "??" },
}

-- Resolve IDs from the tables above so there is exactly one place to edit.
for _, def in ipairs(GamepassDefs) do
	def.Id = MonetizationConfig.Gamepasses[def.Key]
end
for _, def in ipairs(ProductDefs) do
	def.Id = MonetizationConfig.Products[def.Key]
end

MonetizationConfig.GamepassDefs = GamepassDefs
MonetizationConfig.ProductDefs = ProductDefs

function MonetizationConfig.FindDef(key: string): (ProductDef?, string?)
	for _, def in ipairs(GamepassDefs) do
		if def.Key == key then
			return def, "Gamepass"
		end
	end
	for _, def in ipairs(ProductDefs) do
		if def.Key == key then
			return def, "Product"
		end
	end
	return nil, nil
end

return MonetizationConfig
