--[[
	Cheap offers placed right next to the problem they fix (RetentionConfig.Offers). Each is a
	small chip; only tapping it opens Roblox's purchase prompt (through the server), and a chip
	never covers the game for long:
	  LIFT IT NOW      something was too heavy to grab
	  JUNK BLASTER     standing by several packed junk (a saved one shows as a free USE chip)
	  2X SPEED         once per room, a while after the search starts
	  TREASURE RADAR   after your first treasure in a room
	  2X XP            close to a level up
	Lobby cards, once per session after the first room: the one-time STARTER PACK, and the
	question whether to be notified when the daily reward is ready (asked once, ever).
	Also draws Treasure Radar: a sparkle over every treasure (and packed junk holding one).
]]

local CollectionService = game:GetService("CollectionService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local RetentionConfig = require(Shared.Config.RetentionConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")
local serverInfo = ReplicatedStorage:WaitForChild("ServerInfo")

local OfferController = {}

local ROBUX = utf8.char(0xE002)
local OFFERS = RetentionConfig.Offers

local chip: Frame? = nil
local lastShown: { [string]: number } = {}
local shownThisRoom: { [string]: string } = {}
local shownThisSession: { [string]: boolean } = {}
local searchStartedAt = 0
local lobbyCardsDone = false
local chunkParams = OverlapParams.new()
chunkParams.FilterType = Enum.RaycastFilterType.Include

local function attr(name: string, default: any)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function inSearching(): boolean
	return attr("InMatch", false) and matchState:GetAttribute("State") == "Searching"
end

local function roomClutter(): Instance?
	local room = workspace:FindFirstChild("Room" .. (matchState:GetAttribute("RoomNumber") or ""))
	return room and room:FindFirstChild("Clutter")
end

-- Products that aren't on sale yet only show in Studio (where purchases are mocked).
local function available(key: string): boolean
	local def = MonetizationConfig.FindDef(key)
	if not def then
		return false
	end
	return def.Id ~= 0 or (serverInfo:GetAttribute("IsStudio") == true and serverInfo:GetAttribute("DevelopmentMode") == true)
end

local function price(key: string): string
	local def = MonetizationConfig.FindDef(key)
	return string.format("%s %d", ROBUX, def and def.SuggestedPrice or 0)
end

local function track(key: string, step: string)
	Remotes.Event("Track"):FireServer("offer", key, step)
end

local function hideChip(reason: string?)
	local c = chip
	if not c then
		return
	end
	chip = nil
	if reason and c:GetAttribute("Key") then
		track(c:GetAttribute("Key"), reason)
	end
	UI.Tween(c, { Position = c.Position - UDim2.fromOffset(40, 0) }, 0.2)
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("TextLabel") then
			UI.Tween(d, { TextTransparency = 1 }, 0.2)
		end
	end
	task.delay(0.22, function()
		c:Destroy()
	end)
end

-- One chip at a time: the problem, and a price button (or a free USE button).
local function showChip(key: string, title: string, color: Color3, buttonText: string?, onTap: (() -> ())?)
	if chip or UI.GetOpenMenu() then
		return false
	end
	local def = MonetizationConfig.FindDef(key)
	local cfg = OFFERS[key] or {}
	-- At the side of the screen, out of the way of the view: on touch at the top of the left
	-- column (HUDController's side stack, above the streak and boosts), elsewhere mid-left.
	local stack = Controllers.HUDController.GetSideStack()
	local frame = UI.Panel({ Name = "Offer_" .. key, Size = UDim2.fromOffset(stack and 246 or 270, 94), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), BackgroundTransparency = 0.05, LayoutOrder = -1 }, stack or UI.Layers.HUD)
	frame:SetAttribute("Key", key)
	UI.Stroke(frame, color, 3)
	UI.Glow(frame, color, 16, 0.6)
	local badge = UI.Surface3D({ Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(6, 6) }, frame, color, 12, 0.12)
	local icon = UI.Icon(badge, "Icon_Prod_" .. key, def and def.Icon or "!", { TextSize = 18 })
	icon.Size = UDim2.fromScale(0.78, 0.7)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	-- Two lines of title next to the icon, the price button under it.
	local text = UI.Label({ Text = title, TextSize = 15, TextWrapped = true, Size = UDim2.new(1, -94, 0, 46), Position = UDim2.fromOffset(58, 6), TextXAlignment = Enum.TextXAlignment.Left }, frame)
	UI.TextGradient(text, color)
	local buy = UI.Button({ Name = "Buy", Text = buttonText or price(key), Color = buttonText and UI.Colors.Green or UI.Colors.Purple, Size = UDim2.new(1, -12, 0, 32), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), FitText = 18, Shine = 1.8 }, frame)
	local close = UI.Button({ Name = "Close", Text = "X", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), FitText = 13 }, frame)
	buy.Activated:Connect(function()
		if chip ~= frame then
			return
		end
		if onTap then
			onTap()
		else
			track(key, "tapped")
			Remotes.Event("RequestPurchase"):FireServer(key)
		end
		hideChip()
	end)
	close.Activated:Connect(function()
		if chip == frame then
			hideChip("closed")
		end
	end)
	chip = frame
	lastShown[key] = os.clock()
	UI.PopIn(frame, 0.7, 0.3)
	if not buttonText then
		track(key, "shown")
	end
	local seconds = cfg.Seconds or 8
	task.delay(seconds, function()
		if chip == frame then
			hideChip()
		end
	end)
	return true
end

local function cooledDown(key: string): boolean
	local cfg = OFFERS[key] or {}
	return os.clock() - (lastShown[key] or -math.huge) >= (cfg.Cooldown or 0)
end

local function oncePerRoom(key: string): boolean
	return shownThisRoom[key] ~= (attr("MatchId", "") or "")
end

local function markRoom(key: string)
	shownThisRoom[key] = attr("MatchId", "")
end

-- ===== In-room checks =====

local function nearChunks(radius: number): number
	local folder = roomClutter()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not folder or not root then
		return 0
	end
	chunkParams.FilterDescendantsInstances = { folder }
	local seen, count = {}, 0
	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, radius, chunkParams)) do
		local obj = part:GetAttribute("IsChunk") and part or (part.Parent and part.Parent:IsA("BasePart") and part.Parent:GetAttribute("IsChunk") and part.Parent)
		if obj and not seen[obj] then
			seen[obj] = true
			count += 1
		end
	end
	return count
end

local function checkRoomOffers()
	if not inSearching() or chip then
		return
	end
	local t = now()
	local elapsed = os.clock() - searchStartedAt
	-- A saved Junk Blaster is free to use.
	local blaster = OFFERS.JunkBlaster
	if elapsed > 20 and cooledDown("JunkBlaster") and nearChunks(blaster.ChipRadius) >= blaster.NearChunks then
		local charges = attr("BlasterCharges", 0)
		if charges > 0 then
			showChip("JunkBlaster", "PACKED JUNK! USE YOUR BLASTER", UI.Colors.Orange, string.format("USE x%d", charges), function()
				Remotes.Event("UseBlaster"):FireServer()
			end)
			return
		elseif available("JunkBlaster") and showChip("JunkBlaster", "PACKED JUNK? BLAST IT OPEN!", UI.Colors.Orange) then
			return
		end
	end
	if elapsed > OFFERS.SpeedBoost10Min.AfterSearchSeconds and oncePerRoom("SpeedBoost10Min") and attr("SpeedBoostExpires", 0) <= t and available("SpeedBoost10Min") then
		markRoom("SpeedBoost10Min")
		if showChip("SpeedBoost10Min", "RUN 2X FASTER FOR 10 MIN", UI.Colors.Cyan) then
			return
		end
	end
	local need = attr("CleanerXPNext", 0)
	if need > 0 and attr("CleanerXP", 0) / need >= OFFERS.DoubleXP15Min.AtFraction and not shownThisSession.DoubleXP15Min
		and attr("XPBoostExpires", 0) <= t and available("DoubleXP15Min") then
		shownThisSession.DoubleXP15Min = true
		showChip("DoubleXP15Min", "ALMOST A LEVEL UP! GET 2X XP", UI.Colors.Pink)
	end
end

-- ===== Lobby cards =====

local function lobbyFree(): boolean
	return not attr("InMatch", false) and attr("QueueId", "") == "" and not attr("Teleporting", false) and not UI.GetOpenMenu()
end

local function card(title: string, body: string, color: Color3, yesText: string, noText: string, onYes: () -> (), onNo: () -> ())
	local frame = UI.Panel({ Name = "LobbyCard", Size = UDim2.fromOffset(300, 196), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.56, 0), BackgroundTransparency = 0.04 }, UI.Layers.HUD)
	UI.Stroke(frame, color, 3)
	UI.Glow(frame, color, 20, 0.5)
	local header = UI.Surface3D({ Size = UDim2.new(1, 0, 0, 40) }, frame, color, 12, 0.12)
	UI.Label({ Text = title, FitText = 20, TextWrapped = false, Size = UDim2.new(1, -16, 0.9, 0), Position = UDim2.fromOffset(8, 0) }, header)
	UI.Label({ Text = body, TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -20, 0, 84), Position = UDim2.fromOffset(10, 46), TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left }, frame)
	local yes = UI.Button({ Text = yesText, Color = UI.Colors.Green, Size = UDim2.new(0.6, -14, 0, 44), Position = UDim2.new(0, 10, 1, -54), FitText = 20, Shine = 2 }, frame)
	local no = UI.Button({ Text = noText, Color = UI.Colors.PanelLight, Size = UDim2.new(0.4, -10, 0, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 1, -54), FitText = 15 }, frame)
	UI.PopIn(frame, 0.8, 0.3)
	local done = false
	local function finish(fn: (() -> ())?)
		if done then
			return
		end
		done = true
		if fn then
			fn()
		end
		UI.Tween(frame, { Position = frame.Position - UDim2.fromOffset(340, 0) }, 0.25).Completed:Once(function()
			frame:Destroy()
		end)
	end
	yes.Activated:Connect(function()
		finish(onYes)
	end)
	no.Activated:Connect(function()
		finish(onNo)
	end)
	-- Shows until answered, the player gets busy, or 25 seconds pass (then it slides away).
	local deadline = os.clock() + 25
	while not done and lobbyFree() and os.clock() < deadline do
		task.wait(0.5)
	end
	finish(nil)
end

local function waitUntil(check: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if check() then
			return true
		end
		task.wait(0.5)
	end
	return false
end

local function starterPackCard()
	if attr("StarterPackOwned", false) or not available("StarterPack") then
		return
	end
	local def = MonetizationConfig.FindDef("StarterPack")
	track("StarterPack", "shown")
	card("STARTER PACK  ·  ONE TIME", "30 min 2X Cash, 2 Quick Hints and a Mop Pup helper pet. Only once, only " .. price("StarterPack") .. ".", UI.Colors.Purple, "BUY " .. price("StarterPack"), "NO THANKS", function()
		track("StarterPack", "tapped")
		Remotes.Event("RequestPurchase"):FireServer(def and def.Key or "StarterPack")
	end, function()
		track("StarterPack", "closed")
	end)
end

local function notifyCard()
	if attr("NotifyAsked", false) then
		return
	end
	-- Not possible for this player right now (already opted in, too young, Studio): ask another time.
	local ok, canPrompt = pcall(ExperienceNotificationService.CanPromptOptInAsync, ExperienceNotificationService)
	if not ok or not canPrompt then
		return
	end
	card("DAILY REWARD ALERTS", "Want a heads-up when your next daily reward and free spin are ready?", UI.Colors.Cyan, "YES!", "NOT NOW", function()
		local closed = false
		local conn = ExperienceNotificationService.OptInPromptClosed:Connect(function()
			closed = true
		end)
		pcall(ExperienceNotificationService.PromptOptIn, ExperienceNotificationService)
		task.spawn(function()
			waitUntil(function()
				return closed
			end, 60)
			conn:Disconnect()
			local okAgain, stillCan = pcall(ExperienceNotificationService.CanPromptOptInAsync, ExperienceNotificationService)
			Remotes.Event("NotifyAnswered"):FireServer((okAgain and not stillCan) and "allowed" or "denied")
		end)
	end, function()
		Remotes.Event("NotifyAnswered"):FireServer("no")
	end)
	-- Ignored (no answer): asked again next session.
end

-- After the first room, once per session: the Starter Pack, then the notification question.
local function lobbyCards()
	if lobbyCardsDone or attr("InMatch", false) or attr("HighestRoomCompleted", 0) < 1 then
		return
	end
	lobbyCardsDone = true
	task.spawn(function()
		task.wait(4)
		if not waitUntil(lobbyFree, 60) then
			lobbyCardsDone = false
			return
		end
		starterPackCard()
		task.wait(1)
		if waitUntil(lobbyFree, 30) then
			notifyCard()
		end
	end)
end

-- ===== Treasure Radar =====

local sparkles: { [Instance]: BillboardGui } = {}
local radarOn = false

local function holdsTreasure(obj: Instance): boolean
	if not obj:IsA("BasePart") then
		return false
	end
	if obj:GetAttribute("Category") == "Treasure" then
		return true
	end
	return obj:GetAttribute("IsChunk") == true and string.find(obj:GetAttribute("Contents") or "", "Treasure_", 1, true) ~= nil
end

local function addSparkle(obj: Instance)
	if sparkles[obj] or not holdsTreasure(obj) then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "RadarSparkle"
	bb.Size = UDim2.fromOffset(34, 34)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 90
	bb.Adornee = obj :: BasePart
	local star = UI.Label({ Text = "✦", TextSize = 30, TextWrapped = false, TextColor3 = UI.Colors.Gold }, bb)
	UI.Stroke(star, Color3.new(0, 0, 0), 2, 0)
	UI.Pulse(star, 0.2, 2.5)
	bb.Parent = player:WaitForChild("PlayerGui")
	sparkles[obj] = bb
end

local function clearRadar()
	for obj, bb in pairs(sparkles) do
		bb:Destroy()
		sparkles[obj] = nil
	end
end

local function refreshRadar()
	local on = attr("InMatch", false) and attr("TreasureRadar", "") ~= "" and attr("TreasureRadar", "") == attr("MatchId", "")
	if not on then
		radarOn = false
		clearRadar()
		return
	end
	local folder = roomClutter()
	if not folder then
		return
	end
	radarOn = true
	for _, obj in ipairs(folder:GetChildren()) do
		addSparkle(obj)
	end
	for obj, bb in pairs(sparkles) do
		if not obj.Parent then
			bb:Destroy()
			sparkles[obj] = nil
		end
	end
end

-- ===== Lifecycle =====

function OfferController.Init()
	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if type(payload) ~= "table" then
			return
		end
		if name == "TooHeavy" then
			local weight = payload.Weight or 0
			if inSearching() and weight <= GameConfig.MaxWeightCap and attr("LiftExpires", 0) <= now() and cooledDown("LiftItNow") and available("LiftItNow") then
				showChip("LiftItNow", string.format("TOO HEAVY? LIFT IT NOW (%d)", weight), UI.Colors.Orange)
			end
		elseif name == "Deposit" and payload.Mine and payload.Pet then
			if inSearching() and attr("PetSnackExpires", 0) <= now() and cooledDown("PetSnack") and available("PetSnack") then
				task.delay(1.2, function()
					if inSearching() then
						showChip("PetSnack", "YOUR PET IS HELPING! 2X PET SPEED", UI.Colors.Pink)
					end
				end)
				lastShown.PetSnack = os.clock()
			end
		elseif name == "Deposit" and payload.Mine and payload.Treasure then
			if oncePerRoom("TreasureRadar") and attr("TreasureRadar", "") ~= attr("MatchId", "") and available("TreasureRadar") then
				markRoom("TreasureRadar")
				task.delay(1.5, function()
					if inSearching() then
						showChip("TreasureRadar", "MORE TREASURE HIDING! SEE IT ALL", UI.Colors.Gold)
					end
				end)
			end
		elseif name == "Blasted" then
			lastShown.JunkBlaster = os.clock()
			Controllers.FXController.CameraShake(0.5)
			Controllers.FXController.ScreenFlash(UI.Colors.Orange, 0.4)
			Controllers.FXController.FloatingText(string.format("BLAST! %d PACKED JUNK", payload.Count or 0), UI.Colors.Orange, UDim2.fromScale(0.5, 0.45), 34)
		end
	end)
	matchState:GetAttributeChangedSignal("State"):Connect(function()
		if matchState:GetAttribute("State") == "Searching" then
			searchStartedAt = os.clock()
		elseif chip then
			hideChip()
		end
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(function()
		if chip then
			hideChip()
		end
		if not attr("InMatch", false) then
			lobbyCards()
		end
		refreshRadar()
	end)
	for _, name in ipairs({ "TreasureRadar", "MatchId" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshRadar)
	end
	player:GetAttributeChangedSignal("HighestRoomCompleted"):Connect(lobbyCards)
	-- Studio test hook: workspace attribute DevOfferTest = an offer key shows its chip.
	if RunService:IsStudio() then
		workspace:GetAttributeChangedSignal("DevOfferTest"):Connect(function()
			local key = workspace:GetAttribute("DevOfferTest")
			if type(key) == "string" and key ~= "" then
				hideChip()
				showChip(key, "[TEST] " .. key, UI.Colors.Orange)
			end
		end)
	end
end

function OfferController.Start()
	lobbyCards()
	local acc, radarAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		radarAcc += dt
		if acc >= 1 then
			acc = 0
			checkRoomOffers()
		end
		-- Chunk pieces and new treasures appear as the room is dug: keep the radar up to date.
		if radarOn and radarAcc >= 1.5 then
			radarAcc = 0
			refreshRadar()
		end
	end)
	-- Treasures can arrive with a burst: pick them up quickly.
	CollectionService:GetInstanceAddedSignal("Clutter"):Connect(function(obj)
		if radarOn then
			task.defer(addSparkle, obj)
		end
	end)
end

return OfferController
