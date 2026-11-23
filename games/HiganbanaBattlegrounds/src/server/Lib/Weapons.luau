--!strict
-- Placeholder kit for each fighter, built from plain parts welded to the rig: the held weapon,
-- the worn kit (hats, drum, belts, coins), a phase-coloured aura and the Lily Crown. The art
-- stage swaps these for meshes; the names here (Weapon, Kit, LilyCrown, SwingTrail) are what the
-- client and that stage look for.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Phases = require(ReplicatedStorage.Shared.Phases)
local Types = require(ReplicatedStorage.Shared.Types)

type FighterSpec = Types.FighterSpec

local Weapons = {}

local ALONG = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's X axis to -Z (along the weapon)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's X axis to +Y

local WOOD = Color3.fromRGB(122, 86, 56)
local DARK_WOOD = Color3.fromRGB(70, 44, 30)
local STEEL = Color3.fromRGB(196, 204, 212)
local IRON = Color3.fromRGB(70, 72, 78)
local STONE = Color3.fromRGB(128, 120, 110)
local STRAW = Color3.fromRGB(206, 178, 116)
local PAPER = Color3.fromRGB(240, 236, 226)
local BRONZE = Color3.fromRGB(176, 128, 66)
local LACQUER = Color3.fromRGB(26, 22, 24)
local LILY = Color3.fromRGB(214, 34, 46)
-- Cloth is smooth plastic, not Fabric: Fabric takes its look from a material texture fetched from
-- Roblox's CDN, and where that fetch fails (a TLS-inspecting network, measured) it renders near-black.
local CLOTH = Enum.Material.SmoothPlastic

type Rig = {
	character: Model,
	r15: boolean,
	rightHand: BasePart,
	leftHand: BasePart?,
	rightArm: BasePart?, -- lower arm (R15) or arm (R6)
	leftArm: BasePart?,
	chest: BasePart?,
	waist: BasePart?,
	head: BasePart?,
}

type Kit = {
	folder: Model,
	color: Color3,
	accent: Color3,
}

local function makePart(kit: Kit, anchor: BasePart, offset: CFrame, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Name = "KitPart"
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
	p.CFrame = anchor.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = anchor
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = kit.folder
	return p
end

local function rod(length: number, diameter: number): Vector3
	return Vector3.new(length, diameter, diameter)
end

-- A disabled trail along a held weapon (clients enable it during attacks).
local function trail(kit: Kit, hand: BasePart, grip: CFrame, baseZ: number, tipZ: number)
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
	swing.Color = ColorSequence.new(Color3.new(1, 1, 1), kit.color)
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

local function gripOf(hand: BasePart, r15: boolean): CFrame
	-- Bottom of the hand; the weapon points along the hand's -Z (forward while the arm hangs).
	return CFrame.new(0, -hand.Size.Y / 2 + (if r15 then 0 else 0.15), 0)
end

---------------------------------------------------------------------------------------------------
-- Held weapons

local BUILDERS: { [string]: (Kit, Rig) -> () } = {}

BUILDERS.Wagasa = function(kit, rig)
	local hand = rig.rightHand
	local grip = gripOf(hand, rig.r15)
	makePart(kit, hand, grip * CFrame.new(0, 0, -1.6) * ALONG, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(4.6, 0.2),
		Material = Enum.Material.Wood,
		Color = DARK_WOOD,
	})
	makePart(kit, hand, grip * CFrame.new(0, 0, 0.3) * ALONG, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(0.9, 0.3),
		Material = CLOTH,
		Color = kit.accent,
	})
	-- the furled oil-paper canopy
	for index, diameter in { 0.55, 0.85, 1.05, 0.85, 0.55 } do
		makePart(kit, hand, grip * CFrame.new(0, 0, -1.6 - index * 0.55) * ALONG, {
			Shape = Enum.PartType.Cylinder,
			Size = rod(0.6, diameter),
			Material = CLOTH,
			Color = if index % 2 == 0 then kit.accent else kit.color,
		})
	end
	makePart(kit, hand, grip * CFrame.new(0, 0, -5.1) * ALONG, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(0.7, 0.16),
		Material = Enum.Material.Metal,
		Color = STEEL,
	})
	trail(kit, hand, grip, -1.2, -5.3)
end

BUILDERS.TaikoBachi = function(kit, rig)
	local hands: { BasePart } = { rig.rightHand }
	if rig.leftHand then
		table.insert(hands, rig.leftHand)
	end
	for _, hand in hands do
		do
			local grip = gripOf(hand, rig.r15)
			makePart(kit, hand, grip * CFrame.new(0, 0, -0.9) * ALONG, {
				Shape = Enum.PartType.Cylinder,
				Size = rod(2.4, 0.22),
				Material = Enum.Material.Wood,
				Color = WOOD,
			})
			makePart(kit, hand, grip * CFrame.new(0, 0, -2.05), {
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 0.3,
				Material = Enum.Material.Neon,
				Color = kit.color,
			})
			trail(kit, hand, grip, -0.6, -2.1)
		end
	end
end

BUILDERS.StoneBracer = function(kit, rig)
	local arms: { BasePart } = {}
	for _, arm in { rig.rightArm, rig.leftArm } :: { BasePart? } do
		if arm then
			table.insert(arms, arm)
		end
	end
	for _, arm in arms do
		do
			makePart(kit, arm, CFrame.new(0, -0.05, 0), {
				Size = Vector3.new(arm.Size.X + 0.3, arm.Size.Y * 0.8, arm.Size.Z + 0.3),
				Material = Enum.Material.Slate,
				Color = STONE,
			})
			makePart(kit, arm, CFrame.new(0, arm.Size.Y * 0.3, 0), {
				Size = Vector3.new(arm.Size.X + 0.36, 0.14, arm.Size.Z + 0.36),
				Material = Enum.Material.Neon,
				Color = kit.color,
			})
		end
	end
	local hand = rig.rightHand
	trail(kit, hand, gripOf(hand, rig.r15), 0.2, -0.6)
end

BUILDERS.Jitte = function(kit, rig)
	local hand = rig.rightHand
	local grip = gripOf(hand, rig.r15)
	makePart(kit, hand, grip * CFrame.new(0, 0, 0.15) * ALONG, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(0.8, 0.26),
		Material = CLOTH,
		Color = kit.accent,
	})
	makePart(kit, hand, grip * CFrame.new(0, 0, -1.3) * ALONG, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(2.6, 0.18),
		Material = Enum.Material.Metal,
		Color = STEEL,
	})
	-- the side hook that catches blades
	makePart(kit, hand, grip * CFrame.new(0.22, 0, -0.75), {
		Size = Vector3.new(0.12, 0.12, 0.7),
		Material = Enum.Material.Metal,
		Color = STEEL,
	})
	makePart(kit, hand, grip * CFrame.new(0.32, 0, -1.05), {
		Size = Vector3.new(0.12, 0.12, 0.2),
		Material = Enum.Material.Metal,
		Color = STEEL,
	})
	trail(kit, hand, grip, -0.4, -2.6)
end

BUILDERS.FerryOar = function(kit, rig)
	local hand = rig.rightHand
	local grip = gripOf(hand, rig.r15)
	makePart(kit, hand, grip * CFrame.new(0, 0, -2.4) * ALONG, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(8.2, 0.26),
		Material = Enum.Material.Wood,
		Color = WOOD,
	})
	makePart(kit, hand, grip * CFrame.new(0, 0, -7.4), {
		Size = Vector3.new(0.22, 1.3, 2.4),
		Material = Enum.Material.Wood,
		Color = DARK_WOOD,
	})
	makePart(kit, hand, grip * CFrame.new(0, 0, -6.1), {
		Size = Vector3.new(0.3, 0.3, 0.25),
		Material = Enum.Material.Neon,
		Color = kit.color,
	})
	trail(kit, hand, grip, -5.6, -8.6)
end

---------------------------------------------------------------------------------------------------
-- Worn kit

local WORN: { [string]: (Kit, Rig) -> () } = {}

WORN.BackTaiko = function(kit, rig)
	local chest = rig.chest
	if not chest then
		return
	end
	local back = CFrame.new(0, 0.1, chest.Size.Z / 2 + 0.7) * ALONG
	makePart(kit, chest, back, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(1.2, 2.3),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(150, 60, 40),
	})
	for _, z in { -0.62, 0.62 } do
		makePart(kit, chest, back * CFrame.new(z, 0, 0), {
			Shape = Enum.PartType.Cylinder,
			Size = rod(0.06, 2.1),
			Material = CLOTH,
			Color = PAPER,
		})
	end
	makePart(kit, chest, CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(35)), {
		Size = Vector3.new(0.16, 2.6, chest.Size.Z + 0.12),
		Material = CLOTH,
		Color = PAPER,
	})
end

WORN.RopeBelt = function(kit, rig)
	local waist = rig.waist
	if not waist then
		return
	end
	makePart(kit, waist, CFrame.new(0, 0.1, 0), {
		Size = Vector3.new(waist.Size.X + 0.22, 0.42, waist.Size.Z + 0.22),
		Material = CLOTH,
		Color = PAPER,
	})
	-- zig-zag paper streamers at the front
	for index, x in { -0.55, 0, 0.55 } do
		local tilt = if index % 2 == 0 then 10 else -10
		makePart(kit, waist, CFrame.new(x, -0.45, -waist.Size.Z / 2 - 0.14) * CFrame.Angles(0, 0, math.rad(tilt)), {
			Size = Vector3.new(0.28, 0.7, 0.05),
			Material = CLOTH,
			Color = PAPER,
		})
	end
end

WORN.WeightedChain = function(kit, rig)
	local waist = rig.waist
	if not waist then
		return
	end
	makePart(kit, waist, CFrame.new(waist.Size.X / 2 + 0.2, -0.2, 0) * UPRIGHT, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(0.5, 0.75),
		Material = Enum.Material.Metal,
		Color = IRON,
	})
	makePart(kit, waist, CFrame.new(waist.Size.X / 2 + 0.25, -0.75, 0), {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.38,
		Material = Enum.Material.Metal,
		Color = IRON,
	})
end

WORN.Jingasa = function(kit, rig)
	local head = rig.head
	if not head then
		return
	end
	makePart(kit, head, CFrame.new(0, head.Size.Y / 2 + 0.12, 0) * UPRIGHT, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(0.18, 3),
		Material = Enum.Material.SmoothPlastic,
		Color = LACQUER,
	})
	makePart(kit, head, CFrame.new(0, head.Size.Y / 2 + 0.26, 0) * UPRIGHT, {
		Shape = Enum.PartType.Cylinder,
		Size = rod(0.14, 1.2),
		Material = Enum.Material.SmoothPlastic,
		Color = LACQUER,
	})
	makePart(kit, head, CFrame.new(0, head.Size.Y / 2 + 0.2, -0.75), {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.3,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(212, 176, 90),
	})
end

WORN.Sugegasa = function(kit, rig)
	local head = rig.head
	if not head then
		return
	end
	for index, diameter in { 3.8, 2.7, 1.6, 0.6 } do
		makePart(kit, head, CFrame.new(0, head.Size.Y / 2 + 0.06 + index * 0.16, 0) * UPRIGHT, {
			Shape = Enum.PartType.Cylinder,
			Size = rod(0.18, diameter),
			Material = CLOTH,
			Color = if index % 2 == 0 then STRAW:Lerp(Color3.new(0, 0, 0), 0.12) else STRAW,
		})
	end
end

WORN.CoinString = function(kit, rig)
	local waist = rig.waist
	if not waist then
		return
	end
	for index = 1, 6 do
		makePart(kit, waist, CFrame.new(-waist.Size.X / 2 - 0.12, -0.15 - index * 0.17, -0.1) * ALONG, {
			Shape = Enum.PartType.Cylinder,
			Size = rod(0.06, 0.34),
			Material = Enum.Material.Metal,
			Color = BRONZE,
		})
	end
end

---------------------------------------------------------------------------------------------------

local function part(character: Model, r15Name: string, r6Name: string): BasePart?
	local found = character:FindFirstChild(r15Name) or character:FindFirstChild(r6Name)
	return if found and found:IsA("BasePart") then found else nil
end

local function rigOf(character: Model, humanoid: Humanoid): Rig?
	local r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local rightName = if r15 then "RightHand" else "Right Arm"
	local right = character:WaitForChild(rightName, 5)
	if not right or not right:IsA("BasePart") then
		return nil
	end
	return {
		character = character,
		r15 = r15,
		rightHand = right,
		leftHand = part(character, "LeftHand", "Left Arm"),
		rightArm = part(character, "RightLowerArm", "Right Arm"),
		leftArm = part(character, "LeftLowerArm", "Left Arm"),
		chest = part(character, "UpperTorso", "Torso"),
		waist = part(character, "LowerTorso", "Torso"),
		head = part(character, "Head", "Head"),
	}
end

local function addAura(root: BasePart, color: Color3)
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "PhaseAura"
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
	local rig = rigOf(character, humanoid)
	if not rig or character.Parent == nil then
		return
	end
	local color = Color3.new(fighter.color[1], fighter.color[2], fighter.color[3])
	local accent = Color3.new(fighter.accent[1], fighter.accent[2], fighter.accent[3])

	local weapon = Instance.new("Model")
	weapon.Name = "Weapon"
	weapon:SetAttribute("Weapon", fighter.weapon)
	weapon.Parent = character
	local builder = BUILDERS[fighter.weapon]
	if builder then
		builder({ folder = weapon, color = color, accent = accent }, rig)
	else
		warn(`[Weapons] no builder for {fighter.weapon}`)
	end

	local kit = Instance.new("Model")
	kit.Name = "Kit"
	kit.Parent = character
	for _, item in fighter.worn do
		local wear = WORN[item]
		if wear then
			wear({ folder = kit, color = color, accent = accent }, rig)
		else
			warn(`[Weapons] no builder for worn {item}`)
		end
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		addAura(root, Phases.color(fighter.phase))
	end
end

-- The Lily Crown: a ring of red spider-lily petals worn by the Elder's top damage dealer.
function Weapons.crown(character: Model)
	if character:FindFirstChild("LilyCrown") then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local crown = Instance.new("Model")
	crown.Name = "LilyCrown"
	crown.Parent = character
	local kit: Kit = { folder = crown, color = LILY, accent = LILY }
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		makePart(
			kit,
			head,
			CFrame.new(0, head.Size.Y / 2 + 0.25, 0)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, -0.62)
				* CFrame.Angles(math.rad(-35), 0, 0),
			{ Size = Vector3.new(0.12, 0.7, 0.05), Material = Enum.Material.Neon, Color = LILY }
		)
	end
	local light = Instance.new("PointLight")
	light.Color = LILY
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = head
	light.Name = "LilyCrownLight"
end

function Weapons.uncrown(character: Model)
	local crown = character:FindFirstChild("LilyCrown")
	if crown then
		crown:Destroy()
	end
	local head = character:FindFirstChild("Head")
	local light = head and head:FindFirstChild("LilyCrownLight")
	if light then
		light:Destroy()
	end
end

return Weapons
