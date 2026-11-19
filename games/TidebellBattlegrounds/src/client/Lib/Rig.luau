--!strict
-- Finds a character's joints (Motor6D or AnimationConstraint, R15 or R6) and applies poses
-- expressed in the parent part's space. A pose rotation Q becomes Transform = R⁻¹·Q·R, where R is
-- the joint's C0 (or Attachment0) rotation, so the same pose data drives every rig.

local Rig = {}

export type Joint = {
	motor: Motor6D?,
	constraint: AnimationConstraint?,
	rotation: CFrame,
	inverse: CFrame,
}

export type RigInfo = {
	model: Model,
	joints: { [string]: Joint },
	r6: boolean,
}

local R15_NAMES: { [string]: string } = {
	Root = "Root",
	Waist = "Waist",
	Neck = "Neck",
	RightShoulder = "RightShoulder",
	RightElbow = "RightElbow",
	LeftShoulder = "LeftShoulder",
	LeftElbow = "LeftElbow",
	RightHip = "RightHip",
	RightKnee = "RightKnee",
	LeftHip = "LeftHip",
	LeftKnee = "LeftKnee",
}

local R6_NAMES: { [string]: string } = {
	Root = "RootJoint",
	Neck = "Neck",
	RightShoulder = "Right Shoulder",
	LeftShoulder = "Left Shoulder",
	RightHip = "Right Hip",
	LeftHip = "Left Hip",
}

function Rig.build(model: Model): RigInfo?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local names = if r6 then R6_NAMES else R15_NAMES

	local found: { [string]: Instance } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			if found[descendant.Name] == nil then
				found[descendant.Name] = descendant
			end
		end
	end

	local joints: { [string]: Joint } = {}
	for logical, name in names do
		local instance = found[name]
		if instance then
			local frame = CFrame.new()
			local motor: Motor6D? = nil
			local constraint: AnimationConstraint? = nil
			if instance:IsA("Motor6D") then
				motor = instance
				frame = instance.C0
			elseif instance:IsA("AnimationConstraint") then
				constraint = instance
				local attachment = instance.Attachment0
				if attachment then
					frame = attachment.CFrame
				end
			end
			local rotation = frame.Rotation
			joints[logical] = {
				motor = motor,
				constraint = constraint,
				rotation = rotation,
				inverse = rotation:Inverse(),
			}
		end
	end
	return { model = model, joints = joints, r6 = r6 }
end

-- Clear every joint (for rigs no Animator drives, so old poses do not linger).
function Rig.reset(rig: RigInfo)
	for _, joint in rig.joints do
		local motor = joint.motor
		if motor then
			motor.Transform = CFrame.new()
		end
		local constraint = joint.constraint
		if constraint then
			constraint.Transform = CFrame.new()
		end
	end
end

function Rig.jointCount(rig: RigInfo): number
	local count = 0
	for _ in rig.joints do
		count += 1
	end
	return count
end

-- Blend the pose (logical joint -> rotation/offset in parent space) over the current animation.
function Rig.apply(rig: RigInfo, pose: { [string]: CFrame }, weight: number)
	if weight <= 0 then
		return
	end
	local root = pose.Root
	local waist = pose.Waist
	for logical, value in pose do
		local target = value
		if rig.r6 then
			if logical == "Waist" then
				continue -- R6 has no waist; folded into the root below
			elseif logical == "Root" and waist then
				target = value * waist
			end
		end
		local joint = rig.joints[logical]
		if joint then
			local transform = joint.inverse * target * joint.rotation
			local motor = joint.motor
			if motor then
				motor.Transform = if weight >= 1 then transform else motor.Transform:Lerp(transform, weight)
			else
				local constraint = joint.constraint
				if constraint then
					constraint.Transform = if weight >= 1
						then transform
						else constraint.Transform:Lerp(transform, weight)
				end
			end
		end
	end
	if rig.r6 and waist and not root then
		local joint = rig.joints.Root
		if joint then
			local transform = joint.inverse * waist * joint.rotation
			local motor = joint.motor
			if motor then
				motor.Transform = motor.Transform:Lerp(transform, weight)
			end
		end
	end
end

return Rig
