--[[
	Server authority for every individual clutter object.

	States (attribute "State"):
	  Resting -> Held (no collision; the holder owns its physics while an AlignPosition keeps it
	  in front of them; server leashes it) -> Flying (thrown) -> Resting once it has been still
	  for SettleTime. It stays wherever physics leaves it.

	Smooth throws: the holder already simulates the object, so on release they keep simulating
	it (no ownership hand-off hitch). The server checks the flight against the allowed throw
	speed and takes it back after the first impact or OwnedFlightTime.

	Nothing is ever anchored: every object is a real, server-owned physics body that sleeps when
	still. Players walk on the mess and kick it around; thrown objects pass through players until
	they land. Pulling something out of a pile lets whatever was on it fall.

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

local Services = require(script.Parent)

local ObjectService = {}

type Held = { Root: BasePart, Attachment: Attachment, AlignPos: AlignPosition, AlignOri: AlignOrientation }
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
}

local runtime = nil
local held: { [Player]: Held } = {}
local heldBy: { [BasePart]: Player } = {}
local active: { [BasePart]: Flight } = {}
local grabLimiter = RateLimiter.new(GameConfig.GrabRateLimit, GameConfig.GrabRateLimit)
-- Throws get their own, looser budget so a legitimate release is never swallowed.
local throwLimiter = RateLimiter.new(GameConfig.GrabRateLimit * 2, GameConfig.GrabRateLimit * 2)
local rng = Random.new()

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
	for _, name in ipairs({ "Players", "Clutter", "ClutterHeavy", "ClutterFlying" }) do
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

local function settle(root: BasePart, info: Flight)
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
	root.Anchored = false
	root.CanCollide = true
	if not keepOwner then
		serverOwns(root)
	end
	active[root] = { Since = os.clock(), StillFor = 0, By = by }
	setState(root, state)
end

local function release(player: Player, velocity: Vector3)
	local h = held[player]
	if not h then
		return
	end
	held[player] = nil
	local root = h.Root
	heldBy[root] = nil
	h.AlignPos:Destroy()
	h.AlignOri:Destroy()
	h.Attachment:Destroy()
	root:SetAttribute("HeldByUserId", 0)
	if player.Parent then
		player:SetAttribute("HeldObjectId", "")
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
	else
		root.AssemblyLinearVelocity = velocity
	end
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
	if weight > Services.PlayerSessionService.GetMaxWeight(player) then
		Remotes.Event("FXEvent"):FireClient(player, "TooHeavy", { Name = root:GetAttribute("DisplayName"), Weight = weight, RequiredLevel = UpgradeConfig.StrengthLevelFor(weight) })
		return false, "TooHeavy"
	end
	if closestPointDistance(root, hrp.Position) > GameConfig.GrabDistance + GameConfig.GrabLeniency then
		return false, "TooFar"
	end
	if not hasLineOfSight(hrp.Position + Vector3.new(0, 1.5, 0), root) then
		return false, "Blocked"
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
	held[player] = { Root = root, Attachment = attachment, AlignPos = alignPos, AlignOri = alignOri }
	root:SetAttribute("HeldByUserId", player.UserId)
	root:SetAttribute("LastHolderUserId", player.UserId)
	setState(root, "Held")
	player:SetAttribute("HeldObjectId", root:GetAttribute("ObjectId"))
	-- Lifting the last thing off the key reveals it right away.
	Services.MatchService.OnObjectGrabbed(root)
	return true, nil
end

-- The launch velocity for a throw (the client predicts the same numbers for its arc preview).
function ObjectService.ThrowVelocity(player: Player, weight: number, direction: Vector3): Vector3
	local speed = Services.PlayerSessionService.GetThrowSpeed(player) * math.clamp(1.3 - weight * GameConfig.ThrowWeightFalloff, 0.55, 1.2)
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

-- Stop tracking an object that is leaving the room (deposited); drops it first if held.
function ObjectService.Forget(root: BasePart)
	local holder = heldBy[root]
	if holder then
		release(holder, Vector3.zero)
	end
	active[root] = nil
end

-- Teleport an object (dev tools); it stays a physics body.
function ObjectService.Relocate(root: BasePart, cframe: CFrame)
	active[root] = nil
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	setState(root, "Resting")
end

function ObjectService.SetRoom(rt)
	ObjectService.ClearRoom()
	runtime = rt
end

function ObjectService.ClearRoom()
	for player in pairs(held) do
		release(player, Vector3.zero)
	end
	held, heldBy, active = {}, {}, {}
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
		Remotes.Event("GrabResult"):FireClient(player, tonumber(requestId) or 0, ok, objectId, reason)
	end)
	Remotes.Event("ThrowObject").OnServerEvent:Connect(function(player, objectId, direction)
		audit(player, "Dev_ThrowRequests")
		if throwLimiter:Allow(player) then
			ObjectService.Throw(player, objectId, direction)
		end
	end)
	Remotes.Event("DropObject").OnServerEvent:Connect(function(player, objectId)
		ObjectService.Drop(player, objectId)
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
		end
		local now = os.clock()
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
