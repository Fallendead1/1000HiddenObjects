--[[
	Free clue milestones (ROOM CLEANED %: objects deposited in bins), paid hints and hot/cold assistance.
	Clues only ever point at areas; the key is revealed solely by moving its physical blockers.
	Stages: 1 side, 2 area, 3 region highlight, 4 hot/cold, 5 outline the objects covering it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local HintService = {}

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

local function getTargetSide(match): string
	local localPos = match.Runtime.Origin:PointToObjectSpace(match.TargetSocket.Position)
	return localPos.X < 0 and "LEFT" or "RIGHT"
end

local function getRegionName(match): string
	local region = match.Runtime.Regions[match.TargetSocket.RegionId]
	return region and region.Name or match.TargetSocket.RegionId
end

local function getTargetAreaLabel(match): string
	for _, area in ipairs(match.Config.HintAreas or {}) do
		if table.find(area.Regions, match.TargetSocket.RegionId) then
			return area.Label
		end
	end
	return getRegionName(match)
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
	local percent = math.floor((match.Config.HintMilestones[stage] or 0) * 100)
	local target = match.Config.TargetName
	if stage == 1 then
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = string.format("The %s is on the %s side of the room.", target, getTargetSide(match)) })
	elseif stage == 2 then
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = string.format("Search around the %s side.", getTargetAreaLabel(match)) })
	elseif stage == 3 then
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = string.format("It's somewhere in the %s area!", getRegionName(match)) })
		fire(players, "RegionHighlight", { RegionId = match.TargetSocket.RegionId, Duration = MonetizationConfig.Effects.RegionHighlightDuration })
	elseif stage == 4 then
		hotColdEnabled = true
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = "Hot / Cold tracking enabled. Get close to feel the warmth!" })
	elseif stage == 5 then
		HintService.RefreshOutline(match)
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = "Almost there! The objects hiding it are outlined." })
	end
	if not silent then
		Services.AnalyticsService.Log("hint_used", players[1], { Stage = stage, RoomId = match.RoomId, Free = true })
	end
end

local function setStage(match, stage: number)
	match.HintStage = stage
	stateConfig():SetAttribute("HintStage", stage)
	if stage >= 4 then
		hotColdEnabled = true
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
			if match and match.State == "Searching" and hotColdEnabled and match.TargetSocket then
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
	end)
end

function HintService.ResetForMatch(match)
	hotColdEnabled = false
	if match then
		match.HintStage = 0
		stateConfig():SetAttribute("HintStage", 0)
	end
	stateConfig():SetAttribute("OutlinedObjects", "")
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("HotCold", "")
	end
end

-- Silently bring the hint stage up to the current progress (checkpoint resume).
function HintService.ApplyStagesForProgress(match, progress: number)
	for stage, threshold in ipairs(match.Config.HintMilestones) do
		if progress >= threshold and match.HintStage < stage then
			setStage(match, stage)
		end
	end
	HintService.RefreshOutline(match)
end

function HintService.OnProgress(match, progress: number)
	for stage, threshold in ipairs(match.Config.HintMilestones) do
		if progress >= threshold and match.HintStage < stage then
			setStage(match, stage)
			deliverStage(match, stage, match.Players)
		end
	end
end

-- Quick Hint: deliver the next milestone clue now (advances the team's stage).
function HintService.GrantQuickHint(player: Player): boolean
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" then
		return false
	end
	local nextStage = match.HintStage + 1
	if nextStage > #match.Config.HintMilestones then
		Services.NotificationService.Send(player, "Info", "All clues already revealed!")
		return false
	end
	setStage(match, nextStage)
	deliverStage(match, nextStage, match.Players, true)
	Services.NotificationService.SendMany(match.Players, "Premium", string.format("%s used a Quick Hint!", player.Name))
	Services.AnalyticsService.Log("hint_used", player, { Kind = "Quick", RoomId = match.RoomId })
	return true
end

-- Super Hint: highlight the correct region for the buyer.
function HintService.GrantSuperHint(player: Player): boolean
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" then
		return false
	end
	fire({ player }, "RegionHighlight", { RegionId = match.TargetSocket.RegionId, Duration = MonetizationConfig.Effects.SuperHintDuration, Super = true })
	fire({ player }, "Clue", { Stage = 0, Percent = 0, Text = string.format("SUPER HINT: search the %s area!", getRegionName(match)) })
	Services.AnalyticsService.Log("hint_used", player, { Kind = "Super", RoomId = match.RoomId })
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
