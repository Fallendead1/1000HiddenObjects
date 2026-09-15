local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local FormatUtil = require(Shared.Utility.FormatUtil)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local UpgradeService = {}

local limiter = RateLimiter.new(5, 5)

function UpgradeService.Init()
	Remotes.Function("RequestUpgrade").OnServerInvoke = function(player: Player, key: any)
		if not limiter:Allow(player) then
			return false, "Slow down."
		end
		if type(key) ~= "string" or not UpgradeConfig.ByKey[key] then
			return false, "Unknown upgrade."
		end
		return UpgradeService.TryUpgrade(player, key)
	end
end

function UpgradeService.TryUpgrade(player: Player, key: string): (boolean, string)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or (match.State ~= "Searching" and match.State ~= "Countdown") then
		return false, "Upgrades are only available inside a room."
	end
	local def = UpgradeConfig.ByKey[key]
	local level = player:GetAttribute(def.Attribute) or 1
	local cost = UpgradeConfig.GetNextCost(key, level)
	if not cost then
		return false, "MAXED"
	end
	-- A player's very first room (the tutorial) has one upgrade on the house, so the tutorial's
	-- "buy an upgrade" step works before they've earned enough Cash. Set per room by MatchService.
	local free = player:GetAttribute("FreeUpgrade") == true
	if not free then
		local cash = player:GetAttribute("RoomCash") or 0
		if cash < cost then
			return false, string.format("Need %s more.", FormatUtil.CashExact(cost - cash))
		end
		if not Services.EconomyService.TrySpend(player, cost) then
			return false, "Not enough Cash."
		end
	end
	player:SetAttribute("FreeUpgrade", false)
	player:SetAttribute(def.Attribute, level + 1)
	Services.PlayerSessionService.RecomputeDerived(player)
	Remotes.Event("FXEvent"):FireClient(player, "Upgrade", { Key = key, Level = level + 1 })
	Services.AnalyticsService.Log("upgrade_purchase_cash", player, { Upgrade = key, Level = level + 1, RoomId = match.RoomId, Free = free })
	return true, string.format("%s upgraded!", def.Name)
end

return UpgradeService
