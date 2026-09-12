--[[
	Builds the small placeholder lobby from primitives. Everything gameplay-relevant is
	tagged/attributed so a final art pass can replace the geometry without code changes.

	Tags: QueueZone, CollectionBoard, ShopStand, Leaderboard (attr Kind), LobbySpawn
]]

local CollectionService = game:GetService("CollectionService")

local LobbyBuilder = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

function LobbyBuilder.Build(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Lobby"

	local floorColor = Color3.fromRGB(60, 68, 100)
	local wallColor = Color3.fromRGB(34, 40, 62)

	part({ Name = "Floor", Size = Vector3.new(80, 2, 70), CFrame = origin * CFrame.new(0, -1, 0), Color = floorColor, Material = Enum.Material.SmoothPlastic }, model)

	-- Low walls so players cannot wander off
	local wallH = 10
	part({ Name = "WallN", Size = Vector3.new(80, wallH, 2), CFrame = origin * CFrame.new(0, wallH / 2, -35), Color = wallColor, Material = Enum.Material.SmoothPlastic }, model)
	part({ Name = "WallS", Size = Vector3.new(80, wallH, 2), CFrame = origin * CFrame.new(0, wallH / 2, 35), Color = wallColor, Material = Enum.Material.SmoothPlastic }, model)
	part({ Name = "WallE", Size = Vector3.new(2, wallH, 70), CFrame = origin * CFrame.new(40, wallH / 2, 0), Color = wallColor, Material = Enum.Material.SmoothPlastic }, model)
	part({ Name = "WallW", Size = Vector3.new(2, wallH, 70), CFrame = origin * CFrame.new(-40, wallH / 2, 0), Color = wallColor, Material = Enum.Material.SmoothPlastic }, model)

	-- Spawn facing the queue circle (queue is at -Z)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = origin * CFrame.new(0, 0.5, 22)
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(80, 90, 130)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = model
	CollectionService:AddTag(spawn, "LobbySpawn")

	-- Queue circle
	local queue = part({
		Name = "QueueZone",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 18, 18),
		CFrame = origin * CFrame.new(0, 0.3, -8) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(70, 210, 110),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.25,
	}, model)
	queue:SetAttribute("Radius", 9)
	queue:SetAttribute("State", "Empty")
	queue:SetAttribute("Count", 0)
	queue:SetAttribute("MaxPlayers", 4)
	queue:SetAttribute("Countdown", 0)
	queue:SetAttribute("Message", "STEP INSIDE TO PLAY")
	queue:SetAttribute("RoomId", 1)
	CollectionService:AddTag(queue, "QueueZone")
	part({ Name = "QueueRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 19, 19), CFrame = origin * CFrame.new(0, 0.2, -8) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic, CanCollide = false }, model)

	-- Sign post above queue (client attaches the BillboardGui)
	part({ Name = "QueueSignAnchor", Size = Vector3.new(1, 1, 1), CFrame = origin * CFrame.new(0, 9, -8), Transparency = 1, CanCollide = false, CanQuery = false }, model)

	-- Collection board (left wall)
	local board = part({ Name = "CollectionBoard", Size = Vector3.new(1, 10, 18), CFrame = origin * CFrame.new(-38.5, 6, 0), Color = Color3.fromRGB(24, 30, 48), Material = Enum.Material.SmoothPlastic }, model)
	CollectionService:AddTag(board, "CollectionBoard")

	-- Shop stand (right wall)
	local shop = part({ Name = "ShopStand", Size = Vector3.new(6, 6, 6), CFrame = origin * CFrame.new(34, 3, 8), Color = Color3.fromRGB(170, 100, 255), Material = Enum.Material.SmoothPlastic }, model)
	CollectionService:AddTag(shop, "ShopStand")
	part({ Name = "ShopRoof", Size = Vector3.new(8, 0.6, 8), CFrame = origin * CFrame.new(34, 6.6, 8), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.SmoothPlastic }, model)

	-- Leaderboards (back wall)
	local lbA = part({ Name = "Leaderboard_TopFinders", Size = Vector3.new(14, 10, 1), CFrame = origin * CFrame.new(-16, 7, -33.5), Color = Color3.fromRGB(24, 30, 48), Material = Enum.Material.SmoothPlastic }, model)
	lbA:SetAttribute("Kind", "TopFinders")
	CollectionService:AddTag(lbA, "Leaderboard")
	local lbB = part({ Name = "Leaderboard_Fastest", Size = Vector3.new(14, 10, 1), CFrame = origin * CFrame.new(16, 7, -33.5), Color = Color3.fromRGB(24, 30, 48), Material = Enum.Material.SmoothPlastic }, model)
	lbB:SetAttribute("Kind", "Fastest")
	CollectionService:AddTag(lbB, "Leaderboard")

	-- Locked future portal (right wall, forward)
	local door = part({ Name = "FutureDoor", Size = Vector3.new(1, 9, 7), CFrame = origin * CFrame.new(38.5, 4.5, -18), Color = Color3.fromRGB(60, 66, 90), Material = Enum.Material.Metal }, model)
	door:SetAttribute("Label", "MORE ROOMS COMING SOON")
	CollectionService:AddTag(door, "FutureDoor")
	part({ Name = "FutureDoorFrame", Size = Vector3.new(1.2, 10, 8), CFrame = origin * CFrame.new(38.4, 5, -18), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.SmoothPlastic }, model)
	local lock = part({ Name = "FutureDoorLock", Size = Vector3.new(0.6, 1.4, 1.4), CFrame = origin * CFrame.new(37.7, 4.5, -18), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Metal }, model)
	lock.Shape = Enum.PartType.Cylinder

	-- Decorative pillars
	for _, x in ipairs({ -30, 30 }) do
		for _, z in ipairs({ -28, 28 }) do
			part({ Name = "Pillar", Size = Vector3.new(2, 10, 2), CFrame = origin * CFrame.new(x, 5, z), Color = Color3.fromRGB(80, 90, 130), Material = Enum.Material.SmoothPlastic }, model)
		end
	end

	return model
end

return LobbyBuilder
