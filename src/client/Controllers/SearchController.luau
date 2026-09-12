--[[
	One shared SearchAction with multiple inputs: hold LMB / E / gamepad R2, or the large
	mobile SEARCH button. Picks the clutter cluster under the aim, highlights it, and tells the
	server which cluster is being searched. The server decides everything else.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local player = Players.LocalPlayer
local matchState = ReplicatedStorage:WaitForChild("MatchState")

local SearchController = {}

local holding = false
local holdSources: { [string]: boolean } = {}
local currentClusterId: string? = nil
local sentClusterId: string? = nil
local highlight: Highlight? = nil
local highlightedModel: Model? = nil
local trashBombMode = false
local lastEvalTime = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function inSearchingState(): boolean
	return player:GetAttribute("InMatch") == true and matchState:GetAttribute("State") == "Searching"
end

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function distanceToVolume(from: Vector3, volume: BasePart): number
	local localPos = volume.CFrame:PointToObjectSpace(from)
	local half = volume.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPos.X, -half.X, half.X),
		math.clamp(localPos.Y, -half.Y, half.Y),
		math.clamp(localPos.Z, -half.Z, half.Z)
	)
	return (localPos - clamped).Magnitude
end

local function getReach(): number
	return (player:GetAttribute("SearchReach") or GameConfig.SearchDistance)
end

-- Returns the aimed cluster model + id, or nil.
local function findAimedCluster(): (Model?, string?)
	local camera = workspace.CurrentCamera
	local root = getRoot()
	if not camera or not root then
		return nil, nil
	end
	local volumes = Controllers.ClutterVisualController.GetVolumes()
	if #volumes == 0 then
		return nil, nil
	end
	rayParams.FilterDescendantsInstances = volumes
	local reach = getReach()

	local ray
	if UI.IsTouch() or UI.IsGamepad() then
		local vp = camera.ViewportSize
		ray = camera:ViewportPointToRay(vp.X / 2, vp.Y / 2)
	else
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	end

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
	if result and result.Instance then
		local model, id = Controllers.ClutterVisualController.GetClusterByVolume(result.Instance)
		if model and id and distanceToVolume(root.Position, result.Instance) <= reach then
			return model, id
		end
	end

	-- Fallback: nearest pile in front of the character within reach (helps mobile/gamepad).
	local best, bestDist = nil, math.huge
	local forward = root.CFrame.LookVector
	for _, volume in ipairs(volumes) do
		local d = distanceToVolume(root.Position, volume)
		if d <= reach then
			local toVol = (volume.Position - root.Position)
			local flat = Vector3.new(toVol.X, 0, toVol.Z)
			if flat.Magnitude < 1 or flat.Unit:Dot(forward) > 0.2 then
				if d < bestDist then
					best, bestDist = volume, d
				end
			end
		end
	end
	if best then
		return Controllers.ClutterVisualController.GetClusterByVolume(best)
	end
	return nil, nil
end

local function setHighlight(model: Model?, color: Color3?)
	if highlightedModel == model and highlight then
		if color then
			highlight.OutlineColor = color
		end
		return
	end
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	highlightedModel = model
	if model then
		highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.9
		highlight.OutlineTransparency = 0.15
		highlight.OutlineColor = color or Color3.fromRGB(255, 255, 255)
		highlight.FillColor = color or Color3.fromRGB(255, 255, 255)
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
	end
end

local function sendStart(id: string)
	if sentClusterId ~= id then
		sentClusterId = id
		Remotes.Event("SearchStart"):FireServer(id)
	end
end

local function sendStop()
	if sentClusterId then
		sentClusterId = nil
		Remotes.Event("SearchStop"):FireServer()
	end
end

local function updateHolding()
	local any = false
	for _, v in pairs(holdSources) do
		if v then
			any = true
			break
		end
	end
	holding = any
	if not holding then
		sendStop()
	end
end

local function onSearchAction(_, state: Enum.UserInputState)
	if trashBombMode then
		if state == Enum.UserInputState.Begin then
			SearchController.ConfirmTrashBomb()
		end
		return Enum.ContextActionResult.Sink
	end
	if state == Enum.UserInputState.Begin then
		holdSources.Action = true
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		holdSources.Action = false
	end
	updateHolding()
	return Enum.ContextActionResult.Pass
end

local function bindInputs()
	ContextActionService:BindActionAtPriority("SearchAction", onSearchAction, false, 2000,
		Enum.UserInputType.MouseButton1, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
end

local function unbindInputs()
	ContextActionService:UnbindAction("SearchAction")
end

local function step()
	if not inSearchingState() then
		if sentClusterId then
			sendStop()
		end
		setHighlight(nil)
		currentClusterId = nil
		Controllers.HUDController.SetPrompt(nil)
		return
	end

	-- Don't search while a menu is open or the pointer is over UI (PC).
	local menuOpen = UI.GetOpenMenu() ~= nil
	local now = os.clock()
	if now - lastEvalTime < 0.08 then
		return
	end
	lastEvalTime = now

	local model, id = findAimedCluster()
	currentClusterId = id

	if trashBombMode then
		setHighlight(model, UI.Colors.Orange)
		Controllers.HUDController.SetPrompt(model and "TAP / CLICK TO BOMB THIS PILE" or "SELECT A PILE")
		return
	end

	if model then
		setHighlight(model, holding and UI.Colors.Green or Color3.fromRGB(255, 255, 255))
		if UI.IsTouch() then
			Controllers.HUDController.SetPrompt(holding and "SEARCHING..." or nil)
		else
			Controllers.HUDController.SetPrompt(holding and "SEARCHING..." or "HOLD TO SEARCH")
		end
	else
		setHighlight(nil)
		Controllers.HUDController.SetPrompt(nil)
	end
	Controllers.HUDController.SetSearchButtonActive(model ~= nil)

	if holding and not menuOpen then
		if id then
			sendStart(id)
		else
			sendStop()
		end
	elseif sentClusterId then
		sendStop()
	end
end

function SearchController.Init()
	local button = Controllers.HUDController.GetMobileSearchButton()
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if trashBombMode then
				SearchController.ConfirmTrashBomb()
				return
			end
			holdSources.Button = true
			updateHolding()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdSources.Button = false
			updateHolding()
		end
	end)

	local function refreshBinding()
		if player:GetAttribute("InMatch") then
			bindInputs()
		else
			unbindInputs()
			holdSources = {}
			updateHolding()
		end
	end
	player:GetAttributeChangedSignal("InMatch"):Connect(refreshBinding)
	refreshBinding()

	UI.OnMenuChanged(function(_, action)
		if action == "open" then
			holdSources = {}
			updateHolding()
		end
	end)

	Remotes.Event("FXEvent").OnClientEvent:Connect(function(name, payload)
		if name == "SearchStopped" then
			sentClusterId = nil
		end
	end)

	Remotes.Event("PurchaseUpdate").OnClientEvent:Connect(function(kind)
		if kind == "TrashBombReady" then
			Controllers.NotificationController.Show("Premium", "Trash Bomb ready! Press USE BOMB and select a pile.")
		end
	end)
end

function SearchController.Start()
	RunService.RenderStepped:Connect(step)
end

function SearchController.IsHolding(): boolean
	return holding
end

function SearchController.EnterTrashBombMode()
	if (player:GetAttribute("PendingTrashBombs") or 0) <= 0 then
		Controllers.NotificationController.Show("Warning", "You have no Trash Bombs.")
		return
	end
	trashBombMode = true
	holdSources = {}
	updateHolding()
	Controllers.NotificationController.Show("Info", "SELECT A PILE to bomb. Press ESC / CANCEL to stop.")
	Controllers.HUDController.SetTrashBombModeUI(true)
end

function SearchController.ExitTrashBombMode()
	trashBombMode = false
	Controllers.HUDController.SetTrashBombModeUI(false)
end

function SearchController.ConfirmTrashBomb()
	if not trashBombMode then
		return
	end
	if currentClusterId then
		Remotes.Event("RequestTrashBomb"):FireServer(currentClusterId)
		SearchController.ExitTrashBombMode()
	end
end

function SearchController.IsTrashBombMode(): boolean
	return trashBombMode
end

return SearchController
