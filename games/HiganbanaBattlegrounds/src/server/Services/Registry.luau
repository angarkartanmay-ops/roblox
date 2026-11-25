--!strict
-- Every combatant (player characters, training dummies, the Thirsting Elder, its grab branch and
-- its Sap Sprouts) and its combat state. One record per model; recreated on respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)

-- Enemy and Boss are the Wilds' creatures and wardens (WildsService).
export type EntityKind = "Player" | "Dummy" | "Elder" | "Branch" | "Sprout" | "Enemy" | "Boss"
export type ZoneRule = "safe" | "nopvp" | "ffa"

export type Entity = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	kind: EntityKind,
	fighterId: string?,
	phase: Types.PhaseId?,
	hitRadius: number,
	baseWalkSpeed: number,
	baseJumpPower: number,
	baseJumpHeight: number,
	knockbackImmune: boolean,
	stunImmune: boolean,
	alive: boolean,

	-- where it stands (StatusService keeps these current)
	zone: string?,
	rule: ZoneRule,
	safe: boolean, -- the Ferry Landing: nothing lands on or from it

	-- timed statuses (server time)
	stunUntil: number,
	guardBrokenUntil: number,
	lockUntil: number,
	silenceUntil: number,
	slowUntil: number,
	slowFactor: number,
	rootUntil: number,
	bindUntil: number, -- a root drawn as chains
	purifiedUntil: number,
	superArmorUntil: number,
	burnUntil: number,
	burnDps: number,
	burnSource: Entity?,
	nextBurnTick: number,
	actionSlow: number,
	actionSlowUntil: number,
	speedBonus: number,
	speedBonusUntil: number,
	sapUntil: number, -- Elder's Sap
	mistUntil: number, -- Rokumon half-transparent in his mist
	reflectUntil: number, -- Canopy Guard
	reflectRoot: number,
	catchUntil: number, -- Jitte Catch
	catchParams: { [string]: number }?,
	grabbedBy: Entity?, -- held by the Elder's branch or Boulder Grip
	grabbedUntil: number,

	-- block and guard
	blocking: boolean,
	blockStartedAt: number?,
	lastBlockRelease: number,
	guard: number,
	lastGuardDamage: number,
	forceBlock: boolean, -- the guard dummy

	-- actions
	moveToken: number,
	currentMove: string?,
	cooldowns: { [string]: number },
	m1Index: number,
	lastM1At: number?,
	m1ReadyAt: number,
	dashReadyAt: number,

	-- Ki and Mend
	ki: number,
	mending: boolean,
	lastHitTakenAt: number,
	beachKi: number?, -- Ki held when stepping onto Jizo Beach (rolled back on leaving)

	-- passives
	rhythmCount: number,
	lastRhythmAt: number?,
	forceBeat: boolean, -- Kakegoe: the next landed hit is a Beat
	fareHits: number,
	coins: number,
	sproutStacks: number, -- Tsuta's Seed Volley stacks carried by this entity
	sproutUntil: number,
	sproutSource: Entity?,
	graftHits: number, -- Tsuta's Graft: hits left that heal her
	graftFraction: number,
	lastHitTarget: Entity?, -- Kanemori's Hunter's Chase remembers the last enemy he hit
	lastHitTargetAt: number,

	-- bookkeeping
	lastAttacker: Entity?,
	lastAttackedAt: number,
	lastCombatAt: number,
	damageTakenBy: { [string]: number }, -- this life, by attacker name (the death recap)
	published: { [string]: any },
}

local Registry = {}

local byModel: { [Model]: Entity } = {}
local addedListeners: { (Entity) -> () } = {}
local removedListeners: { (Entity) -> () } = {}

local worldParams = RaycastParams.new()
worldParams.FilterType = Enum.RaycastFilterType.Exclude
worldParams.IgnoreWater = true
local excludeDirty = true
local extraExcluded: { Instance } = {}

function Registry.now(): number
	return Workspace:GetServerTimeNow()
end

function Registry.register(model: Model, humanoid: Humanoid, root: BasePart, kind: EntityKind, player: Player?): Entity
	local existing = byModel[model]
	if existing then
		return existing
	end
	local entity: Entity = {
		model = model,
		humanoid = humanoid,
		root = root,
		player = player,
		kind = kind,
		fighterId = nil,
		phase = nil,
		hitRadius = 0,
		baseWalkSpeed = humanoid.WalkSpeed,
		baseJumpPower = humanoid.JumpPower,
		baseJumpHeight = humanoid.JumpHeight,
		knockbackImmune = false,
		stunImmune = false,
		alive = humanoid.Health > 0,

		zone = nil,
		rule = "ffa",
		safe = false,

		stunUntil = 0,
		guardBrokenUntil = 0,
		lockUntil = 0,
		silenceUntil = 0,
		slowUntil = 0,
		slowFactor = 1,
		rootUntil = 0,
		bindUntil = 0,
		purifiedUntil = 0,
		superArmorUntil = 0,
		burnUntil = 0,
		burnDps = 0,
		burnSource = nil,
		nextBurnTick = 0,
		actionSlow = 1,
		actionSlowUntil = 0,
		speedBonus = 0,
		speedBonusUntil = 0,
		sapUntil = 0,
		mistUntil = 0,
		reflectUntil = 0,
		reflectRoot = 0,
		catchUntil = 0,
		catchParams = nil,
		grabbedBy = nil,
		grabbedUntil = 0,

		blocking = false,
		blockStartedAt = nil,
		lastBlockRelease = 0,
		guard = Constants.GUARD_MAX,
		lastGuardDamage = 0,
		forceBlock = false,

		moveToken = 0,
		currentMove = nil,
		cooldowns = {},
		m1Index = 0,
		lastM1At = nil,
		m1ReadyAt = 0,
		dashReadyAt = 0,

		ki = 0,
		mending = false,
		lastHitTakenAt = 0,
		beachKi = nil,

		rhythmCount = 0,
		lastRhythmAt = nil,
		forceBeat = false,
		fareHits = 0,
		coins = 0,
		sproutStacks = 0,
		sproutUntil = 0,
		sproutSource = nil,
		graftHits = 0,
		graftFraction = 0,
		lastHitTarget = nil,
		lastHitTargetAt = 0,

		lastAttacker = nil,
		lastAttackedAt = 0,
		lastCombatAt = 0,
		damageTakenBy = {},
		published = {},
	}
	byModel[model] = entity
	excludeDirty = true

	humanoid.Died:Once(function()
		entity.alive = false
		entity.blocking = false
		entity.mending = false
	end)
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			Registry.unregister(model)
		end
	end)

	for _, listener in addedListeners do
		task.spawn(listener, entity)
	end
	return entity
end

function Registry.unregister(model: Model)
	local entity = byModel[model]
	if not entity then
		return
	end
	byModel[model] = nil
	entity.alive = false
	excludeDirty = true
	for _, listener in removedListeners do
		task.spawn(listener, entity)
	end
end

function Registry.get(model: Instance?): Entity?
	if model == nil or not model:IsA("Model") then
		return nil
	end
	return byModel[model]
end

function Registry.forPlayer(player: Player): Entity?
	local character = player.Character
	return if character then byModel[character] else nil
end

function Registry.isAlive(entity: Entity?): boolean
	return entity ~= nil
		and entity.alive
		and entity.humanoid.Health > 0
		and entity.model.Parent ~= nil
		and entity.root.Parent ~= nil
end

-- Living entities (a fresh array; safe to iterate while others register).
function Registry.all(): { Entity }
	local list = {}
	for _, entity in byModel do
		if Registry.isAlive(entity) then
			table.insert(list, entity)
		end
	end
	return list
end

-- Living player characters.
function Registry.players(): { Entity }
	local list = {}
	for _, entity in byModel do
		if entity.kind == "Player" and Registry.isAlive(entity) then
			table.insert(list, entity)
		end
	end
	return list
end

-- A readable name for kill feeds and the death recap.
function Registry.nameOf(entity: Entity?): string
	if entity == nil then
		return "the mist"
	end
	if entity.player then
		return entity.player.DisplayName
	end
	if entity.kind == "Elder" or entity.kind == "Branch" or entity.kind == "Sprout" then
		return "the Thirsting Elder"
	end
	return entity.model.Name
end

function Registry.onAdded(listener: (Entity) -> ())
	table.insert(addedListeners, listener)
end

function Registry.onRemoved(listener: (Entity) -> ())
	table.insert(removedListeners, listener)
end

-- Set a replicated attribute on the entity's model only when it changed.
function Registry.publish(entity: Entity, name: string, value: any)
	if entity.published[name] == value then
		return
	end
	entity.published[name] = value
	entity.model:SetAttribute(name, value)
end

function Registry.publishPlayer(entity: Entity, name: string, value: any)
	local key = "player:" .. name
	if entity.published[key] == value or entity.player == nil then
		return
	end
	entity.published[key] = value
	entity.player:SetAttribute(name, value)
end

-- Instances (besides characters) that world raycasts should ignore, e.g. effect folders.
function Registry.excludeFromWorld(instance: Instance)
	table.insert(extraExcluded, instance)
	excludeDirty = true
end

-- Raycast against the static world only (characters, dummies and the Elder are ignored).
function Registry.raycastWorld(origin: Vector3, direction: Vector3): RaycastResult?
	if excludeDirty then
		local list: { Instance } = table.clone(extraExcluded)
		for model in byModel do
			table.insert(list, model)
		end
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(list, player.Character)
			end
		end
		worldParams.FilterDescendantsInstances = list
		excludeDirty = false
	end
	return Workspace:Raycast(origin, direction, worldParams)
end

-- Ground position below `position` (or `position` itself when nothing is below).
function Registry.groundBelow(position: Vector3, depth: number?): Vector3
	local reach = depth or 60
	local result = Registry.raycastWorld(position + Vector3.new(0, 4, 0), Vector3.new(0, -(reach + 4), 0))
	return if result then result.Position else position
end

-- Is the entity standing on something (within `reach` studs of its root)?
function Registry.isGrounded(entity: Entity, reach: number?): boolean
	local distance = (reach or 4.2) * math.max(1, entity.root.Size.Y / 2)
	return Registry.raycastWorld(entity.root.Position, Vector3.new(0, -distance, 0)) ~= nil
end

function Registry.init(_self: any)
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			Registry.unregister(character)
		end
	end)
end

return Registry
