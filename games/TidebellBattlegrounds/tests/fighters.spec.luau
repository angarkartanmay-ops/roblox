--!strict
-- Validates the roster data: every move is complete, references real poses and effects,
-- and fits the rules the server executes.

local Harness = require("./harness")
local Fighters = require("../src/shared/Fighters")
local Elements = require("../src/shared/Elements")
local Poses = require("../src/shared/Poses")
local VfxCatalog = require("../src/shared/VfxCatalog")
local Constants = require("../src/shared/Constants")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function isPositive(value: unknown): boolean
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function isNonNegative(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

describe("Roster", function()
	it("has five champions with unique ids and one champion per element", function()
		expect(#Fighters.LIST):toBe(5)
		local ids, elements = {}, {}
		for _, fighter in Fighters.LIST do
			expect(ids[fighter.id] == nil, fighter.id):toBeTruthy()
			ids[fighter.id] = true
			expect(Elements.isElement(fighter.element), fighter.id):toBeTruthy()
			expect(elements[fighter.element] == nil, fighter.element):toBeTruthy()
			elements[fighter.element] = true
		end
	end)

	it("resolves lookups", function()
		expect(Fighters.get(Fighters.DEFAULT_ID) ~= nil):toBeTruthy()
		expect(Fighters.get("Nobody") == nil):toBeTruthy()
		expect(Fighters.getOrDefault("Nobody").id):toBe(Fighters.DEFAULT_ID)
		expect(Fighters.m1MoveId(3)):toBe("M1_3")
		expect(Fighters.parseM1("M1_3")):toBe(3)
		expect(Fighters.parseM1("QuakeStomp") == nil):toBeTruthy()
	end)
end)

for _, fighter in Fighters.LIST do
	describe(fighter.displayName, function()
		it("has sane stats", function()
			expect(fighter.maxHealth):toBeAtLeast(80)
			expect(fighter.maxHealth):toBeAtMost(130)
			expect(fighter.walkSpeed):toBeAtLeast(12)
			expect(fighter.walkSpeed):toBeAtMost(20)
			expect(#fighter.color):toBe(3)
			expect(#fighter.accent):toBe(3)
			expect(fighter.difficulty):toBeAtLeast(1)
			expect(fighter.difficulty):toBeAtMost(3)
			expect(VfxCatalog.WEAPON_SET[fighter.weapon] == true, fighter.weapon):toBeTruthy()
		end)

		it("has a four-hit M1 chain with an animation per hit", function()
			local m1 = fighter.m1
			expect(#m1.damage):toBe(Constants.COMBO_HITS)
			expect(#m1.size):toBe(3)
			expect(isPositive(m1.interval)):toBeTruthy()
			expect(m1.hitDelay < m1.interval, "hit lands before the next swing"):toBeTruthy()
			for index = 1, Constants.COMBO_HITS do
				expect(isPositive(m1.damage[index]), `damage {index}`):toBeTruthy()
				local sequenceId = Poses.m1Sequence(m1.style, index)
				expect(Poses.SEQUENCES[sequenceId] ~= nil, sequenceId):toBeTruthy()
			end
		end)

		it("fills every ability slot and the ultimate exactly once", function()
			expect(#fighter.moves):toBe(#Fighters.SLOTS)
			for index, slot in Fighters.SLOTS do
				expect(fighter.moves[index].slot, `slot order {index}`):toBe(slot)
				expect(Fighters.moveForSlot(fighter, slot) ~= nil, slot):toBeTruthy()
			end
		end)

		for _, move in fighter.moves do
			it(`{move.id} is complete and consistent`, function()
				expect(Fighters.findMove(fighter, move.id) == move):toBeTruthy()
				expect(#move.name > 0 and #move.description > 10, "text"):toBeTruthy()
				expect(isNonNegative(move.cooldown), "cooldown"):toBeTruthy()
				if move.slot ~= "Ultimate" then
					expect(move.cooldown, "ability cooldown"):toBeAtLeast(5)
				end
				expect(isPositive(move.lock), "lock"):toBeTruthy()
				expect(Poses.SEQUENCES[move.pose] ~= nil, `pose {move.pose}`):toBeTruthy()
				expect(VfxCatalog.MOVE_SET[move.vfx] == true, `vfx {move.vfx}`):toBeTruthy()
				if move.moveSlow ~= nil then
					expect(move.moveSlow >= 0 and move.moveSlow <= 1, "moveSlow"):toBeTruthy()
				end

				local hits = move.hits or {}
				local projectiles = move.projectiles or {}
				local doesSomething = #hits > 0 or #projectiles > 0 or move.special ~= nil
				expect(doesSomething, "move must hit, shoot or run a special"):toBeTruthy()

				if move.special then
					expect(VfxCatalog.SPECIAL_SET[move.special] == true, `special {move.special}`):toBeTruthy()
				end

				local lastAt = -1
				local usesPoint = false
				for index, hit in hits do
					local label = `hit {index}`
					expect(hit.at >= lastAt, `{label} sorted`):toBeTruthy()
					lastAt = hit.at
					expect(isNonNegative(hit.at), label):toBeTruthy()
					expect(hit.at <= move.lock + 0.6, `{label} lands close to the lock window`):toBeTruthy()
					expect(isPositive(hit.damage), `{label} damage`):toBeTruthy()
					expect(isNonNegative(hit.stun), `{label} stun`):toBeTruthy()
					if hit.shape == "Box" then
						expect(hit.size ~= nil and #(hit.size :: { number }) == 3, `{label} size`):toBeTruthy()
					elseif hit.shape == "Sphere" then
						expect(isPositive(hit.radius), `{label} radius`):toBeTruthy()
					else
						error(`{label} has unknown shape {hit.shape}`)
					end
					if hit.anchor == "point" then
						usesPoint = true
					end
					if hit.slow then
						expect(hit.slow.factor > 0 and hit.slow.factor < 1, `{label} slow factor`):toBeTruthy()
					end
				end
				if usesPoint then
					expect(isPositive(move.pointForward), "point anchor needs pointForward"):toBeTruthy()
				end

				for index, projectile in projectiles do
					local label = `projectile {index}`
					expect(VfxCatalog.PROJECTILE_SET[projectile.kind] == true, `{label} kind {projectile.kind}`):toBeTruthy()
					expect(isPositive(projectile.speed), `{label} speed`):toBeTruthy()
					expect(isPositive(projectile.radius), `{label} radius`):toBeTruthy()
					expect(isPositive(projectile.range), `{label} range`):toBeTruthy()
					expect(isPositive(projectile.damage), `{label} damage`):toBeTruthy()
					expect(projectile.at <= move.lock, `{label} fires within the lock`):toBeTruthy()
					if projectile.explode then
						expect(isPositive(projectile.explode.radius), `{label} explosion`):toBeTruthy()
					end
				end

				if move.self then
					expect(isPositive(move.self.impulse.duration), "self impulse duration"):toBeTruthy()
					expect(move.self.impulse.duration <= 0.5, "self impulse is short"):toBeTruthy()
				end
			end)
		end

		it("gives the ultimate super armor", function()
			local ultimate = Fighters.moveForSlot(fighter, "Ultimate")
			expect(ultimate ~= nil and ultimate.superArmor == true, "ultimates have super armor"):toBeTruthy()
		end)
	end)
end
