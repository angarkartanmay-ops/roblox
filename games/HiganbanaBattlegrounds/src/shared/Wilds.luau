--!strict
-- The Wilds: three islands adrift in the mist beyond the Far Shore, each joined to it by a bridge.
-- They are hunting grounds (souls cannot hurt each other there) held by the restless dead of
-- the river crossing and by three wardens drawn from old hell-gate and river folklore. This module
-- is the shared data: the map builder (work/map/build_wilds.lua), WildsService (spawning, AI,
-- attacks) and WildsController (telegraphs, boss bar, minimap, banners) all read it, so the island
-- the builder raised, the camp the server fills and the dot the minimap draws cannot disagree.

local Types = require("./Types")

type PhaseId = Types.PhaseId

export type Rule = "safe" | "nopvp" | "ffa"

export type Region = {
	id: string,
	title: string,
	subtitle: string,
	phase: PhaseId,
	center: { number }, -- x, z
	radius: number,
	ground: number, -- world height of the plateau
	bridgeFrom: { number }, -- x, z on the Far Shore
	bridgeTo: { number }, -- x, z on this island (its entrance and fast-travel point)
	arena: { number }, -- x, z of the warden's arena
	arenaRadius: number,
	boss: string,
	surface: string, -- Enum.Material name for the plateau
	cliff: string,
}

export type AttackKind = "circle" | "cone" | "lane" | "charge" | "projectile" | "blink" | "donut"

export type Attack = {
	id: string,
	name: string,
	kind: AttackKind,
	range: number, -- used when the target is at most this far
	windup: number,
	recover: number,
	cooldown: number,
	damage: number,
	stun: number?,
	knockback: Types.Knockback?,
	radial: boolean?,
	slow: Types.Slow?,
	burn: Types.Burn?,
	root: number?,
	yank: number?,
	unblockable: boolean?,
	radius: number?, -- circle / donut outer / cone reach / projectile hit radius
	inner: number?, -- donut: the safe ring inside
	angle: number?, -- cone: half angle in degrees
	length: number?, -- lane / charge
	width: number?,
	count: number?, -- projectiles or circles
	spread: number?, -- projectile fan, degrees between shots
	speed: number?, -- projectile studs/s
	at: ("self" | "target" | "targets")?,
	pose: string,
	color: { number },
	enraged: boolean?, -- only once the warden is enraged
	weight: number?,
}

export type Creature = {
	id: string,
	name: string,
	epithet: string,
	glyph: string,
	phase: PhaseId,
	boss: boolean,
	health: number,
	walkSpeed: number,
	scale: number,
	aggro: number,
	leash: number,
	petals: number,
	thirst: number,
	enrageAt: number?, -- health fraction
	attacks: { Attack },
}

export type Camp = {
	id: string,
	title: string,
	region: string,
	offset: { number }, -- x, z from the region centre
	creatures: { { id: string, count: number } },
	respawn: number,
}

local Wilds = {}

Wilds.RULE = "nopvp" :: Rule
Wilds.BOSS_RESPAWN = 180
Wilds.BOSS_RESET = 8 -- seconds with nobody in the arena before a warden heals and resets
Wilds.BOSS_SHARE = 0.05 -- fraction of a warden's health a soul must deal to share its reward
Wilds.BOSS_PETALS = 60

---------------------------------------------------------------------------------------------------
-- Regions

Wilds.REGIONS = {
	{
		id = "Gatewaste",
		title = "The Gatewaste",
		subtitle = "Ash fields before a hell-gate that was never closed",
		phase = "Earth",
		center = { -570, -40 },
		radius = 180,
		ground = 54,
		bridgeFrom = { -225, -40 },
		bridgeTo = { -405, -40 },
		arena = { -640, -40 },
		arenaRadius = 46,
		boss = "OxHeadJailer",
		surface = "Basalt",
		cliff = "Asphalt",
	},
	{
		id = "LanternRoad",
		title = "The Lantern Road",
		subtitle = "Where fox-fire leads a wedding that never arrives",
		phase = "Fire",
		center = { 580, 20 },
		radius = 180,
		ground = 56,
		bridgeFrom = { 228, 20 },
		bridgeTo = { 412, 20 },
		arena = { 655, 10 },
		arenaRadius = 46,
		boss = "LanternBride",
		surface = "LeafyGrass",
		cliff = "Sandstone",
	},
	{
		id = "RobeShallows",
		title = "The Robe-Taker's Shallows",
		subtitle = "The far bank, where the dead are weighed by their clothes",
		phase = "Water",
		center = { 60, -600 },
		radius = 190,
		ground = 50,
		bridgeFrom = { 60, -232 },
		bridgeTo = { 60, -422 },
		arena = { 60, -690 },
		arenaRadius = 48,
		boss = "RobeTaker",
		surface = "Sand",
		cliff = "Glacier",
	},
} :: { Region }

-- Names the banner shows for the Far Shore's own zones (FarShore.ZONES ids).
Wilds.ZONE_TITLES = {
	FerryLanding = { "The Ferry Landing", "Nothing lands here. Choose your phase." },
	JizoBeach = { "Jizo Beach", "Training stones. Souls do not fight here." },
	Riverbed = { "The Dry Riverbed", "The river ran out of dead to carry." },
	LilyFields = { "The Lily Fields", "Every flower is a soul that stayed." },
	EldersGrove = { "The Elder's Grove", "It sleeps while the Thirst is low." },
	Barrows = { "The Barrows", "Old mounds, older names." },
	PineBluff = { "Pine Bluff", "The wind up here remembers the living." },
} :: { [string]: { string } }

---------------------------------------------------------------------------------------------------
-- Creatures

local RED = { 214, 52, 46 }
local EMBER = { 255, 140, 50 }
local LEAF = { 90, 180, 90 }
local STONE = { 196, 170, 120 }
local STEEL = { 210, 220, 235 }
local RIVER = { 80, 140, 230 }
local FOX = { 150, 210, 255 }

Wilds.CREATURES = {
	-- Wood: a pilgrim's body with a spider lily where its head was.
	BlossomHusk = {
		id = "BlossomHusk",
		name = "Blossom Husk",
		epithet = "a pilgrim the lilies finished",
		glyph = "木",
		phase = "Wood",
		boss = false,
		health = 80,
		walkSpeed = 11,
		scale = 1,
		aggro = 38,
		leash = 60,
		petals = 4,
		thirst = 3,
		attacks = {
			{
				id = "VineLash",
				name = "Vine Lash",
				kind = "cone",
				range = 9,
				windup = 0.65,
				recover = 0.5,
				cooldown = 2.2,
				damage = 7,
				stun = 0.35,
				slow = { factor = 0.6, duration = 1.5 },
				radius = 10,
				angle = 50,
				pose = "Wild_Swipe",
				color = LEAF,
			},
			{
				id = "PollenBurst",
				name = "Pollen Burst",
				kind = "circle",
				at = "self",
				range = 7,
				windup = 1,
				recover = 0.6,
				cooldown = 6,
				damage = 6,
				root = 0.9,
				radius = 9,
				pose = "Wild_Roar",
				color = RED,
			},
		},
	},
	-- Fire: a corpse-stealing cat demon with a paper lantern for a tail.
	LanternKasha = {
		id = "LanternKasha",
		name = "Lantern Kasha",
		epithet = "it carries off the dead it likes",
		glyph = "火",
		phase = "Fire",
		boss = false,
		health = 70,
		walkSpeed = 17,
		scale = 1,
		aggro = 42,
		leash = 65,
		petals = 4,
		thirst = 3,
		attacks = {
			{
				id = "Pounce",
				name = "Pounce",
				kind = "charge",
				range = 18,
				windup = 0.55,
				recover = 0.6,
				cooldown = 4,
				damage = 8,
				stun = 0.4,
				knockback = { forward = 26, up = 14 },
				length = 18,
				width = 6,
				pose = "Wild_Lunge",
				color = EMBER,
			},
			{
				id = "EmberClaw",
				name = "Ember Claw",
				kind = "cone",
				range = 6.5,
				windup = 0.4,
				recover = 0.4,
				cooldown = 1.6,
				damage = 5,
				burn = { dps = 2, duration = 3 },
				radius = 7.5,
				angle = 55,
				pose = "Wild_Swipe",
				color = EMBER,
			},
		},
	},
	-- Earth: a roadside guardian statue that got up and kept walking.
	StoneAcolyte = {
		id = "StoneAcolyte",
		name = "Stone Acolyte",
		epithet = "a road statue that forgot it was one",
		glyph = "土",
		phase = "Earth",
		boss = false,
		health = 160,
		walkSpeed = 9,
		scale = 1.25,
		aggro = 34,
		leash = 55,
		petals = 6,
		thirst = 4,
		attacks = {
			{
				id = "PillarDrop",
				name = "Pillar Drop",
				kind = "circle",
				at = "target",
				range = 22,
				windup = 1.15,
				recover = 0.8,
				cooldown = 5,
				damage = 11,
				stun = 0.4,
				knockback = { forward = 8, up = 26 },
				radial = true,
				radius = 7,
				pose = "Wild_Slam",
				color = STONE,
			},
			{
				id = "StaffSweep",
				name = "Staff Sweep",
				kind = "cone",
				range = 8,
				windup = 0.7,
				recover = 0.6,
				cooldown = 2.6,
				damage = 8,
				stun = 0.3,
				knockback = { forward = 30, up = 8 },
				radius = 9.5,
				angle = 75,
				pose = "Wild_Sweep",
				color = STONE,
			},
		},
	},
	-- Metal: a bone-thin swordsman who still pays the toll in iron nails.
	NailRonin = {
		id = "NailRonin",
		name = "Nail Ronin",
		epithet = "he paid the ferry in nails",
		glyph = "金",
		phase = "Metal",
		boss = false,
		health = 80,
		walkSpeed = 14,
		scale = 1,
		aggro = 44,
		leash = 65,
		petals = 5,
		thirst = 3,
		attacks = {
			{
				id = "DrawCut",
				name = "Draw Cut",
				kind = "lane",
				range = 13,
				windup = 0.7,
				recover = 0.5,
				cooldown = 3.2,
				damage = 8,
				stun = 0.3,
				length = 14,
				width = 5,
				pose = "Wild_DrawCut",
				color = STEEL,
			},
			{
				id = "NailThrow",
				name = "Nail Throw",
				kind = "projectile",
				range = 40,
				windup = 0.55,
				recover = 0.4,
				cooldown = 3.5,
				damage = 5,
				stun = 0.2,
				count = 3,
				spread = 10,
				speed = 70,
				radius = 2.4,
				length = 45,
				pose = "Wild_Throw",
				color = STEEL,
			},
		},
	},
	-- Water: a drowned boat-hand with a dish of river on its head.
	DrownedFerryhand = {
		id = "DrownedFerryhand",
		name = "Drowned Ferryhand",
		epithet = "it still wants a passenger",
		glyph = "水",
		phase = "Water",
		boss = false,
		health = 95,
		walkSpeed = 12,
		scale = 1.1,
		aggro = 38,
		leash = 60,
		petals = 5,
		thirst = 3,
		attacks = {
			{
				id = "Undertow",
				name = "Undertow",
				kind = "lane",
				range = 15,
				windup = 0.75,
				recover = 0.6,
				cooldown = 5,
				damage = 6,
				stun = 0.5,
				yank = 14,
				length = 16,
				width = 5,
				pose = "Wild_Grab",
				color = RIVER,
			},
			{
				id = "RiverSpit",
				name = "River Spit",
				kind = "projectile",
				range = 30,
				windup = 0.6,
				recover = 0.5,
				cooldown = 3,
				damage = 6,
				slow = { factor = 0.55, duration = 2 },
				count = 1,
				speed = 50,
				radius = 3,
				length = 34,
				pose = "Wild_Throw",
				color = RIVER,
			},
		},
	},

	---------------------------------------------------------------------------------------------
	-- Wardens

	-- The ox-headed jailer of the hell-gate, with an iron club and the gate's own chains.
	OxHeadJailer = {
		id = "OxHeadJailer",
		name = "Ox-Head Jailer",
		epithet = "Keeper of the Unclosed Gate",
		glyph = "牛",
		phase = "Earth",
		boss = true,
		health = 750,
		walkSpeed = 13,
		scale = 3,
		aggro = 40,
		leash = 52,
		petals = Wilds.BOSS_PETALS,
		thirst = 30,
		enrageAt = 0.5,
		attacks = {
			{
				id = "KanaboCrush",
				name = "Kanabo Crush",
				kind = "circle",
				at = "target",
				range = 20,
				windup = 1.2,
				recover = 0.9,
				cooldown = 3.5,
				damage = 22,
				stun = 0.6,
				knockback = { forward = 10, up = 30 },
				radial = true,
				radius = 11,
				pose = "Wild_Slam",
				color = RED,
				weight = 3,
			},
			{
				id = "GateCharge",
				name = "Gate Charge",
				kind = "charge",
				range = 45,
				windup = 1.1,
				recover = 1.2,
				cooldown = 9,
				damage = 18,
				stun = 0.5,
				knockback = { forward = 60, up = 22 },
				unblockable = true,
				length = 44,
				width = 11,
				pose = "Wild_Lunge",
				color = RED,
				weight = 2,
			},
			{
				id = "ChainSweep",
				name = "Chain Sweep",
				kind = "circle",
				at = "self",
				range = 15,
				windup = 1,
				recover = 0.8,
				cooldown = 7,
				damage = 14,
				stun = 0.4,
				yank = 9,
				radius = 17,
				pose = "Wild_Sweep",
				color = STEEL,
				weight = 2,
			},
			{
				id = "GateQuake",
				name = "Gate Quake",
				kind = "circle",
				at = "targets",
				range = 60,
				windup = 1.4,
				recover = 1,
				cooldown = 10,
				damage = 18,
				stun = 0.6,
				knockback = { forward = 4, up = 34 },
				count = 4,
				radius = 9,
				pose = "Wild_Roar",
				color = STONE,
				enraged = true,
				weight = 3,
			},
		},
	},
	-- A fox-masked bride under a paper umbrella; her procession is fox-fire.
	LanternBride = {
		id = "LanternBride",
		name = "The Lantern Bride",
		epithet = "Her Procession Never Arrives",
		glyph = "狐",
		phase = "Fire",
		boss = true,
		health = 650,
		walkSpeed = 15,
		scale = 2.6,
		aggro = 40,
		leash = 52,
		petals = Wilds.BOSS_PETALS,
		thirst = 30,
		enrageAt = 0.5,
		attacks = {
			{
				id = "FoxfireVolley",
				name = "Foxfire Volley",
				kind = "projectile",
				range = 45,
				windup = 0.8,
				recover = 0.6,
				cooldown = 4,
				damage = 9,
				burn = { dps = 3, duration = 3 },
				count = 5,
				spread = 12,
				speed = 55,
				radius = 3,
				length = 55,
				pose = "Wild_Cast",
				color = FOX,
				weight = 3,
			},
			{
				id = "UmbrellaWhirl",
				name = "Umbrella Whirl",
				kind = "circle",
				at = "self",
				range = 12,
				windup = 0.9,
				recover = 0.7,
				cooldown = 5,
				damage = 15,
				stun = 0.4,
				knockback = { forward = 40, up = 16 },
				radial = true,
				radius = 13,
				pose = "Wild_Spin",
				color = RED,
				weight = 2,
			},
			{
				id = "Procession",
				name = "Wedding Procession",
				kind = "blink",
				range = 50,
				windup = 0.9,
				recover = 0.8,
				cooldown = 8,
				damage = 16,
				stun = 0.6,
				knockback = { forward = 30, up = 18 },
				radius = 10,
				angle = 70,
				pose = "Wild_Swipe",
				color = FOX,
				weight = 2,
			},
			{
				id = "ThousandLanterns",
				name = "A Thousand Lanterns",
				kind = "circle",
				at = "targets",
				range = 60,
				windup = 1.5,
				recover = 1,
				cooldown = 11,
				damage = 16,
				burn = { dps = 3, duration = 3 },
				count = 8,
				radius = 7,
				pose = "Wild_Cast",
				color = EMBER,
				enraged = true,
				weight = 3,
			},
		},
	},
	-- The old woman of the far bank who strips the dead and hangs their robes on her tree.
	RobeTaker = {
		id = "RobeTaker",
		name = "The Robe-Taker",
		epithet = "Old Woman of the Far Bank",
		glyph = "衣",
		phase = "Water",
		boss = true,
		health = 700,
		walkSpeed = 12,
		scale = 2.8,
		aggro = 42,
		leash = 54,
		petals = Wilds.BOSS_PETALS,
		thirst = 30,
		enrageAt = 0.5,
		attacks = {
			{
				id = "StripTheDead",
				name = "Strip the Dead",
				kind = "lane",
				range = 22,
				windup = 0.9,
				recover = 0.8,
				cooldown = 6,
				damage = 12,
				stun = 0.9,
				yank = 20,
				length = 24,
				width = 7,
				pose = "Wild_Grab",
				color = RIVER,
				weight = 2,
			},
			{
				id = "SanzuTide",
				name = "Sanzu Tide",
				kind = "lane",
				range = 40,
				windup = 1.1,
				recover = 0.8,
				cooldown = 5,
				damage = 14,
				knockback = { forward = 45, up = 10 },
				slow = { factor = 0.5, duration = 2.5 },
				unblockable = true,
				length = 48,
				width = 12,
				count = 3,
				spread = 40,
				pose = "Wild_Cast",
				color = RIVER,
				weight = 3,
			},
			{
				id = "RobeSnare",
				name = "Robe Snare",
				kind = "circle",
				at = "targets",
				range = 50,
				windup = 1.2,
				recover = 0.7,
				cooldown = 7,
				damage = 12,
				root = 1.6,
				count = 3,
				radius = 6.5,
				pose = "Wild_Roar",
				color = { 230, 226, 214 },
				weight = 2,
			},
			{
				id = "WeightOfSins",
				name = "Weight of Sins",
				kind = "donut",
				range = 60,
				windup = 1.8,
				recover = 1.2,
				cooldown = 12,
				damage = 24,
				stun = 0.8,
				unblockable = true,
				inner = 8,
				radius = 30,
				pose = "Wild_Roar",
				color = { 120, 90, 200 },
				enraged = true,
				weight = 4,
			},
		},
	},
} :: { [string]: Creature }

---------------------------------------------------------------------------------------------------
-- Camps (three per island; the warden holds the arena)

Wilds.CAMPS = {
	{
		id = "ShackleYard",
		title = "Shackle Yard",
		region = "Gatewaste",
		offset = { 45, 70 },
		creatures = { { id = "StoneAcolyte", count = 2 }, { id = "NailRonin", count = 2 } },
		respawn = 35,
	},
	{
		id = "AshPits",
		title = "Ash Pits",
		region = "Gatewaste",
		offset = { 40, -85 },
		creatures = { { id = "LanternKasha", count = 3 } },
		respawn = 30,
	},
	{
		id = "BrokenCells",
		title = "Broken Cells",
		region = "Gatewaste",
		offset = { -55, 95 },
		creatures = { { id = "StoneAcolyte", count = 1 }, { id = "NailRonin", count = 2 } },
		respawn = 35,
	},
	{
		id = "FoxShrine",
		title = "Fox Shrine",
		region = "LanternRoad",
		offset = { -45, 80 },
		creatures = { { id = "LanternKasha", count = 3 } },
		respawn = 30,
	},
	{
		id = "DrownedPaddies",
		title = "Drowned Paddies",
		region = "LanternRoad",
		offset = { -35, -85 },
		creatures = { { id = "BlossomHusk", count = 3 } },
		respawn = 30,
	},
	{
		id = "PaperMarket",
		title = "Paper Market",
		region = "LanternRoad",
		offset = { 50, 100 },
		creatures = { { id = "NailRonin", count = 2 }, { id = "LanternKasha", count = 1 } },
		respawn = 35,
	},
	{
		id = "ReedGraves",
		title = "Reed Graves",
		region = "RobeShallows",
		offset = { -85, 40 },
		creatures = { { id = "DrownedFerryhand", count = 3 } },
		respawn = 30,
	},
	{
		id = "DrowningLilies",
		title = "Drowning Lilies",
		region = "RobeShallows",
		offset = { 85, 30 },
		creatures = { { id = "BlossomHusk", count = 2 }, { id = "DrownedFerryhand", count = 1 } },
		respawn = 30,
	},
	{
		id = "BoneWeir",
		title = "Bone Weir",
		region = "RobeShallows",
		offset = { -90, -60 },
		creatures = { { id = "DrownedFerryhand", count = 2 }, { id = "StoneAcolyte", count = 1 } },
		respawn = 35,
	},
} :: { Camp }

-- Ferry lanterns on the Ferry Landing: one per island, lit once a soul has walked there.
Wilds.FERRY_LANTERNS = {
	{ region = "Gatewaste", at = { -22, 50, 118 } },
	{ region = "RobeShallows", at = { 0, 50, 112 } },
	{ region = "LanternRoad", at = { 22, 50, 118 } },
}
Wilds.LANDING_RETURN = { 0, 50, 140 }

---------------------------------------------------------------------------------------------------
-- Lookups

local byRegion: { [string]: Region } = {}
for _, region in Wilds.REGIONS do
	byRegion[region.id] = region
end

function Wilds.region(id: string?): Region?
	return if id then byRegion[id] else nil
end

function Wilds.creature(id: string?): Creature?
	return if id then Wilds.CREATURES[id] else nil
end

function Wilds.attack(creatureId: string?, attackId: string?): Attack?
	local creature = Wilds.creature(creatureId)
	if not creature or not attackId then
		return nil
	end
	for _, attack in creature.attacks do
		if attack.id == attackId then
			return attack
		end
	end
	return nil
end

-- The camp's world x, z.
function Wilds.campPosition(camp: Camp): (number, number)
	local region = byRegion[camp.region]
	return region.center[1] + camp.offset[1], region.center[2] + camp.offset[2]
end

-- The island containing (x, z), if any.
function Wilds.regionAt(x: number, z: number): Region?
	for _, region in Wilds.REGIONS do
		local dx, dz = x - region.center[1], z - region.center[2]
		if dx * dx + dz * dz <= region.radius * region.radius then
			return region
		end
	end
	return nil
end

function Wilds.color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

return Wilds
