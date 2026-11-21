--!strict
-- Server entry point: require every service, run each `init` (sync, no yielding), then each `start`.
-- Also exposes a server-only `Debug` BindableFunction (ServerScriptService is never replicated, so
-- clients cannot reach it) that playtests use to drive the game from the Studio MCP.

type Service = {
	init: ((self: Service) -> ())?,
	start: ((self: Service) -> ())?,
}

local servicesFolder = script:WaitForChild("Services")
local services: { [string]: Service } = {}

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		services[module.Name] = (require :: any)(module)
	end
end

-- Deterministic order: the map must exist before anything spawns into it, and combat before the
-- services that hook into it.
local ORDER = {
	"Registry",
	"MapService",
	"StatusService",
	"KiService",
	"ProjectileService",
	"CombatService",
	"ThirstService",
	"StatsService",
	"FighterService",
	"DummyService",
	"ElderService",
}

local ordered: { string } = {}
local seen: { [string]: boolean } = {}
for _, name in ORDER do
	if services[name] then
		table.insert(ordered, name)
		seen[name] = true
	end
end
for name in services do
	if not seen[name] then
		table.insert(ordered, name)
	end
end

for _, name in ordered do
	local service = services[name]
	local init = service.init
	if init then
		debug.setmemorycategory(name)
		init(service)
		debug.resetmemorycategory()
	end
end

for _, name in ordered do
	local service = services[name]
	local start = service.start
	if start then
		task.spawn(function()
			debug.setmemorycategory(name)
			start(service)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Debug hooks (server only)

local Players = game:GetService("Players")

local Registry = services.Registry :: any
local CombatService = services.CombatService :: any
local KiService = services.KiService :: any
local ThirstService = services.ThirstService :: any

local function entityOf(name: unknown): any
	if type(name) ~= "string" then
		local first = Players:GetPlayers()[1]
		return if first then Registry.forPlayer(first) else nil
	end
	local player = Players:FindFirstChild(name)
	if player and player:IsA("Player") then
		return Registry.forPlayer(player)
	end
	return nil
end

local function summary(entity: any): { [string]: any }
	return {
		name = entity.model.Name,
		kind = entity.kind,
		fighter = entity.fighterId,
		phase = entity.phase,
		health = math.floor(entity.humanoid.Health * 10) / 10,
		maxHealth = entity.humanoid.MaxHealth,
		ki = math.floor(entity.ki * 10) / 10,
		zone = entity.zone,
		rule = entity.rule,
		position = entity.root.Position,
		coins = entity.coins,
		sprouts = entity.sproutStacks,
	}
end

local debugFunction = Instance.new("BindableFunction")
debugFunction.Name = "Debug"
debugFunction.OnInvoke = function(command: string, a: any, b: any, c: any): any
	if command == "entities" then
		local list = {}
		for _, entity in Registry.all() do
			table.insert(list, summary(entity))
		end
		return list
	elseif command == "entity" then
		local entity = entityOf(a)
		return if entity then summary(entity) else nil
	elseif command == "cast" then
		-- cast(playerName?, slot, aimVector?)
		local entity = entityOf(a)
		if not entity then
			return false
		end
		return CombatService.tryMove(entity, b, if typeof(c) == "Vector3" then c else nil)
	elseif command == "ki" then
		local entity = entityOf(a)
		if entity then
			KiService.set(entity, if type(b) == "number" then b else 100)
			return entity.ki
		end
		return nil
	elseif command == "cooldowns" then
		local entity = entityOf(a)
		if entity then
			table.clear(entity.cooldowns)
			entity.m1ReadyAt = 0
			entity.dashReadyAt = 0
			return true
		end
		return false
	elseif command == "teleport" then
		local entity = entityOf(a)
		if entity and typeof(b) == "Vector3" then
			CombatService.teleport(entity, CFrame.new(b))
			return true
		end
		return false
	elseif command == "wake" then
		ThirstService.forceWake()
		return true
	elseif command == "thirst" then
		ThirstService.add(if type(a) == "number" then a else 100)
		return ThirstService.value()
	end
	return `unknown command {command}`
end
debugFunction.Parent = script
