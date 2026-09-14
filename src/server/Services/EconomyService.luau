--[[
	Room Cash. The only currency. Earned by cleaning objects into deposit bins
	(DepositService), spent on room upgrades. Server-owned; clients only read RoomCash.
]]

local EconomyService = {}

function EconomyService.GetCash(player: Player): number
	return player:GetAttribute("RoomCash") or 0
end

function EconomyService.AddCash(player: Player, amount: number)
	player:SetAttribute("RoomCash", math.max(0, math.floor(EconomyService.GetCash(player) + amount + 0.5)))
end

function EconomyService.TrySpend(player: Player, amount: number): boolean
	local cash = EconomyService.GetCash(player)
	if cash < amount then
		return false
	end
	player:SetAttribute("RoomCash", cash - amount)
	return true
end

return EconomyService
