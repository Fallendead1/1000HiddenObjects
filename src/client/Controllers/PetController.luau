--[[
	Helper pets on screen (PetService does the work):
	  Followers  every player's equipped pets (attribute PetsEquipped) follow them around, drawn
	             only on this client. Walkers hop along the ground, fliers hover.
	  Trips      in rooms pets work on their own. PetTrip: the pet walks (or flies) to a piece of
	             junk in the time the server gives; PetPickup: it has it (a small copy rides on
	             its back, or under a flier) and heads for the bin; the Deposit that follows
	             (payload.Pet) tosses it in. Then it pokes around there until its next trip, and
	             walks back to its owner when no more work comes. PetBurst: the dragon flies to a
	             packed junk just before it bursts.
	  Hatching   Hatch plays the egg (or gift) opening: the player taps it five times, it cracks
	             a little more each time, then the top pops off and the pet comes out in front
	             of a burst of light in its rarity's colour.
	  Welcome    a player who hasn't had their welcome pet yet gets a gift to open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local PetModels = require(script.Parent.Parent.UI.PetModels)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local PetController = {}

type Follower = {
	Model: Model,
	Kind: string,
	Owner: Player,
	Index: number,
	Pos: Vector3,
	Look: Vector3,
	Mode: string, -- Follow | Trip | Carry | Burst | Work (idling in the room) | Return (to its owner)
	ArriveAt: number,
	Target: Vector3?,
	To: Vector3?,
	Home: Vector3?,
	IdleSince: number,
	WanderAt: number,
	Carried: { BasePart },
	GroundY: number?,
	GroundAt: number,
	Half: number,
	Flies: boolean,
}

local folder: Folder
local followers: { [Player]: { [string]: Follower } } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local SLOTS = { Vector3.new(2.6, 0, 2.4), Vector3.new(-2.6, 0, 2.4), Vector3.new(0, 0, 3.8), Vector3.new(3.6, 0, 4.4) }
local CULL_DISTANCE = 170

-- ===== Followers =====

local function removeFollower(f: Follower)
	for _, ghost in ipairs(f.Carried) do
		ghost:Destroy()
	end
	f.Carried = {}
	f.Model:Destroy()
end

local function sync(owner: Player)
	local list = followers[owner] or {}
	followers[owner] = list
	local wanted = {}
	for kind in string.gmatch(owner:GetAttribute("PetsEquipped") or "", "[^,]+") do
		if PetConfig.Get(kind) then
			table.insert(wanted, kind)
		end
	end
	for kind, f in pairs(list) do
		if not table.find(wanted, kind) then
			removeFollower(f)
			list[kind] = nil
		end
	end
	local root = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for i, kind in ipairs(wanted) do
		local f = list[kind]
		if f then
			f.Index = i
		else
			local def = PetConfig.Get(kind)
			local model = PetModels.Build(kind)
			model.Name = owner.Name .. "_" .. kind
			local start = root and (root.Position + Vector3.new(0, 1, 3)) or Vector3.new(0, -500, 0)
			model:PivotTo(CFrame.new(start))
			model.Parent = folder
			list[kind] = {
				Model = model,
				Kind = kind,
				Owner = owner,
				Index = i,
				Pos = start,
				Look = Vector3.zAxis,
				Mode = "Follow",
				ArriveAt = 0,
				IdleSince = 0,
				WanderAt = 0,
				Carried = {},
				GroundAt = 0,
				Half = (model.PrimaryPart :: BasePart).Size.Y / 2,
				Flies = def ~= nil and def.Flies == true,
			}
		end
	end
end

local function watch(owner: Player)
	owner:GetAttributeChangedSignal("PetsEquipped"):Connect(function()
		sync(owner)
	end)
	sync(owner)
end

local function followerOf(userId: number, kind: string): Follower?
	local owner = Players:GetPlayerByUserId(userId)
	local list = owner and followers[owner]
	return list and list[kind] or nil
end

local function groundBelow(f: Follower, at: Vector3, clock: number): number?
	if clock - f.GroundAt < 0.15 and f.GroundY then
		return f.GroundY
	end
	f.GroundAt = clock
	local exclude = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), rayParams)
	f.GroundY = hit and hit.Position.Y or nil
	return f.GroundY
end

local function reduceMotion(): boolean
	return player:GetAttribute("Setting_ReduceVFX") == true
end

local function dropCarry(f: Follower, into: Vector3?)
	for _, ghost in ipairs(f.Carried) do
		local goal: { [string]: any } = { Size = ghost.Size * 0.2, Transparency = 1 }
		if into then
			goal.CFrame = CFrame.new(into)
		end
		UI.Tween(ghost, goal, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
			ghost:Destroy()
		end)
	end
	f.Carried = {}
end

-- The pet stays where it is in the room and pokes around until its next trip.
local function settleIn(f: Follower, clock: number)
	f.Mode = "Work"
	f.Home = f.Pos
	f.Target = nil
	f.IdleSince = clock
	f.WanderAt = clock + 1 + math.random() * 2
end

-- Walks (or flies) toward a point so as to get there at arriveAt; never faster than a sprint.
local function travelTo(f: Follower, target: Vector3, arriveAt: number, clock: number, dt: number, floorY: number): boolean
	local flat = Vector3.new(target.X - f.Pos.X, 0, target.Z - f.Pos.Z)
	local dist = flat.Magnitude
	local pace = f.Flies and PetConfig.FlySpeed or PetConfig.WalkSpeed
	local speed = math.clamp(dist / math.max(arriveAt - clock, 0.05), pace * 0.5, pace * 2.6)
	local stepLength = math.min(dist, speed * dt)
	local nextXZ = dist > 0.01 and (f.Pos + flat.Unit * stepLength) or f.Pos
	local y: number
	if f.Flies then
		-- Cruises over the piles and swoops down at the end.
		local cruise = floorY + 7 + math.sin(clock * 2 + f.Index) * 0.4
		y = target.Y + (cruise - target.Y) * math.clamp((dist - 1) / 7, 0, 1)
	else
		local ground = groundBelow(f, nextXZ, clock)
		y = (ground or (target.Y - f.Half)) + f.Half
	end
	local rise = 1 - math.exp(-dt * (f.Flies and 5 or 14))
	f.Pos = Vector3.new(nextXZ.X, f.Pos.Y + (y - f.Pos.Y) * rise, nextXZ.Z)
	if dist > 0.15 then
		f.Look = f.Look:Lerp(flat.Unit, 1 - math.exp(-dt * 10))
	end
	return dist <= 0.6
end

local function step(dt: number)
	local clock = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	for owner, list in pairs(followers) do
		local root = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local inRoom = owner:GetAttribute("InMatch") == true
		for _, f in pairs(list) do
			local model = f.Model
			if not root then
				model.Parent = nil
				continue
			end
			if (f.Pos - eye).Magnitude > CULL_DISTANCE and (root.Position - eye).Magnitude > CULL_DISTANCE then
				model.Parent = nil
				continue
			end
			if model.Parent ~= folder then
				model.Parent = folder
			end
			-- Out of the room (or far from a teleported owner): back to following.
			if f.Mode ~= "Follow" and (not inRoom or (f.Pos - root.Position).Magnitude > 220) then
				dropCarry(f)
				f.Mode = "Follow"
				f.Pos = root.Position + Vector3.new(0, 1, 3)
			end
			local floorY = root.Position.Y - 3
			local moving = false
			if f.Mode == "Follow" or f.Mode == "Return" then
				local slot = SLOTS[f.Index] or SLOTS[#SLOTS]
				local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				local basis = flat.Magnitude > 0.1 and CFrame.lookAt(root.Position, root.Position + flat) or root.CFrame
				local spot = (basis * CFrame.new(slot)).Position
				local target: Vector3
				if f.Flies then
					target = Vector3.new(spot.X, root.Position.Y + 1.6 + math.sin(clock * 2 + f.Index) * 0.35, spot.Z)
				else
					local ground = groundBelow(f, spot, clock) or floorY
					target = Vector3.new(spot.X, ground + f.Half, spot.Z)
				end
				local delta = target - f.Pos
				if f.Mode == "Return" then
					-- Walking back to its owner across the room.
					moving = true
					local pace = (f.Flies and PetConfig.FlySpeed or PetConfig.WalkSpeed) * 1.4
					if travelTo(f, target, clock + delta.Magnitude / pace, clock, dt, floorY) or delta.Magnitude < 3 then
						f.Mode = "Follow"
					end
				else
					if delta.Magnitude > 45 then
						f.Pos = target
					else
						f.Pos = f.Pos:Lerp(target, 1 - math.exp(-dt * 8))
					end
					moving = delta.Magnitude > 0.6
					local flatDelta = Vector3.new(delta.X, 0, delta.Z)
					if moving and flatDelta.Magnitude > 0.3 then
						f.Look = f.Look:Lerp(flatDelta.Unit, 1 - math.exp(-dt * 10))
					else
						local ownerLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
						if ownerLook.Magnitude > 0.1 then
							f.Look = f.Look:Lerp(ownerLook.Unit, 1 - math.exp(-dt * 4))
						end
					end
				end
			elseif f.Mode == "Trip" or f.Mode == "Carry" or f.Mode == "Burst" then
				local target = f.Target or f.Pos
				local arrived = travelTo(f, target, f.ArriveAt, clock, dt, floorY)
				moving = not arrived
				if clock > f.ArriveAt + (f.Mode == "Carry" and 4 or 2.5) then
					-- The pick-up or the pay never came (the room ended, someone else took it).
					dropCarry(f)
					settleIn(f, clock)
				end
			elseif f.Mode == "Work" then
				-- Pokes around near where it finished; heads back to its owner when no work comes.
				if clock - f.IdleSince > 14 then
					f.Mode = "Return"
				elseif f.Target then
					moving = not travelTo(f, f.Target, clock + 1.2, clock, dt, floorY)
					if not moving then
						f.Target = nil
						f.WanderAt = clock + 1.5 + math.random() * 2.5
					end
				elseif clock >= f.WanderAt and f.Home then
					local angle = math.random() * math.pi * 2
					local reach = 1.5 + math.random() * 2.5
					f.Target = f.Home + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
				elseif f.Flies then
					f.Pos = Vector3.new(f.Pos.X, f.Pos.Y + ((floorY + 5.5 + math.sin(clock * 2 + f.Index) * 0.4) - f.Pos.Y) * (1 - math.exp(-dt * 3)), f.Pos.Z)
				end
			end
			-- Placeholder motion when the art has no animations: walkers hop, everyone breathes.
			local carrying = #f.Carried > 0
			local animated = PetModels.Play(model, carrying and "Carry" or (moving and "Walk" or "Idle"))
			local bob = 0
			if not animated then
				bob = (moving and not f.Flies) and math.abs(math.sin(clock * 12)) * 0.35 or math.sin(clock * 3) * 0.06
			end
			local look = f.Look.Magnitude > 0.01 and f.Look.Unit or Vector3.zAxis
			-- Models face -Z, which lookAt points along the direction of travel.
			model:PivotTo(CFrame.lookAt(f.Pos, f.Pos + look) * CFrame.new(0, bob, 0))
			PetModels.Animate(model, clock, moving, f.Flies, carrying)
			-- Walkers carry it on their back, fliers hold it underneath.
			for i, ghost in ipairs(f.Carried) do
				local lift = f.Flies and -(f.Half + ghost.Size.Y / 2 + 0.1) or (f.Half + ghost.Size.Y / 2 + 0.05)
				local stack = (i - 1) * (f.Flies and -0.7 or 0.7)
				ghost.CFrame = CFrame.lookAt(f.Pos, f.Pos + look) * CFrame.new(0, lift + stack + bob, 0)
			end
		end
	end
end

-- ===== Trips =====

-- The pet sets off for a piece of junk (T1 seconds away), then carries it to the bin (T2).
local function onTrip(payload)
	local f = followerOf(payload.Owner or 0, payload.Kind or "")
	if not f or typeof(payload.From) ~= "Vector3" then
		return
	end
	local clock = os.clock()
	dropCarry(f)
	f.Mode = "Trip"
	f.Target = payload.From + Vector3.new(0, f.Half + 0.3, 0)
	f.ArriveAt = clock + (tonumber(payload.T1) or 1)
	f.To = typeof(payload.To) == "Vector3" and payload.To or nil
end

-- It has the junk: a small copy rides along to the bin.
local function onPickup(payload)
	local f = followerOf(payload.Owner or 0, payload.Kind or "")
	if not f then
		return
	end
	local clock = os.clock()
	if not reduceMotion() then
		local size = typeof(payload.Size) == "Vector3" and payload.Size or Vector3.one
		local scale = math.min(1, 1.4 / math.max(size.X, size.Y, size.Z))
		local ghost = Instance.new("Part")
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.CastShadow = false
		ghost.Size = size * scale
		ghost.Color = typeof(payload.Color) == "Color3" and payload.Color or Color3.new(1, 1, 1)
		ghost.Material = Enum.Material.SmoothPlastic
		ghost.CFrame = CFrame.new(f.Pos)
		ghost.Parent = folder
		table.insert(f.Carried, ghost)
	end
	if f.Mode ~= "Carry" then
		f.Mode = "Carry"
		local bin = f.To or f.Pos
		if f.Flies then
			f.Target = bin + Vector3.new(0, 4.5, 0)
		else
			-- Walkers stop in front of the bin and toss it in.
			local away = Vector3.new(f.Pos.X - bin.X, 0, f.Pos.Z - bin.Z)
			local stand = away.Magnitude > 0.5 and away.Unit * 4.2 or Vector3.new(0, 0, 4.2)
			f.Target = Vector3.new(bin.X + stand.X, f.Pos.Y, bin.Z + stand.Z)
		end
		f.ArriveAt = clock + PetConfig.PickupSeconds + (tonumber(payload.T2) or 1)
	end
end

-- It reached the bin: the junk goes in and the pet stays around there.
local function onPetDeposit(payload)
	local f = followerOf(payload.Owner or 0, payload.Pet or "")
	if not f then
		return
	end
	local ghost = table.remove(f.Carried, 1)
	if ghost then
		local keep = f.Carried
		f.Carried = { ghost }
		dropCarry(f, typeof(payload.BinPosition) == "Vector3" and payload.BinPosition or nil)
		f.Carried = keep
	end
	if #f.Carried == 0 and f.Mode == "Carry" then
		settleIn(f, os.clock())
	end
end

local function onIdle(payload)
	local f = followerOf(payload.Owner or 0, payload.Kind or "")
	if f and f.Mode == "Trip" then
		settleIn(f, os.clock())
	end
end

local function onBurst(payload)
	local f = followerOf(payload.Owner or 0, payload.Kind or "")
	if f and typeof(payload.Position) == "Vector3" then
		dropCarry(f)
		f.Mode = "Burst"
		f.Target = payload.Position + Vector3.new(0, 2, 0)
		f.ArriveAt = os.clock() + (tonumber(payload.T) or 0.6)
	end
end

-- ===== Hatching =====

local hatchQueue = {}
local hatching = false

local function rarityOf(kind: string)
	local def = PetConfig.Get(kind)
	return def and PetConfig.Rarities[def.Rarity] or PetConfig.Rarities.Common
end

local TAPS_TO_HATCH = 5
local AUTO_TAP_SECONDS = 3.5 -- nobody gets stuck: the egg gets a tap by itself after this long

-- A burst of light rays behind the pet, in its rarity's colour (every colour for the rarest).
local function sunburst(parent: Instance, color: Color3, rainbow: boolean): Frame
	local holder = UI.Frame({ Name = "Sunburst", BackgroundTransparency = 1, Size = UDim2.fromOffset(760, 760), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 101 }, parent)
	local count = 20
	for i = 1, count do
		local ray = UI.Frame({ BackgroundColor3 = rainbow and Color3.fromHSV((i - 1) / count, 0.75, 1) or color, Size = UDim2.new(0, 30, 0.5, 0), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Rotation = (i - 1) * 360 / count, ZIndex = 101 }, holder)
		UI.New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 0.2) }) }, ray)
	end
	return holder
end

-- Bits of shell fly off with every tap.
local function shards(parent: Instance, color: Color3, count: number)
	for _ = 1, count do
		local size = math.random(8, 16)
		local bit = UI.Frame({ BackgroundColor3 = color, Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = math.random(0, 90), ZIndex = 103 }, parent)
		UI.New("UICorner", { CornerRadius = UDim.new(0, 3) }, bit)
		local angle = math.random() * math.pi * 2
		local reach = math.random(140, 260)
		local goal = UDim2.new(0.5, math.cos(angle) * reach, 0.5, math.sin(angle) * reach + 90)
		UI.Tween(bit, { Position = goal, Rotation = bit.Rotation + math.random(-260, 260), BackgroundTransparency = 1 }, 0.55 + math.random() * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Once(function()
			bit:Destroy()
		end)
	end
end

--[[
	The player cracks the egg open: five taps (a click, a touch, Space / E or the A button), each
	one a harder shake, a new crack and bits of shell; then the top pops off in a flash and the
	pet comes out in front of a burst of light in its rarity's colour. Egg models name their
	moving pieces ShellTop / ShellBottom and number their cracks with a Crack attribute (1-4).
]]
local function playHatch(payload)
	local def = PetConfig.Get(payload.Kind or "")
	if not def then
		return
	end
	local rarity = rarityOf(def.Key)
	local eggDef = PetConfig.Eggs[payload.Egg or ""]
	local isEgg = eggDef ~= nil
	local overlay = UI.New("TextButton", { Name = "Hatch", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100 }, UI.Layers.Top) :: TextButton
	UI.Tween(overlay, { BackgroundTransparency = 0.25 }, 0.25)
	local tapped = false
	overlay.Activated:Connect(function()
		tapped = true
	end)
	local keys = UserInputService.InputBegan:Connect(function(input)
		local k = input.KeyCode
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.E or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonX then
			tapped = true
		end
	end)
	local wash = UI.Frame({ Name = "RarityWash", BackgroundColor3 = rarity.Color, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100 }, overlay)
	UI.New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.45, 0.1), NumberSequenceKeypoint.new(1, 0.9) }) }, wash)
	local stage = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(360, 360), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), ZIndex = 101 }, overlay)
	local top = UI.Label({ Text = isEgg and "TAP THE EGG!" or "TAP TO OPEN!", TextSize = 40, TextWrapped = false, Size = UDim2.new(1, 0, 0, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 0), ZIndex = 103 }, overlay)
	UI.Stroke(top, Color3.new(0, 0, 0), 4, 0)
	UI.TextGradient(top, UI.Colors.Gold)
	UI.Pulse(top, 0.05, 3)
	local hint = UI.Label({ Text = "", TextSize = 16, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, 318), ZIndex = 103 }, overlay)
	-- Five pips fill up as the shell gives way.
	local pips = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(TAPS_TO_HATCH * 34, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, 200), ZIndex = 103 }, overlay)
	UI.ListLayout(pips, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	local pipList = {}
	for i = 1, TAPS_TO_HATCH do
		local pip = UI.Frame({ BackgroundColor3 = Color3.fromRGB(60, 64, 84), Size = UDim2.fromOffset(26, 26), LayoutOrder = i, ZIndex = 103 }, pips)
		UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, pip)
		UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, pip)
		pipList[i] = pip
	end

	local eggModel = PetModels.BuildEgg(payload.Egg or "Gift")
	local vp = PetModels.Viewport(stage, eggModel, { ZIndex = 102 })
	local shellTop = eggModel:FindFirstChild("ShellTop") :: BasePart?
	local cracks: { [number]: BasePart } = {}
	for _, d in ipairs(eggModel:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Crack") then
			cracks[d:GetAttribute("Crack")] = d
		end
	end
	local shellColor = eggDef and eggDef.Color or Color3.fromRGB(255, 120, 170)
	Controllers.AudioController.Play("ChunkBurst")

	local t0 = os.clock()
	local function pose(shake: number)
		local t = os.clock() - t0
		eggModel:PivotTo(CFrame.Angles(0, math.rad(-25) + math.sin(t * 0.9) * 0.25, math.sin(t * 2.2) * 0.04 + math.sin(t * 46) * shake))
	end
	local taps = 0
	local lastTap = os.clock()
	while taps < TAPS_TO_HATCH do
		pose(0)
		RunService.RenderStepped:Wait()
		if tapped or os.clock() - lastTap > AUTO_TAP_SECONDS then
			tapped = false
			taps += 1
			lastTap = os.clock()
			local crack = cracks[math.min(taps, 4)]
			if crack then
				crack.Transparency = 0
			end
			pipList[taps].BackgroundColor3 = UI.Colors.Gold
			UI.PopIn(pipList[taps], 0.4, 0.25)
			Controllers.AudioController.Play("EggTap", 0.85 + taps * 0.13)
			shards(stage, shellColor, 3 + taps * 2)
			top.Text = taps < TAPS_TO_HATCH and ({ "IT MOVED!", "IT'S CRACKING!", "KEEP GOING!", "ALMOST THERE!" })[taps] or "HERE IT COMES!"
			-- The whole stage jolts with the egg, and always ends back at its centre.
			local punchEnd = os.clock() + 0.3 + taps * 0.04
			local jolt = 4 + taps * 3
			while os.clock() < punchEnd do
				pose(0.035 + taps * 0.03)
				stage.Position = UDim2.new(0.5, math.random(-jolt, jolt), 0.42, math.random(-jolt, jolt))
				RunService.RenderStepped:Wait()
			end
			stage.Position = UDim2.fromScale(0.5, 0.42)
		end
	end
	-- The last shake, then the top pops off.
	local burstEnd = os.clock() + 0.45
	while os.clock() < burstEnd do
		pose(0.22)
		stage.Position = UDim2.new(0.5, math.random(-16, 16), 0.42, math.random(-16, 16))
		RunService.RenderStepped:Wait()
	end
	stage.Position = UDim2.fromScale(0.5, 0.42)
	Controllers.AudioController.Play("EggBreak")
	shards(stage, shellColor, 18)
	if shellTop then
		for _, c in pairs(cracks) do
			c.Transparency = 1
		end
		local from = shellTop.CFrame
		local popEnd = os.clock() + 0.32
		while os.clock() < popEnd do
			local u = 1 - (popEnd - os.clock()) / 0.32
			shellTop.CFrame = from * CFrame.new(0, u * 3.2, u * -0.8) * CFrame.Angles(u * 1.6, 0, u * 0.9)
			RunService.RenderStepped:Wait()
		end
	end
	tapped = false
	local skip = false
	-- The reveal.
	Controllers.FXController.ScreenFlash(Color3.new(1, 1, 1), 0.5)
	Controllers.AudioController.Play(rarity.Order >= 4 and "LevelUp" or "CashAward")
	vp:Destroy()
	pips:Destroy()
	UI.Tween(wash, { BackgroundTransparency = 0.35 }, 0.4)
	local rays = sunburst(stage, rarity.Color, rarity.Order >= 4)
	local petModel = PetModels.Build(def.Key)
	PetModels.Viewport(stage, petModel, { ZIndex = 102 }, true)
	PetModels.Play(petModel, "Celebrate")
	UI.PopIn(stage, 0.5, 0.35)
	top.Text = payload.New and "NEW PET!" or string.format("LEVEL UP!  LV %d", payload.Level or 1)
	UI.TextGradient(top, payload.New and UI.Colors.Gold or UI.Colors.Cyan)
	local name = UI.Label({ Text = string.upper(def.Name), TextSize = 36, TextWrapped = false, Size = UDim2.new(1, 0, 0, 44), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, 190), ZIndex = 103 }, overlay)
	UI.Stroke(name, Color3.new(0, 0, 0), 3.5, 0)
	UI.TextGradient(name, rarity.Color)
	local chip = UI.Surface3D({ Size = UDim2.fromOffset(150, 28), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, 236), ZIndex = 103 }, overlay, rarity.Color, 14, 0.12)
	UI.Label({ Text = rarity.Name, TextSize = 15, TextWrapped = false, Size = UDim2.fromScale(1, 0.9), ZIndex = 104 }, chip)
	UI.Label({ Text = payload.New and def.Blurb or "A duplicate makes your pet faster.", TextSize = 16, Font = UI.FontBody, TextWrapped = true, Size = UDim2.fromOffset(460, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, 270), ZIndex = 103 }, overlay)
	hint.Text = "TAP TO CONTINUE"
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Controllers.FXController.Confetti(root.Position)
	end
	local opened = os.clock()
	local close = opened + 6
	local spin = 0
	while os.clock() < close and not skip do
		spin += RunService.RenderStepped:Wait() * (rarity.Order >= 4 and 45 or 28)
		rays.Rotation = spin
		-- A tap closes it, once the pet has had its moment.
		if tapped and os.clock() - opened > 0.8 then
			skip = true
		end
		tapped = false
	end
	keys:Disconnect()
	UI.Tween(overlay, { BackgroundTransparency = 1 }, 0.25)
	for _, d in ipairs(overlay:GetDescendants()) do
		if d:IsA("TextLabel") then
			UI.Tween(d, { TextTransparency = 1 }, 0.2)
		elseif d:IsA("ImageLabel") then
			UI.Tween(d, { ImageTransparency = 1 }, 0.2)
		elseif d:IsA("ViewportFrame") then
			UI.Tween(d, { ImageTransparency = 1 }, 0.2)
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
			UI.Tween(d, { BackgroundTransparency = 1 }, 0.2)
		end
	end
	task.wait(0.3)
	overlay:Destroy()
end

function PetController.IsHatching(): boolean
	return hatching
end

local function queueHatch(payload)
	table.insert(hatchQueue, payload)
	if hatching then
		return
	end
	hatching = true
	task.spawn(function()
		while #hatchQueue > 0 do
			local ok, err = pcall(playHatch, table.remove(hatchQueue, 1))
			if not ok then
				warn("[PetController] hatch:", err)
			end
		end
		hatching = false
	end)
end

-- ===== Welcome gift =====

local welcomeMenu

local function buildWelcome()
	welcomeMenu = UI.Menu("Welcome", "WELCOME GIFT!", UDim2.fromOffset(460, 400), UI.Colors.Pink)
	local stage = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 200), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0) }, welcomeMenu.Content)
	PetModels.Viewport(stage, PetModels.BuildEgg("Welcome"), nil, true)
	UI.Label({ Text = "A helper pet is waiting for you! It follows you and cleans with you.", TextSize = 16, Font = UI.FontBody, Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 204) }, welcomeMenu.Content)
	local open = UI.Button({ Name = "OpenWelcome", Text = "OPEN IT!", Color = UI.Colors.Green, Size = UDim2.fromOffset(240, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 254), TextSize = 26, Shine = 2 }, welcomeMenu.Content)
	welcomeMenu.Primary = open
	open.Activated:Connect(function()
		Remotes.Event("PetWelcome"):FireServer()
		welcomeMenu.Close()
	end)
end

function PetController.OfferWelcome(): boolean
	if player:GetAttribute("PetWelcomed") ~= false or player:GetAttribute("InMatch") then
		return false
	end
	if not welcomeMenu then
		buildWelcome()
	end
	welcomeMenu.Open()
	return true
end

-- ===== Lifecycle =====

function PetController.Init()
	folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = workspace

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if type(payload) ~= "table" then
			return
		end
		if name == "PetTrip" then
			onTrip(payload)
		elseif name == "PetPickup" then
			onPickup(payload)
		elseif name == "PetIdle" then
			onIdle(payload)
		elseif name == "Deposit" and payload.Pet then
			onPetDeposit(payload)
		elseif name == "PetBurst" then
			onBurst(payload)
		elseif name == "Hatch" then
			queueHatch(payload)
		end
	end)
end

function PetController.Start()
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		for _, f in pairs(followers[p] or {}) do
			removeFollower(f)
		end
		followers[p] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function()
			task.defer(sync, p)
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			task.defer(sync, p)
		end)
	end)
	RunService.RenderStepped:Connect(step)

	-- The welcome pet: offered in the lobby once the player has finished their first room (never
	-- before it: a brand-new player goes straight to PLAY NOW), and never on a room server.
	local function tryWelcome()
		local info = ReplicatedStorage:FindFirstChild("ServerInfo")
		if info and info:GetAttribute("Role") == "Match" then
			return
		end
		if player:GetAttribute("PetWelcomed") == false and player:GetAttribute("TutorialCompleted") == true and not player:GetAttribute("InMatch") and not UI.GetOpenMenu() then
			PetController.OfferWelcome()
		end
	end
	player:GetAttributeChangedSignal("TutorialCompleted"):Connect(function()
		task.delay(2, tryWelcome)
	end)
	task.delay(1.5, tryWelcome)
	player:GetAttributeChangedSignal("PetWelcomed"):Connect(function()
		task.delay(0.5, tryWelcome)
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		task.delay(2, tryWelcome)
	end)
end

return PetController
