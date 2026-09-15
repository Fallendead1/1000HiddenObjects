--[[
	The lobby's look (LightingConfig.Lobby): while the local player is in the lobby, their Lighting
	gets the painted sky, haze, glow and soft shadows; in a room the place's own Lighting (what
	Studio saves) comes back. Client-only, so it's right per player even in Studio, where the lobby
	and a room share one server; the Match Server place never shows the lobby look. The switch is
	instant: moving between lobby and room happens behind the loading fade.
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local LightingConfig = require(Shared.Config.LightingConfig)

local player = Players.LocalPlayer

local LightingController = {}

-- The Lighting children a look is made of (the UI's blur and depth of field stay as they are).
local MANAGED = { Sky = true, Atmosphere = true, BloomEffect = true, ColorCorrectionEffect = true, SunRaysEffect = true }

local roomProps: { [string]: any } = {}
local roomChildren: { Instance } = {}
local lobbyChildren: { Instance } = {}
local lobbySky: Sky
local lobbyBloom: BloomEffect
local lobbyRays: SunRaysEffect
local inLobby: boolean? = nil

local function build(className: string, props: { [string]: any }): Instance
	local inst = Instance.new(className)
	inst.Name = "Lobby" .. className
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	table.insert(lobbyChildren, inst)
	return inst
end

local function wantLobby(): boolean
	return game.PlaceId ~= GameConfig.MatchPlaceId and player:GetAttribute("InMatch") ~= true
end

-- Reduce VFX: no glow, no rays, no drifting clouds.
local function applyVfx()
	local reduced = player:GetAttribute("Setting_ReduceVFX") == true
	lobbyBloom.Intensity = if reduced then 0 else LightingConfig.Lobby.Bloom.Intensity
	lobbyRays.Intensity = if reduced then 0 else LightingConfig.Lobby.SunRays.Intensity
end

local function apply()
	local lobby = wantLobby()
	if lobby == inLobby then
		return
	end
	inLobby = lobby
	for _, child in ipairs(roomChildren) do
		child.Parent = if lobby then nil else Lighting
	end
	for _, child in ipairs(lobbyChildren) do
		child.Parent = if lobby then Lighting else nil
	end
	for key, value in pairs(if lobby then LightingConfig.Lobby.Lighting else roomProps) do
		(Lighting :: any)[key] = value
	end
end

function LightingController.Init()
	local look = LightingConfig.Lobby
	lobbySky = build("Sky", look.Sky) :: Sky
	build("Atmosphere", look.Atmosphere)
	lobbyBloom = build("BloomEffect", look.Bloom) :: BloomEffect
	build("ColorCorrectionEffect", look.ColorCorrection)
	lobbyRays = build("SunRaysEffect", look.SunRays) :: SunRaysEffect
	applyVfx()
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { lobbySky })
	end)
end

function LightingController.Start()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	-- The rooms' look is whatever the place saved: remember it before changing anything.
	for key in pairs(LightingConfig.Lobby.Lighting) do
		roomProps[key] = (Lighting :: any)[key]
	end
	for _, child in ipairs(Lighting:GetChildren()) do
		if MANAGED[child.ClassName] then
			table.insert(roomChildren, child)
		end
	end
	apply()
	player:GetAttributeChangedSignal("InMatch"):Connect(apply)
	player:GetAttributeChangedSignal("Setting_ReduceVFX"):Connect(applyVfx)

	-- The painted clouds drift slowly around the lobby.
	RunService.Heartbeat:Connect(function()
		if inLobby and player:GetAttribute("Setting_ReduceVFX") ~= true then
			lobbySky.SkyboxOrientation = Vector3.new(0, (os.clock() * LightingConfig.Lobby.DriftDegreesPerSecond) % 360, 0)
		end
	end)
end

return LightingController
