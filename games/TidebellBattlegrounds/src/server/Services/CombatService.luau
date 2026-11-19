--!strict
-- Server-authoritative combat: validates intents, runs M1 chains and move timelines, resolves hits
-- (element wheel, block, parry, guard break, armor), knockback, statuses, echoes, counters and burns.
-- Clients only send intents (slot + aim); every outcome is decided here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Elements = require(ReplicatedStorage.Shared.Elements)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Types = require(ReplicatedStorage.Shared.Types)
local Hitbox = require("../Lib/Hitbox")
local Net = require("../Lib/Net")
local ProjectileService = require("./ProjectileService")
local Registry = require("./Registry")

type Entity = Registry.Entity
type FighterSpec = Types.FighterSpec
type MoveSpec = Types.MoveSpec
type HitSpec = Types.HitSpec
type ProjectileSpec = Types.ProjectileSpec

-- The effect of one hit, whatever produced it: move data, projectile, explosion, special or boss.
export type Effect = {
	damage: number,
	stun: number,
	knockback: Types.Knockback?,
	radial: boolean?,
	pull: number?,
	guardBreak: boolean?,
	slow: Types.Slow?,
	silence: number?,
	burn: Types.Burn?,
	echo: Types.Echo?,
	unblockable: boolean?,
}

export type HitContext = {
	origin: Vector3, -- hit centre: radial knockback and effect position
	facing: Vector3, -- flat unit vector for directional knockback
	isM1: boolean?,
	melee: boolean?, -- can be reflected by Resonant Ward
	element: string?, -- overrides the attacker's element
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

local damageListeners: { (Entity, Entity?, number) -> () } = {}

-- Called after damage lands: (victim, attacker, amount).
function CombatService.onDamage(listener: (Entity, Entity?, number) -> ())
	table.insert(damageListeners, listener)
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

---------------------------------------------------------------------------------------------------
-- Statuses

local function interrupt(entity: Entity, now: number)
	entity.moveToken += 1
	entity.currentMove = nil
	entity.lockUntil = math.min(entity.lockUntil, now)
	entity.actionSlowUntil = 0
	entity.wardUntil = 0
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

local function gainResonance(entity: Entity?, amount: number)
	if entity == nil or entity.kind ~= "Player" or amount <= 0 then
		return
	end
	entity.resonance = CombatMath.addResonance(entity.resonance, amount)
end

function CombatService.bless(entity: Entity, multiplier: number, duration: number)
	entity.buffMultiplier = multiplier
	entity.buffUntil = Registry.now() + duration
end

local function hitFx(victim: Entity, attacker: Entity?, amount: number, flags: number, position: Vector3)
	Net.HitFx:FireAllClients(victim.model, if attacker then attacker.model else nil, amount, flags, position)
end

local function dealDamage(victim: Entity, attacker: Entity?, amount: number, now: number)
	if amount > 0 then
		victim.humanoid:TakeDamage(amount)
		for _, listener in damageListeners do
			task.spawn(listener, victim, attacker, amount)
		end
	end
	victim.lastCombatAt = now
	if attacker then
		attacker.lastCombatAt = now
		if attacker ~= victim then
			victim.lastAttacker = attacker
			victim.lastAttackedAt = now
			gainResonance(attacker, CombatMath.resonanceGain(amount, "dealt"))
		end
	end
	gainResonance(victim, CombatMath.resonanceGain(amount, "taken"))
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

local function applyDisplacement(attacker: Entity?, victim: Entity, effect: Effect, context: HitContext)
	if effect.pull and attacker then
		local offset = attacker.root.Position - victim.root.Position
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local distance = flatOffset.Magnitude
		if distance > 4 then
			local duration = math.clamp((distance - 4) / effect.pull, 0.06, 0.4)
			CombatService.impulse(victim, flatOffset.Unit * effect.pull + Vector3.new(0, 6, 0), duration)
		end
		return
	end
	local knockback = effect.knockback
	if not knockback then
		return
	end
	local direction = context.facing
	if effect.radial then
		local away = victim.root.Position - context.origin
		local flatAway = Vector3.new(away.X, 0, away.Z)
		direction = if flatAway.Magnitude > 0.2 then flatAway.Unit else context.facing
	end
	CombatService.impulse(victim, direction * knockback.forward + Vector3.new(0, knockback.up, 0), 0.18)
end

---------------------------------------------------------------------------------------------------
-- Hit resolution

type ApplyHit = (Entity?, Entity, Effect, HitContext) -> boolean
-- Calls go through a typed field: hits resolve recursively (counters and echoes land new hits).
local hits: { apply: ApplyHit } = { apply = (nil :: any) :: ApplyHit }

local function counterAttack(monk: Entity, attacker: Entity)
	local params: { [string]: number } = monk.wardParams or {}
	monk.wardUntil = 0
	local behind = (attacker.root.CFrame * CFrame.new(0, 0, 4)).Position
	local target = attacker.root.Position
	local destination = CFrame.lookAt(behind, Vector3.new(target.X, behind.Y, target.Z))
	CombatService.teleport(monk, destination)
	Net.PhaseFx:FireAllClients(monk.model, monk.fighterId or "", "ResonantWard", "Counter", behind)
	hits.apply(monk, attacker, {
		damage = params.counterDamage or 10,
		stun = params.counterStun or 1.3,
		knockback = { forward = 40, up = 18 },
		unblockable = true,
	}, { origin = behind, facing = flat(target - behind), flags = Net.FLAG_COUNTER })
end

local function scheduleEcho(attacker: Entity, victim: Entity, echo: Types.Echo, context: HitContext)
	local anchor = victim.root.Position
	task.delay(echo.delay, function()
		if not Registry.isAlive(victim) or (victim.root.Position - anchor).Magnitude > 30 then
			return
		end
		Net.PhaseFx:FireAllClients(attacker.model, attacker.fighterId or "", "EchoStrike", "Echo", victim.root.Position)
		hits.apply(attacker, victim, { damage = echo.damage, stun = echo.stun, unblockable = true }, {
			origin = victim.root.Position,
			facing = context.facing,
			flags = Net.FLAG_ECHO,
		})
	end)
end

hits.apply = function(attacker: Entity?, victim: Entity, effect: Effect, context: HitContext): boolean
	if not Registry.isAlive(victim) or attacker == victim then
		return false
	end
	local now = Registry.now()
	if victim.safe or (attacker ~= nil and attacker.safe) then
		return false
	end

	-- Resonant Ward reflects melee hits into a counterattack.
	if attacker and context.melee and victim.wardUntil > now and Registry.isAlive(attacker) then
		counterAttack(victim, attacker)
		return false
	end

	local attackerElement = context.element or (if attacker then attacker.element else nil)
	local flags = context.flags or 0
	local relation = Elements.relation(attackerElement, victim.element)
	if relation > 0 then
		flags = bit32.bor(flags, Net.FLAG_ADVANTAGE)
	elseif relation < 0 then
		flags = bit32.bor(flags, Net.FLAG_DISADVANTAGE)
	end

	local source = if attacker then attacker.root.Position else context.origin
	local blocked = false
	if victim.blocking and not effect.unblockable then
		local toSource = source - victim.root.Position
		local look = victim.root.CFrame.LookVector
		if CombatMath.blockFacesAttacker(look.X, look.Z, toSource.X, toSource.Z) then
			if attacker and CombatMath.isParry(victim.blockStartedAt, now, context.isM1 == true) then
				CombatService.stun(attacker, Constants.PARRY_STUN, now, true)
				hitFx(victim, attacker, 0, bit32.bor(flags, Net.FLAG_PARRIED), victim.root.Position)
				return false
			end
			if effect.guardBreak then
				breakGuard(victim, now)
				flags = bit32.bor(flags, Net.FLAG_GUARD_BREAK)
			else
				blocked = true
				flags = bit32.bor(flags, Net.FLAG_BLOCKED)
				victim.guard -= CombatMath.guardDamage(effect.damage, attackerElement, victim.element)
				victim.lastGuardDamage = now
				if victim.guard <= 0 then
					breakGuard(victim, now)
					flags = bit32.bor(flags, Net.FLAG_GUARD_BREAK)
				end
			end
		end
	end

	local amount = CombatMath.damage(effect.damage, {
		attackerElement = attackerElement,
		defenderElement = victim.element,
		attackerMultiplier = if attacker and attacker.buffUntil > now then attacker.buffMultiplier else 1,
		defenderArmor = if victim.armorUntil > now then victim.armor else 0,
		blocked = blocked,
		isM1 = context.isM1,
	})
	dealDamage(victim, attacker, amount, now)

	if not blocked then
		if effect.stun > 0 then
			CombatService.stun(victim, effect.stun, now)
		end
		applyDisplacement(attacker, victim, effect, context)
		if effect.slow then
			applySlow(victim, effect.slow.factor, effect.slow.duration, now)
		end
		if effect.silence then
			victim.silenceUntil = math.max(victim.silenceUntil, now + effect.silence)
		end
		if effect.burn then
			applyBurn(victim, attacker, effect.burn, now)
		end
		if effect.echo and attacker then
			scheduleEcho(attacker, victim, effect.echo, context)
		end
	end

	local toward = flat(source - victim.root.Position)
	hitFx(victim, attacker, amount, flags, victim.root.Position + toward * 1.2 + Vector3.new(0, 0.6, 0))
	return true
end
function CombatService.applyHit(attacker: Entity?, victim: Entity, effect: Effect, context: HitContext): boolean
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
		slow = hit.slow,
		silence = hit.silence,
		burn = hit.burn,
		echo = hit.echo,
		unblockable = hit.unblockable,
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
	local origin = entity.root.Position + Vector3.new(0, spec.up or 0, 0) + direction * 2.5
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
				CombatService.impulse(
					cast.entity,
					cast.facing * impulse.forward + Vector3.new(0, impulse.up, 0),
					impulse.duration
				)
			end,
		})
	end
	for _, hit in move.hits or {} do
		table.insert(events, {
			at = hit.at,
			run = function()
				resolveHit(cast, hit)
			end,
		})
	end
	for _, spec in move.projectiles or {} do
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

local SPECIALS: { [string]: (Cast) -> () } = {}

SPECIALS.GraniteHide = function(cast)
	local p = params(cast)
	local entity = cast.entity
	local now = Registry.now()
	local duration = p.duration or 4
	entity.armorUntil = now + duration
	entity.armor = p.armor or 0.5
	entity.armorSlow = p.slow or 0.8
	entity.superArmorUntil = math.max(entity.superArmorUntil, now + duration)
end

SPECIALS.LandingSlam = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.minAt or 0.5) then
		return
	end
	local maxAt = p.maxAt or 1.3
	while Registry.now() - cast.start < maxAt do
		if Registry.isGrounded(entity, 4.5) then
			break
		end
		task.wait(0.03)
		if not castValid(cast, 0) then
			return
		end
	end
	if not Registry.isAlive(entity) then
		return
	end
	local ground = Registry.groundBelow(entity.root.Position, 14)
	phase(cast, "Slam", ground)
	local effect: Effect = {
		damage = p.damage or 28,
		stun = p.stun or 1.5,
		knockback = { forward = p.knockForward or 70, up = p.knockUp or 38 },
		radial = true,
		guardBreak = true,
	}
	for _, victim in Hitbox.sphere(ground + Vector3.new(0, 2.5, 0), p.radius or 18, entity) do
		hits.apply(entity, victim, effect, { origin = ground, facing = cast.facing })
	end
end

SPECIALS.HundredLanterns = function(cast)
	local p = params(cast)
	local entity = cast.entity
	local center = cast.point or entity.root.Position
	local rng = Random.new()
	for index = 1, p.count or 10 do
		if not waitUntil(cast, (p.first or 0.5) + (index - 1) * (p.gap or 0.18)) then
			return
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(rng:NextNumber()) * (p.scatter or 14)
		local drop =
			Registry.groundBelow(center + Vector3.new(math.cos(angle) * radius, 8, math.sin(angle) * radius), 24)
		phase(cast, "Drop", drop)
		task.delay(0.35, function()
			for _, victim in Hitbox.sphere(drop + Vector3.new(0, 2, 0), p.dropRadius or 6, entity) do
				hits.apply(entity, victim, { damage = p.dropDamage or 4, stun = p.dropStun or 0.5 }, {
					origin = drop,
					facing = cast.facing,
				})
			end
		end)
	end
	if not waitUntil(cast, p.finalAt or 2.6) then
		return
	end
	phase(cast, "Final", center)
	for _, victim in Hitbox.sphere(center + Vector3.new(0, 2, 0), p.finalRadius or 12, entity) do
		hits.apply(entity, victim, {
			damage = p.finalDamage or 12,
			stun = p.finalStun or 1,
			knockback = { forward = 20, up = p.finalUp or 50 },
			radial = true,
		}, { origin = center, facing = cast.facing })
	end
end

SPECIALS.ThousandGusts = function(cast)
	local p = params(cast)
	local entity = cast.entity
	local finalEffect: Effect = {
		damage = p.finalDamage or 12,
		stun = p.finalStun or 1.2,
		knockback = { forward = p.finalForward or 80, up = p.finalUp or 32 },
	}
	local target = Hitbox.nearestEnemy(entity.root.Position, cast.facing, p.searchRange or 42, -0.2, entity)
	if not target then
		-- Nobody in reach: one forward gust instead.
		if not waitUntil(cast, 0.3) then
			return
		end
		local frame = cast.originFrame * CFrame.new(0, 0, -9)
		phase(cast, "Final", frame.Position)
		for _, victim in Hitbox.box(frame, Vector3.new(12, 8, 18), entity) do
			hits.apply(entity, victim, finalEffect, { origin = frame.Position, facing = cast.facing, melee = true })
		end
		return
	end

	local strikes = p.strikes or 6
	local orbit = p.orbit or 6
	local spin = math.random() * math.pi * 2
	for index = 1, strikes do
		if not waitUntil(cast, (p.first or 0.12) + (index - 1) * (p.gap or 0.13)) then
			return
		end
		if not Registry.isAlive(target) then
			return
		end
		local center = target.root.Position
		local angle = spin + index * (math.pi * 2 / strikes) * 2.5
		local position = center + Vector3.new(math.cos(angle) * orbit, 0, math.sin(angle) * orbit)
		CombatService.teleport(entity, CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)))
		phase(cast, "Blink", position)
		hits.apply(entity, target, { damage = p.strikeDamage or 3.5, stun = p.strikeStun or 0.6 }, {
			origin = position,
			facing = flat(center - position),
			melee = true,
		})
	end

	if not waitUntil(cast, p.finalAt or 1.02) or not Registry.isAlive(target) then
		return
	end
	local center = target.root.Position
	local behind = center - cast.facing * orbit
	CombatService.teleport(entity, CFrame.lookAt(behind, Vector3.new(center.X, behind.Y, center.Z)))
	phase(cast, "Final", center)
	hits.apply(entity, target, finalEffect, { origin = behind, facing = cast.facing, melee = true })
end

SPECIALS.NullStep = function(cast)
	local p = params(cast)
	local entity = cast.entity
	if not waitUntil(cast, p.blinkAt or 0.12) then
		return
	end
	local target = Hitbox.nearestEnemy(entity.root.Position, cast.facing, p.searchRange or 36, 0.3, entity)
	local destination: CFrame
	if target then
		local targetPosition = target.root.Position
		local behind = (target.root.CFrame * CFrame.new(0, 0, 4)).Position
		destination = CFrame.lookAt(behind, Vector3.new(targetPosition.X, behind.Y, targetPosition.Z))
	else
		local origin = entity.root.Position
		local distance = p.blinkDistance or 22
		local wall = Registry.raycastWorld(origin, cast.facing * distance)
		local reach = if wall then math.max(0, (wall.Position - origin).Magnitude - 3) else distance
		local position = origin + cast.facing * reach
		destination = CFrame.lookAt(position, position + cast.facing)
	end
	phase(cast, "Blink", destination.Position)
	CombatService.teleport(entity, destination)
	if not target then
		return
	end
	if not waitUntil(cast, p.strikeAt or 0.24) then
		return
	end
	local frame = destination * CFrame.new(0, 0, -3.5)
	for _, victim in Hitbox.box(frame, Vector3.new(7, 6, 7), entity) do
		hits.apply(entity, victim, {
			damage = p.damage or 6,
			stun = p.stun or 0.9,
			knockback = { forward = 18, up = 8 },
		}, { origin = frame.Position, facing = flat(destination.LookVector), melee = true })
	end
end

SPECIALS.ResonantWard = function(cast)
	local p = params(cast)
	cast.entity.wardUntil = Registry.now() + (p.duration or 1)
	cast.entity.wardParams = p
end

local function startMove(entity: Entity, fighter: FighterSpec, move: MoveSpec, aim: Vector3?, now: number)
	entity.moveToken += 1
	entity.currentMove = move.id
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
		point = Registry.groundBelow((originFrame * CFrame.new(0, 0, -move.pointForward)).Position, 30)
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
		and not entity.blocking
end

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
	local token = entity.moveToken
	entity.currentMove = "M1"
	entity.lockUntil = now + m1.interval * 0.8
	entity.actionSlow = 0.65
	entity.actionSlowUntil = now + m1.interval

	local facing = facingOf(entity, aim)
	Net.MoveFx:FireAllClients(entity.model, fighter.id, Fighters.m1MoveId(index), now, facing, nil)

	local effect: Effect = {
		damage = m1.damage[index],
		stun = if finisher then Constants.FINISHER_STUN else Constants.M1_STUN,
		knockback = if finisher then m1.finisherKnockback else nil,
	}
	task.delay(m1.hitDelay, function()
		if entity.moveToken ~= token or not Registry.isAlive(entity) then
			return
		end
		local origin = entity.root.Position
		local frame = CFrame.lookAt(origin, origin + facing) * CFrame.new(0, 0, -m1.forward)
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
	if slot == "Ultimate" then
		if entity.resonance < Constants.RESONANCE_MAX - 0.01 then
			return false
		end
		entity.resonance = 0
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

local function onSetBlock(player: Player, wantsBlock: unknown)
	if not Net.allow(player, 0.5) or type(wantsBlock) ~= "boolean" then
		return
	end
	local entity = Registry.forPlayer(player)
	if not entity or not Registry.isAlive(entity) then
		return
	end
	local now = Registry.now()
	if wantsBlock then
		if entity.blocking then
			return
		end
		if entity.stunUntil > now or entity.guardBrokenUntil > now or entity.lockUntil > now + 0.05 then
			return
		end
		if now - entity.lastBlockRelease < Constants.BLOCK_RESTART_DELAY then
			return
		end
		entity.blocking = true
		entity.blockStartedAt = now
	elseif entity.blocking then
		entity.blocking = false
		entity.lastBlockRelease = now
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
	if not canAct(entity, now) or now < entity.dashReadyAt - 0.1 then
		return
	end
	entity.dashReadyAt = now + Constants.DASH_COOLDOWN
	Net.MoveFx:FireAllClients(entity.model, entity.fighterId or "", "Dash", now, flat(unit), nil)
end

local function tickBurns()
	local now = Registry.now()
	for _, entity in Registry.all() do
		if entity.burnUntil > now then
			if now >= entity.nextBurnTick then
				entity.nextBurnTick = now + Constants.BURN_TICK
				if not entity.safe then
					local amount = math.floor(entity.burnDps * Constants.BURN_TICK * 10 + 0.5) / 10
					local source = entity.burnSource
					dealDamage(entity, source, amount, now)
					hitFx(entity, source, amount, Net.FLAG_BURN, entity.root.Position + Vector3.new(0, 1, 0))
				end
			end
		elseif entity.burnDps > 0 then
			entity.burnDps = 0
			entity.burnSource = nil
		end
	end
end

function CombatService.init(_self: any)
	ProjectileService.onHit = function(projectile: ProjectileService.Projectile, victim: Entity)
		local spec = projectile.spec
		hits.apply(projectile.owner, victim, {
			damage = spec.damage,
			stun = spec.stun,
			knockback = spec.knockback,
			slow = spec.slow,
			burn = spec.burn,
		}, { origin = projectile.position, facing = flat(projectile.direction) })
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
