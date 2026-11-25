--!strict
-- The Wilds on the client: draws every creature attack's telegraph from the geometry the server
-- sent (WildsFx), plays the creature's pose stretched to its windup and the impact when it lands;
-- shows a banner when the soul walks into a new zone, a field boss bar near a warden, a minimap
-- (top-left, under the Petals) and the full world map on M. Everything is drawn with plain Frames
-- and neon parts, so it renders without the asset CDN.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local FarShore = require(ReplicatedStorage.Shared.FarShore)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Wilds = require(ReplicatedStorage.Shared.Wilds)
local Effects = require("../Lib/Effects")
local Remotes = require("../Lib/Remotes")
local UiKit = require("../Lib/UiKit")
local AnimationController = require("./AnimationController")
local SelectController = require("./SelectController")

type Attack = Wilds.Attack

local WildsController = {}

local localPlayer = Players.LocalPlayer
local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)
local BOSS_BAR_RANGE = 140

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

---------------------------------------------------------------------------------------------------
-- Telegraphs

local function groundDisc(position: Vector3, radius: number, color: Color3, transparency: number, life: number): Part
	local disc = Effects.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = CFrame.new(position + UP * 0.12) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = transparency,
	})
	Effects.clean(disc, life)
	return disc
end

local function circleTell(position: Vector3, radius: number, duration: number, color: Color3)
	groundDisc(position, radius, color, 0.82, duration + 0.05)
	local fill = groundDisc(position, 0.3, color, 0.45, duration + 0.05)
	fill.Size = Vector3.new(0.12, 0.5, 0.5)
	Effects.tween(fill, duration, { Size = Vector3.new(0.12, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	Effects.ring(CFrame.new(position + UP * 0.3), color, radius, radius, duration, 0.5, 28, 0.25)
end

local function laneTell(
	origin: Vector3,
	direction: Vector3,
	length: number,
	width: number,
	duration: number,
	color: Color3
)
	local base = CFrame.lookAt(origin + UP * 0.2, origin + UP * 0.2 + direction)
	local lane = Effects.part({
		Size = Vector3.new(width, 0.1, length),
		CFrame = base * CFrame.new(0, 0, -length / 2),
		Color = color,
		Transparency = 0.8,
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
	for _, side in { -1, 1 } do
		local edge = Effects.part({
			Size = Vector3.new(0.25, 0.2, length),
			CFrame = base * CFrame.new(side * width / 2, 0.05, -length / 2),
			Color = color,
			Transparency = 0.2,
		})
		Effects.clean(edge, duration + 0.05)
	end
	Effects.clean(lane, duration + 0.05)
	Effects.clean(fill, duration + 0.05)
end

local function coneTell(
	origin: Vector3,
	facing: Vector3,
	radius: number,
	angle: number,
	duration: number,
	color: Color3
)
	local base = CFrame.lookAt(origin + UP * 0.18, origin + UP * 0.18 + facing)
	local rays = math.max(5, math.floor(angle / 9))
	local step = math.rad(angle * 2 / rays)
	for index = 0, rays - 1 do
		local yaw = -math.rad(angle) + step * (index + 0.5)
		local spin = base * CFrame.Angles(0, yaw, 0)
		local width = radius * step * 1.1
		local ray = Effects.part({
			Size = Vector3.new(width, 0.1, 0.5),
			CFrame = spin * CFrame.new(0, 0, -0.25),
			Color = color,
			Transparency = 0.7,
		})
		Effects.tween(
			ray,
			duration,
			{ Size = Vector3.new(width, 0.1, radius), CFrame = spin * CFrame.new(0, 0, -radius / 2) },
			Enum.EasingStyle.Linear
		)
		Effects.clean(ray, duration + 0.05)
	end
	Effects.arc(base, radius, -angle, angle, color, 0.6, duration, rays)
end

local function donutTell(origin: Vector3, inner: number, outer: number, duration: number, color: Color3)
	groundDisc(origin, outer, color, 0.7, duration + 0.05)
	local safe = groundDisc(origin + UP * 0.03, inner, Color3.fromRGB(240, 236, 220), 0.35, duration + 0.05)
	safe.Material = Enum.Material.Neon
	Effects.ring(CFrame.new(origin + UP * 0.3), color, outer, outer, duration, 0.8, 36, 0.15)
	Effects.ring(CFrame.new(origin + UP * 0.3), WHITE, inner, inner, duration, 0.6, 18, 0.1)
end

---------------------------------------------------------------------------------------------------
-- Impacts

local function circleImpact(position: Vector3, radius: number, color: Color3, creature: Wilds.Creature)
	Effects.shockwave(position, color, radius, 0.5)
	if creature.phase == "Earth" then
		Effects.debris(
			position,
			math.clamp(math.floor(radius), 4, 12),
			Color3.fromRGB(120, 104, 88),
			radius,
			radius * 0.8
		)
	else
		Effects.burst(position + UP, color, 10, radius * 2, 0.6, 0.45)
	end
end

local function laneImpact(origin: Vector3, direction: Vector3, length: number, width: number, color: Color3)
	local base = CFrame.lookAt(origin + UP * 1.2, origin + UP * 1.2 + direction)
	local slab = Effects.part({
		Size = Vector3.new(width, 2.2, length),
		CFrame = base * CFrame.new(0, 0, -length / 2),
		Color = color,
		Transparency = 0.25,
	})
	Effects.tween(slab, 0.4, { Size = Vector3.new(width * 1.2, 0.2, length), Transparency = 1 })
	Effects.clean(slab, 0.45)
	Effects.burst(origin + direction * length + UP, color, 8, 20, 0.5, 0.35)
end

local function shoot(start: Vector3, direction: Vector3, attack: Attack, color: Color3, startTime: number)
	local speed = attack.speed or 50
	local reach = attack.length or 40
	local size = (attack.radius or 2.5) * 0.7
	local orb = Effects.part({
		Shape = if attack.id == "NailThrow" then Enum.PartType.Block else Enum.PartType.Ball,
		Size = if attack.id == "NailThrow" then Vector3.new(0.25, 0.25, 2.2) else Vector3.one * size,
		CFrame = CFrame.lookAt(start, start + direction),
		Color = color,
		Material = if attack.id == "NailThrow" then Enum.Material.Metal else Enum.Material.Neon,
	})
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Range = 8
	glow.Brightness = 1.2
	glow.Parent = orb
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local travelled = (Workspace:GetServerTimeNow() - startTime) * speed
		local here = start + direction * math.min(travelled, reach)
		orb.CFrame = CFrame.lookAt(here, here + direction)
		local done = travelled >= reach
		if not done then
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and (root.Position - here).Magnitude <= (attack.radius or 2.5) + 1 then
					done = true
					break
				end
			end
		end
		if done then
			if connection then
				connection:Disconnect()
			end
			Effects.burst(here, color, 8, 14, 0.4, 0.3)
			orb:Destroy()
		end
	end)
	Effects.clean(orb, reach / speed + 0.5)
end

local function fadeModel(model: Model, duration: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			Effects.tween(part, duration, { Transparency = 1 })
		elseif part:IsA("BillboardGui") then
			part.Enabled = false
		end
	end
end

---------------------------------------------------------------------------------------------------
-- WildsFx

local function onWildsFx(model: Model?, creatureId: unknown, attackId: unknown, startTime: unknown, data: unknown)
	if not model or type(creatureId) ~= "string" or type(attackId) ~= "string" or type(startTime) ~= "number" then
		return
	end
	local creature = Wilds.creature(creatureId)
	if not creature then
		return
	end
	local info: { [string]: any } = if type(data) == "table" then data :: any else {}
	local origin: Vector3 = if typeof(info.origin) == "Vector3" then info.origin else model:GetPivot().Position
	local facing: Vector3 = if typeof(info.facing) == "Vector3"
		then flat(info.facing)
		else flat(model:GetPivot().LookVector)
	local tint = Phases.color(creature.phase)

	if attackId == "Death" then
		AnimationController.stop(model)
		Effects.burst(origin, tint, 16, 18, 0.7, 0.6)
		Effects.sphere(origin, tint, 2, 6 * creature.scale, 0.5, 0.3)
		fadeModel(model, 1.2)
		return
	elseif attackId == "Enrage" then
		Effects.flash(model, Color3.fromRGB(255, 60, 40), 0.8)
		Effects.shockwave(origin - UP * 3 * creature.scale, Color3.fromRGB(255, 60, 40), 22, 0.9)
		return
	end

	local attack = Wilds.attack(creatureId, attackId)
	if not attack then
		return
	end
	local color = Wilds.color(attack.color)
	local now = Workspace:GetServerTimeNow()

	if info.stage == 2 then
		-- Wedding Procession: she reappears behind the soul and strikes.
		Effects.burst(origin + UP * 3, color, 18, 22, 0.6, 0.5)
		Effects.afterimage(model, color, 0.4, 0.4)
		AnimationController.playScaled(model, "Wild_Swipe", startTime - 0.6, 0.4)
		coneTell(origin, facing, attack.radius or 10, attack.angle or 60, 0.4, color)
		task.delay(0.4, function()
			Effects.arc(
				CFrame.lookAt(origin + UP * 3, origin + UP * 3 + facing),
				attack.radius or 10,
				-(attack.angle or 60),
				attack.angle or 60,
				color,
				2.2,
				0.35,
				14
			)
		end)
		return
	end

	AnimationController.playScaled(model, attack.pose, startTime, attack.windup)
	local remaining = attack.windup - (now - startTime)
	if remaining <= 0.02 then
		return
	end

	local kind = attack.kind
	if kind == "circle" then
		local points = if type(info.points) == "table" then info.points else { origin }
		for _, point in points do
			if typeof(point) == "Vector3" then
				circleTell(point, attack.radius or 6, remaining, color)
				if attack.id == "ThousandLanterns" then
					local lantern = Effects.lantern(CFrame.new(point + UP * 40), 1.4)
					local body = lantern:FindFirstChild("Body")
					if body and body:IsA("BasePart") then
						for _, piece in lantern:GetChildren() do
							if piece:IsA("BasePart") then
								local offset = piece.CFrame.Position - body.Position
								Effects.tween(
									piece,
									remaining,
									{ CFrame = CFrame.new(point + UP * 1 + offset) },
									Enum.EasingStyle.Quad,
									Enum.EasingDirection.In
								)
							end
						end
					end
					Effects.clean(lantern, remaining + 0.05)
				end
			end
		end
		task.delay(remaining, function()
			for _, point in points do
				if typeof(point) == "Vector3" then
					circleImpact(point, attack.radius or 6, color, creature)
				end
			end
		end)
	elseif kind == "cone" then
		coneTell(origin, facing, attack.radius or 8, attack.angle or 45, remaining, color)
		task.delay(remaining, function()
			Effects.arc(
				CFrame.lookAt(origin + UP * 2, origin + UP * 2 + facing),
				(attack.radius or 8) * 0.8,
				-(attack.angle or 45),
				attack.angle or 45,
				color,
				1.8,
				0.3,
				12
			)
		end)
	elseif kind == "lane" then
		local directions = if type(info.directions) == "table" then info.directions else { facing }
		for _, direction in directions do
			if typeof(direction) == "Vector3" then
				laneTell(origin, flat(direction), attack.length or 12, attack.width or 5, remaining, color)
			end
		end
		task.delay(remaining, function()
			for _, direction in directions do
				if typeof(direction) == "Vector3" then
					laneImpact(origin, flat(direction), attack.length or 12, attack.width or 5, color)
				end
			end
		end)
	elseif kind == "charge" then
		laneTell(origin, facing, attack.length or 20, attack.width or 6, remaining, color)
		task.delay(remaining, function()
			Effects.afterimage(model, color, 0.45, 0.35)
		end)
	elseif kind == "donut" then
		donutTell(origin, attack.inner or 6, attack.radius or 20, remaining, color)
		task.delay(remaining, function()
			Effects.ring(
				CFrame.new(origin + UP * 0.5),
				color,
				attack.inner or 6,
				(attack.radius or 20) + 4,
				0.6,
				2.5,
				40
			)
			Effects.shockwave(origin, color, attack.radius or 20, 0.7)
		end)
	elseif kind == "projectile" then
		local start: Vector3 = if typeof(info.start) == "Vector3" then info.start else origin + UP * 3
		local directions = if type(info.directions) == "table" then info.directions else { facing }
		for _, direction in directions do
			if typeof(direction) == "Vector3" then
				laneTell(origin, flat(direction), math.min(attack.length or 30, 18), 1.4, remaining, color)
			end
		end
		task.delay(remaining, function()
			for _, direction in directions do
				if typeof(direction) == "Vector3" then
					shoot(start, direction.Unit, attack, color, startTime + attack.windup)
				end
			end
		end)
	elseif kind == "blink" then
		Effects.vortex(origin + UP * 0.5, color, 3 * creature.scale, 6 * creature.scale, remaining)
		Effects.afterimage(model, color, remaining, 0.5)
	end
end

---------------------------------------------------------------------------------------------------
-- HUD: banner, boss bar, minimap, world map

local gui: ScreenGui
local banner: { frame: Frame, title: TextLabel, subtitle: TextLabel, rule: TextLabel }
local bossBar: { frame: Frame, name: TextLabel, epithet: TextLabel, fill: Frame, text: TextLabel, glyph: TextLabel }
local minimap: { frame: Frame, world: Frame, arrow: Frame, bosses: { [string]: Frame } }
local worldMap: { frame: Frame, player: Frame, bosses: { [string]: Frame } }
local bannerToken = 0
local lastZone: string? = nil

local function circle(
	parent: Instance,
	center: Vector2,
	radius: number,
	color: Color3,
	transparency: number,
	z: number?
): Frame
	local frame = UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(radius * 2, radius * 2),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = z or 2,
		Parent = parent,
	})
	UiKit.corner(math.ceil(radius) + 1).Parent = frame
	return frame
end

local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, z: number?): Frame
	local middle = (a + b) / 2
	local delta = b - a
	return UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(middle.X, middle.Y),
		Size = UDim2.fromOffset(delta.Magnitude, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z or 2,
		Parent = parent,
	})
end

local SHORE_CENTER = Vector2.new(0, 0)
local SHORE_RADIUS = 285

-- Draw the whole world into `parent` at `scale` pixels per stud; world (x, z) maps to
-- ((x - origin.X) * scale, (z - origin.Y) * scale). Returns the boss marker per region.
local function drawWorld(parent: Frame, scale: number, origin: Vector2, labels: boolean): { [string]: Frame }
	local function at(x: number, z: number): Vector2
		return Vector2.new((x - origin.X) * scale, (z - origin.Y) * scale)
	end
	-- bridges first, under the islands
	for _, region in Wilds.REGIONS do
		line(
			parent,
			at(region.bridgeFrom[1], region.bridgeFrom[2]),
			at(region.bridgeTo[1], region.bridgeTo[2]),
			math.max(2, 8 * scale),
			Color3.fromRGB(150, 112, 74),
			2
		)
	end
	circle(parent, at(SHORE_CENTER.X, SHORE_CENTER.Y), SHORE_RADIUS * scale, Color3.fromRGB(96, 88, 74), 0.1, 3)
	for _, zone in FarShore.ZONES do
		local color = if zone.rule == "safe"
			then Color3.fromRGB(255, 205, 120)
			elseif zone.rule == "nopvp" then Color3.fromRGB(120, 200, 230)
			else Color3.fromRGB(200, 70, 70)
		circle(parent, at(zone.center[1], zone.center[2]), zone.radius * scale, color, 0.7, 4)
	end
	local bosses: { [string]: Frame } = {}
	for _, region in Wilds.REGIONS do
		local tint = Phases.color(region.phase):Lerp(Color3.fromRGB(70, 64, 58), 0.55)
		circle(parent, at(region.center[1], region.center[2]), region.radius * scale, tint, 0.1, 3)
		circle(
			parent,
			at(region.arena[1], region.arena[2]),
			region.arenaRadius * scale,
			Color3.fromRGB(200, 40, 40),
			0.65,
			4
		)
		local boss = Wilds.creature(region.boss)
		local marker = circle(
			parent,
			at(region.arena[1], region.arena[2]),
			math.max(7, 9 * scale * 2),
			Color3.fromRGB(30, 10, 10),
			0.05,
			7
		)
		UiKit.stroke(Color3.fromRGB(230, 60, 50), 2).Parent = marker
		UiKit.label({
			Size = UDim2.fromScale(1, 1),
			Text = if boss then boss.glyph else "!",
			TextScaled = true,
			Font = UiKit.HEAVY_FONT,
			TextColor3 = Color3.fromRGB(255, 220, 200),
			ZIndex = 8,
			Parent = marker,
		})
		bosses[region.id] = marker
		if labels then
			local spot = at(region.center[1], region.center[2] + region.radius + 14)
			UiKit.label({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(spot.X, spot.Y),
				Size = UDim2.fromOffset(240, 20),
				Text = region.title,
				Font = UiKit.HEAVY_FONT,
				TextSize = 16,
				ZIndex = 9,
				Parent = parent,
			})
		end
	end
	for _, camp in Wilds.CAMPS do
		local x, z = Wilds.campPosition(camp)
		local dot = circle(parent, at(x, z), math.max(3, 10 * scale), Color3.fromRGB(230, 120, 60), 0.15, 6)
		UiKit.stroke(Color3.fromRGB(20, 14, 12), 1).Parent = dot
	end
	local landing = at(0, 150)
	circle(parent, landing, math.max(4, 6 * scale), Color3.fromRGB(255, 205, 120), 0, 6)
	if labels then
		UiKit.label({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(landing.X, landing.Y + 8),
			Size = UDim2.fromOffset(200, 18),
			Text = "Ferry Landing",
			TextSize = 14,
			ZIndex = 9,
			Parent = parent,
		})
		local grove = at(FarShore.GROVE_CENTER[1], FarShore.GROVE_CENTER[3])
		UiKit.label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(grove.X, grove.Y),
			Size = UDim2.fromOffset(200, 18),
			Text = "Elder's Grove",
			TextSize = 14,
			ZIndex = 9,
			Parent = parent,
		})
	end
	return bosses
end

local function arrow(parent: Instance, size: number): Frame
	local holder = UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = parent,
	})
	local tip = UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size * 0.62, size * 0.62),
		Rotation = 45,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 21,
		Parent = holder,
	})
	UiKit.stroke(Color3.fromRGB(20, 20, 26), 2).Parent = tip
	UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.fromOffset(3, size * 0.5),
		BackgroundColor3 = Color3.fromRGB(235, 70, 60),
		BorderSizePixel = 0,
		ZIndex = 22,
		Parent = holder,
	})
	return holder
end

local MINI_SIZE = 168
local MINI_SCALE = 0.55
local MAP_SIZE = 600
local MAP_SCALE = MAP_SIZE / 1620
-- centred on the middle of everything drawn: x -750..770, z -790..290
local MAP_ORIGIN = Vector2.new(10, -250) - Vector2.new(MAP_SIZE, MAP_SIZE) / 2 / MAP_SCALE

local function buildHud()
	gui = UiKit.new("ScreenGui", {
		Name = "WildsHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 11,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})

	-- Zone banner
	local bannerFrame = UiKit.new("Frame", {
		Name = "ZoneBanner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(760, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = bannerFrame
	UiKit.autoScale(bannerScale, 0.55, 1.3)
	local title = UiKit.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 56),
		Font = UiKit.TITLE_FONT,
		TextSize = 52,
		TextColor3 = UiKit.PAPER,
		Parent = bannerFrame,
	})
	UiKit.textStroke(UiKit.OUTLINE, 3).Parent = title
	local subtitle = UiKit.label({
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 26),
		Font = UiKit.BODY_FONT,
		TextSize = 20,
		TextColor3 = UiKit.INK_DIM,
		Parent = bannerFrame,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = subtitle
	local rule = UiKit.label({
		Name = "Rule",
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 0, 22),
		Font = UiKit.HEAVY_FONT,
		TextSize = 16,
		Parent = bannerFrame,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = rule
	banner = { frame = bannerFrame, title = title, subtitle = subtitle, rule = rule }

	-- Field boss bar
	local bar = UiKit.panel({
		Name = "FieldBossBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(560, 70),
		Visible = false,
		Parent = gui,
	})
	local barScale = Instance.new("UIScale")
	barScale.Parent = bar
	UiKit.autoScale(barScale, 0.55, 1.4)
	local glyph = UiKit.label({
		Name = "Glyph",
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(56, 56),
		Font = UiKit.HEAVY_FONT,
		TextSize = 40,
		TextColor3 = Color3.fromRGB(255, 120, 100),
		Parent = bar,
	})
	local name = UiKit.label({
		Name = "Title",
		Position = UDim2.fromOffset(70, 4),
		Size = UDim2.fromOffset(300, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 19,
		Parent = bar,
	})
	local epithet = UiKit.label({
		Name = "Epithet",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(240, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 14,
		TextColor3 = UiKit.INK_DIM,
		Parent = bar,
	})
	local track = UiKit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(70, 32),
		Size = UDim2.new(1, -82, 0, 26),
		BackgroundColor3 = UiKit.OUTLINE,
		BorderSizePixel = 0,
		Parent = bar,
	})
	UiKit.corner(6).Parent = track
	local fill = UiKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.LACQUER,
		BorderSizePixel = 0,
		Parent = track,
	})
	UiKit.corner(6).Parent = fill
	local text = UiKit.label({
		Name = "Health",
		Size = UDim2.fromScale(1, 1),
		Font = UiKit.HEAVY_FONT,
		TextSize = 16,
		ZIndex = 3,
		Parent = track,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = text
	bossBar = { frame = bar, name = name, epithet = epithet, fill = fill, text = text, glyph = glyph }

	-- Minimap, under the Petals panel
	local mini = UiKit.panel({
		Name = "Minimap",
		Position = UDim2.fromOffset(12, 118),
		Size = UDim2.fromOffset(MINI_SIZE, MINI_SIZE + 22),
		ClipsDescendants = true,
		Parent = gui,
	})
	local miniScale = Instance.new("UIScale")
	miniScale.Parent = mini
	UiKit.autoScale(miniScale, 0.55, 1.4)
	local window = UiKit.new("Frame", {
		Name = "Window",
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(MINI_SIZE - 8, MINI_SIZE - 8),
		BackgroundColor3 = Color3.fromRGB(26, 30, 40),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = mini,
	})
	UiKit.corner(8).Parent = window
	local world = UiKit.new("Frame", {
		Name = "World",
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = window,
	})
	local miniBosses = drawWorld(world, MINI_SCALE, Vector2.zero, false)
	local miniArrow = arrow(window, 16)
	miniArrow.Position = UDim2.fromScale(0.5, 0.5)
	UiKit.label({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.new(1, 0, 0, 18),
		Text = "[M] World map",
		TextSize = 13,
		TextColor3 = UiKit.INK_DIM,
		Parent = mini,
	})
	minimap = { frame = mini, world = world, arrow = miniArrow, bosses = miniBosses }

	-- World map
	local mapPanel = UiKit.panel({
		Name = "WorldMap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(MAP_SIZE + 24, MAP_SIZE + 64),
		Visible = false,
		ZIndex = 1,
		Parent = gui,
	})
	local mapScale = Instance.new("UIScale")
	mapScale.Parent = mapPanel
	UiKit.autoScale(mapScale, 0.5, 1.2)
	UiKit.label({
		Name = "Title",
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 34),
		Text = "THE FAR SHORE AND THE WILDS",
		Font = UiKit.TITLE_FONT,
		TextSize = 30,
		Parent = mapPanel,
	})
	local sea = UiKit.new("Frame", {
		Name = "Mist",
		Position = UDim2.fromOffset(12, 46),
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
		BackgroundColor3 = Color3.fromRGB(26, 30, 40),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = mapPanel,
	})
	UiKit.corner(10).Parent = sea
	local mapBosses = drawWorld(sea, MAP_SCALE, MAP_ORIGIN, true)
	local mapPlayer = arrow(sea, 18)
	UiKit.label({
		Name = "Legend",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -20, 0, 16),
		Text = "Orange: creature camps  ·  Red: warden arenas  ·  Gold: Ferry Landing (ferry lanterns)  ·  [M] close",
		TextSize = 13,
		TextColor3 = UiKit.INK_DIM,
		Parent = mapPanel,
	})
	worldMap = { frame = mapPanel, player = mapPlayer, bosses = mapBosses }
end

local function zoneInfo(zone: string): (string, string, string, Color3)
	local region = Wilds.region(zone)
	if region then
		return region.title,
			region.subtitle,
			"HUNTING GROUND  ·  SOULS DO NOT FIGHT HERE",
			Phases.color(region.phase, true)
	end
	local titles = Wilds.ZONE_TITLES[zone]
	local rule = "ffa"
	for _, entry in FarShore.ZONES do
		if entry.name == zone then
			rule = entry.rule
		end
	end
	local tag, color
	if rule == "safe" then
		tag, color = "SANCTUARY", Color3.fromRGB(255, 205, 120)
	elseif rule == "nopvp" then
		tag, color = "NO FIGHTING BETWEEN SOULS", Color3.fromRGB(120, 200, 230)
	else
		tag, color = "OPEN BATTLE", Color3.fromRGB(235, 80, 70)
	end
	return if titles then titles[1] else zone, if titles then titles[2] else "", tag, color
end

local function showBanner(zone: string)
	local title, subtitle, tag, color = zoneInfo(zone)
	bannerToken += 1
	local token = bannerToken
	banner.title.Text = title
	banner.subtitle.Text = subtitle
	banner.rule.Text = tag
	banner.rule.TextColor3 = color
	for _, label in { banner.title, banner.subtitle, banner.rule } do
		label.TextTransparency = 1
		Effects.tween(label, 0.5, { TextTransparency = 0 })
	end
	banner.frame.Visible = true
	task.delay(3.2, function()
		if token ~= bannerToken then
			return
		end
		for _, label in { banner.title, banner.subtitle, banner.rule } do
			Effects.tween(label, 0.8, { TextTransparency = 1 })
		end
		task.delay(0.85, function()
			if token == bannerToken then
				banner.frame.Visible = false
			end
		end)
	end)
end

local function hudScale(): number
	local hud = localPlayer:FindFirstChild("PlayerGui") and (localPlayer :: any).PlayerGui:FindFirstChild("HUD")
	local centre = hud and hud:FindFirstChild("TopCentre")
	local scale = centre and centre:FindFirstChildOfClass("UIScale")
	return if scale then scale.Scale else 1
end

local function elderBarVisible(): boolean
	local hud = (localPlayer :: any).PlayerGui:FindFirstChild("HUD")
	local centre = hud and hud:FindFirstChild("TopCentre")
	local elder = centre and centre:FindFirstChild("ElderBar")
	return elder ~= nil and elder:IsA("GuiObject") and elder.Visible and hud.Enabled
end

local function nearestBoss(position: Vector3): Model?
	local best: Model? = nil
	local bestDistance = BOSS_BAR_RANGE
	for _, tagged in CollectionService:GetTagged("WildBoss") do
		if tagged:IsA("Model") and tagged.Parent then
			local humanoid = tagged:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local distance = (tagged:GetPivot().Position - position).Magnitude
				if distance < bestDistance then
					best = tagged
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local function updateBossMarkers(markers: { [string]: Frame })
	local alive: { [string]: boolean } = {}
	for _, tagged in CollectionService:GetTagged("WildBoss") do
		local region = tagged:GetAttribute("Region")
		local humanoid = tagged:FindFirstChildOfClass("Humanoid")
		if type(region) == "string" and humanoid and humanoid.Health > 0 then
			alive[region] = true
		end
	end
	for region, marker in markers do
		marker.BackgroundTransparency = if alive[region] then 0.05 else 0.7
	end
end

local function step()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local overlay = SelectController.overlayOpen()
	gui.Enabled = not overlay
	if not root or not root:IsA("BasePart") then
		bossBar.frame.Visible = false
		return
	end
	local position = root.Position

	-- zone banner
	local zone = character and character:GetAttribute("Zone")
	if type(zone) == "string" and zone ~= lastZone then
		lastZone = zone
		showBanner(zone)
	end

	-- field boss bar
	local boss = nearestBoss(position)
	if boss then
		local creature = Wilds.creature(boss:GetAttribute("Creature") :: any)
		local humanoid = boss:FindFirstChildOfClass("Humanoid")
		if creature and humanoid then
			local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
			bossBar.fill.Size = UDim2.fromScale(fraction, 1)
			bossBar.text.Text = `{math.ceil(humanoid.Health)} / {math.floor(humanoid.MaxHealth)}`
			local enraged = boss:GetAttribute("Enraged") == true
			bossBar.name.Text = string.upper(creature.name) .. (if enraged then "  ·  ENRAGED" else "")
			bossBar.name.TextColor3 = if enraged then Color3.fromRGB(255, 110, 90) else UiKit.PAPER
			bossBar.epithet.Text = creature.epithet
			bossBar.glyph.Text = creature.glyph
			bossBar.fill.BackgroundColor3 = if enraged then Color3.fromRGB(255, 70, 40) else UiKit.LACQUER
			local top = 44 + (if elderBarVisible() then 100 * hudScale() else 0)
			bossBar.frame.Position = UDim2.new(0.5, 0, 0, top)
			bossBar.frame.Visible = true
		end
	else
		bossBar.frame.Visible = false
	end

	-- minimap: north up, centred on the soul, the arrow turns with the camera
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local heading = math.deg(math.atan2(look.X, -look.Z))
	local half = (MINI_SIZE - 8) / 2
	minimap.world.Position = UDim2.fromOffset(half - position.X * MINI_SCALE, half - position.Z * MINI_SCALE)
	minimap.arrow.Rotation = heading
	updateBossMarkers(minimap.bosses)

	if worldMap.frame.Visible then
		local spot = (Vector2.new(position.X, position.Z) - MAP_ORIGIN) * MAP_SCALE
		worldMap.player.Position = UDim2.fromOffset(spot.X, spot.Y)
		worldMap.player.Rotation = heading
		updateBossMarkers(worldMap.bosses)
	end
end

function WildsController.toggleMap()
	worldMap.frame.Visible = not worldMap.frame.Visible
end

function WildsController.init(_self: any)
	buildHud()
end

function WildsController.start(_self: any)
	Remotes.WildsFx.OnClientEvent:Connect(onWildsFx)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.ButtonSelect then
			WildsController.toggleMap()
		end
	end)
	localPlayer.CharacterAdded:Connect(function()
		lastZone = nil
	end)
	RunService.RenderStepped:Connect(step)
end

return WildsController
