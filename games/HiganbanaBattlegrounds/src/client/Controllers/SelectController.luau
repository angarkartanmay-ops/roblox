--!strict
-- Phase Select and the Death Recap (design/ui.json screens PhaseSelect and DeathRecap).
-- Phase Select teaches the Five Phases: the five fighters sit on a wheel whose rim arrows are the
-- generating cycle and whose inner star is the overcoming cycle. Picking is two clicks (card, then
-- CROSS). It opens on first spawn, with T / D-pad down, at the lantern by the landing (the server's
-- "openSelect"), and from the Death Recap's counter pick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require("../Lib/Remotes")
local UiKit = require("../Lib/UiKit")
local SoundController = require("./SoundController")

type FighterSpec = Types.FighterSpec

local SelectController = {}

local localPlayer = Players.LocalPlayer

local KEY_LABEL: { [string]: string } = {
	M1 = "LMB",
	Ability1 = "1",
	Ability2 = "2",
	Ability3 = "3",
	Ability4 = "4",
	Ultimate = "G",
}

-- Wheel layout: generating order clockwise from the top.
local WHEEL_SIZE = 470
local WHEEL_RADIUS = 168

local selectScreen: ScreenGui? = nil
local recapScreen: ScreenGui? = nil
local cards: { [string]: TextButton } = {}
local detail: { [string]: any } = {}
local selectedId = Fighters.DEFAULT_ID
local openListeners: { (boolean) -> () } = {}
local recapToken = 0

local function upper(text: string): string
	return string.upper(text)
end

local function stars(count: number): string
	return string.rep("★", count) .. string.rep("☆", 3 - count)
end

local function phaseUi(phase: string): Color3
	return Phases.color(phase, true)
end

local function currentFighterId(): string?
	local character = localPlayer.Character
	local id = if character then character:GetAttribute("Fighter") else nil
	if type(id) ~= "string" then
		id = localPlayer:GetAttribute("Fighter")
	end
	return if type(id) == "string" then id else nil
end

---------------------------------------------------------------------------------------------------
-- Phase Select

local function wheelPoint(index: number): Vector2
	local angle = math.rad(-90 + (index - 1) * 72)
	return Vector2.new(WHEEL_SIZE / 2 + math.cos(angle) * WHEEL_RADIUS, WHEEL_SIZE / 2 + math.sin(angle) * WHEEL_RADIUS)
end

-- A straight bar between two points inside the wheel, with an arrowhead dot near `b`.
local function wheelLine(parent: Instance, a: Vector2, b: Vector2, color: Color3, thickness: number, arrow: boolean)
	local delta = b - a
	local length = delta.Magnitude
	local middle = (a + b) / 2
	UiKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(middle.X, middle.Y),
		Size = UDim2.fromOffset(length, thickness),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = parent,
	})
	if arrow then
		local tip = a + delta * 0.78
		UiKit.new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(tip.X, tip.Y),
			Size = UDim2.fromOffset(22, 22),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundTransparency = 1,
			Text = "▶",
			TextColor3 = color,
			TextSize = 20,
			Font = UiKit.HEAVY_FONT,
			ZIndex = 2,
			Parent = parent,
		})
	end
end

local function moveRow(parent: Instance, order: number): { [string]: TextLabel }
	local row = UiKit.new("Frame", {
		Name = `Move{order}`,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = UiKit.PANEL_ALT,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiKit.corner(8).Parent = row
	local key = UiKit.label({
		Name = "Key",
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(46, 36),
		BackgroundTransparency = 0,
		BackgroundColor3 = UiKit.SLOT,
		Font = UiKit.HEAVY_FONT,
		TextSize = 18,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = row,
	})
	UiKit.corner(6).Parent = key
	local name = UiKit.label({
		Name = "MoveName",
		Position = UDim2.fromOffset(64, 4),
		Size = UDim2.new(1, -72, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 19,
		TextColor3 = UiKit.INK_LIGHT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local line = UiKit.label({
		Name = "Line",
		Position = UDim2.fromOffset(64, 26),
		Size = UDim2.new(1, -72, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		TextColor3 = UiKit.INK_DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	return { key = key, name = name, line = line }
end

local function refreshDetail()
	local fighter = Fighters.getOrDefault(selectedId)
	local tint = phaseUi(fighter.phase)
	local info = Phases.INFO[fighter.phase]
	detail.header.BackgroundColor3 = tint
	detail.glyph.Text = info.glyph
	detail.name.Text = upper(fighter.displayName)
	detail.title.Text = fighter.title
	detail.role.Text = `{upper(fighter.phase)}  ·  {fighter.role}  ·  {stars(fighter.difficulty)}`
	detail.passive.Text = if fighter.passiveName and fighter.passive
		then `<b>{fighter.passiveName}:</b> {fighter.passive}`
		else fighter.blurb
	local rows = detail.rows :: { { [string]: TextLabel } }
	rows[1].key.Text = KEY_LABEL.M1
	rows[1].name.Text = "Four-hit chain"
	rows[1].line.Text = "Hold to chain; the fourth hit launches. Hold F to block, Q to dash, R to Mend."
	for index, slot in Fighters.SLOTS do
		local move = Fighters.moveForSlot(fighter, slot)
		local row = rows[index + 1]
		row.key.Text = KEY_LABEL[slot] or slot
		row.name.Text = if move then move.name else "—"
		row.line.Text = if move then move.description else ""
	end
	local overcomes = Phases.OVERCOMES[fighter.phase]
	local overcomer = Phases.overcomerOf(fighter.phase)
	detail.counter.Text = `Overcomes {upper(overcomes or "?")}  |  Overcome by {upper(overcomer or "?")}`
	local current = currentFighterId()
	detail.cross.Text = if current == fighter.id then "CROSS AGAIN" else "CROSS"
	for id, card in cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == selectedId then UiKit.TRIM else UiKit.OUTLINE
			stroke.Thickness = if id == selectedId then 4 else 3
		end
	end
end

local function chooseFighter(id: string)
	if Fighters.get(id) then
		selectedId = id
		refreshDetail()
		SoundController.play("ui")
	end
end

local function buildCard(parent: Instance, fighter: FighterSpec, center: Vector2): TextButton
	local tint = phaseUi(fighter.phase)
	local card = UiKit.button({
		Name = `FighterCard_{fighter.id}`,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(150, 104),
		BackgroundColor3 = UiKit.PANEL,
		Text = "",
		ZIndex = 3,
		Parent = parent,
	})
	local glyph = UiKit.label({
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -20),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 0,
		BackgroundColor3 = UiKit.OUTLINE,
		Text = Phases.INFO[fighter.phase].glyph,
		TextColor3 = tint,
		TextSize = 28,
		Font = UiKit.HEAVY_FONT,
		ZIndex = 4,
		Parent = card,
	})
	UiKit.corner(22).Parent = glyph
	UiKit.stroke(tint, 2).Parent = glyph
	UiKit.label({
		Name = "FighterName",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 26),
		Text = upper(fighter.displayName),
		Font = UiKit.HEAVY_FONT,
		TextSize = 22,
		TextColor3 = UiKit.INK_LIGHT,
		ZIndex = 4,
		Parent = card,
	})
	UiKit.label({
		Name = "Role",
		Position = UDim2.fromOffset(4, 52),
		Size = UDim2.new(1, -8, 0, 20),
		Text = fighter.role,
		TextSize = 13,
		TextColor3 = UiKit.INK_DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 4,
		Parent = card,
	})
	UiKit.label({
		Name = "Difficulty",
		Position = UDim2.fromOffset(0, 74),
		Size = UDim2.new(1, 0, 0, 22),
		Text = stars(fighter.difficulty),
		TextSize = 18,
		TextColor3 = UiKit.TRIM,
		ZIndex = 4,
		Parent = card,
	})
	card.Activated:Connect(function()
		chooseFighter(fighter.id)
	end)
	return card
end

local function buildSelect(parent: Instance)
	local gui, root = UiKit.screen("PhaseSelect", 30, parent)
	selectScreen = gui
	gui.Enabled = false
	UiKit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = UiKit.OUTLINE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = gui,
	})

	UiKit.label({
		Name = "Heading",
		Position = UDim2.fromOffset(40, 22),
		Size = UDim2.fromOffset(700, 52),
		Text = "CHOOSE YOUR PHASE",
		Font = UiKit.TITLE_FONT,
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = root,
	})
	UiKit.label({
		Name = "Subheading",
		Position = UDim2.fromOffset(42, 70),
		Size = UDim2.fromOffset(640, 24),
		Text = "Rim arrows: each phase feeds the next.  Inner star: each phase overcomes the one it points at.",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.INK_DIM,
		Parent = root,
	})

	-- PhaseWheel
	local wheel = UiKit.new("Frame", {
		Name = "PhaseWheel",
		Position = UDim2.fromOffset(40, 140),
		Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local points: { [string]: Vector2 } = {}
	for index, phase in Phases.ORDER do
		points[phase] = wheelPoint(index)
	end
	for _, phase in Phases.ORDER do
		local generated = Phases.GENERATES[phase]
		local overcome = Phases.OVERCOMES[phase]
		wheelLine(wheel, points[phase], points[generated], UiKit.INK_DIM, 4, true)
		wheelLine(wheel, points[phase], points[overcome], UiKit.KI, 3, true)
	end
	for index, phase in Phases.ORDER do
		local fighter = Fighters.forPhase(phase)
		if fighter then
			cards[fighter.id] = buildCard(wheel, fighter, wheelPoint(index))
		end
	end

	-- FighterDetail
	local panel = UiKit.panel({
		Name = "FighterDetail",
		Position = UDim2.fromOffset(560, 104),
		Size = UDim2.fromOffset(680, 590),
		Parent = root,
	})
	local header = UiKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundColor3 = UiKit.TRIM,
		BorderSizePixel = 0,
		Parent = panel,
	})
	UiKit.corner(12).Parent = header
	UiKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(70, 70, 70), 90).Parent = header
	local glyph = UiKit.label({
		Name = "Glyph",
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.fromOffset(72, 72),
		BackgroundTransparency = 0,
		BackgroundColor3 = UiKit.OUTLINE,
		Font = UiKit.HEAVY_FONT,
		TextSize = 46,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = header,
	})
	UiKit.corner(36).Parent = glyph
	local name = UiKit.label({
		Name = "FighterName",
		Position = UDim2.fromOffset(100, 10),
		Size = UDim2.new(1, -110, 0, 44),
		Font = UiKit.TITLE_FONT,
		TextSize = 42,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = header,
	})
	UiKit.textStroke(UiKit.OUTLINE, 3).Parent = name
	local title = UiKit.label({
		Name = "Title",
		Position = UDim2.fromOffset(102, 54),
		Size = UDim2.new(1, -112, 0, 30),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = header,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = title
	local role = UiKit.label({
		Name = "Role",
		Position = UDim2.fromOffset(18, 102),
		Size = UDim2.new(1, -36, 0, 24),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.TRIM,
		Parent = panel,
	})
	local passive = UiKit.label({
		Name = "Passive",
		Position = UDim2.fromOffset(18, 128),
		Size = UDim2.new(1, -36, 0, 40),
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = panel,
	})
	local list = UiKit.new("Frame", {
		Name = "Moves",
		Position = UDim2.fromOffset(14, 172),
		Size = UDim2.new(1, -28, 0, 6 * 56),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local layout = UiKit.list(Enum.FillDirection.Vertical, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = list
	local rows = {}
	for index = 1, 6 do
		table.insert(rows, moveRow(list, index))
	end
	local counter = UiKit.label({
		Name = "CounterHint",
		Position = UDim2.fromOffset(18, 512),
		Size = UDim2.new(1, -300, 0, 60),
		TextSize = 17,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = panel,
	})
	local cross = UiKit.button({
		Name = "CrossButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -12),
		Size = UDim2.fromOffset(260, 88),
		BackgroundColor3 = UiKit.LACQUER,
		Text = "CROSS",
		TextSize = 34,
		Font = UiKit.TITLE_FONT,
		Parent = panel,
	})
	cross.Activated:Connect(function()
		Remotes.SelectFighter:FireServer(selectedId)
		SoundController.play("bell")
		SelectController.close()
	end)

	local close = UiKit.button({
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 18),
		Size = UDim2.fromOffset(88, 88),
		Text = "✕",
		TextSize = 34,
		Parent = root,
	})
	close.Activated:Connect(function()
		SelectController.close()
	end)

	detail = {
		header = header,
		glyph = glyph,
		name = name,
		title = title,
		role = role,
		passive = passive,
		rows = rows,
		counter = counter,
		cross = cross,
	}
	refreshDetail()
end

---------------------------------------------------------------------------------------------------
-- Death Recap

local recap: { [string]: any } = {}

local RELATION_LINE: { [string]: string } = {
	Overcome = "They OVERCAME you: %s overcomes %s",
	Resisted = "You had the edge: %s overcomes %s. They won anyway.",
	Feeding = "Their hits fed your Ki: %s feeds %s",
	Drawing = "They drew on you: %s feeds %s",
}

local function relationText(killerPhase: string?, myPhase: string?): (string, Color3)
	if not killerPhase or not myPhase then
		return "The far shore took you.", UiKit.INK_LIGHT
	end
	local relation = Phases.relation(killerPhase, myPhase)
	local template = RELATION_LINE[relation]
	if not template then
		return `Same phase: {upper(myPhase)} against {upper(killerPhase)}, no edge either way.`, UiKit.INK_LIGHT
	end
	local text = if relation == "Overcome" or relation == "Feeding"
		then string.format(template, upper(killerPhase), upper(myPhase))
		else string.format(template, upper(myPhase), upper(killerPhase))
	return text, UiKit.RELATION[relation] or UiKit.INK_LIGHT
end

local function buildRecap(parent: Instance)
	local gui, root = UiKit.screen("DeathRecap", 25, parent)
	recapScreen = gui
	gui.Enabled = false
	local card = UiKit.panel({
		Name = "KillerCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(640, 300),
		Size = UDim2.fromOffset(700, 330),
		Parent = root,
	})
	local heading = UiKit.label({
		Name = "Heading",
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 54),
		Font = UiKit.TITLE_FONT,
		TextSize = 48,
		TextColor3 = UiKit.LACQUER,
		Text = "YOU CROSSED THE RIVER",
		Parent = card,
	})
	UiKit.textStroke(UiKit.OUTLINE, 3).Parent = heading
	local killer = UiKit.label({
		Name = "Killer",
		Position = UDim2.fromOffset(20, 72),
		Size = UDim2.new(1, -40, 0, 32),
		Font = UiKit.HEAVY_FONT,
		TextSize = 24,
		TextColor3 = UiKit.INK_LIGHT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local relation = UiKit.label({
		Name = "Relation",
		Position = UDim2.fromOffset(20, 108),
		Size = UDim2.new(1, -40, 0, 30),
		Font = UiKit.HEAVY_FONT,
		TextSize = 20,
		TextWrapped = true,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = card,
	})
	local sources = UiKit.label({
		Name = "Sources",
		Position = UDim2.fromOffset(20, 146),
		Size = UDim2.new(1, -40, 0, 70),
		TextSize = 16,
		TextWrapped = true,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = UiKit.INK_DIM,
		Parent = card,
	})
	local counter = UiKit.button({
		Name = "CounterPick",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 226),
		Size = UDim2.fromOffset(520, 88),
		BackgroundColor3 = UiKit.LACQUER,
		TextSize = 26,
		Parent = card,
	})
	local timer = UiKit.label({
		Name = "RespawnTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(640, 478),
		Size = UDim2.fromOffset(400, 34),
		Font = UiKit.HEAVY_FONT,
		TextSize = 24,
		TextColor3 = UiKit.INK_LIGHT,
		Parent = root,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = timer
	local same = UiKit.button({
		Name = "SameFighterButton",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(640, 520),
		Size = UDim2.fromOffset(300, 88),
		Text = "SAME FIGHTER",
		TextSize = 26,
		Parent = root,
	})
	same.Activated:Connect(function()
		gui.Enabled = false
	end)
	counter.Activated:Connect(function()
		gui.Enabled = false
		local id = counter:GetAttribute("FighterId")
		SelectController.open(if type(id) == "string" then id else nil)
	end)
	recap =
		{ heading = heading, killer = killer, relation = relation, sources = sources, counter = counter, timer = timer }
end

local function showRecap(data: any)
	if type(data) ~= "table" then
		return
	end
	recapToken += 1
	local token = recapToken
	local killerName = if type(data.killer) == "string" then data.killer else nil
	local killerFighter = Fighters.get(if type(data.killerFighter) == "string" then data.killerFighter else nil)
	local killerPhase = if type(data.killerPhase) == "string" then data.killerPhase else nil
	local myFighter = Fighters.get(currentFighterId())
	local myPhase = if myFighter then myFighter.phase else nil

	recap.heading.Text = if data.ringOut == true then "RUNG OUT" else "YOU CROSSED THE RIVER"
	if killerName then
		local suffix = if killerFighter then ` ({killerFighter.displayName}, {upper(killerFighter.phase)})` else ""
		recap.killer.Text = `Sent across by {killerName}{suffix}`
	else
		recap.killer.Text = if data.ringOut == true then "You fell from the shore." else "The far shore took you."
	end
	local text, color = relationText(killerPhase, myPhase)
	recap.relation.Text = text
	recap.relation.TextColor3 = color

	local lines = {}
	if type(data.sources) == "table" then
		for index, source in data.sources do
			if index > 3 then
				break
			end
			if type(source) == "table" and type(source.name) == "string" and type(source.amount) == "number" then
				table.insert(lines, `{source.name}  <b>{source.amount}</b>`)
			end
		end
	end
	recap.sources.Text = if #lines > 0 then "Damage taken:  " .. table.concat(lines, "   ·   ") else ""

	local counterFighter = Fighters.get(if type(data.counter) == "string" then data.counter else nil)
	if counterFighter then
		recap.counter.Visible = true
		recap.counter.Text = `Counter with {upper(counterFighter.phase)} ({counterFighter.displayName})`
		recap.counter.BackgroundColor3 = Phases.color(counterFighter.phase, true)
		recap.counter:SetAttribute("FighterId", counterFighter.id)
	else
		recap.counter.Visible = false
	end
	local screen = recapScreen
	if not screen then
		return
	end
	screen.Enabled = true

	local respawnAt = os.clock() + (tonumber(data.respawn) or 4)
	task.spawn(function()
		while recapToken == token and screen.Enabled do
			local left = math.max(0, math.ceil(respawnAt - os.clock()))
			recap.timer.Text = if left > 0 then `Respawning in {left}` else "Returning..."
			task.wait(0.2)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Public API

function SelectController.isOpen(): boolean
	local screen = selectScreen
	return screen ~= nil and screen.Enabled
end

function SelectController.onToggled(listener: (boolean) -> ())
	table.insert(openListeners, listener)
end

local function setOpen(open: boolean)
	local screen = selectScreen
	if not screen or screen.Enabled == open then
		return
	end
	screen.Enabled = open
	for _, listener in openListeners do
		listener(open)
	end
end

-- Open Phase Select, optionally with a fighter already chosen (the recap's counter pick).
function SelectController.open(highlightId: string?)
	if highlightId and Fighters.get(highlightId) then
		selectedId = highlightId
	else
		selectedId = currentFighterId() or selectedId
	end
	refreshDetail()
	local recapGui = recapScreen
	if recapGui then
		recapGui.Enabled = false
	end
	setOpen(true)
end

function SelectController.close()
	setOpen(false)
end

function SelectController.toggle()
	if SelectController.isOpen() then
		SelectController.close()
	else
		SelectController.open()
	end
end

function SelectController.init(_self: any)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	buildSelect(playerGui)
	buildRecap(playerGui)
end

function SelectController.start(_self: any)
	Remotes.Notify.OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "openSelect" then
			SelectController.open()
		elseif kind == "recap" then
			showRecap(data)
		end
	end)

	-- First spawn opens the select screen once.
	local opened = false
	local function onCharacter()
		if not opened then
			opened = true
			task.delay(0.5, function()
				SelectController.open()
			end)
		else
			local recapGui = recapScreen
			if recapGui then
				recapGui.Enabled = false
			end
		end
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
	if localPlayer.Character then
		onCharacter()
	end

	-- Keep the CROSS label honest when the server changes our fighter.
	localPlayer:GetAttributeChangedSignal("Fighter"):Connect(function()
		if SelectController.isOpen() then
			refreshDetail()
		end
	end)
	-- Re-scale with the camera (the camera may be replaced on respawn).
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local screen = selectScreen
		local root = if screen then screen:FindFirstChild("Root") else nil
		local scale = if root then root:FindFirstChildOfClass("UIScale") else nil
		if scale then
			UiKit.autoScale(scale)
		end
	end)
end

return SelectController
