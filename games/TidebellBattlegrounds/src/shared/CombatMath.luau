--!strict
-- Pure combat rules: damage, guard, parry, resonance, hit geometry and movement speed.
-- No Roblox globals, so every rule here is covered by Lune tests.

local Constants = require("./Constants")
local Elements = require("./Elements")

local CombatMath = {}

export type DamageContext = {
	attackerElement: string?,
	defenderElement: string?,
	attackerMultiplier: number?, -- buffs such as Tide-Blessed
	defenderArmor: number?, -- 0-1 damage reduction (Stone Skin)
	blocked: boolean?,
	isM1: boolean?,
}

local function roundTenth(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

function CombatMath.isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Final damage of one hit after element, buffs, armor and block.
function CombatMath.damage(base: number, context: DamageContext): number
	if not CombatMath.isFiniteNumber(base) or base <= 0 then
		return 0
	end
	local amount = base * Elements.damageMultiplier(context.attackerElement, context.defenderElement)
	amount *= context.attackerMultiplier or 1
	local armor = math.clamp(context.defenderArmor or 0, 0, 0.9)
	amount *= 1 - armor
	if context.blocked then
		if context.isM1 then
			return 0
		end
		amount *= Constants.BLOCK_ABILITY_FACTOR
	end
	return roundTenth(amount)
end

-- Guard drained from a blocker by a hit of `base` damage.
function CombatMath.guardDamage(base: number, attackerElement: string?, defenderElement: string?): number
	if not CombatMath.isFiniteNumber(base) or base <= 0 then
		return 0
	end
	return base * Constants.GUARD_PER_DAMAGE * Elements.guardMultiplier(attackerElement, defenderElement)
end

-- An M1 that lands within PARRY_WINDOW of raising the block is parried.
function CombatMath.isParry(blockStartedAt: number?, now: number, isM1: boolean): boolean
	if not isM1 or blockStartedAt == nil then
		return false
	end
	local elapsed = now - blockStartedAt
	return elapsed >= 0 and elapsed <= Constants.PARRY_WINDOW
end

-- Guard after `dt` seconds of regeneration, given how long ago it last took damage.
function CombatMath.regenGuard(guard: number, dt: number, sinceDamaged: number): number
	if sinceDamaged < Constants.GUARD_REGEN_DELAY then
		return guard
	end
	return math.min(Constants.GUARD_MAX, guard + Constants.GUARD_REGEN * dt)
end

function CombatMath.resonanceGain(damage: number, role: "dealt" | "taken"): number
	if not CombatMath.isFiniteNumber(damage) or damage <= 0 then
		return 0
	end
	return damage * (if role == "dealt" then Constants.RESONANCE_DEALT else Constants.RESONANCE_TAKEN)
end

function CombatMath.addResonance(current: number, gain: number): number
	return math.clamp(current + gain, 0, Constants.RESONANCE_MAX)
end

-- Next M1 chain index (1..COMBO_HITS). The chain restarts after COMBO_RESET seconds or after the finisher.
function CombatMath.nextComboIndex(previousIndex: number, lastSwingAt: number?, now: number): number
	if lastSwingAt == nil or now - lastSwingAt > Constants.COMBO_RESET or previousIndex >= Constants.COMBO_HITS then
		return 1
	end
	return previousIndex + 1
end

-- Is a point (in the box's local space) inside a box of size (sx, sy, sz), padded by `tolerance`?
function CombatMath.insideBox(
	lx: number,
	ly: number,
	lz: number,
	sx: number,
	sy: number,
	sz: number,
	tolerance: number
): boolean
	return math.abs(lx) <= sx / 2 + tolerance
		and math.abs(ly) <= sy / 2 + tolerance
		and math.abs(lz) <= sz / 2 + tolerance
end

function CombatMath.insideSphere(dx: number, dy: number, dz: number, radius: number, tolerance: number): boolean
	local reach = radius + tolerance
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

-- Distance from point P to the segment A-B.
function CombatMath.segmentDistance(
	px: number,
	py: number,
	pz: number,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): number
	local abx, aby, abz = bx - ax, by - ay, bz - az
	local apx, apy, apz = px - ax, py - ay, pz - az
	local lengthSquared = abx * abx + aby * aby + abz * abz
	local t = 0
	if lengthSquared > 1e-9 then
		t = math.clamp((apx * abx + apy * aby + apz * abz) / lengthSquared, 0, 1)
	end
	local cx, cy, cz = ax + abx * t - px, ay + aby * t - py, az + abz * t - pz
	return math.sqrt(cx * cx + cy * cy + cz * cz)
end

-- A block only stops hits from the front: the blocker's facing (lx, lz) against the direction
-- toward the attacker (tx, tz), both on the ground plane.
function CombatMath.blockFacesAttacker(lx: number, lz: number, tx: number, tz: number): boolean
	local lookLength = math.sqrt(lx * lx + lz * lz)
	local toLength = math.sqrt(tx * tx + tz * tz)
	if lookLength < 1e-6 or toLength < 1e-6 then
		return true -- attacker on top of the blocker: count it as frontal
	end
	return (lx * tx + lz * tz) / (lookLength * toLength) >= Constants.BLOCK_FACING_DOT
end

export type MovementState = {
	stunned: boolean,
	blocking: boolean,
	actionSlow: number?, -- factor while a move runs
	slowFactor: number?, -- Slow status
	armorSlow: number?, -- Stone Skin
	rooted: boolean?,
}

-- Walk speed and whether jumping is allowed for a fighter in `state`.
function CombatMath.movement(baseSpeed: number, state: MovementState): (number, boolean)
	if state.rooted then
		return 0, false
	end
	if state.stunned then
		return Constants.STUN_WALK_SPEED, false
	end
	local speed = baseSpeed
	local canJump = true
	if state.blocking then
		speed *= Constants.BLOCK_WALK_FACTOR
		canJump = false
	end
	if state.actionSlow then
		speed *= math.clamp(state.actionSlow, 0, 1)
	end
	if state.slowFactor then
		speed *= math.clamp(state.slowFactor, 0, 1)
	end
	if state.armorSlow then
		speed *= math.clamp(state.armorSlow, 0, 1)
	end
	return math.floor(speed * 100 + 0.5) / 100, canJump
end

-- Shards for a kill that brings the killer's streak to `streak`.
function CombatMath.killReward(streak: number): number
	local bonusSteps = math.max(0, streak - 2)
	return Constants.SHARDS_PER_KILL + bonusSteps * Constants.SHARDS_PER_STREAK_STEP
end

function CombatMath.isStreakAnnounced(streak: number): boolean
	for _, value in Constants.STREAK_ANNOUNCE do
		if value == streak then
			return true
		end
	end
	return false
end

return CombatMath
