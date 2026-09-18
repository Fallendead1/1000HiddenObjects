--[[
	Packed junk. A chunk is one physics body standing in for 5-8 real objects (its Contents).
	Grabbing it bursts it: the chunk disappears and its pieces spill out as normal clutter that
	can be grabbed, thrown and deposited. Lower pile layers are made of chunks, so a room can be
	dug deep without thousands of live bodies.

	Opening packed junk is always worth it (GameConfig.ChunkOpenCash, and its pieces often hold a
	treasure) but it never holds the room's hidden object: that only shows once its spot is dug
	clear (MatchService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)

local Services = require(script.Parent)
local ClutterBuilder = require(script.Parent.Parent.Builders.ClutterBuilder)

local ChunkService = {}

local rng = Random.new()

function ChunkService.Burst(chunk: BasePart, player: Player?)
	local match = Services.MatchService.GetMatch()
	local runtime = match and match.Runtime
	local folder = runtime and runtime.Model:FindFirstChild("Clutter")
	if not folder or not chunk.Parent then
		return
	end
	local keys = string.split(chunk:GetAttribute("Contents") or "", ",")
	local center, size = chunk.Position, chunk.Size
	local meta = { RegionId = chunk:GetAttribute("RegionId") or "", PileId = chunk:GetAttribute("OriginalClusterId") or "" }
	local bottom = center.Y - size.Y / 2
	-- Whatever lay on the chunk falls into the gap.
	Services.ObjectService.Wake(chunk)
	chunk:Destroy()

	local spawned = 0
	for i, key in ipairs(keys) do
		local mn, mx = ClutterBuilder.Bounds(key)
		if mn and mx then
			local offset = Vector3.new(rng:NextNumber(-0.35, 0.35) * size.X, 0, rng:NextNumber(-0.35, 0.35) * size.Z)
			-- Staggered upward so the pieces don't start inside each other.
			local pos = Vector3.new(center.X, bottom, center.Z) + offset + Vector3.new(0, -mn.Y + 0.1 + (i - 1) * 0.45, 0)
			local root = ClutterBuilder.Spawn(match.Config, folder, key, CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), meta)
			if root then
				spawned += 1
				Services.RoomService.Register(runtime, root)
				Services.ObjectService.Activate(root, player)
				local out = offset.Magnitude > 0.05 and offset.Unit or Vector3.xAxis
				root.AssemblyLinearVelocity = out * GameConfig.ChunkBurstSpeed * rng:NextNumber(0.5, 1) + Vector3.new(0, rng:NextNumber(6, 11), 0)
				root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
			end
		end
	end
	for _, p in ipairs(match.Players) do
		Remotes.Event("FXEvent"):FireClient(p, "ChunkBurst", { Position = center, Count = spawned })
	end
	if player then
		Services.ProgressionService.OnChunkBurst(player)
		Services.AnalyticsService.ChunkBurst(player)
		-- A little Cash for opening it (the paid cash boosts count, like any pay).
		local base = GameConfig.ChunkOpenCash or 0
		if base > 0 and Services.MatchService.IsPlayerInMatch(player) then
			local amount = math.max(1, math.floor(base * Services.PlayerSessionService.GetCashMultiplier(player) + 0.5))
			Services.EconomyService.AddCash(player, amount)
			Services.WalletService.OnDeposit(player, base, "Chunk")
			Remotes.Event("FXEvent"):FireClient(player, "CashAward", { Position = center, Amount = amount })
		end
	end
	Services.MatchService.OnChunkBurst(chunk, center)
end

return ChunkService
