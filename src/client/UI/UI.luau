--[[
	Client UI toolkit: one ScreenGui with layered containers, styled element constructors,
	a menu manager (one menu open at a time) and responsive scaling for phone/desktop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UI = {}
UI.Colors = UIConfig.Colors
UI.Font = UIConfig.Font
UI.FontBody = UIConfig.FontBody

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

-- ===== Studio-authored art (added in Studio, no code change needed) =====
-- ReplicatedStorage.GameAssets.UIImages is a Configuration whose string attributes map a UI
-- key to an image ("rbxassetid://123"). Frames (Panel, Button, BarTrack, BarFill) are white
-- 9-slice images tinted in code; an optional "<Key>_Slice" Rect attribute overrides the
-- default slice centre (64, 64, 192, 192 on a 256 x 256 image). Missing keys fall back to the
-- flat built-in style, so the game always works without art.
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

-- Put a tinted 9-slice skin behind a frame/button when the art exists. The element keeps its
-- BackgroundColor3/BackgroundTransparency API: the skin follows both.
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
	inst:SetAttribute("SkinTransparency", inst.BackgroundTransparency)
	inst.BackgroundTransparency = 1
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			child.Enabled = false
		end
	end
	inst:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		skin.ImageColor3 = inst.BackgroundColor3
	end)
	inst:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if inst.BackgroundTransparency < 1 then
			skin.ImageTransparency = inst.BackgroundTransparency
			inst.BackgroundTransparency = 1
		end
	end)
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
	local label = UI.New("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIConfig.Font,
		TextColor3 = UIConfig.Colors.Text,
		TextSize = 18,
		Size = UDim2.fromScale(1, 1),
	}, parent) :: TextLabel
	for k, v in pairs(props) do
		(label :: any)[k] = v
	end
	return label
end

function UI.IsTouch(): boolean
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
		s = math.clamp(viewport.Y / 560, 0.75, 1.15)
	else
		s = math.clamp(math.min(viewport.Y / 760, viewport.X / 1300), 0.7, 1.25)
	end
	scale.Scale = s
	UI.Scale = s
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

function UI.Corner(inst: GuiObject, radius: number?): UICorner
	return UI.New("UICorner", { CornerRadius = UDim.new(0, radius or UIConfig.Corner) }, inst) :: UICorner
end

function UI.Stroke(inst: GuiObject, color: Color3?, thickness: number?, transparency: number?): UIStroke
	-- Text labels get a text outline; everything else gets a border.
	local mode = inst:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	return UI.New("UIStroke", {
		Color = color or UI.Colors.Stroke,
		Thickness = thickness or UIConfig.StrokeThickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = mode,
	}, inst) :: UIStroke
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

function UI.Panel(props: { [string]: any }?, parent: Instance?): Frame
	local frame = UI.Frame(props, parent)
	UI.Corner(frame)
	UI.Stroke(frame)
	UI.Skin(frame, "Panel")
	return frame
end

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
	if props then
		for k, v in pairs(props) do
			base[k] = v
		end
	end
	local label = UI.New("TextLabel", base, parent) :: TextLabel
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

local clickSoundHook: ((string) -> ())? = nil
function UI.SetClickSound(fn: (string) -> ())
	clickSoundHook = fn
end

function UI.PressEffect(button: GuiButton)
	local scaleObj = button:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, button) :: UIScale
	button.MouseButton1Down:Connect(function()
		UI.Tween(scaleObj, { Scale = 0.94 }, 0.08)
	end)
	local function release()
		UI.Tween(scaleObj, { Scale = 1 }, 0.12, Enum.EasingStyle.Back)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		if clickSoundHook then
			clickSoundHook("UIClick")
		end
	end)
end

function UI.Button(props: { [string]: any }?, parent: Instance?): TextButton
	local color = props and props.Color or UI.Colors.Green
	local base = {
		BackgroundColor3 = color,
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
			if k ~= "Color" and k ~= "Corner" then
				base[k] = v
			end
		end
	end
	local button = UI.New("TextButton", base, parent) :: TextButton
	UI.Corner(button, props and props.Corner or UIConfig.CornerSmall)
	local stroke = UI.Stroke(button, Color3.new(0, 0, 0), 2, 0.6)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	UI.Skin(button, props and props.Corner and props.Corner >= 40 and "ButtonRound" or "Button")
	UI.PressEffect(button)
	return button
end

function UI.SetButtonEnabled(button: TextButton, enabled: boolean, disabledText: string?)
	button.Active = enabled
	button.AutoButtonColor = false
	local skin = button:FindFirstChild("Skin")
	if enabled then
		if skin then
			skin.ImageTransparency = 0
		else
			button.BackgroundTransparency = 0
		end
		button.TextTransparency = 0
	else
		if skin then
			skin.ImageTransparency = 0.5
		else
			button.BackgroundTransparency = 0.5
		end
		button.TextTransparency = 0.3
		if disabledText then
			button.Text = disabledText
		end
	end
end

-- Toggle switch used by Settings.
function UI.Toggle(parent: Instance, labelText: string, initial: boolean, onChange: (boolean) -> ())
	local row = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52) }, parent)
	UI.Label({ Text = labelText, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -110, 1, 0), TextSize = 22 }, row)
	local button = UI.Button({ Text = initial and "ON" or "OFF", Color = initial and UI.Colors.Green or UI.Colors.Locked, Size = UDim2.fromOffset(96, 44), Position = UDim2.new(1, -96, 0.5, -22) }, row)
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

function UI.Menu(name: string, title: string, size: UDim2)
	local frame = UI.Frame({
		Name = name .. "Menu",
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Visible = false,
	}, UI.Layers.Menus)
	UI.Corner(frame, 16)
	UI.Stroke(frame, UI.Colors.Stroke, 3)
	UI.Skin(frame, "Panel")
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(1100, 800), MinSize = Vector2.new(280, 200) }, frame)

	local titleBar = UI.Frame({ Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = UI.Colors.PanelDark }, frame)
	UI.Corner(titleBar, 16)
	UI.Frame({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), BackgroundColor3 = UI.Colors.PanelDark }, titleBar)
	UI.Label({ Text = title, TextSize = 28, Size = UDim2.new(1, -140, 1, 0), Position = UDim2.fromOffset(20, 0), TextXAlignment = Enum.TextXAlignment.Left }, titleBar)
	local close = UI.Button({ Text = "", Color = UI.Colors.Red, Size = UDim2.fromOffset(48, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), TextSize = 22 }, titleBar)
	UI.Icon(close, "Icon_Close", "X", { TextSize = 22 })

	local content = UI.Frame({ Name = "Content", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -72), Position = UDim2.fromOffset(12, 64) }, frame)

	local menu = {}
	menu.Frame = frame
	menu.Content = content
	menu.Title = titleBar
	local isOpen = false
	local onOpen: (() -> ())? = nil
	local onClose: (() -> ())? = nil

	function menu.Open()
		if openMenu and openMenu ~= name and menus[openMenu] then
			menus[openMenu].Close()
		end
		openMenu = name
		isOpen = true
		frame.Visible = true
		local uiScale = frame:FindFirstChildOfClass("UIScale") or UI.New("UIScale", { Scale = 0.85 }, frame)
		uiScale.Scale = 0.85
		UI.Tween(uiScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
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
		frame.Visible = false
		if openMenu == name then
			openMenu = nil
		end
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

function UI.ProgressBar(parent: Instance, size: UDim2, position: UDim2?, color: Color3?)
	local bg = UI.Frame({ Size = size, Position = position or UDim2.new(), BackgroundColor3 = UI.Colors.PanelDark }, parent)
	UI.Corner(bg, 999)
	UI.Stroke(bg, UI.Colors.Stroke, 2)
	UI.Skin(bg, "BarTrack")
	local fill = UI.Frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = color or UI.Colors.Green }, bg)
	UI.Corner(fill, 999)
	UI.Skin(fill, "BarFill")
	return {
		Frame = bg,
		Fill = fill,
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

return UI
