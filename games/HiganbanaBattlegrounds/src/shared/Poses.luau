--!strict
-- Procedural animation data: joint poses and timed sequences. No animation assets are needed.
--
-- Angles are degrees, offsets are studs, both in the parent part's space of an R15 rig
-- (X right, Y up, -Z forward). The client converts them per joint, so the same data drives R6 rigs.
--   Shoulder/Hip  rx > 0 swings the limb forward; rz > 0 raises the RIGHT limb outward (LEFT: rz < 0)
--   Elbow         rx > 0 folds the forearm forward;  Knee rx < 0 bends the lower leg back
--   Waist/Root    rx < 0 leans forward; ry > 0 twists left; Root py < 0 crouches
--   Neck          rx < 0 looks down

local Types = require("./Types")

type Pose = Types.Pose
type JointPose = Types.JointPose
type Sequence = Types.Sequence

local Poses = {}

Poses.JOINTS = {
	"Root",
	"Waist",
	"Neck",
	"RightShoulder",
	"RightElbow",
	"LeftShoulder",
	"LeftElbow",
	"RightHip",
	"RightKnee",
	"LeftHip",
	"LeftKnee",
}

local MIRROR_NAME: { [string]: string } = {
	RightShoulder = "LeftShoulder",
	LeftShoulder = "RightShoulder",
	RightElbow = "LeftElbow",
	LeftElbow = "RightElbow",
	RightHip = "LeftHip",
	LeftHip = "RightHip",
	RightKnee = "LeftKnee",
	LeftKnee = "RightKnee",
}

-- Reflect a pose across the body's centre plane: swap sides, negate yaw, roll and sideways offset.
function Poses.mirror(pose: Pose): Pose
	local result: Pose = {}
	for joint, value in pose do
		local mirrored: JointPose = {
			rx = value.rx,
			ry = if value.ry then -value.ry else nil,
			rz = if value.rz then -value.rz else nil,
			px = if value.px then -value.px else nil,
			py = value.py,
			pz = value.pz,
		}
		result[MIRROR_NAME[joint] or joint] = mirrored
	end
	return result
end

local P: { [string]: Pose } = {}

P.Neutral = {}

P.WindupRight = {
	Root = { py = -0.2 },
	Waist = { ry = -35 },
	RightShoulder = { rx = 60, rz = 70 },
	RightElbow = { rx = 40 },
	LeftShoulder = { rx = 35, rz = -20 },
	LeftElbow = { rx = 50 },
}
P.SwingRight = {
	Root = { py = -0.35, rx = -6 },
	Waist = { ry = 40, rx = -8 },
	RightShoulder = { rx = 90, rz = -35 },
	RightElbow = { rx = 10 },
	LeftShoulder = { rx = -15, rz = -25 },
	RightHip = { rx = 15 },
	LeftHip = { rx = -15 },
}
P.WindupLeft = Poses.mirror(P.WindupRight)
P.SwingLeft = Poses.mirror(P.SwingRight)

P.Overhead = {
	Root = { rx = 6 },
	Waist = { rx = 14 },
	Neck = { rx = 10 },
	RightShoulder = { rx = 165, rz = -12 },
	RightElbow = { rx = 35 },
	LeftShoulder = { rx = 165, rz = 12 },
	LeftElbow = { rx = 35 },
}
P.Slam = {
	Root = { py = -0.9, rx = -14 },
	Waist = { rx = -32 },
	Neck = { rx = -10 },
	RightShoulder = { rx = 70, rz = -12 },
	RightElbow = { rx = 5 },
	LeftShoulder = { rx = 70, rz = 12 },
	LeftElbow = { rx = 5 },
	RightHip = { rx = 45 },
	RightKnee = { rx = -55 },
	LeftHip = { rx = -12 },
	LeftKnee = { rx = -35 },
}

P.ThrowWindup = {
	Root = { py = -0.2 },
	Waist = { ry = -35, rx = 10 },
	RightShoulder = { rx = 150, rz = 25 },
	RightElbow = { rx = 85 },
	LeftShoulder = { rx = 70, rz = -15 },
	LeftHip = { rx = 25 },
}
P.ThrowRelease = {
	Root = { rx = -10, py = -0.3 },
	Waist = { ry = 30, rx = -18 },
	RightShoulder = { rx = 80, rz = -15 },
	RightElbow = { rx = 5 },
	LeftShoulder = { rx = -30, rz = -25 },
	RightHip = { rx = -20 },
	LeftHip = { rx = 30 },
}

P.Uppercut = {
	Root = { rx = 8, py = -0.1 },
	Waist = { ry = 25, rx = 12 },
	Neck = { rx = 12 },
	RightShoulder = { rx = 155, rz = -10 },
	RightElbow = { rx = 45 },
	LeftShoulder = { rx = 20, rz = -25 },
	LeftElbow = { rx = 60 },
}

P.Thrust = {
	Root = { py = -0.45, rx = -12 },
	Waist = { ry = 18, rx = -10 },
	RightShoulder = { rx = 92, rz = -5 },
	RightElbow = { rx = 0 },
	LeftShoulder = { rx = 80, rz = 15 },
	LeftElbow = { rx = 25 },
	RightHip = { rx = -25 },
	RightKnee = { rx = -20 },
	LeftHip = { rx = 35 },
	LeftKnee = { rx = -30 },
}

P.PalmWindup = {
	Root = { py = -0.3 },
	Waist = { ry = -30 },
	RightShoulder = { rx = 35, rz = 20 },
	RightElbow = { rx = 100 },
	LeftShoulder = { rx = 60, rz = -20 },
	LeftElbow = { rx = 40 },
	LeftHip = { rx = 20 },
	LeftKnee = { rx = -20 },
}
P.Palm = {
	Root = { py = -0.45, rx = -8 },
	Waist = { ry = 25, rx = -10 },
	RightShoulder = { rx = 92 },
	RightElbow = { rx = 0 },
	LeftShoulder = { rx = 30, rz = -30 },
	LeftElbow = { rx = 80 },
	RightHip = { rx = -20 },
	LeftHip = { rx = 35 },
	LeftKnee = { rx = -35 },
}

P.StompLift = {
	Waist = { rx = 8 },
	RightHip = { rx = 75 },
	RightKnee = { rx = -70 },
	RightShoulder = { rx = 30, rz = 35 },
	LeftShoulder = { rx = 30, rz = -35 },
}
P.StompDown = {
	Root = { py = -0.8 },
	Waist = { rx = -14 },
	Neck = { rx = -12 },
	RightHip = { rx = 20 },
	RightKnee = { rx = -20 },
	LeftHip = { rx = 20 },
	LeftKnee = { rx = -45 },
	RightShoulder = { rx = 15, rz = 60 },
	LeftShoulder = { rx = 15, rz = -60 },
}

P.Brace = {
	Root = { py = -0.7 },
	Waist = { rx = -8 },
	RightShoulder = { rx = 70, rz = -40 },
	RightElbow = { rx = 80 },
	LeftShoulder = { rx = 70, rz = 40 },
	LeftElbow = { rx = 80 },
	RightHip = { rx = 25, rz = 10 },
	RightKnee = { rx = -35 },
	LeftHip = { rx = 25, rz = -10 },
	LeftKnee = { rx = -35 },
}

P.ChargeLean = {
	Root = { rx = -28, py = -0.3 },
	Waist = { ry = 25, rx = -10 },
	RightShoulder = { rx = 20, rz = 20 },
	RightElbow = { rx = 90 },
	LeftShoulder = { rx = 60, rz = -10 },
	LeftElbow = { rx = 70 },
	RightHip = { rx = 40 },
	RightKnee = { rx = -40 },
	LeftHip = { rx = -30 },
	LeftKnee = { rx = -20 },
}

P.CastForward = {
	Root = { py = -0.35 },
	Waist = { rx = -8 },
	RightShoulder = { rx = 92, rz = -12 },
	RightElbow = { rx = 8 },
	LeftShoulder = { rx = 92, rz = 12 },
	LeftElbow = { rx = 8 },
	RightHip = { rx = -15 },
	LeftHip = { rx = 20 },
	LeftKnee = { rx = -20 },
}
P.Recoil = {
	Root = { py = -0.3, rx = 6 },
	Waist = { rx = 10 },
	RightShoulder = { rx = -20, rz = 20 },
	RightElbow = { rx = 90 },
	LeftShoulder = { rx = -20, rz = -20 },
	LeftElbow = { rx = 90 },
	RightHip = { rx = 20 },
	RightKnee = { rx = -25 },
}
P.CastUp = {
	Root = { rx = 4 },
	Waist = { rx = 12 },
	Neck = { rx = 25 },
	RightShoulder = { rx = 170, rz = -8 },
	RightElbow = { rx = 10 },
	LeftShoulder = { rx = 170, rz = 8 },
	LeftElbow = { rx = 10 },
}

P.Crouch = {
	Root = { py = -1.2, rx = -10 },
	Waist = { rx = -18 },
	RightHip = { rx = 70 },
	RightKnee = { rx = -95 },
	LeftHip = { rx = 70 },
	LeftKnee = { rx = -95 },
	RightShoulder = { rx = 20, rz = 25 },
	LeftShoulder = { rx = 20, rz = -25 },
}
P.Leap = {
	Root = { rx = -8 },
	Waist = { rx = 8 },
	RightHip = { rx = 65 },
	RightKnee = { rx = -95 },
	LeftHip = { rx = 25 },
	LeftKnee = { rx = -45 },
	RightShoulder = { rx = 155, rz = 15 },
	LeftShoulder = { rx = 155, rz = -15 },
}

P.KickChamber = {
	Root = { rx = 6 },
	Waist = { rx = 12, ry = 10 },
	RightHip = { rx = 85 },
	RightKnee = { rx = -90 },
	RightShoulder = { rx = -20, rz = 35 },
	LeftShoulder = { rx = 40, rz = -35 },
	LeftElbow = { rx = 60 },
}
P.Kick = {
	Root = { rx = 10 },
	Waist = { rx = 16 },
	RightHip = { rx = 100 },
	RightKnee = { rx = -5 },
	RightShoulder = { rx = -30, rz = 40 },
	LeftShoulder = { rx = 45, rz = -40 },
	LeftElbow = { rx = 70 },
}

local function spinPose(yaw: number): Pose
	return {
		Root = { ry = yaw, py = -0.3 },
		RightShoulder = { rz = 80 },
		LeftShoulder = { rz = -80 },
	}
end
P.SpinA = spinPose(120)
P.SpinB = spinPose(240)
P.SpinC = spinPose(359)

local function flipPose(pitch: number): Pose
	return {
		Root = { rx = pitch, py = 0.5 },
		RightHip = { rx = 80 },
		RightKnee = { rx = -100 },
		LeftHip = { rx = 80 },
		LeftKnee = { rx = -100 },
		RightShoulder = { rx = 60 },
		LeftShoulder = { rx = 60 },
	}
end
P.FlipA = flipPose(120)
P.FlipB = flipPose(240)
P.FlipC = flipPose(359)

P.DashLean = {
	Root = { rx = -22, py = -0.2 },
	Waist = { rx = -10 },
	RightShoulder = { rx = -50, rz = 10 },
	RightElbow = { rx = 20 },
	LeftShoulder = { rx = -50, rz = -10 },
	LeftElbow = { rx = 20 },
	RightHip = { rx = 35 },
	RightKnee = { rx = -40 },
	LeftHip = { rx = -25 },
	LeftKnee = { rx = -30 },
}
P.DashSlash = {
	Root = { rx = -30, py = -0.5 },
	Waist = { ry = -20, rx = -10 },
	RightShoulder = { rx = 40, rz = 70 },
	RightElbow = { rx = 5 },
	LeftShoulder = { rx = 40, rz = -70 },
	LeftElbow = { rx = 5 },
	RightHip = { rx = 50 },
	RightKnee = { rx = -60 },
	LeftHip = { rx = -35 },
	LeftKnee = { rx = -15 },
}

P.Gust = {
	Root = { rx = -18, py = -0.3, ry = 30 },
	Waist = { ry = 30 },
	RightShoulder = { rx = 95, rz = -45 },
	LeftShoulder = { rx = 30, rz = -60 },
}
P.GustMirror = Poses.mirror(P.Gust)

P.FanSpread = {
	Root = { py = -0.3 },
	Waist = { rx = -5 },
	RightShoulder = { rz = 85, rx = 10 },
	RightElbow = { rx = 10 },
	LeftShoulder = { rz = -85, rx = 10 },
	LeftElbow = { rx = 10 },
}
P.FanCross = {
	Root = { py = -0.4 },
	Waist = { rx = -10 },
	RightShoulder = { rx = 85, rz = -38 },
	RightElbow = { rx = 15 },
	LeftShoulder = { rx = 85, rz = 38 },
	LeftElbow = { rx = 15 },
	RightHip = { rx = -15 },
	LeftHip = { rx = 25 },
	LeftKnee = { rx = -25 },
}

P.Ward = {
	Root = { py = -0.6 },
	Waist = { rx = -5 },
	Neck = { rx = -8 },
	RightShoulder = { rx = 70, rz = -20 },
	RightElbow = { rx = 60 },
	LeftShoulder = { rx = 40, rz = 30 },
	LeftElbow = { rx = 100 },
	RightHip = { rx = 30, rz = 12 },
	RightKnee = { rx = -40 },
	LeftHip = { rx = 30, rz = -12 },
	LeftKnee = { rx = -40 },
}

-- Held states and reactions
P.Guard = {
	Root = { py = -0.35 },
	Waist = { rx = -8 },
	RightShoulder = { rx = 75, rz = -28 },
	RightElbow = { rx = 70 },
	LeftShoulder = { rx = 75, rz = 28 },
	LeftElbow = { rx = 70 },
	RightHip = { rx = 15 },
	RightKnee = { rx = -20 },
	LeftHip = { rx = -10 },
	LeftKnee = { rx = -15 },
}
P.Stunned = {
	Root = { py = -0.3, rx = 6 },
	Waist = { rx = -22, rz = 6 },
	Neck = { rx = -28 },
	RightShoulder = { rz = 12 },
	RightElbow = { rx = 15 },
	LeftShoulder = { rz = -12 },
	LeftElbow = { rx = 15 },
}
P.Hurt = {
	Root = { rx = 10 },
	Waist = { rx = 16 },
	Neck = { rx = 18 },
	RightShoulder = { rx = 20, rz = 25 },
	LeftShoulder = { rx = 20, rz = -25 },
}

-- Higanbana poses -------------------------------------------------------------------------------

P.Parry = {
	Root = { rx = 6 },
	Waist = { rx = 8 },
	RightShoulder = { rx = 110, rz = -45 },
	RightElbow = { rx = 95 },
	LeftShoulder = { rx = 70, rz = 25 },
	LeftElbow = { rx = 60 },
}
P.GuardBroken = {
	Root = { py = -0.2 },
	Waist = { rx = 16 },
	Neck = { rx = 20 },
	RightShoulder = { rx = -25, rz = 70 },
	LeftShoulder = { rx = -25, rz = -70 },
	RightElbow = { rx = 20 },
	LeftElbow = { rx = 20 },
}
P.Grabbed = {
	Neck = { rx = 18 },
	RightShoulder = { rx = 40, rz = 55 },
	LeftShoulder = { rx = 40, rz = -55 },
	RightElbow = { rx = 45 },
	LeftElbow = { rx = 45 },
	RightHip = { rx = 20 },
	LeftHip = { rx = -10 },
	RightKnee = { rx = -35 },
	LeftKnee = { rx = -25 },
}
P.Thrown = {
	Waist = { rx = 20 },
	Neck = { rx = 25 },
	RightShoulder = { rx = 150, rz = 60 },
	LeftShoulder = { rx = 150, rz = -60 },
	RightHip = { rx = 45, rz = 15 },
	LeftHip = { rx = -20, rz = -15 },
	RightKnee = { rx = -50 },
}
P.Drained = {
	Root = { py = -0.3 },
	Waist = { rx = 18 },
	Neck = { rx = 30 },
	RightShoulder = { rx = 30, rz = 45 },
	LeftShoulder = { rx = 30, rz = -45 },
	RightElbow = { rx = 30 },
	LeftElbow = { rx = 30 },
	RightKnee = { rx = -40 },
	LeftKnee = { rx = -40 },
}
P.MendSeat = {
	Root = { py = -1.15 },
	Waist = { rx = -4 },
	Neck = { rx = -18 },
	RightShoulder = { rx = 45, rz = -18 },
	RightElbow = { rx = 85 },
	LeftShoulder = { rx = 45, rz = 18 },
	LeftElbow = { rx = 85 },
	RightHip = { rx = 75 },
	RightKnee = { rx = -85 },
	LeftHip = { rx = -10 },
	LeftKnee = { rx = -95 },
}

-- Tsuta (umbrella)
P.UmbrellaOpen = {
	Root = { py = -0.25 },
	Waist = { rx = -6, ry = 10 },
	RightShoulder = { rx = 80, rz = -10 },
	RightElbow = { rx = 45 },
	LeftShoulder = { rx = 35, rz = -10 },
	LeftElbow = { rx = 40 },
	RightHip = { rx = 10 },
	LeftHip = { rx = -12 },
}
P.Plant = {
	Root = { py = -1, rx = -8 },
	Waist = { rx = -30 },
	Neck = { rx = -10 },
	RightShoulder = { rx = 65, rz = -10 },
	RightElbow = { rx = 10 },
	LeftShoulder = { rx = 65, rz = 10 },
	LeftElbow = { rx = 10 },
	RightHip = { rx = 40 },
	RightKnee = { rx = -60 },
	LeftHip = { rx = -5 },
	LeftKnee = { rx = -45 },
}

-- Hibiki (taiko bachi)
P.DrumBack = {
	Root = { py = -0.2 },
	Waist = { rx = 10 },
	Neck = { rx = 8 },
	RightShoulder = { rx = 165, rz = 25 },
	RightElbow = { rx = 110 },
	LeftShoulder = { rx = 150, rz = -25 },
	LeftElbow = { rx = 100 },
}
P.DrumStrike = {
	Root = { py = -0.45, rx = -6 },
	Waist = { rx = -16 },
	RightShoulder = { rx = 75, rz = -10 },
	RightElbow = { rx = 15 },
	LeftShoulder = { rx = 70, rz = 10 },
	LeftElbow = { rx = 20 },
	RightHip = { rx = 15 },
	LeftHip = { rx = -15 },
}
P.DrumGround = {
	Root = { py = -1.1 },
	Waist = { rx = -36 },
	Neck = { rx = -14 },
	RightShoulder = { rx = 60 },
	RightElbow = { rx = 0 },
	LeftShoulder = { rx = 60 },
	LeftElbow = { rx = 0 },
	RightHip = { rx = 70 },
	RightKnee = { rx = -95 },
	LeftHip = { rx = -10 },
	LeftKnee = { rx = -80 },
}
P.Shout = {
	Root = { py = -0.25 },
	Waist = { rx = 12 },
	Neck = { rx = 16 },
	RightShoulder = { rx = 25, rz = 80 },
	RightElbow = { rx = 35 },
	LeftShoulder = { rx = 25, rz = -80 },
	LeftElbow = { rx = 35 },
	RightHip = { rz = 10 },
	LeftHip = { rz = -10 },
}

-- Iwao (sumo)
P.PalmWindupLeft = Poses.mirror(P.PalmWindup)
P.Tsuppari = {
	Root = { py = -0.35, rx = -6 },
	Waist = { ry = 28, rx = -8 },
	RightShoulder = { rx = 92 },
	RightElbow = { rx = 4 },
	LeftShoulder = { rx = 40, rz = -12 },
	LeftElbow = { rx = 65 },
	RightHip = { rx = 18 },
	LeftHip = { rx = -14 },
}
P.TsuppariLeft = Poses.mirror(P.Tsuppari)
P.Shove = {
	Root = { py = -0.5, rx = -10 },
	Waist = { rx = -14 },
	RightShoulder = { rx = 88, rz = -6 },
	RightElbow = { rx = 4 },
	LeftShoulder = { rx = 88, rz = 6 },
	LeftElbow = { rx = 4 },
	RightHip = { rx = 25 },
	RightKnee = { rx = -20 },
	LeftHip = { rx = -30 },
}
P.ShikoLift = {
	Root = { py = -0.5 },
	Waist = { rx = -10 },
	RightShoulder = { rx = 25, rz = 35 },
	RightElbow = { rx = 20 },
	LeftShoulder = { rx = 30, rz = -15 },
	LeftElbow = { rx = 40 },
	RightHip = { rx = 35, rz = 75 },
	RightKnee = { rx = -25 },
	LeftKnee = { rx = -25 },
}
P.ShikoDown = {
	Root = { py = -1.25 },
	Waist = { rx = -12 },
	RightShoulder = { rx = 30, rz = 20 },
	RightElbow = { rx = 35 },
	LeftShoulder = { rx = 30, rz = -20 },
	LeftElbow = { rx = 35 },
	RightHip = { rx = 50, rz = 35 },
	RightKnee = { rx = -75 },
	LeftHip = { rx = 50, rz = -35 },
	LeftKnee = { rx = -75 },
}
P.Grab = {
	Root = { py = -0.4, rx = -8 },
	Waist = { rx = -14 },
	RightShoulder = { rx = 82, rz = 18 },
	RightElbow = { rx = 35 },
	LeftShoulder = { rx = 82, rz = -18 },
	LeftElbow = { rx = 35 },
	RightHip = { rx = 20 },
	LeftHip = { rx = -18 },
}
P.LiftOverhead = {
	Root = { py = -0.3 },
	Waist = { rx = 12 },
	Neck = { rx = 12 },
	RightShoulder = { rx = 170, rz = -8 },
	RightElbow = { rx = 25 },
	LeftShoulder = { rx = 170, rz = 8 },
	LeftElbow = { rx = 25 },
}
P.Clap = {
	Root = { py = -0.7 },
	RightShoulder = { rx = 80, rz = -14 },
	RightElbow = { rx = 45 },
	LeftShoulder = { rx = 80, rz = 14 },
	LeftElbow = { rx = 45 },
	RightHip = { rx = 30, rz = 25 },
	RightKnee = { rx = -45 },
	LeftHip = { rx = 30, rz = -25 },
	LeftKnee = { rx = -45 },
}

-- Kanemori (jitte and chain)
P.HookTwist = {
	Root = { py = -0.3 },
	Waist = { ry = -42, rx = -10 },
	RightShoulder = { rx = 80, rz = 20 },
	RightElbow = { rx = 45 },
	LeftShoulder = { rx = 25, rz = -15 },
	LeftElbow = { rx = 50 },
	RightHip = { rx = 12 },
	LeftHip = { rx = -12 },
}
P.ChainWindup = {
	Root = { py = -0.2 },
	Waist = { ry = -40 },
	RightShoulder = { rx = 130, rz = 45 },
	RightElbow = { rx = 55 },
	LeftShoulder = { rx = 45, rz = -20 },
	LeftHip = { rx = 20 },
}
P.ChainThrow = {
	Root = { py = -0.3, rx = -6 },
	Waist = { ry = 32, rx = -12 },
	RightShoulder = { rx = 92, rz = -20 },
	RightElbow = { rx = 0 },
	LeftShoulder = { rx = 10, rz = -30 },
	RightHip = { rx = 18 },
	LeftHip = { rx = -18 },
}
P.Yank = {
	Root = { py = -0.4, rx = 6 },
	Waist = { ry = -28, rx = 12 },
	RightShoulder = { rx = 45, rz = 10 },
	RightElbow = { rx = 115 },
	LeftShoulder = { rx = 30, rz = -20 },
	LeftElbow = { rx = 60 },
	RightHip = { rx = -15 },
	LeftHip = { rx = 20 },
	LeftKnee = { rx = -20 },
}
P.CatchStance = {
	Root = { py = -0.35 },
	Waist = { ry = 22 },
	RightShoulder = { rx = 100, rz = -40 },
	RightElbow = { rx = 75 },
	LeftShoulder = { rx = 30, rz = -10 },
	LeftElbow = { rx = 40 },
	RightHip = { rx = 14 },
	LeftHip = { rx = -16 },
}
P.Drive = {
	Root = { py = -1, rx = -6 },
	Waist = { rx = -34 },
	Neck = { rx = -10 },
	RightShoulder = { rx = 45, rz = -4 },
	RightElbow = { rx = 0 },
	LeftShoulder = { rx = 20, rz = -25 },
	RightHip = { rx = 60 },
	RightKnee = { rx = -90 },
	LeftHip = { rx = -5 },
	LeftKnee = { rx = -70 },
}

-- Rokumon (ferry oar)
P.OarSweepRight = {
	Root = { py = -0.3 },
	Waist = { ry = -50 },
	RightShoulder = { rx = 70, rz = 30 },
	RightElbow = { rx = 25 },
	LeftShoulder = { rx = 75, rz = 25 },
	LeftElbow = { rx = 55 },
	RightHip = { rx = -10 },
	LeftHip = { rx = 15 },
}
P.OarSweepLeft = {
	Root = { py = -0.35, rx = -4 },
	Waist = { ry = 50, rx = -6 },
	RightShoulder = { rx = 75, rz = -25 },
	RightElbow = { rx = 55 },
	LeftShoulder = { rx = 70, rz = -30 },
	LeftElbow = { rx = 25 },
	RightHip = { rx = 15 },
	LeftHip = { rx = -10 },
}
P.OarScoop = {
	Root = { py = -0.2, rx = 6 },
	Waist = { rx = 16 },
	Neck = { rx = 14 },
	RightShoulder = { rx = 155, rz = -10 },
	RightElbow = { rx = 20 },
	LeftShoulder = { rx = 140, rz = 10 },
	LeftElbow = { rx = 30 },
}
P.Pole = {
	Root = { py = -0.35 },
	Waist = { rx = -18 },
	RightShoulder = { rx = 40, rz = 10 },
	RightElbow = { rx = 30 },
	LeftShoulder = { rx = 65, rz = 10 },
	LeftElbow = { rx = 45 },
	RightHip = { rx = 25 },
	RightKnee = { rx = -20 },
	LeftHip = { rx = -15 },
}
P.Summon = {
	Root = { py = -0.2 },
	Waist = { rx = 8 },
	Neck = { rx = 20 },
	RightShoulder = { rx = 140, rz = 25 },
	RightElbow = { rx = 10 },
	LeftShoulder = { rx = 140, rz = -25 },
	LeftElbow = { rx = 10 },
}

P.StickUpRight = {
	Root = { py = -0.15 },
	Waist = { ry = -12, rx = 6 },
	RightShoulder = { rx = 165, rz = 12 },
	RightElbow = { rx = 70 },
	LeftShoulder = { rx = 60, rz = -15 },
	LeftElbow = { rx = 80 },
}
P.StickDownRight = {
	Root = { py = -0.4, rx = -6 },
	Waist = { ry = 10, rx = -14 },
	RightShoulder = { rx = 70, rz = -8 },
	RightElbow = { rx = 12 },
	LeftShoulder = { rx = 70, rz = -15 },
	LeftElbow = { rx = 85 },
	RightHip = { rx = 14 },
	LeftHip = { rx = -12 },
}
P.StickUpLeft = Poses.mirror(P.StickUpRight)
P.StickDownLeft = Poses.mirror(P.StickDownRight)
P.ChainWindupLeft = Poses.mirror(P.ChainWindup)
P.ChainThrowLeft = Poses.mirror(P.ChainThrow)
P.YankLeft = Poses.mirror(P.Yank)

-- Idles: upper body only, so the walk cycle keeps the legs.
P.IdleTsuta = {
	RightShoulder = { rx = 12, rz = 8 },
	RightElbow = { rx = 18 },
	LeftShoulder = { rx = 6, rz = -6 },
	Neck = { rx = -4 },
}
P.IdleHibiki = {
	RightShoulder = { rx = 100, rz = 35 },
	RightElbow = { rx = 100 },
	LeftShoulder = { rx = 100, rz = -35 },
	LeftElbow = { rx = 100 },
	Waist = { rx = -4 },
}
P.IdleIwao = {
	Waist = { rx = -6 },
	RightShoulder = { rx = 16, rz = 26 },
	RightElbow = { rx = 30 },
	LeftShoulder = { rx = 16, rz = -26 },
	LeftElbow = { rx = 30 },
}
P.IdleKanemori = {
	RightShoulder = { rx = 30, rz = 6 },
	RightElbow = { rx = 48 },
	LeftShoulder = { rx = 10, rz = -12 },
	LeftElbow = { rx = 22 },
}
P.IdleRokumon = {
	RightShoulder = { rx = 62, rz = 16 },
	RightElbow = { rx = 98 },
	LeftShoulder = { rx = 46, rz = -10 },
	LeftElbow = { rx = 82 },
}

Poses.POSES = P

local DEFAULT_FADE_IN = 0.06
local DEFAULT_FADE_OUT = 0.12

-- keys: { { time, poseName }, ... } sorted by time; the last key's time is the duration.
local function sequence(keys: { { any } }, fadeIn: number?, fadeOut: number?): Sequence
	local list = {}
	for _, key in keys do
		table.insert(list, { t = key[1] :: number, pose = key[2] :: string })
	end
	return {
		keys = list,
		duration = list[#list].t,
		fadeIn = fadeIn or DEFAULT_FADE_IN,
		fadeOut = fadeOut or DEFAULT_FADE_OUT,
	}
end

-- A two-beat strike: wind up, hit at `strikeAt`, hold, recover by `total`.
local function strike(windup: string, hit: string, strikeAt: number, total: number): Sequence
	return sequence({ { 0, windup }, { strikeAt, hit }, { total * 0.75, hit }, { total, "Neutral" } })
end

local function idle(pose: string, duration: number): Sequence
	local s = sequence({ { 0, pose }, { duration, pose } }, 0.3, 0.3)
	s.upper = true
	return s
end

-- Sequence ids are the clip names in design/animations.json (poses.spec checks every R15 clip).
local S: { [string]: Sequence } = {}

-- Shared
S.Block_Hold = sequence({ { 0, "Guard" }, { 0.8, "Guard" } })
S.Parry = sequence({ { 0, "Guard" }, { 0.05, "Parry" }, { 0.2, "Parry" }, { 0.3, "Neutral" } }, 0.02)
S.Dash = sequence({ { 0, "DashLean" }, { 0.24, "DashLean" }, { 0.35, "Neutral" } }, 0.03)
S.Mend_Channel = sequence({ { 0, "MendSeat" }, { 1.2, "MendSeat" } }, 0.15, 0.2)
S.HitStun = sequence({ { 0, "Hurt" }, { 0.12, "Hurt" }, { 0.4, "Neutral" } }, 0.03, 0.15)
S.GuardBreak = sequence({ { 0, "GuardBroken" }, { 0.6, "GuardBroken" }, { 0.8, "Neutral" } }, 0.03)
S.Grabbed_Thrown = sequence({ { 0, "Grabbed" }, { 0.5, "Grabbed" }, { 0.6, "Thrown" }, { 0.9, "Neutral" } }, 0.05)
S.Grabbed_Drained = sequence({ { 0, "Drained" }, { 1, "Drained" } }, 0.1)
S.Hurt = S.HitStun

-- Tsuta
S.Tsuta_Idle = idle("IdleTsuta", 2)
S.Tsuta_M1_A = strike("PalmWindup", "Thrust", 0.12, 0.32)
S.Tsuta_M1_B = strike("SwingRight", "WindupRight", 0.12, 0.32)
S.Tsuta_M1_Finisher =
	sequence({ { 0, "PalmWindup" }, { 0.24, "UmbrellaOpen" }, { 0.45, "UmbrellaOpen" }, { 0.55, "Neutral" } })
S.Tsuta_RootSnare =
	sequence({ { 0, "Neutral" }, { 0.15, "PalmWindup" }, { 0.3, "Drive" }, { 0.5, "Drive" }, { 0.6, "Neutral" } })
S.Tsuta_SeedVolley = strike("UmbrellaOpen", "Thrust", 0.2, 0.5)
S.Tsuta_CanopyGuard =
	sequence({ { 0, "Neutral" }, { 0.1, "UmbrellaOpen" }, { 1.4, "UmbrellaOpen" }, { 1.5, "Neutral" } })
S.Tsuta_Graft = sequence({
	{ 0, "WindupRight" },
	{ 0.2, "SwingRight" },
	{ 0.35, "DashLean" },
	{ 0.6, "DashLean" },
	{ 0.7, "Neutral" },
})
S.Tsuta_ThousandRootBloom = sequence({
	{ 0, "SpinA" },
	{ 0.2, "SpinB" },
	{ 0.35, "Overhead" },
	{ 0.5, "Plant" },
	{ 1.8, "Plant" },
	{ 2, "Neutral" },
})

-- Hibiki
S.Hibiki_Idle = idle("IdleHibiki", 1.6)
S.Hibiki_M1_A = strike("StickUpRight", "StickDownRight", 0.11, 0.3)
S.Hibiki_M1_B = strike("StickUpLeft", "StickDownLeft", 0.11, 0.3)
S.Hibiki_M1_Finisher = sequence({ { 0, "Overhead" }, { 0.26, "Slam" }, { 0.42, "Slam" }, { 0.55, "Neutral" } })
S.Hibiki_WarBeat = sequence({
	{ 0, "Neutral" },
	{ 0.18, "DrumBack" },
	{ 0.3, "DrumStrike" },
	{ 0.5, "DrumStrike" },
	{ 0.6, "Neutral" },
})
S.Hibiki_FireRoll = sequence({ { 0, "Crouch" }, { 0.2, "DrumGround" }, { 0.7, "DrumGround" }, { 0.8, "Neutral" } })
S.Hibiki_Kakegoe = sequence({ { 0, "Crouch" }, { 0.25, "Shout" }, { 0.5, "Shout" }, { 0.6, "Neutral" } })
S.Hibiki_ThunderRoll = sequence({
	{ 0, "StickUpRight" },
	{ 0.3, "StickDownRight" },
	{ 0.42, "StickUpLeft" },
	{ 0.55, "StickDownLeft" },
	{ 0.67, "StickUpRight" },
	{ 0.8, "StickDownRight" },
	{ 0.92, "StickUpLeft" },
	{ 1.05, "StickDownLeft" },
	{ 1.17, "StickUpRight" },
	{ 1.3, "StickDownRight" },
	{ 1.42, "StickDownRight" },
	{ 1.5, "Neutral" },
})
S.Hibiki_FestivalOfDrums = sequence({
	{ 0, "Shout" },
	{ 0.6, "DrumStrike" },
	{ 0.75, "DrumBack" },
	{ 0.9, "DrumStrike" },
	{ 1.05, "DrumBack" },
	{ 1.2, "DrumStrike" },
	{ 1.35, "DrumBack" },
	{ 1.5, "DrumStrike" },
	{ 1.65, "DrumBack" },
	{ 1.8, "DrumStrike" },
	{ 1.95, "Overhead" },
	{ 2.1, "Slam" },
	{ 2.3, "Slam" },
	{ 2.4, "Neutral" },
})

-- Iwao
S.Iwao_Idle = idle("IdleIwao", 2)
S.Iwao_M1_A = strike("PalmWindup", "Tsuppari", 0.13, 0.34)
S.Iwao_M1_B = strike("PalmWindupLeft", "TsuppariLeft", 0.13, 0.34)
S.Iwao_M1_Finisher = sequence({ { 0, "Crouch" }, { 0.28, "Shove" }, { 0.45, "Shove" }, { 0.6, "Neutral" } })
S.Iwao_ShikoStomp = sequence({
	{ 0, "Neutral" },
	{ 0.35, "ShikoLift" },
	{ 0.5, "ShikoLift" },
	{ 0.6, "ShikoDown" },
	{ 0.8, "ShikoDown" },
	{ 0.9, "Neutral" },
})
S.Iwao_BoulderGrip = sequence({
	{ 0, "Grab" },
	{ 0.2, "Grab" },
	{ 0.5, "LiftOverhead" },
	{ 0.7, "ThrowRelease" },
	{ 0.9, "ThrowRelease" },
	{ 1, "Neutral" },
})
S.Iwao_PurifyingSalt = strike("ThrowWindup", "ThrowRelease", 0.3, 0.6)
S.Iwao_TachiaiCharge =
	sequence({ { 0, "ShikoDown" }, { 0.15, "ChargeLean" }, { 0.65, "ChargeLean" }, { 0.8, "Neutral" } })
S.Iwao_Dohyo = sequence({
	{ 0, "Neutral" },
	{ 0.5, "ShikoLift" },
	{ 0.8, "ShikoDown" },
	{ 1, "ShikoDown" },
	{ 1.2, "Clap" },
	{ 1.4, "Clap" },
	{ 1.5, "Neutral" },
})

-- Kanemori
S.Kanemori_Idle = idle("IdleKanemori", 2)
S.Kanemori_M1_A = strike("PalmWindup", "Thrust", 0.11, 0.3)
S.Kanemori_M1_B = strike("SwingRight", "WindupRight", 0.11, 0.3)
S.Kanemori_M1_Finisher =
	sequence({ { 0, "Thrust" }, { 0.25, "HookTwist" }, { 0.45, "HookTwist" }, { 0.55, "Neutral" } })
S.Kanemori_ChainLash = sequence({
	{ 0, "ChainWindupLeft" },
	{ 0.2, "ChainThrowLeft" },
	{ 0.35, "ChainThrowLeft" },
	{ 0.45, "YankLeft" },
	{ 0.55, "YankLeft" },
	{ 0.6, "Neutral" },
})
S.Kanemori_JitteCatch = sequence(
	{ { 0, "CatchStance" }, { 0.6, "CatchStance" }, { 0.7, "Thrust" }, { 0.9, "Thrust" }, { 1, "Neutral" } },
	0.02
)
S.Kanemori_IronEdict = sequence({ { 0, "Overhead" }, { 0.35, "Drive" }, { 0.6, "Drive" }, { 0.7, "Neutral" } })
S.Kanemori_HuntersChase =
	sequence({ { 0, "DashLean" }, { 0.3, "Overhead" }, { 0.4, "Slam" }, { 0.48, "Slam" }, { 0.5, "Neutral" } })
S.Kanemori_EdictOfChains = sequence({
	{ 0, "Neutral" },
	{ 0.5, "Overhead" },
	{ 0.8, "Overhead" },
	{ 1, "Yank" },
	{ 1.5, "Yank" },
	{ 1.8, "Drive" },
	{ 2.05, "Drive" },
	{ 2.2, "Neutral" },
})

-- Rokumon
S.Rokumon_Idle = idle("IdleRokumon", 2.2)
S.Rokumon_M1_A = strike("OarSweepRight", "OarSweepLeft", 0.14, 0.36)
S.Rokumon_M1_B = strike("OarSweepLeft", "OarSweepRight", 0.14, 0.36)
S.Rokumon_M1_Finisher = sequence({ { 0, "Crouch" }, { 0.28, "OarScoop" }, { 0.45, "OarScoop" }, { 0.6, "Neutral" } })
S.Rokumon_Riverpull =
	sequence({ { 0, "OarSweepRight" }, { 0.35, "OarSweepLeft" }, { 0.6, "OarSweepLeft" }, { 0.7, "Neutral" } })
S.Rokumon_PhantomFerry = sequence({ { 0, "Pole" }, { 0.7, "Pole" }, { 0.8, "Neutral" } })
S.Rokumon_Mist = sequence({
	{ 0, "Neutral" },
	{ 0.12, "LiftOverhead" },
	{ 0.24, "SpinA" },
	{ 0.36, "SpinB" },
	{ 0.48, "SpinC" },
	{ 0.6, "Neutral" },
})
S.Rokumon_TollStrike = sequence({ { 0, "Overhead" }, { 0.32, "Slam" }, { 0.5, "Slam" }, { 0.6, "Neutral" } })
S.Rokumon_RiverReturns = sequence({
	{ 0, "Crouch" },
	{ 0.6, "Pole" },
	{ 0.95, "Pole" },
	{ 1.05, "OarSweepLeft" },
	{ 2, "OarSweepLeft" },
	{ 2.2, "Neutral" },
})

Poses.SEQUENCES = S

-- Poses held while a state lasts.
Poses.HELD = {
	Blocking = "Guard",
	Stunned = "Stunned",
	Mending = "MendSeat",
	Grabbed = "Drained",
} :: { [string]: string }

-- M1 hit `index` of a chain: hits 1 and 3 swing A, hit 2 swings B, the last is the finisher.
function Poses.m1Sequence(style: string, index: number): string
	if index >= 4 then
		return `{style}_M1_Finisher`
	end
	return if index % 2 == 1 then `{style}_M1_A` else `{style}_M1_B`
end

function Poses.idleSequence(fighterId: string): string
	return `{fighterId}_Idle`
end

return Poses
