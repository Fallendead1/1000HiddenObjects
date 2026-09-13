--[[
	Object Found ceremony (~6 seconds) followed by the Results screen.
	Ceremony: gold flash + vignette, the key rises and spins, three confetti waves,
	OBJECT FOUND! -> GOLDEN KEY / Found by -> 1 / 1000.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
local resBest: TextLabel
local resContrib: Frame
local returnButton: TextButton
local nextButton: TextButton

local function setCeremony(big: string, small: string, color: Color3?, size: number?)
	ceremonyBig.Text = big
	ceremonyBig.TextColor3 = color or UI.Colors.Gold
	ceremonyBig.TextSize = size or 64
	ceremonySmall.Text = small
	local s = ceremonyBig:FindFirstChildOfClass("UIScale") or UI.New("UIScale", {}, ceremonyBig)
	s.Scale = 0.5
	UI.Tween(s, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
end

local function raiseKey(position: Vector3?)
	local model = CollectionService:GetTagged("HiddenTarget")[1]
	if not model or not model:IsA("Model") then
		return
	end
	local start = model:GetPivot()
	local goal = start + Vector3.new(0, 3.5, 0)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < 2.2 and model.Parent do
			local a = math.min(1, (os.clock() - t0) / 2.2)
			local eased = 1 - (1 - a) ^ 3
			model:PivotTo(start:Lerp(goal, eased) * CFrame.Angles(0, (os.clock() - t0) * 3, 0))
			task.wait()
		end
	end)
	local primary = model.PrimaryPart
	if primary then
		local light = primary:FindFirstChildOfClass("PointLight")
		if light then
			TweenService:Create(light, TweenInfo.new(1.5), { Brightness = 4, Range = 30 }):Play()
		end
	end
end

local function runCeremony(payload)
	UI.CloseAllMenus()
	ceremony.Visible = true
	ceremony.BackgroundTransparency = 1
	UI.Tween(ceremony, { BackgroundTransparency = 0.4 }, 0.4)
	ceremonyIcon.Visible = false

	Controllers.AudioController.Play("TargetFound")
	Controllers.FXController.ScreenFlash(UI.Colors.Gold, 0.9)
	Controllers.FXController.SetVignette(UI.Colors.Gold, 0.45, 0.3)
	Controllers.FXController.FovPunch(8)
	Controllers.FXController.CameraShake(0.5)
	raiseKey(payload.TargetPosition)
	if payload.TargetPosition then
		for i = 0, 2 do
			task.delay(i * 0.7, function()
				Controllers.FXController.Confetti(payload.TargetPosition + Vector3.new(0, 1 + i, 0))
			end)
		end
	end

	setCeremony("OBJECT FOUND!", "", UI.Colors.Gold, 74)
	task.wait(1.5)

	local def = TargetData.GetById(payload.TargetId or "")
	ceremonyIcon.Visible = true
	ceremonyIcon.BackgroundColor3 = def and def.Color or UI.Colors.Gold
	ceremonyGlyph.Text = def and string.upper(string.sub(def.Name, 1, 1)) or "?"
	setCeremony(string.upper(payload.TargetName or ""), "Found by @" .. (payload.FinderName or "?"), UI.Colors.Gold, 62)
	Controllers.AudioController.Play("VictorySting")
	task.wait(2.2)

	local found = math.max(player:GetAttribute("ObjectsFound") or 0, payload.ObjectNumber or 1)
	ceremonyIcon.Visible = false
	setCeremony(string.format("%d / %d", found, GameConfig.TotalObjects), string.format("OBJECT %s COLLECTED", TargetData.FormatNumber(payload.ObjectNumber or 1)), UI.Colors.Green, 84)
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
			mine = c.Objects or 0
		end
	end
	resStats.Text = string.format("Time: %s\nFinder: %s\nTeam Size: %d\nYou Cleaned: %s objects\nRoom Cleaned: %s",
		FormatUtil.Time(payload.Elapsed or 0), payload.FinderName or "?", payload.TeamSize or 1, FormatUtil.Comma(mine), FormatUtil.Percent(payload.RoomSearched or 0))
	local best = player:GetAttribute("BestTimeRoom1") or 0
	if best > 0 then
		resBest.Text = "Best time: " .. FormatUtil.Time(best) .. ((payload.Elapsed or 0) <= best + 1 and "  (NEW BEST!)" or "")
	else
		resBest.Text = ""
	end

	for _, c in ipairs(resContrib:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, c in ipairs(payload.Contributions or {}) do
		local row = UI.Frame({ Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = UI.Colors.PanelLight, LayoutOrder = i }, resContrib)
		UI.Corner(row, 6)
		UI.Label({ Text = c.Name, TextSize = 15, Font = UI.FontBody, TextColor3 = c.UserId == player.UserId and UI.Colors.Gold or UI.Colors.Text, Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left }, row)
		UI.Label({ Text = tostring(c.Objects or 0) .. " cleaned", TextSize = 15, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.4, -10, 1, 0), Position = UDim2.new(0.6, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }, row)
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
	UI.Stroke(ceremonyBig, Color3.new(0, 0, 0), 3, 0.2)
	ceremonySmall = UI.Label({ Text = "", TextSize = 26, Size = UDim2.new(1, 0, 0, 40), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53) }, ceremony)
	UI.Stroke(ceremonySmall, Color3.new(0, 0, 0), 2, 0.2)
	ceremonyIcon = UI.Frame({ Size = UDim2.fromOffset(120, 120), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), BackgroundColor3 = UI.Colors.Gold, Visible = false }, ceremony)
	UI.Corner(ceremonyIcon, 24)
	UI.Stroke(ceremonyIcon, Color3.new(1, 1, 1), 4)
	ceremonyGlyph = UI.Label({ Text = "K", TextSize = 70, TextColor3 = UI.Colors.PanelDark }, ceremonyIcon)

	results = UI.Frame({ Name = "Results", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Visible = false }, UI.Layers.Top)
	resultsCard = UI.Panel({ Size = UDim2.fromOffset(520, 540), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) }, results)
	UI.Stroke(resultsCard, UI.Colors.Gold, 3)
	UI.New("UISizeConstraint", { MaxSize = Vector2.new(520, 540), MinSize = Vector2.new(300, 420) }, resultsCard)
	resTitle = UI.Label({ Text = "ROOM #001 COMPLETE", TextSize = 32, TextColor3 = UI.Colors.Green, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 14) }, resultsCard)
	local icon = UI.Frame({ Size = UDim2.fromOffset(84, 84), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), BackgroundColor3 = UI.Colors.Gold }, resultsCard)
	UI.Corner(icon, 18)
	UI.Stroke(icon, Color3.new(1, 1, 1), 3)
	UI.Icon(icon, "Icon_Key", "K", { TextSize = 50, TextColor3 = UI.Colors.PanelDark })
	resObject = UI.Label({ Text = "#001 - Golden Key", TextSize = 24, TextColor3 = UI.Colors.Gold, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 152) }, resultsCard)
	resStats = UI.Label({ Text = "", TextSize = 18, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(0.5, -20, 0, 110), Position = UDim2.fromOffset(20, 192), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, resultsCard)
	resBest = UI.Label({ Text = "", TextSize = 16, Font = UI.FontBody, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(0.5, -20, 0, 22), Position = UDim2.fromOffset(20, 300), TextXAlignment = Enum.TextXAlignment.Left }, resultsCard)
	resContrib = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.new(0.5, -20, 0, 130), Position = UDim2.new(0.5, 0, 0, 192) }, resultsCard)
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
			Controllers.FXController.SetVignette(nil, 1, 0.3)
		end
	end)
end

return ResultsController
