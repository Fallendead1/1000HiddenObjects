--[[
	Free gifts (RetentionService / RetentionConfig):
	  Playtime gifts  the GIFTS tiles count down to the next gift ("00:42", then "OPEN!" with a red
	                  dot); the Gifts menu shows today's whole ladder and opens the one that's ready.
	  Gift bar        in rooms, a slim bar hanging under the room panel: "NEXT GIFT IN 7".
	  Reveals         a gift opening, a gift-bar gift and first-time rewards pop up with their
	                  reward; Cash saved to the wallet floats up as "+$50 SAVED".
	Server attributes: PlaytimeSeconds, GiftsClaimed, PlaytimeResetAt, GiftBarCount, GiftBarNeed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local FormatUtil = require(Shared.Utility.FormatUtil)
local RetentionConfig = require(Shared.Config.RetentionConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local GiftController = {}

local GIFTS = RetentionConfig.PlaytimeGifts

local menu
local cards: { { Card: Frame, State: TextLabel, Pulsing: boolean } } = {}
local openButton: TextButton
local headerLabel: TextLabel
local footerLabel: TextLabel
local barFrame: Frame
local bar
local barLabel: TextLabel
local busyUntil = 0
local notifiedReady = 0

local function attr(name: string, default: any)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

-- The next gift (index, seconds until it's ready; nil when today's ladder is done).
local function nextGift(): (number?, number)
	local index = attr("GiftsClaimed", 0) + 1
	local gift = GIFTS[index]
	if not gift then
		return nil, 0
	end
	return index, math.max(0, gift.Minutes * 60 - attr("PlaytimeSeconds", 0))
end

function GiftController.IsReady(): boolean
	local index, left = nextGift()
	return index ~= nil and left <= 0
end

local function tileText(): string
	local index, left = nextGift()
	if not index then
		return "TOMORROW"
	elseif left <= 0 then
		return "OPEN!"
	end
	return FormatUtil.Time(left)
end

local function resetText(): string
	local seconds = math.max(0, attr("PlaytimeResetAt", 0) - workspace:GetServerTimeNow())
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function colorOf(key: string?): Color3
	return (key and UI.Colors[key]) or UI.Colors.Gold
end

local function refreshMenu()
	if not menu or not menu.IsOpen() then
		return
	end
	local claimed = attr("GiftsClaimed", 0)
	local seconds = attr("PlaytimeSeconds", 0)
	local index, left = nextGift()
	headerLabel.Text = string.format("PLAYED TODAY: %s", FormatUtil.Time(seconds))
	for i, c in ipairs(cards) do
		local gift = GIFTS[i]
		local done = i <= claimed
		local ready = not done and seconds >= gift.Minutes * 60
		UI.Stroke(c.Card, ready and UI.Colors.Gold or (done and UI.Colors.Green or Color3.new(0, 0, 0)), ready and 3.5 or 2.5)
		c.Card.BackgroundTransparency = (done or ready) and 0.05 or 0.4
		if done then
			c.State.Text = "OPENED"
			c.State.TextColor3 = UI.Colors.Green
		elseif ready then
			c.State.Text = "READY!"
			c.State.TextColor3 = UI.Colors.Gold
		else
			c.State.Text = FormatUtil.Time(gift.Minutes * 60 - seconds)
			c.State.TextColor3 = UI.Colors.TextDim
		end
		if ready and not c.Pulsing then
			c.Pulsing = true
			UI.Pulse(c.Card, 0.05, 2.4)
		elseif not ready and c.Pulsing then
			c.Pulsing = false
			UI.StopPulse(c.Card)
		end
	end
	if os.clock() < busyUntil then
		return
	end
	if index and left <= 0 then
		UI.SetButtonEnabled(openButton, true)
		openButton.Text = "OPEN GIFT"
		footerLabel.Text = "Gifts count while you play - lobby and rooms."
	elseif index then
		UI.SetButtonEnabled(openButton, false, "NEXT GIFT " .. FormatUtil.Time(left))
		footerLabel.Text = "Gifts count while you play - lobby and rooms."
	else
		UI.SetButtonEnabled(openButton, false, "ALL OPENED!")
		footerLabel.Text = "New gifts in " .. resetText()
	end
end

local function open()
	if os.clock() < busyUntil or not GiftController.IsReady() then
		return
	end
	busyUntil = os.clock() + 2
	UI.SetButtonEnabled(openButton, false, "OPENING...")
	Remotes.Event("ClaimGift"):FireServer()
	task.delay(2.05, refreshMenu)
end

-- ===== Reveals =====

-- A gift card that pops up in the middle of the screen with its reward, then drifts away.
function GiftController.Reveal(title: string, text: string, color: Color3, glyph: string?)
	local holder = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(420, 190), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42) }, UI.Layers.Overlay)
	local rays = UI.Image({ Image = UI.Asset("Rays") or "", Size = UDim2.fromOffset(300, 300), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 56), ImageColor3 = color, ImageTransparency = 0.4, ZIndex = 0 }, holder)
	local box = UI.Surface3D({ Size = UDim2.fromOffset(96, 96), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8) }, holder, color, 20, 0.12)
	local icon = UI.Icon(box, "Gift_Box", glyph or "G", { TextSize = 48 })
	icon.Size = UDim2.fromScale(0.78, 0.7)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	UI.Glow(box, color, 26, 0.35)
	local top = UI.Label({ Text = title, TextSize = 34, TextWrapped = false, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 112) }, holder)
	UI.Stroke(top, Color3.new(0, 0, 0), 3.5, 0)
	UI.TextGradient(top, color)
	local bottom = UI.Label({ Text = text, TextSize = 22, TextWrapped = false, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 152) }, holder)
	UI.Stroke(bottom, Color3.new(0, 0, 0), 2.5, 0)
	UI.PopIn(holder, 0.3, 0.4)
	Controllers.AudioController.Play("CashAward")
	Controllers.FXController.ScreenFlash(color, 0.45)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		Controllers.FXController.Confetti(root.Position)
	end
	task.spawn(function()
		local spin = 0
		local conn = RunService.RenderStepped:Connect(function(dt)
			spin += dt * 40
			rays.Rotation = spin
		end)
		task.wait(2.4)
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("TextLabel") then
				UI.Tween(d, { TextTransparency = 1 }, 0.35)
			elseif d:IsA("ImageLabel") then
				UI.Tween(d, { ImageTransparency = 1 }, 0.35)
			end
		end
		UI.Tween(holder, { Position = holder.Position - UDim2.fromOffset(0, 40) }, 0.35)
		task.wait(0.4)
		conn:Disconnect()
		holder:Destroy()
	end)
end

local function savedPopup(amount: number)
	local walletPanel = Controllers.HUDController.GetWalletPanel()
	local anchor
	if not player:GetAttribute("InMatch") and walletPanel and walletPanel.AbsoluteSize.X > 0 then
		local pos, size = walletPanel.AbsolutePosition, walletPanel.AbsoluteSize
		anchor = UI.FromAbsolute(Vector2.new(pos.X + size.X + 90, pos.Y + size.Y / 2))
	end
	Controllers.FXController.FloatingText(string.format("+%s SAVED", FormatUtil.CashExact(amount)), UI.Colors.Cash, anchor or UDim2.new(0.5, 0, 0.7, 0), 24)
end

-- ===== Gift bar (rooms) =====

local function refreshBar()
	if not barFrame then
		return
	end
	local count, need = attr("GiftBarCount", 0), math.max(1, attr("GiftBarNeed", 10))
	bar.Set(count / need, true)
	local left = need - count
	barLabel.Text = string.format("NEXT GIFT IN %d OBJECT%s", left, left == 1 and "" or "S")
end

local function buildBar()
	-- Under the room panel, so it moves with it (and nothing at the bottom covers it).
	barFrame = UI.Panel({ Name = "GiftBar", Size = UDim2.fromOffset(300, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), BackgroundTransparency = 0.12 }, Controllers.HUDController.GetMatchTop())
	UI.Stroke(barFrame, UI.Colors.Gold, 2)
	local badge = UI.Surface3D({ Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(3, 3) }, barFrame, UI.Colors.Gold, 14, 0.12)
	local icon = UI.Icon(badge, "Icon_Gift", "G", { TextSize = 15 })
	icon.Size = UDim2.fromScale(0.72, 0.64)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	bar = UI.ProgressBar(barFrame, UDim2.new(1, -44, 0, 22), UDim2.fromOffset(38, 6), UI.Colors.Gold)
	barLabel = UI.Label({ Text = "", FitText = 13, TextWrapped = false, Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), ZIndex = 3 }, bar.Frame)
	refreshBar()
end

-- ===== Lifecycle =====

function GiftController.Init()
	menu = UI.Menu("Gifts", "FREE GIFTS", UDim2.fromOffset(760, 430), UI.Colors.Gold)
	headerLabel = UI.Label({ Text = "", TextSize = 22, TextWrapped = false, Size = UDim2.new(1, 0, 0, 28) }, menu.Content)
	UI.TextGradient(headerLabel, UI.Colors.Gold)
	UI.Label({ Text = "Keep playing to open every gift. A new set every day!", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 30) }, menu.Content)

	local grid = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 200), Position = UDim2.fromOffset(0, 56) }, menu.Content)
	local layout = UI.GridLayout(grid, UDim2.new(1 / 5, -8, 0.5, -5), 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, gift in ipairs(GIFTS) do
		local color = colorOf(gift.Color)
		local card = UI.Panel({ BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, grid)
		UI.Label({ Text = string.format("%d MIN", gift.Minutes), TextSize = 13, TextWrapped = false, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 4) }, card)
		local badge = UI.Surface3D({ Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22) }, card, color, 10, 0.12)
		local icon = UI.Icon(badge, "Gift_Box", "G", { TextSize = 18 })
		icon.Size = UDim2.fromScale(0.74, 0.66)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.45)
		UI.Label({ Text = gift.Text, TextSize = 11, Font = UI.FontBody, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 58) }, card)
		local state = UI.Label({ Text = "", TextSize = 12, TextWrapped = false, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -16) }, card)
		cards[i] = { Card = card, State = state, Pulsing = false }
	end

	openButton = UI.Button({ Name = "OpenGift", Text = "OPEN GIFT", Color = UI.Colors.Gold, Size = UDim2.fromOffset(280, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 268), TextSize = 24, Shine = 2.5 }, menu.Content)
	footerLabel = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 330) }, menu.Content)
	openButton.Activated:Connect(open)
	menu.Primary = openButton
	menu.OnOpen(refreshMenu)

	buildBar()
	for _, name in ipairs({ "GiftBarCount", "GiftBarNeed" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshBar)
	end

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if type(payload) ~= "table" then
			return
		end
		if name == "GiftOpened" then
			busyUntil = 0
			local c = cards[payload.Index or 0]
			if c then
				UI.Flash(c.Card, UI.Colors.Gold, 0.8)
			end
			GiftController.Reveal("FREE GIFT!", payload.Text or "", colorOf(payload.Color))
			refreshMenu()
		elseif name == "GiftBar" then
			if barFrame then
				UI.PopIn(barFrame, 0.85, 0.3)
				UI.Flash(barFrame, UI.Colors.Gold, 0.6)
			end
			Controllers.AudioController.Play("CashAward")
			local pos, size = barFrame.AbsolutePosition, barFrame.AbsoluteSize
			Controllers.FXController.FloatingText("GIFT!  " .. (payload.Text or ""), UI.Colors.Gold, UI.FromAbsolute(Vector2.new(pos.X + size.X / 2, pos.Y + size.Y + 60)), 28)
		elseif name == "FirstReward" then
			Controllers.ProgressionController.Banner(payload.Title or "FIRST!", payload.Text or "", UI.Colors.Gold, "CashAward")
		elseif name == "Wallet" then
			if (payload.Amount or 0) > 0 then
				savedPopup(payload.Amount)
			end
		end
	end)
end

function GiftController.Start()
	local hud = Controllers.HUDController
	local tiles = { hud.Buttons.LobbyGifts, hud.Buttons.Gifts }
	for _, tile in ipairs(tiles) do
		hud.AddTileDot(tile, { "PlaytimeSeconds", "GiftsClaimed" }, GiftController.IsReady)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local text = tileText()
		for _, tile in ipairs(tiles) do
			hud.SetTileText(tile, text)
		end
		barFrame.Visible = player:GetAttribute("InMatch") == true
		refreshMenu()
		-- A toast once per ready gift (never a popup in the way).
		local index, left = nextGift()
		if index and left <= 0 and notifiedReady < index then
			notifiedReady = index
			Controllers.NotificationController.Show("Success", "A free gift is ready! Open it from GIFTS.", 4)
		end
	end)
end

function GiftController.Open()
	menu.Open()
end

return GiftController
