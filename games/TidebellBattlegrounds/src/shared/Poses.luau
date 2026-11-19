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
	return sequence({ { 0, windup }, { strikeAt, hit }, { total * 0.72, hit }, { total, "Neutral" } })
end

local S: { [string]: Sequence } = {}

-- M1 chains, one family per weapon style: M1_<Style>_<1..4>
Poses.M1_STYLES = {
	Heavy = {
		strike("WindupRight", "SwingRight", 0.16, 0.5),
		strike("WindupLeft", "SwingLeft", 0.16, 0.5),
		strike("Overhead", "Slam", 0.18, 0.52),
		strike("ThrowWindup", "Uppercut", 0.18, 0.56),
	},
	Polearm = {
		strike("PalmWindup", "Thrust", 0.13, 0.42),
		strike("WindupRight", "SwingRight", 0.13, 0.42),
		strike("WindupLeft", "SwingLeft", 0.13, 0.42),
		sequence({ { 0, "Neutral" }, { 0.08, "SpinA" }, { 0.16, "SpinB" }, { 0.26, "SpinC" }, { 0.42, "Neutral" } }),
	},
	Fans = {
		strike("WindupRight", "SwingRight", 0.1, 0.34),
		strike("WindupLeft", "SwingLeft", 0.1, 0.34),
		strike("FanSpread", "FanCross", 0.1, 0.36),
		strike("KickChamber", "Kick", 0.11, 0.42),
	},
	Sickles = {
		strike("WindupLeft", "SwingLeft", 0.09, 0.32),
		strike("WindupRight", "SwingRight", 0.09, 0.32),
		strike("Gust", "GustMirror", 0.09, 0.34),
		strike("KickChamber", "Kick", 0.1, 0.4),
	},
	Staff = {
		strike("PalmWindup", "Thrust", 0.12, 0.4),
		strike("WindupRight", "SwingRight", 0.12, 0.4),
		strike("Overhead", "Slam", 0.13, 0.42),
		strike("PalmWindup", "Palm", 0.13, 0.46),
	},
} :: { [string]: { Sequence } }

for style, chain in Poses.M1_STYLES do
	for index, value in chain do
		S[`M1_{style}_{index}`] = value
	end
end

-- Universal
S.Hurt = sequence({ { 0, "Hurt" }, { 0.12, "Hurt" }, { 0.3, "Neutral" } }, 0.03, 0.15)
S.Dash = sequence({ { 0, "DashLean" }, { 0.24, "DashLean" }, { 0.34, "Neutral" } }, 0.03)

-- Stonebreaker
S.Stomp = sequence({
	{ 0, "Neutral" },
	{ 0.2, "StompLift" },
	{ 0.36, "StompDown" },
	{ 0.62, "StompDown" },
	{ 0.8, "Neutral" },
})
S.Throw = sequence({
	{ 0, "ThrowWindup" },
	{ 0.3, "ThrowWindup" },
	{ 0.4, "ThrowRelease" },
	{ 0.58, "ThrowRelease" },
	{ 0.72, "Neutral" },
})
S.ThrowQuick = sequence({
	{ 0, "ThrowWindup" },
	{ 0.14, "ThrowWindup" },
	{ 0.22, "ThrowRelease" },
	{ 0.4, "ThrowRelease" },
	{ 0.54, "Neutral" },
})
S.Brace = sequence({ { 0, "Brace" }, { 0.45, "Brace" }, { 0.6, "Neutral" } })
S.Charge = sequence({ { 0, "Crouch" }, { 0.08, "ChargeLean" }, { 0.44, "ChargeLean" }, { 0.62, "Neutral" } })
S.Mountainfall = sequence({
	{ 0, "Crouch" },
	{ 0.08, "Leap" },
	{ 0.4, "Overhead" },
	{ 0.86, "Overhead" },
	{ 0.98, "Slam" },
	{ 1.3, "Slam" },
	{ 1.45, "Neutral" },
})

-- Tide Dancer
S.Sweep = sequence({
	{ 0, "WindupRight" },
	{ 0.22, "WindupRight" },
	{ 0.3, "SwingRight" },
	{ 0.42, "SwingRight" },
	{ 0.55, "Neutral" },
})
S.Pull = sequence({
	{ 0, "CastForward" },
	{ 0.32, "CastForward" },
	{ 0.42, "Recoil" },
	{ 0.58, "Recoil" },
	{ 0.72, "Neutral" },
})
S.Spin = sequence({
	{ 0, "Neutral" },
	{ 0.12, "SpinA" },
	{ 0.24, "SpinB" },
	{ 0.36, "SpinC" },
	{ 0.48, "SpinA" },
	{ 0.6, "SpinB" },
	{ 0.72, "SpinC" },
	{ 0.95, "Neutral" },
})
S.TideCall = sequence({
	{ 0, "CastUp" },
	{ 0.48, "CastUp" },
	{ 0.62, "CastForward" },
	{ 1.0, "CastForward" },
	{ 1.15, "Neutral" },
})

-- Lantern Fox
S.FanFlick = sequence({
	{ 0, "FanSpread" },
	{ 0.18, "FanCross" },
	{ 0.31, "FanSpread" },
	{ 0.44, "FanCross" },
	{ 0.66, "Neutral" },
})
S.FanBlaze = sequence({ { 0, "FanCross" }, { 0.7, "FanCross" }, { 0.82, "Neutral" } })
S.Backflip =
	sequence({ { 0, "Crouch" }, { 0.05, "FlipA" }, { 0.15, "FlipB" }, { 0.26, "FlipC" }, { 0.42, "Neutral" } }, 0.03)
S.CastUp = sequence({ { 0, "CastUp" }, { 1.0, "CastUp" }, { 1.2, "Neutral" } })

-- Gale Courier
S.Kick = sequence({ { 0, "KickChamber" }, { 0.16, "Kick" }, { 0.36, "Kick" }, { 0.5, "Neutral" } })
S.Leap = sequence({ { 0, "Crouch" }, { 0.06, "Leap" }, { 0.36, "Leap" }, { 0.5, "Neutral" } }, 0.03)
S.DashSlash = sequence({ { 0, "DashSlash" }, { 0.3, "DashSlash" }, { 0.45, "Neutral" } }, 0.03)
S.Gusts = sequence({
	{ 0, "Gust" },
	{ 0.13, "GustMirror" },
	{ 0.26, "Gust" },
	{ 0.39, "GustMirror" },
	{ 0.52, "Gust" },
	{ 0.65, "GustMirror" },
	{ 0.78, "Gust" },
	{ 0.98, "Kick" },
	{ 1.2, "Kick" },
	{ 1.36, "Neutral" },
})

-- Bell Monk
S.Palm = sequence({ { 0, "PalmWindup" }, { 0.18, "Palm" }, { 0.4, "Palm" }, { 0.52, "Neutral" } })
S.BellRing =
	sequence({ { 0, "CastUp" }, { 0.28, "CastUp" }, { 0.36, "StompDown" }, { 0.52, "StompDown" }, { 0.66, "Neutral" } })
S.Ward = sequence({ { 0, "Ward" }, { 1.0, "Ward" }, { 1.12, "Neutral" } })
S.Toll = sequence({ { 0, "CastUp" }, { 0.86, "CastUp" }, { 0.98, "Slam" }, { 1.42, "Slam" }, { 1.6, "Neutral" } })

-- Tide Warden (boss)
S.BossSlam =
	sequence({ { 0, "Overhead" }, { 1.1, "Overhead" }, { 1.22, "Slam" }, { 1.6, "Slam" }, { 1.85, "Neutral" } }, 0.15)
S.BossSweep = sequence({
	{ 0, "WindupRight" },
	{ 0.82, "WindupRight" },
	{ 0.94, "SwingRight" },
	{ 1.25, "SwingRight" },
	{ 1.45, "Neutral" },
}, 0.15)
S.BossToll = sequence(
	{ { 0, "CastUp" }, { 1.95, "CastUp" }, { 2.1, "StompDown" }, { 2.5, "StompDown" }, { 2.7, "Neutral" } },
	0.2
)

Poses.SEQUENCES = S

-- Poses held while a state lasts (blocking, stunned).
Poses.HELD = {
	Blocking = "Guard",
	Stunned = "Stunned",
} :: { [string]: string }

function Poses.m1Sequence(style: string, index: number): string
	return `M1_{style}_{index}`
end

return Poses
