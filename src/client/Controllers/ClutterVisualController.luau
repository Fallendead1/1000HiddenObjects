--[[
	Client-side clutter visuals. Watches every ClutterCluster's replicated VisualStage and
	animates chunk removal: pop up, spin, get sucked toward the searching player's bag, shrink
	and fade. Also hides ForceHiddenChunks around a revealed target and decorates the revealed
	target with a sparkle + gold burst.
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
local ghostFolder: Folder

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
	end
end

-- Who is pulling this pile apart? Prefer the local player if they are searching it, else any
-- teammate searching it, else nobody (fly up and away).
local function findPuller(clusterId: string): BasePart?
	local best = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("SearchingCluster") == clusterId then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				if p == player then
					return root
				end
				best = best or root
			end
		end
	end
	return best
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
	local puller = findPuller(entry.Id)
	for _, p in ipairs(parts) do
		local ghost = p:Clone()
		for _, child in ipairs(ghost:GetChildren()) do
			child:Destroy()
		end
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CanQuery = false
		ghost.CanTouch = false
		ghost.CastShadow = false
		ghost.LocalTransparencyModifier = 0
		ghost.Parent = ghostFolder
		p.LocalTransparencyModifier = 1

		local away = (p.Position - center)
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.5 then
			away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		end
		away = away.Unit * rng:NextNumber(1.5, 3.5)
		local up = Vector3.new(0, rng:NextNumber(2.5, 4.5), 0)
		local spin = CFrame.Angles(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2))
		local popGoal = p.CFrame + up + away

		local t1 = TweenService:Create(ghost, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = popGoal * spin })
		t1:Play()
		t1.Completed:Once(function()
			local goal
			if puller and puller.Parent then
				goal = CFrame.new(puller.Position + Vector3.new(0, 1, 0)) * spin
			else
				goal = popGoal * spin + Vector3.new(0, -2, 0)
			end
			local t2 = TweenService:Create(ghost, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = goal, Transparency = 0.6, Size = ghost.Size * 0.25 })
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
	local delayIndex = 0
	for i = 1, stage do
		local chunk = entry.Chunks[i]
		if chunk and not entry.Hidden[chunk] then
			entry.Hidden[chunk] = true
			if animate then
				local d = delayIndex * 0.07
				delayIndex += 1
				task.delay(d, function()
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
	sparkle.Rate = 8
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparkle.LightEmission = 1
	sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	sparkle.Parent = attachment
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Brightness = 1
	light.Range = 8
	light.Parent = primary
	Controllers.AudioController.PlayAt("TargetReveal", primary.Position)
	Controllers.FXController.Burst(primary.Position + Vector3.new(0, 1, 0), Color3.fromRGB(255, 210, 60), 24, 0.35)

	-- Gentle hover so the key catches the eye once exposed.
	if model:IsA("Model") then
		task.spawn(function()
			local base = model:GetPivot()
			local t0 = os.clock()
			while model.Parent do
				local t = os.clock() - t0
				model:PivotTo(base * CFrame.new(0, math.sin(t * 2) * 0.15 + 0.15, 0) * CFrame.Angles(0, t * 0.6, 0))
				task.wait()
			end
		end)
	end
end

function ClutterVisualController.Init()
	ghostFolder = Instance.new("Folder")
	ghostFolder.Name = "ClutterGhosts"
	ghostFolder.Parent = workspace.CurrentCamera

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

-- Tactile shake of a few visible chunks nearest the top of the pile on a search tick.
function ClutterVisualController.Shake(id: string)
	local entry = byId[id]
	if not entry or reduceVFX() then
		return
	end
	local shaken = 0
	local visibleTop = {}
	for i = 1, #entry.Chunks do
		local chunk = entry.Chunks[i]
		if not entry.Hidden[chunk] then
			table.insert(visibleTop, chunk)
			if #visibleTop >= 6 then
				break
			end
		end
	end
	for _, chunk in ipairs(visibleTop) do
		if rng:NextNumber() < 0.6 then
			local p = partsOf(chunk)[1]
			if p then
				local original = p.CFrame
				local offset = CFrame.new(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0.1, 0.35), rng:NextNumber(-0.2, 0.2)) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1))
				TweenService:Create(p, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { CFrame = original * offset }):Play()
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
