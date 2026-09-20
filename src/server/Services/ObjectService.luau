--[[
	Server authority for every individual clutter object.

	States (attribute "State"):
	  Resting (anchored) -> Held (unanchored, no collision; the holder owns its physics while an
	  AlignPosition keeps it in front of them; server leashes it) -> Flying (thrown or dropped:
	  normal physics, it rolls and tumbles) -> Resting once it has been still for SettleTime,
	  anchored wherever physics left it.

	Smooth throws: the holder already simulates the object, so on release they keep simulating
	it (no ownership hand-off hitch). The server checks the flight against the allowed throw
	speed and takes it back after the first impact or OwnedFlightTime.

	Resting objects are anchored ("dead"): the room settles under real physics behind the loading
	screen and is then anchored where it came to rest (FreezeRoom), so nothing creeps, shakes
	underfoot or gets shoved by walking. Only what is grabbed, thrown, burst or knocked loose is a
	physics body, and only until it lands. Nothing floats: when a resting object is taken out of a
	pile, whatever rested on it wakes up and falls (wakeAbove). Thrown objects pass through players
	until they land.

	Armful: grabbing something small (ArmfulMaxWeight) also scoops up the small, uncovered things
	right beside it, up to the player's Arm Capacity. They ride along beside the held object
	(the holder steers them too) and leave the hands with it: thrown the same way as one throw
	group (DepositService calls DOUBLE!, TRIPLE!) or set down. The held object itself behaves
	exactly as without them.

	Cash is never paid here: objects pay when deposited in a bin (DepositService).
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ClutterConfig = require(Shared.Config.ClutterConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)
local Heavy = require(Shared.Utility.Heavy)

local Services = require(script.Parent)

local ObjectService = {}

type Held = { Root: BasePart, Attachment: Attachment, AlignPos: AlignPosition, AlignOri: AlignOrientation, Passengers: { BasePart } }
export type Flight = {
	Since: number,
	StillFor: number,
	By: Player?,
	Lift: boolean?,
	LastSpeed: number?,
	Thrown: boolean?,
	ReleasePos: Vector3?,
	MaxSpeed: number?,
	Owned: boolean?,
	Cheated: boolean?,
	LaunchVelocity: Vector3?,
	CheckPos: Vector3?,
	CheckAt: number?,
	ThrowGroup: number?,
	GroupSize: number?,
	BankedAt: number?,
}

local runtime = nil
local held: { [Player]: Held } = {}
local heldBy: { [BasePart]: Player } = {}
local active: { [BasePart]: Flight } = {}
-- Landed but still moving (a flight that timed out mid-roll, or junk jittering in place):
-- anchored as soon as it's still or stops going anywhere.
local unsettled: { [BasePart]: { Pos: Vector3, At: number } } = {}
local grabLimiter = RateLimiter.new(GameConfig.GrabRateLimit, GameConfig.GrabRateLimit)
-- Throws get their own, looser budget so a legitimate release is never swallowed.
local throwLimiter = RateLimiter.new(GameConfig.GrabRateLimit * 2, GameConfig.GrabRateLimit * 2)
local rng = Random.new()
local throwGroups = 0
local scoopParams = OverlapParams.new()
scoopParams.FilterType = Enum.RaycastFilterType.Include
local coverParams = RaycastParams.new()
coverParams.FilterType = Enum.RaycastFilterType.Exclude

local SOFT = { Clothes = true, Bedding = true, Bag = true, Toy = true, Shoes = true, Chunk = true }
local PAPER = { Paper = true, Book = true, School = true }

-- Studio/dev-only input audit: proves one press = one grab request = one throw.
local function audit(player: Player, counter: string)
	if Services.DevService.IsAuthorized(player) then
		player:SetAttribute(counter, (player:GetAttribute(counter) or 0) + 1)
	end
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include

local function setupCollisionGroups()
	for _, name in ipairs({ "Players", "Clutter", "ClutterHeavy", "ClutterFlying", "BinWall" }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	-- Players walk on the mess and kick through it: every resting object is solid to them.
	PhysicsService:CollisionGroupSetCollidable("Players", "Clutter", true)
	PhysicsService:CollisionGroupSetCollidable("Players", "ClutterHeavy", true)
	-- Thrown objects pass through players until they land, so a throw never bumps the thrower
	-- or clobbers a teammate.
	PhysicsService:CollisionGroupSetCollidable("Players", "ClutterFlying", false)
	-- The walls behind the bins (RoomService) stop junk only; players walk through them.
	PhysicsService:CollisionGroupSetCollidable("Players", "BinWall", false)
end

local function restingGroup(root: BasePart): string
	return (root:GetAttribute("Weight") or 1) >= ClutterConfig.PlayerCollisionWeight and "ClutterHeavy" or "Clutter"
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isRoomClutter(root: any): boolean
	return runtime ~= nil
		and typeof(root) == "Instance"
		and root:IsA("BasePart")
		and CollectionService:HasTag(root, "Clutter")
		and root:IsDescendantOf(runtime.Model)
end

local function closestPointDistance(root: BasePart, point: Vector3): number
	local lp = root.CFrame:PointToObjectSpace(point)
	local half = root.Size / 2
	local clamped = Vector3.new(math.clamp(lp.X, -half.X, half.X), math.clamp(lp.Y, -half.Y, half.Y), math.clamp(lp.Z, -half.Z, half.Z))
	return (lp - clamped).Magnitude
end

local function hasLineOfSight(from: Vector3, root: BasePart): boolean
	if #runtime.StructureParts == 0 then
		return true
	end
	losParams.FilterDescendantsInstances = runtime.StructureParts
	local target = root.Position
	local dir = target - from
	local result = workspace:Raycast(from, dir, losParams)
	return result == nil or (result.Position - from).Magnitude >= dir.Magnitude - math.max(root.Size.X, root.Size.Y, root.Size.Z) / 2 - 0.5
end

local function setState(root: BasePart, state: string)
	root:SetAttribute("State", state)
end

local function serverOwns(root: BasePart)
	if not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
end

-- Dead where it lies. An anchored part keeps the velocity it had and would carry anyone standing
-- on it like a conveyor belt, so that is cleared too.
local function anchorAtRest(root: BasePart)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- A loose, server-tracked physics body from now until it lands (see settle).
local function activate(root: BasePart, by: Player?, state: string, keepOwner: boolean?)
	root.Anchored = false
	root.CanCollide = true
	if not keepOwner then
		serverOwns(root)
	end
	active[root] = { Since = os.clock(), StillFor = 0, By = by }
	unsettled[root] = nil
	setState(root, state)
end

local function clutterRootOf(part: Instance, folder: Instance): BasePart?
	local node: Instance? = part
	while node and node ~= folder do
		if node:IsA("BasePart") and CollectionService:HasTag(node, "Clutter") then
			return node :: BasePart
		end
		node = node.Parent
	end
	return nil
end

--[[
	Nothing floats: when a resting object is taken, burst or knocked loose, whatever rests on it
	or leans on it wakes up and falls, and so on up the pile. Anything anchored from the base's
	middle to just above its top (a little wider than it) whose centre is higher counts. Generous
	on purpose: waking something that was fine costs a moment of physics (it is anchored again
	once still), missing one leaves it hanging in the air.
]]
local WAKE_LIMIT = 150
local WAKE_PAD = 0.3
local wakeParams = OverlapParams.new()
wakeParams.FilterType = Enum.RaycastFilterType.Include

local function wakeAbove(base: BasePart)
	local folder = runtime and runtime.Model:FindFirstChild("Clutter")
	if not folder then
		return
	end
	wakeParams.FilterDescendantsInstances = { folder }
	local queue = { base }
	local seen = { [base] = true }
	local i = 1
	while queue[i] and #queue <= WAKE_LIMIT do
		local cf, half = queue[i].CFrame, queue[i].Size / 2
		i += 1
		-- World-space half extents of the (possibly rotated) box.
		local ext = Vector3.new(
			math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
			math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
			math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
		)
		local centre = cf.Position
		local height = ext.Y + 0.6
		local box = CFrame.new(centre.X, centre.Y + height / 2, centre.Z)
		local size = Vector3.new(ext.X * 2 + WAKE_PAD * 2, height, ext.Z * 2 + WAKE_PAD * 2)
		for _, part in ipairs(workspace:GetPartBoundsInBox(box, size, wakeParams)) do
			local root = clutterRootOf(part, folder)
			if root and not seen[root] and root.Anchored and not heldBy[root] and root.Position.Y > centre.Y then
				seen[root] = true
				activate(root, nil, "Falling")
				table.insert(queue, root)
			end
		end
	end
end

-- Thrown objects feel reduced gravity until their first impact so throws carry across the room.
local function addLift(root: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.Name = "FlightLift"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * (1 - GameConfig.ThrowGravityScale), 0)
	force.Parent = root
end

local function clearLift(root: BasePart)
	for _, name in ipairs({ "FlightLift", "FlightAttachment" }) do
		local inst = root:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
end

local function landSound(root: BasePart): string
	local category = root:GetAttribute("Category")
	if SOFT[category] then
		return "LandSoft"
	elseif PAPER[category] then
		return "LandPaper"
	end
	return "LandHard"
end

local function settle(root: BasePart, info: Flight, stopped: boolean?)
	active[root] = nil
	if not root.Parent then
		return
	end
	clearLift(root)
	if info.Owned then
		info.Owned = false
		serverOwns(root)
	end
	if root.CollisionGroup == "ClutterFlying" then
		root.CollisionGroup = restingGroup(root)
	end
	-- Landed: dead again, anchored where it stopped (or the moment it stops, if the flight timed
	-- out while it was still rolling).
	if stopped or (root.AssemblyLinearVelocity.Magnitude < GameConfig.SettleSpeed and root.AssemblyAngularVelocity.Magnitude < 3) then
		anchorAtRest(root)
	else
		unsettled[root] = { Pos = root.Position, At = os.clock() }
	end
	setState(root, "Resting")
	if info.Thrown then
		local match = Services.MatchService.GetMatch()
		for _, p in ipairs(match and match.Players or {}) do
			Remotes.Event("FXEvent"):FireClient(p, "Land", { Position = root.Position, Sound = landSound(root) })
		end
	end
	Services.MatchService.OnObjectSettled(root)
end

local function makeActive(root: BasePart, by: Player?, state: string, keepOwner: boolean?)
	local wasResting = root.Anchored
	activate(root, by, state, keepOwner)
	if wasResting then
		wakeAbove(root)
	end
end

-- A carried passenger (Armful) lets go: no longer held, its hold constraints removed.
local function detachPassenger(p: BasePart)
	heldBy[p] = nil
	for _, name in ipairs({ "ArmfulAlignPosition", "ArmfulAlignOrientation", "ArmfulAttachment" }) do
		local inst = p:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
	p:SetAttribute("HeldByUserId", 0)
end

-- Everything carried with the held object leaves the hands with it: thrown the same way (the
-- thrower's client launches them too, as one throw group) or set down. Returns the group id.
local function releasePassengers(player: Player, h: Held, velocity: Vector3): number?
	local passengers = h.Passengers
	h.Passengers = {}
	if #passengers == 0 then
		return nil
	end
	local hrp = characterRoot(player)
	local throwing = velocity.Magnitude > 1 and hrp ~= nil and player.Parent ~= nil
	local group = nil
	if throwing then
		throwGroups += 1
		group = throwGroups
	end
	for _, p in ipairs(passengers) do
		if heldBy[p] == player then
			detachPassenger(p)
			if p.Parent then
				if hrp and (p.Position - hrp.Position).Magnitude > GameConfig.HoldMaxDistance then
					p.CFrame = CFrame.new(hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 1.5, 0))
				end
				makeActive(p, player, "Flying", throwing)
				local info = active[p]
				info.Thrown = true
				info.ReleasePos = p.Position
				if throwing then
					local v = velocity.Unit * ObjectService.ThrowVelocity(player, p:GetAttribute("Weight") or 1, velocity.Unit).Magnitude
					info.LaunchVelocity = v
					p.CollisionGroup = "ClutterFlying"
					addLift(p)
					info.Lift = true
					info.MaxSpeed = v.Magnitude
					info.Owned = true
					info.ThrowGroup = group
					info.GroupSize = #passengers + 1
				else
					p.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
	end
	return group
end

local function release(player: Player, velocity: Vector3)
	local h = held[player]
	if not h then
		return
	end
	held[player] = nil
	local groupSize = #h.Passengers + 1
	local group = releasePassengers(player, h, velocity)
	local root = h.Root
	heldBy[root] = nil
	h.AlignPos:Destroy()
	h.AlignOri:Destroy()
	h.Attachment:Destroy()
	root:SetAttribute("HeldByUserId", 0)
	if player.Parent then
		player:SetAttribute("HeldObjectId", "")
		player:SetAttribute("HeldWeight", 0)
		Services.PlayerSessionService.ApplyWalkSpeed(player)
	end
	if not root.Parent then
		return
	end
	local hrp = characterRoot(player)
	if hrp and (root.Position - hrp.Position).Magnitude > GameConfig.HoldMaxDistance then
		root.CFrame = CFrame.new(hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 1.5, 0))
	end
	local throwing = velocity.Magnitude > 1 and hrp ~= nil and player.Parent ~= nil
	-- A thrower keeps simulating their own throw (they already own it while holding it).
	makeActive(root, player, "Flying", throwing)
	local info = active[root]
	info.Thrown = true
	info.ReleasePos = root.Position
	if throwing then
		-- The thrower's client has already launched it (it owns the physics); writing the
		-- velocity here too would fight that simulation. It is kept as a fallback launch.
		info.LaunchVelocity = velocity
		root.CollisionGroup = "ClutterFlying"
		addLift(root)
		info.Lift = true
		info.MaxSpeed = velocity.Magnitude
		info.Owned = true
		info.ThrowGroup = group
		info.GroupSize = group and groupSize or nil
	else
		root.AssemblyLinearVelocity = velocity
	end
end

-- Armful: the small, uncovered things right beside a small grabbed object, same kind first and
-- then closest, up to the player's Arm Capacity (the grabbed object counts as one).
local function scoopCandidates(player: Player, root: BasePart, hrp: BasePart): { BasePart }
	local room = Services.PlayerSessionService.GetArmful(player) - 1
	local folder = root.Parent
	if room <= 0 or not folder or (root:GetAttribute("Weight") or 1) > GameConfig.ArmfulMaxWeight then
		return {}
	end
	scoopParams.FilterDescendantsInstances = { folder }
	local found, seen = {}, { [root] = true }
	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, GameConfig.ArmfulRadius, scoopParams)) do
		local obj = clutterRootOf(part, folder)
		if obj and not seen[obj] then
			seen[obj] = true
			local flight = active[obj]
			if obj:GetAttribute("Movable") == true and not obj:GetAttribute("IsChunk") and not obj:GetAttribute("Deposited")
				and obj:GetAttribute("Category") ~= "Treasure" and (obj:GetAttribute("Weight") or 1) <= GameConfig.ArmfulMaxWeight
				and not heldBy[obj] and not (flight and flight.Thrown) then
				-- Only what's on top: something buried stays for digging.
				coverParams.FilterDescendantsInstances = { obj, root, player.Character :: Instance }
				local above = workspace:Raycast(obj.Position + Vector3.new(0, obj.Size.Y / 2 - 0.05, 0), Vector3.new(0, 4, 0), coverParams)
				local cover = above and clutterRootOf(above.Instance, folder)
				if not cover and hasLineOfSight(hrp.Position + Vector3.new(0, 1.5, 0), obj) then
					table.insert(found, obj)
				end
			end
		end
	end
	local category = root:GetAttribute("Category")
	table.sort(found, function(a, b)
		local sa, sb = a:GetAttribute("Category") == category, b:GetAttribute("Category") == category
		if sa ~= sb then
			return sa
		end
		return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
	end)
	local picked = {}
	for i = 1, math.min(room, #found) do
		picked[i] = found[i]
	end
	return picked
end

-- Picks up one Armful passenger: held like the main object (no collision, the holder simulates
-- and steers it), but through its own constraints.
local function carry(player: Player, p: BasePart, responsiveness: number)
	if p.Anchored then
		wakeAbove(p)
	end
	active[p] = nil
	clearLift(p)
	unsettled[p] = nil
	heldBy[p] = player
	p.Anchored = false
	p.CanCollide = false
	local attachment = Instance.new("Attachment")
	attachment.Name = "ArmfulAttachment"
	attachment.Parent = p
	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "ArmfulAlignPosition"
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = attachment
	alignPos.Position = p.Position
	alignPos.MaxForce = 1e7
	alignPos.MaxVelocity = 80
	alignPos.Responsiveness = responsiveness
	alignPos.Parent = p
	local alignOri = Instance.new("AlignOrientation")
	alignOri.Name = "ArmfulAlignOrientation"
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = attachment
	alignOri.CFrame = p.CFrame.Rotation
	alignOri.MaxTorque = 1e7
	alignOri.Responsiveness = responsiveness
	alignOri.Parent = p
	pcall(function()
		p:SetNetworkOwner(player)
	end)
	p:SetAttribute("HeldByUserId", player.UserId)
	p:SetAttribute("LastHolderUserId", player.UserId)
	setState(p, "Held")
	Services.MatchService.OnObjectGrabbed(p)
end

function ObjectService.Grab(player: Player, root: any): (boolean, string?)
	local match = Services.MatchService.GetMatchForPlayer(player)
	if not match or match.State ~= "Searching" or held[player] then
		return false, "Busy"
	end
	if not isRoomClutter(root) or root:GetAttribute("Movable") ~= true then
		return false, "Invalid"
	end
	if heldBy[root] then
		return false, "Held"
	end
	local hrp = characterRoot(player)
	if not hrp then
		return false, "Dead"
	end
	local weight = root:GetAttribute("Weight") or 1
	if closestPointDistance(root, hrp.Position) > GameConfig.GrabDistance + GameConfig.GrabLeniency then
		return false, "TooFar"
	end
	if not hasLineOfSight(hrp.Position + Vector3.new(0, 1.5, 0), root) then
		return false, "Blocked"
	end
	Services.RetentionService.Touch(player)
	-- Nothing is too heavy to lift; heavier than your Strength handles is slow to carry and
	-- short to throw (Shared/Utility/Heavy). A saved Lift It Now turns on for it.
	if weight > Services.PlayerSessionService.GetMaxWeight(player) and not root:GetAttribute("IsChunk") then
		Services.RetentionService.NoteTooHeavy(player, weight)
		if weight > Services.PlayerSessionService.GetMaxWeight(player) then
			Remotes.Event("FXEvent"):FireClient(player, "TooHeavy", { Name = root:GetAttribute("DisplayName"), Weight = weight, RequiredLevel = Services.PlayerSessionService.StrengthLevelToLift(player, weight) or UpgradeConfig.StrengthLevelFor(weight) })
		end
	end
	-- Whatever rested on it falls instead of hanging in the air.
	if root.Anchored then
		wakeAbove(root)
	end
	-- Packed junk bursts into its pieces instead of being carried.
	if root:GetAttribute("IsChunk") then
		active[root] = nil
		Services.ChunkService.Burst(root, player)
		return false, "Burst"
	end

	active[root] = nil
	clearLift(root)
	heldBy[root] = player
	unsettled[root] = nil
	root.Anchored = false
	root.CanCollide = false
	local attachment = Instance.new("Attachment")
	attachment.Name = "HoldAttachment"
	attachment.Parent = root
	local responsiveness = Services.PlayerSessionService.GetHoldResponsiveness(player, weight)
	local alignPos = Instance.new("AlignPosition")
	alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPos.Attachment0 = attachment
	alignPos.Position = root.Position
	alignPos.MaxForce = 1e7
	alignPos.MaxVelocity = 80
	alignPos.Responsiveness = responsiveness
	alignPos.Parent = root
	local alignOri = Instance.new("AlignOrientation")
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = attachment
	alignOri.CFrame = root.CFrame.Rotation
	alignOri.MaxTorque = 1e7
	alignOri.Responsiveness = responsiveness
	alignOri.Parent = root
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	local passengers = scoopCandidates(player, root, hrp)
	held[player] = { Root = root, Attachment = attachment, AlignPos = alignPos, AlignOri = alignOri, Passengers = passengers }
	for _, p in ipairs(passengers) do
		carry(player, p, responsiveness)
	end
	root:SetAttribute("HeldByUserId", player.UserId)
	root:SetAttribute("LastHolderUserId", player.UserId)
	setState(root, "Held")
	player:SetAttribute("HeldObjectId", root:GetAttribute("ObjectId"))
	player:SetAttribute("HeldWeight", weight)
	Services.PlayerSessionService.ApplyWalkSpeed(player)
	Services.AnalyticsService.Grabbed(player)
	-- Lifting the last thing off the key reveals it right away.
	Services.MatchService.OnObjectGrabbed(root)
	return true, nil
end

-- The launch velocity for a throw (the client predicts the same numbers for its arc preview).
function ObjectService.ThrowVelocity(player: Player, weight: number, direction: Vector3): Vector3
	local speed = Services.PlayerSessionService.GetThrowSpeed(player) * math.clamp(1.3 - weight * GameConfig.ThrowWeightFalloff, 0.55, 1.2)
		* Heavy.ThrowFactor(weight, Services.PlayerSessionService.GetMaxWeight(player))
	return (direction + Vector3.new(0, GameConfig.ThrowUpwardBias, 0)).Unit * speed
end

-- Only the exact object the client says it is holding can be thrown.
function ObjectService.Throw(player: Player, objectId: any, direction: any)
	local h = held[player]
	if not h or typeof(objectId) ~= "string" or h.Root:GetAttribute("ObjectId") ~= objectId then
		return
	end
	local velocity = Vector3.zero
	if typeof(direction) == "Vector3" and direction.Magnitude > 0.1 and direction.Magnitude < 1e4 and direction.X == direction.X then
		velocity = ObjectService.ThrowVelocity(player, h.Root:GetAttribute("Weight") or 1, direction.Unit)
	end
	release(player, velocity)
	Services.AnalyticsService.Threw(player)
end

-- Drop in place. With an objectId, only drops if that is really the held object.
function ObjectService.Drop(player: Player, objectId: any?)
	local h = held[player]
	if h and (objectId == nil or h.Root:GetAttribute("ObjectId") == objectId) then
		release(player, Vector3.zero)
	end
end

function ObjectService.GetHeld(player: Player): BasePart?
	local h = held[player]
	return h and h.Root or nil
end

-- The ObjectIds of the small things carried along with the held object (Armful).
function ObjectService.GetPassengerIds(player: Player): { string }
	local ids = {}
	local h = held[player]
	for _, p in ipairs(h and h.Passengers or {}) do
		table.insert(ids, p:GetAttribute("ObjectId"))
	end
	return ids
end

function ObjectService.GetHolder(root: BasePart): Player?
	return heldBy[root]
end

function ObjectService.GetFlight(root: BasePart): Flight?
	return active[root]
end

-- Every tracked loose object in motion (read-only; used by DepositService for swept checks).
function ObjectService.GetFlights(): { [BasePart]: Flight }
	return active
end

function ObjectService.IsBusy(root: BasePart): boolean
	return heldBy[root] ~= nil or active[root] ~= nil
end

-- Start tracking a loose object as a physics body in flight (chunk pieces, knocked objects).
function ObjectService.Activate(root: BasePart, by: Player?)
	makeActive(root, by, "Falling")
end

-- Stop tracking an object that is leaving the room (deposited); drops it first if held. Whatever
-- rested on it falls.
function ObjectService.Forget(root: BasePart)
	local holder = heldBy[root]
	local h = holder and held[holder]
	if h and h.Root ~= root then
		-- A carried passenger (it went into a bin while carried): only it leaves the hands.
		local i = table.find(h.Passengers, root)
		if i then
			table.remove(h.Passengers, i)
		end
		detachPassenger(root)
	elseif holder then
		release(holder, Vector3.zero)
	end
	active[root] = nil
	unsettled[root] = nil
	if root.Anchored then
		wakeAbove(root)
	end
end

-- Whatever rests on this object falls (call before it disappears, e.g. a chunk bursting).
function ObjectService.Wake(root: BasePart)
	wakeAbove(root)
end

-- Teleport an object (dev tools); it drops from there and is anchored once it lands.
function ObjectService.Relocate(root: BasePart, cframe: CFrame)
	if root.Anchored then
		wakeAbove(root)
	end
	root.CFrame = cframe
	activate(root, nil, "Falling")
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

--[[
	The freshly settled room goes dead: everything is anchored where physics left it, so nothing
	creeps, shakes underfoot or gets shoved. The objects in stillLoose (still moving when the room
	settled, or put back by hand) and whatever rests on them stay physics bodies until they land.
	Returns how many were left loose.
]]
function ObjectService.FreezeRoom(stillLoose: { [BasePart]: boolean }?): number
	if not runtime then
		return 0
	end
	local falling = {}
	for _, obj in ipairs(runtime.Objects) do
		if obj.Parent and not obj.Anchored and not heldBy[obj] and not active[obj] then
			if stillLoose and stillLoose[obj] then
				table.insert(falling, obj)
			else
				anchorAtRest(obj)
			end
		end
	end
	for _, obj in ipairs(falling) do
		activate(obj, nil, "Falling")
	end
	for _, obj in ipairs(falling) do
		wakeAbove(obj)
	end
	return #falling
end

function ObjectService.SetRoom(rt)
	ObjectService.ClearRoom()
	runtime = rt
end

function ObjectService.ClearRoom()
	for player in pairs(held) do
		release(player, Vector3.zero)
	end
	held, heldBy, active, unsettled = {}, {}, {}, {}
	runtime = nil
end

function ObjectService.Init()
	setupCollisionGroups()
	-- Every grab request gets exactly one reply carrying its request id, so the client can
	-- tell which press a hold belongs to and never keeps an object it didn't ask for.
	Remotes.Event("GrabObject").OnServerEvent:Connect(function(player, root, requestId)
		audit(player, "Dev_GrabRequests")
		local ok, reason = false, "RateLimited"
		if grabLimiter:Allow(player) then
			ok, reason = ObjectService.Grab(player, root)
		end
		if ok then
			audit(player, "Dev_GrabsGranted")
		end
		local objectId = ok and root:GetAttribute("ObjectId") or nil
		local passengers = ok and ObjectService.GetPassengerIds(player) or nil
		Remotes.Event("GrabResult"):FireClient(player, tonumber(requestId) or 0, ok, objectId, reason, passengers)
	end)
	Remotes.Event("ThrowObject").OnServerEvent:Connect(function(player, objectId, direction)
		audit(player, "Dev_ThrowRequests")
		if throwLimiter:Allow(player) then
			ObjectService.Throw(player, objectId, direction)
		end
	end)
	Remotes.Event("DropObject").OnServerEvent:Connect(function(player, objectId)
		local had = held[player] ~= nil
		ObjectService.Drop(player, objectId)
		if had and not held[player] then
			Services.AnalyticsService.Threw(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		ObjectService.Drop(player)
		grabLimiter:Clear(player)
		throwLimiter:Clear(player)
	end)
end

function ObjectService.Start()
	-- Anything loose can be knocked out of the room: sweep for it.
	task.spawn(function()
		while true do
			task.wait(2)
			if runtime then
				for _, obj in ipairs(runtime.Objects) do
					if obj.Parent and not heldBy[obj] and Services.RoomService.IsOutOfRoom(runtime, obj) then
						Services.RoomService.RecoverObject(runtime, obj)
						if not active[obj] then
							-- It drops back to the floor and is anchored once it lands.
							activate(obj, nil, "Falling")
						end
					end
				end
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not runtime then
			return
		end
		-- Leash held objects: a client can only move what it holds, and only near itself.
		for player, h in pairs(held) do
			local hrp = characterRoot(player)
			if not h.Root.Parent or not hrp or not player.Parent then
				release(player, Vector3.zero)
			elseif (h.Root.Position - hrp.Position).Magnitude > GameConfig.HoldMaxDistance then
				h.Root.CFrame = CFrame.new(hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 1.5, 0))
				h.Root.AssemblyLinearVelocity = Vector3.zero
			end
			if held[player] == h and hrp then
				for i = #h.Passengers, 1, -1 do
					local p = h.Passengers[i]
					if not p.Parent then
						table.remove(h.Passengers, i)
						heldBy[p] = nil
					elseif (p.Position - hrp.Position).Magnitude > GameConfig.HoldMaxDistance then
						p.CFrame = CFrame.new(h.Root.Position + Vector3.new(0, 1, 0))
						p.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end
		end
		local now = os.clock()
		for root, u in pairs(unsettled) do
			if not root.Parent or heldBy[root] or active[root] then
				unsettled[root] = nil
			elseif root.AssemblyLinearVelocity.Magnitude < GameConfig.SettleSpeed and root.AssemblyAngularVelocity.Magnitude < 3 then
				unsettled[root] = nil
				anchorAtRest(root)
			elseif now - u.At >= 0.5 then
				if (root.Position - u.Pos).Magnitude < 0.25 then
					-- Only jittering in place.
					unsettled[root] = nil
					anchorAtRest(root)
				else
					u.Pos, u.At = root.Position, now
				end
			end
		end
		for root, info in pairs(active) do
			if not root.Parent then
				active[root] = nil
				continue
			end
			if Services.RoomService.IsOutOfRoom(runtime, root) then
				warn(string.format("[ObjectService] %s left the room in flight at %s; recovered", root.Name, tostring(root.Position)))
				Services.RoomService.RecoverObject(runtime, root)
				if info.Owned then
					info.Owned = false
					serverOwns(root)
				end
				info.StillFor = 0
				continue
			end
			local speed = root.AssemblyLinearVelocity.Magnitude
			local t = now - info.Since
			-- For the first moments of a thrower-simulated flight the server may still be seeing
			-- the object's held state (replication lag): don't read that as an impact.
			local settling = info.Owned and t < 0.35
			if settling then
				info.LastSpeed = math.max(info.LastSpeed or 0, speed)
				continue
			end
			if info.Owned and info.LaunchVelocity and t < 0.8 and speed < 3 and (root.Position - (info.ReleasePos or root.Position)).Magnitude < 2 then
				-- The thrower's client never launched it (lag/desync): launch it from the server.
				info.Owned = false
				serverOwns(root)
				root.AssemblyLinearVelocity = info.LaunchVelocity
				info.LastSpeed = info.LaunchVelocity.Magnitude
				info.LaunchVelocity = nil
				continue
			end
			if info.Owned then
				-- The thrower simulates this flight: it must stay a plausible throw.
				local maxTravel = (info.MaxSpeed or 0) * t * 1.15 + 0.5 * workspace.Gravity * t * t + 8
				local travel = (root.Position - (info.ReleasePos or root.Position)).Magnitude
				if speed > (info.MaxSpeed or 0) * 1.25 + 8 or travel > maxTravel then
					warn(string.format("[ObjectService] Throw of %s rejected: speed %.1f (max %.1f), travel %.1f (max %.1f) at t=%.2f",
						root.Name, speed, (info.MaxSpeed or 0) * 1.25 + 8, travel, maxTravel, t))
					info.Cheated = true
					info.Owned = false
					serverOwns(root)
					root.AssemblyLinearVelocity = Vector3.zero
				elseif not info.Lift or t > GameConfig.OwnedFlightTime then
					info.Owned = false
					serverOwns(root)
				end
			end
			if info.Lift then
				-- First real impact (sudden speed loss) ends the floaty flight.
				if info.LastSpeed and speed < info.LastSpeed * 0.6 then
					clearLift(root)
					info.Lift = false
				end
				info.LastSpeed = speed
			end
			if not info.Thrown and now >= (info.CheckAt or 0) then
				-- Knocked-loose junk (a woken pile, chunk pieces) has landed once it stops going
				-- anywhere, even if it keeps jittering in place (the speed check never calls that still).
				if info.CheckPos and (root.Position - info.CheckPos).Magnitude < 0.25 then
					settle(root, info, true)
					continue
				end
				info.CheckPos, info.CheckAt = root.Position, now + 0.5
			end
			if speed < GameConfig.SettleSpeed and root.AssemblyAngularVelocity.Magnitude < 3 then
				info.StillFor += dt
			else
				info.StillFor = 0
			end
			if info.StillFor >= GameConfig.SettleTime or t > GameConfig.MaxFlightTime then
				settle(root, info)
			end
		end
	end)
end

return ObjectService
