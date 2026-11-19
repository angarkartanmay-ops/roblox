--!strict
-- Renders every combat event the server reports: move animations and effects (MoveFx), mid-move
-- moments (PhaseFx), hits (HitFx), projectiles (ProjectileFx) and the Tide Warden (BossFx).
-- The local player's own moves are predicted by InputController and not replayed on echo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Elements = require(ReplicatedStorage.Shared.Elements)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
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
	color: Color3,
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
local ROCK = Color3.fromRGB(112, 98, 84)
local DUST = Color3.fromRGB(180, 168, 150)
local MIST = Color3.fromRGB(214, 244, 248)
local EMBER = Color3.fromRGB(255, 150, 60)
local GOLD = Color3.fromRGB(255, 210, 110)
local VOID_DARK = Color3.fromRGB(34, 20, 58)
local TEAL = Color3.fromRGB(60, 240, 225)
local RED = Color3.fromRGB(255, 70, 60)
local BLOCK_BLUE = Color3.fromRGB(150, 210, 255)

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

local function elementColor(model: Model?): Color3
	local element = if model then model:GetAttribute("Element") else nil
	if type(element) == "string" and Elements.INFO[element] then
		local rgb = Elements.INFO[element].color
		return Color3.new(rgb[1], rgb[2], rgb[3])
	end
	return WHITE
end

local function fighterColor(fighter: Types.FighterSpec?, model: Model?): Color3
	if fighter then
		return Color3.new(fighter.color[1], fighter.color[2], fighter.color[3])
	end
	return elementColor(model)
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

local function asModel(value: any): Model?
	if typeof(value) == "Instance" and (value :: Instance):IsA("Model") then
		return value :: Model
	end
	return nil
end

local function predictionKey(moveId: string): string
	return if Fighters.parseM1(moveId) then "M1" else moveId
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
	return {
		model = model,
		fighter = fighter,
		color = fighterColor(fighter, model),
		facing = direction,
		start = start,
		origin = if root then CFrame.lookAt(root.Position, root.Position + direction) else CFrame.new(),
		point = point,
		isLocal = model ~= nil and model == localPlayer.Character,
		moveId = moveId,
	}
end

local function groundAt(ctx: Context): Vector3?
	local root = rootOf(ctx.model)
	return if root then Effects.ground(root.Position, 10) else nil
end

---------------------------------------------------------------------------------------------------
-- Universal

local function m1Fx(ctx: Context, index: number)
	local fighter = ctx.fighter
	local style = if fighter then fighter.m1.style else "Heavy"
	local finisher = index >= Constants.COMBO_HITS
	if ctx.model then
		Effects.swingTrails(ctx.model, 0.35)
	end
	at(ctx, (if fighter then fighter.m1.hitDelay else 0.12) * 0.75, function()
		local root = rootOf(ctx.model)
		if not root then
			return
		end
		local base = CFrame.lookAt(root.Position, root.Position + ctx.facing)
		local tilt = if index % 2 == 0 then -28 else 28
		local frame = base * CFrame.new(0, 0.4, -1) * CFrame.Angles(0, 0, math.rad(tilt))
		local radius = if style == "Polearm" then 5.6 elseif style == "Heavy" then 5 else 4.2
		Effects.arc(frame, radius, -75, 75, ctx.color, if finisher then 1.5 else 0.9, if finisher then 0.3 else 0.2, 12)
		if finisher then
			Effects.ring(
				base * CFrame.new(0, 0.5, -radius) * CFrame.Angles(math.rad(90), 0, 0),
				ctx.color,
				0.5,
				3.5,
				0.3,
				0.4,
				14
			)
		end
		SoundController.play("swing", root.Position, 1, if finisher then 0.8 else 0.95 + index * 0.06)
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
	local ground = groundAt(ctx)
	if ground then
		Effects.ring(CFrame.new(ground + UP * 0.3), WHITE, 1, 5, 0.3, 0.3, 14)
		Effects.particles(ground + UP * 0.5, {
			texture = Effects.TEXTURE_SMOKE,
			color = DUST,
			count = 6,
			speed = 8,
			lifetime = 0.5,
			size = 1.6,
			spread = 70,
			lightEmission = 0,
		})
		SoundController.play("whoosh", ground)
	end
end

---------------------------------------------------------------------------------------------------
-- Per-move effects (keys are VfxCatalog.MOVES)

local MOVES: { [string]: (Context) -> () } = {}

-- Stonebreaker ----------------------------------------------------------------------------------

MOVES.QuakeStomp = function(ctx: Context)
	at(ctx, 0.38, function()
		local ground = groundAt(ctx)
		if not ground then
			return
		end
		Effects.shockwave(ground, ctx.color, 11, 0.6)
		Effects.debris(ground, 10, ROCK, 12, 7)
		CameraController.shakeAt(ground, 0.9, 40)
		SoundController.play("heavy", ground)
	end)
end

MOVES.BoulderHeave = function(ctx: Context)
	at(ctx, 0.12, function()
		local root = rootOf(ctx.model)
		if root then
			Effects.debris(Effects.ground(root.Position + ctx.facing * 2, 8), 5, ROCK, 3, 3)
			SoundController.play("heavy", root.Position, 0.5, 1.4)
		end
	end)
end

MOVES.GraniteHide = function(ctx: Context)
	local model = ctx.model
	local root = rootOf(model)
	if not model or not root then
		return
	end
	Effects.ring(CFrame.new(Effects.ground(root.Position, 8) + UP * 0.3), ctx.color, 1, 7, 0.45, 0.6, 18)
	SoundController.play("heavy", root.Position, 0.7, 1.3)
	local plates: { Part } = {}
	for _ = 1, 6 do
		table.insert(
			plates,
			Effects.part({
				Size = Vector3.new(1.5, 1.9, 0.45),
				Material = Enum.Material.Slate,
				Color = Color3.fromRGB(128, 114, 98),
			})
		)
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		local current = rootOf(model)
		if elapsed > 4 or not current then
			connection:Disconnect()
			for _, plate in plates do
				Effects.tween(plate, 0.25, { Transparency = 1, Size = plate.Size * 0.4 })
				Effects.clean(plate, 0.3)
			end
			return
		end
		for index, plate in plates do
			local angle = elapsed * 2.4 + index * (math.pi * 2 / #plates)
			plate.CFrame = CFrame.new(current.Position)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, math.sin(elapsed * 3 + index) * 0.7, -2.7)
		end
	end)
end

MOVES.RocklineRush = function(ctx: Context)
	for index = 0, 6 do
		at(ctx, 0.08 + index * 0.05, function()
			local ground = groundAt(ctx)
			if not ground then
				return
			end
			Effects.particles(ground + UP * 0.5, {
				texture = Effects.TEXTURE_SMOKE,
				color = DUST,
				count = 4,
				speed = 6,
				lifetime = 0.6,
				size = 2.2,
				spread = 60,
				lightEmission = 0,
			})
			if index % 2 == 0 then
				Effects.debris(ground, 2, ROCK, 3, 2.5)
			end
		end)
	end
	at(ctx, 0.1, function()
		local model = ctx.model
		if model then
			Effects.afterimage(model, ctx.color, 0.3, 0.6)
		end
		SoundController.play("lunge", ctx.origin.Position, 1, 0.7)
	end)
end

MOVES.Mountainfall = function(ctx: Context)
	at(ctx, 0.02, function()
		local ground = groundAt(ctx)
		if ground then
			Effects.shockwave(ground, ctx.color, 5, 0.4)
		end
		local model = ctx.model
		if model then
			Effects.afterimage(model, ctx.color, 0.4, 0.5)
		end
		if ctx.isLocal then
			CameraController.fovPunch(8, 0.9)
		end
		SoundController.play("whoosh", ctx.origin.Position, 1.2, 0.6)
	end)
end

-- Tide Dancer -----------------------------------------------------------------------------------

MOVES.CrescentWave = function(ctx: Context)
	at(ctx, 0.26, function()
		local root = rootOf(ctx.model)
		if root then
			Effects.arc(
				CFrame.lookAt(root.Position, root.Position + ctx.facing),
				4.5,
				-80,
				80,
				ctx.color,
				1.2,
				0.25,
				12
			)
			SoundController.play("water", root.Position, 0.7, 1.3)
		end
	end)
end

MOVES.Undertow = function(ctx: Context)
	at(ctx, 0.3, function()
		local root = rootOf(ctx.model)
		if not root then
			return
		end
		local base = CFrame.lookAt(root.Position, root.Position + ctx.facing)
		for index = 0, 4 do
			task.delay(index * 0.05, function()
				Effects.ring(
					base * CFrame.new(0, 0, -(20 - index * 4)) * CFrame.Angles(math.rad(90), 0, 0),
					ctx.color,
					4,
					1.2,
					0.35,
					0.45,
					14
				)
			end)
		end
		Effects.particles((base * CFrame.new(0, 0, -16)).Position, {
			color = MIST,
			count = 20,
			speed = 22,
			lifetime = 0.5,
			size = 1,
			spread = 25,
			cframe = CFrame.lookAt((base * CFrame.new(0, 0, -16)).Position, root.Position),
			forward = true,
		})
		SoundController.play("water", root.Position)
	end)
end

MOVES.MistStep = function(ctx: Context)
	local origin = ctx.origin.Position
	local model = ctx.model
	if model then
		Effects.afterimage(model, ctx.color, 0.45, 0.45)
	end
	local rng = Random.new()
	for _ = 1, 3 do
		local offset = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-1, 1), rng:NextNumber(-2, 2))
		Effects.sphere(origin + offset, MIST, 4, 15, 2.5, 0.65)
	end
	Effects.particles(origin, {
		texture = Effects.TEXTURE_SMOKE,
		color = MIST,
		count = 18,
		speed = 4,
		lifetime = 2.2,
		size = 5,
		lightEmission = 0.3,
	})
	SoundController.play("whoosh", origin)
end

MOVES.WhirlpoolSpin = function(ctx: Context)
	for _, t in { 0.2, 0.45, 0.7 } do
		at(ctx, t, function()
			local root = rootOf(ctx.model)
			if not root then
				return
			end
			local base = CFrame.new(root.Position + Vector3.new(0, -1.2, 0)) * CFrame.Angles(0, math.random() * 6.28, 0)
			Effects.arc(base, 7.5, -180, 180, ctx.color, 1.3, 0.3, 18)
			Effects.particles(
				root.Position,
				{ color = MIST, count = 10, speed = 18, lifetime = 0.4, size = 0.8, spread = 180 }
			)
			SoundController.play("swing", root.Position, 0.9, 0.8)
		end)
	end
end

MOVES.DrowningTide = function(ctx: Context)
	at(ctx, 0, function()
		local ground = groundAt(ctx)
		if ground then
			Effects.column(ground - ctx.facing * 3, 16, 6, ctx.color, 0.8, 0.35)
			Effects.particles(
				ground + UP,
				{ color = MIST, count = 30, speed = 20, lifetime = 0.8, size = 1.2, spread = 40 }
			)
		end
		if ctx.isLocal then
			CameraController.fovPunch(6, 1)
		end
	end)
	at(ctx, 0.58, function()
		CameraController.shakeAt(ctx.origin.Position, 0.8, 60)
		SoundController.play("water", ctx.origin.Position, 1.4, 0.7)
	end)
end

-- Lantern Fox -----------------------------------------------------------------------------------

MOVES.Foxfire = function(ctx: Context)
	at(ctx, 0.15, function()
		local root = rootOf(ctx.model)
		if root then
			Effects.particles(root.Position + ctx.facing * 2 + UP, {
				texture = Effects.TEXTURE_FIRE,
				color = EMBER,
				count = 14,
				speed = 8,
				lifetime = 0.5,
				size = 1.4,
			})
			SoundController.play("whoosh", root.Position, 0.8, 1.2)
		end
	end)
end

MOVES.FanBlaze = function(ctx: Context)
	for _, t in { 0.18, 0.38, 0.58 } do
		at(ctx, t, function()
			local root = rootOf(ctx.model)
			if not root then
				return
			end
			local base = CFrame.lookAt(root.Position, root.Position + ctx.facing)
			local mouth = base * CFrame.new(0, 0.4, -2)
			Effects.particles(mouth.Position, {
				texture = Effects.TEXTURE_FIRE,
				color = ctx.color,
				count = 30,
				speed = 30,
				lifetime = 0.45,
				size = 2.4,
				spread = 22,
				cframe = mouth,
				forward = true,
			})
			Effects.arc(base * CFrame.new(0, 0.3, -2), 9, -32, 32, ctx.color, 2.6, 0.3, 10)
			Effects.light(mouth.Position, EMBER, 18, 3, 0.3)
			SoundController.play("whoosh", root.Position, 0.9, 0.9)
		end)
	end
end

MOVES.EmberHop = function(ctx: Context)
	local origin = ctx.origin.Position
	local model = ctx.model
	if model then
		Effects.afterimage(model, ctx.color, 0.35, 0.55)
	end
	at(ctx, 0.04, function()
		local ground = Effects.ground(origin, 8)
		Effects.sphere(ground + UP * 1.5, ctx.color, 2, 15, 0.45, 0.1)
		Effects.ring(CFrame.new(ground + UP * 0.3), GOLD, 1, 9, 0.4, 0.6, 18)
		Effects.particles(
			ground + UP,
			{ texture = Effects.TEXTURE_FIRE, color = EMBER, count = 25, speed = 16, lifetime = 0.6, size = 1.8 }
		)
		Effects.light(ground + UP * 2, EMBER, 20, 4, 0.5)
		SoundController.play("heavy", ground, 0.7, 1.2)
	end)
end

MOVES.LanternSnare = function(ctx: Context)
	at(ctx, 0.22, function()
		local root = rootOf(ctx.model)
		if root then
			Effects.burst(root.Position + ctx.facing * 2 + UP, GOLD, 6, 14, 0.5, 0.25)
		end
	end)
end

MOVES.HundredLanterns = function(ctx: Context)
	at(ctx, 0.05, function()
		local root = rootOf(ctx.model)
		if not root then
			return
		end
		for index = 1, 6 do
			local start = root.Position + Vector3.new(math.cos(index) * 2, 1, math.sin(index) * 2)
			local rising = Effects.part({
				Size = Vector3.new(1.2, 1.6, 1.2),
				CFrame = CFrame.new(start),
				Color = Color3.fromRGB(255, 92, 40),
			})
			Effects.tween(
				rising,
				1.1,
				{ CFrame = CFrame.new(start + Vector3.new(0, 26, 0)), Transparency = 1 },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			Effects.clean(rising, 1.15)
		end
		Effects.light(root.Position + UP * 4, EMBER, 30, 3, 1.2)
		SoundController.play("whoosh", root.Position, 1, 0.7)
	end)
	local point = ctx.point
	if point then
		at(ctx, 0.35, function()
			local ground = CFrame.new(point + UP * 0.2)
			local warning = Effects.part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.1, 28, 28),
				CFrame = ground * CFrame.Angles(0, 0, math.rad(90)),
				Color = EMBER,
				Transparency = 0.82,
			})
			Effects.clean(warning, 2.3)
		end)
	end
end

-- Gale Courier ----------------------------------------------------------------------------------

MOVES.CycloneKick = function(ctx: Context)
	at(ctx, 0.18, function()
		local root = rootOf(ctx.model)
		if not root then
			return
		end
		local spot = Effects.ground(root.Position + ctx.facing * 3.5, 8)
		Effects.vortex(spot, ctx.color, 3.5, 10, 0.55, 5)
		Effects.particles(
			spot + UP * 2,
			{ color = WHITE, count = 12, speed = 18, lifetime = 0.5, size = 0.7, spread = 30, acceleration = UP * 20 }
		)
		SoundController.play("whoosh", root.Position, 1, 1.3)
	end)
end

MOVES.SickleBoomerang = function(ctx: Context)
	at(ctx, 0.2, function()
		local root = rootOf(ctx.model)
		if root then
			Effects.arc(CFrame.lookAt(root.Position, root.Position + ctx.facing), 3, -60, 60, ctx.color, 0.8, 0.2, 10)
		end
	end)
end

MOVES.Updraft = function(ctx: Context)
	local origin = ctx.origin.Position
	local model = ctx.model
	at(ctx, 0.03, function()
		local ground = Effects.ground(origin, 8)
		Effects.vortex(ground, ctx.color, 4.5, 15, 0.65, 6)
		Effects.ring(CFrame.new(ground + UP * 0.3), WHITE, 1, 9, 0.35, 0.4, 16)
		if model then
			Effects.afterimage(model, ctx.color, 0.4, 0.55)
		end
		SoundController.play("whoosh", origin, 1.2, 0.9)
	end)
end

MOVES.Slipstream = function(ctx: Context)
	local model = ctx.model
	if model then
		Effects.afterimage(model, ctx.color, 0.35, 0.5)
	end
	at(ctx, 0.02, function()
		local base = ctx.origin
		local rng = Random.new()
		for index = 1, 9 do
			local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-1.5, 2.5), 0)
			local line = Effects.part({
				Size = Vector3.new(0.12, 0.12, 24),
				CFrame = base * CFrame.new(offset) * CFrame.new(0, 0, -13),
				Color = if index % 2 == 0 then WHITE else ctx.color,
				Transparency = 0.15,
			})
			Effects.tween(line, 0.35, { Transparency = 1, Size = Vector3.new(0.04, 0.04, 32) })
			Effects.clean(line, 0.4)
		end
		SoundController.play("lunge", base.Position, 1, 1.2)
	end)
	at(ctx, 0.13, function()
		if model and model.Parent then
			Effects.afterimage(model, ctx.color, 0.3, 0.6)
		end
	end)
end

MOVES.ThousandGusts = function(ctx: Context)
	at(ctx, 0, function()
		local ground = groundAt(ctx)
		if ground then
			Effects.ring(CFrame.new(ground + UP * 0.3), ctx.color, 1, 10, 0.4, 0.5, 18)
		end
		if ctx.isLocal then
			CameraController.fovPunch(10, 1.3)
		end
	end)
end

-- Bell Monk -------------------------------------------------------------------------------------

MOVES.EchoStrike = function(ctx: Context)
	at(ctx, 0.2, function()
		local root = rootOf(ctx.model)
		if not root then
			return
		end
		local palm = CFrame.lookAt(root.Position, root.Position + ctx.facing) * CFrame.new(0, 0.5, -3)
		Effects.ring(palm * CFrame.Angles(math.rad(90), 0, 0), ctx.color, 0.5, 4, 0.3, 0.4, 16)
		Effects.sphere(palm.Position, WHITE, 0.5, 3, 0.18, 0)
		SoundController.play("bell", root.Position, 1, 1.1)
	end)
end

MOVES.Hush = function(ctx: Context)
	at(ctx, 0.33, function()
		local root = rootOf(ctx.model)
		if not root then
			return
		end
		Effects.sphere(root.Position, VOID_DARK, 4, 30, 0.6, 0.35)
		Effects.ring(CFrame.new(Effects.ground(root.Position, 8) + UP * 0.3), ctx.color, 2, 14, 0.5, 0.6, 24)
		if near(root.Position, 14) then
			CameraController.darkBeat(0.4)
		end
		SoundController.play("bell", root.Position, 1.2, 0.5)
	end)
end

local function voidPuff(position: Vector3, color: Color3)
	Effects.sphere(position, VOID_DARK, 1, 7, 0.3, 0.2)
	Effects.sphere(position, color, 0.5, 4.5, 0.25, 0.1)
	Effects.particles(position, { color = color, count = 14, speed = 10, lifetime = 0.45, size = 0.9 })
end

MOVES.NullStep = function(ctx: Context)
	local origin = ctx.origin.Position
	at(ctx, 0.1, function()
		voidPuff(origin, ctx.color)
		local model = ctx.model
		if model and model.Parent then
			Effects.afterimage(model, ctx.color, 0.3, 0.5)
		end
		SoundController.play("bell", origin, 0.8, 1.4)
	end)
end

MOVES.ResonantWard = function(ctx: Context)
	local model = ctx.model
	local root = rootOf(model)
	if not model or not root then
		return
	end
	local dome = Effects.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 9,
		CFrame = root.CFrame,
		Color = ctx.color,
		Transparency = 0.45,
		Material = Enum.Material.ForceField,
	})
	SoundController.play("bell", root.Position, 0.9, 0.8)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local current = rootOf(model)
		if os.clock() - started > 1 or not current then
			connection:Disconnect()
			Effects.tween(dome, 0.2, { Transparency = 1 })
			Effects.clean(dome, 0.25)
			return
		end
		dome.CFrame = current.CFrame
	end)
end

MOVES.TollOfTheDeep = function(ctx: Context)
	local point = ctx.point or (ctx.origin * CFrame.new(0, 0, -16)).Position
	local body = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(14, 15, 15),
		CFrame = CFrame.new(point + Vector3.new(0, 34, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ctx.color,
		Transparency = 1,
		Material = Enum.Material.ForceField,
	})
	local crown = Effects.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 15,
		CFrame = CFrame.new(point + Vector3.new(0, 41, 0)),
		Color = ctx.color,
		Transparency = 1,
		Material = Enum.Material.ForceField,
	})
	local marker = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, 32, 32),
		CFrame = CFrame.new(point + UP * 0.2) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ctx.color,
		Transparency = 0.8,
	})
	Effects.tween(body, 0.3, { Transparency = 0.15 })
	Effects.tween(crown, 0.3, { Transparency = 0.15 })
	at(ctx, 0.86, function()
		Effects.tween(
			body,
			0.14,
			{ CFrame = CFrame.new(point + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		Effects.tween(
			crown,
			0.14,
			{ CFrame = CFrame.new(point + Vector3.new(0, 14, 0)) },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)
		if near(point, 60) then
			CameraController.darkBeat(0.14)
		end
	end)
	at(ctx, 1.0, function()
		Effects.shockwave(point, ctx.color, 16, 0.9)
		Effects.sphere(point + UP * 4, WHITE, 6, 26, 0.35, 0)
		CameraController.shakeAt(point, 2, 90)
		if near(point, 60) then
			CameraController.flash(ctx.color, 0.35)
		end
		SoundController.play("bell", point, 1.6, 0.35)
		SoundController.play("heavy", point, 1.2, 0.5)
		for _, part in { body, crown } do
			Effects.tween(part, 0.6, { Transparency = 1 })
		end
		marker:Destroy()
	end)
	at(ctx, 1.4, function()
		Effects.ring(CFrame.new(point + UP * 0.5), ctx.color, 2, 24, 0.6, 1, 30)
		Effects.disc(CFrame.new(point + UP * 0.2), VOID_DARK, 4, 48, 0.6, 0.5, 0.15)
		SoundController.play("bell", point, 1, 0.5)
	end)
	Effects.clean(body, 1.8)
	Effects.clean(crown, 1.8)
	Effects.clean(marker, 1.2)
end

---------------------------------------------------------------------------------------------------
-- Mid-move phases (PhaseFx)

local PHASES: { [string]: (Context, Vector3) -> () } = {}

PHASES["Mountainfall:Slam"] = function(ctx: Context, position: Vector3)
	if near(position, 60) then
		CameraController.darkBeat(0.08)
	end
	task.delay(0.06, function()
		Effects.shockwave(position, ctx.color, 18, 0.9)
		Effects.ring(CFrame.new(position + UP * 0.5), WHITE, 4, 24, 0.5, 1.2, 28)
		Effects.debris(position, 18, ROCK, 20, 12)
		Effects.column(position, 26, 7, ctx.color, 0.5, 0.25)
		if near(position, 60) then
			CameraController.flash(ctx.color, 0.3)
		end
		CameraController.shakeAt(position, 2.2, 90)
		SoundController.play("heavy", position, 1.4, 0.5)
	end)
end

PHASES["EchoStrike:Echo"] = function(ctx: Context, position: Vector3)
	Effects.ring(CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0), ctx.color, 0.5, 5, 0.35, 0.45, 16)
	Effects.ring(CFrame.new(position), WHITE, 0.5, 4, 0.3, 0.3, 14)
	SoundController.play("bell", position, 1, 1.25)
end

PHASES["NullStep:Blink"] = function(ctx: Context, position: Vector3)
	voidPuff(position, ctx.color)
end

PHASES["ResonantWard:Counter"] = function(ctx: Context, position: Vector3)
	Effects.sphere(position, WHITE, 1, 10, 0.25, 0)
	Effects.ring(CFrame.new(position), ctx.color, 1, 8, 0.35, 0.6, 20)
	CameraController.shakeAt(position, 1, 40)
	SoundController.play("bell", position, 1.3, 1.5)
end

PHASES["HundredLanterns:Drop"] = function(ctx: Context, position: Vector3)
	local lantern = Effects.part({
		Size = Vector3.new(1.4, 1.9, 1.4),
		CFrame = CFrame.new(position + Vector3.new(0, 22, 0)),
		Color = Color3.fromRGB(255, 92, 40),
	})
	Effects.tween(lantern, 0.35, { CFrame = CFrame.new(position + UP) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.35, function()
		lantern:Destroy()
		Effects.sphere(position + UP * 1.5, ctx.color, 2, 12, 0.35, 0.1)
		Effects.particles(
			position + UP,
			{ texture = Effects.TEXTURE_FIRE, color = EMBER, count = 14, speed = 12, lifetime = 0.5, size = 1.5 }
		)
		Effects.light(position + UP * 2, EMBER, 16, 3, 0.35)
		SoundController.play("hit", position, 0.6, 0.8)
	end)
end

PHASES["HundredLanterns:Final"] = function(ctx: Context, position: Vector3)
	Effects.sphere(position + UP * 3, WHITE, 4, 24, 0.45, 0)
	Effects.sphere(position + UP * 3, ctx.color, 6, 30, 0.8, 0.2)
	Effects.shockwave(position, ctx.color, 12, 0.8)
	Effects.particles(
		position + UP * 2,
		{ texture = Effects.TEXTURE_FIRE, color = EMBER, count = 50, speed = 30, lifetime = 0.9, size = 2.5 }
	)
	if near(position, 60) then
		CameraController.flash(ctx.color, 0.35)
	end
	CameraController.shakeAt(position, 1.8, 80)
	SoundController.play("heavy", position, 1.3, 0.7)
end

PHASES["LanternSnare:Explode"] = function(ctx: Context, position: Vector3)
	Effects.sphere(position, WHITE, 2, 10, 0.3, 0)
	Effects.sphere(position, ctx.color, 3, 20, 0.55, 0.15)
	Effects.ring(CFrame.new(Effects.ground(position, 8) + UP * 0.3), GOLD, 1, 10, 0.45, 0.6, 18)
	Effects.particles(
		position,
		{ texture = Effects.TEXTURE_FIRE, color = EMBER, count = 30, speed = 20, lifetime = 0.7, size = 2 }
	)
	Effects.light(position, EMBER, 24, 4, 0.5)
	CameraController.shakeAt(position, 1, 50)
	SoundController.play("heavy", position, 0.9, 1.1)
end

PHASES["ThousandGusts:Blink"] = function(ctx: Context, position: Vector3)
	Effects.sphere(position + UP, WHITE, 1, 6, 0.2, 0)
	Effects.arc(
		CFrame.new(position + UP) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28),
		4,
		-90,
		90,
		ctx.color,
		1,
		0.25,
		10
	)
	SoundController.play("swing", position, 0.9, 1.4)
end

PHASES["ThousandGusts:Final"] = function(ctx: Context, position: Vector3)
	local ground = Effects.ground(position, 12)
	Effects.vortex(ground, ctx.color, 7, 16, 0.7, 6)
	Effects.shockwave(ground, WHITE, 10, 0.5)
	if near(position, 50) then
		CameraController.flash(ctx.color, 0.3)
	end
	CameraController.shakeAt(position, 1.6, 70)
	SoundController.play("heavy", position, 1, 0.9)
end

local GENERIC_PHASES: { [string]: (Context, Vector3) -> () } = {
	Slam = function(ctx: Context, position: Vector3)
		Effects.shockwave(position, ctx.color, 12, 0.7)
	end,
	Blink = function(ctx: Context, position: Vector3)
		Effects.sphere(position, ctx.color, 1, 6, 0.25, 0.1)
	end,
	Explode = function(ctx: Context, position: Vector3)
		Effects.sphere(position, ctx.color, 2, 14, 0.4, 0.1)
	end,
	Final = function(ctx: Context, position: Vector3)
		Effects.shockwave(position, ctx.color, 10, 0.6)
	end,
}

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
	local move = Fighters.findMove(fighter, moveId)
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
	if not victim or typeof(position) ~= "Vector3" then
		return
	end
	local character = localPlayer.Character
	local involved = (victim == character) or (attacker ~= nil and attacker == character)

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

	if bit32.btest(flags, Remotes.FLAG_BURN) then
		Effects.particles(
			position,
			{ texture = Effects.TEXTURE_FIRE, color = EMBER, count = 4, speed = 4, lifetime = 0.5, size = 1 }
		)
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

	local color = elementColor(attacker)
	local big = amount >= 10
	Effects.burst(position, color, if big then 12 else 7, 30, 0.8, 0.22)
	Effects.sphere(position, WHITE, 0.5, if big then 6 else 3.5, 0.15, 0)
	Effects.flash(victim, WHITE, 0.18)
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
type Visual = { parts: { VisualPart }, spin: number, spinAxis: string }
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
	local p = Effects.part(props)
	table.insert(visual.parts, { part = p, offset = offset })
	return p
end

local function makeVisual(kind: string, color: Color3, radius: number): Visual
	local visual: Visual = { parts = {}, spin = 0, spinAxis = "Y" }
	if kind == "Boulder" then
		local core = addVisualPart(visual, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * radius * 1.6,
			Color = ROCK,
			Material = Enum.Material.Slate,
		}, CFrame.new())
		addVisualPart(visual, {
			Size = Vector3.one * radius * 1.15,
			Color = Color3.fromRGB(92, 82, 72),
			Material = Enum.Material.Slate,
		}, CFrame.Angles(0.5, 0.3, 0.2))
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = Effects.TEXTURE_SMOKE
		dust.Color = ColorSequence.new(DUST)
		dust.Rate = 25
		dust.Lifetime = NumberRange.new(0.4, 0.7)
		dust.Speed = NumberRange.new(1, 3)
		dust.Size = NumberSequence.new(1.5, 0)
		dust.Parent = core
		visual.spin = 9
		visual.spinAxis = "X"
	elseif kind == "Crescent" then
		for index = 0, 8 do
			local t = index / 8
			local angle = math.rad(-75 + 150 * t)
			local taper = math.sin(math.pi * (0.05 + 0.9 * t))
			local offset = CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius * 0.6)
			addVisualPart(
				visual,
				{ Size = Vector3.new(radius * 0.45, 0.3, 0.7 * taper + 0.2), Color = color, Transparency = 0.05 },
				offset
			)
			addVisualPart(
				visual,
				{ Size = Vector3.new(radius * 0.4, 0.32, 0.3 * taper + 0.1), Color = WHITE },
				offset * CFrame.new(0, 0.02, -0.1)
			)
		end
	elseif kind == "Wave" then
		for index = -4, 4 do
			local x = index * radius * 0.25
			local curve = index * index * 0.18
			addVisualPart(
				visual,
				{ Size = Vector3.new(radius * 0.27, radius * 0.85, 1.8), Color = color, Transparency = 0.25 },
				CFrame.new(x, 0, curve)
			)
			addVisualPart(
				visual,
				{ Size = Vector3.new(radius * 0.27, 0.7, 2.4), Color = WHITE, Transparency = 0.05 },
				CFrame.new(x, radius * 0.45, curve - 0.5)
			)
		end
	elseif kind == "Foxfire" then
		local core =
			addVisualPart(visual, { Shape = Enum.PartType.Ball, Size = Vector3.one * 1.7, Color = color }, CFrame.new())
		addVisualPart(visual, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Color = WHITE }, CFrame.new())
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = Effects.TEXTURE_FIRE
		fire.Color = ColorSequence.new(EMBER, color)
		fire.LightEmission = 1
		fire.Rate = 40
		fire.Lifetime = NumberRange.new(0.25, 0.4)
		fire.Speed = NumberRange.new(0.5, 2)
		fire.Size = NumberSequence.new(1.6, 0)
		fire.Parent = core
		local light = Instance.new("PointLight")
		light.Color = EMBER
		light.Range = 10
		light.Brightness = 2
		light.Parent = core
	elseif kind == "Lantern" then
		local body = addVisualPart(
			visual,
			{ Size = Vector3.new(1.4, 1.8, 1.4), Color = Color3.fromRGB(255, 92, 40) },
			CFrame.new()
		)
		for _, y in { 1, -1 } do
			addVisualPart(visual, {
				Size = Vector3.new(1.55, 0.22, 1.55),
				Color = Color3.fromRGB(30, 20, 18),
				Material = Enum.Material.SmoothPlastic,
			}, CFrame.new(0, y, 0))
		end
		local light = Instance.new("PointLight")
		light.Color = EMBER
		light.Range = 14
		light.Brightness = 2.5
		light.Parent = body
		visual.spin = 2
	elseif kind == "Sickle" then
		local blade = addVisualPart(visual, {
			Size = Vector3.new(2.8, 0.18, 0.45),
			Color = Color3.fromRGB(200, 214, 222),
			Material = Enum.Material.Metal,
		}, CFrame.new())
		addVisualPart(visual, { Size = Vector3.new(2.7, 0.2, 0.12), Color = color }, CFrame.new(0, 0, -0.26))
		local tipA = Instance.new("Attachment")
		tipA.Position = Vector3.new(1.4, 0, 0)
		tipA.Parent = blade
		local tipB = Instance.new("Attachment")
		tipB.Position = Vector3.new(-1.4, 0, 0)
		tipB.Parent = blade
		local trail = Instance.new("Trail")
		trail.Attachment0 = tipA
		trail.Attachment1 = tipB
		trail.Color = ColorSequence.new(WHITE, color)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.15
		trail.LightEmission = 1
		trail.Parent = blade
		visual.spin = 24
	else
		addVisualPart(visual, { Shape = Enum.PartType.Ball, Size = Vector3.one * radius, Color = color }, CFrame.new())
	end
	return visual
end

local function placeVisual(visual: Visual, position: Vector3, direction: Vector3, age: number)
	local frame = CFrame.lookAt(position, position + direction)
	if visual.spin ~= 0 then
		frame *= if visual.spinAxis == "X"
			then CFrame.Angles(-age * visual.spin, 0, 0)
			else CFrame.Angles(0, age * visual.spin, 0)
	end
	for _, entry in visual.parts do
		entry.part.CFrame = frame * entry.offset
	end
end

local function destroyVisual(visual: Visual)
	for _, entry in visual.parts do
		entry.part:Destroy()
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
	local color = elementColor(owner)
	local speed = tonumber(data.speed) or 60
	local lag = math.clamp(now() - (tonumber(data.startTime) or now()), 0, 0.3)
	local direction = (data.direction :: Vector3).Unit
	local projectile: ClientProjectile = {
		id = data.id,
		kind = tostring(data.kind),
		visual = makeVisual(tostring(data.kind), color, tonumber(data.radius) or 2),
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
	placeVisual(projectile.visual, projectile.position, projectile.direction, 0)
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
	local kind = projectile.kind
	if kind == "Boulder" then
		Effects.debris(position, 8, ROCK, 6, 4)
		Effects.particles(position, {
			texture = Effects.TEXTURE_SMOKE,
			color = DUST,
			count = 10,
			speed = 10,
			lifetime = 0.7,
			size = 2.5,
			lightEmission = 0,
		})
		SoundController.play("heavy", position, 0.8, 1.1)
	elseif kind == "Crescent" or kind == "Wave" then
		Effects.particles(position, { color = MIST, count = 16, speed = 16, lifetime = 0.5, size = 1 })
		SoundController.play("water", position, 0.6, 1.2)
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
		placeVisual(projectile.visual, projectile.position, projectile.direction, age)
	end
end

---------------------------------------------------------------------------------------------------
-- The Tide Warden

local function circleTelegraph(position: Vector3, radius: number, duration: number)
	local ground = CFrame.new(position + UP * 0.15) * CFrame.Angles(0, 0, math.rad(90))
	local area = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = ground,
		Color = RED,
		Transparency = 0.78,
	})
	local fill = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.5, 0.5),
		CFrame = ground,
		Color = RED,
		Transparency = 0.45,
	})
	Effects.tween(fill, duration, { Size = Vector3.new(0.12, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	Effects.clean(area, duration + 0.05)
	Effects.clean(fill, duration + 0.05)
	Effects.ring(CFrame.new(position + UP * 0.3), RED, radius, radius, duration, 0.5, 28, 0.2)
end

local function coneTelegraph(position: Vector3, direction: Vector3, radius: number, angle: number, duration: number)
	local base = CFrame.lookAt(position + UP * 0.2, position + UP * 0.2 + flat(direction))
	local spokes = 13
	for index = 0, spokes - 1 do
		local spokeAngle = math.rad(-angle / 2 + angle * index / (spokes - 1))
		local spoke = Effects.part({
			Size = Vector3.new(0.45, 0.1, radius),
			CFrame = base * CFrame.Angles(0, -spokeAngle, 0) * CFrame.new(0, 0, -radius / 2),
			Color = RED,
			Transparency = 0.6,
		})
		Effects.tween(spoke, duration, { Transparency = 0.25 }, Enum.EasingStyle.Linear)
		Effects.clean(spoke, duration + 0.05)
	end
	Effects.arc(base, radius, -angle / 2, angle / 2, RED, 1.2, duration, 18)
end

-- A ring whose radius grows exactly like the server's Tide Toll (linear, from `startTime`).
local function tollRing(center: Vector3, speed: number, maxRadius: number, startTime: number)
	local count = 48
	local segments: { Part } = {}
	for _ = 1, count do
		table.insert(segments, Effects.part({ Size = Vector3.new(1, 2.2, 0.6), Color = TEAL, Transparency = 0.1 }))
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
			segment.Size = Vector3.new(length, 2.2, 0.6)
			segment.CFrame = CFrame.new(center + UP * 1.1)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, -math.max(radius, 0.5))
		end
	end)
end

local function onBoss(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	local hasPosition = typeof(data.position) == "Vector3"
	local position: Vector3 = if hasPosition then data.position else Vector3.zero
	if kind == "pose" then
		local model = asModel(data.model)
		if model and type(data.sequence) == "string" then
			AnimationController.play(model, data.sequence, tonumber(data.startTime))
		end
	elseif kind == "telegraph" and hasPosition then
		local duration = tonumber(data.duration) or 1
		if data.shape == "cone" and typeof(data.direction) == "Vector3" then
			coneTelegraph(position, data.direction, tonumber(data.radius) or 20, tonumber(data.angle) or 120, duration)
		else
			circleTelegraph(position, tonumber(data.radius) or 15, duration)
		end
	elseif kind == "impact" and hasPosition then
		local radius = tonumber(data.radius) or 15
		if data.kind == "sweep" and typeof(data.direction) == "Vector3" then
			local base = CFrame.lookAt(position + UP * 2, position + UP * 2 + flat(data.direction))
			Effects.arc(base, radius * 0.8, -60, 60, TEAL, 4, 0.4, 18)
			CameraController.shakeAt(position, 1.2, radius * 2)
			SoundController.play("water", position, 1.3, 0.6)
		else
			Effects.shockwave(position, TEAL, radius, 0.8)
			Effects.debris(position, 12, ROCK, radius, 8)
			CameraController.shakeAt(position, 1.6, radius * 3)
			SoundController.play("heavy", position, 1.4, 0.45)
		end
	elseif kind == "toll" and hasPosition then
		local windup = tonumber(data.windup) or 2
		local start = tonumber(data.startTime) or now()
		Effects.column(position, 40, 10, TEAL, windup, 0.55)
		SoundController.play("bell", position, 1.4, 0.4)
		tollRing(position, tonumber(data.speed) or 30, tonumber(data.maxRadius) or 80, start + windup)
		task.delay(math.max(0, start + windup - now()), function()
			Effects.disc(CFrame.new(position + UP * 0.2), TEAL, 4, 40, 0.8, 0.5, 0.15)
			CameraController.shakeAt(position, 1.4, 120)
			SoundController.play("heavy", position, 1.2, 0.4)
		end)
	elseif kind == "spawn" and hasPosition then
		local ground = Effects.ground(position, 40)
		Effects.column(ground - UP * 6, 54, 18, TEAL, 1.6, 0.35)
		Effects.shockwave(ground, TEAL, 24, 1.2)
		Effects.particles(
			ground + UP * 3,
			{ color = MIST, count = 60, speed = 40, lifetime = 1.2, size = 2.5, spread = 50 }
		)
		CameraController.shakeAt(ground, 1.8, 260)
		if near(ground, 200) then
			CameraController.flash(TEAL, 0.6, 0.2)
		end
		SoundController.play("water", ground, 1.6, 0.5)
	elseif kind == "enrage" then
		local root = rootOf(asModel(data.model))
		if root then
			Effects.sphere(root.Position, RED, 6, 40, 0.8, 0.3)
			CameraController.shakeAt(root.Position, 1, 150)
		end
	elseif kind == "defeated" and hasPosition then
		local ground = Effects.ground(position, 40)
		Effects.column(ground, 60, 14, TEAL, 2, 0.3)
		Effects.shockwave(ground, TEAL, 20, 1.2)
		Effects.burst(ground + UP * 6, WHITE, 24, 50, 1.4, 0.7)
		CameraController.shakeAt(ground, 1.5, 200)
		SoundController.play("bell", ground, 1.5, 0.6)
	end
end

---------------------------------------------------------------------------------------------------
-- "Ultimate ready" aura on every fighter whose Resonance is full

local function refreshUltAuras()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player.Character)
		local resonance = player:GetAttribute("Resonance")
		local ready = type(resonance) == "number" and resonance >= Constants.RESONANCE_MAX
		local existing = root and root:FindFirstChild("UltAura")
		if ready and root and not existing then
			local aura = Instance.new("ParticleEmitter")
			aura.Name = "UltAura"
			aura.Color = ColorSequence.new(elementColor(player.Character))
			aura.LightEmission = 1
			aura.Rate = 22
			aura.Lifetime = NumberRange.new(0.5, 0.9)
			aura.Speed = NumberRange.new(3, 6)
			aura.SpreadAngle = Vector2.new(25, 25)
			aura.Acceleration = Vector3.new(0, 8, 0)
			aura.Size = NumberSequence.new(0.6, 0)
			aura.Parent = root
		elseif not ready and existing then
			existing:Destroy()
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
			local ctx = contextFor(model, fighterId, moveId, now(), Vector3.new(0, 0, -1), nil)
			local handler = PHASES[`{moveId}:{phase}`] or GENERIC_PHASES[phase]
			if handler then
				handler(ctx, position)
			end
		end
	)

	Remotes.HitFx.OnClientEvent:Connect(onHit)

	Remotes.ProjectileFx.OnClientEvent:Connect(function(action: string, a: any, b: any, c: any)
		if action == "spawn" then
			onProjectileSpawn(a)
		elseif action == "end" then
			onProjectileEnd(a, b, c)
		end
	end)

	Remotes.BossFx.OnClientEvent:Connect(onBoss)

	RunService.RenderStepped:Connect(stepProjectiles)

	task.spawn(function()
		while true do
			refreshUltAuras()
			task.wait(0.5)
		end
	end)
end

return VfxController
