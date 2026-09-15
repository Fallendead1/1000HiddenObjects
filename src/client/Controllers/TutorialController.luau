--[[
	The tutorial, done like a guided walkthrough: one line of instructions at the top of the
	screen, a bouncing arrow with a white frame on the exact button to press, an arrow over the
	thing to go to in the world, and a guide beam in the lobby. Each step moves on when the player
	does it, and it all runs only until the first room's tutorial is finished (or skipped).
	  Lobby:      welcome  ->  walk into a glowing circle  ->  pick a room and press CREATE
	  First room: 1 grab   2 throw it into the x2 bin   3 upgrades   4 find the key (HINT)   done
	Settings > HOW TO PLAY replays the lessons as a short animated video, from anywhere.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local DepositConfig = require(ReplicatedStorage.Shared.Config.DepositConfig)
local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local TutorialController = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local STAGE_COLOR = Color3.fromRGB(34, 38, 56)
local CLUE_BANNER_HEIGHT = 60 -- HintController's banner

local function platformText(pc: string, touch: string, pad: string): string
	if UI.IsTouch() then
		return touch
	elseif UI.IsGamepad() then
		return pad
	end
	return pc
end

-- The lessons, as HOW TO PLAY shows them.
local Steps = {
	{
		Title = "GRAB",
		Scene = "Grab",
		Text = function()
			return platformText("Aim at any object and HOLD LEFT MOUSE to grab it.", "Aim at any object and tap GRAB.", "Aim at any object and HOLD R2 to grab it.")
		end,
	},
	{
		Title = "AIM & THROW",
		Scene = "Throw",
		Text = function()
			return platformText("Keep holding and aim: the dotted arc shows where it lands. RELEASE to throw!", "Turn the camera to aim: the dotted arc shows where it lands. Tap THROW!", "Keep holding R2 and aim: the arc shows where it lands. RELEASE to throw!")
		end,
	},
	{
		Title = "THE RIGHT BIN PAYS x2",
		Scene = "Bins",
		Text = function()
			return "Every bin cleans junk for Cash, but the RIGHT one pays DOUBLE. Follow the gold x2 arrow while you hold something."
		end,
	},
	{
		Title = "UPGRADES",
		Scene = "Upgrade",
		Text = function()
			return "Spend your Cash on UPGRADES to lift heavier things and throw farther."
		end,
	},
	{
		Title = "FIND THE KEY",
		Scene = "Key",
		Text = function()
			return "The Golden Key is hidden under the junk. Dig through the piles - stuck? Tap HINT!"
		end,
	},
}

-- ===== HOW TO PLAY's mini "video": little looping scenes drawn with UI shapes =====

local function sleep(seconds: number, alive: () -> boolean): boolean
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime do
		if not alive() then
			return false
		end
		task.wait()
	end
	return alive()
end

local function edge(b: GuiObject, color: Color3)
	local stroke = b:FindFirstChild("Edge")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = color
	end
end

local function block(stage: Frame, color: Color3, size: UDim2, pos: UDim2, text: string?): Frame
	local b = UI.Frame({ Size = size, AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, BackgroundColor3 = color }, stage)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	UI.New("UIStroke", { Name = "Edge", Color = BLACK, Thickness = 2 }, b)
	if text then
		UI.Label({ Text = text, TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.9, 0.7), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, b)
	end
	return b
end

local function binShape(stage: Frame, color: Color3, name: string, pos: UDim2): Frame
	local b = UI.Frame({ Size = UDim2.fromScale(0.26, 0.26), AnchorPoint = Vector2.new(0.5, 1), Position = pos, BackgroundColor3 = color }, stage)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	UI.New("UIStroke", { Color = BLACK, Thickness = 2 }, b)
	local rim = UI.Frame({ Size = UDim2.new(1.12, 0, 0.16, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0), BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35) }, b)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 4) }, rim)
	UI.New("UIStroke", { Color = BLACK, Thickness = 2 }, rim)
	UI.Label({ Text = name, TextScaled = true, TextWrapped = false, Size = UDim2.new(0.9, 0, 0.45, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.58) }, b)
	return b
end

local function cursor(stage: Frame): Frame
	local c = UI.Frame({ Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 10 }, stage)
	UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, c)
	UI.New("UIStroke", { Color = BLACK, Thickness = 2.5 }, c)
	return c
end

local function floor(stage: Frame)
	UI.Frame({ Size = UDim2.new(1, 0, 0.14, 0), Position = UDim2.fromScale(0, 0.86), BackgroundColor3 = Color3.fromRGB(150, 105, 70) }, stage)
end

local function pop(stage: Frame, text: string, color: Color3, pos: UDim2)
	local label = UI.Label({ Text = text, TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.56, 0.16), AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, ZIndex = 12 }, stage)
	UI.TextGradient(label, color)
	UI.PopIn(label, 0.4, 0.3)
	UI.Tween(label, { Position = pos - UDim2.fromScale(0, 0.18), TextTransparency = 1 }, 1.2)
	task.delay(1.25, function()
		label:Destroy()
	end)
end

-- Moves a shape along a throw arc (scale positions), lifting `lift` at the top.
local function arc(obj: GuiObject, from: Vector2, to: Vector2, lift: number, duration: number, alive: () -> boolean): boolean
	local t0 = os.clock()
	while alive() do
		local t = math.min(1, (os.clock() - t0) / duration)
		obj.Position = UDim2.fromScale(from.X + (to.X - from.X) * t, from.Y + (to.Y - from.Y) * t - lift * 4 * t * (1 - t))
		if t >= 1 then
			return true
		end
		task.wait()
	end
	return false
end

local function arcDots(stage: Frame, from: Vector2, to: Vector2, lift: number, color: Color3): { Frame }
	local dots = {}
	for i = 1, 7 do
		local t = i / 8
		local d = UI.Frame({ Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(from.X + (to.X - from.X) * t, from.Y + (to.Y - from.Y) * t - lift * 4 * t * (1 - t)), BackgroundColor3 = color, BackgroundTransparency = 0.1 + i * 0.08 }, stage)
		UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		table.insert(dots, d)
	end
	return dots
end

local function destroyAll(list: { Instance })
	for _, g in ipairs(list) do
		g:Destroy()
	end
end

local Scenes = {}

Scenes.Grab = function(stage: Frame, alive)
	floor(stage)
	block(stage, Color3.fromRGB(230, 90, 120), UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.2, 0.76))
	block(stage, Color3.fromRGB(255, 200, 60), UDim2.fromScale(0.18, 0.24), UDim2.fromScale(0.8, 0.74))
	local target = block(stage, Color3.fromRGB(90, 150, 230), UDim2.fromScale(0.22, 0.18), UDim2.fromScale(0.5, 0.77))
	local hand = cursor(stage)
	while alive() do
		target.Position = UDim2.fromScale(0.5, 0.77)
		edge(target, BLACK)
		hand.Position = UDim2.fromScale(0.95, 0.15)
		UI.Tween(hand, { Position = UDim2.fromScale(0.55, 0.7) }, 0.7, Enum.EasingStyle.Quad)
		if not sleep(0.85, alive) then
			return
		end
		UI.PopIn(hand, 0.7, 0.2)
		edge(target, UI.Colors.Green)
		pop(stage, platformText("HOLD", "TAP GRAB", "HOLD R2"), UI.Colors.Green, UDim2.fromScale(0.5, 0.28))
		UI.Tween(target, { Position = UDim2.fromScale(0.5, 0.45) }, 0.45, Enum.EasingStyle.Back)
		UI.Tween(hand, { Position = UDim2.fromScale(0.55, 0.38) }, 0.45)
		if not sleep(1.6, alive) then
			return
		end
	end
end

Scenes.Throw = function(stage: Frame, alive)
	floor(stage)
	local bin = binShape(stage, DepositConfig.Types.Laundry.Color, "BIN", UDim2.fromScale(0.8, 0.86))
	local from, to = Vector2.new(0.22, 0.5), Vector2.new(0.8, 0.66)
	while alive() do
		local obj = block(stage, Color3.fromRGB(230, 90, 120), UDim2.fromScale(0.16, 0.14), UDim2.fromScale(from.X, from.Y))
		edge(obj, UI.Colors.Green)
		local dots = arcDots(stage, from, to, 0.35, UI.Colors.Gold)
		if not sleep(1.2, alive) then
			return
		end
		destroyAll(dots)
		if not arc(obj, from, to, 0.35, 0.7, alive) then
			return
		end
		obj:Destroy()
		pop(stage, "+$2", UI.Colors.Cash, UDim2.fromScale(0.8, 0.5))
		UI.PopIn(bin, 0.85, 0.3)
		if not sleep(1.2, alive) then
			return
		end
	end
end

Scenes.Bins = function(stage: Frame, alive)
	floor(stage)
	local toyColor = DepositConfig.Types.Toys.Color
	local toyBin = binShape(stage, toyColor, "TOYS", UDim2.fromScale(0.27, 0.86))
	local trash = binShape(stage, DepositConfig.Types.Trash.Color, "TRASH", UDim2.fromScale(0.73, 0.86))
	-- The same gold x2 guide the game shows over the right bin.
	local guide = UI.Label({ Text = "x2", TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.22, 0.15), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.27, 0.3) }, stage)
	UI.TextGradient(guide, UI.Colors.Gold)
	local start = Vector2.new(0.5, 0.16)
	while alive() do
		for round = 1, 2 do
			local right = round == 1
			if right then
				UI.PopIn(guide, 0.8, 0.3)
			end
			local obj = block(stage, toyColor, UDim2.fromScale(0.15, 0.13), UDim2.fromScale(start.X, start.Y), "TOY")
			if not sleep(0.5, alive) then
				return
			end
			local target = right and Vector2.new(0.27, 0.66) or Vector2.new(0.73, 0.66)
			if not arc(obj, start, target, 0.12, 0.6, alive) then
				return
			end
			obj:Destroy()
			if right then
				pop(stage, "x2  +$6", UI.Colors.Gold, UDim2.fromScale(0.27, 0.56))
				UI.PopIn(toyBin, 0.8, 0.3)
			else
				pop(stage, "x1  +$3", Color3.new(1, 1, 1), UDim2.fromScale(0.73, 0.56))
				UI.PopIn(trash, 0.85, 0.3)
			end
			if not sleep(1.3, alive) then
				return
			end
		end
	end
end

Scenes.Upgrade = function(stage: Frame, alive)
	floor(stage)
	local cash = UI.Label({ Text = "$60", TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.3, 0.16), Position = UDim2.fromScale(0.04, 0.05), TextXAlignment = Enum.TextXAlignment.Left }, stage)
	UI.TextGradient(cash, UI.Colors.Cash)
	local button = UI.Frame({ Size = UDim2.fromScale(0.42, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.3, 0.46), BackgroundColor3 = UI.Colors.Green }, stage)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 8) }, button)
	UI.New("UIStroke", { Color = BLACK, Thickness = 2 }, button)
	UI.Label({ Text = "UPGRADE", TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.86, 0.66), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, button)
	local box = block(stage, Color3.fromRGB(150, 105, 70), UDim2.fromScale(0.22, 0.26), UDim2.fromScale(0.76, 0.73), "5")
	local tag = UI.Label({ Text = "TOO HEAVY", TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.38, 0.12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.76, 0.48) }, stage)
	local hand = cursor(stage)
	while alive() do
		cash.Text = "$60"
		tag.Text = "TOO HEAVY"
		UI.TextGradient(tag, UI.Colors.Red)
		box.Position = UDim2.fromScale(0.76, 0.73)
		hand.Position = UDim2.fromScale(0.9, 0.12)
		if not sleep(0.6, alive) then
			return
		end
		UI.Tween(hand, { Position = UDim2.fromScale(0.34, 0.5) }, 0.6, Enum.EasingStyle.Quad)
		if not sleep(0.7, alive) then
			return
		end
		UI.PopIn(button, 0.85, 0.25)
		cash.Text = "$0"
		pop(stage, "STRENGTH UP!", UI.Colors.Green, UDim2.fromScale(0.3, 0.26))
		if not sleep(0.6, alive) then
			return
		end
		tag.Text = "CAN LIFT!"
		UI.TextGradient(tag, UI.Colors.Green)
		UI.Tween(box, { Position = UDim2.fromScale(0.76, 0.6) }, 0.4, Enum.EasingStyle.Back)
		if not sleep(1.6, alive) then
			return
		end
	end
end

Scenes.Key = function(stage: Frame, alive)
	floor(stage)
	local colors = { Color3.fromRGB(230, 90, 120), Color3.fromRGB(90, 150, 230), Color3.fromRGB(255, 200, 60), Color3.fromRGB(120, 200, 120), Color3.fromRGB(170, 100, 255) }
	local spots = { { 0.5, 0.74 }, { 0.36, 0.76 }, { 0.64, 0.76 }, { 0.44, 0.58 }, { 0.57, 0.6 } }
	while alive() do
		local rays = UI.Image({ Image = UI.Asset("Rays") or "", Size = UDim2.fromScale(0.7, 0.9), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.64), ImageColor3 = UI.Colors.Gold, ImageTransparency = 1 }, stage)
		local key = UI.Frame({ Size = UDim2.fromScale(0.16, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.76), BackgroundColor3 = UI.Colors.Gold }, stage)
		UI.New("UICorner", { CornerRadius = UDim.new(0, 8) }, key)
		UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, key)
		local art = UI.Asset("Icon_Key")
		if art then
			UI.Image({ Image = art, Size = UDim2.fromScale(0.8, 0.8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, key)
		else
			UI.Label({ Text = "KEY", TextScaled = true, TextWrapped = false, Size = UDim2.fromScale(0.9, 0.6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, key)
		end
		local junk = {}
		for i, spot in ipairs(spots) do
			table.insert(junk, block(stage, colors[i], UDim2.fromScale(0.2, 0.17), UDim2.fromScale(spot[1], spot[2])))
		end
		if not sleep(0.8, alive) then
			return
		end
		for i = #junk, 1, -1 do
			local j = junk[i]
			local side = (i % 2 == 0) and 1 or -1
			UI.Tween(j, { Position = j.Position + UDim2.fromScale(0.45 * side, -0.25), Rotation = 60 * side, BackgroundTransparency = 1 }, 0.45, Enum.EasingStyle.Quad)
			local stroke = j:FindFirstChild("Edge")
			if stroke then
				UI.Tween(stroke, { Transparency = 1 }, 0.45)
			end
			if not sleep(0.35, alive) then
				return
			end
		end
		UI.Tween(rays, { ImageTransparency = 0.3, Rotation = 90 }, 1.2)
		UI.PopIn(key, 0.6, 0.4)
		pop(stage, "FOUND IT!", UI.Colors.Gold, UDim2.fromScale(0.5, 0.34))
		if not sleep(1.8, alive) then
			return
		end
		destroyAll(junk)
		key:Destroy()
		rays:Destroy()
	end
end

-- Plays one scene in a stage frame; playing another (or Stop) cancels the one before.
local function newPlayer(stage: Frame)
	local token = 0
	local function wipe()
		for _, c in ipairs(stage:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	local self = {}
	function self.Play(name: string)
		token += 1
		local my = token
		wipe()
		local scene = Scenes[name]
		if scene then
			task.spawn(scene, stage, function()
				return token == my and stage.Parent ~= nil
			end)
		end
	end
	function self.Stop()
		token += 1
		wipe()
	end
	return self
end

-- ===== The guide: an instruction line, a pointer for buttons, one for the world, a beam =====

type View = {
	Text: string?,
	Tag: string?,
	Gui: GuiObject?,
	Side: string?,
	Part: BasePart?,
	Lift: number?,
	Beam: Vector3?,
	Instant: boolean?,
}

local line: Frame
local lineLabel: TextLabel
local lineText: string? = nil
local typeToken = 0

local pointerFrame: Frame
local pointerStroke: UIStroke
local pointerArrow: Frame
local pointerTarget: GuiObject? = nil
local pointerSide = "Above"

local worldPointer: BillboardGui
local worldArrow: Frame
local beam: Beam
local beamStart: Attachment
local beamEnd: Attachment
local beamGoal: Vector3? = nil

local finished = false
local roomStep = 0 -- 0 = none; 1 grab, 2 throw, 3 upgrades, 4 find the key, 5 done
local stepToken = 0
local upgradesOpened = false
local upgradeBought = false
local countdown = 0
local welcomeUntil: number? = nil
local grabObject: BasePart? = nil
local nextPick = 0

local function pending(): boolean
	return not finished and player:GetAttribute("TutorialCompleted") == false
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- A white chevron with a black edge, pointing down (turn it with Rotation).
local function chevron(parent: Instance, width: number): Frame
	local holder = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(width, width * 0.75), AnchorPoint = Vector2.new(0.5, 0.5) }, parent)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = UI.Frame({ Size = UDim2.fromScale(0.62, 0.3), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(angle > 0 and 0.34 or 0.66, 0.5), Rotation = angle, BackgroundColor3 = WHITE }, holder)
		UI.New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
		UI.New("UIStroke", { Color = BLACK, Thickness = 2.5 }, bar)
	end
	return holder
end

local function setLine(text: string?, tag: string?, instant: boolean?)
	local full = text and ((tag and string.format('<font color="#%s">%s</font>   ', UI.Colors.Gold:ToHex(), tag) or "") .. text) or nil
	if full == lineText then
		return
	end
	lineText = full
	typeToken += 1
	if not full then
		line.Visible = false
		return
	end
	lineLabel.Text = full
	line.Visible = true
	if instant then
		lineLabel.MaxVisibleGraphemes = -1
		return
	end
	-- Types itself in.
	local my = typeToken
	local total = utf8.len(lineLabel.ContentText) or #full
	lineLabel.MaxVisibleGraphemes = 0
	task.spawn(function()
		local count = 0
		while count < total and typeToken == my do
			count = math.min(total, count + 2)
			lineLabel.MaxVisibleGraphemes = count
			task.wait(0.02)
		end
		if typeToken == my then
			lineLabel.MaxVisibleGraphemes = -1
		end
	end)
end

local function show(view: View?)
	local v: View = view or {}
	setLine(v.Text, v.Tag, v.Instant)
	pointerTarget = v.Gui
	pointerSide = v.Side or "Above"
	if v.Part then
		worldPointer.Adornee = v.Part
		worldPointer.StudsOffset = Vector3.new(0, v.Lift or 3, 0)
		worldPointer.Enabled = true
	else
		worldPointer.Enabled = false
		worldPointer.Adornee = nil
	end
	beamGoal = v.Beam
	beam.Enabled = beamGoal ~= nil
end

-- Whether a button is really on screen (it and every frame above it visible).
local function onScreen(g: GuiObject): boolean
	local node: Instance? = g
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return g.AbsoluteSize.X > 2
end

-- Keeps the white frame on the target button and bounces the arrow at it.
local function placePointer(t: number)
	local target = pointerTarget
	if not target or not onScreen(target) then
		pointerFrame.Visible = false
		pointerArrow.Visible = false
		return
	end
	local pad = 6
	local pos, size = target.AbsolutePosition, target.AbsoluteSize
	pointerFrame.Position = UI.FromAbsolute(pos - Vector2.new(pad, pad))
	pointerFrame.Size = UDim2.fromOffset((size.X + pad * 2) / UI.Scale, (size.Y + pad * 2) / UI.Scale)
	pointerStroke.Transparency = 0.1 + 0.4 * (math.sin(t * 6) + 1) / 2
	pointerFrame.Visible = true
	local bounce = math.abs(math.sin(t * 5)) * 8
	if pointerSide == "Left" then
		pointerArrow.Rotation = -90
		pointerArrow.Position = UI.FromAbsolute(Vector2.new(pos.X - pad, pos.Y + size.Y / 2)) - UDim2.fromOffset(24 + bounce, 0)
	else
		pointerArrow.Rotation = 0
		pointerArrow.Position = UI.FromAbsolute(Vector2.new(pos.X + size.X / 2, pos.Y - pad)) - UDim2.fromOffset(0, 22 + bounce)
	end
	pointerArrow.Visible = true
end

-- A bright pulse running along the lobby beam toward the circle.
local function beamWave(t: number): NumberSequence
	local head = (t * 0.8) % 1
	local keys = { NumberSequenceKeypoint.new(0, 0.6) }
	if head - 0.12 > 0.001 then
		table.insert(keys, NumberSequenceKeypoint.new(head - 0.12, 0.6))
	end
	table.insert(keys, NumberSequenceKeypoint.new(math.clamp(head, 0.002, 0.998), 0))
	if head + 0.12 < 0.999 then
		table.insert(keys, NumberSequenceKeypoint.new(head + 0.12, 0.6))
	end
	table.insert(keys, NumberSequenceKeypoint.new(1, 0.6))
	return NumberSequence.new(keys)
end

local function menuClose(name: string): GuiObject?
	local frame = UI.Layers.Menus:FindFirstChild(name .. "Menu")
	local header = frame and frame:FindFirstChild("Header")
	return header and header:FindFirstChild("Close") :: GuiObject?
end

-- Something light right in front of the player, for the GRAB arrow.
local function pickObject(root: BasePart): BasePart?
	local room = workspace:FindFirstChild("Room" .. (matchState:GetAttribute("RoomNumber") or ""))
	local clutter = room and room:FindFirstChild("Clutter")
	local camera = workspace.CurrentCamera
	if not clutter or not camera then
		return nil
	end
	local look = camera.CFrame.LookVector
	local maxWeight = player:GetAttribute("MaxWeight") or 2
	local best, bestScore = nil, math.huge
	for _, part in ipairs(clutter:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("ObjectId") and not part:GetAttribute("IsChunk") and (part:GetAttribute("Weight") or 1) <= maxWeight then
			local offset = part.Position - root.Position
			local distance = offset.Magnitude
			if distance > 3 and distance < 24 then
				local facing = look:Dot(offset.Unit)
				local score = distance - facing * 12
				if facing > 0.3 and score < bestScore then
					best, bestScore = part, score
				end
			end
		end
	end
	return best
end

local function grabTarget(): BasePart?
	local root = rootPart()
	if not root then
		return nil
	end
	local current = grabObject
	if current and current.Parent and not current:GetAttribute("Deposited") and (current.Position - root.Position).Magnitude < 30 then
		return current
	end
	if os.clock() < nextPick then
		return nil
	end
	nextPick = os.clock() + 1
	grabObject = pickObject(root)
	return grabObject
end

-- The closest circle a party can start in (or join).
local function openCircle(root: BasePart): BasePart?
	local best, bestDistance = nil, math.huge
	for _, zone in ipairs(CollectionService:GetTagged("QueueZone")) do
		if zone:IsA("BasePart") and zone:IsDescendantOf(workspace) then
			local state = zone:GetAttribute("State") or "Empty"
			if state == "Empty" or zone:GetAttribute("Joinable") == true then
				local distance = (zone.Position - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = zone, distance
				end
			end
		end
	end
	return best
end

local function roomView(): View?
	local hud = Controllers.HUDController
	local open = UI.GetOpenMenu()
	if roomStep == 3 then
		-- The first room's first upgrade is free (the server grants FreeUpgrade), so this step
		-- always ends with a real purchase.
		local free = player:GetAttribute("FreeUpgrade") == true
		if open == "Upgrades" then
			if upgradeBought then
				return { Text = "Close the menu to keep going.", Tag = "3/4", Gui = menuClose("Upgrades") }
			end
			return { Text = free and "Tap UPGRADE on STRENGTH - your first one is FREE!" or "Buy STRENGTH when you have enough Cash - it lifts heavier junk.", Tag = "3/4", Gui = Controllers.UpgradeController.GetButton("Strength") }
		elseif open then
			return nil
		end
		return { Text = free and "Nice! Your first upgrade is FREE - open UPGRADES." or "Nice! Spend your Cash on UPGRADES to get stronger.", Tag = "3/4", Gui = hud.Buttons.Upgrades, Side = "Left" }
	end
	if open then
		return nil
	end
	-- Touch: the GRAB / THROW button is part of the lesson too.
	local action = UI.IsTouch() and hud.GetMobileActionButton() or nil
	if roomStep == 1 then
		local object = grabTarget()
		return { Text = Steps[1].Text(), Tag = "1/4", Gui = action, Part = object, Lift = object and math.max(object.Size.X, object.Size.Y, object.Size.Z) / 2 + 1.5 }
	elseif roomStep == 2 then
		return { Text = platformText("Aim at the bin with the gold x2 and RELEASE to throw!", "Aim at the bin with the gold x2 and tap THROW!", "Aim at the bin with the gold x2 and RELEASE R2!"), Tag = "2/4", Gui = action }
	elseif roomStep == 4 then
		return { Text = string.format("Now find the %s under the junk! Stuck? Use HINT.", matchState:GetAttribute("TargetName") or "Golden Key"), Tag = "4/4", Gui = hud.Buttons.Hint, Side = "Left" }
	elseif roomStep == 5 then
		return { Text = string.format("That's it - have fun! (%d)", countdown), Instant = countdown < 3 }
	end
	return nil
end

local function lobbyView(): View?
	local root = rootPart()
	if not root or UI.GetOpenMenu() then
		return nil
	end
	welcomeUntil = welcomeUntil or os.clock() + 5
	if os.clock() < welcomeUntil then
		return { Text = "Welcome! Dig through a messy room to find the hidden Golden Key." }
	end
	if (player:GetAttribute("QueueId") or "") ~= "" then
		local create = Controllers.RoomSelectController.GetCreateButton()
		if create then
			return { Text = platformText("Pick a room, then press CREATE!", "Pick a room, then tap CREATE!", "Pick a room, then press CREATE!"), Gui = create, Side = "Left" }
		end
		return { Text = "Get ready - your room is about to start!" }
	end
	local circle = openCircle(root)
	if not circle then
		return { Text = "Every circle is busy - one opens up in a moment!" }
	end
	-- The arrow hovers over the glowing disc, under the circle's own sign.
	return { Text = "Walk into a glowing circle to start a room!", Part = circle, Lift = 1.8, Beam = Vector3.new(circle.Position.X, root.Position.Y - 2.6, circle.Position.Z) }
end

-- Where the line sits (top-layer units): just under the top panel; up by the top edge while a
-- menu or the party panel is open (it draws over them); under the clue banner while one shows.
local function lineY(): number
	local safeTop = UI.FromAbsolute(UI.Layers.HUD.AbsolutePosition).Y.Offset
	if UI.GetOpenMenu() or Controllers.RoomSelectController.GetCreateButton() then
		return safeTop + 6
	end
	local below = safeTop + Controllers.HUDController.TopClear() + 10
	if Controllers.HintController.IsClueShowing() then
		return below + CLUE_BANNER_HEIGHT + 8
	end
	return below
end

local function update()
	if not line then
		return
	end
	if not pending() then
		show(nil)
	elseif player:GetAttribute("InMatch") then
		show(roomStep > 0 and roomView() or nil)
	else
		show(lobbyView())
	end
end

local function setRoomStep(n: number)
	roomStep = n
	stepToken += 1
	local my = stepToken
	upgradesOpened, upgradeBought = false, false
	if n == 3 then
		-- Moves on by itself if the menu is never opened.
		task.delay(20, function()
			if stepToken == my and not upgradesOpened then
				setRoomStep(4)
			end
		end)
	elseif n == 4 then
		task.delay(7, function()
			if stepToken == my then
				setRoomStep(5)
			end
		end)
	elseif n == 5 then
		task.spawn(function()
			for i = 3, 1, -1 do
				if stepToken ~= my then
					return
				end
				countdown = i
				update()
				task.wait(1)
			end
			if stepToken == my then
				TutorialController.Finish()
			end
		end)
	end
	update()
end

function TutorialController.Finish()
	if finished then
		return
	end
	finished = true
	roomStep = 0
	stepToken += 1
	show(nil)
	Remotes.Event("TutorialComplete"):FireServer()
end

-- ===== Anywhere: HOW TO PLAY, the lessons as an auto-playing video =====

local video = nil

local function buildVideo()
	local menu = UI.Menu("HowTo", "HOW TO PLAY", UDim2.fromOffset(640, 470), UI.Colors.Cyan)
	local stage = UI.Frame({ Name = "Stage", Size = UDim2.fromOffset(400, 226), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), BackgroundColor3 = STAGE_COLOR, ClipsDescendants = true }, menu.Content)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 12) }, stage)
	UI.New("UIStroke", { Color = BLACK, Thickness = 2.5 }, stage)
	local title = UI.Label({ Text = "", TextSize = 24, TextWrapped = false, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 234) }, menu.Content)
	UI.TextGradient(title, UI.Colors.Cyan)
	local text = UI.Label({ Text = "", TextSize = 17, Font = UI.FontBody, Size = UDim2.new(1, -40, 0, 50), Position = UDim2.fromOffset(20, 266) }, menu.Content)
	local dotsRow = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 322) }, menu.Content)
	UI.ListLayout(dotsRow, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	local dots = {}
	for i = 1, #Steps do
		local d = UI.Frame({ Size = UDim2.fromOffset(12, 12), BackgroundColor3 = UI.Colors.Locked, LayoutOrder = i }, dotsRow)
		UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		dots[i] = d
	end
	local back = UI.Button({ Text = "BACK", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(120, 44), Position = UDim2.new(0, 20, 1, -46), TextSize = 18 }, menu.Content)
	local nextButton = UI.Button({ Text = "NEXT", Color = UI.Colors.Green, Size = UDim2.fromOffset(120, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 1, -46), TextSize = 18 }, menu.Content)
	local demo = newPlayer(stage)
	local index, token = 1, 0

	local function show(i: number)
		index = math.clamp(i, 1, #Steps)
		local def = Steps[index]
		title.Text = string.format("%d.  %s", index, def.Title)
		text.Text = def.Text()
		demo.Play(def.Scene)
		for n, d in ipairs(dots) do
			d.BackgroundColor3 = n == index and UI.Colors.Cyan or UI.Colors.Locked
		end
		UI.SetButtonEnabled(back, index > 1)
		nextButton.Text = index < #Steps and "NEXT" or "DONE"
		-- Plays on by itself like a video; any press restarts the timer.
		token += 1
		local my = token
		task.delay(6.5, function()
			if token == my and menu.IsOpen() and index < #Steps then
				show(index + 1)
			end
		end)
	end

	back.Activated:Connect(function()
		if index > 1 then
			show(index - 1)
		end
	end)
	nextButton.Activated:Connect(function()
		if index < #Steps then
			show(index + 1)
		else
			menu.Close()
		end
	end)
	menu.OnOpen(function()
		show(1)
	end)
	menu.OnClose(function()
		token += 1
		demo.Stop()
	end)
	return { Menu = menu }
end

function TutorialController.PlayVideo()
	video = video or buildVideo()
	video.Menu.Open()
end

function TutorialController.Init()
	-- The instruction line (types itself in) with a small SKIP at its end. On the top layer so
	-- it stays readable over the party panel and the Upgrades menu.
	line = UI.Frame({ Name = "TutorialLine", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, Visible = false }, UI.Layers.Top)
	UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, line)
	UI.New("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 5) }, line)
	UI.ListLayout(line, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	lineLabel = UI.Label({ Text = "", RichText = true, TextSize = 19, TextWrapped = false, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36), LayoutOrder = 1 }, line)
	local skip = UI.Button({ Name = "SkipTutorial", Text = "SKIP", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(58, 26), TextSize = 13, LayoutOrder = 2 }, line)
	skip.Activated:Connect(TutorialController.Finish)

	-- Button pointer: a white frame around the button and a bouncing arrow, over everything.
	pointerFrame = UI.Frame({ Name = "TutorialPointer", BackgroundTransparency = 1, Visible = false }, UI.Layers.Top)
	UI.New("UICorner", { CornerRadius = UDim.new(0, 14) }, pointerFrame)
	pointerStroke = UI.New("UIStroke", { Color = WHITE, Thickness = 3 }, pointerFrame) :: UIStroke
	pointerArrow = chevron(UI.Layers.Top, 44)
	pointerArrow.Visible = false

	-- World pointer: the same arrow over a thing in the world, seen through walls.
	worldPointer = Instance.new("BillboardGui")
	worldPointer.Name = "TutorialWorldPointer"
	worldPointer.Size = UDim2.fromOffset(64, 64)
	worldPointer.AlwaysOnTop = true
	worldPointer.LightInfluence = 0
	worldPointer.MaxDistance = 400
	worldPointer.ResetOnSpawn = false
	worldPointer.Enabled = false
	worldPointer.Parent = player:WaitForChild("PlayerGui")
	worldArrow = chevron(worldPointer, 52)
	worldArrow.Position = UDim2.fromScale(0.5, 0.5)

	-- Lobby guide beam, from your feet to the circle.
	beamStart = Instance.new("Attachment")
	beamStart.Name = "TutorialBeamStart"
	beamStart.Position = Vector3.new(0, -2.6, 0)
	beamEnd = Instance.new("Attachment")
	beamEnd.Name = "TutorialBeamEnd"
	beamEnd.Parent = workspace.Terrain
	beam = Instance.new("Beam")
	beam.Name = "TutorialBeam"
	beam.Attachment0 = beamStart
	beam.Attachment1 = beamEnd
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(WHITE, UI.Colors.Cyan)
	beam.Enabled = false
	beam.Parent = workspace.Terrain

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName)
		if eventName == "Started" and pending() then
			setRoomStep(1)
		elseif eventName == "TargetFound" and roomStep > 0 then
			TutorialController.Finish()
		elseif eventName == "ReturnedToLobby" then
			roomStep = 0
			stepToken += 1
		end
	end)

	player:GetAttributeChangedSignal("HeldObjectId"):Connect(function()
		local holding = (player:GetAttribute("HeldObjectId") or "") ~= ""
		if holding and roomStep == 1 then
			setRoomStep(2)
		elseif holding and roomStep == 2 then
			stepToken += 1 -- grabbed again: cancels the fall-back below
		elseif not holding and roomStep == 2 then
			-- Missed the bins? Back to GRAB, unless a deposit comes in first.
			local my = stepToken
			task.delay(1.8, function()
				if stepToken == my and roomStep == 2 then
					setRoomStep(1)
				end
			end)
		end
	end)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if name == "Deposit" and type(payload) == "table" and payload.Mine and (roomStep == 1 or roomStep == 2) then
			setRoomStep(3)
		elseif name == "Upgrade" and roomStep == 3 then
			upgradeBought = true
			update()
		end
	end)

	UI.OnMenuChanged(function(name, action)
		if roomStep == 3 and name == "Upgrades" then
			if action == "open" then
				upgradesOpened = true
			elseif upgradesOpened then
				setRoomStep(4)
				return
			end
		end
		update()
	end)
end

function TutorialController.Start()
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			update()
		end
		local t = os.clock()
		placePointer(t)
		local y = lineY()
		if line.Position.Y.Offset ~= y then
			line.Position = UDim2.new(0.5, 0, 0, y)
		end
		if worldPointer.Enabled then
			worldArrow.Position = UDim2.new(0.5, 0, 0.5, -math.abs(math.sin(t * 5)) * 10)
		end
		if beam.Enabled and beamGoal then
			local root = rootPart()
			if root and beamStart.Parent ~= root then
				beamStart.Parent = root
			end
			beamEnd.WorldPosition = beamGoal
			beam.Transparency = beamWave(t)
		end
	end)
	for _, name in ipairs({ "TutorialCompleted", "QueueId", "InMatch" }) do
		player:GetAttributeChangedSignal(name):Connect(update)
	end
end

return TutorialController
