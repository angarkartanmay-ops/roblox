--!strict
local Harness = require("./harness")
local CombatMath = require("../src/shared/CombatMath")
local Constants = require("../src/shared/Constants")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("CombatMath.damage", function()
	it("passes neutral damage through unchanged", function()
		expect(CombatMath.damage(10, { attackerElement = "Fire", defenderElement = "Fire" })):toBeNear(10)
	end)

	it("applies element advantage and disadvantage", function()
		expect(CombatMath.damage(10, { attackerElement = "Water", defenderElement = "Fire" })):toBeNear(11.5)
		expect(CombatMath.damage(10, { attackerElement = "Fire", defenderElement = "Water" })):toBeNear(9)
	end)

	it("stacks buffs and armor", function()
		local amount = CombatMath.damage(10, { attackerMultiplier = 1.1, defenderArmor = 0.5 })
		expect(amount):toBeNear(5.5)
	end)

	it("caps armor at 90 %", function()
		expect(CombatMath.damage(10, { defenderArmor = 5 })):toBeNear(1)
	end)

	it("lets blocks stop M1s and soften abilities", function()
		expect(CombatMath.damage(10, { blocked = true, isM1 = true })):toBe(0)
		expect(CombatMath.damage(10, { blocked = true, isM1 = false })):toBeNear(10 * Constants.BLOCK_ABILITY_FACTOR)
	end)

	it("rejects invalid input", function()
		expect(CombatMath.damage(0 / 0, {})):toBe(0)
		expect(CombatMath.damage(math.huge, {})):toBe(0)
		expect(CombatMath.damage(-5, {})):toBe(0)
	end)
end)

describe("Guard and parry", function()
	it("drains guard faster with element advantage", function()
		local neutral = CombatMath.guardDamage(5, "Fire", "Fire")
		local advantaged = CombatMath.guardDamage(5, "Water", "Fire")
		expect(neutral):toBeNear(5 * Constants.GUARD_PER_DAMAGE)
		expect(advantaged):toBeGreaterThan(neutral)
	end)

	it("parries only M1s inside the window", function()
		expect(CombatMath.isParry(10, 10.1, true)):toBeTruthy()
		expect(CombatMath.isParry(10, 10 + Constants.PARRY_WINDOW + 0.05, true)):toBeFalsy()
		expect(CombatMath.isParry(10, 10.1, false)):toBeFalsy()
		expect(CombatMath.isParry(nil, 10.1, true)):toBeFalsy()
	end)

	it("regenerates guard only after the delay and never above max", function()
		expect(CombatMath.regenGuard(50, 1, 0.5)):toBe(50)
		expect(CombatMath.regenGuard(50, 1, Constants.GUARD_REGEN_DELAY + 0.1)):toBeNear(50 + Constants.GUARD_REGEN)
		expect(CombatMath.regenGuard(99, 10, 10)):toBe(Constants.GUARD_MAX)
	end)
end)

describe("Resonance and rewards", function()
	it("fills faster from dealing than taking damage", function()
		expect(CombatMath.resonanceGain(10, "dealt")):toBeGreaterThan(CombatMath.resonanceGain(10, "taken"))
		expect(CombatMath.resonanceGain(-3, "dealt")):toBe(0)
	end)

	it("clamps the meter", function()
		expect(CombatMath.addResonance(95, 20)):toBe(Constants.RESONANCE_MAX)
		expect(CombatMath.addResonance(5, -20)):toBe(0)
	end)

	it("pays streak bonuses from the third kill", function()
		expect(CombatMath.killReward(1)):toBe(Constants.SHARDS_PER_KILL)
		expect(CombatMath.killReward(2)):toBe(Constants.SHARDS_PER_KILL)
		expect(CombatMath.killReward(4)):toBe(Constants.SHARDS_PER_KILL + 2 * Constants.SHARDS_PER_STREAK_STEP)
		expect(CombatMath.isStreakAnnounced(5)):toBeTruthy()
		expect(CombatMath.isStreakAnnounced(4)):toBeFalsy()
	end)
end)

describe("Combo chain", function()
	it("advances, resets after the finisher, and resets after idling", function()
		expect(CombatMath.nextComboIndex(0, nil, 1)):toBe(1)
		expect(CombatMath.nextComboIndex(1, 1, 1.3)):toBe(2)
		expect(CombatMath.nextComboIndex(3, 1, 1.3)):toBe(4)
		expect(CombatMath.nextComboIndex(4, 1, 1.3)):toBe(1)
		expect(CombatMath.nextComboIndex(2, 1, 1 + Constants.COMBO_RESET + 0.01)):toBe(1)
	end)
end)

describe("Hit geometry", function()
	it("tests boxes with tolerance", function()
		expect(CombatMath.insideBox(0, 0, 0, 4, 4, 4, 0)):toBeTruthy()
		expect(CombatMath.insideBox(2.5, 0, 0, 4, 4, 4, 0)):toBeFalsy()
		expect(CombatMath.insideBox(2.5, 0, 0, 4, 4, 4, 1)):toBeTruthy()
	end)

	it("tests spheres with tolerance", function()
		expect(CombatMath.insideSphere(3, 4, 0, 5, 0)):toBeTruthy()
		expect(CombatMath.insideSphere(3, 4, 0.1, 5, 0)):toBeFalsy()
		expect(CombatMath.insideSphere(3, 4, 0.1, 5, 0.5)):toBeTruthy()
	end)

	it("measures point-to-segment distance", function()
		expect(CombatMath.segmentDistance(0, 1, 0, -1, 0, 0, 1, 0, 0)):toBeNear(1)
		expect(CombatMath.segmentDistance(3, 0, 0, -1, 0, 0, 1, 0, 0)):toBeNear(2)
		expect(CombatMath.segmentDistance(2, 2, 2, 2, 2, 2, 2, 2, 2)):toBeNear(0)
	end)

	it("only blocks attacks from the front", function()
		-- Blocker faces -Z. Attacker in front (toward -Z) is blocked, behind is not.
		expect(CombatMath.blockFacesAttacker(0, -1, 0, -5)):toBeTruthy()
		expect(CombatMath.blockFacesAttacker(0, -1, 0, 5)):toBeFalsy()
		expect(CombatMath.blockFacesAttacker(0, -1, 5, -0.5)):toBeFalsy()
	end)
end)

describe("Movement", function()
	it("slows blockers and stops them jumping", function()
		local speed, canJump = CombatMath.movement(16, { stunned = false, blocking = true })
		expect(speed):toBeNear(16 * Constants.BLOCK_WALK_FACTOR, 0.01)
		expect(canJump):toBeFalsy()
	end)

	it("pins stunned fighters to stun speed", function()
		local speed, canJump = CombatMath.movement(16, { stunned = true, blocking = false, slowFactor = 0.5 })
		expect(speed):toBe(Constants.STUN_WALK_SPEED)
		expect(canJump):toBeFalsy()
	end)

	it("stacks action, slow and armor factors", function()
		local speed, canJump = CombatMath.movement(20, {
			stunned = false,
			blocking = false,
			actionSlow = 0.5,
			slowFactor = 0.5,
			armorSlow = 0.8,
		})
		expect(speed):toBeNear(4, 0.01)
		expect(canJump):toBeTruthy()
	end)

	it("roots completely", function()
		local speed = CombatMath.movement(16, { stunned = false, blocking = false, rooted = true })
		expect(speed):toBe(0)
	end)
end)
