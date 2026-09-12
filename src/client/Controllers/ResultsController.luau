--[[
	Object Found ceremony (4-7 seconds) followed by the Results screen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)
local FormatUtil = require(Shared.Utility.FormatUtil)
local TargetData = require(Shared.Data.TargetData)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local ResultsController = {}

local ceremony: Frame
local ceremonyBig: TextLabel
local ceremonySmall: TextLabel
local ceremonyIcon: Frame
local ceremonyGlyph: TextLabel

local results: Frame
local resultsCard: Frame
local resTitle: TextLabel
local resObject: TextLabel
local resStats: TextLabel
local resContrib: Frame
local returnButton: TextButton
local nextButton: TextButton

local function setCeremony(big: string, small: string, color: Color3?, size: number?)
	ceremonyBig.Text = big
	ceremonyBig.TextColor3 = color or UI.Colors.Gold
	ceremonyBig.TextSize = size or 64
	ceremonySmall.Text = small
	local s = ceremonyBig:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, ceremonyBig)
	s.Scale = 0.6
	UI.Tween(s, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
end

local function runCeremony(payload)
	UI.CloseAllMenus()
	ceremony.Visible = true
	ceremony.BackgroundTransparency = 1
	UI.Tween(ceremony, { BackgroundTransparency = 0.35 }, 0.4)
	ceremonyIcon.Visible = false

	Controllers.AudioController.Play("TargetFound")
	Controllers.FXController.ScreenFlash(UI.Colors.Gold, 0.8)
	if payload.TargetPosition then
		Controllers.FXController.Confetti(payload.TargetPosition)
	end
	Controllers.FXController.CameraShake(0.4)

	setCeremony("OBJECT FOUND!", "", UI.Colors.Gold, 72)
	task.wait(1.4)

	local def = TargetData.GetById(payload.TargetId or "")
	ceremonyIcon.Visible = true
	ceremonyIcon.BackgroundColor3 = def and def.Color or UI.Colors.Gold
	ceremonyGlyph.Text = def and string.upper(string.sub(def.Name, 1, 1)) or "?"
	setCeremony(string.upper(payload.TargetName or ""), "Found by @" .. (payload.FinderName or "?"), UI.Colors.Gold, 60)
	Controllers.AudioController.Play("VictorySting")
	task.wait(2.2)

	local found = math.max(player:GetAttribute("ObjectsFound") or 0, payload.ObjectNumber or 1)
	ceremonyIcon.Visible = false
	setCeremony(string.format("%d / %d", found, GameConfig.TotalObjects), string.format("OBJECT %s COLLECTED", TargetData.FormatNumber(payload.ObjectNumber or 1)), UI.Colors.Green, 80)
	task.wait(2)

	UI.Tween(ceremony, { BackgroundTransparency = 1 }, 0.4)
	UI.Tween(ceremonyBig, { TextTransparency = 1 }, 0.4)
	UI.Tween(ceremonySmall, { TextTransparency = 1 }, 0.4)
	task.wait(0.4)
	ceremony.Visible = false
	ceremonyBig.TextTransparency = 0
	ceremonySmall.TextTransparency = 0
end

local function showResults(payload)
	results.Visible = true
	results.BackgroundTransparency = 1
	UI.Tween(results, { BackgroundTransparency = 0.45 }, 0.3)
	local s = resultsCard:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, resultsCard)
	s.Scale = 0.85
	UI.Tween(s, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)

	resTitle.Text = string.format("ROOM #%s COMPLETE", payload.RoomNumber or "001")
	resObject.Text = string.format("%s  -  %s  ✓", TargetData.FormatNumber(payload.ObjectNumber or 1), payload.TargetName or "")
	local mine = 0
	for _, c in ipairs(payload.Contributions or {}) do
		if c.UserId == player.UserId then
			mine = c.Mess
		end
	end
	resStats.Text = string.format("Time: %s\nFinder: %s\nTeam Size: %d\nYour Mess Cleared: %s",
		FormatUtil.Time(payload.Elapsed or 0), payload.FinderName or "?", payload.TeamSize or 1, FormatUtil.Comma(mine))

	for _, c in ipairs(resContrib:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, c in ipairs(payload.Contributions or {}) do
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, resContrib)
		UI.Corner(row, 6)
		UI.Label({ Text = c.Name, TextSize = 15, Font = UI.FontBody, TextColor3 = c.UserId == player.UserId and UI.Colors.Gold or UI.Colors.Text, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left }, row)
		UI.Label({ Text = FormatUtil.Compact(c.Mess), TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.4, -10, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
	end

	if payload.NextRoomAvailable then
		nextButton.Text = "NEXT ROOM"
		UI.SetButtonEnabled(nextButton, true)
	else
		local nextNum = (payload.ObjectNumber or 1) + 1
		nextButton.Text = string.format("ROOM %s - COMING SOON", FormatUtil.RoomNumber(nextNum))
		UI.SetButtonEnabled(nextButton, false)
	end
end

function ResultsController.Init()
	ceremony = UI.Frame({ Name = "Ceremony", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Visible = false }, UI.Layers.Top)
	ceremonyBig = UI.Label({ Text = "", TextSize = 64, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 110), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42) }, ceremony)
	UI.Stroke(ceremonyBig, Color3.new(0, 0, 0), 3, 0.3)
	ceremonySmall = UI.Label({ Text = "", TextSize = 26, Size = UDim2.new(1, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53) }, ceremony)
	UI.Stroke(ceremonySmall, Color3.new(0, 0, 0), 2, 0.3)
	ceremonyIcon = UI.Frame({ Size = UDim2.fromOffset(120, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), BackgroundColor3 = UI.Colors.Gold, Visible = false }, ceremony)
	UI.Corner(ceremonyIcon, 24)
	UI.Stroke(ceremonyIcon, Color3.new(1, 1, 1), 4)
	ceremonyGlyph = UI.Label({ Text = "K", TextSize = 70, TextColor3 = UI.Colors.PanelDark }, ceremonyIcon)

	results = UI.Frame({ Name = "Results", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false }, UI.Layers.Top)
	resultsCard = UI.Panel({ Size = UDim2.fromOffset(520, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, results)
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(520, 520), MinSize = Vector2.new(300, 400) }, resultsCard)
	resTitle = UI.Label({ Text = "ROOM #001 COMPLETE", TextSize = 32, TextColor3 = UI.Colors.Green, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 14) }, resultsCard)
	local icon = UI.Frame({ Size = UDim2.fromOffset(84, 84), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), BackgroundColor3 = UI.Colors.Gold }, resultsCard)
	UI.Corner(icon, 18)
	UI.Label({ Text = "K", TextSize = 50, TextColor3 = UI.Colors.PanelDark }, icon)
	resObject = UI.Label({ Text = "#001 - Golden Key", TextSize = 24, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 152) }, resultsCard)
	resStats = UI.Label({ Text = "", TextSize = 18, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.5, -20, 0, 120), Position = UDim2.fromOffset(20, 194), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, resultsCard)
	resContrib = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(0.5, -20, 0, 120), Position = UDim2.new(0.5, 0, 0, 194) }, resultsCard)
	UI.ListLayout(resContrib, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center)

	returnButton = UI.Button({ Text = "RETURN TO LOBBY", Color = UI.Colors.Green, Size = UDim2.new(1, -40, 0, 54), Position = UDim2.new(0, 20, 1, -132), TextSize = 22 }, resultsCard)
	nextButton = UI.Button({ Text = "ROOM #002 - COMING SOON", Color = UI.Colors.Gold, Size = UDim2.new(1, -40, 0, 54), Position = UDim2.new(0, 20, 1, -68), TextSize = 20 }, resultsCard)
	UI.SetButtonEnabled(nextButton, false)

	returnButton.Activated:Connect(function()
		results.Visible = false
		Remotes.Event("ReturnToLobby"):FireServer()
	end)
	nextButton.Activated:Connect(function()
		if nextButton.Active then
			results.Visible = false
			Remotes.Event("ReturnToLobby"):FireServer()
		end
	end)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName, payload)
		if eventName == "TargetFound" then
			task.spawn(runCeremony, payload or {})
		elseif eventName == "Results" then
			showResults(payload or {})
		elseif eventName == "ReturnedToLobby" then
			results.Visible = false
			ceremony.Visible = false
		end
	end)
end

return ResultsController
