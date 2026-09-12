--[[
	Feedback for every gameplay beat: search ticks, selling (chute chomp + coins to HUD),
	bag full, upgrades, trash bombs, reveal. Respects Reduce VFX and Camera Shake settings.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)
local FormatUtil = require(Shared.Utility.FormatUtil)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local FXController = {}

local tickCounter = 0
local pendingMess = 0
local lastPopup = 0
local bagArrow: BillboardGui? = nil
local bagFullBanner: Frame
local vignette: Frame
local shakeAmount = 0
local fovPunch = 0
local baseFov = 70

local function reduceVFX(): boolean
	return player:GetAttribute("Setting_ReduceVFX") == true
end

local function cameraShakeEnabled(): boolean
	return player:GetAttribute("Setting_CameraShake") ~= false
end

function FXController.DustPuff(position: Vector3)
	if reduceVFX() then
		return
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Speed = NumberRange.new(2, 4)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(215, 205, 185))
	pe.Parent = att
	pe:Emit(7)
	task.delay(1.2, function()
		att:Destroy()
	end)
end

function FXController.Burst(position: Vector3, color: Color3, count: number, size: number?)
	if reduceVFX() then
		count = math.max(3, math.floor(count / 3))
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.6, 1.3)
	pe.Speed = NumberRange.new(8, 18)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -22, 0)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.7
	pe.Parent = att
	pe:Emit(count)
	task.delay(2.2, function()
		att:Destroy()
	end)
end

function FXController.Confetti(position: Vector3)
	local colors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(70, 210, 110), Color3.fromRGB(70, 190, 255), Color3.fromRGB(255, 100, 150), Color3.fromRGB(255, 255, 255) }
	for _, c in ipairs(colors) do
		FXController.Burst(position + Vector3.new(0, 2, 0), c, 22, 0.4)
	end
end

function FXController.ScreenFlash(color: Color3, duration: number?)
	local flash = UI.Frame({ BackgroundColor3 = color, BackgroundTransparency = 0.55 }, UI.Layers.Overlay)
	UI.Tween(flash, { BackgroundTransparency = 1 }, duration or 0.5).Completed:Once(function()
		flash:Destroy()
	end)
end

-- Soft coloured edge tint (hot/cold, bag full, victory). transparency 1 = off.
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
	local label = UI.Label({
		Text = text,
		TextSize = size or 30,
		TextColor3 = color,
		Size = UDim2.fromOffset(340, 44),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = anchorPos or UDim2.new(0.5, 0, 0.62, 0),
	}, UI.Layers.Overlay)
	UI.Stroke(label, Color3.new(0, 0, 0), 2, 0.3)
	local s = UI.New("UIScale", { Scale = 0.6 }, label)
	UI.Tween(s, { Scale = 1 }, 0.18, Enum.EasingStyle.Back)
	UI.Tween(label, { Position = label.Position - UDim2.fromOffset(0, 80), TextTransparency = 1 }, 1.1)
	task.delay(1.15, function()
		label:Destroy()
	end)
end

function FXController.CameraShake(amount: number)
	if not cameraShakeEnabled() or reduceVFX() then
		return
	end
	shakeAmount = math.max(shakeAmount, amount)
end

function FXController.FovPunch(amount: number)
	if reduceVFX() then
		return
	end
	fovPunch = math.max(fovPunch, amount)
end

-- Coins that fly from the screen centre to the cash label.
local function coinsToHud(count: number)
	if reduceVFX() then
		count = 2
	end
	local target = Controllers.HUDController.GetCashLabelPosition()
	for i = 1, count do
		task.delay(i * 0.04, function()
			local coin = UI.Frame({ Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.random(-60, 60), 0.6, math.random(-30, 30)), BackgroundColor3 = UI.Colors.Gold }, UI.Layers.Overlay)
			UI.Corner(coin, 9)
			UI.Stroke(coin, UI.Colors.GoldDark, 2)
			UI.Tween(coin, { Position = target, Size = UDim2.fromOffset(8, 8) }, 0.45 + math.random() * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
				coin:Destroy()
				Controllers.HUDController.PulseCash()
			end)
		end)
	end
end

local function chuteChomp()
	local chute = CollectionService:GetTagged("TrashChute")[1]
	if not chute then
		return
	end
	local mouth = chute:FindFirstChild("Mouth")
	local beacon = chute:FindFirstChild("Beacon")
	if mouth and mouth:IsA("BasePart") then
		local size = mouth.Size
		TweenService:Create(mouth, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = Vector3.new(size.X * 1.15, size.Y * 0.5, size.Z) }):Play()
		FXController.Burst(mouth.Position - Vector3.new(0, 0, 1), UI.Colors.Cash, 12, 0.3)
	end
	if beacon and beacon:IsA("BasePart") then
		local light = beacon:FindFirstChildOfClass("PointLight")
		TweenService:Create(beacon, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Size = beacon.Size * 1.8 }):Play()
		if light then
			TweenService:Create(light, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Brightness = 4 }):Play()
		end
	end
	Controllers.AudioController.PlayAt("ChuteChomp", chute:GetPivot().Position)
end

local function showBagFull(chutePosition: Vector3?)
	bagFullBanner.Visible = true
	bagFullBanner.Position = UDim2.new(0.5, 0, 0.3, 0)
	UI.Tween(bagFullBanner, { Position = UDim2.new(0.5, 0, 0.26, 0) }, 0.3, Enum.EasingStyle.Back)
	Controllers.HUDController.FlashBagFull()
	Controllers.AudioController.Play("BagFull")
	FXController.SetVignette(UI.Colors.Red, 0.6, 0.2)
	task.delay(0.6, function()
		FXController.SetVignette(nil, 1, 0.6)
	end)
	task.delay(3, function()
		bagFullBanner.Visible = false
	end)

	if bagArrow then
		bagArrow:Destroy()
		bagArrow = nil
	end
	if chutePosition then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Position = chutePosition + Vector3.new(0, 10, 0)
		anchor.Parent = workspace.CurrentCamera
		local bb = UI.Billboard(anchor, UDim2.fromOffset(220, 90), Vector3.zero, 500)
		bb.AlwaysOnTop = true
		bb.Parent = anchor
		local lbl = UI.Label({ Text = "DUMP MESS HERE\n▼", TextSize = 26, TextColor3 = UI.Colors.Orange }, bb)
		UI.Stroke(lbl, Color3.new(0, 0, 0), 2, 0.2)
		bagArrow = bb
		task.spawn(function()
			local t0 = os.clock()
			while anchor.Parent and os.clock() - t0 < 6 do
				bb.StudsOffset = Vector3.new(0, math.sin(os.clock() * 5) * 0.8, 0)
				task.wait()
			end
			anchor:Destroy()
			if bagArrow == bb then
				bagArrow = nil
			end
		end)
	end
end

local function onSearchTick(payload)
	tickCounter += 1
	pendingMess += payload.Amount or 0
	Controllers.ClutterVisualController.Shake(payload.ClusterId)
	if tickCounter % 2 == 0 then
		Controllers.AudioController.Play("SearchRustle")
	end
	if tickCounter % 3 == 0 then
		local center = Controllers.ClutterVisualController.GetClusterCenter(payload.ClusterId)
		if center then
			FXController.DustPuff(center + Vector3.new(0, 1, 0))
		end
	end
	local now = os.clock()
	if now - lastPopup > 1.0 and pendingMess > 0 then
		lastPopup = now
		FXController.FloatingText(string.format("+%d MESS", pendingMess), UI.Colors.Orange, UDim2.new(0.5, math.random(-40, 40), 0.58, 0), 26)
		pendingMess = 0
	end
	FXController.CameraShake(0.04)
end

function FXController.Init()
	vignette = UI.Image({ Size = UDim2.fromScale(1, 1), Image = "rbxasset://textures/ui/Vignette.png", ImageTransparency = 1, ImageColor3 = UI.Colors.Red, ScaleType = Enum.ScaleType.Stretch, ZIndex = 0 }, UI.Layers.World)

	bagFullBanner = UI.Panel({ Size = UDim2.fromOffset(380, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.26, 0), Visible = false, BackgroundColor3 = UI.Colors.PanelDark }, UI.Layers.Overlay)
	UI.Stroke(bagFullBanner, UI.Colors.Red, 3)
	UI.Label({ Text = "BAG FULL!", TextSize = 36, TextColor3 = UI.Colors.Red, Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 6) }, bagFullBanner)
	UI.Label({ Text = "Dump your mess at the Trash Chute to earn Cash.", TextSize = 16, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 54) }, bagFullBanner)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		payload = payload or {}
		if name == "SearchTick" then
			onSearchTick(payload)
		elseif name == "Sell" then
			Controllers.AudioController.Play("SellCash")
			FXController.FloatingText(payload.Text or ("+" .. FormatUtil.CashExact(payload.Amount or 0)), UI.Colors.Cash, nil, 34)
			coinsToHud(math.clamp(math.floor((payload.Amount or 0) / 20) + 3, 3, 10))
			chuteChomp()
			if payload.Position then
				FXController.Burst(payload.Position + Vector3.new(0, 3, 0), UI.Colors.Cash, 14, 0.4)
			end
			if bagArrow then
				bagArrow:Destroy()
				bagArrow = nil
			end
			bagFullBanner.Visible = false
		elseif name == "BagFull" then
			showBagFull(payload.ChutePosition)
		elseif name == "Upgrade" then
			FXController.ScreenFlash(UI.Colors.Green, 0.4)
			FXController.FovPunch(4)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				FXController.Burst(root.Position, UI.Colors.Green, 18, 0.45)
			end
		elseif name == "TrashBomb" then
			Controllers.AudioController.PlayAt("TrashBomb", payload.Position or Vector3.zero)
			if payload.Position then
				FXController.Burst(payload.Position + Vector3.new(0, 3, 0), UI.Colors.Orange, 45, 0.9)
				FXController.Burst(payload.Position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 90, 60), 35, 1.3)
			end
			FXController.CameraShake(0.7)
			FXController.FovPunch(6)
			Controllers.NotificationController.Show("Premium", string.format("%s used a TRASH BOMB!", payload.PlayerName or "Someone"))
		end
	end)
end

function FXController.Start()
	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if shakeAmount > 0.001 then
			local offset = Vector3.new((math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
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
