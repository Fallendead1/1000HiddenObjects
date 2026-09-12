local RobloxAnalytics = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")

local AnalyticsService = {}

function AnalyticsService.Log(eventName: string, player: Player?, params: { [string]: any }?)
	if RunService:IsStudio() then
		local parts = {}
		if params then
			for k, v in pairs(params) do
				table.insert(parts, k .. "=" .. tostring(v))
			end
		end
		print(string.format("[Analytics] %s %s %s", eventName, player and player.Name or "-", table.concat(parts, " ")))
		return
	end
	if not player then
		return
	end
	pcall(function()
		local value = params and params.Value or 1
		RobloxAnalytics:LogCustomEvent(player, eventName, value, params)
	end)
end

return AnalyticsService
