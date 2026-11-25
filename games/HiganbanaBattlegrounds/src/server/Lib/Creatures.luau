--!strict
-- Builds the Wilds' creatures out of plain Parts: an R6 rig (so the procedural animation drives
-- them like the dummies) dressed with welded pieces, then scaled. Parts only, no meshes or
-- textures, and only materials that render without the asset CDN, so every creature reads the
-- same on any network. Each look is original, drawn from public folklore:
--   Blossom Husk       a pilgrim's corpse with a spider lily where its head was
--   Lantern Kasha      a corpse-stealing cat demon whose tail ends in a paper lantern
--   Stone Acolyte      a roadside guardian statue with a red bib and a ringed staff
--   Nail Ronin         a bone swordsman under a broken straw hat, studded with toll nails
--   Drowned Ferryhand  a river imp with a dish of water on its head and a shell on its back
--   Ox-Head Jailer     the ox-headed gate warden with an iron club and the gate's chains
--   The Lantern Bride  a fox-masked bride in white under a red umbrella, foxfire around her
--   The Robe-Taker     the old woman of the far bank with the robes of the dead on her back

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Phases = require(ReplicatedStorage.Shared.Phases)
local Wilds = require(ReplicatedStorage.Shared.Wilds)

type Creature = Wilds.Creature

local Creatures = {}

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local METAL = Enum.Material.Metal
local WOOD = Enum.Material.Wood
local STONE = Enum.Material.Limestone
local GLASS = Enum.Material.Glass

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

type Piece = {
	shape: Enum.PartType?,
	wedge: boolean?,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	name: string?,
}

-- Weld a dressing piece to `attach`, placed in that part's own frame (-Z forward, +Y up).
local function add(model: Model, attach: BasePart, piece: Piece): BasePart
	local part: BasePart
	if piece.wedge then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = piece.shape or Enum.PartType.Block
		part = p
	end
	part.Name = piece.name or "Dressing"
	part.Size = piece.size
	part.CFrame = attach.CFrame * piece.at
	part.Color = piece.color
	part.Material = piece.material or SMOOTH
	part.Transparency = piece.transparency or 0
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = piece.material ~= NEON
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attach
	weld.Part1 = part
	weld.Parent = part
	part.Parent = model
	return part
end

local function ball(size: number, cf: CFrame, color: Color3, material: Enum.Material?): Piece
	return {
		shape = Enum.PartType.Ball,
		size = Vector3.new(size, size, size),
		at = cf,
		color = color,
		material = material,
	}
end

-- A cylinder whose axis runs along the attach part's Y (upright) unless rotated further.
local function rod(length: number, thickness: number, cf: CFrame, color: Color3, material: Enum.Material?): Piece
	return {
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(length, thickness, thickness),
		at = cf * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		material = material,
	}
end

-- A flat disc lying level in the attach part's frame (a hat brim, a dish, an umbrella).
local function disc(diameter: number, thickness: number, cf: CFrame, color: Color3, material: Enum.Material?): Piece
	return rod(thickness, diameter, cf, color, material)
end

local function block(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Piece
	return { size = size, at = cf, color = color, material = material }
end

local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = false
	pointLight.Parent = part
end

-- A ring of `count` short links (staff rings, nose rings, manacles), upright in the XY plane.
local function ring(
	model: Model,
	attach: BasePart,
	center: CFrame,
	radius: number,
	count: number,
	thick: number,
	color: Color3
)
	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local link = 2 * math.pi * radius / count * 1.15
		add(model, attach, {
			size = Vector3.new(link, thick, thick),
			at = center
				* CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
				* CFrame.Angles(0, 0, angle + math.pi / 2),
			color = color,
			material = METAL,
		})
	end
end

---------------------------------------------------------------------------------------------------
-- The rig

type Rig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart,
	head: BasePart,
	rightArm: BasePart,
	leftArm: BasePart,
	rightLeg: BasePart,
	leftLeg: BasePart,
}

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = c1
	joint.Parent = part0
end

local function buildRig(skin: Color3, material: Enum.Material?): Rig
	local model = Instance.new("Model")
	local function limb(name: string, size: Vector3, cframe: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = skin
		p.Material = material or SMOOTH
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
	root.Transparency = 1
	local torso = limb("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
	local head = limb("Head", Vector3.new(2, 1, 1), CFrame.new(0, 4.5, 0))
	local rightArm = limb("Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0))
	local leftArm = limb("Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0))
	local rightLeg = limb("Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0))
	local leftLeg = limb("Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0))
	for _, part in { head, rightArm, leftArm } do
		part.CanCollide = false
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
	return {
		model = model,
		humanoid = humanoid,
		root = root,
		torso = torso,
		head = head,
		rightArm = rightArm,
		leftArm = leftArm,
		rightLeg = rightLeg,
		leftLeg = leftLeg,
	}
end

local function paint(part: BasePart, color: Color3, material: Enum.Material?)
	part.Color = color
	if material then
		part.Material = material
	end
end

---------------------------------------------------------------------------------------------------
-- Looks

local LOOKS: { [string]: (Rig) -> () } = {}

LOOKS.BlossomHusk = function(r)
	local m = r.model
	local robe = rgb(214, 206, 186)
	local vine = rgb(62, 112, 58)
	local lily = rgb(214, 36, 44)
	paint(r.leftLeg, rgb(84, 78, 64))
	paint(r.rightLeg, rgb(84, 78, 64))
	-- a pilgrim's white robe, torn short
	add(m, r.torso, block(Vector3.new(2.2, 2.1, 1.2), at(0, 0.02, 0), robe))
	add(m, r.torso, block(Vector3.new(2.3, 1.1, 1.3), at(0, -1.45, 0), robe))
	add(
		m,
		r.torso,
		{ wedge = true, size = Vector3.new(0.6, 0.7, 1.3), at = at(0.85, -2.3, 0, 0, 0, 180), color = robe }
	)
	add(m, r.torso, block(Vector3.new(2.25, 0.25, 1.25), at(0, -0.55, 0), rgb(120, 96, 70)))
	-- the head is gone: a stem, and the lily it became
	r.head.Transparency = 1
	add(m, r.head, rod(1.3, 0.38, at(0, 0.1, 0), vine))
	local center = at(0, 0.85, 0)
	add(m, r.head, ball(0.55, center, rgb(150, 28, 34)))
	for index = 1, 6 do
		local yaw = index * 60
		add(
			m,
			r.head,
			block(Vector3.new(0.16, 0.12, 1.7), center * at(0, 0, 0, 0, yaw, 0) * at(0, 0.35, -0.75, 28, 0, 0), lily)
		)
		add(
			m,
			r.head,
			block(
				Vector3.new(0.06, 0.06, 2.1),
				center * at(0, 0, 0, 0, yaw + 30, 0) * at(0, 0.8, -0.8, 50, 0, 0),
				rgb(255, 80, 90),
				NEON
			)
		)
	end
	-- vines up both arms, a bud on each shoulder
	for _, arm in { r.rightArm, r.leftArm } do
		add(m, arm, rod(2.2, 0.22, at(0, -0.1, -0.45, 0, 0, 20), vine))
		add(m, arm, rod(1.6, 0.18, at(0, 0, 0.45, 0, 0, -25), vine))
		add(m, arm, ball(0.45, at(0, 1.05, 0), lily))
	end
	-- the straw hat it walked in with, still on its back
	add(m, r.torso, disc(2.4, 0.18, at(0, 0.4, 0.75, 80, 0, 0), rgb(176, 146, 92), WOOD))
end

LOOKS.LanternKasha = function(r)
	local m = r.model
	local fur = rgb(46, 32, 42)
	local mask = rgb(240, 236, 226)
	local flame = rgb(255, 128, 40)
	for _, part in { r.torso, r.rightArm, r.leftArm, r.rightLeg, r.leftLeg, r.head } do
		paint(part, fur)
	end
	-- a hump of fur over the shoulders and a flame mane
	add(m, r.torso, block(Vector3.new(2.3, 0.9, 1.4), at(0, 0.8, 0.15, -12, 0, 0), rgb(36, 24, 32)))
	for index = -1, 1 do
		local part = add(m, r.torso, {
			wedge = true,
			size = Vector3.new(0.5, 1.2, 0.8),
			at = at(index * 0.7, 1.35, 0.3, -20, 0, index * 14),
			color = flame,
			material = NEON,
		})
		part.Transparency = 0.15
	end
	-- the cat mask
	add(m, r.head, block(Vector3.new(1.5, 1.05, 0.14), at(0, 0, -0.56), mask))
	add(m, r.head, block(Vector3.new(0.38, 0.08, 0.04), at(-0.36, 0.12, -0.65, 0, 0, -12), flame, NEON))
	add(m, r.head, block(Vector3.new(0.38, 0.08, 0.04), at(0.36, 0.12, -0.65, 0, 0, 12), flame, NEON))
	add(m, r.head, block(Vector3.new(0.06, 0.4, 0.04), at(0, -0.15, -0.65), rgb(200, 40, 40)))
	for _, side in { -1, 1 } do
		add(m, r.head, {
			wedge = true,
			size = Vector3.new(0.18, 0.7, 0.5),
			at = at(side * 0.6, 0.8, -0.1, 0, 0, side * -8),
			color = fur,
		})
		add(m, r.head, {
			wedge = true,
			size = Vector3.new(0.1, 0.45, 0.3),
			at = at(side * 0.6, 0.74, -0.2, 0, 0, side * -8),
			color = rgb(200, 60, 60),
		})
		-- whiskers
		add(m, r.head, block(Vector3.new(0.8, 0.04, 0.04), at(side * 0.95, -0.2, -0.6, 0, 0, side * 10), mask))
	end
	-- claws
	for _, arm in { r.rightArm, r.leftArm } do
		for index = -1, 1 do
			add(m, arm, {
				wedge = true,
				size = Vector3.new(0.14, 0.55, 0.28),
				at = at(index * 0.3, -1.25, -0.3, 180, 0, 0),
				color = rgb(236, 226, 206),
			})
		end
	end
	-- the tail, arching up behind it, and the paper lantern it carries
	local tail = at(0, -0.7, 0.5)
	local links = { at(0, 0, 0.6, 30, 0, 0), at(0, 0.7, 1.1, 60, 0, 0), at(0, 1.6, 1.3, 85, 0, 0) }
	for _, link in links do
		add(m, r.torso, {
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(1.1, 0.32, 0.32),
			at = tail * link * CFrame.Angles(0, math.rad(90), 0),
			color = fur,
		})
	end
	local lanternAt = tail * at(0, 2.4, 1.3)
	add(m, r.torso, disc(0.95, 0.12, lanternAt * at(0, 0.62, 0), rgb(30, 20, 20)))
	add(m, r.torso, disc(0.95, 0.12, lanternAt * at(0, -0.62, 0), rgb(30, 20, 20)))
	local paper = add(m, r.torso, rod(1.15, 0.9, lanternAt, rgb(238, 222, 190)))
	paper.Transparency = 0.1
	local core = add(m, r.torso, ball(0.55, lanternAt, rgb(255, 170, 70), NEON))
	light(core, rgb(255, 150, 60), 12, 1.6)
	add(m, r.torso, block(Vector3.new(0.92, 0.12, 0.92), lanternAt * at(0, 0.1, 0), rgb(200, 40, 40)))
end

LOOKS.StoneAcolyte = function(r)
	local m = r.model
	local stone = rgb(176, 172, 160)
	local bib = rgb(196, 36, 40)
	local moss = rgb(82, 112, 62)
	for _, part in { r.torso, r.rightArm, r.leftArm, r.rightLeg, r.leftLeg } do
		paint(part, stone, STONE)
	end
	-- round bald head, eyes closed in prayer
	r.head.Transparency = 1
	add(m, r.head, ball(1.75, at(0, 0.3, 0), stone, STONE))
	add(m, r.head, block(Vector3.new(0.4, 0.06, 0.06), at(-0.35, 0.3, -0.86, 0, 0, -6), rgb(60, 56, 52)))
	add(m, r.head, block(Vector3.new(0.4, 0.06, 0.06), at(0.35, 0.3, -0.86, 0, 0, 6), rgb(60, 56, 52)))
	add(m, r.head, block(Vector3.new(0.12, 0.12, 0.12), at(0, 0.6, -0.84), rgb(60, 56, 52)))
	add(m, r.head, ball(0.6, at(0.4, 1.0, 0.3), moss))
	-- the red bib every roadside statue is given
	add(
		m,
		r.torso,
		{ wedge = true, size = Vector3.new(1.9, 1.4, 0.14), at = at(0, 0.2, -0.58, 0, 180, 180), color = bib }
	)
	add(m, r.torso, block(Vector3.new(2.05, 0.18, 1.1), at(0, 0.95, 0), bib))
	-- a heavy stone robe
	add(m, r.torso, block(Vector3.new(2.4, 1.6, 1.4), at(0, -1.45, 0), stone, STONE))
	add(m, r.torso, block(Vector3.new(0.9, 0.5, 0.2), at(0.6, -0.4, 0.55), moss))
	add(m, r.torso, block(Vector3.new(0.08, 1.2, 0.08), at(-0.5, -0.1, -0.52, 0, 0, 18), rgb(90, 86, 80)))
	-- the ringed staff in its right hand
	local hand = at(0, -1.1, -0.1)
	add(m, r.rightArm, rod(7, 0.22, hand * at(0, 1.3, -0.3), rgb(120, 92, 52), METAL))
	local top = hand * at(0, 4.9, -0.3)
	ring(m, r.rightArm, top, 0.55, 8, 0.12, rgb(190, 160, 90))
	ring(m, r.rightArm, top * at(0.45, -0.55, 0, 0, 90, 0), 0.22, 6, 0.07, rgb(190, 160, 90))
	ring(m, r.rightArm, top * at(-0.45, -0.55, 0, 0, 90, 0), 0.22, 6, 0.07, rgb(190, 160, 90))
end

LOOKS.NailRonin = function(r)
	local m = r.model
	local bone = rgb(226, 218, 196)
	local navy = rgb(38, 44, 70)
	local iron = rgb(70, 72, 80)
	-- bone limbs
	for _, part in { r.rightArm, r.leftArm, r.rightLeg, r.leftLeg } do
		paint(part, bone)
		part.Size = Vector3.new(0.45, 2, 0.45)
	end
	paint(r.torso, bone)
	-- ribs behind an open, ragged haori
	for index = 0, 3 do
		add(m, r.torso, block(Vector3.new(1.5, 0.14, 0.9), at(0, 0.7 - index * 0.38, -0.1), rgb(204, 196, 172)))
	end
	r.torso.Transparency = 1
	add(m, r.torso, rod(2, 0.35, at(0, 0, 0.1), bone))
	for _, side in { -1, 1 } do
		add(m, r.torso, block(Vector3.new(0.7, 2.1, 1.15), at(side * 0.7, 0.05, 0.05), navy))
		add(m, r.torso, {
			wedge = true,
			size = Vector3.new(0.7, 0.6, 1.15),
			at = at(side * 0.7, -1.3, 0.05, 0, 0, 180),
			color = navy,
		})
	end
	add(m, r.torso, block(Vector3.new(2.3, 1.3, 1.3), at(0, -1.55, 0), rgb(30, 32, 44)))
	add(m, r.torso, block(Vector3.new(2.15, 0.22, 1.2), at(0, -0.85, 0), rgb(150, 40, 40)))
	-- skull
	r.head.Transparency = 1
	add(m, r.head, block(Vector3.new(1.05, 1.1, 1.05), at(0, 0.05, 0), bone))
	add(m, r.head, block(Vector3.new(0.75, 0.3, 0.8), at(0, -0.55, -0.1), rgb(214, 206, 184)))
	for _, side in { -1, 1 } do
		add(m, r.head, block(Vector3.new(0.3, 0.26, 0.1), at(side * 0.24, 0.1, -0.5), rgb(20, 20, 26)))
		add(m, r.head, ball(0.14, at(side * 0.24, 0.1, -0.54), rgb(140, 200, 255), NEON))
	end
	-- the broken straw hat
	add(m, r.head, disc(3.3, 0.14, at(0, 0.7, 0, 10, 0, -8), rgb(190, 160, 100), WOOD))
	add(m, r.head, disc(1.4, 0.5, at(0, 0.95, 0, 10, 0, -8), rgb(170, 140, 86), WOOD))
	add(m, r.head, block(Vector3.new(0.6, 0.1, 0.9), at(1.4, 0.45, 0.4, 0, 20, -40), rgb(150, 120, 74), WOOD))
	-- the sheathed sword it draws from, and the toll nails driven through it
	add(m, r.torso, block(Vector3.new(0.18, 0.28, 3.6), at(-1.15, -1.1, -0.3, 20, 10, 0), rgb(24, 20, 24)))
	add(m, r.torso, block(Vector3.new(0.2, 0.22, 1.1), at(-1.1, -0.45, -2.2, 20, 10, 0), rgb(120, 40, 40)))
	for _, nail in
		{
			at(0.5, 0.6, 0.6, 50, 0, 20),
			at(-0.4, 0.2, 0.6, 40, 0, -30),
			at(0.2, -0.3, 0.6, 60, 0, 5),
			at(0.9, 0.9, 0, 0, 0, -60),
		}
	do
		add(m, r.torso, rod(1.2, 0.12, nail, iron, METAL))
	end
	add(m, r.rightArm, rod(0.9, 0.1, at(0, 0.3, 0.3, 60, 0, 0), iron, METAL))
end

LOOKS.DrownedFerryhand = function(r)
	local m = r.model
	local skin = rgb(78, 114, 98)
	local straw = rgb(150, 122, 72)
	for _, part in { r.torso, r.rightArm, r.leftArm, r.rightLeg, r.leftLeg, r.head } do
		paint(part, skin)
	end
	-- shell
	add(m, r.torso, {
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.7, 2.6, 2.6),
		at = at(0, -0.1, 0.75, 0, 90, 0),
		color = rgb(96, 72, 46),
	})
	add(m, r.torso, {
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.5, 2.85, 2.85),
		at = at(0, -0.1, 0.62, 0, 90, 0),
		color = rgb(150, 130, 80),
	})
	for _, plate in { at(0, 0.5, 1.12), at(-0.55, -0.45, 1.12), at(0.55, -0.45, 1.12) } do
		add(m, r.torso, block(Vector3.new(0.7, 0.7, 0.1), plate * at(0, 0, 0, 0, 0, 45), rgb(70, 52, 34)))
	end
	-- plastron and a straw rain cape over the shoulders
	add(m, r.torso, block(Vector3.new(1.6, 1.7, 0.12), at(0, -0.1, -0.53), rgb(196, 180, 120)))
	for index = -2, 2 do
		add(m, r.torso, {
			wedge = true,
			size = Vector3.new(0.55, 1.1, 0.5),
			at = at(index * 0.48, 0.65, -0.1, 0, 0, 0) * at(0, 0, 0, 0, 180, 0),
			color = straw,
		})
	end
	-- the dish of river on its head, a ring of lank hair, a beak
	add(m, r.head, disc(1.25, 0.16, at(0, 0.55, 0), rgb(200, 196, 180)))
	local water = add(m, r.head, disc(1.0, 0.06, at(0, 0.64, 0), rgb(110, 190, 235), GLASS))
	water.Transparency = 0.25
	for index = 1, 8 do
		local yaw = math.rad(index * 45)
		add(
			m,
			r.head,
			block(Vector3.new(0.14, 0.7, 0.14), at(math.sin(yaw) * 0.68, 0.2, math.cos(yaw) * 0.68), rgb(32, 56, 40))
		)
	end
	add(m, r.head, {
		wedge = true,
		size = Vector3.new(0.6, 0.35, 0.6),
		at = at(0, -0.2, -0.75, 0, 180, 0),
		color = rgb(196, 170, 84),
	})
	for _, side in { -1, 1 } do
		add(m, r.head, block(Vector3.new(0.22, 0.14, 0.06), at(side * 0.34, 0.12, -0.52), rgb(255, 220, 80), NEON))
	end
	-- webbed hands, and a mooring rope with an iron hook
	for _, arm in { r.rightArm, r.leftArm } do
		add(m, arm, block(Vector3.new(1.2, 0.08, 0.9), at(0, -1.05, -0.1), rgb(60, 96, 82)))
	end
	for index = 1, 4 do
		add(
			m,
			r.rightArm,
			rod(0.6, 0.12, at(0, -1.2 - index * 0.5, -0.1, 0, 0, if index % 2 == 0 then 8 else -8), rgb(160, 140, 100))
		)
	end
	add(m, r.rightArm, block(Vector3.new(0.12, 0.12, 0.6), at(0, -3.55, -0.3), rgb(70, 72, 80), METAL))
	add(m, r.rightArm, block(Vector3.new(0.12, 0.5, 0.12), at(0, -3.35, -0.6), rgb(70, 72, 80), METAL))
end

LOOKS.OxHeadJailer = function(r)
	local m = r.model
	local skin = rgb(124, 40, 32)
	local hide = rgb(58, 36, 28)
	local horn = rgb(232, 222, 192)
	local iron = rgb(64, 64, 72)
	for _, part in { r.torso, r.rightArm, r.leftArm } do
		paint(part, skin)
	end
	paint(r.rightLeg, rgb(90, 30, 26))
	paint(r.leftLeg, rgb(90, 30, 26))
	-- the ox head
	r.head.Transparency = 1
	add(m, r.head, block(Vector3.new(1.5, 1.3, 1.4), at(0, 0.2, 0), hide))
	add(m, r.head, block(Vector3.new(1.0, 0.7, 0.7), at(0, -0.15, -0.9), rgb(80, 52, 40)))
	add(m, r.head, block(Vector3.new(0.9, 0.2, 0.2), at(0, 0.75, -0.55), rgb(40, 24, 20)))
	for _, side in { -1, 1 } do
		add(
			m,
			r.head,
			block(Vector3.new(0.22, 0.12, 0.06), at(side * 0.4, 0.45, -0.72, 0, 0, side * -15), rgb(255, 60, 40), NEON)
		)
		add(m, r.head, block(Vector3.new(0.16, 0.16, 0.06), at(side * 0.22, -0.2, -1.26), rgb(20, 12, 10)))
		-- horns sweep out, then up
		add(m, r.head, rod(1.3, 0.42, at(side * 1.25, 0.55, 0, 0, 0, 90), horn))
		add(m, r.head, rod(1.2, 0.32, at(side * 1.78, 1.05, 0, 0, 0, side * 12), horn))
		add(m, r.head, rod(0.55, 0.2, at(side * 1.68, 1.78, 0, 0, 0, side * 25), rgb(60, 50, 40)))
		-- ears
		add(m, r.head, block(Vector3.new(0.6, 0.18, 0.35), at(side * 0.95, 0.2, 0.2, 0, 0, side * -25), hide))
	end
	ring(m, r.head, at(0, -0.55, -1.25), 0.22, 6, 0.08, rgb(200, 170, 90))
	-- iron pauldrons and broken manacles
	for _, arm in { r.rightArm, r.leftArm } do
		add(m, arm, block(Vector3.new(1.35, 0.5, 1.35), at(0, 0.85, 0), iron, METAL))
		add(m, arm, block(Vector3.new(1.15, 0.4, 1.15), at(0, -0.6, 0), iron, METAL))
		for index = 1, 3 do
			add(
				m,
				arm,
				block(Vector3.new(0.12, 0.35, 0.22), at(0.4, -0.85 - index * 0.32, 0.2, 0, index * 90, 0), iron, METAL)
			)
		end
	end
	-- chains over the shoulder
	for index = 0, 6 do
		add(
			m,
			r.torso,
			block(
				Vector3.new(0.14, 0.38, 0.24),
				at(-0.9 + index * 0.3, 0.9 - index * 0.3, -0.55, 0, index * 90, 40),
				iron,
				METAL
			)
		)
	end
	-- a striped hide loincloth on a rope belt
	add(m, r.torso, block(Vector3.new(2.3, 1.1, 1.3), at(0, -1.45, 0), rgb(214, 170, 60)))
	for index = -1, 1 do
		add(m, r.torso, block(Vector3.new(0.16, 0.9, 1.34), at(index * 0.65, -1.45, 0, 0, 0, 12), rgb(30, 24, 20)))
	end
	add(m, r.torso, block(Vector3.new(2.2, 0.25, 1.2), at(0, -0.85, 0), rgb(200, 188, 150)))
	-- the kanabo: an iron club studded with rivets, carried low and forward from the right fist
	local grip = at(0, -1.1, -0.2) * at(0, 0, 0, -130, 0, 0)
	add(m, r.rightArm, rod(1.2, 0.3, grip * at(0, 0.4, 0), rgb(50, 36, 30), WOOD))
	local club = grip * at(0, 2.5, 0)
	add(m, r.rightArm, rod(3.2, 0.85, club, rgb(48, 46, 52), METAL))
	for row = -1, 1 do
		for index = 1, 4 do
			local yaw = math.rad(index * 90 + row * 45)
			add(
				m,
				r.rightArm,
				ball(0.24, club * at(math.sin(yaw) * 0.45, row * 0.8, math.cos(yaw) * 0.45), rgb(140, 130, 110), METAL)
			)
		end
	end
end

LOOKS.LanternBride = function(r)
	local m = r.model
	local white = rgb(242, 238, 230)
	local red = rgb(186, 30, 40)
	local foxfire = rgb(150, 210, 255)
	for _, part in { r.torso, r.rightArm, r.leftArm, r.rightLeg, r.leftLeg } do
		paint(part, white)
	end
	paint(r.head, white)
	-- a white wedding kimono to the ground, red at the hem and collar
	add(m, r.torso, block(Vector3.new(2.5, 2.3, 1.7), at(0, -1.9, 0), white))
	add(m, r.torso, block(Vector3.new(2.6, 0.25, 1.8), at(0, -3.0, 0), red))
	add(m, r.torso, { wedge = true, size = Vector3.new(0.12, 0.9, 0.6), at = at(0, 0.6, -0.6, 0, 180, 0), color = red })
	add(m, r.torso, block(Vector3.new(2.15, 0.6, 1.15), at(0, -0.3, 0), rgb(214, 176, 90)))
	add(m, r.torso, block(Vector3.new(0.8, 0.5, 0.3), at(0, -0.3, 0.65), rgb(214, 176, 90)))
	-- long hanging sleeves
	for _, arm in { r.rightArm, r.leftArm } do
		add(m, arm, block(Vector3.new(1.1, 2.1, 1.7), at(0, -0.4, 0.15), white))
		add(m, arm, block(Vector3.new(1.12, 0.18, 1.72), at(0, -1.45, 0.15), red))
	end
	-- the hood and the fox mask
	add(m, r.head, block(Vector3.new(2.1, 0.7, 1.4), at(0, 0.6, 0.05), white))
	add(m, r.head, block(Vector3.new(2.1, 1.3, 0.3), at(0, 0.05, 0.6), white))
	add(m, r.head, block(Vector3.new(1.4, 1.0, 0.12), at(0, -0.05, -0.56), rgb(252, 250, 246)))
	add(m, r.head, {
		wedge = true,
		size = Vector3.new(0.5, 0.35, 0.5),
		at = at(0, -0.3, -0.85, 0, 180, 0),
		color = rgb(252, 250, 246),
	})
	add(m, r.head, block(Vector3.new(0.14, 0.12, 0.08), at(0, -0.38, -1.08), rgb(20, 20, 20)))
	for _, side in { -1, 1 } do
		add(m, r.head, block(Vector3.new(0.4, 0.07, 0.04), at(side * 0.34, 0.08, -0.64, 0, 0, side * 18), red, NEON))
		add(
			m,
			r.head,
			{ wedge = true, size = Vector3.new(0.14, 0.6, 0.45), at = at(side * 0.55, 1.15, -0.2), color = white }
		)
		add(
			m,
			r.head,
			{ wedge = true, size = Vector3.new(0.08, 0.4, 0.28), at = at(side * 0.55, 1.1, -0.3), color = red }
		)
	end
	-- the red paper umbrella in her left hand
	local hand = at(0, -1.1, -0.2)
	add(m, r.leftArm, rod(5.2, 0.16, hand * at(0, 2.3, 0), rgb(60, 40, 30), WOOD))
	local canopy = hand * at(0, 4.8, 0)
	local cover = add(m, r.leftArm, disc(5.4, 0.22, canopy, red))
	cover.Transparency = 0.05
	add(m, r.leftArm, disc(1.4, 0.3, canopy * at(0, 0.2, 0), rgb(150, 24, 30)))
	for index = 1, 8 do
		local yaw = index * 45
		add(
			m,
			r.leftArm,
			block(Vector3.new(0.07, 0.07, 2.7), canopy * at(0, -0.14, 0, 0, yaw, 0) * at(0, 0, -1.35), rgb(70, 40, 30))
		)
	end
	-- foxfire circling her
	for index, offset in { at(2.2, 1.2, 0.6), at(-2.3, 0.4, 0.8), at(1.8, -1.2, 1.1), at(-1.6, 2.0, 0.9) } do
		local orb = add(m, r.torso, ball(0.55, offset, foxfire, NEON))
		orb.Transparency = 0.15
		if index == 1 then
			light(orb, foxfire, 16, 1.4)
		end
	end
end

LOOKS.RobeTaker = function(r)
	local m = r.model
	local skin = rgb(196, 184, 160)
	local robe = rgb(62, 52, 66)
	local hair = rgb(222, 220, 212)
	paint(r.head, skin)
	paint(r.rightArm, skin)
	paint(r.leftArm, skin)
	paint(r.torso, robe)
	paint(r.rightLeg, robe)
	paint(r.leftLeg, robe)
	-- tattered robes and a hump
	add(m, r.torso, block(Vector3.new(2.45, 2.1, 1.6), at(0, -1.9, 0), robe))
	for index = -2, 2 do
		add(m, r.torso, {
			wedge = true,
			size = Vector3.new(0.45, 0.6, 1.6),
			at = at(index * 0.5, -3.25, 0, 0, 0, 180),
			color = robe,
		})
	end
	add(m, r.torso, ball(1.9, at(0, 0.7, 0.55), robe))
	-- the robes of the dead, draped over her back
	local clothColors = { rgb(150, 40, 40), rgb(60, 90, 140), rgb(214, 204, 176) }
	local clothPlaces = { at(0.1, 0.9, 0.95, 20, 0, 10), at(-0.2, 0.4, 1.05, 10, 0, -14), at(0.3, -0.2, 1.0, 4, 0, 6) }
	for index, place in clothPlaces do
		add(m, r.torso, block(Vector3.new(2.0 - index * 0.2, 1.5, 0.22), place, clothColors[index]))
	end
	-- wild white hair
	for index = 1, 10 do
		local yaw = (index - 5.5) * 24
		add(
			m,
			r.head,
			block(
				Vector3.new(0.16, 1.8, 0.16),
				at(0, 0.2, 0, 0, yaw, 0) * at(0, -0.2, 0.55, 14, 0, (index % 3 - 1) * 10),
				hair
			)
		)
	end
	add(m, r.head, block(Vector3.new(2.05, 0.4, 1.1), at(0, 0.5, 0.02), hair))
	-- face: yellow eyes, a long nose, a wide mouth
	for _, side in { -1, 1 } do
		add(m, r.head, block(Vector3.new(0.24, 0.12, 0.06), at(side * 0.36, 0.12, -0.52), rgb(255, 210, 60), NEON))
	end
	add(
		m,
		r.head,
		{ wedge = true, size = Vector3.new(0.22, 0.45, 0.3), at = at(0, -0.05, -0.62, 0, 180, 0), color = skin }
	)
	add(m, r.head, block(Vector3.new(0.7, 0.07, 0.05), at(0, -0.32, -0.52), rgb(60, 24, 30)))
	-- prayer beads across the chest
	for index = 0, 7 do
		add(m, r.torso, ball(0.24, at(-0.85 + index * 0.25, 0.75 - index * 0.2, -0.6), rgb(40, 30, 30)))
	end
	-- long fingers
	for _, arm in { r.rightArm, r.leftArm } do
		for index = -1, 2 do
			add(m, arm, block(Vector3.new(0.1, 0.9, 0.1), at(index * 0.22 - 0.1, -1.4, -0.2, -15, 0, 0), skin))
		end
	end
	-- the branch she hangs robes on
	local hand = at(0, -1.1, -0.1)
	add(m, r.rightArm, rod(6.5, 0.3, hand * at(0, 2.2, 0), rgb(70, 52, 40), WOOD))
	for _, twig in { at(0.5, 4.2, 0, 0, 0, -40), at(-0.4, 3.4, 0, 0, 0, 45), at(0.3, 5.0, 0, 0, 0, -20) } do
		add(m, r.rightArm, rod(1.4, 0.14, hand * twig, rgb(70, 52, 40), WOOD))
	end
	add(m, r.rightArm, block(Vector3.new(0.9, 1.1, 0.1), hand * at(0.9, 3.4, 0), rgb(232, 226, 210)))
	add(m, r.rightArm, block(Vector3.new(0.8, 1.0, 0.1), hand * at(-0.8, 2.6, 0), rgb(120, 40, 50)))
end

---------------------------------------------------------------------------------------------------
-- Public

-- A finished creature at the origin: rig, dressing, scale, humanoid settings and attributes.
function Creatures.build(spec: Creature): (Model, Humanoid, BasePart)
	local skin = Phases.color(spec.phase):Lerp(Color3.fromRGB(150, 140, 126), 0.6)
	local r = buildRig(skin)
	local look = LOOKS[spec.id]
	if look then
		look(r)
	end
	local model = r.model
	model.Name = spec.name
	if spec.scale ~= 1 then
		model:ScaleTo(spec.scale)
	end

	local humanoid = r.humanoid
	humanoid.DisplayName = spec.name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = spec.health
	humanoid.Health = spec.health
	humanoid.WalkSpeed = spec.walkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

	model:SetAttribute("Phase", spec.phase)
	model:SetAttribute("Creature", spec.id)
	return model, humanoid, r.root
end

-- The floating plate over an ordinary creature (wardens get the field boss bar instead).
function Creatures.addNameplate(model: Model, root: BasePart, humanoid: Humanoid, spec: Creature)
	local info = Phases.INFO[spec.phase]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Size = UDim2.fromOffset(190, 58)
	billboard.StudsOffset = Vector3.new(0, 3.6 * spec.scale, 0)
	billboard.MaxDistance = 90
	billboard.LightInfluence = 0
	billboard.Adornee = root
	billboard.Parent = model

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 26)
	title.Font = Enum.Font.BuilderSansExtraBold
	title.TextSize = 19
	title.TextColor3 = Color3.fromRGB(255, 226, 214)
	title.TextStrokeTransparency = 0.4
	title.Text = `{info.glyph}  {spec.name}`
	title.Parent = billboard

	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(20, 32)
	bar.Size = UDim2.new(1, -40, 0, 10)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	bar.BorderSizePixel = 0
	bar.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(214, 60, 52)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	humanoid.HealthChanged:Connect(function(health)
		fill.Size = UDim2.fromScale(math.clamp(health / math.max(humanoid.MaxHealth, 1), 0, 1), 1)
	end)
end

return Creatures
