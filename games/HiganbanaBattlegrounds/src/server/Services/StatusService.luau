--!strict
-- Turns timed statuses into movement (walk speed, jumping), regenerates guard, tracks which zone
-- of the Far Shore everyone stands in (safe landing, no-PvP beach, free-for-all), rings out
-- anyone who falls into the mist, and publishes the attributes clients render.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require("../Lib/Net")
local MapService = require("./MapService")
local Registry = require("./Registry")

type Entity = Registry.Entity

local StatusService = {}

local ZONE_CHECK_INTERVAL = 0.25
local zoneTimer = 0
local zoneListeners: { (Entity, string?, string?) -> () } = {}

-- Called when an entity's zone changes: (entity, previous zone name, new zone name).
function StatusService.onZoneChanged(listener: (Entity, string?, string?) -> ())
	table.insert(zoneListeners, listener)
end

function StatusService.isRooted(entity: Entity, now: number): boolean
	return entity.rootUntil > now or entity.bindUntil > now or entity.grabbedBy ~= nil
end

function StatusService.isStunned(entity: Entity, now: number): boolean
	return entity.stunUntil > now or entity.guardBrokenUntil > now
end

local function applyMovement(entity: Entity, now: number)
	local speed, canJump = CombatMath.movement(entity.baseWalkSpeed, {
		stunned = StatusService.isStunned(entity, now),
		blocking = entity.blocking,
		actionSlow = if entity.actionSlowUntil > now then entity.actionSlow else nil,
		slowFactor = if entity.slowUntil > now then entity.slowFactor else nil,
		speedBonus = if entity.speedBonusUntil > now then entity.speedBonus else nil,
		mending = entity.mending,
		rooted = StatusService.isRooted(entity, now),
	})
	if entity.published.walkSpeed ~= speed then
		entity.published.walkSpeed = speed
		entity.humanoid.WalkSpeed = speed
	end
	if entity.published.canJump ~= canJump then
		entity.published.canJump = canJump
		entity.humanoid.JumpPower = if canJump then entity.baseJumpPower else 0
		entity.humanoid.JumpHeight = if canJump then entity.baseJumpHeight else 0
	end
end

local function publishStatus(entity: Entity, now: number)
	Registry.publish(entity, "Stunned", StatusService.isStunned(entity, now))
	Registry.publish(entity, "GuardBroken", entity.guardBrokenUntil > now)
	Registry.publish(entity, "Blocking", entity.blocking)
	Registry.publish(entity, "Guard", math.floor(entity.guard / 5 + 0.5) * 5)
	Registry.publish(entity, "Silenced", entity.silenceUntil > now)
	Registry.publish(entity, "Slowed", entity.slowUntil > now)
	Registry.publish(entity, "Burning", entity.burnUntil > now)
	Registry.publish(entity, "Rooted", entity.rootUntil > now)
	Registry.publish(entity, "Bound", entity.bindUntil > now)
	Registry.publish(entity, "Purified", entity.purifiedUntil > now)
	Registry.publish(entity, "SuperArmor", entity.superArmorUntil > now)
	Registry.publish(entity, "Sap", entity.sapUntil > now)
	Registry.publish(entity, "Mending", entity.mending)
	Registry.publish(entity, "Grabbed", entity.grabbedBy ~= nil)
	Registry.publish(entity, "Sprouts", entity.sproutStacks)
	Registry.publish(entity, "Mist", entity.mistUntil > now)
	Registry.publish(entity, "Reflecting", entity.reflectUntil > now)
	Registry.publish(entity, "Catching", entity.catchUntil > now)
	Registry.publish(entity, "Hasted", entity.speedBonusUntil > now)
	Registry.publish(entity, "Safe", entity.safe)
	if entity.zone then
		Registry.publish(entity, "Zone", entity.zone)
	end
	if entity.fighterId == "Rokumon" then
		Registry.publish(entity, "Coins", entity.coins)
	elseif entity.fighterId == "Hibiki" then
		local live = entity.lastRhythmAt ~= nil and now - entity.lastRhythmAt <= Constants.HIBIKI_RHYTHM_WINDOW
		Registry.publish(entity, "Rhythm", if live then entity.rhythmCount % Constants.HIBIKI_BEAT_EVERY else 0)
		Registry.publish(entity, "BeatReady", entity.forceBeat)
	end
end

local function updateZone(entity: Entity)
	local zone = MapService.zoneAt(entity.root.Position)
	local name = if zone then zone.name else nil
	entity.rule = if zone then zone.rule else "ffa"
	entity.safe = entity.kind == "Player" and entity.rule == "safe"
	if name ~= entity.zone then
		local previous = entity.zone
		entity.zone = name
		for _, listener in zoneListeners do
			task.spawn(listener, entity, previous, name)
		end
	end
end

-- Falling into the mist below the shore is a ring-out, credited to the last hitter.
local function checkRingOut(entity: Entity, now: number)
	if entity.kind ~= "Player" and entity.kind ~= "Dummy" then
		return
	end
	if entity.root.Position.Y >= MapService.ringOutY() then
		return
	end
	local credited = entity.lastAttacker ~= nil and now - entity.lastAttackedAt <= Constants.KILL_CREDIT_WINDOW
	if not credited then
		entity.lastAttacker = nil
	end
	Net.HitFx:FireAllClients(
		entity.model,
		if credited and entity.lastAttacker then entity.lastAttacker.model else nil,
		0,
		Net.FLAG_RING_OUT,
		entity.root.Position
	)
	entity.model:SetAttribute("RingOut", true)
	entity.humanoid.Health = 0
end

local function step(dt: number)
	local now = Registry.now()
	zoneTimer += dt
	local checkZones = zoneTimer >= ZONE_CHECK_INTERVAL
	if checkZones then
		zoneTimer = 0
	end

	for _, entity in Registry.all() do
		local stunned = StatusService.isStunned(entity, now)
		if stunned and entity.blocking and not entity.forceBlock then
			entity.blocking = false
		end
		if entity.forceBlock and not stunned and not entity.blocking then
			entity.blocking = true
			entity.blockStartedAt = nil -- dummies never parry
			entity.guard = Constants.GUARD_MAX
		end

		if not entity.blocking then
			entity.guard = CombatMath.regenGuard(entity.guard, dt, now - entity.lastGuardDamage)
		elseif entity.forceBlock then
			-- The guard dummy recovers slowly even while blocking so it can be broken repeatedly.
			entity.guard = math.min(Constants.GUARD_MAX, entity.guard + dt * Constants.GUARD_REGEN * 0.35)
		end

		if entity.sproutStacks > 0 and entity.sproutUntil <= now then
			entity.sproutStacks = 0
			entity.sproutSource = nil
		end
		if entity.grabbedBy and (entity.grabbedUntil <= now or not Registry.isAlive(entity.grabbedBy)) then
			entity.grabbedBy = nil
		end

		if checkZones and (entity.kind == "Player" or entity.kind == "Dummy") then
			updateZone(entity)
		end
		checkRingOut(entity, now)

		applyMovement(entity, now)
		publishStatus(entity, now)
	end
end

function StatusService.start(_self: any)
	RunService.Heartbeat:Connect(step)
end

return StatusService
