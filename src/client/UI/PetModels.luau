--[[
	Pet and egg models for the client (followers, the Pet Shop, the hatch scene).

	Final art (Codex) lives in ReplicatedStorage.GameAssets:
	  Pets.<Kind>  a Model with PrimaryPart "Root" (an invisible part at the model's centre; the
	               lowest point of the model sits Root.Size.Y / 2 below it), welded or rigged
	               MeshParts, an AnimationController with an Animator, and a folder "Animations"
	               holding Animation objects named Idle, Walk, Carry, Hatch and Celebrate.
	  Eggs.<Egg>   a Model with PrimaryPart "Root" (Dusty, Shiny, Royal, Attic), plus Eggs.GiftBox for
	               pets that come as a gift (welcome pet, Starter Pack, pet passes).
	Until then each pet is a small placeholder built from shapes in its PetConfig colours.

	Moving parts without uploaded animations: a MeshPart with the STRING attribute Joint is moved
	by code (PetModels.Animate) around its own pivot (PivotOffset = the hinge, e.g. the shoulder).
	Roles: WingL / WingR (flap), LegFL / LegFR / LegBL / LegBR (walk), Tail (wag), EarL / EarR
	(flop), Head (looks around), Squash (a whole soft body that squashes and stretches, hinged at
	its bottom). Joint parts stay anchored; anything welded to them rides along. In a viewport
	they simply rest as built.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetConfig = require(ReplicatedStorage.Shared.Config.PetConfig)

local PetModels = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local C3 = Color3.fromRGB

local function assetFolder(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	return assets and assets:FindFirstChild(name)
end

local function prepare(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.Anchored = d == model.PrimaryPart or d:GetAttribute("Joint") ~= nil
		elseif d:IsA("Script") then
			d:Destroy()
		end
	end
end

-- Placeholder pieces are welded to the root and posed relative to it.
local function piece(model: Model, root: BasePart, shape: Enum.PartType, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	if shape == Enum.PartType.Ball then
		-- Balls are always round; a sphere mesh stretches to any size (ellipsoids).
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	else
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * offset
	p.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function eyes(model: Model, root: BasePart, s: number, y: number, z: number, spread: number)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Ball, Vector3.one * s * 0.22, CFrame.new(side * spread * s, y * s, z * s), BLACK)
		piece(model, root, Enum.PartType.Ball, Vector3.one * s * 0.08, CFrame.new(side * spread * s + 0.03 * s, (y + 0.05) * s, (z - 0.09) * s), WHITE)
	end
end

local Builders = {}

function Builders.Bunny(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.one * s, CFrame.new(0, 0, 0), def.Color, Enum.Material.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Block, Vector3.new(0.18, 0.62, 0.12) * s, CFrame.new(side * 0.2 * s, 0.68 * s, 0) * CFrame.Angles(0, 0, -side * 0.18), def.Color, Enum.Material.Fabric)
		piece(model, root, Enum.PartType.Block, Vector3.new(0.1, 0.44, 0.13) * s, CFrame.new(side * 0.2 * s, 0.66 * s, -0.01 * s) * CFrame.Angles(0, 0, -side * 0.18), def.Accent)
	end
	eyes(model, root, s, 0.1, -0.44, 0.17)
	piece(model, root, Enum.PartType.Ball, Vector3.one * s * 0.12, CFrame.new(0, -0.02 * s, -0.5 * s), def.Accent)
end

function Builders.Puppy(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.new(0.9, 0.85, 1.05) * s, CFrame.new(0, -0.05 * s, 0.1 * s), def.Color, Enum.Material.Fabric)
	piece(model, root, Enum.PartType.Ball, Vector3.one * 0.7 * s, CFrame.new(0, 0.3 * s, -0.42 * s), def.Color, Enum.Material.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Block, Vector3.new(0.12, 0.4, 0.22) * s, CFrame.new(side * 0.36 * s, 0.25 * s, -0.4 * s) * CFrame.Angles(0, 0, side * 0.3), def.Accent)
	end
	eyes(model, root, s, 0.38, -0.72, 0.13)
	piece(model, root, Enum.PartType.Ball, Vector3.one * 0.13 * s, CFrame.new(0, 0.25 * s, -0.78 * s), BLACK)
	piece(model, root, Enum.PartType.Cylinder, Vector3.new(0.4, 0.1, 0.1) * s, CFrame.new(0, 0.15 * s, 0.62 * s) * CFrame.Angles(0, math.rad(90), math.rad(40)), def.Accent)
end

function Builders.Slime(model, root, def, s)
	local body = piece(model, root, Enum.PartType.Ball, Vector3.new(1.1, 0.8, 1.1) * s, CFrame.new(0, -0.1 * s, 0), def.Color, Enum.Material.Glass)
	body.Transparency = 0.25
	piece(model, root, Enum.PartType.Ball, Vector3.one * 0.3 * s, CFrame.new(0.25 * s, 0.25 * s, 0.1 * s), def.Accent, Enum.Material.Glass).Transparency = 0.3
	eyes(model, root, s, 0.05, -0.46, 0.18)
end

function Builders.Bird(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.new(0.8, 0.85, 0.95) * s, CFrame.new(0, 0, 0), def.Color, Enum.Material.Fabric)
	piece(model, root, Enum.PartType.Wedge, Vector3.new(0.12, 0.18, 0.3) * s, CFrame.new(0, 0.02 * s, -0.55 * s) * CFrame.Angles(0, math.rad(180), 0), def.Accent)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Block, Vector3.new(0.5, 0.08, 0.45) * s, CFrame.new(side * 0.55 * s, 0.05 * s, 0.05 * s) * CFrame.Angles(0, 0, side * 0.35), def.Accent, Enum.Material.Fabric)
	end
	piece(model, root, Enum.PartType.Block, Vector3.new(0.3, 0.06, 0.45) * s, CFrame.new(0, 0.05 * s, 0.6 * s) * CFrame.Angles(0.3, 0, 0), def.Accent)
	eyes(model, root, s, 0.18, -0.38, 0.16)
end

function Builders.Frog(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.new(1.15, 0.75, 1) * s, CFrame.new(0, -0.1 * s, 0), def.Color, Enum.Material.SmoothPlastic)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Ball, Vector3.one * 0.36 * s, CFrame.new(side * 0.25 * s, 0.3 * s, -0.2 * s), def.Color)
		piece(model, root, Enum.PartType.Ball, Vector3.one * 0.2 * s, CFrame.new(side * 0.25 * s, 0.36 * s, -0.33 * s), BLACK)
	end
	piece(model, root, Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.05) * s, CFrame.new(0, -0.05 * s, -0.5 * s), def.Accent)
end

function Builders.Cat(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.new(0.85, 0.8, 1.05) * s, CFrame.new(0, -0.08 * s, 0.1 * s), def.Color, Enum.Material.Fabric)
	piece(model, root, Enum.PartType.Ball, Vector3.one * 0.68 * s, CFrame.new(0, 0.3 * s, -0.4 * s), def.Color, Enum.Material.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Wedge, Vector3.new(0.08, 0.28, 0.22) * s, CFrame.new(side * 0.2 * s, 0.7 * s, -0.4 * s), def.Accent)
	end
	eyes(model, root, s, 0.36, -0.7, 0.13)
	piece(model, root, Enum.PartType.Cylinder, Vector3.new(0.7, 0.09, 0.09) * s, CFrame.new(0, 0.2 * s, 0.75 * s) * CFrame.Angles(0, math.rad(90), math.rad(55)), def.Color)
	-- The vacuum nozzle.
	piece(model, root, Enum.PartType.Cylinder, Vector3.new(0.35, 0.16, 0.16) * s, CFrame.new(0, 0.12 * s, -0.8 * s) * CFrame.Angles(0, math.rad(90), 0), def.Accent, Enum.Material.Metal)
end

function Builders.Turtle(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.new(1.2, 0.6, 1.2) * s, CFrame.new(0, 0.05 * s, 0), def.Color, Enum.Material.Metal)
	piece(model, root, Enum.PartType.Cylinder, Vector3.new(0.06, 1.05, 1.05) * s, CFrame.new(0, -0.05 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), def.Accent, Enum.Material.Neon)
	piece(model, root, Enum.PartType.Ball, Vector3.one * 0.4 * s, CFrame.new(0, 0, -0.65 * s), C3(120, 190, 120))
	eyes(model, root, s, 0.05, -0.8, 0.09)
end

function Builders.Dragon(model, root, def, s)
	piece(model, root, Enum.PartType.Ball, Vector3.new(0.85, 0.85, 1.1) * s, CFrame.new(0, 0, 0.1 * s), def.Color, Enum.Material.Metal)
	piece(model, root, Enum.PartType.Ball, Vector3.one * 0.6 * s, CFrame.new(0, 0.4 * s, -0.45 * s), def.Color, Enum.Material.Metal)
	for _, side in ipairs({ -1, 1 }) do
		piece(model, root, Enum.PartType.Wedge, Vector3.new(0.06, 0.25, 0.14) * s, CFrame.new(side * 0.15 * s, 0.78 * s, -0.4 * s), def.Accent)
		piece(model, root, Enum.PartType.Block, Vector3.new(0.7, 0.06, 0.5) * s, CFrame.new(side * 0.65 * s, 0.3 * s, 0.1 * s) * CFrame.Angles(0, 0, side * 0.5), def.Accent, Enum.Material.Neon)
	end
	eyes(model, root, s, 0.46, -0.72, 0.12)
	piece(model, root, Enum.PartType.Cylinder, Vector3.new(0.8, 0.14, 0.14) * s, CFrame.new(0, -0.05 * s, 0.85 * s) * CFrame.Angles(0, math.rad(90), math.rad(-20)), def.Color, Enum.Material.Metal)
	-- The broom it rides.
	piece(model, root, Enum.PartType.Cylinder, Vector3.new(1.6, 0.08, 0.08) * s, CFrame.new(0, -0.45 * s, 0.1 * s) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 100, 50), Enum.Material.Wood)
end

local function placeholder(kind: string): Model
	local def = PetConfig.Get(kind) or PetConfig.List[1]
	local s = def.Size
	local model = Instance.new("Model")
	model.Name = kind
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Transparency = 1
	root.Size = Vector3.one * s
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	;(Builders[def.Shape] or Builders.Bunny)(model, root, def, s)
	-- A little sparkle for the rarest.
	local rarity = PetConfig.Rarities[def.Rarity]
	if rarity.Order >= 4 then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(rarity.Color)
		emitter.Rate = 3
		emitter.Lifetime = NumberRange.new(0.6, 1)
		emitter.Size = NumberSequence.new(0.35 * s, 0)
		emitter.Speed = NumberRange.new(0.5, 1)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 1
		emitter.Parent = root
	end
	return model
end

-- A fresh model of a pet (the final art when it exists), ready to be moved with PivotTo.
function PetModels.Build(kind: string): Model
	local folder = assetFolder("Pets")
	local source = folder and folder:FindFirstChild(kind)
	local model: Model
	if source and source:IsA("Model") and source.PrimaryPart then
		model = source:Clone()
	else
		model = placeholder(kind)
	end
	prepare(model)
	return model
end

-- An egg (or, for gifts that aren't eggs, a gift box).
function PetModels.BuildEgg(eggKey: string): Model
	local folder = assetFolder("Eggs")
	local source = folder and folder:FindFirstChild(PetConfig.Eggs[eggKey] and eggKey or "GiftBox")
	if source and source:IsA("Model") and source.PrimaryPart then
		local model = source:Clone()
		prepare(model)
		return model
	end
	local egg = PetConfig.Eggs[eggKey]
	local model = Instance.new("Model")
	model.Name = eggKey
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Transparency = 1
	root.Size = Vector3.new(2, 2.6, 2)
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	if egg then
		piece(model, root, Enum.PartType.Ball, Vector3.new(2, 2.6, 2), CFrame.new(), egg.Color)
		for i = 1, 6 do
			local a = i * math.pi / 3
			piece(model, root, Enum.PartType.Ball, Vector3.one * 0.45, CFrame.new(math.cos(a) * 0.85, (i % 2 == 0 and 0.4 or -0.35), math.sin(a) * 0.85), WHITE)
		end
		if eggKey == "Royal" then
			piece(model, root, Enum.PartType.Cylinder, Vector3.new(0.3, 1.1, 1.1), CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 200, 40), Enum.Material.Metal)
		end
	else
		-- A gift box.
		piece(model, root, Enum.PartType.Block, Vector3.new(2, 1.8, 2), CFrame.new(0, -0.2, 0), Color3.fromRGB(255, 60, 120))
		piece(model, root, Enum.PartType.Block, Vector3.new(2.2, 0.45, 2.2), CFrame.new(0, 0.85, 0), Color3.fromRGB(255, 90, 150))
		piece(model, root, Enum.PartType.Block, Vector3.new(0.4, 2.3, 2.25), CFrame.new(0, 0, 0), Color3.fromRGB(255, 220, 60))
		piece(model, root, Enum.PartType.Block, Vector3.new(2.25, 2.3, 0.4), CFrame.new(0, 0, 0), Color3.fromRGB(255, 220, 60))
	end
	prepare(model)
	return model
end

-- Plays one of the model's animations (Idle, Walk, Carry, Hatch, Celebrate) if the art has it.
local tracks: { [Model]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any
function PetModels.Play(model: Model, name: string, looped: boolean?): boolean
	local anims = model:FindFirstChild("Animations")
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	local animator = controller and controller:FindFirstChildWhichIsA("Animator")
	local anim = anims and anims:FindFirstChild(name)
	if not animator or not (anim and anim:IsA("Animation")) then
		return false
	end
	local cache = tracks[model] or {}
	tracks[model] = cache
	local current = cache._playing
	if current == name then
		return true
	end
	for key, track in pairs(cache) do
		if key ~= "_playing" and key ~= name then
			(track :: AnimationTrack):Stop(0.2)
		end
	end
	local track = cache[name]
	if not track then
		track = (animator :: Animator):LoadAnimation(anim)
		cache[name] = track
	end
	(track :: AnimationTrack).Looped = looped ~= false
	;(track :: AnimationTrack):Play(0.2)
	cache._playing = name :: any
	return true
end

-- ===== Moving parts (Joint attributes) =====

type JointInfo = { Part: BasePart, Role: string, Rest: CFrame, Size: Vector3, Phase: number }
local joints: { [Model]: { Scale: number, List: { JointInfo } } } = setmetatable({}, { __mode = "k" }) :: any

local LEG_PHASE = { LegFL = 0, LegBR = 0, LegFR = math.pi, LegBL = math.pi, LegL = 0, LegR = math.pi }

local function jointsOf(model: Model)
	local cache = joints[model]
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local scale = model:GetScale()
	if cache and math.abs(cache.Scale - scale) < 1e-4 then
		return cache
	end
	if cache then
		-- Rescaled (the hatch scene grows the pet): the hinges move out with it.
		local k = scale / cache.Scale
		for _, j in ipairs(cache.List) do
			j.Rest = j.Rest.Rotation + j.Rest.Position * k
			j.Size *= k
		end
		cache.Scale = scale
		return cache
	end
	local list = {}
	for i, d in ipairs(model:GetDescendants()) do
		local role = d:IsA("BasePart") and d:GetAttribute("Joint")
		if type(role) == "string" then
			table.insert(list, { Part = d, Role = role, Rest = root.CFrame:ToObjectSpace((d :: BasePart):GetPivot()), Size = (d :: BasePart).Size, Phase = i * 1.7 })
		end
	end
	cache = { Scale = scale, List = list }
	joints[model] = cache
	return cache
end

-- Poses the model's moving parts for this moment. Call after the model has been moved.
function PetModels.Animate(model: Model, clock: number, moving: boolean, flies: boolean, carrying: boolean)
	local cache = jointsOf(model)
	local root = model.PrimaryPart
	if not cache or not root or #cache.List == 0 then
		return
	end
	local base = root.CFrame
	for _, j in ipairs(cache.List) do
		local role = j.Role
		local turn = CFrame.identity
		if role == "WingL" or role == "WingR" then
			local a = 0.15 + math.sin(clock * (moving and 17 or 10)) * (flies and 0.8 or 0.12)
			turn = CFrame.Angles(0, 0, role == "WingL" and a or -a)
		elseif LEG_PHASE[role] then
			if moving and not flies then
				turn = CFrame.Angles(math.sin(clock * 14 + LEG_PHASE[role]) * 0.75, 0, 0)
			elseif flies then
				turn = CFrame.Angles(0.5 + (carrying and 0.35 or 0), 0, 0) -- tucked up (reaching down while carrying)
			end
		elseif role == "Tail" then
			turn = CFrame.Angles(0, math.sin(clock * (moving and 11 or 4) + j.Phase) * 0.45, 0)
		elseif role == "EarL" or role == "EarR" then
			local a = moving and (0.28 + math.sin(clock * 14 + j.Phase) * 0.14) or math.sin(clock * 2 + j.Phase) * 0.07
			turn = CFrame.Angles(a, 0, 0)
		elseif role == "Head" then
			if moving then
				turn = CFrame.Angles(math.sin(clock * 14) * 0.06, 0, 0)
			else
				turn = CFrame.Angles(math.sin(clock * 1.7 + j.Phase) * 0.06, math.sin(clock * 0.9 + j.Phase) * 0.3, 0)
			end
		elseif role == "Squash" then
			-- Hinged at its bottom: taller and thinner, then shorter and wider.
			local s = math.sin(clock * (moving and 12 or 3)) * (moving and 0.13 or 0.05)
			local size = Vector3.new(j.Size.X * (1 - s * 0.6), j.Size.Y * (1 + s), j.Size.Z * (1 - s * 0.6))
			j.Part.Size = size
			local hinge = base * j.Rest
			local offset = j.Part.PivotOffset
			j.Part.CFrame = hinge * CFrame.new(-offset.Position.X, -offset.Position.Y * (1 + s), -offset.Position.Z)
			continue
		end
		j.Part:PivotTo(base * CFrame.new(j.Rest.Position) * turn * j.Rest.Rotation)
	end
end

-- The model's bounding radius (for framing it in a viewport).
function PetModels.Radius(model: Model): number
	local _, size = model:GetBoundingBox()
	return size.Magnitude / 2
end

-- A ViewportFrame showing `model`, framed and slowly turning (when spin is set).
function PetModels.Viewport(parent: Instance, model: Model, props: { [string]: any }?, spin: boolean?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(200, 200, 210)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-1, -2, -1)
	for k, v in pairs(props or {}) do
		(vp :: any)[k] = v
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = vp
	vp.CurrentCamera = camera
	model:PivotTo(CFrame.new())
	model.Parent = vp
	local r = PetModels.Radius(model)
	local distance = r / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(Vector3.new(0, r * 0.35, -distance), Vector3.zero)
	if spin then
		local angle = 0
		local conn
		conn = game:GetService("RunService").RenderStepped:Connect(function(dt)
			if not vp.Parent then
				conn:Disconnect()
				return
			end
			if vp.Visible then
				angle += dt * 0.8
				model:PivotTo(CFrame.Angles(0, angle, 0))
			end
		end)
	else
		model:PivotTo(CFrame.Angles(0, math.rad(-25), 0))
	end
	vp.Parent = parent
	return vp
end

return PetModels
