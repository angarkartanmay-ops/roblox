--!strict
-- Server-side hit queries against entity roots (server positions; nothing reported by clients).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Registry = require("../Services/Registry")

type Entity = Registry.Entity

local Hitbox = {}

local function tolerance(entity: Entity): number
	return Constants.HIT_TOLERANCE + entity.hitRadius
end

-- Entities whose root lies inside the oriented box (padded by body size).
function Hitbox.box(cframe: CFrame, size: Vector3, exclude: Entity?): { Entity }
	local found = {}
	for _, entity in Registry.all() do
		if entity ~= exclude then
			local localPosition = cframe:PointToObjectSpace(entity.root.Position)
			if
				CombatMath.insideBox(
					localPosition.X,
					localPosition.Y,
					localPosition.Z,
					size.X,
					size.Y,
					size.Z,
					tolerance(entity)
				)
			then
				table.insert(found, entity)
			end
		end
	end
	return found
end

function Hitbox.sphere(center: Vector3, radius: number, exclude: Entity?): { Entity }
	local found = {}
	for _, entity in Registry.all() do
		if entity ~= exclude then
			local offset = entity.root.Position - center
			if CombatMath.insideSphere(offset.X, offset.Y, offset.Z, radius, tolerance(entity)) then
				table.insert(found, entity)
			end
		end
	end
	return found
end

-- Entities within `radius` of the segment from `a` to `b`.
function Hitbox.segment(a: Vector3, b: Vector3, radius: number, exclude: Entity?): { Entity }
	local found = {}
	for _, entity in Registry.all() do
		if entity ~= exclude then
			local p = entity.root.Position
			local distance = CombatMath.segmentDistance(p.X, p.Y, p.Z, a.X, a.Y, a.Z, b.X, b.Y, b.Z)
			if distance <= radius + tolerance(entity) then
				table.insert(found, entity)
			end
		end
	end
	return found
end

-- The closest living enemy within `range`, preferring targets in front of `facing`.
-- `minDot` rejects targets outside the cone (-1 accepts any direction).
function Hitbox.nearestEnemy(origin: Vector3, facing: Vector3, range: number, minDot: number, exclude: Entity?): Entity?
	local best: Entity? = nil
	local bestScore = math.huge
	for _, entity in Registry.all() do
		if entity ~= exclude and not entity.safe then
			local offset = entity.root.Position - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			if distance <= range then
				local dot = if distance > 0.01 then flat.Unit:Dot(facing) else 1
				if dot >= minDot then
					local score = distance - dot * 12
					if score < bestScore then
						best = entity
						bestScore = score
					end
				end
			end
		end
	end
	return best
end

return Hitbox
