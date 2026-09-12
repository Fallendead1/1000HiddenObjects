--[[
	Lazy service accessor. `Services.MatchService` requires the module on first access,
	which lets services reference each other without top-level require cycles.
]]

local Services = {}

setmetatable(Services, {
	__index = function(t, name: string)
		local child = script:FindFirstChild(name)
		if not child then
			error(string.format("Unknown service '%s'", name))
		end
		local module = require(child)
		rawset(t, name, module)
		return module
	end,
})

return Services
