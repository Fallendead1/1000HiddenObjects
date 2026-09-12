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
		AutoSell = 0, -- suggested 199 R$
		BigBag = 0, -- suggested 79 R$
		FastSearch = 0, -- suggested 149 R$
		WiderReach = 0, -- suggested 99 R$
		VIP = 0, -- suggested 299 R$
	},

	Products = {
		QuickHint = 0, -- suggested 19 R$
		SuperHint = 0, -- suggested 39 R$
		SearchPower10Min = 0, -- suggested 49 R$
		Cash10Min = 0, -- suggested 29 R$
		TeamSearchSurge = 0, -- suggested 129 R$
		TrashBomb = 0, -- suggested 79 R$
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
		BigBagMultiplier = 1.5,
		FastSearchIntervalMultiplier = 0.8,
		WiderReachMultiplier = 1.3,
		VIPWalkSpeedMultiplier = 1.1,
		VIPFreeSuperHintsPerMatch = 1,

		BoostDurationSeconds = 600,
		SearchPowerBoostMultiplier = 2,
		CashBoostMultiplier = 2,
		TeamSurgeMultiplier = 1.5,

		TrashBombRoomFraction = 0.02,
		TrashBombMaxDistance = 30,
		SuperHintDuration = 15,
		RegionHighlightDuration = 8,
	},
}

local GamepassDefs: { ProductDef } = {
	{ Key = "DoubleCash", Id = 0, Name = "2X CASH", Description = "Every sold bag gives double Cash. Forever.", SuggestedPrice = 149, Tab = "Permanent", Icon = "$$" },
	{ Key = "AutoSell", Id = 0, Name = "AUTO SELL", Description = "Never run back to the Trash Chute when your bag fills.", SuggestedPrice = 199, Tab = "Permanent", Icon = "AS" },
	{ Key = "BigBag", Id = 0, Name = "BIG BAG", Description = "+50% bag capacity at every bag level.", SuggestedPrice = 79, Tab = "Permanent", Icon = "BB" },
	{ Key = "FastSearch", Id = 0, Name = "FAST SEARCH", Description = "Search ticks 20% faster. Forever.", SuggestedPrice = 149, Tab = "Permanent", Icon = "FS" },
	{ Key = "WiderReach", Id = 0, Name = "WIDER REACH", Description = "+30% search range.", SuggestedPrice = 99, Tab = "Permanent", Icon = "WR" },
	{ Key = "VIP", Id = 0, Name = "VIP SEARCHER", Description = "Gold tag, lobby trail, +10% speed in matches and a free Super Hint every match.", SuggestedPrice = 299, Tab = "Permanent", Icon = "VIP" },
}

local ProductDefs: { ProductDef } = {
	{ Key = "SearchPower10Min", Id = 0, Name = "2X SEARCH POWER", Description = "Double your search power for 10 minutes.", SuggestedPrice = 49, Tab = "Boosts", MatchOnly = true, Icon = "2X" },
	{ Key = "Cash10Min", Id = 0, Name = "2X CASH BOOST", Description = "Double Cash from selling for 10 minutes.", SuggestedPrice = 29, Tab = "Boosts", MatchOnly = true, Icon = "$2" },
	{ Key = "TeamSearchSurge", Id = 0, Name = "TEAM SEARCH SURGE", Description = "Everyone in your match gets +50% search power for 10 minutes.", SuggestedPrice = 129, Tab = "Boosts", MatchOnly = true, Icon = "TM" },
	{ Key = "QuickHint", Id = 0, Name = "QUICK HINT", Description = "Instantly receive the next clue.", SuggestedPrice = 19, Tab = "Help", MatchOnly = true, Icon = "?" },
	{ Key = "SuperHint", Id = 0, Name = "SUPER HINT", Description = "Highlight the correct search region for 15 seconds.", SuggestedPrice = 39, Tab = "Help", MatchOnly = true, Icon = "??" },
	{ Key = "TrashBomb", Id = 0, Name = "TRASH BOMB", Description = "Blast a pile and clear a huge chunk of mess instantly.", SuggestedPrice = 79, Tab = "Help", MatchOnly = true, Icon = "TB" },
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
