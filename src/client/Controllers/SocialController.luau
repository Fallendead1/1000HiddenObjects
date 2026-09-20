--[[
	The lobby's two reward stations (parts tagged SocialStation, attribute Kind; SocialConfig):

	  Reward  a big green thumbs-up floats over its pedestal under "CLAIM REWARD". Walk onto the
	          pedestal and the FREE REWARD card opens: "Like the game for a FREE PET!", the pet,
	          and a CHECK button. CHECK shows Roblox's join-the-group and favourite prompts and
	          turns into a countdown; after it, CHECK again claims (SocialService checks the
	          group for real). Once claimed the button reads CLAIMED for good.
	  Event   a bell under "JOIN EVENT" with a Join Event prompt: Roblox's own event card
	          (SocialConfig.EventId).

	The floating icons turn to face you when you come close, and spin slowly otherwise.
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local CollectionService = game:GetService("CollectionService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage.Shared
local PetConfig = require(Shared.Config.PetConfig)
local SocialConfig = require(Shared.Config.SocialConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local PetModels = require(script.Parent.Parent.UI.PetModels)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local SocialController = {}

type Station = { Base: BasePart, Kind: string, Icon: Model?, Yaw: number, Armed: boolean, Title: TextLabel? }
local stations: { Station } = {}

local menu
local checkButton: TextButton
local hintLabel: TextLabel
local countdownUntil = 0
local waitingForServer = false

local STYLE = {
	Reward = { Icon = "ThumbsUp", Title = "CLAIM REWARD", Sub = "FREE PET!", Color = Color3.fromRGB(255, 214, 60), Glow = Color3.fromRGB(70, 230, 90) },
	Event = { Icon = "Bell", Title = "JOIN EVENT", Sub = "GET NOTIFIED", Color = Color3.fromRGB(80, 220, 255), Glow = Color3.fromRGB(60, 200, 255) },
}

local function claimed(): boolean
	return player:GetAttribute("SocialRewardClaimed") == true
end

-- ===== The FREE REWARD card =====

local function refreshButton()
	if claimed() then
		checkButton.Text = "CLAIMED"
		UI.SetButtonEnabled(checkButton, false, "CLAIMED")
		hintLabel.Visible = false
		return
	end
	local left = math.ceil(countdownUntil - os.clock())
	if left > 0 then
		UI.SetButtonEnabled(checkButton, false, string.format("(%d)", left))
		hintLabel.Visible = true
	else
		UI.SetButtonEnabled(checkButton, not waitingForServer)
		checkButton.Text = "CHECK"
		hintLabel.Visible = false
	end
end

-- Roblox's own prompts, one after the other: join the group, then favourite the game. (The
-- like can only be given on the game's page; the hint line says so.)
local function showPrompts()
	task.spawn(function()
		local inGroup = false
		pcall(function()
			inGroup = player:IsInGroup(SocialConfig.GroupId)
		end)
		if not inGroup then
			pcall(function()
				GroupService:PromptJoinAsync(SocialConfig.GroupId)
			end)
		end
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	end)
end

local function startCountdown(seconds: number)
	countdownUntil = os.clock() + seconds
	refreshButton()
	task.spawn(function()
		while os.clock() < countdownUntil and menu.Frame.Visible do
			refreshButton()
			task.wait(0.2)
		end
		refreshButton()
	end)
end

local function onCheck()
	if claimed() or waitingForServer or os.clock() < countdownUntil then
		return
	end
	waitingForServer = true
	refreshButton()
	Remotes.Event("SocialCheck"):FireServer()
	task.delay(6, function()
		if waitingForServer then
			waitingForServer = false
			refreshButton()
		end
	end)
end

local function onResult(state: string, seconds: number?)
	waitingForServer = false
	if state == "Wait" then
		if os.clock() >= countdownUntil then
			showPrompts()
		end
		startCountdown(tonumber(seconds) or SocialConfig.CheckSeconds)
	elseif state == "NeedGroup" then
		Controllers.NotificationController.Show("Warning", "Join our group first, then press CHECK again!", 4)
		showPrompts()
		startCountdown(tonumber(seconds) or SocialConfig.CheckSeconds)
	elseif state == "Claimed" then
		countdownUntil = 0
		player:SetAttribute("SocialRewardClaimed", true)
		refreshButton()
		-- Out of the way of the gift opening.
		task.delay(0.6, function()
			if menu.Frame.Visible then
				menu.Close()
			end
		end)
	end
end

local function buildMenu()
	menu = UI.Menu("Social", "FREE REWARD", UDim2.fromOffset(560, 440), UI.Colors.Cyan)
	local content = menu.Content
	local def = PetConfig.Get(SocialConfig.RewardPet)
	local title = UI.Label({ Text = "Like the game for a FREE PET!", TextSize = 28, TextWrapped = false, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 4) }, content)
	UI.TextGradient(title, UI.Colors.Gold)
	UI.Label({ Text = "Join the Group   +   ★ the Game   +   👍 the Game", TextSize = 17, TextWrapped = false, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 42) }, content)

	-- What you get: the pet itself, turning slowly.
	local box = UI.Panel({ Size = UDim2.fromOffset(190, 190), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), BackgroundColor3 = Color3.fromRGB(14, 16, 26) }, content)
	UI.Stroke(box, UI.Colors.Cyan, 2.5)
	PetModels.Viewport(box, PetModels.Build(SocialConfig.RewardPet), { Size = UDim2.new(1, -10, 1, -36), Position = UDim2.fromOffset(5, 2) }, true)
	local name = UI.Label({ Text = def and string.upper(def.Name) or "FREE PET", TextSize = 18, TextWrapped = false, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -30) }, box)
	UI.TextGradient(name, UI.Colors.Gold)

	checkButton = UI.Button({ Name = "Check", Text = "CHECK", Color = UI.Colors.Gold, Size = UDim2.fromOffset(220, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 284), TextSize = 26, Shine = 2.5 }, content)
	checkButton.Activated:Connect(onCheck)
	menu.Primary = checkButton

	-- Above the card while the countdown runs, like a caption.
	hintLabel = UI.Label({ Text = "Favorite and like the game, then press CHECK again after the countdown to claim.", TextSize = 18, TextWrapped = true, Size = UDim2.new(1, 120, 0, 48), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -8), Visible = false }, menu.Frame)
	UI.Stroke(hintLabel, Color3.new(0, 0, 0), 3, 0)
	UI.TextGradient(hintLabel, UI.Colors.Gold)

	menu.OnOpen(refreshButton)
	player:GetAttributeChangedSignal("SocialRewardClaimed"):Connect(refreshButton)
end

function SocialController.Open()
	if player:GetAttribute("InMatch") == true then
		return
	end
	menu.Open()
end

-- ===== The stations in the world =====

local function titleBoard(base: BasePart, style, height: number): TextLabel
	local bb = UI.Billboard(base, UDim2.fromScale(11, 3.2), Vector3.new(0, height, 0), 130)
	local title = UI.Label({ Text = style.Title, TextScaled = true, Size = UDim2.fromScale(1, 0.62), Position = UDim2.fromScale(0, 0.38) }, bb)
	local face = Font.fromEnum(UI.Font)
	face.Style = Enum.FontStyle.Italic
	title.FontFace = face
	UI.Stroke(title, Color3.new(0, 0, 0), 3, 0)
	UI.TextGradient(title, style.Color)
	local sub = UI.Label({ Text = style.Sub, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 0.32), Position = UDim2.fromScale(0, 0.04) }, bb)
	UI.Stroke(sub, Color3.new(0, 0, 0), 2.5, 0)
	return title
end

local function attach(base: Instance)
	if not base:IsA("BasePart") or not base:IsDescendantOf(workspace) then
		return
	end
	for _, s in ipairs(stations) do
		if s.Base == base then
			return
		end
	end
	local kind = base:GetAttribute("Kind") == "Event" and "Event" or "Reward"
	local style = STYLE[kind]
	local station: Station = { Base = base, Kind = kind, Yaw = 0, Armed = true }
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	local folder = assets and assets:FindFirstChild("Social")
	local source = folder and folder:FindFirstChild(style.Icon)
	if source and source:IsA("Model") then
		local icon = source:Clone()
		for _, p in ipairs(icon:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
			end
		end
		icon:ScaleTo(1.7)
		icon.Parent = workspace.CurrentCamera
		station.Icon = icon
	end
	-- A soft pad of colour on the top step (kept matte: the lobby blooms anything bright).
	local pad = Instance.new("Part")
	pad.Name = "SocialPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = style.Glow
	pad.Transparency = 0.45
	pad.Size = Vector3.new(0.08, 3.4, 3.4)
	pad.CFrame = CFrame.new(base.Position + Vector3.new(0, base.Size.Y / 2 + 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Parent = workspace.CurrentCamera

	station.Title = titleBoard(base, style, base.Size.Y / 2 + 7.2)

	if kind == "Event" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "JoinEventPrompt"
		prompt.ActionText = "Join Event"
		prompt.ObjectText = ""
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Triggered:Connect(function()
			if SocialConfig.EventId == "" then
				Controllers.NotificationController.Show("Info", "Our next event is coming soon - check back!", 3.5)
				return
			end
			pcall(function()
				SocialService:PromptRsvpToEventAsync(SocialConfig.EventId)
			end)
		end)
		prompt.Parent = base
	end
	table.insert(stations, station)
end

local function step(dt: number)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local clock = os.clock()
	for _, s in ipairs(stations) do
		local base = s.Base
		if not base.Parent then
			continue
		end
		local top = base.Position + Vector3.new(0, base.Size.Y / 2, 0)
		local away = root and Vector3.new(root.Position.X - top.X, 0, root.Position.Z - top.Z) or nil
		local distance = away and away.Magnitude or math.huge
		-- The icon: bobbing; facing you when you're near, turning slowly when you're not.
		if s.Icon then
			local want: number
			if away and distance < SocialConfig.LookDistance and distance > 0.5 then
				-- Models face -Z: looking along `away` points the front at the player.
				want = math.atan2(-away.X, -away.Z)
				local diff = (want - s.Yaw + math.pi) % (2 * math.pi) - math.pi
				s.Yaw += diff * (1 - math.exp(-dt * 6))
			else
				s.Yaw += dt * 0.9
			end
			local bob = math.sin(clock * 2 + top.X) * 0.35
			local tilt = math.sin(clock * 1.3 + top.X) * 0.08
			s.Icon:PivotTo(CFrame.new(top + Vector3.new(0, 3.6 + bob, 0)) * CFrame.Angles(0, s.Yaw, 0) * CFrame.Angles(tilt, 0, 0))
		end
		if s.Kind == "Reward" then
			if s.Title then
				s.Title.Text = claimed() and "CLAIMED!" or STYLE.Reward.Title
			end
			-- Stepping onto the pedestal opens the card (once per visit).
			local close = distance <= SocialConfig.OpenDistance and root ~= nil and math.abs(root.Position.Y - top.Y) < 8
			if close and s.Armed and not UI.GetOpenMenu() and not Controllers.PetController.IsHatching() and player:GetAttribute("InMatch") ~= true then
				s.Armed = false
				SocialController.Open()
			elseif distance > SocialConfig.OpenDistance + 4 then
				s.Armed = true
			end
		end
	end
end

function SocialController.Init()
	buildMenu()
	Remotes.Event("SocialResult").OnClientEvent:Connect(onResult)
end

function SocialController.Start()
	for _, base in ipairs(CollectionService:GetTagged("SocialStation")) do
		attach(base)
	end
	CollectionService:GetInstanceAddedSignal("SocialStation"):Connect(attach)
	RunService.RenderStepped:Connect(step)
end

return SocialController
