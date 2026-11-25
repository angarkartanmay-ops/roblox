--!strict
-- Asset-free VFX primitives: everything is built from neon parts, built-in particle textures,
-- trails and lights, tweened locally on each client. Style: white-hot core, saturated rim,
-- hard shapes, short holds (see the roblox-vfx anime_cel notes).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Effects = {}

Effects.TEXTURE_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
Effects.TEXTURE_FIRE = "rbxasset://textures/particles/fire_main.dds"
Effects.TEXTURE_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local WHITE = Color3.new(1, 1, 1)

local fxFolder: Folder? = nil

function Effects.folder(): Folder
	local existing = fxFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "ClientFx"
	created.Parent = Workspace
	fxFolder = created
	return created
end

function Effects.clean(instance: Instance, delay: number)
	task.delay(delay, function()
		instance:Destroy()
	end)
end

function Effects.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = Effects.folder()
	return p
end

function Effects.tween(
	instance: Instance,
	time: number,
	goal: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = false

-- Ground point below `position`, ignoring characters, NPCs and effects.
function Effects.ground(position: Vector3, depth: number?): Vector3
	local ignore: { Instance } = { Effects.folder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local dummies = Workspace:FindFirstChild("Dummies")
	if dummies then
		table.insert(ignore, dummies)
	end
	local creatures = Workspace:FindFirstChild("WildCreatures")
	if creatures then
		table.insert(ignore, creatures)
	end
	groundParams.FilterDescendantsInstances = ignore
	local result =
		Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -((depth or 40) + 3), 0), groundParams)
	return if result then result.Position else position
end

-- Expanding, fading sphere.
function Effects.sphere(
	position: Vector3,
	color: Color3,
	fromSize: number,
	toSize: number,
	duration: number,
	transparency: number?
): Part
	local ball = Effects.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * fromSize,
		CFrame = CFrame.new(position),
		Color = color,
		Transparency = transparency or 0.15,
	})
	Effects.tween(ball, duration, { Size = Vector3.one * toSize, Transparency = 1 })
	Effects.clean(ball, duration + 0.05)
	return ball
end

-- Flat expanding disc lying in the cframe's XZ plane.
function Effects.disc(
	cframe: CFrame,
	color: Color3,
	fromDiameter: number,
	toDiameter: number,
	duration: number,
	transparency: number?,
	thickness: number?
): Part
	local depth = thickness or 0.2
	local disc = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(depth, fromDiameter, fromDiameter),
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency or 0.35,
	})
	Effects.tween(disc, duration, { Size = Vector3.new(depth, toDiameter, toDiameter), Transparency = 1 })
	Effects.clean(disc, duration + 0.05)
	return disc
end

-- Expanding ring made of segments in the cframe's XZ plane.
function Effects.ring(
	cframe: CFrame,
	color: Color3,
	fromRadius: number,
	toRadius: number,
	duration: number,
	height: number?,
	segments: number?,
	transparency: number?
)
	local count = segments or 20
	local tall = height or 0.6
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		local spin = cframe * CFrame.Angles(0, angle, 0)
		local fromLength = math.max(0.2, 2 * math.pi * fromRadius / count * 1.15)
		local toLength = math.max(0.2, 2 * math.pi * toRadius / count * 1.15)
		local segment = Effects.part({
			Size = Vector3.new(fromLength, tall, 0.35),
			CFrame = spin * CFrame.new(0, 0, -fromRadius),
			Color = color,
			Transparency = transparency or 0.05,
		})
		Effects.tween(segment, duration, {
			CFrame = spin * CFrame.new(0, 0, -toRadius),
			Size = Vector3.new(toLength, tall * 0.3, 0.2),
			Transparency = 1,
		})
		Effects.clean(segment, duration + 0.05)
	end
end

-- Crescent slash in the cframe's XZ plane (angles in degrees, 0 = straight ahead, -Z).
function Effects.arc(
	cframe: CFrame,
	radius: number,
	fromAngle: number,
	toAngle: number,
	color: Color3,
	width: number,
	duration: number,
	segments: number?
)
	local count = segments or 12
	for index = 0, count - 1 do
		local t = (index + 0.5) / count
		local angle = math.rad(fromAngle + (toAngle - fromAngle) * t)
		local taper = math.sin(math.pi * t)
		local length = math.abs(math.rad(toAngle - fromAngle)) * radius / count * 1.25
		local spin = cframe * CFrame.Angles(0, -angle, 0)
		for layer = 1, 2 do
			local core = layer == 2
			local piece = Effects.part({
				Size = Vector3.new(
					math.max(0.15, length),
					if core then 0.12 else 0.2,
					math.max(0.12, width * taper * (if core then 0.45 else 1))
				),
				CFrame = spin * CFrame.new(0, if core then 0.06 else 0, -radius),
				Color = if core then WHITE else color,
				Transparency = if core then 0 else 0.1,
			})
			Effects.tween(piece, duration, {
				CFrame = spin * CFrame.new(0, 0, -radius * 1.18),
				Transparency = 1,
			})
			Effects.clean(piece, duration + 0.05)
		end
	end
end

-- Neon sparks flying outward.
function Effects.burst(position: Vector3, color: Color3, count: number, speed: number, size: number, lifetime: number)
	local rng = Random.new()
	for _ = 1, count do
		local direction = rng:NextUnitVector()
		direction = Vector3.new(direction.X, math.abs(direction.Y) * 0.8 + 0.2, direction.Z).Unit
		local spark = Effects.part({
			Size = Vector3.new(size * 0.35, size * 0.35, size * 1.6),
			CFrame = CFrame.lookAt(position, position + direction),
			Color = if rng:NextNumber() < 0.35 then WHITE else color,
		})
		local travel = direction * speed * lifetime * rng:NextNumber(0.6, 1.1)
		Effects.tween(spark, lifetime, {
			CFrame = CFrame.lookAt(position + travel, position + travel * 2)
				+ Vector3.new(0, -speed * lifetime * 0.25, 0),
			Size = Vector3.new(0.05, 0.05, size * 0.3),
			Transparency = 1,
		})
		Effects.clean(spark, lifetime + 0.05)
	end
end

-- Rock chunks thrown up and falling back (anchored, so they never push characters).
function Effects.debris(position: Vector3, count: number, color: Color3, spread: number, height: number)
	local rng = Random.new()
	for _ = 1, count do
		local size = rng:NextNumber(0.6, 1.6)
		local rock = Effects.part({
			Size = Vector3.new(size, size * rng:NextNumber(0.6, 1), size),
			CFrame = CFrame.new(position) * CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0),
			Color = color,
			Material = Enum.Material.Slate,
		})
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(spread * 0.4, spread)
		local apex = position
			+ Vector3.new(
				math.cos(angle) * distance * 0.5,
				rng:NextNumber(height * 0.5, height),
				math.sin(angle) * distance * 0.5
			)
		local landing = position + Vector3.new(math.cos(angle) * distance, -0.5, math.sin(angle) * distance)
		local up = rng:NextNumber(0.25, 0.4)
		Effects.tween(
			rock,
			up,
			{ CFrame = CFrame.new(apex) * CFrame.Angles(rng:NextNumber(0, 6.28), 0, rng:NextNumber(0, 6.28)) }
		)
		task.delay(up, function()
			if rock.Parent then
				Effects.tween(
					rock,
					up * 1.1,
					{ CFrame = CFrame.new(landing) },
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				)
				task.delay(up * 1.1 + 0.6, function()
					if rock.Parent then
						Effects.tween(rock, 0.4, { Transparency = 1, Size = rock.Size * 0.3 })
					end
				end)
			end
		end)
		Effects.clean(rock, up * 2.2 + 1.2)
	end
end

-- Vertical pillar that shoots up and fades.
function Effects.column(
	position: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	duration: number,
	transparency: number?
): Part
	local pillar = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency or 0.3,
	})
	Effects.tween(pillar, duration * 0.35, {
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	task.delay(duration * 0.35, function()
		if pillar.Parent then
			Effects.tween(
				pillar,
				duration * 0.65,
				{ Size = Vector3.new(height, diameter * 0.2, diameter * 0.2), Transparency = 1 }
			)
		end
	end)
	Effects.clean(pillar, duration + 0.05)
	return pillar
end

-- Stacked rotating rings rising from the ground (tornado / whirlpool).
function Effects.vortex(
	position: Vector3,
	color: Color3,
	radius: number,
	height: number,
	duration: number,
	layers: number?
)
	local count = layers or 5
	for layer = 0, count - 1 do
		local t = layer / math.max(1, count - 1)
		local base = CFrame.new(position + Vector3.new(0, t * height, 0)) * CFrame.Angles(0, t * 2, 0)
		task.delay(t * duration * 0.3, function()
			Effects.arc(base, radius * (0.55 + t * 0.6), -150, 150, color, 0.7, duration * 0.6, 10)
		end)
	end
end

function Effects.particles(
	position: Vector3,
	options: {
		texture: string?,
		color: Color3,
		count: number,
		speed: number?,
		lifetime: number?,
		size: number?,
		spread: number?,
		acceleration: Vector3?,
		lightEmission: number?,
		cframe: CFrame?, -- orient the emitter (with forward = true it sprays along LookVector)
		forward: boolean?,
	}
)
	local holder =
		Effects.part({ Size = Vector3.one * 0.2, CFrame = options.cframe or CFrame.new(position), Transparency = 1 })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = options.texture or Effects.TEXTURE_SPARK
	emitter.Color = ColorSequence.new(options.color)
	emitter.LightEmission = options.lightEmission or 1
	emitter.Enabled = false
	local life = options.lifetime or 0.8
	emitter.Lifetime = NumberRange.new(life * 0.6, life)
	local speed = options.speed or 10
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	local spread = options.spread or 180
	emitter.SpreadAngle = Vector2.new(spread, spread)
	emitter.Acceleration = options.acceleration or Vector3.zero
	local size = options.size or 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	if options.forward then
		emitter.EmissionDirection = Enum.NormalId.Front
	end
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = holder
	emitter:Emit(options.count)
	Effects.clean(holder, life + 0.2)
end

function Effects.light(position: Vector3, color: Color3, range: number, brightness: number, duration: number)
	local holder = Effects.part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(position), Transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = holder
	Effects.tween(light, duration, { Brightness = 0 })
	Effects.clean(holder, duration + 0.05)
end

local highlightCount = 0
-- Contact flash on a model (capped: the engine renders at most 31 highlights).
function Effects.flash(model: Model, color: Color3, duration: number)
	if highlightCount >= 12 or model.Parent == nil then
		return
	end
	highlightCount += 1
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = WHITE
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = Effects.folder()
	Effects.tween(highlight, duration, { FillTransparency = 1, OutlineTransparency = 1 })
	task.delay(duration + 0.05, function()
		highlight:Destroy()
		highlightCount -= 1
	end)
end

-- Neon ghost copy of a model's visible parts (dashes, blinks).
function Effects.afterimage(model: Model, color: Color3, duration: number, transparency: number?)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.9 and descendant.Name ~= "HumanoidRootPart" then
			if descendant.Size.Magnitude < 14 then
				local wasArchivable = descendant.Archivable
				descendant.Archivable = true
				local ghost = descendant:Clone()
				descendant.Archivable = wasArchivable
				if ghost then
					ghost:ClearAllChildren()
					ghost.Anchored = true
					ghost.CanCollide = false
					ghost.CanQuery = false
					ghost.CanTouch = false
					ghost.CastShadow = false
					ghost.Massless = true
					ghost.Material = Enum.Material.Neon
					ghost.Color = color
					ghost.Transparency = transparency or 0.55
					ghost.Parent = Effects.folder()
					Effects.tween(ghost, duration, { Transparency = 1 })
					Effects.clean(ghost, duration + 0.05)
				end
			end
		end
	end
end

local trailTokens: { [Model]: number } = {}
-- Switch on a character's weapon swing trails for `duration` seconds.
function Effects.swingTrails(model: Model, duration: number)
	local weapon = model:FindFirstChild("Weapon")
	if not weapon then
		return
	end
	local token = (trailTokens[model] or 0) + 1
	trailTokens[model] = token
	for _, child in weapon:GetChildren() do
		if child:IsA("Trail") then
			child.Enabled = true
		end
	end
	task.delay(duration, function()
		if trailTokens[model] ~= token then
			return
		end
		trailTokens[model] = nil
		if weapon.Parent then
			for _, child in weapon:GetChildren() do
				if child:IsA("Trail") then
					child.Enabled = false
				end
			end
		end
	end)
end

-- Ground impact: flash disc, expanding ring, dust and light.
function Effects.shockwave(position: Vector3, color: Color3, radius: number, duration: number)
	local ground = CFrame.new(position + Vector3.new(0, 0.15, 0))
	Effects.disc(ground, WHITE, radius * 0.3, radius * 1.4, duration * 0.45, 0.2, 0.25)
	Effects.disc(ground, color, radius * 0.5, radius * 2.1, duration, 0.4, 0.15)
	Effects.ring(ground * CFrame.new(0, 0.4, 0), color, radius * 0.3, radius, duration * 0.8, 0.9, 24)
	Effects.particles(position + Vector3.new(0, 1, 0), {
		texture = Effects.TEXTURE_SMOKE,
		color = Color3.fromRGB(170, 160, 150),
		count = math.floor(radius),
		speed = radius * 1.4,
		lifetime = 0.9,
		size = 2.5,
		spread = 80,
		lightEmission = 0,
	})
	Effects.light(position + Vector3.new(0, 3, 0), color, radius * 2, 4, duration)
end

-- A small paper lantern model (projectile, drops).
function Effects.lantern(cframe: CFrame, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Lantern"
	local body = Effects.part({
		Size = Vector3.new(1.3, 1.7, 1.3) * s,
		CFrame = cframe,
		Color = Color3.fromRGB(255, 92, 40),
		Transparency = 0.05,
	})
	body.Name = "Body"
	body.Parent = model
	for _, y in { 0.95, -0.95 } do
		local cap = Effects.part({
			Size = Vector3.new(1.45, 0.2, 1.45) * s,
			CFrame = cframe * CFrame.new(0, y * s, 0),
			Color = Color3.fromRGB(30, 20, 18),
			Material = Enum.Material.SmoothPlastic,
		})
		cap.Parent = model
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = 10 * s
	light.Brightness = 2
	light.Parent = body
	model.PrimaryPart = body
	model.Parent = Effects.folder()
	return model
end

return Effects
