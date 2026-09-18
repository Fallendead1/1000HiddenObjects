--[[
	Central game configuration. Every tunable number that is not upgrade,
	monetization, audio or room specific lives here.
]]

return {
	-- When true, Studio runs a single-place "Combined" server (the lobby and local matches
	-- together) so the game is fully testable there. Live servers use the Place IDs below.
	DevelopmentMode = true,

	-- Extra UserIds that may use developer tools outside Studio (leave empty for production).
	DeveloperUserIds = {},

	-- Place IDs: the lobby is the start place; every party gets its own private match server.
	-- Rooms run in reserved servers of the lobby place itself (MatchInLobbyPlace), so there is
	-- one place to publish. MatchPlaceId is the old separate "Match Server" place: a server there
	-- still works as a match server. LobbyPlaceId 0 = single-place Combined servers.
	LobbyPlaceId = 117675182630398,
	MatchPlaceId = 122762042441174,
	MatchInLobbyPlace = true,

	-- Queue / matchmaking
	MaxPartySize = 4,
	QueueCountdown = 20, -- how long a party waits for players (the host can start early)
	FullQueueCountdown = 2, -- a full party (or a solo run) starts this soon
	QueueRadius = 8.5,
	QueuePollInterval = 0.2,
	MatchWaitForPartySeconds = 20,
	-- A match server waits (up to this long) for every party member's game to finish loading
	-- before the intro starts, so slow phones don't miss the intro and countdown.
	ClientReadyWaitSeconds = 20,
	-- The first player in an empty circle hosts it. If they haven't created a party after this
	-- many seconds, they're moved out of the circle so it frees up for everyone else.
	QueueSelectionTimeout = 25,
	-- Circles are walled: touching the ring teleports you in (if you may join) and BACK / LEAVE
	-- teleports you out. Studs past the ring that count as touching it:
	QueueTouchMargin = 2,
	QueueRejoinCooldown = 3, -- seconds before someone moved out of a circle can be pulled back in

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
	KeyRattleDistance = 10,
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

	-- Where the key hides. Normal runs keep it under junk the first Strength upgrade can lift
	-- (weight 3); Hard Mode can bury it under anything. A brand-new player's easy first run puts
	-- it under light junk close to where they start, and it glints through the pile.
	KeyMaxBlockerWeight = 3,
	EasySpotMaxDistance = 32, -- studs from the room spawn
	KeyGlintInterval = 3, -- seconds between glints on the easy first run

	-- Clues arrive on a timer (seconds of searching): side, area, region, hot/cold, outline.
	-- Every object cleaned into a bin brings the next clue this many seconds closer. The easy
	-- first run has its own quick schedule; Hard Mode waits longer.
	ClueTimes = { 60, 150, 240, 330, 420 },
	EasyClueTimes = { 20, 45, 70, 95, 130 },
	HardClueTimeScale = 1.5,
	ClueSecondsPerDeposit = 2,

	-- Hot / cold distances (studs to target cluster center)
	HotCold = {
		Warm = 30,
		Hot = 18,
		VeryHot = 9,
		PollInterval = 0.5,
	},

	-- Match flow
	-- Room start: the intro (room name, then the object to find) plays while the fresh room
	-- settles behind the loading screen; the 3, 2, 1 starts once it has, then SEARCH!
	IntroMinSeconds = 2.4, -- the room name and the object reveal always get this long
	CountdownSeconds = 2.1, -- 3, 2, 1 at 0.7 s each (LoadingController ticks the same)
	CeremonySeconds = 6,
	ReturnToLobbyDelay = 1,
	FallProtectionDepth = 40,
	CombinedRoomOffset = Vector3.new(600, 0, 0),

	-- Persistence
	DataStoreName = "PlayerData_v1",
	LeaderboardTopFinders = "TopObjectFinders_v1",
	LeaderboardMostCleaned = "MostCleaned_v1",
	LeaderboardMostPlayed = "MostPlayed_v1", -- all-time active play, in seconds
	LeaderboardFastestPrefix = "FastestRoom_v1_",
	AutosaveInterval = 120,
	LeaderboardRefreshInterval = 60,
	MinimumLegitimateRoomTime = 60, -- seconds; faster results are treated as invalid

	TotalObjects = 1000,
}
