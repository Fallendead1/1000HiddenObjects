--[[
	The client's part of analytics (the server does all the tracking): it reports the UI-only
	moments over the Track remote. Menus opened (UI.OnMenuOpen), shop tabs and invites come from
	their controllers through Track(); the average frame rate goes out every couple of minutes with
	the device type, so slow phones show up in the numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local Shared = ReplicatedStorage.Shared
local AnalyticsConfig = require(Shared.Config.AnalyticsConfig)
local Remotes = require(Shared.Utility.Remotes)

local UI = require(script.Parent.Parent.UI.UI)

local AnalyticsController = {}

local function device(): string
	if VRService.VREnabled then
		return "vr"
	elseif UI.IsTouch() then
		return "touch"
	elseif UI.IsGamepad() then
		return "gamepad"
	end
	return "desktop"
end

function AnalyticsController.Track(kind: string, value: any?)
	Remotes.Event("Track"):FireServer(kind, value)
end

function AnalyticsController.Init()
	UI.OnMenuOpen = function(name: string)
		AnalyticsController.Track("menu", name)
	end
end

function AnalyticsController.Start()
	local frames, since = 0, os.clock()
	RunService.RenderStepped:Connect(function()
		frames += 1
	end)
	for _ = 1, AnalyticsConfig.FpsReportsPerSession do
		task.wait(AnalyticsConfig.FpsReportSeconds)
		local now = os.clock()
		local fps = frames / math.max(1, now - since)
		frames, since = 0, now
		Remotes.Event("Track"):FireServer("fps", fps, device())
	end
end

return AnalyticsController
