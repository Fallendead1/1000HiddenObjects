--[[
	Heavy objects: anyone can lift anything. What your Strength handles easily (the player's
	MaxWeight) moves and throws as always; every weight class above that makes the object slower
	to carry and shorter to throw. Upgrading Strength removes the penalty class by class.
	Used by the server (PlayerSessionService walk speed, ObjectService throws) and the client
	(GrabController's throw preview), so both always agree.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local Heavy = {}

-- Weight classes over what the player handles easily.
function Heavy.Over(weight: number, maxWeight: number): number
	return math.max(0, weight - maxWeight)
end

-- Walk speed multiplier while carrying it.
function Heavy.CarryFactor(weight: number, maxWeight: number): number
	return math.max(GameConfig.HeavyCarryMin, 1 - Heavy.Over(weight, maxWeight) * GameConfig.HeavyCarrySlow)
end

-- Throw speed multiplier.
function Heavy.ThrowFactor(weight: number, maxWeight: number): number
	return math.max(GameConfig.HeavyThrowMin, 1 - Heavy.Over(weight, maxWeight) * GameConfig.HeavyThrowLoss)
end

return Heavy
