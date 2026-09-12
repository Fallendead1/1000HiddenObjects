--[[
	Lightweight feedback for every gameplay beat: search ticks, selling, bag full, upgrades,
	trash bombs, reveal and confetti. Pooled/short-lived, respects Reduce VFX and Camera Shake.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local shakeAmount = 0

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
	pe.Lifetime = NumberRange.new(0.4, 0.7)
	pe.Speed = NumberRange.new(2, 4)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(210, 200, 180))
	pe.Parent = att
	pe:Emit(6)
	task.delay(1, function()
		att:Destroy()
	end)
end

function FXController.Burst(position: Vector3, color: Color3, count: number, size: number?)
	if reduceVFX() then
		count = math.floor(count / 3)
	end
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Speed = NumberRange.new(8, 16)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, -20, 0)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.6
	pe.Parent = att
	pe:Emit(count)
	task.delay(2, function()
		att:Destroy()
	end)
end

function FXController.Confetti(position: Vector3)
	local colors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(70, 210, 110), Color3.fromRGB(70, 190, 255), Color3.fromRGB(255, 100, 150), Color3.fromRGB(255, 255, 255) }
	for _, c in ipairs(colors) do
		FXController.Burst(position + Vector3.new(0, 2, 0), c, 18, 0.35)
	end
end

function FXController.ScreenFlash(color: Color3, duration: number?)
	local flash = UI.Frame({ BackgroundColor3 = color, BackgroundTransparency = 0.55 }, UI.Layers.Overlay)
	UI.Tween(flash, { BackgroundTransparency = 1 }, duration or 0.5).Completed:Once(function()
		flash:Destroy()
	end)
end

function FXController.FloatingText(text: string, color: Color3, anchorPos: UDim2?)
	local label = UI.Label({
		Text = text,
		TextSize = 30,
		TextColor3 = color,
		Size = UDim2.fromOffset(300, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = anchorPos or UDim2.new(0.5, 0, 0.62, 0),
	}, UI.Layers.Overlay)
	UI.Stroke(label, Color3.new(0, 0, 0), 2, 0.4)
	UI.Tween(label, { Position = label.Position - UDim2.fromOffset(0, 70), TextTransparency = 1 }, 1.1)
	task.delay(1.1, function()
		label:Destroy()
	end)
end

function FXController.CameraShake(amount: number)
	if not cameraShakeEnabled() or reduceVFX() then
		return
	end
	shakeAmount = math.max(shakeAmount, amount)
end

local function showBagFull(chutePosition: Vector3?)
	bagFullBanner.Visible = true
	bagFullBanner.Position = UDim2.new(0.5, 0, 0.3, 0)
	UI.Tween(bagFullBanner, { Position = UDim2.new(0.5, 0, 0.26, 0) }, 0.3, Enum.EasingStyle.Back)
	Controllers.HUDController.FlashBagFull()
	Controllers.AudioController.Play("BagFull")
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
		anchor.Position = chutePosition + Vector3.new(0, 9, 0)
		anchor.Parent = workspace.CurrentCamera
		local bb = UI.Billboard(anchor, UDim2.fromOffset(200, 80), Vector3.zero, 500)
		bb.AlwaysOnTop = true
		bb.Parent = anchor
		local lbl = UI.Label({ Text = "DUMP MESS HERE\nv", TextSize = 24, TextColor3 = UI.Colors.Orange }, bb)
		UI.Stroke(lbl, Color3.new(0, 0, 0), 2, 0.3)
		bagArrow = bb
		task.spawn(function()
			local t0 = os.clock()
			while anchor.Parent and os.clock() - t0 < 5 do
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
	if tickCounter % 3 == 0 then
		Controllers.AudioController.Play("SearchRustle")
		local center = Controllers.ClutterVisualController.GetClusterCenter(payload.ClusterId)
		if center then
			FXController.DustPuff(center)
		end
	end
	local now = os.clock()
	if now - lastPopup > 1.2 and pendingMess > 0 then
		lastPopup = now
		FXController.FloatingText(string.format("+%d MESS", pendingMess), UI.Colors.Orange, UDim2.new(0.5, 0, 0.58, 0))
		pendingMess = 0
	end
	FXController.CameraShake(0.05)
end

function FXController.Init()
	bagFullBanner = UI.Panel({ Size = UDim2.fromOffset(360, 84), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.26, 0), Visible = false, BackgroundColor3 = UI.Colors.PanelDark }, UI.Layers.Overlay)
	UI.Stroke(bagFullBanner, UI.Colors.Red, 3)
	UI.Label({ Text = "BAG FULL!", TextSize = 34, TextColor3 = UI.Colors.Red, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 6) }, bagFullBanner)
	UI.Label({ Text = "Dump your mess to earn cash.", TextSize = 16, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 50) }, bagFullBanner)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		payload = payload or {}
		if name == "SearchTick" then
			onSearchTick(payload)
		elseif name == "Sell" then
			Controllers.AudioController.Play("SellCash")
			FXController.FloatingText(payload.Text or ("+" .. FormatUtil.CashExact(payload.Amount or 0)), UI.Colors.Cash)
			Controllers.HUDController.PulseCash()
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
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				FXController.Burst(root.Position, UI.Colors.Green, 16, 0.4)
			end
		elseif name == "TrashBomb" then
			Controllers.AudioController.PlayAt("TrashBomb", payload.Position or Vector3.zero)
			if payload.Position then
				FXController.Burst(payload.Position + Vector3.new(0, 3, 0), UI.Colors.Orange, 40, 0.8)
				FXController.Burst(payload.Position + Vector3.new(0, 3, 0), Color3.fromRGB(120, 90, 60), 30, 1.2)
			end
			FXController.CameraShake(0.6)
			Controllers.NotificationController.Show("Premium", string.format("%s used a TRASH BOMB!", payload.PlayerName or "Someone"))
		end
	end)
end

function FXController.Start()
	RunService.RenderStepped:Connect(function(dt)
		if shakeAmount > 0.001 then
			local camera = workspace.CurrentCamera
			if camera then
				local offset = Vector3.new((math.random() - 0.5) * shakeAmount, (math.random() - 0.5) * shakeAmount, 0)
				camera.CFrame = camera.CFrame * CFrame.new(offset)
			end
			shakeAmount = math.max(0, shakeAmount - dt * 1.5)
		end
	end)
end

return FXController
