--!strict
-- The Wilds on the server: fills each island's camps with creatures and each arena with its
-- warden, thinks for them ten times a second (aggro, chase, leash, wander, heal), runs their
-- telegraphed attacks, pays Petals and Thirst for kills, and lights the ferry lanterns that carry
-- a soul back to any island it has walked to. Creatures only ever hit souls (players): never each
-- other, the dummies or the Elder. Every attack is announced to clients through WildsFx with its
-- geometry, so the telegraph a player dodges is exactly the area the server checks.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local FarShore = require(ReplicatedStorage.Shared.FarShore)
local Wilds = require(ReplicatedStorage.Shared.Wilds)
local Creatures = require("../Lib/Creatures")
local Net = require("../Lib/Net")
local CombatService = require("./CombatService")
local Registry = require("./Registry")
local StatsService = require("./StatsService")
local StatusService = require("./StatusService")
local ThirstService = require("./ThirstService")

type Entity = Registry.Entity
type Creature = Wilds.Creature
type Attack = Wilds.Attack
type Region = Wilds.Region
type Camp = Wilds.Camp

type Slot = {
	spec: Creature,
	region: Region,
	camp: Camp?,
	anchor: Vector3, -- x, z of the camp or arena (y unused)
	scatter: number,
}

type Wild = {
	slot: Slot,
	spec: Creature,
	entity: Entity,
	home: Vector3,
	boss: boolean,
	target: Entity?,
	busyUntil: number,
	nextAttackAt: number,
	cooldowns: { [string]: number },
	enraged: boolean,
	lastTargetAt: number,
	wanderAt: number,
	damage: { [Player]: number },
}

local WildsService = {}

local THINK = 0.1
local SLEEP_RANGE = 260 -- nobody this close to a creature's home: it does not think
local REGEN = 0.12 -- of max health per second once out of combat
local OUT_OF_COMBAT = 6
local TRAVEL_COMBAT_LOCK = 5
local CHARGE_TIME = 0.45
local BLINK_STRIKE = 0.4
local MAX_ATTACKERS = 1 -- ordinary creatures swinging at one soul at the same time (a pack takes turns)
local TURN_GAP = 0.35 -- breathing room between one pack member's swing and the next
local EDGE_MARGIN = 14 -- creatures will not chase a soul this close to the island's rim

local UP = Vector3.new(0, 1, 0)

local folder: Folder
local lanterns: Folder
local wilds: { [Entity]: Wild } = {}
local random = Random.new()

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

-- Ground height under (x, z), searching from high above; nil over open air.
local function groundAt(x: number, z: number): Vector3?
	local hit = Registry.raycastWorld(Vector3.new(x, 400, z), Vector3.new(0, -520, 0))
	return if hit then hit.Position else nil
end

local function feetOf(entity: Entity): Vector3
	local hit = Registry.raycastWorld(entity.root.Position, Vector3.new(0, -30, 0))
	if hit then
		return hit.Position
	end
	return entity.root.Position - Vector3.new(0, entity.root.Size.Y * 1.5, 0)
end

local function insideIsland(region: Region, position: Vector3): boolean
	local dx, dz = position.X - region.center[1], position.Z - region.center[2]
	local limit = region.radius - EDGE_MARGIN
	return dx * dx + dz * dz <= limit * limit
end

---------------------------------------------------------------------------------------------------
-- Spawning

local spawnSlot: (Slot) -> ()

local function onDeath(wild: Wild)
	local entity = wild.entity
	local spec = wild.spec
	wilds[entity] = nil
	local now = Registry.now()
	Net.WildsFx:FireAllClients(entity.model, spec.id, "Death", now, { origin = entity.root.Position })

	local killer = entity.lastAttacker
	local credited = killer ~= nil and now - entity.lastAttackedAt <= Constants.KILL_CREDIT_WINDOW
	local killerPlayer = if credited and killer then killer.player else nil

	if wild.boss then
		local share = entity.humanoid.MaxHealth * Wilds.BOSS_SHARE
		local names = {}
		for player, dealt in wild.damage do
			if dealt >= share and player.Parent == Players then
				StatsService.addPetals(player, spec.petals)
				StatsService.toast(player, `+{spec.petals} Petals for felling {spec.name}`)
				table.insert(names, player.DisplayName)
			end
		end
		if #names > 0 then
			ThirstService.add(spec.thirst)
			local who = if #names == 1
				then names[1]
				else `{names[1]} and {#names - 1} other soul{if #names > 2 then "s" else ""}`
			StatsService.announce(`{who} felled {spec.name}!`, Wilds.color({ 255, 205, 120 }))
			Net.Notify:FireAllClients("kill", {
				killer = if killerPlayer then killerPlayer.DisplayName else names[1],
				victim = spec.name,
				killerFighter = if killer then killer.fighterId else nil,
			})
		end
	elseif killerPlayer then
		StatsService.addPetals(killerPlayer, spec.petals)
		StatsService.toast(killerPlayer, `+{spec.petals} Petals  ·  {spec.name}`)
		ThirstService.add(spec.thirst)
	end

	local model = entity.model
	task.delay(1.4, function()
		model:Destroy()
	end)
	local wait = if wild.boss then Wilds.BOSS_RESPAWN else (if wild.slot.camp then wild.slot.camp.respawn else 30)
	task.delay(wait, function()
		spawnSlot(wild.slot)
		if wild.boss then
			StatsService.announce(
				`{spec.name} stirs again in {wild.slot.region.title}.`,
				Wilds.color(spec.attacks[1].color)
			)
		end
	end)
end

spawnSlot = function(slot: Slot)
	local spec = slot.spec
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(0, slot.scatter)
	local x = slot.anchor.X + math.cos(angle) * distance
	local z = slot.anchor.Z + math.sin(angle) * distance
	local ground = groundAt(x, z)
	if not ground then
		-- The island is not built here (a bare rojo build): try again later.
		task.delay(20, spawnSlot, slot)
		return
	end

	local model, humanoid, root = Creatures.build(spec)
	local facing = random:NextNumber(0, math.pi * 2)
	model:PivotTo(CFrame.new(ground + UP * (3 * spec.scale + 0.3)) * CFrame.Angles(0, facing, 0))
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	CollectionService:AddTag(model, "Npc")
	if spec.boss then
		CollectionService:AddTag(model, "WildBoss")
		model:SetAttribute("Region", slot.region.id)
	else
		Creatures.addNameplate(model, root, humanoid, spec)
	end

	local entity = Registry.register(model, humanoid, root, if spec.boss then "Boss" else "Enemy", nil)
	entity.phase = spec.phase
	entity.baseWalkSpeed = spec.walkSpeed
	entity.baseJumpPower = 0
	entity.baseJumpHeight = 0
	-- big bodies: the root sits high and wide, so hits reach it from a soul's height
	entity.hitRadius = math.max(0, (spec.scale - 1) * 2.4)
	entity.knockbackImmune = spec.boss
	entity.stunImmune = spec.boss

	local wild: Wild = {
		slot = slot,
		spec = spec,
		entity = entity,
		home = ground,
		boss = spec.boss,
		target = nil,
		busyUntil = 0,
		nextAttackAt = Registry.now() + 1,
		cooldowns = {},
		enraged = false,
		lastTargetAt = 0,
		wanderAt = Registry.now() + random:NextNumber(2, 8),
		damage = {},
	}
	wilds[entity] = wild

	if spec.boss and spec.enrageAt then
		local threshold = spec.enrageAt
		humanoid.HealthChanged:Connect(function(health)
			if not wild.enraged and health > 0 and health <= humanoid.MaxHealth * threshold then
				wild.enraged = true
				model:SetAttribute("Enraged", true)
				entity.baseWalkSpeed = spec.walkSpeed * 1.2
				Net.WildsFx:FireAllClients(model, spec.id, "Enrage", Registry.now(), { origin = root.Position })
			end
		end)
	end
	humanoid.Died:Once(function()
		onDeath(wild)
	end)
end

---------------------------------------------------------------------------------------------------
-- Attacks

local function effectOf(attack: Attack): CombatService.Effect
	return {
		damage = attack.damage,
		stun = attack.stun or 0,
		knockback = attack.knockback,
		radial = attack.radial,
		slow = attack.slow,
		burn = attack.burn,
		root = attack.root,
		yank = attack.yank,
		unblockable = attack.unblockable,
	}
end

-- Souls (players) whose position passes `test`, at most once per attack.
local function strike(
	wild: Wild,
	attack: Attack,
	test: (Vector3) -> boolean,
	origin: Vector3,
	facing: Vector3,
	struck: { [Entity]: boolean }?
)
	local seen = struck or {}
	local effect = effectOf(attack)
	local melee = attack.kind == "cone" or attack.kind == "charge" or attack.kind == "blink"
	for _, victim in Registry.players() do
		if not seen[victim] and not victim.safe and test(victim.root.Position) then
			seen[victim] = true
			CombatService.applyHit(wild.entity, victim, effect, { origin = origin, facing = facing, melee = melee })
		end
	end
end

local function inCircle(center: Vector3, radius: number): (Vector3) -> boolean
	return function(p)
		return flatDistance(p, center) <= radius + 1 and math.abs(p.Y - center.Y) <= radius + 8
	end
end

local function inCone(origin: Vector3, facing: Vector3, radius: number, angle: number): (Vector3) -> boolean
	local minDot = math.cos(math.rad(angle))
	return function(p)
		local offset = flat(p - origin)
		local distance = offset.Magnitude
		if distance > radius + 1 or math.abs(p.Y - origin.Y) > 10 then
			return false
		end
		return distance < 2.5 or offset.Unit:Dot(facing) >= minDot
	end
end

local function inLane(origin: Vector3, facing: Vector3, length: number, width: number): (Vector3) -> boolean
	local right = facing:Cross(UP)
	return function(p)
		local offset = flat(p - origin)
		local along = offset:Dot(facing)
		return along >= -1.5
			and along <= length + 1
			and math.abs(offset:Dot(right)) <= width / 2 + 1
			and math.abs(p.Y - origin.Y) <= 12
	end
end

local function rotateFlat(direction: Vector3, degrees: number): Vector3
	return (CFrame.Angles(0, math.rad(degrees), 0) * direction).Unit
end

-- Directions for a fan of `count` shots or lanes `spread` degrees apart.
local function fan(facing: Vector3, count: number, spread: number): { Vector3 }
	local list = {}
	for index = 1, count do
		table.insert(list, rotateFlat(facing, (index - (count + 1) / 2) * spread))
	end
	return list
end

-- Drive a server-owned body along `velocity` (charges ignore their own knockback immunity).
local function drive(entity: Entity, velocity: Vector3, duration: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "ChargeAttachment"
	attachment.Parent = entity.root
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	mover.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	mover.MaxForce = 1e7
	mover.Parent = entity.root
	task.delay(duration, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

-- Up to `count` circle centres: the target, other souls in range, then spots around the target.
local function targetPoints(wild: Wild, attack: Attack, target: Entity): { Vector3 }
	local points = { feetOf(target) }
	local count = attack.count or 1
	if attack.at == "targets" then
		for _, other in Registry.players() do
			if #points >= count then
				break
			end
			if
				other ~= target
				and not other.safe
				and flatDistance(other.root.Position, wild.entity.root.Position) <= attack.range
			then
				table.insert(points, feetOf(other))
			end
		end
		local around = points[1]
		local tries = 0
		while #points < count and tries < count * 4 do
			tries += 1
			local angle = random:NextNumber(0, math.pi * 2)
			local reach = random:NextNumber(attack.radius or 6, (attack.radius or 6) * 2.6)
			local spot = around + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
			local ground = groundAt(spot.X, spot.Z)
			if ground and math.abs(ground.Y - around.Y) < 20 then
				table.insert(points, ground)
			end
		end
	end
	return points
end

local function stillActing(wild: Wild, token: number): boolean
	local entity = wild.entity
	return Registry.isAlive(entity)
		and entity.moveToken == token
		and not StatusService.isStunned(entity, Registry.now())
end

local function perform(wild: Wild, attack: Attack, target: Entity)
	local entity = wild.entity
	local spec = wild.spec
	local now = Registry.now()
	local token = entity.moveToken
	local scale = if wild.enraged then 0.8 else 1
	wild.cooldowns[attack.id] = now + attack.cooldown * scale
	wild.busyUntil = now + attack.windup + attack.recover
	wild.nextAttackAt = wild.busyUntil
		+ (if wild.boss then random:NextNumber(0.2, 0.6) else random:NextNumber(0.9, 1.8))
	entity.actionSlow = 0
	entity.actionSlowUntil = now + attack.windup + attack.recover * 0.6
	entity.humanoid:Move(Vector3.zero)

	local position = entity.root.Position
	local toward = flat(target.root.Position - position)
	local facing = if toward.Magnitude > 0.1 then toward.Unit else flat(entity.root.CFrame.LookVector).Unit
	entity.root.CFrame = CFrame.lookAt(position, position + facing)
	local origin = feetOf(entity)

	local data: { [string]: any } = { origin = origin, facing = facing }
	if attack.kind == "circle" then
		data.points = if attack.at == "self" then { origin } else targetPoints(wild, attack, target)
	elseif attack.kind == "lane" and (attack.count or 1) > 1 then
		data.directions = fan(facing, attack.count or 1, attack.spread or 0)
	elseif attack.kind == "projectile" then
		data.directions = fan(facing, attack.count or 1, attack.spread or 0)
		data.start = position
	end
	Net.WildsFx:FireAllClients(entity.model, spec.id, attack.id, now, data)

	task.wait(attack.windup)
	if not stillActing(wild, token) then
		return
	end

	local kind = attack.kind
	if kind == "circle" then
		local struck = {}
		for _, point in data.points :: { Vector3 } do
			strike(wild, attack, inCircle(point, attack.radius or 6), point, facing, struck)
		end
	elseif kind == "cone" then
		strike(wild, attack, inCone(origin, facing, attack.radius or 8, attack.angle or 45), origin, facing)
	elseif kind == "donut" then
		local inner, outer = attack.inner or 6, attack.radius or 20
		strike(wild, attack, function(p)
			local distance = flatDistance(p, origin)
			return distance >= inner - 0.5 and distance <= outer + 1 and math.abs(p.Y - origin.Y) <= 14
		end, origin, facing)
	elseif kind == "lane" then
		local struck = {}
		for _, direction in (data.directions or { facing }) :: { Vector3 } do
			strike(
				wild,
				attack,
				inLane(origin, direction, attack.length or 12, attack.width or 5),
				origin,
				direction,
				struck
			)
		end
	elseif kind == "charge" then
		local length = attack.length or 20
		drive(entity, facing * (length / CHARGE_TIME), CHARGE_TIME)
		local struck = {}
		local started = os.clock()
		while os.clock() - started < CHARGE_TIME and Registry.isAlive(entity) do
			local here = entity.root.Position
			strike(wild, attack, function(p)
				return flatDistance(p, here) <= (attack.width or 6) / 2 + 1.5 and math.abs(p.Y - here.Y) <= 8
			end, here, facing, struck)
			task.wait(0.05)
		end
	elseif kind == "projectile" then
		local speed = attack.speed or 50
		local reach = attack.length or 40
		local radius = (attack.radius or 2.5) + 1
		local start = data.start :: Vector3
		local live = {}
		for _, direction in data.directions :: { Vector3 } do
			table.insert(live, direction)
		end
		local struck = {}
		local fired = os.clock()
		while #live > 0 do
			task.wait()
			local travelled = math.min(reach, (os.clock() - fired) * speed)
			for index = #live, 1, -1 do
				local here = start + live[index] * travelled
				local hitSomeone = false
				for _, victim in Registry.players() do
					if not struck[victim] and not victim.safe and (victim.root.Position - here).Magnitude <= radius then
						struck[victim] = true
						hitSomeone = true
						CombatService.applyHit(
							entity,
							victim,
							effectOf(attack),
							{ origin = here, facing = live[index] }
						)
					end
				end
				if hitSomeone then
					table.remove(live, index)
				end
			end
			if travelled >= reach then
				break
			end
		end
	elseif kind == "blink" then
		if not Registry.isAlive(target) then
			return
		end
		local behind = flat(target.root.CFrame.LookVector)
		behind = if behind.Magnitude > 0.1 then behind.Unit else facing
		local spot = target.root.Position - behind * (3 + 2 * spec.scale)
		local ground = groundAt(spot.X, spot.Z)
		if not ground or not insideIsland(wild.slot.region, spot) then
			spot = target.root.Position - facing * (3 + 2 * spec.scale)
			ground = groundAt(spot.X, spot.Z)
		end
		if not ground then
			return
		end
		local stand = ground + UP * (3 * spec.scale + 0.3)
		local look = flat(target.root.Position - stand)
		local newFacing = if look.Magnitude > 0.1 then look.Unit else behind
		entity.root.AssemblyLinearVelocity = Vector3.zero
		entity.model:PivotTo(CFrame.lookAt(stand, stand + newFacing))
		local strikeAt = Registry.now()
		Net.WildsFx:FireAllClients(
			entity.model,
			spec.id,
			attack.id,
			strikeAt,
			{ origin = ground, facing = newFacing, stage = 2 }
		)
		task.wait(BLINK_STRIKE)
		if Registry.isAlive(entity) then
			strike(wild, attack, inCone(ground, newFacing, attack.radius or 10, attack.angle or 60), ground, newFacing)
		end
	end
end

-- Creatures take turns: at most MAX_ATTACKERS ordinary creatures swing at one soul at once.
local function attackersOn(target: Entity, now: number): number
	local count = 0
	for _, other in wilds do
		if not other.boss and other.target == target and other.busyUntil + TURN_GAP > now then
			count += 1
		end
	end
	return count
end

local function chooseAttack(wild: Wild, distance: number, now: number): Attack?
	local total = 0
	local options: { Attack } = {}
	for _, attack in wild.spec.attacks do
		local ready = (wild.cooldowns[attack.id] or 0) <= now
		local allowed = not attack.enraged or wild.enraged
		if ready and allowed and distance <= attack.range then
			table.insert(options, attack)
			total += attack.weight or 1
		end
	end
	if #options == 0 then
		return nil
	end
	local roll = random:NextNumber(0, total)
	for _, attack in options do
		roll -= attack.weight or 1
		if roll <= 0 then
			return attack
		end
	end
	return options[#options]
end

---------------------------------------------------------------------------------------------------
-- Thinking

local function leashCentre(wild: Wild): Vector3
	return wild.home
end

local function leashRange(wild: Wild): number
	-- a warden holds its arena, with some slack for souls it knocked to the edge
	return if wild.boss then wild.slot.region.arenaRadius + 14 else wild.spec.leash
end

local function validTarget(wild: Wild, candidate: Entity?, range: number): boolean
	if candidate == nil or candidate.kind ~= "Player" or not Registry.isAlive(candidate) or candidate.safe then
		return false
	end
	local position = candidate.root.Position
	if flatDistance(position, leashCentre(wild)) > leashRange(wild) then
		return false
	end
	if not insideIsland(wild.slot.region, position) then
		return false
	end
	return flatDistance(position, wild.entity.root.Position) <= range
end

local function acquire(wild: Wild): Entity?
	local entity = wild.entity
	if validTarget(wild, wild.target, wild.spec.aggro * 2) then
		return wild.target
	end
	local attacker = entity.lastAttacker
	if
		attacker
		and Registry.now() - entity.lastAttackedAt < 4
		and validTarget(wild, attacker, wild.spec.aggro * 2.5)
	then
		return attacker
	end
	local best: Entity? = nil
	local bestDistance = wild.spec.aggro
	for _, player in Registry.players() do
		if validTarget(wild, player, wild.spec.aggro) then
			local distance = flatDistance(player.root.Position, entity.root.Position)
			if distance < bestDistance then
				best = player
				bestDistance = distance
			end
		end
	end
	return best
end

local function anyoneNear(position: Vector3, range: number): boolean
	for _, player in Registry.players() do
		if flatDistance(player.root.Position, position) <= range then
			return true
		end
	end
	return false
end

local function resetBoss(wild: Wild)
	local entity = wild.entity
	local humanoid = entity.humanoid
	humanoid.Health = humanoid.MaxHealth
	wild.enraged = false
	entity.model:SetAttribute("Enraged", false)
	entity.baseWalkSpeed = wild.spec.walkSpeed
	table.clear(wild.damage)
	table.clear(wild.cooldowns)
	entity.root.AssemblyLinearVelocity = Vector3.zero
	entity.model:PivotTo(CFrame.new(wild.home + UP * (3 * wild.spec.scale + 0.3)))
end

local function think(wild: Wild, now: number)
	local entity = wild.entity
	local humanoid = entity.humanoid
	local position = entity.root.Position

	if not anyoneNear(wild.home, SLEEP_RANGE) then
		wild.target = nil
		if wild.boss and humanoid.Health < humanoid.MaxHealth then
			resetBoss(wild)
		end
		return
	end
	if now < wild.busyUntil or StatusService.isStunned(entity, now) then
		return
	end

	local target = acquire(wild)
	wild.target = target
	if target then
		wild.lastTargetAt = now
		local distance = flatDistance(target.root.Position, position)
		local silenced = entity.silenceUntil > now
		local crowded = not wild.boss and attackersOn(target, now) >= MAX_ATTACKERS
		if not silenced and not crowded and now >= wild.nextAttackAt then
			local attack = chooseAttack(wild, distance, now)
			if attack then
				task.spawn(perform, wild, attack, target)
				return
			end
		end
		local reach = 2.4 + 1.6 * wild.spec.scale
		if distance > reach then
			humanoid:MoveTo(target.root.Position)
		else
			humanoid:Move(Vector3.zero)
			local toward = flat(target.root.Position - position)
			if toward.Magnitude > 0.1 then
				entity.root.CFrame = CFrame.lookAt(position, position + toward.Unit)
			end
		end
		return
	end

	-- No quarry: go home, mend, wander a little.
	local fromHome = flatDistance(position, wild.home)
	if fromHome > leashRange(wild) * 1.8 or position.Y < wild.home.Y - 40 then
		entity.root.AssemblyLinearVelocity = Vector3.zero
		entity.model:PivotTo(CFrame.new(wild.home + UP * (3 * wild.spec.scale + 0.3)))
	elseif fromHome > 5 then
		humanoid:MoveTo(wild.home)
	elseif now >= wild.wanderAt and not wild.boss then
		wild.wanderAt = now + random:NextNumber(4, 9)
		local angle = random:NextNumber(0, math.pi * 2)
		humanoid:MoveTo(wild.home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(3, 9))
	end
	if wild.boss then
		if now - wild.lastTargetAt > Wilds.BOSS_RESET and humanoid.Health < humanoid.MaxHealth then
			resetBoss(wild)
		end
	elseif now - entity.lastCombatAt > OUT_OF_COMBAT and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * REGEN * THINK)
	end
end

---------------------------------------------------------------------------------------------------
-- Ferry lanterns

local function lanternPart(parent: Instance, name: string, base: Vector3, color: Color3): BasePart
	local model = Instance.new("Model")
	model.Name = name
	local function piece(
		size: Vector3,
		offset: Vector3,
		partColor: Color3,
		material: Enum.Material,
		shape: Enum.PartType?
	): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.Shape = shape or Enum.PartType.Block
		p.CFrame = CFrame.new(base + offset)
		p.Color = partColor
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	piece(Vector3.new(0.8, 6, 0.8), Vector3.new(0, 3, 0), Color3.fromRGB(70, 50, 38), Enum.Material.Wood)
	piece(Vector3.new(2.4, 0.3, 2.4), Vector3.new(0, 6.15, 0), Color3.fromRGB(40, 30, 28), Enum.Material.Wood)
	local paper = piece(
		Vector3.new(1.8, 2, 1.8),
		Vector3.new(0, 7.3, 0),
		Color3.fromRGB(240, 226, 196),
		Enum.Material.SmoothPlastic
	)
	paper.Transparency = 0.15
	local core = piece(Vector3.new(1, 1, 1), Vector3.new(0, 7.3, 0), color, Enum.Material.Neon, Enum.PartType.Ball)
	piece(
		Vector3.new(2.6, 0.4, 2.6),
		Vector3.new(0, 8.5, 0),
		color:Lerp(Color3.new(0, 0, 0), 0.4),
		Enum.Material.SmoothPlastic
	)
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 14
	glow.Brightness = 1.4
	glow.Parent = core
	model.Parent = parent
	return paper
end

local function travel(player: Player, destination: Vector3, label: string)
	local entity = Registry.forPlayer(player)
	if not entity or not Registry.isAlive(entity) then
		return
	end
	if Registry.now() - entity.lastCombatAt < TRAVEL_COMBAT_LOCK then
		StatsService.toast(player, "The lantern will not carry a soul that is still fighting.")
		return
	end
	CombatService.teleport(entity, CFrame.new(destination + UP * 4))
	StatsService.toast(player, `Crossed to {label}.`)
end

local function buildLanterns()
	for _, entry in Wilds.FERRY_LANTERNS do
		local region = Wilds.region(entry.region)
		if not region then
			continue
		end
		local base = groundAt(entry.at[1], entry.at[3]) or Vector3.new(entry.at[1], entry.at[2], entry.at[3])
		local color = Wilds.color(Wilds.CREATURES[region.boss].attacks[1].color)
		local part = lanternPart(lanterns, `FerryLantern_{region.id}`, base, color)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = `Cross to {region.title}`
		prompt.ObjectText = "Ferry Lantern"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			if player:GetAttribute(`Visited_{region.id}`) ~= true then
				StatsService.toast(player, `Walk the bridge to {region.title} once to light this lantern.`)
				return
			end
			local entrance = groundAt(region.bridgeTo[1], region.bridgeTo[2])
			if entrance then
				travel(player, entrance, region.title)
			end
		end)
	end

	local landing = FarShore.SPAWNS[1]
	for _, region in Wilds.REGIONS do
		-- just inside the island from where its bridge lands
		local inward = Vector3.new(region.center[1] - region.bridgeTo[1], 0, region.center[2] - region.bridgeTo[2]).Unit
		local spot = Vector3.new(region.bridgeTo[1], 0, region.bridgeTo[2]) + inward * 14 + inward:Cross(UP) * 7
		local base = groundAt(spot.X, spot.Z)
		if not base then
			continue
		end
		local part = lanternPart(lanterns, `ReturnLantern_{region.id}`, base, Color3.fromRGB(255, 205, 120))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Return to the Ferry Landing"
		prompt.ObjectText = "Ferry Lantern"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			local target = groundAt(landing[1], landing[3]) or Vector3.new(landing[1], landing[2], landing[3])
			travel(player, target, "the Ferry Landing")
		end)
	end
end

local function onZoneChanged(entity: Entity, _previous: string?, current: string?)
	local player = entity.player
	local region = Wilds.region(current)
	if not player or not region then
		return
	end
	local key = `Visited_{region.id}`
	if player:GetAttribute(key) ~= true then
		player:SetAttribute(key, true)
		StatsService.toast(player, `The Ferry Lantern for {region.title} is lit.`)
	end
end

---------------------------------------------------------------------------------------------------

-- A snapshot for the server Debug hook.
function WildsService.debug(): { { [string]: any } }
	local list = {}
	for entity, wild in wilds do
		table.insert(list, {
			id = wild.spec.id,
			region = wild.slot.region.id,
			health = math.floor(entity.humanoid.Health),
			position = entity.root.Position,
			target = if wild.target then wild.target.model.Name else nil,
			enraged = wild.enraged,
		})
	end
	return list
end

function WildsService.init(_self: any)
	folder = Instance.new("Folder")
	folder.Name = "WildCreatures"
	folder.Parent = Workspace
	Registry.excludeFromWorld(folder)
	lanterns = Instance.new("Folder")
	lanterns.Name = "FerryLanterns"
	lanterns.Parent = Workspace

	StatusService.onZoneChanged(onZoneChanged)
	CombatService.onDamage(function(victim, attacker, amount)
		local wild = wilds[victim]
		if not wild or not attacker or not attacker.player then
			return
		end
		wild.damage[attacker.player] = (wild.damage[attacker.player] or 0) + amount
	end)
end

function WildsService.start(_self: any)
	buildLanterns()
	for _, region in Wilds.REGIONS do
		local boss = Wilds.creature(region.boss)
		if boss then
			spawnSlot({
				spec = boss,
				region = region,
				camp = nil,
				anchor = Vector3.new(region.arena[1], 0, region.arena[2]),
				scatter = 0,
			})
		end
	end
	for _, camp in Wilds.CAMPS do
		local region = Wilds.region(camp.region)
		if not region then
			continue
		end
		local x, z = Wilds.campPosition(camp)
		for _, group in camp.creatures do
			local spec = Wilds.creature(group.id)
			if spec then
				for _ = 1, group.count do
					spawnSlot({ spec = spec, region = region, camp = camp, anchor = Vector3.new(x, 0, z), scatter = 9 })
				end
			end
		end
	end

	while true do
		task.wait(THINK)
		local now = Registry.now()
		for entity, wild in wilds do
			if Registry.isAlive(entity) then
				think(wild, now)
			end
		end
	end
end

return WildsService
