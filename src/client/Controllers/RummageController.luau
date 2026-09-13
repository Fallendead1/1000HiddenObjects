--[[
	Procedural rummaging animation. No animation assets required: while a player is searching
	(replicated IsSearching attribute) their arms reach forward and alternate digging motions
	and the torso leans in. Works for R15 and R6, for the local player and teammates.

	The pose is layered onto each joint's Transform right after the Animator writes it
	(PreSimulation), so it blends with walk/idle animations. C0 is never touched: with
	Roblox's avatar joint upgrade, Motor6D.C0 is read-only and joints may be
	AnimationConstraints instead of Motor6Ds; both expose a writable Transform.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Controllers = require(script.Parent)

local player = Players.LocalPlayer

local RummageController = {}

type Joint = { Instance: Instance, Kind: string, Base: CFrame?, Written: CFrame? }
type Tracked = { Player: Player, Character: Model, Joints: { Joint }, Weight: number, Phase: number }

local tracked: { [Player]: Tracked } = {}

local R15 = { RightShoulder = "R", LeftShoulder = "L", Waist = "Waist" }
local R6 = { ["Right Shoulder"] = "R6R", ["Left Shoulder"] = "R6L" }

local function isActiveJoint(inst: Instance): boolean
	if inst:IsA("AnimationConstraint") then
		return inst.Enabled
	end
	if inst:IsA("Motor6D") then
		return inst.Enabled
	end
	return false
end

-- Prefer an enabled AnimationConstraint (joint upgrade), else an enabled Motor6D.
local function collectJoints(character: Model): { Joint }
	local found: { [string]: Instance } = {}
	for _, d in ipairs(character:GetDescendants()) do
		local kind = R15[d.Name] or R6[d.Name]
		if kind and isActiveJoint(d) then
			local existing = found[kind]
			if not existing or (d:IsA("AnimationConstraint") and not existing:IsA("AnimationConstraint")) then
				found[kind] = d
			end
		end
	end
	local joints = {}
	for kind, inst in pairs(found) do
		table.insert(joints, { Instance = inst, Kind = kind })
	end
	return joints
end

local function track(p: Player, character: Model)
	tracked[p] = { Player = p, Character = character, Joints = {}, Weight = 0, Phase = math.random() * 10 }
end

local function untrack(p: Player)
	tracked[p] = nil
end

local function offsetFor(kind: string, ph: number): CFrame
	if kind == "R" then
		return CFrame.Angles(math.rad(70 + math.sin(ph) * 25), 0, math.rad(-15))
	elseif kind == "L" then
		return CFrame.Angles(math.rad(70 + math.sin(ph + math.pi) * 25), 0, math.rad(15))
	elseif kind == "Waist" then
		return CFrame.Angles(math.rad(-14 + math.sin(ph * 0.5) * 3), 0, 0)
	elseif kind == "R6R" then
		return CFrame.Angles(0, 0, math.rad(80 + math.sin(ph) * 25))
	elseif kind == "R6L" then
		return CFrame.Angles(0, 0, math.rad(-80 - math.sin(ph + math.pi) * 25))
	end
	return CFrame.identity
end

local function nearlyEqual(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-4 and a.LookVector:Dot(b.LookVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function applyPose(t: Tracked, now: number)
	local ph = now * 9 + t.Phase
	for _, j in ipairs(t.Joints) do
		local joint = j.Instance :: any
		if joint.Parent then
			local current: CFrame = joint.Transform
			-- If nothing overwrote our last write (no animation on this joint), reuse the
			-- stored base so the offset never accumulates frame over frame.
			local base = (j.Written and nearlyEqual(current, j.Written) and j.Base) or current
			if t.Weight <= 0.001 then
				if j.Written then
					joint.Transform = base
					j.Written, j.Base = nil, nil
				end
			else
				local written = base * CFrame.identity:Lerp(offsetFor(j.Kind, ph), t.Weight)
				joint.Transform = written
				j.Base, j.Written = base, written
			end
		end
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
	RunService.PreSimulation:Connect(function(dt)
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
			local target = p:GetAttribute("IsSearching") == true and 1 or 0
			if target > t.Weight then
				t.Weight = math.min(1, t.Weight + dt * 6)
			elseif target < t.Weight then
				t.Weight = math.max(0, t.Weight - dt * 5)
			end
			-- At zero weight this restores the last base once, then no-ops.
			applyPose(t, now)
		end

		if player:GetAttribute("IsSearching") and tracked[player] then
			Controllers.AudioController.PlayLoop("SearchLoop")
		else
			Controllers.AudioController.StopLoop("SearchLoop")
		end
	end)
end

return RummageController
