--[[
	The game's one visual style (drawn from the imported UI pack): bold white Gotham text with
	black outlines, saturated "studded 3D" surfaces (a gradient face over a darker lip, a light
	inner edge, a studs pattern and a soft sheen), dark glassy panels with black borders.

	Colour meanings are fixed everywhere:
	  Gold   the hidden object, rewards, headers     Green  progress, confirm, buy
	  Cash   money (lime)                            Cyan   info, hints, level/XP
	  Red    close, danger, can't afford             Purple premium / Robux
	  Orange warnings, streaks                       Locked unavailable / maxed-out neutral
]]

local C = Color3.fromRGB

local Colors = {
	Panel = C(28, 30, 42),
	PanelLight = C(46, 50, 68),
	PanelDark = C(12, 13, 20),
	Stroke = C(0, 0, 0),
	Text = C(255, 255, 255),
	TextDim = C(198, 204, 224),
	Gold = C(255, 196, 0),
	GoldDark = C(170, 115, 0),
	Green = C(40, 215, 60),
	GreenDark = C(0, 140, 40),
	Cash = C(125, 255, 40),
	Cyan = C(0, 180, 255),
	Red = C(255, 70, 76),
	Orange = C(255, 150, 0),
	Purple = C(200, 40, 255),
	Pink = C(255, 45, 150),
	Overlay = C(0, 0, 0),
	Locked = C(112, 122, 152),
}

-- Studded surface looks: Top/Bottom = the face gradient, Base = the darker lip under the face,
-- Edge = the light inner outline. `Match` lists the UI colours that pick this look.
local Variants = {
	Green = { Top = C(179, 255, 0), Bottom = C(0, 215, 64), Base = C(0, 125, 36), Edge = C(205, 255, 80), Match = { Colors.Green, Colors.GreenDark, Colors.Cash } },
	Cyan = { Top = C(0, 205, 255), Bottom = C(0, 140, 255), Base = C(0, 82, 150), Edge = C(110, 225, 255), Match = { Colors.Cyan } },
	Red = { Top = C(255, 112, 114), Bottom = C(214, 38, 46), Base = C(118, 0, 8), Edge = C(255, 160, 160), Match = { Colors.Red } },
	Gold = { Top = C(255, 220, 20), Bottom = C(255, 160, 0), Base = C(150, 90, 0), Edge = C(255, 240, 130), Match = { Colors.Gold, Colors.GoldDark } },
	Purple = { Top = C(240, 70, 255), Bottom = C(165, 0, 255), Base = C(85, 0, 128), Edge = C(245, 150, 255), Match = { Colors.Purple } },
	Orange = { Top = C(255, 196, 50), Bottom = C(255, 116, 0), Base = C(150, 58, 0), Edge = C(255, 215, 130), Match = { Colors.Orange } },
	Pink = { Top = C(255, 80, 180), Bottom = C(230, 0, 90), Base = C(118, 0, 52), Edge = C(255, 150, 210), Match = { Colors.Pink } },
	Locked = { Top = C(150, 160, 190), Bottom = C(96, 106, 136), Base = C(52, 57, 76), Edge = C(190, 200, 222), Match = { Colors.Locked } },
	Dark = { Top = C(70, 75, 98), Bottom = C(40, 44, 60), Base = C(16, 18, 28), Edge = C(100, 106, 136), Match = { Colors.Panel, Colors.PanelLight, Colors.PanelDark } },
}

return {
	Colors = Colors,
	Variants = Variants,

	-- Pack textures: a studs tile, a light-rays sheen, diagonal stripes (progress fills).
	Images = {
		Studs = "rbxassetid://76728843491214",
		Rays = "rbxassetid://92627249277540",
		Stripes = "rbxassetid://111332203742056",
	},

	Font = Enum.Font.GothamBlack,
	FontBody = Enum.Font.GothamBold,

	Corner = 12,
	CornerSmall = 10,
	StrokeThickness = 2.5,

	-- Minimum comfortable touch button size (logical pixels before UIScale)
	MinButtonSize = 48,
}
