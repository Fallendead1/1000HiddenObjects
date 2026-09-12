--[[
	Procedural rummaging animation. No animation assets required: while a player is searching
	(replicated IsSearching attribute) their arms reach forward and alternate digging motions
	and the torso leans in. Works for R15 and R6, for the local player and teammates.
	Also drives the local rummage loop sound.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local RummageController = {}

type Tracked = {
	Player: Player,
	Character: Model,
	Joints: { { Motor: Motor6D, Base: CFrame, Kind: string } },
	Weight: number,
	Phase: number,
}

local tracked: { [Player]: Tracked } = {}

local function collectJoints(character: Model)
	local joints = {}
	local function add(motor: Instance?, kind: string)
		if motor and motor:IsA("Motor6D") then
			table.insert(joints, { Motor = motor, Base = motor.C0, Kind = kind })
		end
	end
	local rua = character:FindFirstChild("RightUpperArm")
	local lua = character:FindFirstChild("LeftUpperArm")
	local ut = character:FindFirstChild("UpperTorso")
	if rua then
		add(rua:FindFirstChild("RightShoulder"), "R")
		add(lua and lua:FindFirstChild("LeftShoulder"), "L")
		add(ut and ut:FindFirstChild("Waist"), "Waist")
	else
		local torso = character:FindFirstChild("Torso")
		if torso then
			add(torso:FindFirstChild("Right Shoulder"), "R6R")
			add(torso:FindFirstChild("Left Shoulder"), "R6L")
		end
	end
	return joints
end

local function track(p: Player, character: Model)
	task.defer(function()
		if not character.Parent then
			return
		end
		tracked[p] = { Player = p, Character = character, Joints = collectJoints(character), Weight = 0, Phase = math.random() * 10 }
	end)
end

local function untrack(p: Player)
	local t = tracked[p]
	if t then
		for _, j in ipairs(t.Joints) do
			if j.Motor.Parent then
				j.Motor.C0 = j.Base
			end
		end
		tracked[p] = nil
	end
end

local function pose(t: Tracked, now: number)
	local w = t.Weight
	local ph = now * 9 + t.Phase
	for _, j in ipairs(t.Joints) do
		local offset
		if j.Kind == "R" then
			offset = CFrame.Angles(math.rad(-70 + math.sin(ph) * 25), 0, math.rad(-15))
		elseif j.Kind == "L" then
			offset = CFrame.Angles(math.rad(-70 + math.sin(ph + math.pi) * 25), 0, math.rad(15))
		elseif j.Kind == "Waist" then
			offset = CFrame.Angles(math.rad(-14 + math.sin(ph * 0.5) * 3), 0, 0)
		elseif j.Kind == "R6R" then
			offset = CFrame.Angles(0, 0, math.rad(80 + math.sin(ph) * 25))
		elseif j.Kind == "R6L" then
			offset = CFrame.Angles(0, 0, math.rad(-80 - math.sin(ph + math.pi) * 25))
		else
			offset = CFrame.new()
		end
		j.Motor.C0 = j.Base:Lerp(j.Base * offset, w)
	end
end

function RummageController.Init()
	local function onPlayer(p: Player)
		if p.Character then
			track(p, p.Character)
		end
		p.CharacterAdded:Connect(function(c)
			track(p, c)
		end)
		p.CharacterRemoving:Connect(function()
			untrack(p)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(untrack)
end

function RummageController.Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for p, t in pairs(tracked) do
			if not t.Character.Parent then
				tracked[p] = nil
				continue
			end
			if #t.Joints == 0 then
				-- Limbs/joints can arrive a few frames after CharacterAdded.
				t.Joints = collectJoints(t.Character)
				if #t.Joints == 0 then
					continue
				end
			end
			local searching = p:GetAttribute("IsSearching") == true
			local target = searching and 1 or 0
			if t.Weight ~= target then
				t.Weight = target > t.Weight and math.min(target, t.Weight + dt * 6) or math.max(target, t.Weight - dt * 5)
				pose(t, now)
			elseif searching then
				pose(t, now)
			end
		end
		local me = tracked[player]
		if me and player:GetAttribute("IsSearching") then
			Controllers.AudioController.PlayLoop("SearchLoop")
		else
			Controllers.AudioController.StopLoop("SearchLoop")
		end
	end)
end

return RummageController
