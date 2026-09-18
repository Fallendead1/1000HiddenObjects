--[[
	Deposit bins: the only source of Cash. Watches every bin's mouth volume (tag DepositBin);
	any object that ends up inside - thrown, dropped or carried in - is cleaned: it leaves the
	room and pays the player who last held it:

	  CashValue x (matching bin 2x) x (swish 1.5x) x streak (up to 1.5x) x friend bonus x cash boosts

	The pay before the paid cash boosts is the base pay: a share of it is saved to the player's
	lasting wallet (WalletService).

	A swish is a throw from SwishMinDistance+ studs that drops in before its first impact.
	Objects whose flight failed the anti-cheat check (or nobody ever held) are cleaned for free.

	Phones and controllers aim less precisely, so a throw from a player using touch or a gamepad
	(the client reports it: InputMode) counts as soon as it touches any part of a bin: its sides,
	its rim or the wall behind it (the outline RoomService stores on each mouth).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local DepositConfig = require(Shared.Config.DepositConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local DepositService = {}

type Box = { Min: Vector3, Max: Vector3 }
type Bin = { Part: BasePart, Type: string, Name: string, Touch: { Box } }

local LENIENT_MODES = { Touch = true, Gamepad = true }
local TOUCH_MARGIN = 0.6 -- studs around a bin that still count as touching it

local bins: { Bin } = {}
local binsRuntime = nil
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
local limiter = RateLimiter.new(DepositConfig.MaxDepositsPerSecond, DepositConfig.MaxDepositsPerSecond)

local function clutterRootOf(part: Instance): BasePart?
	if CollectionService:HasTag(part, "Clutter") then
		return part :: BasePart
	end
	local parent = part.Parent
	if parent and parent:IsA("BasePart") and CollectionService:HasTag(parent, "Clutter") then
		return parent
	end
	return nil
end

local function refreshBins(runtime)
	if binsRuntime == runtime then
		return
	end
	binsRuntime = runtime
	bins = {}
	if not runtime then
		return
	end
	for _, part in ipairs(CollectionService:GetTagged("DepositBin")) do
		if part:IsA("BasePart") and part:IsDescendantOf(runtime.Model) then
			local touch = {}
			local bodyMin, bodyMax = part:GetAttribute("BodyMin"), part:GetAttribute("BodyMax")
			if typeof(bodyMin) == "Vector3" and typeof(bodyMax) == "Vector3" then
				-- The bin itself, up to a little above its rim.
				table.insert(touch, { Min = bodyMin, Max = bodyMax + Vector3.new(0, 1, 0) })
			end
			local backMin, backMax = part:GetAttribute("BackMin"), part:GetAttribute("BackMax")
			if typeof(backMin) == "Vector3" and typeof(backMax) == "Vector3" then
				table.insert(touch, { Min = backMin, Max = backMax })
			end
			table.insert(bins, { Part = part, Type = part:GetAttribute("BinType") or "", Name = part:GetAttribute("BinName") or "BIN", Touch = touch })
		end
	end
end

local function creditFor(root: BasePart, flight): Player?
	local holder = Services.ObjectService.GetHolder(root)
	if holder then
		return holder
	end
	if flight and flight.Cheated then
		return nil
	end
	local player = Players:GetPlayerByUserId(root:GetAttribute("LastHolderUserId") or 0)
	if player and Services.MatchService.IsPlayerInMatch(player) then
		return player
	end
	return nil
end

function DepositService.Deposit(root: BasePart, bin: Bin)
	local match = Services.MatchService.GetMatch()
	if not match or match.State ~= "Searching" or not root.Parent then
		return
	end
	if root:GetAttribute("Deposited") or root:GetAttribute("IsChunk") then
		return
	end
	local flight = Services.ObjectService.GetFlight(root)
	local player = creditFor(root, flight)
	local category = root:GetAttribute("Category")
	local isMatch = DepositConfig.MatchingType(category, root:GetAttribute("Weight")) == bin.Type
	local swish = false
	if flight and flight.Thrown and flight.Lift and flight.ReleasePos and not flight.Cheated then
		local d = Vector2.new(root.Position.X - flight.ReleasePos.X, root.Position.Z - flight.ReleasePos.Z).Magnitude
		swish = d >= DepositConfig.SwishMinDistance
	end

	local amount, streak = 0, 0
	if player and limiter:Allow(player) then
		local now = workspace:GetServerTimeNow()
		streak = ((player:GetAttribute("StreakExpires") or 0) > now) and (player:GetAttribute("Streak") or 0) + 1 or 1
		player:SetAttribute("Streak", streak)
		player:SetAttribute("StreakExpires", now + DepositConfig.StreakWindow)
		local base = (root:GetAttribute("CashValue") or 1)
			* (isMatch and DepositConfig.MatchMultiplier or 1)
			* (swish and DepositConfig.SwishMultiplier or 1)
			* DepositConfig.StreakMultiplier(streak)
			* Services.RetentionService.CashMultiplier(player)
		amount = math.max(1, math.floor(base * Services.PlayerSessionService.GetCashMultiplier(player) + 0.5))
		Services.EconomyService.AddCash(player, amount)
		Services.WalletService.OnDeposit(player, base, category == "Treasure" and "Treasure" or ("Bin_" .. bin.Type))
		player:SetAttribute("ObjectsCleaned", (player:GetAttribute("ObjectsCleaned") or 0) + 1)
		Services.ProgressionService.OnDeposit(player, { Match = isMatch, BinType = bin.Type, Swish = swish, Streak = streak, Treasure = category == "Treasure" })
		Services.RetentionService.OnDeposit(player, { Swish = swish, Streak = streak, Treasure = category == "Treasure" })
		Services.AnalyticsService.Deposited(player, { Amount = amount, BinType = bin.Type, Match = isMatch, Swish = swish, Streak = streak, Treasure = category == "Treasure", Balance = player:GetAttribute("RoomCash") or 0 })
	end

	root:SetAttribute("Deposited", true)
	Services.ObjectService.Forget(root)
	local base = {
		Position = root.Position,
		BinPosition = bin.Part.Position,
		BinType = bin.Type,
		Color = root.Color,
		Size = root.Size,
		Name = root:GetAttribute("DisplayName"),
		Treasure = category == "Treasure",
	}
	for _, p in ipairs(match.Players) do
		local payload = table.clone(base)
		if p == player then
			payload.Amount = amount
			payload.Match = isMatch
			payload.Swish = swish
			payload.Streak = streak
			payload.Mine = true
		end
		Remotes.Event("FXEvent"):FireClient(p, "Deposit", payload)
	end
	root:Destroy()
	Services.MatchService.OnObjectDeposited(player, category == "Treasure")
end

-- A helper pet cleaned this (PetService already checked the rules): it pays its owner like a
-- plain deposit (no swish or streak) with the pet's Cash bonus, and counts toward ROOM CLEANED.
function DepositService.PetDeposit(player: Player, root: BasePart, bin: Bin, pet): boolean
	local match = Services.MatchService.GetMatch()
	if not match or match.State ~= "Searching" or not root.Parent or not player.Parent then
		return false
	end
	if root:GetAttribute("Deposited") or root:GetAttribute("IsChunk") or Services.ObjectService.IsBusy(root) then
		return false
	end
	local category = root:GetAttribute("Category")
	local isMatch = DepositConfig.MatchingType(category, root:GetAttribute("Weight")) == bin.Type
	local base = (root:GetAttribute("CashValue") or 1)
		* (isMatch and DepositConfig.MatchMultiplier or 1)
		* (1 + (pet.CashBonus or 0))
		* Services.RetentionService.CashMultiplier(player)
	local amount = math.max(1, math.floor(base * Services.PlayerSessionService.GetCashMultiplier(player) + 0.5))
	Services.EconomyService.AddCash(player, amount)
	Services.WalletService.OnDeposit(player, base, "Pet_" .. pet.Key)
	player:SetAttribute("PetCleaned", (player:GetAttribute("PetCleaned") or 0) + 1)
	Services.AnalyticsService.Economy(player, "Source", "Cash", amount, player:GetAttribute("RoomCash") or 0, "Gameplay", "Pet_" .. pet.Key, isMatch and "right bin (x2)" or "other bin (x1)")

	root:SetAttribute("Deposited", true)
	Services.ObjectService.Forget(root)
	local base2 = {
		Position = root.Position,
		BinPosition = bin.Part.Position,
		BinType = bin.Type,
		Color = root.Color,
		Size = root.Size,
		Name = root:GetAttribute("DisplayName"),
		Treasure = category == "Treasure",
		Pet = pet.Key,
		Owner = player.UserId,
	}
	for _, p in ipairs(match.Players) do
		local payload = table.clone(base2)
		if p == player then
			payload.Amount = amount
			payload.Match = isMatch
			payload.Mine = true
		end
		Remotes.Event("FXEvent"):FireClient(p, "Deposit", payload)
	end
	root:Destroy()
	Services.MatchService.OnObjectDeposited(player, category == "Treasure")
	return true
end

function DepositService.GetBins(): { Bin }
	return bins
end

-- Did a flight segment drop into this bin's mouth through its top opening? (Same rule as the
-- client's throw preview.) Catches fast throws that would otherwise bounce out between scans.
local lastPos: { [BasePart]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local function crossesMouth(mouth: BasePart, a: Vector3, b: Vector3): boolean
	local top = mouth.Position.Y + mouth.Size.Y / 2 - 0.8
	if a.Y < top then
		return false
	end
	local half = mouth.Size / 2
	for i = 1, 6 do
		local lp = mouth.CFrame:PointToObjectSpace(a:Lerp(b, i / 6))
		if math.abs(lp.X) <= half.X and math.abs(lp.Y) <= half.Y and math.abs(lp.Z) <= half.Z then
			return true
		end
	end
	return false
end

-- Is a thrown object (by its centre plus a bit of its size) touching this bin anywhere?
local function touchesBin(bin: Bin, root: BasePart): boolean
	local pad = Vector3.one * (TOUCH_MARGIN + math.min(1.5, root.Size.Magnitude / 2))
	local p = root.Position
	for _, box in ipairs(bin.Touch) do
		local mn, mx = box.Min - pad, box.Max + pad
		if p.X >= mn.X and p.X <= mx.X and p.Y >= mn.Y and p.Y <= mx.Y and p.Z >= mn.Z and p.Z <= mx.Z then
			return true
		end
	end
	return false
end

local function lenientThrower(root: BasePart): boolean
	local thrower = Players:GetPlayerByUserId(root:GetAttribute("LastHolderUserId") or 0)
	return thrower ~= nil and LENIENT_MODES[thrower:GetAttribute("InputMode") or ""] == true
end

local function sweptCheck()
	local match = Services.MatchService.GetMatch()
	if not match or match.State ~= "Searching" or #bins == 0 then
		return
	end
	for root, flight in pairs(Services.ObjectService.GetFlights()) do
		if flight.Thrown and root.Parent then
			local p = root.Position
			local prev = lastPos[root]
			lastPos[root] = p
			local lenient = lenientThrower(root)
			for _, bin in ipairs(bins) do
				if (prev and crossesMouth(bin.Part, prev, p)) or (lenient and touchesBin(bin, root)) then
					DepositService.Deposit(root, bin)
					break
				end
			end
		end
	end
end

function DepositService.Start()
	RunService.Heartbeat:Connect(sweptCheck)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local match = Services.MatchService.GetMatch()
			refreshBins(match and match.Runtime)
			if match and match.State == "Searching" and #bins > 0 then
				local folder = match.Runtime.Model:FindFirstChild("Clutter")
				if folder then
					params.FilterDescendantsInstances = { folder }
					for _, bin in ipairs(bins) do
						local seen = {}
						for _, part in ipairs(workspace:GetPartBoundsInBox(bin.Part.CFrame, bin.Part.Size, params)) do
							local root = clutterRootOf(part)
							if root and not seen[root] then
								seen[root] = true
								DepositService.Deposit(root, bin)
							end
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Clear(player)
	end)
	-- The client says how it's being played (touch, controller or mouse and keyboard).
	Remotes.Event("InputMode").OnServerEvent:Connect(function(player, mode)
		if mode == "Touch" or mode == "Gamepad" or mode == "KeyboardMouse" then
			player:SetAttribute("InputMode", mode)
		end
	end)
end

return DepositService
