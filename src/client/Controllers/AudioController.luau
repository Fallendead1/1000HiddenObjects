local ContentProvider = game:GetService("ContentProvider")
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

-- A final numeric id in AudioConfig wins; otherwise a Studio override
-- (SoundService.GameSounds.<Key>) replaces the placeholder.
local function pickSound(key: string, def): (string?, number?)
	local final = def ~= nil and type(def.Id) == "number" and def.Id ~= 0
	if not final then
		local overrides = SoundService:FindFirstChild("GameSounds")
		local override = overrides and overrides:FindFirstChild(key)
		if override and override:IsA("Sound") and override.SoundId ~= "" then
			return override.SoundId, override.Volume
		end
	end
	return def and resolveId(def.Id), def and def.Volume
end

-- The Studio sound to use when a final asset can't load (for example its audio permission
-- isn't granted to this experience yet): the key's own override, or its Fallback key's.
local function fallbackSound(key: string, def): string?
	local overrides = SoundService:FindFirstChild("GameSounds")
	for _, k in ipairs({ key, def and def.Fallback }) do
		local override = k and overrides and overrides:FindFirstChild(k)
		if override and override:IsA("Sound") and override.SoundId ~= "" then
			return override.SoundId
		end
	end
	return nil
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

	for key, def in pairs(AudioConfig.SFX) do
		local id, volume = pickSound(key, def)
		if id then
			local s = Instance.new("Sound")
			s.Name = key
			s.SoundId = id
			s.Volume = volume or 0.5
			s.Looped = def.Looped == true
			s.SoundGroup = sfxGroup
			s:SetAttribute("Pitch", type(def.Pitch) == "table" and 0 or (def.Pitch or 1))
			s.Parent = SoundService
			templates[key] = s
			if type(def.Id) == "number" then
				task.spawn(function()
					ContentProvider:PreloadAsync({ s }, function(_, status)
						local fallback = status == Enum.AssetFetchStatus.Failure and fallbackSound(key, def)
						if fallback then
							warn(string.format("[Audio] %s (%s) could not load - using the Studio sound instead. Check that audio's permissions allow this experience.", key, id))
							s.SoundId = fallback
						end
					end)
				end)
			end
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
	local def = key and AudioConfig.Music[key]
	local id, volume
	if key then
		id, volume = pickSound(key, def)
	end
	-- The lobby and the rooms share one track: keep it playing instead of restarting it.
	if currentMusic and id and currentMusic.SoundId == id then
		currentMusicKey = key
		currentMusic.Volume = volume or currentMusic.Volume
		return
	end
	if currentMusic then
		currentMusic:Stop()
		currentMusic:Destroy()
		currentMusic = nil
	end
	currentMusicKey = key
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id
	s.Volume = volume or 0.3
	s.Looped = not def or def.Looped ~= false
	s.SoundGroup = musicGroup
	s.Parent = SoundService
	s:Play()
	currentMusic = s
end

return AudioController
