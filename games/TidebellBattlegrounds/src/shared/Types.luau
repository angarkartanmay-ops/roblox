--!strict
-- Shared type definitions. Every shared module is pure (no Roblox globals) so Lune can load it in tests.

export type ElementId = "Earth" | "Water" | "Fire" | "Wind" | "Void"
export type SlotId = "M1" | "Ability1" | "Ability2" | "Ability3" | "Ability4" | "Ultimate"

export type Knockback = { forward: number, up: number }
export type Slow = { factor: number, duration: number }
export type Burn = { dps: number, duration: number }
export type Echo = { delay: number, damage: number, stun: number }

export type HitSpec = {
	at: number, -- seconds after the move starts
	shape: "Box" | "Sphere",
	size: { number }?, -- Box: { x, y, z } in studs
	radius: number?, -- Sphere
	forward: number?, -- centre offset ahead of the anchor
	up: number?,
	anchor: ("self" | "origin" | "point")?, -- current root, root at cast time, or the move's target point
	damage: number,
	stun: number,
	knockback: Knockback?,
	radial: boolean?, -- push away from the hit centre instead of along the caster's facing
	pull: number?, -- velocity toward the caster
	guardBreak: boolean?,
	group: string?, -- a target is hit at most once per move by all hits sharing a group
	slow: Slow?,
	silence: number?,
	burn: Burn?,
	echo: Echo?,
	unblockable: boolean?,
}

export type Explosion = {
	radius: number,
	damage: number,
	stun: number,
	knockback: Knockback?,
	burn: Burn?,
}

export type ProjectileSpec = {
	at: number,
	kind: string, -- visual id (see VfxCatalog.PROJECTILES)
	speed: number,
	radius: number,
	range: number,
	damage: number,
	stun: number,
	knockback: Knockback?,
	pierce: boolean?,
	homing: number?, -- max turn rate in radians per second
	returns: boolean?, -- flies out to range, then back to the caster
	spread: number?, -- yaw offset in degrees
	up: number?, -- spawn height above the root
	explode: Explosion?,
	slow: Slow?,
	burn: Burn?,
}

export type Impulse = { forward: number, up: number, duration: number }
export type SelfSpec = { at: number, impulse: Impulse }

export type MoveSpec = {
	id: string,
	name: string,
	description: string,
	slot: SlotId,
	cooldown: number,
	lock: number, -- the caster cannot start another action for this long
	moveSlow: number?, -- walk-speed factor while the move runs (Constants.DEFAULT_MOVE_SLOW otherwise)
	superArmor: boolean?, -- hits do not stun or interrupt the caster
	pose: string, -- Poses.SEQUENCES id
	vfx: string, -- VfxCatalog.MOVES id
	hits: { HitSpec }?,
	projectiles: { ProjectileSpec }?,
	self: SelfSpec?,
	pointForward: number?, -- "point" anchor: studs ahead of the caster at cast time
	special: string?, -- behaviour implemented in code (see VfxCatalog.SPECIALS)
	params: { [string]: number }?,
}

export type M1Spec = {
	style: string, -- pose family, see Poses.M1_STYLES
	interval: number, -- seconds between swings
	hitDelay: number,
	damage: { number }, -- one entry per chain hit (4)
	size: { number }, -- hitbox { x, y, z }
	forward: number, -- hitbox centre ahead of the root
	finisherKnockback: Knockback,
}

export type FighterSpec = {
	id: string,
	displayName: string,
	title: string,
	element: ElementId,
	role: string,
	difficulty: number,
	blurb: string,
	color: { number }, -- rgb 0-1
	accent: { number },
	maxHealth: number,
	walkSpeed: number,
	weapon: string,
	m1: M1Spec,
	moves: { MoveSpec }, -- Ability1-4 and Ultimate, in slot order
}

export type JointPose = {
	rx: number?,
	ry: number?,
	rz: number?,
	px: number?,
	py: number?,
	pz: number?,
}
export type Pose = { [string]: JointPose }
export type PoseKey = { t: number, pose: string }
export type Sequence = { keys: { PoseKey }, duration: number, fadeIn: number, fadeOut: number }

return {}
