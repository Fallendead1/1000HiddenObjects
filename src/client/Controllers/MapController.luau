--[[
	The room map and the clue guidance (colour zones: Shared/Utility/Zones, RoomConfigs Zones).

	  Map         a small top-down map of the room (desktop: bottom left; touch: top of the left
	              column): the colour zones with their names, the bins, the door, you (an arrow
	              that turns with your view) and your teammates, and the clues so far - the other
	              half dimmed (clue 1), the clue zone lit up (clue 2), the gold ring (clue 3), and
	              a tick on every pile cleared that didn't hide the object.
	  In the room the clue zone glows (see-through boxes over its areas), its hanging sign
	              flashes, and a column of gold light stands around the object (clue 3).
	  Arrow       above the hover card: points toward the clue zone (then the ring) and says how
	              far, until you're there.
	It all reads MatchState (ClueSide, ClueZone, ClueSpot + ClueSpotRadius, PilesCleared,
	RoomOrigin); a Super Hint adds the zone and ring for its buyer only (MatchUpdate "SuperClue").
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local DepositConfig = require(Shared.Config.DepositConfig)
local RoomRegistry = require(Shared.Config.RoomConfigs)
local Remotes = require(Shared.Utility.Remotes)
local Zones = require(Shared.Utility.Zones)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local MapController = {}

local MAP_WIDTH = 196
local GOLD = Color3.fromRGB(255, 205, 60)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local config = nil
local origin = CFrame.new()
local scale = 1
local mapSize = Vector2.zero

local panel: Frame? = nil
local area: Frame? = nil
local binLayer: Frame? = nil
local zoneFrames: { [string]: { Frame } } = {}
local shade: Frame? = nil
local ring: Frame? = nil
local you: TextLabel? = nil
local mateDots: { [Player]: Frame } = {}
local pileMarks: { [string]: TextLabel } = {}

local worldGlow: { Instance } = {}
local glowZone = ""
local pillar: Model? = nil
local pillarKey = ""

-- A Super Hint's zone and ring (for its buyer only).
local superZone: string? = nil
local superSpot: Vector3? = nil
local superRadius = 0

local compass: Frame
local compassArrow: TextLabel
local compassLabel: TextLabel
local pileBar: Frame
local pileFill: Frame
local pileLabel: TextLabel

local function inRoom(): boolean
	local s = matchState:GetAttribute("State")
	return player:GetAttribute("InMatch") == true and (s == "Countdown" or s == "Searching")
end

local function roomModel(): Instance?
	return workspace:FindFirstChild("Room" .. (matchState:GetAttribute("RoomNumber") or ""))
end

-- Room-local (X, Z) to a position on the map (the door is at the bottom).
local function toMap(x: number, z: number): UDim2
	return UDim2.fromOffset((x + config.Size.X / 2) * scale, (z + config.Size.Z / 2) * scale)
end

local function toLocal(world: Vector3): Vector3
	return origin:PointToObjectSpace(world)
end

-- ===== The map =====

local function clearMap()
	if panel then
		panel:Destroy()
	end
	panel, area, binLayer, shade, ring, you = nil, nil, nil, nil, nil, nil
	zoneFrames, mateDots, pileMarks = {}, {}, {}
end

local function drawBins()
	if not binLayer then
		return
	end
	binLayer:ClearAllChildren()
	local room = roomModel()
	for _, mouth in ipairs(room and room:GetDescendants() or {}) do
		if mouth:IsA("BasePart") and CollectionService:HasTag(mouth, "DepositBin") then
			local def = DepositConfig.Types[mouth:GetAttribute("BinType") or ""]
			local p = toLocal(mouth.Position)
			local b = UI.Frame({ Name = "Bin", BackgroundColor3 = def and def.Color or WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(p.X, p.Z), Size = UDim2.fromOffset(8, 8), ZIndex = 5 }, binLayer)
			UI.Stroke(b, BLACK, 1.5)
		end
	end
end

local function buildMap()
	clearMap()
	config = RoomRegistry.Get(matchState:GetAttribute("RoomId") or 0)
	if not config or #Zones.List(config) == 0 then
		config = nil
		return
	end
	local o = matchState:GetAttribute("RoomOrigin")
	origin = typeof(o) == "CFrame" and o or CFrame.new()
	scale = MAP_WIDTH / config.Size.X
	mapSize = Vector2.new(MAP_WIDTH, math.floor(config.Size.Z * scale + 0.5))
	local stack = Controllers.HUDController.GetSideStack()
	panel = UI.Panel({ Name = "RoomMap", Size = UDim2.fromOffset(mapSize.X + 12, mapSize.Y + 12), AnchorPoint = if stack then Vector2.zero else Vector2.new(0, 1), Position = if stack then UDim2.new() else UDim2.new(0, 12, 1, -12), BackgroundTransparency = 0.1, LayoutOrder = 0 }, stack or UI.Layers.HUD)
	area = UI.Frame({ Name = "Area", BackgroundColor3 = Color3.fromRGB(24, 26, 38), Size = UDim2.fromOffset(mapSize.X, mapSize.Y), Position = UDim2.fromOffset(6, 6), ClipsDescendants = true }, panel)
	UI.Corner(area :: Frame, 6)

	for _, zone in ipairs(Zones.List(config)) do
		local color = Zones.ColorOf(zone)
		local frames = {}
		for _, r in ipairs(Zones.Rects(config, zone)) do
			local f = UI.Frame({ Name = "Zone_" .. zone.Id, BackgroundColor3 = color, BackgroundTransparency = if zone.Upstairs then 0.85 else 0.45, AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(r.Center.X, r.Center.Y), Size = UDim2.fromOffset(r.Size.X * scale, r.Size.Y * scale), ZIndex = if zone.Upstairs then 3 else 2 }, area)
			UI.Corner(f, 3)
			if zone.Upstairs then
				UI.Stroke(f, color, 2)
			end
			table.insert(frames, f)
		end
		zoneFrames[zone.Id] = frames
		local c = Zones.Center(config, zone)
		UI.Label({ Name = "ZoneName", Text = zone.Short or zone.Name, FitText = 10, AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(c.X, c.Y), Size = UDim2.fromOffset(64, 12), ZIndex = 6 }, area)
	end
	-- The door, where you come in.
	local spawnX = config.SpawnPosition and config.SpawnPosition.X or 0
	UI.Frame({ Name = "Door", BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 1), Position = toMap(spawnX, config.Size.Z / 2), Size = UDim2.fromOffset(8 * scale, 3), ZIndex = 6 }, area)

	binLayer = UI.Frame({ Name = "Bins", BackgroundTransparency = 1, ZIndex = 5 }, area)
	drawBins()

	-- Clue 1: the other half of the room is dimmed.
	shade = UI.Frame({ Name = "Shade", BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, Size = UDim2.fromOffset(mapSize.X / 2, mapSize.Y), Visible = false, ZIndex = 4 }, area)
	-- Clue 3: the gold ring.
	ring = UI.Frame({ Name = "Ring", BackgroundColor3 = GOLD, BackgroundTransparency = 0.7, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 7 }, area)
	UI.Corner(ring :: Frame, 999)
	UI.Stroke(ring :: Frame, GOLD, 2)
	-- You: an arrow that turns with your view.
	you = UI.Label({ Name = "You", Text = "▲", TextSize = 14, TextColor3 = GOLD, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16), ZIndex = 9 }, area)
end

-- ===== Clues on the map and in the room =====

local function currentZone(): string
	if superZone and superZone ~= "" then
		return superZone
	end
	return matchState:GetAttribute("ClueZone") or ""
end

local function currentSpot(): (Vector3?, number)
	if superSpot then
		return superSpot, superRadius
	end
	local radius = matchState:GetAttribute("ClueSpotRadius") or 0
	local spot = matchState:GetAttribute("ClueSpot")
	if radius > 0 and typeof(spot) == "Vector3" then
		return spot, radius
	end
	return nil, 0
end

local function clearGlow()
	for _, p in ipairs(worldGlow) do
		p:Destroy()
	end
	worldGlow = {}
	glowZone = ""
end

-- The clue zone's hanging sign flashes white and gold for a few seconds.
local function flashSign(zoneId: string)
	local room = roomModel()
	local folder = room and room:FindFirstChild("Wayfinding")
	local sign = folder and folder:FindFirstChild("ZoneSign_" .. zoneId)
	if not sign then
		return
	end
	for _, gui in ipairs(sign:GetChildren()) do
		local border = gui:IsA("SurfaceGui") and gui:FindFirstChild("Border", true)
		if border and border:IsA("UIStroke") then
			local base = border.Thickness
			task.spawn(function()
				for _ = 1, 6 do
					UI.Tween(border, { Color = GOLD, Thickness = base * 2.4 }, 0.35)
					task.wait(0.45)
					UI.Tween(border, { Color = WHITE, Thickness = base }, 0.35)
					task.wait(0.45)
				end
			end)
		end
	end
end

-- A thin rod of steady light between two points (no fill, nothing that can flicker against the
-- floor or the junk).
local function lightRod(a: Vector3, b: Vector3, thickness: number, color: Color3, transparency: number, parent: Instance): BasePart
	local rod = Instance.new("Part")
	rod.Name = "LightRod"
	rod.Anchored = true
	rod.CanCollide = false
	rod.CanQuery = false
	rod.CanTouch = false
	rod.CastShadow = false
	rod.Material = Enum.Material.Neon
	rod.Color = color
	rod.Transparency = transparency
	rod.Size = Vector3.new(thickness, thickness, (b - a).Magnitude + thickness)
	rod.CFrame = CFrame.lookAt((a + b) / 2, b)
	rod.Parent = parent
	return rod
end

local RAIL_HEIGHT = 7 -- studs over the floor: above the junk, below the hanging signs

-- A glowing rail around each of the clue zone's areas, on four corner posts (the room config's
-- regions). Steady light, in the zone's colour.
local function glowZoneInRoom(zoneId: string)
	if glowZone == zoneId then
		return
	end
	clearGlow()
	glowZone = zoneId
	local zone = config and Zones.Get(config, zoneId)
	if not zone then
		return
	end
	local color = Zones.ColorOf(zone)
	for _, region in ipairs(config.Regions or {}) do
		if table.find(zone.Regions, region.Id) then
			local holder = Instance.new("Model")
			holder.Name = "ZoneGlow"
			holder.Parent = workspace.CurrentCamera
			table.insert(worldGlow, holder)
			local hx, hz = region.Size.X / 2 - 0.3, region.Size.Z / 2 - 0.3
			local base = region.Center.Y - region.Size.Y / 2
			local corners = {}
			for i, c in ipairs({ Vector3.new(-hx, 0, -hz), Vector3.new(hx, 0, -hz), Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz) }) do
				corners[i] = Vector3.new(region.Center.X + c.X, base, region.Center.Z + c.Z)
			end
			local up = Vector3.new(0, RAIL_HEIGHT, 0)
			for i = 1, 4 do
				local a, b = origin * corners[i], origin * corners[i % 4 + 1]
				lightRod(a + up, b + up, 0.35, color, 0.1, holder)
				lightRod(a, a + up, 0.2, color, 0.45, holder)
			end
		end
	end
	flashSign(zoneId)
end

-- A hoop of gold light hanging over the junk around the object, on thin posts (steady, no fill).
local function showPillar(spot: Vector3?, radius: number)
	local key = if spot then string.format("%.1f,%.1f,%.1f", spot.X, spot.Z, radius) else ""
	if key == pillarKey then
		return
	end
	pillarKey = key
	if pillar then
		pillar:Destroy()
		pillar = nil
	end
	if not spot then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "ClueRing"
	holder.Parent = workspace.CurrentCamera
	pillar = holder
	local floorY = origin.Position.Y
	local segments = 28
	local function at(i: number, y: number): Vector3
		local a = i / segments * math.pi * 2
		return Vector3.new(spot.X + math.cos(a) * radius, floorY + y, spot.Z + math.sin(a) * radius)
	end
	for i = 1, segments do
		lightRod(at(i, RAIL_HEIGHT - 1), at(i + 1, RAIL_HEIGHT - 1), 0.4, GOLD, 0, holder)
		if i % 4 == 0 then
			lightRod(at(i, 0), at(i, RAIL_HEIGHT - 1), 0.2, GOLD, 0.4, holder)
		end
	end
end

local function refreshClues()
	if not config or not area then
		return
	end
	-- Clue 1: dim the other half (LEFT = -X, the left of the map).
	local side = matchState:GetAttribute("ClueSide") or ""
	if shade then
		shade.Visible = side == "LEFT" or side == "RIGHT"
		shade.Position = if side == "LEFT" then UDim2.fromOffset(mapSize.X / 2, 0) else UDim2.fromOffset(0, 0)
	end
	-- Clue 2: the zone lights up, the rest fades.
	local zoneId = currentZone()
	for id, frames in pairs(zoneFrames) do
		local zone = Zones.Get(config, id)
		for _, f in ipairs(frames) do
			local stroke = f:FindFirstChild("ClueStroke")
			if zoneId == "" then
				f.BackgroundTransparency = if zone and zone.Upstairs then 0.85 else 0.45
				if stroke then
					stroke:Destroy()
				end
			elseif id == zoneId then
				f.BackgroundTransparency = 0.1
				if not stroke then
					local s = UI.Stroke(f, GOLD, 2)
					s.Name = "ClueStroke"
				end
			else
				f.BackgroundTransparency = 0.8
				if stroke then
					stroke:Destroy()
				end
			end
		end
	end
	if zoneId ~= "" and matchState:GetAttribute("State") == "Searching" then
		glowZoneInRoom(zoneId)
	elseif zoneId == "" then
		clearGlow()
	end
	-- Clue 3: the ring.
	local spot, radius = currentSpot()
	if ring then
		ring.Visible = spot ~= nil
		if spot then
			local p = toLocal(spot)
			ring.Position = toMap(p.X, p.Z)
			ring.Size = UDim2.fromOffset(radius * 2 * scale, radius * 2 * scale)
		end
	end
	showPillar(if matchState:GetAttribute("State") == "Searching" then spot else nil, radius)
end

-- Ticks on piles cleared that didn't hide the object (MatchState PilesCleared, pile ids).
local function refreshPiles()
	if not config or not area then
		return
	end
	local cleared = {}
	for id in string.gmatch(matchState:GetAttribute("PilesCleared") or "", "[^,]+") do
		cleared[id] = true
	end
	for _, pile in ipairs(config.Piles or {}) do
		local mark = pileMarks[pile.Id]
		if cleared[pile.Id] and not mark and pile.Center then
			mark = UI.Label({ Name = "Cleared", Text = "✓", TextSize = 12, TextColor3 = Color3.fromRGB(120, 255, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = toMap(pile.Center.X, pile.Center.Z), Size = UDim2.fromOffset(12, 12), ZIndex = 8 }, area)
			UI.PopIn(mark, 0.4, 0.3)
			pileMarks[pile.Id] = mark
		end
	end
end

-- ===== Per frame: you, teammates, the arrow =====

local function step()
	local visible = inRoom() and config ~= nil and panel ~= nil
	if panel then
		panel.Visible = visible
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not visible or not root then
		compass.Visible = false
		pileBar.Visible = false
		return
	end
	local camera = workspace.CurrentCamera
	local me = toLocal(root.Position)
	if you then
		you.Position = toMap(me.X, me.Z)
		local look = origin:VectorToObjectSpace(camera.CFrame.LookVector)
		you.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end
	-- Teammates in this room.
	local seen = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local r = other ~= player and other:GetAttribute("InMatch") and other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and area then
			local dot = mateDots[other]
			if not dot then
				dot = UI.Frame({ Name = "Mate", BackgroundColor3 = WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6), ZIndex = 8 }, area)
				UI.Corner(dot, 3)
				mateDots[other] = dot
			end
			local p = toLocal(r.Position)
			dot.Position = toMap(p.X, p.Z)
			seen[other] = true
		end
	end
	for other, dot in pairs(mateDots) do
		if not seen[other] then
			dot:Destroy()
			mateDots[other] = nil
		end
	end

	-- Standing on a heap that's a goal: how much of it is cleared.
	local onPile = nil
	for _, pile in ipairs(config.Piles or {}) do
		if pile.Layout == "Heap" and pile.Center and pile.Size and math.abs(me.X - pile.Center.X) <= pile.Size.X / 2 + 1 and math.abs(me.Z - pile.Center.Z) <= pile.Size.Y / 2 + 1 then
			local progress = matchState:GetAttribute("PileProgress_" .. pile.Id)
			if progress and progress < 1 then
				onPile = progress
				break
			end
		end
	end
	pileBar.Visible = onPile ~= nil and matchState:GetAttribute("State") == "Searching"
	if onPile then
		pileFill.Size = UDim2.fromScale(math.max(0.02, onPile), 1)
		pileLabel.Text = string.format("THIS PILE: %d%% CLEARED", math.floor(onPile * 100 + 0.5))
	end

	-- The arrow: toward the ring (clue 3) or else the clue zone, until you're there.
	local spot, radius = currentSpot()
	local target: Vector3? = nil
	local label = ""
	if spot then
		local flat = Vector3.new(spot.X - root.Position.X, 0, spot.Z - root.Position.Z)
		if flat.Magnitude > radius then
			target = spot
			label = string.format("GOLD RING  ·  %d studs", math.floor(flat.Magnitude - radius + 0.5))
		end
	else
		local zone = Zones.Get(config, currentZone())
		if zone and not Zones.Contains(config, zone, Vector2.new(me.X, me.Z)) then
			local c = Zones.Center(config, zone)
			target = origin:PointToWorldSpace(Vector3.new(c.X, 0, c.Y))
			local d = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z).Magnitude
			label = string.format("%s ZONE  ·  %d studs", string.upper(zone.Color), math.floor(d + 0.5))
			compassArrow.TextColor3 = Zones.ColorOf(zone)
		end
	end
	compass.Visible = target ~= nil and matchState:GetAttribute("State") == "Searching"
	if target then
		if spot then
			compassArrow.TextColor3 = GOLD
		end
		local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		local dir = Vector3.new(target.X - camera.CFrame.Position.X, 0, target.Z - camera.CFrame.Position.Z)
		if look.Magnitude > 0.01 and dir.Magnitude > 0.01 then
			look, dir = look.Unit, dir.Unit
			local cross = look.Z * dir.X - look.X * dir.Z
			compassArrow.Rotation = -math.deg(math.atan2(cross, look:Dot(dir)))
		end
		compassLabel.Text = label
	end
end

-- ===== Lifecycle =====

local function onState()
	local s = matchState:GetAttribute("State")
	if s == "Countdown" or s == "Searching" then
		if not panel then
			buildMap()
		elseif s == "Searching" then
			drawBins() -- the room has fully arrived by now
		end
		refreshClues()
		refreshPiles()
	elseif s == "Loading" or s == "None" or s == "Ended" then
		clearMap()
		clearGlow()
		showPillar(nil, 0)
		superZone, superSpot, superRadius = nil, nil, 0
	else
		-- The object was found: the room guidance goes away, the map stays until the room ends.
		clearGlow()
		showPillar(nil, 0)
	end
end

function MapController.Init()
	compass = UI.Panel({ Name = "ClueCompass", Size = UDim2.fromOffset(250, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -122), BackgroundTransparency = 0.15, Visible = false }, UI.Layers.HUD)
	UI.Stroke(compass, GOLD, 2)
	local disc = UI.Frame({ BackgroundColor3 = Color3.fromRGB(20, 22, 34), Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(4, 4) }, compass)
	UI.Corner(disc, 16)
	compassArrow = UI.Label({ Text = "▲", TextSize = 22, TextColor3 = GOLD, Size = UDim2.fromScale(1, 1) }, disc)
	compassLabel = UI.Label({ Text = "", FitText = 17, TextWrapped = false, Size = UDim2.new(1, -46, 1, 0), Position = UDim2.fromOffset(42, 0), TextXAlignment = Enum.TextXAlignment.Left }, compass)

	-- "THIS PILE: 60% CLEARED" while you stand on a heap (PileService).
	pileBar = UI.Panel({ Name = "PileBar", Size = UDim2.fromOffset(230, 24), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -168), BackgroundTransparency = 0.15, Visible = false }, UI.Layers.HUD)
	local track = UI.Frame({ BackgroundColor3 = Color3.fromRGB(24, 26, 38), Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4) }, pileBar)
	UI.Corner(track, 6)
	pileFill = UI.Frame({ BackgroundColor3 = UI.Colors.Green, Size = UDim2.fromScale(0, 1) }, track)
	UI.Corner(pileFill, 6)
	pileLabel = UI.Label({ Text = "", FitText = 13, TextWrapped = false, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, track)

	for _, name in ipairs({ "ClueSide", "ClueZone", "ClueSpot", "ClueSpotRadius" }) do
		matchState:GetAttributeChangedSignal(name):Connect(refreshClues)
	end
	matchState:GetAttributeChangedSignal("PilesCleared"):Connect(refreshPiles)
	matchState:GetAttributeChangedSignal("State"):Connect(onState)
	matchState:GetAttributeChangedSignal("RoomId"):Connect(function()
		clearMap()
		superZone, superSpot, superRadius = nil, nil, 0
		onState()
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(onState)
	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName, payload)
		if eventName == "SuperClue" and type(payload) == "table" then
			superZone = payload.ZoneId
			superSpot = typeof(payload.Center) == "Vector3" and payload.Center or nil
			superRadius = tonumber(payload.Radius) or 0
			if superZone then
				glowZone = "" -- flash its sign even if the party already had this zone
			end
			refreshClues()
		end
	end)
end

function MapController.Start()
	onState()
	RunService.RenderStepped:Connect(step)
end

return MapController
