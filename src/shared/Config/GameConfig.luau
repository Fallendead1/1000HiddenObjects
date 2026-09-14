--[[
	Central game configuration. Every tunable number that is not upgrade,
	monetization, audio or room specific lives here.
]]

return {
	-- When true, missing Place IDs fall back to a single-place "Combined" server
	-- that runs the lobby and local matches together so the game is fully testable.
	DevelopmentMode = true,

	-- Extra UserIds that may use developer tools outside Studio (leave empty for production).
	DeveloperUserIds = {},

	-- Place IDs. Leave at 0 until the places exist on Creator Hub.
	LobbyPlaceId = 0,
	MatchPlaceId = 0,

	-- Queue / matchmaking
	MaxPartySize = 4,
	QueueCountdown = 20, -- how long a party waits for players (the host can start early)
	FullQueueCountdown = 3,
	QueueRadius = 8.5,
	QueuePollInterval = 0.2,
	MatchWaitForPartySeconds = 20,
	-- The first player in an empty circle picks the room. After this many seconds without a
	-- choice the queue auto-selects their highest unlocked room so groups never stall.
	QueueSelectionTimeout = 25,

	-- Physical grab / throw
	GrabDistance = 9, -- studs from the character to the closest point of the object
	GrabLeniency = 2.5, -- extra server tolerance for latency
	GrabRateLimit = 6, -- grab + throw requests per second
	HoldDistance = 3, -- studs in front of the character (plus object radius)
	HoldMaxDistance = 12, -- server snaps a held object back if a client drags it farther
	HoldBaseResponsiveness = 40, -- AlignPosition responsiveness at Strength Lv. 1 / weight 1
	HoldWeightFalloff = 0.18, -- responsiveness /= 1 + weight * falloff
	ThrowUpwardBias = 0.25, -- extra lift so throws arc
	ThrowGravityScale = 0.45, -- gravity felt by a thrown object until its first impact (floaty arcs)
	ThrowWeightFalloff = 0.08, -- speed *= clamp(1.3 - weight * falloff, 0.55, 1.2)
	SettleSpeed = 1.2, -- studs/second below which a thrown object counts as still
	SettleTime = 1.2, -- seconds it must stay still before it counts as landed
	MaxFlightTime = 8, -- stop tracking a flight after this long no matter what
	OwnedFlightTime = 1.5, -- the thrower keeps simulating its throw (no hitch) until first impact or this
	RoomSettleSeconds = 10, -- max time a freshly built room gets to settle under physics

	-- Junk chunks
	ChunkBurstSpeed = 7, -- outward speed of the pieces

	-- The key "rattles" the junk over it when a player's hands are close
	KeyRattleDistance = 6,
	KeyRattleInterval = 1.6,
	-- Junk still covering the key when its chunk bursts is blasted outward. Gravity is ~196
	-- studs/s^2, so the lift must be big to clear the spot (38 -> ~3.7 studs up, ~0.4 s aloft).
	KeyBurstSpeed = 16,
	KeyBurstLift = 38,

	-- Economy
	MaxCashMultiplier = 4,
	MaxTempStrengthMultiplier = 2.5,
	MaxWeightCap = 10,

	-- Progress / checkpoints
	-- Fractions of the room CLEANED (objects deposited in bins). A run finds the key long before
	-- most of the room is cleaned, so checkpoints sit early.
	Checkpoints = { 0.05, 0.10, 0.15, 0.20 },

	-- Hot / cold distances (studs to target cluster center)
	HotCold = {
		Warm = 30,
		Hot = 18,
		VeryHot = 9,
		PollInterval = 0.5,
	},

	-- Match flow
	IntroSequenceSeconds = 7, -- loading -> object reveal -> 3,2,1 -> SEARCH!
	CeremonySeconds = 6,
	ReturnToLobbyDelay = 1,
	FallProtectionDepth = 40,
	CombinedRoomOffset = Vector3.new(600, 0, 0),

	-- Persistence
	DataStoreName = "PlayerData_v1",
	LeaderboardTopFinders = "TopObjectFinders_v1",
	LeaderboardMostCleaned = "MostCleaned_v1",
	LeaderboardFastestPrefix = "FastestRoom_v1_",
	AutosaveInterval = 120,
	LeaderboardRefreshInterval = 60,
	MinimumLegitimateRoomTime = 60, -- seconds; faster results are treated as invalid

	TotalObjects = 1000,
}
