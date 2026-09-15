--[[
	Teleport overlay ("FINDING YOUR ROOM...") and the match intro sequence:
	ROOM #001 -> OBJECT TO FIND -> SOMEWHERE IN THIS ROOM... -> 3 2 1 -> SEARCH!
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)
local TargetData = require(Shared.Data.TargetData)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local LoadingController = {}

local overlay: Frame
local bigLabel: TextLabel
local smallLabel: TextLabel
local iconFrame: Frame
local iconGlyph: TextLabel
local iconImage: ImageLabel
local token = 0

local function show()
	overlay.Visible = true
	overlay.BackgroundTransparency = 0
end

local function hide(fadeTime: number?)
	UI.Tween(overlay, { BackgroundTransparency = 1 }, fadeTime or 0.5)
	UI.Tween(bigLabel, { TextTransparency = 1 }, fadeTime or 0.5)
	UI.Tween(smallLabel, { TextTransparency = 1 }, fadeTime or 0.5)
	iconFrame.Visible = false
	task.delay(fadeTime or 0.5, function()
		overlay.Visible = false
		bigLabel.TextTransparency = 0
		smallLabel.TextTransparency = 0
	end)
end

local function setText(big: string, small: string, bigColor: Color3?, bigSize: number?)
	bigLabel.Text = big
	bigLabel.TextColor3 = Color3.new(1, 1, 1)
	UI.TextGradient(bigLabel, bigColor or UI.Colors.Text)
	bigLabel.TextSize = bigSize or 56
	smallLabel.Text = small
	bigLabel.TextTransparency = 0
	smallLabel.TextTransparency = 0
	local s = bigLabel:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, bigLabel)
	s.Scale = 0.8
	UI.Tween(s, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
end

local function runIntro(payload)
	token += 1
	local myToken = token
	local function alive()
		return token == myToken
	end
	show()
	iconFrame.Visible = false
	local roomName = string.upper(payload.RoomName or "") .. (payload.Hard and "  ·  HARD MODE" or "")
	setText("ROOM #" .. (payload.RoomNumber or "001"), roomName, payload.Hard and UI.Colors.Red or UI.Colors.Text)
	if payload.ResumePercent and payload.ResumePercent > 0 then
		smallLabel.Text = string.format("%s  -  RESUMING FROM %d%%", roomName, math.floor(payload.ResumePercent * 100))
	end
	task.wait(1.5)
	if not alive() then return end

	local def = TargetData.GetById(payload.TargetId or "")
	setText(string.upper(payload.TargetName or "???"), "OBJECT TO FIND", UI.Colors.Gold)
	iconFrame.Visible = true
	iconFrame.BackgroundColor3 = def and def.Color or UI.Colors.Gold
	iconGlyph.Text = def and string.upper(string.sub(def.Name, 1, 1)) or "?"
	local art = def and UI.Asset(def.IconKey or "")
	iconImage.Image = art or ""
	iconImage.Visible = art ~= nil
	iconGlyph.Visible = art == nil
	UI.PopIn(iconFrame, 0.4, 0.45)
	task.wait(2)
	if not alive() then return end

	iconFrame.Visible = false
	setText("SOMEWHERE IN THIS ROOM...", "", UI.Colors.TextDim, 40)
	task.wait(1)
	if not alive() then return end

	for i = 3, 1, -1 do
		setText(tostring(i), "", UI.Colors.Text, 96)
		Controllers.AudioController.Play("Countdown")
		task.wait(0.83)
		if not alive() then return end
	end
	setText("SEARCH!", "", UI.Colors.Green, 90)
	Controllers.AudioController.Play("Countdown")
	task.wait(0.7)
	if not alive() then return end
	hide(0.4)
end

function LoadingController.Init()
	overlay = UI.Frame({ Name = "LoadingOverlay", BackgroundColor3 = Color3.fromRGB(8, 10, 18), Visible = false }, UI.Layers.Top)
	-- Optional art: a full-screen backdrop and the game logo (ReplicatedStorage.GameAssets.UIImages).
	local backdropArt = UI.Asset("LoadingBackground")
	if backdropArt then
		UI.Image({ Image = backdropArt, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.25, ZIndex = 0 }, overlay)
	end
	local logoArt = UI.Asset("Logo")
	if logoArt then
		local logo = UI.Image({ Image = logoArt, Size = UDim2.fromOffset(460, 200), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.03, 0) }, overlay)
		UI.New("UISizeConstraint", { MaxSize = Vector2.new(460, 200) }, logo)
		UI.Pulse(logo, 0.02, 1.6)
	end
	bigLabel = UI.Label({ Text = "", TextSize = 56, Size = UDim2.new(1, 0, 0, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45) }, overlay)
	UI.Stroke(bigLabel, Color3.new(0, 0, 0), 3, 0.3)
	smallLabel = UI.Label({ Text = "", TextSize = 24, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.56) }, overlay)
	iconFrame = UI.Frame({ Size = UDim2.fromOffset(140, 140), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.25), BackgroundColor3 = UI.Colors.Gold, Visible = false }, overlay)
	UI.Corner(iconFrame, 24)
	UI.Stroke(iconFrame, Color3.new(1, 1, 1), 4)
	iconGlyph = UI.Label({ Text = "K", TextSize = 80, TextColor3 = UI.Colors.PanelDark }, iconFrame)
	iconImage = UI.Image({ Size = UDim2.new(1, -18, 1, -18), Position = UDim2.fromOffset(9, 9), Visible = false }, iconFrame)
	UI.Glow(iconFrame, UI.Colors.Gold, 36, 0.35)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName, payload)
		if eventName == "Intro" then
			task.spawn(runIntro, payload)
		elseif eventName == "ReturnedToLobby" then
			token += 1
			show()
			setText("RETURNING TO LOBBY", "", UI.Colors.TextDim, 40)
			task.delay(0.8, function()
				hide(0.5)
			end)
		end
	end)

	-- The overlay stays up until the room is really ready (building and settling a room can take
	-- several seconds), so the lobby never flashes back in between.
	player:GetAttributeChangedSignal("Teleporting"):Connect(function()
		if player:GetAttribute("Teleporting") then
			token += 1
			show()
			setText("FINDING YOUR ROOM...", "", UI.Colors.TextDim, 44)
			Controllers.AudioController.Play("TeleportWhoosh")
			-- Last-resort safety if nothing ever follows.
			local myToken = token
			task.delay(30, function()
				if token == myToken and overlay.Visible and not player:GetAttribute("InMatch") then
					hide(0.4)
				end
			end)
		else
			-- Same-server matches clear Teleporting once the room is ready. Still in the lobby by
			-- then means the launch failed. (A real teleport leaves the server instead.)
			local info = ReplicatedStorage:FindFirstChild("ServerInfo")
			if info and info:GetAttribute("Role") == "Combined" and not player:GetAttribute("InMatch") and overlay.Visible then
				token += 1
				hide(0.4)
			end
		end
	end)
end

function LoadingController.ShowMessage(text: string, seconds: number)
	token += 1
	show()
	setText(text, "", UI.Colors.TextDim, 40)
	task.delay(seconds, function()
		hide(0.4)
	end)
end

return LoadingController
