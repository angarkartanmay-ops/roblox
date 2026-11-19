--!strict
-- Combat and economy tunables shared by server and client.

local Constants = {
	-- M1 chain
	COMBO_HITS = 4,
	COMBO_RESET = 1.1, -- seconds without a swing before the chain restarts
	FINISHER_LOCK = 1.0, -- M1 lockout after the 4th hit
	M1_STUN = 0.45,
	FINISHER_STUN = 0.75,

	-- Block, guard and parry
	PARRY_WINDOW = 0.22,
	PARRY_STUN = 1.25,
	BLOCK_ABILITY_FACTOR = 0.4, -- abilities deal 40 % through a block; M1s deal nothing
	BLOCK_FACING_DOT = 0.15, -- the attacker must be in front of the blocker
	BLOCK_WALK_FACTOR = 0.45,
	BLOCK_RESTART_DELAY = 0.35, -- anti block-spam
	GUARD_MAX = 100,
	GUARD_PER_DAMAGE = 3,
	GUARD_REGEN = 18, -- per second
	GUARD_REGEN_DELAY = 1.5,
	GUARD_BREAK_STUN = 1.6,

	-- Dash
	DASH_COOLDOWN = 1.8,
	DASH_SPEED = 72,
	DASH_DURATION = 0.22,

	-- Ultimate meter
	RESONANCE_MAX = 100,
	RESONANCE_DEALT = 1.2,
	RESONANCE_TAKEN = 0.6,

	-- Movement while acting
	DEFAULT_MOVE_SLOW = 0.35,
	STUN_WALK_SPEED = 2,

	-- Hit detection
	HIT_TOLERANCE = 1.6, -- half the width of a body, added to every hitbox test

	-- Statuses
	BURN_TICK = 0.5,

	-- Stats and economy
	KILL_CREDIT_WINDOW = 12,
	SHARDS_PER_KILL = 5,
	SHARDS_PER_STREAK_STEP = 2,
	STREAK_ANNOUNCE = { 3, 5, 10 },
	COMBAT_TAG_TIME = 6, -- seconds after a hit during which a fighter cannot switch champions
	SELECT_COOLDOWN = 2,

	-- Remote rate limits (token bucket)
	ACTION_BURST = 12,
	ACTION_REFILL = 10, -- tokens per second
}

return table.freeze(Constants)
