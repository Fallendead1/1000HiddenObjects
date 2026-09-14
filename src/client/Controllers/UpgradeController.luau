local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local FormatUtil = require(Shared.Utility.FormatUtil)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local UpgradeController = {}

local menu
local cards: { [string]: any } = {}
local busy = false
local cashHeader: TextLabel

local CategoryColor = {
	Strength = UI.Colors.Red,
	ThrowPower = UI.Colors.Orange,
	MoveSpeed = UI.Colors.Green,
}

local function buildCard(def, parent: Instance, order: number)
	local color = CategoryColor[def.Key] or UI.Colors.Green
	local card = UI.Panel({ Size = UDim2.fromOffset(310, 206), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, parent)
	UI.Stroke(card, color, 2)

	local icon = UI.Frame({ Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(14, 14), BackgroundColor3 = color }, card)
	UI.Corner(icon, 12)
	UI.Icon(icon, "Icon_" .. def.Key, def.Icon, { TextSize = 20, TextColor3 = UI.Colors.PanelDark })

	UI.Label({ Text = def.Name, TextSize = 22, Size = UDim2.new(1, -90, 0, 28), Position = UDim2.fromOffset(78, 12), TextXAlignment = Enum.TextXAlignment.Left }, card)
	local levelLabel = UI.Label({ Text = "Lv. 1 -> Lv. 2", TextSize = 15, TextColor3 = UI.Colors.TextDim, Font = UI.FontBody, Size = UDim2.new(1, -90, 0, 20), Position = UDim2.fromOffset(78, 40), TextXAlignment = Enum.TextXAlignment.Left }, card)

	-- Level pips
	local pips = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 10), Position = UDim2.fromOffset(14, 76) }, card)
	UI.ListLayout(pips, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Left)
	local pipList = {}
	local max = UpgradeConfig.GetMaxLevel(def.Key)
	for i = 1, max do
		local pip = UI.Frame({ Size = UDim2.new(1 / max, -4, 1, 0), BackgroundColor3 = UI.Colors.PanelDark, LayoutOrder = i }, pips)
		UI.Corner(pip, 4)
		table.insert(pipList, pip)
	end

	local desc = UI.Label({ Text = def.Description, TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 92), TextXAlignment = Enum.TextXAlignment.Left }, card)
	local statLabel = UI.Label({ Text = "1.00x  ->  1.20x", TextSize = 24, TextColor3 = UI.Colors.Text, Size = UDim2.new(1, -28, 0, 32), Position = UDim2.fromOffset(14, 112) }, card)

	local priceBadge = UI.Frame({ Size = UDim2.new(0.5, -18, 0, 44), Position = UDim2.new(0, 14, 1, -58), BackgroundColor3 = UI.Colors.PanelDark }, card)
	UI.Corner(priceBadge, 10)
	local priceLabel = UI.Label({ Text = "$150", TextSize = 22, TextColor3 = UI.Colors.Cash }, priceBadge)
	local button = UI.Button({ Text = "UPGRADE", Color = color, Size = UDim2.new(0.5, -18, 0, 44), Position = UDim2.new(0.5, 4, 1, -58), TextSize = 20, Shine = 3.5 + order * 0.6 }, card)

	local entry = { Card = card, Level = levelLabel, Stat = statLabel, Price = priceLabel, PriceBadge = priceBadge, Button = button, Def = def, Desc = desc, Pips = pipList, Color = color }
	button.Activated:Connect(function()
		UpgradeController.Buy(def.Key, entry)
	end)
	return entry
end

local function refreshCard(entry)
	local def = entry.Def
	local level = player:GetAttribute(def.Attribute) or 1
	local max = UpgradeConfig.GetMaxLevel(def.Key)
	local current = UpgradeConfig.GetValue(def.Key, level)
	for i, pip in ipairs(entry.Pips) do
		pip.BackgroundColor3 = i <= level and entry.Color or UI.Colors.PanelDark
	end
	if level >= max then
		entry.Level.Text = string.format("Lv. %d  -  MAX", level)
		entry.Stat.Text = def.Format(current)
		entry.Stat.TextColor3 = entry.Color
		entry.Price.Text = "MAXED"
		entry.Price.TextColor3 = UI.Colors.Gold
		UI.SetButtonEnabled(entry.Button, false, "MAXED")
		return
	end
	local nextValue = UpgradeConfig.GetValue(def.Key, level + 1)
	local cost = UpgradeConfig.GetNextCost(def.Key, level) or 0
	entry.Level.Text = string.format("Lv. %d  ->  Lv. %d", level, level + 1)
	entry.Stat.Text = string.format("%s  ->  %s", def.Format(current), def.Format(nextValue))
	entry.Stat.TextColor3 = UI.Colors.Text
	entry.Price.Text = FormatUtil.CashExact(cost)
	local cash = player:GetAttribute("RoomCash") or 0
	local affordable = cash >= cost
	entry.Price.TextColor3 = affordable and UI.Colors.Cash or UI.Colors.Red
	UI.SetButtonEnabled(entry.Button, true)
	entry.Button.Text = "UPGRADE"
	entry.Button.BackgroundColor3 = affordable and entry.Color or UI.Colors.Locked
end

local function refreshAll()
	for _, entry in pairs(cards) do
		refreshCard(entry)
	end
	if cashHeader then
		cashHeader.Text = "CASH: " .. FormatUtil.CashExact(player:GetAttribute("RoomCash") or 0)
	end
end

function UpgradeController.Init()
	menu = UI.Menu("Upgrades", "UPGRADES", UDim2.fromOffset(680, 560))
	cashHeader = UI.Label({ Text = "CASH: $0", TextSize = 22, TextColor3 = UI.Colors.Cash, Size = UDim2.new(1, 0, 0, 30) }, menu.Content)
	local scroll = UI.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -36),
		Position = UDim2.fromOffset(0, 36),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
	}, menu.Content)
	UI.GridLayout(scroll, UDim2.fromOffset(310, 206), 14)

	for i, def in ipairs(UpgradeConfig.List) do
		cards[def.Key] = buildCard(def, scroll, i)
	end

	for _, def in ipairs(UpgradeConfig.List) do
		player:GetAttributeChangedSignal(def.Attribute):Connect(refreshAll)
	end
	player:GetAttributeChangedSignal("RoomCash"):Connect(function()
		if menu.IsOpen() then
			refreshAll()
		end
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(refreshAll)
	menu.OnOpen(refreshAll)
	refreshAll()
end

function UpgradeController.Open()
	if not player:GetAttribute("InMatch") then
		Controllers.NotificationController.Show("Info", "Upgrades are available inside rooms.")
		return
	end
	menu.Open()
end

function UpgradeController.Buy(key: string, entry)
	if busy then
		return
	end
	busy = true
	local ok, message = Remotes.Function("RequestUpgrade"):InvokeServer(key)
	busy = false
	if ok then
		UI.Flash(entry.Card, UI.Colors.GreenDark, 0.5)
		local s = entry.Card:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, entry.Card)
		s.Scale = 1.06
		UI.Tween(s, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
		Controllers.AudioController.Play("UpgradePurchase")
		Controllers.NotificationController.Show("Success", message or "Upgraded!")
	else
		UI.Shake(entry.Card, 6, 0.3)
		UI.Flash(entry.Card, UI.Colors.Red, 0.5)
		Controllers.AudioController.Play("UpgradeDenied")
		if message and message ~= "MAXED" then
			Controllers.NotificationController.Show("Error", message, 2.5)
		end
	end
	refreshAll()
end

function UpgradeController.IsOpen(): boolean
	return menu.IsOpen()
end

return UpgradeController
