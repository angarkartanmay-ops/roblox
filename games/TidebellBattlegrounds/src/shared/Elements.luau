--!strict
-- The element wheel. Five Great Elements (godai); every different pair has a winner.
-- Arranged in a circle, each element beats the next one and the one three steps on,
-- so each beats two and loses to two.

local Types = require("./Types")

type ElementId = Types.ElementId

export type ElementInfo = {
	id: ElementId,
	glyph: string,
	color: { number },
	verb: string, -- flavour shown on the wheel
}

local Elements = {}

Elements.ORDER = { "Water", "Fire", "Wind", "Earth", "Void" } :: { ElementId }

Elements.INFO = {
	Earth = { id = "Earth", glyph = "地", color = { 0.84, 0.58, 0.28 }, verb = "anchors the void, smothers flame" },
	Water = { id = "Water", glyph = "水", color = { 0.22, 0.78, 0.9 }, verb = "douses fire, erodes stone" },
	Fire = { id = "Fire", glyph = "火", color = { 1, 0.45, 0.2 }, verb = "devours the air, lights the dark" },
	Wind = { id = "Wind", glyph = "風", color = { 0.62, 0.96, 0.76 }, verb = "scours stone, scatters the sea" },
	Void = { id = "Void", glyph = "空", color = { 0.66, 0.5, 1 }, verb = "swallows the tide, stills the wind" },
} :: { [string]: ElementInfo }

Elements.ADVANTAGE_DAMAGE = 1.15
Elements.DISADVANTAGE_DAMAGE = 0.9
Elements.ADVANTAGE_GUARD = 1.5

local indexOf: { [string]: number } = {}
for index, id in Elements.ORDER do
	indexOf[id] = index - 1
end

function Elements.isElement(value: unknown): boolean
	return type(value) == "string" and indexOf[value] ~= nil
end

-- True when `attacker` beats `defender`.
function Elements.beats(attacker: string, defender: string): boolean
	local a, d = indexOf[attacker], indexOf[defender]
	if a == nil or d == nil or a == d then
		return false
	end
	local step = (d - a) % 5
	return step == 1 or step == 3
end

-- 1 when the attacker has the advantage, -1 when the defender has it, 0 otherwise.
function Elements.relation(attacker: string?, defender: string?): number
	if attacker == nil or defender == nil then
		return 0
	end
	if Elements.beats(attacker, defender) then
		return 1
	elseif Elements.beats(defender, attacker) then
		return -1
	end
	return 0
end

function Elements.damageMultiplier(attacker: string?, defender: string?): number
	local relation = Elements.relation(attacker, defender)
	if relation > 0 then
		return Elements.ADVANTAGE_DAMAGE
	elseif relation < 0 then
		return Elements.DISADVANTAGE_DAMAGE
	end
	return 1
end

function Elements.guardMultiplier(attacker: string?, defender: string?): number
	return if Elements.relation(attacker, defender) > 0 then Elements.ADVANTAGE_GUARD else 1
end

-- The two elements `element` beats, in wheel order.
function Elements.beatsList(element: string): { ElementId }
	local list = {}
	for _, other in Elements.ORDER do
		if Elements.beats(element, other) then
			table.insert(list, other)
		end
	end
	return list
end

-- The two elements that beat `element`, in wheel order.
function Elements.beatenByList(element: string): { ElementId }
	local list = {}
	for _, other in Elements.ORDER do
		if Elements.beats(other, element) then
			table.insert(list, other)
		end
	end
	return list
end

return Elements
