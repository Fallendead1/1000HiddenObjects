--[[
	The lasting Cash wallet (WalletService). Room Cash still resets every room and buys upgrades;
	a share of what you earn in a room is saved to your wallet, which stays with you and buys
	eggs in the Pet Shop.

	Only the base pay counts toward the wallet: the right bin, swishes, streaks and the party
	bonus do, paid multipliers (the 2x Cash pass and 2x Cash boosts) never do. So the wallet
	(and the eggs it buys) can't be bought with Robux, which keeps eggs out of the paid random
	item rules. The Pet Shop still shows every egg's odds.
]]

return {
	-- Share of each deposit's base pay that is saved to the wallet (fractions add up per player).
	WalletShare = 0.1,

	-- Saved to the wallet when a room is completed (everyone in the party unless noted).
	RoomComplete = 50,
	RoomCompleteHardBonus = 25, -- extra on Hard Mode
	KeyFound = 25, -- the finder only
	FirstClear = 100, -- the first time a player completes that room
	MegaRoomBonus = 150, -- extra for completing a Mega room (they are about twice as long)
	Star = 25, -- per newly earned mastery star
	Challenge = 25, -- per daily challenge completed

	-- Friends in your party: this much more room Cash for everyone who has a friend with them.
	FriendBonus = 0.25,
}
