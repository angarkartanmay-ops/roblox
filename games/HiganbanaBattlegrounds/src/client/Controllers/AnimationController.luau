--!strict
-- Procedural animation for every character this client sees. Runs in PreSimulation, after the
-- engine's Animator step, layering: NPC walk cycle -> fighter idle stance (upper body only, the legs
-- stay with the walk) -> held state (drained, stunned, guard broken, guarding, mending) -> move
-- sequence. Every client animates every fighter from the same server events, so nothing uploads.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Poses = require(ReplicatedStorage.Shared.Poses)
local Types = require(ReplicatedStorage.Shared.Types)
local Rig = require("../Lib/Rig")

type Sequence = Types.Sequence
type CompiledPose = { [string]: CFrame }
type Track = { sequence: Sequence, start: number }

local AnimationController = {}

local IDENTITY = CFrame.new()
local compiled: { [string]: CompiledPose } = {}
local tracks: { [Model]: Track } = {}
local rigs: { [Model]: Rig.RigInfo } = {}
local heldWeight: { [Model]: number } = {}
local heldName: { [Model]: string } = {}
local walkPhase: { [Model]: number } = {}

-- Joints an upper-body sequence (the idles) leaves to the walk cycle.
local LOWER: { [string]: boolean } = { Root = true, RightHip = true, RightKnee = true, LeftHip = true, LeftKnee = true }

-- Held states in priority order: attribute on the model -> pose name.
local HELD_ORDER: { { attribute: string, pose: string } } = {
	{ attribute = "Grabbed", pose = Poses.HELD.Grabbed },
	{ attribute = "Stunned", pose = Poses.HELD.Stunned },
	{ attribute = "GuardBroken", pose = "GuardBroken" },
	{ attribute = "Blocking", pose = Poses.HELD.Blocking },
	{ attribute = "Mending", pose = Poses.HELD.Mending },
}

local function compile(pose: Types.Pose): CompiledPose
	local result: CompiledPose = {}
	for joint, value in pose do
		result[joint] = CFrame.new(value.px or 0, value.py or 0, value.pz or 0)
			* CFrame.Angles(math.rad(value.rx or 0), math.rad(value.ry or 0), math.rad(value.rz or 0))
	end
	return result
end

local function forget(model: Model)
	rigs[model] = nil
	tracks[model] = nil
	heldWeight[model] = nil
	heldName[model] = nil
	walkPhase[model] = nil
end

local function rigFor(model: Model): Rig.RigInfo?
	local cached = rigs[model]
	if cached then
		return cached
	end
	local built = Rig.build(model)
	if built and Rig.jointCount(built) >= 5 then
		rigs[model] = built
		model.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				forget(model)
			end
		end)
		return built
	end
	return nil
end

local function easeOut(alpha: number): number
	return 1 - (1 - alpha) * (1 - alpha)
end

local function evaluate(sequence: Sequence, t: number): CompiledPose
	local keys = sequence.keys
	local a = keys[1]
	local b = keys[#keys]
	if t >= b.t then
		a = b
	else
		for index = 1, #keys - 1 do
			if t < keys[index + 1].t then
				a = keys[index]
				b = keys[index + 1]
				break
			end
		end
	end
	local span = b.t - a.t
	local alpha = if span > 1e-4 then easeOut(math.clamp((t - a.t) / span, 0, 1)) else 1
	local poseA: CompiledPose = compiled[a.pose] or {}
	local poseB: CompiledPose = compiled[b.pose] or {}
	local result: CompiledPose = {}
	for joint, value in poseA do
		local target = poseB[joint]
		result[joint] = value:Lerp(if target then target else IDENTITY, alpha)
	end
	for joint, value in poseB do
		if not poseA[joint] then
			result[joint] = IDENTITY:Lerp(value, alpha)
		end
	end
	return result
end

local function envelope(sequence: Sequence, t: number): number
	local fadeIn = if sequence.fadeIn > 0 then math.clamp(t / sequence.fadeIn, 0, 1) else 1
	local fadeOut = if sequence.fadeOut > 0 then math.clamp((sequence.duration - t) / sequence.fadeOut, 0, 1) else 1
	return fadeIn * fadeOut
end

local function walkCycle(model: Model, dt: number): CompiledPose
	local root = model:FindFirstChild("HumanoidRootPart")
	local scale = model:GetScale()
	local speed = 0
	if root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end
	local amount = math.clamp(speed / (8 * scale), 0, 1)
	local phase = (walkPhase[model] or 0) + dt * speed / (2.4 * scale)
	walkPhase[model] = phase
	local swing = math.sin(phase * math.pi) * 38 * amount
	local breathe = math.sin(os.clock() * 2.2) * 2.5
	return {
		RightHip = CFrame.Angles(math.rad(swing), 0, 0),
		LeftHip = CFrame.Angles(math.rad(-swing), 0, 0),
		RightKnee = CFrame.Angles(math.rad(-math.max(0, -swing) * 0.9), 0, 0),
		LeftKnee = CFrame.Angles(math.rad(-math.max(0, swing) * 0.9), 0, 0),
		RightShoulder = CFrame.Angles(math.rad(-swing * 0.7), 0, math.rad(6)),
		LeftShoulder = CFrame.Angles(math.rad(swing * 0.7), 0, math.rad(-6)),
		Waist = CFrame.Angles(math.rad(breathe - 5 * amount), 0, 0),
		Neck = CFrame.Angles(math.rad(-breathe * 0.5), 0, 0),
	}
end

local function heldState(model: Model): string?
	for _, entry in HELD_ORDER do
		if model:GetAttribute(entry.attribute) == true then
			return entry.pose
		end
	end
	return nil
end

local function upperOnly(pose: CompiledPose): CompiledPose
	local result: CompiledPose = {}
	for joint, value in pose do
		if not LOWER[joint] then
			result[joint] = value
		end
	end
	return result
end

-- The fighter's idle stance, looped on the local clock (it only has to look alive, not agree).
local function idleFor(model: Model): (CompiledPose?, Sequence?)
	local fighterId = model:GetAttribute("Fighter")
	if type(fighterId) ~= "string" then
		return nil, nil
	end
	local sequence = Poses.SEQUENCES[Poses.idleSequence(fighterId)]
	if not sequence then
		return nil, nil
	end
	local t = if sequence.duration > 0 then os.clock() % sequence.duration else 0
	local pose = evaluate(sequence, t)
	return if sequence.upper then upperOnly(pose) else pose, sequence
end

local function step(dt: number)
	local now = Workspace:GetServerTimeNow()
	for model, track in tracks do
		if model.Parent == nil or now - track.start > track.sequence.duration then
			tracks[model] = nil
		end
	end

	local models: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			models[character] = true
		end
	end
	for _, tagged in CollectionService:GetTagged("Npc") do
		if tagged:IsA("Model") then
			models[tagged] = true
		end
	end

	for model in models do
		local rig = rigFor(model)
		if not rig then
			continue
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		if model:HasTag("Npc") then
			Rig.reset(rig)
			Rig.apply(rig, walkCycle(model, dt), 1)
		end

		local track = tracks[model]
		local held = heldState(model)
		if not track and not held then
			local idle = idleFor(model)
			if idle then
				Rig.apply(rig, idle, 1)
			end
		end

		if held then
			heldName[model] = held
		end
		local weight = heldWeight[model] or 0
		weight += ((if held then 1 else 0) - weight) * math.min(1, dt * 14)
		heldWeight[model] = weight
		local heldPose = heldName[model]
		if weight > 0.01 and heldPose then
			local pose = compiled[heldPose]
			if pose then
				Rig.apply(rig, pose, weight)
			end
		end

		if track then
			local t = math.max(0, now - track.start)
			local pose = evaluate(track.sequence, t)
			Rig.apply(rig, if track.sequence.upper then upperOnly(pose) else pose, envelope(track.sequence, t))
		end
	end
end

-- Play a sequence on a model, timed from `startTime` (server clock) so every client agrees.
function AnimationController.play(model: Model, sequenceId: string, startTime: number?)
	local sequence = Poses.SEQUENCES[sequenceId]
	if not sequence then
		return
	end
	tracks[model] = { sequence = sequence, start = startTime or Workspace:GetServerTimeNow() }
end

-- A short flinch, unless the model is in the middle of its own move.
function AnimationController.hurt(model: Model)
	if tracks[model] == nil then
		AnimationController.play(model, "Hurt")
	end
end

function AnimationController.stop(model: Model)
	tracks[model] = nil
end

-- True while a move sequence is playing on the model.
function AnimationController.isPlaying(model: Model): boolean
	return tracks[model] ~= nil
end

function AnimationController.init(_self: any)
	for name, pose in Poses.POSES do
		compiled[name] = compile(pose)
	end
end

function AnimationController.start(_self: any)
	RunService.PreSimulation:Connect(step)
end

return AnimationController
