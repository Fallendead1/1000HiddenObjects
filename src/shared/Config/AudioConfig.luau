--[[
	Audio configuration. `Id` may be:
	  0                      -> no sound (silently skipped)
	  <number>               -> rbxassetid://<number> (final uploaded asset; always used)
	  "rbxasset://sounds/.." -> built-in Roblox engine sound (placeholder until final SFX exist)
	Pitch may be a number or { min, max } for random variation per play.

	Studio override (no code change): a Sound named <Key> inside SoundService.GameSounds
	(e.g. SoundService.GameSounds.Deposit) replaces a PLACEHOLDER's SoundId/Volume at runtime.
	A numeric Id here is final and wins over the override.
]]

-- The game's own sounds.
local MUSIC = 132601187837139 -- lobby and rooms (one continuous loop)
local CLICK = 75757588904639 -- buttons, closing menus, grabbing an object
local DENIED = 133211074702094 -- refused actions: too heavy, can't afford, warnings
local LEVEL_UP = 96666005075540
local PURCHASE = 134116566819117 -- shop purchases and upgrades

return {
	Music = {
		LobbyAmbience = { Id = MUSIC, Volume = 0.35, Looped = true },
		RoomAmbience = { Id = MUSIC, Volume = 0.35, Looped = true },
	},

	SFX = {
		UIClick = { Id = CLICK, Volume = 0.5, Pitch = { 0.97, 1.03 } },
		UIClose = { Id = CLICK, Volume = 0.45, Pitch = 0.88 },
		QueueEnter = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Pitch = 1.8 },
		QueueLeave = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Pitch = 0.8 },
		Countdown = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.6, Pitch = 1.2 },
		TeleportWhoosh = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.6, Pitch = 0.7 },
		Grab = { Id = CLICK, Volume = 0.5, Pitch = { 0.92, 1.08 } },
		Throw = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.45, Pitch = { 1.5, 1.8 } },
		Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.35, Pitch = { 1.1, 1.6 } },
		LandSoft = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.3, Pitch = { 0.7, 0.9 } },
		LandPaper = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.35, Pitch = { 1.6, 1.9 } },
		LandHard = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.45, Pitch = { 1.4, 1.8 } },
		CashAward = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.45, Pitch = { 1.5, 1.7 } },
		Deposit = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.5, Pitch = { 1.3, 1.5 } },
		DepositMatch = { Id = "rbxasset://sounds/impact_water.mp3", Volume = 0.6, Pitch = { 1.7, 1.9 } },
		Swish = { Id = "rbxasset://sounds/action_swim.mp3", Volume = 0.6, Pitch = 2.2 },
		Streak = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.5, Pitch = { 2.0, 2.4 } },
		Treasure = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.8, Pitch = 2.2 },
		ChunkBurst = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.6, Pitch = { 0.55, 0.7 } },
		KeyRattle = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.35, Pitch = { 2.6, 3.0 } },
		BinHover = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.2, Pitch = 1.9 },
		TooHeavy = { Id = DENIED, Volume = 0.5, Pitch = 1 },
		UpgradePurchase = { Id = PURCHASE, Volume = 0.6, Pitch = 1 },
		UpgradeDenied = { Id = DENIED, Volume = 0.5, Pitch = 1 },
		-- Fallback: whose Studio sound to use if this final asset can't load.
		Purchase = { Id = PURCHASE, Volume = 0.6, Pitch = 1, Fallback = "UpgradePurchase" },
		Denied = { Id = DENIED, Volume = 0.5, Pitch = 1, Fallback = "UpgradeDenied" },
		LevelUp = { Id = LEVEL_UP, Volume = 0.7, Pitch = 1, Fallback = "VictorySting" },
		Hint = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.6, Pitch = 2 },
		HotColdPing = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.4, Pitch = { 1.8, 2.2 } },
		TargetReveal = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.8, Pitch = 2 },
		TargetFound = { Id = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.7, Pitch = 1.4 },
		VictorySting = { Id = "rbxasset://sounds/action_get_up.mp3", Volume = 0.9, Pitch = 1.2 },
		Notification = { Id = "rbxasset://sounds/volume_slider.ogg", Volume = 0.3, Pitch = 1.3 },
	},
}
