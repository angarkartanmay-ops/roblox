--!strict
-- Every effect, projectile, special and kit id the game uses. The client's VfxController implements
-- each move id; fighters.spec checks every move references an id listed here.

local VfxCatalog = {}

VfxCatalog.MOVES = {
	-- Tsuta (Wood)
	"RootSnare",
	"SeedVolley",
	"CanopyGuard",
	"Graft",
	"ThousandRootBloom",
	-- Hibiki (Fire)
	"WarBeat",
	"FireRoll",
	"Kakegoe",
	"ThunderRoll",
	"FestivalOfDrums",
	-- Iwao (Earth)
	"ShikoStomp",
	"BoulderGrip",
	"PurifyingSalt",
	"TachiaiCharge",
	"Dohyo",
	-- Kanemori (Metal)
	"ChainLash",
	"JitteCatch",
	"IronEdict",
	"HuntersChase",
	"EdictOfChains",
	-- Rokumon (Water)
	"Riverpull",
	"PhantomFerry",
	"Mist",
	"TollStrike",
	"RiverReturns",
}

VfxCatalog.PROJECTILES = { "Seed", "Chain" }

-- Moves whose behaviour lives in code rather than in hit/projectile data.
VfxCatalog.SPECIALS = {
	"CanopyGuard",
	"Graft",
	"RootBloom",
	"Kakegoe",
	"BoulderGrip",
	"Tachiai",
	"Dohyo",
	"JitteCatch",
	"HuntersChase",
	"EdictChains",
	"Mist",
	"TollStrike",
	"RiverReturns",
}

-- Mid-move moments the server reports with PhaseFx (server-chosen timing or positions).
VfxCatalog.PHASES = {
	"Reflect", -- Canopy Guard sends a projectile back
	"Lash", -- Graft's vine reaches its target
	"Erupt", -- Thousand-Root Bloom tree rises
	"Tick", -- a damage-over-time pulse (Bloom)
	"Grab", -- Boulder Grip catches
	"Throw", -- Boulder Grip lets go
	"Land", -- a thrown fighter lands (wall flag in the position's Y offset is not used)
	"Slam", -- Tachiai wall or body slam
	"Rise", -- the Dohyo ring rises
	"RingOut", -- a fighter is knocked out of the Dohyo
	"Catch", -- Jitte Catch catches a hit
	"Chase", -- Hunter's Chase arrives
	"Chains", -- Edict of Chains binds
	"Shock", -- Edict of Chains shockwave
	"Toll", -- Toll Strike lands (coins spent)
	"Wave", -- The River Returns floods
	"Drain", -- The River Returns drains
	"Mist", -- Mist of the Crossing settles
	"Beat", -- Hibiki's Rhythm Beat
	"Sprout", -- Tsuta's Sprout burst
	"Coin", -- Rokumon earns a coin
}

VfxCatalog.WEAPONS = { "Wagasa", "TaikoBachi", "StoneBracer", "Jitte", "FerryOar" }
VfxCatalog.KIT = { "BackTaiko", "RopeBelt", "WeightedChain", "Jingasa", "Sugegasa", "CoinString" }

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
VfxCatalog.PHASE_SET = toSet(VfxCatalog.PHASES)
VfxCatalog.WEAPON_SET = toSet(VfxCatalog.WEAPONS)
VfxCatalog.KIT_SET = toSet(VfxCatalog.KIT)

return VfxCatalog
