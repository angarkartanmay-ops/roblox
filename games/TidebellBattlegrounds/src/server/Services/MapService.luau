--!strict
-- Builds Kanejima: the ocean, the island, the Toll Plaza, the bell tower with the Tide Bell,
-- the Shrine of Arrival (spawn and safe zone), the Training Grounds and the Drowned Grove.
-- Everything is generated from code (deterministic), so the place file stays small.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Elements = require(ReplicatedStorage.Shared.Elements)

local MapService = {}

MapService.GROUND_Y = 8
MapService.PLAZA_TOP = 9
MapService.PLAZA_CENTER = Vector3.new(0, 9, 0)
MapService.PLAZA_RADIUS = 75
MapService.BOSS_SPAWN = CFrame.lookAt(Vector3.new(0, 24, -52), Vector3.new(0, 24, 0))
MapService.SAFE_CENTER = Vector3.new(0, 16, 128)
MapService.SAFE_SIZE = Vector3.new(56, 34, 50)
MapService.TRAINING_SPOTS = {
	CFrame.lookAt(Vector3.new(-122, 13, -13), Vector3.new(-100, 13, -13)),
	CFrame.lookAt(Vector3.new(-122, 13, 0), Vector3.new(-100, 13, 0)),
	CFrame.lookAt(Vector3.new(-122, 13, 13), Vector3.new(-100, 13, 13)),
}

local STONE = Color3.fromRGB(92, 87, 84)
local STONE_DARK = Color3.fromRGB(64, 61, 60)
local WOOD = Color3.fromRGB(107, 76, 52)
local VERMILION = Color3.fromRGB(190, 42, 28)
local BRONZE = Color3.fromRGB(140, 102, 56)
local TIDE = Color3.fromRGB(60, 240, 225)
local LANTERN = Color3.fromRGB(255, 183, 110)

local mapFolder: Folder

local function color3(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

local function part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Slate
	p.Color = STONE
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent or mapFolder
	return p
end

-- Vertical cylinder: Roblox cylinders run along X, so turn X upward.
local function column(
	position: Vector3,
	height: number,
	diameter: number,
	props: { [string]: any }?,
	parent: Instance?
): Part
	local p = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
	}, parent)
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	return p
end

local function disc(
	center: Vector3,
	thickness: number,
	diameter: number,
	props: { [string]: any }?,
	parent: Instance?
): Part
	return column(center, thickness, diameter, props, parent)
end

local function label(target: BasePart, face: Enum.NormalId, title: string, subtitle: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = target

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, if subtitle then 0.62 else 1)
	titleLabel.Font = Enum.Font.Bangers
	titleLabel.TextScaled = true
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.fromRGB(255, 236, 200)
	titleLabel.Parent = gui

	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0.05, 0.62)
		sub.Size = UDim2.fromScale(0.9, 0.3)
		sub.Font = Enum.Font.BuilderSansBold
		sub.TextScaled = true
		sub.Text = subtitle
		sub.TextColor3 = Color3.fromRGB(220, 210, 195)
		sub.Parent = gui
	end
end

local function buildTerrain()
	local terrain = Workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(18, 78, 84)
	terrain.WaterTransparency = 0.45
	terrain.WaterReflectance = 0.5
	terrain.WaterWaveSize = 0.25
	terrain.WaterWaveSpeed = 9

	-- Seabed and ocean (water surface at y = 0)
	terrain:FillBlock(CFrame.new(0, -32, 0), Vector3.new(1600, 8, 1600), Enum.Material.Sand)
	terrain:FillBlock(CFrame.new(0, -14, 0), Vector3.new(1600, 28, 1600), Enum.Material.Water)
	-- Beach ring, then the island's grass plateau (top at GROUND_Y)
	terrain:FillCylinder(CFrame.new(0, -13.5, 0), 33, 238, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -12.25, 0), 35.5, 214, Enum.Material.Ground)
	terrain:FillCylinder(CFrame.new(0, -11, 0), 38, 200, Enum.Material.Grass)

	-- Rock outcrops around the rim
	local rng = Random.new(1060)
	for index = 1, 14 do
		local angle = index / 14 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local radius = rng:NextNumber(196, 222)
		local center = Vector3.new(math.cos(angle) * radius, rng:NextNumber(2, 7), math.sin(angle) * radius)
		terrain:FillBall(
			center,
			rng:NextNumber(8, 15),
			if index % 3 == 0 then Enum.Material.Slate else Enum.Material.Rock
		)
	end

	-- Tide pools in the Drowned Grove
	terrain:FillCylinder(CFrame.new(118, 5, 30), 6, 13, Enum.Material.Water)
	terrain:FillCylinder(CFrame.new(140, 5, -24), 6, 9, Enum.Material.Water)
	terrain:FillCylinder(CFrame.new(100, 5, -40), 6, 7, Enum.Material.Water)
end

local function buildLantern(position: Vector3, parent: Instance)
	part({ Size = Vector3.new(2.6, 0.7, 2.6), CFrame = CFrame.new(position + Vector3.new(0, 0.35, 0)) }, parent)
	column(position + Vector3.new(0, 2.3, 0), 3.2, 1.1, nil, parent)
	part({ Size = Vector3.new(2.4, 0.5, 2.4), CFrame = CFrame.new(position + Vector3.new(0, 4.1, 0)) }, parent)
	local light = part({
		Size = Vector3.new(1.6, 1.4, 1.6),
		CFrame = CFrame.new(position + Vector3.new(0, 5.05, 0)),
		Material = Enum.Material.Neon,
		Color = LANTERN,
	}, parent)
	local glow = Instance.new("PointLight")
	glow.Color = LANTERN
	glow.Range = 18
	glow.Brightness = 1.6
	glow.Shadows = true
	glow.Parent = light
	part(
		{ Size = Vector3.new(3, 0.6, 3), CFrame = CFrame.new(position + Vector3.new(0, 6.05, 0)), Color = STONE_DARK },
		parent
	)
	part({
		Size = Vector3.new(0.8, 0.6, 0.8),
		CFrame = CFrame.new(position + Vector3.new(0, 6.65, 0)),
		Color = STONE_DARK,
	}, parent)
end

local function buildPlaza()
	local plaza = Instance.new("Model")
	plaza.Name = "TollPlaza"
	plaza.Parent = mapFolder
	local top = MapService.PLAZA_TOP

	disc(Vector3.new(0, top - 1, 0), 2, 150, { Name = "Floor", Color = STONE }, plaza)
	disc(Vector3.new(0, top + 0.03, 0), 0.06, 112, { Color = STONE_DARK }, plaza)
	disc(Vector3.new(0, top + 0.06, 0), 0.06, 106, { Color = STONE }, plaza)
	disc(Vector3.new(0, top + 0.09, 0), 0.06, 52, { Color = STONE_DARK }, plaza)
	disc(Vector3.new(0, top + 0.12, 0), 0.06, 48, { Color = STONE }, plaza)
	disc(
		Vector3.new(0, top + 0.15, 0),
		0.08,
		14,
		{ Material = Enum.Material.Marble, Color = Color3.fromRGB(196, 188, 172) },
		plaza
	)

	-- The Five Seals: one short pillar per element, linked to the centre by glowing lines.
	for index, element in Elements.ORDER do
		local info = Elements.INFO[element]
		local angle = math.rad(-90 + (index - 1) * 72)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = direction * 22 + Vector3.new(0, top, 0)
		local seal = part({
			Name = `Seal{element}`,
			Size = Vector3.new(3.4, 4, 3.4),
			CFrame = CFrame.lookAt(position + Vector3.new(0, 2, 0), Vector3.new(0, top + 2, 0)),
			Color = STONE_DARK,
		}, plaza)
		part({
			Size = Vector3.new(3.8, 0.5, 3.8),
			CFrame = seal.CFrame * CFrame.new(0, 2.25, 0),
			Material = Enum.Material.Neon,
			Color = color3(info.color),
		}, plaza)
		local line = part({
			Size = Vector3.new(0.35, 0.05, 15),
			CFrame = CFrame.lookAt(direction * 14.5 + Vector3.new(0, top + 0.2, 0), Vector3.new(0, top + 0.2, 0)),
			Material = Enum.Material.Neon,
			Color = color3(info.color),
			Transparency = 0.25,
		}, plaza)
		line.CastShadow = false

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(3.5, 3.5)
		billboard.StudsOffset = Vector3.new(0, 4.6, 0)
		billboard.MaxDistance = 140
		billboard.LightInfluence = 0
		billboard.Parent = seal
		local glyph = Instance.new("TextLabel")
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.TextScaled = true
		glyph.Font = Enum.Font.BuilderSansExtraBold
		glyph.Text = info.glyph
		glyph.TextColor3 = color3(info.color)
		glyph.TextStrokeTransparency = 0.4
		glyph.Parent = billboard
	end

	-- Broken pillars around the rim, some toppled.
	local rng = Random.new(77)
	for index = 1, 12 do
		local angle = (index - 0.5) / 12 * math.pi * 2
		local base = Vector3.new(math.cos(angle) * 64, top, math.sin(angle) * 64)
		part(
			{ Size = Vector3.new(5, 1, 5), CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)), Color = STONE_DARK },
			plaza
		)
		if index % 4 == 0 then
			local length = rng:NextNumber(12, 16)
			local fallen = part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(length, 3.4, 3.4),
				CFrame = CFrame.new(base + Vector3.new(0, 1.8, 0))
					* CFrame.Angles(0, angle + math.rad(rng:NextNumber(60, 120)), 0)
					* CFrame.new(length / 2 - 1.5, 0, 0),
				Color = STONE,
			}, plaza)
			fallen.Name = "FallenPillar"
		else
			local height = rng:NextNumber(7, 16)
			column(base + Vector3.new(0, 1 + height / 2, 0), height, 3.4, { Color = STONE }, plaza)
			part({
				Size = Vector3.new(3.8, 0.8, 3.8),
				CFrame = CFrame.new(base + Vector3.new(0, 1 + height + 0.1, 0))
					* CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12))),
				Color = STONE_DARK,
			}, plaza)
		end
	end

	for index = 1, 8 do
		local angle = math.rad(22.5 + (index - 1) * 45)
		buildLantern(Vector3.new(math.cos(angle) * 76, MapService.GROUND_Y, math.sin(angle) * 76), plaza)
	end
end

local function buildBellTower()
	local tower = Instance.new("Model")
	tower.Name = "BellTower"
	tower.Parent = mapFolder
	local z = -128
	local deck = 22

	part(
		{ Name = "Deck", Size = Vector3.new(46, 14, 38), CFrame = CFrame.new(0, deck - 7, z), Color = STONE_DARK },
		tower
	)
	-- Stairs from the plaza rim up to the deck.
	for step = 0, 9 do
		local height = 1.4 * (step + 1)
		part({
			Size = Vector3.new(16, height + 1, 3.4),
			CFrame = CFrame.new(0, MapService.GROUND_Y + (height + 1) / 2, -74 - step * 3.4),
			Color = if step % 2 == 0 then STONE else STONE_DARK,
		}, tower)
	end

	for _, offset in
		{ Vector3.new(-14, 0, -11), Vector3.new(14, 0, -11), Vector3.new(-14, 0, 11), Vector3.new(14, 0, 11) }
	do
		column(
			Vector3.new(offset.X, deck + 13, z + offset.Z),
			26,
			2.8,
			{ Material = Enum.Material.Wood, Color = VERMILION },
			tower
		)
	end
	local roofColor = Color3.fromRGB(42, 46, 56)
	part({ Size = Vector3.new(38, 2, 32), CFrame = CFrame.new(0, deck + 27, z), Color = roofColor }, tower)
	part({ Size = Vector3.new(28, 2, 23), CFrame = CFrame.new(0, deck + 29, z), Color = roofColor }, tower)
	part({ Size = Vector3.new(17, 2, 13), CFrame = CFrame.new(0, deck + 31, z), Color = roofColor }, tower)
	part({
		Size = Vector3.new(30, 1.6, 1.6),
		CFrame = CFrame.new(0, deck + 24.5, z),
		Material = Enum.Material.Wood,
		Color = WOOD,
	}, tower)

	-- The Tide Bell
	local bellTop = deck + 18
	column(
		Vector3.new(0, deck + 11, z),
		14,
		12,
		{ Name = "TideBell", Material = Enum.Material.Metal, Color = BRONZE },
		tower
	)
	part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(12, 12, 12),
		CFrame = CFrame.new(0, bellTop, z),
		Material = Enum.Material.Metal,
		Color = BRONZE,
	}, tower)
	column(Vector3.new(0, deck + 4.6, z), 1.2, 13.4, { Material = Enum.Material.Metal, Color = BRONZE }, tower)
	column(Vector3.new(0, deck + 23.5, z), 1.6, 1.6, { Material = Enum.Material.Metal, Color = BRONZE }, tower)
	for index = 0, 5 do
		local angle = index / 6 * math.pi * 2
		local rune = part({
			Size = Vector3.new(0.6, 9, 0.3),
			CFrame = CFrame.new(0, deck + 11, z) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -6.05),
			Material = Enum.Material.Neon,
			Color = TIDE,
		}, tower)
		rune.CastShadow = false
	end
	local inner = part(
		{ Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, deck + 6, z), Transparency = 1, CanCollide = false },
		tower
	)
	local light = Instance.new("PointLight")
	light.Color = TIDE
	light.Range = 34
	light.Brightness = 2.4
	light.Parent = inner

	local sign = part({
		Size = Vector3.new(18, 3.4, 0.6),
		CFrame = CFrame.new(0, deck + 2.6, z + 19.3),
		Material = Enum.Material.Wood,
		Color = WOOD,
	}, tower)
	label(sign, Enum.NormalId.Back, "THE TIDE BELL", "It rises once in sixty years")
end

local function buildShrine()
	local shrine = Instance.new("Model")
	shrine.Name = "ShrineOfArrival"
	shrine.Parent = mapFolder
	local deckTop = MapService.GROUND_Y + 1.5

	part({
		Name = "Deck",
		Size = Vector3.new(52, 3, 46),
		CFrame = CFrame.new(0, deckTop - 1.5, 130),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD,
	}, shrine)
	-- Pier into the sea
	part({
		Size = Vector3.new(10, 1.4, 80),
		CFrame = CFrame.new(0, 4.5, 190),
		Material = Enum.Material.WoodPlanks,
		Color = WOOD,
	}, shrine)
	for step = 0, 6 do
		for _, x in { -5.5, 5.5 } do
			column(
				Vector3.new(x, -2, 158 + step * 12),
				14,
				1.2,
				{ Material = Enum.Material.Wood, Color = WOOD },
				shrine
			)
		end
	end

	-- Spawn points (hidden; characters land on the deck)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = shrine
	for _, offset in { Vector3.new(-9, 0, -6), Vector3.new(9, 0, -6), Vector3.new(-9, 0, 8), Vector3.new(9, 0, 8) } do
		local spawn = Instance.new("SpawnLocation")
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 3
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = CFrame.new(Vector3.new(0, deckTop + 0.5, 130) + offset)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanQuery = false
		local decal = spawn:FindFirstChildOfClass("Decal")
		if decal then
			decal:Destroy()
		end
		spawn.Parent = spawns
	end

	-- Shrine hall behind the spawns
	for _, x in { -12, 12 } do
		for _, zOffset in { 144, 152 } do
			column(
				Vector3.new(x, deckTop + 6, zOffset),
				12,
				1.6,
				{ Material = Enum.Material.Wood, Color = VERMILION },
				shrine
			)
		end
	end
	part({
		Size = Vector3.new(32, 1.4, 14),
		CFrame = CFrame.new(0, deckTop + 12.7, 148),
		Color = Color3.fromRGB(42, 46, 56),
	}, shrine)
	part({
		Size = Vector3.new(24, 1.4, 10),
		CFrame = CFrame.new(0, deckTop + 14.1, 148),
		Color = Color3.fromRGB(42, 46, 56),
	}, shrine)
	local hallSign = part({
		Size = Vector3.new(16, 3, 0.5),
		CFrame = CFrame.new(0, deckTop + 10.6, 140.6),
		Material = Enum.Material.Wood,
		Color = WOOD,
	}, shrine)
	label(hallSign, Enum.NormalId.Front, "SHRINE OF ARRIVAL", "No blood is spilled here")

	-- Altar of the Five Schools: opens the champion picker.
	local altar = part({
		Name = "Altar",
		Size = Vector3.new(4.4, 3, 4.4),
		CFrame = CFrame.new(0, deckTop + 1.5, 116),
		Material = Enum.Material.Marble,
		Color = Color3.fromRGB(196, 188, 172),
	}, shrine)
	local altarGlow = part({
		Size = Vector3.new(3.4, 0.4, 3.4),
		CFrame = CFrame.new(0, deckTop + 3.2, 116),
		Material = Enum.Material.Neon,
		Color = TIDE,
	}, shrine)
	altarGlow.CastShadow = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Choose Champion"
	prompt.ObjectText = "Altar of the Five Schools"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = altar
	CollectionService:AddTag(altar, "FighterAltar")

	-- Torii gate between the shrine and the plaza
	local gateZ = 96
	for _, x in { -9.5, 9.5 } do
		column(
			Vector3.new(x, MapService.GROUND_Y + 8.5, gateZ),
			17,
			2.4,
			{ Material = Enum.Material.SmoothPlastic, Color = VERMILION },
			shrine
		)
	end
	part({
		Size = Vector3.new(21, 1.3, 1.6),
		CFrame = CFrame.new(0, MapService.GROUND_Y + 13.5, gateZ),
		Material = Enum.Material.SmoothPlastic,
		Color = VERMILION,
	}, shrine)
	part({
		Size = Vector3.new(28, 1.6, 2.8),
		CFrame = CFrame.new(0, MapService.GROUND_Y + 17.6, gateZ),
		Material = Enum.Material.SmoothPlastic,
		Color = VERMILION,
	}, shrine)
	part({
		Size = Vector3.new(29, 0.7, 3.2),
		CFrame = CFrame.new(0, MapService.GROUND_Y + 18.7, gateZ),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(26, 24, 24),
	}, shrine)

	-- Stepping stones from the gate to the plaza rim
	for step = 0, 4 do
		part({
			Size = Vector3.new(7, 0.6, 3.6),
			CFrame = CFrame.new(if step % 2 == 0 then -1.2 else 1.2, MapService.GROUND_Y + 0.25, 92 - step * 4),
			Color = STONE,
		}, shrine)
	end
end

local function buildTrainingGrounds()
	local grounds = Instance.new("Model")
	grounds.Name = "TrainingGrounds"
	grounds.Parent = mapFolder
	part({
		Size = Vector3.new(44, 1.4, 44),
		CFrame = CFrame.new(-120, MapService.GROUND_Y + 0.7, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 118, 82),
	}, grounds)
	for index = 0, 9 do
		local angle = index / 10 * math.pi * 2
		column(
			Vector3.new(-120 + math.cos(angle) * 23, MapService.GROUND_Y + 2.5, math.sin(angle) * 23),
			5,
			1,
			{ Material = Enum.Material.Wood, Color = WOOD },
			grounds
		)
	end
	local sign = part({
		Size = Vector3.new(14, 4.4, 0.6),
		CFrame = CFrame.lookAt(
			Vector3.new(-98, MapService.GROUND_Y + 4.5, -24),
			Vector3.new(-60, MapService.GROUND_Y + 4.5, -24)
		),
		Material = Enum.Material.Wood,
		Color = WOOD,
	}, grounds)
	label(sign, Enum.NormalId.Front, "TRAINING GROUNDS", "Each dummy wears an element. Test the wheel.")
end

local function buildGrove()
	local grove = Instance.new("Model")
	grove.Name = "DrownedGrove"
	grove.Parent = mapFolder
	local rng = Random.new(4242)
	local bark = Color3.fromRGB(56, 48, 43)
	for _ = 1, 10 do
		local position = Vector3.new(rng:NextNumber(92, 170), MapService.GROUND_Y, rng:NextNumber(-70, 70))
		local height = rng:NextNumber(14, 24)
		local lean = CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12)))
		local base = CFrame.new(position) * lean
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, rng:NextNumber(1.6, 2.6), rng:NextNumber(1.6, 2.6)),
			CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Material = Enum.Material.Wood,
			Color = bark,
		}, grove)
		for _ = 1, 3 do
			local branchLength = rng:NextNumber(5, 9)
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(branchLength, 0.7, 0.7),
				CFrame = base
					* CFrame.new(0, rng:NextNumber(height * 0.5, height * 0.95), 0)
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(20, 50)))
					* CFrame.new(branchLength / 2, 0, 0),
				Material = Enum.Material.Wood,
				Color = bark,
			}, grove)
		end
	end
end

local function buildBoundary()
	local walls = Instance.new("Folder")
	walls.Name = "Boundary"
	walls.Parent = mapFolder
	local segments = 36
	local radius = 250
	for index = 0, segments - 1 do
		local angle = index / segments * math.pi * 2
		local position = Vector3.new(math.cos(angle) * radius, 25, math.sin(angle) * radius)
		local wall = part({
			Size = Vector3.new(46, 80, 2),
			CFrame = CFrame.lookAt(position, Vector3.new(0, 25, 0)),
			Transparency = 1,
			CanQuery = false,
			CastShadow = false,
		}, walls)
		wall.Name = "Wall"
	end
end

function MapService.isSafe(position: Vector3): boolean
	local offset = position - MapService.SAFE_CENTER
	local half = MapService.SAFE_SIZE / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

function MapService.init(_self: any)
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = Workspace

	buildTerrain()
	buildPlaza()
	buildBellTower()
	buildShrine()
	buildTrainingGrounds()
	buildGrove()
	buildBoundary()
end

return MapService
