--!strict
local Harness = require("./harness")
local Elements = require("../src/shared/Elements")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

describe("Elements", function()
	it("has five elements, each with display info", function()
		expect(#Elements.ORDER):toBe(5)
		for _, id in Elements.ORDER do
			local info = Elements.INFO[id]
			expect(info ~= nil, id):toBeTruthy()
			expect(#info.color, id):toBe(3)
			expect(#info.glyph > 0, id):toBeTruthy()
		end
	end)

	it("makes every element beat exactly two and lose to exactly two", function()
		for _, id in Elements.ORDER do
			expect(#Elements.beatsList(id), id):toBe(2)
			expect(#Elements.beatenByList(id), id):toBe(2)
		end
	end)

	it("gives every different pair exactly one winner", function()
		for _, a in Elements.ORDER do
			for _, b in Elements.ORDER do
				if a ~= b then
					local forward = Elements.beats(a, b)
					local backward = Elements.beats(b, a)
					expect(forward ~= backward, `{a} vs {b}`):toBeTruthy()
					expect(Elements.relation(a, b), `{a} vs {b}`):toBe(-Elements.relation(b, a))
				else
					expect(Elements.beats(a, a)):toBeFalsy()
					expect(Elements.relation(a, a)):toBe(0)
				end
			end
		end
	end)

	it("matches the documented wheel", function()
		local expected = {
			Water = { "Fire", "Earth" },
			Fire = { "Wind", "Void" },
			Wind = { "Earth", "Water" },
			Earth = { "Void", "Fire" },
			Void = { "Water", "Wind" },
		}
		for attacker, victims in expected do
			for _, victim in victims do
				expect(Elements.beats(attacker, victim), `{attacker} beats {victim}`):toBeTruthy()
			end
		end
	end)

	it("scales damage and guard by the relation", function()
		expect(Elements.damageMultiplier("Water", "Fire")):toBeNear(Elements.ADVANTAGE_DAMAGE)
		expect(Elements.damageMultiplier("Fire", "Water")):toBeNear(Elements.DISADVANTAGE_DAMAGE)
		expect(Elements.damageMultiplier("Fire", "Fire")):toBeNear(1)
		expect(Elements.damageMultiplier(nil, "Fire")):toBeNear(1)
		expect(Elements.guardMultiplier("Water", "Fire")):toBeNear(Elements.ADVANTAGE_GUARD)
		expect(Elements.guardMultiplier("Fire", "Water")):toBeNear(1)
	end)

	it("rejects unknown element names", function()
		expect(Elements.isElement("Water")):toBeTruthy()
		expect(Elements.isElement("Lightning")):toBeFalsy()
		expect(Elements.isElement(5)):toBeFalsy()
		expect(Elements.beats("Lightning", "Water")):toBeFalsy()
	end)
end)
