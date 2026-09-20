--[[
	The lobby's two reward stations (SocialService, client SocialController):
	  Reward  "Like the game for a FREE PET": join the group, favourite and like the game, press
	          CHECK, wait for the countdown, press CHECK again. One reward per player, ever.
	  Event   "JOIN EVENT": Roblox's own "notify me" card for the experience event in EventId.

	Roblox only lets a game verify the group (not the like or the favourite), which is why the
	countdown gives the player time to do those in the prompts and on the game's page.
]]

return {
	GroupId = 506801379, -- Game Factory Studio
	RequireGroup = true, -- the reward needs the player to really be in the group
	RewardPet = "SockPuppy", -- a Common pet (the welcome pet is the Dust Bunny)
	CheckSeconds = 10, -- CHECK turns into this countdown before it can be pressed again
	EventId = "", -- the experience event's id (Creator Hub > Events); empty: the station says "coming soon"
	OpenDistance = 7, -- studs from a station's middle that opens its card
	LookDistance = 34, -- closer than this, the floating icon turns to face you
}
