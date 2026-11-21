--!strict
-- Server-authoritative combat: validates intents, runs M1 chains and move timelines, resolves hits
-- through the Five Phases (Overcome / Resisted / Feeding / Drawing), block, parry and guard break,
-- the fighters' passives (Rhythm, Fare, Arrest, Rooted, Sprout, Graft), statuses and the
-- thirteen special moves. Clients only send intents (slot + aim); every outcome is decided here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Types = require(ReplicatedStorage.Shared.Types)
local Hitbox = require("../Lib/Hitbox")
local Net = require("../Lib/Net")
local KiService = require("./KiService")
local ProjectileService = require("./ProjectileService")
local Registry = require("./Registry")
local StatusService = require("./StatusService")
local ThirstService = require("./ThirstService")

type Entity = Registry.Entity
type FighterSpec = Types.FighterSpec
type MoveSpec = Types.MoveSpec
type HitSpec = Types.HitSpec
type ProjectileSpec = Types.ProjectileSpec
type Relation = Types.Relation

-- The effect of one hit, whatever produced it: move data, projectile, special or the Elder.
export type Effect = {
	damage: number,
	stun: number,
	knockback: Types.Knockback?,
	radial: boolean?,
	pull: number?,
	yank: number?,
	guardBreak: boolean?,
	guardMultiplier: number?,
	slow: Types.Slow?,
	silence: number?,
	burn: Types.Burn?,
	root: number?,
	bind: number?,
	purify: number?,
	sprout: boolean?,
	unblockable: boolean?,
	noPassive: boolean?, -- does not advance Rhythm, Fare or Graft (bursts, ring-outs)
}

export type HitContext = {
	origin: Vector3, -- hit centre: radial knockback and effect position
	facing: Vector3, -- flat unit vector for directional knockback
	isM1: boolean?,
	melee: boolean?, -- can be caught by Jitte Catch and stopped by Canopy Guard
	phase: string?, -- overrides the attacker's phase
	flags: number?, -- extra HitFx flags
}

type Cast = {
	entity: Entity,
	fighter: FighterSpec,
	move: MoveSpec,
	token: number,
	start: number,
	facing: Vector3,
	originFrame: CFrame,
	point: Vector3?,
	groupHits: { [string]: { [Entity]: boolean } },
}

local CombatService = {}

local VALID_SLOTS: { [string]: boolean } = {
	M1 = true,
	Ability1 = true,
	Ability2 = true,
	Ability3 = true,
	Ability4 = true,
	Ultimate = true,
}

local UP = Vector3.new(0, 1, 0)

-- Seed Volley's burst, read from the move so the numbers live in one place.
local SPROUT_BURST_DAMAGE = 8
local SPROUT_BURST_ROOT = 0.6
do
	local tsuta = Fighters.get("Tsuta")
	local seeds = if tsuta then Fighters.findMove(tsuta, "SeedVolley") else nil
	local params = if seeds then seeds.params else nil
	if params then
		SPROUT_BURST_DAMAGE = params.burstDamage or SPROUT_BURST_DAMAGE
		SPROUT_BURST_ROOT = params.burstRoot or SPROUT_BURST_ROOT
	end
end

local damageListeners: { (Entity, Entity?, number) -> () } = {}
local elderListeners: { (Entity?, CombatMath.ElderHit, number, number) -> () } = {}

-- Called after damage lands: (victim, attacker, amount).
function CombatService.onDamage(listener: (Entity, Entity?, number) -> ())
	table.insert(damageListeners, listener)
end

-- Called for every hit on the Elder: (attacker, kind, damage dealt, health restored).
function CombatService.onElderHit(listener: (Entity?, CombatMath.ElderHit, number, number) -> ())
	table.insert(elderListeners, listener)
end

local function flat(vector: Vector3): Vector3
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 1e-3 then flattened.Unit else Vector3.new(0, 0, -1)
end
CombatService.flat = flat

-- The direction a caster acts in: the client's aim (flattened) or the character's facing.
local function facingOf(entity: Entity, aim: Vector3?): Vector3
	if aim then
		local flattened = Vector3.new(aim.X, 0, aim.Z)
		if flattened.Magnitude > 0.1 then
			return flattened.Unit
		end
	end
	return flat(entity.root.CFrame.LookVector)
end

local function isElderSide(entity: Entity): boolean
	return entity.kind == "Elder" or entity.kind == "Branch" or entity.kind == "Sprout"
end

-- May `attacker` touch `victim` at all? Nothing lands on or from the Ferry Landing, souls do not
-- fight on Jizo Beach (its dummies are fair game), and the Elder's parts never hit each other.
local function canTouch(attacker: Entity?, victim: Entity): boolean
	if victim.safe or (attacker ~= nil and attacker.safe) then
		return false
	end
	if attacker == nil then
		return true
	end
	if attacker.kind == "Player" and victim.kind == "Player" then
		if attacker.rule == "nopvp" or victim.rule == "nopvp" then
			return false
		end
	end
	if isElderSide(attacker) and isElderSide(victim) then
		return false
	end
	if attacker.kind == "Dummy" then
		return false
	end
	return true
end
CombatService.canTouch = canTouch

---------------------------------------------------------------------------------------------------
-- Movement helpers

-- Push an entity. Players move their own characters (network ownership), so the server asks them;
-- server-owned NPCs are pushed here.
function CombatService.impulse(entity: Entity, velocity: Vector3, duration: number)
	if entity.knockbackImmune or not Registry.isAlive(entity) then
		return
	end
	if entity.player then
		Net.Impulse:FireClient(entity.player, velocity, duration)
		return
	end
	if entity.root.Anchored then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ImpulseAttachment"
	attachment.Parent = entity.root
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e6
	mover.VectorVelocity = velocity
	mover.Parent = entity.root
	task.delay(duration, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

function CombatService.teleport(entity: Entity, cframe: CFrame)
	if entity.player then
		Net.Teleport:FireClient(entity.player, cframe)
	else
		entity.model:PivotTo(cframe)
	end
end

-- Move `entity` toward `target` so it ends `gap` studs short, over at most `maxDuration`.
local function dragToward(entity: Entity, target: Vector3, gap: number, speed: number, maxDuration: number)
	local offset = target - entity.root.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = flatOffset.Magnitude - gap
	if distance <= 0.5 then
		return
	end
	local duration = math.clamp(distance / speed, 0.06, maxDuration)
	CombatService.impulse(entity, flatOffset.Unit * (distance / duration) + UP * 5, duration)
end

---------------------------------------------------------------------------------------------------
-- Statuses

local function interrupt(entity: Entity, now: number)
	entity.moveToken += 1
	entity.currentMove = nil
	entity.lockUntil = math.min(entity.lockUntil, now)
	entity.actionSlowUntil = 0
	entity.reflectUntil = 0
	entity.catchUntil = 0
	entity.mending = false
end

function CombatService.stun(entity: Entity, duration: number, now: number, force: boolean?)
	if duration <= 0 or entity.stunImmune then
		return
	end
	if not force and entity.superArmorUntil > now then
		return
	end
	entity.stunUntil = math.max(entity.stunUntil, now + duration)
	if not entity.forceBlock then
		entity.blocking = false
	end
	interrupt(entity, now)
end

function CombatService.root(entity: Entity, duration: number, now: number, bind: boolean?)
	if duration <= 0 or entity.stunImmune then
		return
	end
	if bind then
		entity.bindUntil = math.max(entity.bindUntil, now + duration)
	else
		entity.rootUntil = math.max(entity.rootUntil, now + duration)
	end
end

function CombatService.silence(entity: Entity, duration: number, now: number)
	if duration <= 0 or entity.stunImmune then
		return
	end
	entity.silenceUntil = math.max(entity.silenceUntil, now + duration)
end

-- Purified: buffs stripped, no Ki gain, no Mend.
local function purify(entity: Entity, duration: number, now: number)
	if duration <= 0 or entity.stunImmune then
		return
	end
	entity.purifiedUntil = math.max(entity.purifiedUntil, now + duration)
	if entity.speedBonusUntil > now then
		entity.superArmorUntil = math.min(entity.superArmorUntil, now) -- Kakegoe's armour goes with it
	end
	entity.speedBonusUntil = 0
	entity.forceBeat = false
	entity.graftHits = 0
	entity.mending = false
end

local function breakGuard(entity: Entity, now: number)
	entity.blocking = false
	entity.guard = 0
	entity.lastGuardDamage = now
	if entity.stunImmune then
		return
	end
	entity.guardBrokenUntil = now + Constants.GUARD_BREAK_STUN
	interrupt(entity, now)
end

local function hitFx(victim: Entity, attacker: Entity?, amount: number, flags: number, position: Vector3)
	Net.HitFx:FireAllClients(victim.model, if attacker then attacker.model else nil, amount, flags, position)
end

local function heal(entity: Entity, amount: number)
	if amount <= 0 or not Registry.isAlive(entity) then
		return
	end
	local humanoid = entity.humanoid
	local before = humanoid.Health
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	local restored = CombatMath.roundTenth(humanoid.Health - before)
	if restored > 0 then
		hitFx(entity, entity, restored, Net.FLAG_HEAL, entity.root.Position + UP * 2)
	end
end
CombatService.heal = heal

local function dealDamage(victim: Entity, attacker: Entity?, amount: number, now: number, relation: Relation)
	if amount > 0 then
		victim.humanoid:TakeDamage(amount)
		victim.lastHitTakenAt = now
		victim.mending = false
		local name = Registry.nameOf(attacker)
		victim.damageTakenBy[name] = (victim.damageTakenBy[name] or 0) + amount
		KiService.onHitLanded(attacker, victim, amount, relation)
		if attacker and attacker.kind == "Player" and victim.kind == "Player" then
			ThirstService.add(amount)
		end
		for _, listener in damageListeners do
			task.spawn(listener, victim, attacker, amount)
		end
	end
	victim.lastCombatAt = now
	if attacker and attacker ~= victim then
		attacker.lastCombatAt = now
		victim.lastAttacker = attacker
		victim.lastAttackedAt = now
	end
end

local function applyBurn(victim: Entity, attacker: Entity?, burn: Types.Burn, now: number)
	if victim.burnUntil <= now then
		victim.burnDps = 0
		victim.nextBurnTick = now + Constants.BURN_TICK
	end
	victim.burnUntil = math.max(victim.burnUntil, now + burn.duration)
	victim.burnDps = math.max(victim.burnDps, burn.dps)
	victim.burnSource = attacker
end

local function applySlow(victim: Entity, factor: number, duration: number, now: number)
	local current = if victim.slowUntil > now then victim.slowFactor else 1
	victim.slowFactor = math.min(current, factor)
	victim.slowUntil = math.max(victim.slowUntil, now + duration)
end
CombatService.slow = applySlow

local function applyDisplacement(attacker: Entity?, victim: Entity, effect: Effect, context: HitContext, now: number)
	if victim.knockbackImmune then
		return
	end
	if effect.pull and attacker then
		dragToward(victim, attacker.root.Position, 4, effect.pull, 0.4)
		return
	end
	if effect.yank and attacker then
		local offset = attacker.root.Position - victim.root.Position
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local distance = math.min(effect.yank, math.max(0, flatOffset.Magnitude - 4))
		if distance > 0.5 then
			CombatService.impulse(victim, flatOffset.Unit * (distance / 0.2) + UP * 4, 0.2)
		end
		return
	end
	local knockback = effect.knockback
	if not knockback or victim.superArmorUntil > now then
		return
	end
	local direction = context.facing
	if effect.radial then
		local away = victim.root.Position - context.origin
		local flatAway = Vector3.new(away.X, 0, away.Z)
		direction = if flatAway.Magnitude > 0.2 then flatAway.Unit else context.facing
	end
	local scale = CombatMath.knockbackTaken(victim.fighterId)
	CombatService.impulse(victim, (direction * knockback.forward + UP * knockback.up) * scale, 0.18)
end

---------------------------------------------------------------------------------------------------
-- Hit resolution

type ApplyHit = (Entity?, Entity, Effect, HitContext) -> (boolean, number)
-- Calls go through a typed field: hits resolve recursively (counters and bursts land new hits).
local hits: { apply: ApplyHit } = { apply = (nil :: any) :: ApplyHit }

local function sourceOf(attacker: Entity?, context: HitContext): Vector3
	return if attacker then attacker.root.Position else context.origin
end

local function facesSource(victim: Entity, source: Vector3): boolean
	local toSource = source - victim.root.Position
	local look = victim.root.CFrame.LookVector
	return CombatMath.blockFacesAttacker(look.X, look.Z, toSource.X, toSource.Z)
end

-- Jitte Catch: silence the attacker and strike back.
local function catchCounter(catcher: Entity, attacker: Entity)
	local p: { [string]: number } = catcher.catchParams or {}
	local now = Registry.now()
	catcher.catchUntil = 0
	CombatService.silence(attacker, p.silence or 2.5, now)
	Net.PhaseFx:FireAllClients(catcher.model, catcher.fighterId or "", "JitteCatch", "Catch", catcher.root.Position)
	hitFx(catcher, attacker, 0, Net.FLAG_CATCH, catcher.root.Position + UP)
	task.defer(function()
		if not Registry.isAlive(attacker) or not Registry.isAlive(catcher) then
			return
		end
		hits.apply(catcher, attacker, {
			damage = p.damage or 10,
			stun = p.stun or 0.8,
			knockback = { forward = 24, up = 10 },
			unblockable = true,
		}, { origin = catcher.root.Position, facing = flat(attacker.root.Position - catcher.root.Position) })
	end)
end

-- Tsuta's Sprouts: every seed plants one; a full set bursts.
local function addSprout(attacker: Entity, victim: Entity, now: number)
	if isElderSide(victim) then
		return
	end
	local stacks, burst = CombatMath.sprout(victim.sproutStacks)
	victim.sproutStacks = stacks
	victim.sproutUntil = now + Constants.TSUTA_SPROUT_SECONDS
	victim.sproutSource = attacker
	if burst then
		task.defer(function()
			if not Registry.isAlive(victim) then
				return
			end
			hits.apply(attacker, victim, {
				damage = SPROUT_BURST_DAMAGE,
				stun = 0,
				root = SPROUT_BURST_ROOT,
				unblockable = true,
				noPassive = true,
			}, {
				origin = victim.root.Position,
				facing = flat(victim.root.Position - attacker.root.Position),
				flags = Net.FLAG_SPROUT,
			})
		end)
	end
end

-- After a landed hit: Rokumon's Fare, Tsuta's Graft heal, Kanemori's quarry.
local function landedPassives(attacker: Entity, victim: Entity, amount: number, now: number)
	if attacker.fighterId == "Rokumon" then
		attacker.fareHits, attacker.coins = CombatMath.fare(attacker.fareHits, attacker.coins)
	elseif attacker.fighterId == "Tsuta" and attacker.graftHits > 0 then
		attacker.graftHits -= 1
		heal(attacker, amount * attacker.graftFraction)
	elseif attacker.fighterId == "Kanemori" and not isElderSide(victim) then
		attacker.lastHitTarget = victim
		attacker.lastHitTargetAt = now
	end
end

local function elderHitPosition(victim: Entity, source: Vector3): Vector3
	local toward = flat(source - victim.root.Position)
	return victim.root.Position + toward * victim.hitRadius * 0.9 + UP * 2
end

-- A hit on the Elder follows its heart: the overcoming phase Wounds it, the feeding phase heals it.
local function hitElder(
	attacker: Entity?,
	victim: Entity,
	effect: Effect,
	context: HitContext,
	now: number
): (boolean, number)
	local attackerPhase = context.phase or (if attacker then attacker.phase else nil)
	local heart = victim.phase or "Wood"
	local relation: Relation = Phases.relation(attackerPhase, heart)
	local multiplier = if attacker and attacker.sapUntil > now then 1 + Constants.ELDER_SAP_DAMAGE else 1
	local kind: CombatMath.ElderHit, amount, healed = CombatMath.elderHit(effect.damage, attackerPhase, heart)
	local flags = bit32.bor(context.flags or 0, Net.relationFlag(relation))
	local position = elderHitPosition(victim, sourceOf(attacker, context))
	if kind == "Feed" then
		local humanoid = victim.humanoid
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + healed)
		hitFx(victim, attacker, healed, bit32.bor(flags, Net.FLAG_HEAL), position)
		amount = 0
	else
		if kind == "Wound" then
			amount = CombatMath.roundTenth(amount * multiplier)
			flags = bit32.bor(flags, Net.FLAG_WOUND)
		else
			amount = CombatMath.damage(effect.damage, { relation = relation, attackerMultiplier = multiplier })
		end
		dealDamage(victim, attacker, amount, now, relation)
		hitFx(victim, attacker, amount, flags, position)
	end
	for _, listener in elderListeners do
		task.spawn(listener, attacker, kind, amount, if kind == "Feed" then healed else 0)
	end
	return true, amount
end

hits.apply = function(attacker: Entity?, victim: Entity, effect: Effect, context: HitContext): (boolean, number)
	if not Registry.isAlive(victim) or attacker == victim then
		return false, 0
	end
	if not canTouch(attacker, victim) then
		return false, 0
	end
	local now = Registry.now()
	if victim.kind == "Elder" then
		return hitElder(attacker, victim, effect, context, now)
	end

	local attackerPhase = context.phase or (if attacker then attacker.phase else nil)
	local relation: Relation = Phases.relation(attackerPhase, victim.phase)
	local flags = bit32.bor(context.flags or 0, Net.relationFlag(relation))
	local source = sourceOf(attacker, context)
	local facing = facesSource(victim, source)

	-- Canopy Guard stops frontal melee and roots the attacker.
	if attacker and context.melee and victim.reflectUntil > now and facing then
		CombatService.root(attacker, victim.reflectRoot, now)
		hitFx(victim, attacker, 0, bit32.bor(flags, Net.FLAG_BLOCKED, Net.FLAG_REFLECT), victim.root.Position + UP)
		return false, 0
	end
	-- Jitte Catch turns a melee hit into a counter.
	if attacker and context.melee and victim.catchUntil > now and not isElderSide(attacker) then
		catchCounter(victim, attacker)
		return false, 0
	end

	local blocked = false
	if victim.blocking and not effect.unblockable and facing then
		if attacker and CombatMath.isParry(victim.blockStartedAt, now, context.isM1 == true) then
			CombatService.stun(attacker, Constants.PARRY_STUN, now, true)
			if victim.fighterId == "Kanemori" then
				CombatService.silence(attacker, Constants.KANEMORI_PARRY_SILENCE, now) -- Arrest
			end
			hitFx(victim, attacker, 0, bit32.bor(flags, Net.FLAG_PARRIED), victim.root.Position)
			return false, 0
		end
		if effect.guardBreak then
			breakGuard(victim, now)
			flags = bit32.bor(flags, Net.FLAG_GUARD_BREAK)
		else
			blocked = true
			flags = bit32.bor(flags, Net.FLAG_BLOCKED)
			victim.guard -= CombatMath.guardDamage(effect.damage, relation, effect.guardMultiplier)
			victim.lastGuardDamage = now
			if victim.guard <= 0 then
				breakGuard(victim, now)
				flags = bit32.bor(flags, Net.FLAG_GUARD_BREAK)
			end
		end
	end

	local multiplier = if attacker and attacker.sapUntil > now then 1 + Constants.ELDER_SAP_DAMAGE else 1
	local passive = attacker ~= nil and not effect.noPassive and not blocked and effect.damage > 0
	if passive and attacker and attacker.fighterId == "Hibiki" then
		local count, beat = CombatMath.rhythm(attacker.rhythmCount, attacker.lastRhythmAt, now, attacker.forceBeat)
		attacker.rhythmCount = count
		attacker.lastRhythmAt = now
		if beat then
			attacker.forceBeat = false
			multiplier *= 1 + Constants.HIBIKI_BEAT_BONUS
			flags = bit32.bor(flags, Net.FLAG_BEAT)
		end
	end

	local amount = CombatMath.damage(effect.damage, {
		relation = relation,
		attackerMultiplier = multiplier,
		blocked = blocked,
		isM1 = context.isM1,
	})
	dealDamage(victim, attacker, amount, now, relation)

	if not blocked then
		if effect.stun > 0 then
			CombatService.stun(victim, effect.stun, now)
		end
		applyDisplacement(attacker, victim, effect, context, now)
		if effect.slow then
			applySlow(victim, effect.slow.factor, effect.slow.duration, now)
		end
		if effect.silence then
			CombatService.silence(victim, effect.silence, now)
		end
		if effect.burn then
			applyBurn(victim, attacker, effect.burn, now)
		end
		if effect.root then
			CombatService.root(victim, effect.root, now)
		end
		if effect.bind then
			CombatService.root(victim, effect.bind, now, true)
		end
		if effect.purify then
			purify(victim, effect.purify, now)
		end
		if effect.sprout and attacker then
			addSprout(attacker, victim, now)
		end
	end
	if passive and attacker and amount > 0 then
		landedPassives(attacker, victim, amount, now)
	end

	local toward = flat(source - victim.root.Position)
	hitFx(victim, attacker, amount, flags, victim.root.Position + toward * 1.2 + UP * 0.6)
	return true, amount
end

function CombatService.applyHit(
	attacker: Entity?,
	victim: Entity,
	effect: Effect,
	context: HitContext
): (boolean, number)
	return hits.apply(attacker, victim, effect, context)
end

local function effectOfHit(hit: HitSpec): Effect
	return {
		damage = hit.damage,
		stun = hit.stun,
		knockback = hit.knockback,
		radial = hit.radial,
		pull = hit.pull,
		guardBreak = hit.guardBreak,
		guardMultiplier = hit.guardMultiplier,
		slow = hit.slow,
		silence = hit.silence,
		burn = hit.burn,
		root = hit.root,
		bind = hit.bind,
		purify = hit.purify,
		unblockable = hit.unblockable,
	}
end

local function effectOfProjectile(spec: ProjectileSpec): Effect
	return {
		damage = spec.damage,
		stun = spec.stun,
		knockback = spec.knockback,
		slow = spec.slow,
		burn = spec.burn,
		root = spec.root,
		sprout = spec.sprout,
		yank = spec.yank,
	}
end

---------------------------------------------------------------------------------------------------
-- Casting

local function castValid(cast: Cast, at: number): boolean
	local entity = cast.entity
	if not Registry.isAlive(entity) then
		return false
	end
	-- Inside the lock the cast can be interrupted; after it, its effects are already in the world.
	if at <= cast.move.lock then
		return entity.moveToken == cast.token
	end
	return true
end

-- Wait until `at` seconds after the cast started. False when the cast was interrupted.
local function waitUntil(cast: Cast, at: number): boolean
	local remaining = cast.start + at - Registry.now()
	if remaining > 0 then
		task.wait(remaining)
	end
	return castValid(cast, at)
end

local function anchorFrame(cast: Cast, hit: HitSpec): CFrame
	local anchor = hit.anchor or "self"
	if anchor == "origin" then
		return cast.originFrame
	end
	local point = cast.point
	if anchor == "point" and point then
		return CFrame.lookAt(point, point + cast.facing)
	end
	local position = cast.entity.root.Position
	return CFrame.lookAt(position, position + cast.facing)
end

local function resolveHit(cast: Cast, hit: HitSpec)
	local frame = anchorFrame(cast, hit) * CFrame.new(0, hit.up or 0, -(hit.forward or 0))
	local victims: { Entity }
	if hit.shape == "Box" then
		local size = hit.size or { 6, 6, 6 }
		victims = Hitbox.box(frame, Vector3.new(size[1], size[2], size[3]), cast.entity)
	else
		victims = Hitbox.sphere(frame.Position, hit.radius or 6, cast.entity)
	end

	local seen: { [Entity]: boolean }? = nil
	local group = hit.group
	if group then
		seen = cast.groupHits[group]
		if not seen then
			local fresh: { [Entity]: boolean } = {}
			cast.groupHits[group] = fresh
			seen = fresh
		end
	end

	local melee = hit.shape == "Box" and (hit.forward or 0) <= 6 and (hit.anchor or "self") == "self"
	local effect = effectOfHit(hit)
	for _, victim in victims do
		if seen then
			if seen[victim] then
				continue
			end
			seen[victim] = true
		end
		hits.apply(cast.entity, victim, effect, { origin = frame.Position, facing = cast.facing, melee = melee })
	end
end

local function launch(cast: Cast, spec: ProjectileSpec)
	local entity = cast.entity
	local direction = cast.facing
	local spread = spec.spread
	if spread and spread ~= 0 then
		direction = CFrame.Angles(0, math.rad(spread), 0):VectorToWorldSpace(direction)
	end
	local origin = entity.root.Position + UP * (spec.up or 0) + direction * 2.5
	local target: Entity? = nil
	if spec.homing then
		target = Hitbox.nearestEnemy(origin, direction, spec.range, 0.35, entity)
	end
	ProjectileService.fire(entity, spec, cast.move.id, origin, direction, target)
end

type TimelineEvent = { at: number, run: () -> () }

local function runTimeline(cast: Cast)
	local move = cast.move
	local events: { TimelineEvent } = {}
	local selfSpec = move.self
	if selfSpec then
		table.insert(events, {
			at = selfSpec.at,
			run = function()
				local impulse = selfSpec.impulse
				CombatService.impulse(cast.entity, cast.facing * impulse.forward + UP * impulse.up, impulse.duration)
			end,
		})
	end
	for _, hit in move.hits or ({} :: { HitSpec }) do
		table.insert(events, {
			at = hit.at,
			run = function()
				resolveHit(cast, hit)
			end,
		})
	end
	for _, spec in move.projectiles or ({} :: { ProjectileSpec }) do
		table.insert(events, {
			at = spec.at,
			run = function()
				launch(cast, spec)
			end,
		})
	end
	table.sort(events, function(a: TimelineEvent, b: TimelineEvent): boolean
		return a.at < b.at
	end)
	for _, event in events do
		if not waitUntil(cast, event.at) then
			return
		end
		event.run()
	end
end

local function phase(cast: Cast, name: string, position: Vector3)
	Net.PhaseFx:FireAllClients(cast.entity.model, cast.fighter.id, cast.move.id, name, position)
end

local function params(cast: Cast): { [string]: number }
	return cast.move.params or {}
end

local function frontFrame(entity: Entity, facing: Vector3, forward: number): CFrame
	local position = entity.root.Position
	return CFrame.lookAt(position, position + facing) * CFrame.new(0, 0, -forward)
end

-- Can this entity be grabbed, carried or thrown?
local function grabbable(attacker: Entity, victim: Entity): boolean
	return (victim.kind == "Player" or victim.kind == "Dummy") and canTouch(attacker, victim)
end

local SPECIALS: { [string]: (Cast) -> () } = {}

-- Tsuta ------------------------------------------------------------------------------------------

SPECIALS.CanopyGuard = function(cast)
	local p = params(cast)
	if not waitUntil(cast, p.openAt or 0.1) then
		return
	end
	local entity = cast.entity
	entity.reflectUntil = Registry.now() + (p.duration or 1.4)
	entity.reflectRoot = p.root or 0.8
end

SPECIALS.Graft = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.lashAt or 0.2) then
		return
	end
	local range = p.range or 25
	local target = Hitbox.nearestEnemy(entity.root.Position, cast.facing, range, 0.55, entity)
	if not target or not canTouch(entity, target) then
		phase(cast, "Miss", frontFrame(entity, cast.facing, range).Position)
		return
	end
	phase(cast, "Lash", target.root.Position)
	hits.apply(entity, target, { damage = p.damage or 4, stun = 0.35 }, {
		origin = target.root.Position,
		facing = cast.facing,
	})
	entity.graftHits = p.heals or 3
	entity.graftFraction = p.fraction or 0.4
	if not waitUntil(cast, p.pullAt or 0.35) or not Registry.isAlive(target) then
		return
	end
	dragToward(entity, target.root.Position, 4, 90, 0.3)
end

SPECIALS.RootBloom = function(cast)
	local p = params(cast)
	local entity = cast.entity
	local eruptAt = p.eruptAt or 0.8
	if not waitUntil(cast, eruptAt) then
		return
	end
	local center = Registry.groundBelow(entity.root.Position, 12)
	local radius = p.radius or 22
	phase(cast, "Erupt", center)
	for tick = 1, p.ticks or 4 do
		if tick > 1 then
			if not waitUntil(cast, eruptAt + (tick - 1) * (p.gap or 0.75)) then
				return
			end
			phase(cast, "Tick", center)
		end
		local dealt = 0
		for _, victim in Hitbox.sphere(center + UP * 3, radius, entity) do
			local _, amount = hits.apply(entity, victim, {
				damage = p.damage or 7,
				stun = 0.15,
				root = if tick == 1 then p.root or 2 else nil,
			}, { origin = center, facing = cast.facing })
			dealt += amount
		end
		heal(entity, dealt * (p.heal or 0.3))
	end
end

-- Hibiki ------------------------------------------------------------------------------------------

SPECIALS.Kakegoe = function(cast)
	local p = params(cast)
	if not waitUntil(cast, p.shoutAt or 0.25) then
		return
	end
	local entity = cast.entity
	local now = Registry.now()
	local duration = p.duration or 3
	entity.superArmorUntil = math.max(entity.superArmorUntil, now + duration)
	entity.speedBonus = p.speed or 0.2
	entity.speedBonusUntil = now + duration
	entity.forceBeat = true
	phase(cast, "Shout", entity.root.Position)
end

-- Iwao --------------------------------------------------------------------------------------------

SPECIALS.BoulderGrip = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.grabAt or 0.2) then
		return
	end
	local reach = p.reach or 5
	local frame = frontFrame(entity, cast.facing, reach / 2 + 1)
	local target: Entity? = nil
	local best = math.huge
	for _, victim in Hitbox.box(frame, Vector3.new(6, 7, reach + 2), entity) do
		if grabbable(entity, victim) then
			local distance = (victim.root.Position - entity.root.Position).Magnitude
			if distance < best then
				target = victim
				best = distance
			end
		end
	end
	if not target then
		phase(cast, "Miss", frame.Position)
		return
	end
	local victim = target
	local now = Registry.now()
	local throwAt = p.throwAt or 0.7
	-- A grab opens a block: it is how a grappler answers a turtle.
	victim.blocking = false
	interrupt(victim, now)
	victim.grabbedBy = entity
	victim.grabbedUntil = now + (throwAt - (p.grabAt or 0.2)) + 0.3
	victim.stunUntil = math.max(victim.stunUntil, victim.grabbedUntil)
	phase(cast, "Grab", victim.root.Position)
	CombatService.teleport(victim, entity.root.CFrame * CFrame.new(0, 4.5, -1.5))
	local held = waitUntil(cast, throwAt)
	victim.grabbedBy = nil
	if not held or not Registry.isAlive(victim) then
		victim.stunUntil = math.min(victim.stunUntil, Registry.now() + 0.3)
		return
	end
	local direction = cast.facing
	local flight = 0.5
	victim.lastAttacker = entity
	victim.lastAttackedAt = Registry.now()
	phase(cast, "Throw", victim.root.Position)
	CombatService.impulse(victim, direction * ((p.distance or 25) / flight) + UP * 18, flight)
	local wall = false
	local landsAt = Registry.now() + flight
	while Registry.now() < landsAt do
		task.wait(0.05)
		if not Registry.isAlive(victim) then
			return
		end
		if Registry.raycastWorld(victim.root.Position, direction * 3.5) then
			wall = true
			break
		end
	end
	phase(cast, "Land", victim.root.Position)
	hits.apply(entity, victim, {
		damage = (p.damage or 12) + (if wall then p.wallBonus or 6 else 0),
		stun = 0.6,
		unblockable = true,
	}, { origin = victim.root.Position, facing = direction })
end

SPECIALS.Tachiai = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.goAt or 0.15) then
		return
	end
	local speed = p.speed or 80
	local duration = p.duration or 0.45
	local direction = cast.facing
	CombatService.impulse(entity, direction * speed, duration)
	phase(cast, "Charge", entity.root.Position)
	local carried: Entity? = nil
	local slammed = false
	local ends = Registry.now() + duration
	while Registry.now() < ends do
		task.wait(0.03)
		if not castValid(cast, 0) then
			break
		end
		local now = Registry.now()
		if carried == nil then
			for _, victim in Hitbox.box(frontFrame(entity, direction, 3), Vector3.new(6, 7, 5), entity) do
				if grabbable(entity, victim) then
					carried = victim
					victim.lastAttacker = entity
					victim.lastAttackedAt = now
					CombatService.stun(victim, ends - now + 0.25, now)
					CombatService.impulse(victim, direction * speed, math.max(0.05, ends - now))
					break
				end
			end
		else
			local front = carried.root.Position
			if Registry.raycastWorld(front, direction * 3.2) then
				slammed = true
				break
			end
			for _, other in Hitbox.sphere(front + direction * 2.5, 3, entity) do
				if other ~= carried and not isElderSide(other) then
					slammed = true
					break
				end
			end
			if slammed then
				break
			end
		end
	end
	local victim = carried
	if not victim or not Registry.isAlive(victim) then
		return
	end
	if slammed then
		local at = victim.root.Position
		phase(cast, "Slam", at)
		for _, struck in Hitbox.sphere(at, 8, entity) do
			hits.apply(entity, struck, {
				damage = p.damage or 13,
				stun = 0.8,
				knockback = { forward = 18, up = 14 },
				radial = true,
			}, { origin = at, facing = direction })
		end
	else
		hits.apply(entity, victim, {
			damage = p.shove or 7,
			stun = 0.4,
			knockback = { forward = 40, up = 12 },
		}, { origin = victim.root.Position, facing = direction })
	end
end

SPECIALS.Dohyo = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.riseAt or 0.8) then
		return
	end
	local center = Registry.groundBelow(entity.root.Position, 12)
	local radius = p.radius or Constants.IWAO_DOHYO_RADIUS
	local duration = p.duration or Constants.IWAO_DOHYO_SECONDS
	local started = Registry.now()
	entity.superArmorUntil = math.max(entity.superArmorUntil, started + duration)
	phase(cast, "Rise", center)
	local trapped: { [Entity]: boolean } = {}
	for _, victim in Hitbox.sphere(center + UP * 3, radius, entity) do
		if grabbable(entity, victim) then
			trapped[victim] = true
		end
	end
	while Registry.now() < started + duration and Registry.isAlive(entity) do
		task.wait(0.05)
		local now = Registry.now()
		for victim in trapped do
			if not Registry.isAlive(victim) then
				trapped[victim] = nil
				continue
			end
			local offset = victim.root.Position - center
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			local distance = flatOffset.Magnitude
			if distance <= radius - 0.5 then
				continue
			end
			local outward = if distance > 0.1 then flatOffset.Unit else Vector3.new(0, 0, 1)
			local knockedOut = victim.lastAttacker == entity and now - victim.lastAttackedAt < 0.9
			if knockedOut then
				trapped[victim] = nil
				phase(cast, "RingOut", victim.root.Position)
				hits.apply(entity, victim, {
					damage = p.ringOut or Constants.IWAO_RING_OUT_DAMAGE,
					stun = 0.4,
					unblockable = true,
					noPassive = true,
				}, { origin = center, facing = outward, flags = Net.FLAG_RING_OUT })
			elseif distance > radius + 6 then
				CombatService.teleport(victim, CFrame.new(center + outward * (radius - 2) + UP * 3))
			else
				CombatService.impulse(victim, -outward * 36, 0.12)
			end
		end
	end
	phase(cast, "Fall", center)
end

-- Kanemori ----------------------------------------------------------------------------------------

SPECIALS.JitteCatch = function(cast)
	local p = params(cast)
	local entity = cast.entity
	entity.catchUntil = Registry.now() + (p.window or 0.6)
	entity.catchParams = p
end

SPECIALS.HuntersChase = function(cast)
	local p = params(cast)
	local entity = cast.entity
	local now = Registry.now()
	local quarry = entity.lastHitTarget
	local remembered = quarry ~= nil
		and Registry.isAlive(quarry)
		and now - entity.lastHitTargetAt <= (p.memory or 6)
		and (quarry.root.Position - entity.root.Position).Magnitude <= (p.range or 40)
		and canTouch(entity, quarry)
	if not remembered or not quarry then
		entity.cooldowns[cast.move.id] = now + 1 -- nobody to chase: most of the cooldown comes back
		phase(cast, "Miss", entity.root.Position)
		return
	end
	local target = quarry
	if not waitUntil(cast, 0.12) or not Registry.isAlive(target) then
		return
	end
	local targetPosition = target.root.Position
	local toward = flat(targetPosition - entity.root.Position)
	local destination = targetPosition - toward * 3.5
	phase(cast, "Chase", destination)
	CombatService.teleport(
		entity,
		CFrame.lookAt(destination, Vector3.new(targetPosition.X, destination.Y, targetPosition.Z))
	)
	if not waitUntil(cast, p.hitAt or 0.4) or not Registry.isAlive(target) then
		return
	end
	if (target.root.Position - destination).Magnitude <= 9 then
		hits.apply(entity, target, {
			damage = p.damage or 9,
			stun = p.stun or 0.7,
			knockback = { forward = 12, up = 6 },
		}, { origin = destination, facing = toward, melee = true })
	end
end

SPECIALS.EdictChains = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.chainsAt or 0.5) then
		return
	end
	local center = entity.root.Position
	phase(cast, "Chains", center)
	local bound: { Entity } = {}
	for _, victim in Hitbox.sphere(center, p.radius or 20, entity) do
		local landed = hits.apply(entity, victim, {
			damage = 0,
			stun = 0,
			bind = p.bind or 2.5,
			unblockable = true,
		}, { origin = center, facing = flat(victim.root.Position - center) })
		if landed and not isElderSide(victim) then
			table.insert(bound, victim)
		end
	end
	if not waitUntil(cast, p.pullAt or 1) then
		return
	end
	for _, victim in bound do
		if Registry.isAlive(victim) then
			dragToward(victim, entity.root.Position, 4, 60, 0.4)
		end
	end
	if not waitUntil(cast, p.shockAt or 1.8) then
		return
	end
	local here = entity.root.Position
	phase(cast, "Shock", here)
	for _, victim in Hitbox.sphere(here, p.shockRadius or 12, entity) do
		hits.apply(entity, victim, {
			damage = p.damage or 30,
			stun = 0.8,
			knockback = { forward = 30, up = 34 },
			radial = true,
		}, { origin = here, facing = cast.facing })
	end
end

-- Rokumon -----------------------------------------------------------------------------------------

SPECIALS.Mist = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.castAt or 0.3) then
		return
	end
	local center = Registry.groundBelow(entity.root.Position, 12)
	local radius = p.radius or 14
	local ends = Registry.now() + (p.duration or 4)
	entity.mistUntil = ends
	phase(cast, "Mist", center)
	while Registry.now() < ends do
		local now = Registry.now()
		for _, victim in Hitbox.sphere(center + UP * 3, radius, entity) do
			if canTouch(entity, victim) and not isElderSide(victim) then
				applySlow(victim, p.slow or 0.6, 0.4, now)
			end
		end
		task.wait(0.25)
	end
end

SPECIALS.TollStrike = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.hitAt or 0.32) then
		return
	end
	local coins = entity.coins
	entity.coins = 0
	local reach = p.reach or 6
	local frame = frontFrame(entity, cast.facing, reach / 2 + 1)
	phase(cast, "Toll", frame.Position)
	local damage = CombatMath.tollDamage(p.damage or 8, coins)
	for _, victim in Hitbox.box(frame, Vector3.new(7, 8, reach + 2), entity) do
		hits.apply(entity, victim, {
			damage = damage,
			stun = p.stun or 0.6,
			knockback = { forward = 14 + coins * 3, up = 10 },
		}, { origin = frame.Position, facing = cast.facing, melee = true })
	end
end

SPECIALS.RiverReturns = function(cast)
	local p = params(cast)
	local entity = cast.entity
	local length = p.length or 50
	local width = p.width or 14
	local speed = p.speed or 60
	if not waitUntil(cast, p.waveAt or 1) then
		return
	end
	local frame = cast.originFrame
	phase(cast, "Wave", frame.Position)
	local carried: { [Entity]: boolean } = {}
	local travel = length / speed
	local started = Registry.now()
	while true do
		local elapsed = Registry.now() - started
		local front = math.min(length, elapsed * speed)
		if front > 0.5 then
			local band = frame * CFrame.new(0, 0, -front / 2)
			for _, victim in Hitbox.box(band, Vector3.new(width, 14, front), entity) do
				if not carried[victim] then
					carried[victim] = true
					hits.apply(entity, victim, {
						damage = p.carryDamage or 10,
						stun = 0.3,
						slow = { factor = 0.5, duration = 2.5 },
					}, { origin = victim.root.Position, facing = cast.facing })
					CombatService.impulse(
						victim,
						cast.facing * speed * 0.9 + UP * 4,
						math.max(0.15, travel - elapsed + 0.1)
					)
				end
			end
		end
		if elapsed >= travel then
			break
		end
		task.wait(0.05)
	end
	if not waitUntil(cast, p.drainAt or 2.4) then
		return
	end
	local lane = frame * CFrame.new(0, 0, -length / 2)
	phase(cast, "Drain", lane.Position)
	for _, victim in Hitbox.box(lane, Vector3.new(width + 2, 14, length + 6), entity) do
		hits.apply(entity, victim, { damage = p.drainDamage or 16, stun = 1 }, {
			origin = lane.Position,
			facing = cast.facing,
		})
	end
end

---------------------------------------------------------------------------------------------------
-- Starting moves

local function startMove(entity: Entity, fighter: FighterSpec, move: MoveSpec, aim: Vector3?, now: number)
	entity.moveToken += 1
	entity.currentMove = move.id
	entity.mending = false
	entity.lockUntil = now + move.lock
	entity.actionSlow = move.moveSlow or Constants.DEFAULT_MOVE_SLOW
	entity.actionSlowUntil = now + move.lock
	if move.superArmor then
		entity.superArmorUntil = math.max(entity.superArmorUntil, now + move.lock)
	end

	local facing = facingOf(entity, aim)
	local origin = entity.root.Position
	local originFrame = CFrame.lookAt(origin, origin + facing)
	local point: Vector3? = nil
	if move.pointForward then
		if move.pointRange then
			local target = Hitbox.nearestEnemy(origin, facing, move.pointRange, 0.6, entity)
			if target and canTouch(entity, target) then
				point = Registry.groundBelow(target.root.Position, 30)
			end
		end
		if not point then
			point = Registry.groundBelow((originFrame * CFrame.new(0, 0, -move.pointForward)).Position, 30)
		end
	end
	Net.MoveFx:FireAllClients(entity.model, fighter.id, move.id, now, facing, { point = point })

	local cast: Cast = {
		entity = entity,
		fighter = fighter,
		move = move,
		token = entity.moveToken,
		start = now,
		facing = facing,
		originFrame = originFrame,
		point = point,
		groupHits = {},
	}
	task.spawn(runTimeline, cast)
	local special = move.special
	if special then
		local handler = SPECIALS[special]
		if handler then
			task.spawn(handler, cast)
		else
			warn(`[Combat] no handler for special {special}`)
		end
	end
end

local function canAct(entity: Entity, now: number): boolean
	return Registry.isAlive(entity)
		and entity.stunUntil <= now
		and entity.guardBrokenUntil <= now
		and entity.lockUntil <= now + 0.08
		and entity.grabbedBy == nil
		and not entity.blocking
end
CombatService.canAct = canAct

local function doM1(entity: Entity, fighter: FighterSpec, aim: Vector3?, now: number): boolean
	if now < entity.m1ReadyAt - 0.06 then
		return false
	end
	local m1 = fighter.m1
	local index = CombatMath.nextComboIndex(entity.m1Index, entity.lastM1At, now)
	local finisher = index >= Constants.COMBO_HITS
	entity.m1Index = index
	entity.lastM1At = now
	entity.m1ReadyAt = now + m1.interval + (if finisher then Constants.FINISHER_LOCK else 0)
	entity.moveToken += 1
	entity.mending = false
	local token = entity.moveToken
	entity.currentMove = "M1"
	entity.lockUntil = now + m1.interval * 0.8
	entity.actionSlow = 0.65
	entity.actionSlowUntil = now + m1.interval

	local facing = facingOf(entity, aim)
	Net.MoveFx:FireAllClients(entity.model, fighter.id, Fighters.m1MoveId(index), now, facing, nil)

	local effect: Effect = {
		damage = m1.damage[index],
		stun = if finisher then m1.finisherStun or Constants.FINISHER_STUN else Constants.M1_STUN,
		knockback = if finisher then m1.finisherKnockback else nil,
		burn = if finisher then m1.finisherBurn else nil,
	}
	task.delay(if finisher then m1.finisherDelay else m1.hitDelay, function()
		if entity.moveToken ~= token or not Registry.isAlive(entity) then
			return
		end
		local frame = frontFrame(entity, facing, m1.forward)
		local size = Vector3.new(m1.size[1], m1.size[2], m1.size[3])
		for _, victim in Hitbox.box(frame, size, entity) do
			hits.apply(entity, victim, effect, { origin = frame.Position, facing = facing, isM1 = true, melee = true })
		end
	end)
	return true
end

-- Attempt the move in `slot` for `entity`. Returns whether it started.
function CombatService.tryMove(entity: Entity, slot: string, aim: Vector3?): boolean
	local fighter = Fighters.get(entity.fighterId)
	if not fighter then
		return false
	end
	local now = Registry.now()
	if not canAct(entity, now) then
		return false
	end
	if slot == "M1" then
		return doM1(entity, fighter, aim, now)
	end
	if entity.silenceUntil > now then
		return false
	end
	local move = Fighters.moveForSlot(fighter, slot)
	if not move then
		return false
	end
	if now < (entity.cooldowns[move.id] or 0) - 0.15 then
		return false
	end
	if slot == "Ultimate" and not KiService.spendUltimate(entity) then
		return false
	end
	entity.cooldowns[move.id] = now + move.cooldown
	startMove(entity, fighter, move, aim, now)
	return true
end

---------------------------------------------------------------------------------------------------
-- Remote handlers

local function onAction(player: Player, slot: unknown, aim: unknown)
	if not Net.allow(player) then
		return
	end
	if type(slot) ~= "string" or not VALID_SLOTS[slot] then
		return
	end
	local entity = Registry.forPlayer(player)
	if entity then
		CombatService.tryMove(entity, slot, Net.unitVector(aim))
	end
end

function CombatService.setBlock(entity: Entity, wantsBlock: boolean)
	if not Registry.isAlive(entity) then
		return
	end
	local now = Registry.now()
	if wantsBlock then
		if entity.blocking then
			return
		end
		if StatusService.isStunned(entity, now) or entity.lockUntil > now + 0.05 or entity.grabbedBy then
			return
		end
		if now - entity.lastBlockRelease < Constants.BLOCK_RESTART_DELAY then
			return
		end
		entity.blocking = true
		entity.blockStartedAt = now
		entity.mending = false
	elseif entity.blocking then
		entity.blocking = false
		entity.lastBlockRelease = now
	end
end

local function onSetBlock(player: Player, wantsBlock: unknown)
	if not Net.allow(player, 0.5) or type(wantsBlock) ~= "boolean" then
		return
	end
	local entity = Registry.forPlayer(player)
	if entity then
		CombatService.setBlock(entity, wantsBlock)
	end
end

local function onDash(player: Player, direction: unknown)
	if not Net.allow(player) then
		return
	end
	local unit = Net.unitVector(direction)
	local entity = Registry.forPlayer(player)
	if not unit or not entity then
		return
	end
	local now = Registry.now()
	if not canAct(entity, now) or StatusService.isRooted(entity, now) or now < entity.dashReadyAt - 0.1 then
		return
	end
	entity.dashReadyAt = now + Constants.DASH_COOLDOWN
	entity.mending = false
	Net.MoveFx:FireAllClients(entity.model, entity.fighterId or "", "Dash", now, flat(unit), nil)
end

local function tickBurns()
	local now = Registry.now()
	for _, entity in Registry.all() do
		if entity.burnUntil > now then
			if now >= entity.nextBurnTick then
				entity.nextBurnTick = now + Constants.BURN_TICK
				if not entity.safe and not isElderSide(entity) then
					local amount = CombatMath.roundTenth(entity.burnDps * Constants.BURN_TICK)
					local source = entity.burnSource
					dealDamage(entity, source, amount, now, "Neutral")
					hitFx(entity, source, amount, Net.FLAG_BURN, entity.root.Position + UP)
				end
			end
		elseif entity.burnDps > 0 then
			entity.burnDps = 0
			entity.burnSource = nil
		end
	end
end

function CombatService.init(_self: any)
	ProjectileService.onHit = function(
		projectile: ProjectileService.Projectile,
		victim: Entity
	): ProjectileService.HitOutcome
		local owner = projectile.owner
		if not canTouch(owner, victim) then
			return "pass"
		end
		local now = Registry.now()
		local spec = projectile.spec
		if victim.reflectUntil > now and not projectile.reflected and facesSource(victim, projectile.position) then
			Net.PhaseFx:FireAllClients(
				victim.model,
				victim.fighterId or "",
				"CanopyGuard",
				"Reflect",
				projectile.position
			)
			hitFx(victim, owner, 0, Net.FLAG_REFLECT, projectile.position)
			return "reflect"
		end
		if spec.weapon and victim.catchUntil > now and not isElderSide(owner) then
			catchCounter(victim, owner)
			return "caught"
		end
		hits.apply(owner, victim, effectOfProjectile(spec), {
			origin = projectile.position,
			facing = flat(projectile.direction),
		})
		return "hit"
	end
	ProjectileService.onExplode = function(projectile: ProjectileService.Projectile, position: Vector3)
		local explosion = projectile.spec.explode
		if not explosion then
			return
		end
		local owner = projectile.owner
		Net.PhaseFx:FireAllClients(owner.model, owner.fighterId or "", projectile.moveId, "Explode", position)
		for _, victim in Hitbox.sphere(position, explosion.radius, owner) do
			hits.apply(owner, victim, {
				damage = explosion.damage,
				stun = explosion.stun,
				knockback = explosion.knockback,
				radial = true,
				burn = explosion.burn,
			}, { origin = position, facing = flat(projectile.direction) })
		end
	end
end

function CombatService.start(_self: any)
	Net.Action.OnServerEvent:Connect(onAction)
	Net.SetBlock.OnServerEvent:Connect(onSetBlock)
	Net.Dash.OnServerEvent:Connect(onDash)
	RunService.Heartbeat:Connect(tickBurns)
end

return CombatService
