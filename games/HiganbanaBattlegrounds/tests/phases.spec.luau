--!strict
-- The Five Phases: both cycles are single 5-cycles, every pair of phases has exactly one relation,
-- and every phase faces the same matchup profile (the "balanced by construction" claim).

local Harness = require("./harness")
local Phases = require("../src/shared/Phases")
local Constants = require("../src/shared/Constants")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local function cycleLength(map: { [string]: string }, start: string): number
	local seen, phase, steps = {}, start, 0
	repeat
		seen[phase] = true
		phase = map[phase]
		steps += 1
	until phase == start or seen[phase] or steps > 10
	return steps
end

describe("Five Phases", function()
	it("has five phases with info", function()
		expect(#Phases.ORDER):toBe(5)
		for _, phase in Phases.ORDER do
			local info = Phases.INFO[phase]
			expect(info ~= nil, phase):toBeTruthy()
			expect(#info.glyph > 0 and #info.color == 3 and #info.ui == 3, phase):toBeTruthy()
			expect(Phases.isPhase(phase)):toBeTruthy()
		end
		expect(Phases.isPhase("Void")):toBeFalsy()
	end)

	it("generating and overcoming are each one 5-cycle", function()
		for _, phase in Phases.ORDER do
			expect(cycleLength(Phases.GENERATES, phase), `generates from {phase}`):toBe(5)
			expect(cycleLength(Phases.OVERCOMES, phase), `overcomes from {phase}`):toBe(5)
		end
	end)

	it("follows the classical cycles", function()
		expect(Phases.GENERATES.Wood):toBe("Fire")
		expect(Phases.GENERATES.Water):toBe("Wood")
		expect(Phases.OVERCOMES.Wood):toBe("Earth")
		expect(Phases.OVERCOMES.Fire):toBe("Metal")
		expect(Phases.OVERCOMES.Water):toBe("Fire")
	end)

	it("gives every phase the same matchup profile", function()
		for _, attacker in Phases.ORDER do
			local tally: { [string]: number } = {}
			for _, target in Phases.ORDER do
				local relation = Phases.relation(attacker, target)
				tally[relation] = (tally[relation] or 0) + 1
			end
			expect(tally.Neutral, `{attacker} mirror`):toBe(1)
			expect(tally.Overcome, `{attacker} overcomes`):toBe(1)
			expect(tally.Resisted, `{attacker} is resisted`):toBe(1)
			expect(tally.Feeding, `{attacker} feeds`):toBe(1)
			expect(tally.Drawing, `{attacker} draws`):toBe(1)
		end
	end)

	it("pairs relations symmetrically", function()
		local inverse = { Overcome = "Resisted", Resisted = "Overcome", Feeding = "Drawing", Drawing = "Feeding" }
		for _, a in Phases.ORDER do
			for _, b in Phases.ORDER do
				if a ~= b then
					expect(Phases.relation(b, a), `{a} vs {b}`):toBe(inverse[Phases.relation(a, b)])
				end
			end
		end
	end)

	it("treats a missing phase as neutral", function()
		expect(Phases.relation(nil, "Fire")):toBe("Neutral")
		expect(Phases.relation("Fire", nil)):toBe("Neutral")
	end)

	it("maps relations to the configured multipliers", function()
		expect(Phases.damageMultiplier("Overcome")):toBe(Constants.OVERCOME_DAMAGE)
		expect(Phases.damageMultiplier("Resisted")):toBe(Constants.RESISTED_DAMAGE)
		expect(Phases.damageMultiplier("Feeding")):toBe(Constants.FEEDING_DAMAGE)
		expect(Phases.damageMultiplier("Drawing")):toBe(1)
		expect(Phases.damageMultiplier("Neutral")):toBe(1)
		expect(Phases.guardMultiplier("Overcome")):toBe(Constants.OVERCOME_GUARD)
		expect(Phases.guardMultiplier("Resisted")):toBe(1)
		local drawAttacker, drawTarget = Phases.kiMultipliers("Drawing")
		expect(drawAttacker):toBe(1 + Constants.DRAWING_KI_BONUS)
		expect(drawTarget):toBe(0)
		local feedAttacker, feedTarget = Phases.kiMultipliers("Feeding")
		expect(feedAttacker):toBe(1)
		expect(feedTarget):toBe(Constants.FEEDING_KI_TO_TARGET)
	end)

	it("finds the overcomer and generator of each phase", function()
		for _, phase in Phases.ORDER do
			local overcomer = Phases.overcomerOf(phase)
			expect(overcomer ~= nil and Phases.OVERCOMES[overcomer :: string] == phase, phase):toBeTruthy()
			local generator = Phases.generatorOf(phase)
			expect(generator ~= nil and Phases.GENERATES[generator :: string] == phase, phase):toBeTruthy()
			expect(Phases.relation(overcomer, phase), phase):toBe("Overcome")
			expect(Phases.relation(generator, phase), phase):toBe("Feeding")
		end
		expect(Phases.nextInCycle("Metal")):toBe("Water")
	end)
end)
