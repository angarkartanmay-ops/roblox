--!strict
-- Every tunable in design/game.json `config` lives in src/shared/Constants with the same value.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Harness = require("./harness")
local Constants = require("../src/shared/Constants")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local contract = serde.decode("json", fs.readFile("design/game.json"))

local MAP: { [string]: string } = {
	MaxPlayersPerServer = "MAX_PLAYERS",
	RespawnSeconds = "RESPAWN_SECONDS",
	LandingSafeRadius = "LANDING_SAFE_RADIUS",
	PhaseSwitchOutOfCombatSeconds = "PHASE_SWITCH_OOC",
	RelationOvercomeDamage = "OVERCOME_DAMAGE",
	RelationOvercomeGuard = "OVERCOME_GUARD",
	RelationResistedDamage = "RESISTED_DAMAGE",
	RelationFeedingDamage = "FEEDING_DAMAGE",
	RelationFeedingKiToTarget = "FEEDING_KI_TO_TARGET",
	RelationDrawingKiBonus = "DRAWING_KI_BONUS",
	KiMax = "KI_MAX",
	KiPerDamageDealt = "KI_PER_DAMAGE_DEALT",
	KiPerDamageTaken = "KI_PER_DAMAGE_TAKEN",
	MendKiPerSecond = "MEND_KI_PER_SECOND",
	MendHealthPerKi = "MEND_HEALTH_PER_KI",
	MendLockoutAfterHitSeconds = "MEND_LOCKOUT",
	MendMoveSpeedMultiplier = "MEND_SPEED",
	M1ChainHits = "COMBO_HITS",
	M1ResetSeconds = "COMBO_RESET",
	M1FinisherLockSeconds = "FINISHER_LOCK",
	GuardMax = "GUARD_MAX",
	BlockAbilityDamageTaken = "BLOCK_ABILITY_FACTOR",
	GuardBreakStunSeconds = "GUARD_BREAK_STUN",
	ParryWindowSeconds = "PARRY_WINDOW",
	ParryStunSeconds = "PARRY_STUN",
	DashCooldownSeconds = "DASH_COOLDOWN",
	KillCreditWindowSeconds = "KILL_CREDIT_WINDOW",
	PetalsPerKill = "PETALS_PER_KILL",
	PetalsPerStreakStepAbove2 = "PETALS_PER_STREAK_STEP",
	StreakAnnounceAt = "STREAK_ANNOUNCE",
	ThirstBase = "THIRST_BASE",
	ThirstPerPlayer = "THIRST_PER_PLAYER",
	ThirstFirstAwakeMinSeconds = "THIRST_FIRST_AWAKE",
	ThirstCooldownAfterFallSeconds = "THIRST_COOLDOWN_AFTER_FALL",
	ElderHealthBase = "ELDER_HEALTH_BASE",
	ElderHealthPerPlayer = "ELDER_HEALTH_PER_PLAYER",
	ElderPhaseSeconds = "ELDER_PHASE_SECONDS",
	ElderPhaseSecondsEnraged = "ELDER_PHASE_SECONDS_ENRAGED",
	ElderPhaseWarningSeconds = "ELDER_PHASE_WARNING",
	ElderRegenPercentPerSecond = "ELDER_REGEN_PERCENT",
	ElderWoundPauseSeconds = "ELDER_WOUND_PAUSE",
	ElderOvercomeBonus = "ELDER_OVERCOME_BONUS",
	ElderFeedingHealFraction = "ELDER_FEEDING_HEAL",
	ElderEnrageAtFraction = "ELDER_ENRAGE_AT",
	ElderTimeoutSeconds = "ELDER_TIMEOUT",
	ElderBranchHealth = "ELDER_BRANCH_HEALTH",
	ElderGrabDrainPerSecond = "ELDER_GRAB_DRAIN",
	ElderGrabSeconds = "ELDER_GRAB_SECONDS",
	SapSproutCount = "SAP_SPROUT_COUNT",
	SapSproutHealSeconds = "SAP_SPROUT_HEAL_SECONDS",
	SapSproutHealFraction = "SAP_SPROUT_HEAL_FRACTION",
	ElderRewardMinContribution = "ELDER_REWARD_MIN_SHARE",
	ElderRewardPetals = "ELDER_REWARD_PETALS",
	ElderSapSeconds = "ELDER_SAP_SECONDS",
	ElderSapDamageBonus = "ELDER_SAP_DAMAGE",
	ElderSapMendBonus = "ELDER_SAP_MEND",
	HibikiBeatEveryHits = "HIBIKI_BEAT_EVERY",
	HibikiBeatDamageBonus = "HIBIKI_BEAT_BONUS",
	RokumonHitsPerCoin = "ROKUMON_HITS_PER_COIN",
	RokumonMaxCoins = "ROKUMON_MAX_COINS",
	RokumonTollDamagePerCoin = "ROKUMON_TOLL_PER_COIN",
	IwaoKnockbackTakenMultiplier = "IWAO_KNOCKBACK_TAKEN",
	IwaoDohyoSeconds = "IWAO_DOHYO_SECONDS",
	IwaoDohyoRadius = "IWAO_DOHYO_RADIUS",
	IwaoRingOutDamage = "IWAO_RING_OUT_DAMAGE",
	KanemoriParrySilenceSeconds = "KANEMORI_PARRY_SILENCE",
	TsutaSproutBurstStacks = "TSUTA_SPROUT_BURST",
	CombatDebugAttribute = "DEBUG_ATTRIBUTE",
}

local function same(a: any, b: any): boolean
	if type(a) == "table" and type(b) == "table" then
		if #a ~= #b then
			return false
		end
		for index, value in a do
			if b[index] ~= value then
				return false
			end
		end
		return true
	end
	return a == b
end

describe("Constants match the contract", function()
	for key, value in contract.config do
		it(key, function()
			local name = MAP[key]
			expect(name ~= nil, `{key} is mapped to a constant`):toBeTruthy()
			local actual = (Constants :: any)[name :: string]
			expect(actual ~= nil, `Constants.{name} exists`):toBeTruthy()
			expect(same(value, actual), `{key}: game.json {value} vs Constants.{name} {actual}`):toBeTruthy()
		end)
	end
end)
