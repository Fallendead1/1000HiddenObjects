--[[
	The lobby's "like the game" reward (SocialConfig): the player presses CHECK (the client shows
	the join-group and favourite prompts and counts down), then CHECK again. The server keeps the
	countdown honest, checks the group for real, and gives the free pet once per player.

	Remotes: SocialCheck C->S (); SocialResult S->C (state, seconds?)
	  state: "Wait" (countdown started / still running), "NeedGroup" (not in the group yet, the
	  countdown starts over), "Claimed" (just now or before).
	Attribute: SocialRewardClaimed (boolean) on the player.
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SocialConfig = require(Shared.Config.SocialConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local SocialService = {}

local startedAt: { [Player]: number } = {}
local limiter = RateLimiter.new(2, 3)

-- Asks Roblox afresh (Player:IsInGroup remembers its first answer for the whole session, so
-- it would miss someone who joined a minute ago).
local function inGroup(player: Player): boolean
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if not ok then
		-- Roblox didn't answer: don't punish the player for that.
		return true
	end
	for _, g in ipairs(groups) do
		if g.Id == SocialConfig.GroupId then
			return true
		end
	end
	return false
end

local function reply(player: Player, state: string, seconds: number?)
	Remotes.Event("SocialResult"):FireClient(player, state, seconds)
end

local function check(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	if data.Social.RewardClaimed then
		reply(player, "Claimed")
		return
	end
	local now = os.clock()
	local started = startedAt[player]
	if not started then
		startedAt[player] = now
		Services.AnalyticsService.Event(player, "social_check", 1)
		reply(player, "Wait", SocialConfig.CheckSeconds)
		return
	end
	local left = SocialConfig.CheckSeconds - (now - started)
	if left > 0.5 then
		reply(player, "Wait", math.ceil(left))
		return
	end
	if SocialConfig.RequireGroup and not inGroup(player) then
		startedAt[player] = now
		reply(player, "NeedGroup", SocialConfig.CheckSeconds)
		return
	end
	Services.DataService.Update(player, function(d)
		d.Social.RewardClaimed = true
	end)
	Services.DataService.Save(player)
	player:SetAttribute("SocialRewardClaimed", true)
	Services.PetService.GivePet(player, SocialConfig.RewardPet, "Like")
	Services.AnalyticsService.Event(player, "social_reward", 1, SocialConfig.RewardPet)
	reply(player, "Claimed")
end

function SocialService.Init()
	Remotes.Event("SocialCheck").OnServerEvent:Connect(function(player)
		if limiter:Allow(player) then
			check(player)
		end
	end)
	local function onPlayer(player: Player)
		task.spawn(function()
			if Services.DataService.WaitFor(player, 15) then
				local data = Services.DataService.Get(player)
				player:SetAttribute("SocialRewardClaimed", data ~= nil and data.Social.RewardClaimed == true)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		startedAt[player] = nil
		limiter:Clear(player)
	end)
end

function SocialService.Start() end

return SocialService
