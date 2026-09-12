--[[
	Audio configuration. `Id` may be:
	  0                      -> no sound (silently skipped)
	  <number>               -> rbxassetid://<number> (final uploaded asset)
	  "rbxasset://sounds/.." -> built-in Roblox engine sound (placeholder until final SFX exist)
	Pitch may be a number or { min, max } for random variation per play.
	Replace placeholders by setting the numeric asset id; nothing else needs to change.
]]

return {
	Music = {
		LobbyAmbience = { Id = 0, Volume = 0.3, Looped = true },
		RoomAmbience = { Id = 0, Volume = 0.25, Looped = true },
	},

	SFX = {
		UIClick = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.35, Pitch = { 1.4, 1.6 } },
		UIClose = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.3, Pitch = { 0.9, 1.0 } },
		QueueEnter = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Pitch = 1.8 },
		QueueLeave = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Pitch = 0.8 },
		Countdown = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.6, Pitch = 1.2 },
		TeleportWhoosh = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.6, Pitch = 0.7 },
		SearchRustle = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.35, Pitch = { 1.1, 1.5 } },
		SearchLoop = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.25, Pitch = 1.3, Looped = true },
		ClutterPop = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.4, Pitch = { 1.2, 1.7 } },
		BagTick = { Id = 0, Volume = 0.3 },
		BagFull = { Id = "rbxasset://sounds/oof.ogg", Volume = 0.6, Pitch = 1 },
		SellCash = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.7, Pitch = { 1.3, 1.5 } },
		UpgradePurchase = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.7, Pitch = 1.6 },
		UpgradeDenied = { Id = "rbxasset://sounds/oof.ogg", Volume = 0.4, Pitch = 0.7 },
		Hint = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.6, Pitch = 2 },
		HotColdPing = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.4, Pitch = { 1.8, 2.2 } },
		TargetReveal = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.8, Pitch = 2 },
		TargetFound = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.7, Pitch = 1.4 },
		VictorySting = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.9, Pitch = 1.2 },
		TrashBomb = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.9, Pitch = 1 },
		Notification = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.3, Pitch = 1.3 },
		ChuteChomp = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.6, Pitch = 0.6 },
	},
}
