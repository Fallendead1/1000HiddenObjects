--[[
	Room registry. Adding Room #002 = drop Room002.luau next to Room001.luau and add it here.
]]

local Rooms = {
	[1] = require(script.Room001),
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
