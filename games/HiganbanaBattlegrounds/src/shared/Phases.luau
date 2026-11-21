--!strict
-- The Five Phases (Wood, Fire, Earth, Metal, Water). Two cycles decide every matchup:
--   generating  Wood > Fire > Earth > Metal > Water > Wood   (wood feeds fire, fire makes ash, ...)
--   overcoming  Wood > Earth > Water > Fire > Metal > Wood   (roots split earth, earth dams water, ...)
-- Every pair of different phases is exactly one of Overcome / Resisted / Feeding / Drawing, so every
-- phase has the same matchup profile (phases.spec proves it).

local Constants = require("./Constants")
local Types = require("./Types")

type PhaseId = Types.PhaseId
type Relation = Types.Relation

export type PhaseInfo = {
	name: string,
	glyph: string,
	color: { number }, -- world colour, 0..255
	ui: { number }, -- readable on the dark lacquer UI, 0..255
	verb: string,
}

local Phases = {}

Phases.ORDER = { "Wood", "Fire", "Earth", "Metal", "Water" } :: { PhaseId }

local GENERATES: { [string]: PhaseId } = {
	Wood = "Fire",
	Fire = "Earth",
	Earth = "Metal",
	Metal = "Water",
	Water = "Wood",
}
Phases.GENERATES = table.freeze(GENERATES)

local OVERCOMES: { [string]: PhaseId } = {
	Wood = "Earth",
	Earth = "Water",
	Water = "Fire",
	Fire = "Metal",
	Metal = "Wood",
}
Phases.OVERCOMES = table.freeze(OVERCOMES)

Phases.INFO = table.freeze({
	Wood = { name = "Wood", glyph = "木", color = { 74, 168, 96 }, ui = { 74, 168, 96 }, verb = "roots" },
	Fire = { name = "Fire", glyph = "火", color = { 228, 72, 40 }, ui = { 228, 72, 40 }, verb = "burns" },
	Earth = { name = "Earth", glyph = "土", color = { 214, 168, 64 }, ui = { 214, 168, 64 }, verb = "buries" },
	Metal = { name = "Metal", glyph = "金", color = { 226, 230, 236 }, ui = { 226, 230, 236 }, verb = "binds" },
	Water = { name = "Water", glyph = "水", color = { 40, 52, 104 }, ui = { 91, 111, 214 }, verb = "drowns" },
}) :: { [string]: PhaseInfo }

-- Short rule text per relation, shown by the HUD's relation indicator and the select screen.
Phases.RELATION_TEXT = table.freeze({
	Overcome = "+20% damage, +50% guard damage",
	Resisted = "-15% damage",
	Feeding = "-10% damage, feeds them Ki",
	Drawing = "+50% Ki",
	Neutral = "no modifier",
}) :: { [string]: string }

function Phases.isPhase(value: unknown): boolean
	return type(value) == "string" and Phases.INFO[value] ~= nil
end

-- How a hit from `attacker` lands on `target`.
function Phases.relation(attacker: string?, target: string?): Relation
	if attacker == nil or target == nil or attacker == target then
		return "Neutral"
	end
	if Phases.OVERCOMES[attacker] == target then
		return "Overcome"
	elseif Phases.OVERCOMES[target] == attacker then
		return "Resisted"
	elseif Phases.GENERATES[attacker] == target then
		return "Feeding"
	elseif Phases.GENERATES[target] == attacker then
		return "Drawing"
	end
	return "Neutral"
end

function Phases.damageMultiplier(relation: Relation): number
	if relation == "Overcome" then
		return Constants.OVERCOME_DAMAGE
	elseif relation == "Resisted" then
		return Constants.RESISTED_DAMAGE
	elseif relation == "Feeding" then
		return Constants.FEEDING_DAMAGE
	end
	return 1
end

function Phases.guardMultiplier(relation: Relation): number
	return if relation == "Overcome" then Constants.OVERCOME_GUARD else 1
end

-- Ki multipliers for one landed hit: (attacker's gain, target's gain from feeding).
-- The attacker's Ki is KI_PER_DAMAGE_DEALT x damage x the first value; a Feeding hit also gives the
-- target that same base times the second value.
function Phases.kiMultipliers(relation: Relation): (number, number)
	if relation == "Drawing" then
		return 1 + Constants.DRAWING_KI_BONUS, 0
	elseif relation == "Feeding" then
		return 1, Constants.FEEDING_KI_TO_TARGET
	end
	return 1, 0
end

-- The phase that overcomes `phase` (the only phase that can Wound the Elder's heart).
function Phases.overcomerOf(phase: string): PhaseId?
	for attacker, target in Phases.OVERCOMES do
		if target == phase then
			return attacker :: PhaseId
		end
	end
	return nil
end

-- The phase that generates `phase` (its hits feed the Elder's heart).
function Phases.generatorOf(phase: string): PhaseId?
	for source, target in Phases.GENERATES do
		if target == phase then
			return source :: PhaseId
		end
	end
	return nil
end

function Phases.nextInCycle(phase: string): PhaseId
	return Phases.GENERATES[phase] or "Wood"
end

function Phases.color(phase: string?, forUi: boolean?): Color3
	local info = if phase then Phases.INFO[phase] else nil
	if not info then
		return Color3.fromRGB(232, 225, 210)
	end
	local rgb = if forUi then info.ui else info.color
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

return Phases
