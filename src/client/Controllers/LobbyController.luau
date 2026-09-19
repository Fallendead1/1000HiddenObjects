--[[
	Lobby presentation. The lobby itself is authored in Workspace.Lobby; this controller only
	animates and labels it:
	  - QueueZone: glowing circle (Visual/GlowDisc, GlowCore, GlowRim, SparklePlane.Sparkles)
	    coloured + pulsed by queue state; a see-through wall ring (built locally, so it can
	    block only the local player when the circle is closed to them); "0/4" + status text
	    floating above; a plaque with the room and its fastest record; and a HUD pill with
	    START NOW / LEAVE while the local player is in a party.
	  - Optional tagged extras: CollectionBoard, ShopStand, Leaderboard (attr Kind), FutureDoor,
	    LobbyKeyDeco. Tag any part in the lobby to enable them.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local FormatUtil = require(Shared.Utility.FormatUtil)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local LobbyController = {}

type QueueVisual = {
	Zone: BasePart,
	Disc: BasePart?,
	Core: BasePart?,
	Light: PointLight?,
	Sparkles: ParticleEmitter?,
	Color: Color3,
	PulseSpeed: number,
}

local attached: { [Instance]: boolean } = {}
local visuals: { QueueVisual } = {}
local queuePill: Frame
local queuePillLabel: TextLabel
local queuePillStart: TextButton
local queuePillLeave: TextButton
local wallFolder: Folder? = nil

local WALL_SEGMENTS = 28
local WALL_HEIGHT = 5

-- Floating signs fade in only when the camera is close, so far-away text never turns into
-- tiny, jagged noise. Each sign draws inside a CanvasGroup that one loop fades.
local faders: { { Group: CanvasGroup, Position: Vector3, Near: number, Far: number } } = {}

local function fadeWithDistance(bb: BillboardGui, position: Vector3, near: number, far: number): CanvasGroup
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = far + 5
	local group = Instance.new("CanvasGroup")
	group.Name = "Fade"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.GroupTransparency = 1
	group.Parent = bb
	table.insert(faders, { Group = group, Position = position, Near = near, Far = far })
	return group
end

local StateStyle = {
	Empty = { Color = UI.Colors.Green, Pulse = 1.2 },
	Selecting = { Color = UI.Colors.Cyan, Pulse = 2 },
	CountingDown = { Color = UI.Colors.Gold, Pulse = 3 },
	Locked = { Color = UI.Colors.Orange, Pulse = 6 },
	Teleporting = { Color = UI.Colors.Orange, Pulse = 6 },
	Resetting = { Color = UI.Colors.Locked, Pulse = 0.6 },
}

local function zoneState(zone: BasePart): string
	return zone:GetAttribute("State") or "Empty"
end

-- The big line over a circle (players / party size) and the status line under it.
local function describe(zone: BasePart): (string, string)
	local state = zoneState(zone)
	local count = zone:GetAttribute("Count") or 0
	local max = zone:GetAttribute("MaxPlayers") or GameConfig.MaxPartySize
	local countText = string.format("%d/%d", count, max)
	if state == "Selecting" then
		if zone:GetAttribute("OwnerUserId") == player.UserId then
			return countText, "Set up your party"
		end
		return countText, (zone:GetAttribute("OwnerName") or "Someone") .. " is creating a party"
	elseif state == "CountingDown" then
		local cd = zone:GetAttribute("Countdown") or 0
		local hard = zone:GetAttribute("Hard") == true and "HARD · " or ""
		if max == 1 then
			return countText, hard .. "Solo run - starting in " .. cd
		elseif count >= max then
			return countText, hard .. "Party full - starting in " .. cd
		end
		return countText, hard .. "Touch to join - starting in " .. cd
	elseif state == "Locked" or state == "Teleporting" then
		return countText, "Starting..."
	elseif state == "Resetting" then
		return string.format("0/%d", GameConfig.MaxPartySize), "Next party..."
	end
	return countText, "Touch to create a party"
end

local WallColors = {
	Open = Color3.fromRGB(255, 244, 214),
	Setup = UI.Colors.Cyan,
	Joinable = UI.Colors.Green,
	Member = UI.Colors.Gold,
	Closed = UI.Colors.Red,
}

-- Wall colour: what touching this circle would do for the local player right now.
local function wallState(zone: BasePart): Color3
	local state = zoneState(zone)
	if state == "Empty" then
		return WallColors.Open
	elseif player:GetAttribute("QueueId") == zone:GetAttribute("QueueId") then
		return WallColors.Member
	elseif zone:GetAttribute("Joinable") == true then
		return WallColors.Joinable
	elseif state == "Selecting" then
		return WallColors.Setup
	end
	return WallColors.Closed
end

-- A see-through ring wall around a circle, with a glowing top edge. Always solid for the local
-- player (built locally, so it only ever blocks your own character): touching it teleports you
-- in when you may join, and BACK / LEAVE teleports you out (the server does both).
local function buildWall(zone: BasePart): ({ BasePart }, { BasePart }, number)
	if not wallFolder then
		wallFolder = Instance.new("Folder")
		wallFolder.Name = "LocalQueueWalls"
		wallFolder.Parent = workspace
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { zone.Parent or zone, wallFolder :: Folder, player.Character }
	local hit = workspace:Raycast(zone.Position + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0), params)
	local groundY = hit and hit.Position.Y or (zone.Position.Y - zone.Size.Y / 2)
	local radius = (zone:GetAttribute("Radius") or GameConfig.QueueRadius) + 0.25
	local width = 2 * math.pi * radius / WALL_SEGMENTS * 1.04
	local walls, rims = {}, {}
	for i = 1, WALL_SEGMENTS do
		local angle = (i - 0.5) / WALL_SEGMENTS * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local base = Vector3.new(zone.Position.X, groundY, zone.Position.Z) + offset
		local facing = CFrame.lookAt(base, base + offset)
		local wall = Instance.new("Part")
		wall.Name = "QueueWall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Material = Enum.Material.SmoothPlastic
		wall.Color = WallColors.Open
		wall.Transparency = 0.78
		wall.Size = Vector3.new(width, WALL_HEIGHT, 0.15)
		wall.CFrame = facing * CFrame.new(0, WALL_HEIGHT / 2, 0)
		wall.Parent = wallFolder
		table.insert(walls, wall)
		local rim = wall:Clone()
		rim.Name = "QueueWallRim"
		rim.Material = Enum.Material.Neon
		rim.Transparency = 0.2
		rim.Size = Vector3.new(width, 0.18, 0.2)
		rim.CFrame = facing * CFrame.new(0, WALL_HEIGHT, 0)
		rim.Parent = wallFolder
		table.insert(rims, rim)
	end
	return walls, rims, groundY
end

-- A small plaque at the circle's front edge (facing the plaza): the room and its fastest
-- record. Returns its refresh function.
local function buildPlate(zone: BasePart, groundY: number): () -> ()
	local lobby = workspace:FindFirstChild("Lobby")
	local keyDeco = lobby and lobby:FindFirstChild("LobbyKeyDeco")
	local center = keyDeco and (keyDeco :: any):GetPivot().Position or Vector3.zero
	local toCenter = Vector3.new(center.X - zone.Position.X, 0, center.Z - zone.Position.Z)
	local dir = toCenter.Magnitude > 0.1 and toCenter.Unit or Vector3.zAxis
	local radius = zone:GetAttribute("Radius") or GameConfig.QueueRadius
	local anchor = Instance.new("Attachment")
	anchor.Name = "QueuePlate"
	anchor.WorldPosition = Vector3.new(zone.Position.X, groundY + 1.4, zone.Position.Z) + dir * (radius - 1.4)
	anchor.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Name = "QueuePlate_" .. (zone:GetAttribute("QueueId") or "")
	bb.Size = UDim2.fromScale(5.5, 2.4)
	bb.Adornee = anchor
	bb.Parent = player:WaitForChild("PlayerGui")
	local group = fadeWithDistance(bb, anchor.WorldPosition, 14, 24)
	local function line(y: number, h: number, color: Color3, font: Enum.Font, maxSize: number): TextLabel
		local label = UI.Label({ Text = "", TextScaled = true, Font = font, TextColor3 = color, Size = UDim2.new(1, 0, h, 0), Position = UDim2.fromScale(0, y) }, group)
		UI.New("UITextSizeConstraint", { MaxTextSize = maxSize }, label)
		UI.Stroke(label, Color3.new(0, 0, 0), 2, 0.2)
		return label
	end
	local roomLine = line(0, 0.34, UI.Colors.Text, UI.Font, 28)
	local nameLine = line(0.34, 0.3, UI.Colors.Text, UI.FontBody, 22)
	local timeLine = line(0.64, 0.34, UI.Colors.Gold, UI.Font, 26)
	local data = ReplicatedStorage:FindFirstChild("LeaderboardData")
	local function refresh()
		local roomNumber = zone:GetAttribute("RoomNumber") or ""
		if roomNumber == "" then
			roomNumber = "001"
		end
		roomLine.Text = "ROOM #" .. roomNumber
		-- The fastest board tracks Room #001.
		local best = nil
		if roomNumber == "001" and data then
			local ok, entries = pcall(HttpService.JSONDecode, HttpService, data:GetAttribute("Fastest") or "[]")
			best = ok and type(entries) == "table" and entries[1] or nil
		end
		nameLine.Text = best and tostring(best.Name) or "No record yet"
		timeLine.Text = "🏆 " .. (best and FormatUtil.Time(best.Value or 0) or "--:--")
	end
	task.spawn(function()
		data = data or ReplicatedStorage:WaitForChild("LeaderboardData", 30)
		if data then
			data:GetAttributeChangedSignal("Fastest"):Connect(refresh)
			refresh()
		end
	end)
	refresh()
	return refresh
end

local function attachQueueZone(zone: BasePart)
	local model = zone.Parent
	local visualFolder = model and model:FindFirstChild("Visual")
	local disc = visualFolder and visualFolder:FindFirstChild("GlowDisc") :: BasePart?
	local plane = visualFolder and visualFolder:FindFirstChild("SparklePlane")
	local entry: QueueVisual = {
		Zone = zone,
		Disc = disc,
		Core = visualFolder and visualFolder:FindFirstChild("GlowCore") :: BasePart?,
		Light = disc and disc:FindFirstChildOfClass("PointLight"),
		Sparkles = plane and plane:FindFirstChildOfClass("ParticleEmitter"),
		Color = UI.Colors.Green,
		PulseSpeed = 1.2,
	}
	table.insert(visuals, entry)

	local walls, rims, groundY = buildWall(zone)
	local refreshPlate = buildPlate(zone, groundY)

	-- Floating sign over the circle (world-sized, fades in when you're close): a big clean count
	-- and a rounded status tag outlined in the circle's colour.
	local bb = UI.Billboard(zone, UDim2.fromScale(8, 3.4), Vector3.new(0, 6, 0), 60)
	bb.Name = "QueueSign_" .. (zone:GetAttribute("QueueId") or "")
	local group = fadeWithDistance(bb, zone.Position + Vector3.new(0, 6, 0), 36, 52)
	local countLabel = UI.Label({ Text = "0/4", TextScaled = true, TextColor3 = UI.Colors.Text, Size = UDim2.new(1, 0, 0.56, 0) }, group)
	UI.New("UITextSizeConstraint", { MaxTextSize = 96 }, countLabel)
	UI.Stroke(countLabel, Color3.fromRGB(20, 24, 40), 3, 0)
	local tag = UI.Frame({ Size = UDim2.new(0.94, 0, 0.36, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62, 0), BackgroundColor3 = Color3.fromRGB(20, 24, 40), BackgroundTransparency = 0.2 }, group)
	UI.New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, tag)
	local tagStroke = UI.Stroke(tag, WallColors.Open, 2, 0)
	local countdown = UI.Label({ Text = "", TextScaled = true, TextColor3 = UI.Colors.Text, Size = UDim2.new(0.9, 0, 0.7, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, tag)
	UI.New("UITextSizeConstraint", { MaxTextSize = 34 }, countdown)

	local lastCount, lastCd = zone:GetAttribute("Count") or 0, -1
	local lastWallColor: Color3? = nil
	local function refresh()
		local countText, status = describe(zone)
		countLabel.Text = countText
		countdown.Text = status
		local wallColor = wallState(zone)
		tagStroke.Color = wallColor
		if wallColor ~= lastWallColor then
			lastWallColor = wallColor
			for _, w in ipairs(walls) do
				UI.Tween(w, { Color = wallColor }, 0.3)
			end
			for _, r in ipairs(rims) do
				UI.Tween(r, { Color = wallColor }, 0.3)
			end
		end
		refreshPlate()

		local style = StateStyle[zoneState(zone)] or StateStyle.Empty
		entry.Color = style.Color
		entry.PulseSpeed = style.Pulse
		if entry.Disc then
			UI.Tween(entry.Disc, { Color = style.Color }, 0.3)
		end
		if entry.Light then
			UI.Tween(entry.Light, { Color = style.Color }, 0.3)
		end
		if entry.Sparkles then
			entry.Sparkles.Color = ColorSequence.new(style.Color)
			entry.Sparkles.Rate = zoneState(zone) == "Empty" and 5 or 14
		end

		local inThisQueue = player:GetAttribute("QueueId") == zone:GetAttribute("QueueId")
		local count = zone:GetAttribute("Count") or 0
		if count ~= lastCount then
			if inThisQueue then
				Controllers.AudioController.Play(count > lastCount and "QueueEnter" or "QueueLeave")
			end
			lastCount = count
		end
		local cdValue = zone:GetAttribute("Countdown") or 0
		if zoneState(zone) == "CountingDown" and cdValue ~= lastCd then
			lastCd = cdValue
			local sc = countdown:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, countdown)
			sc.Scale = 1.3
			UI.Tween(sc, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
			if inThisQueue and cdValue <= 3 then
				Controllers.AudioController.Play("Countdown")
			end
		end
		LobbyController.RefreshPill()
	end
	for _, name in ipairs({ "State", "Count", "MaxPlayers", "Joinable", "Countdown", "RoomNumber", "OwnerUserId", "OwnerName", "Hard" }) do
		zone:GetAttributeChangedSignal(name):Connect(refresh)
	end
	player:GetAttributeChangedSignal("QueueId"):Connect(refresh)
	refresh()
end

function LobbyController.RefreshPill()
	local queueId = player:GetAttribute("QueueId") or ""
	if queueId == "" or player:GetAttribute("InMatch") then
		queuePill.Visible = false
		return
	end
	for _, v in ipairs(visuals) do
		local zone = v.Zone
		if zone:GetAttribute("QueueId") == queueId then
			local state = zoneState(zone)
			local isHost = zone:GetAttribute("OwnerUserId") == player.UserId
			if state == "Selecting" and isHost then
				queuePill.Visible = false -- the party setup panel is showing instead
				return
			end
			local count, max = zone:GetAttribute("Count") or 0, zone:GetAttribute("MaxPlayers") or GameConfig.MaxPartySize
			local cd = zone:GetAttribute("Countdown") or 0
			local text
			if state == "Selecting" then
				text = "WAITING FOR THE HOST TO SET UP THE PARTY"
			elseif state == "CountingDown" then
				local sub = max == 1 and "Solo run" or (count >= max and "Party full!" or "Waiting for players...")
				text = string.format("ROOM #%s%s  ·  %d/%d  ·  STARTING IN %d\n%s", zone:GetAttribute("RoomNumber") or "", zone:GetAttribute("Hard") and " HARD" or "", count, max, cd, sub)
			else
				text = "STARTING..."
			end
			queuePillLabel.Text = text
			queuePillLeave.Visible = state == "Selecting" or state == "CountingDown"
			queuePillStart.Visible = state == "CountingDown" and isHost and cd > GameConfig.FullQueueCountdown
			queuePill.Visible = true
			local stroke = queuePill:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = v.Color
			end
			return
		end
	end
	queuePill.Visible = false
end

local function fitText(label: TextLabel, maxSize: number): TextLabel
	UI.New("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8 }, label)
	return label
end

-- Leaderboard kinds: which LeaderboardData attribute feeds the board, its two-colour title, and
-- whether lower values rank higher (times).
local BoardKinds = {
	TopFinders = { Title = '<font color="#FFFFFF">TOP</font> <font color="#FFD200">FINDERS</font>', Attr = "TopFinders" },
	Fastest = { Title = '<font color="#FFFFFF">FASTEST</font> <font color="#3CD2FF">ROOM #001</font>', Attr = "Fastest", Time = true },
	MostCleaned = { Title = '<font color="#FFFFFF">MOST</font> <font color="#7DFF28">CLEANED</font>', Attr = "MostCleaned" },
	MostPlayed = { Title = '<font color="#FFFFFF">TIME</font> <font color="#FF8C3C">PLAYED</font>', Attr = "MostPlayed", Duration = true },
}

-- "3h 25m" / "42m": how long someone has played, for the TIME PLAYED board.
local function playedText(seconds: number): string
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then
		return string.format("%dm", minutes)
	end
	return string.format("%dh %02dm", minutes // 60, minutes % 60)
end
local BOARD_ROWS = 100 -- GameConfig.LeaderboardSize: the list scrolls

local function attachCollectionBoard(part: BasePart)
	local sg = UI.Surface(part, (part:GetAttribute("Face") and Enum.NormalId[part:GetAttribute("Face")]) or Enum.NormalId.Front, 30)
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	-- Every board text scales to the board's real size (boards come in any dimensions).
	fitText(UI.Label({ Text = "YOUR COLLECTION", TextScaled = true, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.9, 0, 0.16, 0), Position = UDim2.fromScale(0.05, 0.04) }, panel), 54)
	local count = fitText(UI.Label({ Text = "0 / 1000", TextScaled = true, TextColor3 = UI.Colors.Gold, Size = UDim2.new(0.9, 0, 0.42, 0), Position = UDim2.fromScale(0.05, 0.22) }, panel), 130)
	local button = UI.Button({ Text = "", Color = UI.Colors.Gold, Size = UDim2.new(0.7, 0, 0.2, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.72), Shine = 3 }, panel)
	fitText(UI.Label({ Text = "VIEW COLLECTION", TextScaled = true, TextColor3 = UI.Colors.PanelDark, Size = UDim2.new(0.9, 0, 0.7, 0), Position = UDim2.fromScale(0.05, 0.15), ZIndex = 3 }, button), 44)
	button.Activated:Connect(function()
		Controllers.CollectionController.Open()
	end)
	local function refresh()
		count.Text = string.format("%d / %d", player:GetAttribute("ObjectsFound") or 0, GameConfig.TotalObjects)
	end
	player:GetAttributeChangedSignal("ObjectsFound"):Connect(refresh)
	refresh()
end

-- A small world-sized sign pill (fades in when you're close).
local function signPill(part: BasePart, text: string, color: Color3, size: UDim2, height: number, near: number, far: number)
	local offset = Vector3.new(0, part.Size.Y / 2 + height, 0)
	local bb = UI.Billboard(part, size, offset, far)
	local group = fadeWithDistance(bb, part.Position + offset, near, far)
	local pill = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 24, 40), BackgroundTransparency = 0.15 }, group)
	UI.New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	UI.Stroke(pill, color, 2, 0)
	local label = UI.Label({ Text = text, TextScaled = true, TextColor3 = color, Size = UDim2.new(0.86, 0, 0.66, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, pill)
	UI.New("UITextSizeConstraint", { MaxTextSize = 48 }, label)
end

-- The shop's sign floats over the stand's roof, big and solid so it never blends into the stand:
-- bright purple with white letters, seen from across the lobby.
local function shopSign(part: BasePart)
	local stand = part:FindFirstAncestorOfClass("Model")
	local top = part.Position.Y + part.Size.Y / 2
	if stand then
		local cf, size = stand:GetBoundingBox()
		top = cf.Position.Y + size.Y / 2
	end
	local offset = Vector3.new(0, top - part.Position.Y + 3, 0)
	local bb = UI.Billboard(part, UDim2.fromScale(9, 3), offset, 140)
	local group = fadeWithDistance(bb, part.Position + offset, 90, 140)
	local pill = UI.Frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, group)
	UI.New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
	UI.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(240, 70, 255), Color3.fromRGB(150, 0, 235)) }, pill)
	UI.Stroke(pill, Color3.new(1, 1, 1), 4, 0)
	local label = UI.Label({ Text = "SHOP", TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0.8, 0, 0.74, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, pill)
	UI.Stroke(label, Color3.fromRGB(60, 0, 100), 3, 0)
end

local function attachShopStand(part: BasePart)
	shopSign(part)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Shop"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		Controllers.ShopController.Open()
	end)
end

-- A scaled title line in the leaderboard asset's text style (heavy white, black outline).
local function boardText(parent: Instance, richText: string, font: Font?, order: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "BoardText"
	label.BackgroundTransparency = 1
	label.RichText = true
	label.Text = richText
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	if font then
		label.FontFace = font
	else
		label.Font = UI.Font
	end
	label.Size = UDim2.fromScale(0.95, height)
	label.LayoutOrder = order
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 0.1
	pcall(function()
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	end)
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- One ranked row from the asset's row design (rank 1-3 have their own looks, 4+ share one).
local function boardRow(style: Frame, rank: number, entry, def): Frame
	local row = style:Clone()
	row.Name = string.format("Rank%02d", rank)
	row.LayoutOrder = rank
	row.Visible = true
	local icon = row:FindFirstChild("PlayerIcon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", tonumber(entry.UserId) or 0)
	end
	local name = row:FindFirstChild("PlayerName")
	if name and name:IsA("TextLabel") then
		name.Text = "@" .. tostring(entry.Name or "?")
	end
	local place = row:FindFirstChild("Place")
	if place and place:IsA("TextLabel") then
		place.Text = "#" .. rank
	end
	local amount = row:FindFirstChild("Amount")
	if amount and amount:IsA("TextLabel") then
		amount.Text = if def.Time then FormatUtil.Time(entry.Value or 0) elseif def.Duration then playedText(entry.Value or 0) else FormatUtil.Compact(entry.Value or 0)
	end
	if entry.UserId == player.UserId then
		local stroke = row:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = UI.Colors.Gold
			stroke.Thickness *= 2
		end
	end
	return row
end

-- The lobby leaderboards use the imported leaderboard asset (GameAssets.LeaderboardTemplate):
-- its #1 gold / #2 silver / #3 bronze / plain rows with avatar, name and amount. Data: the
-- global OrderedDataStore tops LeaderboardService publishes on ReplicatedStorage.LeaderboardData.
local function attachLeaderboard(part: BasePart)
	local def = BoardKinds[part:GetAttribute("Kind") or "TopFinders"] or BoardKinds.TopFinders
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	local template = assets and assets:FindFirstChild("LeaderboardTemplate")
	if not (template and template:IsA("SurfaceGui")) then
		warn("[LobbyController] ReplicatedStorage.GameAssets.LeaderboardTemplate is missing - leaderboards not shown")
		return
	end
	local sg = template:Clone() :: SurfaceGui
	local list = sg:FindFirstChildWhichIsA("ScrollingFrame") or sg:FindFirstChildWhichIsA("Frame")
	if not list then
		return
	end
	-- Keep one of each row design as a style, drop the asset's placeholder rows.
	local styles: { Frame } = {}
	for i = 1, 4 do
		local style = list:FindFirstChild("Top" .. i)
		if style then
			styles[i] = style :: Frame
			style.Parent = nil
		end
	end
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") and string.match(c.Name, "^Top%d") then
			c:Destroy()
		end
	end
	for i = 2, 4 do
		styles[i] = styles[i] or styles[i - 1]
	end
	if not styles[1] then
		return
	end
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	-- The top 100 scroll (mouse wheel, or a drag on touch).
	if list:IsA("ScrollingFrame") then
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.ScrollingEnabled = true
		list.ScrollingDirection = Enum.ScrollingDirection.Y
	end
	local spacer = list:FindFirstChild("Empty")
	if spacer and spacer:IsA("GuiObject") then
		spacer.LayoutOrder = -2
	end
	sg.Name = "Leaderboard_" .. def.Attr
	sg.Adornee = part
	sg.Face = (part:GetAttribute("Face") and Enum.NormalId[part:GetAttribute("Face")]) or Enum.NormalId.Front
	sg.ResetOnSpawn = false
	sg.Enabled = true
	local nameLabel = styles[1]:FindFirstChild("PlayerName")
	local font = nameLabel and nameLabel:IsA("TextLabel") and nameLabel.FontFace or nil
	boardText(list, def.Title, font, -1, 0.12)
	sg.Parent = player:WaitForChild("PlayerGui")

	local data = ReplicatedStorage:WaitForChild("LeaderboardData")
	local rows: { Instance } = {}
	local status: TextLabel? = nil
	local function setStatus(text: string?)
		if status then
			status:Destroy()
			status = nil
		end
		if text then
			status = boardText(list, '<font color="#C8CDE0">' .. text .. "</font>", font, 1, 0.07)
		end
	end
	local function render()
		for _, r in ipairs(rows) do
			r:Destroy()
		end
		table.clear(rows)
		local raw = data:GetAttribute(def.Attr)
		local ok, entries = pcall(HttpService.JSONDecode, HttpService, raw or "")
		if raw == nil or not ok or type(entries) ~= "table" then
			setStatus("Loading...")
			return
		end
		-- One row per player, best first (fastest = lowest time); nobody ranks with nothing done.
		local seen, clean = {}, {}
		for _, e in ipairs(entries) do
			if type(e) == "table" and e.UserId and not seen[e.UserId] and (def.Time or (tonumber(e.Value) or 0) > 0) then
				seen[e.UserId] = true
				table.insert(clean, e)
			end
		end
		table.sort(clean, function(a, b)
			if def.Time then
				return (a.Value or 0) < (b.Value or 0)
			end
			return (a.Value or 0) > (b.Value or 0)
		end)
		setStatus(#clean == 0 and "No entries yet - be the first!" or nil)
		for rank = 1, math.min(#clean, BOARD_ROWS) do
			local row = boardRow(styles[math.min(rank, 4)], rank, clean[rank], def)
			row.Parent = list
			table.insert(rows, row)
		end
	end
	data:GetAttributeChangedSignal(def.Attr):Connect(render)
	render()
end

local function attachFutureDoor(part: BasePart)
	signPill(part, part:GetAttribute("Label") or "MORE ROOMS COMING SOON", UI.Colors.Gold, UDim2.fromScale(7, 1.3), 1.5, 16, 26)
end

local function spinKey(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local base = model:GetPivot()
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function()
		if model.Parent then
			local t = os.clock() - t0
			model:PivotTo(base * CFrame.new(0, math.sin(t * 1.5) * 0.6, 0) * CFrame.Angles(0, t * 0.8, 0))
		end
	end)
end

local handlers = {
	QueueZone = attachQueueZone,
	CollectionBoard = attachCollectionBoard,
	ShopStand = attachShopStand,
	Leaderboard = attachLeaderboard,
	FutureDoor = attachFutureDoor,
	LobbyKeyDeco = spinKey,
}

local function tryAttach(tag: string, inst: Instance)
	if attached[inst] then
		return
	end
	if tag ~= "LobbyKeyDeco" and not inst:IsA("BasePart") then
		return
	end
	attached[inst] = true
	task.spawn(handlers[tag], inst)
end

function LobbyController.Init()
	queuePill = UI.Panel({ Size = UDim2.fromOffset(580, 70), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Visible = false, BackgroundTransparency = 0.08 }, UI.Layers.HUD)
	queuePillLabel = UI.Label({ Text = "", TextSize = 17, TextWrapped = true, Size = UDim2.new(1, -266, 1, 0), Position = UDim2.fromOffset(12, 0), TextXAlignment = Enum.TextXAlignment.Left }, queuePill)
	queuePillStart = UI.Button({ Text = "START NOW", Color = UI.Colors.Gold, Size = UDim2.fromOffset(120, 46), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -134, 0.5, 0), TextSize = 16, Shine = 3 }, queuePill)
	queuePillLeave = UI.Button({ Text = "LEAVE", Color = UI.Colors.Red, Size = UDim2.fromOffset(110, 46), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), TextSize = 18 }, queuePill)
	local function startNow()
		Remotes.Event("StartParty"):FireServer(player:GetAttribute("QueueId"))
	end
	local function leaveQueue()
		Remotes.Event("LeaveQueue"):FireServer(player:GetAttribute("QueueId"))
	end
	queuePillStart.Activated:Connect(startNow)
	queuePillLeave.Activated:Connect(leaveQueue)
	-- Controllers: X starts now (host), B leaves; the buttons wear those badges. (Y is the shop.)
	UI.PadBadge(queuePillStart, Enum.KeyCode.ButtonX)
	UI.PadBadge(queuePillLeave, Enum.KeyCode.ButtonB)
	game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not queuePill.Visible or UI.GetOpenMenu() then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonX and queuePillStart.Visible then
			startNow()
		elseif input.KeyCode == Enum.KeyCode.ButtonB and queuePillLeave.Visible then
			leaveQueue()
		end
	end)
	player:GetAttributeChangedSignal("QueueId"):Connect(LobbyController.RefreshPill)
	player:GetAttributeChangedSignal("InMatch"):Connect(LobbyController.RefreshPill)

	for tag in pairs(handlers) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			tryAttach(tag, inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			tryAttach(tag, inst)
		end)
	end
end

function LobbyController.Start()
	-- One cheap loop pulses every circle's glow at a speed set by its state.
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local camera = workspace.CurrentCamera
		if camera then
			local eye = camera.CFrame.Position
			for _, f in ipairs(faders) do
				f.Group.GroupTransparency = math.clamp(((eye - f.Position).Magnitude - f.Near) / (f.Far - f.Near), 0, 1)
			end
		end
		for _, v in ipairs(visuals) do
			local wave = (math.sin(t * v.PulseSpeed * math.pi) + 1) / 2
			if v.Disc then
				v.Disc.Transparency = 0.25 + wave * 0.35
			end
			if v.Core then
				v.Core.Transparency = 0.4 + (1 - wave) * 0.4
			end
			if v.Light then
				v.Light.Brightness = 0.6 + wave * 1.2
			end
		end
	end)
end

return LobbyController
