--[[
	Toasts (the pack's notification style): a black band that fades out at both ends, a
	coloured studded badge and gradient text in the kind's colour. New toasts grow in at the
	top of the stack (older ones slide down) and shrink away after a few seconds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local NotificationController = {}

local container: Frame
local order = 0
local MAX_TOASTS = 4
local TEXT_SIZE = 18
local TEXT_WIDTH = 380

local KindColors = {
	Info = UI.Colors.Cyan,
	Success = UI.Colors.Green,
	Warning = UI.Colors.Orange,
	Error = UI.Colors.Red,
	Premium = UI.Colors.Purple,
}
local KindGlyphs = { Info = "i", Success = "✓", Warning = "!", Error = "✕", Premium = "★" }

local function dismiss(toast: Frame)
	if not toast.Parent or toast:GetAttribute("Leaving") then
		return
	end
	toast:SetAttribute("Leaving", true)
	for _, d in ipairs(toast:GetDescendants()) do
		if d:IsA("TextLabel") then
			UI.Tween(d, { TextTransparency = 1 }, 0.2)
		end
	end
	UI.Tween(toast, { Size = UDim2.new(1, 0, 0, 0) }, 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		toast:Destroy()
	end)
end

function NotificationController.Init()
	container = UI.Frame({
		Name = "Notifications",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(470, 360),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 176),
	}, UI.Layers.Notify)
	UI.ListLayout(container, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	-- Just below the HUD's top-centre pieces (in rooms: below the level badge and clue banner);
	-- while a menu is open, at the very top so toasts never cover the menu.
	local player = game:GetService("Players").LocalPlayer
	local function place()
		local y = UI.GetOpenMenu() and 8 or (player:GetAttribute("InMatch") and 248 or 136)
		UI.Tween(container, { Position = UDim2.new(0.5, 0, 0, y) }, 0.2)
	end
	player:GetAttributeChangedSignal("InMatch"):Connect(place)
	UI.OnMenuChanged(function()
		task.defer(place)
	end)
	place()

	Remotes.Event("Notification").OnClientEvent:Connect(function(kind, text, duration)
		NotificationController.Show(kind, text, duration)
	end)
end

function NotificationController.Show(kind: string, text: string, duration: number?)
	local color = KindColors[kind] or UI.Colors.Cyan
	order += 1
	local bounds = TextService:GetTextSize(text, TEXT_SIZE, UI.Font, Vector2.new(TEXT_WIDTH, 1000))
	local height = math.max(42, bounds.Y + 16)
	local badgeSize = 30
	local contentWidth = math.min(bounds.X, TEXT_WIDTH) + badgeSize + 12

	local toast = UI.Frame({ Name = "Toast", BackgroundTransparency = 1, ClipsDescendants = true, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = -order }, container)
	local body = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, toast)
	local band = UI.Frame({ BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1) }, body)
	UI.New("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0.3),
			NumberSequenceKeypoint.new(0.78, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, band)
	local badge = UI.Surface3D({ Size = UDim2.fromOffset(badgeSize, badgeSize), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, -contentWidth / 2, 0.5, 0) }, body, color, badgeSize / 2, 0.12)
	local glyph = UI.Icon(badge, "Icon_Notify_" .. kind, KindGlyphs[kind] or "i", { TextSize = 15 })
	glyph.Size = UDim2.fromScale(0.7, 0.62)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.45)
	local label = UI.Label({
		Text = text,
		TextSize = TEXT_SIZE,
		Size = UDim2.fromOffset(math.min(bounds.X, TEXT_WIDTH) + 6, height),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, -contentWidth / 2 + badgeSize + 12, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, body)
	UI.TextGradient(label, color)

	UI.Tween(toast, { Size = UDim2.new(1, 0, 0, height) }, 0.35, Enum.EasingStyle.Back)
	UI.PopIn(badge, 0.3, 0.45)

	if kind ~= "Info" then
		-- Purchases get the buy sound, refusals the denied sound.
		local sound = (kind == "Premium" and "Purchase") or ((kind == "Warning" or kind == "Error") and "Denied") or "Notification"
		Controllers.AudioController.Play(sound)
	end

	task.delay(duration or 3.5, function()
		dismiss(toast)
	end)
	-- Keep the stack short: the oldest leave first.
	local toasts = {}
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("Frame") and not c:GetAttribute("Leaving") then
			table.insert(toasts, c)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder > b.LayoutOrder
	end)
	for i = MAX_TOASTS + 1, #toasts do
		dismiss(toasts[i])
	end
end

return NotificationController
