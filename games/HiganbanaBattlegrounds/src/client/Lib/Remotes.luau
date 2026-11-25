--!strict
-- Client-side references to the remotes declared in default.project.json (ReplicatedStorage.Remotes).
-- The HitFx flag bits come from Constants.FLAG, the same table the server's Net module reads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function remote(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

local FLAG = Constants.FLAG

return {
	-- client -> server
	Action = remote("Action"),
	SetBlock = remote("SetBlock"),
	Dash = remote("Dash"),
	Mend = remote("Mend"),
	SelectFighter = remote("SelectFighter"),

	-- server -> client
	MoveFx = remote("MoveFx"),
	PhaseFx = remote("PhaseFx"),
	HitFx = remote("HitFx"),
	ProjectileFx = remote("ProjectileFx"),
	ElderFx = remote("ElderFx"),
	Impulse = remote("Impulse"),
	Teleport = remote("Teleport"),
	Notify = remote("Notify"),
	WildsFx = remote("WildsFx"),

	FLAG_BLOCKED = FLAG.BLOCKED,
	FLAG_PARRIED = FLAG.PARRIED,
	FLAG_GUARD_BREAK = FLAG.GUARD_BREAK,
	FLAG_OVERCOME = FLAG.OVERCOME,
	FLAG_RESISTED = FLAG.RESISTED,
	FLAG_FEEDING = FLAG.FEEDING,
	FLAG_DRAWING = FLAG.DRAWING,
	FLAG_BURN = FLAG.BURN,
	FLAG_BEAT = FLAG.BEAT,
	FLAG_WOUND = FLAG.WOUND,
	FLAG_HEAL = FLAG.HEAL,
	FLAG_REFLECT = FLAG.REFLECT,
	FLAG_CATCH = FLAG.CATCH,
	FLAG_RING_OUT = FLAG.RING_OUT,
	FLAG_SPROUT = FLAG.SPROUT,
}
