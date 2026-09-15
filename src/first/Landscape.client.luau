--[[
	Runs before anything else in the game loads: phones go straight to landscape (the sensor picks
	which way round). StarterGui starts everyone in landscape as well (default.project.json), and
	UI.luau holds it there afterwards.
]]

local Players = game:GetService("Players")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
pcall(function()
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end)
