local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local TargetData = require(Shared.Data.TargetData)

local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local CollectionController = {}

local menu
local header: TextLabel
local grid: ScrollingFrame
local tiles: { [number]: { Frame: Frame, Icon: Frame, Name: TextLabel, Number: TextLabel, Check: TextLabel, Glyph: TextLabel, Image: ImageLabel } } = {}
local built = false

local function buildTile(number: number)
	local tile = UI.Frame({ Size = UDim2.fromOffset(96, 110), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = number }, grid)
	UI.Corner(tile, 10)
	UI.Stroke(tile, UI.Colors.Stroke, 1)
	local numberLabel = UI.Label({ Text = TargetData.FormatNumber(number), TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 4) }, tile)
	local icon = UI.Frame({ Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), BackgroundColor3 = UI.Colors.Locked }, tile)
	UI.Corner(icon, 8)
	local glyph = UI.Label({ Text = "?", TextSize = 28, TextColor3 = UI.Colors.TextDim }, icon)
	local image = UI.Image({ Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), Visible = false }, icon)
	local nameLabel = UI.Label({ Text = "???", TextSize = 13, Font = UI.FontBody, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 80), TextTruncate = Enum.TextTruncate.AtEnd }, tile)
	local check = UI.Label({ Text = "✓", TextSize = 16, TextColor3 = UI.Colors.Green, Size = UDim2.fromOffset(24, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Visible = false }, tile)
	tiles[number] = { Frame = tile, Icon = icon, Name = nameLabel, Number = numberLabel, Check = check, Glyph = glyph, Image = image }
end

local function refresh()
	local found = player:GetAttribute("ObjectsFound") or 0
	header.Text = string.format("%d / %d FOUND", found, GameConfig.TotalObjects)
	for number, tile in pairs(tiles) do
		local def = TargetData.Get(number)
		local art = def and number <= found and UI.Asset(def.IconKey or "") or nil
		tile.Image.Image = art or ""
		tile.Image.Visible = art ~= nil
		tile.Glyph.Visible = art == nil
		if number <= found and def then
			tile.Icon.BackgroundColor3 = def.Color
			tile.Glyph.Text = string.upper(string.sub(def.Name, 1, 1))
			tile.Glyph.TextColor3 = UI.Colors.PanelDark
			tile.Name.Text = def.Name
			tile.Name.TextColor3 = UI.Colors.Text
			tile.Check.Visible = true
			tile.Frame.BackgroundColor3 = UI.Colors.Panel
		elseif def then
			-- Known but unfound object: silhouette.
			tile.Icon.BackgroundColor3 = UI.Colors.Locked
			tile.Glyph.Text = "?"
			tile.Glyph.TextColor3 = UI.Colors.TextDim
			tile.Name.Text = "???"
			tile.Name.TextColor3 = UI.Colors.TextDim
			tile.Check.Visible = false
		else
			tile.Icon.BackgroundColor3 = UI.Colors.Locked
			tile.Glyph.Text = "?"
			tile.Name.Text = "???"
			tile.Name.TextColor3 = UI.Colors.TextDim
			tile.Check.Visible = false
		end
	end
end

local function build()
	if built then
		return
	end
	built = true
	for i = 1, GameConfig.TotalObjects do
		buildTile(i)
		if i % 100 == 0 then
			task.wait()
		end
	end
	refresh()
end

function CollectionController.Init()
	menu = UI.Menu("Collection", "1000 HIDDEN OBJECTS", UDim2.fromOffset(760, 560))
	header = UI.Label({ Text = "0 / 1000 FOUND", TextSize = 26, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 36) }, menu.Content)
	grid = UI.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.fromOffset(0, 44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		BorderSizePixel = 0,
	}, menu.Content) :: ScrollingFrame
	UI.GridLayout(grid, UDim2.fromOffset(96, 110), 8)

	menu.OnOpen(function()
		if not built then
			task.spawn(build)
		else
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("ObjectsFound"):Connect(function()
		if built then
			refresh()
		end
	end)
end

function CollectionController.Open()
	menu.Open()
end

return CollectionController
