-- Lazy controller accessor (mirrors the server Services registry).
local Controllers = {}

setmetatable(Controllers, {
	__index = function(t, name: string)
		local child = script:FindFirstChild(name)
		if not child then
			error(string.format("Unknown controller '%s'", name))
		end
		local module = require(child)
		rawset(t, name, module)
		return module
	end,
})

return Controllers
