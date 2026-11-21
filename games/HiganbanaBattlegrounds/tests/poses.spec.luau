--!strict
-- Procedural poses: known joints, finite values, well-formed sequences, and one sequence per R15
-- clip in design/animations.json with the clip's length and contact markers.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Harness = require("./harness")
local Fighters = require("../src/shared/Fighters")
local Poses = require("../src/shared/Poses")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local KNOWN_JOINTS: { [string]: boolean } = {}
for _, joint in Poses.JOINTS do
	KNOWN_JOINTS[joint] = true
end

local FIELDS = { rx = true, ry = true, rz = true, px = true, py = true, pz = true }

local animations = serde.decode("json", fs.readFile("design/animations.json"))

describe("Poses", function()
	it("uses only known joints and fields with finite values", function()
		for name, pose in Poses.POSES do
			for joint, value in pose do
				expect(KNOWN_JOINTS[joint] == true, `{name}.{joint}`):toBeTruthy()
				for field, number in value :: { [string]: number } do
					expect(FIELDS[field] == true, `{name}.{joint}.{field}`):toBeTruthy()
					expect(number == number and math.abs(number) < 400, `{name}.{joint}.{field}`):toBeTruthy()
				end
			end
		end
	end)

	it("mirrors left and right", function()
		local mirrored = Poses.mirror({ RightShoulder = { rx = 10, rz = 30, ry = 5 }, Waist = { ry = 20 } })
		local left = mirrored.LeftShoulder
		expect(left ~= nil):toBeTruthy()
		expect(left.rx):toBe(10)
		expect(left.rz):toBe(-30)
		expect(left.ry):toBe(-5)
		expect(mirrored.Waist.ry):toBe(-20)
		expect(mirrored.RightShoulder == nil):toBeTruthy()
	end)

	it("keeps idles off the legs", function()
		for _, fighter in Fighters.LIST do
			local sequence = Poses.SEQUENCES[Poses.idleSequence(fighter.id)]
			expect(sequence.upper == true, fighter.id):toBeTruthy()
			for _, key in sequence.keys do
				local pose = Poses.POSES[key.pose]
				for _, leg in { "Root", "RightHip", "LeftHip", "RightKnee", "LeftKnee" } do
					expect(pose[leg] == nil, `{key.pose}.{leg}`):toBeTruthy()
				end
			end
		end
	end)
end)

describe("Sequences", function()
	for id, sequence in Poses.SEQUENCES do
		it(`{id} is well formed`, function()
			expect(#sequence.keys):toBeAtLeast(2)
			expect(sequence.keys[1].t):toBe(0)
			local last = -1
			for _, key in sequence.keys do
				expect(key.t >= last, "keys sorted"):toBeTruthy()
				last = key.t
				expect(Poses.POSES[key.pose] ~= nil, `pose {key.pose}`):toBeTruthy()
			end
			expect(sequence.duration):toBe(last)
			expect(sequence.duration):toBeGreaterThan(0)
			expect(sequence.fadeIn + sequence.fadeOut <= sequence.duration + 0.05, "fades fit"):toBeTruthy()
		end)
	end

	it("has a held pose for every held state", function()
		for state, poseName in Poses.HELD do
			expect(Poses.POSES[poseName] ~= nil, state):toBeTruthy()
		end
	end)
end)

describe("Animation contract", function()
	for _, clip in animations.clips do
		if clip.rig == "R15" then
			it(`{clip.name} has a sequence of the clip's length`, function()
				local sequence = Poses.SEQUENCES[clip.name]
				expect(sequence ~= nil, clip.name):toBeTruthy()
				expect(sequence.duration):toBeNear(clip.seconds, 1e-6)
			end)
		end
	end

	it("lands every M1 on its clip's contact marker", function()
		local byName: { [string]: any } = {}
		for _, clip in animations.clips do
			byName[clip.name] = clip
		end
		for _, fighter in Fighters.LIST do
			local a = byName[`{fighter.id}_M1_A`]
			local finisher = byName[`{fighter.id}_M1_Finisher`]
			expect(fighter.m1.hitDelay, `{fighter.id} M1`):toBeNear(a.markers.Hit, 1e-6)
			expect(fighter.m1.finisherDelay, `{fighter.id} finisher`):toBeNear(finisher.markers.Hit, 1e-6)
		end
	end)
end)
