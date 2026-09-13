--[[
	Clue banners, region highlights (75% milestone / Super Hint) and the 97% cluster outline.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local UI = require(script.Parent.Parent.UI.UI)
local Controllers = require(script.Parent)

local matchState = ReplicatedStorage:WaitForChild("MatchState")

local HintController = {}

local banner: Frame
local bannerLabel: TextLabel
local bannerToken = 0
local activeRegionParts: { BasePart } = {}
local outlineBoxes: { SelectionBox } = {}
local outlineThread: thread? = nil

function HintController.ShowClue(text: string, duration: number?)
	bannerToken += 1
	local token = bannerToken
	bannerLabel.Text = text
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, 110)
	UI.Tween(banner, { Position = UDim2.new(0.5, 0, 0, 140) }, 0.3, Enum.EasingStyle.Back)
	Controllers.AudioController.Play("Hint")
	task.delay(duration or 7, function()
		if bannerToken == token then
			UI.Tween(banner, { Position = UDim2.new(0.5, 0, 0, 110) }, 0.25).Completed:Once(function()
				if bannerToken == token then
					banner.Visible = false
				end
			end)
		end
	end)
end

function HintController.HighlightRegion(regionId: string, duration: number, super: boolean?)
	for _, p in ipairs(activeRegionParts) do
		p:Destroy()
	end
	activeRegionParts = {}
	for _, region in ipairs(CollectionService:GetTagged("SearchRegion")) do
		if region:IsA("BasePart") and region:GetAttribute("RegionId") == regionId then
			local ghost = Instance.new("Part")
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Size = region.Size
			ghost.CFrame = region.CFrame
			ghost.Material = Enum.Material.ForceField
			ghost.Color = super and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(80, 200, 255)
			ghost.Transparency = 0.55
			ghost.Parent = workspace.CurrentCamera
			table.insert(activeRegionParts, ghost)
			task.spawn(function()
				while ghost.Parent do
					UI.Tween(ghost, { Transparency = 0.75 }, 0.6)
					task.wait(0.6)
					if ghost.Parent then
						UI.Tween(ghost, { Transparency = 0.45 }, 0.6)
					end
					task.wait(0.6)
				end
			end)

			local bb = UI.Billboard(ghost, UDim2.fromOffset(240, 50), Vector3.new(0, region.Size.Y / 2 + 2, 0), 200)
			bb.AlwaysOnTop = true
			UI.Label({ Text = region:GetAttribute("RegionName") or regionId, TextSize = 26, TextColor3 = ghost.Color }, bb)
			bb.Parent = ghost
		end
	end
	task.delay(duration, function()
		for _, p in ipairs(activeRegionParts) do
			UI.Tween(p, { Transparency = 1 }, 0.5).Completed:Once(function()
				p:Destroy()
			end)
		end
		activeRegionParts = {}
	end)
end

-- Final anti-frustration stage: pulse a subtle box around each object still covering the key.
local function updateOutline()
	for _, box in ipairs(outlineBoxes) do
		box:Destroy()
	end
	outlineBoxes = {}
	if outlineThread then
		task.cancel(outlineThread)
		outlineThread = nil
	end
	local ids = matchState:GetAttribute("OutlinedObjects") or ""
	if ids == "" then
		return
	end
	local room = workspace:FindFirstChild("Room" .. (matchState:GetAttribute("RoomNumber") or ""))
	local folder = room and room:FindFirstChild("Clutter")
	if not folder then
		task.delay(1, updateOutline)
		return
	end
	for id in string.gmatch(ids, "[^,]+") do
		local root = folder:FindFirstChild(id)
		if root and root:IsA("BasePart") then
			local box = Instance.new("SelectionBox")
			box.Adornee = root
			box.Color3 = Color3.fromRGB(255, 200, 40)
			box.LineThickness = 0.04
			box.SurfaceTransparency = 1
			box.Transparency = 0.2
			box.Parent = workspace.CurrentCamera
			table.insert(outlineBoxes, box)
		end
	end
	local boxes = outlineBoxes
	outlineThread = task.spawn(function()
		while true do
			for _, b in ipairs(boxes) do
				UI.Tween(b, { Transparency = 0.85 }, 0.7)
			end
			task.wait(0.7)
			for _, b in ipairs(boxes) do
				UI.Tween(b, { Transparency = 0.15 }, 0.7)
			end
			task.wait(0.7)
		end
	end)
end

function HintController.Init()
	banner = UI.Panel({ Size = UDim2.fromOffset(520, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 140), Visible = false, BackgroundTransparency = 0.05 }, UI.Layers.HUD)
	banner.BackgroundColor3 = UI.Colors.PanelDark
	UI.Stroke(banner, UI.Colors.Cyan, 2)
	bannerLabel = UI.Label({ Text = "", TextSize = 20, TextColor3 = UI.Colors.Cyan, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0) }, banner)

	Remotes.Event("MatchUpdate").OnClientEvent:Connect(function(eventName, payload)
		if eventName == "Clue" then
			HintController.ShowClue(payload.Text, 8)
			if payload.Stage and payload.Stage > 0 then
				Controllers.NotificationController.Show("Info", string.format("Clue unlocked at %d%%!", payload.Percent or 0))
			end
		elseif eventName == "RegionHighlight" then
			HintController.HighlightRegion(payload.RegionId, payload.Duration or 8, payload.Super)
		end
	end)

	matchState:GetAttributeChangedSignal("OutlinedObjects"):Connect(updateOutline)
	matchState:GetAttributeChangedSignal("State"):Connect(function()
		if matchState:GetAttribute("State") ~= "Searching" then
			bannerToken += 1
			banner.Visible = false
		end
	end)
end

return HintController
