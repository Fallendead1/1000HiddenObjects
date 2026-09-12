--[[
	Room Cash: selling bags at the Trash Chute (proximity, automatic), Auto Sell pass,
	cash multipliers and spending. Cash is a per-room resource owned by the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)
local FormatUtil = require(Shared.Utility.FormatUtil)

local Services = require(script.Parent)

local EconomyService = {}

local autoSellPending: { [Player]: boolean } = {}

function EconomyService.Init() end

function EconomyService.Start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.SellPollInterval)
			local match = Services.MatchService.GetMatch()
			if match and match.State == "Searching" and match.Runtime.TrashChuteZone then
				local zonePos = match.Runtime.TrashChuteZone.Position
				local radius = match.Runtime.TrashChuteRadius
				for _, player in ipairs(match.Players) do
					local bag = player:GetAttribute("BagCurrent") or 0
					if bag > 0 then
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if root and (root.Position - zonePos).Magnitude <= radius then
							EconomyService.Sell(player, match, false)
						end
					end
				end
			end
		end
	end)
end

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

function EconomyService.Sell(player: Player, match, auto: boolean)
	local bag = player:GetAttribute("BagCurrent") or 0
	if bag <= 0 then
		return
	end
	local mult = Services.PlayerSessionService.GetCashMultiplier(player)
	local earned = math.floor(bag * GameConfig.CashPerMess * mult + 0.5)
	player:SetAttribute("BagCurrent", 0)
	EconomyService.AddCash(player, earned)
	autoSellPending[player] = nil

	if not match.FirstSaleLogged then
		match.FirstSaleLogged = true
		Services.AnalyticsService.Log("first_sale", player, { RoomId = match.RoomId })
	end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	Remotes.Event("FXEvent"):FireClient(player, "Sell", {
		Amount = earned,
		Auto = auto,
		Position = root and root.Position or nil,
		Text = (auto and "AUTO SOLD " or "") .. "+" .. FormatUtil.CashExact(earned),
	})
	-- Let the search loop resume for a player who was blocked by a full bag.
	Services.SearchService.OnBagChanged(player)
end

-- Called by SearchService whenever the bag reaches capacity.
function EconomyService.OnBagFull(player: Player, match)
	if Services.MonetizationService.OwnsPass(player, "AutoSell") then
		if autoSellPending[player] then
			return
		end
		autoSellPending[player] = true
		task.delay(GameConfig.AutoSellDelay, function()
			if autoSellPending[player] and player.Parent and match.State == "Searching" then
				EconomyService.Sell(player, match, true)
			end
			autoSellPending[player] = nil
		end)
	else
		Remotes.Event("FXEvent"):FireClient(player, "BagFull", {
			ChutePosition = match.Runtime.TrashChuteZone and match.Runtime.TrashChuteZone.Position or nil,
		})
	end
end

function EconomyService.ClearPlayer(player: Player)
	autoSellPending[player] = nil
end

return EconomyService
