local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local AudioController = {}

local sfxGroup: SoundGroup
local musicGroup: SoundGroup
local templates: { [string]: Sound } = {}
local loops: { [string]: Sound } = {}
local currentMusic: Sound? = nil
local currentMusicKey: string? = nil
local rng = Random.new()

local function resolveId(id: any): string?
	if type(id) == "number" then
		return id ~= 0 and ("rbxassetid://" .. id) or nil
	elseif type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function resolvePitch(pitch: any): number
	if type(pitch) == "table" then
		return rng:NextNumber(pitch[1], pitch[2])
	end
	return tonumber(pitch) or 1
end

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

	-- Studio overrides: SoundService.GameSounds.<Key> (a Sound) replaces the config placeholder.
	local overrides = SoundService:FindFirstChild("GameSounds")
	for key, def in pairs(AudioConfig.SFX) do
		local override = overrides and overrides:FindFirstChild(key)
		local id = (override and override:IsA("Sound") and override.SoundId ~= "") and override.SoundId or resolveId(def.Id)
		if id then
			local s = Instance.new("Sound")
			s.Name = key
			s.SoundId = id
			s.Volume = (override and override:IsA("Sound")) and override.Volume or def.Volume or 0.5
			s.Looped = def.Looped == true
			s.SoundGroup = sfxGroup
			s:SetAttribute("Pitch", type(def.Pitch) == "table" and 0 or (def.Pitch or 1))
			s.Parent = SoundService
			templates[key] = s
		end
	end

	player:GetAttributeChangedSignal("Setting_SFX"):Connect(applyVolumes)
	player:GetAttributeChangedSignal("Setting_Music"):Connect(applyVolumes)
	applyVolumes()

	UI.SetClickSound(AudioController.Play)
end

local function spawnSound(key: string, parent: Instance): Sound?
	local template = templates[key]
	if not template or not sfxEnabled() then
		return nil
	end
	local def = AudioConfig.SFX[key]
	local clone = template:Clone()
	clone.PlaybackSpeed = resolvePitch(def.Pitch)
	clone.Parent = parent
	return clone
end

function AudioController.Play(key: string)
	local s = spawnSound(key, SoundService)
	if s then
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
		task.delay(6, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
end

function AudioController.PlayAt(key: string, position: Vector3)
	local template = templates[key]
	if not template or not sfxEnabled() then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local s = spawnSound(key, anchor)
	if not s then
		anchor:Destroy()
		return
	end
	s.RollOffMaxDistance = 60
	s:Play()
	s.Ended:Once(function()
		anchor:Destroy()
	end)
	task.delay(6, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- Looping sounds (e.g. rummaging while searching). Safe to call repeatedly.
function AudioController.PlayLoop(key: string)
	if loops[key] then
		return
	end
	local s = spawnSound(key, SoundService)
	if not s then
		return
	end
	s.Looped = true
	s:Play()
	loops[key] = s
end

function AudioController.StopLoop(key: string)
	local s = loops[key]
	if s then
		loops[key] = nil
		UI.Tween(s, { Volume = 0 }, 0.15).Completed:Once(function()
			s:Destroy()
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
	local overrides = SoundService:FindFirstChild("GameSounds")
	local override = overrides and overrides:FindFirstChild(key)
	local useOverride = override ~= nil and override:IsA("Sound") and override.SoundId ~= ""
	local id = useOverride and override.SoundId or (def and resolveId(def.Id))
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id
	s.Volume = useOverride and override.Volume or (def and def.Volume) or 0.3
	s.Looped = def.Looped ~= false
	s.SoundGroup = musicGroup
	s.Parent = SoundService
	s:Play()
	currentMusic = s
end

return AudioController
