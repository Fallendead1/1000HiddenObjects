--[[
	Lobby presentation. The lobby itself is authored in Workspace.Lobby; this controller only
	animates and labels it:
	  - QueueZone: glowing circle (Visual/GlowDisc, GlowCore, GlowRim, SparklePlane.Sparkles)
	    coloured + pulsed by queue state, with a floating sign above it, plus a HUD pill while
	    the local player is queued.
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

-- Text for the floating sign above a circle. Returns title, subtitle, count, countdown.
local function describe(zone: BasePart): (string, string, string, string, Color3)
	local state = zoneState(zone)
	local count = zone:GetAttribute("Count") or 0
	local max = zone:GetAttribute("MaxPlayers") or GameConfig.MaxPartySize
	local roomNumber = zone:GetAttribute("RoomNumber") or ""
	local roomName = string.upper(zone:GetAttribute("RoomName") or "")
	local countText = string.format("%d / %d PLAYERS", count, max)
	local style = StateStyle[state] or StateStyle.Empty

	if state == "Selecting" then
		local owner = zone:GetAttribute("OwnerUserId") == player.UserId and "YOU ARE" or ((zone:GetAttribute("OwnerName") or "HOST") .. " IS")
		return "JOINING...", owner .. " CHOOSING A ROOM", countText, "", style.Color
	elseif state == "CountingDown" then
		local cd = zone:GetAttribute("Countdown") or 0
		local resume = zone:GetAttribute("ResumePercent") or 0
		local sub = roomName .. (resume > 0 and string.format("  -  RESUME %d%%", math.floor(resume * 100)) or "")
		return "ROOM #" .. roomNumber, sub, countText, count >= max and "STARTING..." or ("STARTING IN " .. cd), style.Color
	elseif state == "Locked" then
		return "ROOM #" .. roomNumber, roomName, string.format("%d / %d", count, max), "STARTING...", style.Color
	elseif state == "Teleporting" then
		return string.format("%d / %d", count, max), "ROOM #" .. roomNumber, "", "TELEPORTING...", style.Color
	elseif state == "Resetting" then
		return "PLAY", "NEXT GROUP...", "", "", style.Color
	end
	return "PLAY", "STEP INSIDE TO PLAY", "1 - 4 PLAYERS", "", style.Color
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

	-- Sized in studs so signs shrink with distance instead of crowding the screen.
	local bb = UI.Billboard(zone, UDim2.fromScale(11, 6.4), Vector3.new(0, 7.5, 0), 160)
	bb.Name = "QueueSign_" .. (zone:GetAttribute("QueueId") or "")
	local panel = UI.Panel({ BackgroundTransparency = 0.12 }, bb)
	local stroke = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 3
	local function line(y: number, h: number, color: Color3, maxSize: number): TextLabel
		local label = UI.Label({ Text = "", TextScaled = true, TextColor3 = color, Size = UDim2.new(0.92, 0, h, 0), Position = UDim2.new(0.04, 0, y, 0) }, panel)
		UI.New("UITextSizeConstraint", { MaxTextSize = maxSize }, label)
		return label
	end
	local title = line(0.03, 0.32, UI.Colors.Green, 64)
	local subtitle = line(0.36, 0.16, UI.Colors.Text, 26)
	local countLabel = line(0.54, 0.18, UI.Colors.TextDim, 30)
	local countdown = line(0.74, 0.22, UI.Colors.Gold, 40)

	local lastCount, lastCd = zone:GetAttribute("Count") or 0, -1
	local function refresh()
		local t, s, c, cd, color = describe(zone)
		title.Text = t
		title.TextColor3 = color
		subtitle.Text = s
		countLabel.Text = c
		countdown.Text = cd
		stroke.Color = color

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
	for _, name in ipairs({ "State", "Count", "Countdown", "RoomNumber", "RoomName", "OwnerUserId", "OwnerName", "ResumePercent" }) do
		zone:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
end

function LobbyController.RefreshPill()
	local queueId = player:GetAttribute("QueueId") or ""
	if queueId == "" or player:GetAttribute("InMatch") then
		queuePill.Visible = false
		return
	end
	for _, v in ipairs(visuals) do
		if v.Zone:GetAttribute("QueueId") == queueId then
			local state = zoneState(v.Zone)
			local text
			if state == "Selecting" then
				text = v.Zone:GetAttribute("OwnerUserId") == player.UserId and "CHOOSE A ROOM TO START" or "WAITING FOR THE HOST TO CHOOSE A ROOM"
			elseif state == "CountingDown" then
				text = string.format("ROOM #%s  -  %d/%d  -  STARTING IN %d", v.Zone:GetAttribute("RoomNumber") or "", v.Zone:GetAttribute("Count") or 0, v.Zone:GetAttribute("MaxPlayers") or 4, v.Zone:GetAttribute("Countdown") or 0)
			else
				text = "TELEPORTING..."
			end
			queuePillLabel.Text = text .. (state ~= "Teleporting" and "\nWalk out of the circle to leave" or "")
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

local function attachCollectionBoard(part: BasePart)
	local sg = UI.Surface(part, (part:GetAttribute("Face") and Enum.NormalId[part:GetAttribute("Face")]) or Enum.NormalId.Front, 30)
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	UI.Label({ Text = "YOUR COLLECTION", TextSize = 44, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0.2, 0) }, panel)
	local count = UI.Label({ Text = "0 / 1000", TextSize = 100, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.18) }, panel)
	local button = UI.Button({ Text = "VIEW COLLECTION", Color = UI.Colors.Gold, Size = UDim2.new(0.6, 0, 0.16, 0), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.72), TextSize = 40 }, panel)
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
	local kind = part:GetAttribute("Kind") or "TopFinders"
	local sg = UI.Surface(part, (part:GetAttribute("Face") and Enum.NormalId[part:GetAttribute("Face")]) or Enum.NormalId.Front, 30)
	local panel = UI.Frame({ BackgroundTransparency = 1 }, sg)
	UI.Label({ Text = kind == "Fastest" and "FASTEST ROOM #001" or "TOP OBJECT FINDERS", TextSize = 40, TextColor3 = kind == "Fastest" and UI.Colors.Cyan or UI.Colors.Gold, Size = UDim2.new(1, 0, 0.14, 0) }, panel)
	local list = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -20, 0.84, 0), Position = UDim2.new(0, 10, 0.15, 0) }, panel)
	UI.ListLayout(list, Enum.FillDirection.Vertical, 4)

	local data = ReplicatedStorage:WaitForChild("LeaderboardData")
	local attrName = kind == "Fastest" and "Fastest" or "TopFinders"
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
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, list)
			UI.Label({ Text = "No entries yet - be the first!", TextSize = 22, TextColor3 = UI.Colors.TextDim }, row)
		end
		for i, e in ipairs(entries) do
			if i > 10 then
				break
			end
			local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = i == 1 and UI.Colors.GoldDark or UI.Colors.PanelLight, LayoutOrder = i }, list)
			UI.Corner(row, 6)
			UI.Label({ Text = string.format("%d. %s", i, e.Name or "?"), TextSize = 22, Font = UI.FontBody, Size = UDim2.new(0.7, 0, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = e.UserId == player.UserId and UI.Colors.Gold or UI.Colors.Text }, row)
			local valueText = kind == "Fastest" and FormatUtil.Time(e.Value or 0) or tostring(e.Value or 0)
			UI.Label({ Text = valueText, TextSize = 22, Font = UI.FontBody, Size = UDim2.new(0.3, -10, 1, 0), Position = UDim2.new(0.7, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.TextDim }, row)
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
	queuePill = UI.Panel({ Size = UDim2.fromOffset(460, 58), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Visible = false, BackgroundTransparency = 0.08 }, UI.Layers.HUD)
	queuePillLabel = UI.Label({ Text = "", TextSize = 18, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0) }, queuePill)
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
