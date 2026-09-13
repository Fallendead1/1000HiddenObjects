--[[
	Server authority for every individual clutter object.

	No clutter is ever anchored during play. Everything is a real, server-owned physics body that
	sleeps when still. States (attribute "State"):
	  Resting -> Held (no collision, the holder owns its physics while an AlignPosition keeps it
	  in front of them; server leashes it) -> Flying (server-owned after a throw) -> Resting
	  again once it has been still for SettleTime. It simply stays wherever physics leaves it.
	Pulling something out of a pile lets whatever was on it fall naturally.

	First time an object ends up MoveDisplacementThreshold studs from its OriginalCFrame the
	player who moved it earns its CashValue once and room progress goes up by one object.
]]

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local ObjectService = {}

type Held = { Root: BasePart, Attachment: Attachment, AlignPos: AlignPosition, AlignOri: AlignOrientation }
type Active = { Since: number, StillFor: number, By: Player?, Lift: boolean?, LastSpeed: number?, Thrown: boolean? }

local runtime = nil
local held: { [Player]: Held } = {}
local heldBy: { [BasePart]: Player } = {}
local active: { [BasePart]: Active } = {}
local grabLimiter = RateLimiter.new(GameConfig.GrabRateLimit, GameConfig.GrabRateLimit)
-- Throws get their own, looser budget so a legitimate release is never swallowed.
local throwLimiter = RateLimiter.new(GameConfig.GrabRateLimit * 2, GameConfig.GrabRateLimit * 2)
local rng = Random.new()

-- Studio/dev-only input audit: proves one press = one grab request = one throw.
local function audit(player: Player, counter: string)
	if Services.DevService.IsAuthorized(player) then
		player:SetAttribute(counter, (player:GetAttribute(counter) or 0) + 1)
	end
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Include
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local function setupCollisionGroups()
	for _, name in ipairs({ "Players", "Clutter", "ClutterHeavy" }) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	-- Light clutter never blocks or flings players; big boxes/bins do block.
	PhysicsService:CollisionGroupSetCollidable("Players", "Clutter", false)
	PhysicsService:CollisionGroupSetCollidable("Players", "ClutterHeavy", true)
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

local function award(root: BasePart, player: Player?)
	if root:GetAttribute("MovedBefore") then
		return
	end
	local original: CFrame? = root:GetAttribute("OriginalCFrame")
	if not original or (root.Position - original.Position).Magnitude < GameConfig.MoveDisplacementThreshold then
		return
	end
	root:SetAttribute("MovedBefore", true)
	runtime.MovedCount += 1
	local weight = root:GetAttribute("Weight") or 1
	if player and player.Parent and Services.MatchService.IsPlayerInMatch(player) then
		local cash = math.floor((root:GetAttribute("CashValue") or 1) * Services.PlayerSessionService.GetCashMultiplier(player) + 0.5)
		Services.EconomyService.AddCash(player, cash)
		player:SetAttribute("ObjectsMoved", (player:GetAttribute("ObjectsMoved") or 0) + 1)
		player:SetAttribute("WeightedMoveValue", (player:GetAttribute("WeightedMoveValue") or 0) + weight)
		Remotes.Event("FXEvent"):FireClient(player, "CashAward", { Amount = cash, Position = root.Position, Name = root:GetAttribute("DisplayName") })
	end
	Services.MatchService.OnObjectFirstMoved(root, player)
end

local function settle(root: BasePart, info: Active)
	active[root] = nil
	if not root.Parent then
		return
	end
	clearLift(root)
	setState(root, "Resting")
	award(root, info.By)
	if info.Thrown then
		local match = Services.MatchService.GetMatch()
		for _, p in ipairs(match and match.Players or {}) do
			Remotes.Event("FXEvent"):FireClient(p, "Land", { Position = root.Position })
		end
	end
	Services.MatchService.OnObjectSettled(root)
end

local function makeActive(root: BasePart, by: Player?, state: string)
	root.Anchored = false
	root.CanCollide = true
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
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
	makeActive(root, player, "Flying")
	root.AssemblyLinearVelocity = velocity
	active[root].Thrown = true
	if velocity.Magnitude > 1 then
		root.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-5, 5), rng:NextNumber(-5, 5))
		addLift(root)
		active[root].Lift = true
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
	setState(root, "Held")
	player:SetAttribute("HeldObjectId", root:GetAttribute("ObjectId"))
	-- Lifting the last thing off the key reveals it right away.
	Services.MatchService.OnObjectGrabbed(root)
	return true, nil
end

-- Only the exact object the client says it is holding can be thrown.
function ObjectService.Throw(player: Player, objectId: any, direction: any)
	local h = held[player]
	if not h or typeof(objectId) ~= "string" or h.Root:GetAttribute("ObjectId") ~= objectId then
		return
	end
	local dir = Vector3.zero
	if typeof(direction) == "Vector3" and direction.Magnitude > 0.1 and direction.Magnitude < 1e4 and direction.X == direction.X then
		dir = direction.Unit
	end
	local weight = h.Root:GetAttribute("Weight") or 1
	local speed = Services.PlayerSessionService.GetThrowSpeed(player) * math.clamp(1.3 - weight * GameConfig.ThrowWeightFalloff, 0.55, 1.2)
	local velocity = dir.Magnitude > 0 and (dir + Vector3.new(0, GameConfig.ThrowUpwardBias, 0)).Unit * speed or Vector3.zero
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

function ObjectService.IsBusy(root: BasePart): boolean
	return heldBy[root] ~= nil or active[root] ~= nil
end

-- Teleport an object (resume/dev tools); it stays a physics body. Counts as moved, no Cash.
function ObjectService.Relocate(root: BasePart, cframe: CFrame)
	active[root] = nil
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	setState(root, "Resting")
	if not root:GetAttribute("MovedBefore") then
		root:SetAttribute("MovedBefore", true)
		runtime.MovedCount += 1
	end
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
	-- Everything is loose physics, so anything can be knocked out of the room: sweep for it.
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
				Services.RoomService.RecoverObject(runtime, root)
				info.StillFor = 0
				continue
			end
			local speed = root.AssemblyLinearVelocity.Magnitude
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
			if info.StillFor >= GameConfig.SettleTime or now - info.Since > GameConfig.MaxFlightTime then
				settle(root, info)
			end
		end
	end)
end

return ObjectService
