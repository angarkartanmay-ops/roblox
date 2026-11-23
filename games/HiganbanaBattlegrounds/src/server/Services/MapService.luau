--!strict
-- The Far Shore on the server: finds the map the roblox-map stage built into the place
-- (Workspace.FarShore), answers zone questions from the shared FarShore data, and wires the
-- Ferryman's Lantern that opens Phase Select. When the place has no built map (a bare
-- `rojo build`), it lays a flat fallback shore so the loop can still be played.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FarShore = require(ReplicatedStorage.Shared.FarShore)
local Net = require("../Lib/Net")

local MapService = {}

MapService.MAP_NAME = "FarShore"
MapService.model = nil :: Model?
MapService.fallback = false
MapService.trunkBlock = nil :: BasePart?
-- The Elder asleep in its grove (map dressing: the generated trunk and crown), if the map has it.
MapService.dormantElder = nil :: Model?

local lanternListeners: { (Player) -> () } = {}

function MapService.world(spec: { number }): Vector3
	local x, y, z = FarShore.world(spec)
	return Vector3.new(x, y, z)
end

function MapService.zoneAt(position: Vector3): FarShore.Zone?
	return FarShore.zoneAt(position.X, position.Z)
end

function MapService.ruleAt(position: Vector3): "safe" | "nopvp" | "ffa"
	return FarShore.ruleAt(position.X, position.Z)
end

function MapService.isSafe(position: Vector3): boolean
	return MapService.ruleAt(position) == "safe"
end

-- Below this world height a body has fallen into the mist: a ring-out.
function MapService.ringOutY(): number
	return FarShore.RING_OUT_Y + FarShore.LIFT
end

-- Where the Elder stands (the base of its trunk on the grove floor), in world space.
function MapService.elderAnchor(): Vector3
	local trunk = MapService.trunkBlock
	if trunk then
		return trunk.Position - Vector3.new(0, trunk.Size.Y / 2, 0)
	end
	return MapService.world(FarShore.ELDER_ANCHOR)
end

function MapService.groveCenter(): Vector3
	return MapService.world(FarShore.GROVE_CENTER)
end

function MapService.dummyCenter(): Vector3
	return MapService.world(FarShore.DUMMY_CENTER)
end

-- Spawn frames facing the river (the landing looks south-to-north across the bridge).
function MapService.spawnFrames(): { CFrame }
	local frames = {}
	for _, spawn in FarShore.SPAWNS do
		local position = MapService.world(spawn) + Vector3.new(0, 3, 0)
		table.insert(frames, CFrame.lookAt(position, position + Vector3.new(0, 0, -1)))
	end
	return frames
end

function MapService.onLantern(listener: (Player) -> ())
	table.insert(lanternListeners, listener)
end

-- The map builder groups landmarks into folders that share the part's name
-- (Landmarks/SelectLantern/SelectLantern), so look for the PART, not the first match.
local function find(name: string): Instance?
	local model = MapService.model
	if not model then
		return nil
	end
	for _, descendant in model:GetDescendants() do
		if descendant.Name == name and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function fallbackPart(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A flat shore at the landing's height with the lantern, the beach and a stand-in trunk, so the
-- game is playable from a bare place. The real map replaces all of it.
local function buildFallback(): Model
	local model = Instance.new("Model")
	model.Name = MapService.MAP_NAME
	local groundY = FarShore.SPAWNS[1][2] + FarShore.LIFT
	fallbackPart({
		Name = "FallbackShore",
		Size = Vector3.new(520, 4, 520),
		CFrame = CFrame.new(0, groundY - 2, 0),
		Material = Enum.Material.Limestone,
		Color = Color3.fromRGB(196, 188, 170),
	}, model)
	local lantern = MapService.world(FarShore.SELECT_LANTERN)
	fallbackPart({
		Name = "SelectLantern",
		Size = Vector3.new(3, 7, 3),
		CFrame = CFrame.new(lantern.X, groundY + 3.5, lantern.Z),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(201, 194, 178),
	}, model)
	local anchor = MapService.world(FarShore.ELDER_ANCHOR)
	fallbackPart({
		Name = "ElderTrunkBlock",
		Size = Vector3.new(24, 90, 24),
		CFrame = CFrame.new(anchor.X, groundY + 45, anchor.Z),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(92, 38, 34),
	}, model)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = model
	for index, frame in MapService.spawnFrames() do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = `Spawn{index}`
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(frame.Position.X, groundY + 0.5, frame.Position.Z)
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = spawns
	end
	model.Parent = Workspace
	return model
end

local function wireLantern()
	local found = find("SelectLantern")
	if not found or not found:IsA("BasePart") then
		warn("[Map] no SelectLantern part; Phase Select opens from the T key and the death recap only")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PhaseSelectPrompt"
	prompt.ActionText = "Choose your phase"
	prompt.ObjectText = "Ferryman's Lantern"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = found
	prompt.Triggered:Connect(function(player)
		Net.Notify:FireClient(player, "openSelect", {})
		for _, listener in lanternListeners do
			task.spawn(listener, player)
		end
	end)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 110)
	light.Range = 18
	light.Brightness = 1.6
	light.Parent = found
end

function MapService.init(_self: any)
	local existing = Workspace:FindFirstChild(MapService.MAP_NAME)
	if existing and existing:IsA("Model") then
		MapService.model = existing
	else
		warn("[Map] Workspace.FarShore not found: building the flat fallback shore (install the map for the real one)")
		MapService.model = buildFallback()
		MapService.fallback = true
	end
	local trunk = find("ElderTrunkBlock")
	if trunk and trunk:IsA("BasePart") then
		MapService.trunkBlock = trunk
	end
	local model = MapService.model
	local dormant = if model then model:FindFirstChild("DormantElder", true) else nil
	if dormant and dormant:IsA("Model") then
		MapService.dormantElder = dormant
	end
	-- The kill plane the map builder lays is only a marker; StatusService rings out below it.
	for _, plane in CollectionService:GetTagged("KillPlane") do
		if plane:IsA("BasePart") then
			plane.CanTouch = false
			plane.CanQuery = false
		end
	end
	-- Only the landing's spawns are used, so a template SpawnLocation never sends anyone elsewhere.
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(MapService.model :: Model) then
			descendant.Enabled = false
		end
	end
end

function MapService.start(_self: any)
	wireLantern()
end

return MapService
