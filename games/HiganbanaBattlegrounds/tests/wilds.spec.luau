--!strict
-- The Wilds data: islands clear of the Far Shore and of each other, bridges that start on the
-- shore and land on their island, camps inside their island, and creature attacks that name a
-- real pose sequence and carry the geometry their kind needs.

local Harness = require("./harness")
local FarShore = require("../src/shared/FarShore")
local Phases = require("../src/shared/Phases")
local Poses = require("../src/shared/Poses")
local Wilds = require("../src/shared/Wilds")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local SHORE_RADIUS = 285

local function distance(a: { number }, b: { number }): number
	local dx, dz = a[1] - b[1], a[2] - b[2]
	return math.sqrt(dx * dx + dz * dz)
end

describe("Wilds regions", function()
	it("float clear of the Far Shore and of each other", function()
		for index, region in Wilds.REGIONS do
			expect(distance(region.center, { 0, 0 }) - region.radius, region.id):toBeGreaterThan(SHORE_RADIUS + 60)
			for other = index + 1, #Wilds.REGIONS do
				local second = Wilds.REGIONS[other]
				expect(distance(region.center, second.center), region.id):toBeGreaterThan(
					region.radius + second.radius + 60
				)
			end
		end
	end)

	it("join the shore by a bridge that lands on the island", function()
		for _, region in Wilds.REGIONS do
			expect(distance(region.bridgeFrom, { 0, 0 }), region.id):toBeAtMost(SHORE_RADIUS - 40)
			expect(distance(region.bridgeTo, region.center), region.id):toBeAtMost(region.radius)
			expect(Wilds.regionAt(region.bridgeTo[1], region.bridgeTo[2]) == region, region.id):toBeTruthy()
		end
	end)

	it("keep each warden's arena on its island and name a real warden", function()
		for _, region in Wilds.REGIONS do
			expect(distance(region.arena, region.center) + region.arenaRadius, region.id):toBeAtMost(region.radius - 10)
			local boss = Wilds.creature(region.boss)
			expect(boss ~= nil and boss.boss, region.id):toBeTruthy()
			expect(Phases.isPhase(region.phase), region.id):toBeTruthy()
		end
	end)

	it("do not overlap any Far Shore zone", function()
		for _, region in Wilds.REGIONS do
			for _, zone in FarShore.ZONES do
				expect(distance(region.center, zone.center), region.id):toBeGreaterThan(region.radius + zone.radius)
			end
		end
	end)
end)

describe("Wilds camps", function()
	it("sit inside their island, clear of the arena, holding ordinary creatures", function()
		for _, camp in Wilds.CAMPS do
			local region = Wilds.region(camp.region)
			expect(region ~= nil, camp.id):toBeTruthy()
			local x, z = Wilds.campPosition(camp)
			local r = region :: Wilds.Region
			expect(distance({ x, z }, r.center), camp.id):toBeAtMost(r.radius - 40)
			expect(distance({ x, z }, r.arena), camp.id):toBeGreaterThan(r.arenaRadius + 20)
			for _, group in camp.creatures do
				local spec = Wilds.creature(group.id)
				expect(spec ~= nil and not spec.boss, `{camp.id}/{group.id}`):toBeTruthy()
				expect(group.count, camp.id):toBeAtLeast(1)
			end
		end
	end)
end)

local NEEDS: { [string]: { string } } = {
	circle = { "radius" },
	cone = { "radius", "angle" },
	lane = { "length", "width" },
	charge = { "length", "width" },
	projectile = { "speed", "length", "radius" },
	blink = { "radius", "angle" },
	donut = { "radius", "inner" },
}

describe("Wilds creatures", function()
	it("have sane stats and a phase", function()
		for id, spec in Wilds.CREATURES do
			expect(spec.id, id):toBe(id)
			expect(Phases.isPhase(spec.phase), id):toBeTruthy()
			expect(spec.health, id):toBeGreaterThan(0)
			expect(spec.walkSpeed, id):toBeGreaterThan(0)
			expect(spec.leash, id):toBeGreaterThan(spec.aggro * 0.5)
			expect(#spec.attacks, id):toBeAtLeast(2)
			if spec.boss then
				expect(spec.enrageAt ~= nil, id):toBeTruthy()
			end
		end
	end)

	it("attack with a real pose and the geometry of their kind", function()
		for id, spec in Wilds.CREATURES do
			local seen: { [string]: boolean } = {}
			for _, attack in spec.attacks do
				local name = `{id}.{attack.id}`
				expect(seen[attack.id] == nil, name):toBeTruthy()
				seen[attack.id] = true
				expect(Poses.SEQUENCES[attack.pose] ~= nil, name):toBeTruthy()
				expect(attack.windup, name):toBeGreaterThan(0.3)
				expect(attack.cooldown, name):toBeAtLeast(attack.windup)
				expect(attack.damage, name):toBeGreaterThan(0)
				for _, field in NEEDS[attack.kind] do
					expect((attack :: any)[field] ~= nil, `{name} needs {field}`):toBeTruthy()
				end
				if attack.kind == "donut" then
					expect((attack.inner :: number) < (attack.radius :: number), name):toBeTruthy()
				end
				if attack.enraged then
					expect(spec.boss, name):toBeTruthy()
				end
				expect(Wilds.attack(id, attack.id) == attack, name):toBeTruthy()
			end
		end
	end)

	it("stretch their pose so the blow lands at the end of the windup", function()
		for _, spec in Wilds.CREATURES do
			for _, attack in spec.attacks do
				local scaled = Poses.scaled(Poses.SEQUENCES[attack.pose], attack.windup)
				expect(scaled.duration, attack.id):toBeNear(Poses.SEQUENCES[attack.pose].duration * attack.windup)
				expect(scaled.fadeIn + scaled.fadeOut, attack.id):toBeAtMost(scaled.duration)
			end
		end
	end)
end)
