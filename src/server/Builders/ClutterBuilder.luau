--[[
	Generates every individual movable clutter object for a room from its Piles config and
	owns the final-art replacement pipeline.

	Each object is ONE BasePart root (the physics body + all gameplay attributes), tagged
	"Clutter", named by ObjectId. Placeholder detail parts and final-art parts are welded,
	massless, non-colliding children of that root, so every system only ever deals with the root.
	Objects are built anchored (placement needs static geometry to stack against) and then
	released to real physics by RoomService.SettleAndSnapshot before anyone plays.

	Layouts:
	  Heap   - a mound stacked with a height map (heavier items tend to sit lower)
	  Row    - items standing upright in a line (books on shelves, clothes on a rail)
	  Carpet - the whole floor tiled with layered flat junk so the ground disappears

	Every Heap/Carpet placement is rejected if it would intersect furniture or clutter that is
	already there, and each object takes the region it actually lands in.

	Attributes: ObjectId, AssetKey, DisplayName, Category, RegionId, Weight, CashValue,
	OriginalCFrame, OriginalClusterId, DepthLayer, Movable, State (+ IsChunk/Contents on junk
	chunks, tag Treasure on treasures).

	Final art: put a Model/BasePart named <AssetKey> in ServerStorage.ClutterAssets. Every
	object with that key (every room) gets it, scaled to the object's size, same CFrame/ids.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ClutterConfig = require(ReplicatedStorage.Shared.Config.ClutterConfig)

local ClutterBuilder = {}

local CELL = 0.5
local placeParams = OverlapParams.new()
placeParams.FilterType = Enum.RaycastFilterType.Include
-- Rectangles (room-local XZ) no pile may place into: deposit bins and a margin around them.
local keepOut: { { Center: Vector2, Size: Vector2 } } = {}
local spawnCounter = 0
local spawnRng = Random.new()

local function hashString(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function sortedKeys(mix: { [string]: number }): { string }
	local keys = {}
	for k in pairs(mix) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function pickFromMix(rng: Random, mix: { [string]: number }, keys: { string }): string
	local total = 0
	for _, k in ipairs(keys) do
		total += mix[k]
	end
	local roll = rng:NextNumber() * total
	for _, k in ipairs(keys) do
		roll -= mix[k]
		if roll <= 0 then
			return k
		end
	end
	return keys[#keys]
end

-- Local-space bounds of an asset (root + extras) at scale 1: returns min, max.
local boundsCache: { [string]: { Vector3 } } = {}
local function assetBounds(def): (Vector3, Vector3)
	local cached = boundsCache[def.Key]
	if cached then
		return cached[1], cached[2]
	end
	local half = def.Size / 2
	local mn, mx = -half, half
	for _, extra in ipairs(def.Extras or {}) do
		local eh = extra.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local p = extra.Offset:PointToWorldSpace(Vector3.new(eh.X * sx, eh.Y * sy, eh.Z * sz))
					mn = Vector3.new(math.min(mn.X, p.X), math.min(mn.Y, p.Y), math.min(mn.Z, p.Z))
					mx = Vector3.new(math.max(mx.X, p.X), math.max(mx.Y, p.Y), math.max(mx.Z, p.Z))
				end
			end
		end
	end
	boundsCache[def.Key] = { mn, mx }
	return mn, mx
end

local function applyShape(part: Part, shape: string?)
	if shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
	end
end

local function rootSize(def, scale: number): Vector3
	local size = def.Size * scale
	if def.Shape == "Ball" then
		local d = math.max(size.X, size.Y, size.Z)
		size = Vector3.new(d, d, d)
	end
	return size
end

local function makeRoot(def, scale: number, color: Color3, cframe: CFrame): BasePart
	local root: BasePart
	-- Round things get a box collider with the round shape as a welded visual: loose cylinders
	-- and balls roll forever and keep whole piles awake, which is what costs physics time.
	local rounded = def.Shape == "Ball" or def.Shape == "Cylinder"
	if def.Shape == "Wedge" then
		root = Instance.new("WedgePart")
	else
		root = Instance.new("Part")
	end
	root.Size = rootSize(def, scale)
	if rounded then
		local body = Instance.new("Part")
		body.Name = "Body"
		applyShape(body, def.Shape)
		body.Size = root.Size
		body.CFrame = cframe
		body.Color = color
		body.Material = def.Material
		body.TopSurface = Enum.SurfaceType.Smooth
		body.BottomSurface = Enum.SurfaceType.Smooth
		body.Anchored = false
		body.CanCollide = false
		body.CanQuery = true
		body.CanTouch = false
		body.Massless = true
		body.CastShadow = def.Weight >= ClutterConfig.PlayerCollisionWeight
		body:SetAttribute("PlaceholderVisual", true)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = body
		weld.Parent = body
		body.Parent = root
		root.Transparency = 1
	end
	root.CFrame = cframe
	root.Color = color
	root.Material = def.Material
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	-- No bounce + high friction: thrown things thud and stop where they land, and piles go to sleep.
	root.CustomPhysicalProperties = PhysicalProperties.new(0.7, 1, 0, 1, 100)
	root.CastShadow = def.Weight >= ClutterConfig.PlayerCollisionWeight
	root.CollisionGroup = def.Weight >= ClutterConfig.PlayerCollisionWeight and "ClutterHeavy" or "Clutter"

	for i, extra in ipairs(def.Extras or {}) do
		local e = Instance.new("Part")
		e.Name = "Detail" .. i
		applyShape(e, extra.Shape)
		e.Size = extra.Size * scale
		e.CFrame = cframe * CFrame.new(extra.Offset.Position * scale) * extra.Offset.Rotation
		e.Color = extra.Color or color
		e.Material = extra.Material or def.Material
		e.Anchored = false
		e.CanCollide = false
		e.CanQuery = true
		e.CanTouch = false
		e.Massless = true
		e.CastShadow = false
		e:SetAttribute("PlaceholderVisual", true)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = e
		weld.Parent = e
		e.Parent = root
	end
	return root
end

-- Swap placeholder visuals for final art if ServerStorage.ClutterAssets.<AssetKey> exists.
function ClutterBuilder.ApplyFinalAsset(root: BasePart): boolean
	local library = ServerStorage:FindFirstChild("ClutterAssets")
	local source = library and library:FindFirstChild(root:GetAttribute("AssetKey") or "")
	if not source then
		return false
	end
	for _, child in ipairs(root:GetChildren()) do
		if child:GetAttribute("PlaceholderVisual") or child:GetAttribute("FinalVisual") then
			child:Destroy()
		end
	end
	local clone = source:Clone()
	local parts = {}
	-- Fit the art into the object's FULL placeholder outline (root + detail parts), centred on
	-- that outline, so a duck's head or a laptop's lid isn't squashed into the root box.
	local def = ClutterConfig.Get(root:GetAttribute("AssetKey") or "")
	local boxSize, boxCF = root.Size, root.CFrame
	if def then
		local s = root.Size.X / math.max(rootSize(def, 1).X, 0.001)
		local mn, mx = assetBounds(def)
		boxSize = (mx - mn) * s
		boxCF = root.CFrame * CFrame.new((mn + mx) / 2 * s)
	end
	if clone:IsA("Model") then
		local _, size = clone:GetBoundingBox()
		local fit = math.min(boxSize.X / math.max(size.X, 0.01), boxSize.Y / math.max(size.Y, 0.01), boxSize.Z / math.max(size.Z, 0.01))
		clone:ScaleTo(clone:GetScale() * fit)
		local bbCF = clone:GetBoundingBox()
		clone:PivotTo(boxCF * bbCF:ToObjectSpace(clone:GetPivot()))
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	elseif clone:IsA("BasePart") then
		clone.Size = boxSize
		clone.CFrame = boxCF
		table.insert(parts, clone)
	end
	for _, p in ipairs(parts) do
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = true
		p.CanTouch = false
		p.Massless = true
		-- One mesh, many colours: parts marked Tintable take this object's rolled colour.
		if p:GetAttribute("Tintable") == true then
			p.Color = root.Color
		end
		p:SetAttribute("FinalVisual", true)
		for _, j in ipairs(p:GetChildren()) do
			if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
				j:Destroy()
			end
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		p.Parent = root
	end
	clone:Destroy()
	root.Transparency = 1
	root:SetAttribute("FinalAsset", true)
	return true
end

local function finalize(root: BasePart, def, meta, folder: Instance)
	root.Name = meta.ObjectId
	root:SetAttribute("ObjectId", meta.ObjectId)
	root:SetAttribute("AssetKey", def.Key)
	root:SetAttribute("DisplayName", def.DisplayName)
	root:SetAttribute("Category", def.Category)
	root:SetAttribute("RegionId", meta.RegionId)
	root:SetAttribute("Weight", def.Weight)
	root:SetAttribute("CashValue", def.CashValue)
	root:SetAttribute("OriginalCFrame", root.CFrame)
	root:SetAttribute("OriginalClusterId", meta.PileId)
	root:SetAttribute("DepthLayer", meta.DepthLayer)
	root:SetAttribute("Movable", true)
	root:SetAttribute("State", "Resting")
	if def.Category == "Chunk" then
		root:SetAttribute("IsChunk", true)
		root:SetAttribute("Contents", table.concat(meta.Contents or {}, ","))
	elseif def.Category == "Treasure" then
		CollectionService:AddTag(root, "Treasure")
	end
	CollectionService:AddTag(root, "Clutter")
	ClutterBuilder.ApplyFinalAsset(root)
	root.Parent = folder
end

-- The smallest configured region containing a room-local point (nearest one otherwise).
local function regionFor(config, localPos: Vector3): string
	local best, bestVolume = nil, math.huge
	for _, r in ipairs(config.Regions or {}) do
		local d = localPos - r.Center
		if math.abs(d.X) <= r.Size.X / 2 and math.abs(d.Y) <= r.Size.Y / 2 + 1 and math.abs(d.Z) <= r.Size.Z / 2 then
			local volume = r.Size.X * r.Size.Y * r.Size.Z
			if volume < bestVolume then
				best, bestVolume = r.Id, volume
			end
		end
	end
	if best then
		return best
	end
	local nearest = math.huge
	for _, r in ipairs(config.Regions or {}) do
		local d = Vector2.new(localPos.X - r.Center.X, localPos.Z - r.Center.Z).Magnitude
		if d < nearest then
			best, nearest = r.Id, d
		end
	end
	return best or "CenterFloor"
end

local function insideExclusion(exclusions, x: number, z: number): boolean
	for _, rect in ipairs(exclusions or {}) do
		if math.abs(x - rect.Center.X) <= rect.Size.X / 2 and math.abs(z - rect.Center.Y) <= rect.Size.Y / 2 then
			return true
		end
	end
	return false
end

-- Would a box here intersect furniture or clutter that is already placed? Full size: clutter
-- is loose physics, and any spawn overlap turns into jitter that stops piles from sleeping.
local function fits(cframe: CFrame, size: Vector3): boolean
	return #workspace:GetPartBoundsInBox(cframe, size, placeParams) == 0
end

local function maybeTreasure(rng: Random, key: string): string
	if rng:NextNumber() < ClutterConfig.TreasureChance then
		return ClutterConfig.TreasureKeys[rng:NextInteger(1, #ClutterConfig.TreasureKeys)]
	end
	return key
end

-- What a junk chunk bursts into: real objects from the pile's own mix.
local function rollContents(rng: Random, mix, keys: { string }, range: { number }?): { string }
	local contents = {}
	local lo, hi = (range and range[1]) or 5, (range and range[2]) or 8
	for _ = 1, rng:NextInteger(lo, hi) do
		table.insert(contents, maybeTreasure(rng, pickFromMix(rng, mix, keys)))
	end
	return contents
end

-- Stack `pile.Count` objects into a height map over the pile's footprint.
local function buildHeap(pile, config, origin: CFrame, rng: Random, folder: Instance, newId, out)
	local keys = sortedKeys(pile.Mix)
	local picks = {}
	for _ = 1, pile.Count do
		local def = ClutterConfig.Get(maybeTreasure(rng, pickFromMix(rng, pile.Mix, keys)))
		if def then
			table.insert(picks, { Def = def, Order = def.Weight + rng:NextNumber() * 2.5 })
		end
	end
	-- The bottom share of the pile is packed junk (Order 100+ sorts it to the bottom).
	for i = 1, math.floor(#picks * (pile.ChunkFraction or 0)) do
		local chunk = ClutterConfig.Get(ClutterConfig.ChunkKeys[rng:NextInteger(1, #ClutterConfig.ChunkKeys)])
		picks[i] = { Def = chunk, Order = 100 + rng:NextNumber(), Contents = rollContents(rng, pile.Mix, keys, pile.ChunkContents) }
	end
	-- Heavier things tend to go down first so big boxes/bins end up at the bottom of piles.
	table.sort(picks, function(a, b)
		return a.Order > b.Order
	end)

	local sizeX, sizeZ = pile.Size.X, pile.Size.Y
	local nx, nz = math.max(1, math.ceil(sizeX / CELL)), math.max(1, math.ceil(sizeZ / CELL))
	local heights = table.create(nx * nz, 0)
	local function cellRange(cx: number, hx: number, n: number, size: number): (number, number)
		local a = math.clamp(math.floor((cx - hx + size / 2) / CELL) + 1, 1, n)
		local b = math.clamp(math.floor((cx + hx + size / 2) / CELL) + 1, 1, n)
		return a, b
	end
	local scaleMin, scaleMax = pile.ScaleMin or 0.9, pile.ScaleMax or 1.12

	local layer = 0
	for _, pick in ipairs(picks) do
		local def = pick.Def
		local scale = rng:NextNumber(scaleMin, scaleMax)
		local mn, mx = assetBounds(def)
		mn, mx = mn * scale, mx * scale
		local height = mx.Y - mn.Y
		if height <= pile.MaxHeight then
			local yaw = rng:NextNumber(0, math.pi * 2)
			local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
			local ex, ez = (mx.X - mn.X) / 2, (mx.Z - mn.Z) / 2
			local hx, hz = c * ex + s * ez, s * ex + c * ez
			local candidates = {}
			for _ = 1, pile.Tries or 10 do
				local px, pz
				if pile.Uniform then
					px = rng:NextNumber(-sizeX / 2 + hx * 0.5, math.max(-sizeX / 2 + hx * 0.5, sizeX / 2 - hx * 0.5))
					pz = rng:NextNumber(-sizeZ / 2 + hz * 0.5, math.max(-sizeZ / 2 + hz * 0.5, sizeZ / 2 - hz * 0.5))
				else
					local r = rng:NextNumber() ^ 0.75 * 0.5
					local ang = rng:NextNumber(0, math.pi * 2)
					px = math.clamp(math.cos(ang) * r * sizeX, -sizeX / 2 + hx * 0.6, sizeX / 2 - hx * 0.6)
					pz = math.clamp(math.sin(ang) * r * sizeZ, -sizeZ / 2 + hz * 0.6, sizeZ / 2 - hz * 0.6)
				end
				if not insideExclusion(pile.Exclusions, pile.Center.X + px, pile.Center.Z + pz) and not insideExclusion(keepOut, pile.Center.X + px, pile.Center.Z + pz) then
					local ax, bx = cellRange(px, hx, nx, sizeX)
					local az, bz = cellRange(pz, hz, nz, sizeZ)
					local top = 0
					for ix = ax, bx do
						for iz = az, bz do
							top = math.max(top, heights[(iz - 1) * nx + ix])
						end
					end
					if top + height <= pile.MaxHeight then
						table.insert(candidates, { px, pz, ax, bx, az, bz, top })
					end
				end
			end
			-- Lowest spot first (fills outward, then upward), skipping anything that would clip.
			table.sort(candidates, function(a, b)
				return a[7] < b[7]
			end)
			local tilt = pile.Tilt or 2
			local rotation = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(rng:NextNumber(-tilt, tilt)), 0, math.rad(rng:NextNumber(-tilt, tilt)))
			for _, cand in ipairs(candidates) do
				-- A small gap so unanchored neighbours never start interpenetrating (they'd be kicked apart).
				local localPos = Vector3.new(pile.Center.X + cand[1], pile.Center.Y + cand[7] - mn.Y + 0.08, pile.Center.Z + cand[2])
				local cf = origin * CFrame.new(localPos) * rotation
				if fits(cf, rootSize(def, scale)) then
					layer += 1
					local root = makeRoot(def, scale, def.Colors[rng:NextInteger(1, #def.Colors)], cf)
					local region = pile.RegionId or regionFor(config, localPos)
					finalize(root, def, { ObjectId = newId(def), RegionId = region, PileId = pile.PileId or pile.Id, DepthLayer = layer, Contents = pick.Contents }, folder)
					table.insert(out, root)
					local newTop = cand[7] + height
					for ix = cand[3], cand[4] do
						for iz = cand[5], cand[6] do
							heights[(iz - 1) * nx + ix] = newTop
						end
					end
					break
				end
			end
		end
	end
end

local function buildRow(pile, origin: CFrame, rng: Random, folder: Instance, newId, out)
	local keys = sortedKeys(pile.Mix)
	local from = Vector3.new(pile.From.X, 0, pile.From.Z)
	local to = Vector3.new(pile.To.X, 0, pile.To.Z)
	local length = (to - from).Magnitude
	local dir = (to - from).Unit
	local cursor = rng:NextNumber(0, 0.3)
	local layer = 0
	while true do
		local def = ClutterConfig.Get(pickFromMix(rng, pile.Mix, keys))
		if not def then
			break
		end
		local thickness, height = def.Size.Y, def.Size.X
		if cursor + thickness > length then
			break
		end
		layer += 1
		local center = from + dir * (cursor + thickness / 2)
		-- Upright: the asset's X becomes vertical, its thickness (Y) runs along the row.
		local pos = Vector3.new(center.X, pile.BaseY + height / 2 + 0.02, center.Z)
		local lean = rng:NextNumber() < 0.12 and math.rad(rng:NextNumber(-12, 12)) or 0
		local cf = origin * CFrame.fromMatrix(pos, Vector3.yAxis, dir) * CFrame.Angles(0, lean, 0)
		local root = makeRoot(def, 1, def.Colors[rng:NextInteger(1, #def.Colors)], cf)
		finalize(root, def, { ObjectId = newId(def), RegionId = pile.RegionId, PileId = pile.Id, DepthLayer = layer }, folder)
		table.insert(out, root)
		cursor += thickness + rng:NextNumber(0.03, 0.25)
	end
end

-- Carpet: tile a rectangle with small uniform heaps so the floor disappears under junk.
local function buildCarpet(pile, config, origin: CFrame, folder: Instance, newId, out, variant)
	local tile = pile.Tile or 8
	local nx = math.ceil(pile.Size.X / tile)
	local nz = math.ceil(pile.Size.Y / tile)
	local startX = pile.Center.X - pile.Size.X / 2
	local startZ = pile.Center.Z - pile.Size.Y / 2
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local w = math.min(tile, pile.Size.X - ix * tile)
			local d = math.min(tile, pile.Size.Y - iz * tile)
			local tileCenter = Vector3.new(startX + ix * tile + w / 2, pile.Center.Y, startZ + iz * tile + d / 2)
			local rng = Random.new(hashString(config.Name .. pile.Id .. ix .. ":" .. iz .. tostring(variant or 1)))
			buildHeap({
				Id = pile.Id,
				PileId = pile.Id,
				Center = tileCenter,
				Size = Vector2.new(w, d),
				Count = math.floor(w * d * pile.Density + 0.5),
				MaxHeight = pile.MaxHeight,
				Mix = pile.Mix,
				Uniform = true,
				-- Flat and many attempts: carpet has to find every gap between heaps and furniture.
				Tilt = 1,
				Tries = 16,
				ScaleMin = pile.ScaleMin,
				ScaleMax = pile.ScaleMax,
				Exclusions = pile.Exclusions,
			}, config, origin, rng, folder, newId, out)
		end
	end
end

-- Builds all piles (heaps and rows first, then carpets filling the gaps between them).
-- `solids` = furniture/walls that clutter must never intersect. Needs the room in Workspace.
function ClutterBuilder.Build(config, origin: CFrame, folder: Instance, variant: number?, solids: { BasePart }?): { BasePart }
	local started = os.clock()
	local prefix = config.ObjectPrefix or ("Room" .. config.DisplayNumber)
	local counters: { [string]: number } = {}
	local function newId(def): string
		counters[def.Category] = (counters[def.Category] or 0) + 1
		return string.format("%s_%s_%04d", prefix, def.Category, counters[def.Category])
	end
	local filter = { folder }
	for _, part in ipairs(solids or {}) do
		table.insert(filter, part)
	end
	placeParams.FilterDescendantsInstances = filter
	keepOut = {}
	for _, bin in ipairs(config.DepositBins or {}) do
		table.insert(keepOut, { Center = Vector2.new(bin.Center.X, bin.Center.Z), Size = Vector2.new(bin.Size.X + 3, bin.Size.Z + 3) })
	end

	local out = {}
	for _, pile in ipairs(config.Piles or {}) do
		if pile.Layout == "Row" then
			buildRow(pile, origin, Random.new(hashString(config.Name .. pile.Id .. tostring(variant or 1))), folder, newId, out)
		elseif pile.Layout ~= "Carpet" then
			local heap = table.clone(pile)
			heap.Count = math.floor(pile.Count * (config.CountMultiplier or 1) + 0.5)
			if pile.Center.Y == 0 and pile.MaxHeight > 2 then
				heap.MaxHeight = pile.MaxHeight + (config.FloorHeapHeightBonus or 0)
				-- Only real floor heaps get packed-junk bottoms (not scatter, shelves or furniture tops).
				heap.ChunkFraction = config.ChunkFraction
				heap.ChunkContents = config.ChunkContents
			end
			buildHeap(heap, config, origin, Random.new(hashString(config.Name .. pile.Id .. tostring(variant or 1))), folder, newId, out)
		end
	end
	local piled = #out
	for _, pile in ipairs(config.Piles or {}) do
		if pile.Layout == "Carpet" then
			buildCarpet(pile, config, origin, folder, newId, out, variant)
		end
	end
	local chunks, hidden, treasures = 0, 0, 0
	for _, root in ipairs(out) do
		if root:GetAttribute("IsChunk") then
			chunks += 1
			hidden += #string.split(root:GetAttribute("Contents") or "", ",")
		elseif root:GetAttribute("Category") == "Treasure" then
			treasures += 1
		end
	end
	print(string.format("[ClutterBuilder] %s: %d physics bodies (%d in heaps/rows, %d floor carpet), %d junk chunks holding %d more objects, %d treasures, built in %.2fs",
		config.Name, #out, piled, #out - piled, chunks, hidden, treasures, os.clock() - started))
	return out
end

-- Create one more object at runtime (junk chunk pieces). Same attributes/tags/final art as
-- built objects; ids continue with an X counter so they never collide with built ones.
function ClutterBuilder.Spawn(config, folder: Instance, key: string, cframe: CFrame, meta: { RegionId: string, PileId: string }): BasePart?
	local def = ClutterConfig.Get(key)
	if not def then
		return nil
	end
	spawnCounter += 1
	local prefix = config.ObjectPrefix or ("Room" .. config.DisplayNumber)
	local root = makeRoot(def, 1, def.Colors[spawnRng:NextInteger(1, #def.Colors)], cframe)
	finalize(root, def, {
		ObjectId = string.format("%s_%s_X%04d", prefix, def.Category, spawnCounter),
		RegionId = meta.RegionId,
		PileId = meta.PileId,
		DepthLayer = 0,
	}, folder)
	return root
end

-- Local-space bounds (min, max) of an asset at scale 1, root + extras.
function ClutterBuilder.Bounds(key: string): (Vector3?, Vector3?)
	local def = ClutterConfig.Get(key)
	if not def then
		return nil, nil
	end
	return assetBounds(def)
end

return ClutterBuilder
