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
	QueueCountdown = 10,
	FullQueueCountdown = 3,
	QueueRadius = 9,
	QueuePollInterval = 0.2,
	MatchWaitForPartySeconds = 20,

	-- Searching
	SearchDistance = 8,
	SearchLineOfSight = true,
	BaseMessPerTick = 3, -- mess removed per tick at Search Power 1.0
	SearchLeniencyDistance = 3, -- extra tolerance on top of reach for validation
	SearchRemoteRateLimit = 8, -- max SearchStart/Stop calls per second

	-- Economy
	CashPerMess = 1,
	MaxCashMultiplier = 4,
	MaxTempSearchPowerMultiplier = 2.5,
	TrashChuteRadius = 7,
	SellPollInterval = 0.25,
	AutoSellDelay = 0.4,

	-- Progress / checkpoints
	Checkpoints = { 0.25, 0.50, 0.75, 0.90 },

	PartyMessMultiplier = {
		[1] = 1.00,
		[2] = 1.65,
		[3] = 2.30,
		[4] = 2.95,
	},

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
	LeaderboardFastestPrefix = "FastestRoom_v1_",
	AutosaveInterval = 120,
	LeaderboardRefreshInterval = 60,
	MinimumLegitimateRoomTime = 60, -- seconds; faster results are treated as invalid

	TotalObjects = 1000,
}
