--[[
	Contextual first-match tutorial. Five short steps; never repeats once completed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local TutorialController = {}

local card: Frame
local stepLabel: TextLabel
local textLabel: TextLabel
local step = 0
local active = false
local highlightStroke: UIStroke? = nil

local Steps = {
	[1] = "Hold SEARCH on a pile of mess.",
	[2] = "Your bag stores the mess you clear.",
	[3] = "Dump your bag at the Trash Chute to earn Cash.",
	[4] = "Spend Cash in UPGRADES to search faster.",
	[5] = "Now find the hidden object!",
}

local function clearHighlight()
	if highlightStroke then
		highlightStroke:Destroy()
		highlightStroke = nil
	end
end

local function highlightButton(button: GuiObject)
	clearHighlight()
	highlightStroke = UI.Stroke(button, UI.Colors.Gold, 4)
	task.spawn(function()
		while highlightStroke and highlightStroke.Parent do
			UI.Tween(highlightStroke, { Transparency = 0.8 }, 0.5)
			task.wait(0.5)
			if highlightStroke then
				UI.Tween(highlightStroke, { Transparency = 0 }, 0.5)
			end
			task.wait(0.5)
		end
	end)
end

local function showStep(n: number)
	step = n
	local text = Steps[n]
	if not text then
		return
	end
	card.Visible = true
	stepLabel.Text = string.format("TUTORIAL %d / %d", n, #Steps)
	textLabel.Text = text
	local s = card:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, card)
	s.Scale = 0.85
	UI.Tween(s, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	clearHighlight()
	if n == 4 then
		highlightButton(Controllers.HUDController.Buttons.Upgrades)
	end
end

local function finish()
	if not active then
		return
	end
	active = false
	clearHighlight()
	card.Visible = false
	Remotes.Event("TutorialComplete"):FireServer()
end

function TutorialController.Init()
	card = UI.Panel({ Size = UDim2.fromOffset(380, 84), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -20), Visible = false, BackgroundTransparency = 0.05 }, UI.Layers.Overlay)
	UI.Stroke(card, UI.Colors.Gold, 2)
	stepLabel = UI.Label({ Text = "TUTORIAL", TextSize = 14, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Left }, card)
	textLabel = UI.Label({ Text = "", TextSize = 18, Font = UI.FontBody, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 28), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, card)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName)
		if eventName == "Started" then
			if player:GetAttribute("TutorialCompleted") ~= true then
				active = true
				showStep(1)
			end
		elseif eventName == "ReturnedToLobby" or eventName == "TargetFound" then
			active = false
			clearHighlight()
			card.Visible = false
		end
	end)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name)
		if not active then
			return
		end
		if name == "SearchTick" and step == 1 then
			showStep(2)
		elseif name == "BagFull" and step <= 2 then
			showStep(3)
		elseif name == "Sell" and step <= 3 then
			showStep(4)
		elseif name == "Upgrade" and step == 4 then
			showStep(5)
			task.delay(6, finish)
		end
	end)

	-- Auto Sell owners never see BagFull; move on when their bag empties after filling.
	player:GetAttributeChangedSignal("BagCurrent"):Connect(function()
		if active and step == 2 and (player:GetAttribute("BagCurrent") or 0) >= (player:GetAttribute("BagCapacity") or 40) then
			showStep(3)
		end
	end)

	UI.OnMenuChanged(function(name, action)
		if active and step == 4 and name == "Upgrades" and action == "open" then
			clearHighlight()
		end
	end)
end

return TutorialController
