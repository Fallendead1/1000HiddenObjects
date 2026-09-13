--[[
	Remote registry. The server creates every remote listed here inside
	ReplicatedStorage.Remotes at boot; the client waits for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {
	Events = {
		"GrabObject", -- C->S (clutter root part, requestId)
		"GrabResult", -- S->C (requestId, ok, objectId?, reason?)
		"ThrowObject", -- C->S (objectId, aim direction Vector3)
		"DropObject", -- C->S (objectId?)
		"RequestHint", -- C->S (kind: "Free" | "Quick" | "Super")
		"RequestPurchase", -- C->S (productKey)
		"ReturnToLobby", -- C->S
		"SelectRoom", -- C->S (queueId, roomId) queue owner picks the room
		"UpdateSettings", -- C->S (settingsTable)
		"TutorialComplete", -- C->S
		"DiscardCheckpoint", -- C->S
		"DevCommand", -- C->S (command, ...)
		"MatchUpdate", -- S->C (eventName, payload)
		"Notification", -- S->C (kind, text, duration?)
		"PurchaseUpdate", -- S->C (kind, payload)
		"FXEvent", -- S->C (fxName, payload)
		"QueueUpdate", -- S->C (payload)
	},
	Functions = {
		"RequestUpgrade", -- C->S (upgradeKey) -> ok, message
		"GetShopInfo", -- C->S () -> list of products with live prices
		"GetLeaderboards", -- C->S () -> { TopFinders = {...}, Fastest = {...} }
	},
}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = "Remotes"
			existing.Parent = ReplicatedStorage
		end
		folder = existing :: Folder
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder :: Folder
end

function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init is server-only")
	local f = getFolder()
	for _, name in ipairs(Remotes.Events) do
		if not f:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = f
		end
	end
	for _, name in ipairs(Remotes.Functions) do
		if not f:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = f
		end
	end
end

function Remotes.Event(name: string): RemoteEvent
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	local f = getFolder()
	if RunService:IsServer() then
		return f:FindFirstChild(name) :: RemoteFunction
	end
	return f:WaitForChild(name) :: RemoteFunction
end

return Remotes
