--[[
	Room props on the client:
	  - a floating label over every deposit bin (icon, name, what it pays double for); the bin
	    that matches what you're holding glows gold with "x2"
	  - treasures sparkle once they're uncovered (nothing lying on top of them)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DepositConfig = require(Shared.Config.DepositConfig)

local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local BinController = {}

type Label = { Gui: BillboardGui, Stroke: UIStroke, Bonus: TextLabel, Type: string, Scale: UIScale }
local labels: { [Instance]: Label } = {}
local heldMatch: string? = nil
local sparkles: { [Instance]: Attachment } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function categoryText(def): string
	local names = {}
	for _, c in ipairs(def.Categories) do
		table.insert(names, string.upper(c))
	end
	if def.HeavyWeight then
		table.insert(names, "HEAVY STUFF")
	end
	return table.concat(names, " / ") .. "  x2"
end

local function addLabel(mouth: Instance)
	if labels[mouth] or not mouth:IsA("BasePart") then
		return
	end
	local def = DepositConfig.Types[mouth:GetAttribute("BinType") or ""]
	if not def then
		return
	end
	local gui = UI.Billboard(mouth, UDim2.fromOffset(214, 66), Vector3.new(0, mouth.Size.Y / 2 + 1.8, 0), 90)
	gui.Name = "BinLabel"
	local panel = UI.Panel({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.12 }, gui)
	local stroke = UI.Stroke(panel, def.Color, 2.5)
	local scale = UI.New("UIScale", {}, panel) :: UIScale
	local badge = UI.Surface3D({ Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(7, 7) }, panel, def.Color, 25, 0.12)
	local icon = UI.Icon(badge, def.IconKey, string.sub(def.Name, 1, 1), { TextSize = 24 })
	icon.Size = UDim2.fromScale(0.74, 0.66)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	local title = UI.Label({ Text = def.Name, TextSize = 16, Size = UDim2.new(1, -70, 0, 24), Position = UDim2.fromOffset(64, 8), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false }, panel)
	UI.TextGradient(title, def.Color)
	local bonus = UI.Label({ Text = categoryText(def), TextSize = 11, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -70, 0, 26), Position = UDim2.fromOffset(64, 33), TextXAlignment = Enum.TextXAlignment.Left }, panel)
	labels[mouth] = { Gui = gui, Stroke = stroke, Bonus = bonus, Type = def.Type, Scale = scale }
	mouth.AncestryChanged:Connect(function()
		if not mouth:IsDescendantOf(workspace) and labels[mouth] then
			labels[mouth].Gui:Destroy()
			labels[mouth] = nil
		end
	end)
end

local guide: BillboardGui? = nil
local guideHeight = 0

-- The bin guide: a gold "x2" and a down chevron that float over the right bin, drawn on top of
-- everything so it can be found from anywhere in the room.
local function makeGuide(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "BinGuide"
	gui.Size = UDim2.fromOffset(90, 96)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 500
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local tag = UI.Label({ Text = "x2", TextSize = 30, TextWrapped = false, Size = UDim2.new(1, 0, 0, 36) }, gui)
	UI.TextGradient(tag, UI.Colors.Gold)
	for _, angle in ipairs({ 45, -45 }) do
		local bar = UI.Frame({ Size = UDim2.fromOffset(40, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, angle > 0 and -12 or 12, 0, 62), Rotation = angle, BackgroundColor3 = UI.Colors.Gold }, gui)
		UI.New("UICorner", { CornerRadius = UDim.new(0, 6) }, bar)
		UI.New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2.5 }, bar)
	end
	return gui
end

local function refreshGuide()
	local target: BasePart? = nil
	if heldMatch then
		for mouth, label in pairs(labels) do
			if label.Type == heldMatch and mouth.Parent then
				target = mouth :: BasePart
				break
			end
		end
	end
	if not target then
		if guide then
			guide.Enabled = false
		end
		return
	end
	local g = guide or makeGuide()
	guide = g
	g.Adornee = target
	guideHeight = target.Size.Y / 2 + 5.4
	g.Enabled = true
end

local function refreshHighlight()
	for _, label in pairs(labels) do
		local lit = heldMatch == label.Type
		label.Stroke.Color = lit and UI.Colors.Gold or (DepositConfig.Types[label.Type] and DepositConfig.Types[label.Type].Color or UI.Colors.Stroke)
		label.Stroke.Thickness = lit and 4 or 2
		label.Bonus.TextColor3 = lit and UI.Colors.Gold or UI.Colors.TextDim
		UI.Tween(label.Scale, { Scale = lit and 1.15 or 1 }, 0.15)
	end
	refreshGuide()
end

-- GrabController tells us what is being held so its bin lights up (nil = nothing).
function BinController.SetHeld(root: BasePart?)
	local match = root and DepositConfig.MatchingType(root:GetAttribute("Category"), root:GetAttribute("Weight")) or nil
	if match ~= heldMatch then
		heldMatch = match
		refreshHighlight()
	end
end

-- Every bin mouth in the current room (for the throw-arc "IN!" check and bin magnetism).
function BinController.GetMouths(): { BasePart }
	local list = {}
	for mouth in pairs(labels) do
		if mouth.Parent then
			table.insert(list, mouth :: BasePart)
		end
	end
	return list
end

local function sparkleOn(root: BasePart)
	if sparkles[root] then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "TreasureSparkle"
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 6
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 235, 140))
	pe.LightEmission = 1
	pe.Parent = att
	att.Parent = root
	sparkles[root] = att
end

local function sparkleOff(root: Instance)
	local att = sparkles[root]
	if att then
		att:Destroy()
		sparkles[root] = nil
	end
end

local function updateTreasures()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	rayParams.FilterDescendantsInstances = { player.Character, camera }
	for root in pairs(sparkles) do
		if not root.Parent then
			sparkles[root] = nil
		end
	end
	for _, root in ipairs(CollectionService:GetTagged("Treasure")) do
		if root:IsA("BasePart") then
			if (root.Position - camera.CFrame.Position).Magnitude > 50 then
				sparkleOff(root)
			else
				local hit = workspace:Raycast(root.Position + Vector3.new(0, 8, 0), Vector3.new(0, -9, 0), rayParams)
				local exposed = hit ~= nil and (hit.Instance == root or hit.Instance.Parent == root)
				if exposed then
					sparkleOn(root)
				else
					sparkleOff(root)
				end
			end
		end
	end
end

function BinController.Init()
	for _, mouth in ipairs(CollectionService:GetTagged("DepositBin")) do
		addLabel(mouth)
	end
	CollectionService:GetInstanceAddedSignal("DepositBin"):Connect(function(mouth)
		task.defer(addLabel, mouth)
	end)
	-- The guide bobs gently so the eye catches it.
	task.spawn(function()
		while true do
			if guide and guide.Enabled then
				guide.StudsOffset = Vector3.new(0, guideHeight + math.sin(os.clock() * 5) * 0.4, 0)
			end
			task.wait(0.03)
		end
	end)
end

function BinController.Start()
	while true do
		task.wait(0.5)
		if player:GetAttribute("InMatch") then
			updateTreasures()
		end
	end
end

return BinController
