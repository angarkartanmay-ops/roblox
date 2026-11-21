--!strict
-- Ki: earned by landing and taking hits (shaped by the Five Phases relation), spent whole on an
-- ultimate or a little at a time on Mend, the channelled heal. Purified fighters gain no Ki and
-- cannot Mend. Players see their Ki on the `Ki` player attribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require("../Lib/Net")
local Registry = require("./Registry")

type Entity = Registry.Entity

local KiService = {}

local function publish(entity: Entity)
	Registry.publishPlayer(entity, "Ki", math.floor(entity.ki))
end

function KiService.set(entity: Entity, value: number)
	entity.ki = math.clamp(value, 0, Constants.KI_MAX)
	publish(entity)
end

function KiService.gain(entity: Entity?, amount: number)
	if entity == nil or entity.kind ~= "Player" or amount <= 0 then
		return
	end
	if entity.purifiedUntil > Registry.now() then
		return
	end
	entity.ki = CombatMath.addKi(entity.ki, amount)
	publish(entity)
end

-- Ki from one landed hit of `damage` with the attacker->target `relation`.
function KiService.onHitLanded(attacker: Entity?, victim: Entity, damage: number, relation: Types.Relation)
	local attackerGain, targetGain = CombatMath.kiForHit(damage, relation)
	if attacker and attacker ~= victim then
		KiService.gain(attacker, attackerGain)
	end
	KiService.gain(victim, targetGain)
end

function KiService.isFull(entity: Entity): boolean
	return entity.ki >= Constants.KI_MAX - 0.01
end

-- Spend a full meter on an ultimate. False when the meter is not full.
function KiService.spendUltimate(entity: Entity): boolean
	if not KiService.isFull(entity) then
		return false
	end
	KiService.set(entity, 0)
	return true
end

function KiService.stopMend(entity: Entity)
	entity.mending = false
end

local function canChannel(entity: Entity, now: number): boolean
	return Registry.isAlive(entity)
		and CombatMath.canMend(now, entity.lastHitTakenAt, entity.purifiedUntil)
		and entity.stunUntil <= now
		and entity.guardBrokenUntil <= now
		and entity.grabbedBy == nil
		and entity.lockUntil <= now
		and not entity.blocking
		and entity.ki > 0
		and entity.humanoid.Health < entity.humanoid.MaxHealth
end

local function onMend(player: Player, wants: unknown)
	if not Net.allow(player, 0.5) or type(wants) ~= "boolean" then
		return
	end
	local entity = Registry.forPlayer(player)
	if not entity then
		return
	end
	if wants then
		local now = Registry.now()
		if canChannel(entity, now) then
			entity.mending = true
		elseif now - entity.lastHitTakenAt < Constants.MEND_LOCKOUT then
			Net.Notify:FireClient(player, "toast", { text = "Too soon after a hit to Mend." })
		elseif entity.purifiedUntil > now then
			Net.Notify:FireClient(player, "toast", { text = "Purified: you cannot Mend." })
		end
	else
		entity.mending = false
	end
end

local function step(dt: number)
	local now = Registry.now()
	for _, entity in Registry.players() do
		if not entity.mending then
			continue
		end
		if not canChannel(entity, now) then
			entity.mending = false
			continue
		end
		local missing = entity.humanoid.MaxHealth - entity.humanoid.Health
		local bonus = if entity.sapUntil > now then Constants.ELDER_SAP_MEND else 0
		local spend, heal = CombatMath.mendStep(entity.ki, missing, dt, bonus)
		if spend <= 0 then
			entity.mending = false
			continue
		end
		entity.ki -= spend
		entity.humanoid.Health = math.min(entity.humanoid.MaxHealth, entity.humanoid.Health + heal)
		publish(entity)
	end
end

function KiService.init(_self: any)
	Registry.onAdded(function(entity)
		if entity.kind == "Player" then
			publish(entity)
		end
	end)
end

function KiService.start(_self: any)
	Net.Mend.OnServerEvent:Connect(onMend)
	RunService.Heartbeat:Connect(step)
end

return KiService
