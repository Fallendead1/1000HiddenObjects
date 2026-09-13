--[[
	Client bootstrap. Waits for remotes, then initialises and starts every controller.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")
ReplicatedStorage:WaitForChild("MatchState")
ReplicatedStorage:WaitForChild("ServerInfo")

if not player:GetAttribute("DataLoaded") then
	local conn
	local loaded = false
	conn = player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
		loaded = true
	end)
	local deadline = os.clock() + 15
	while not loaded and not player:GetAttribute("DataLoaded") and os.clock() < deadline do
		task.wait(0.1)
	end
	conn:Disconnect()
end

local Controllers = script.Controllers

local order = {
	"AudioController",
	"NotificationController",
	"HUDController",
	"ClutterVisualController",
	"SearchController",
	"RummageController",
	"UpgradeController",
	"ShopController",
	"CollectionController",
	"SettingsController",
	"HintController",
	"FXController",
	"LoadingController",
	"ResultsController",
	"TutorialController",
	"LobbyController",
	"RoomSelectController",
	"DevPanelController",
}

local loaded = {}
for _, name in ipairs(order) do
	local module = Controllers:FindFirstChild(name)
	if module then
		local ok, controller = pcall(require, module)
		if ok then
			loaded[name] = controller
			if controller.Init then
				local okInit, err = pcall(controller.Init)
				if not okInit then
					warn("[Client] Init failed for", name, err)
				end
			end
		else
			warn("[Client] Failed to require", name, controller)
		end
	end
end

for _, name in ipairs(order) do
	local controller = loaded[name]
	if controller and controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start)
			if not ok then
				warn("[Client] Start failed for", name, err)
			end
		end)
	end
end
