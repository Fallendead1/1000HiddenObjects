--[[
	Helper pets on screen (PetService does the work):
	  Followers  every player's equipped pets (attribute PetsEquipped) follow them around, drawn
	             only on this client. Walkers hop along the ground, fliers hover.
	  Trips      PetTrip sends the owner's pet to the junk; the Deposit that follows (payload.Pet)
	             has it carry the junk into the bin, then it comes back. PetBurst: the dragon
	             swoops at a packed junk just before it bursts.
	  Hatching   Hatch plays the egg (or gift) opening: shakes, a flash, then the pet with its
	             rarity. Tap to skip.
	  Welcome    a player who hasn't had their welcome pet yet gets a gift to open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	Mode: string, -- Follow | Trip | Carry | Burst
	ModeUntil: number,
	Target: Vector3?,
	To: Vector3?,
	Carry: BasePart?,
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
	if f.Carry then
		f.Carry:Destroy()
		f.Carry = nil
	end
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
				ModeUntil = 0,
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

local function step(dt: number)
	local clock = os.clock()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	for owner, list in pairs(followers) do
		local root = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for _, f in pairs(list) do
			local model = f.Model
			if not root then
				model.Parent = nil
				continue
			end
			if (root.Position - eye).Magnitude > CULL_DISTANCE then
				model.Parent = nil
				continue
			end
			if model.Parent ~= folder then
				model.Parent = folder
			end
			if f.Mode ~= "Follow" and clock >= f.ModeUntil then
				if f.Carry then
					local ghost = f.Carry
					f.Carry = nil
					UI.Tween(ghost, { Size = ghost.Size * 0.2, Transparency = 1 }, 0.2).Completed:Once(function()
						ghost:Destroy()
					end)
				end
				f.Mode = "Follow"
			end
			local target: Vector3
			local rate = 8
			if f.Mode == "Follow" then
				local slot = SLOTS[f.Index] or SLOTS[#SLOTS]
				local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				local basis = flat.Magnitude > 0.1 and CFrame.lookAt(root.Position, root.Position + flat) or root.CFrame
				local spot = (basis * CFrame.new(slot)).Position
				if f.Flies then
					target = Vector3.new(spot.X, root.Position.Y + 1.6 + math.sin(clock * 2 + f.Index) * 0.35, spot.Z)
				else
					local ground = groundBelow(f, spot, clock) or (root.Position.Y - 3)
					target = Vector3.new(spot.X, ground + f.Half, spot.Z)
				end
			else
				target = (f.Mode == "Carry" and f.To or f.Target) or f.Pos
				rate = 10
			end
			local delta = target - f.Pos
			if delta.Magnitude > 45 then
				f.Pos = target
			else
				f.Pos = f.Pos:Lerp(target, 1 - math.exp(-dt * rate))
			end
			local moving = delta.Magnitude > 0.6
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if moving and flat.Magnitude > 0.3 then
				f.Look = f.Look:Lerp(flat.Unit, 1 - math.exp(-dt * 10))
			elseif f.Mode == "Follow" then
				local ownerLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				if ownerLook.Magnitude > 0.1 then
					f.Look = f.Look:Lerp(ownerLook.Unit, 1 - math.exp(-dt * 4))
				end
			end
			-- Placeholder motion when the art has no animations: walkers hop, everyone breathes.
			local animated = PetModels.Play(model, f.Mode == "Carry" and "Carry" or (moving and "Walk" or "Idle"))
			local bob = 0
			if not animated then
				bob = (moving and not f.Flies) and math.abs(math.sin(clock * 12)) * 0.35 or math.sin(clock * 3) * 0.06
			end
			local look = f.Look.Magnitude > 0.01 and f.Look.Unit or Vector3.zAxis
			-- Models face -Z, which lookAt points along the direction of travel.
			model:PivotTo(CFrame.lookAt(f.Pos, f.Pos + look) * CFrame.new(0, bob, 0))
			if f.Carry then
				f.Carry.CFrame = CFrame.new(f.Pos - Vector3.new(0, f.Half + f.Carry.Size.Y / 2 + 0.1, 0))
			end
		end
	end
end

-- ===== Trips =====

local function reduceMotion(): boolean
	return player:GetAttribute("Setting_ReduceVFX") == true
end

local function onTrip(payload)
	local f = followerOf(payload.Owner or 0, payload.Kind or "")
	if not f or typeof(payload.From) ~= "Vector3" then
		return
	end
	f.Mode = "Trip"
	f.Target = payload.From + Vector3.new(0, f.Half + 0.8 + (payload.Index or 1) * 0.3, 0)
	f.To = typeof(payload.To) == "Vector3" and payload.To + Vector3.new(0, 4, 0) or nil
	f.ModeUntil = os.clock() + 2.2
end

local function onPetDeposit(payload)
	local f = followerOf(payload.Owner or 0, payload.Pet or "")
	if not f or reduceMotion() then
		return
	end
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
	if f.Carry then
		f.Carry:Destroy()
	end
	f.Carry = ghost
	f.Mode = "Carry"
	f.To = typeof(payload.BinPosition) == "Vector3" and payload.BinPosition + Vector3.new(0, 3.5, 0) or f.To
	f.ModeUntil = os.clock() + 1.1
end

local function onBurst(payload)
	local f = followerOf(payload.Owner or 0, payload.Kind or "")
	if f and typeof(payload.Position) == "Vector3" then
		f.Mode = "Burst"
		f.Target = payload.Position + Vector3.new(0, 2, 0)
		f.ModeUntil = os.clock() + 1
	end
end

-- ===== Hatching =====

local hatchQueue = {}
local hatching = false

local function rarityOf(kind: string)
	local def = PetConfig.Get(kind)
	return def and PetConfig.Rarities[def.Rarity] or PetConfig.Rarities.Common
end

local function playHatch(payload)
	local def = PetConfig.Get(payload.Kind or "")
	if not def then
		return
	end
	local rarity = rarityOf(def.Key)
	local isEgg = PetConfig.Eggs[payload.Egg or ""] ~= nil
	local overlay = UI.New("TextButton", { Name = "Hatch", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100 }, UI.Layers.Top) :: TextButton
	UI.Tween(overlay, { BackgroundTransparency = 0.25 }, 0.25)
	local skip = false
	overlay.Activated:Connect(function()
		skip = true
	end)
	local stage = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(360, 360), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), ZIndex = 101 }, overlay)
	local rays = UI.Image({ Image = UI.Asset("Rays") or "", Size = UDim2.fromOffset(520, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ImageColor3 = rarity.Color, ImageTransparency = 1, ZIndex = 101 }, stage)
	local top = UI.Label({ Text = isEgg and "HATCHING..." or "OPENING...", TextSize = 40, TextWrapped = false, Size = UDim2.new(1, 0, 0, 50), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.08, 0), ZIndex = 103 }, overlay)
	UI.Stroke(top, Color3.new(0, 0, 0), 4, 0)
	UI.TextGradient(top, UI.Colors.Gold)
	local hint = UI.Label({ Text = "TAP TO SKIP", TextSize = 16, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, 0, 0, 20), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, 318), ZIndex = 103 }, overlay)

	local eggModel = PetModels.BuildEgg(payload.Egg or "Gift")
	local vp = PetModels.Viewport(stage, eggModel, { ZIndex = 102 })
	Controllers.AudioController.Play("ChunkBurst")
	-- Three shakes, each harder.
	local t0 = os.clock()
	local egg = eggModel
	for i = 1, 3 do
		local shakeEnd = os.clock() + 0.45
		while os.clock() < shakeEnd and not skip do
			local t = os.clock() - t0
			egg:PivotTo(CFrame.Angles(0, t * 0.6, math.sin(t * 40) * 0.08 * i))
			RunService.RenderStepped:Wait()
		end
		if skip then
			break
		end
		Controllers.AudioController.Play("KeyRattle")
		task.wait(0.15)
	end
	skip = false
	-- The reveal.
	Controllers.FXController.ScreenFlash(Color3.new(1, 1, 1), 0.5)
	Controllers.AudioController.Play(rarity.Order >= 4 and "LevelUp" or "CashAward")
	vp:Destroy()
	local petModel = PetModels.Build(def.Key)
	PetModels.Viewport(stage, petModel, { ZIndex = 102 }, true)
	PetModels.Play(petModel, "Celebrate")
	UI.PopIn(stage, 0.5, 0.35)
	rays.ImageTransparency = 0.25
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
	local close = os.clock() + 4.5
	local spin = 0
	while os.clock() < close and not skip do
		spin += RunService.RenderStepped:Wait() * 30
		rays.Rotation = spin
	end
	UI.Tween(overlay, { BackgroundTransparency = 1 }, 0.25)
	for _, d in ipairs(overlay:GetDescendants()) do
		if d:IsA("TextLabel") then
			UI.Tween(d, { TextTransparency = 1 }, 0.2)
		elseif d:IsA("ImageLabel") then
			UI.Tween(d, { ImageTransparency = 1 }, 0.2)
		elseif d:IsA("ViewportFrame") then
			UI.Tween(d, { ImageTransparency = 1 }, 0.2)
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
