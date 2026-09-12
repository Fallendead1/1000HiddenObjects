--[[
	Audio asset IDs. 0 = not set; the AudioController silently skips missing sounds.
	Volume is a per-sound multiplier applied on top of the SFX/Music settings.
]]

return {
	Music = {
		LobbyAmbience = { Id = 0, Volume = 0.3, Looped = true },
		RoomAmbience = { Id = 0, Volume = 0.25, Looped = true },
	},

	SFX = {
		UIClick = { Id = 0, Volume = 0.5 },
		UIClose = { Id = 0, Volume = 0.5 },
		QueueEnter = { Id = 0, Volume = 0.6 },
		QueueLeave = { Id = 0, Volume = 0.6 },
		Countdown = { Id = 0, Volume = 0.6 },
		TeleportWhoosh = { Id = 0, Volume = 0.7 },
		SearchRustle = { Id = 0, Volume = 0.4 },
		ClutterPop = { Id = 0, Volume = 0.5 },
		BagTick = { Id = 0, Volume = 0.3 },
		BagFull = { Id = 0, Volume = 0.7 },
		SellCash = { Id = 0, Volume = 0.8 },
		UpgradePurchase = { Id = 0, Volume = 0.8 },
		UpgradeDenied = { Id = 0, Volume = 0.6 },
		Hint = { Id = 0, Volume = 0.7 },
		HotColdPing = { Id = 0, Volume = 0.4 },
		TargetReveal = { Id = 0, Volume = 0.8 },
		TargetFound = { Id = 0, Volume = 1 },
		VictorySting = { Id = 0, Volume = 1 },
		TrashBomb = { Id = 0, Volume = 0.9 },
		Notification = { Id = 0, Volume = 0.5 },
	},
}
