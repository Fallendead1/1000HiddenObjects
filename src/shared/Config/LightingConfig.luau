--[[
	The lobby's look (LightingController puts it on for the local player while they're in the lobby;
	rooms keep the place's own Lighting). A painted anime sky whose clouds drift slowly around you,
	a cool lavender haze on the horizon, soft blue-tinted shadows and a gentle glow: a peaceful
	welcome. Sky art: "Anime Sky" by Aschorking (Creator Store asset 72835926026092).
]]

return {
	Lobby = {
		Sky = {
			SkyboxBk = "rbxassetid://18351376859",
			SkyboxDn = "rbxassetid://18351374919",
			SkyboxFt = "rbxassetid://18351376800",
			SkyboxLf = "rbxassetid://18351376469",
			SkyboxRt = "rbxassetid://18351376457",
			SkyboxUp = "rbxassetid://18351377189",
			SunAngularSize = 14,
			StarCount = 0,
		},
		DriftDegreesPerSecond = 0.5, -- the painted clouds turn slowly (off with Reduce VFX)

		-- Lighting's own properties (the rooms' values come back when you enter a room).
		Lighting = {
			ClockTime = 14.5,
			GeographicLatitude = 25,
			Brightness = 2.6,
			ExposureCompensation = 0,
			Ambient = Color3.fromRGB(110, 115, 150),
			OutdoorAmbient = Color3.fromRGB(150, 160, 205), -- shaded sides turn cool blue, as in the reference
			ColorShift_Top = Color3.fromRGB(255, 240, 220), -- warm sunlit tops
			ColorShift_Bottom = Color3.fromRGB(120, 140, 200),
			ShadowSoftness = 0.35,
			EnvironmentDiffuseScale = 1,
			EnvironmentSpecularScale = 0.6,
		},

		Atmosphere = {
			Density = 0.28,
			Offset = 0.15,
			Color = Color3.fromRGB(199, 214, 255),
			Decay = Color3.fromRGB(140, 130, 190),
			Glare = 0.25,
			Haze = 1.2,
		},
		Bloom = { Intensity = 0.8, Size = 28, Threshold = 1.6 },
		ColorCorrection = { Brightness = 0.02, Contrast = 0.1, Saturation = 0.25, TintColor = Color3.fromRGB(248, 246, 255) },
		SunRays = { Intensity = 0.06, Spread = 0.55 },
	},
}
