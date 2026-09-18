--[[
	Pile goals. Every heap in a room is a small goal: move its junk away and it's cleared -
	"PILE CLEARED!" and a Cash bonus for the whole party - and when the room's hidden object
	isn't under it, the map ticks it off ("not here", MatchState PilesCleared). That turns
	thousands of objects into a few dozen goals, and the search into crossing piles off.

	A heap counts as cleared once at most CLEAR_SHARE of the objects it was built with still lie
	inside its footprint. Anything taken away, cleaned into a bin or burst open counts; junk that
	falls back in (or spills out of packed junk there) counts against it again. Each pile's
	progress is published in 5% steps (MatchState PileProgress_<id>) for the "THIS PILE" bar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)

local Services = require(script.Parent)

local PileService = {}

local CLEAR_SHARE = 0.15 -- cleared once no more than this share is left in the footprint
local MIN_OBJECTS = 8 -- smaller heaps aren't goals
local MARGIN = 1 -- studs around a heap's footprint that still count as on it
local CHECK_EVERY = 1.5

type Pile = { Id: string, Center: Vector3, Half: Vector2, Total: number, Cleared: boolean, Shown: number }

local piles: { [string]: Pile } = {}
local pileOf: { [BasePart]: string } = setmetatable({}, { __mode = "k" }) :: any
local activeMatch = nil

local function stateConfig(): Configuration
	return Services.MatchService.GetStateConfig()
end

local function inFootprint(pile: Pile, pos: Vector3): boolean
	return math.abs(pos.X - pile.Center.X) <= pile.Half.X and math.abs(pos.Z - pile.Center.Z) <= pile.Half.Y
end

-- How many of each pile's objects are still on it (loose pieces from its packed junk too).
local function countRemaining(match): { [string]: number }
	local left = {}
	for _, root in ipairs(match.Runtime.Objects) do
		if root.Parent and (root:GetAttribute("HeldByUserId") or 0) == 0 then
			local id = pileOf[root]
			if id == nil then
				id = root:GetAttribute("OriginalClusterId") or ""
				pileOf[root] = id
			end
			local pile = piles[id]
			if pile and not pile.Cleared and inFootprint(pile, root.Position) then
				left[id] = (left[id] or 0) + 1
			end
		end
	end
	return left
end

local function publishCleared(match)
	local ids = {}
	for id, pile in pairs(piles) do
		-- The pile hiding the object is never ticked off: that would give it away.
		if pile.Cleared and id ~= match.TargetSocket.PileId then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	stateConfig():SetAttribute("PilesCleared", table.concat(ids, ","))
end

local function setProgress(pile: Pile, fraction: number)
	local shown = math.floor(fraction * 20) / 20
	if shown ~= pile.Shown then
		pile.Shown = shown
		stateConfig():SetAttribute("PileProgress_" .. pile.Id, shown)
	end
end

-- The room's heaps become goals (called at SEARCH!, after a resumed room's pre-clean): heaps
-- that are already clear start ticked off, with no reward.
function PileService.Setup(match)
	PileService.Reset()
	activeMatch = match
	local origin = match.Runtime.Origin
	for _, def in ipairs(match.Config.Piles or {}) do
		if def.Layout == "Heap" and def.Center and def.Size then
			piles[def.Id] = {
				Id = def.Id,
				Center = origin:PointToWorldSpace(def.Center),
				Half = Vector2.new(def.Size.X / 2 + MARGIN, def.Size.Y / 2 + MARGIN),
				Total = 0,
				Cleared = false,
				Shown = -1,
			}
		end
	end
	for _, root in ipairs(match.Runtime.Objects) do
		local id = root:GetAttribute("OriginalClusterId") or ""
		pileOf[root] = id
		if piles[id] then
			piles[id].Total += 1
		end
	end
	local left = countRemaining(match)
	for id, pile in pairs(piles) do
		if pile.Total < MIN_OBJECTS then
			piles[id] = nil
		elseif (left[id] or 0) <= pile.Total * CLEAR_SHARE and id ~= match.TargetSocket.PileId then
			pile.Cleared = true
			setProgress(pile, 1)
		else
			setProgress(pile, 1 - (left[id] or 0) / pile.Total)
		end
	end
	publishCleared(match)
end

function PileService.Reset()
	for id in pairs(piles) do
		stateConfig():SetAttribute("PileProgress_" .. id, nil)
	end
	piles = {}
	activeMatch = nil
	stateConfig():SetAttribute("PilesCleared", "")
end

local function onCleared(match, pile: Pile)
	pile.Cleared = true
	setProgress(pile, 1)
	local notHere = pile.Id ~= match.TargetSocket.PileId
	local amount = 15 + math.floor(pile.Total / 2)
	for _, player in ipairs(match.Players) do
		if player.Parent then
			Services.EconomyService.AddCash(player, amount)
			Remotes.Event("FXEvent"):FireClient(player, "PileCleared", { Position = pile.Center, Amount = amount, NotHere = notHere })
			Services.AnalyticsService.Event(player, "pile_cleared", pile.Total, "room " .. tostring(match.RoomId), notHere and "not here" or "the object's pile")
		end
	end
	publishCleared(match)
end

function PileService.Start()
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local match = Services.MatchService.GetMatch()
			if match ~= activeMatch or not match or match.State ~= "Searching" or not match.TargetSocket then
				continue
			end
			local left = countRemaining(match)
			for id, pile in pairs(piles) do
				if not pile.Cleared then
					local remaining = left[id] or 0
					setProgress(pile, math.clamp(1 - remaining / pile.Total, 0, 1))
					if remaining <= pile.Total * CLEAR_SHARE then
						onCleared(match, pile)
					end
				end
			end
		end
	end)
end

return PileService
