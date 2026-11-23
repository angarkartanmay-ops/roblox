--!strict
-- Keeps the game readable when Roblox's asset CDN cannot be reached. A network that inspects TLS
-- (a firewall re-signing roblox.com, so every fetch ends in "HttpError: TlsVerificationFail") never
-- delivers avatar meshes or the generated props' textures: fighters and dummies turn invisible
-- with only their weapons floating. On such a network each body part whose mesh fetch FAILED gets a
-- plain stand-in welded on (client only), dressed in the fighter's phase colours, and map props
-- whose texture fetch FAILED (they render flat white) are tinted with the colour their kind carries
-- in the place. With a healthy network every fetch succeeds and this adds nothing.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Phases = require(ReplicatedStorage.Shared.Phases)

local FallbackController = {}

type Role = "skin" | "robe" | "hakama"

-- R15 body parts and what a fighter wears on each.
local ROLE: { [string]: Role } = {
	Head = "skin",
	UpperTorso = "robe",
	LowerTorso = "robe",
	LeftUpperArm = "robe",
	RightUpperArm = "robe",
	LeftLowerArm = "skin",
	RightLowerArm = "skin",
	LeftHand = "skin",
	RightHand = "skin",
	LeftUpperLeg = "hakama",
	RightUpperLeg = "hakama",
	LeftLowerLeg = "hakama",
	RightLowerLeg = "hakama",
	LeftFoot = "hakama",
	RightFoot = "hakama",
}

local standIns: Folder
type StandIn = { part: BasePart, body: BasePart, extras: { BasePart } }
local active: { StandIn } = {}
local covered: { [BasePart]: boolean } = {}

local function fetchState(id: string): boolean?
	if id == "" then
		return nil
	end
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(id)
	end)
	if not ok then
		return nil
	end
	if status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
		return true
	elseif status == Enum.AssetFetchStatus.Success then
		return false
	end
	return nil
end

-- Run `done(failed)` once the asset's fetch settles, now or later.
local function whenSettled(id: string, done: (failed: boolean) -> ())
	local state = fetchState(id)
	if state ~= nil then
		done(state)
		return
	end
	local connection: RBXScriptConnection? = nil
	local settled = false
	local function check()
		if settled then
			return
		end
		local now = fetchState(id)
		if now ~= nil then
			settled = true
			if connection then
				connection:Disconnect()
			end
			done(now)
		end
	end
	local ok = pcall(function()
		connection = ContentProvider:GetAssetFetchStatusChangedSignal(id):Connect(check)
	end)
	check()
	if not ok then
		-- No status signal for this id: look again every few seconds for a minute.
		task.spawn(function()
			for _ = 1, 20 do
				if settled then
					return
				end
				task.wait(3)
				check()
			end
		end)
	end
end

local function whenFailed(id: string, onFailed: () -> ())
	whenSettled(id, function(failed)
		if failed then
			onFailed()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Map props whose texture never arrives
-- A generated prop whose texture fetch FAILED renders flat white, and MeshPart.Color never shows
-- through a texture (clearing the TextureID renders the prop black instead: measured). So the parts
-- of each failed texture are gathered, client side, into one model tinted by a single Highlight in
-- the colour their kind carries in the place. One Highlight per texture keeps far under the
-- engine's limit of 31 (Effects.flash uses at most 12).

local TINT_FILL = 0.45
local MAX_TINTS = 16

type TextureState = "pending" | "failed" | "ok"
local textureState: { [string]: TextureState } = {}
local textureUsers: { [string]: { MeshPart } } = {}
local tintGroups: { [string]: Model } = {}
local tintCount = 0
local tintRoot: Instance? = nil

local function tint(part: MeshPart, id: string)
	local root = tintRoot
	if root == nil or part.Parent == nil or part.TextureID ~= id then
		return
	end
	local group: Model? = tintGroups[id]
	if not group then
		if tintCount >= MAX_TINTS then
			return
		end
		tintCount += 1
		local model = Instance.new("Model")
		model.Name = "Tint_" .. (string.match(part.Name, "__(.+)$") or "Prop")
		local highlight = Instance.new("Highlight")
		highlight.FillColor = part.Color
		highlight.FillTransparency = TINT_FILL
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
		model.Parent = root
		tintGroups[id] = model
		group = model
	end
	if part.Parent ~= group then
		part.Parent = group
	end
end

local function trackTexture(part: MeshPart)
	local id = part.TextureID
	local existing: Model? = tintGroups[id]
	if id == "" or (existing and part.Parent == existing) then
		return
	end
	local state = textureState[id]
	if state == "failed" then
		-- Deferred: this runs from DescendantAdded, where re-parenting at once is refused.
		task.defer(tint, part, id)
		return
	elseif state == "ok" then
		return
	elseif state == "pending" then
		local users = textureUsers[id]
		if users then
			table.insert(users, part)
		end
		return
	end
	textureState[id] = "pending"
	textureUsers[id] = { part }
	whenSettled(id, function(failed)
		textureState[id] = if failed then "failed" else "ok"
		local users = textureUsers[id]
		textureUsers[id] = nil
		if failed and users then
			for _, user in users do
				task.defer(tint, user, id)
			end
		end
	end)
	-- Ask for it now: a prop far from the camera may not have requested its texture yet.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ id })
		end)
	end)
end

---------------------------------------------------------------------------------------------------
-- Stand-in bodies

local function weld(part0: BasePart, part1: BasePart, offset: CFrame)
	local joint = Instance.new("Weld")
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = offset
	joint.Parent = part1
end

local function plain(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

-- A player whose avatar appearance could not load keeps Roblox's default bright-yellow skin.
local DEFAULT_SKIN = Color3.fromRGB(245, 205, 48)
local FALLBACK_SKIN = Color3.fromRGB(226, 182, 146)

local function isDefaultSkin(color: Color3): boolean
	local dr = math.abs(color.R - DEFAULT_SKIN.R)
	local dg = math.abs(color.G - DEFAULT_SKIN.G)
	local db = math.abs(color.B - DEFAULT_SKIN.B)
	return dr + dg + db < 0.08
end

local function colourFor(model: Model, part: BasePart): Color3
	local role = ROLE[part.Name]
	local phase = model:GetAttribute("Phase")
	if role == "skin" and isDefaultSkin(part.Color) then
		return FALLBACK_SKIN
	end
	if model:GetAttribute("Fighter") == nil or type(phase) ~= "string" or role == "skin" then
		return part.Color
	end
	local base = Phases.color(phase)
	if role == "robe" then
		return base:Lerp(Color3.fromRGB(24, 22, 28), 0.3)
	end
	return base:Lerp(Color3.fromRGB(16, 15, 20), 0.72)
end

local function addStandIn(model: Model, part: BasePart)
	if covered[part] or part.Parent == nil then
		return
	end
	covered[part] = true
	local size = part.Size
	local isHead = part.Name == "Head"
	local body: Part
	local extras: { BasePart } = {}
	if isHead then
		local diameter = math.min(size.X, size.Y, size.Z) * 1.08
		body = plain("StandInHead", Vector3.one * diameter, colourFor(model, part), Enum.PartType.Ball)
		local radius = diameter / 2
		for _, side in { -1, 1 } do
			local eye = plain("Eye", Vector3.one * radius * 0.2, Color3.fromRGB(20, 18, 22), Enum.PartType.Ball)
			eye.CastShadow = false
			weld(body, eye, CFrame.new(side * radius * 0.36, radius * 0.12, -radius * 0.9))
			table.insert(extras, eye)
		end
	else
		body = plain("StandIn" .. part.Name, size * 0.96, colourFor(model, part))
	end
	body.CFrame = part.CFrame
	weld(part, body, CFrame.identity)
	for _, extra in extras do
		extra.Parent = standIns
	end
	body.Parent = standIns
	local entry: StandIn = { part = part, body = body, extras = extras }
	table.insert(active, entry)
end

local function coverModel(model: Model)
	for _, child in model:GetChildren() do
		if child:IsA("MeshPart") and ROLE[child.Name] then
			local part = child
			whenFailed(part.MeshId, function()
				addStandIn(model, part)
			end)
		end
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("StandInWatched") then
		return
	end
	model:SetAttribute("StandInWatched", true)
	coverModel(model)
	-- Avatar parts arrive over a few frames after the model does.
	model.ChildAdded:Connect(function(child)
		if child:IsA("MeshPart") and ROLE[child.Name] then
			task.defer(coverModel, model)
		end
	end)
end

-- Stand-ins follow their body part's transparency (Mist, first-person zoom) and leave with it.
local function syncStandIns()
	for index = #active, 1, -1 do
		local entry = active[index]
		local part = entry.part
		if part.Parent == nil or not part:IsDescendantOf(Workspace) then
			entry.body:Destroy()
			for _, extra in entry.extras do
				extra:Destroy()
			end
			covered[part] = nil
			table.remove(active, index)
		else
			local transparency = part.Transparency
			local modifier = part.LocalTransparencyModifier
			if entry.body.Transparency ~= transparency then
				entry.body.Transparency = transparency
				for _, extra in entry.extras do
					extra.Transparency = transparency
				end
			end
			if entry.body.LocalTransparencyModifier ~= modifier then
				entry.body.LocalTransparencyModifier = modifier
				for _, extra in entry.extras do
					extra.LocalTransparencyModifier = modifier
				end
			end
		end
	end
end

function FallbackController.init(_self: any)
	standIns = Instance.new("Folder")
	standIns.Name = "StandInBodies"
	standIns.Parent = Workspace
end

function FallbackController.start(_self: any)
	local function onCharacter(character: Model)
		watch(character)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			onCharacter(player.Character)
		end
		player.CharacterAdded:Connect(onCharacter)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(onCharacter)
	end)
	for _, model in CollectionService:GetTagged("Npc") do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal("Npc"):Connect(watch)
	RunService.Heartbeat:Connect(syncStandIns)
	local map = Workspace:FindFirstChild("FarShore")
	if map then
		tintRoot = map
		for _, descendant in map:GetDescendants() do
			if descendant:IsA("MeshPart") then
				trackTexture(descendant)
			end
		end
		map.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("MeshPart") then
				trackTexture(descendant)
			end
		end)
	end
end

return FallbackController
