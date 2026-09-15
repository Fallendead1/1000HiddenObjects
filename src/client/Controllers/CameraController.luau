--[[
	Room camera: locked near-first-person while searching (and during the start countdown),
	normal third person everywhere else (lobby, ceremony, results).

	In first person the mouse is locked to the screen centre, so:
	  - a small crosshair shows what the centre of view is pointing at
	  - hold ALT (or open any menu) to get the mouse back and click the HUD
	  - U / B / H open Upgrades / Shop / Hints without leaving the view
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local CameraController = {}

local firstPerson = false
local altHeld = false
local modal: TextButton
local crosshair: Frame
local crossRing: UIStroke
local crossDot: Frame
local CROSS_IDLE, CROSS_ACTIVE = 28, 34 -- design units (the HUD scale applies)
local hint: TextLabel
local freeReasons: { [string]: boolean } = {} -- on-screen things that need a click in first person

local CrosshairColors = {
	idle = Color3.fromRGB(255, 255, 255),
	hover = UI.Colors.Gold,
	heavy = UI.Colors.Red,
	hold = UI.Colors.Green,
}

local function wantFirstPerson(): boolean
	local s = matchState:GetAttribute("State")
	return player:GetAttribute("InMatch") == true and (s == "Countdown" or s == "Searching")
end

local function apply()
	local fp = wantFirstPerson()
	if fp ~= firstPerson then
		firstPerson = fp
		if fp then
			player.CameraMinZoomDistance = 0.5
			player.CameraMaxZoomDistance = 0.5
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		else
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMaxZoomDistance = 128
			-- Push the camera back out of the head, then let the player zoom freely again.
			player.CameraMinZoomDistance = 12
			task.delay(0.25, function()
				if not firstPerson then
					player.CameraMinZoomDistance = 0.5
				end
			end)
		end
	end
	-- A visible Modal button is Roblox's way of freeing the mouse in first person. Touch has no
	-- mouse to free and that full-screen button would swallow the thumbstick, jump and camera
	-- drags, so on-screen prompts (freeReasons) never raise it there: their buttons are tappable.
	local prompt = next(freeReasons) ~= nil and not UI.IsTouch()
	local cursorFree = fp and (altHeld or UI.GetOpenMenu() ~= nil or prompt)
	modal.Visible = cursorFree
	crosshair.Visible = fp and not cursorFree
	hint.Visible = fp and not cursorFree and not UI.IsTouch()
	hint.Text = if UI.IsGamepad() then "[R2] grab / throw   [B] drop   [Y] shop   D-pad left: upgrades   right: hints" else "[ALT] mouse   [Q] drop   [U] upgrades   [B] shop   [H] hints"
end

function CameraController.IsFirstPerson(): boolean
	return firstPerson
end

function CameraController.IsCursorFree(): boolean
	return modal ~= nil and modal.Visible
end

-- Frees the mouse in first person while something on screen needs a click (e.g. the exit door's
-- buttons), without the player holding ALT. Touch has nothing to free (see apply).
function CameraController.SetCursorFree(reason: string, on: boolean)
	freeReasons[reason] = on or nil
	if modal then
		apply()
	end
end

function CameraController.SetCrosshair(kind: string)
	if not crosshair then
		return
	end
	local color = CrosshairColors[kind] or CrosshairColors.idle
	if crossRing.Color ~= color then
		crossRing.Color = color
		crossDot.BackgroundColor3 = color
		local size = if kind == "idle" then CROSS_IDLE else CROSS_ACTIVE
		crosshair.Size = UDim2.fromOffset(size, size)
	end
end

local function toggleMenu(open: () -> (), name: string)
	if UI.GetOpenMenu() == name then
		UI.CloseAllMenus()
	else
		open()
	end
end

function CameraController.Init()
	-- Lowest layer: clicks on empty screen hit this (not the world) while the cursor is free;
	-- HUD buttons sit above it and stay clickable.
	modal = UI.New("TextButton", {
		Name = "CursorUnlock",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Visible = false,
	}, UI.Layers.World) :: TextButton

	-- Full-screen layer: aiming uses the exact viewport centre, and so must the crosshair. A white
	-- ring and dot on a dark outline read over any colour (bright walls, dark junk, the sky); they
	-- take the state colour and grow a little while you aim at or hold something.
	crosshair = UI.Frame({ Name = "Crosshair", Size = UDim2.fromOffset(CROSS_IDLE, CROSS_IDLE), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Visible = false }, UI.Layers.World)
	local function round(frame: Frame)
		UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	end
	-- The dark ring sits a little inside the white one, so it edges it on both sides.
	local outline = UI.Frame({ Name = "Outline", BackgroundTransparency = 1, Size = UDim2.new(1, -3, 1, -3), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, crosshair)
	round(outline)
	UI.New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 5.5, Transparency = 0.25 }, outline)
	local ring = UI.Frame({ Name = "Ring", BackgroundTransparency = 1 }, crosshair)
	round(ring)
	crossRing = UI.New("UIStroke", { Color = CrosshairColors.idle, Thickness = 2.5 }, ring) :: UIStroke
	local dotOutline = UI.Frame({ Name = "DotOutline", Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.25 }, crosshair)
	round(dotOutline)
	crossDot = UI.Frame({ Name = "Dot", Size = UDim2.fromOffset(4, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = CrosshairColors.idle }, crosshair)
	round(crossDot)

	hint = UI.Label({
		Text = "[ALT] mouse   [Q] drop   [U] upgrades   [B] shop   [H] hints",
		TextSize = 14,
		Font = UI.FontBody,
		TextColor3 = UI.Colors.TextDim,
		Size = UDim2.fromOffset(460, 20),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -10),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
	}, UI.Layers.HUD)
	UI.Stroke(hint, Color3.new(0, 0, 0), 1, 0.5)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = true
			apply()
			return
		end
		if gameProcessed or not player:GetAttribute("InMatch") then
			return
		end
		if input.KeyCode == Enum.KeyCode.U then
			toggleMenu(Controllers.UpgradeController.Open, "Upgrades")
		elseif input.KeyCode == Enum.KeyCode.B then
			toggleMenu(Controllers.ShopController.Open, "Shop")
		elseif input.KeyCode == Enum.KeyCode.H then
			toggleMenu(function()
				Controllers.ShopController.Open("Help")
			end, "Shop")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
			altHeld = false
			apply()
		end
	end)

	player:GetAttributeChangedSignal("InMatch"):Connect(apply)
	matchState:GetAttributeChangedSignal("State"):Connect(apply)
	UI.OnMenuChanged(function()
		apply()
	end)
	UI.OnInputModeChanged(apply)
	apply()
end

return CameraController
