--[[
	Returns the hidden-object model for a target id. Uses ServerStorage.Targets.<TargetId>
	when a final asset exists, otherwise builds a chunky placeholder from primitives.
]]

local ServerStorage = game:GetService("ServerStorage")

local TargetBuilder = {}

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function buildGoldenKey(): Model
	local model = Instance.new("Model")
	model.Name = "GoldenKey"
	local gold = Color3.fromRGB(255, 200, 40)
	local mat = Enum.Material.Metal

	local origin = CFrame.new()
	local head = part("Head", Vector3.new(1.2, 1.2, 0.3), origin * CFrame.new(-0.7, 0, 0), gold, mat, model)
	head.Shape = Enum.PartType.Cylinder
	head.CFrame = origin * CFrame.new(-0.7, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	local hole = part("Hole", Vector3.new(0.5, 0.5, 0.36), origin * CFrame.new(-0.7, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(120, 90, 20), mat, model)
	hole.Shape = Enum.PartType.Cylinder
	part("Shaft", Vector3.new(1.6, 0.28, 0.28), origin * CFrame.new(0.5, 0, 0), gold, mat, model)
	part("Tooth1", Vector3.new(0.25, 0.45, 0.28), origin * CFrame.new(1.1, -0.3, 0), gold, mat, model)
	part("Tooth2", Vector3.new(0.25, 0.32, 0.28), origin * CFrame.new(0.7, -0.25, 0), gold, mat, model)

	model.PrimaryPart = head
	return model
end

local placeholderBuilders: { [string]: () -> Model } = {
	GoldenKey = buildGoldenKey,
}

function TargetBuilder.Get(targetId: string): Model
	local targetsFolder = ServerStorage:FindFirstChild("Targets")
	local existing = targetsFolder and targetsFolder:FindFirstChild(targetId)
	if existing and existing:IsA("Model") then
		local clone = existing:Clone()
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		return clone
	end
	local builder = placeholderBuilders[targetId]
	if builder then
		return builder()
	end
	-- Generic fallback: a gold cube so a new room never breaks because art is missing.
	local model = Instance.new("Model")
	model.Name = targetId
	local p = part("Body", Vector3.new(1.5, 1.5, 1.5), CFrame.new(), Color3.fromRGB(255, 200, 40), Enum.Material.Neon, model)
	model.PrimaryPart = p
	return model
end

return TargetBuilder
