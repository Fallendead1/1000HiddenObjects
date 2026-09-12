--[[
	Single visual style used by every screen. Deep navy panels, bold white text,
	gold for the hidden object, green for progress, cyan for cash, red/orange for warnings.
]]

return {
	Colors = {
		Panel = Color3.fromRGB(24, 30, 48),
		PanelLight = Color3.fromRGB(36, 44, 68),
		PanelDark = Color3.fromRGB(16, 20, 34),
		Stroke = Color3.fromRGB(70, 82, 120),
		Text = Color3.fromRGB(255, 255, 255),
		TextDim = Color3.fromRGB(170, 180, 205),
		Gold = Color3.fromRGB(255, 200, 40),
		GoldDark = Color3.fromRGB(190, 140, 20),
		Green = Color3.fromRGB(70, 210, 110),
		GreenDark = Color3.fromRGB(40, 150, 75),
		Cash = Color3.fromRGB(80, 230, 200),
		Cyan = Color3.fromRGB(70, 190, 255),
		Red = Color3.fromRGB(235, 70, 70),
		Orange = Color3.fromRGB(255, 140, 40),
		Purple = Color3.fromRGB(170, 100, 255),
		Overlay = Color3.fromRGB(0, 0, 0),
		Locked = Color3.fromRGB(60, 66, 90),
	},

	Font = Enum.Font.FredokaOne,
	FontBody = Enum.Font.GothamBold,

	Corner = 12,
	CornerSmall = 8,
	StrokeThickness = 2,

	-- Minimum comfortable touch button size (logical pixels before UIScale)
	MinButtonSize = 48,
}
