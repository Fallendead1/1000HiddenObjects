local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local NotificationController = {}

local container: Frame
local KindColors = {
	Info = UI.Colors.Cyan,
	Success = UI.Colors.Green,
	Warning = UI.Colors.Orange,
	Error = UI.Colors.Red,
	Premium = UI.Colors.Purple,
}
local KindGlyphs = { Info = "i", Success = "✓", Warning = "!", Error = "✕", Premium = "★" }

function NotificationController.Init()
	container = UI.Frame({
		Name = "Notifications",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 360, 1, -140),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 130),
	}, UI.Layers.Notify)
	UI.ListLayout(container, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)

	Remotes.Event("Notification").OnClientEvent:Connect(function(kind, text, duration)
		NotificationController.Show(kind, text, duration)
	end)
end

function NotificationController.Show(kind: string, text: string, duration: number?)
	local color = KindColors[kind] or UI.Colors.Cyan
	local toast = UI.Frame({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.05 }, container)
	UI.Corner(toast, 10)
	UI.Stroke(toast, color, 2)
	UI.Frame({ Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = color }, toast)
	local badge = UI.Frame({ Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(14, 8), BackgroundColor3 = color }, toast)
	UI.Corner(badge, 14)
	UI.Icon(badge, "Icon_Notify_" .. kind, KindGlyphs[kind] or "i", { TextSize = 16, TextColor3 = UI.Colors.PanelDark })
	local label = UI.Label({
		Text = text,
		TextSize = 18,
		Font = UI.FontBody,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -58, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(50, 0),
	}, toast)
	UI.Padding(label, { 0, 8, 10, 10 })
	toast.Position = UDim2.fromOffset(60, 0)
	UI.Tween(toast, { Position = UDim2.fromOffset(0, 0) }, 0.25, Enum.EasingStyle.Back)
	UI.PopIn(badge, 0.3, 0.4)
	local glow = UI.Glow(toast, color, 12, 0.1)
	UI.Tween(glow, { [glow:IsA("UIStroke") and "Transparency" or "ImageTransparency"] = 0.85 }, 0.8)

	if kind ~= "Info" then
		Controllers.AudioController.Play("Notification")
	end

	task.delay(duration or 4, function()
		if toast.Parent then
			local t = UI.Tween(toast, { BackgroundTransparency = 1 }, 0.3)
			UI.Tween(label, { TextTransparency = 1 }, 0.3)
			t.Completed:Wait()
			toast:Destroy()
		end
	end)
	-- Keep the stack bounded.
	local children = container:GetChildren()
	local toasts = {}
	for _, c in ipairs(children) do
		if c:IsA("Frame") then
			table.insert(toasts, c)
		end
	end
	while #toasts > 5 do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

return NotificationController
