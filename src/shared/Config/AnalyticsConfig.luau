--[[
	What the game tracks (AnalyticsService sends it; Creator Hub > Analytics shows it). Funnel
	steps are numbered by their order here, so each list follows the order players go through it:
	Roblox counts a later step as passing every earlier one.
]]

local function steps(list: { { string } })
	local def = { Steps = {}, Index = {} }
	for i, pair in ipairs(list) do
		def.Steps[i] = { Key = pair[1], Name = pair[2] }
		def.Index[pair[1]] = i
	end
	return def
end

return {
	-- Brand-new players only (a profile created in the last OnboardingDays days), each step once.
	OnboardingDays = 7,
	Onboarding = steps({
		{ "Joined", "Joined the game" },
		{ "EnteredCircle", "Stepped into a circle" },
		{ "PartyReady", "Created or joined a party" },
		{ "RoomLoaded", "Room loaded (SEARCH!)" },
		{ "FirstGrab", "Grabbed something" },
		{ "FirstThrow", "Threw or dropped it" },
		{ "FirstDeposit", "First item into a bin" },
		{ "FoundKey", "Found the key" },
		{ "SecondRoom", "Started a second room" },
	}),

	-- Recurring funnels (a new session each time: a room run, a party, a shop visit, a day).
	Funnels = {
		Tutorial = steps({
			{ "Started", "Tutorial started" },
			{ "Circle", "Stepped into a circle" },
			{ "Party", "Pressed CREATE" },
			{ "RoomLoaded", "Room loaded" },
			{ "Grab", "Grabbed something" },
			{ "Deposit", "Put it in a bin" },
			{ "Upgrade", "Bought an upgrade" },
			{ "Finished", "Tutorial finished" },
		}),
		RoomRun = steps({
			{ "Started", "Room started" },
			{ "FirstDeposit", "First item into a bin" },
			{ "KeyUncovered", "Key uncovered" },
			{ "KeyFound", "Key found" },
		}),
		Party = steps({
			{ "EnteredCircle", "Stepped into a circle" },
			{ "Ready", "Party ready" },
			{ "Launched", "Sent to the room" },
			{ "Arrived", "Arrived in the room" },
		}),
		Shop = steps({
			{ "Opened", "Opened the shop" },
			{ "Prompted", "Started a purchase" },
			{ "Bought", "Bought it" },
		}),
		DailyReward = steps({
			{ "Waiting", "Daily reward waiting" },
			{ "Opened", "Opened DAILY" },
			{ "Claimed", "Claimed it" },
		}),
	},

	-- Tallied per player in each room and reported when they're done with it (room_<name>).
	RoomCounts = { "grabs", "throws", "deposits", "swishes", "chunks", "treasures", "upgrades", "hints" },

	-- What the client may report over the Track remote; anything else is ignored.
	ShopTabs = { Permanent = true, Boosts = true, Help = true },
	Platforms = { touch = true, desktop = true, gamepad = true, vr = true },

	EconomyFlushSeconds = 60, -- Cash / XP transactions are summed and sent this often
	FpsReportSeconds = 120, -- the client reports its average frame rate this often
	FpsReportsPerSession = 15,
}
