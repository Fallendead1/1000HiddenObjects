--[[
	First-room tutorial for the physical grab/throw loop. Six short contextual steps; never
	repeats once completed.
	  1 aim + grab   2 keep holding and aim   3 release to throw
	  4 move new objects for Cash   5 buy upgrades   6 find the Golden Key
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local TutorialController = {}

local card: Frame
local stepLabel: TextLabel
local textLabel: TextLabel
local step = 0
local active = false
local highlight: Instance? = nil
local TOTAL = 6

local function platformText(pc: string, touch: string, pad: string): string
	if UI.IsTouch() then
		return touch
	elseif UI.IsGamepad() then
		return pad
	end
	return pc
end

local function stepText(n: number): string
	if n == 1 then
		return platformText("Aim at an object and HOLD LEFT MOUSE TO GRAB it.", "Aim at an object and tap GRAB.", "Aim at an object and HOLD R2 to grab it.")
	elseif n == 2 then
		return platformText("KEEP HOLDING and aim. The dotted arc shows where it lands.", "Turn the camera to aim. The dotted arc shows where it lands.", "KEEP HOLDING R2 and aim. The arc shows where it lands.")
	elseif n == 3 then
		return platformText("RELEASE LEFT MOUSE TO THROW!", "Tap THROW!", "RELEASE R2 TO THROW!")
	elseif n == 4 then
		return "Throw or carry junk into a glowing BIN to clean it and earn Cash. The right bin pays DOUBLE!"
	elseif n == 5 then
		return "Buy UPGRADES to lift heavier objects."
	end
	return "Dig down through the junk and find the Golden Key!"
end

local function clearHighlight()
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
end

local function showStep(n: number)
	if not active or n <= step then
		return
	end
	step = n
	card.Visible = true
	stepLabel.Text = string.format("TUTORIAL %d / %d", n, TOTAL)
	textLabel.Text = stepText(n)
	local s = card:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, card)
	s.Scale = 0.85
	UI.Tween(s, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	clearHighlight()
	if n == 5 then
		-- A separate glow (not the button's own border, which must survive the highlight).
		highlight = UI.Glow(Controllers.HUDController.Buttons.Upgrades, UI.Colors.Gold, 18, 0.1)
		task.delay(12, function()
			showStep(6)
		end)
	elseif n == 6 then
		task.delay(6, TutorialController.Finish)
	end
end

function TutorialController.Finish()
	if not active then
		return
	end
	active = false
	clearHighlight()
	card.Visible = false
	Remotes.Event("TutorialComplete"):FireServer()
end

function TutorialController.Init()
	card = UI.Panel({ Size = UDim2.fromOffset(420, 92), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -20), Visible = false, BackgroundTransparency = 0.05 }, UI.Layers.Overlay)
	UI.Stroke(card, UI.Colors.Gold, 2.5)
	-- A studded gold tab sticking out of the card's top edge.
	local tab = UI.Surface3D({ Size = UDim2.fromOffset(156, 28), Position = UDim2.fromOffset(12, -14) }, card, UI.Colors.Gold, 12, 0.14)
	stepLabel = UI.Label({ Text = "TUTORIAL", TextSize = 13, TextWrapped = false, Size = UDim2.new(1, -8, 0.86, 0), Position = UDim2.fromOffset(4, 0) }, tab)
	textLabel = UI.Label({ Text = "", TextSize = 17, Font = UI.FontBody, Size = UDim2.new(1, -24, 0, 62), Position = UDim2.fromOffset(12, 22), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, card)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName)
		if eventName == "Started" and player:GetAttribute("TutorialCompleted") ~= true then
			active = true
			step = 0
			showStep(1)
		elseif eventName == "ReturnedToLobby" or eventName == "TargetFound" then
			active = false
			clearHighlight()
			card.Visible = false
		end
	end)

	player:GetAttributeChangedSignal("HeldObjectId"):Connect(function()
		local holding = (player:GetAttribute("HeldObjectId") or "") ~= ""
		if holding and step <= 1 then
			showStep(2)
			task.delay(1.2, function()
				if (player:GetAttribute("HeldObjectId") or "") ~= "" then
					showStep(3)
				end
			end)
		elseif not holding and step >= 2 and step <= 3 then
			showStep(4)
		end
	end)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if name == "Deposit" and payload and payload.Mine and step == 4 then
			task.delay(1, function()
				showStep(5)
			end)
		elseif name == "Upgrade" and step == 5 then
			showStep(6)
		end
	end)

	UI.OnMenuChanged(function(name, action)
		if active and step == 5 and name == "Upgrades" and action == "open" then
			clearHighlight()
		end
	end)
end

return TutorialController
