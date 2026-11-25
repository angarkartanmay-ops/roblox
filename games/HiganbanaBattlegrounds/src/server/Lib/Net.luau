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
	Mend = remote("Mend"),
	SelectFighter = remote("SelectFighter"),
	-- server -> clients
	MoveFx = remote("MoveFx"),
	PhaseFx = remote("PhaseFx"),
	HitFx = remote("HitFx"),
	ProjectileFx = remote("ProjectileFx"),
	ElderFx = remote("ElderFx"),
	Impulse = remote("Impulse"),
	Teleport = remote("Teleport"),
	Notify = remote("Notify"),
	WildsFx = remote("WildsFx"),
}

-- HitFx flags (bit field, shared with the client through Constants.FLAG)
local FLAG = Constants.FLAG
Net.FLAG_BLOCKED = FLAG.BLOCKED
Net.FLAG_PARRIED = FLAG.PARRIED
Net.FLAG_GUARD_BREAK = FLAG.GUARD_BREAK
Net.FLAG_OVERCOME = FLAG.OVERCOME
Net.FLAG_RESISTED = FLAG.RESISTED
Net.FLAG_FEEDING = FLAG.FEEDING
Net.FLAG_DRAWING = FLAG.DRAWING
Net.FLAG_BURN = FLAG.BURN
Net.FLAG_BEAT = FLAG.BEAT
Net.FLAG_WOUND = FLAG.WOUND
Net.FLAG_HEAL = FLAG.HEAL
Net.FLAG_REFLECT = FLAG.REFLECT
Net.FLAG_CATCH = FLAG.CATCH
Net.FLAG_RING_OUT = FLAG.RING_OUT
Net.FLAG_SPROUT = FLAG.SPROUT

local RELATION_FLAGS: { [string]: number } = {
	Overcome = FLAG.OVERCOME,
	Resisted = FLAG.RESISTED,
	Feeding = FLAG.FEEDING,
	Drawing = FLAG.DRAWING,
}

function Net.relationFlag(relation: string): number
	return RELATION_FLAGS[relation] or 0
end

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

-- A finite Vector3 from the network (a world point), or nil.
function Net.point(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local vector = value :: Vector3
	if not (finite(vector.X) and finite(vector.Y) and finite(vector.Z)) then
		return nil
	end
	return vector
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return Net
