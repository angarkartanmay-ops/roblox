--!strict
-- The Tide Warden: a colossus of barnacled bronze that climbs out of the sea in front of the bell
-- tower. Telegraphed attacks (Bell Slam, Undertow Sweep, Tide Toll), enrage below 40 % health,
-- rewards for everyone who helped bring it down.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Hitbox = require("../Lib/Hitbox")
local Net = require("../Lib/Net")
local CombatService = require("./CombatService")
local MapService = require("./MapService")
local Registry = require("./Registry")
local StatsService = require("./StatsService")

type Entity = Registry.Entity

local CONFIG = {
	firstSpawn = if RunService:IsStudio() then 25 else 150,
	respawnDelay = 360,
	warning = 15,
	baseHealth = 1800,
	healthPerPlayer = 350,
	scale = 4.6,
	walkSpeed = 11,
	enragedSpeed = 14,
	enrageAt = 0.4,
	attackGap = 2.4,
	leash = 95,
	rewardShards = 30,
	rewardShare = 0.04,
	blessMultiplier = 1.1,
	blessDuration = 90,
	slam = { range = 60, radius = 18, telegraph = 1.2, damage = 30, stun = 1.0, forward = 55, up = 45 },
	sweep = { range = 24, radius = 26, halfAngle = 60, telegraph = 0.9, damage = 22, stun = 0.8, pull = 40 },
	toll = {
		windup = 2.0,
		speed = 32,
		maxRadius = 85,
		band = 3.5,
		damage = 18,
		stun = 0.6,
		forward = 30,
		up = 35,
		every = 40,
	},
}

local TEAL = Color3.fromRGB(60, 240, 225)
local BRONZE = Color3.fromRGB(140, 102, 56)
local VERDIGRIS = Color3.fromRGB(82, 150, 140)

local BossService = {}

local current: Entity? = nil
local nextSpawnAt = 0
local damageBy: { [Player]: number } = {}
local enraged = false
local attacking = false
local nextAttackAt = 0
local nextTollAt = 0
local tollThresholds = { 0.66, 0.33 }
local thresholdsUsed: { [number]: boolean } = {}

local function finishAttack()
	attacking = false
	nextAttackAt = Registry.now() + CONFIG.attackGap * (if enraged then 0.7 else 1)
end

local function face(entity: Entity, position: Vector3)
	local root = entity.root.Position
	local flat = Vector3.new(position.X, root.Y, position.Z)
	if (flat - root).Magnitude > 0.5 then
		entity.model:PivotTo(CFrame.lookAt(root, flat))
	end
end

local function pose(entity: Entity, sequence: string, startTime: number)
	Net.BossFx:FireAllClients("pose", { model = entity.model, sequence = sequence, startTime = startTime })
end

local function pickTarget(entity: Entity): Entity?
	local best: Entity? = nil
	local bestDistance = math.huge
	local center = MapService.PLAZA_CENTER
	for _, candidate in Registry.all() do
		if candidate.kind == "Player" and not candidate.safe then
			local position = candidate.root.Position
			local fromCenter = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
			local distance = (position - entity.root.Position).Magnitude
			if fromCenter <= CONFIG.leash + 20 and distance < bestDistance then
				best = candidate
				bestDistance = distance
			end
		end
	end
	return best
end

local function attackSlam(entity: Entity, target: Entity)
	attacking = true
	local spec = CONFIG.slam
	entity.humanoid:MoveTo(entity.root.Position)
	local point = Registry.groundBelow(target.root.Position, 30)
	face(entity, point)
	local start = Registry.now()
	Net.BossFx:FireAllClients("telegraph", {
		shape = "circle",
		position = point,
		radius = spec.radius,
		duration = spec.telegraph,
		startTime = start,
	})
	pose(entity, "BossSlam", start)
	task.wait(spec.telegraph)
	if not Registry.isAlive(entity) then
		return
	end
	Net.BossFx:FireAllClients("impact", { position = point, radius = spec.radius, kind = "slam" })
	local damage = if enraged then spec.damage * 1.15 else spec.damage
	for _, victim in Hitbox.sphere(point + Vector3.new(0, 2, 0), spec.radius, entity) do
		if victim.kind == "Player" then
			CombatService.applyHit(entity, victim, {
				damage = damage,
				stun = spec.stun,
				knockback = { forward = spec.forward, up = spec.up },
				radial = true,
			}, { origin = point, facing = CombatService.flat(point - entity.root.Position) })
		end
	end
	task.wait(0.8)
	finishAttack()
end

local function attackSweep(entity: Entity, target: Entity)
	attacking = true
	local spec = CONFIG.sweep
	entity.humanoid:MoveTo(entity.root.Position)
	face(entity, target.root.Position)
	local origin = entity.root.Position
	local facing = CombatService.flat(entity.root.CFrame.LookVector)
	local start = Registry.now()
	Net.BossFx:FireAllClients("telegraph", {
		shape = "cone",
		position = Registry.groundBelow(origin, 40),
		direction = facing,
		radius = spec.radius,
		angle = spec.halfAngle * 2,
		duration = spec.telegraph,
		startTime = start,
	})
	pose(entity, "BossSweep", start)
	task.wait(spec.telegraph)
	if not Registry.isAlive(entity) then
		return
	end
	Net.BossFx:FireAllClients("impact", { position = origin, direction = facing, radius = spec.radius, kind = "sweep" })
	local cosLimit = math.cos(math.rad(spec.halfAngle))
	for _, victim in Hitbox.sphere(origin, spec.radius, entity) do
		if victim.kind == "Player" then
			local offset = victim.root.Position - origin
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			if flatOffset.Magnitude < 4 or flatOffset.Unit:Dot(facing) >= cosLimit then
				CombatService.applyHit(entity, victim, {
					damage = if enraged then spec.damage * 1.15 else spec.damage,
					stun = spec.stun,
					pull = spec.pull,
				}, { origin = origin, facing = facing })
			end
		end
	end
	task.wait(0.6)
	finishAttack()
end

local function attackToll(entity: Entity)
	attacking = true
	local spec = CONFIG.toll
	entity.humanoid:MoveTo(entity.root.Position)
	nextTollAt = Registry.now() + spec.every
	local origin = Registry.groundBelow(entity.root.Position, 40)
	local start = Registry.now()
	Net.BossFx:FireAllClients("toll", {
		position = origin,
		windup = spec.windup,
		speed = spec.speed,
		maxRadius = spec.maxRadius,
		startTime = start,
	})
	pose(entity, "BossToll", start)
	task.wait(spec.windup)
	local hit: { [Entity]: boolean } = {}
	local ringStart = Registry.now()
	while Registry.isAlive(entity) do
		local radius = (Registry.now() - ringStart) * spec.speed
		if radius > spec.maxRadius then
			break
		end
		for _, victim in Registry.all() do
			if victim.kind == "Player" and not hit[victim] then
				local offset = victim.root.Position - origin
				local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if math.abs(distance - radius) <= spec.band and offset.Y < 10 and Registry.isGrounded(victim) then
					hit[victim] = true
					CombatService.applyHit(entity, victim, {
						damage = spec.damage,
						stun = spec.stun,
						knockback = { forward = spec.forward, up = spec.up },
						radial = true,
						unblockable = true,
					}, { origin = origin, facing = CombatService.flat(offset) })
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	task.wait(0.5)
	finishAttack()
end

local function tollDue(healthFraction: number, now: number): boolean
	for index, threshold in tollThresholds do
		if healthFraction <= threshold and not thresholdsUsed[index] then
			thresholdsUsed[index] = true
			return true
		end
	end
	return now >= nextTollAt
end

local function think(entity: Entity)
	while Registry.isAlive(entity) do
		local now = Registry.now()
		local position = entity.root.Position
		local center = MapService.PLAZA_CENTER
		local fromCenter = Vector3.new(position.X - center.X, 0, position.Z - center.Z).Magnitude
		if position.Y < -20 or fromCenter > 160 then
			entity.root.AssemblyLinearVelocity = Vector3.zero
			entity.model:PivotTo(MapService.BOSS_SPAWN)
		end

		if not attacking then
			local target = pickTarget(entity)
			if target then
				local offset = target.root.Position - position
				local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if fromCenter > CONFIG.leash then
					entity.humanoid:MoveTo(center)
				else
					entity.humanoid:MoveTo(target.root.Position)
				end
				if now >= nextAttackAt then
					local fraction = entity.humanoid.Health / math.max(entity.humanoid.MaxHealth, 1)
					if tollDue(fraction, now) then
						task.spawn(attackToll, entity)
					elseif distance <= CONFIG.sweep.range and math.random() < 0.45 then
						task.spawn(attackSweep, entity, target)
					elseif distance <= CONFIG.slam.range then
						task.spawn(attackSlam, entity, target)
					end
				end
			elseif fromCenter > 20 then
				entity.humanoid:MoveTo(center)
			end
		end
		task.wait(0.25)
	end
end

local function decorate(model: Model)
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local size = torso.Size
	for index = -1, 1 do
		local rune = Instance.new("Part")
		rune.Name = "Rune"
		rune.Material = Enum.Material.Neon
		rune.Color = TEAL
		rune.Size = Vector3.new(size.X * 0.08, size.Y * 0.7, 0.2)
		rune.CanCollide = false
		rune.CanQuery = false
		rune.CanTouch = false
		rune.Massless = true
		rune.CastShadow = false
		local offset = CFrame.new(index * size.X * 0.28, 0, -size.Z / 2 - 0.05)
		rune.CFrame = torso.CFrame * offset
		local weld = Instance.new("Weld")
		weld.Part0 = torso
		weld.Part1 = rune
		weld.C0 = offset
		weld.Parent = rune
		rune.Parent = model
	end
	local glow = Instance.new("PointLight")
	glow.Color = TEAL
	glow.Range = 40
	glow.Brightness = 2
	glow.Parent = torso
end

local function onDeath(entity: Entity)
	local maxHealth = entity.humanoid.MaxHealth
	for player, dealt in damageBy do
		if player.Parent and dealt >= maxHealth * CONFIG.rewardShare then
			StatsService.addShards(player, CONFIG.rewardShards)
			local playerEntity = Registry.forPlayer(player)
			if playerEntity then
				CombatService.bless(playerEntity, CONFIG.blessMultiplier, CONFIG.blessDuration)
			end
			StatsService.toast(player, `+{CONFIG.rewardShards} Bell Shards. Tide-Blessed: +10% damage for 90 s.`)
		end
	end
	StatsService.announce("The Tide Warden sinks back into the deep!", TEAL)
	Net.BossFx:FireAllClients("defeated", { position = entity.root.Position })
	current = nil
	damageBy = {}
	nextSpawnAt = Registry.now() + CONFIG.respawnDelay
	task.delay(6, function()
		entity.model:Destroy()
	end)
end

local function spawnBoss()
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = VERDIGRIS
	description.TorsoColor = BRONZE
	description.LeftArmColor = VERDIGRIS
	description.RightArmColor = VERDIGRIS
	description.LeftLegColor = BRONZE
	description.RightLegColor = BRONZE
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[Boss] could not build the Tide Warden:", result)
		nextSpawnAt = Registry.now() + 60
		return
	end
	local model: Model = result
	model.Name = "TideWarden"
	model:ScaleTo(CONFIG.scale)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		nextSpawnAt = Registry.now() + 60
		return
	end
	local health = CONFIG.baseHealth + CONFIG.healthPerPlayer * #Players:GetPlayers()
	humanoid.DisplayName = "The Tide Warden"
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = CONFIG.walkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Material = Enum.Material.Metal
		end
	end
	decorate(model)
	model:PivotTo(MapService.BOSS_SPAWN)
	model.Parent = workspace
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	model:SetAttribute("Element", "Water")
	CollectionService:AddTag(model, "TideWarden")
	CollectionService:AddTag(model, "Npc")

	local entity = Registry.register(model, humanoid, root, "Boss", nil)
	entity.element = "Water"
	entity.hitRadius = 8
	entity.knockbackImmune = true
	entity.stunImmune = true
	entity.baseWalkSpeed = CONFIG.walkSpeed
	entity.baseJumpPower = 0
	entity.baseJumpHeight = 0
	current = entity
	enraged = false
	attacking = false
	thresholdsUsed = {}
	damageBy = {}
	nextAttackAt = Registry.now() + 3
	nextTollAt = Registry.now() + CONFIG.toll.every

	humanoid.HealthChanged:Connect(function(value)
		if not enraged and value > 0 and value / humanoid.MaxHealth <= CONFIG.enrageAt then
			enraged = true
			entity.baseWalkSpeed = CONFIG.enragedSpeed
			StatsService.announce("The Tide Warden is enraged!", Color3.fromRGB(255, 96, 80))
			Net.BossFx:FireAllClients("enrage", { model = model })
		end
	end)
	humanoid.Died:Once(function()
		onDeath(entity)
	end)

	StatsService.announce("The Tide Bell tolls... the Tide Warden rises from the deep!", TEAL)
	Net.BossFx:FireAllClients("spawn", { model = model, position = root.Position })
	task.spawn(think, entity)
end

local function despawn()
	local entity = current
	current = nil
	if entity then
		entity.model:Destroy()
	end
	damageBy = {}
	nextSpawnAt = Registry.now() + CONFIG.firstSpawn
end

function BossService.init(_self: any)
	CombatService.onDamage(function(victim, attacker, amount)
		if victim == current and attacker and attacker.player then
			damageBy[attacker.player] = (damageBy[attacker.player] or 0) + amount
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		damageBy[player] = nil
	end)
end

function BossService.start(_self: any)
	nextSpawnAt = Registry.now() + CONFIG.firstSpawn
	local warned = false
	local emptySince: number? = nil
	while true do
		task.wait(1)
		local now = Registry.now()
		local playerCount = #Players:GetPlayers()
		if current == nil then
			if playerCount > 0 and not warned and now >= nextSpawnAt - CONFIG.warning then
				warned = true
				StatsService.announce("The sea is stirring... the Tide Bell begins to hum.", TEAL)
			end
			if playerCount > 0 and now >= nextSpawnAt then
				warned = false
				spawnBoss()
			end
		elseif playerCount == 0 then
			emptySince = emptySince or now
			if emptySince and now - emptySince > 30 then
				emptySince = nil
				despawn()
			end
		else
			emptySince = nil
		end
	end
end

return BossService
