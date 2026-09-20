--[[
	Free clues on a timer, paid hints and hot/cold assistance.
	Clues only ever point at areas; the key is revealed solely by moving its physical blockers.
	Stages: 1 side (LEFT / RIGHT half), 2 its colour zone ("the TEAL zone: HAMPER CORNER",
	Shared/Utility/Zones), 3 a glowing ring on the floor around it, 4 hot/cold, 5 outline the
	objects covering it. The party's clues sit on MatchState (ClueSide, ClueZone, ClueSpot +
	ClueSpotRadius) so the map and the room show them (MapController); a Super Hint shows the
	buyer the zone and the ring at once.

	The clue clock starts at SEARCH! and every object cleaned into a bin moves it forward
	(GameConfig.ClueSecondsPerDeposit), so cleaning brings clues sooner but nobody waits forever.
	A brand-new player's easy first run has its own quick schedule and hot/cold from the start.
	Quick and Super Hints work any time while searching.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)
local Zones = require(Shared.Utility.Zones)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local HintService = {}

local STAGES = 5
local SPOT_RADIUS = 8 -- studs: the clue-3 ring around the object

local hintLimiter = RateLimiter.new(2, 3)
local hotColdEnabled = false

local function fire(players: { Player }, eventName: string, payload)
	for _, player in ipairs(players) do
		if player.Parent then
			Remotes.Event("MatchUpdate"):FireClient(player, eventName, payload)
		end
	end
end

local function stateConfig(): Configuration
	return Services.MatchService.GetStateConfig()
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Seconds of searching at which each stage arrives on its own.
local function clueTimes(match): { number }
	local times = if match.Easy then GameConfig.EasyClueTimes else (match.Config.ClueTimes or GameConfig.ClueTimes)
	if match.Hard then
		local scaled = {}
		for i, t in ipairs(times) do
			scaled[i] = t * (GameConfig.HardClueTimeScale or 1)
		end
		return scaled
	end
	return times
end

-- Clues can be given (free on the clock, or paid) whenever the party is searching.
function HintService.HintsUnlocked(match): boolean
	return match ~= nil and match.State == "Searching"
end

local function getTargetSide(match): string
	local localPos = match.Runtime.Origin:PointToObjectSpace(match.TargetSocket.Position)
	return localPos.X < 0 and "LEFT" or "RIGHT"
end

local function getRegionName(match): string
	local region = match.Runtime.Regions[match.TargetSocket.RegionId]
	return region and region.Name or match.TargetSocket.RegionId
end

-- "the TEAL zone: HAMPER CORNER" (a room without zones: its region's name).
local function zoneText(match): string
	local zone = Zones.ForRegion(match.Config, match.TargetSocket.RegionId)
	if zone then
		return string.format("the %s zone: %s", string.upper(zone.Color), zone.Name)
	end
	return "the " .. getRegionName(match) .. " area"
end

-- The clue-3 ring's centre: near the object but not on it, so the ring doesn't give the exact
-- spot away. Picked once per room.
local function spotCenter(match): Vector3
	if not match.ClueSpot then
		local a = match.Rng:NextNumber(0, math.pi * 2)
		local d = match.Rng:NextNumber(0, SPOT_RADIUS * 0.5)
		match.ClueSpot = match.TargetSocket.Position + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
	end
	return match.ClueSpot
end

-- Stage 5: outline whatever is physically covering the key right now.
function HintService.RefreshOutline(match)
	if not match or match.HintStage < 5 or match.TargetRevealed then
		stateConfig():SetAttribute("OutlinedObjects", "")
		return
	end
	local ids = {}
	for _, root in ipairs(Services.MatchService.GetCoveringObjects()) do
		table.insert(ids, root:GetAttribute("ObjectId"))
	end
	stateConfig():SetAttribute("OutlinedObjects", table.concat(ids, ","))
end

local function deliverStage(match, stage: number, players: { Player }, silent: boolean?)
	local target = match.Config.TargetName
	if stage == 1 then
		local side = getTargetSide(match)
		stateConfig():SetAttribute("ClueSide", side)
		fire(players, "Clue", { Stage = stage, Side = side, Text = string.format("The %s is on the %s half of the room - look for the %s SIDE sign.", target, side, side) })
	elseif stage == 2 then
		local zone = Zones.ForRegion(match.Config, match.TargetSocket.RegionId)
		stateConfig():SetAttribute("ClueZone", zone and zone.Id or "")
		fire(players, "Clue", { Stage = stage, ZoneId = zone and zone.Id, Text = string.format("It's in %s! Follow the arrow.", zoneText(match)) })
	elseif stage == 3 then
		stateConfig():SetAttribute("ClueSpot", spotCenter(match))
		stateConfig():SetAttribute("ClueSpotRadius", SPOT_RADIUS)
		fire(players, "Clue", { Stage = stage, Text = string.format("It's inside the glowing gold ring in %s!", zoneText(match)) })
	elseif stage == 4 then
		hotColdEnabled = true
		fire(players, "Clue", { Stage = stage, Text = "Hot / Cold tracking enabled. Get close to feel the warmth!" })
	elseif stage == 5 then
		HintService.RefreshOutline(match)
		fire(players, "Clue", { Stage = stage, Text = "Almost there! The objects hiding it are outlined." })
	end
	if not silent then
		Services.AnalyticsService.Clue(players, stage, "free", match.Progress)
	end
end

-- When the next stage arrives on its own (server time), or 0 when every clue is out.
local function publishNext(match)
	local times = clueTimes(match)
	local nextTime = times[match.HintStage + 1]
	local at = (nextTime and match.ClueStart) and (match.ClueStart - (match.ClueBonus or 0) + nextTime) or 0
	if stateConfig():GetAttribute("NextClueAt") ~= at then
		stateConfig():SetAttribute("NextClueAt", at)
	end
end

local function setStage(match, stage: number)
	match.HintStage = stage
	stateConfig():SetAttribute("HintStage", stage)
	if stage >= 4 then
		hotColdEnabled = true
	end
	publishNext(match)
end

-- Hands out every stage whose time has come.
local function tickClues(match)
	if not match.ClueStart or match.TargetRevealed then
		return
	end
	local clock = now() - match.ClueStart + (match.ClueBonus or 0)
	local times = clueTimes(match)
	while match.HintStage < STAGES and times[match.HintStage + 1] and clock >= times[match.HintStage + 1] do
		setStage(match, match.HintStage + 1)
		deliverStage(match, match.HintStage, match.Players)
	end
end

function HintService.Init()
	Remotes.Event("RequestHint").OnServerEvent:Connect(function(player, kind)
		if not hintLimiter:Allow(player) then
			return
		end
		local match = Services.MatchService.GetMatchForPlayer(player)
		if not match or match.State ~= "Searching" then
			Services.NotificationService.Send(player, "Warning", "Hints are only available while searching.")
			return
		end
		if kind == "Quick" then
			Services.MonetizationService.PromptPurchase(player, "QuickHint")
		elseif kind == "Super" or kind == "Free" then
			if (player:GetAttribute("VIPFreeHints") or 0) > 0 then
				HintService.UseFreeSuperHint(player)
			else
				Services.MonetizationService.PromptPurchase(player, "SuperHint")
			end
		end
	end)
end

function HintService.Start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.HotCold.PollInterval)
			local match = Services.MatchService.GetMatch()
			if match and match.State == "Searching" and match.TargetSocket then
				tickClues(match)
				if hotColdEnabled then
					local center = match.TargetSocket.Position
					for _, player in ipairs(match.Players) do
						local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						local state = ""
						if root then
							local d = (root.Position - center).Magnitude
							state = d <= GameConfig.HotCold.VeryHot and "VERY HOT" or d <= GameConfig.HotCold.Hot and "HOT" or d <= GameConfig.HotCold.Warm and "WARM" or "COLD"
						end
						if player:GetAttribute("HotCold") ~= state then
							player:SetAttribute("HotCold", state)
						end
					end
				end
			end
		end
	end)
end

function HintService.ResetForMatch(match)
	hotColdEnabled = false
	if match then
		match.HintStage = 0
		match.ClueStart = nil
		match.ClueBonus = 0
		match.ClueSpot = nil
		stateConfig():SetAttribute("HintStage", 0)
	end
	stateConfig():SetAttribute("NextClueAt", 0)
	stateConfig():SetAttribute("ClueSide", "")
	stateConfig():SetAttribute("ClueZone", "")
	stateConfig():SetAttribute("ClueSpotRadius", 0)
	stateConfig():SetAttribute("OutlinedObjects", "")
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("HotCold", "")
	end
end

-- SEARCH!: the clue clock starts. The easy first run feels the warmth straight away.
function HintService.StartClock(match)
	match.ClueStart = now()
	match.ClueBonus = 0
	if match.Easy then
		hotColdEnabled = true
	end
	publishNext(match)
end

-- An object went into a bin: the next clue comes a little sooner.
function HintService.OnDeposit(match)
	if not match.ClueStart then
		return
	end
	match.ClueBonus = (match.ClueBonus or 0) + (GameConfig.ClueSecondsPerDeposit or 0)
	publishNext(match)
	tickClues(match)
end

-- Developer: move the clue clock forward.
function HintService.DevAdvance(match, seconds: number)
	if match and match.ClueStart then
		match.ClueBonus = (match.ClueBonus or 0) + seconds
		publishNext(match)
		tickClues(match)
	end
end

-- Quick Hint: deliver the next clue now (advances the team's stage).
function HintService.GrantQuickHint(player: Player): boolean
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not HintService.HintsUnlocked(match) then
		return false
	end
	local nextStage = match.HintStage + 1
	if nextStage > STAGES then
		Services.NotificationService.Send(player, "Info", "All clues already revealed!")
		return false
	end
	setStage(match, nextStage)
	deliverStage(match, nextStage, match.Players, true)
	-- Teammates hear who brought the clue; the player who did already sees the clue itself.
	for _, p in ipairs(match.Players) do
		if p ~= player then
			Services.NotificationService.Send(p, "Premium", string.format("%s used a Quick Hint!", player.Name))
		end
	end
	Services.AnalyticsService.Clue({ player }, nextStage, "quick", match.Progress)
	return true
end

-- Super Hint: the buyer sees the object's zone and the gold ring around it straight away.
function HintService.GrantSuperHint(player: Player): boolean
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not HintService.HintsUnlocked(match) then
		return false
	end
	local zone = Zones.ForRegion(match.Config, match.TargetSocket.RegionId)
	fire({ player }, "SuperClue", { ZoneId = zone and zone.Id, Center = spotCenter(match), Radius = SPOT_RADIUS })
	fire({ player }, "Clue", { Stage = 0, Text = string.format("SUPER HINT: it's inside the gold ring in %s!", zoneText(match)) })
	Services.AnalyticsService.Clue({ player }, 0, "super", match.Progress)
	return true
end

function HintService.UseFreeSuperHint(player: Player)
	local free = player:GetAttribute("VIPFreeHints") or 0
	if free <= 0 then
		Services.NotificationService.Send(player, "Warning", "No free hints left this room.")
		return
	end
	player:SetAttribute("VIPFreeHints", free - 1)
	HintService.GrantSuperHint(player)
end

return HintService
