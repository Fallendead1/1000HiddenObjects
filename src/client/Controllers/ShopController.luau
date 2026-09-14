local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local serverInfo = ReplicatedStorage:WaitForChild("ServerInfo")

local ShopController = {}

local menu
local tabButtons: { [string]: TextButton } = {}
local listFrame: ScrollingFrame
local currentTab = "Permanent"
local products = nil
local fetching = false

local TabColors = { Permanent = UI.Colors.Gold, Boosts = UI.Colors.Green, Help = UI.Colors.Cyan }

local function isDev(): boolean
	return serverInfo:GetAttribute("IsStudio") == true and serverInfo:GetAttribute("DevelopmentMode") == true
end

local function buildCard(info, order: number)
	local owned = info.Kind == "Gamepass" and player:GetAttribute("Pass_" .. info.Key) == true
	local card = UI.Panel({ Size = UDim2.new(1, -12, 0, 104), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = order }, listFrame)
	local icon = UI.Frame({ Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(14, 20), BackgroundColor3 = TabColors[info.Tab] or UI.Colors.Cyan }, card)
	UI.Corner(icon, 12)
	UI.Icon(icon, "Icon_Prod_" .. info.Key, info.Icon or "?", { TextSize = 20, TextColor3 = UI.Colors.PanelDark })
	UI.Label({ Text = info.Name, TextSize = 22, Size = UDim2.new(1, -260, 0, 30), Position = UDim2.fromOffset(92, 12), TextXAlignment = Enum.TextXAlignment.Left }, card)
	UI.Label({ Text = info.Description, TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -260, 0, 52), Position = UDim2.fromOffset(92, 42), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, card)

	local priceText
	if info.Price then
		priceText = string.format("%d R$", info.Price)
	elseif info.Configured then
		priceText = "R$ --"
	else
		priceText = string.format("~%d R$", info.SuggestedPrice)
	end
	UI.Label({ Text = priceText, TextSize = 22, TextColor3 = UI.Colors.Green, Size = UDim2.fromOffset(140, 30), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), TextXAlignment = Enum.TextXAlignment.Right }, card)
	if not info.Configured then
		UI.Label({ Text = isDev() and "PRODUCT ID NOT SET (dev mock)" or "COMING SOON", TextSize = 12, Font = UI.FontBody, TextColor3 = UI.Colors.Orange, Size = UDim2.fromOffset(200, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 40), TextXAlignment = Enum.TextXAlignment.Right }, card)
	end

	local button = UI.Button({ Text = owned and "OWNED" or "BUY", Color = owned and UI.Colors.Locked or UI.Colors.Green, Size = UDim2.fromOffset(130, 42), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -12), TextSize = 20, Shine = not owned and (3 + order * 0.5) or nil }, card)
	if owned then
		UI.SetButtonEnabled(button, false, "OWNED")
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

local function render()
	-- Everything but the list layout (cards and the "Loading..." line alike).
	for _, c in ipairs(listFrame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == currentTab and TabColors[name] or UI.Colors.PanelLight
	end
	if not products then
		UI.Label({ Text = "Loading...", TextSize = 20, Size = UDim2.new(1, 0, 0, 60) }, listFrame)
		return
	end
	local order = 0
	for _, info in ipairs(products) do
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
	menu = UI.Menu("Shop", "SHOP", UDim2.fromOffset(620, 540))

	local tabs = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44) }, menu.Content)
	UI.ListLayout(tabs, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center)
	for i, name in ipairs({ "Permanent", "Boosts", "Help" }) do
		local b = UI.Button({ Text = string.upper(name), Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(150, 40), TextSize = 18, LayoutOrder = i }, tabs)
		tabButtons[name] = b
		b.Activated:Connect(function()
			currentTab = name
			render()
		end)
	end

	listFrame = UI.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.fromOffset(0, 52),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		BorderSizePixel = 0,
	}, menu.Content) :: ScrollingFrame
	UI.ListLayout(listFrame, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)

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

function ShopController.Open(tab: string?)
	if tab then
		currentTab = tab
	elseif not player:GetAttribute("InMatch") then
		currentTab = "Permanent"
	end
	menu.Open()
end

return ShopController
