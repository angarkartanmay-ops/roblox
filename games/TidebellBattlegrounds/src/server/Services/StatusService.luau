--!strict
-- Turns timed statuses into movement (walk speed, jumping), regenerates guard, tracks the safe zone,
-- and publishes the attributes clients render (Stunned, Blocking, Guard, Silenced, ...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MapService = require("./MapService")
local Registry = require("./Registry")

type Entity = Registry.Entity

local StatusService = {}

local SAFE_CHECK_INTERVAL = 0.25
local safeTimer = 0

local function applyMovement(entity: Entity, now: number)
	local stunned = entity.stunUntil > now or entity.guardBrokenUntil > now
	local speed, canJump = CombatMath.movement(entity.baseWalkSpeed, {
		stunned = stunned,
		blocking = entity.blocking,
		actionSlow = if entity.actionSlowUntil > now then entity.actionSlow else nil,
		slowFactor = if entity.slowUntil > now then entity.slowFactor else nil,
		armorSlow = if entity.armorUntil > now then entity.armorSlow else nil,
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
	Registry.publish(entity, "Stunned", entity.stunUntil > now or entity.guardBrokenUntil > now)
	Registry.publish(entity, "GuardBroken", entity.guardBrokenUntil > now)
	Registry.publish(entity, "Blocking", entity.blocking)
	Registry.publish(entity, "Guard", math.floor(entity.guard / 5 + 0.5) * 5)
	Registry.publish(entity, "Silenced", entity.silenceUntil > now)
	Registry.publish(entity, "Slowed", entity.slowUntil > now)
	Registry.publish(entity, "Burning", entity.burnUntil > now)
	Registry.publish(entity, "Armored", entity.armorUntil > now)
	Registry.publish(entity, "Warding", entity.wardUntil > now)
	Registry.publish(entity, "Blessed", entity.buffUntil > now)
	Registry.publish(entity, "Safe", entity.safe)
	if entity.player then
		Registry.publishPlayer(entity, "Resonance", math.floor(entity.resonance))
	end
end

local function step(dt: number)
	local now = Registry.now()
	safeTimer += dt
	local checkSafe = safeTimer >= SAFE_CHECK_INTERVAL
	if checkSafe then
		safeTimer = 0
	end

	for _, entity in Registry.all() do
		local stunned = entity.stunUntil > now or entity.guardBrokenUntil > now
		if stunned and entity.blocking and not entity.forceBlock then
			entity.blocking = false
		end
		if entity.forceBlock and not stunned then
			if not entity.blocking then
				entity.blocking = true
				entity.blockStartedAt = nil -- dummies never parry
				entity.guard = Constants.GUARD_MAX
			end
		end

		if not entity.blocking then
			entity.guard = CombatMath.regenGuard(entity.guard, dt, now - entity.lastGuardDamage)
		elseif entity.forceBlock then
			-- The guard dummy recovers slowly even while blocking so it can be broken repeatedly.
			entity.guard = math.min(Constants.GUARD_MAX, entity.guard + dt * Constants.GUARD_REGEN * 0.35)
		end

		if checkSafe and entity.kind == "Player" then
			entity.safe = MapService.isSafe(entity.root.Position)
		end

		applyMovement(entity, now)
		publishStatus(entity, now)
	end
end

function StatusService.start(_self: any)
	RunService.Heartbeat:Connect(step)
end

return StatusService
