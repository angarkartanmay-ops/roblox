--!strict
-- Server entry point: require every service, run each `init` (sync, no yielding), then each `start`.

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

-- Deterministic order: the map must exist before anything spawns into it.
local ORDER = {
	"Registry",
	"MapService",
	"StatusService",
	"ProjectileService",
	"CombatService",
	"StatsService",
	"FighterService",
	"DummyService",
	"BossService",
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
	if service.init then
		debug.setmemorycategory(name)
		service:init()
		debug.resetmemorycategory()
	end
end

for _, name in ordered do
	local service = services[name]
	if service.start then
		task.spawn(function()
			debug.setmemorycategory(name)
			service:start()
		end)
	end
end
