--[[
	Feedback for every gameplay beat: bin deposits (a ghost of the object zips into the bin,
	+$ popup with MATCH / SWISH / STREAK tags, the pay bursting out as bills that fly into you),
	chunk bursts, the key rattle,
	upgrades, landing dust + material sounds, Golden Key reveal sparkle. Respects Reduce VFX
	and Camera Shake settings.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local FXController = {}

local vignette: ImageLabel
local shakeAmount = 0
local fovPunch = 0
local baseFov = 70

local function reduceVFX(): boolean
	return player:GetAttribute("Setting_ReduceVFX") == true
end

local function cameraShakeEnabled(): boolean
	return player:GetAttribute("Setting_CameraShake") ~= false
end

local function emitAt(position: Vector3, configure: (ParticleEmitter) -> (), count: number, life: number)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	configure(pe)
	pe.Parent = att
	pe:Emit(count)
	task.delay(life, function()
		att:Destroy()
	end)
end

function FXController.DustPuff(position: Vector3)
	if reduceVFX() then
		return
	end
	emitAt(position, function(pe)
		pe.Lifetime = NumberRange.new(0.4, 0.8)
		pe.Speed = NumberRange.new(2, 4)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.3) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
		pe.Color = ColorSequence.new(Color3.fromRGB(215, 205, 185))
	end, 5, 1.2)
end

function FXController.Burst(position: Vector3, color: Color3, count: number, size: number?)
	if reduceVFX() then
		count = math.max(3, math.floor(count / 3))
	end
	emitAt(position, function(pe)
		pe.Lifetime = NumberRange.new(0.6, 1.3)
		pe.Speed = NumberRange.new(8, 18)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, -22, 0)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.5), NumberSequenceKeypoint.new(1, 0) })
		pe.Color = ColorSequence.new(color)
		pe.LightEmission = 0.7
	end, count, 2.2)
end

function FXController.Confetti(position: Vector3)
	for _, c in ipairs({ Color3.fromRGB(255, 200, 40), Color3.fromRGB(70, 210, 110), Color3.fromRGB(70, 190, 255), Color3.fromRGB(255, 100, 150), Color3.fromRGB(255, 255, 255) }) do
		FXController.Burst(position + Vector3.new(0, 2, 0), c, 22, 0.4)
	end
end

function FXController.ScreenFlash(color: Color3, duration: number?)
	local flash = UI.Frame({ BackgroundColor3 = color, BackgroundTransparency = 0.55 }, UI.Layers.Overlay)
	UI.Tween(flash, { BackgroundTransparency = 1 }, duration or 0.5).Completed:Once(function()
		flash:Destroy()
	end)
end

-- Soft coloured edge tint (hot/cold, victory). transparency 1 = off.
function FXController.SetVignette(color: Color3?, transparency: number, time: number?)
	if not vignette then
		return
	end
	if color then
		vignette.ImageColor3 = color
	end
	UI.Tween(vignette, { ImageTransparency = transparency }, time or 0.4)
end

function FXController.FloatingText(text: string, color: Color3, anchorPos: UDim2?, size: number?)
	local label = UI.Label({ Text = text, TextSize = size or 30, TextWrapped = false, Size = UDim2.fromOffset(460, 48), AnchorPoint = Vector2.new(0.5, 0.5), Position = anchorPos or UDim2.new(0.5, 0, 0.62, 0) }, UI.Layers.Overlay)
	UI.Stroke(label, Color3.new(0, 0, 0), math.clamp((size or 30) * 0.1, 2, 4), 0)
	UI.TextGradient(label, color)
	UI.Tween(label, { Position = label.Position - UDim2.fromOffset(0, 80), TextTransparency = 1 }, 1.1)
	task.delay(1.15, function()
		label:Destroy()
	end)
end

local coinsToHud: (number) -> ()

-- "+$2" that pops up in the world and floats away, with optional bonus tags under it.
local function worldCashPopup(position: Vector3, amount: number, tags: string?, gold: boolean?)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, 1, 0)
	anchor.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 70)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 90
	bb.Adornee = anchor
	bb.Parent = player:WaitForChild("PlayerGui")
	local label = UI.Label({ Text = "+$" .. amount, TextSize = gold and 36 or 30, TextWrapped = false, Size = UDim2.new(1, 0, 0, 40) }, bb)
	UI.Stroke(label, Color3.new(0, 0, 0), 3, 0)
	UI.TextGradient(label, gold and UI.Colors.Gold or UI.Colors.Cash)
	local tagLabel
	if tags and tags ~= "" then
		tagLabel = UI.Label({ Text = tags, TextSize = 18, TextWrapped = false, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 40) }, bb)
		UI.TextGradient(tagLabel, UI.Colors.Gold)
	end
	UI.Tween(bb, { StudsOffset = Vector3.new(0, 3, 0) }, 1.2)
	UI.Tween(label, { TextTransparency = 1 }, 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if tagLabel then
		UI.Tween(tagLabel, { TextTransparency = 1 }, 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.delay(1.25, function()
		bb:Destroy()
		anchor:Destroy()
	end)
end

-- The server removes a deposited object instantly; a local ghost of it zips into the bin.
local function ghostIntoBin(payload)
	if not payload.Position or not payload.BinPosition or reduceVFX() then
		return
	end
	local size = typeof(payload.Size) == "Vector3" and payload.Size or Vector3.one
	local ghost = Instance.new("Part")
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.CastShadow = false
	ghost.Size = size
	ghost.Color = typeof(payload.Color) == "Color3" and payload.Color or Color3.new(1, 1, 1)
	ghost.Material = Enum.Material.SmoothPlastic
	ghost.CFrame = CFrame.new(payload.Position)
	ghost.Parent = workspace.CurrentCamera
	UI.Tween(ghost, { CFrame = CFrame.new(payload.BinPosition), Size = size * 0.2, Transparency = 1 }, 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		ghost:Destroy()
	end)
end

-- ===== Pay that comes to you =====
-- Your pay bursts out of the bin as stacks of bills, hangs for a beat, then gets pulled into you
-- on gold streaks; each one ticks as it lands and the cash counter rolls up when they arrive.

local BILL_GREEN = Color3.fromRGB(64, 196, 88)
local BILL_BAND = Color3.fromRGB(250, 226, 140)
local STREAK_GOLD = Color3.fromRGB(255, 236, 140)
local BILL_GRAVITY = 55

type Bill = { Part: BasePart, From: Vector3, Velocity: Vector3, Spin: Vector3, Born: number, PullAt: number, PullTime: number, PullFrom: Vector3?, Curve: Vector3, Index: number }
local bills: { Bill } = {}

local function makeBill(withTrail: boolean): BasePart
	local bill = Instance.new("Part")
	bill.Name = "CashBill"
	bill.Anchored = true
	bill.CanCollide = false
	bill.CanQuery = false
	bill.CanTouch = false
	bill.CastShadow = false
	bill.Material = Enum.Material.SmoothPlastic
	bill.Color = BILL_GREEN
	bill.Size = Vector3.new(0.95, 0.24, 0.55)
	local band = Instance.new("Part")
	band.Name = "Band"
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.CastShadow = false
	band.Massless = true
	band.Material = Enum.Material.SmoothPlastic
	band.Color = BILL_BAND
	band.Size = Vector3.new(0.24, 0.26, 0.57)
	band.CFrame = bill.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bill
	weld.Part1 = band
	weld.Parent = band
	band.Parent = bill
	if withTrail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.22, 0)
		a0.Parent = bill
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.22, 0)
		a1.Parent = bill
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.Lifetime = 0.2
		trail.LightEmission = 1
		trail.Color = ColorSequence.new(STREAK_GOLD)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
		trail.Parent = bill
	end
	bill.Parent = workspace.CurrentCamera
	return bill
end

-- Where the money goes: just under your view in first person (into your hands), else your body.
local function pocket(): Vector3?
	local camera = workspace.CurrentCamera
	if camera and Controllers.CameraController.IsFirstPerson() then
		return camera.CFrame.Position + camera.CFrame.LookVector * 1.6 - camera.CFrame.UpVector * 1.1
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position + Vector3.new(0, 0.5, 0)
end

local function cashToYou(from: Vector3, amount: number)
	local count = reduceVFX() and 2 or math.clamp(2 + math.floor(amount / 3), 3, 10)
	local now = os.clock()
	local firstArrival = math.huge
	for i = 1, count do
		local angle = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (5 + math.random() * 5)
		local pullAt = now + 0.42 + math.random() * 0.12 + i * 0.045
		local pullTime = 0.32 + math.random() * 0.1
		firstArrival = math.min(firstArrival, pullAt + pullTime)
		table.insert(bills, {
			Part = makeBill(not reduceVFX()),
			From = from,
			Velocity = out + Vector3.new(0, 16 + math.random() * 8, 0),
			Spin = Vector3.new(math.random() * 10 - 5, math.random() * 14 - 7, math.random() * 10 - 5),
			Born = now,
			PullAt = pullAt,
			PullTime = pullTime,
			Curve = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5) * 3,
			Index = i,
		})
	end
	-- The counter waits for the money to get to you.
	Controllers.HUDController.HoldCash(firstArrival - now)
end

local function stepBills()
	local now = os.clock()
	local target: Vector3? = nil
	for i = #bills, 1, -1 do
		local b = bills[i]
		local part = b.Part
		local t = now - b.Born
		local spin = CFrame.Angles(b.Spin.X * t, b.Spin.Y * t, b.Spin.Z * t)
		if now < b.PullAt then
			-- Burst: tossed up and out of the bin.
			part.CFrame = CFrame.new(b.From + b.Velocity * t + Vector3.new(0, -0.5 * BILL_GRAVITY * t * t, 0)) * spin
		else
			target = target or pocket()
			local u = math.clamp((now - b.PullAt) / b.PullTime, 0, 1)
			if target then
				b.PullFrom = b.PullFrom or part.Position
				-- Slow to start, then sucked in, on a slight curve.
				part.CFrame = CFrame.new((b.PullFrom :: Vector3):Lerp(target, u * u * u) + b.Curve * math.sin(u * math.pi)) * spin
			end
			if u >= 1 or not target then
				part:Destroy()
				table.remove(bills, i)
				if target then
					Controllers.AudioController.Play("CashPickup", math.min(1.3 + b.Index * 0.07, 2))
					Controllers.HUDController.PulseCash()
				end
			end
		end
	end
end

local function onDeposit(payload)
	ghostIntoBin(payload)
	if not payload.BinPosition then
		return
	end
	if not payload.Mine then
		Controllers.AudioController.PlayAt("Deposit", payload.BinPosition)
		return
	end
	-- The deposit sound always plays; treasure / swish ring on top of it, and a streak climbs a
	-- semitone with every deposit it lasts (up to an octave).
	Controllers.AudioController.Play(payload.Match and "DepositMatch" or "Deposit")
	if payload.Treasure then
		Controllers.AudioController.Play("Treasure")
	elseif payload.Swish then
		Controllers.AudioController.Play("Swish")
	end
	local streak = payload.Streak or 0
	if streak >= 2 then
		Controllers.AudioController.Play("Streak", math.min(2 ^ ((streak - 2) / 12), 2))
	end
	local tags = {}
	if payload.Treasure then
		table.insert(tags, "TREASURE!")
	end
	if payload.Match then
		table.insert(tags, "MATCH x2")
	end
	if payload.Swish then
		table.insert(tags, "SWISH!")
	end
	if (payload.Streak or 0) >= 2 then
		table.insert(tags, "STREAK x" .. payload.Streak)
	end
	worldCashPopup(payload.BinPosition + Vector3.new(0, 2, 0), payload.Amount or 0, table.concat(tags, "  "), payload.Treasure or payload.Swish)
	cashToYou(payload.BinPosition + Vector3.new(0, 1.5, 0), payload.Amount or 1)
	FXController.Burst(payload.BinPosition + Vector3.new(0, 1.5, 0), payload.Treasure and UI.Colors.Gold or UI.Colors.Cash, payload.Swish and 18 or 8, 0.3)
	if payload.Swish or payload.Treasure then
		FXController.FovPunch(3)
	end
end

function coinsToHud(count: number)
	local target = Controllers.HUDController.GetCashLabelPosition()
	for i = 1, (reduceVFX() and 1 or count) do
		task.delay(i * 0.05, function()
			local coin = UI.Frame({ Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.random(-40, 40), 0.55, math.random(-20, 20)), BackgroundColor3 = UI.Colors.Gold }, UI.Layers.Overlay)
			UI.Corner(coin, 8)
			UI.Tween(coin, { Position = target, Size = UDim2.fromOffset(8, 8) }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
				coin:Destroy()
				Controllers.HUDController.PulseCash()
			end)
		end)
	end
end

function FXController.CameraShake(amount: number)
	if cameraShakeEnabled() and not reduceVFX() then
		shakeAmount = math.max(shakeAmount, amount)
	end
end

function FXController.FovPunch(amount: number)
	if not reduceVFX() then
		fovPunch = math.max(fovPunch, amount)
	end
end

-- The Golden Key once exposed: gentle sparkle, glow and hover so it catches the eye.
local function decorateTarget(model: Instance)
	local primary = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or model
	if not primary or not primary:IsA("BasePart") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = primary
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 8
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkle.LightEmission = 1
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Brightness = 1
	light.Range = 8
	light.Parent = primary
	Controllers.AudioController.PlayAt("TargetReveal", primary.Position)
	FXController.Burst(primary.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 210, 60), 24, 0.35)
	if model:IsA("Model") then
		task.spawn(function()
			local base = model:GetPivot()
			local t0 = os.clock()
			while model.Parent and not matchState:GetAttribute("TargetFound") do
				local t = os.clock() - t0
				model:PivotTo(base * CFrame.new(0, 0, -(math.sin(t * 2) * 0.12 + 0.12)))
				task.wait()
			end
		end)
	end
end

function FXController.Init()
	vignette = UI.Image({ Size = UDim2.fromScale(1, 1), Image = "rbxasset://textures/ui/Vignette.png", ImageTransparency = 1, ImageColor3 = UI.Colors.Red, ScaleType = Enum.ScaleType.Stretch, ZIndex = 0 }, UI.Layers.World)

	local lastLand = 0
	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		payload = payload or {}
		if name == "Land" then
			if payload.Position and os.clock() - lastLand > 0.06 then
				lastLand = os.clock()
				FXController.DustPuff(payload.Position)
				Controllers.AudioController.PlayAt(payload.Sound or "Land", payload.Position)
			end
		elseif name == "Deposit" then
			onDeposit(payload)
		elseif name == "ChunkBurst" then
			if payload.Position then
				Controllers.AudioController.PlayAt("ChunkBurst", payload.Position)
				FXController.DustPuff(payload.Position)
				FXController.Burst(payload.Position, Color3.fromRGB(190, 170, 140), 14, 0.5)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and (root.Position - payload.Position).Magnitude < 14 then
					FXController.CameraShake(0.25)
				end
			end
		elseif name == "KeyRattle" then
			if payload.Position then
				Controllers.AudioController.PlayAt("KeyRattle", payload.Position)
				FXController.DustPuff(payload.Position + Vector3.new(0, 0.5, 0))
			end
		elseif name == "CashAward" then
			Controllers.AudioController.Play("CashAward")
			if payload.Position then
				worldCashPopup(payload.Position, payload.Amount or 0)
				cashToYou(payload.Position, payload.Amount or 1)
			else
				coinsToHud(math.clamp(payload.Amount or 1, 1, 4))
			end
		elseif name == "Upgrade" then
			FXController.ScreenFlash(UI.Colors.Green, 0.4)
			FXController.FovPunch(4)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				FXController.Burst(root.Position, UI.Colors.Green, 18, 0.45)
			end
		end
	end)

	for _, t in ipairs(CollectionService:GetTagged("HiddenTarget")) do
		decorateTarget(t)
	end
	CollectionService:GetInstanceAddedSignal("HiddenTarget"):Connect(function(t)
		task.defer(decorateTarget, t)
	end)
end

function FXController.Start()
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if #bills > 0 then
			stepBills()
		end
		if shakeAmount > 0.001 then
			camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
			shakeAmount = math.max(0, shakeAmount - dt * 1.6)
		end
		if fovPunch > 0.01 then
			camera.FieldOfView = baseFov + fovPunch
			fovPunch = math.max(0, fovPunch - dt * 14)
			if fovPunch <= 0.01 then
				camera.FieldOfView = baseFov
			end
		end
	end)
end

return FXController
