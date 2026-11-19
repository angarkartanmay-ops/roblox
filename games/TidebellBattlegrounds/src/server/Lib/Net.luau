--!strict
-- Server-side remote references, argument validation and per-player rate limiting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local function remote(name: string): RemoteEvent
	local found = remotesFolder:FindFirstChild(name)
	assert(found and found:IsA("RemoteEvent"), `missing RemoteEvent {name}`)
	return found
end

local Net = {
	-- client -> server
	Action = remote("Action"),
	SetBlock = remote("SetBlock"),
	Dash = remote("Dash"),
	SelectFighter = remote("SelectFighter"),
	-- server -> clients
	MoveFx = remote("MoveFx"),
	PhaseFx = remote("PhaseFx"),
	HitFx = remote("HitFx"),
	ProjectileFx = remote("ProjectileFx"),
	BossFx = remote("BossFx"),
	Impulse = remote("Impulse"),
	Teleport = remote("Teleport"),
	Notify = remote("Notify"),
}

-- HitFx flags (bit field)
Net.FLAG_BLOCKED = 1
Net.FLAG_PARRIED = 2
Net.FLAG_GUARD_BREAK = 4
Net.FLAG_ADVANTAGE = 8
Net.FLAG_DISADVANTAGE = 16
Net.FLAG_ECHO = 32
Net.FLAG_COUNTER = 64
Net.FLAG_BURN = 128

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: Bucket } = {}

-- Token bucket: ACTION_BURST requests at once, refilled at ACTION_REFILL per second.
function Net.allow(player: Player, cost: number?): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		bucket = { tokens = Constants.ACTION_BURST, last = now }
		buckets[player] = bucket
	end
	bucket.tokens = math.min(Constants.ACTION_BURST, bucket.tokens + (now - bucket.last) * Constants.ACTION_REFILL)
	bucket.last = now
	local price = cost or 1
	if bucket.tokens < price then
		return false
	end
	bucket.tokens -= price
	return true
end

local function finite(value: number): boolean
	return value == value and math.abs(value) < 1e6
end

-- A finite, non-zero Vector3 from the network, normalised; nil when malformed.
function Net.unitVector(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local vector = value :: Vector3
	if not (finite(vector.X) and finite(vector.Y) and finite(vector.Z)) then
		return nil
	end
	if vector.Magnitude < 0.01 then
		return nil
	end
	return vector.Unit
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return Net
