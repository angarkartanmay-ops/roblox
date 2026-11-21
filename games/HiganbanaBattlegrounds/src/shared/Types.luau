--!strict
-- Shared data shapes for fighters, moves, hits, projectiles and procedural poses.

export type PhaseId = "Wood" | "Fire" | "Earth" | "Metal" | "Water"
export type Relation = "Overcome" | "Resisted" | "Feeding" | "Drawing" | "Neutral"
export type SlotId = "M1" | "Ability1" | "Ability2" | "Ability3" | "Ability4" | "Ultimate"

export type Knockback = { forward: number, up: number }
export type Slow = { factor: number, duration: number }
export type Burn = { dps: number, duration: number }

export type HitSpec = {
	at: number,
	shape: "Box" | "Sphere",
	size: { number }?,
	radius: number?,
	forward: number?,
	up: number?,
	anchor: ("self" | "origin" | "point")?,
	damage: number,
	stun: number,
	knockback: Knockback?,
	radial: boolean?,
	pull: number?, -- studs per second toward the attacker
	guardBreak: boolean?,
	guardMultiplier: number?, -- extra guard damage (Iron Edict: 2)
	group: string?, -- hits sharing a group land once per victim per cast
	slow: Slow?,
	silence: number?,
	burn: Burn?,
	root: number?, -- seconds unable to walk, jump or dash
	bind: number?, -- a root drawn as chains
	purify: number?, -- seconds Purified: buffs stripped, no Ki gain, no Mend
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
	kind: string,
	speed: number,
	radius: number,
	range: number,
	damage: number,
	stun: number,
	knockback: Knockback?,
	pierce: boolean?,
	homing: number?,
	returns: boolean?,
	spread: number?,
	up: number?,
	explode: Explosion?,
	slow: Slow?,
	burn: Burn?,
	root: number?,
	sprout: boolean?, -- adds a Sprout stack (Seed Volley)
	yank: number?, -- studs to drag the victim toward the thrower (Chain Lash)
	weapon: boolean?, -- a thrown weapon: Jitte Catch can catch it
}

export type Impulse = { forward: number, up: number, duration: number }
export type SelfSpec = { at: number, impulse: Impulse }

export type MoveSpec = {
	id: string,
	name: string,
	description: string,
	slot: SlotId,
	cooldown: number,
	lock: number,
	moveSlow: number?,
	superArmor: boolean?,
	pose: string,
	vfx: string,
	hits: { HitSpec }?,
	projectiles: { ProjectileSpec }?,
	self: SelfSpec?,
	pointForward: number?, -- default aimed point distance
	pointRange: number?, -- snap the point to an enemy in front within this range
	special: string?,
	params: { [string]: number }?,
}

export type M1Spec = {
	style: string, -- pose family: <style>_M1_A / _M1_B / _M1_Finisher
	interval: number,
	hitDelay: number, -- contact marker of the _M1_A / _M1_B clips
	finisherDelay: number, -- contact marker of the _M1_Finisher clip
	damage: { number },
	size: { number },
	forward: number,
	finisherKnockback: Knockback?,
	finisherStun: number?,
	finisherBurn: Burn?,
}

export type FighterSpec = {
	id: string,
	displayName: string,
	title: string,
	phase: PhaseId,
	role: string,
	difficulty: number,
	blurb: string,
	passiveName: string?,
	passive: string?,
	color: { number }, -- 0..1
	accent: { number }, -- 0..1
	maxHealth: number,
	walkSpeed: number,
	weapon: string,
	worn: { string },
	m1: M1Spec,
	moves: { MoveSpec },
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
export type Sequence = {
	keys: { PoseKey },
	duration: number,
	fadeIn: number,
	fadeOut: number,
	upper: boolean?, -- leave the legs to the walk cycle (idles)
}

return nil
