--!strict
-- Every visual-effect id the game uses. The client's VfxController must implement each one;
-- tests check that every move references an id listed here.

local VfxCatalog = {}

VfxCatalog.MOVES = {
	-- Stonebreaker
	"QuakeStomp",
	"BoulderHeave",
	"GraniteHide",
	"RocklineRush",
	"Mountainfall",
	-- Tide Dancer
	"CrescentWave",
	"Undertow",
	"MistStep",
	"WhirlpoolSpin",
	"DrowningTide",
	-- Lantern Fox
	"Foxfire",
	"FanBlaze",
	"EmberHop",
	"LanternSnare",
	"HundredLanterns",
	-- Gale Courier
	"CycloneKick",
	"SickleBoomerang",
	"Updraft",
	"Slipstream",
	"ThousandGusts",
	-- Bell Monk
	"EchoStrike",
	"Hush",
	"NullStep",
	"ResonantWard",
	"TollOfTheDeep",
}

VfxCatalog.PROJECTILES = { "Boulder", "Crescent", "Wave", "Foxfire", "Lantern", "Sickle" }

-- Moves whose behaviour lives in code rather than in hit/projectile data.
VfxCatalog.SPECIALS = { "GraniteHide", "LandingSlam", "HundredLanterns", "ThousandGusts", "NullStep", "ResonantWard" }

-- Mid-move events the server reports with PhaseFx (variable timing or server-chosen positions).
VfxCatalog.PHASES = {
	"Slam", -- LandingSlam impact (position)
	"Echo", -- Echo Strike second hit (position)
	"Blink", -- Null Step / Thousand Gusts teleport (position)
	"Counter", -- Resonant Ward counter (position)
	"Drop", -- Hundred Lanterns drop (position)
	"Final", -- Hundred Lanterns / Thousand Gusts finisher (position)
	"Explode", -- projectile explosion (position)
}

VfxCatalog.WEAPONS = { "StoneMaul", "Naginata", "WarFans", "ChainSickles", "RingedStaff" }

local function toSet(list: { string }): { [string]: boolean }
	local set = {}
	for _, id in list do
		set[id] = true
	end
	return set
end

VfxCatalog.MOVE_SET = toSet(VfxCatalog.MOVES)
VfxCatalog.PROJECTILE_SET = toSet(VfxCatalog.PROJECTILES)
VfxCatalog.SPECIAL_SET = toSet(VfxCatalog.SPECIALS)
VfxCatalog.WEAPON_SET = toSet(VfxCatalog.WEAPONS)

return VfxCatalog
