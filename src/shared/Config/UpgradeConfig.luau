--[[
	Room upgrade definitions. Levels are 1-indexed; level 1 is the free starting value.
	Order defines the order cards appear in the Upgrades menu.
]]

export type UpgradeLevel = { Value: number, Cost: number }
export type UpgradeDef = {
	Key: string,
	Name: string,
	Description: string,
	Icon: string,
	Attribute: string,
	Format: (number) -> string,
	Levels: { UpgradeLevel },
}

local Upgrades: { UpgradeDef } = {
	{
		Key = "SearchPower",
		Name = "SEARCH POWER",
		Description = "Clear more mess every search.",
		Icon = "PW",
		Attribute = "SearchPowerLevel",
		Format = function(v) return string.format("%.2fx", v) end,
		Levels = {
			{ Value = 1.00, Cost = 0 },
			{ Value = 1.20, Cost = 150 },
			{ Value = 1.45, Cost = 600 },
			{ Value = 1.75, Cost = 1800 },
			{ Value = 2.15, Cost = 5000 },
			{ Value = 2.70, Cost = 11000 },
			{ Value = 3.40, Cost = 26000 },
			{ Value = 4.25, Cost = 55000 },
		},
	},
	{
		Key = "SearchSpeed",
		Name = "SEARCH SPEED",
		Description = "Search ticks happen faster.",
		Icon = "SP",
		Attribute = "SearchSpeedLevel",
		Format = function(v) return string.format("%.2fs", v) end,
		Levels = {
			{ Value = 0.50, Cost = 0 },
			{ Value = 0.46, Cost = 250 },
			{ Value = 0.42, Cost = 900 },
			{ Value = 0.38, Cost = 2800 },
			{ Value = 0.34, Cost = 7000 },
			{ Value = 0.30, Cost = 18000 },
		},
	},
	{
		Key = "BagSize",
		Name = "BAG SIZE",
		Description = "Carry more mess before selling.",
		Icon = "BG",
		Attribute = "BagLevel",
		Format = function(v) return tostring(math.floor(v)) end,
		Levels = {
			{ Value = 40, Cost = 0 },
			{ Value = 80, Cost = 120 },
			{ Value = 150, Cost = 500 },
			{ Value = 275, Cost = 1700 },
			{ Value = 500, Cost = 5500 },
			{ Value = 900, Cost = 14000 },
			{ Value = 1600, Cost = 38000 },
		},
	},
	{
		Key = "MoveSpeed",
		Name = "MOVE SPEED",
		Description = "Run between piles faster.",
		Icon = "MV",
		Attribute = "MoveSpeedLevel",
		Format = function(v) return tostring(math.floor(v)) end,
		Levels = {
			{ Value = 16, Cost = 0 },
			{ Value = 18, Cost = 300 },
			{ Value = 20, Cost = 1200 },
			{ Value = 22, Cost = 4000 },
			{ Value = 24, Cost = 12000 },
		},
	},
}

local ByKey: { [string]: UpgradeDef } = {}
for _, def in ipairs(Upgrades) do
	ByKey[def.Key] = def
end

local UpgradeConfig = {
	List = Upgrades,
	ByKey = ByKey,
}

function UpgradeConfig.GetValue(key: string, level: number): number
	local def = ByKey[key]
	local idx = math.clamp(level, 1, #def.Levels)
	return def.Levels[idx].Value
end

function UpgradeConfig.GetMaxLevel(key: string): number
	return #ByKey[key].Levels
end

function UpgradeConfig.GetNextCost(key: string, level: number): number?
	local def = ByKey[key]
	local nextLevel = def.Levels[level + 1]
	return nextLevel and nextLevel.Cost or nil
end

return UpgradeConfig
