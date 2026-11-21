--!strict
-- Client entry point: wait for the initial snapshot, then init and start every controller.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

type Controller = {
	init: ((self: Controller) -> ())?,
	start: ((self: Controller) -> ())?,
}

local controllersFolder = script:WaitForChild("Controllers")
local controllers: { [string]: Controller } = {}
for _, module in controllersFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		controllers[module.Name] = (require :: any)(module)
	end
end

local ORDER = {
	"SoundController",
	"CameraController",
	"AnimationController",
	"VfxController",
	"SelectController",
	"InputController",
	"HudController",
	"NameplateController",
}

local ordered: { string } = {}
local seen: { [string]: boolean } = {}
for _, name in ORDER do
	if controllers[name] then
		table.insert(ordered, name)
		seen[name] = true
	end
end
for name in controllers do
	if not seen[name] then
		table.insert(ordered, name)
	end
end

for _, name in ordered do
	local controller = controllers[name]
	local init = controller.init
	if init then
		init(controller)
	end
end
for _, name in ordered do
	local controller = controllers[name]
	local start = controller.start
	if start then
		task.spawn(start, controller)
	end
end
