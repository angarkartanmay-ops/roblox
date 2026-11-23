--!strict
-- Renders every combat event the server reports: move animations and effects (MoveFx), mid-move
-- moments (PhaseFx), hits (HitFx), projectiles (ProjectileFx) and the Thirsting Elder (ElderFx).
-- Also draws the state auras the server publishes as model attributes (burning, rooted, mending,
-- ultimate ready, ...) and fades fighters standing in Rokumon's Mist.
-- The local player's own moves are predicted by InputController and not replayed on echo.
-- Effects are procedural placeholders built from parts and stock particles; section 4 replaces them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Poses = require(ReplicatedStorage.Shared.Poses)
local Types = require(ReplicatedStorage.Shared.Types)
local Effects = require("../Lib/Effects")
local Remotes = require("../Lib/Remotes")
local AnimationController = require("./AnimationController")
local CameraController = require("./CameraController")
local SoundController = require("./SoundController")

type Context = {
	model: Model?,
	fighter: Types.FighterSpec?,
	move: Types.MoveSpec?,
	color: Color3,
	accent: Color3,
	facing: Vector3,
	start: number,
	origin: CFrame,
	point: Vector3?,
	isLocal: boolean,
	moveId: string,
}

local VfxController = {}

local localPlayer = Players.LocalPlayer
local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)
local LILY = Color3.fromRGB(194, 31, 46)
local BARK = Color3.fromRGB(92, 64, 44)
local LEAF = Color3.fromRGB(74, 168, 96)
local EMBER = Color3.fromRGB(255, 150, 60)
local FLAME = Color3.fromRGB(228, 72, 40)
local ROCK = Color3.fromRGB(122, 104, 84)
local DUST = Color3.fromRGB(186, 170, 146)
local SALT = Color3.fromRGB(246, 244, 236)
local STRAW = Color3.fromRGB(196, 164, 98)
local IRON = Color3.fromRGB(150, 156, 166)
local STEEL = Color3.fromRGB(226, 230, 236)
local RIVER = Color3.fromRGB(70, 96, 190)
local FOAM = Color3.fromRGB(196, 214, 240)
local MIST = Color3.fromRGB(206, 214, 226)
local COIN = Color3.fromRGB(201, 154, 59)
local GOLD = Color3.fromRGB(255, 205, 110)
local SAP = Color3.fromRGB(224, 150, 40)
local KI = Color3.fromRGB(224, 48, 62)
local RED = Color3.fromRGB(235, 52, 52)
local BLOCK_BLUE = Color3.fromRGB(150, 210, 255)
-- Leaves and straw are smooth plastic in their own colour, not Grass or Fabric: those take their look
-- from material textures fetched from Roblox's CDN, and where that fetch fails (measured) they render
-- as flat near-black or dull grey.
local SOFT = Enum.Material.SmoothPlastic

local predicted: { [string]: number } = {}
local confirmListeners: { (string) -> () } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(vector: Vector3): Vector3
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 1e-3 then flattened.Unit else Vector3.new(0, 0, -1)
end

local function rootOf(model: Model?): BasePart?
	if not model or model.Parent == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function partOf(model: Model?, name: string): BasePart?
	if not model or model.Parent == nil then
		return nil
	end
	local part = model:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function handOf(model: Model?): Vector3?
	local hand = partOf(model, "RightHand") or partOf(model, "Right Arm")
	if hand then
		return hand.Position
	end
	local root = rootOf(model)
	return if root then root.Position else nil
end

local function phaseOf(model: Model?): string?
	if not model then
		return nil
	end
	local phase = model:GetAttribute("Phase")
	return if type(phase) == "string" then phase else nil
end

local function phaseColor(model: Model?): Color3
	local phase = phaseOf(model)
	return if phase then Phases.color(phase) else WHITE
end

local function asModel(value: any): Model?
	if typeof(value) == "Instance" and (value :: Instance):IsA("Model") then
		return value :: Model
	end
	return nil
end

-- Run `callback` at `t` seconds after the move started (server clock).
local function at(ctx: Context, t: number, callback: () -> ())
	local delay = ctx.start + t - now()
	if delay <= 0 then
		task.spawn(callback)
	else
		task.delay(delay, callback)
	end
end

local function near(position: Vector3, radius: number): boolean
	local root = rootOf(localPlayer.Character)
	return root ~= nil and (root.Position - position).Magnitude <= radius
end

local function predictionKey(moveId: string): string
	return if Fighters.parseM1(moveId) then "M1" else moveId
end

local function param(ctx: Context, name: string, default: number): number
	local move = ctx.move
	local params = if move then move.params else nil
	local value = if params then params[name] else nil
	return if value ~= nil then value else default
end

local function contextFor(
	model: Model?,
	fighterId: string?,
	moveId: string,
	start: number,
	facing: Vector3,
	extra: any
): Context
	local fighter = Fighters.get(fighterId)
	local root = rootOf(model)
	local direction = flat(facing)
	local point: Vector3? = nil
	if type(extra) == "table" and typeof(extra.point) == "Vector3" then
		point = extra.point
	end
	local color = if fighter then Phases.color(fighter.phase) else phaseColor(model)
	local accent = if fighter then Color3.new(fighter.accent[1], fighter.accent[2], fighter.accent[3]) else WHITE
	return {
		model = model,
		fighter = fighter,
		move = if fighter then Fighters.findMove(fighter, moveId) else nil,
		color = color,
		accent = accent,
		facing = direction,
		start = start,
		origin = if root then CFrame.lookAt(root.Position, root.Position + direction) else CFrame.new(),
		point = point,
		isLocal = model ~= nil and model == localPlayer.Character,
		moveId = moveId,
	}
end

-- The caster's current frame facing the cast direction (they may have moved since the cast).
local function frameOf(ctx: Context): CFrame?
	local root = rootOf(ctx.model)
	if not root then
		return nil
	end
	return CFrame.lookAt(root.Position, root.Position + ctx.facing)
end

local function groundOf(ctx: Context): Vector3?
	local root = rootOf(ctx.model)
	return if root then Effects.ground(root.Position, 10) else nil
end

---------------------------------------------------------------------------------------------------
-- Building blocks

-- A thin glowing bar from a to b that fades out.
local function line(a: Vector3, b: Vector3, color: Color3, width: number, duration: number, material: Enum.Material?)
	local length = math.max((b - a).Magnitude, 0.1)
	local bar = Effects.part({
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Material = material or Enum.Material.Neon,
	})
	Effects.tween(bar, duration, { Transparency = 1, Size = Vector3.new(width * 0.3, width * 0.3, length) })
	Effects.clean(bar, duration + 0.05)
end

-- A bar that follows two moving points until `duration` passes or either end disappears.
local function tether(
	getA: () -> Vector3?,
	getB: () -> Vector3?,
	color: Color3,
	width: number,
	duration: number,
	material: Enum.Material?
): Part
	local bar =
		Effects.part({ Size = Vector3.new(width, width, 1), Color = color, Material = material or Enum.Material.Neon })
	local ends = os.clock() + duration
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local a = getA()
		local b = getB()
		if os.clock() > ends or a == nil or b == nil or bar.Parent == nil then
			connection:Disconnect()
			bar:Destroy()
			return
		end
		local length = math.max((b - a).Magnitude, 0.1)
		bar.Size = Vector3.new(width, width, length)
		bar.CFrame = CFrame.lookAt((a + b) / 2, b)
	end)
	return bar
end

-- A part welded to a character so it follows it (a canopy, a shield, a ghost boat).
local function attached(model: Model?, props: { [string]: any }, offset: CFrame, duration: number): Part?
	local root = rootOf(model)
	if not root then
		return nil
	end
	local piece = Effects.part(props)
	piece.Anchored = false
	piece.Massless = true
	piece.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = piece
	weld.Parent = piece
	Effects.clean(piece, duration)
	return piece
end

-- Wedges bursting out of the ground: roots, stone, iron stakes.
local function spikes(
	center: Vector3,
	radius: number,
	count: number,
	height: number,
	color: Color3,
	material: Enum.Material,
	hold: number
)
	local rng = Random.new()
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0, radius)
		local base = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local tall = height * rng:NextNumber(0.6, 1.2)
		local width = rng:NextNumber(0.6, 1.4)
		local tilt = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4))
		local spike = Effects.part({
			Size = Vector3.new(width, 0.2, width),
			CFrame = CFrame.new(base) * tilt,
			Color = color,
			Material = material,
		})
		Effects.tween(
			spike,
			0.12,
			{ Size = Vector3.new(width, tall, width), CFrame = CFrame.new(base) * tilt * CFrame.new(0, tall / 2, 0) },
			Enum.EasingStyle.Back
		)
		task.delay(hold, function()
			if spike.Parent then
				Effects.tween(spike, 0.3, { Size = Vector3.new(width * 0.4, 0.2, width * 0.4), Transparency = 1 })
			end
		end)
		Effects.clean(spike, hold + 0.35)
	end
end

-- A ground circle filling up over `duration` (an attack's tell).
local function areaTelegraph(position: Vector3, radius: number, duration: number, color: Color3)
	local ground = CFrame.new(position + UP * 0.15) * CFrame.Angles(0, 0, math.rad(90))
	local area = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = ground,
		Color = color,
		Transparency = 0.8,
	})
	local fill = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.5, 0.5),
		CFrame = ground,
		Color = color,
		Transparency = 0.5,
	})
	Effects.tween(fill, duration, { Size = Vector3.new(0.12, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	Effects.clean(area, duration + 0.05)
	Effects.clean(fill, duration + 0.05)
	Effects.ring(CFrame.new(position + UP * 0.3), color, radius, radius, duration, 0.5, 28, 0.2)
end

-- A rectangle on the ground from `position` along `direction` (a line attack's tell).
local function laneTelegraph(
	position: Vector3,
	direction: Vector3,
	length: number,
	width: number,
	duration: number,
	color: Color3
)
	local base = CFrame.lookAt(position + UP * 0.2, position + UP * 0.2 + flat(direction))
	local lane = Effects.part({
		Size = Vector3.new(width, 0.1, length),
		CFrame = base * CFrame.new(0, 0, -length / 2),
		Color = color,
		Transparency = 0.75,
	})
	local fill = Effects.part({
		Size = Vector3.new(width, 0.12, 0.5),
		CFrame = base * CFrame.new(0, 0, -0.25),
		Color = color,
		Transparency = 0.45,
	})
	Effects.tween(
		fill,
		duration,
		{ Size = Vector3.new(width, 0.12, length), CFrame = base * CFrame.new(0, 0, -length / 2) },
		Enum.EasingStyle.Linear
	)
	Effects.clean(lane, duration + 0.05)
	Effects.clean(fill, duration + 0.05)
end

-- A ring that grows at `speed` studs/s from `startTime` (server clock) until `maxRadius`.
local function growingRing(
	center: Vector3,
	speed: number,
	maxRadius: number,
	startTime: number,
	color: Color3,
	height: number
)
	local count = 48
	local segments: { Part } = {}
	for _ = 1, count do
		table.insert(segments, Effects.part({ Size = Vector3.new(1, height, 0.6), Color = color, Transparency = 0.1 }))
	end
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local radius = (now() - startTime) * speed
		if radius > maxRadius then
			connection:Disconnect()
			for _, segment in segments do
				segment:Destroy()
			end
			return
		end
		local length = math.max(0.4, 2 * math.pi * math.max(radius, 0.5) / count * 1.1)
		for index, segment in segments do
			local angle = index / count * math.pi * 2
			segment.Size = Vector3.new(length, height, 0.6)
			segment.CFrame = CFrame.new(center + UP * (height / 2))
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, -math.max(radius, 0.5))
		end
	end)
end

local function petals(position: Vector3, count: number, speed: number, spread: number?)
	Effects.particles(position, {
		texture = Effects.TEXTURE_SPARK,
		color = LILY,
		count = count,
		speed = speed,
		lifetime = 1.1,
		size = 0.9,
		spread = spread or 180,
		acceleration = Vector3.new(0, -6, 0),
		lightEmission = 0.4,
	})
end

local function smoke(position: Vector3, color: Color3, count: number, speed: number, size: number)
	Effects.particles(position, {
		texture = Effects.TEXTURE_SMOKE,
		color = color,
		count = count,
		speed = speed,
		lifetime = 0.8,
		size = size,
		lightEmission = 0,
	})
end

local function fire(position: Vector3, count: number, speed: number, size: number)
	Effects.particles(position, {
		texture = Effects.TEXTURE_FIRE,
		color = EMBER,
		count = count,
		speed = speed,
		lifetime = 0.6,
		size = size,
		acceleration = Vector3.new(0, 10, 0),
	})
end

local function splash(position: Vector3, count: number, speed: number)
	Effects.particles(position, {
		color = FOAM,
		count = count,
		speed = speed,
		lifetime = 0.7,
		size = 1.1,
		spread = 60,
		acceleration = Vector3.new(0, -40, 0),
	})
end

local function coins(position: Vector3, count: number)
	local rng = Random.new()
	for _ = 1, count do
		local coin = Effects.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, 0.8, 0.8),
			CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
			Color = COIN,
			Material = Enum.Material.Metal,
		})
		local offset = rng:NextUnitVector() * rng:NextNumber(2, 5) + UP * rng:NextNumber(2, 4)
		Effects.tween(coin, 0.5, { CFrame = coin.CFrame + offset, Transparency = 1 }, Enum.EasingStyle.Quad)
		Effects.clean(coin, 0.55)
	end
end

-- A phantom drum: a short cylinder with a pale skin, used by Hibiki's ultimate. A `ghost` drum is
-- nearly clear (one sitting by the viewer's camera would otherwise fill the screen).
local function drum(cframe: CFrame, scale: number, duration: number, ghost: boolean?)
	local body = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4 * scale, 3.2 * scale, 3.2 * scale),
		CFrame = cframe,
		Color = FLAME,
		Material = Enum.Material.SmoothPlastic,
		Transparency = if ghost then 0.88 else 0.35,
	})
	local skin = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.5 * scale, 2.9 * scale, 2.9 * scale),
		CFrame = cframe,
		Color = SALT,
		Transparency = if ghost then 0.92 else 0.45,
	})
	for _, piece in { body, skin } do
		Effects.tween(piece, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Effects.clean(piece, duration + 0.05)
	end
end

---------------------------------------------------------------------------------------------------
-- Universal: M1 chain and dash

local M1_REACH: { [string]: number } = {
	Tsuta = 4.6,
	Hibiki = 4.2,
	Iwao = 4.4,
	Kanemori = 4.4,
	Rokumon = 5.8,
}

local function m1Fx(ctx: Context, index: number)
	local fighter = ctx.fighter
	local style = if fighter then fighter.m1.style else "Tsuta"
	local finisher = index >= Constants.COMBO_HITS
	if ctx.model then
		Effects.swingTrails(ctx.model, 0.35)
	end
	local delay = if fighter then (if finisher then fighter.m1.finisherDelay else fighter.m1.hitDelay) else 0.12
	at(ctx, delay * 0.75, function()
		local base = frameOf(ctx)
		if not base then
			return
		end
		local tilt = if index % 2 == 0 then -28 else 28
		local frame = base * CFrame.new(0, 0.4, -1) * CFrame.Angles(0, 0, math.rad(tilt))
		local radius = M1_REACH[style] or 4.4
		Effects.arc(frame, radius, -75, 75, ctx.color, if finisher then 1.5 else 0.9, if finisher then 0.3 else 0.2, 12)
		if finisher then
			Effects.ring(
				base * CFrame.new(0, 0.5, -radius) * CFrame.Angles(math.rad(90), 0, 0),
				ctx.accent,
				0.5,
				3.5,
				0.3,
				0.4,
				14
			)
			if style == "Hibiki" then
				fire(base.Position + base.LookVector * radius, 8, 10, 1.4)
			elseif style == "Rokumon" then
				splash(base.Position + base.LookVector * radius, 10, 18)
			end
		end
		SoundController.play("swing", base.Position, 1, if finisher then 0.8 else 0.95 + index * 0.06)
	end)
end

local function dashFx(ctx: Context)
	local model = ctx.model
	if model then
		Effects.afterimage(model, ctx.color, 0.35, 0.55)
		at(ctx, 0.12, function()
			if model.Parent then
				Effects.afterimage(model, ctx.color, 0.3, 0.7)
			end
		end)
	end
	local ground = groundOf(ctx)
	if ground then
		Effects.ring(CFrame.new(ground + UP * 0.3), WHITE, 1, 5, 0.3, 0.3, 14)
		smoke(ground + UP * 0.5, DUST, 6, 8, 1.6)
		SoundController.play("whoosh", ground)
	end
end

---------------------------------------------------------------------------------------------------
-- Per-move effects (keys are VfxCatalog.MOVES)

local MOVES: { [string]: (Context) -> () } = {}

-- Tsuta (Wood) -----------------------------------------------------------------------------------

MOVES.RootSnare = function(ctx: Context)
	local point = ctx.point or (ctx.origin.Position + ctx.facing * 18)
	local strikeAt = 0.8
	areaTelegraph(point, 7, math.max(0.1, ctx.start + strikeAt - now()), LEAF)
	at(ctx, strikeAt, function()
		spikes(point, 6, 14, 6, BARK, Enum.Material.Wood, 1.2)
		spikes(point, 5, 6, 4, LEAF, SOFT, 1.2)
		Effects.debris(point, 8, BARK, 6, 5)
		petals(point + UP, 10, 12)
		SoundController.play("heavy", point, 1, 0.8)
		CameraController.shakeAt(point, 0.6, 30)
	end)
end

MOVES.SeedVolley = function(ctx: Context)
	at(ctx, 0.2, function()
		local base = frameOf(ctx)
		if not base then
			return
		end
		local muzzle = base.Position + base.LookVector * 2 + UP * 1
		Effects.particles(muzzle, {
			color = LEAF,
			count = 12,
			speed = 20,
			lifetime = 0.4,
			size = 0.7,
			spread = 35,
			cframe = base,
			forward = true,
		})
		SoundController.play("whoosh", muzzle, 0.8, 1.6)
	end)
end

MOVES.CanopyGuard = function(ctx: Context)
	local openAt = param(ctx, "openAt", 0.1)
	local duration = param(ctx, "duration", 1.4)
	at(ctx, openAt, function()
		local canopy = attached(ctx.model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 9, 9),
			Color = LEAF,
			Transparency = 0.45,
		}, CFrame.new(0, 1, -2.6) * CFrame.Angles(0, math.rad(90), 0), duration)
		local rim = attached(ctx.model, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.35, 9.4, 9.4),
			Color = LILY,
			Transparency = 0.7,
		}, CFrame.new(0, 1, -2.5) * CFrame.Angles(0, math.rad(90), 0), duration)
		for _, piece in { canopy, rim } do
			if piece then
				task.delay(duration - 0.25, function()
					if piece.Parent then
						Effects.tween(piece, 0.25, { Transparency = 1 })
					end
				end)
			end
		end
		local root = rootOf(ctx.model)
		if root then
			SoundController.play("whoosh", root.Position, 0.7, 0.9)
		end
	end)
end

MOVES.Graft = function(ctx: Context)
	at(ctx, param(ctx, "lashAt", 0.2), function()
		local base = frameOf(ctx)
		if base then
			Effects.particles(base.Position + base.LookVector * 2, {
				color = LEAF,
				count = 8,
				speed = 14,
				lifetime = 0.3,
				size = 0.6,
				spread = 25,
				cframe = base,
				forward = true,
			})
		end
	end)
end

MOVES.ThousandRootBloom = function(ctx: Context)
	local ground = groundOf(ctx)
	if ground then
		Effects.vortex(ground, LEAF, 6, 8, 0.8, 3)
		petals(ground + UP * 2, 20, 8)
		SoundController.play("whoosh", ground, 1.2, 0.6)
	end
	if ctx.isLocal then
		CameraController.fovPunch(6, 0.8)
	end
end

-- Hibiki (Fire) ----------------------------------------------------------------------------------

local function drumBeat(position: Vector3, radius: number, color: Color3, strength: number)
	Effects.shockwave(position, color, radius, 0.45)
	Effects.ring(CFrame.new(position + UP * 1.2), EMBER, radius * 0.3, radius, 0.35, 0.6, 24, 0.3)
	fire(position + UP, math.floor(6 * strength), 14 * strength, 1.6)
	SoundController.play("heavy", position, 0.9 * strength, 1.2)
	CameraController.shakeAt(position, 0.4 * strength, radius * 3)
end

MOVES.WarBeat = function(ctx: Context)
	at(ctx, 0.3, function()
		local ground = groundOf(ctx)
		if ground then
			drumBeat(ground, 12, FLAME, 1.2)
			Effects.light(ground + UP * 2, EMBER, 18, 3, 0.4)
		end
	end)
end

MOVES.FireRoll = function(ctx: Context)
	local base = ctx.origin
	local steps = { { 0.35, 7.5 }, { 0.5, 15 }, { 0.65, 22.5 }, { 0.8, 30 } }
	for _, step in steps do
		at(ctx, step[1], function()
			local spot = Effects.ground(base.Position + ctx.facing * step[2], 12)
			Effects.column(spot, 9, 7, FLAME, 0.45, 0.25)
			fire(spot + UP * 2, 10, 16, 2)
			Effects.ring(CFrame.new(spot + UP * 0.3), EMBER, 2, 5, 0.3, 0.5, 16)
			SoundController.play("heavy", spot, 0.6, 1.4)
		end)
	end
end

MOVES.Kakegoe = function(ctx: Context)
	local root = rootOf(ctx.model)
	if root then
		Effects.sphere(root.Position, EMBER, 1, 4, 0.25, 0.4)
	end
end

MOVES.ThunderRoll = function(ctx: Context)
	local times = { 0.3, 0.55, 0.8, 1.05, 1.3 }
	for index, t in times do
		at(ctx, t, function()
			local base = frameOf(ctx)
			if not base then
				return
			end
			local spot = Effects.ground(base.Position + base.LookVector * 6, 10)
			local last = index == #times
			drumBeat(spot, if last then 9 else 6, FLAME, if last then 1.3 else 0.7)
			if last then
				Effects.column(spot, 14, 6, EMBER, 0.4, 0.3)
			end
		end)
	end
end

MOVES.FestivalOfDrums = function(ctx: Context)
	local ground = groundOf(ctx)
	if not ground then
		return
	end
	local center = ground
	-- The ring stands around Hibiki, so for this viewer the drums by the camera are ghosts.
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	for index = 0, 7 do
		local angle = index / 8 * math.pi * 2
		local spot = center + Vector3.new(math.cos(angle) * 10, 3, math.sin(angle) * 10)
		local ghost = eye ~= nil and (eye - spot).Magnitude < 12
		drum(CFrame.lookAt(spot, center + UP * 3) * CFrame.Angles(0, math.rad(90), 0), 1, 2.4, ghost)
	end
	SoundController.play("bell", center, 1.2, 0.6)
	if ctx.isLocal then
		CameraController.fovPunch(8, 0.6)
	end
	for _, t in { 0.6, 0.9, 1.2, 1.5, 1.8 } do
		at(ctx, t, function()
			drumBeat(center, 18, FLAME, 0.9)
		end)
	end
	at(ctx, 2.1, function()
		Effects.sphere(center + UP * 2, EMBER, 4, 38, 0.6, 0.3)
		Effects.column(center, 30, 16, FLAME, 0.7, 0.3)
		drumBeat(center, 18, FLAME, 2)
		Effects.light(center + UP * 4, EMBER, 40, 5, 0.7)
		CameraController.shakeAt(center, 1.4, 90)
		if near(center, 40) then
			CameraController.flash(EMBER, 0.35, 0.25)
		end
	end)
end

-- Iwao (Earth) -----------------------------------------------------------------------------------

local function quake(position: Vector3, radius: number, strength: number)
	Effects.shockwave(position, DUST, radius, 0.6)
	Effects.debris(position, math.floor(10 * strength), ROCK, radius * 0.6, 6 * strength)
	smoke(position + UP, DUST, math.floor(12 * strength), 14, 3)
	spikes(position, radius * 0.5, math.floor(6 * strength), 2.5, ROCK, Enum.Material.Slate, 0.6)
	SoundController.play("heavy", position, 1.1 * strength, 0.6)
	CameraController.shakeAt(position, 0.8 * strength, radius * 4)
end

MOVES.ShikoStomp = function(ctx: Context)
	at(ctx, 0.6, function()
		local ground = groundOf(ctx)
		if ground then
			quake(ground, 12, 1.2)
		end
	end)
end

MOVES.BoulderGrip = function(ctx: Context)
	at(ctx, param(ctx, "grabAt", 0.2), function()
		local base = frameOf(ctx)
		if base then
			Effects.sphere(base.Position + base.LookVector * 3, DUST, 0.5, 4, 0.2, 0.4)
		end
	end)
end

MOVES.PurifyingSalt = function(ctx: Context)
	at(ctx, 0.3, function()
		local base = frameOf(ctx)
		if not base then
			return
		end
		Effects.particles(base.Position + UP, {
			color = SALT,
			count = 40,
			speed = 34,
			lifetime = 0.6,
			size = 0.6,
			spread = 32,
			cframe = base,
			forward = true,
			acceleration = Vector3.new(0, -20, 0),
		})
		Effects.arc(base * CFrame.new(0, 0.6, -2), 9, -40, 40, SALT, 1.2, 0.35, 12)
		SoundController.play("whoosh", base.Position, 0.8, 2)
	end)
end

MOVES.TachiaiCharge = function(ctx: Context)
	local goAt = param(ctx, "goAt", 0.15)
	local duration = param(ctx, "duration", 0.45)
	at(ctx, goAt, function()
		local model = ctx.model
		if not model then
			return
		end
		for step = 0, 3 do
			task.delay(step * duration / 4, function()
				if model.Parent then
					Effects.afterimage(model, DUST, 0.3, 0.6)
					local ground = groundOf(ctx)
					if ground then
						smoke(ground + UP * 0.5, DUST, 4, 6, 2)
					end
				end
			end)
		end
		local root = rootOf(model)
		if root then
			SoundController.play("whoosh", root.Position, 1, 0.8)
		end
	end)
end

MOVES.Dohyo = function(ctx: Context)
	local ground = groundOf(ctx)
	if ground then
		Effects.particles(ground + UP * 3, {
			color = SALT,
			count = 30,
			speed = 18,
			lifetime = 0.9,
			size = 0.6,
			spread = 70,
			acceleration = Vector3.new(0, -30, 0),
		})
		SoundController.play("heavy", ground, 0.9, 0.5)
	end
end

-- Kanemori (Metal) -------------------------------------------------------------------------------

MOVES.ChainLash = function(ctx: Context)
	at(ctx, 0.2, function()
		local hand = handOf(ctx.model)
		if hand then
			Effects.sphere(hand, STEEL, 0.4, 2.5, 0.15, 0.3)
			SoundController.play("lunge", hand, 0.9, 1.3)
		end
	end)
end

MOVES.JitteCatch = function(ctx: Context)
	local window = param(ctx, "window", 0.6)
	local stance = attached(ctx.model, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 6, 6),
		Color = STEEL,
		Transparency = 0.7,
	}, CFrame.new(0, 1, -2) * CFrame.Angles(0, math.rad(90), 0), window)
	if stance then
		Effects.tween(stance, window, { Transparency = 0.95 }, Enum.EasingStyle.Linear)
	end
	local hand = handOf(ctx.model)
	if hand then
		Effects.sphere(hand, WHITE, 0.3, 1.8, 0.2, 0.2)
	end
end

MOVES.IronEdict = function(ctx: Context)
	local base = ctx.origin
	local steps = { { 0.35, 4 }, { 0.42, 8 }, { 0.49, 12 }, { 0.56, 16 }, { 0.63, 20 }, { 0.7, 24 } }
	for index, step in steps do
		at(ctx, step[1], function()
			local spot = Effects.ground(base.Position + ctx.facing * step[2], 12)
			spikes(spot, 2, 3, 5, IRON, Enum.Material.Metal, 0.7)
			Effects.burst(spot + UP, STEEL, 6, 22, 0.5, 0.25)
			if index == 1 or index == #steps then
				SoundController.play("heavy", spot, 0.8, 1.6)
			end
		end)
	end
	at(ctx, 0.35, function()
		CameraController.shakeAt(base.Position, 0.5, 40)
	end)
end

MOVES.HuntersChase = function(ctx: Context)
	local model = ctx.model
	if model then
		Effects.afterimage(model, STEEL, 0.3, 0.5)
	end
end

MOVES.EdictOfChains = function(ctx: Context)
	local ground = groundOf(ctx)
	if ground then
		Effects.ring(CFrame.new(ground + UP * 0.3), STEEL, 20, 20, 0.5, 0.4, 32, 0.4)
		SoundController.play("bell", ground, 1.1, 0.8)
	end
	if ctx.isLocal then
		CameraController.fovPunch(5, 0.5)
	end
end

-- Rokumon (Water) --------------------------------------------------------------------------------

MOVES.Riverpull = function(ctx: Context)
	at(ctx, 0.35, function()
		local base = frameOf(ctx)
		if not base then
			return
		end
		Effects.arc(base * CFrame.new(0, 0.5, -1), 14, -55, 55, RIVER, 2.5, 0.4, 16)
		Effects.arc(base * CFrame.new(0, 0.8, -1), 11, -50, 50, FOAM, 1.2, 0.35, 14)
		local far = base.Position + base.LookVector * 14
		Effects.particles(far, {
			color = FOAM,
			count = 24,
			speed = 30,
			lifetime = 0.45,
			size = 1,
			spread = 40,
			cframe = CFrame.lookAt(far, base.Position),
			forward = true,
		})
		SoundController.play("water", base.Position, 1, 1.1)
	end)
end

MOVES.PhantomFerry = function(ctx: Context)
	at(ctx, 0.1, function()
		local boat = attached(ctx.model, {
			Size = Vector3.new(3.2, 0.8, 9),
			Color = MIST,
			Transparency = 0.55,
			Material = Enum.Material.Glass,
		}, CFrame.new(0, -2.6, 0), 0.6)
		if boat then
			Effects.tween(boat, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		local model = ctx.model
		for step = 0, 3 do
			task.delay(step * 0.12, function()
				if model and model.Parent then
					Effects.afterimage(model, RIVER, 0.3, 0.6)
					local ground = groundOf(ctx)
					if ground then
						splash(ground + UP * 0.5, 8, 14)
					end
				end
			end)
		end
		local root = rootOf(model)
		if root then
			SoundController.play("water", root.Position, 0.9, 0.8)
		end
	end)
end

MOVES.Mist = function(ctx: Context)
	local root = rootOf(ctx.model)
	if root then
		Effects.particles(root.Position, {
			texture = Effects.TEXTURE_SMOKE,
			color = MIST,
			count = 10,
			speed = 6,
			lifetime = 0.6,
			size = 3,
			lightEmission = 0,
		})
	end
end

MOVES.TollStrike = function(ctx: Context)
	if ctx.model then
		Effects.swingTrails(ctx.model, 0.4)
	end
end

MOVES.RiverReturns = function(ctx: Context)
	local ground = groundOf(ctx)
	if ground then
		Effects.vortex(ground, RIVER, 5, 6, 1, 3)
		SoundController.play("water", ground, 1.2, 0.6)
	end
	if ctx.isLocal then
		CameraController.fovPunch(6, 0.8)
	end
end

---------------------------------------------------------------------------------------------------
-- Mid-move moments (PhaseFx): "<moveId>:<phase>" first, then the phase name alone.

local PHASES: { [string]: (Context, Vector3) -> () } = {}
local GENERIC_PHASES: { [string]: (Context, Vector3) -> () } = {}

-- Persistent pieces some phases leave behind (the Dohyo ring, the Mist cloud), keyed by caster.
local lingering: { [Model]: { [string]: { Instance } } } = {}

local function keep(model: Model?, key: string, instances: { Instance }, duration: number)
	if not model then
		return
	end
	local byKey: { [string]: { Instance } } = lingering[model] or {}
	lingering[model] = byKey
	byKey[key] = instances
	task.delay(duration, function()
		if byKey[key] == instances then
			byKey[key] = nil
		end
		for _, instance in instances do
			instance:Destroy()
		end
	end)
end

local function release(model: Model?, key: string, fade: number)
	local byKey = if model then lingering[model] else nil
	local instances = if byKey then byKey[key] else nil
	if not byKey or not instances then
		return
	end
	byKey[key] = nil
	for _, instance in instances do
		if instance:IsA("BasePart") then
			Effects.tween(instance, fade, { Transparency = 1 })
		end
		Effects.clean(instance, fade + 0.05)
	end
end

GENERIC_PHASES.Miss = function(ctx: Context, position: Vector3)
	smoke(position, DUST, 5, 6, 1.4)
	Effects.sphere(position, ctx.color, 0.5, 3, 0.2, 0.5)
end

GENERIC_PHASES.Explode = function(ctx: Context, position: Vector3)
	Effects.sphere(position, ctx.color, 2, 12, 0.35, 0.2)
	Effects.burst(position, ctx.color, 10, 24, 0.8, 0.3)
	SoundController.play("heavy", position, 0.8, 1.2)
end

PHASES["CanopyGuard:Reflect"] = function(_ctx: Context, position: Vector3)
	Effects.sphere(position, LEAF, 1, 6, 0.25, 0.2)
	Effects.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), LILY, 1, 4, 0.3, 0.4, 16)
	SoundController.play("bell", position, 0.8, 1.5)
end

PHASES["Graft:Lash"] = function(ctx: Context, position: Vector3)
	local model = ctx.model
	local root = rootOf(model)
	if not root then
		return
	end
	local start = root.Position
	line(start, position, LEAF, 0.6, 0.5, SOFT)
	line(start, position, LILY, 0.25, 0.35)
	Effects.burst(position, LEAF, 8, 14, 0.6, 0.3)
	-- the drawn sap: green motes running back to Tsuta
	for step = 1, 4 do
		task.delay(step * 0.12, function()
			local back = rootOf(model)
			if back then
				Effects.sphere(position:Lerp(back.Position, step / 4), LEAF, 0.6, 1.6, 0.2, 0.2)
			end
		end)
	end
	SoundController.play("lunge", position, 0.8, 0.9)
end

PHASES["Graft:Miss"] = function(ctx: Context, position: Vector3)
	local root = rootOf(ctx.model)
	if root then
		line(root.Position, position, LEAF, 0.4, 0.3, SOFT)
	end
end

PHASES["ThousandRootBloom:Erupt"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 20)
	-- The tree rises a stride ahead of the caster: centred on them, it swallowed their own view.
	local flat = Vector3.new(ctx.facing.X, 0, ctx.facing.Z)
	local ahead = if flat.Magnitude > 1e-3 then flat.Unit * 7 else Vector3.zero
	local base = Effects.ground(position + ahead, 20)
	local trunk = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 5, 5),
		CFrame = CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90)),
		Color = BARK,
		Material = Enum.Material.Wood,
	})
	Effects.tween(
		trunk,
		0.4,
		{ Size = Vector3.new(26, 5, 5), CFrame = CFrame.new(base + UP * 13) * CFrame.Angles(0, 0, math.rad(90)) },
		Enum.EasingStyle.Back
	)
	local crown = Effects.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		CFrame = CFrame.new(base + UP * 26),
		Color = LILY,
		Material = SOFT,
		Transparency = 0.15,
	})
	Effects.tween(crown, 0.5, { Size = Vector3.one * 22 }, Enum.EasingStyle.Back)
	for _, piece in { trunk, crown } do
		task.delay(3, function()
			if piece.Parent then
				Effects.tween(piece, 0.6, { Transparency = 1 })
			end
		end)
		Effects.clean(piece, 3.7)
	end
	spikes(ground, 20, 26, 7, BARK, Enum.Material.Wood, 2.6)
	Effects.shockwave(ground, LEAF, 22, 0.8)
	petals(ground + UP * 20, 40, 20)
	SoundController.play("heavy", ground, 1.4, 0.45)
	CameraController.shakeAt(ground, 1.4, 90)
	if near(ground, 26) then
		CameraController.flash(LEAF, 0.3, 0.2)
	end
end

PHASES["ThousandRootBloom:Tick"] = function(_ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 20)
	Effects.ring(CFrame.new(ground + UP * 0.4), LEAF, 6, 22, 0.5, 0.6, 28, 0.3)
	petals(ground + UP * 8, 12, 10)
end

PHASES["Kakegoe:Shout"] = function(ctx: Context, position: Vector3)
	Effects.ring(CFrame.new(position + UP * 1.5), EMBER, 2, 14, 0.35, 0.8, 24, 0.2)
	Effects.sphere(position + UP * 1.5, EMBER, 2, 10, 0.3, 0.5)
	SoundController.play("bell", position, 1.1, 1.1)
	CameraController.shakeAt(position, 0.5, 30)
	if ctx.isLocal then
		CameraController.fovPunch(4, 0.3)
	end
end

PHASES["BoulderGrip:Grab"] = function(_ctx: Context, position: Vector3)
	smoke(position, DUST, 8, 8, 2)
	Effects.sphere(position, DUST, 1, 5, 0.25, 0.4)
	SoundController.play("hit", position, 1, 0.7)
end

PHASES["BoulderGrip:Throw"] = function(_ctx: Context, position: Vector3)
	Effects.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), DUST, 1, 6, 0.3, 0.4, 16)
	SoundController.play("whoosh", position, 1, 0.7)
end

GENERIC_PHASES.Land = function(_ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 10)
	quake(ground, 8, 0.9)
end

PHASES["TachiaiCharge:Charge"] = function(_ctx: Context, position: Vector3)
	smoke(position, DUST, 6, 10, 2.2)
end

GENERIC_PHASES.Slam = function(_ctx: Context, position: Vector3)
	Effects.sphere(position, DUST, 2, 9, 0.3, 0.3)
	Effects.debris(position, 10, ROCK, 5, 5)
	smoke(position, DUST, 12, 16, 3)
	SoundController.play("heavy", position, 1.3, 0.6)
	CameraController.shakeAt(position, 1, 50)
end

PHASES["Dohyo:Rise"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 20)
	local radius = param(ctx, "radius", Constants.IWAO_DOHYO_RADIUS)
	local duration = param(ctx, "duration", Constants.IWAO_DOHYO_SECONDS)
	local pieces: { Instance } = {}
	local bales = 20
	for index = 0, bales - 1 do
		local angle = index / bales * math.pi * 2
		local spot = ground + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local frame = CFrame.lookAt(spot, ground) * CFrame.Angles(0, math.rad(90), 0)
		local bale = Effects.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(radius * 0.36, 1.6, 1.6),
			CFrame = frame - UP * 1,
			Color = STRAW,
			Material = SOFT,
		})
		Effects.tween(bale, 0.35, { CFrame = frame + UP * 0.6 }, Enum.EasingStyle.Back)
		table.insert(pieces, bale)
	end
	local rope = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, radius * 2 + 1, radius * 2 + 1),
		CFrame = CFrame.new(ground + UP * 0.08) * CFrame.Angles(0, 0, math.rad(90)),
		Color = SALT,
		Transparency = 0.55,
	})
	table.insert(pieces, rope)
	keep(ctx.model, "Dohyo", pieces, duration + 1)
	Effects.shockwave(ground, STRAW, radius, 0.7)
	SoundController.play("heavy", ground, 1.2, 0.5)
	CameraController.shakeAt(ground, 0.9, radius * 4)
end

PHASES["Dohyo:RingOut"] = function(_ctx: Context, position: Vector3)
	Effects.column(position, 16, 5, SALT, 0.5, 0.3)
	Effects.burst(position, STRAW, 14, 30, 0.9, 0.4)
	SoundController.play("bell", position, 1.3, 0.7)
	CameraController.shakeAt(position, 1.2, 60)
end

PHASES["Dohyo:Fall"] = function(ctx: Context, _position: Vector3)
	release(ctx.model, "Dohyo", 0.5)
end

GENERIC_PHASES.Catch = function(_ctx: Context, position: Vector3)
	Effects.sphere(position, WHITE, 1, 7, 0.25, 0)
	Effects.burst(position, STEEL, 14, 30, 0.6, 0.3)
	Effects.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), STEEL, 1, 5, 0.3, 0.4, 16)
	SoundController.play("bell", position, 1.3, 1.9)
	CameraController.shakeAt(position, 0.6, 30)
end

PHASES["HuntersChase:Chase"] = function(ctx: Context, position: Vector3)
	local model = ctx.model
	if model then
		Effects.afterimage(model, STEEL, 0.4, 0.4)
	end
	Effects.arc(
		CFrame.new(position + UP * 1.5) * CFrame.Angles(0, math.rad(math.random(0, 360)), math.rad(35)),
		4,
		-80,
		80,
		STEEL,
		1.2,
		0.25,
		12
	)
	Effects.burst(position + UP, STEEL, 8, 20, 0.5, 0.25)
	SoundController.play("lunge", position, 1, 1.1)
end

PHASES["EdictOfChains:Chains"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 20)
	local radius = param(ctx, "radius", 20)
	for index = 0, 9 do
		local angle = index / 10 * math.pi * 2
		local tip = ground + Vector3.new(math.cos(angle) * radius, 1.2, math.sin(angle) * radius)
		line(ground + UP * 1.2, tip, IRON, 0.5, 0.9, Enum.Material.Metal)
		spikes(tip - UP * 1.2, 1, 1, 3, IRON, Enum.Material.Metal, 1.6)
	end
	Effects.ring(CFrame.new(ground + UP * 0.5), STEEL, radius * 0.2, radius, 0.4, 0.6, 32, 0.2)
	SoundController.play("bell", ground, 1.2, 1.2)
	CameraController.shakeAt(ground, 0.8, radius * 3)
end

PHASES["EdictOfChains:Shock"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 12)
	local radius = param(ctx, "shockRadius", 12)
	Effects.shockwave(ground, STEEL, radius, 0.6)
	Effects.sphere(ground + UP * 2, WHITE, 2, radius * 1.6, 0.35, 0.3)
	spikes(ground, radius * 0.6, 10, 5, IRON, Enum.Material.Metal, 0.8)
	SoundController.play("heavy", ground, 1.3, 1.1)
	CameraController.shakeAt(ground, 1.3, radius * 5)
	if near(ground, radius + 4) then
		CameraController.flash(STEEL, 0.25, 0.2)
	end
end

PHASES["Mist:Mist"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 20)
	local radius = param(ctx, "radius", 14)
	local duration = param(ctx, "duration", 4)
	local cloud = Effects.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 2, radius * 0.9, radius * 2),
		CFrame = CFrame.new(ground + UP * 2),
		Color = MIST,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.55,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Effects.TEXTURE_SMOKE
	emitter.Color = ColorSequence.new(MIST)
	emitter.LightEmission = 0
	emitter.Rate = 30
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 7) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = cloud
	task.delay(duration - 0.5, function()
		if cloud.Parent then
			emitter.Enabled = false
			Effects.tween(cloud, 0.5, { Transparency = 1 })
		end
	end)
	keep(ctx.model, "Mist", { cloud }, duration + 1.5)
	SoundController.play("water", ground, 0.6, 0.5)
end

PHASES["TollStrike:Toll"] = function(_ctx: Context, position: Vector3)
	coins(position, 6)
	Effects.sphere(position, COIN, 1, 6, 0.25, 0.3)
	Effects.burst(position, GOLD, 10, 22, 0.6, 0.3)
	SoundController.play("bell", position, 1.2, 1.4)
	CameraController.shakeAt(position, 0.6, 30)
end

PHASES["RiverReturns:Wave"] = function(ctx: Context, position: Vector3)
	local length = param(ctx, "length", 50)
	local width = param(ctx, "width", 14)
	local speed = param(ctx, "speed", 60)
	local direction = ctx.facing
	local start = Effects.ground(position, 20)
	local wave = Effects.part({
		Size = Vector3.new(width, 7, 3),
		CFrame = CFrame.lookAt(start + UP * 3.5, start + UP * 3.5 + direction),
		Color = RIVER,
		Material = Enum.Material.Glass,
		Transparency = 0.25,
	})
	local crest = Effects.part({
		Size = Vector3.new(width, 1.2, 3.6),
		CFrame = wave.CFrame * CFrame.new(0, 3.8, -0.3),
		Color = FOAM,
		Transparency = 0.1,
	})
	local travel = length / speed
	for _, piece in { wave, crest } do
		Effects.tween(piece, travel, { CFrame = piece.CFrame + direction * length }, Enum.EasingStyle.Linear)
		task.delay(travel, function()
			if piece.Parent then
				Effects.tween(piece, 0.3, { Transparency = 1 })
			end
		end)
		Effects.clean(piece, travel + 0.35)
	end
	for step = 0, 4 do
		task.delay(step * travel / 5, function()
			splash(start + direction * (length * step / 5) + UP, 14, 22)
		end)
	end
	SoundController.play("water", start, 1.4, 0.6)
	CameraController.shakeAt(start, 1, 70)
end

PHASES["RiverReturns:Drain"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 20)
	local width = param(ctx, "width", 14)
	Effects.vortex(ground, RIVER, width * 0.5, 4, 0.8, 3)
	Effects.disc(CFrame.new(ground + UP * 0.2), RIVER, width * 2, 2, 0.7, 0.3, 0.2)
	Effects.particles(ground + UP * 4, {
		color = FOAM,
		count = 30,
		speed = 12,
		lifetime = 0.6,
		size = 1.2,
		acceleration = Vector3.new(0, -60, 0),
	})
	SoundController.play("water", ground, 1.2, 0.4)
	CameraController.shakeAt(ground, 1.1, 60)
end

---------------------------------------------------------------------------------------------------
-- Public API

function VfxController.markPredicted(moveId: string)
	predicted[predictionKey(moveId)] = os.clock()
end

-- Listeners run when the server confirms a move this client predicted.
function VfxController.onOwnMoveConfirmed(listener: (string) -> ())
	table.insert(confirmListeners, listener)
end

-- Play a move's animation and effects. Used for server events and local prediction.
function VfxController.playMove(
	model: Model,
	fighterId: string?,
	moveId: string,
	start: number,
	facing: Vector3,
	extra: any
)
	local ctx = contextFor(model, fighterId, moveId, start, facing, extra)
	local fighter = ctx.fighter
	local m1Index = Fighters.parseM1(moveId)
	if moveId == "Dash" then
		AnimationController.play(model, "Dash", start)
		dashFx(ctx)
		return
	end
	if not fighter then
		return
	end
	if m1Index then
		AnimationController.play(model, Poses.m1Sequence(fighter.m1.style, m1Index), start)
		m1Fx(ctx, m1Index)
		return
	end
	local move = ctx.move
	if not move then
		return
	end
	AnimationController.play(model, move.pose, start)
	Effects.swingTrails(model, math.min(move.lock + 0.1, 1.4))
	local handler = MOVES[move.vfx]
	if handler then
		handler(ctx)
	end
end

---------------------------------------------------------------------------------------------------
-- Hits

local function onHit(victim: Model?, attacker: Model?, amount: number, flags: number, position: Vector3)
	if not victim or typeof(position) ~= "Vector3" or type(flags) ~= "number" then
		return
	end
	local character = localPlayer.Character
	local involved = (victim == character) or (attacker ~= nil and attacker == character)

	if bit32.btest(flags, Remotes.FLAG_RING_OUT) then
		Effects.column(position, 30, 6, LILY, 0.8, 0.3)
		petals(position + UP * 4, 30, 24)
		SoundController.play("bell", position, 1.4, 0.5)
		if victim == character then
			CameraController.flash(LILY, 0.5, 0.3)
		end
		return
	end

	if bit32.btest(flags, Remotes.FLAG_HEAL) then
		Effects.particles(position, {
			color = LEAF,
			count = 8,
			speed = 4,
			lifetime = 0.8,
			size = 0.7,
			acceleration = Vector3.new(0, 8, 0),
		})
		return
	end

	if bit32.btest(flags, Remotes.FLAG_PARRIED) then
		Effects.sphere(position, WHITE, 1, 9, 0.25, 0)
		Effects.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), BLOCK_BLUE, 1, 6, 0.3, 0.5, 18)
		SoundController.play("bell", position, 1.2, 1.8)
		if involved then
			CameraController.shake(0.7)
			CameraController.flash(BLOCK_BLUE, 0.2, 0.15)
		end
		return
	end

	if bit32.btest(flags, Remotes.FLAG_CATCH) or bit32.btest(flags, Remotes.FLAG_REFLECT) then
		local color = if bit32.btest(flags, Remotes.FLAG_CATCH) then STEEL else LEAF
		Effects.sphere(position, color, 1, 6, 0.2, 0.1)
		Effects.burst(position, color, 8, 22, 0.6, 0.25)
		SoundController.play("bell", position, 1, 1.6)
		if involved then
			CameraController.shake(0.5)
		end
		return
	end

	if bit32.btest(flags, Remotes.FLAG_BURN) then
		fire(position, 4, 4, 1)
		return
	end

	if bit32.btest(flags, Remotes.FLAG_GUARD_BREAK) then
		Effects.burst(position, BLOCK_BLUE, 16, 28, 1, 0.4)
		Effects.ring(CFrame.new(position), WHITE, 1, 7, 0.35, 0.5, 18)
		SoundController.play("heavy", position, 1, 1.4)
		if involved then
			CameraController.shake(0.9)
		end
	end

	if bit32.btest(flags, Remotes.FLAG_BLOCKED) then
		Effects.sphere(position, BLOCK_BLUE, 0.6, 4, 0.18, 0.2)
		Effects.burst(position, BLOCK_BLUE, 5, 18, 0.6, 0.18)
		SoundController.play("hit", position, 0.6, 2)
		if involved then
			CameraController.shake(0.25)
		end
		return
	end

	local color = phaseColor(attacker)
	local big = amount >= 10
	Effects.burst(position, color, if big then 12 else 7, 30, 0.8, 0.22)
	Effects.sphere(position, WHITE, 0.5, if big then 6 else 3.5, 0.15, 0)
	if bit32.btest(flags, Remotes.FLAG_OVERCOME) then
		Effects.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), KI, 1, 5, 0.25, 0.4, 16)
	end
	if bit32.btest(flags, Remotes.FLAG_BEAT) then
		Effects.ring(CFrame.new(position), EMBER, 1, 6, 0.3, 0.6, 18)
		fire(position, 6, 10, 1.2)
		SoundController.play("heavy", position, 0.7, 1.5)
	end
	if bit32.btest(flags, Remotes.FLAG_SPROUT) then
		spikes(Effects.ground(position, 8), 1.5, 5, 3, LEAF, SOFT, 0.8)
		petals(position, 10, 10)
	end
	if bit32.btest(flags, Remotes.FLAG_WOUND) then
		Effects.sphere(position, color, 2, 12, 0.3, 0.2)
		Effects.burst(position, GOLD, 18, 40, 1.2, 0.4)
		SoundController.play("bell", position, 1, 1.2)
	end
	Effects.flash(victim, WHITE, 0.18)
	-- The Elder wears its tree outside its combat model (ElderService): flash the tree too.
	local tree = victim:FindFirstChild("Body")
	if tree and tree:IsA("ObjectValue") and tree.Value and tree.Value:IsA("Model") then
		Effects.flash(tree.Value, WHITE, 0.18)
	end
	AnimationController.hurt(victim)
	SoundController.play("hit", position, if big then 1.2 else 0.9, if big then 0.8 else 1 + math.random() * 0.15)
	if victim == character then
		CameraController.shake(0.45 + amount * 0.04)
	elseif attacker ~= nil and attacker == character then
		CameraController.shake(0.2 + amount * 0.02)
	end
end

---------------------------------------------------------------------------------------------------
-- Projectiles

type VisualPart = { part: BasePart, offset: CFrame }
type Visual = { parts: { VisualPart }, spin: number, tether: Part? }
type ClientProjectile = {
	id: number,
	kind: string,
	visual: Visual,
	position: Vector3,
	direction: Vector3,
	speed: number,
	range: number,
	traveled: number,
	returns: boolean,
	returning: boolean,
	homing: number?,
	target: Model?,
	owner: Model?,
	born: number,
	color: Color3,
}

local projectiles: { [number]: ClientProjectile } = {}

local function addVisualPart(visual: Visual, props: { [string]: any }, offset: CFrame): Part
	local piece = Effects.part(props)
	local entry: VisualPart = { part = piece, offset = offset }
	table.insert(visual.parts, entry)
	return piece
end

local function makeVisual(kind: string, color: Color3, radius: number): Visual
	local visual: Visual = { parts = {}, spin = 0, tether = nil }
	if kind == "Seed" then
		local seed = addVisualPart(visual, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.7, 1.4),
			Color = LEAF,
			Material = Enum.Material.SmoothPlastic,
		}, CFrame.new())
		addVisualPart(
			visual,
			{ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.45, Color = LILY },
			CFrame.new(0, 0, -0.55)
		)
		local tipA = Instance.new("Attachment")
		tipA.Position = Vector3.new(0, 0.2, 0.5)
		tipA.Parent = seed
		local tipB = Instance.new("Attachment")
		tipB.Position = Vector3.new(0, -0.2, 0.5)
		tipB.Parent = seed
		local trail = Instance.new("Trail")
		trail.Attachment0 = tipA
		trail.Attachment1 = tipB
		trail.Color = ColorSequence.new(LEAF)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.18
		trail.LightEmission = 0.6
		trail.Parent = seed
		visual.spin = 14
	elseif kind == "Chain" then
		addVisualPart(visual, {
			Size = Vector3.new(0.6, 0.6, 1.6),
			Color = IRON,
			Material = Enum.Material.Metal,
		}, CFrame.new())
		addVisualPart(visual, {
			Size = Vector3.new(1.4, 0.3, 0.3),
			Color = STEEL,
			Material = Enum.Material.Metal,
		}, CFrame.new(0, 0, -0.8))
		visual.tether = Effects.part({
			Size = Vector3.new(0.25, 0.25, 1),
			Color = IRON,
			Material = Enum.Material.Metal,
		})
	else
		addVisualPart(visual, { Shape = Enum.PartType.Ball, Size = Vector3.one * radius, Color = color }, CFrame.new())
	end
	return visual
end

local function placeVisual(projectile: ClientProjectile, age: number)
	local visual = projectile.visual
	local position = projectile.position
	local frame = CFrame.lookAt(position, position + projectile.direction)
	if visual.spin ~= 0 then
		frame *= CFrame.Angles(0, 0, age * visual.spin)
	end
	for _, entry in visual.parts do
		entry.part.CFrame = frame * entry.offset
	end
	local tetherPart = visual.tether
	if tetherPart then
		local hand = handOf(projectile.owner)
		if hand then
			local length = math.max((position - hand).Magnitude, 0.1)
			tetherPart.Size = Vector3.new(0.25, 0.25, length)
			tetherPart.CFrame = CFrame.lookAt((position + hand) / 2, position)
		end
	end
end

local function destroyVisual(visual: Visual)
	for _, entry in visual.parts do
		entry.part:Destroy()
	end
	if visual.tether then
		visual.tether:Destroy()
	end
end

local function steer(current: Vector3, desired: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(current:Dot(desired), -1, 1))
	if angle <= maxAngle or angle < 1e-4 then
		return desired
	end
	local blended = current:Lerp(desired, maxAngle / angle)
	return if blended.Magnitude > 1e-4 then blended.Unit else desired
end

local function onProjectileSpawn(data: any)
	if
		type(data) ~= "table"
		or type(data.id) ~= "number"
		or typeof(data.origin) ~= "Vector3"
		or typeof(data.direction) ~= "Vector3"
	then
		return
	end
	local owner = asModel(data.owner)
	local target = asModel(data.target)
	local color = phaseColor(owner)
	local speed = tonumber(data.speed) or 60
	local lag = math.clamp(now() - (tonumber(data.startTime) or now()), 0, 0.3)
	local direction = (data.direction :: Vector3).Unit
	local kind = tostring(data.kind)
	local projectile: ClientProjectile = {
		id = data.id,
		kind = kind,
		visual = makeVisual(kind, color, tonumber(data.radius) or 1),
		position = data.origin + direction * speed * lag,
		direction = direction,
		speed = speed,
		range = tonumber(data.range) or 60,
		traveled = speed * lag,
		returns = data.returns == true,
		returning = false,
		homing = tonumber(data.homing),
		target = target,
		owner = owner,
		born = os.clock(),
		color = color,
	}
	projectiles[projectile.id] = projectile
	placeVisual(projectile, 0)
end

local function onProjectileReflect(id: any, position: any, direction: any, reflector: any)
	local projectile = if type(id) == "number" then projectiles[id] else nil
	if not projectile or typeof(position) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	local previousOwner = projectile.owner
	projectile.position = position
	projectile.direction = (direction :: Vector3).Unit
	projectile.traveled = 0
	projectile.returning = false
	projectile.target = previousOwner
	projectile.owner = asModel(reflector)
	projectile.color = LEAF
	for _, entry in projectile.visual.parts do
		entry.part.Color = LEAF
	end
	Effects.sphere(position, LEAF, 0.8, 4, 0.2, 0.2)
end

local function onProjectileEnd(id: any, position: any, exploded: any)
	local projectile = if type(id) == "number" then projectiles[id] else nil
	if not projectile then
		return
	end
	projectiles[id] = nil
	destroyVisual(projectile.visual)
	if typeof(position) ~= "Vector3" or exploded == true then
		return -- explosions are drawn by PhaseFx "Explode"
	end
	if projectile.kind == "Seed" then
		Effects.burst(position, LEAF, 5, 10, 0.4, 0.2)
	elseif projectile.kind == "Chain" then
		local hand = handOf(projectile.owner)
		if hand then
			line(position, hand, IRON, 0.2, 0.2, Enum.Material.Metal)
		end
		Effects.burst(position, STEEL, 6, 16, 0.4, 0.2)
		SoundController.play("hit", position, 0.6, 1.8)
	else
		Effects.burst(position, projectile.color, 8, 16, 0.6, 0.25)
	end
end

local function stepProjectiles(dt: number)
	for id, projectile in projectiles do
		local age = os.clock() - projectile.born
		if age > 8 then
			projectiles[id] = nil
			destroyVisual(projectile.visual)
			continue
		end
		if projectile.returning then
			local ownerRoot = rootOf(projectile.owner)
			if ownerRoot then
				local toOwner = ownerRoot.Position - projectile.position
				if toOwner.Magnitude > 0.5 then
					projectile.direction = toOwner.Unit
				end
			end
		elseif projectile.homing and projectile.target then
			local targetRoot = rootOf(projectile.target)
			if targetRoot then
				local desired = targetRoot.Position - projectile.position
				if desired.Magnitude > 0.5 then
					projectile.direction = steer(projectile.direction, desired.Unit, projectile.homing * dt)
				end
			end
		end
		local distance = projectile.speed * dt
		if projectile.traveled < projectile.range * 2.5 + 30 then
			projectile.position += projectile.direction * distance
			projectile.traveled += distance
		end
		if projectile.returns and not projectile.returning and projectile.traveled >= projectile.range then
			projectile.returning = true
		end
		placeVisual(projectile, age)
	end
end

---------------------------------------------------------------------------------------------------
-- The Thirsting Elder

local grabTethers: { [Model]: Part } = {}

local function onElder(kind: string, data: any)
	if type(kind) ~= "string" or type(data) ~= "table" then
		return
	end
	local hasPosition = typeof(data.position) == "Vector3"
	local position: Vector3 = if hasPosition then data.position else Vector3.zero
	if kind == "wake" and hasPosition then
		local ground = Effects.ground(position, 60)
		local heart = if type(data.heart) == "string" then Phases.color(data.heart) else LILY
		Effects.column(ground - UP * 6, 70, 24, LILY, 2, 0.35)
		Effects.shockwave(ground, heart, 30, 1.4)
		spikes(ground, 26, 30, 9, BARK, Enum.Material.Wood, 3)
		petals(ground + UP * 30, 80, 40)
		CameraController.shakeAt(ground, 1.8, 320)
		if near(ground, 220) then
			CameraController.flash(LILY, 0.6, 0.25)
		end
		SoundController.play("heavy", ground, 1.6, 0.35)
		SoundController.play("bell", ground, 1.4, 0.3)
	elseif kind == "heart" then
		local model = Workspace:FindFirstChild("ThirstingElder", true)
		local heartPart = if model then model:FindFirstChild("Heart", true) else nil
		local place = if heartPart and heartPart:IsA("BasePart") then heartPart.Position else nil
		if place then
			if data.warning == true and type(data.next) == "string" then
				Effects.ring(CFrame.new(place), Phases.color(data.next), 4, 14, 0.6, 1, 24, 0.3)
				SoundController.play("bell", place, 1, 0.9)
			elseif type(data.heart) == "string" then
				local color = Phases.color(data.heart)
				Effects.sphere(place, color, 4, 18, 0.5, 0.3)
				Effects.burst(place, color, 20, 30, 1, 0.5)
				SoundController.play("bell", place, 1.3, 0.6)
			end
		end
	elseif kind == "telegraph" and hasPosition then
		local duration = tonumber(data.duration) or 1
		if data.kind == "reach" and typeof(data.direction) == "Vector3" then
			laneTelegraph(position, data.direction, tonumber(data.length) or 40, 7, duration, RED)
		elseif data.kind == "petals" then
			Effects.column(position, 40, 12, LILY, duration, 0.55)
			Effects.ring(CFrame.new(position + UP * 0.5), LILY, 6, 6, duration, 1.5, 32, 0.3)
			SoundController.play("bell", position, 1.3, 0.45)
		else
			areaTelegraph(position, tonumber(data.radius) or 7, duration, RED)
		end
	elseif kind == "impact" and hasPosition then
		if data.kind == "reach" then
			local ground = Effects.ground(position, 20)
			Effects.debris(ground, 8, BARK, 5, 5)
			smoke(ground + UP, DUST, 10, 12, 3)
			SoundController.play("heavy", ground, 1, 0.7)
			CameraController.shakeAt(ground, 0.9, 60)
		else
			local radius = tonumber(data.radius) or 7
			spikes(position, radius * 0.8, 12, 8, BARK, Enum.Material.Wood, 0.9)
			Effects.shockwave(position, LILY, radius, 0.6)
			Effects.debris(position, 10, BARK, radius, 7)
			SoundController.play("heavy", position, 1.3, 0.5)
			CameraController.shakeAt(position, 1.2, radius * 6)
		end
	elseif kind == "grab" then
		local victim = asModel(data.victim)
		local branch = asModel(data.branch)
		local from: Vector3? = if typeof(data.from) == "Vector3" then data.from else nil
		if victim then
			local existing = grabTethers[victim]
			if existing then
				existing:Destroy()
			end
			grabTethers[victim] = tether(function(): Vector3?
				local branchRoot = rootOf(branch)
				return if branchRoot then branchRoot.Position else from
			end, function(): Vector3?
				local victimRoot = rootOf(victim)
				return if victimRoot then victimRoot.Position else nil
			end, BARK, 1.2, Constants.ELDER_GRAB_SECONDS + 0.5, Enum.Material.Wood)
			local victimRoot = rootOf(victim)
			if victimRoot then
				petals(victimRoot.Position, 12, 10)
				SoundController.play("hit", victimRoot.Position, 1.2, 0.6)
			end
		end
	elseif kind == "release" then
		local victim = asModel(data.victim)
		if victim then
			local existing = grabTethers[victim]
			grabTethers[victim] = nil
			if existing then
				existing:Destroy()
			end
		end
	elseif kind == "petals" and hasPosition then
		growingRing(
			position,
			tonumber(data.speed) or 40,
			tonumber(data.maxRadius) or 75,
			tonumber(data.startTime) or now(),
			LILY,
			2.2
		)
		Effects.disc(CFrame.new(position + UP * 0.2), LILY, 4, 30, 0.8, 0.5, 0.15)
		CameraController.shakeAt(position, 1.2, 140)
		SoundController.play("heavy", position, 1.2, 0.4)
	elseif kind == "enrage" and hasPosition then
		Effects.sphere(position + UP * 20, RED, 8, 60, 0.9, 0.35)
		petals(position + UP * 25, 60, 36)
		CameraController.shakeAt(position, 1.2, 220)
		SoundController.play("bell", position, 1.5, 0.35)
	elseif kind == "sprout" and hasPosition then
		Effects.column(position, 10, 3, SAP, 0.6, 0.3)
		spikes(position, 1.5, 5, 3, LEAF, SOFT, 0.7)
	elseif kind == "wither" and hasPosition then
		if data.healed == true then
			local model = Workspace:FindFirstChild("ThirstingElder", true)
			local heartPart = if model then model:FindFirstChild("Heart", true) else nil
			if heartPart and heartPart:IsA("BasePart") then
				line(position, heartPart.Position, SAP, 0.8, 0.6)
			end
			Effects.sphere(position, SAP, 1, 6, 0.3, 0.3)
		else
			smoke(position, DUST, 10, 8, 2)
			Effects.burst(position, SAP, 10, 16, 0.6, 0.3)
		end
	elseif kind == "fall" and hasPosition then
		local ground = Effects.ground(position, 60)
		Effects.column(ground, 80, 20, LILY, 2.2, 0.3)
		Effects.shockwave(ground, GOLD, 30, 1.4)
		petals(ground + UP * 20, 120, 50)
		Effects.burst(ground + UP * 10, GOLD, 30, 50, 1.4, 0.8)
		CameraController.shakeAt(ground, 1.6, 260)
		SoundController.play("bell", ground, 1.6, 0.5)
		SoundController.play("heavy", ground, 1.4, 0.4)
	elseif kind == "timeout" and hasPosition then
		local ground = Effects.ground(position, 60)
		smoke(ground + UP * 4, DUST, 30, 16, 6)
		SoundController.play("heavy", ground, 1, 0.3)
	end
end

---------------------------------------------------------------------------------------------------
-- State auras (model attributes the server publishes) and Mist fading

type AuraSpec = {
	color: Color3,
	texture: string?,
	rate: number,
	speed: number,
	size: number,
	lift: number,
	emission: number,
}

local AURAS: { [string]: AuraSpec } = {
	Burning = {
		color = EMBER,
		texture = Effects.TEXTURE_FIRE,
		rate = 18,
		speed = 2,
		size = 1.4,
		lift = 8,
		emission = 1,
	},
	Rooted = { color = LEAF, rate = 10, speed = 1, size = 0.6, lift = -2, emission = 0.3 },
	Bound = { color = STEEL, rate = 10, speed = 2, size = 0.5, lift = 0, emission = 0.6 },
	Purified = { color = SALT, rate = 12, speed = 2, size = 0.4, lift = -4, emission = 0.4 },
	Hasted = { color = EMBER, rate = 14, speed = 4, size = 0.5, lift = 2, emission = 1 },
	Sap = { color = SAP, rate = 4, speed = 1, size = 0.5, lift = -6, emission = 0.6 },
	Mending = { color = KI, rate = 16, speed = 2, size = 0.6, lift = 6, emission = 1 },
	Sprouts = { color = LEAF, rate = 6, speed = 1, size = 0.5, lift = 3, emission = 0.4 },
}

local function setAura(root: BasePart, name: string, spec: AuraSpec?)
	local existing = root:FindFirstChild(name)
	if spec and not existing then
		local aura = Instance.new("ParticleEmitter")
		aura.Name = name
		aura.Texture = spec.texture or Effects.TEXTURE_SPARK
		aura.Color = ColorSequence.new(spec.color)
		aura.LightEmission = spec.emission
		aura.Rate = spec.rate
		aura.Lifetime = NumberRange.new(0.5, 0.9)
		aura.Speed = NumberRange.new(spec.speed * 0.5, spec.speed)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Acceleration = Vector3.new(0, spec.lift, 0)
		aura.Size = NumberSequence.new(spec.size, 0)
		aura.Parent = root
	elseif not spec and existing then
		existing:Destroy()
	end
end

local mistFaded: { [Model]: boolean } = {}
local lastCoins: { [Model]: number } = {}

local function fade(model: Model, amount: number)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			(descendant :: any).LocalTransparencyModifier = amount
		end
	end
end

local function refreshAuras()
	local models: { Model } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(models, player.Character)
		end
	end
	for _, tagged in CollectionService:GetTagged("Npc") do
		if tagged:IsA("Model") then
			table.insert(models, tagged)
		end
	end
	for _, model in models do
		local root = rootOf(model)
		if not root then
			continue
		end
		for attribute, spec in AURAS do
			local value = model:GetAttribute(attribute)
			local active = value == true or (type(value) == "number" and value > 0)
			setAura(root, `Aura{attribute}`, if active then spec else nil)
		end

		-- Ultimate ready: the player's Ki is full
		local player = Players:GetPlayerFromCharacter(model)
		local ki = if player then player:GetAttribute("Ki") else nil
		local ready = type(ki) == "number" and ki >= Constants.KI_MAX
		setAura(
			root,
			"AuraUltimate",
			if ready
				then {
					color = phaseColor(model),
					rate = 22,
					speed = 6,
					size = 0.6,
					lift = 8,
					emission = 1,
				}
				else nil
		)

		-- Rokumon earns a coin
		local coinCount = model:GetAttribute("Coins")
		if type(coinCount) == "number" then
			local previous = lastCoins[model] or 0
			if coinCount > previous then
				coins(root.Position + UP * 3, 3)
				SoundController.play("bell", root.Position, 0.5, 2)
			end
			lastCoins[model] = coinCount
		end

		-- Mist of the Crossing: others fade almost out, you see yourself as a ghost
		local inMist = model:GetAttribute("Mist") == true
		if inMist ~= (mistFaded[model] == true) then
			if inMist then
				mistFaded[model] = true
			else
				mistFaded[model] = nil
			end
			fade(model, if inMist then (if model == localPlayer.Character then 0.5 else 0.85) else 0)
		end
	end
	for model in mistFaded do
		if model.Parent == nil then
			mistFaded[model] = nil
		end
	end
	for model in lastCoins do
		if model.Parent == nil then
			lastCoins[model] = nil
		end
	end
	for model in lingering do
		if model.Parent == nil then
			lingering[model] = nil
		end
	end
end

function VfxController.start(_self: any)
	Remotes.MoveFx.OnClientEvent:Connect(
		function(model: Model?, fighterId: string, moveId: string, start: number, facing: Vector3, extra: any)
			if not model or type(moveId) ~= "string" or typeof(facing) ~= "Vector3" then
				return
			end
			if model == localPlayer.Character then
				local key = predictionKey(moveId)
				local predictedAt = predicted[key]
				if predictedAt and os.clock() - predictedAt < 0.9 then
					predicted[key] = nil
					for _, listener in confirmListeners do
						listener(moveId)
					end
					return
				end
			end
			VfxController.playMove(model, fighterId, moveId, tonumber(start) or now(), facing, extra)
		end
	)

	Remotes.PhaseFx.OnClientEvent:Connect(
		function(model: Model?, fighterId: string, moveId: string, phase: string, position: Vector3)
			if typeof(position) ~= "Vector3" or type(moveId) ~= "string" or type(phase) ~= "string" then
				return
			end
			local root = rootOf(model)
			local facing = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
			local ctx = contextFor(model, fighterId, moveId, now(), facing, nil)
			local handler: ((Context, Vector3) -> ())? = PHASES[`{moveId}:{phase}`] or GENERIC_PHASES[phase]
			if handler then
				handler(ctx, position)
			end
		end
	)

	Remotes.HitFx.OnClientEvent:Connect(onHit)

	Remotes.ProjectileFx.OnClientEvent:Connect(function(action: string, a: any, b: any, c: any, d: any)
		if action == "spawn" then
			onProjectileSpawn(a)
		elseif action == "end" then
			onProjectileEnd(a, b, c)
		elseif action == "reflect" then
			onProjectileReflect(a, b, c, d)
		end
	end)

	Remotes.ElderFx.OnClientEvent:Connect(onElder)

	RunService.RenderStepped:Connect(stepProjectiles)

	task.spawn(function()
		while true do
			refreshAuras()
			task.wait(0.25)
		end
	end)
end

return VfxController
