local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)
local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local SettingsController = {}

local menu
local toggles = {}
local keys = {
	{ Key = "Music", Label = "Music" },
	{ Key = "SFX", Label = "Sound Effects" },
	{ Key = "ReduceVFX", Label = "Reduce VFX" },
	{ Key = "CameraShake", Label = "Camera Shake" },
}

local function current(key: string): boolean
	local v = player:GetAttribute("Setting_" .. key)
	if v == nil then
		return key ~= "ReduceVFX"
	end
	return v
end

local function push()
	local payload = {}
	for _, def in ipairs(keys) do
		payload[def.Key] = current(def.Key)
	end
	Remotes.Event("UpdateSettings"):FireServer(payload)
end

function SettingsController.Init()
	menu = UI.Menu("Settings", "SETTINGS", UDim2.fromOffset(420, 360), UI.Colors.Locked)
	local list = UI.Frame({ BackgroundTransparency = 1 }, menu.Content)
	UI.ListLayout(list, Enum.FillDirection.Vertical, 6)
	UI.Padding(list, 8)
	for _, def in ipairs(keys) do
		toggles[def.Key] = UI.Toggle(list, def.Label, current(def.Key), function(value)
			-- Optimistic local apply; server persists and re-replicates.
			player:SetAttribute("Setting_" .. def.Key, value)
			push()
		end)
		player:GetAttributeChangedSignal("Setting_" .. def.Key):Connect(function()
			toggles[def.Key].Set(current(def.Key))
		end)
	end
end

function SettingsController.Open()
	menu.Open()
end

function SettingsController.Get(key: string): boolean
	return current(key)
end

return SettingsController
