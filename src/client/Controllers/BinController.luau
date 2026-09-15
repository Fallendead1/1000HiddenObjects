--[[
	Room props on the client:
	  - a big sign on a post over every deposit bin: its colour, icon and one word (TOYS,
	    BOOKS...), plus a white outline around the bin so it stands out from the junk. While you
	    hold something, the bin it belongs in lights up gold and grows (a gold "x2" arrow floats
	    over it, seen from anywhere) and the other signs dim
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

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- The sign is a board in the world, not a screen label: it stays over its bin and shrinks with
-- distance like real signage instead of piling up on screen. It faces into the room, stands at
-- the bin's back edge (clear of the opening) and sits high enough to show over the junk.
local SIGN_SIZE = Vector2.new(7.2, 2.8) -- studs (the closest bins are 8.5 studs apart)
local SIGN_CANVAS = Vector2.new(280, 110) -- pixels drawn onto it
local SIGN_LIFT = 4.2 -- sign centre above the bin's rim
local SIGN_BACK = 1.8 -- from the bin's centre toward the wall
local SIGN_GROW = 1.15 -- the bin you need gets this much bigger

type Face = { Dim: Frame, Stroke: UIStroke }
type Bin = { Type: string, Sign: BasePart, Faces: { Face }, Outline: Highlight? }
local bins: { [Instance]: Bin } = {}
local heldMatch: string? = nil
local sparkles: { [Instance]: Attachment } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- One side of the sign: colour panel, white icon disc, the bin's one word, and a dark tint
-- that dims it while you hold something that belongs in another bin.
local function signFace(board: BasePart, face: Enum.NormalId, def): Face
	local gui = UI.New("SurfaceGui", {
		Name = "BinSign" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = SIGN_CANVAS,
		LightInfluence = 0,
		MaxDistance = 250,
		ResetOnSpawn = false,
	}, board)
	local panel = UI.Frame({ Size = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = WHITE }, gui)
	UI.Corner(panel, 20)
	UI.Gradient(panel, def.Color:Lerp(WHITE, 0.2), def.Color:Lerp(BLACK, 0.2))
	local stroke = UI.Stroke(panel, BLACK, 5)
	local disc = UI.Frame({ Size = UDim2.fromOffset(76, 76), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), BackgroundColor3 = WHITE }, panel)
	UI.Corner(disc, 38)
	UI.Stroke(disc, BLACK, 3)
	local icon = UI.Icon(disc, def.IconKey, string.sub(def.Short, 1, 1), { TextSize = 38, TextColor3 = def.Color })
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local word = UI.Label({ Text = def.Short, TextScaled = true, TextWrapped = false, Size = UDim2.new(1, -110, 0.6, 0), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 98, 0.5, 0), TextXAlignment = Enum.TextXAlignment.Left }, panel)
	local edge = word:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Thickness = 4
	end
	local dim = UI.Frame({ Size = panel.Size, AnchorPoint = panel.AnchorPoint, Position = panel.Position, BackgroundColor3 = BLACK, BackgroundTransparency = 1, ZIndex = 5 }, gui)
	UI.Corner(dim, 20)
	return { Dim = dim, Stroke = stroke }
end

local function makeSign(mouth: BasePart, def): BasePart
	local room = mouth:FindFirstAncestorOfClass("Model")
	local centre = room and room:GetPivot().Position or mouth.Position
	local toCentre = Vector3.new(centre.X - mouth.Position.X, 0, centre.Z - mouth.Position.Z)
	-- Square to the nearest wall so the signs line up with the room.
	local facing = if math.abs(toCentre.X) > math.abs(toCentre.Z) then Vector3.new(math.sign(toCentre.X), 0, 0) else Vector3.new(0, 0, math.sign(toCentre.Z))
	if facing.Magnitude < 0.5 then
		facing = Vector3.new(0, 0, -1)
	end
	local rim = mouth.Position.Y + mouth.Size.Y / 2
	local base = mouth.Position - facing * SIGN_BACK
	local at = Vector3.new(base.X, rim + SIGN_LIFT, base.Z)
	local board = Instance.new("Part")
	board.Name = "BinSign"
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.CastShadow = false
	board.Transparency = 1
	board.Size = Vector3.new(SIGN_SIZE.X, SIGN_SIZE.Y, 0.1)
	board.CFrame = CFrame.lookAt(at, at + facing)
	-- The post from the bin's back edge up to the sign, so it reads as that bin's sign.
	local postHeight = SIGN_LIFT - SIGN_SIZE.Y / 2
	local post = Instance.new("Part")
	post.Name = "BinSignPost"
	post.Anchored = true
	post.CanCollide = false
	post.CanQuery = false
	post.CanTouch = false
	post.CastShadow = false
	post.Material = Enum.Material.SmoothPlastic
	post.Color = def.Color:Lerp(BLACK, 0.35)
	post.Size = Vector3.new(0.35, postHeight, 0.35)
	post.CFrame = CFrame.new(base.X, rim + postHeight / 2, base.Z)
	post.Parent = board
	board.Parent = mouth -- client-only, and it goes away with the room
	return board
end

-- The bin's own model (Room.Props.<PropKey> standing on its mouth), outlined in white.
local function outlineFor(mouth: BasePart, board: BasePart, def): Highlight?
	local room = mouth:FindFirstAncestorOfClass("Model")
	local props = room and room:FindFirstChild("Props")
	local best, bestDistance = nil, 6
	for _, prop in ipairs(props and props:GetChildren() or {}) do
		if prop.Name == def.PropKey and prop:IsA("Model") then
			local d = ((prop:GetPivot().Position - mouth.Position) * Vector3.new(1, 0, 1)).Magnitude
			if d < bestDistance then
				best, bestDistance = prop, d
			end
		end
	end
	if not best then
		return nil
	end
	return UI.New("Highlight", {
		Name = "BinOutline",
		Adornee = best,
		FillColor = UI.Colors.Gold,
		FillTransparency = 1,
		OutlineColor = WHITE,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
	}, board) :: Highlight
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
		for mouth, bin in pairs(bins) do
			if bin.Type == heldMatch and mouth.Parent then
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
	-- Just above the (grown) sign.
	guideHeight = target.Size.Y / 2 + SIGN_LIFT + SIGN_SIZE.Y * SIGN_GROW / 2 + 1.7
	g.Enabled = true
end

local function refreshHighlight()
	for _, bin in pairs(bins) do
		local lit = heldMatch == bin.Type
		local faded = heldMatch ~= nil and not lit
		for _, f in ipairs(bin.Faces) do
			f.Stroke.Color = lit and UI.Colors.Gold or BLACK
			f.Stroke.Thickness = lit and 9 or 5
			UI.Tween(f.Dim, { BackgroundTransparency = faded and 0.45 or 1 }, 0.2)
		end
		local grow = lit and SIGN_GROW or 1
		UI.Tween(bin.Sign, { Size = Vector3.new(SIGN_SIZE.X * grow, SIGN_SIZE.Y * grow, 0.1) }, 0.18, Enum.EasingStyle.Back)
		if bin.Outline then
			bin.Outline.OutlineColor = lit and UI.Colors.Gold or WHITE
			bin.Outline.FillTransparency = lit and 0.7 or 1
			bin.Outline.OutlineTransparency = faded and 0.8 or 0
		end
	end
	refreshGuide()
end

local function addBin(mouth: Instance)
	if bins[mouth] or not mouth:IsA("BasePart") then
		return
	end
	local def = DepositConfig.Types[mouth:GetAttribute("BinType") or ""]
	if not def then
		return
	end
	local board = makeSign(mouth, def)
	local bin: Bin = { Type = def.Type, Sign = board, Faces = {}, Outline = nil }
	-- Readable from behind too (the entrance side of a front-wall bin).
	bin.Faces = { signFace(board, Enum.NormalId.Front, def), signFace(board, Enum.NormalId.Back, def) }
	bin.Outline = outlineFor(mouth, board, def)
	bins[mouth] = bin
	if not bin.Outline then
		-- The props can arrive a moment after the mouth.
		task.delay(1, function()
			if bins[mouth] == bin and not bin.Outline and board.Parent then
				bin.Outline = outlineFor(mouth, board, def)
			end
		end)
	end
	mouth.AncestryChanged:Connect(function()
		if not mouth:IsDescendantOf(workspace) and bins[mouth] then
			bins[mouth].Sign:Destroy()
			bins[mouth] = nil
		end
	end)
	if heldMatch then
		refreshHighlight()
	end
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
	for mouth in pairs(bins) do
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
		addBin(mouth)
	end
	CollectionService:GetInstanceAddedSignal("DepositBin"):Connect(function(mouth)
		task.defer(addBin, mouth)
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
