--!strict
-- The Thirsting Elder: a colossal tree that wakes when the server's Thirst fills. Its hollow heart
-- cycles through the Five Phases; only the phase that overcomes the heart wounds it (+50%, and its
-- regeneration pauses), while the phase that feeds the heart heals it. It never walks: it erupts
-- roots under souls, reaches a hollow branch out to grab and drink from one, and sweeps the grove
-- with a ring of razor petals. Below 35% it enrages and grows Sap Sprouts that heal it unless cut.
-- Fell it inside the timeout for Petals, Elder's Sap and the Lily Crown; fail and it drinks its
-- fill and sinks back, paying nobody.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local FarShore = require(ReplicatedStorage.Shared.FarShore)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Types = require(ReplicatedStorage.Shared.Types)
local Hitbox = require("../Lib/Hitbox")
local Net = require("../Lib/Net")
local CombatService = require("./CombatService")
local MapService = require("./MapService")
local Registry = require("./Registry")
local StatsService = require("./StatsService")
local ThirstService = require("./ThirstService")

type Entity = Registry.Entity
type PhaseId = Types.PhaseId

local ElderService = {}

local BARK = Color3.fromRGB(92, 30, 28)
local BARK_DARK = Color3.fromRGB(58, 20, 20)
local LILY = Color3.fromRGB(214, 34, 46)
local UP = Vector3.new(0, 1, 0)

local ATTACK_GAP = 5
local ATTACK_GAP_ENRAGED = 3.5
local SPROUT_HEALTH = 60
local ROOT_RADIUS = 7
local ROOT_WINDUP = 1.2
local REACH_WINDUP = 0.9
local PETAL_WINDUP = 2
local PETAL_SPEED = 40
local PETAL_RANGE = 75

type Awakening = {
	entity: Entity,
	model: Model,
	heartPart: BasePart,
	anchor: Vector3,
	maxHealth: number,
	awokeAt: number,
	heart: PhaseId,
	nextHeartAt: number,
	warned: boolean,
	enraged: boolean,
	woundUntil: number,
	damageBy: { [string]: number },
	branch: Entity?,
	grabbed: Entity?,
	sprouts: { Entity },
	over: boolean,
}

local current: Awakening? = nil

local function fx(kind: string, data: { [string]: any })
	Net.ElderFx:FireAllClients(kind, data)
end

local function setWorld(name: string, value: any)
	Workspace:SetAttribute(name, value)
end

local function publish(awakening: Awakening)
	setWorld("ElderHealth", math.floor(awakening.entity.humanoid.Health + 0.5))
	setWorld("ElderMaxHealth", awakening.maxHealth)
	setWorld("ElderHeart", awakening.heart)
	setWorld("ElderNextHeart", Phases.nextInCycle(awakening.heart))
	setWorld("ElderHeartAt", awakening.nextHeartAt)
	setWorld("ElderEndsAt", awakening.awokeAt + Constants.ELDER_TIMEOUT)
	setWorld("ElderEnraged", awakening.enraged)
	setWorld("ElderWounded", awakening.woundUntil > Registry.now())
end

local function period(awakening: Awakening): number
	return if awakening.enraged then Constants.ELDER_PHASE_SECONDS_ENRAGED else Constants.ELDER_PHASE_SECONDS
end

---------------------------------------------------------------------------------------------------
-- Building

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Wood
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A combat body (Humanoid + anchored root) for the Elder, its branch or a Sap Sprout.
local function body(name: string, position: Vector3, health: number, size: Vector3): (Model, Humanoid, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local root = part({
		Name = "HumanoidRootPart",
		Size = size,
		CFrame = CFrame.new(position),
		Transparency = 1,
		CastShadow = false,
	}, model)
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = health
	humanoid.Health = health
	humanoid.WalkSpeed = 0
	humanoid.Parent = model
	return model, humanoid, root
end

-- The placeholder Elder: trunk, hollow reed branches, buttress roots and a glowing heart facing
-- the grove. The art stage replaces the visuals; the root, heart and names stay.
local function buildElder(anchor: Vector3, health: number, heart: PhaseId): (Model, Humanoid, BasePart, BasePart)
	local model, humanoid, root = body("ThirstingElder", anchor + UP * 6, health, Vector3.new(10, 10, 10))
	local facing = CFrame.lookAt(anchor, anchor + Vector3.new(0, 0, 1))
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(64, 22, 22),
		CFrame = CFrame.new(anchor + UP * 32) * CFrame.Angles(0, 0, math.rad(90)),
		Color = BARK,
	}, model)
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2 + 0.3
		local length = 26 + (index % 3) * 6
		local branch = CFrame.new(anchor + UP * 58)
			* CFrame.Angles(0, angle, 0)
			* CFrame.Angles(math.rad(-40 - (index % 2) * 15), 0, 0)
			* CFrame.new(0, 0, -length / 2)
		part({
			Name = "Branch",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, 3.2, 3.2),
			CFrame = branch * CFrame.Angles(0, math.rad(90), 0),
			Color = BARK_DARK,
		}, model)
		part({
			Name = "BranchMouth",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 3.6, 3.6),
			CFrame = branch * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.rad(90), 0),
			Material = Enum.Material.Neon,
			Color = LILY,
		}, model)
	end
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		part({
			Name = "Root",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(22, 3.4, 3.4),
			CFrame = CFrame.new(anchor + UP * 2)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, -16)
				* CFrame.Angles(math.rad(14), math.rad(90), 0),
			Color = BARK_DARK,
		}, model)
	end
	local heartPart = part({
		Name = "Heart",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 7,
		CFrame = facing * CFrame.new(0, 20, -10.5),
		Material = Enum.Material.Neon,
		Color = Phases.color(heart),
	}, model)
	local light = Instance.new("PointLight")
	light.Name = "HeartLight"
	light.Range = 40
	light.Brightness = 3
	light.Color = Phases.color(heart)
	light.Parent = heartPart
	return model, humanoid, root, heartPart
end

local function setHeart(awakening: Awakening, heart: PhaseId)
	awakening.heart = heart
	awakening.entity.phase = heart
	awakening.entity.model:SetAttribute("Phase", heart)
	awakening.heartPart.Color = Phases.color(heart)
	local light = awakening.heartPart:FindFirstChild("HeartLight")
	if light and light:IsA("PointLight") then
		light.Color = Phases.color(heart)
	end
end

local function rise(model: Model, from: Vector3, to: Vector3, seconds: number)
	local steps = math.max(1, math.floor(seconds / 0.05))
	local pivot = model:GetPivot()
	local base = pivot - pivot.Position
	for step = 1, steps do
		local alpha = step / steps
		local eased = 1 - (1 - alpha) ^ 3
		model:PivotTo(base + from:Lerp(to, eased))
		task.wait(seconds / steps)
	end
end

local function showTrunkBlock(visible: boolean)
	local trunk = MapService.trunkBlock
	if trunk then
		trunk.Transparency = if visible then 0 else 1
	end
end

---------------------------------------------------------------------------------------------------
-- Targets

local function inGrove(entity: Entity): boolean
	local center = MapService.groveCenter()
	local offset = entity.root.Position - center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= FarShore.GROVE_RADIUS + 20 and not entity.safe
end

local function groveTargets(): { Entity }
	local list = {}
	for _, entity in Registry.players() do
		if inGrove(entity) and entity.grabbedBy == nil then
			table.insert(list, entity)
		end
	end
	return list
end

local function elderHit(
	awakening: Awakening,
	victim: Entity,
	damage: number,
	stun: number,
	knockback: Types.Knockback?,
	radial: boolean?,
	at: Vector3
)
	CombatService.applyHit(awakening.entity, victim, {
		damage = damage,
		stun = stun,
		knockback = knockback,
		radial = radial,
		unblockable = true,
	}, { origin = at, facing = CombatService.flat(victim.root.Position - at) })
end

---------------------------------------------------------------------------------------------------
-- Attacks

local function rootEruption(awakening: Awakening, targets: { Entity })
	local count = math.min(#targets, math.random(1, 3))
	local spots: { Vector3 } = {}
	for index = 1, count do
		local victim = table.remove(targets, math.random(1, #targets))
		if not victim then
			break
		end
		local spot = Registry.groundBelow(victim.root.Position, 20)
		spots[index] = spot
		fx("telegraph", { kind = "roots", position = spot, radius = ROOT_RADIUS, duration = ROOT_WINDUP })
	end
	task.wait(ROOT_WINDUP)
	if awakening.over then
		return
	end
	for _, spot in spots do
		fx("impact", { kind = "roots", position = spot, radius = ROOT_RADIUS })
		for _, victim in Hitbox.sphere(spot + UP * 2, ROOT_RADIUS, awakening.entity) do
			if victim.kind == "Player" or victim.kind == "Dummy" then
				elderHit(awakening, victim, 14, 0.6, { forward = 0, up = 55 }, false, spot)
			end
		end
	end
end

local function release(awakening: Awakening)
	local victim = awakening.grabbed
	awakening.grabbed = nil
	if victim then
		victim.grabbedBy = nil
		victim.stunUntil = math.min(victim.stunUntil, Registry.now() + 0.2)
		fx("release", { victim = victim.model })
	end
	local branch = awakening.branch
	awakening.branch = nil
	if branch then
		branch.model:Destroy()
	end
end

local function thirstingReach(awakening: Awakening, targets: { Entity })
	local anchor = awakening.anchor
	local nearest: Entity? = nil
	local best = math.huge
	for _, victim in targets do
		local distance = (victim.root.Position - anchor).Magnitude
		if distance < best then
			nearest = victim
			best = distance
		end
	end
	if not nearest then
		return
	end
	local from = anchor + UP * 4
	local aim = nearest.root.Position
	local direction = CombatService.flat(aim - from)
	local length = math.min(Vector3.new(aim.X - from.X, 0, aim.Z - from.Z).Magnitude + 6, FarShore.GROVE_RADIUS + 20)
	fx(
		"telegraph",
		{ kind = "reach", position = from, direction = direction, length = length, duration = REACH_WINDUP }
	)
	task.wait(REACH_WINDUP)
	if awakening.over then
		return
	end
	local tip = from + direction * length
	local caught: Entity? = nil
	local closest = math.huge
	for _, victim in Hitbox.segment(from, tip, 4, awakening.entity) do
		if victim.kind == "Player" and CombatService.canTouch(awakening.entity, victim) then
			local distance = (victim.root.Position - tip).Magnitude
			if distance < closest then
				caught = victim
				closest = distance
			end
		end
	end
	if not caught then
		fx("impact", { kind = "reach", position = tip, direction = direction })
		return
	end
	local victim = caught
	local now = Registry.now()
	local hold = victim.root.Position + UP * 4
	local midpoint = from:Lerp(hold, 0.5)
	local branchModel, branchHumanoid, branchRoot =
		body("ElderBranch", midpoint, Constants.ELDER_BRANCH_HEALTH, Vector3.new(4, 4, 4))
	branchModel:SetAttribute("ElderPart", "Branch")
	branchModel.Parent = awakening.model
	local branch = Registry.register(branchModel, branchHumanoid, branchRoot, "Branch", nil)
	branch.stunImmune = true
	branch.knockbackImmune = true
	branch.hitRadius = 3
	awakening.branch = branch
	awakening.grabbed = victim
	victim.blocking = false
	victim.mending = false
	victim.grabbedBy = branch
	victim.grabbedUntil = now + Constants.ELDER_GRAB_SECONDS
	victim.stunUntil = math.max(victim.stunUntil, now + Constants.ELDER_GRAB_SECONDS)
	CombatService.teleport(victim, CFrame.new(hold))
	fx("grab", { victim = victim.model, branch = branchModel, from = from, position = hold })

	local tick = 0.25
	local ends = now + Constants.ELDER_GRAB_SECONDS
	while Registry.now() < ends do
		task.wait(tick)
		if
			awakening.over
			or awakening.branch ~= branch
			or not Registry.isAlive(branch)
			or not Registry.isAlive(victim)
		then
			break
		end
		local drain = Constants.ELDER_GRAB_DRAIN * tick
		CombatService.applyHit(awakening.entity, victim, {
			damage = drain,
			stun = 0,
			unblockable = true,
			noPassive = true,
		}, { origin = hold, facing = direction, phase = victim.phase })
		local humanoid = awakening.entity.humanoid
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + drain)
	end
	if awakening.branch == branch then
		release(awakening)
	end
end

local function petalStorm(awakening: Awakening)
	local center = Registry.groundBelow(awakening.anchor + UP * 6, 20)
	fx("telegraph", { kind = "petals", position = center, duration = PETAL_WINDUP })
	task.wait(PETAL_WINDUP)
	if awakening.over then
		return
	end
	local started = Registry.now()
	fx("petals", { position = center, startTime = started, speed = PETAL_SPEED, maxRadius = PETAL_RANGE })
	local struck: { [Entity]: boolean } = {}
	while true do
		local radius = (Registry.now() - started) * PETAL_SPEED
		if radius > PETAL_RANGE or awakening.over then
			break
		end
		for _, victim in Registry.all() do
			if struck[victim] or (victim.kind ~= "Player" and victim.kind ~= "Dummy") then
				continue
			end
			local offset = victim.root.Position - center
			local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if distance >= radius - 2.5 and distance <= radius + 1.5 then
				struck[victim] = true
				-- Jump it: only grounded souls are cut.
				if Registry.isGrounded(victim, 4.2) then
					elderHit(awakening, victim, 16, 0.4, { forward = 20, up = 10 }, true, center)
				end
			end
		end
		task.wait(0.05)
	end
end

---------------------------------------------------------------------------------------------------
-- Enrage and Sap Sprouts

local function growSprouts(awakening: Awakening)
	for index = 1, Constants.SAP_SPROUT_COUNT do
		local angle = math.rad(-50 + (index - 1) * 50)
		local spot = awakening.anchor + Vector3.new(math.sin(angle) * 26, 0, math.cos(angle) * 26)
		local ground = Registry.groundBelow(spot + UP * 30, 80)
		local model, humanoid, root = body("SapSprout", ground + UP * 2.5, SPROUT_HEALTH, Vector3.new(3, 5, 3))
		part({
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 3.4,
			CFrame = CFrame.new(ground + UP * 3),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(196, 120, 40),
		}, model)
		model:SetAttribute("ElderPart", "Sprout")
		model.Parent = awakening.model
		local sprout = Registry.register(model, humanoid, root, "Sprout", nil)
		sprout.stunImmune = true
		sprout.knockbackImmune = true
		sprout.hitRadius = 1.5
		table.insert(awakening.sprouts, sprout)
		fx("sprout", { position = ground, model = model, seconds = Constants.SAP_SPROUT_HEAL_SECONDS })
		task.delay(Constants.SAP_SPROUT_HEAL_SECONDS, function()
			if awakening.over or not Registry.isAlive(sprout) then
				return
			end
			-- It ripened: the Elder drinks it.
			local elderHumanoid = awakening.entity.humanoid
			elderHumanoid.Health = math.min(
				elderHumanoid.MaxHealth,
				elderHumanoid.Health + awakening.maxHealth * Constants.SAP_SPROUT_HEAL_FRACTION
			)
			fx("wither", { position = sprout.root.Position, healed = true })
			model:Destroy()
		end)
		humanoid.Died:Once(function()
			fx("wither", { position = root.Position, healed = false })
			task.delay(0.3, function()
				model:Destroy()
			end)
		end)
	end
end

local function enrage(awakening: Awakening)
	awakening.enraged = true
	local now = Registry.now()
	awakening.nextHeartAt = math.min(awakening.nextHeartAt, now + Constants.ELDER_PHASE_SECONDS_ENRAGED)
	awakening.warned = false
	fx("enrage", { position = awakening.anchor })
	StatsService.announce("The Thirsting Elder rages! Cut down its Sap Sprouts!", LILY)
	growSprouts(awakening)
end

---------------------------------------------------------------------------------------------------
-- The awakening's lifetime

local function sink(awakening: Awakening)
	release(awakening)
	for _, sprout in awakening.sprouts do
		if sprout.model.Parent then
			sprout.model:Destroy()
		end
	end
	Registry.unregister(awakening.entity.model)
	local model = awakening.model
	task.spawn(function()
		local pivot = model:GetPivot().Position
		rise(model, pivot, pivot - UP * 70, 3)
		model:Destroy()
		showTrunkBlock(true)
	end)
	if current == awakening then
		current = nil
	end
	for _, name in { "ElderHealth", "ElderHeart", "ElderNextHeart", "ElderHeartAt", "ElderEndsAt" } do
		setWorld(name, nil)
	end
	setWorld("ElderEnraged", false)
	setWorld("ElderWounded", false)
	ThirstService.setAwake(false)
end

local function fall(awakening: Awakening)
	if awakening.over then
		return
	end
	awakening.over = true
	local earned, top = CombatMath.elderRewards(awakening.damageBy, awakening.maxHealth)
	local now = Registry.now()
	for _, name in earned do
		local player = Players:FindFirstChild(name)
		if player and player:IsA("Player") then
			StatsService.addPetals(player, Constants.ELDER_REWARD_PETALS)
			player:SetAttribute("SapUntil", now + Constants.ELDER_SAP_SECONDS)
			local entity = Registry.forPlayer(player)
			if entity then
				entity.sapUntil = now + Constants.ELDER_SAP_SECONDS
			end
			StatsService.toast(
				player,
				`+{Constants.ELDER_REWARD_PETALS} Petals and Elder's Sap: +10% damage, faster Mend for {Constants.ELDER_SAP_SECONDS} s.`
			)
		end
	end
	local topPlayer = if top then Players:FindFirstChild(top) else nil
	local displayTop = if topPlayer and topPlayer:IsA("Player") then topPlayer.DisplayName else nil
	if topPlayer and topPlayer:IsA("Player") then
		StatsService.crown(topPlayer)
	end
	fx("fall", { position = awakening.anchor, top = displayTop, earned = earned })
	StatsService.announce(
		if displayTop
			then `The Thirsting Elder falls! {displayTop} wears the Lily Crown.`
			else "The Thirsting Elder falls!",
		LILY
	)
	sink(awakening)
end

local function timeout(awakening: Awakening)
	if awakening.over then
		return
	end
	awakening.over = true
	awakening.entity.humanoid.Health = awakening.entity.humanoid.MaxHealth
	fx("timeout", { position = awakening.anchor })
	StatsService.announce("The Elder drank its fill and sank back into the grove. Nobody was paid.", LILY)
	sink(awakening)
end

local function heartLoop(awakening: Awakening)
	while not awakening.over do
		local now = Registry.now()
		if not awakening.warned and now >= awakening.nextHeartAt - Constants.ELDER_PHASE_WARNING then
			awakening.warned = true
			fx("heart", {
				warning = true,
				heart = awakening.heart,
				next = Phases.nextInCycle(awakening.heart),
				at = awakening.nextHeartAt,
			})
		end
		if now >= awakening.nextHeartAt then
			setHeart(awakening, Phases.nextInCycle(awakening.heart))
			awakening.nextHeartAt = now + period(awakening)
			awakening.warned = false
			fx(
				"heart",
				{ heart = awakening.heart, next = Phases.nextInCycle(awakening.heart), at = awakening.nextHeartAt }
			)
		end
		-- regeneration, paused while Wounded
		if now >= awakening.woundUntil then
			local humanoid = awakening.entity.humanoid
			humanoid.Health = math.min(
				humanoid.MaxHealth,
				humanoid.Health + awakening.maxHealth * Constants.ELDER_REGEN_PERCENT / 100 * 0.25
			)
		end
		if
			not awakening.enraged
			and awakening.entity.humanoid.Health < awakening.maxHealth * Constants.ELDER_ENRAGE_AT
		then
			enrage(awakening)
		end
		if now - awakening.awokeAt >= Constants.ELDER_TIMEOUT then
			timeout(awakening)
			return
		end
		publish(awakening)
		task.wait(0.25)
	end
end

local function attackLoop(awakening: Awakening)
	local last = ""
	task.wait(3)
	while not awakening.over do
		local targets = groveTargets()
		if #targets > 0 then
			local options = { "roots", "reach", "petals" }
			if last == "petals" then
				options = { "roots", "reach" }
			end
			if awakening.grabbed then
				options = { "roots", "petals" }
			end
			local choice = options[math.random(1, #options)]
			last = choice
			if choice == "roots" then
				rootEruption(awakening, targets)
			elseif choice == "reach" then
				task.spawn(thirstingReach, awakening, targets)
				task.wait(REACH_WINDUP)
			else
				petalStorm(awakening)
			end
		end
		task.wait(if awakening.enraged then ATTACK_GAP_ENRAGED else ATTACK_GAP)
	end
end

-- Wake the Elder (ThirstService decides when).
function ElderService.wake()
	if current then
		return
	end
	ThirstService.setAwake(true)
	local anchor = MapService.elderAnchor()
	local players = math.max(1, #Players:GetPlayers())
	local maxHealth = CombatMath.elderHealth(players)
	local first: PhaseId = Phases.ORDER[math.random(1, #Phases.ORDER)]
	local model, humanoid, root, heartPart = buildElder(anchor, maxHealth, first)
	model:PivotTo(model:GetPivot() - UP * 60)
	model.Parent = Workspace
	showTrunkBlock(false)
	fx("wake", { model = model, position = anchor, heart = first, maxHealth = maxHealth })
	StatsService.announce("The Thirst is full. The Thirsting Elder wakes in its grove!", LILY)
	local pivot = model:GetPivot().Position
	rise(model, pivot, pivot + UP * 60, 3)

	local entity = Registry.register(model, humanoid, root, "Elder", nil)
	entity.stunImmune = true
	entity.knockbackImmune = true
	entity.hitRadius = 12
	entity.baseWalkSpeed = 0
	local now = Registry.now()
	local awakening: Awakening = {
		entity = entity,
		model = model,
		heartPart = heartPart,
		anchor = anchor,
		maxHealth = maxHealth,
		awokeAt = now,
		heart = first,
		nextHeartAt = now + Constants.ELDER_PHASE_SECONDS,
		warned = false,
		enraged = false,
		woundUntil = 0,
		damageBy = {},
		branch = nil,
		grabbed = nil,
		sprouts = {},
		over = false,
	}
	current = awakening
	setHeart(awakening, first)
	publish(awakening)
	humanoid.Died:Once(function()
		fall(awakening)
	end)
	task.spawn(heartLoop, awakening)
	task.spawn(attackLoop, awakening)
end

function ElderService.isAwake(): boolean
	return current ~= nil
end

local function onElderHit(attacker: Entity?, kind: CombatMath.ElderHit, dealt: number, _healed: number)
	local awakening = current
	if not awakening then
		return
	end
	if kind == "Wound" then
		awakening.woundUntil = Registry.now() + Constants.ELDER_WOUND_PAUSE
	end
	if attacker and attacker.player and dealt > 0 then
		local name = attacker.player.Name
		awakening.damageBy[name] = (awakening.damageBy[name] or 0) + dealt
	end
end

function ElderService.init(_self: any)
	CombatService.onElderHit(onElderHit)
	ThirstService.onWake(ElderService.wake)
	Registry.onRemoved(function(entity)
		local awakening = current
		if awakening and awakening.grabbed == entity then
			release(awakening)
		end
	end)
end

return ElderService
