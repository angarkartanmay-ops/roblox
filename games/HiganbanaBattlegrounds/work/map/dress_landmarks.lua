-- Section 3 follow-up (playtest fixes): dress the two landmarks that were still greybox and give
-- every generated prop a colour of its own. MeshPart.Color is ignored where the texture loads, so
-- this changes nothing on a healthy network; where Roblox's CDN is blocked (TLS inspection) the
-- props read as what they are instead of flat white.
--   * SelectLantern: the 3x7x3 Slate box becomes invisible (it keeps the prompt and collision);
--     a StoneLantern mesh scaled to its height stands in it.
--   * ElderTrunkBlock: invisible collider; a DormantElder model (ElderTrunk x1.7 + ElderCrown x2,
--     the same meshes ElderService builds the awake Elder from) stands over it.
local cache = game.ServerStorage.DressingCache
local map = workspace.FarShore
local dressing = map:FindFirstChild("Dressing")
assert(dressing, "no FarShore.Dressing")

local KIND_COLOUR = {
	ToriiGate = Color3.fromRGB(184, 42, 34),
	PineTree = Color3.fromRGB(58, 98, 64),
	DeadPine = Color3.fromRGB(96, 84, 76),
	BambooClump = Color3.fromRGB(104, 150, 72),
	BambooCluster = Color3.fromRGB(104, 150, 72),
	SpiderLilyCluster = Color3.fromRGB(200, 36, 52),
	Boulder = Color3.fromRGB(110, 114, 104),
	StoneCairn = Color3.fromRGB(152, 148, 140),
	StoneLantern = Color3.fromRGB(178, 172, 158),
	JizoStatue = Color3.fromRGB(162, 158, 148),
	FerrymanHut = Color3.fromRGB(170, 130, 72),
	FerryBoat = Color3.fromRGB(98, 72, 52),
	FerryPier = Color3.fromRGB(98, 82, 66),
	PhantomBoat = Color3.fromRGB(120, 132, 152),
	TrainingDummy = Color3.fromRGB(172, 142, 92),
	ArmorPile = Color3.fromRGB(92, 88, 86),
	NoboriBanner = Color3.fromRGB(204, 194, 174),
	BridgeParapet = Color3.fromRGB(182, 178, 170),
	ElderTrunk = Color3.fromRGB(92, 30, 28),
	ElderCrown = Color3.fromRGB(214, 34, 46),
}

local function meshOf(name)
	local holder = cache:FindFirstChild(name)
	local mesh = holder and holder:FindFirstChildWhichIsA("MeshPart", true)
	assert(mesh, "no cached mesh " .. name)
	return mesh:Clone()
end

local function findPart(name)
	for _, d in map:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function stand(mesh, scale, base, name, kind, parent)
	mesh.Name = name
	mesh.Size = mesh.Size * scale
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanTouch = false
	mesh.CanQuery = false
	mesh.CastShadow = true
	mesh.Color = KIND_COLOUR[kind] or Color3.new(1, 1, 1)
	mesh.CFrame = CFrame.new(base + Vector3.new(0, mesh.Size.Y / 2, 0)) * mesh.CFrame.Rotation
	mesh:SetAttribute("Dressing", kind)
	mesh.Parent = parent
	return mesh
end

local report = {}

-- 1. colours
local painted = 0
for _, d in dressing:GetDescendants() do
	if d:IsA("MeshPart") then
		local kind = string.match(d.Name, "__(.+)$") or d:GetAttribute("Dressing")
		local colour = kind and KIND_COLOUR[kind]
		if colour then
			d.Color = colour
			painted += 1
		end
	end
end
table.insert(report, "painted " .. painted)

-- 2. select lantern
local lantern = findPart("SelectLantern")
assert(lantern, "no SelectLantern")
local old = dressing:FindFirstChild("SelectLantern__StoneLantern")
if old then
	old:Destroy()
end
local mesh = meshOf("StoneLantern")
local scale = lantern.Size.Y * 1.1 / mesh.Size.Y
local base = lantern.Position - Vector3.new(0, lantern.Size.Y / 2, 0)
stand(mesh, scale, base, "SelectLantern__StoneLantern", "StoneLantern", dressing)
lantern.Transparency = 1
table.insert(report, ("lantern mesh %s at %s"):format(tostring(mesh.Size), tostring(mesh.Position)))

-- 3. dormant Elder
local block = findPart("ElderTrunkBlock")
assert(block, "no ElderTrunkBlock")
local prior = dressing:FindFirstChild("DormantElder")
if prior then
	prior:Destroy()
end
local anchor = block.Position - Vector3.new(0, block.Size.Y / 2, 0)
local dormant = Instance.new("Model")
dormant.Name = "DormantElder"
local trunk = stand(meshOf("ElderTrunk"), 1.7, anchor - Vector3.new(0, 1.5, 0), "Trunk__ElderTrunk", "ElderTrunk", dormant)
stand(meshOf("ElderCrown"), 2, anchor + Vector3.new(0, trunk.Size.Y - 12, 0), "Crown__ElderCrown", "ElderCrown", dormant)
dormant.PrimaryPart = trunk
dormant.Parent = dressing
block.Transparency = 1
local cf, size = dormant:GetBoundingBox()
table.insert(report, ("dormant elder bbox %s at %s (anchor %s)"):format(tostring(size), tostring(cf.Position), tostring(anchor)))

local preview = workspace:FindFirstChild("_MeshPreview")
if preview then
	preview:Destroy()
end
return table.concat(report, "\n")
