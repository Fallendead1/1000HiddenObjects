--[[
	Feedback for every gameplay beat: Cash earned from newly moved objects (world popup + coins
	to the HUD), upgrades, landing dust, Golden Key reveal sparkle. Respects Reduce VFX and
	Camera Shake settings.
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
	local label = UI.Label({ Text = text, TextSize = size or 30, TextColor3 = color, Size = UDim2.fromOffset(340, 44), AnchorPoint = Vector2.new(0.5, 0.5), Position = anchorPos or UDim2.new(0.5, 0, 0.62, 0) }, UI.Layers.Overlay)
	UI.Stroke(label, Color3.new(0, 0, 0), 2, 0.3)
	UI.Tween(label, { Position = label.Position - UDim2.fromOffset(0, 80), TextTransparency = 1 }, 1.1)
	task.delay(1.15, function()
		label:Destroy()
	end)
end

-- "+$2" that pops out of the object in the world and floats up.
local function worldCashPopup(position: Vector3, amount: number)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, 1, 0)
	anchor.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 40)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 80
	bb.Adornee = anchor
	bb.Parent = player:WaitForChild("PlayerGui")
	local label = UI.Label({ Text = "+$" .. amount, TextSize = 28, TextColor3 = UI.Colors.Cash }, bb)
	UI.Stroke(label, Color3.new(0, 0, 0), 2, 0.2)
	UI.Tween(bb, { StudsOffset = Vector3.new(0, 3, 0) }, 1)
	UI.Tween(label, { TextTransparency = 1 }, 1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(1.05, function()
		bb:Destroy()
		anchor:Destroy()
	end)
end

local function coinsToHud(count: number)
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
				Controllers.AudioController.PlayAt("Land", payload.Position)
			end
		elseif name == "CashAward" then
			Controllers.AudioController.Play("CashAward")
			if payload.Position then
				worldCashPopup(payload.Position, payload.Amount or 0)
			end
			coinsToHud(math.clamp(payload.Amount or 1, 1, 4))
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
