--[[
	Client UI toolkit: one ScreenGui with layered containers, styled element constructors,
	a menu manager (one menu open at a time) and responsive scaling for phone/desktop.

	The look (see UIConfig): bold white Gotham text with black outlines, "studded 3D" surfaces
	(gradient face over a darker lip, light inner edge, studs pattern, soft sheen), dark glassy
	panels with black borders. Buttons spring on hover/press with a ripple; menus slide up over a
	dimmed, blurred world. Everything animated respects Reduce VFX.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UI = {}
UI.Colors = UIConfig.Colors
UI.Variants = UIConfig.Variants
UI.Images = UIConfig.Images
UI.Font = UIConfig.Font
UI.FontBody = UIConfig.FontBody

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

local gui = Instance.new("ScreenGui")
gui.Name = "MainUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
gui.Parent = playerGui
UI.Gui = gui

local scale = Instance.new("UIScale")
scale.Parent = gui
UI.ScaleObject = scale

UI.Layers = {}
for i, name in ipairs({ "World", "HUD", "Menus", "Overlay", "Notify", "Top" }) do
	local layer = Instance.new("Frame")
	layer.Name = name
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = i * 10
	layer.Parent = gui
	UI.Layers[name] = layer
end
-- HUD, menus and notifications live in the safe area under the Roblox top bar (its buttons would
-- cover anything above it). World, Overlay and Top stay full screen for dims, flashes and fades.
local SAFE_LAYERS = { UI.Layers.HUD, UI.Layers.Menus, UI.Layers.Notify }
UI.SafeTop = 0

local function reduceMotion(): boolean
	return player:GetAttribute("Setting_ReduceVFX") == true
end

local function luminance(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- ===== Studio-authored art (added in Studio, no code change needed) =====
-- ReplicatedStorage.GameAssets.UIImages is a Configuration whose string attributes map a UI
-- key to an image ("rbxassetid://123"): icons, the Glow blob, Rays, Logo... Missing keys fall
-- back to text glyphs, so the game always works without art.
local imageRegistry: Instance? = nil
local function registry(): Instance?
	if not imageRegistry then
		local folder = ReplicatedStorage:FindFirstChild("GameAssets")
		imageRegistry = folder and folder:FindFirstChild("UIImages")
	end
	return imageRegistry
end

function UI.Asset(key: string): string?
	local reg = registry()
	local value = reg and reg:GetAttribute(key)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function sliceOf(key: string): Rect
	local reg = registry()
	local rect = reg and reg:GetAttribute(key .. "_Slice")
	return typeof(rect) == "Rect" and rect or Rect.new(64, 64, 192, 192)
end

-- A tinted 9-slice skin from the registry (kept for older art; the core elements no longer
-- need it).
function UI.Skin(inst: GuiObject, key: string): ImageLabel?
	local image = UI.Asset(key)
	if not image then
		return nil
	end
	local skin = UI.New("ImageLabel", {
		Name = "Skin",
		BackgroundTransparency = 1,
		Image = image,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = sliceOf(key),
		ImageColor3 = inst.BackgroundColor3,
		ImageTransparency = inst.BackgroundTransparency,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	}, inst) :: ImageLabel
	inst.BackgroundTransparency = 1
	return skin
end

-- An icon image when the art exists, otherwise the fallback text glyph.
function UI.Icon(parent: Instance, key: string, fallbackText: string, labelProps: { [string]: any }?): GuiObject
	local image = UI.Asset(key)
	if image then
		return UI.New("ImageLabel", {
			Name = key,
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(1, -4, 1, -4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		}, parent) :: ImageLabel
	end
	local props = labelProps and table.clone(labelProps) or {}
	props.Text = fallbackText
	props.Size = props.Size or UDim2.fromScale(1, 1)
	return UI.Label(props, parent)
end

function UI.IsTouch(): boolean
	-- Studio-only: set the workspace attribute DevForceTouch to preview the phone layout.
	if workspace:GetAttribute("DevForceTouch") == true and game:GetService("RunService"):IsStudio() then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

function UI.IsGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local s
	if UI.IsTouch() then
		s = math.clamp(viewport.Y / 560, 0.62, 1.15)
	else
		s = math.clamp(math.min(viewport.Y / 760, viewport.X / 1300), 0.62, 1.25)
	end
	-- Studio-only: workspace.DevForceScale emulates a phone's scale on a desktop viewport.
	local forced = workspace:GetAttribute("DevForceScale")
	if type(forced) == "number" and game:GetService("RunService"):IsStudio() then
		s = forced
	end
	scale.Scale = s
	UI.Scale = s
	-- The top-bar inset is in screen pixels; layer offsets are in scaled units.
	UI.SafeTop = GuiService:GetGuiInset().Y / s
	for _, layer in ipairs(SAFE_LAYERS) do
		layer.Position = UDim2.fromOffset(0, UI.SafeTop)
		layer.Size = UDim2.new(1, 0, 1, -UI.SafeTop)
	end
end
UI.Scale = 1
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		updateScale()
	end
end)
-- The top bar can finish laying out after this module loads.
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(updateScale)
end)
task.delay(2, updateScale)
workspace:GetAttributeChangedSignal("DevForceScale"):Connect(updateScale)

-- ===== Primitive constructors =====

function UI.New(className: string, props: { [string]: any }?, parent: Instance?): Instance
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Studded surfaces built by this module, so colour/corner changes can restyle every layer.
type Surface = { Base: Frame, Face: Frame, Gradient: UIGradient, Edge: UIStroke, Corners: { UICorner } }
local surfaces: { [Instance]: Surface } = setmetatable({}, { __mode = "k" }) :: any

function UI.Corner(inst: GuiObject, radius: number?): UICorner
	local r = UDim.new(0, radius or UIConfig.Corner)
	local surface = surfaces[inst]
	if surface then
		for _, c in ipairs(surface.Corners) do
			c.CornerRadius = r
		end
		return surface.Corners[1]
	end
	local corner = inst:FindFirstChildOfClass("UICorner") or UI.New("UICorner", {}, inst)
	;(corner :: UICorner).CornerRadius = r
	return corner :: UICorner
end

-- Text gets an outline, frames a border. Calling it again on the same element restyles the
-- existing stroke instead of stacking a second one; on a studded surface it styles the rim.
function UI.Stroke(inst: GuiObject, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local target = surfaces[inst] and surfaces[inst].Base or inst
	local isText = target:IsA("TextLabel") or target:IsA("TextBox")
	local name = isText and "Outline" or "Border"
	local stroke = target:FindFirstChild(name)
	if not (stroke and stroke:IsA("UIStroke")) then
		stroke = UI.New("UIStroke", {
			Name = name,
			ApplyStrokeMode = isText and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Round,
		}, target)
	end
	local s = stroke :: UIStroke
	s.Color = color or UI.Colors.Stroke
	s.Thickness = thickness or UIConfig.StrokeThickness
	s.Transparency = transparency or 0
	if isText then
		-- The outline fades with its text (tweened TextTransparency never leaves a ghost outline).
		local label = target :: TextLabel
		label:SetAttribute("OutlineBase", s.Transparency)
		if not label:GetAttribute("OutlineBound") then
			label:SetAttribute("OutlineBound", true)
			label:GetPropertyChangedSignal("TextTransparency"):Connect(function()
				local base = label:GetAttribute("OutlineBase") or 0
				s.Transparency = base + (1 - base) * label.TextTransparency
			end)
		end
		s.Transparency = s.Transparency + (1 - s.Transparency) * label.TextTransparency
	end
	return s
end

function UI.Padding(inst: GuiObject, all: number | { number }): UIPadding
	local l, r, t, b
	if type(all) == "number" then
		l, r, t, b = all, all, all, all
	else
		l, r, t, b = all[1], all[2] or all[1], all[3] or all[1], all[4] or all[3] or all[1]
	end
	return UI.New("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r),
		PaddingTop = UDim.new(0, t),
		PaddingBottom = UDim.new(0, b),
	}, inst) :: UIPadding
end

function UI.ListLayout(parent: GuiObject, direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UI.New("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent) :: UIListLayout
end

function UI.GridLayout(parent: GuiObject, cellSize: UDim2, padding: number?): UIGridLayout
	return UI.New("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(padding or 8, padding or 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent) :: UIGridLayout
end

function UI.Frame(props: { [string]: any }?, parent: Instance?): Frame
	local base = {
		BackgroundColor3 = UI.Colors.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}
	if props then
		for k, v in pairs(props) do
			base[k] = v
		end
	end
	return UI.New("Frame", base, parent) :: Frame
end

-- A vertical colour gradient on any element (for text: the text itself).
function UI.Gradient(inst: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = inst:FindFirstChild("Gradient") or UI.New("UIGradient", { Name = "Gradient" }, inst)
	;(g :: UIGradient).Color = ColorSequence.new(top, bottom)
	;(g :: UIGradient).Rotation = rotation or 90
	return g :: UIGradient
end

-- Gradient text in the colour family of `color` (e.g. cash: lime -> green).
function UI.TextGradient(label: TextLabel, color: Color3): UIGradient
	local v = UI.VariantFor(color)
	return UI.Gradient(label, v.Top:Lerp(WHITE, 0.25), v.Bottom)
end

-- Dark glassy panel: the given colour shaded top -> bottom, black border, rounded.
function UI.Panel(props: { [string]: any }?, parent: Instance?): Frame
	local frame = UI.Frame(props, parent)
	UI.Corner(frame)
	UI.Stroke(frame, BLACK, UIConfig.StrokeThickness)
	UI.Gradient(frame, WHITE, Color3.fromRGB(150, 152, 168))
	return frame
end

-- Display-font labels get a black outline when their text is light (the pack's text look).
-- Pass NoOutline = true to skip it.
function UI.Label(props: { [string]: any }?, parent: Instance?): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = UI.Font,
		TextColor3 = UI.Colors.Text,
		TextSize = 20,
		Text = "",
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
	}
	local noOutline = false
	if props then
		for k, v in pairs(props) do
			if k == "NoOutline" then
				noOutline = v
			else
				base[k] = v
			end
		end
	end
	local label = UI.New("TextLabel", base, parent) :: TextLabel
	if not noOutline and label.Font == UI.Font and luminance(label.TextColor3) > 0.45 then
		UI.Stroke(label, BLACK, label.TextScaled and 2 or math.clamp(label.TextSize * 0.1, 1.5, 4), 0)
	end
	return label
end

function UI.Image(props: { [string]: any }?, parent: Instance?): ImageLabel
	local base = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
	}
	if props then
		for k, v in pairs(props) do
			base[k] = v
		end
	end
	return UI.New("ImageLabel", base, parent) :: ImageLabel
end

function UI.Tween(inst: Instance, props: { [string]: any }, time: number?, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- ===== Studded 3D surfaces =====

local derivedVariants: { [string]: any } = {}
local variantByColor: { [string]: any } = {}
local function colorKey(c: Color3): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
for _, v in pairs(UIConfig.Variants) do
	for _, c in ipairs(v.Match or {}) do
		variantByColor[colorKey(c)] = v
	end
end

-- The studded look for a UI colour (unknown colours get a look derived from them).
function UI.VariantFor(color: Color3)
	local key = colorKey(color)
	local v = variantByColor[key] or derivedVariants[key]
	if not v then
		v = { Top = color:Lerp(WHITE, 0.2), Bottom = color, Base = color:Lerp(BLACK, 0.5), Edge = color:Lerp(WHITE, 0.45) }
		derivedVariants[key] = v
	end
	return v
end

local function applyVariant(s: Surface, v)
	s.Base.BackgroundColor3 = v.Base
	s.Gradient.Color = ColorSequence.new(v.Top, v.Bottom)
	s.Edge.Color = v.Edge
end

-- A darker base that shows as a lip under a gradient face with a light inner edge, a studs
-- pattern and a soft light-rays sheen. Layers sit first in `host`, so everything added later
-- draws on top.
local function buildSurface(host: GuiObject, radius: number, v, lip: number?): Surface
	local z = host.ZIndex
	local corners = {}
	local function corner(parent: Instance)
		local c = UI.New("UICorner", { CornerRadius = UDim.new(0, radius) }, parent) :: UICorner
		table.insert(corners, c)
	end
	local base = UI.New("Frame", { Name = "Base", BorderSizePixel = 0, BackgroundColor3 = v.Base, Size = UDim2.fromScale(1, 1), ZIndex = z }, host) :: Frame
	corner(base)
	UI.New("UIStroke", { Name = "Border", Color = BLACK, Thickness = UIConfig.StrokeThickness, LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, base)
	local face = UI.New("Frame", { Name = "Face", BorderSizePixel = 0, BackgroundColor3 = WHITE, Size = UDim2.new(1, 0, 1 - (lip or 0.1), 0), ZIndex = z }, host) :: Frame
	corner(face)
	local gradient = UI.New("UIGradient", { Name = "Gradient", Rotation = 90, Color = ColorSequence.new(v.Top, v.Bottom) }, face) :: UIGradient
	local edge = UI.New("UIStroke", { Name = "Edge", Color = v.Edge, Thickness = 1.5, Transparency = 0.15, LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, face) :: UIStroke
	local studs = UI.New("ImageLabel", { Name = "Studs", BackgroundTransparency = 1, Image = UIConfig.Images.Studs, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(26, 26), ImageTransparency = 0.62, Size = UDim2.fromScale(1, 1), ZIndex = z }, face)
	corner(studs)
	local rays = UI.New("ImageLabel", { Name = "Rays", BackgroundTransparency = 1, Image = UIConfig.Images.Rays, ScaleType = Enum.ScaleType.Stretch, ImageTransparency = 0.55, Size = UDim2.fromScale(1, 1), ZIndex = z }, face)
	corner(rays)
	local s: Surface = { Base = base, Face = face, Gradient = gradient, Edge = edge, Corners = corners }
	surfaces[host] = s
	return s
end

-- A non-interactive studded tile (header bars, badges, capsules, cards).
function UI.Surface3D(props: { [string]: any }?, parent: Instance?, color: Color3?, radius: number?, lip: number?): Frame
	local p = props and table.clone(props) or {}
	p.BackgroundTransparency = 1
	local frame = UI.Frame(p, parent)
	buildSurface(frame, radius or UIConfig.Corner, UI.VariantFor(color or UI.Colors.Gold), lip)
	return frame
end

function UI.SetSurfaceColor(inst: GuiObject, color: Color3)
	local s = surfaces[inst]
	if s then
		applyVariant(s, UI.VariantFor(color))
	end
end

-- A section title on a black band that fades out at both ends.
function UI.SectionTitle(parent: Instance, text: string, props: { [string]: any }?): Frame
	local p = { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = BLACK, BackgroundTransparency = 0 }
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	local band = UI.Frame(p, parent)
	UI.New("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) }),
	}, band)
	UI.Label({ Text = text, TextSize = 20, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0) }, band)
	return band
end

-- ===== Blur behind menus =====
local blur: BlurEffect? = nil
local blurUsers = 0
function UI.Blur(on: boolean)
	blurUsers = math.max(0, blurUsers + (on and 1 or -1))
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "UIBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	local target = (blurUsers > 0 and not reduceMotion()) and 14 or 0
	UI.Tween(blur :: BlurEffect, { Size = target }, target > 0 and 0.25 or 0.2)
end

-- ===== Buttons =====

local clickSoundHook: ((string) -> ())? = nil
function UI.SetClickSound(fn: (string) -> ())
	clickSoundHook = fn
end

-- A soft white circle that grows from the press point and fades (clipped to the face).
function UI.Ripple(button: GuiObject, at: Vector3 | Vector2 | nil)
	if reduceMotion() then
		return
	end
	local host = (surfaces[button] and surfaces[button].Face) or button
	local holder = host:FindFirstChild("RippleHolder")
	if not holder then
		holder = UI.New("Frame", { Name = "RippleHolder", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.fromScale(1, 1), ZIndex = host.ZIndex }, host)
	end
	local absPos, absSize = host.AbsolutePosition, host.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then
		return
	end
	local rx, ry = 0.5, 0.5
	if at then
		rx = math.clamp((at.X - absPos.X) / absSize.X, 0, 1)
		ry = math.clamp((at.Y - absPos.Y) / absSize.Y, 0, 1)
	end
	local ripple = UI.New("Frame", { Name = "Ripple", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, BorderSizePixel = 0, Position = UDim2.fromScale(rx, ry), Size = UDim2.fromOffset(0, 0), ZIndex = host.ZIndex }, holder)
	UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, ripple)
	local d = math.max(absSize.X, absSize.Y) * 1.6 / UI.Scale
	UI.Tween(ripple, { Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 }, 0.45).Completed:Once(function()
		ripple:Destroy()
	end)
end

-- Hover lifts, press squashes (with a ripple), release springs back; a small rotation kick
-- and the click sound on activation.
function UI.PressEffect(button: GuiButton)
	local scaleObj = button:FindFirstChild("PressScale") or UI.New("UIScale", { Name = "PressScale" }, button)
	local hovering, pressed = false, false
	local function to(target: number, info: TweenInfo)
		TweenService:Create(scaleObj, info, { Scale = target }):Play()
	end
	local hoverInfo = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local leaveInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local pressInfo = TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local releaseInfo = TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		hovering = true
		if not pressed and button.Active then
			to(1.06, hoverInfo)
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		if not pressed then
			to(1, leaveInfo)
		end
	end)
	button.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and button.Active then
			pressed = true
			to(0.9, pressInfo)
			UI.Ripple(button, input.Position)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pressed = false
			to(hovering and button.Active and 1.06 or 1, releaseInfo)
		end
	end)
	button.Activated:Connect(function()
		if clickSoundHook then
			clickSoundHook("UIClick")
		end
		if not reduceMotion() and button.Active then
			local kick = TweenService:Create(button, TweenInfo.new(0.06, Enum.EasingStyle.Sine), { Rotation = math.random(0, 1) == 0 and -3 or 3 })
			kick:Play()
			kick.Completed:Once(function()
				TweenService:Create(button, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { Rotation = 0 }):Play()
			end)
		end
	end)
end

-- ===== Motion & glow =====
-- One RenderStepped loop drives every shine sweep and pulse. Everything is skipped while the
-- player has Reduce VFX on.

type Shine = { Overlay: GuiObject, Gradient: UIGradient, Period: number, Phase: number, Owner: GuiObject }
type Pulse = { Scale: UIScale, Amount: number, Speed: number, Phase: number, Owner: GuiObject }
local shines: { Shine } = {}
local pulses: { Pulse } = {}

-- Soft coloured glow around an element: the "Glow" image (a soft white radial blob) when it
-- exists, else a soft stroke. Sits under the element's content.
function UI.Glow(inst: GuiObject, color: Color3, spread: number?, transparency: number?): GuiObject | UIStroke
	local image = UI.Asset("Glow")
	local s = spread or 20
	if image then
		return UI.New("ImageLabel", {
			Name = "Glow",
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = color,
			ImageTransparency = transparency or 0.4,
			Size = UDim2.new(1, s * 2, 1, s * 2),
			Position = UDim2.fromOffset(-s, -s),
			ZIndex = -1,
		}, inst) :: ImageLabel
	end
	return UI.New("UIStroke", {
		Name = "Glow",
		Color = color,
		Thickness = math.max(2, s / 7),
		Transparency = transparency or 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst) :: UIStroke
end

-- A light streak that sweeps across the element (its studded face when it has one) every
-- `period` seconds.
function UI.Shine(inst: GuiObject, period: number?): GuiObject
	local host = (surfaces[inst] and surfaces[inst].Face) or inst
	local overlay = UI.New("Frame", { Name = "Shine", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = host.ZIndex }) :: Frame
	local corner = host:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = overlay
	end
	overlay.Parent = host
	local gradient = UI.New("UIGradient", {
		Rotation = 20,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1.2, 0),
	}, overlay) :: UIGradient
	table.insert(shines, { Overlay = overlay, Gradient = gradient, Period = period or 3.5, Phase = math.random() * 3, Owner = inst })
	return overlay
end

-- Gentle breathing scale (layout-safe: uses a UIScale).
function UI.Pulse(inst: GuiObject, amount: number?, speed: number?)
	local scaleObj = inst:FindFirstChild("PulseScale") or UI.New("UIScale", { Name = "PulseScale" }, inst)
	table.insert(pulses, { Scale = scaleObj :: UIScale, Amount = amount or 0.04, Speed = speed or 2, Phase = math.random() * 6, Owner = inst })
end

function UI.StopPulse(inst: GuiObject)
	for i = #pulses, 1, -1 do
		if pulses[i].Owner == inst then
			pulses[i].Scale.Scale = 1
			table.remove(pulses, i)
		end
	end
end

-- Pop an element in with a springy scale.
function UI.PopIn(inst: GuiObject, from: number?, time: number?)
	local scaleObj = inst:FindFirstChild("PopScale") or UI.New("UIScale", { Name = "PopScale" }, inst)
	local target = inst:GetAttribute("FitScale") or 1
	;(scaleObj :: UIScale).Scale = (from or 0.6) * target
	UI.Tween(scaleObj, { Scale = target }, time or 0.35, Enum.EasingStyle.Back)
end

-- Roll a number label from one value to another.
local countTokens: { [Instance]: number } = {}
function UI.CountUp(label: TextLabel, from: number, to: number, format: (number) -> string, time: number?)
	local token = (countTokens[label] or 0) + 1
	countTokens[label] = token
	local duration = reduceMotion() and 0 or (time or 0.4)
	if duration <= 0 or from == to then
		label.Text = format(to)
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while countTokens[label] == token do
			local a = math.min(1, (os.clock() - t0) / duration)
			local eased = 1 - (1 - a) ^ 3
			label.Text = format(math.floor(from + (to - from) * eased + 0.5))
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

game:GetService("RunService").RenderStepped:Connect(function()
	local t = os.clock()
	local still = reduceMotion()
	for i = #shines, 1, -1 do
		local s = shines[i]
		if not s.Overlay.Parent or not s.Owner.Parent then
			table.remove(shines, i)
		else
			local owner = s.Owner :: any
			local disabled = owner:IsA("GuiButton") and not owner.Active
			s.Overlay.Visible = not still and not disabled
			local cycle = ((t + s.Phase) % s.Period) / s.Period
			-- Sweep during the first 40% of each period, rest off-element the remainder.
			s.Gradient.Offset = Vector2.new(-1.2 + math.min(cycle / 0.4, 1) * 2.4, 0)
		end
	end
	for i = #pulses, 1, -1 do
		local p = pulses[i]
		if not p.Owner.Parent then
			table.remove(pulses, i)
		else
			p.Scale.Scale = still and 1 or 1 + math.sin(t * p.Speed + p.Phase) * p.Amount
		end
	end
end)

local function restyleButton(button: TextButton)
	local s = surfaces[button]
	if s then
		local disabled = button:GetAttribute("Disabled") == true
		applyVariant(s, disabled and UIConfig.Variants.Locked or UI.VariantFor(button.BackgroundColor3))
	end
end

-- A studded 3D button. Its API is a normal TextButton: set Text / TextSize / TextColor3 /
-- BackgroundColor3 and the visuals follow (the text is drawn on the face by a child label).
function UI.Button(props: { [string]: any }?, parent: Instance?): TextButton
	local color = props and props.Color or UI.Colors.Green
	local radius = props and props.Corner or UIConfig.CornerSmall
	local base = {
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = UI.Font,
		TextColor3 = UI.Colors.Text,
		TextSize = 22,
		Text = "BUTTON",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(160, UIConfig.MinButtonSize),
		TextWrapped = true,
	}
	if props then
		for k, v in pairs(props) do
			if k ~= "Color" and k ~= "Corner" and k ~= "Shine" then
				base[k] = v
			end
		end
	end
	base.BackgroundTransparency = 1
	local button = UI.New("TextButton", base, parent) :: TextButton
	buildSurface(button, radius, UI.VariantFor(color))

	local label = UI.New("TextLabel", { Name = "Label", BackgroundTransparency = 1, Size = UDim2.new(1, -10, 0.9, 0), Position = UDim2.fromOffset(5, 0), ZIndex = button.ZIndex }, button) :: TextLabel
	local outline = UI.Stroke(label, BLACK, 2, 0)
	local function sync()
		label.Text = button.Text
		label.RichText = button.RichText
		label.Font = button.Font
		label.TextSize = button.TextSize
		label.TextScaled = button.TextScaled
		label.TextColor3 = button.TextColor3
		label.TextWrapped = button.TextWrapped
		label.TextXAlignment = button.TextXAlignment
		label.TextYAlignment = button.TextYAlignment
		outline.Thickness = button.TextScaled and 2 or math.clamp(button.TextSize * 0.1, 1.5, 4)
		outline.Enabled = luminance(button.TextColor3) > 0.45
		if button.TextTransparency < 1 then
			label.TextTransparency = button.TextTransparency
			outline.Transparency = button.TextTransparency
			button.TextTransparency = 1
		end
	end
	sync()
	for _, prop in ipairs({ "Text", "RichText", "Font", "TextSize", "TextScaled", "TextColor3", "TextTransparency", "TextWrapped", "TextXAlignment", "TextYAlignment" }) do
		button:GetPropertyChangedSignal(prop):Connect(sync)
	end
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		restyleButton(button)
	end)
	button:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if button.BackgroundTransparency < 1 then
			button.BackgroundTransparency = 1
		end
	end)

	UI.PressEffect(button)
	-- Call-to-action buttons get a periodic light sweep.
	if props and props.Shine then
		UI.Shine(button, type(props.Shine) == "number" and props.Shine or 3.2)
	end
	return button
end

function UI.SetButtonEnabled(button: TextButton, enabled: boolean, disabledText: string?)
	button.Active = enabled
	button.AutoButtonColor = false
	button:SetAttribute("Disabled", not enabled)
	restyleButton(button)
	button.TextTransparency = enabled and 0 or 0.3
	if not enabled and disabledText then
		button.Text = disabledText
	end
end

-- On/off switch used by Settings: a studded ON (green) / OFF (grey) button.
function UI.Toggle(parent: Instance, labelText: string, initial: boolean, onChange: (boolean) -> ())
	local row = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56) }, parent)
	UI.Label({ Text = labelText, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -120, 1, 0), TextSize = 22 }, row)
	local button = UI.Button({ Text = initial and "ON" or "OFF", Color = initial and UI.Colors.Green or UI.Colors.Locked, Size = UDim2.fromOffset(104, 46), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), TextSize = 22 }, row)
	local state = initial
	local function render()
		button.Text = state and "ON" or "OFF"
		button.BackgroundColor3 = state and UI.Colors.Green or UI.Colors.Locked
	end
	button.Activated:Connect(function()
		state = not state
		render()
		onChange(state)
	end)
	return {
		Set = function(v: boolean)
			state = v
			render()
		end,
	}
end

-- ===== Menu manager =====

local menus: { [string]: any } = {}
local openMenu: string? = nil
local menuListeners: { (string?, string?) -> () } = {}

-- Dimmed (and blurred) backdrop behind an open menu; clicking it closes the menu.
local backdrop = UI.New("TextButton", {
	Name = "MenuBackdrop",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	-- The Menus layer starts under the top bar; the dim reaches up to cover that strip too.
	Position = UDim2.fromOffset(0, -200),
	Size = UDim2.new(1, 0, 1, 200),
	Visible = false,
	ZIndex = 0,
}, UI.Layers.Menus) :: TextButton
backdrop.Activated:Connect(function()
	UI.CloseAllMenus()
end)
local backdropOn = false
local function setBackdrop(on: boolean)
	if on == backdropOn then
		return
	end
	backdropOn = on
	UI.Blur(on)
	if on then
		backdrop.Visible = true
		UI.Tween(backdrop, { BackgroundTransparency = 0.45 }, 0.2)
	else
		UI.Tween(backdrop, { BackgroundTransparency = 1 }, 0.15).Completed:Once(function()
			if not openMenu then
				backdrop.Visible = false
			end
		end)
	end
end

function UI.OnMenuChanged(fn: (string?, string?) -> ())
	table.insert(menuListeners, fn)
end

function UI.CloseAllMenus()
	if openMenu and menus[openMenu] then
		menus[openMenu].Close()
	end
end

function UI.GetOpenMenu(): string?
	return openMenu
end

-- A centred menu: dark glass body, a studded header in `accent` with the title and a red close
-- button. Opens by sliding up and springing in over the blurred world; closes by dropping away.
function UI.Menu(name: string, title: string, size: UDim2, accent: Color3?)
	local frame = UI.Frame({
		Name = name .. "Menu",
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.04,
	}, UI.Layers.Menus)
	UI.Corner(frame, 16)
	UI.Stroke(frame, BLACK, 3)
	UI.Gradient(frame, Color3.fromRGB(48, 51, 70), Color3.fromRGB(16, 17, 26))
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(1100, 800), MinSize = Vector2.new(280, 200) }, frame)
	local home = frame.Position
	-- Never taller or wider than the safe area (the content scrolls): matters on phones.
	local design = Vector2.new(size.X.Offset, size.Y.Offset)
	local function fit()
		local area = UI.Layers.Menus.AbsoluteSize / UI.Scale
		if area.Y > 0 then
			frame.Size = UDim2.fromOffset(math.min(design.X, area.X - 24), math.min(design.Y, area.Y - 24))
		end
	end
	fit()
	UI.Layers.Menus:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local titleBar = UI.Surface3D({ Name = "Header", Size = UDim2.new(1, 0, 0, 62) }, frame, accent or UI.Colors.Gold, 16, 0.1)
	UI.Label({ Text = title, TextSize = 30, Size = UDim2.new(1, -150, 0.9, 0), Position = UDim2.fromOffset(75, 0), TextWrapped = false, TextScaled = false }, titleBar)
	local close = UI.Button({ Name = "Close", Text = "", Color = UI.Colors.Red, Size = UDim2.fromOffset(48, 46), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.45, 0), TextSize = 22 }, titleBar)
	UI.Icon(close, "Icon_Close", "X", { TextSize = 24 })

	local content = UI.Frame({ Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -86), Position = UDim2.fromOffset(12, 74) }, frame)

	local menu = {}
	menu.Frame = frame
	menu.Content = content
	menu.Title = titleBar
	local isOpen = false
	local onOpen: (() -> ())? = nil
	local onClose: (() -> ())? = nil
	local menuScale = UI.New("UIScale", { Name = "MenuScale" }, frame) :: UIScale

	function menu.Open()
		if openMenu and openMenu ~= name and menus[openMenu] then
			menus[openMenu].Close()
		end
		openMenu = name
		isOpen = true
		fit()
		frame.Visible = true
		setBackdrop(true)
		if reduceMotion() then
			frame.Position = home
			menuScale.Scale = 1
		else
			frame.Position = home + UDim2.fromOffset(0, 70)
			menuScale.Scale = 0.92
			UI.Tween(frame, { Position = home }, 0.32, Enum.EasingStyle.Back)
			UI.Tween(menuScale, { Scale = 1 }, 0.32, Enum.EasingStyle.Back)
		end
		if onOpen then
			onOpen()
		end
		for _, fn in ipairs(menuListeners) do
			fn(name, "open")
		end
	end

	function menu.Close()
		if not isOpen then
			return
		end
		isOpen = false
		if openMenu == name then
			openMenu = nil
			setBackdrop(false)
		end
		-- Quick drop-away, then hide (unless it was reopened meanwhile).
		UI.Tween(menuScale, { Scale = 0.94 }, 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UI.Tween(frame, { Position = home + UDim2.fromOffset(0, 50) }, 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
			if not isOpen then
				frame.Visible = false
				frame.Position = home
			end
		end)
		if onClose then
			onClose()
		end
		if clickSoundHook then
			clickSoundHook("UIClose")
		end
		for _, fn in ipairs(menuListeners) do
			fn(name, "close")
		end
	end

	function menu.Toggle()
		if isOpen then
			menu.Close()
		else
			menu.Open()
		end
	end

	function menu.IsOpen()
		return isOpen
	end

	function menu.OnOpen(fn)
		onOpen = fn
	end

	function menu.OnClose(fn)
		onClose = fn
	end

	close.Activated:Connect(menu.Close)
	menus[name] = menu
	return menu
end

-- ===== World-attached GUIs =====

function UI.Billboard(adornee: BasePart, size: UDim2, offset: Vector3?, maxDistance: number?): BillboardGui
	local bb = UI.New("BillboardGui", {
		Adornee = adornee,
		Size = size,
		StudsOffset = offset or Vector3.new(0, 0, 0),
		AlwaysOnTop = false,
		MaxDistance = maxDistance or 120,
		LightInfluence = 0,
		ResetOnSpawn = false,
	}, playerGui) :: BillboardGui
	return bb
end

function UI.Surface(adornee: BasePart, face: Enum.NormalId, pixelsPerStud: number?): SurfaceGui
	return UI.New("SurfaceGui", {
		Adornee = adornee,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud or 40,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
	}, playerGui) :: SurfaceGui
end

-- A rounded dark track with a gradient fill carrying the pack's moving-stripe pattern.
function UI.ProgressBar(parent: Instance, size: UDim2, position: UDim2?, color: Color3?)
	local bg = UI.Frame({ Name = "ProgressBar", Size = size, Position = position or UDim2.new(), BackgroundColor3 = UI.Colors.PanelDark, BackgroundTransparency = 0.1 }, parent)
	UI.Corner(bg, 999)
	UI.Stroke(bg, BLACK, UIConfig.StrokeThickness)
	local fill = UI.Frame({ Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE }, bg)
	UI.Corner(fill, 999)
	local gradient = UI.Gradient(fill, WHITE, WHITE)
	local edge = UI.New("UIStroke", { Name = "Edge", Color = WHITE, Thickness = 1.5, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, fill) :: UIStroke
	local stripes = UI.New("ImageLabel", { Name = "Stripes", BackgroundTransparency = 1, Image = UIConfig.Images.Stripes, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(40, 40), ImageTransparency = 0.72, Size = UDim2.fromScale(1, 1) }, fill)
	UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, stripes)
	local function setColor(c: Color3)
		local v = UI.VariantFor(c)
		gradient.Color = ColorSequence.new(v.Top, v.Bottom)
		edge.Color = v.Edge
	end
	setColor(color or UI.Colors.Green)
	return {
		Frame = bg,
		Fill = fill,
		SetColor = setColor,
		Set = function(fraction: number, animate: boolean?)
			fraction = math.clamp(fraction, 0, 1)
			if animate then
				UI.Tween(fill, { Size = UDim2.fromScale(fraction, 1) }, 0.3)
			else
				fill.Size = UDim2.fromScale(fraction, 1)
			end
		end,
	}
end

function UI.Shake(inst: GuiObject, magnitude: number?, duration: number?)
	local original = inst.Position
	local mag = magnitude or 6
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < (duration or 0.35) do
			inst.Position = original + UDim2.fromOffset(math.random(-mag, mag), math.random(-mag, mag))
			task.wait(0.03)
		end
		inst.Position = original
	end)
end

function UI.Flash(inst: GuiObject, color: Color3, duration: number?)
	local original = inst.BackgroundColor3
	inst.BackgroundColor3 = color
	UI.Tween(inst, { BackgroundColor3 = original }, duration or 0.4)
end

function UI.GetTopInset(): number
	local inset = GuiService:GetGuiInset()
	return inset.Y
end

-- How much a fixed-layout panel of `design` size must shrink to fit the safe area (1 = it fits).
-- PopIn settles on this scale.
function UI.FitScale(panel: GuiObject, design: Vector2): number
	local area = UI.Layers.Menus.AbsoluteSize / UI.Scale
	local f = area.Y > 0 and math.min(1, (area.X - 24) / design.X, (area.Y - 24) / design.Y) or 1
	panel:SetAttribute("FitScale", f)
	return f
end

-- A screen point (AbsolutePosition space) as an offset in the full-screen layers.
function UI.FromAbsolute(point: Vector2): UDim2
	local origin = gui.AbsolutePosition
	return UDim2.fromOffset((point.X - origin.X) / UI.Scale, (point.Y - origin.Y) / UI.Scale)
end

-- Studio-only test hook: fire MainUI.DevOpenMenu with a menu name to open it ("" closes).
if game:GetService("RunService"):IsStudio() then
	local hook = Instance.new("BindableEvent")
	hook.Name = "DevOpenMenu"
	hook.Parent = gui
	hook.Event:Connect(function(name: string)
		if menus[name] then
			menus[name].Open()
		else
			UI.CloseAllMenus()
		end
	end)
end

return UI
