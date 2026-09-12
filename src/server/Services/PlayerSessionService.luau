--[[
	Server-authoritative per-player match session state, replicated through player attributes.
	Also owns character setup (collision group, walk speed) and derived stat calculations
	(search power, interval, reach, cash multiplier) that fold in upgrades, passes and boosts.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)

local Services = require(script.Parent)

local PlayerSessionService = {}

local PLAYER_GROUP = "Players"

local SessionDefaults = {
	InMatch = false,
	RoomCash = 0,
	BagCurrent = 0,
	BagCapacity = 40,
	SearchPowerLevel = 1,
	SearchSpeedLevel = 1,
	BagLevel = 1,
	MoveSpeedLevel = 1,
	ContributionMess = 0,
	SearchBoostExpires = 0,
	CashBoostExpires = 0,
	VIPFreeHints = 0,
	PendingTrashBombs = 0,
	HotCold = "",
	IsSearching = false,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setupCollisionGroup()
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
	end)
	if ok or true then
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)
		end)
	end
end

local function applyCollisionGroup(character: Model)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = PLAYER_GROUP
		end
	end
	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			desc.CollisionGroup = PLAYER_GROUP
		end
	end)
end

function PlayerSessionService.Init()
	setupCollisionGroup()

	local function onPlayer(player: Player)
		for k, v in pairs(SessionDefaults) do
			player:SetAttribute(k, v)
		end
		player:SetAttribute("Dev", Services.DevService.IsAuthorized(player))
		player.CharacterAdded:Connect(function(character)
			applyCollisionGroup(character)
			PlayerSessionService.ApplyWalkSpeed(player)
			Services.MatchService.OnCharacterAdded(player, character)
		end)
		if player.Character then
			applyCollisionGroup(player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

function PlayerSessionService.Reset(player: Player)
	for k, v in pairs(SessionDefaults) do
		player:SetAttribute(k, v)
	end
	if Services.MonetizationService.OwnsPass(player, "VIP") then
		player:SetAttribute("VIPFreeHints", MonetizationConfig.Effects.VIPFreeSuperHintsPerMatch)
	end
	PlayerSessionService.RecomputeDerived(player)
end

function PlayerSessionService.RestoreFromCheckpoint(player: Player, checkpoint)
	player:SetAttribute("RoomCash", checkpoint.RoomCash or 0)
	player:SetAttribute("SearchPowerLevel", checkpoint.SearchPowerLevel or 1)
	player:SetAttribute("SearchSpeedLevel", checkpoint.SearchSpeedLevel or 1)
	player:SetAttribute("BagLevel", checkpoint.BagLevel or 1)
	player:SetAttribute("MoveSpeedLevel", checkpoint.MoveSpeedLevel or 1)
	PlayerSessionService.RecomputeDerived(player)
end

function PlayerSessionService.GetLevel(player: Player, key: string): number
	local def = UpgradeConfig.ByKey[key]
	return player:GetAttribute(def.Attribute) or 1
end

function PlayerSessionService.GetBagCapacity(player: Player): number
	local base = UpgradeConfig.GetValue("BagSize", PlayerSessionService.GetLevel(player, "BagSize"))
	if Services.MonetizationService.OwnsPass(player, "BigBag") then
		base = base * MonetizationConfig.Effects.BigBagMultiplier
	end
	return math.floor(base + 0.5)
end

function PlayerSessionService.GetWalkSpeed(player: Player): number
	local speed = UpgradeConfig.GetValue("MoveSpeed", PlayerSessionService.GetLevel(player, "MoveSpeed"))
	if player:GetAttribute("InMatch") and Services.MonetizationService.OwnsPass(player, "VIP") then
		speed = speed * MonetizationConfig.Effects.VIPWalkSpeedMultiplier
	end
	return speed
end

-- Effective mess removed per tick before cluster/bag clamping.
function PlayerSessionService.GetSearchPower(player: Player, teamSurgeExpires: number?): number
	local base = UpgradeConfig.GetValue("SearchPower", PlayerSessionService.GetLevel(player, "SearchPower"))
	local temp = 1
	if (player:GetAttribute("SearchBoostExpires") or 0) > now() then
		temp *= MonetizationConfig.Effects.SearchPowerBoostMultiplier
	end
	if teamSurgeExpires and teamSurgeExpires > now() then
		temp *= MonetizationConfig.Effects.TeamSurgeMultiplier
	end
	temp = math.min(temp, GameConfig.MaxTempSearchPowerMultiplier)
	return base * temp * GameConfig.BaseMessPerTick
end

function PlayerSessionService.GetSearchInterval(player: Player): number
	local interval = UpgradeConfig.GetValue("SearchSpeed", PlayerSessionService.GetLevel(player, "SearchSpeed"))
	if Services.MonetizationService.OwnsPass(player, "FastSearch") then
		interval *= MonetizationConfig.Effects.FastSearchIntervalMultiplier
	end
	return interval
end

function PlayerSessionService.GetReach(player: Player): number
	local reach = GameConfig.SearchDistance
	if Services.MonetizationService.OwnsPass(player, "WiderReach") then
		reach *= MonetizationConfig.Effects.WiderReachMultiplier
	end
	return reach
end

function PlayerSessionService.GetCashMultiplier(player: Player): number
	local mult = 1
	if Services.MonetizationService.OwnsPass(player, "DoubleCash") then
		mult *= MonetizationConfig.Effects.DoubleCashMultiplier
	end
	if (player:GetAttribute("CashBoostExpires") or 0) > now() then
		mult *= MonetizationConfig.Effects.CashBoostMultiplier
	end
	return math.min(mult, GameConfig.MaxCashMultiplier)
end

function PlayerSessionService.RecomputeDerived(player: Player)
	player:SetAttribute("BagCapacity", PlayerSessionService.GetBagCapacity(player))
	player:SetAttribute("SearchReach", PlayerSessionService.GetReach(player))
	PlayerSessionService.ApplyWalkSpeed(player)
end

function PlayerSessionService.ApplyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = PlayerSessionService.GetWalkSpeed(player)
	end
end

function PlayerSessionService.ExtendBoost(player: Player, attribute: string, seconds: number)
	local current = player:GetAttribute(attribute) or 0
	local base = math.max(current, now())
	player:SetAttribute(attribute, base + seconds)
end

return PlayerSessionService
