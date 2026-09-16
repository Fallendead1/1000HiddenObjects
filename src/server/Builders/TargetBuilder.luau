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

-- Placeholders are authored standing in the XY plane (MatchService lays them flat).
-- Each part: { name, size, cframe, color, material, shape? }.
local function simple(name: string, parts: { { any } }): Model
	local model = Instance.new("Model")
	model.Name = name
	for i, spec in ipairs(parts) do
		local p = part(spec[1], spec[2], spec[3], spec[4], spec[5], model)
		if spec[6] then
			p.Shape = spec[6]
		end
		if i == 1 then
			model.PrimaryPart = p
		end
	end
	return model
end

local GOLD = Color3.fromRGB(255, 200, 40)
local METAL = Enum.Material.Metal
local SIDEWAYS = CFrame.Angles(0, math.rad(90), 0) -- a cylinder's axis along Z: a disc facing out of the XY plane

local placeholderBuilders: { [string]: () -> Model } = {
	GoldenKey = buildGoldenKey,
	GrandmasRing = function()
		return simple("GrandmasRing", {
			{ "Band", Vector3.new(0.3, 1.4, 1.4), SIDEWAYS, GOLD, METAL, Enum.PartType.Cylinder },
			{ "Inside", Vector3.new(0.32, 0.9, 0.9), SIDEWAYS, Color3.fromRGB(120, 90, 20), METAL, Enum.PartType.Cylinder },
			{ "Setting", Vector3.new(0.5, 0.3, 0.5), CFrame.new(0, 0.75, 0), GOLD, METAL },
			{ "Diamond", Vector3.new(0.7, 0.7, 0.7), CFrame.new(0, 1.15, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), Color3.fromRGB(190, 240, 255), Enum.Material.Glass },
		})
	end,
	GoldenRemote = function()
		local parts = {
			{ "Body", Vector3.new(0.9, 2.4, 0.35), CFrame.new(), GOLD, METAL },
			{ "Power", Vector3.new(0.25, 0.25, 0.1), CFrame.new(0, 0.9, -0.2), Color3.fromRGB(220, 40, 40), Enum.Material.Neon },
		}
		for row = 0, 2 do
			for col = -1, 1 do
				table.insert(parts, { "Button", Vector3.new(0.18, 0.18, 0.08), CFrame.new(col * 0.25, 0.4 - row * 0.3, -0.2), Color3.fromRGB(120, 90, 20), METAL })
			end
		end
		return simple("GoldenRemote", parts)
	end,
	GoldenWrench = function()
		return simple("GoldenWrench", {
			{ "Handle", Vector3.new(2.2, 0.32, 0.22), CFrame.new(), GOLD, METAL },
			{ "Head", Vector3.new(0.24, 0.9, 0.9), CFrame.new(1.3, 0, 0) * SIDEWAYS, GOLD, METAL, Enum.PartType.Cylinder },
			{ "Jaw", Vector3.new(0.5, 0.35, 0.26), CFrame.new(1.55, 0, 0), Color3.fromRGB(120, 90, 20), METAL },
			{ "Ring", Vector3.new(0.24, 0.7, 0.7), CFrame.new(-1.2, 0, 0) * SIDEWAYS, GOLD, METAL, Enum.PartType.Cylinder },
		})
	end,
	TreasureMap = function()
		return simple("TreasureMap", {
			{ "Paper", Vector3.new(2.4, 1.7, 0.08), CFrame.new(), Color3.fromRGB(235, 210, 160), Enum.Material.SmoothPlastic },
			{ "CrossA", Vector3.new(0.6, 0.1, 0.1), CFrame.new(0.5, -0.2, -0.05) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(210, 40, 40), Enum.Material.SmoothPlastic },
			{ "CrossB", Vector3.new(0.6, 0.1, 0.1), CFrame.new(0.5, -0.2, -0.05) * CFrame.Angles(0, 0, math.rad(-45)), Color3.fromRGB(210, 40, 40), Enum.Material.SmoothPlastic },
			{ "Path", Vector3.new(1.2, 0.06, 0.06), CFrame.new(-0.3, 0.2, -0.05) * CFrame.Angles(0, 0, math.rad(-15)), Color3.fromRGB(120, 80, 40), Enum.Material.SmoothPlastic },
			{ "RollL", Vector3.new(1.8, 0.22, 0.22), CFrame.new(-1.2, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 170, 120), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder },
			{ "RollR", Vector3.new(1.8, 0.22, 0.22), CFrame.new(1.2, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 170, 120), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder },
		})
	end,
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
