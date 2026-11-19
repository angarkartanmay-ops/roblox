--!strict
-- Client-side references to the remotes declared in the place file (ReplicatedStorage.Remotes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function remote(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return {
	Action = remote("Action"),
	SetBlock = remote("SetBlock"),
	Dash = remote("Dash"),
	SelectFighter = remote("SelectFighter"),
	MoveFx = remote("MoveFx"),
	PhaseFx = remote("PhaseFx"),
	HitFx = remote("HitFx"),
	ProjectileFx = remote("ProjectileFx"),
	BossFx = remote("BossFx"),
	Impulse = remote("Impulse"),
	Teleport = remote("Teleport"),
	Notify = remote("Notify"),

	-- HitFx flags (mirror of the server's Net module)
	FLAG_BLOCKED = 1,
	FLAG_PARRIED = 2,
	FLAG_GUARD_BREAK = 4,
	FLAG_ADVANTAGE = 8,
	FLAG_DISADVANTAGE = 16,
	FLAG_ECHO = 32,
	FLAG_COUNTER = 64,
	FLAG_BURN = 128,
}
