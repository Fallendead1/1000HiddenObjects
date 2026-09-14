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
		if max == 1 then
			return countText, "Solo run - starting in " .. cd
		elseif count >= max then
			return countText, "Party full - starting in " .. cd
		end
		return countText, "Touch to join - starting in " .. cd
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

-- Wall colour, and whether the circle is closed to the local player right now.
local function wallState(zone: BasePart): (Color3, boolean)
	local state = zoneState(zone)
	if state == "Empty" then
		return WallColors.Open, false
	elseif player:GetAttribute("QueueId") == zone:GetAttribute("QueueId") then
		return WallColors.Member, false
	elseif zone:GetAttribute("Joinable") == true then
		return WallColors.Joinable, false
	elseif state == "Selecting" then
		return WallColors.Setup, true
	end
	return WallColors.Closed, true
end

-- A see-through ring wall around a circle, with a glowing top edge. Built locally, so it can
-- block only the local player (whose character physics is their own) when the circle is closed
-- to them. The server moves anyone out regardless.
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
		wall.CanCollide = false
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
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = player:WaitForChild("PlayerGui")
	local function line(y: number, h: number, color: Color3, font: Enum.Font, maxSize: number): TextLabel
		local label = UI.Label({ Text = "", TextScaled = true, Font = font, TextColor3 = color, Size = UDim2.new(1, 0, h, 0), Position = UDim2.fromScale(0, y) }, bb)
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

	-- Floating text over the circle, sized in studs so it shrinks with distance.
	local bb = UI.Billboard(zone, UDim2.fromScale(12, 4.4), Vector3.new(0, 6.5, 0), 140)
	bb.Name = "QueueSign_" .. (zone:GetAttribute("QueueId") or "")
	local countLabel = UI.Label({ Text = "0/4", TextScaled = true, Size = UDim2.new(1, 0, 0.58, 0) }, bb)
	UI.New("UITextSizeConstraint", { MaxTextSize = 90 }, countLabel)
	UI.Stroke(countLabel, Color3.new(0, 0, 0), 3, 0.15)
	local countdown = UI.Label({ Text = "", TextScaled = true, Size = UDim2.new(1, 0, 0.34, 0), Position = UDim2.fromScale(0, 0.62) }, bb)
	UI.New("UITextSizeConstraint", { MaxTextSize = 44 }, countdown)
	UI.Stroke(countdown, Color3.new(0, 0, 0), 3, 0.15)

	local lastCount, lastCd = zone:GetAttribute("Count") or 0, -1
	local lastWallColor: Color3? = nil
	local function refresh()
		local countText, status = describe(zone)
		countLabel.Text = countText
		countdown.Text = status
		local wallColor, blocked = wallState(zone)
		countdown.TextColor3 = wallColor == WallColors.Open and UI.Colors.Text or wallColor
		if wallColor ~= lastWallColor then
			lastWallColor = wallColor
			for _, w in ipairs(walls) do
				UI.Tween(w, { Color = wallColor }, 0.3)
			end
			for _, r in ipairs(rims) do
				UI.Tween(r, { Color = wallColor }, 0.3)
			end
		end
		for _, w in ipairs(walls) do
			w.CanCollide = blocked
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
	for _, name in ipairs({ "State", "Count", "MaxPlayers", "Joinable", "Countdown", "RoomNumber", "OwnerUserId", "OwnerName" }) do
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
				text = string.format("ROOM #%s  ·  %d/%d  ·  STARTING IN %d\n%s", zone:GetAttribute("RoomNumber") or "", count, max, cd, sub)
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

local BoardKinds = {
	TopFinders = { Title = "TOP OBJECT FINDERS", Color = UI.Colors.Gold, Attr = "TopFinders" },
	Fastest = { Title = "FASTEST ROOM #001", Color = UI.Colors.Cyan, Attr = "Fastest", Time = true },
	MostCleaned = { Title = "MOST CLEANED", Color = UI.Colors.Green, Attr = "MostCleaned" },
}

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

local function attachShopStand(part: BasePart)
	local bb = UI.Billboard(part, UDim2.fromOffset(220, 80), Vector3.new(0, part.Size.Y / 2 + 4, 0), 90)
	local panel = UI.Panel({ BackgroundTransparency = 0.1 }, bb)
	UI.Stroke(panel, UI.Colors.Purple, 3)
	UI.Label({ Text = "SHOP", TextSize = 44, TextColor3 = UI.Colors.Purple }, panel)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Shop"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		Controllers.ShopController.Open()
	end)
end

local function attachLeaderboard(part: BasePart)
	local def = BoardKinds[part:GetAttribute("Kind") or "TopFinders"] or BoardKinds.TopFinders
	local sg = UI.Surface(part, (part:GetAttribute("Face") and Enum.NormalId[part:GetAttribute("Face")]) or Enum.NormalId.Front, 30)
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	fitText(UI.Label({ Text = def.Title, TextScaled = true, TextColor3 = def.Color, Size = UDim2.new(0.92, 0, 0.11, 0), Position = UDim2.fromScale(0.04, 0.02) }, panel), 56)
	local list = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0.84, 0), Position = UDim2.new(0, 10, 0.15, 0) }, panel)
	UI.ListLayout(list, Enum.FillDirection.Vertical, 4)

	local data = ReplicatedStorage:WaitForChild("LeaderboardData")
	local attrName = def.Attr
	local function refresh()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local ok, entries = pcall(function()
			return HttpService:JSONDecode(data:GetAttribute(attrName) or "[]")
		end)
		if not ok or type(entries) ~= "table" then
			return
		end
		if #entries == 0 then
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0.08, 0), BackgroundTransparency = 1 }, list)
			fitText(UI.Label({ Text = "No entries yet - be the first!", TextScaled = true, TextColor3 = UI.Colors.TextDim }, row), 24)
		end
		for i, e in ipairs(entries) do
			if i > 10 then
				break
			end
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0.085, 0), BackgroundColor3 = i == 1 and UI.Colors.GoldDark or UI.Colors.PanelLight, LayoutOrder = i }, list)
			UI.Corner(row, 6)
			fitText(UI.Label({ Text = string.format("%d. %s", i, e.Name or "?"), TextScaled = true, Font = UI.FontBody, Size = UDim2.new(0.66, -10, 0.8, 0), Position = UDim2.new(0, 10, 0.1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = e.UserId == player.UserId and UI.Colors.Gold or UI.Colors.Text }, row), 24)
			local valueText = def.Time and FormatUtil.Time(e.Value or 0) or tostring(e.Value or 0)
			fitText(UI.Label({ Text = valueText, TextScaled = true, Font = UI.FontBody, Size = UDim2.new(0.34, -10, 0.8, 0), Position = UDim2.new(0.66, 0, 0.1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.TextDim }, row), 24)
		end
	end
	data:GetAttributeChangedSignal(attrName):Connect(refresh)
	refresh()
end

local function attachFutureDoor(part: BasePart)
	local bb = UI.Billboard(part, UDim2.fromOffset(280, 64), Vector3.new(0, part.Size.Y / 2 + 2, 0), 80)
	local panel = UI.Panel({ BackgroundTransparency = 0.1 }, bb)
	UI.Stroke(panel, UI.Colors.Gold, 2)
	UI.Label({ Text = part:GetAttribute("Label") or "MORE ROOMS COMING SOON", TextSize = 22, TextColor3 = UI.Colors.Gold }, panel)
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
	queuePillStart.Activated:Connect(function()
		Remotes.Event("StartParty"):FireServer(player:GetAttribute("QueueId"))
	end)
	queuePillLeave.Activated:Connect(function()
		Remotes.Event("LeaveQueue"):FireServer(player:GetAttribute("QueueId"))
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
