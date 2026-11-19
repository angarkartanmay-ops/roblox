--!strict
local Harness = require("./harness")
local Poses = require("../src/shared/Poses")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local KNOWN_JOINTS: { [string]: boolean } = {}
for _, joint in Poses.JOINTS do
	KNOWN_JOINTS[joint] = true
end

local FIELDS = { rx = true, ry = true, rz = true, px = true, py = true, pz = true }

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
