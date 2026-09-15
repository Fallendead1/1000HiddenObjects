local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local TargetData = require(Shared.Data.TargetData)

local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local CollectionController = {}

-- The book shows 100 objects a page, and one set of 100 tiles is reused for every page (all
-- 1,000 tiles at once were ~14k GUI objects - heavy on phones).
local PAGE_SIZE = 100

local menu
local header: TextLabel
local pageLabel: TextLabel
local prevButton: TextButton
local nextButton: TextButton
local grid: ScrollingFrame
local tiles: { { Frame: Frame, Icon: Frame, Name: TextLabel, Number: TextLabel, Check: TextLabel, Glyph: TextLabel, Image: ImageLabel } } = {}
local page = 1

local function pageCount(): number
	return math.ceil(GameConfig.TotalObjects / PAGE_SIZE)
end

local function buildTile(index: number)
	local tile = UI.Panel({ Size = UDim2.fromOffset(96, 110), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = index }, grid)
	local numberLabel = UI.Label({ Text = "", TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 4) }, tile)
	local icon = UI.Frame({ Size = UDim2.fromOffset(52, 52), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), BackgroundColor3 = UI.Colors.Locked }, tile)
	UI.Corner(icon, 8)
	UI.Stroke(icon, Color3.new(0, 0, 0), 2)
	local glyph = UI.Label({ Text = "?", TextSize = 28, TextColor3 = UI.Colors.TextDim }, icon)
	local image = UI.Image({ Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), Visible = false }, icon)
	local nameLabel = UI.Label({ Text = "???", TextSize = 13, Font = UI.FontBody, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 80), TextTruncate = Enum.TextTruncate.AtEnd }, tile)
	local check = UI.Label({ Text = "✓", TextSize = 16, TextColor3 = UI.Colors.Green, Size = UDim2.fromOffset(24, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Visible = false }, tile)
	tiles[index] = { Frame = tile, Icon = icon, Name = nameLabel, Number = numberLabel, Check = check, Glyph = glyph, Image = image }
end

local function refresh()
	local found = player:GetAttribute("ObjectsFound") or 0
	header.Text = string.format("%d / %d FOUND", found, GameConfig.TotalObjects)
	local first = (page - 1) * PAGE_SIZE
	local last = math.min(first + PAGE_SIZE, GameConfig.TotalObjects)
	pageLabel.Text = string.format("%s - %s   ·   PAGE %d / %d", TargetData.FormatNumber(first + 1), TargetData.FormatNumber(last), page, pageCount())
	UI.SetButtonEnabled(prevButton, page > 1)
	UI.SetButtonEnabled(nextButton, page < pageCount())
	for index, tile in ipairs(tiles) do
		local number = first + index
		tile.Frame.Visible = number <= GameConfig.TotalObjects
		tile.Number.Text = TargetData.FormatNumber(number)
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
			UI.Stroke(tile.Frame, UI.Colors.Gold, 2.5)
		else
			-- Not found yet: a silhouette (tiles are reused, so reset everything).
			tile.Icon.BackgroundColor3 = UI.Colors.Locked
			tile.Glyph.Text = "?"
			tile.Glyph.TextColor3 = UI.Colors.TextDim
			tile.Name.Text = "???"
			tile.Name.TextColor3 = UI.Colors.TextDim
			tile.Check.Visible = false
			UI.Stroke(tile.Frame, Color3.new(0, 0, 0), 2.5)
		end
	end
end

local function setPage(p: number)
	page = math.clamp(p, 1, pageCount())
	grid.CanvasPosition = Vector2.zero
	refresh()
end

function CollectionController.Init()
	menu = UI.Menu("Collection", "1000 HIDDEN OBJECTS", UDim2.fromOffset(760, 560))
	header = UI.Label({ Text = "0 / 1000 FOUND", TextSize = 26, TextWrapped = false, Size = UDim2.new(1, 0, 0, 34) }, menu.Content)
	UI.TextGradient(header, UI.Colors.Gold)
	-- Pager:  <   #001 - #100 · PAGE 1 / 10   >
	prevButton = UI.Button({ Text = "<", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(56, 36), Position = UDim2.fromOffset(4, 38), TextSize = 26 }, menu.Content)
	nextButton = UI.Button({ Text = ">", Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(56, 36), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 38), TextSize = 26 }, menu.Content)
	menu.Primary = nextButton -- controllers: A pages on
	pageLabel = UI.Label({ Text = "", TextSize = 16, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, -140, 0, 36), Position = UDim2.fromOffset(70, 38) }, menu.Content)
	grid = UI.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -84),
		Position = UDim2.fromOffset(0, 84),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		BorderSizePixel = 0,
	}, menu.Content) :: ScrollingFrame
	UI.GridLayout(grid, UDim2.fromOffset(96, 110), 8)
	-- Room for the tiles' borders, which draw just outside them (the scroll clips its edges).
	UI.New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, grid)

	prevButton.Activated:Connect(function()
		if page > 1 then
			setPage(page - 1)
		end
	end)
	nextButton.Activated:Connect(function()
		if page < pageCount() then
			setPage(page + 1)
		end
	end)

	menu.OnOpen(function()
		if #tiles == 0 then
			for i = 1, PAGE_SIZE do
				buildTile(i)
			end
		end
		-- Open on the page with the next object to find.
		setPage(math.floor((player:GetAttribute("ObjectsFound") or 0) / PAGE_SIZE) + 1)
	end)
	player:GetAttributeChangedSignal("ObjectsFound"):Connect(function()
		if #tiles > 0 then
			refresh()
		end
	end)
end

function CollectionController.Open()
	menu.Open()
end

return CollectionController
