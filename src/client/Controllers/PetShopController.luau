--[[
	The Pet Shop and pet menu (PETS tile, and the lobby's egg pedestals: parts tagged
	EggPedestal with an Egg attribute, or PetShop):
	  EGGS     the three eggs with their price in saved Cash and every pet's exact odds; HATCH buys
	           one (PetService). Premium pets and perks (game passes) sit underneath.
	  MY PETS  equip and unequip, levels and slots.
	  INDEX    every pet, found or not, and how to get it.
	Server attributes: PetData (JSON), PetSlots, Wallet, CleanerLevel.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local FormatUtil = require(Shared.Utility.FormatUtil)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local PetModels = require(script.Parent.Parent.UI.PetModels)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local serverInfo = ReplicatedStorage:WaitForChild("ServerInfo")

local PetShopController = {}

local ROBUX = utf8.char(0xE002)
local TABS = { "Eggs", "MyPets", "Index" }
local TAB_NAMES = { Eggs = "EGGS", MyPets = "MY PETS", Index = "INDEX" }

local menu
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}
local walletLabel: TextLabel
local current = "Eggs"
local firstHatch: TextButton? = nil
local busyUntil = 0

local function attr(name: string, default: any)
	local v = player:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end

local function petData()
	local ok, data = pcall(HttpService.JSONDecode, HttpService, attr("PetData", "{}"))
	data = (ok and type(data) == "table") and data or {}
	data.Owned = data.Owned or {}
	data.Equipped = data.Equipped or {}
	return data
end

local function clear(frame: Instance)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function rarity(kind: string)
	local def = PetConfig.Get(kind)
	return def and PetConfig.Rarities[def.Rarity] or PetConfig.Rarities.Common
end

local function isDev(): boolean
	return serverInfo:GetAttribute("IsStudio") == true and serverInfo:GetAttribute("DevelopmentMode") == true
end

-- Which eggs (or pass) a pet comes from.
local function sourceText(kind: string): string
	local def = PetConfig.Get(kind)
	local from = {}
	for _, eggKey in ipairs(PetConfig.EggOrder) do
		if PetConfig.Eggs[eggKey].Odds[kind] then
			local name = string.gsub(string.lower(PetConfig.Eggs[eggKey].Name), "^%l", string.upper)
			table.insert(from, name)
		end
	end
	if kind == PetConfig.StarterPet then
		table.insert(from, 1, "Welcome gift")
	end
	if def and def.Pass then
		table.insert(from, "Pet pass")
	end
	return table.concat(from, ", ")
end

-- ===== Eggs =====

local function premiumButton(parent: Instance, key: string, order: number)
	local def = MonetizationConfig.FindDef(key)
	if not def or (def.Id == 0 and not isDev()) then
		return
	end
	local owned = attr("Pass_" .. key, false)
	local b = UI.Button({ Text = owned and (def.Name .. "  ✓") or string.format("%s  %s %d", def.Name, ROBUX, def.SuggestedPrice), Color = owned and UI.Colors.Locked or UI.Colors.Purple, Size = UDim2.fromOffset(196, 40), FitText = 14, LayoutOrder = order }, parent)
	if owned then
		UI.SetButtonEnabled(b, false)
	else
		b.Activated:Connect(function()
			Remotes.Event("RequestPurchase"):FireServer(key)
		end)
	end
end

local function renderEggs(page: Frame)
	clear(page)
	firstHatch = nil
	local wallet = attr("Wallet", 0)
	local row = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 330) }, page)
	UI.ListLayout(row, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)
	for i, eggKey in ipairs(PetConfig.EggOrder) do
		local egg = PetConfig.Eggs[eggKey]
		local card = UI.Panel({ Name = "Egg_" .. eggKey, Size = UDim2.new(1 / 3, -10, 1, 0), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, row)
		UI.Stroke(card, egg.Color, 2.5)
		local header = UI.Surface3D({ Size = UDim2.new(1, 0, 0, 34) }, card, egg.Color, 12, 0.12)
		UI.Label({ Text = egg.Name, TextSize = 18, TextWrapped = false, Size = UDim2.fromScale(1, 0.9) }, header)
		local stage = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(96, 96), Position = UDim2.fromOffset(6, 38) }, card)
		local art = UI.Asset("Egg_" .. eggKey)
		if art then
			UI.Image({ Image = art, Size = UDim2.fromScale(1, 1) }, stage)
		else
			PetModels.Viewport(stage, PetModels.BuildEgg(eggKey), nil, true)
		end
		local price = UI.Label({ Text = FormatUtil.CashExact(egg.Price), TextSize = 26, TextWrapped = false, Size = UDim2.new(1, -110, 0, 32), Position = UDim2.fromOffset(106, 50), TextXAlignment = Enum.TextXAlignment.Left }, card)
		UI.TextGradient(price, UI.Colors.Cash)
		UI.Label({ Text = "saved Cash", TextSize = 12, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, -110, 0, 16), Position = UDim2.fromOffset(106, 82), TextXAlignment = Enum.TextXAlignment.Left }, card)
		-- Every pet in the egg with its exact chance.
		local odds = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 116), Position = UDim2.fromOffset(8, 140) }, card)
		UI.ListLayout(odds, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Left)
		for n, entry in ipairs(PetConfig.EggOdds(eggKey)) do
			local def = PetConfig.Get(entry.Key)
			local r = rarity(entry.Key)
			local line = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = n }, odds)
			local dot = UI.Frame({ Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 0, 0.5, -5), BackgroundColor3 = r.Color }, line)
			UI.New("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			UI.Label({ Text = def and def.Name or entry.Key, TextSize = 13, Font = UI.FontBody, TextWrapped = false, TextColor3 = r.Color, Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(16, 0), TextXAlignment = Enum.TextXAlignment.Left }, line)
			local pct = entry.Chance * 100
			UI.Label({ Text = pct >= 1 and string.format("%d%%", math.floor(pct + 0.5)) or string.format("%.1f%%", pct), TextSize = 13, TextWrapped = false, Size = UDim2.new(0, 50, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, line)
		end
		local hatch = UI.Button({ Name = "Hatch_" .. eggKey, Text = "HATCH", Color = UI.Colors.Green, Size = UDim2.new(1, -24, 0, 48), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), TextSize = 22, Shine = 2 + i * 0.4 }, card)
		if wallet < egg.Price then
			UI.SetButtonEnabled(hatch, false, "NEED " .. FormatUtil.CashExact(egg.Price - wallet))
		end
		hatch.Activated:Connect(function()
			if not hatch.Active or os.clock() < busyUntil then
				return
			end
			busyUntil = os.clock() + 1.5
			Remotes.Event("BuyEgg"):FireServer(eggKey)
		end)
		firstHatch = firstHatch or hatch
	end
	-- Premium pets and perks (game passes).
	local strip = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 84), Position = UDim2.fromOffset(0, 338) }, page)
	UI.Label({ Text = "PREMIUM PETS & PERKS", TextSize = 14, TextWrapped = false, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left }, strip)
	local buttons = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 22) }, strip)
	UI.ListLayout(buttons, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	for i, key in ipairs({ "PetVacuumCat", "PetGoldenDragon", "PetSlot", "FasterPets" }) do
		premiumButton(buttons, key, i)
	end
	UI.Label({ Text = "Eggs are bought with saved Cash, which can't be bought. The odds above are exact.", TextSize = 11, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 70), TextXAlignment = Enum.TextXAlignment.Left }, strip)
end

-- ===== My pets =====

local function renderMyPets(page: Frame)
	clear(page)
	local data = petData()
	local slots = attr("PetSlots", 1)
	local header = UI.Label({ Text = string.format("EQUIPPED %d / %d", #data.Equipped, slots), TextSize = 20, TextWrapped = false, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left }, page)
	UI.TextGradient(header, UI.Colors.Pink)
	local slotHint = attr("CleanerLevel", 1) >= PetConfig.SlotLevel and "More slots: the +1 Pet Slot pass." or string.format("A free extra slot at Cleaner level %d.", PetConfig.SlotLevel)
	UI.Label({ Text = slotHint, TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(0.6, 0, 0, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, page)
	local scroll = UI.New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, -34), Position = UDim2.fromOffset(0, 34), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 }, page) :: ScrollingFrame
	local grid = UI.GridLayout(scroll, UDim2.fromOffset(150, 196), 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	local kinds = {}
	for _, def in ipairs(PetConfig.List) do
		if data.Owned[def.Key] then
			table.insert(kinds, def)
		end
	end
	table.sort(kinds, function(a, b)
		local ea, eb = table.find(data.Equipped, a.Key) ~= nil, table.find(data.Equipped, b.Key) ~= nil
		if ea ~= eb then
			return ea
		end
		return PetConfig.Rarities[a.Rarity].Order > PetConfig.Rarities[b.Rarity].Order
	end)
	if #kinds == 0 then
		UI.Label({ Text = "No pets yet - hatch an egg to get your first helper!", TextSize = 18, Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 120) }, page)
		return
	end
	for i, def in ipairs(kinds) do
		local owned = data.Owned[def.Key]
		local equipped = table.find(data.Equipped, def.Key) ~= nil
		local r = PetConfig.Rarities[def.Rarity]
		local card = UI.Panel({ Name = "Pet_" .. def.Key, BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, scroll)
		UI.Stroke(card, equipped and Color3.new(1, 1, 1) or r.Color, equipped and 3 or 2)
		if equipped then
			local tag = UI.Surface3D({ Size = UDim2.fromOffset(84, 20), Position = UDim2.fromOffset(4, 4), ZIndex = 5 }, card, UI.Colors.Green, 8, 0.1)
			UI.Label({ Text = "EQUIPPED", TextSize = 11, TextWrapped = false, Size = UDim2.fromScale(1, 0.9), ZIndex = 6 }, tag)
		end
		local stage = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromOffset(84, 84), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4) }, card)
		PetModels.Viewport(stage, PetModels.Build(def.Key))
		local name = UI.Label({ Text = def.Name, TextSize = 14, TextWrapped = false, Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 88) }, card)
		UI.TextGradient(name, r.Color)
		UI.Label({ Text = string.format("%s · LV %d", r.Name, owned.Level or 1), TextSize = 11, TextWrapped = false, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 106) }, card)
		local bar = UI.ProgressBar(card, UDim2.new(1, -20, 0, 12), UDim2.fromOffset(10, 124), UI.Colors.Cyan)
		bar.Set((owned.Next or 0) > 0 and (owned.XP or 0) / owned.Next or 1, true)
		local b = UI.Button({ Name = "Equip", Text = equipped and "UNEQUIP" or "EQUIP", Color = equipped and UI.Colors.Red or UI.Colors.Green, Size = UDim2.new(1, -16, 0, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), FitText = 16 }, card)
		if not equipped and #data.Equipped >= slots then
			b.Text = "SLOTS FULL"
			b.BackgroundColor3 = UI.Colors.Locked
		end
		b.Activated:Connect(function()
			Remotes.Event("EquipPet"):FireServer(def.Key, not equipped)
		end)
	end
end

-- ===== Index =====

local function renderIndex(page: Frame)
	clear(page)
	local data = petData()
	local found = 0
	for _, def in ipairs(PetConfig.List) do
		if data.Owned[def.Key] then
			found += 1
		end
	end
	local header = UI.Label({ Text = string.format("PET INDEX: %d / %d FOUND", found, #PetConfig.List), TextSize = 20, TextWrapped = false, Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left }, page)
	UI.TextGradient(header, UI.Colors.Gold)
	UI.Label({ Text = string.format("Find all %d: $%s and the %s title", #PetConfig.List, FormatUtil.Comma(PetConfig.IndexReward), string.upper(PetConfig.IndexTitle)), TextSize = 13, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, TextWrapped = false, Size = UDim2.new(0.6, 0, 0, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, page)
	local gridFrame = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -34), Position = UDim2.fromOffset(0, 34) }, page)
	local grid = UI.GridLayout(gridFrame, UDim2.new(0.2, -8, 0.5, -8), 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	for i, def in ipairs(PetConfig.List) do
		local has = data.Owned[def.Key] ~= nil
		local r = PetConfig.Rarities[def.Rarity]
		local card = UI.Panel({ Name = "Index_" .. def.Key, BackgroundColor3 = UI.Colors.PanelLight, BackgroundTransparency = has and 0.05 or 0.4, LayoutOrder = i }, gridFrame)
		UI.Stroke(card, has and r.Color or Color3.new(0, 0, 0), 2)
		local stage = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0.55, 0) }, card)
		-- Pets not found yet show as a dark silhouette.
		PetModels.Viewport(stage, PetModels.Build(def.Key), if has then nil else { ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.15 }, has)
		local name = UI.Label({ Text = has and def.Name or "???", TextSize = 13, TextWrapped = false, Size = UDim2.new(1, -6, 0, 16), Position = UDim2.new(0, 3, 0.56, 0) }, card)
		if has then
			UI.TextGradient(name, r.Color)
		end
		UI.Label({ Text = r.Name, TextSize = 10, TextWrapped = false, TextColor3 = r.Color, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0.56, 17) }, card)
		UI.Label({ Text = sourceText(def.Key), TextSize = 10, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -6, 0, 26), Position = UDim2.new(0, 3, 0.56, 31), TextYAlignment = Enum.TextYAlignment.Top }, card)
	end
end

-- ===== Menu =====

local renderers = { Eggs = renderEggs, MyPets = renderMyPets, Index = renderIndex }

local function render()
	if not menu or not menu.IsOpen() then
		return
	end
	walletLabel.Text = "SAVED CASH: " .. FormatUtil.CashExact(attr("Wallet", 0))
	for name, b in pairs(tabButtons) do
		b.BackgroundColor3 = name == current and UI.Colors.Pink or UI.Colors.PanelLight
		pages[name].Visible = name == current
	end
	renderers[current](pages[current])
end

-- Each egg on show in the lobby floats, turns slowly and burns with an aura in its own colour:
-- a flame of light around it, sparkles, a glowing ring on its pedestal and a light. The rarer
-- the egg, the stronger all of it. The egg itself is the model "<Egg>Display" next to the
-- pedestal (the pedestal is the part tagged EggPedestal).
local AURAS = {
	Dusty = { Color = Color3.fromRGB(255, 214, 150), Second = Color3.fromRGB(255, 240, 210), Power = 1 },
	Shiny = { Color = Color3.fromRGB(90, 210, 255), Second = Color3.fromRGB(255, 255, 255), Power = 1.6 },
	Royal = { Color = Color3.fromRGB(200, 90, 255), Second = Color3.fromRGB(255, 210, 60), Power = 2.4 },
}

local function eggAura(pedestal: BasePart, eggKey: string)
	local aura = AURAS[eggKey]
	local display = pedestal.Parent and pedestal.Parent:WaitForChild(eggKey .. "Display", 10)
	if not aura or not (display and display:IsA("Model")) or display:GetAttribute("HasAura") then
		return
	end
	display:SetAttribute("HasAura", true)
	local home = display:GetPivot()
	local power = aura.Power

	local core = Instance.new("Part")
	core.Name = "EggAura"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Transparency = 1
	core.Size = Vector3.new(2.2, 3, 2.2)
	core.CFrame = CFrame.new(home.Position)
	core.Parent = workspace.CurrentCamera

	local flame = Instance.new("ParticleEmitter")
	flame.Name = "Flame"
	flame.Texture = "rbxasset://textures/particles/fire_main.dds"
	flame.Color = ColorSequence.new(aura.Color, aura.Second)
	flame.LightEmission = 1
	flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4 + power * 0.5), NumberSequenceKeypoint.new(1, 0.6) })
	flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.72 - power * 0.06), NumberSequenceKeypoint.new(1, 1) })
	flame.Lifetime = NumberRange.new(0.9, 1.4)
	flame.Speed = NumberRange.new(2.2, 3.4 + power)
	flame.Rate = 7 * power
	flame.Rotation = NumberRange.new(-20, 20)
	flame.EmissionDirection = Enum.NormalId.Top
	flame.LockedToPart = true
	flame.Parent = core

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(aura.Second, aura.Color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35 + power * 0.1), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(1.2, 2.2)
	sparkles.Speed = NumberRange.new(0.6, 1.8)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 5 * power
	sparkles.RotSpeed = NumberRange.new(-90, 90)
	sparkles.Shape = Enum.ParticleEmitterShape.Sphere
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparkles.Parent = core

	local light = Instance.new("PointLight")
	light.Color = aura.Color
	light.Range = 9 + power * 3
	light.Brightness = 0.8 * power
	light.Shadows = false
	light.Parent = core

	-- A ring of light lying on the pedestal under the egg.
	local ring = Instance.new("Part")
	ring.Name = "EggAuraRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = aura.Color
	ring.Size = Vector3.new(0.12, 3.1, 3.1)
	ring.CFrame = CFrame.new(pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace.CurrentCamera

	local seed = pedestal.Position.Z
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not display.Parent or not pedestal.Parent then
			conn:Disconnect()
			core:Destroy()
			ring:Destroy()
			return
		end
		local t = os.clock() + seed
		display:PivotTo(home * CFrame.new(0, 0.25 + math.sin(t * 1.6) * 0.18, 0) * CFrame.Angles(0, t * 0.7, math.sin(t * 1.1) * 0.05))
		ring.Transparency = 0.35 + math.sin(t * 2.4) * 0.2
		local wide = 3.1 + math.sin(t * 2.4) * 0.25
		ring.Size = Vector3.new(0.12, wide, wide)
	end)
end

function PetShopController.Init()
	menu = UI.Menu("Pets", "PETS", UDim2.fromOffset(860, 560), UI.Colors.Pink)
	local tabs = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(1, -240, 0, 44) }, menu.Content)
	UI.ListLayout(tabs, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
	for i, name in ipairs(TABS) do
		local b = UI.Button({ Name = "Tab_" .. name, Text = TAB_NAMES[name], Color = UI.Colors.PanelLight, Size = UDim2.fromOffset(150, 42), TextSize = 17, LayoutOrder = i }, tabs)
		tabButtons[name] = b
		b.Activated:Connect(function()
			current = name
			render()
		end)
		pages[name] = UI.Frame({ Name = "Page_" .. name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), Visible = false }, menu.Content)
	end
	walletLabel = UI.Label({ Text = "", TextSize = 18, TextWrapped = false, Size = UDim2.fromOffset(230, 42), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, menu.Content)
	UI.TextGradient(walletLabel, UI.Colors.Cash)
	menu.Primary = function()
		return current == "Eggs" and firstHatch or tabButtons[current]
	end
	menu.OnOpen(render)

	for _, name in ipairs({ "PetData", "PetSlots", "Wallet" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			task.defer(render)
		end)
	end
	Remotes.Event("PurchaseUpdate").OnClientEvent:Connect(function(kind)
		if kind == "PassGranted" then
			task.defer(render)
		end
	end)

	-- Egg pedestals and pet shop stands in the lobby open the shop.
	local function attach(part: Instance, eggKey: string?)
		if not part:IsA("BasePart") or part:FindFirstChild("PetShopPrompt") then
			return
		end
		if eggKey then
			task.spawn(eggAura, part, eggKey)
		end
		local egg = eggKey and PetConfig.Eggs[eggKey]
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PetShopPrompt"
		prompt.ActionText = egg and "Hatch" or "Pet Shop"
		prompt.ObjectText = egg and string.format("%s  ·  $%s", egg.Name, FormatUtil.Comma(egg.Price)) or "Eggs & pets"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Triggered:Connect(function()
			PetShopController.Open("Eggs")
		end)
		prompt.Parent = part
	end
	for _, part in ipairs(CollectionService:GetTagged("EggPedestal")) do
		attach(part, part:GetAttribute("Egg"))
	end
	CollectionService:GetInstanceAddedSignal("EggPedestal"):Connect(function(part)
		attach(part, part:GetAttribute("Egg"))
	end)
	for _, part in ipairs(CollectionService:GetTagged("PetShop")) do
		attach(part, nil)
	end
	CollectionService:GetInstanceAddedSignal("PetShop"):Connect(function(part)
		attach(part, nil)
	end)
end

function PetShopController.Open(tab: string?)
	-- The welcome pet comes first.
	if Controllers.PetController.OfferWelcome() then
		return
	end
	if tab and pages[tab] then
		current = tab
	end
	menu.Open()
end

return PetShopController
