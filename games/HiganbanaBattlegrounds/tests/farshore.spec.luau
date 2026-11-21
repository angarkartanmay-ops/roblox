--!strict
-- The code's view of the map (src/shared/FarShore) must agree with the map spec (design/map.json).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Harness = require("./harness")
local FarShore = require("../src/shared/FarShore")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local map = serde.decode("json", fs.readFile("design/map.json"))

local RULES = { FerryLanding = "safe", JizoBeach = "nopvp" }

local function partNamed(id: string): any
	for _, part in map.parts do
		if part.id == id then
			return part
		end
	end
	error(`map.json has no part {id}`)
end

describe("Far Shore data", function()
	it("has every map zone with the same centre, radius and rule", function()
		expect(#FarShore.ZONES):toBe(#map.terrain.zones)
		for _, spec in map.terrain.zones do
			local found = nil
			for _, zone in FarShore.ZONES do
				if zone.name == spec.name then
					found = zone
				end
			end
			expect(found ~= nil, spec.name):toBeTruthy()
			local zone = found :: FarShore.Zone
			expect(zone.center[1], spec.name):toBe(spec.center[1])
			expect(zone.center[2], spec.name):toBe(spec.center[2])
			expect(zone.radius, spec.name):toBe(spec.radius)
			expect(zone.rule, spec.name):toBe(RULES[spec.name] or "ffa")
		end
	end)

	it("spawns where the map spawns", function()
		expect(#FarShore.SPAWNS):toBe(#map.spawns)
		for index, spawn in map.spawns do
			for axis = 1, 3 do
				expect(FarShore.SPAWNS[index][axis], `spawn {index}`):toBe(spawn[axis])
			end
		end
	end)

	it("uses the map's kill plane and ring-out line", function()
		expect(FarShore.KILL_PLANE):toBe(map.volume.killPlane)
		expect(FarShore.RING_OUT_Y):toBe(map.volume.killPlane + map.volume.ringOutOffset)
	end)

	it("lifts spec heights into the world by the map's lift", function()
		expect(FarShore.LIFT):toBe(map.volume.lift)
		local x, y, z = FarShore.world({ 1, 2, 3 })
		expect(x):toBe(1)
		expect(y):toBe(2 + map.volume.lift)
		expect(z):toBe(3)
	end)

	it("anchors the Elder on its trunk block and the lantern on its part", function()
		local trunk = partNamed("ElderTrunkBlock")
		expect(FarShore.ELDER_ANCHOR[1]):toBe(trunk.pos[1])
		expect(FarShore.ELDER_ANCHOR[2]):toBe(trunk.pos[2] - trunk.size[2] / 2)
		expect(FarShore.ELDER_ANCHOR[3]):toBe(trunk.pos[3])
		local lantern = partNamed("SelectLantern")
		for axis = 1, 3 do
			expect(FarShore.SELECT_LANTERN[axis]):toBe(lantern.pos[axis])
		end
	end)

	it("puts the dummies on Jizo Beach", function()
		local zone = FarShore.zoneAt(FarShore.DUMMY_CENTER[1], FarShore.DUMMY_CENTER[3])
		expect(zone ~= nil and zone.name == "JizoBeach"):toBeTruthy()
	end)

	it("answers zone queries", function()
		expect(FarShore.ruleAt(0, 150)):toBe("safe")
		expect(FarShore.ruleAt(-196, 40)):toBe("nopvp")
		expect(FarShore.ruleAt(60, -8)):toBe("ffa")
		expect(FarShore.ruleAt(-300, 300)):toBe("ffa")
		expect(FarShore.zoneAt(-300, 300) == nil):toBeTruthy()
	end)
end)
