--[[
	Free clue milestones (25/50/75/90/97%), paid hints and hot/cold assistance.
	The exact socket is never sent to clients; region-level information only until 97%.
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

local function getTargetSide(match): string
	local localPos = match.Runtime.Origin:PointToObjectSpace(match.TargetCluster.Center)
	return localPos.X < 0 and "LEFT" or "RIGHT"
end

local function getTargetAreaLabel(match): string
	local regionId = match.TargetCluster.RegionId
	for _, area in ipairs(match.Config.HintAreas or {}) do
		if table.find(area.Regions, regionId) then
			return area.Label
		end
	end
	local region = match.Runtime.Regions[regionId]
	return region and region.Name or regionId
end

local function getRegionName(match): string
	local region = match.Runtime.Regions[match.TargetCluster.RegionId]
	return region and region.Name or match.TargetCluster.RegionId
end

-- Deliver the clue for a given stage index (1-based into HintMilestones).
local function deliverStage(match, stage: number, players: { Player }, silent: boolean?)
	local milestones = match.Config.HintMilestones
	local percent = math.floor((milestones[stage] or 0) * 100)
	if stage == 1 then
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = string.format("The %s is on the %s side of the room.", match.Config.TargetName, getTargetSide(match)) })
	elseif stage == 2 then
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = string.format("Search around the %s side.", getTargetAreaLabel(match)) })
	elseif stage == 3 then
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = string.format("It's somewhere in the %s area!", getRegionName(match)) })
		fire(players, "RegionHighlight", { RegionId = match.TargetCluster.RegionId, Duration = MonetizationConfig.Effects.RegionHighlightDuration })
	elseif stage == 4 then
		hotColdEnabled = true
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = "Hot / Cold tracking enabled. Get close to feel the warmth!" })
	elseif stage == 5 then
		Services.MatchService.GetStateConfig():SetAttribute("OutlinedClusterId", match.TargetCluster.Id)
		fire(players, "Clue", { Stage = stage, Percent = percent, Text = "Almost there! The correct pile is outlined." })
	end
	if not silent then
		Services.AnalyticsService.Log("hint_used", players[1], { Stage = stage, RoomId = match.RoomId, Free = true })
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
		if kind == "Free" then
			HintService.UseFreeSuperHint(player, match)
		elseif kind == "Quick" then
			Services.MonetizationService.PromptPurchase(player, "QuickHint")
		elseif kind == "Super" then
			if (player:GetAttribute("VIPFreeHints") or 0) > 0 then
				HintService.UseFreeSuperHint(player, match)
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
			if match and match.State == "Searching" and hotColdEnabled and not match.TargetFound then
				local center = match.TargetCluster.Center
				for _, player in ipairs(match.Players) do
					local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local state = ""
					if root then
						local d = (root.Position - center).Magnitude
						if d <= GameConfig.HotCold.VeryHot then
							state = "VERY HOT"
						elseif d <= GameConfig.HotCold.Hot then
							state = "HOT"
						elseif d <= GameConfig.HotCold.Warm then
							state = "WARM"
						else
							state = "COLD"
						end
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
		Services.MatchService.GetStateConfig():SetAttribute("HintStage", 0)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("HotCold", "")
	end
end

-- Silently bring the hint stage up to the current progress (used on checkpoint resume).
function HintService.ApplyStagesForProgress(match, progress: number, silent: boolean)
	local milestones = match.Config.HintMilestones
	for stage, threshold in ipairs(milestones) do
		if progress >= threshold and match.HintStage < stage then
			match.HintStage = stage
			Services.MatchService.GetStateConfig():SetAttribute("HintStage", stage)
			if stage == 4 then
				hotColdEnabled = true
			elseif stage == 5 then
				Services.MatchService.GetStateConfig():SetAttribute("OutlinedClusterId", match.TargetCluster.Id)
			end
		end
	end
end

function HintService.OnProgress(match, oldProgress: number, newProgress: number)
	local milestones = match.Config.HintMilestones
	for stage, threshold in ipairs(milestones) do
		if newProgress >= threshold and match.HintStage < stage then
			match.HintStage = stage
			Services.MatchService.GetStateConfig():SetAttribute("HintStage", stage)
			deliverStage(match, stage, match.Players)
		end
	end
end

-- Quick Hint: immediately deliver the next milestone clue to the buyer (advances the team stage).
function HintService.GrantQuickHint(player: Player)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" then
		return false
	end
	local milestones = match.Config.HintMilestones
	local nextStage = match.HintStage + 1
	if nextStage > #milestones then
		Services.NotificationService.Send(player, "Info", "All clues already revealed!")
		return false
	end
	match.HintStage = nextStage
	Services.MatchService.GetStateConfig():SetAttribute("HintStage", nextStage)
	deliverStage(match, nextStage, match.Players, true)
	Services.NotificationService.SendMany(match.Players, "Premium", string.format("%s used a Quick Hint!", player.Name))
	Services.AnalyticsService.Log("hint_used", player, { Kind = "Quick", RoomId = match.RoomId })
	return true
end

-- Super Hint: highlight the correct region for the buyer for 15 seconds.
function HintService.GrantSuperHint(player: Player)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" then
		return false
	end
	fire({ player }, "RegionHighlight", { RegionId = match.TargetCluster.RegionId, Duration = MonetizationConfig.Effects.SuperHintDuration, Super = true })
	fire({ player }, "Clue", { Stage = 0, Percent = 0, Text = string.format("SUPER HINT: search the %s area!", getRegionName(match)) })
	Services.AnalyticsService.Log("hint_used", player, { Kind = "Super", RoomId = match.RoomId })
	return true
end

function HintService.UseFreeSuperHint(player: Player, match)
	local free = player:GetAttribute("VIPFreeHints") or 0
	if free <= 0 then
		Services.NotificationService.Send(player, "Warning", "No free hints left this match.")
		return
	end
	player:SetAttribute("VIPFreeHints", free - 1)
	HintService.GrantSuperHint(player)
end

return HintService
