--!strict
-- Every tunable the game reads. Values come from design/game.json `config` (constants.spec checks
-- the two agree); the rest are engine feel numbers inherited from the combat core.

local Constants = {
	-- server
	MAX_PLAYERS = 12,
	RESPAWN_SECONDS = 4,
	LANDING_SAFE_RADIUS = 40,
	PHASE_SWITCH_OOC = 8, -- seconds out of combat before a fighter may switch away from the landing

	-- the Five Phases (relation multipliers)
	OVERCOME_DAMAGE = 1.2,
	OVERCOME_GUARD = 1.5,
	RESISTED_DAMAGE = 0.85,
	FEEDING_DAMAGE = 0.9,
	FEEDING_KI_TO_TARGET = 0.5,
	DRAWING_KI_BONUS = 0.5,

	-- Ki and Mend
	KI_MAX = 100,
	KI_PER_DAMAGE_DEALT = 1.0,
	KI_PER_DAMAGE_TAKEN = 0.5,
	MEND_KI_PER_SECOND = 12,
	MEND_HEALTH_PER_KI = 1.0,
	MEND_LOCKOUT = 3, -- seconds after taking a hit
	MEND_SPEED = 0.5, -- walk speed multiplier while mending

	-- M1 chain
	COMBO_HITS = 4,
	COMBO_RESET = 1.1,
	FINISHER_LOCK = 1.0,
	M1_STUN = 0.45,
	FINISHER_STUN = 0.75,

	-- block, guard, parry, dash
	GUARD_MAX = 100,
	BLOCK_ABILITY_FACTOR = 0.4,
	GUARD_BREAK_STUN = 1.6,
	PARRY_WINDOW = 0.22,
	PARRY_STUN = 1.25,
	BLOCK_FACING_DOT = 0.15,
	BLOCK_WALK_FACTOR = 0.45,
	BLOCK_RESTART_DELAY = 0.35,
	GUARD_PER_DAMAGE = 3,
	GUARD_REGEN = 18,
	GUARD_REGEN_DELAY = 1.5,
	DASH_COOLDOWN = 1.8,
	DASH_SPEED = 72,
	DASH_DURATION = 0.22,

	-- statuses and movement
	DEFAULT_MOVE_SLOW = 0.35,
	STUN_WALK_SPEED = 2,
	HIT_TOLERANCE = 1.6,
	BURN_TICK = 0.5,

	-- kills and Petals
	KILL_CREDIT_WINDOW = 10,
	PETALS_PER_KILL = 5,
	PETALS_PER_STREAK_STEP = 2,
	STREAK_ANNOUNCE = { 3, 5, 10 },
	COMBAT_TAG_TIME = 8,
	SELECT_COOLDOWN = 2,

	-- the Thirst and the Thirsting Elder
	THIRST_BASE = 2400,
	THIRST_PER_PLAYER = 300,
	THIRST_FIRST_AWAKE = 120,
	THIRST_COOLDOWN_AFTER_FALL = 180,
	ELDER_HEALTH_BASE = 2000,
	ELDER_HEALTH_PER_PLAYER = 400,
	ELDER_PHASE_SECONDS = 18,
	ELDER_PHASE_SECONDS_ENRAGED = 12,
	ELDER_PHASE_WARNING = 3,
	ELDER_REGEN_PERCENT = 1.5,
	ELDER_WOUND_PAUSE = 4,
	ELDER_OVERCOME_BONUS = 1.5,
	ELDER_FEEDING_HEAL = 0.5,
	ELDER_ENRAGE_AT = 0.35,
	ELDER_TIMEOUT = 240,
	ELDER_BRANCH_HEALTH = 120,
	ELDER_GRAB_DRAIN = 15,
	ELDER_GRAB_SECONDS = 2.5,
	SAP_SPROUT_COUNT = 3,
	SAP_SPROUT_HEAL_SECONDS = 10,
	SAP_SPROUT_HEAL_FRACTION = 0.05,
	ELDER_REWARD_MIN_SHARE = 0.04,
	ELDER_REWARD_PETALS = 30,
	ELDER_SAP_SECONDS = 120,
	ELDER_SAP_DAMAGE = 0.1,
	ELDER_SAP_MEND = 0.2,

	-- fighter passives
	HIBIKI_BEAT_EVERY = 3,
	HIBIKI_BEAT_BONUS = 0.25,
	HIBIKI_RHYTHM_WINDOW = 2,
	ROKUMON_HITS_PER_COIN = 6,
	ROKUMON_MAX_COINS = 6,
	ROKUMON_TOLL_PER_COIN = 6,
	IWAO_KNOCKBACK_TAKEN = 0.7,
	IWAO_DOHYO_SECONDS = 6,
	IWAO_DOHYO_RADIUS = 16,
	IWAO_RING_OUT_DAMAGE = 25,
	KANEMORI_PARRY_SILENCE = 2,
	TSUTA_SPROUT_BURST = 3,
	TSUTA_SPROUT_SECONDS = 6,

	-- networking
	ACTION_BURST = 12,
	ACTION_REFILL = 10,
	DEBUG_ATTRIBUTE = "HiganCombatDebug",

	-- HitFx flags (a bit field shared by the server's Net and the client's Remotes)
	FLAG = table.freeze({
		BLOCKED = 1,
		PARRIED = 2,
		GUARD_BREAK = 4,
		OVERCOME = 8,
		RESISTED = 16,
		FEEDING = 32,
		DRAWING = 64,
		BURN = 128,
		BEAT = 256,
		WOUND = 512, -- an overcoming hit on the Elder's heart
		HEAL = 1024, -- the amount is health restored, not damage
		REFLECT = 2048,
		CATCH = 4096,
		RING_OUT = 8192,
		SPROUT = 16384, -- a Sprout burst
	}),
}

return table.freeze(Constants)
