--[[
	Client-side clutter visuals. Watches every ClutterCluster's replicated VisualStage and
	animates chunk removal (pop up, fly aside, fade). Also hides ForceHiddenChunks around a
	revealed target and decorates the revealed target with a subtle sparkle.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local ClutterVisualController = {}

type ClusterEntry = {
	Model: Model,
	Id: string,
	Volume: BasePart?,
	Chunks: { Instance },
	Hidden: { [Instance]: boolean },
	Connections: { RBXScriptConnection },
}

local clusters: { [Model]: ClusterEntry } = {}
local byId: { [string]: ClusterEntry } = {}
local volumes: { BasePart } = {}
local rng = Random.new()

local function reduceVFX(): boolean
	return player:GetAttribute("Setting_ReduceVFX") == true
end

local function collectChunks(model: Model): { Instance }
	local folder = model:FindFirstChild("Chunks")
	local list = {}
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("BasePart") or c:IsA("Model") then
				table.insert(list, c)
			end
		end
	end
	table.sort(list, function(a, b)
		local oa = a:GetAttribute("RemovalOrder") or tonumber(a.Name:match("%d+")) or 0
		local ob = b:GetAttribute("RemovalOrder") or tonumber(b.Name:match("%d+")) or 0
		return oa < ob
	end)
	return list
end

local function partsOf(chunk: Instance): { BasePart }
	if chunk:IsA("BasePart") then
		return { chunk }
	end
	local parts = {}
	for _, d in ipairs(chunk:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function hideInstant(chunk: Instance)
	for _, p in ipairs(partsOf(chunk)) do
		p.LocalTransparencyModifier = 1
		p.CastShadow = false
	end
end

local function hideAnimated(entry: ClusterEntry, chunk: Instance)
	local parts = partsOf(chunk)
	if #parts == 0 then
		return
	end
	if reduceVFX() then
		hideInstant(chunk)
		return
	end
	local center = entry.Volume and entry.Volume.Position or parts[1].Position
	for _, p in ipairs(parts) do
		-- Animate a throwaway clone so the real (server-owned) part stays untouched.
		local ghost = p:Clone()
		for _, child in ipairs(ghost:GetChildren()) do
			child:Destroy()
		end
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.LocalTransparencyModifier = 0
		ghost.Parent = workspace.CurrentCamera
		p.LocalTransparencyModifier = 1

		local away = (p.Position - center)
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.5 then
			away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		end
		away = away.Unit * rng:NextNumber(3, 6)
		local up = Vector3.new(0, rng:NextNumber(2.5, 4.5), 0)
		local goal = p.CFrame + up + away
		local spin = CFrame.Angles(rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 1.5), rng:NextNumber(-1.5, 1.5))
		local t1 = TweenService:Create(ghost, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal * spin })
		t1:Play()
		t1.Completed:Once(function()
			local t2 = TweenService:Create(ghost, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = goal * spin + Vector3.new(0, -1.5, 0), Transparency = 1, Size = ghost.Size * 0.4 })
			t2:Play()
			t2.Completed:Once(function()
				ghost:Destroy()
			end)
		end)
	end
	Controllers.AudioController.PlayAt("ClutterPop", parts[1].Position)
	Controllers.FXController.DustPuff(parts[1].Position)
end

local function applyStage(entry: ClusterEntry, stage: number, animate: boolean)
	stage = math.clamp(stage, 0, #entry.Chunks)
	for i = 1, stage do
		local chunk = entry.Chunks[i]
		if chunk and not entry.Hidden[chunk] then
			entry.Hidden[chunk] = true
			if animate then
				task.delay((i % 4) * 0.06, function()
					hideAnimated(entry, chunk)
				end)
			else
				hideInstant(chunk)
			end
		end
	end
end

local function applyForceHidden(entry: ClusterEntry)
	local list = entry.Model:GetAttribute("ForceHiddenChunks")
	if type(list) ~= "string" or list == "" then
		return
	end
	for name in string.gmatch(list, "[^,]+") do
		for _, chunk in ipairs(entry.Chunks) do
			if chunk.Name == name and not entry.Hidden[chunk] then
				entry.Hidden[chunk] = true
				hideAnimated(entry, chunk)
			end
		end
	end
end

local function register(model: Model)
	if clusters[model] then
		return
	end
	local volume = model:FindFirstChild("SearchVolume") or model.PrimaryPart
	local entry: ClusterEntry = {
		Model = model,
		Id = model:GetAttribute("ClusterId") or model.Name,
		Volume = volume :: BasePart?,
		Chunks = collectChunks(model),
		Hidden = {},
		Connections = {},
	}
	clusters[model] = entry
	byId[entry.Id] = entry
	if volume and volume:IsA("BasePart") then
		table.insert(volumes, volume)
	end

	applyStage(entry, model:GetAttribute("VisualStage") or 0, false)
	applyForceHidden(entry)

	table.insert(entry.Connections, model:GetAttributeChangedSignal("VisualStage"):Connect(function()
		applyStage(entry, model:GetAttribute("VisualStage") or 0, true)
	end))
	table.insert(entry.Connections, model:GetAttributeChangedSignal("ForceHiddenChunks"):Connect(function()
		applyForceHidden(entry)
	end))
	-- Chunks may stream in slightly after the model.
	local chunksFolder = model:FindFirstChild("Chunks")
	if chunksFolder then
		table.insert(entry.Connections, chunksFolder.ChildAdded:Connect(function()
			task.defer(function()
				entry.Chunks = collectChunks(model)
				applyStage(entry, model:GetAttribute("VisualStage") or 0, false)
			end)
		end))
	end
end

local function unregister(model: Model)
	local entry = clusters[model]
	if not entry then
		return
	end
	for _, c in ipairs(entry.Connections) do
		c:Disconnect()
	end
	clusters[model] = nil
	byId[entry.Id] = nil
	if entry.Volume then
		local idx = table.find(volumes, entry.Volume)
		if idx then
			table.remove(volumes, idx)
		end
	end
end

local function decorateTarget(model: Instance)
	local primary = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")) or model
	if not primary or not primary:IsA("BasePart") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = primary
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Rate = 6
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkle.LightEmission = 1
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Brightness = 0.8
	light.Range = 6
	light.Parent = primary
	Controllers.AudioController.PlayAt("TargetReveal", primary.Position)
end

function ClutterVisualController.Init()
	for _, model in ipairs(CollectionService:GetTagged("ClutterCluster")) do
		if model:IsA("Model") then
			register(model)
		end
	end
	CollectionService:GetInstanceAddedSignal("ClutterCluster"):Connect(function(model)
		if model:IsA("Model") then
			task.defer(register, model)
		end
	end)
	CollectionService:GetInstanceRemovedSignal("ClutterCluster"):Connect(function(model)
		if model:IsA("Model") then
			unregister(model)
		end
	end)

	for _, t in ipairs(CollectionService:GetTagged("HiddenTarget")) do
		decorateTarget(t)
	end
	CollectionService:GetInstanceAddedSignal("HiddenTarget"):Connect(function(t)
		task.defer(decorateTarget, t)
	end)
end

function ClutterVisualController.GetVolumes(): { BasePart }
	return volumes
end

function ClutterVisualController.GetClusterByVolume(part: BasePart): (Model?, string?)
	for model, entry in pairs(clusters) do
		if entry.Volume == part then
			return model, entry.Id
		end
	end
	return nil, nil
end

function ClutterVisualController.GetClusterModel(id: string): Model?
	local entry = byId[id]
	return entry and entry.Model or nil
end

function ClutterVisualController.GetClusterCenter(id: string): Vector3?
	local entry = byId[id]
	return entry and entry.Volume and entry.Volume.Position or nil
end

-- Small tactile shake of a few visible chunks on a search tick.
function ClutterVisualController.Shake(id: string)
	local entry = byId[id]
	if not entry or reduceVFX() then
		return
	end
	local shaken = 0
	for i = #entry.Chunks, 1, -1 do
		local chunk = entry.Chunks[i]
		if not entry.Hidden[chunk] then
			local parts = partsOf(chunk)
			local p = parts[1]
			if p then
				local original = p.CFrame
				local offset = CFrame.new(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0.05, 0.25), rng:NextNumber(-0.15, 0.15))
				-- Shaking the real part locally is safe: server never re-sends unchanged CFrames.
				local t = TweenService:Create(p, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { CFrame = original * offset })
				t:Play()
			end
			shaken += 1
			if shaken >= 3 then
				break
			end
		end
	end
end

function ClutterVisualController.GetAllClusterModels(): { [string]: Model }
	local out = {}
	for _, entry in pairs(clusters) do
		out[entry.Id] = entry.Model
	end
	return out
end

return ClutterVisualController
