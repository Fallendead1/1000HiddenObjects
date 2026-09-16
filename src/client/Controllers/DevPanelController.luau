--[[
	Studio-only developer Test Panel. Visible when running in Studio or when the server marks
	this player as a developer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Utility.Remotes)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)

local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local DevPanelController = {}

local function authorized(): boolean
	return RunService:IsStudio() or player:GetAttribute("Dev") == true
end

local function send(command: string, ...)
	Remotes.Event("DevCommand"):FireServer(command, ...)
end

function DevPanelController.Init()
	if not authorized() then
		player:GetAttributeChangedSignal("Dev"):Connect(function()
			if authorized() then
				DevPanelController.Init()
			end
		end)
		return
	end

	-- Bottom left, out of the way of the lobby's side cards.
	local toggle = UI.Button({ Text = "DEV", Color = UI.Colors.Orange, Size = UDim2.fromOffset(60, 32), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), TextSize = 16 }, UI.Layers.Top)
	local panel = UI.Panel({ Size = UDim2.fromOffset(240, 470), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 80, 1, -12), Visible = false, BackgroundTransparency = 0.05 }, UI.Layers.Top)
	local scroll = UI.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
	}, panel)
	UI.ListLayout(scroll, Enum.FillDirection.Vertical, 4)

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	local order = 0
	local function header(text: string)
		order += 1
		UI.Label({ Text = text, TextSize = 14, TextColor3 = UI.Colors.Orange, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order }, scroll)
	end
	local function button(text: string, color: Color3, fn: () -> ())
		order += 1
		local b = UI.Button({ Text = text, Color = color, Size = UDim2.new(1, -8, 0, 30), TextSize = 14, LayoutOrder = order }, scroll)
		b.Activated:Connect(fn)
	end

	header("MATCH")
	for _, n in ipairs({ 1, 2, 3, 4 }) do
		button(string.format("Start Room #001 (party %d)", n), UI.Colors.Green, function()
			send("StartRoom", n, 1)
		end)
	end
	for _, id in ipairs({ 2, 3, 4, 5 }) do
		button(string.format("Start Room #%03d (solo)", id), UI.Colors.Green, function()
			send("StartRoom", 1, id)
		end)
	end
	button("Start Room #001 (easy, solo)", UI.Colors.Green, function()
		send("StartRoom", 1, 1, true)
	end)
	button("Reset / End Room", UI.Colors.Red, function()
		send("ResetRoom")
	end)
	for _, id in ipairs({ 1, 2, 3, 4, 5 }) do
		button(string.format("Validate Room #%03d", id), UI.Colors.Cyan, function()
			send("ValidateRoom", id)
		end)
	end

	header("PROGRESS")
	button("+$10K", UI.Colors.Cash, function()
		send("AddCash", 10000)
	end)
	for _, p in ipairs({ 0.25, 0.5, 0.75, 0.9, 0.97 }) do
		button(string.format("Set %d%%", p * 100), UI.Colors.PanelLight, function()
			send("SetProgress", p)
		end)
	end
	button("Reveal Target", UI.Colors.Gold, function()
		send("RevealTarget")
	end)
	button("Target Info (console)", UI.Colors.PanelLight, function()
		send("TargetInfo")
	end)
	button("Complete Room", UI.Colors.Gold, function()
		send("CompleteRoom")
	end)
	button("Force Checkpoint 25%", UI.Colors.PanelLight, function()
		send("ForceCheckpoint", 0.25)
	end)

	header("MONETIZATION (mock)")
	for _, def in ipairs(MonetizationConfig.GamepassDefs) do
		button("Grant " .. def.Name, UI.Colors.Purple, function()
			send("MockPurchase", def.Key)
		end)
	end
	for _, def in ipairs(MonetizationConfig.ProductDefs) do
		button("Buy " .. def.Name, UI.Colors.Purple, function()
			send("MockPurchase", def.Key)
		end)
	end

	header("RETENTION")
	button("+$1K Wallet", UI.Colors.Cash, function()
		send("AddWallet", 1000)
	end)
	button("+5 min playtime", UI.Colors.Gold, function()
		send("AddPlaytime", 5)
	end)
	button("Miss a day (streak freeze)", UI.Colors.Orange, function()
		send("MissADay")
	end)
	button("Reset wallet / gifts / spin / firsts", UI.Colors.Red, function()
		send("ResetRetention")
	end)

	header("PETS")
	for _, egg in ipairs({ "Dusty", "Shiny", "Royal" }) do
		button("Hatch " .. egg .. " egg (free)", UI.Colors.Pink, function()
			send("GiveEgg", egg)
		end)
	end
	button("Give Golden Broom Dragon", UI.Colors.Gold, function()
		send("GivePet", "GoldenBroomDragon")
	end)
	button("Reset pets", UI.Colors.Red, function()
		send("ResetPets")
	end)

	header("DATA")
	button("Reset Save Data", UI.Colors.Red, function()
		send("ResetData")
	end)
end

return DevPanelController
