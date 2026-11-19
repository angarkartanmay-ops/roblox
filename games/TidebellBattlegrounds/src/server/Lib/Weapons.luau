--!strict
-- Builds each champion's weapon, school sash and element aura from plain parts (no assets),
-- welded to the character's hands. Each weapon carries disabled "SwingTrail" trails that
-- clients switch on during attacks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

type FighterSpec = Types.FighterSpec

local Weapons = {}

local ALONG_BLADE = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's X axis to -Z (the blade direction)

type Kit = {
	folder: Model,
	color: Color3,
	accent: Color3,
}

local function makePart(kit: Kit, hand: BasePart, grip: CFrame, offset: CFrame, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = "WeaponPart"
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.CFrame = hand.CFrame * grip * offset
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = p
	weld.C0 = grip * offset
	weld.Parent = p
	p.Parent = kit.folder
	return p
end

local function trail(kit: Kit, hand: BasePart, grip: CFrame, baseZ: number, tipZ: number, color: Color3)
	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.CFrame = grip * CFrame.new(0, 0, baseZ)
	base.Parent = hand
	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.CFrame = grip * CFrame.new(0, 0, tipZ)
	tip.Parent = hand
	local swing = Instance.new("Trail")
	swing.Name = "SwingTrail"
	swing.Attachment0 = base
	swing.Attachment1 = tip
	swing.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	swing.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	swing.LightEmission = 0.8
	swing.Lifetime = 0.18
	swing.MinLength = 0.05
	swing.FaceCamera = true
	swing.Enabled = false
	swing.Parent = kit.folder
end

local function cylinder(length: number, diameter: number): Vector3
	return Vector3.new(length, diameter, diameter)
end

local BUILDERS: { [string]: (Kit, BasePart, BasePart?, CFrame, CFrame) -> () } = {}

BUILDERS.StoneMaul = function(kit, right, _left, grip, _leftGrip)
	makePart(kit, right, grip, CFrame.new(0, 0, -1.5) * ALONG_BLADE, {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(4.8, 0.38),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(82, 56, 38),
	})
	makePart(kit, right, grip, CFrame.new(0, 0, -4.2), {
		Size = Vector3.new(2.6, 1.5, 1.5),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(102, 94, 88),
	})
	for _, x in { -0.8, 0.8 } do
		makePart(kit, right, grip, CFrame.new(x, 0, -4.2), {
			Size = Vector3.new(0.3, 1.6, 1.6),
			Material = Enum.Material.Neon,
			Color = kit.color,
		})
	end
	trail(kit, right, grip, -2.2, -4.9, kit.color)
end

BUILDERS.Naginata = function(kit, right, _left, grip, _leftGrip)
	makePart(kit, right, grip, CFrame.new(0, 0, -1) * ALONG_BLADE, {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(6.8, 0.24),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(62, 26, 22),
	})
	makePart(kit, right, grip, CFrame.new(0, 0, -4.4) * ALONG_BLADE, {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(0.4, 0.34),
		Material = Enum.Material.Neon,
		Color = kit.color,
	})
	local bend = CFrame.Angles(math.rad(-6), 0, 0)
	makePart(kit, right, grip, CFrame.new(0, 0.1, -5.5) * bend, {
		Size = Vector3.new(0.12, 0.55, 2.2),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(198, 219, 228),
	})
	makePart(kit, right, grip, CFrame.new(0, 0.39, -5.5) * bend, {
		Size = Vector3.new(0.13, 0.1, 2.1),
		Material = Enum.Material.Neon,
		Color = kit.color,
	})
	trail(kit, right, grip, -3.8, -6.6, kit.color)
end

local function fan(kit: Kit, hand: BasePart, grip: CFrame)
	makePart(kit, hand, grip, CFrame.new(0, 0, -0.15) * ALONG_BLADE, {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(0.6, 0.18),
		Color = Color3.fromRGB(28, 22, 22),
	})
	makePart(kit, hand, grip, CFrame.new(0, 0, -1.05), {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(0.1, 2.1),
		Material = Enum.Material.Fabric,
		Color = Color3.fromRGB(160, 22, 18),
	})
	makePart(kit, hand, grip, CFrame.new(0, 0, -1.05), {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(0.04, 2.32),
		Material = Enum.Material.Neon,
		Color = kit.accent,
	})
	trail(kit, hand, grip, -0.3, -2.1, kit.color)
end

BUILDERS.WarFans = function(kit, right, left, grip, leftGrip)
	fan(kit, right, grip)
	if left then
		fan(kit, left, leftGrip)
	end
end

local function sickle(kit: Kit, hand: BasePart, grip: CFrame, side: number): Attachment
	makePart(kit, hand, grip, CFrame.new(0, 0, -0.5) * ALONG_BLADE, {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(1.4, 0.2),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(90, 64, 46),
	})
	makePart(kit, hand, grip, CFrame.new(0.5 * side, 0, -1.2), {
		Size = Vector3.new(1.2, 0.26, 0.08),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(190, 204, 210),
	})
	makePart(kit, hand, grip, CFrame.new(0.5 * side, 0.13, -1.2), {
		Size = Vector3.new(1.15, 0.08, 0.1),
		Material = Enum.Material.Neon,
		Color = kit.color,
	})
	trail(kit, hand, grip, -0.6, -1.4, kit.color)
	local chainEnd = Instance.new("Attachment")
	chainEnd.Name = "ChainEnd"
	chainEnd.CFrame = grip * CFrame.new(0, 0, 0.25)
	chainEnd.Parent = hand
	return chainEnd
end

BUILDERS.ChainSickles = function(kit, right, left, grip, leftGrip)
	local rightEnd = sickle(kit, right, grip, 1)
	if not left then
		return
	end
	local leftEnd = sickle(kit, left, leftGrip, -1)
	local chain = Instance.new("Beam")
	chain.Name = "Chain"
	chain.Attachment0 = rightEnd
	chain.Attachment1 = leftEnd
	chain.Width0 = 0.12
	chain.Width1 = 0.12
	chain.Segments = 12
	chain.CurveSize0 = 1.4
	chain.CurveSize1 = -1.4
	chain.Color = ColorSequence.new(Color3.fromRGB(120, 124, 130))
	chain.FaceCamera = true
	chain.LightInfluence = 1
	chain.Parent = kit.folder
end

BUILDERS.RingedStaff = function(kit, right, _left, grip, _leftGrip)
	makePart(kit, right, grip, CFrame.new(0, 0, -0.9) * ALONG_BLADE, {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(6.4, 0.22),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(56, 38, 30),
	})
	makePart(kit, right, grip, CFrame.new(0, 0, -4.4), {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7),
		Material = Enum.Material.Neon,
		Color = kit.color,
	})
	local gold = Color3.fromRGB(216, 178, 90)
	makePart(kit, right, grip, CFrame.new(0, 0, -4.4), {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(0.05, 1.25),
		Material = Enum.Material.Metal,
		Color = gold,
	})
	makePart(kit, right, grip, CFrame.new(0, 0, -4.4) * CFrame.Angles(0, 0, math.rad(90)), {
		Shape = Enum.PartType.Cylinder,
		Size = cylinder(0.05, 1.25),
		Material = Enum.Material.Metal,
		Color = gold,
	})
	makePart(kit, right, grip, CFrame.new(0, 0, -4.95), {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.5, 0.5, 0.5),
		Material = Enum.Material.Metal,
		Color = gold,
	})
	trail(kit, right, grip, -2.8, -4.8, kit.color)
end

local function handFor(character: Model, rigType: Enum.HumanoidRigType, side: string): BasePart?
	local name = if rigType == Enum.HumanoidRigType.R15 then `{side}Hand` else `{side} Arm`
	local found = character:WaitForChild(name, 5)
	return if found and found:IsA("BasePart") then found else nil
end

local function gripFor(hand: BasePart, rigType: Enum.HumanoidRigType): CFrame
	-- Bottom of the hand; the blade points along the hand's -Z (forward while the arm hangs).
	local inset = if rigType == Enum.HumanoidRigType.R15 then 0 else 0.15
	return CFrame.new(0, -hand.Size.Y / 2 + inset, 0)
end

local function addSash(kit: Kit, character: Model, rigType: Enum.HumanoidRigType)
	local waistName = if rigType == Enum.HumanoidRigType.R15 then "LowerTorso" else "Torso"
	local waist = character:FindFirstChild(waistName)
	if not waist or not waist:IsA("BasePart") then
		return
	end
	local y = if rigType == Enum.HumanoidRigType.R15 then 0.05 else -waist.Size.Y / 2 + 0.3
	makePart(kit, waist, CFrame.new(), CFrame.new(0, y, 0), {
		Size = Vector3.new(waist.Size.X + 0.12, 0.45, waist.Size.Z + 0.12),
		Material = Enum.Material.Fabric,
		Color = kit.color,
	})
	makePart(
		kit,
		waist,
		CFrame.new(),
		CFrame.new(0.55, y - 0.65, waist.Size.Z / 2 + 0.08) * CFrame.Angles(math.rad(8), 0, math.rad(-6)),
		{
			Size = Vector3.new(0.45, 1.3, 0.08),
			Material = Enum.Material.Fabric,
			Color = kit.color:Lerp(Color3.new(0, 0, 0), 0.25),
		}
	)
end

local function addAura(root: BasePart, color: Color3)
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "ElementAura"
	aura.Color = ColorSequence.new(color)
	aura.LightEmission = 1
	aura.Rate = 3
	aura.Lifetime = NumberRange.new(1, 1.6)
	aura.Speed = NumberRange.new(1, 2.5)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Acceleration = Vector3.new(0, 3, 0)
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	aura.Parent = root
end

-- Dress a freshly spawned character as `fighter`.
function Weapons.equip(character: Model, humanoid: Humanoid, fighter: FighterSpec)
	local rigType = humanoid.RigType
	local right = handFor(character, rigType, "Right")
	if not right or character.Parent == nil then
		return
	end
	local left = handFor(character, rigType, "Left")
	local folder = Instance.new("Model")
	folder.Name = "Weapon"
	folder:SetAttribute("Weapon", fighter.weapon)
	local kit: Kit = {
		folder = folder,
		color = Color3.new(fighter.color[1], fighter.color[2], fighter.color[3]),
		accent = Color3.new(fighter.accent[1], fighter.accent[2], fighter.accent[3]),
	}
	folder.Parent = character

	local builder = BUILDERS[fighter.weapon]
	if builder then
		local leftGrip = if left then gripFor(left, rigType) else CFrame.new()
		builder(kit, right, left, gripFor(right, rigType), leftGrip)
	else
		warn(`[Weapons] no builder for {fighter.weapon}`)
	end
	addSash(kit, character, rigType)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		addAura(root, kit.color)
	end
end

return Weapons
