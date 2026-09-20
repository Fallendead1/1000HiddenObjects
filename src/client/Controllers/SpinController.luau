--[[
	The free daily spin (RetentionConfig.Spin): one spin a day, never sold. The wheel shows every
	prize and the odds list next to it shows each prize's exact chance. SPIN asks the server, which
	picks and grants the prize; the wheel then turns to it and the prize pops up.
	Final art (optional): ReplicatedStorage.GameAssets.UIImages "Spin_Wheel" (the wheel face,
	drawn under the prize labels) and "Spin_Pointer".
	Server attributes: SpinReady, SpinResetAt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RetentionConfig = require(Shared.Config.RetentionConfig)
local RewardInfo = require(Shared.Config.RewardInfo)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local SpinController = {}

local SEGMENTS = RetentionConfig.Spin
local STEP = 360 / #SEGMENTS
local SPIN_TIME = 3.4

local menu
local wheel: Frame
local spinButton: TextButton
local footer: TextLabel
local spinning = false
local rotation = 0

local function colorOf(key: string?): Color3
	return (key and UI.Colors[key]) or UI.Colors.Gold
end

local function timeLeft(): string
	local seconds = math.max(0, (player:GetAttribute("SpinResetAt") or 0) - workspace:GetServerTimeNow())
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function refresh()
	if not menu or spinning then
		return
	end
	if player:GetAttribute("SpinReady") == true then
		UI.SetButtonEnabled(spinButton, true)
		spinButton.Text = "SPIN!"
		footer.Text = "One free spin every day."
	else
		UI.SetButtonEnabled(spinButton, false, "SPUN TODAY")
		footer.Text = "Next free spin in " .. timeLeft()
	end
end

local function buildWheel(parent: Instance)
	local size = 320
	local holder = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(size, size + 20), Position = UDim2.fromOffset(4, 0) }, parent)
	wheel = UI.Frame({ Name = "Wheel", Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(0, 20), BackgroundColor3 = UI.Colors.PanelDark, BackgroundTransparency = 1 }, holder)
	local face = UI.Asset("Spin_Wheel")
	if face then
		UI.Image({ Image = face, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, wheel)
	else
		wheel.BackgroundTransparency = 0
		UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, wheel)
		UI.New("UIStroke", { Color = UI.Colors.Gold, Thickness = 6 }, wheel)
		for i = 0, #SEGMENTS / 2 - 1 do
			UI.Frame({ Size = UDim2.new(0, 3, 1, -8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Rotation = (i + 0.5) * STEP, BackgroundColor3 = UI.Colors.Stroke, BackgroundTransparency = 0.2, ZIndex = 1 }, wheel)
		end
	end
	-- Each slice: the prize's picture toward the rim, its few characters under it (they stand
	-- upright when the slice is at the top, like on a real wheel).
	for i, s in ipairs(SEGMENTS) do
		local angle = (i - 1) * STEP
		local r = size * 0.33
		local slot = UI.Frame({
			Name = "Prize" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(64, 76),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.sin(math.rad(angle)) * r, 0.5, -math.cos(math.rad(angle)) * r),
			Rotation = angle,
			ZIndex = 2,
		}, wheel)
		local info = RewardInfo.Of(s.Reward)
		local isPet = s.Reward.Pet ~= nil
		local icon = UI.Icon(slot, info.Icon, info.Glyph, { TextSize = 20 })
		icon.Size = isPet and UDim2.fromOffset(52, 52) or UDim2.fromOffset(38, 38)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, isPet and -6 or 4)
		icon.ZIndex = 3
		local label = UI.Label({ Text = s.Short or s.Text, FitText = 14, TextWrapped = false, Size = UDim2.new(1, 8, 0, 18), Position = UDim2.new(0, -4, 0, 45), ZIndex = 3 }, slot)
		UI.Stroke(label, Color3.new(0, 0, 0), 2.5, 0)
	end
	local hub = UI.Surface3D({ Size = UDim2.fromOffset(60, 60), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 4 }, wheel, UI.Colors.Gold, 30, 0.12)
	UI.Label({ Text = "★", TextSize = 28, TextWrapped = false, Size = UDim2.fromScale(1, 0.9), ZIndex = 5 }, hub)
	-- The pointer at the top.
	local pointerArt = UI.Asset("Spin_Pointer")
	if pointerArt then
		UI.Image({ Image = pointerArt, Size = UDim2.fromOffset(44, 48), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), ZIndex = 6 }, holder)
	else
		local pointer = UI.Frame({ Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 22), Rotation = 45, BackgroundColor3 = UI.Colors.Red, ZIndex = 6 }, holder)
		UI.New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3 }, pointer)
	end
end

-- The odds, from the most common prize at the top to the rarest at the bottom (the pets and the
-- jackpot stand out in gold).
local function buildOdds(parent: Instance)
	local list = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -350, 0, 300), Position = UDim2.fromOffset(340, 12) }, parent)
	UI.Label({ Text = "PRIZES & ODDS", TextSize = 18, TextWrapped = false, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left }, list)
	local rows = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -28), Position = UDim2.fromOffset(0, 28) }, list)
	UI.ListLayout(rows, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left)
	local total = 0
	local sorted = {}
	for _, s in ipairs(SEGMENTS) do
		total += s.Weight
		table.insert(sorted, s)
	end
	table.sort(sorted, function(x, y)
		return x.Weight > y.Weight
	end)
	for i, s in ipairs(sorted) do
		local chance = s.Weight / total * 100
		local rare = chance <= 3
		local row = UI.Panel({ Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, rows)
		if rare then
			UI.Stroke(row, UI.Colors.Gold, 2)
		end
		local info = RewardInfo.Of(s.Reward)
		local chip = UI.Icon(row, info.Icon, info.Glyph, { TextSize = 11 })
		chip.Size = UDim2.fromOffset(20, 20)
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.Position = UDim2.new(0, 6, 0.5, 0)
		local name = UI.Label({ Text = s.Text, TextSize = 14, Font = UI.FontBody, TextWrapped = false, Size = UDim2.new(1, -92, 1, 0), Position = UDim2.fromOffset(32, 0), TextXAlignment = Enum.TextXAlignment.Left }, row)
		if rare then
			name.TextColor3 = UI.Colors.Gold
		end
		UI.Label({ Text = chance >= 1 and string.format("%d%%", math.floor(chance + 0.5)) or string.format("%.1f%%", chance), TextSize = 14, TextWrapped = false, TextColor3 = UI.Colors.Gold, Size = UDim2.new(0, 56, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
	end
end

local function spinTo(index: number, text: string)
	-- Five full turns, ending with prize `index` under the pointer.
	local target = -(index - 1) * STEP
	local current = rotation % 360
	local delta = (target - current) % 360
	rotation = rotation + 360 * 5 + delta
	UI.Tween(wheel, { Rotation = rotation }, SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	Controllers.AudioController.Play("Streak")
	task.delay(SPIN_TIME + 0.1, function()
		spinning = false
		local s = SEGMENTS[index]
		-- A pet opens as its own gift (PetController's hatch scene); everything else pops up here.
		if not (s and s.Reward.Pet) then
			Controllers.GiftController.Reveal("YOU WON!", text, colorOf(s and s.Color), nil, RewardInfo.Of(s and s.Reward))
		end
		refresh()
	end)
end

local function spin()
	if spinning or player:GetAttribute("SpinReady") ~= true then
		return
	end
	spinning = true
	UI.SetButtonEnabled(spinButton, false, "SPINNING...")
	-- The wallet waits for the wheel, so it doesn't give the prize away.
	Controllers.HUDController.HoldWallet(SPIN_TIME + 1)
	Remotes.Event("SpinWheel"):FireServer()
	task.delay(6, function()
		if spinning and wheel.Rotation == rotation then
			-- No answer from the server.
			spinning = false
			refresh()
		end
	end)
end

function SpinController.Init()
	menu = UI.Menu("Spin", "DAILY SPIN", UDim2.fromOffset(700, 490), UI.Colors.Pink)
	buildWheel(menu.Content)
	buildOdds(menu.Content)
	spinButton = UI.Button({ Name = "SpinButton", Text = "SPIN!", Color = UI.Colors.Pink, Size = UDim2.fromOffset(220, 52), Position = UDim2.new(1, -262, 0, 332), TextSize = 26, Shine = 2.2 }, menu.Content)
	footer = UI.Label({ Text = "", TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.fromOffset(300, 18), Position = UDim2.new(1, -302, 0, 386) }, menu.Content)
	spinButton.Activated:Connect(spin)
	menu.Primary = spinButton
	menu.OnOpen(refresh)
	player:GetAttributeChangedSignal("SpinReady"):Connect(refresh)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if name == "SpinResult" and type(payload) == "table" and payload.Index then
			spinning = true
			spinTo(payload.Index, payload.Text or "")
		end
	end)
end

function SpinController.Start()
	task.spawn(function()
		while true do
			task.wait(30)
			if menu.IsOpen() then
				refresh()
			end
		end
	end)
end

function SpinController.Open()
	menu.Open()
end

return SpinController
