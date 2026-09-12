--[[
	Development validator for room runtimes. Produces a readable report so AI-generated
	rooms can be checked before they are ever played.
]]

local RoomValidator = {}

local SANE_MESS_MIN = 5000
local SANE_MESS_MAX = 2000000

function RoomValidator.Validate(runtime, config): (boolean, string)
	local errors = {}
	local warnings = {}

	local function err(msg: string)
		table.insert(errors, msg)
	end
	local function warnMsg(msg: string)
		table.insert(warnings, msg)
	end

	if not runtime.SpawnPart then
		err("Missing RoomSpawn (tag RoomSpawn)")
	end
	if not runtime.TrashChuteZone then
		err("Missing TrashChute (tag TrashChute)")
	end
	if #runtime.ClusterList == 0 then
		err("No ClutterClusters found (tag ClutterCluster)")
	end

	local seenIds = {}
	local eligibleCount = 0
	for _, cluster in ipairs(runtime.ClusterList) do
		if seenIds[cluster.Id] then
			err("Duplicate ClusterId: " .. cluster.Id)
		end
		seenIds[cluster.Id] = true
		if cluster.Weight <= 0 then
			err("Cluster has zero/negative Weight (would get zero MaxMess): " .. cluster.Id)
		end
		if cluster.RegionId == "" then
			err("Cluster missing RegionId: " .. cluster.Id)
		elseif not runtime.Regions[cluster.RegionId] then
			warnMsg("Cluster references unknown region '" .. cluster.RegionId .. "': " .. cluster.Id)
		end
		if cluster.ChunkCount == 0 then
			warnMsg("Cluster has no visual chunks: " .. cluster.Id)
		end
		if cluster.TargetEligible then
			eligibleCount += 1
		end
		if cluster.MaxMess > 0 and cluster.MaxMess < 200 then
			warnMsg(string.format("Cluster %s has very little mess (%d)", cluster.Id, cluster.MaxMess))
		end
	end
	if eligibleCount == 0 and #runtime.ClusterList > 0 then
		err("No TargetEligible clusters")
	end

	local minSockets = config.MinimumTargetSockets or 30
	local validSockets = 0
	for _, socket in ipairs(runtime.SocketList) do
		local cluster = runtime.Clusters[socket.ClusterId]
		if not cluster then
			err("Socket references missing cluster '" .. socket.ClusterId .. "': " .. socket.Id)
		else
			if not cluster.TargetEligible then
				warnMsg("Socket in non-eligible cluster: " .. socket.Id)
			else
				validSockets += 1
			end
			local half = cluster.Volume.Size / 2 + Vector3.new(1, 2, 1)
			local lp = cluster.Volume.CFrame:PointToObjectSpace(socket.Part.Position)
			if math.abs(lp.X) > half.X or math.abs(lp.Y) > half.Y or math.abs(lp.Z) > half.Z then
				warnMsg("Socket lies outside its cluster volume: " .. socket.Id)
			end
		end
		if socket.RegionId == "" then
			warnMsg("Socket missing RegionId: " .. socket.Id)
		end
	end
	if validSockets < minSockets then
		err(string.format("Only %d valid target sockets (minimum %d)", validSockets, minSockets))
	end

	local total = 0
	for _, cluster in ipairs(runtime.ClusterList) do
		total += cluster.MaxMess
	end
	if total > 0 and (total < SANE_MESS_MIN or total > SANE_MESS_MAX) then
		err(string.format("Total mess %d outside sane range [%d, %d]", total, SANE_MESS_MIN, SANE_MESS_MAX))
	end

	if #runtime.Regions == 0 then
		local count = 0
		for _ in pairs(runtime.Regions) do
			count += 1
		end
		if count == 0 then
			warnMsg("No SearchRegion volumes found; 75% hint highlight will have nothing to show")
		end
	end

	local ServerStorage = game:GetService("ServerStorage")
	local targets = ServerStorage:FindFirstChild("Targets")
	if not (targets and targets:FindFirstChild(config.TargetId)) then
		warnMsg("No final target model at ServerStorage.Targets." .. config.TargetId .. " (placeholder in use)")
	end

	local lines = {
		string.format("=== ROOM VALIDATION: %s (%s) ===", config.Name, config.DisplayNumber),
		string.format("Clusters: %d | Eligible: %d | Sockets: %d valid / %d | Regions: %d | Total mess: %d",
			#runtime.ClusterList, eligibleCount, validSockets, #runtime.SocketList,
			(function()
				local n = 0
				for _ in pairs(runtime.Regions) do
					n += 1
				end
				return n
			end)(), total),
	}
	if #errors == 0 then
		table.insert(lines, "RESULT: PASS")
	else
		table.insert(lines, string.format("RESULT: FAIL (%d errors)", #errors))
	end
	for _, e in ipairs(errors) do
		table.insert(lines, "  [ERROR] " .. e)
	end
	for _, w in ipairs(warnings) do
		table.insert(lines, "  [WARN]  " .. w)
	end
	return #errors == 0, table.concat(lines, "\n")
end

return RoomValidator
