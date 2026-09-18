--[[
	Room zones. Every room groups its search regions into a few colour-coded zones with one
	simple name (RoomConfigs: Room.Zones). Clues name a zone ("the TEAL zone: HAMPER CORNER"),
	a sign hangs over each zone in the room (RoomService) and the map in the corner draws them
	(MapController). Zone names never reuse a bin's word (TOYS, LAUNDRY, GAMES...), so a clue
	can't be mistaken for a bin.

	A zone: { Id, Name, Short? (for the map), Color (a key of Zones.Colors), Regions = { region
	ids }, Sign = Vector3? (room-local spot for its sign; Y 0 = the usual height), Upstairs? }
]]

local Zones = {}

Zones.Colors = {
	Red = Color3.fromRGB(255, 95, 95),
	Orange = Color3.fromRGB(255, 150, 50),
	Yellow = Color3.fromRGB(255, 205, 60),
	Green = Color3.fromRGB(95, 210, 95),
	Teal = Color3.fromRGB(40, 205, 190),
	Blue = Color3.fromRGB(80, 155, 255),
	Purple = Color3.fromRGB(175, 115, 255),
	Pink = Color3.fromRGB(255, 125, 200),
}

export type Rect = { Center: Vector2, Size: Vector2 }

function Zones.List(config): { any }
	return config and config.Zones or {}
end

function Zones.Get(config, id: string?)
	for _, zone in ipairs(Zones.List(config)) do
		if zone.Id == id then
			return zone
		end
	end
	return nil
end

-- The zone a search region belongs to.
function Zones.ForRegion(config, regionId: string?)
	for _, zone in ipairs(Zones.List(config)) do
		if table.find(zone.Regions, regionId) then
			return zone
		end
	end
	return nil
end

function Zones.ColorOf(zone): Color3
	return zone and Zones.Colors[zone.Color] or Color3.new(1, 1, 1)
end

-- Room-local floor rectangles (X, Z) a zone covers: its regions' footprints.
function Zones.Rects(config, zone): { Rect }
	local rects = {}
	for _, region in ipairs(config.Regions or {}) do
		if table.find(zone.Regions, region.Id) then
			table.insert(rects, { Center = Vector2.new(region.Center.X, region.Center.Z), Size = Vector2.new(region.Size.X, region.Size.Z) })
		end
	end
	return rects
end

-- Room-local (X, Z) min and max corners of a zone.
function Zones.Bounds(config, zone): (Vector2, Vector2)
	local mn, mx = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, r in ipairs(Zones.Rects(config, zone)) do
		mn = Vector2.new(math.min(mn.X, r.Center.X - r.Size.X / 2), math.min(mn.Y, r.Center.Y - r.Size.Y / 2))
		mx = Vector2.new(math.max(mx.X, r.Center.X + r.Size.X / 2), math.max(mx.Y, r.Center.Y + r.Size.Y / 2))
	end
	if mn.X == math.huge then
		return Vector2.zero, Vector2.zero
	end
	return mn, mx
end

-- Where a zone "is" (room-local X, Z): its sign spot, else the middle of its area.
function Zones.Center(config, zone): Vector2
	if zone.Sign then
		return Vector2.new(zone.Sign.X, zone.Sign.Z)
	end
	local mn, mx = Zones.Bounds(config, zone)
	return (mn + mx) / 2
end

-- Is a room-local (X, Z) point inside the zone?
function Zones.Contains(config, zone, point: Vector2): boolean
	for _, r in ipairs(Zones.Rects(config, zone)) do
		if math.abs(point.X - r.Center.X) <= r.Size.X / 2 and math.abs(point.Y - r.Center.Y) <= r.Size.Y / 2 then
			return true
		end
	end
	return false
end

return Zones
