--!strict
-- Pure combat rules: damage through the Five Phases, guard, parry, Ki and Mend, the fighter
-- passives' counters, the Elder's heart, hit geometry and movement speed.
-- No Roblox globals, so every rule here is covered by Lune specs.

local Constants = require("./Constants")
local Phases = require("./Phases")
local Types = require("./Types")

type Relation = Types.Relation

local CombatMath = {}

export type DamageContext = {
	relation: Relation?,
	attackerMultiplier: number?, -- Elder's Sap, a Rhythm Beat
	defenderArmor: number?, -- 0..1 damage reduction
	blocked: boolean?,
	isM1: boolean?,
}

local function roundTenth(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end
CombatMath.roundTenth = roundTenth

function CombatMath.isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Final damage of one hit after the phase relation, buffs, armour and block.
function CombatMath.damage(base: number, context: DamageContext): number
	if not CombatMath.isFiniteNumber(base) or base <= 0 then
		return 0
	end
	local amount = base * Phases.damageMultiplier(context.relation or "Neutral")
	amount *= context.attackerMultiplier or 1
	amount *= 1 - math.clamp(context.defenderArmor or 0, 0, 0.9)
	if context.blocked then
		if context.isM1 then
			return 0
		end
		amount *= Constants.BLOCK_ABILITY_FACTOR
	end
	return roundTenth(amount)
end

-- Guard drained from a blocker by a hit of `base` damage.
function CombatMath.guardDamage(base: number, relation: Relation?, extra: number?): number
	if not CombatMath.isFiniteNumber(base) or base <= 0 then
		return 0
	end
	return base * Constants.GUARD_PER_DAMAGE * Phases.guardMultiplier(relation or "Neutral") * (extra or 1)
end

-- An M1 that lands within PARRY_WINDOW of raising the block is parried.
function CombatMath.isParry(blockStartedAt: number?, now: number, isM1: boolean): boolean
	if not isM1 or blockStartedAt == nil then
		return false
	end
	local elapsed = now - blockStartedAt
	return elapsed >= 0 and elapsed <= Constants.PARRY_WINDOW
end

function CombatMath.regenGuard(guard: number, dt: number, sinceDamaged: number): number
	if sinceDamaged < Constants.GUARD_REGEN_DELAY then
		return guard
	end
	return math.min(Constants.GUARD_MAX, guard + Constants.GUARD_REGEN * dt)
end

---------------------------------------------------------------------------------------------------
-- Ki

-- Ki earned by one landed hit of `damage`: (attacker's gain, target's gain).
-- The target always gains KI_PER_DAMAGE_TAKEN; a Feeding hit adds half the attacker's base on top;
-- a Drawing hit gives the attacker +50%.
function CombatMath.kiForHit(damage: number, relation: Relation?): (number, number)
	if not CombatMath.isFiniteNumber(damage) or damage <= 0 then
		return 0, 0
	end
	local attackerMul, feedMul = Phases.kiMultipliers(relation or "Neutral")
	local base = damage * Constants.KI_PER_DAMAGE_DEALT
	return base * attackerMul, damage * Constants.KI_PER_DAMAGE_TAKEN + base * feedMul
end

function CombatMath.addKi(current: number, gain: number): number
	if not CombatMath.isFiniteNumber(gain) then
		return current
	end
	return math.clamp(current + gain, 0, Constants.KI_MAX)
end

-- One Mend tick: Ki spent and health restored over `dt` seconds.
-- `rateBonus` is the Elder's Sap bonus (0.2 = 20% faster). Never spends more Ki than is held and
-- never heals past the missing health.
function CombatMath.mendStep(ki: number, missingHealth: number, dt: number, rateBonus: number?): (number, number)
	if ki <= 0 or missingHealth <= 0 or dt <= 0 then
		return 0, 0
	end
	local rate = Constants.MEND_KI_PER_SECOND * (1 + (rateBonus or 0))
	local spend = math.min(ki, rate * dt, missingHealth / Constants.MEND_HEALTH_PER_KI)
	return spend, spend * Constants.MEND_HEALTH_PER_KI
end

function CombatMath.canMend(now: number, lastHitTakenAt: number, purifiedUntil: number): boolean
	return now - lastHitTakenAt >= Constants.MEND_LOCKOUT and purifiedUntil <= now
end

---------------------------------------------------------------------------------------------------
-- Passives

-- Hibiki's Rhythm: the running count after landing a hit at `now`, and whether that hit is a Beat.
-- `forced` is Kakegoe's "next hit is a Beat".
function CombatMath.rhythm(count: number, lastHitAt: number?, now: number, forced: boolean?): (number, boolean)
	local nextCount = if lastHitAt ~= nil and now - lastHitAt <= Constants.HIBIKI_RHYTHM_WINDOW then count + 1 else 1
	local beat = forced == true or nextCount % Constants.HIBIKI_BEAT_EVERY == 0
	return nextCount, beat
end

-- Rokumon's Fare: (hit counter, coins) after one more landed hit.
function CombatMath.fare(hits: number, coins: number): (number, number)
	local nextHits = hits + 1
	if nextHits >= Constants.ROKUMON_HITS_PER_COIN then
		return 0, math.min(coins + 1, Constants.ROKUMON_MAX_COINS)
	end
	return nextHits, coins
end

function CombatMath.tollDamage(base: number, coins: number): number
	return base + Constants.ROKUMON_TOLL_PER_COIN * math.clamp(coins, 0, Constants.ROKUMON_MAX_COINS)
end

-- Tsuta's Sprout: (stacks after this hit, burst?) — a burst consumes the stacks.
function CombatMath.sprout(stacks: number): (number, boolean)
	local nextStacks = stacks + 1
	if nextStacks >= Constants.TSUTA_SPROUT_BURST then
		return 0, true
	end
	return nextStacks, false
end

function CombatMath.knockbackTaken(fighterId: string?): number
	return if fighterId == "Iwao" then Constants.IWAO_KNOCKBACK_TAKEN else 1
end

---------------------------------------------------------------------------------------------------
-- The Thirsting Elder

export type ElderHit = "Wound" | "Feed" | "Normal"

-- How a hit of `damage` from `attackerPhase` lands on the Elder's `heart`:
-- (kind, damage to deal, health to restore).
function CombatMath.elderHit(damage: number, attackerPhase: string?, heart: string): (ElderHit, number, number)
	if damage <= 0 then
		return "Normal", 0, 0
	end
	local relation = Phases.relation(attackerPhase, heart)
	if relation == "Overcome" then
		return "Wound", roundTenth(damage * Constants.ELDER_OVERCOME_BONUS), 0
	elseif relation == "Feeding" then
		return "Feed", 0, roundTenth(damage * Constants.ELDER_FEEDING_HEAL)
	end
	return "Normal", damage, 0
end

function CombatMath.elderHealth(players: number): number
	return Constants.ELDER_HEALTH_BASE + Constants.ELDER_HEALTH_PER_PLAYER * math.max(players, 1)
end

function CombatMath.thirstThreshold(players: number): number
	return Constants.THIRST_BASE + Constants.THIRST_PER_PLAYER * math.max(players, 1)
end

-- May the Elder wake now?
function CombatMath.elderMayWake(thirst: number, players: number, sinceStart: number, sinceFall: number?): boolean
	if players <= 0 or sinceStart < Constants.THIRST_FIRST_AWAKE then
		return false
	end
	if sinceFall ~= nil and sinceFall < Constants.THIRST_COOLDOWN_AFTER_FALL then
		return false
	end
	return thirst >= CombatMath.thirstThreshold(players)
end

-- The heart's phase `elapsed` seconds into an awakening that began on `first`.
function CombatMath.heartPhase(first: string, elapsed: number, period: number): string
	local steps = math.floor(math.max(elapsed, 0) / period)
	local phase = first
	for _ = 1, steps % 5 do
		phase = Phases.nextInCycle(phase)
	end
	return phase
end

-- Players whose share of the Elder's health earns the reward, and the top dealer.
function CombatMath.elderRewards(damageBy: { [string]: number }, maxHealth: number): ({ string }, string?)
	local earned = {}
	local top: string? = nil
	local best = 0
	for name, dealt in damageBy do
		if dealt >= maxHealth * Constants.ELDER_REWARD_MIN_SHARE then
			table.insert(earned, name)
		end
		if dealt > best then
			best = dealt
			top = name
		end
	end
	table.sort(earned)
	return earned, top
end

---------------------------------------------------------------------------------------------------
-- Chains, geometry, movement, rewards

function CombatMath.nextComboIndex(previousIndex: number, lastSwingAt: number?, now: number): number
	if lastSwingAt == nil or now - lastSwingAt > Constants.COMBO_RESET or previousIndex >= Constants.COMBO_HITS then
		return 1
	end
	return previousIndex + 1
end

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

function CombatMath.blockFacesAttacker(lx: number, lz: number, tx: number, tz: number): boolean
	local lookLength = math.sqrt(lx * lx + lz * lz)
	local toLength = math.sqrt(tx * tx + tz * tz)
	if lookLength < 1e-6 or toLength < 1e-6 then
		return true
	end
	return (lx * tx + lz * tz) / (lookLength * toLength) >= Constants.BLOCK_FACING_DOT
end

export type MovementState = {
	stunned: boolean,
	blocking: boolean,
	actionSlow: number?,
	slowFactor: number?,
	speedBonus: number?, -- Kakegoe +0.2
	mending: boolean?,
	rooted: boolean?,
}

function CombatMath.movement(baseSpeed: number, state: MovementState): (number, boolean)
	if state.rooted then
		return 0, false
	end
	if state.stunned then
		return Constants.STUN_WALK_SPEED, false
	end
	local speed = baseSpeed * (1 + (state.speedBonus or 0))
	local canJump = true
	if state.blocking then
		speed *= Constants.BLOCK_WALK_FACTOR
		canJump = false
	end
	if state.mending then
		speed *= Constants.MEND_SPEED
		canJump = false
	end
	if state.actionSlow then
		speed *= math.clamp(state.actionSlow, 0, 1)
	end
	if state.slowFactor then
		speed *= math.clamp(state.slowFactor, 0, 1)
	end
	return speed, canJump
end

-- Petals for a kill that brings the killer's streak to `streak`.
function CombatMath.killReward(streak: number): number
	return Constants.PETALS_PER_KILL + Constants.PETALS_PER_STREAK_STEP * math.max(0, streak - 2)
end

function CombatMath.isStreakAnnounced(streak: number): boolean
	return table.find(Constants.STREAK_ANNOUNCE, streak) ~= nil
end

return CombatMath
