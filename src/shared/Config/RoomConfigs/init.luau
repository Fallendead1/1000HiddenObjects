--[[
	Room registry. Adding a room = drop RoomNNN.luau next to Room001.luau and add it here
	(plus its object in Shared.Data.TargetData). Kit.luau holds helpers shared by the configs.
]]

local Rooms = {
	[1] = require(script.Room001),
	[2] = require(script.Room002),
	[3] = require(script.Room003),
	[4] = require(script.Room004),
}

local RoomRegistry = {}

function RoomRegistry.Get(roomId: number)
	return Rooms[roomId]
end

function RoomRegistry.Exists(roomId: number): boolean
	return Rooms[roomId] ~= nil
end

function RoomRegistry.GetHighestAvailable(): number
	local highest = 0
	for id in pairs(Rooms) do
		if id > highest then
			highest = id
		end
	end
	return highest
end

function RoomRegistry.GetAll()
	return Rooms
end

return RoomRegistry
