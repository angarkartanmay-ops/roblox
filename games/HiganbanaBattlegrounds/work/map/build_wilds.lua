-- Raises the three Wilds islands in the Edit DataModel and dresses them with Part-built props.
-- Run in Studio's Edit mode (Play stopped), then save the place:
--   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8767/build_wilds.lua"))()
-- Reads every position from ReplicatedStorage.Shared.Wilds (src/shared/Wilds.luau), so the islands,
-- camps and arenas line up with what WildsService spawns and what the minimap draws. Re-running it
-- clears Workspace.FarShore.Wilds and each island's terrain box first, so it is idempotent.
-- Only reliable materials (they render without the asset CDN): parts are SmoothPlastic, Wood,
-- WoodPlanks, Slate, Metal, Neon, Limestone, Marble; terrain uses materials the Far Shore does not,
-- so their colours can be set here without changing the shore.

local Wilds = require(game.ReplicatedStorage.Shared.Wilds)
local Terrain = workspace.Terrain
local RES = 4

local map = workspace:FindFirstChild("FarShore")
assert(map, "no Workspace.FarShore")
local old = map:FindFirstChild("Wilds")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "Wilds"
root.Parent = map

-- Terrain colours for the materials only the Wilds use.
local COLOURS = {
	Basalt = Color3.fromRGB(72, 64, 62),
	Asphalt = Color3.fromRGB(58, 52, 54),
	CrackedLava = Color3.fromRGB(140, 58, 36),
	Salt = Color3.fromRGB(150, 144, 138),
	LeafyGrass = Color3.fromRGB(122, 112, 56),
	Sandstone = Color3.fromRGB(132, 88, 66),
	Pavement = Color3.fromRGB(150, 134, 112),
	Sand = Color3.fromRGB(118, 114, 96),
	Glacier = Color3.fromRGB(76, 86, 90),
	Concrete = Color3.fromRGB(104, 108, 104),
}
for name, colour in COLOURS do
	Terrain:SetMaterialColor(Enum.Material[name], colour)
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

---------------------------------------------------------------------------------------------------
-- Terrain

local function regionCentre(region)
	return region.center[1], region.center[2]
end

-- Flat spots: the arena, every camp, the bridge landing and the road to the arena.
local function flatSpots(region)
	local spots = {}
	table.insert(spots, { region.arena[1], region.arena[2], region.arenaRadius + 10 })
	table.insert(spots, { region.bridgeTo[1], region.bridgeTo[2], 26 })
	for _, camp in Wilds.CAMPS do
		if camp.region == region.id then
			local x, z = Wilds.campPosition(camp)
			table.insert(spots, { x, z, 24 })
		end
	end
	return spots
end

local function distanceToSegment(px, pz, ax, az, bx, bz)
	local vx, vz = bx - ax, bz - az
	local t = math.clamp(((px - ax) * vx + (pz - az) * vz) / (vx * vx + vz * vz), 0, 1)
	local dx, dz = px - (ax + vx * t), pz - (az + vz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Pools of shallow water (the Shallows) and paddies (the Lantern Road): { x, z, radius }.
local function pools(region)
	local list = {}
	local cx, cz = regionCentre(region)
	if region.id == "RobeShallows" then
		for _, p in { { -40, 90, 16 }, { 30, 100, 12 }, { 120, -20, 18 }, { -130, 10, 14 }, { -40, -120, 15 }, { 90, -110, 12 } } do
			table.insert(list, { cx + p[1], cz + p[2], p[3] })
		end
		-- a moat ring around the warden's arena
		table.insert(list, { region.arena[1], region.arena[2], -1 })
	elseif region.id == "LanternRoad" then
		for _, p in { { -75, -60, 9 }, { -55, -110, 9 }, { -20, -115, 9 }, { -5, -70, 9 } } do
			table.insert(list, { cx + p[1], cz + p[2], p[3] })
		end
	end
	return list
end

-- Top height, bottom height, surface material and water depth for the column at (x, z).
local function column(region, x, z, seed, spots, poolList)
	local cx, cz = regionCentre(region)
	local dx, dz = x - cx, z - cz
	local r = math.sqrt(dx * dx + dz * dz)
	local angle = math.atan2(dz, dx)
	local edge = region.radius - 6 + math.noise(math.cos(angle) * 2.2 + seed, math.sin(angle) * 2.2, 0.31) * 16
	-- the bridge always lands on solid ground
	local toBridge = math.sqrt((x - region.bridgeTo[1]) ^ 2 + (z - region.bridgeTo[2]) ^ 2)
	if toBridge < 34 then
		edge = math.max(edge, region.radius + 6)
	end
	if r > edge then
		return nil
	end
	local top = region.ground
		+ math.noise(x / 70, z / 70, seed) * 5
		+ math.noise(x / 19, z / 19, seed + 7.7) * 1.4
	for _, spot in spots do
		local d = math.sqrt((x - spot[1]) ^ 2 + (z - spot[2]) ^ 2)
		if d < spot[3] then
			local w = smooth((d - spot[3] * 0.6) / (spot[3] * 0.4))
			top = region.ground + (top - region.ground) * w
		end
	end
	-- a rounded lip, then the cliff
	local lip = edge - r
	if lip < 12 then
		top -= (1 - lip / 12) ^ 2 * 7
	end
	local depth = 16 + 95 * (1 - r / edge) ^ 0.7 + math.noise(x / 23, z / 23, seed + 3.1) * 12
	local bottom = top - math.max(8, depth)

	local material = Enum.Material[region.surface]
	local water = 0
	if region.id == "Gatewaste" then
		local ash = math.noise(x / 40, z / 40, seed + 11)
		if ash > 0.25 then
			material = Enum.Material.Salt
		end
		-- three ember pits beside the Ash Pits camp
		for _, camp in Wilds.CAMPS do
			if camp.id == "AshPits" then
				local ax, az = Wilds.campPosition(camp)
				for index = 0, 2 do
					local a = index * 2.1 + 0.4
					local px, pz = ax + math.cos(a) * 30, az + math.sin(a) * 30
					local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
					if d < 11 then
						top -= (1 - d / 11) * 5
						material = if d < 6 then Enum.Material.CrackedLava else Enum.Material.Basalt
					end
				end
			end
		end
	elseif region.id == "LanternRoad" then
		-- the stone road from the bridge to the arena
		local d = distanceToSegment(x, z, region.bridgeTo[1], region.bridgeTo[2], region.arena[1], region.arena[2])
		if d < 6 then
			material = Enum.Material.Pavement
			top = math.min(top, region.ground + 0.3)
		end
	elseif region.id == "RobeShallows" then
		if math.noise(x / 30, z / 30, seed + 5) > 0.3 then
			material = Enum.Material.Mud
		end
	end
	for _, pool in poolList do
		local d = math.sqrt((x - pool[1]) ^ 2 + (z - pool[2]) ^ 2)
		if pool[3] < 0 then
			-- moat: a ring just outside the arena
			local inner = region.arenaRadius + 2
			if d > inner and d < inner + 7 then
				water = 2
				material = Enum.Material.Sand
			end
		elseif d < pool[3] then
			water = 1.5 + (1 - d / pool[3]) * 1
			material = if region.id == "LanternRoad" then Enum.Material.Mud else Enum.Material.Sand
		end
	end
	return top, bottom, material, water
end

local function buildIsland(region, seed)
	local cx, cz = regionCentre(region)
	local half = region.radius + 16
	local minY = region.ground - 130
	local maxY = region.ground + 16
	local box = Region3.new(Vector3.new(cx - half, minY, cz - half), Vector3.new(cx + half, maxY, cz + half)):ExpandToGrid(RES)
	-- clear what a previous run raised here
	Terrain:FillRegion(box, RES, Enum.Material.Air)
	local materials, occupancies = Terrain:ReadVoxels(box, RES)
	local size = materials.Size
	local low = box.CFrame.Position - box.Size / 2
	local spots = flatSpots(region)
	local poolList = pools(region)
	local cliff = Enum.Material[region.cliff]
	for ix = 1, size.X do
		local x = low.X + (ix - 0.5) * RES
		for iz = 1, size.Z do
			local z = low.Z + (iz - 0.5) * RES
			local top, bottom, surface, water = column(region, x, z, seed, spots, poolList)
			if top then
				-- water fills whole voxels: drop the bed to the voxel boundary under the surface
				local bed = if water > 0 then math.floor((top - 0.5) / RES) * RES else top
				for iy = 1, size.Y do
					local y0 = low.Y + (iy - 1) * RES
					local y1 = y0 + RES
					if y1 > bottom and y0 < bed then
						local fill = math.clamp((math.min(y1, bed) - math.max(y0, bottom)) / RES, 0, 1)
						materials[ix][iy][iz] = if y1 >= bed - RES * 1.5 then surface else cliff
						occupancies[ix][iy][iz] = math.max(fill, 0.05)
					elseif water > 0 and y1 > bed and y0 < top then
						materials[ix][iy][iz] = Enum.Material.Water
						occupancies[ix][iy][iz] = math.clamp((math.min(y1, top) - math.max(y0, bed)) / RES, 0.1, 1)
					end
				end
			end
		end
	end
	Terrain:WriteVoxels(box, RES, materials, occupancies)
end

---------------------------------------------------------------------------------------------------
-- Parts

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { root }

local function groundAt(x, z)
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -520, 0), params)
	return if hit then hit.Position else nil
end

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function wedge(parent, props)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		p[key] = value
	end
	p.Parent = parent
	return p
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function glow(p, colour, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = colour
	l.Range = range
	l.Brightness = brightness or 1.2
	l.Shadows = false
	l.Parent = p
end

-- A frame standing on the ground at (x, z), facing `yaw` degrees.
local function base(x, z, yaw)
	local g = groundAt(x, z)
	if not g then
		return nil
	end
	return CFrame.new(g) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

local function paperLantern(parent, cf, colour, size)
	local s = size or 1
	local body = part(parent, {
		Name = "Lantern",
		Size = Vector3.new(1.4, 1.8, 1.4) * s,
		CFrame = cf,
		Color = colour or rgb(255, 120, 50),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	for _, y in { 1, -1 } do
		part(parent, {
			Size = Vector3.new(1.6, 0.22, 1.6) * s,
			CFrame = cf * CFrame.new(0, y * 1 * s, 0),
			Color = rgb(30, 22, 20),
			CanCollide = false,
		})
	end
	glow(body, colour or rgb(255, 140, 60), 14 * s, 1.1)
	return body
end

local function brazier(parent, cf, colour)
	local m = model(parent, "Brazier")
	part(m, { Size = Vector3.new(1.2, 3.2, 1.2), CFrame = cf * CFrame.new(0, 1.6, 0), Color = rgb(60, 56, 56), Material = Enum.Material.Slate })
	part(m, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 3.4, 3.4),
		CFrame = cf * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rgb(48, 44, 46),
		Material = Enum.Material.Metal,
	})
	local fire = part(m, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = cf * CFrame.new(0, 4.4, 0),
		Color = colour or rgb(255, 110, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
	})
	glow(fire, colour or rgb(255, 120, 50), 22, 1.6)
end

local function cage(parent, cf, broken)
	local m = model(parent, "Cage")
	local iron = rgb(56, 56, 62)
	part(m, { Size = Vector3.new(10, 1, 10), CFrame = cf * CFrame.new(0, 0.5, 0), Color = rgb(70, 66, 64), Material = Enum.Material.Slate })
	part(m, { Size = Vector3.new(10.6, 0.8, 10.6), CFrame = cf * CFrame.new(0, 9.4, 0), Color = iron, Material = Enum.Material.Metal })
	for side = 0, 3 do
		local turn = cf * CFrame.Angles(0, math.rad(side * 90), 0)
		for index = -4, 4, 2 do
			if not (broken and side == 0 and math.abs(index) <= 2) then
				part(m, {
					Size = Vector3.new(0.35, 8.6, 0.35),
					CFrame = turn * CFrame.new(index, 5.1, -4.8),
					Color = iron,
					Material = Enum.Material.Metal,
				})
			end
		end
	end
	if broken then
		part(m, {
			Size = Vector3.new(0.35, 7, 0.35),
			CFrame = cf * CFrame.new(-1, 1.2, -7) * CFrame.Angles(math.rad(80), 0, math.rad(20)),
			Color = iron,
			Material = Enum.Material.Metal,
		})
	end
	return m
end

local function torii(parent, cf, width, height, colour)
	local m = model(parent, "Torii")
	local red = colour or rgb(190, 40, 34)
	for _, side in { -1, 1 } do
		part(m, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 1.1, 1.1),
			CFrame = cf * CFrame.new(side * width / 2, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = red,
		})
		part(m, { Size = Vector3.new(1.5, 0.8, 1.5), CFrame = cf * CFrame.new(side * width / 2, 0.4, 0), Color = rgb(30, 24, 22) })
	end
	part(m, { Size = Vector3.new(width + 4, 0.9, 1.4), CFrame = cf * CFrame.new(0, height + 0.4, 0), Color = rgb(30, 24, 22) })
	part(m, { Size = Vector3.new(width + 3, 0.8, 1.1), CFrame = cf * CFrame.new(0, height - 0.5, 0), Color = red })
	part(m, { Size = Vector3.new(width + 1, 0.6, 0.9), CFrame = cf * CFrame.new(0, height - 2.6, 0), Color = red })
	return m
end

local function shrine(parent, cf)
	local m = model(parent, "FoxShrine")
	local wood = rgb(120, 84, 56)
	part(m, { Size = Vector3.new(12, 1.4, 10), CFrame = cf * CFrame.new(0, 0.7, 0), Color = rgb(150, 144, 132), Material = Enum.Material.Limestone })
	part(m, { Size = Vector3.new(9, 6, 7), CFrame = cf * CFrame.new(0, 4.4, 0.5), Color = wood, Material = Enum.Material.Wood })
	part(m, { Size = Vector3.new(4, 4.2, 0.3), CFrame = cf * CFrame.new(0, 3.6, -3.1), Color = rgb(40, 28, 24) })
	for _, side in { -1, 1 } do
		wedge(m, {
			Size = Vector3.new(12, 3, 5.5),
			CFrame = cf * CFrame.new(0, 8.9, side * 2.75) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0),
			Color = rgb(150, 36, 32),
		})
		-- fox guardians with red bibs
		local fox = cf * CFrame.new(side * 8, 1.4, -6)
		part(m, { Size = Vector3.new(2.2, 1.6, 2.2), CFrame = fox * CFrame.new(0, 0.8, 0), Color = rgb(170, 164, 150), Material = Enum.Material.Limestone })
		part(m, { Size = Vector3.new(1.4, 3, 1.6), CFrame = fox * CFrame.new(0, 3.1, 0), Color = rgb(226, 222, 210), Material = Enum.Material.Marble })
		part(m, { Size = Vector3.new(1.2, 1.2, 1.6), CFrame = fox * CFrame.new(0, 5.2, -0.3), Color = rgb(226, 222, 210), Material = Enum.Material.Marble })
		part(m, { Size = Vector3.new(1.5, 1, 0.2), CFrame = fox * CFrame.new(0, 4.1, -0.85), Color = rgb(196, 36, 40) })
		for _, ear in { -1, 1 } do
			wedge(m, { Size = Vector3.new(0.3, 0.9, 0.6), CFrame = fox * CFrame.new(ear * 0.4, 6.2, -0.2), Color = rgb(226, 222, 210) })
		end
	end
	return m
end

local function stall(parent, cf, colour)
	local m = model(parent, "Stall")
	local wood = rgb(110, 80, 56)
	for _, x in { -3.5, 3.5 } do
		for _, z in { -2.5, 2.5 } do
			part(m, { Size = Vector3.new(0.5, 7, 0.5), CFrame = cf * CFrame.new(x, 3.5, z), Color = wood, Material = Enum.Material.Wood })
		end
	end
	part(m, { Size = Vector3.new(7.6, 2.4, 3), CFrame = cf * CFrame.new(0, 1.2, -1.5), Color = wood, Material = Enum.Material.WoodPlanks })
	part(m, {
		Size = Vector3.new(8.6, 0.3, 6.6),
		CFrame = cf * CFrame.new(0, 7.3, 0) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = colour,
	})
	paperLantern(m, cf * CFrame.new(-3.5, 5.6, -3), rgb(255, 130, 60), 0.6)
	paperLantern(m, cf * CFrame.new(3.5, 5.6, -3), rgb(255, 130, 60), 0.6)
	return m
end

local function stupa(parent, cf, scale)
	local s = scale or 1
	local m = model(parent, "Stupa")
	local stone = rgb(150, 146, 136)
	part(m, { Size = Vector3.new(3, 1.6, 3) * s, CFrame = cf * CFrame.new(0, 0.8 * s, 0), Color = stone, Material = Enum.Material.Limestone })
	part(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6 * s, CFrame = cf * CFrame.new(0, 2.6 * s, 0), Color = stone, Material = Enum.Material.Limestone })
	part(m, { Size = Vector3.new(3.2, 0.7, 3.2) * s, CFrame = cf * CFrame.new(0, 4.1 * s, 0), Color = stone, Material = Enum.Material.Limestone })
	part(m, { Size = Vector3.new(1.4, 1.2, 1.4) * s, CFrame = cf * CFrame.new(0, 5, 0) * CFrame.new(0, 0, 0) * CFrame.new(0, 0.1 * s, 0), Color = stone, Material = Enum.Material.Limestone })
	return m
end

local function sotoba(parent, cf, height)
	part(parent, {
		Name = "Sotoba",
		Size = Vector3.new(0.9, height, 0.2),
		CFrame = cf * CFrame.new(0, height / 2 - 0.6, 0) * CFrame.Angles(0, 0, math.rad(math.random(-8, 8))),
		Color = rgb(206, 192, 160),
		Material = Enum.Material.Wood,
	})
end

local function reeds(parent, cf)
	for _ = 1, 7 do
		local h = math.random(40, 75) / 10
		part(parent, {
			Name = "Reed",
			Size = Vector3.new(0.18, h, 0.18),
			CFrame = cf
				* CFrame.new(math.random(-20, 20) / 10, h / 2, math.random(-20, 20) / 10)
				* CFrame.Angles(math.rad(math.random(-10, 10)), 0, math.rad(math.random(-10, 10))),
			Color = rgb(150, 150, 84),
			CanCollide = false,
		})
	end
end

local function boulder(parent, cf, size, colour)
	return part(parent, {
		Name = "Boulder",
		Size = Vector3.new(size, size * 0.7, size * 0.9),
		CFrame = cf * CFrame.new(0, size * 0.25, 0) * CFrame.Angles(math.random() * 0.4, math.random() * 6.28, math.random() * 0.4),
		Color = colour or rgb(84, 78, 76),
		Material = Enum.Material.Slate,
	})
end

---------------------------------------------------------------------------------------------------
-- Bridges

local function buildBridge(region, parent)
	local a = groundAt(region.bridgeFrom[1], region.bridgeFrom[2])
	local b = groundAt(region.bridgeTo[1], region.bridgeTo[2])
	assert(a and b, "bridge ends not found for " .. region.id)
	local m = model(parent, "Bridge_" .. region.id)
	local flatA = Vector3.new(a.X, 0, a.Z)
	local flatB = Vector3.new(b.X, 0, b.Z)
	local length = (flatB - flatA).Magnitude
	local dir = (flatB - flatA).Unit
	local right = dir:Cross(Vector3.new(0, 1, 0))
	local width = 12
	local step = 6
	local count = math.ceil(length / step)
	local function deckAt(t)
		local p = a:Lerp(b, t)
		local sag = math.sin(t * math.pi) * 4
		return Vector3.new(p.X, p.Y + 0.6 - sag, p.Z)
	end
	for index = 0, count - 1 do
		local t0, t1 = index / count, (index + 1) / count
		local p0, p1 = deckAt(t0), deckAt(t1)
		local mid = (p0 + p1) / 2
		local cf = CFrame.lookAt(mid, p1)
		part(m, {
			Name = "Plank",
			Size = Vector3.new(width, 0.9, (p1 - p0).Magnitude + 0.15),
			CFrame = cf,
			Color = if index % 2 == 0 then rgb(118, 86, 58) else rgb(104, 76, 52),
			Material = Enum.Material.WoodPlanks,
		})
		for _, side in { -1, 1 } do
			-- rope rails
			part(m, {
				Name = "Rail",
				Size = Vector3.new(0.3, 0.3, (p1 - p0).Magnitude + 0.2),
				CFrame = cf * CFrame.new(side * (width / 2 - 0.3), 3.2, 0),
				Color = rgb(170, 150, 110),
				CanCollide = false,
			})
			part(m, {
				Name = "Guard",
				Size = Vector3.new(0.6, 3.6, (p1 - p0).Magnitude + 0.2),
				CFrame = cf * CFrame.new(side * (width / 2 + 0.3), 1.8, 0),
				Transparency = 1,
			})
		end
		if index % 4 == 0 then
			for _, side in { -1, 1 } do
				part(m, {
					Name = "Post",
					Size = Vector3.new(0.7, 5, 0.7),
					CFrame = CFrame.new(p0 + right * side * (width / 2 - 0.3) + Vector3.new(0, 1.8, 0)),
					Color = rgb(70, 50, 38),
					Material = Enum.Material.Wood,
				})
				if index % 8 == 0 then
					paperLantern(m, CFrame.new(p0 + right * side * (width / 2 - 0.3) + Vector3.new(0, 5.2, 0)), rgb(255, 140, 60), 0.6)
				end
			end
		end
	end
	-- rocks hanging below the far end so the bridge reads as anchored
	return m
end

---------------------------------------------------------------------------------------------------
-- Region dressing

local function campFrame(campId, dx, dz, yaw)
	for _, camp in Wilds.CAMPS do
		if camp.id == campId then
			local x, z = Wilds.campPosition(camp)
			return base(x + (dx or 0), z + (dz or 0), yaw)
		end
	end
	return nil
end

local function arenaRing(parent, region, colour, posts)
	local cx, cz = region.arena[1], region.arena[2]
	local n = posts or 12
	local tops = {}
	for index = 1, n do
		local a = index / n * math.pi * 2
		local cf = base(cx + math.cos(a) * region.arenaRadius, cz + math.sin(a) * region.arenaRadius, math.deg(-a))
		if cf then
			part(parent, { Name = "ArenaPost", Size = Vector3.new(1.6, 6, 1.6), CFrame = cf * CFrame.new(0, 3, 0), Color = rgb(70, 64, 62), Material = Enum.Material.Slate })
			local cap = part(parent, {
				Name = "ArenaFlame",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 1.3,
				CFrame = cf * CFrame.new(0, 6.6, 0),
				Color = colour,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
			if index % 3 == 0 then
				glow(cap, colour, 18, 1)
			end
			table.insert(tops, cf * CFrame.new(0, 5.4, 0))
		end
	end
	return tops
end

local function dressGatewaste(region, folder)
	local cx, cz = region.center[1], region.center[2]
	local ax, az = region.arena[1], region.arena[2]
	-- The hell-gate that was never closed, west of the arena, facing the island.
	local gateCf = base(ax - region.arenaRadius - 14, az, 90)
	if gateCf then
		local gate = model(folder, "HellGate")
		local dark = rgb(54, 40, 40)
		local iron = rgb(48, 46, 52)
		for _, side in { -1, 1 } do
			part(gate, { Size = Vector3.new(6, 40, 6), CFrame = gateCf * CFrame.new(side * 16, 20, 0), Color = dark, Material = Enum.Material.Slate })
			part(gate, { Size = Vector3.new(8, 3, 8), CFrame = gateCf * CFrame.new(side * 16, 1.5, 0), Color = rgb(40, 32, 32), Material = Enum.Material.Slate })
			-- the doors, swung open and hanging
			part(gate, {
				Size = Vector3.new(14, 30, 1.4),
				CFrame = gateCf * CFrame.new(side * 16, 16, 0) * CFrame.Angles(0, math.rad(side * -70), 0) * CFrame.new(side * -7, 0, 0),
				Color = iron,
				Material = Enum.Material.Metal,
			})
		end
		part(gate, { Size = Vector3.new(46, 4, 7), CFrame = gateCf * CFrame.new(0, 41, 0), Color = dark, Material = Enum.Material.Slate })
		part(gate, { Size = Vector3.new(40, 2.5, 5), CFrame = gateCf * CFrame.new(0, 35, 0), Color = rgb(150, 34, 30) })
		local maw = part(gate, {
			Size = Vector3.new(26, 32, 0.6),
			CFrame = gateCf * CFrame.new(0, 16, 1.5),
			Color = rgb(255, 60, 30),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
		})
		glow(maw, rgb(255, 70, 40), 40, 2)
	end
	local tops = arenaRing(folder, region, rgb(255, 80, 40), 12)
	-- chains between the arena posts
	for index = 1, #tops do
		local p0 = tops[index].Position
		local p1 = tops[index % #tops + 1].Position
		part(folder, {
			Name = "Chain",
			Size = Vector3.new(0.4, 0.4, (p1 - p0).Magnitude),
			CFrame = CFrame.lookAt((p0 + p1) / 2 - Vector3.new(0, 1, 0), p1 - Vector3.new(0, 1, 0)),
			Color = rgb(60, 60, 66),
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
	end
	-- Shackle Yard and Broken Cells: cages and braziers
	for _, spec in { { "ShackleYard", -16, -12, 10, false }, { "ShackleYard", 14, 16, -20, true }, { "BrokenCells", -12, 10, 30, true }, { "BrokenCells", 16, -8, 0, true } } do
		local cf = campFrame(spec[1], spec[2], spec[3], spec[4])
		if cf then
			cage(folder, cf, spec[5])
		end
	end
	for _, spec in { { "ShackleYard", 0, -22 }, { "BrokenCells", 0, 20 }, { "AshPits", 0, 0 } } do
		local cf = campFrame(spec[1], spec[2], spec[3])
		if cf then
			brazier(folder, cf)
		end
	end
	-- the entrance: two braziers and a torii in iron
	local inward = Vector3.new(cx - region.bridgeTo[1], 0, cz - region.bridgeTo[2]).Unit
	local entrance = Vector3.new(region.bridgeTo[1], 0, region.bridgeTo[2]) + inward * 8
	local entranceCf = base(entrance.X, entrance.Z, math.deg(math.atan2(-inward.X, -inward.Z)))
	if entranceCf then
		torii(folder, entranceCf, 14, 13, rgb(62, 58, 60))
		brazier(folder, entranceCf * CFrame.new(-10, 0, 0))
		brazier(folder, entranceCf * CFrame.new(10, 0, 0))
	end
	-- scattered rubble and broken pillars
	local rng = Random.new(11)
	for _ = 1, 40 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(30, region.radius - 25)
		local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
		local nearArena = math.sqrt((x - ax) ^ 2 + (z - az) ^ 2) < region.arenaRadius + 6
		local cf = base(x, z, rng:NextNumber(0, 360))
		if cf and not nearArena then
			if rng:NextNumber() < 0.6 then
				boulder(folder, cf, rng:NextNumber(3, 8), rgb(70, 62, 60))
			else
				part(folder, {
					Name = "BrokenPillar",
					Size = Vector3.new(3, rng:NextNumber(5, 14), 3),
					CFrame = cf * CFrame.new(0, 3, 0) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12))),
					Color = rgb(64, 50, 48),
					Material = Enum.Material.Slate,
				})
			end
		end
	end
end

local function dressLanternRoad(region, folder)
	local cx, cz = region.center[1], region.center[2]
	local ax, az = region.arena[1], region.arena[2]
	-- a tunnel of red gates along the road from the bridge to the arena
	local from = Vector3.new(region.bridgeTo[1], 0, region.bridgeTo[2])
	local to = Vector3.new(ax, 0, az)
	local dir = (to - from).Unit
	local length = (to - from).Magnitude - region.arenaRadius - 4
	local yaw = math.deg(math.atan2(-dir.X, -dir.Z))
	local distance = 14
	while distance < length do
		local p = from + dir * distance
		local cf = base(p.X, p.Z, yaw)
		if cf then
			torii(folder, cf, 11, 11)
			paperLantern(folder, cf * CFrame.new(0, 8.6, 0), rgb(255, 150, 70), 0.7)
		end
		distance += 9
	end
	-- the bride's arena: a ring of fox-fire posts and lanterns
	arenaRing(folder, region, rgb(150, 210, 255), 14)
	local rng = Random.new(23)
	for _ = 1, 16 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(6, region.arenaRadius - 8)
		local p = Vector3.new(ax + math.cos(a) * d, 0, az + math.sin(a) * d)
		local g = groundAt(p.X, p.Z)
		if g then
			paperLantern(folder, CFrame.new(g + Vector3.new(0, rng:NextNumber(10, 18), 0)), rgb(255, 150, 70), 1.1)
		end
	end
	local shrineCf = campFrame("FoxShrine", 0, 14, 180)
	if shrineCf then
		shrine(folder, shrineCf)
	end
	local colours = { rgb(190, 50, 46), rgb(60, 90, 140), rgb(210, 170, 80), rgb(80, 120, 80) }
	for index, offset in { { -14, -8, 20 }, { 0, -14, 0 }, { 14, -8, -20 }, { -10, 12, 160 }, { 12, 12, 200 } } do
		local cf = campFrame("PaperMarket", offset[1], offset[2], offset[3])
		if cf then
			stall(folder, cf, colours[(index - 1) % #colours + 1])
		end
	end
	-- maples (Part-built): trunk and a red crown
	for _ = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(40, region.radius - 22)
		local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
		local road = (function()
			local vx, vz = to.X - from.X, to.Z - from.Z
			local t = math.clamp(((x - from.X) * vx + (z - from.Z) * vz) / (vx * vx + vz * vz), 0, 1)
			return math.sqrt((x - (from.X + vx * t)) ^ 2 + (z - (from.Z + vz * t)) ^ 2)
		end)()
		local arena = math.sqrt((x - ax) ^ 2 + (z - az) ^ 2)
		local cf = base(x, z, rng:NextNumber(0, 360))
		if cf and road > 12 and arena > region.arenaRadius + 8 then
			local h = rng:NextNumber(10, 16)
			local m = model(folder, "Maple")
			part(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 1.6, 1.6), CFrame = cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(70, 48, 36), Material = Enum.Material.Wood })
			for _ = 1, 3 do
				part(m, {
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * rng:NextNumber(6, 9),
					CFrame = cf * CFrame.new(rng:NextNumber(-2.5, 2.5), h + rng:NextNumber(-1, 2), rng:NextNumber(-2.5, 2.5)),
					Color = if rng:NextNumber() < 0.5 then rgb(196, 64, 40) else rgb(214, 110, 46),
					CanCollide = false,
				})
			end
		end
	end
end

local function dressShallows(region, folder)
	local cx, cz = region.center[1], region.center[2]
	local ax, az = region.arena[1], region.arena[2]
	-- the Robe Tree behind the arena: a dead giant hung with the clothes of the dead
	local treeCf = base(ax, az - region.arenaRadius + 6, 0)
	if treeCf then
		local tree = model(folder, "RobeTree")
		local bark = rgb(58, 46, 40)
		part(tree, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(34, 7, 7), CFrame = treeCf * CFrame.new(0, 17, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = bark, Material = Enum.Material.Wood })
		local robes = { rgb(214, 204, 176), rgb(150, 40, 40), rgb(60, 90, 140), rgb(230, 226, 214), rgb(90, 70, 110), rgb(200, 190, 150) }
		local rng = Random.new(5)
		for index = 1, 7 do
			local a = index / 7 * math.pi * 2
			local y = 18 + index * 2
			local reach = rng:NextNumber(12, 18)
			local tip = treeCf * CFrame.new(math.cos(a) * reach, y + 6, math.sin(a) * reach)
			local start = treeCf * CFrame.new(0, y, 0)
			local p0, p1 = start.Position, tip.Position
			part(tree, {
				Name = "Branch",
				Size = Vector3.new(1.6, 1.6, (p1 - p0).Magnitude),
				CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
				Color = bark,
				Material = Enum.Material.Wood,
			})
			for k = 1, 2 do
				local hang = p0:Lerp(p1, 0.45 + k * 0.22)
				part(tree, {
					Name = "Robe",
					Size = Vector3.new(3.2, 5, 0.3),
					CFrame = CFrame.new(hang - Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, a, math.rad(rng:NextNumber(-6, 6))),
					Color = robes[(index + k) % #robes + 1],
					CanCollide = false,
				})
			end
		end
		glow(tree:FindFirstChildWhichIsA("BasePart"), rgb(140, 120, 220), 30, 0.8)
	end
	arenaRing(folder, region, rgb(140, 120, 220), 12)
	-- grave boards and stupas at the Reed Graves, a weir of stakes at the Bone Weir
	local rng = Random.new(41)
	local graves = campFrame("ReedGraves", 0, 0, 0)
	if graves then
		for _ = 1, 22 do
			local cf = graves * CFrame.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20))
			local g = groundAt(cf.Position.X, cf.Position.Z)
			if g then
				sotoba(folder, CFrame.new(g) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), rng:NextNumber(4, 7))
			end
		end
		for _ = 1, 5 do
			local cf = graves * CFrame.new(rng:NextNumber(-22, 22), 0, rng:NextNumber(-22, 22))
			local g = groundAt(cf.Position.X, cf.Position.Z)
			if g then
				stupa(folder, CFrame.new(g), rng:NextNumber(0.9, 1.4))
			end
		end
	end
	local weir = campFrame("BoneWeir", 0, 0, 0)
	if weir then
		for index = -8, 8 do
			local cf = weir * CFrame.new(index * 2.4, 0, -18 + math.sin(index) * 1.2)
			local g = groundAt(cf.Position.X, cf.Position.Z)
			if g then
				part(folder, {
					Name = "Stake",
					Size = Vector3.new(0.7, 6, 0.7),
					CFrame = CFrame.new(g + Vector3.new(0, 2, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-10, 10))),
					Color = rgb(96, 80, 64),
					Material = Enum.Material.Wood,
				})
			end
		end
	end
	-- reeds around the island, stone lanterns along the shallows
	for _ = 1, 60 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(20, region.radius - 15)
		local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
		local arena = math.sqrt((x - ax) ^ 2 + (z - az) ^ 2)
		local cf = base(x, z, 0)
		if cf and arena > region.arenaRadius + 10 then
			reeds(folder, cf)
		end
	end
	for index = 1, 10 do
		local a = index / 10 * math.pi * 2
		local cf = base(cx + math.cos(a) * 70, cz + math.sin(a) * 70, 0)
		if cf then
			local m = model(folder, "StoneLantern")
			part(m, { Size = Vector3.new(2.4, 1, 2.4), CFrame = cf * CFrame.new(0, 0.5, 0), Color = rgb(150, 146, 136), Material = Enum.Material.Limestone })
			part(m, { Size = Vector3.new(1, 3, 1), CFrame = cf * CFrame.new(0, 2.5, 0), Color = rgb(150, 146, 136), Material = Enum.Material.Limestone })
			local light = part(m, { Size = Vector3.new(1.8, 1.6, 1.8), CFrame = cf * CFrame.new(0, 4.8, 0), Color = rgb(180, 200, 255), Material = Enum.Material.Neon, Transparency = 0.2 })
			part(m, { Size = Vector3.new(3, 0.7, 3), CFrame = cf * CFrame.new(0, 6, 0), Color = rgb(130, 126, 118), Material = Enum.Material.Limestone })
			glow(light, rgb(170, 190, 255), 16, 0.9)
		end
	end
end

---------------------------------------------------------------------------------------------------

local report = {}
for index, region in Wilds.REGIONS do
	buildIsland(region, index * 13.7)
end
-- terrain first, then everything that stands on it
for _, region in Wilds.REGIONS do
	local folder = Instance.new("Folder")
	folder.Name = region.id
	folder.Parent = root
	buildBridge(region, folder)
	if region.id == "Gatewaste" then
		dressGatewaste(region, folder)
	elseif region.id == "LanternRoad" then
		dressLanternRoad(region, folder)
	else
		dressShallows(region, folder)
	end
	local landing = groundAt(region.bridgeTo[1], region.bridgeTo[2])
	local arena = groundAt(region.arena[1], region.arena[2])
	table.insert(report, `{region.id}: parts {#folder:GetDescendants()} landing {landing and math.floor(landing.Y) or "nil"} arena {arena and math.floor(arena.Y) or "nil"}`)
end
return table.concat(report, " | ")
