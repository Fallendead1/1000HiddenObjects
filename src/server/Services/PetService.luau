--[[
	Helper pets (PetConfig): ownership, eggs, equipping, the welcome pet, and the helpers at work
	in rooms. Profile: data.Pets = { Owned = { [kind] = { Level, XP, Count } }, Equipped = { kind },
	Welcomed, IndexRewarded }.

	Attributes: PetData (JSON: Owned + Equipped), PetsEquipped (comma list, read by every client to
	draw followers), PetSlots, PetWelcomed, PetCleaned (this room), PetSnackExpires.
	FX events: Hatch { Egg, Kind, New, Level } to the player; PetTrip { Owner, Kind, Object,
	From, To } and PetBurst { Owner, Kind, Position } to everyone in the room. Pet deposits come
	through DepositService as a normal Deposit event with Pet set.

	The helper rules are in PetConfig's header: pets never touch the hidden object, the junk over
	it or anything near its spot, only take the top of a pile, stay under a hard rate cap, and
	rest while their owner is away.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local DepositConfig = require(Shared.Config.DepositConfig)
local PetConfig = require(Shared.Config.PetConfig)
local ProgressionConfig = require(Shared.Config.ProgressionConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)
local TableUtil = require(Shared.Utility.TableUtil)

local Services = require(script.Parent)

local PetService = {}

type Work = { Next: { [string]: number }, BurstAt: { [string]: number }, Tokens: number, TokenAt: number, MatchId: string? }

local work: { [Player]: Work } = {}
local limiter = RateLimiter.new(3, 4)
local rng = Random.new()
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

local TRIP_SECONDS = 0.75 -- the pet flies to the junk before it is picked up

local function now(): number
	return workspace:GetServerTimeNow()
end

local function xz(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- ===== Ownership =====

function PetService.Slots(player: Player): number
	local slots = PetConfig.BaseSlots
	local data = Services.DataService.Get(player)
	local level = data and ProgressionConfig.LevelFor(data.CleanerXP) or 1
	if level >= PetConfig.SlotLevel then
		slots += 1
	end
	if Services.MonetizationService.OwnsPass(player, "PetSlot") then
		slots += 1
	end
	return slots
end

function PetService.Publish(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local pets = data.Pets
	local active = PetService.Active(player)
	local owned = {}
	for kind, p in pairs(pets.Owned) do
		owned[kind] = { Level = p.Level, XP = p.XP, Next = PetConfig.XPToNext(p.Level), Count = p.Count }
	end
	player:SetAttribute("PetData", HttpService:JSONEncode({ Owned = owned, Equipped = active }))
	player:SetAttribute("PetsEquipped", table.concat(active, ","))
	player:SetAttribute("PetSlots", PetService.Slots(player))
	player:SetAttribute("PetWelcomed", pets.Welcomed == true)
end

-- The equipped pets that are out (the list is kept even when there are fewer slots than
-- pets in it, e.g. while a pass is still loading; the extras just rest).
function PetService.Active(player: Player): { string }
	local data = Services.DataService.Get(player)
	local active = {}
	if data then
		local slots = PetService.Slots(player)
		for i, kind in ipairs(data.Pets.Equipped) do
			if i > slots then
				break
			end
			if data.Pets.Owned[kind] then
				table.insert(active, kind)
			end
		end
	end
	return active
end

local function checkIndex(player: Player)
	local data = Services.DataService.Get(player)
	if not data or data.Pets.IndexRewarded then
		return
	end
	for _, def in ipairs(PetConfig.List) do
		if not data.Pets.Owned[def.Key] then
			return
		end
	end
	Services.DataService.Update(player, function(d)
		d.Pets.IndexRewarded = true
	end)
	Services.WalletService.Add(player, PetConfig.IndexReward, "Gameplay", "PetIndex")
	Services.NotificationService.Send(player, "Premium", string.format("PET INDEX COMPLETE! +$%d and the title %s", PetConfig.IndexReward, PetConfig.IndexTitle), 6)
	Services.AnalyticsService.Event(player, "pet_index_complete", #PetConfig.List)
	Services.ProgressionService.RefreshTag(player)
end

-- Gives a pet (a duplicate levels it up). Returns whether it's new and its level.
function PetService.GivePet(player: Player, kind: string, source: string, fx: { [string]: any }?): (boolean, number)
	local def = PetConfig.Get(kind)
	local data = Services.DataService.Get(player)
	if not def or not data then
		return false, 0
	end
	local isNew, level = false, 1
	local slots = PetService.Slots(player)
	local activeCount = #PetService.Active(player)
	Services.DataService.Update(player, function(d)
		local owned = d.Pets.Owned[kind]
		if owned then
			owned.Count = (owned.Count or 1) + 1
			if owned.Level < PetConfig.MaxLevel then
				owned.Level += 1
				owned.XP = 0
			end
			level = owned.Level
		else
			isNew = true
			d.Pets.Owned[kind] = { Level = 1, XP = 0, Count = 1 }
			if activeCount < slots then
				-- Out straight away (ahead of any resting extras).
				table.insert(d.Pets.Equipped, activeCount + 1, kind)
			end
		end
	end)
	PetService.Publish(player)
	local payload = { Egg = source, Kind = kind, New = isNew, Level = level }
	for k, v in pairs(fx or {}) do
		payload[k] = v
	end
	Remotes.Event("FXEvent"):FireClient(player, "Hatch", payload)
	Services.AnalyticsService.Funnel(player, "Pets", "pets " .. tostring(player.UserId), "Hatched", kind, def.Rarity, source)
	Services.AnalyticsService.Event(player, "pet_gained", level, kind, def.Rarity, source)
	if isNew and table.find((Services.DataService.Get(player) :: any).Pets.Equipped, kind) then
		Services.AnalyticsService.Funnel(player, "Pets", "pets " .. tostring(player.UserId), "Equipped", kind)
	end
	task.defer(checkIndex, player)
	Services.DataService.SaveSoon(player)
	return isNew, level
end

-- Hatches an egg for free (rewards). Returns the pet's kind.
function PetService.GrantEgg(player: Player, eggKey: string, source: string): string?
	local egg = PetConfig.Eggs[eggKey]
	if not egg then
		return nil
	end
	local total = 0
	for _, w in pairs(egg.Odds) do
		total += w
	end
	local roll = rng:NextNumber() * total
	local keys = TableUtil.Keys(egg.Odds)
	table.sort(keys)
	local kind = keys[#keys]
	for _, key in ipairs(keys) do
		roll -= egg.Odds[key]
		if roll <= 0 then
			kind = key
			break
		end
	end
	PetService.GivePet(player, kind, eggKey, { Source = source })
	return kind
end

local function buyEgg(player: Player, eggKey: any)
	local egg = type(eggKey) == "string" and PetConfig.Eggs[eggKey]
	if not egg then
		return
	end
	local session = "pets " .. tostring(player.UserId)
	if not Services.WalletService.TrySpend(player, egg.Price, "Shop", "Egg_" .. eggKey) then
		Services.NotificationService.Send(player, "Warning", string.format("You need $%d saved Cash for the %s.", egg.Price, egg.Name))
		return
	end
	Services.AnalyticsService.Funnel(player, "Pets", session, "Bought", eggKey)
	PetService.GrantEgg(player, eggKey, "Shop")
end

local function equip(player: Player, kind: any, on: any)
	local data = Services.DataService.Get(player)
	if not data or type(kind) ~= "string" or not data.Pets.Owned[kind] then
		return
	end
	local slots = PetService.Slots(player)
	local list = data.Pets.Equipped
	local index = table.find(list, kind)
	if index and index > slots then
		-- Resting (over the slot count): equipping moves it out.
		table.remove(list, index)
		index = nil
	end
	if on == true and not index then
		if #list >= slots then
			Services.NotificationService.Send(player, "Warning", "All your pet slots are full. Unequip a pet first.")
			return
		end
		Services.DataService.Update(player, function(d)
			table.insert(d.Pets.Equipped, kind)
		end)
		Services.AnalyticsService.Funnel(player, "Pets", "pets " .. tostring(player.UserId), "Equipped", kind)
	elseif on == false and index then
		Services.DataService.Update(player, function(d)
			table.remove(d.Pets.Equipped, index)
		end)
	end
	PetService.Publish(player)
	Services.DataService.SaveSoon(player)
end

local function welcome(player: Player)
	local data = Services.DataService.Get(player)
	if not data or data.Pets.Welcomed then
		return
	end
	Services.DataService.Update(player, function(d)
		d.Pets.Welcomed = true
	end)
	PetService.GivePet(player, PetConfig.StarterPet, "Welcome")
	Services.AnalyticsService.Event(player, "welcome_gift", 1, player:GetAttribute("TutorialCompleted") and "returning" or "new player")
end

-- Pets sold directly as game passes arrive as soon as the pass is owned.
local function syncPassPets(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	for _, def in ipairs(PetConfig.List) do
		if def.Pass and Services.MonetizationService.OwnsPass(player, def.Pass) and not data.Pets.Owned[def.Key] then
			PetService.GivePet(player, def.Key, "Pass")
		end
	end
end

-- ===== Helpers at work =====

local function speedFor(player: Player): number
	local speed = 1
	if Services.MonetizationService.OwnsPass(player, "FasterPets") then
		speed *= PetConfig.FasterPetsMultiplier
	end
	if (player:GetAttribute("PetSnackExpires") or 0) > now() then
		speed *= PetConfig.SnackMultiplier
	end
	return speed
end

-- Is anything resting on this object? (Pets only take the top of a pile.)
local function covered(root: BasePart, folder: Instance): boolean
	overlap.FilterDescendantsInstances = { folder }
	local size = root.Size
	local top = root.Position.Y + math.max(size.X, size.Y, size.Z) / 2
	local box = CFrame.new(root.Position.X, top + 0.35, root.Position.Z)
	for _, part in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(math.max(size.X, 1), 0.7, math.max(size.Z, 1)), overlap)) do
		local other = part
		if not other:GetAttribute("ObjectId") and other.Parent and other.Parent:IsA("BasePart") then
			other = other.Parent
		end
		if other ~= root and other:GetAttribute("ObjectId") and other.Position.Y > root.Position.Y + 0.1 then
			return true
		end
	end
	return false
end

-- What the hidden object's spot rules out: its blockers, its packed junk, and its surroundings.
local function forbidden(match): ({ [Instance]: boolean }, Vector3?)
	local set = {}
	local spot = nil
	if match.TargetSocket and not match.TargetRevealed then
		spot = match.TargetSocket.Position
		for _, b in ipairs(match.TargetSocket.Blockers) do
			set[b] = true
		end
	end
	if match.KeyChunk then
		set[match.KeyChunk] = true
	end
	return set, spot
end

local function pickJunk(player: Player, match, def, here: Vector3, count: number, taken: { [Instance]: boolean }): { BasePart }
	local folder = match.Runtime.Model:FindFirstChild("Clutter")
	if not folder then
		return {}
	end
	local blocked, spot = forbidden(match)
	local candidates = {}
	for _, obj in ipairs(match.Runtime.Objects) do
		if obj.Parent and obj.Anchored and not taken[obj] and not blocked[obj]
			and not obj:GetAttribute("IsChunk") and not obj:GetAttribute("Deposited") and not obj:GetAttribute("PetClaimed")
			and (obj:GetAttribute("Weight") or 1) <= def.MaxWeight and not Services.ObjectService.IsBusy(obj) then
			local d = (obj.Position - here).Magnitude
			if d <= PetConfig.Reach and (not spot or xz(obj.Position, spot) >= PetConfig.SafeRadius) then
				local score = d + rng:NextNumber() * 6
				local category = obj:GetAttribute("Category")
				if def.TreasureFirst and category == "Treasure" then
					score -= 200
				elseif def.Loves and category == def.Loves then
					score -= 100
				end
				table.insert(candidates, { Obj = obj, Score = score })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.Score < b.Score
	end)
	local picked = {}
	for _, c in ipairs(candidates) do
		if #picked >= count then
			break
		end
		local limit = #picked == 0 and def.MaxWeight or (def.CarryWeight or def.MaxWeight)
		if (c.Obj:GetAttribute("Weight") or 1) <= limit and not covered(c.Obj, folder) then
			table.insert(picked, c.Obj)
		end
		if #picked == 0 and c.Score > PetConfig.Reach * 2 then
			break
		end
	end
	return picked
end

local function binFor(def, root: BasePart)
	local bins = Services.DepositService.GetBins()
	if #bins == 0 then
		return nil
	end
	local category = root:GetAttribute("Category")
	local want = DepositConfig.MatchingType(category, root:GetAttribute("Weight"))
	local useRight = def.RightBin or (def.Loves ~= nil and category == def.Loves) or rng:NextNumber() < PetConfig.RightBinChance
	if want and useRight then
		for _, bin in ipairs(bins) do
			if bin.Type == want then
				return bin
			end
		end
	end
	return bins[rng:NextInteger(1, #bins)]
end

local function trip(player: Player, match, def, here: Vector3, st: Work): boolean
	local count = def.Carry or 1
	local junk = pickJunk(player, match, def, here, math.min(count, math.floor(st.Tokens)), {})
	if #junk == 0 then
		return false
	end
	st.Tokens -= #junk
	for i, root in ipairs(junk) do
		local bin = binFor(def, root)
		if bin then
			root:SetAttribute("PetClaimed", true)
			for _, p in ipairs(match.Players) do
				Remotes.Event("FXEvent"):FireClient(p, "PetTrip", { Owner = player.UserId, Kind = def.Key, Object = root, From = root.Position, To = bin.Part.Position, Index = i })
			end
			task.delay(TRIP_SECONDS + (i - 1) * 0.25, function()
				if root.Parent and not Services.ObjectService.IsBusy(root) and Services.MatchService.GetMatch() == match then
					if Services.DepositService.PetDeposit(player, root, bin, def) then
						Services.DataService.Update(player, function(d)
							local owned = d.Pets.Owned[def.Key]
							if owned and owned.Level < PetConfig.MaxLevel then
								owned.XP += 1
								if owned.XP >= PetConfig.XPToNext(owned.Level) then
									owned.XP = 0
									owned.Level += 1
									Services.NotificationService.Send(player, "Success", string.format("%s reached level %d!", def.Name, owned.Level))
								end
							end
						end)
					end
				elseif root.Parent then
					root:SetAttribute("PetClaimed", nil)
				end
			end)
		end
	end
	return true
end

-- The dragon bursts packed junk near its owner, never near the hidden object.
local function burst(player: Player, match, def, here: Vector3)
	local blocked, spot = forbidden(match)
	local best, bestD = nil, math.huge
	for _, obj in ipairs(match.Runtime.Objects) do
		if obj.Parent and obj:GetAttribute("IsChunk") and not blocked[obj] and not Services.ObjectService.IsBusy(obj) then
			local d = (obj.Position - here).Magnitude
			if d < bestD and d <= PetConfig.Reach and (not spot or xz(obj.Position, spot) >= PetConfig.PetBurstSafeRadius) then
				best, bestD = obj, d
			end
		end
	end
	if best then
		for _, p in ipairs(match.Players) do
			Remotes.Event("FXEvent"):FireClient(p, "PetBurst", { Owner = player.UserId, Kind = def.Key, Position = best.Position })
		end
		task.delay(0.6, function()
			if best.Parent and not Services.ObjectService.IsBusy(best) and Services.MatchService.GetMatch() == match then
				Services.ChunkService.Burst(best, player)
			end
		end)
	end
end

local function step(dt: number)
	local clock = os.clock()
	local match = Services.MatchService.GetMatch()
	for player, st in pairs(work) do
		local data = Services.DataService.Get(player)
		if not data or not match or match.State ~= "Searching" or not table.find(match.Players, player) then
			st.MatchId = nil
			continue
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not Services.RetentionService.IsActive(player, PetConfig.ActiveWindow) then
			continue
		end
		local speed = speedFor(player)
		if st.MatchId ~= match.Id then
			-- A new room: pets start after a short, staggered wait.
			st.MatchId = match.Id
			st.Tokens = 1
			st.TokenAt = clock
			for i, kind in ipairs(PetService.Active(player)) do
				st.Next[kind] = clock + 4 + i * 1.5
				st.BurstAt[kind] = clock + 12
			end
		end
		local cap = PetConfig.MaxPerMinute * speed / 60
		st.Tokens = math.min(st.Tokens + (clock - st.TokenAt) * cap, 2)
		st.TokenAt = clock
		for _, kind in ipairs(PetService.Active(player)) do
			local def = PetConfig.Get(kind)
			local owned = data.Pets.Owned[kind]
			if def and owned then
				if def.BurstEvery and clock >= (st.BurstAt[kind] or 0) then
					st.BurstAt[kind] = clock + def.BurstEvery / speed
					burst(player, match, def, root.Position)
				end
				if clock >= (st.Next[kind] or 0) and st.Tokens >= 1 then
					local ok = trip(player, match, def, root.Position, st)
					st.Next[kind] = clock + (ok and (PetConfig.Interval(kind, owned.Level) / speed + rng:NextNumber() * 0.8) or 2)
				end
			end
		end
	end
end

-- ===== Lifecycle =====

function PetService.Init()
	Remotes.Event("BuyEgg").OnServerEvent:Connect(function(player, eggKey)
		if limiter:Allow(player) then
			Services.RetentionService.Touch(player)
			buyEgg(player, eggKey)
		end
	end)
	Remotes.Event("EquipPet").OnServerEvent:Connect(function(player, kind, on)
		if limiter:Allow(player) then
			equip(player, kind, on)
		end
	end)
	Remotes.Event("PetWelcome").OnServerEvent:Connect(function(player)
		if limiter:Allow(player) then
			welcome(player)
		end
	end)

	local function onPlayer(player: Player)
		work[player] = { Next = {}, BurstAt = {}, Tokens = 1, TokenAt = os.clock() }
		for _, name in ipairs({ "CleanerLevel", "Pass_PetSlot", "Pass_FasterPets" }) do
			player:GetAttributeChangedSignal(name):Connect(function()
				PetService.Publish(player)
			end)
		end
		for _, def in ipairs(PetConfig.List) do
			if def.Pass then
				player:GetAttributeChangedSignal("Pass_" .. def.Pass):Connect(function()
					syncPassPets(player)
				end)
			end
		end
		task.spawn(function()
			if Services.DataService.WaitFor(player, 15) then
				PetService.Publish(player)
				syncPassPets(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		work[player] = nil
	end)
end

function PetService.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			step(acc)
			acc = 0
		end
	end)
end

return PetService
