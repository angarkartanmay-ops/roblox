--!strict
-- Server-simulated projectiles: straight, homing, boomerang (out and back) and exploding, plus
-- the two ways a fighter can answer one: Canopy Guard reflects it back at its owner and Jitte
-- Catch snatches a thrown weapon out of the air. Clients get one "spawn" and one "end" message
-- per projectile (and a "reflect" when it turns) and animate it themselves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require("../Lib/Net")
local Registry = require("./Registry")

type Entity = Registry.Entity
type ProjectileSpec = Types.ProjectileSpec

export type Projectile = {
	id: number,
	owner: Entity,
	spec: ProjectileSpec,
	moveId: string,
	position: Vector3,
	direction: Vector3,
	traveled: number,
	returning: boolean,
	reflected: boolean,
	target: Entity?,
	hit: { [Entity]: boolean },
	alive: boolean,
}

-- What a projectile touching an entity did: landed, passed through (safe zone, no-PvP beach),
-- bounced off a Canopy Guard, or was caught by a Jitte Catch.
export type HitOutcome = "hit" | "pass" | "reflect" | "caught"

local ProjectileService = {}

-- Set by CombatService (avoids a require cycle).
ProjectileService.onHit = nil :: ((Projectile, Entity) -> HitOutcome)?
ProjectileService.onExplode = nil :: ((Projectile, Vector3) -> ())?

local active: { Projectile } = {}
local nextId = 0

local function finish(projectile: Projectile, position: Vector3, explode: boolean)
	if not projectile.alive then
		return
	end
	projectile.alive = false
	local exploded = explode and projectile.spec.explode ~= nil
	Net.ProjectileFx:FireAllClients("end", projectile.id, position, exploded)
	local onExplode = ProjectileService.onExplode
	if exploded and onExplode then
		onExplode(projectile, position)
	end
end

function ProjectileService.fire(
	owner: Entity,
	spec: ProjectileSpec,
	moveId: string,
	origin: Vector3,
	direction: Vector3,
	target: Entity?
): Projectile
	nextId += 1
	local projectile: Projectile = {
		id = nextId,
		owner = owner,
		spec = spec,
		moveId = moveId,
		position = origin,
		direction = direction.Unit,
		traveled = 0,
		returning = false,
		reflected = false,
		target = target,
		hit = {},
		alive = true,
	}
	table.insert(active, projectile)
	Net.ProjectileFx:FireAllClients("spawn", {
		id = projectile.id,
		kind = spec.kind,
		owner = owner.model,
		origin = origin,
		direction = projectile.direction,
		speed = spec.speed,
		range = spec.range,
		radius = spec.radius,
		returns = spec.returns == true,
		homing = spec.homing,
		target = if target then target.model else nil,
		startTime = Registry.now(),
	})
	return projectile
end

-- Send the projectile back the way it came, now owned by `reflector`.
local function reflect(projectile: Projectile, reflector: Entity)
	local original = projectile.owner
	local back = -projectile.direction
	if Registry.isAlive(original) then
		local toOwner = original.root.Position - projectile.position
		if toOwner.Magnitude > 0.5 then
			back = toOwner.Unit
		end
	end
	projectile.owner = reflector
	projectile.direction = back
	projectile.traveled = 0
	projectile.returning = false
	projectile.reflected = true
	projectile.target = if Registry.isAlive(original) then original else nil
	projectile.hit = { [reflector] = true }
	Net.ProjectileFx:FireAllClients("reflect", projectile.id, projectile.position, back, reflector.model)
end

-- Turn `current` toward `desired` by at most `maxAngle` radians.
local function steer(current: Vector3, desired: Vector3, maxAngle: number): Vector3
	local dot = math.clamp(current:Dot(desired), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngle or angle < 1e-4 then
		return desired
	end
	local t = maxAngle / angle
	local blended = current:Lerp(desired, t)
	return if blended.Magnitude > 1e-4 then blended.Unit else desired
end

local function stepProjectile(projectile: Projectile, dt: number)
	local spec = projectile.spec
	local owner = projectile.owner

	if projectile.returning then
		if not Registry.isAlive(owner) then
			finish(projectile, projectile.position, false)
			return
		end
		local toOwner = owner.root.Position - projectile.position
		if toOwner.Magnitude < 4 then
			finish(projectile, projectile.position, false)
			return
		end
		projectile.direction = toOwner.Unit
	elseif (spec.homing or projectile.reflected) and projectile.target then
		local target = projectile.target
		if Registry.isAlive(target) then
			local desired = (target.root.Position - projectile.position)
			if desired.Magnitude > 0.5 then
				local rate = if projectile.reflected then 3 else spec.homing or 0
				projectile.direction = steer(projectile.direction, desired.Unit, rate * dt)
			end
		end
	end

	local distance = spec.speed * dt
	local from = projectile.position
	local to = from + projectile.direction * distance

	-- Entities along the swept segment
	for _, entity in Registry.all() do
		if entity == projectile.owner or projectile.hit[entity] then
			continue
		end
		local p = entity.root.Position
		local gap = CombatMath.segmentDistance(p.X, p.Y, p.Z, from.X, from.Y, from.Z, to.X, to.Y, to.Z)
		if gap > spec.radius + Constants.HIT_TOLERANCE + entity.hitRadius then
			continue
		end
		projectile.hit[entity] = true
		local onHit = ProjectileService.onHit
		local outcome: HitOutcome = if onHit then onHit(projectile, entity) else "hit"
		if outcome == "reflect" then
			reflect(projectile, entity)
			return
		elseif outcome == "caught" then
			finish(projectile, p, false)
			return
		elseif outcome == "hit" and not spec.pierce then
			finish(projectile, p, true)
			return
		end
	end

	-- Static world
	local result = Registry.raycastWorld(from, to - from)
	if result then
		if spec.returns and not projectile.returning then
			projectile.returning = true
			projectile.hit = {}
			projectile.position = result.Position - projectile.direction * 0.5
			return
		end
		if not projectile.returning then
			finish(projectile, result.Position, true)
			return
		end
	end

	projectile.position = to
	projectile.traveled += distance

	if not projectile.returning and projectile.traveled >= spec.range then
		if spec.returns then
			projectile.returning = true
			projectile.hit = {}
		else
			finish(projectile, to, true)
		end
	elseif projectile.traveled > spec.range * 2.5 + 30 then
		finish(projectile, to, false)
	end
end

local function step(dt: number)
	if #active == 0 then
		return
	end
	for _, projectile in table.clone(active) do
		if projectile.alive then
			stepProjectile(projectile, dt)
		end
	end
	local index = 1
	while index <= #active do
		if active[index].alive then
			index += 1
		else
			table.remove(active, index)
		end
	end
end

function ProjectileService.start(_self: any)
	RunService.Heartbeat:Connect(step)
end

return ProjectileService
