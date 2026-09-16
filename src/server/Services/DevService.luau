--[[
	Studio/development-only commands driven by the client Test Panel. Never available to
	normal players in production.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)
local RoomValidator = require(script.Parent.Parent.RoomValidator)

local DevService = {}

function DevService.IsAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if GameConfig.DevelopmentMode and table.find(GameConfig.DeveloperUserIds, player.UserId) then
		return true
	end
	return false
end

local commands: { [string]: (Player, ...any) -> () } = {}

commands.StartRoom = function(player, partySize, roomId, easy)
	partySize = math.clamp(tonumber(partySize) or 1, 1, GameConfig.MaxPartySize)
	roomId = tonumber(roomId) or 1
	if not RoomRegistry.Exists(roomId) then
		roomId = 1
	end
	if Services.MatchService.GetMatch() then
		Services.MatchService.EndMatch()
		task.wait(0.5)
	end
	Services.MatchService.StartLocalMatch({
		Players = { player },
		RoomId = roomId,
		PartySize = partySize,
		ResumePercent = Services.CheckpointService.ResolveResumePercent({ player }, roomId),
		Seed = Random.new():NextInteger(1, 2 ^ 30),
		MatchId = HttpService:GenerateGUID(false),
		Easy = easy == true,
	})
end

commands.AddWallet = function(player, amount)
	Services.WalletService.Add(player, tonumber(amount) or 1000, "Gameplay", "Dev")
end

-- Adds active playtime today (minutes), so the gift ladder can be tested quickly.
commands.AddPlaytime = function(player, minutes)
	Services.DataService.Update(player, function(data)
		data.Playtime.Seconds += math.floor((tonumber(minutes) or 1) * 60)
	end)
	Services.RetentionService.Publish(player)
end

-- The wallet, gifts, spin, firsts, gift bar, Starter Pack and the notify question start over.
commands.ResetRetention = function(player)
	Services.DataService.Update(player, function(data)
		data.Wallet = 0
		data.Banked.LiftItNow = 0
		data.Banked.JunkBlaster = 0
		data.Banked.TreasureRadar = 0
		data.Playtime = { Day = 0, Seconds = 0, Claimed = 0 }
		data.GiftBar = { Count = 0, Level = 0 }
		data.Firsts = {}
		data.Spin = { Day = 0 }
		data.StarterPack = false
		data.NotifyAsked = false
		data.Login.FreezeWeek = 0
	end)
	Services.RetentionService.Publish(player)
	Services.ProgressionService.Publish(player)
	Services.NotificationService.Send(player, "Info", "[DEV] Wallet, gifts, spin, firsts and offers reset.")
end

-- A free egg hatch (the same roll as buying one).
commands.GiveEgg = function(player, eggKey)
	Services.PetService.GrantEgg(player, tostring(eggKey or "Dusty"), "Dev")
end

commands.GivePet = function(player, kind)
	Services.PetService.GivePet(player, tostring(kind or "DustBunny"), "Dev")
end

-- Pets start over (the welcome pet is offered again).
commands.ResetPets = function(player)
	Services.DataService.Update(player, function(data)
		data.Pets = { Owned = {}, Equipped = {}, Welcomed = false, IndexRewarded = false }
	end)
	Services.PetService.Publish(player)
	Services.ProgressionService.RefreshTag(player)
end

-- Pretends the last daily claim was two days ago, so the streak freeze can be tested.
commands.MissADay = function(player)
	Services.DataService.Update(player, function(data)
		local day = math.floor(workspace:GetServerTimeNow() / 86400)
		data.Login.Day = day - 2
		data.Login.Streak = math.max(1, data.Login.Streak)
	end)
	Services.ProgressionService.Publish(player)
end

commands.AddCash = function(player, amount)
	if Services.MatchService.IsPlayerInMatch(player) then
		Services.EconomyService.AddCash(player, tonumber(amount) or 10000)
	end
end

commands.SetProgress = function(player, fraction)
	Services.MatchService.ForceProgress(tonumber(fraction) or 0.25)
end

commands.RevealTarget = function(player)
	Services.MatchService.ForceReveal()
end

commands.CompleteRoom = function(player)
	Services.MatchService.ForceComplete(player)
end

commands.ResetRoom = function(player)
	if Services.MatchService.GetMatch() then
		Services.MatchService.EndMatch()
	end
end

commands.ValidateRoom = function(player, roomId)
	roomId = tonumber(roomId) or 1
	local match = Services.MatchService.GetMatch()
	local report
	if match and match.RoomId == roomId then
		local _, r = RoomValidator.Validate(match.Runtime, match.Config)
		report = r
	else
		local config = RoomRegistry.Get(roomId)
		if not config then
			report = "Unknown room " .. tostring(roomId)
		else
			-- Built off to the side (not near FallenPartsDestroyHeight) and never released to physics.
			local runtime = Services.RoomService.Build(config, CFrame.new(-700, 0, 0))
			local _, r = RoomValidator.Validate(runtime, config)
			report = r
			Services.RoomService.Destroy(runtime)
		end
	end
	print(report)
	Services.NotificationService.Send(player, "Info", report, 12)
end

commands.ResetData = function(player)
	if Services.MatchService.IsPlayerInMatch(player) then
		return
	end
	Services.DataService.ResetProfile(player)
	Services.NotificationService.Send(player, "Info", "[DEV] Save data reset.")
end

commands.MockPurchase = function(player, key)
	if type(key) == "string" then
		Services.MonetizationService.MockGrant(player, key)
	end
end

commands.ForceCheckpoint = function(player, percent)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if match then
		Services.CheckpointService.SaveCheckpoint(player, match, tonumber(percent) or 0.25)
		Services.NotificationService.Send(player, "Info", "[DEV] Checkpoint saved.")
	end
end

-- Breaks open the packed junk that secretly holds the key (same path as grabbing it).
commands.BurstKeyChunk = function(player)
	local match = Services.MatchService.GetMatch()
	local chunk = match and match.KeyChunk
	if chunk and chunk.Parent then
		Services.ChunkService.Burst(chunk, player)
	else
		print("[DEV] No key chunk on this spot")
	end
end

commands.TargetInfo = function(player)
	local info = Services.MatchService.GetTargetInfo()
	if info then
		local text = string.format("[DEV] Target: %s (%s) at %s | %d covering / %d blockers (depth %d, heaviest %d) | easy=%s | revealed=%s | keyChunk=%s | blockers: %s", tostring(info.SocketId), tostring(info.RegionId), tostring(info.Position), info.Covering or 0, info.Blockers or 0, info.Depth or 0, info.Heaviest or 0, tostring(info.Easy), tostring(info.Revealed), tostring(info.KeyChunk), table.concat(info.BlockerIds or {}, ","))
		-- Where this spot ranks among every hiding spot by depth (1 = shallowest).
		local match = Services.MatchService.GetMatch()
		local depths = {}
		for _, socket in ipairs(match.Runtime.SocketList or {}) do
			local d = 0
			for _, b in ipairs(socket.Blockers) do
				d += b:GetAttribute("IsChunk") and 3 or 1
			end
			table.insert(depths, d)
		end
		table.sort(depths)
		local rank = 0
		for i, d in ipairs(depths) do
			if d <= (info.Depth or 0) then
				rank = i
			end
		end
		text ..= string.format(" | depth rank %d of %d (depths %d..%d)", rank, #depths, depths[1] or 0, depths[#depths] or 0)
		print(text)
		Services.NotificationService.Send(player, "Info", text, 8)
	end
end

function DevService.Run(player: Player, command: string, ...)
	local fn = commands[command]
	if fn then
		local ok, err = pcall(fn, player, ...)
		if not ok then
			warn("[DevService]", command, err)
		end
	end
end

function DevService.Init()
	-- Studio test hook: workspace attribute DevRun = "Command arg1 arg2" runs it for the first player.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("DevRun"):Connect(function()
			local line = workspace:GetAttribute("DevRun")
			local player = game:GetService("Players"):GetPlayers()[1]
			if type(line) ~= "string" or line == "" or not player then
				return
			end
			local parts = string.split(line, " ")
			local args = {}
			for i = 2, #parts do
				local v: any = parts[i]
				if v == "true" or v == "false" then
					v = v == "true"
				elseif tonumber(v) then
					v = tonumber(v)
				end
				args[i - 1] = v
			end
			print("[DEV] run", line)
			DevService.Run(player, parts[1], table.unpack(args))
			workspace:SetAttribute("DevRun", "")
		end)
	end

	Remotes.Event("DevCommand").OnServerEvent:Connect(function(player, command, ...)
		if not DevService.IsAuthorized(player) then
			return
		end
		local fn = type(command) == "string" and commands[command]
		if fn then
			local ok, err = pcall(fn, player, ...)
			if not ok then
				warn("[DevService]", command, err)
			end
		end
	end)
end

return DevService
