--[[
	Shop: three tabs (Permanent game passes, timed Boosts, instant Help). Every card shows what
	kind of purchase it is (FOREVER / 10 MIN BOOST / INSTANT), the price on its buy button and
	OWNED for passes already bought. Purchases go through the server (RequestPurchase).
	It opens instantly: the cards come straight from MonetizationConfig, and the server's live
	prices (fetched in the background at start) replace the config prices when they arrive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local serverInfo = ReplicatedStorage:WaitForChild("ServerInfo")

local ShopController = {}

local menu
local tabButtons: { [string]: TextButton } = {}
local listFrame: ScrollingFrame
local tabHint: TextLabel
local currentTab = "Permanent"
local products = nil
local fetching = false

local ROBUX = utf8.char(0xE002) -- the Robux icon glyph

local TabColors = { Permanent = UI.Colors.Gold, Boosts = UI.Colors.Green, Help = UI.Colors.Cyan }
local TabInfo = {
	Permanent = { Ribbon = "FOREVER", Hint = "Permanent perks: buy once, keep them forever." },
	Boosts = { Ribbon = "10 MIN BOOST", Hint = "Timed boosts: they stack and carry between rooms." },
	Help = { Ribbon = "INSTANT", Hint = "Clues unlock at 25% ROOM CLEANED." },
}

local function isDev(): boolean
	return serverInfo:GetAttribute("IsStudio") == true and serverInfo:GetAttribute("DevelopmentMode") == true
end

local function buildCard(info, order: number)
	local owned = info.Kind == "Gamepass" and player:GetAttribute("Pass_" .. info.Key) == true
	local accent = TabColors[info.Tab] or UI.Colors.Cyan
	local card = UI.Panel({ Size = UDim2.new(1, -14, 0, 112), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, listFrame)
	UI.Stroke(card, owned and UI.Colors.Green or UI.Colors.Stroke, 2.5)

	local icon = UI.Surface3D({ Size = UDim2.fromOffset(76, 76), Position = UDim2.fromOffset(14, 16) }, card, accent, 14, 0.1)
	local glyph = UI.Icon(icon, "Icon_Prod_" .. info.Key, info.Icon or "?", { TextSize = 22 })
	glyph.Size = UDim2.fromScale(0.8, 0.72)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.45)

	UI.Label({ Text = info.Name, TextSize = 21, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -290, 0, 26), Position = UDim2.fromOffset(104, 12), TextXAlignment = Enum.TextXAlignment.Left }, card)
	local ribbon = UI.Surface3D({ Size = UDim2.fromOffset(116, 22), Position = UDim2.fromOffset(104, 40) }, card, owned and UI.Colors.Green or accent, 11, 0.14)
	UI.Label({ Text = owned and "OWNED" or TabInfo[info.Tab].Ribbon, TextSize = 12, TextWrapped = false, Size = UDim2.new(1, -8, 0.86, 0), Position = UDim2.fromOffset(4, 0) }, ribbon)
	UI.Label({ Text = info.Description, TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -290, 0, 40), Position = UDim2.fromOffset(104, 66), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, card)

	local priceText
	if info.Price then
		priceText = string.format("%s %d", ROBUX, info.Price)
	elseif info.Configured then
		-- The store price is set to the config price; the live one replaces it when it arrives.
		priceText = string.format("%s %d", ROBUX, info.SuggestedPrice)
	else
		priceText = string.format("~%s %d", ROBUX, info.SuggestedPrice)
	end
	local button = UI.Button({ Text = owned and "OWNED ✓" or priceText, Color = UI.Colors.Green, Size = UDim2.fromOffset(160, 54), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), TextSize = 22, Shine = not owned and (3 + order * 0.5) or nil }, card)
	if not info.Configured then
		UI.Label({ Text = isDev() and "ID NOT SET (dev mock)" or "COMING SOON", TextSize = 11, Font = UI.FontBody, TextColor3 = UI.Colors.Orange, Size = UDim2.fromOffset(160, 14), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -18), TextXAlignment = Enum.TextXAlignment.Center }, card)
	end
	if owned then
		UI.SetButtonEnabled(button, false, "OWNED ✓")
	elseif not info.Configured and not isDev() then
		UI.SetButtonEnabled(button, false, "SOON")
	else
		button.Activated:Connect(function()
			if info.MatchOnly and not player:GetAttribute("InMatch") then
				Controllers.NotificationController.Show("Warning", "You can use this inside a room.")
				return
			end
			Remotes.Event("RequestPurchase"):FireServer(info.Key)
		end)
	end
end

-- The shop list straight from the config, in the same shape the server sends (no live prices).
local function configProducts()
	local list = {}
	for _, pair in ipairs({ { MonetizationConfig.GamepassDefs, "Gamepass" }, { MonetizationConfig.ProductDefs, "Product" } }) do
		for _, def in ipairs(pair[1]) do
			table.insert(list, {
				Key = def.Key, Kind = pair[2], Name = def.Name, Description = def.Description, Icon = def.Icon,
				Tab = def.Tab, Price = nil, SuggestedPrice = def.SuggestedPrice, Configured = def.Id ~= 0, MatchOnly = def.MatchOnly == true,
			})
		end
	end
	return list
end

local function render()
	for _, c in ipairs(listFrame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == currentTab and TabColors[name] or UI.Colors.PanelLight
	end
	tabHint.Text = TabInfo[currentTab].Hint
	local order = 0
	for _, info in ipairs(products or configProducts()) do
		if info.Tab == currentTab then
			order += 1
			buildCard(info, order)
		end
	end
end

local function fetch()
	if fetching then
		return
	end
	fetching = true
	local ok, result = pcall(function()
		return Remotes.Function("GetShopInfo"):InvokeServer()
	end)
	fetching = false
	if ok and type(result) == "table" then
		products = result
	end
	if menu.IsOpen() then
		render()
	end
end

function ShopController.Init()
	menu = UI.Menu("Shop", "SHOP", UDim2.fromOffset(640, 560), UI.Colors.Purple)

	local tabs = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46) }, menu.Content)
	UI.ListLayout(tabs, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	for i, name in ipairs({ "Permanent", "Boosts", "Help" }) do
		local b = UI.Button({ Text = string.upper(name), Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(160, 44), TextSize = 18, LayoutOrder = i }, tabs)
		tabButtons[name] = b
		b.Activated:Connect(function()
			currentTab = name
			render()
		end)
	end
	tabHint = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 52) }, menu.Content)

	listFrame = UI.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -80),
		Position = UDim2.fromOffset(0, 78),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UI.Colors.TextDim,
		BorderSizePixel = 0,
	}, menu.Content) :: ScrollingFrame
	UI.ListLayout(listFrame, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)
	UI.Padding(listFrame, { 0, 0, 4, 8 })

	menu.OnOpen(function()
		render()
		task.spawn(fetch)
	end)

	Remotes.Event("PurchaseUpdate").OnClientEvent:Connect(function(kind)
		if kind == "PassGranted" and menu.IsOpen() then
			render()
		end
	end)
end

function ShopController.Start()
	-- Have the live prices ready before the shop is first opened.
	task.delay(2, fetch)
end

function ShopController.Open(tab: string?)
	if tab then
		currentTab = tab
	elseif not player:GetAttribute("InMatch") then
		currentTab = "Permanent"
	end
	menu.Open()
end

return ShopController
