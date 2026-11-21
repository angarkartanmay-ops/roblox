--!strict
-- The Far Shore as data the code needs: zones, spawns, the Elder's grove and the ring-out line.
-- Mirrors design/map.json (farshore.spec checks every value against it), so the server never has
-- to guess where the built map put things. Positions are world studs.

export type Zone = {
	name: string,
	center: { number }, -- x, z
	radius: number,
	rule: "safe" | "nopvp" | "ffa",
}

local FarShore = {}

FarShore.ZONES = {
	{ name = "FerryLanding", center = { 0, 150 }, radius = 40, rule = "safe" },
	{ name = "JizoBeach", center = { -196, 40 }, radius = 34, rule = "nopvp" },
	{ name = "Riverbed", center = { 60, -8 }, radius = 40, rule = "ffa" },
	{ name = "LilyFields", center = { 150, 140 }, radius = 50, rule = "ffa" },
	{ name = "EldersGrove", center = { 0, -170 }, radius = 40, rule = "ffa" },
	{ name = "Barrows", center = { -160, -130 }, radius = 30, rule = "ffa" },
	{ name = "PineBluff", center = { 170, -140 }, radius = 30, rule = "ffa" },
} :: { Zone }

FarShore.SPAWNS = {
	{ 0, 47, 150 },
	{ -16, 47, 146 },
	{ 16, 47, 146 },
	{ -12, 47, 164 },
	{ 12, 47, 164 },
	{ 0, 47, 176 },
}

FarShore.KILL_PLANE = -70
FarShore.RING_OUT_OFFSET = 10
FarShore.RING_OUT_Y = FarShore.KILL_PLANE + FarShore.RING_OUT_OFFSET

-- The map builder raises everything by volume.lift (clear of Studio's y=0 editor grid), so every
-- spec height above becomes `y + LIFT` in the world. `world` does that conversion.
FarShore.LIFT = 8

function FarShore.world(spec: { number }): (number, number, number)
	return spec[1], spec[2] + FarShore.LIFT, spec[3]
end

-- The Elder stands where the greybox ElderTrunkBlock stands (its base on the grove floor).
FarShore.ELDER_ANCHOR = { 0, 52, -215 }
FarShore.GROVE_CENTER = { 0, 52, -190 }
FarShore.GROVE_RADIUS = 60
FarShore.SELECT_LANTERN = { 0, 47.5, 128 }

-- Five training dummies stand on Jizo Beach, one per phase, in a crescent facing the river.
FarShore.DUMMY_CENTER = { -196, 28, 40 }
FarShore.DUMMY_RADIUS = 14

-- Name of the zone containing (x, z), safe and no-PvP zones first.
function FarShore.zoneAt(x: number, z: number): Zone?
	for _, zone in FarShore.ZONES do
		local dx, dz = x - zone.center[1], z - zone.center[2]
		if dx * dx + dz * dz <= zone.radius * zone.radius then
			return zone
		end
	end
	return nil
end

function FarShore.ruleAt(x: number, z: number): "safe" | "nopvp" | "ffa"
	local zone = FarShore.zoneAt(x, z)
	return if zone then zone.rule else "ffa"
end

return FarShore
