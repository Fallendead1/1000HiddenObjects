local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local AudioController = {}

local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local sounds: { [string]: Sound } = {}
local currentMusic: Sound? = nil
local currentMusicKey: string? = nil

local function sfxEnabled(): boolean
	return player:GetAttribute("Setting_SFX") ~= false
end

local function musicEnabled(): boolean
	return player:GetAttribute("Setting_Music") ~= false
end

local function applyVolumes()
	sfxGroup.Volume = sfxEnabled() and 1 or 0
	musicGroup.Volume = musicEnabled() and 1 or 0
end

function AudioController.Init()
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFX"
	sfxGroup.Parent = SoundService
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "Music"
	musicGroup.Parent = SoundService

	for key, def in pairs(AudioConfig.SFX) do
		if def.Id and def.Id ~= 0 then
			local s = Instance.new("Sound")
			s.Name = key
			s.SoundId = "rbxassetid://" .. def.Id
			s.Volume = def.Volume or 0.5
			s.SoundGroup = sfxGroup
			s.Parent = SoundService
			sounds[key] = s
		end
	end

	player:GetAttributeChangedSignal("Setting_SFX"):Connect(applyVolumes)
	player:GetAttributeChangedSignal("Setting_Music"):Connect(applyVolumes)
	applyVolumes()

	UI.SetClickSound(AudioController.Play)
end

function AudioController.Play(key: string)
	local s = sounds[key]
	if s and sfxEnabled() then
		local clone = s:Clone()
		clone.Parent = SoundService
		clone:Play()
		clone.Ended:Once(function()
			clone:Destroy()
		end)
	end
end

function AudioController.PlayAt(key: string, position: Vector3)
	local s = sounds[key]
	if s and sfxEnabled() then
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = position
		anchor.Parent = workspace.Terrain
		local clone = s:Clone()
		clone.Parent = anchor
		clone:Play()
		clone.Ended:Once(function()
			anchor:Destroy()
		end)
	end
end

function AudioController.SetMusic(key: string?)
	if currentMusicKey == key then
		return
	end
	if currentMusic then
		currentMusic:Stop()
		currentMusic:Destroy()
		currentMusic = nil
	end
	currentMusicKey = key
	if not key then
		return
	end
	local def = AudioConfig.Music[key]
	if not def or def.Id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = "rbxassetid://" .. def.Id
	s.Volume = def.Volume or 0.3
	s.Looped = def.Looped ~= false
	s.SoundGroup = musicGroup
	s.Parent = SoundService
	s:Play()
	currentMusic = s
end

return AudioController
