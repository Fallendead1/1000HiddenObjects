--[[
	Shared helpers for room configs (see Room001 for what each field means).
	  Kit.Piles(mixes)  -> heap, row, carpet builders bound to a room's mix table
	  Kit.socket        a hiding spot on a pile (Offset = XZ from the pile's centre)
	  Kit.solid / deco  placeholder furniture (PlaceholderRoomBuilder, config.Furniture);
	                    solid pieces block players and clutter, deco is looks only
	  Kit.door          the exit door on the front wall (+Z) and its frame
]]

local Kit = {}

function Kit.Piles(mixes)
	local function heap(id: string, region: string, mix: string, center: Vector3, size: Vector2, count: number, maxHeight: number)
		assert(mixes[mix], "unknown mix " .. mix)
		return { Id = id, RegionId = region, Layout = "Heap", Mix = mixes[mix], Center = center, Size = size, Count = count, MaxHeight = maxHeight }
	end
	local function row(id: string, region: string, mix: string, from: Vector3, to: Vector3, baseY: number, depthX: number)
		assert(mixes[mix], "unknown mix " .. mix)
		return { Id = id, RegionId = region, Layout = "Row", Mix = mixes[mix], From = from, To = to, BaseY = baseY, DepthX = depthX }
	end
	local function carpet(id: string, mix: string, center: Vector3, size: Vector2, density: number, maxHeight: number, exclusions, scaleMax: number?)
		assert(mixes[mix], "unknown mix " .. mix)
		return { Id = id, Layout = "Carpet", Mix = mixes[mix], Center = center, Size = size, Tile = 8, Density = density, MaxHeight = maxHeight, ScaleMin = 1.0, ScaleMax = scaleMax or 1.5, Exclusions = exclusions }
	end
	return heap, row, carpet
end

function Kit.socket(id: string, pile: string, x: number, z: number, difficulty: number?)
	return { Id = id, PileId = pile, Offset = Vector2.new(x, z), Difficulty = difficulty or 2 }
end

function Kit.solid(name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?, extra: { [string]: any }?)
	local f = { Solid = true, Name = name, Size = size, Center = center, Color = color, Material = material }
	for k, v in pairs(extra or {}) do
		f[k] = v
	end
	return f
end

function Kit.deco(name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?, extra: { [string]: any }?)
	local f = Kit.solid(name, size, center, color, material, extra)
	f.Solid = false
	return f
end

-- The way out, centred on the front wall of a 90 x 70 room.
function Kit.door(list, doorColor: Color3, frameColor: Color3)
	table.insert(list, Kit.solid("Door", Vector3.new(7, 12, 0.6), Vector3.new(0, 6, 34.6), doorColor, Enum.Material.Wood))
	table.insert(list, Kit.deco("DoorFrameL", Vector3.new(0.6, 12.6, 0.9), Vector3.new(-3.8, 6.3, 34.5), frameColor))
	table.insert(list, Kit.deco("DoorFrameR", Vector3.new(0.6, 12.6, 0.9), Vector3.new(3.8, 6.3, 34.5), frameColor))
	table.insert(list, Kit.deco("DoorFrameTop", Vector3.new(8.2, 0.6, 0.9), Vector3.new(0, 12.6, 34.5), frameColor))
	table.insert(list, Kit.deco("DoorKnob", Vector3.new(0.6, 0.6, 0.6), Vector3.new(2.6, 5.6, 34.1), Color3.fromRGB(220, 190, 90), Enum.Material.Metal, { Shape = Enum.PartType.Ball }))
end

-- A wall shelf unit against the right (+X) or left (-X) wall: back, two sides, shelves.
function Kit.shelves(list, name: string, side: number, zFrom: number, zTo: number, height: number, depth: number, levels: { number }, color: Color3, shelfColor: Color3)
	local wallX = side * 44.2
	local mid = (zFrom + zTo) / 2
	local length = math.abs(zTo - zFrom)
	local inner = side * (44.45 - depth / 2)
	table.insert(list, Kit.solid(name .. "Back", Vector3.new(0.5, height, length), Vector3.new(wallX, height / 2, mid), color, Enum.Material.Wood))
	table.insert(list, Kit.solid(name .. "SideA", Vector3.new(depth, height, 0.5), Vector3.new(inner, height / 2, math.min(zFrom, zTo)), color, Enum.Material.Wood))
	table.insert(list, Kit.solid(name .. "SideB", Vector3.new(depth, height, 0.5), Vector3.new(inner, height / 2, math.max(zFrom, zTo)), color, Enum.Material.Wood))
	for _, y in ipairs(levels) do
		table.insert(list, Kit.solid(name .. "Shelf", Vector3.new(depth, 0.4, length), Vector3.new(inner, y - 0.2, mid), shelfColor, Enum.Material.Wood))
	end
end

return Kit
