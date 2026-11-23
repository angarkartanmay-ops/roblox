--!strict
-- World-space UI (design/ui.json billboards): a PhaseNameplate over every other player, the
-- RelationIndicator over the enemy you are fighting (the last one you hit, else the nearest in
-- front), a DamageNumber for every hit you deal or take, and the DummyPhaseLabel that tells you how
-- your phase meets each training dummy's. Everything is local: other clients never see these.
-- The damage numbers and the relation indicator must read through bodies, but a BillboardGui with
-- AlwaysOnTop = true does not draw on every renderer (measured in Studio: the same billboard showed
-- with false and never with true). So those two live on a ScreenGui, projected from their world
-- point every frame; only the nameplates stay billboards.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Phases = require(ReplicatedStorage.Shared.Phases)
local Remotes = require("../Lib/Remotes")
local UiKit = require("../Lib/UiKit")

local NameplateController = {}

local localPlayer = Players.LocalPlayer
local TARGET_MEMORY = 4 -- seconds the last enemy you hit stays your target
local TARGET_RANGE = 45
local DAMAGE_RANGE = 140 -- studs from the camera a damage number still shows
local INDICATOR_RANGE = 120
local INDICATOR_LIFT = 4.4 -- studs above the target's head

type Plate = { gui: BillboardGui, name: TextLabel, glyph: TextLabel, fill: Frame, humanoid: Humanoid }

local plates: { [Model]: Plate } = {}
local dummyTags: { [Model]: TextLabel } = {}
local overlay: ScreenGui
local indicatorText: TextLabel
local lastTarget: Model? = nil
local lastTargetAt = 0

local function myPhase(): string?
	local character = localPlayer.Character
	local phase = if character then character:GetAttribute("Phase") else nil
	return if type(phase) == "string" then phase else nil
end

local function rootOf(model: Model?): BasePart?
	if not model or model.Parent == nil then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

---------------------------------------------------------------------------------------------------
-- PhaseNameplate

local function makePlate(model: Model): Plate?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	if not humanoid or not head or not head:IsA("BasePart") then
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local gui = UiKit.new("BillboardGui", {
		Name = "PhaseNameplate",
		Adornee = head,
		Size = UDim2.fromOffset(200, 46),
		StudsOffset = Vector3.new(0, 2.6, 0),
		MaxDistance = 120,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
	})
	local glyph = UiKit.label({
		Name = "Glyph",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(28, 28),
		Font = UiKit.HEAVY_FONT,
		TextSize = 22,
		Parent = gui,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = glyph
	local name = UiKit.label({
		Name = "DisplayName",
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -30, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 18,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = gui,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = name
	local bar = UiKit.new("Frame", {
		Name = "Health",
		Position = UDim2.fromOffset(30, 32),
		Size = UDim2.new(1, -40, 0, 6),
		BackgroundColor3 = UiKit.OUTLINE,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local fill = UiKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.HEALTH,
		BorderSizePixel = 0,
		Parent = bar,
	})
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	local player = Players:GetPlayerFromCharacter(model)
	name.Text = if player then player.DisplayName else model.Name
	return { gui = gui, name = name, glyph = glyph, fill = fill, humanoid = humanoid }
end

local function refreshPlates()
	local seen: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local model = player.Character
		if model and player ~= localPlayer then
			seen[model] = true
			local plate = plates[model]
			if not plate then
				local made = makePlate(model)
				if made then
					plates[model] = made
					plate = made
				end
			end
			if plate then
				local phase = model:GetAttribute("Phase")
				local info = if type(phase) == "string" then Phases.INFO[phase] else nil
				plate.glyph.Text = if info then info.glyph else ""
				plate.glyph.TextColor3 = if type(phase) == "string" then Phases.color(phase, true) else UiKit.INK_LIGHT
				local crowned = player:GetAttribute("LilyCrown") == true
				plate.name.Text = (if crowned then "✿ " else "") .. player.DisplayName
				plate.name.TextColor3 = if crowned then UiKit.TRIM else UiKit.INK_LIGHT
				local health = plate.humanoid.Health
				plate.fill.Size = UDim2.fromScale(math.clamp(health / math.max(plate.humanoid.MaxHealth, 1), 0, 1), 1)
				plate.gui.Enabled = health > 0 and model:GetAttribute("Mist") ~= true
			end
		end
	end
	for model, plate in plates do
		if not seen[model] or model.Parent == nil then
			plate.gui:Destroy()
			plates[model] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- DummyPhaseLabel

local function refreshDummyTags()
	local mine = myPhase()
	for _, model in CollectionService:GetTagged("Npc") do
		if not model:IsA("Model") then
			continue
		end
		local phase = model:GetAttribute("Phase")
		local root = rootOf(model)
		if type(phase) ~= "string" or not root or model:GetAttribute("Fighter") ~= nil then
			continue
		end
		local label = dummyTags[model]
		if not label then
			-- The relation is a third line on the dummy's own nameplate (a second billboard
			-- stacked over it collided with the neighbours' plates).
			local plate = model:FindFirstChild("Nameplate")
			if not plate or not plate:IsA("BillboardGui") then
				continue
			end
			plate.Size = UDim2.fromOffset(200, 66)
			plate.MaxDistance = 70
			local made = UiKit.label({
				Name = "DummyPhaseLabel",
				Position = UDim2.fromOffset(0, 46),
				Size = UDim2.new(1, 0, 0, 18),
				Font = UiKit.HEAVY_FONT,
				TextSize = 14,
				Parent = plate,
			})
			UiKit.textStroke(UiKit.OUTLINE, 2).Parent = made
			model.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					dummyTags[model] = nil
				end
			end)
			dummyTags[model] = made
			label = made
		end
		if label then
			local relation = Phases.relation(mine, phase)
			local verb = if relation == "Overcome"
				then "you OVERCOME it"
				elseif relation == "Resisted" then "it RESISTS you"
				elseif relation == "Feeding" then "you FEED it"
				elseif relation == "Drawing" then "you DRAW on it"
				else "even match"
			label.Text = verb
			label.TextColor3 = UiKit.RELATION[relation] or UiKit.INK_LIGHT
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Screen overlay

-- Put a label (anchored at its centre) over a world point, hidden behind the camera or past range.
local function place(label: GuiObject, world: Vector3, range: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		label.Visible = false
		return
	end
	local point = camera:WorldToViewportPoint(world)
	if point.Z <= 0 or (camera.CFrame.Position - world).Magnitude > range then
		label.Visible = false
		return
	end
	label.Position = UDim2.fromOffset(point.X, point.Y)
	label.Visible = true
end

---------------------------------------------------------------------------------------------------
-- RelationIndicator

local function nearestInFront(): Model?
	local character = localPlayer.Character
	local root = rootOf(character)
	if not root then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.new(0, 0, -1)
	local best: Model? = nil
	local bestScore = math.huge
	local candidates: { Model } = {}
	for _, player in Players:GetPlayers() do
		if player ~= localPlayer and player.Character then
			table.insert(candidates, player.Character)
		end
	end
	for _, tagged in CollectionService:GetTagged("Npc") do
		if tagged:IsA("Model") then
			table.insert(candidates, tagged)
		end
	end
	for _, model in candidates do
		local targetRoot = rootOf(model)
		if not targetRoot or not alive(model) or model:GetAttribute("Mist") == true then
			continue
		end
		local offset = targetRoot.Position - root.Position
		local planar = Vector3.new(offset.X, 0, offset.Z)
		local distance = planar.Magnitude
		if distance <= TARGET_RANGE and distance > 0.1 then
			local dot = planar.Unit:Dot(facing)
			if dot > 0.5 then
				local score = distance - dot * 12
				if score < bestScore then
					best = model
					bestScore = score
				end
			end
		end
	end
	return best
end

local function refreshIndicator()
	local target: Model? = nil
	if lastTarget and os.clock() - lastTargetAt <= TARGET_MEMORY and lastTarget.Parent and alive(lastTarget) then
		target = lastTarget
	else
		target = nearestInFront()
	end
	local mine = myPhase()
	local theirs = if target then target:GetAttribute("Phase") else nil
	local relation = if target and type(theirs) == "string" then Phases.relation(mine, theirs) else "Neutral"
	local root = rootOf(target)
	-- A training dummy's nameplate already states the relation.
	local isDummy = false
	if target and dummyTags[target] then
		isDummy = true
	end
	if not target or not root or relation == "Neutral" or isDummy then
		indicatorText.Visible = false
		return
	end
	local head = target:FindFirstChild("Head")
	local over: BasePart = if head and head:IsA("BasePart") then head else root
	indicatorText.Text = string.upper(relation)
	indicatorText.TextColor3 = UiKit.RELATION[relation] or UiKit.INK_LIGHT
	place(indicatorText, over.Position + Vector3.new(0, INDICATOR_LIFT, 0), INDICATOR_RANGE)
end

---------------------------------------------------------------------------------------------------
-- DamageNumber

local function damageNumber(position: Vector3, text: string, color: Color3, big: boolean)
	local label = UiKit.label({
		Name = "DamageNumber",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(120, 40),
		Font = UiKit.TITLE_FONT,
		TextSize = if big then 34 else 26,
		Text = text,
		TextColor3 = color,
		Visible = false,
		Parent = overlay,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	-- Numbers pop out to one side of the body and rise only a little: rising straight up they ran
	-- through the victim's nameplate and hid its health bar and relation line.
	local side = if math.random() < 0.5 then -1 else 1
	local drift = side * (1.8 + math.random() * 0.9)
	local lift = (math.random() - 0.5) * 0.8
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local age = os.clock() - started
		if age > 0.9 or label.Parent == nil then
			connection:Disconnect()
			label:Destroy()
			return
		end
		local camera = Workspace.CurrentCamera
		local right = if camera then camera.CFrame.RightVector else Vector3.xAxis
		local rise = 1.4 * (1 - (1 - math.min(age / 0.6, 1)) ^ 2)
		place(label, position + right * (drift + side * age * 0.6) + Vector3.new(0, lift + rise, 0), DAMAGE_RANGE)
		scale.Scale = 1 + 0.5 * math.max(0, 1 - age / 0.12)
		label.TextTransparency = math.clamp((age - 0.5) / 0.4, 0, 1)
	end)
end

local function relationOfFlags(flags: number): string
	if bit32.btest(flags, Remotes.FLAG_OVERCOME) then
		return "Overcome"
	elseif bit32.btest(flags, Remotes.FLAG_RESISTED) then
		return "Resisted"
	elseif bit32.btest(flags, Remotes.FLAG_FEEDING) then
		return "Feeding"
	elseif bit32.btest(flags, Remotes.FLAG_DRAWING) then
		return "Drawing"
	end
	return "Neutral"
end

local function onHit(victim: Model?, attacker: Model?, amount: number, flags: number, position: Vector3)
	if typeof(position) ~= "Vector3" or type(amount) ~= "number" or type(flags) ~= "number" then
		return
	end
	local character = localPlayer.Character
	local mine = attacker ~= nil and attacker == character
	local onMe = victim ~= nil and victim == character
	if mine and victim and victim ~= character then
		lastTarget = victim
		lastTargetAt = os.clock()
	end
	if not mine and not onMe then
		return
	end
	if bit32.btest(flags, Remotes.FLAG_HEAL) then
		if amount >= 1 then
			damageNumber(position, `+{math.floor(amount + 0.5)}`, UiKit.HEALTH, false)
		end
		return
	end
	if bit32.btest(flags, Remotes.FLAG_PARRIED) then
		damageNumber(position, "PARRY", UiKit.INK_LIGHT, true)
		return
	end
	if bit32.btest(flags, Remotes.FLAG_CATCH) then
		damageNumber(position, "CAUGHT", UiKit.INK_LIGHT, true)
		return
	end
	if bit32.btest(flags, Remotes.FLAG_RING_OUT) then
		damageNumber(position, "RING-OUT", UiKit.TRIM, true)
		return
	end
	if bit32.btest(flags, Remotes.FLAG_GUARD_BREAK) then
		damageNumber(position + Vector3.new(0, 1.5, 0), "GUARD BREAK", UiKit.TRIM, true)
	end
	if amount <= 0 then
		return
	end
	local blocked = bit32.btest(flags, Remotes.FLAG_BLOCKED)
	local relation = relationOfFlags(flags)
	local color = if blocked
		then UiKit.GREY
		elseif onMe then UiKit.LACQUER
		else UiKit.RELATION[relation] or UiKit.INK_LIGHT
	local text = `-{math.floor(amount * 10 + 0.5) / 10}`
	if bit32.btest(flags, Remotes.FLAG_BEAT) then
		text ..= "!"
	end
	damageNumber(position, text, color, amount >= 10 or relation == "Overcome")
end

function NameplateController.init(_self: any)
	-- Under the HUD (DisplayOrder 10), over the world. IgnoreGuiInset so viewport points match.
	overlay = UiKit.new("ScreenGui", {
		Name = "WorldOverlay",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 2,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	indicatorText = UiKit.label({
		Name = "RelationIndicator",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(160, 30),
		Font = UiKit.TITLE_FONT,
		TextSize = 26,
		Visible = false,
		Parent = overlay,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = indicatorText
end

function NameplateController.start(_self: any)
	Remotes.HitFx.OnClientEvent:Connect(onHit)
	task.spawn(function()
		while true do
			refreshPlates()
			refreshDummyTags()
			task.wait(0.25)
		end
	end)
	-- After the camera moves, so the indicator sits on the target this frame.
	RunService:BindToRenderStep("RelationIndicator", Enum.RenderPriority.Camera.Value + 2, refreshIndicator)
end

return NameplateController
