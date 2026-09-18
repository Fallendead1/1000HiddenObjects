--[[
	What each kind of free reward looks like and what it does, for the gift, daily reward and
	spin screens: the icon on the card (ReplicatedStorage.GameAssets.UIImages key, with a text
	glyph until the art exists) and a one-line explanation shown after it's claimed.

	A reward is any table with the fields RetentionService.Grant and the daily rewards use:
	Cash, XP, Hint ("QuickHint" / "SuperHint"), Boost ("CashBoost" / "StrengthBoost"), Egg.
]]

export type Info = { Icon: string, Glyph: string, Color: string, Explain: string }

local KINDS: { [string]: Info } = {
	Cash = { Icon = "Icon_Cash", Glyph = "$", Color = "Cash", Explain = "Saved Cash stays with you. Spend it on eggs in the Pet Shop!" },
	XP = { Icon = "Icon_XP", Glyph = "XP", Color = "Cyan", Explain = "XP levels you up and unlocks new cleaner titles." },
	QuickHint = { Icon = "Icon_Prod_QuickHint", Glyph = "?", Color = "Purple", Explain = "Quick Hint: gives you the next clue to the hidden object in a room." },
	SuperHint = { Icon = "Icon_Prod_SuperHint", Glyph = "?!", Color = "Red", Explain = "Super Hint: lights up the area where the hidden object is." },
	CashBoost = { Icon = "Icon_Prod_Cash10Min", Glyph = "2X", Color = "Green", Explain = "2X Cash: every object you clean into a bin pays double." },
	StrengthBoost = { Icon = "Icon_Prod_Strength10Min", Glyph = "2X", Color = "Orange", Explain = "2X Strength: lift heavier junk than your upgrades allow." },
	Egg = { Icon = "Gift_Box", Glyph = "EGG", Color = "Pink", Explain = "Hatch it for a helper pet that cleans rooms with you!" },
}

local RewardInfo = {}

-- The info for one kind: "Cash", "XP", "QuickHint", "SuperHint", "CashBoost", "StrengthBoost", "Egg".
function RewardInfo.Kind(kind: string): Info?
	return KINDS[kind]
end

-- The most special part of a reward (a hint or a boost beats Cash or XP) and its explanation.
-- A bundle explains its special part and mentions the rest.
function RewardInfo.Of(reward: { [string]: any }?): Info
	local r = reward or {}
	local main: Info? = nil
	if r.Hint then
		main = KINDS[r.Hint]
	elseif r.Boost then
		main = KINDS[r.Boost]
	elseif r.Egg then
		local egg = table.clone(KINDS.Egg)
		egg.Icon = "Egg_" .. tostring(r.Egg)
		main = egg
	elseif r.XP and not r.Cash then
		main = KINDS.XP
	end
	main = main or KINDS.Cash
	local info = table.clone(main :: Info)
	if (r.Hint or r.Boost or r.Egg) and (r.Cash or r.XP) then
		info.Explain ..= if r.Cash then " (The Cash is saved for the Pet Shop.)" else " (The XP levels you up.)"
	end
	return info
end

return RewardInfo
