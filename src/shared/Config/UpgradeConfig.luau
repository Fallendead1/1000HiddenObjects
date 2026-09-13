--[[
	Room upgrade definitions. Levels are 1-indexed; level 1 is the free starting value.
	Order defines the order cards appear in the Upgrades menu.

	Strength   -> maximum object Weight the player can grab.
	ThrowPower -> launch speed (studs/second) of a thrown object before weight falloff.
	GrabSpeed  -> held-object responsiveness multiplier (heavy items feel sluggish without it).
	MoveSpeed  -> WalkSpeed.
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
		Key = "Strength",
		Name = "STRENGTH",
		Description = "Lift heavier objects.",
		Icon = "ST",
		Attribute = "StrengthLevel",
		Format = function(v) return "Weight " .. tostring(math.floor(v)) end,
		Levels = {
			{ Value = 2, Cost = 0 },
			{ Value = 3, Cost = 60 },
			{ Value = 4, Cost = 200 },
			{ Value = 5, Cost = 450 },
			{ Value = 6, Cost = 900 },
			{ Value = 8, Cost = 1500 },
		},
	},
	{
		Key = "ThrowPower",
		Name = "THROW POWER",
		Description = "Throw objects farther.",
		Icon = "TH",
		Attribute = "ThrowPowerLevel",
		Format = function(v) return tostring(math.floor(v)) end,
		Levels = {
			{ Value = 50, Cost = 0 },
			{ Value = 60, Cost = 50 },
			{ Value = 70, Cost = 150 },
			{ Value = 82, Cost = 350 },
			{ Value = 95, Cost = 700 },
		},
	},
	{
		Key = "GrabSpeed",
		Name = "GRAB SPEED",
		Description = "Handle heavy objects faster.",
		Icon = "GR",
		Attribute = "GrabSpeedLevel",
		Format = function(v) return string.format("%.2fx", v) end,
		Levels = {
			{ Value = 1.0, Cost = 0 },
			{ Value = 1.25, Cost = 40 },
			{ Value = 1.5, Cost = 120 },
			{ Value = 1.8, Cost = 300 },
			{ Value = 2.2, Cost = 600 },
		},
	},
	{
		Key = "MoveSpeed",
		Name = "MOVE SPEED",
		Description = "Run around the room faster.",
		Icon = "MV",
		Attribute = "MoveSpeedLevel",
		Format = function(v) return tostring(math.floor(v)) end,
		Levels = {
			{ Value = 16, Cost = 0 },
			{ Value = 18, Cost = 60 },
			{ Value = 20, Cost = 180 },
			{ Value = 22, Cost = 400 },
			{ Value = 24, Cost = 800 },
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

-- Lowest Strength level whose max weight covers `weight` (nil if no level can).
function UpgradeConfig.StrengthLevelFor(weight: number): number?
	for i, lvl in ipairs(ByKey.Strength.Levels) do
		if lvl.Value >= weight then
			return i
		end
	end
	return nil
end

return UpgradeConfig
