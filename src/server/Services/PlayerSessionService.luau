--[[
	Server-authoritative per-player match session state, replicated through player attributes,
	plus derived stats that fold upgrades, passes and boosts together:
	  GetMaxWeight (Strength), GetThrowSpeed, GetHoldResponsiveness (Strength level + FastHands),
	  GetWalkSpeed, GetCashMultiplier, GetXPMultiplier.
	Timed extras: 2x Speed and 2x XP boosts (saved like the others) and Lift It Now (LiftWeight
	until LiftExpires, this room only).
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
	FreeUpgrade = false, -- the tutorial room's free first upgrade (see UpgradeService)
	StrengthLevel = 1,
	ThrowPowerLevel = 1,
	MoveSpeedLevel = 1,
	ArmfulLevel = 1,
	ObjectsCleaned = 0, -- objects this player got into a bin this room
	Streak = 0,
	StreakExpires = 0,
	ThrowSpeed = 50,
	StrengthBoostExpires = 0,
	CashBoostExpires = 0,
	SpeedBoostExpires = 0,
	XPBoostExpires = 0,
	PetSnackExpires = 0,
	PetCleaned = 0, -- objects this player's pets cleaned this room
	LiftWeight = 0,
	LiftExpires = 0,
	TreasureRadar = "",
	FriendBonus = false,
	RoomSaved = 0,
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
			PlayerSessionService.RefreshTrail(player)
		end)
		if player.Character then
			applyCollisionGroup(player.Character)
		end
		player:GetAttributeChangedSignal("InMatch"):Connect(function()
			PlayerSessionService.RefreshTrail(player)
		end)
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
	for _, attr in ipairs({ "StrengthBoostExpires", "CashBoostExpires", "SpeedBoostExpires", "XPBoostExpires", "PetSnackExpires" }) do
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
	player:SetAttribute("ArmfulLevel", checkpoint.ArmfulLevel or 1)
	PlayerSessionService.RecomputeDerived(player)
end

function PlayerSessionService.GetLevel(player: Player, key: string): number
	return player:GetAttribute(UpgradeConfig.ByKey[key].Attribute) or 1
end

-- The heaviest weight the player would lift at Strength `level`, with their passes and boosts.
local function maxWeightAt(player: Player, level: number): number
	local weight = UpgradeConfig.GetValue("Strength", level)
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
	local lifted = math.floor(weight * temp + 1e-6)
	-- Lift It Now: anything up to the weight it was bought for, for a minute.
	if (player:GetAttribute("LiftExpires") or 0) > now() then
		lifted = math.max(lifted, player:GetAttribute("LiftWeight") or 0)
	end
	return math.min(lifted, GameConfig.MaxWeightCap)
end

function PlayerSessionService.GetMaxWeight(player: Player): number
	return maxWeightAt(player, PlayerSessionService.GetLevel(player, "Strength"))
end

-- The lowest Strength level that lifts `weight` for this player (nil: no level can).
function PlayerSessionService.StrengthLevelToLift(player: Player, weight: number): number?
	for level = 1, UpgradeConfig.GetMaxLevel("Strength") do
		if maxWeightAt(player, level) >= weight then
			return level
		end
	end
	return nil
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

-- How many things one grab carries (Armful): the grabbed object plus small ones beside it.
function PlayerSessionService.GetArmful(player: Player): number
	return UpgradeConfig.GetValue("Armful", PlayerSessionService.GetLevel(player, "Armful"))
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
	-- 2x Speed, capped so grabbing and throwing on the run stay under control.
	if player:GetAttribute("InMatch") and (player:GetAttribute("SpeedBoostExpires") or 0) > now() then
		speed = math.max(speed, math.min(speed * Effects.SpeedBoostMultiplier, Effects.MaxBoostedWalkSpeed))
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

function PlayerSessionService.GetXPMultiplier(player: Player): number
	local mult = 1
	if owns(player, "DoubleXP") then
		mult *= Effects.DoubleXPPassMultiplier
	end
	if (player:GetAttribute("XPBoostExpires") or 0) > now() then
		mult *= Effects.XPBoostMultiplier
	end
	return math.min(mult, Effects.MaxXPMultiplier)
end

-- Rainbow Trail pass: a rainbow trail behind the player while in the lobby.
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 60)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 230, 90)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(60, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 90, 255)),
})
function PlayerSessionService.RefreshTrail(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local trail = root:FindFirstChild("RainbowTrail")
	local want = owns(player, "RainbowTrail")
	if want and not trail then
		local a0 = Instance.new("Attachment")
		a0.Name = "RainbowTrailTop"
		a0.Position = Vector3.new(0, 0.6, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "RainbowTrailBottom"
		a1.Position = Vector3.new(0, -2.2, 0)
		a1.Parent = root
		local t = Instance.new("Trail")
		t.Name = "RainbowTrail"
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Color = RAINBOW
		t.Lifetime = 0.7
		t.LightEmission = 0.6
		t.MinLength = 0.2
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		t.Parent = root
		trail = t
	end
	if trail then
		(trail :: Trail).Enabled = want and player:GetAttribute("InMatch") ~= true
	end
end

function PlayerSessionService.RecomputeDerived(player: Player)
	local maxWeight = PlayerSessionService.GetMaxWeight(player)
	if player:GetAttribute("MaxWeight") ~= maxWeight then
		player:SetAttribute("MaxWeight", maxWeight)
	end
	-- What each Strength level would lift for this player ("3,4,5,..."), so the client can say
	-- exactly which level an object needs and what the next upgrade gives, bonuses included.
	local lifts = {}
	for level = 1, UpgradeConfig.GetMaxLevel("Strength") do
		lifts[level] = tostring(maxWeightAt(player, level))
	end
	local liftList = table.concat(lifts, ",")
	if player:GetAttribute("LiftByLevel") ~= liftList then
		player:SetAttribute("LiftByLevel", liftList)
	end
	-- The client draws its throw-arc preview from this.
	local throwSpeed = PlayerSessionService.GetThrowSpeed(player)
	if player:GetAttribute("ThrowSpeed") ~= throwSpeed then
		player:SetAttribute("ThrowSpeed", throwSpeed)
	end
	PlayerSessionService.ApplyWalkSpeed(player)
	updateVipTag(player)
	PlayerSessionService.RefreshTrail(player)
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
