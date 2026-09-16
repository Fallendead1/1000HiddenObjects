--[[
	The lasting Cash wallet (EconomyConfig). Room Cash (EconomyService) resets every room; the
	wallet keeps what was saved from rooms, gifts and rewards, and pays for eggs.
	Server-owned; the client reads the "Wallet" attribute. FX event to the player: Wallet
	{ Amount, Reason } whenever something is saved (the HUD counts it up).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)

local WalletService = {}

-- Fractions of a Cash saved from deposits, per player (paid out once they add up to 1).
local pending: { [Player]: number } = {}
-- Saved from deposits during the current room, for the results screen.
local roomSaved: { [Player]: number } = {}

function WalletService.Get(player: Player): number
	local data = Services.DataService.Get(player)
	return data and data.Wallet or 0
end

-- Saves `amount` to the wallet. `source` names it for analytics (Gameplay, TimedReward, ...).
function WalletService.Add(player: Player, amount: number, source: string, sku: string, quiet: boolean?): boolean
	amount = math.floor(amount)
	if amount <= 0 then
		return false
	end
	local balance = 0
	local ok = Services.DataService.Update(player, function(data)
		data.Wallet += amount
		data.WalletEarned += amount
		balance = data.Wallet
	end)
	if not ok then
		return false
	end
	Services.AnalyticsService.Economy(player, "Source", "Wallet", amount, balance, source, sku)
	if not quiet then
		Remotes.Event("FXEvent"):FireClient(player, "Wallet", { Amount = amount, Reason = sku })
	end
	return true
end

-- Spends from the wallet. Returns false (and spends nothing) if there isn't enough.
function WalletService.TrySpend(player: Player, amount: number, sink: string, sku: string): boolean
	amount = math.floor(amount)
	local data = Services.DataService.Get(player)
	if not data or amount < 0 or data.Wallet < amount then
		return false
	end
	local balance = 0
	Services.DataService.Update(player, function(d)
		d.Wallet -= amount
		balance = d.Wallet
	end)
	Services.AnalyticsService.Economy(player, "Sink", "Wallet", amount, balance, sink, sku)
	return true
end

-- A deposit's base pay (before paid multipliers): its share is saved, quietly (the results
-- screen shows the room's total).
function WalletService.OnDeposit(player: Player, basePay: number, sku: string)
	local share = (pending[player] or 0) + basePay * EconomyConfig.WalletShare
	local whole = math.floor(share)
	pending[player] = share - whole
	if whole > 0 and WalletService.Add(player, whole, "Gameplay", sku, true) then
		roomSaved[player] = (roomSaved[player] or 0) + whole
		player:SetAttribute("RoomSaved", roomSaved[player])
	end
end

-- What this room's deposits have saved so far (reset when a room starts).
function WalletService.RoomSaved(player: Player): number
	return roomSaved[player] or 0
end

function WalletService.ResetRoom(player: Player)
	roomSaved[player] = 0
	player:SetAttribute("RoomSaved", 0)
end

function WalletService.Init()
	Players.PlayerRemoving:Connect(function(player)
		pending[player] = nil
		roomSaved[player] = nil
	end)
end

return WalletService
