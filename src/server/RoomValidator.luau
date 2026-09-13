--[[
	Development validator for a built room (and the lobby's matchmaking zones). Produces a
	readable report so AI-generated rooms can be checked before they are ever played.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ClutterConfig = require(ReplicatedStorage.Shared.Config.ClutterConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)

local RoomValidator = {}

-- Structure/decor names that would read as clutter to a player but can't be grabbed.
local CLUTTER_LOOKING = { "book", "shirt", "sock", "shoe", "toy", "box", "pillow", "blanket", "basketball", "bottle", "cup", "can", "paper", "magazine", "controller", "skateboard", "plush", "bear" }

local function looksLikeClutter(name: string): boolean
	local lower = string.lower(name)
	if string.find(lower, "shelf", 1, true) then
		return false
	end
	for _, word in ipairs(CLUTTER_LOOKING) do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

function RoomValidator.ValidateLobby(errors: { string }, warnings: { string })
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		table.insert(warnings, "No Workspace.Lobby (matchmaking circles unavailable on this server)")
		return
	end
	local seen, count = {}, 0
	for _, zone in ipairs(CollectionService:GetTagged("QueueZone")) do
		if zone:IsDescendantOf(lobby) then
			count += 1
			local id = zone:GetAttribute("QueueId")
			if not id or id == "" then
				table.insert(errors, "Matchmaking zone without QueueId: " .. zone:GetFullName())
			elseif seen[id] then
				table.insert(errors, "Duplicate QueueId: " .. id)
			end
			if id then
				seen[id] = true
			end
		end
	end
	if count == 0 then
		table.insert(errors, "Workspace.Lobby has no matchmaking zones (tag QueueZone)")
	end
end

function RoomValidator.Validate(runtime, config): (boolean, string)
	local errors, warnings = {}, {}
	local function err(msg: string)
		table.insert(errors, msg)
	end
	local function warnMsg(msg: string)
		table.insert(warnings, msg)
	end

	if not runtime.SpawnPart then
		err("Missing RoomSpawn (tag RoomSpawn)")
	end
	local regionCount = 0
	for _ in pairs(runtime.Regions) do
		regionCount += 1
	end
	if regionCount == 0 then
		warnMsg("No SearchRegion volumes; region hints will have nothing to highlight")
	end

	-- Individual clutter objects
	local ids, perKey, badPhysics = {}, {}, 0
	local chunks, hidden, treasures = 0, 0, 0
	local maxStrength = UpgradeConfig.GetValue("Strength", UpgradeConfig.GetMaxLevel("Strength"))
	if #runtime.Objects == 0 then
		err("Room has no movable clutter objects (tag Clutter)")
	end
	for _, root in ipairs(runtime.Objects) do
		local id = root:GetAttribute("ObjectId")
		local label = id or root:GetFullName()
		if not id or id == "" then
			err("Clutter object missing ObjectId: " .. root:GetFullName())
		elseif ids[id] then
			err("Duplicate ObjectId: " .. id)
		else
			ids[id] = true
		end
		if root:GetAttribute("Movable") ~= true then
			err("Visible clutter not Movable: " .. label)
		end
		local key = root:GetAttribute("AssetKey")
		if not key or key == "" then
			err("Missing AssetKey: " .. label)
		else
			perKey[key] = (perKey[key] or 0) + 1
			if not ClutterConfig.Get(key) then
				warnMsg("AssetKey not in ClutterConfig: " .. key .. " (" .. label .. ")")
			end
		end
		local weight = root:GetAttribute("Weight")
		if type(weight) ~= "number" then
			err("Missing Weight: " .. label)
		elseif weight < 1 or weight > ClutterConfig.MaxReasonableWeight then
			err(string.format("Absurd Weight %s: %s", tostring(weight), label))
		elseif weight > maxStrength then
			warnMsg(string.format("%s weighs %d - heavier than max Strength %d, can never be moved", label, weight, maxStrength))
		end
		if type(root:GetAttribute("CashValue")) ~= "number" then
			err("Missing CashValue: " .. label)
		end
		if typeof(root:GetAttribute("OriginalCFrame")) ~= "CFrame" then
			err("Invalid OriginalCFrame: " .. label)
		end
		local region = root:GetAttribute("RegionId")
		if not region or not runtime.Regions[region] then
			err("Invalid RegionId '" .. tostring(region) .. "': " .. label)
		end
		if not root.CanQuery then
			badPhysics += 1
		end
		if root:GetAttribute("IsChunk") then
			chunks += 1
			local contents = root:GetAttribute("Contents") or ""
			if contents == "" then
				err("Junk chunk with no contents: " .. label)
			end
			for _, k in ipairs(string.split(contents, ",")) do
				hidden += 1
				if k ~= "" and not ClutterConfig.Get(k) then
					err("Junk chunk holds unknown AssetKey '" .. k .. "': " .. label)
				end
			end
		elseif root:GetAttribute("Category") == "Treasure" then
			treasures += 1
		end
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("BasePart") and (child.CanCollide or not child.Massless or not child:FindFirstChildWhichIsA("WeldConstraint")) then
				badPhysics += 1
			end
		end
	end
	if badPhysics > 0 then
		err(string.format("%d clutter parts have broken physics setup (root must be queryable; details massless, non-colliding, welded)", badPhysics))
	end

	-- Deposit bins (the only Cash source) and nothing spawned inside one
	local binCount = 0
	local clutterFolder = runtime.Model:FindFirstChild("Clutter")
	local binParams = OverlapParams.new()
	binParams.FilterType = Enum.RaycastFilterType.Include
	binParams.FilterDescendantsInstances = clutterFolder and { clutterFolder } or {}
	for _, mouth in ipairs(CollectionService:GetTagged("DepositBin")) do
		if mouth:IsA("BasePart") and mouth:IsDescendantOf(runtime.Model) then
			binCount += 1
			local inside = clutterFolder and #workspace:GetPartBoundsInBox(mouth.CFrame, mouth.Size, binParams) or 0
			if inside > 0 then
				err(string.format("%d clutter parts spawned inside %s (they would be cleaned instantly)", inside, mouth.Name))
			end
		end
	end
	if binCount == 0 then
		err("Room has no deposit bins (tag DepositBin): players could never earn Cash")
	end

	-- Anything visible that isn't furniture/clutter and looks grabbable
	local structure = runtime.Model:FindFirstChild("Structure")
	if structure then
		for _, p in ipairs(structure:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 1 and looksLikeClutter(p.Name) then
				warnMsg("Decor looks like clutter but is not interactive: " .. p.Name)
			end
		end
	end

	-- Target sockets and their physical blocker groups
	local minSockets = config.MinimumTargetSockets or 30
	local exposable = 0
	for _, socket in ipairs(runtime.SocketList) do
		local group = socket.Part:GetAttribute("BlockerGroup") or ""
		if group == "" or #socket.Blockers == 0 then
			err("TargetSocket has no blocker group (key would be visible at start): " .. socket.Id)
		else
			local ok = true
			for blockerId in string.gmatch(group, "[^,]+") do
				local obj = runtime.ObjectsById[blockerId]
				if not obj then
					err("Socket " .. socket.Id .. " blocker references missing object " .. blockerId)
					ok = false
				elseif (obj:GetAttribute("Weight") or 1) > maxStrength then
					err("Impossible exposure: " .. socket.Id .. " is under " .. blockerId .. " which no Strength level can lift")
					ok = false
				end
			end
			if ok then
				exposable += 1
			end
		end
		if socket.RegionId == "" or not runtime.Regions[socket.RegionId] then
			err("Socket has invalid RegionId: " .. socket.Id)
		end
		-- Only solid furniture can swallow the key; thin decor such as rugs does not.
		local solid = {}
		for _, part in ipairs(runtime.StructureParts) do
			if part.CanCollide then
				table.insert(solid, part)
			end
		end
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = solid
		local inside = workspace:GetPartBoundsInBox(CFrame.new(socket.Position), Vector3.new(0.4, 0.4, 0.4), params)
		if #inside > 0 then
			err("Socket " .. socket.Id .. " is inside furniture (" .. inside[1].Name .. ")")
		end
	end
	if exposable < minSockets then
		err(string.format("Only %d exposable target sockets (minimum %d)", exposable, minSockets))
	end

	local targets = ServerStorage:FindFirstChild("Targets")
	if not (targets and targets:FindFirstChild(config.TargetId)) then
		warnMsg("No final target model at ServerStorage.Targets." .. config.TargetId .. " (placeholder in use)")
	end

	RoomValidator.ValidateLobby(errors, warnings)

	local keys = {}
	for k in pairs(perKey) do
		table.insert(keys, k)
	end
	table.sort(keys)
	local partCount = 0
	for _, d in ipairs(runtime.Model:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	local lines = {
		string.format("=== ROOM VALIDATION: %s (%s) ===", config.Name, config.DisplayNumber),
		string.format("Movable objects: %d | AssetKeys used: %d | Sockets: %d exposable / %d | Regions: %d | Total parts: %d",
			#runtime.Objects, #keys, exposable, #runtime.SocketList, regionCount, partCount),
		string.format("Bins: %d | Junk chunks: %d holding %d objects | Treasures: %d | Real objects in room: %d",
			binCount, chunks, hidden, treasures, runtime.TotalObjects or #runtime.Objects),
		#errors == 0 and "RESULT: PASS" or string.format("RESULT: FAIL (%d errors)", #errors),
	}
	for i, e in ipairs(errors) do
		if i > 25 then
			table.insert(lines, string.format("  ... %d more errors", #errors - 25))
			break
		end
		table.insert(lines, "  [ERROR] " .. e)
	end
	for i, w in ipairs(warnings) do
		if i > 15 then
			table.insert(lines, string.format("  ... %d more warnings", #warnings - 15))
			break
		end
		table.insert(lines, "  [WARN]  " .. w)
	end
	return #errors == 0, table.concat(lines, "\n")
end

return RoomValidator
