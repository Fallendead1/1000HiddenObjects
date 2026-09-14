--[[
	Server-authoritative per-player match session state, replicated through player attributes,
	plus derived stats that fold upgrades, passes and boosts together:
	  GetMaxWeight (Strength), GetThrowSpeed, GetHoldResponsiveness (Strength level + FastHands),
	  GetWalkSpeed, GetCashMultiplier.
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
local Effects = MonetizationConfig.Effects

-- Defined further down; declared here because Init/RecomputeDerived use them.
local restoreBoosts: (Player) -> ()
local updateVipTag: (Player) -> ()

local SessionDefaults = {
	InMatch = false,
	RoomCash = 0,
	StrengthLevel = 1,
	ThrowPowerLevel = 1,
	MoveSpeedLevel = 1,
	ObjectsCleaned = 0, -- objects this player got into a bin this room
	Streak = 0,
	StreakExpires = 0,
	ThrowSpeed = 50,
	StrengthBoostExpires = 0,
	CashBoostExpires = 0,
	VIPFreeHints = 0,
	HotCold = "",
	HeldObjectId = "",
	MaxWeight = 2,
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function owns(player: Player, key: string): boolean
	return Services.MonetizationService.OwnsPass(player, key)
end

local function teamMuscleActive(player: Player): boolean
	local match = Services.MatchService.GetMatchForPlayer(player)
	return match ~= nil and (match.TeamMuscleExpires or 0) > now()
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
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)

	local function onPlayer(player: Player)
		for k, v in pairs(SessionDefaults) do
			player:SetAttribute(k, v)
		end
		player:SetAttribute("Dev", Services.DevService.IsAuthorized(player))
		player.CharacterAdded:Connect(function(character)
			applyCollisionGroup(character)
			PlayerSessionService.ApplyWalkSpeed(player)
			Services.MatchService.OnCharacterAdded(player, character)
			character:WaitForChild("Head", 5)
			updateVipTag(player)
		end)
		if player.Character then
			applyCollisionGroup(player.Character)
		end
		task.spawn(function()
			if Services.DataService.WaitFor(player, 15) then
				restoreBoosts(player)
				PlayerSessionService.RecomputeDerived(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

function PlayerSessionService.Start()
	-- Boost expiry changes derived stats; refresh the replicated values once a second.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("InMatch") then
					PlayerSessionService.RecomputeDerived(player)
				end
			end
		end
	end)
end

-- Paid timed boosts live in the profile, so a room change or server hop never eats them.
function restoreBoosts(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, attr in ipairs({ "StrengthBoostExpires", "CashBoostExpires" }) do
		local expires = data.Boosts[attr] or 0
		if expires > now then
			player:SetAttribute(attr, expires)
		end
	end
end

function PlayerSessionService.Reset(player: Player)
	for k, v in pairs(SessionDefaults) do
		player:SetAttribute(k, v)
	end
	if owns(player, "VIP") then
		player:SetAttribute("VIPFreeHints", Effects.VIPFreeSuperHintsPerMatch)
	end
	restoreBoosts(player)
	PlayerSessionService.RecomputeDerived(player)
end

function PlayerSessionService.RestoreFromCheckpoint(player: Player, checkpoint)
	player:SetAttribute("RoomCash", checkpoint.RoomCash or 0)
	player:SetAttribute("StrengthLevel", checkpoint.StrengthLevel or 1)
	player:SetAttribute("ThrowPowerLevel", checkpoint.ThrowPowerLevel or 1)
	player:SetAttribute("MoveSpeedLevel", checkpoint.MoveSpeedLevel or 1)
	PlayerSessionService.RecomputeDerived(player)
end

function PlayerSessionService.GetLevel(player: Player, key: string): number
	return player:GetAttribute(UpgradeConfig.ByKey[key].Attribute) or 1
end

function PlayerSessionService.GetMaxWeight(player: Player): number
	local weight = UpgradeConfig.GetValue("Strength", PlayerSessionService.GetLevel(player, "Strength"))
	if owns(player, "StrongerHands") then
		weight += Effects.StrongerHandsWeightBonus
	end
	local temp = 1
	if (player:GetAttribute("StrengthBoostExpires") or 0) > now() then
		temp *= Effects.StrengthBoostMultiplier
	end
	if teamMuscleActive(player) then
		temp *= Effects.TeamMuscleStrengthMultiplier
	end
	temp = math.min(temp, GameConfig.MaxTempStrengthMultiplier)
	return math.min(math.floor(weight * temp + 1e-6), GameConfig.MaxWeightCap)
end

function PlayerSessionService.GetThrowSpeed(player: Player): number
	local speed = UpgradeConfig.GetValue("ThrowPower", PlayerSessionService.GetLevel(player, "ThrowPower"))
	if owns(player, "ThrowBoost") then
		speed *= Effects.ThrowBoostMultiplier
	end
	if teamMuscleActive(player) then
		speed *= Effects.TeamMuscleThrowMultiplier
	end
	return speed
end

function PlayerSessionService.GetHoldResponsiveness(player: Player, weight: number): number
	local grab = 1 + (PlayerSessionService.GetLevel(player, "Strength") - 1) * 0.2
	if owns(player, "FastHands") then
		grab *= Effects.FastHandsMultiplier
	end
	return GameConfig.HoldBaseResponsiveness * grab / (1 + weight * GameConfig.HoldWeightFalloff)
end

function PlayerSessionService.GetWalkSpeed(player: Player): number
	local speed = UpgradeConfig.GetValue("MoveSpeed", PlayerSessionService.GetLevel(player, "MoveSpeed"))
	if player:GetAttribute("InMatch") and owns(player, "VIP") then
		speed *= Effects.VIPWalkSpeedMultiplier
	end
	return speed
end

function PlayerSessionService.GetCashMultiplier(player: Player): number
	local mult = 1
	if owns(player, "DoubleCash") then
		mult *= Effects.DoubleCashMultiplier
	end
	if (player:GetAttribute("CashBoostExpires") or 0) > now() then
		mult *= Effects.CashBoostMultiplier
	end
	return math.min(mult, GameConfig.MaxCashMultiplier)
end

function PlayerSessionService.RecomputeDerived(player: Player)
	local maxWeight = PlayerSessionService.GetMaxWeight(player)
	if player:GetAttribute("MaxWeight") ~= maxWeight then
		player:SetAttribute("MaxWeight", maxWeight)
	end
	-- The client draws its throw-arc preview from this.
	local throwSpeed = PlayerSessionService.GetThrowSpeed(player)
	if player:GetAttribute("ThrowSpeed") ~= throwSpeed then
		player:SetAttribute("ThrowSpeed", throwSpeed)
	end
	PlayerSessionService.ApplyWalkSpeed(player)
	updateVipTag(player)
end

function PlayerSessionService.ApplyWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = PlayerSessionService.GetWalkSpeed(player)
	end
end

function PlayerSessionService.ExtendBoost(player: Player, attribute: string, seconds: number)
	local base = math.max(player:GetAttribute(attribute) or 0, now())
	player:SetAttribute(attribute, base + seconds)
	Services.DataService.Update(player, function(data)
		data.Boosts[attribute] = base + seconds
	end)
	PlayerSessionService.RecomputeDerived(player)
end

-- Overhead tag: "LV 12 · SOCK HUNTER", gold with a VIP prefix for VIP pass owners.
function updateVipTag(player: Player)
	Services.ProgressionService.RefreshTag(player)
end

return PlayerSessionService
