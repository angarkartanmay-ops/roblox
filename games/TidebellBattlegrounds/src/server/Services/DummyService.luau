--!strict
-- Training dummies on the Training Grounds: a striker, a guard dummy that always blocks
-- (teaches facing and guard breaks) and a heavy dummy. Each wears an element so players can
-- practise the wheel. They heal and return home after a few quiet seconds and respawn when beaten.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Elements = require(ReplicatedStorage.Shared.Elements)
local Types = require(ReplicatedStorage.Shared.Types)
local MapService = require("./MapService")
local Registry = require("./Registry")

type Entity = Registry.Entity

type DummySpec = {
	name: string,
	element: Types.ElementId,
	health: number,
	guard: boolean,
}

local DUMMIES: { DummySpec } = {
	{ name = "Striker Dummy", element = "Fire", health = 250, guard = false },
	{ name = "Guard Dummy", element = "Earth", health = 250, guard = true },
	{ name = "Heavy Dummy", element = "Void", health = 500, guard = false },
}

local DummyService = {}

local folder: Folder
local slots: { { entity: Entity?, home: CFrame } } = {}

local function color3(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

-- Plain R6 rig used only if the avatar service is unavailable.
local function buildBlockRig(color: Color3): Model
	local model = Instance.new("Model")
	local function block(name: string, size: Vector3, cframe: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
	root.Transparency = 1
	local torso = block("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
	local head = block("Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0))
	local rightArm = block("Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0))
	local leftArm = block("Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0))
	local rightLeg = block("Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0))
	local leftLeg = block("Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0))

	local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
		local joint = Instance.new("Motor6D")
		joint.Name = name
		joint.Part0 = part0
		joint.Part1 = part1
		joint.C0 = c0
		joint.C1 = c1
		joint.Parent = part0
	end
	local rootRotation = CFrame.Angles(math.rad(-90), 0, math.rad(180))
	motor("RootJoint", root, torso, rootRotation, rootRotation)
	motor("Neck", torso, head, CFrame.new(0, 1, 0) * rootRotation, CFrame.new(0, -0.5, 0) * rootRotation)
	local right90 = CFrame.Angles(0, math.rad(90), 0)
	local left90 = CFrame.Angles(0, math.rad(-90), 0)
	motor("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0) * right90, CFrame.new(-0.5, 0.5, 0) * right90)
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0) * left90, CFrame.new(0.5, 0.5, 0) * left90)
	motor("Right Hip", torso, rightLeg, CFrame.new(1, -1, 0) * right90, CFrame.new(0.5, 1, 0) * right90)
	motor("Left Hip", torso, leftLeg, CFrame.new(-1, -1, 0) * left90, CFrame.new(-0.5, 1, 0) * left90)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildRig(color: Color3): Model
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = color
	description.TorsoColor = color
	description.LeftArmColor = color
	description.RightArmColor = color
	description.LeftLegColor = color
	description.RightLegColor = color
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	if ok and model then
		return model
	end
	warn("[Dummies] avatar rig unavailable, using block dummies:", model)
	return buildBlockRig(color)
end

local function addNameplate(model: Model, root: BasePart, spec: DummySpec, humanoid: Humanoid)
	local info = Elements.INFO[spec.element]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(180, 54)
	billboard.StudsOffset = Vector3.new(0, 4.4, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Adornee = root
	billboard.Parent = model

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Font = Enum.Font.BuilderSansExtraBold
	title.TextSize = 20
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.4
	title.Text = `{info.glyph}  {spec.name}`
	title.Parent = billboard

	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(20, 30)
	bar.Size = UDim2.new(1, -40, 0, 10)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	bar.BorderSizePixel = 0
	bar.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color3(info.color)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	humanoid.HealthChanged:Connect(function(health)
		fill.Size = UDim2.fromScale(math.clamp(health / math.max(humanoid.MaxHealth, 1), 0, 1), 1)
	end)
end

local spawnDummy: (number) -> ()

spawnDummy = function(index: number)
	local spec = DUMMIES[index]
	local slot = slots[index]
	local info = Elements.INFO[spec.element]
	local tint = color3(info.color):Lerp(Color3.fromRGB(210, 190, 160), 0.55)
	local model = buildRig(tint)
	model.Name = spec.name

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return
	end
	humanoid.DisplayName = spec.name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = spec.health
	humanoid.Health = spec.health
	humanoid.WalkSpeed = 0
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false

	model:PivotTo(slot.home)
	model.Parent = folder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	model:SetAttribute("Element", spec.element)
	CollectionService:AddTag(model, "Npc")
	addNameplate(model, root, spec, humanoid)

	local entity = Registry.register(model, humanoid, root, "Dummy", nil)
	entity.element = spec.element
	entity.baseWalkSpeed = 0
	entity.baseJumpPower = 0
	entity.baseJumpHeight = 0
	entity.forceBlock = spec.guard
	entity.blocking = spec.guard
	slot.entity = entity

	humanoid.Died:Once(function()
		task.delay(3, function()
			model:Destroy()
			spawnDummy(index)
		end)
	end)
end

-- Heal and return dummies that have been left alone.
local function tend()
	local now = Registry.now()
	for _, slot in slots do
		local entity = slot.entity
		if entity and Registry.isAlive(entity) and now - entity.lastCombatAt > 4 then
			entity.humanoid.Health = entity.humanoid.MaxHealth
			local stunned = entity.stunUntil > now or entity.guardBrokenUntil > now
			if not stunned and (entity.root.Position - slot.home.Position).Magnitude > 3 then
				entity.root.AssemblyLinearVelocity = Vector3.zero
				entity.model:PivotTo(slot.home)
			end
		end
	end
end

function DummyService.init(_self: any)
	folder = Instance.new("Folder")
	folder.Name = "Dummies"
	folder.Parent = Workspace
	Registry.excludeFromWorld(folder)
	for index in DUMMIES do
		slots[index] = { entity = nil, home = MapService.TRAINING_SPOTS[index] }
	end
end

function DummyService.start(_self: any)
	for index in DUMMIES do
		task.spawn(spawnDummy, index)
	end
	while true do
		task.wait(1)
		tend()
	end
end

return DummyService
