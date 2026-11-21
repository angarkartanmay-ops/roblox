--!strict
-- The fight HUD (design/ui.json screen HUD) and the touch controls (screen TouchControls).
-- Every element is laid out at the 1280x720 reference inside an edge-anchored group with its own
-- UIScale, so it stays in its corner on any screen. Reads only replicated state: the character's
-- status attributes, the player's Ki / Fighter / Streak attributes, leaderstats, and the Workspace
-- attributes the Thirst and the Elder publish. Events: Notify (toast, announce, kill), HitFx (combo
-- counter) and ElderFx (reward popup).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Remotes = require("../Lib/Remotes")
local UiKit = require("../Lib/UiKit")
local InputController = require("./InputController")
local SelectController = require("./SelectController")
local SoundController = require("./SoundController")

local HudController = {}

local localPlayer = Players.LocalPlayer

local SLOTS = { "M1", "Ability1", "Ability2", "Ability3", "Ability4", "Ultimate" }
local SLOT_NAME: { [string]: string } = {
	M1 = "Slot_M1",
	Ability1 = "Slot_1",
	Ability2 = "Slot_2",
	Ability3 = "Slot_3",
	Ability4 = "Slot_4",
	Ultimate = "Slot_G",
}
local KEY_HINT: { [string]: string } = {
	M1 = "LMB",
	Ability1 = "1",
	Ability2 = "2",
	Ability3 = "3",
	Ability4 = "4",
	Ultimate = "G",
}

-- Status chips in display order: attribute, short label, colour.
local STATUS_CHIPS: { { attribute: string, label: string, color: Color3 } } = {
	{ attribute = "Stunned", label = "STUN", color = Color3.fromHex("#E3C341") },
	{ attribute = "GuardBroken", label = "BROKEN", color = Color3.fromHex("#C99A3B") },
	{ attribute = "Grabbed", label = "HELD", color = Color3.fromHex("#8C5A3A") },
	{ attribute = "Rooted", label = "ROOT", color = Color3.fromHex("#4AA860") },
	{ attribute = "Bound", label = "BOUND", color = Color3.fromHex("#E2E6EC") },
	{ attribute = "Silenced", label = "SILENCE", color = Color3.fromHex("#C21F2E") },
	{ attribute = "Slowed", label = "SLOW", color = Color3.fromHex("#8C8A93") },
	{ attribute = "Burning", label = "BURN", color = Color3.fromHex("#E44828") },
	{ attribute = "Purified", label = "PURIFIED", color = Color3.fromHex("#F6F4EC") },
	{ attribute = "SuperArmor", label = "ARMOR", color = Color3.fromHex("#D6A840") },
	{ attribute = "Sprouts", label = "SPROUT", color = Color3.fromHex("#4AA860") },
	{ attribute = "Sap", label = "SAP", color = Color3.fromHex("#E09628") },
	{ attribute = "Hasted", label = "HASTE", color = Color3.fromHex("#FF963C") },
	{ attribute = "Mist", label = "MIST", color = Color3.fromHex("#CED6E2") },
}

local gui: ScreenGui
local ui: { [string]: any } = {}
local slotViews: { [string]: { [string]: any } } = {}
local feedLines: { TextLabel } = {}
local comboCount = 0
local lastComboAt = 0
local rewardToken = 0
local pulse = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function character(): Model?
	return localPlayer.Character
end

local function humanoidOf(model: Model?): Humanoid?
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

local function attribute(instance: Instance?, name: string): any
	return if instance then instance:GetAttribute(name) else nil
end

local function number(value: any, default: number): number
	return if type(value) == "number" then value else default
end

local function commas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

local function clock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

-- A frame anchored to a point of the screen with its own reference-scaled UIScale.
local function group(name: string, anchor: Vector2, position: UDim2, size: Vector2): Frame
	local frame = UiKit.new("Frame", {
		Name = name,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	UiKit.autoScale(scale, 0.55, 1.4)
	return frame
end

-- A labelled meter: returns the frame, the fill and the caption.
local function meter(
	parent: Instance,
	name: string,
	position: UDim2,
	size: UDim2,
	color: Color3
): (Frame, Frame, TextLabel)
	local frame = UiKit.new("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = UiKit.OUTLINE,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = parent,
	})
	UiKit.corner(6).Parent = frame
	UiKit.stroke(UiKit.OUTLINE, 2).Parent = frame
	local fill = UiKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = frame,
	})
	UiKit.corner(6).Parent = fill
	local caption = UiKit.label({
		Name = "Caption",
		Size = UDim2.fromScale(1, 1),
		Font = UiKit.HEAVY_FONT,
		TextSize = 16,
		TextColor3 = UiKit.INK_LIGHT,
		ZIndex = 3,
		Parent = frame,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = caption
	return frame, fill, caption
end

local function setFill(fill: Frame, fraction: number)
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

---------------------------------------------------------------------------------------------------
-- Build

local function buildBottom()
	local bottom = group("Bottom", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), Vector2.new(820, 250))

	-- StatusRow
	local statusRow = UiKit.new("Frame", {
		Name = "StatusRow",
		Position = UDim2.fromOffset(130, 0),
		Size = UDim2.fromOffset(560, 30),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	UiKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center).Parent = statusRow
	local chips: { [string]: TextLabel } = {}
	for order, spec in STATUS_CHIPS do
		local chip = UiKit.label({
			Name = spec.attribute,
			LayoutOrder = order,
			Size = UDim2.fromOffset(84, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0.1,
			BackgroundColor3 = UiKit.PANEL,
			Text = spec.label,
			Font = UiKit.HEAVY_FONT,
			TextSize = 14,
			TextColor3 = spec.color,
			Visible = false,
			Parent = statusRow,
		})
		UiKit.corner(6).Parent = chip
		UiKit.stroke(spec.color, 2).Parent = chip
		UiKit.padding(4).Parent = chip
		chips[spec.attribute] = chip
	end
	ui.chips = chips

	-- PhaseBadge
	local badge = UiKit.panel({
		Name = "PhaseBadge",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.fromOffset(120, 112),
		Parent = bottom,
	})
	ui.badgeGlyph = UiKit.label({
		Name = "Glyph",
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, 0, 0, 52),
		Font = UiKit.HEAVY_FONT,
		TextSize = 46,
		Parent = badge,
	})
	ui.badgePhase = UiKit.label({
		Name = "PhaseName",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 0, 24),
		Font = UiKit.HEAVY_FONT,
		TextSize = 20,
		Parent = badge,
	})
	ui.badgeFighter = UiKit.label({
		Name = "FighterName",
		Position = UDim2.fromOffset(0, 82),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 16,
		TextColor3 = UiKit.INK_DIM,
		Parent = badge,
	})

	-- Vitals
	local vitals = UiKit.new("Frame", {
		Name = "Vitals",
		Position = UDim2.fromOffset(130, 36),
		Size = UDim2.fromOffset(560, 92),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	local _, healthFill, healthText =
		meter(vitals, "HealthBar", UDim2.fromOffset(0, 4), UDim2.fromOffset(560, 28), UiKit.HEALTH)
	healthText.TextSize = 18
	local kiFrame, kiFill, kiText = meter(vitals, "KiBar", UDim2.fromOffset(0, 38), UDim2.fromOffset(560, 22), UiKit.KI)
	local kiGlow = UiKit.stroke(UiKit.TRIM, 3, 1)
	kiGlow.Parent = kiFrame
	local guardFrame, guardFill =
		meter(vitals, "GuardBar", UDim2.fromOffset(0, 66), UDim2.fromOffset(560, 10), UiKit.GUARD)
	local mendFrame, mendFill, mendText =
		meter(vitals, "MendBar", UDim2.fromOffset(80, 66), UDim2.fromOffset(400, 22), UiKit.HEALTH)
	mendText.Text = "MENDING"
	mendFrame.Visible = false
	ui.healthFill = healthFill
	ui.healthText = healthText
	ui.kiFill = kiFill
	ui.kiText = kiText
	ui.kiGlow = kiGlow
	ui.guardFrame = guardFrame
	ui.guardFill = guardFill
	ui.mendFrame = mendFrame
	ui.mendFill = mendFill

	-- AbilityBar
	local bar = UiKit.new("Frame", {
		Name = "AbilityBar",
		Position = UDim2.fromOffset(130, 140),
		Size = UDim2.fromOffset(560, 100),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	UiKit.list(Enum.FillDirection.Horizontal, 8).Parent = bar
	for order, slot in SLOTS do
		local frame = UiKit.panel({
			Name = SLOT_NAME[slot],
			LayoutOrder = order,
			Size = UDim2.fromOffset(84, 92),
			Parent = bar,
		})
		frame.ClipsDescendants = true
		local icon = UiKit.label({
			Name = "Icon",
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 40),
			Font = UiKit.HEAVY_FONT,
			TextSize = 28,
			Parent = frame,
		})
		local name = UiKit.label({
			Name = "MoveName",
			Position = UDim2.fromOffset(2, 60),
			Size = UDim2.new(1, -4, 0, 28),
			TextSize = 12,
			TextWrapped = true,
			TextColor3 = UiKit.INK_DIM,
			Parent = frame,
		})
		local key = UiKit.label({
			Name = "Key",
			Position = UDim2.fromOffset(4, 2),
			Size = UDim2.fromOffset(40, 18),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = UiKit.HEAVY_FONT,
			TextSize = 14,
			TextColor3 = UiKit.TRIM,
			Text = KEY_HINT[slot],
			Parent = frame,
		})
		local sweep = UiKit.new("Frame", {
			Name = "Sweep",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = UiKit.OUTLINE,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = frame,
		})
		local seconds = UiKit.label({
			Name = "Seconds",
			Size = UDim2.fromScale(1, 1),
			Font = UiKit.HEAVY_FONT,
			TextSize = 26,
			ZIndex = 5,
			Parent = frame,
		})
		UiKit.textStroke(UiKit.OUTLINE, 2).Parent = seconds
		local view: { [string]: any } =
			{ frame = frame, icon = icon, name = name, key = key, sweep = sweep, seconds = seconds }
		if slot == "M1" then
			local pips = UiKit.new("Frame", {
				Name = "ComboPips",
				Position = UDim2.new(0, 8, 1, -14),
				Size = UDim2.new(1, -16, 0, 8),
				BackgroundTransparency = 1,
				ZIndex = 6,
				Parent = frame,
			})
			UiKit.list(Enum.FillDirection.Horizontal, 4).Parent = pips
			local list = {}
			for index = 1, Constants.COMBO_HITS do
				local pip = UiKit.new("Frame", {
					Name = `Pip{index}`,
					LayoutOrder = index,
					Size = UDim2.fromOffset(13, 8),
					BackgroundColor3 = UiKit.SLOT,
					BorderSizePixel = 0,
					ZIndex = 6,
					Parent = pips,
				})
				UiKit.corner(3).Parent = pip
				table.insert(list, pip)
			end
			view.pips = list
		end
		slotViews[slot] = view
	end

	-- Toast (short local notices) above the status row
	ui.toast = UiKit.label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(410, -6),
		Size = UDim2.fromOffset(700, 30),
		Font = UiKit.HEAVY_FONT,
		TextSize = 22,
		TextTransparency = 1,
		Parent = bottom,
	})
	UiKit.textStroke(UiKit.OUTLINE, 2).Parent = ui.toast
end

local function buildTop()
	-- PetalsPanel (top-left, below the 36 px top bar)
	local left = group("TopLeft", Vector2.new(0, 0), UDim2.fromOffset(12, 48), Vector2.new(240, 60))
	local petals = UiKit.panel({ Name = "PetalsPanel", Size = UDim2.fromOffset(240, 56), Parent = left })
	UiKit.label({
		Name = "Icon",
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromOffset(40, 56),
		Text = "✿",
		TextSize = 34,
		TextColor3 = UiKit.LACQUER,
		Parent = petals,
	})
	ui.petals = UiKit.label({
		Name = "Petals",
		Position = UDim2.fromOffset(50, 0),
		Size = UDim2.fromOffset(120, 56),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 26,
		Text = "0",
		Parent = petals,
	})
	ui.streak = UiKit.label({
		Name = "Streak",
		Position = UDim2.fromOffset(170, 0),
		Size = UDim2.fromOffset(62, 56),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = UiKit.HEAVY_FONT,
		TextSize = 22,
		TextColor3 = UiKit.TRIM,
		Text = "",
		Parent = petals,
	})

	-- ThirstMeter and KillFeed (top-right)
	local right = group("TopRight", Vector2.new(1, 0), UDim2.new(1, -12, 0, 48), Vector2.new(420, 300))
	local thirst = UiKit.panel({
		Name = "ThirstMeter",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(210, 64),
		Parent = right,
	})
	local bud = UiKit.new("Frame", {
		Name = "Bud",
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = UiKit.OUTLINE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = thirst,
	})
	UiKit.corner(26).Parent = bud
	UiKit.stroke(UiKit.LACQUER, 2).Parent = bud
	ui.thirstFill = UiKit.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = UiKit.LACQUER,
		BorderSizePixel = 0,
		Parent = bud,
	})
	UiKit.label({
		Name = "Title",
		Position = UDim2.fromOffset(68, 6),
		Size = UDim2.fromOffset(134, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
		TextColor3 = UiKit.INK_DIM,
		Text = "THE THIRST",
		Parent = thirst,
	})
	ui.thirstText = UiKit.label({
		Name = "Percent",
		Position = UDim2.fromOffset(68, 26),
		Size = UDim2.fromOffset(134, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 26,
		Text = "0%",
		Parent = thirst,
	})

	local feed = UiKit.new("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 74),
		Size = UDim2.fromOffset(420, 5 * 28),
		BackgroundTransparency = 1,
		Parent = right,
	})
	local feedLayout = UiKit.list(Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Right)
	feedLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	feedLayout.Parent = feed
	ui.feed = feed

	-- ElderBar and Announcement (top-centre)
	local centre = group("TopCentre", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 44), Vector2.new(640, 200))
	local elder = UiKit.panel({
		Name = "ElderBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(640, 86),
		Visible = false,
		Parent = centre,
	})
	ui.elderName = UiKit.label({
		Name = "Title",
		Position = UDim2.fromOffset(12, 4),
		Size = UDim2.fromOffset(330, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 19,
		Text = "THE THIRSTING ELDER",
		Parent = elder,
	})
	ui.elderTime = UiKit.label({
		Name = "TimeLeft",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 4),
		Size = UDim2.fromOffset(120, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = UiKit.HEAVY_FONT,
		TextSize = 19,
		Parent = elder,
	})
	local _, elderFill, elderText =
		meter(elder, "Health", UDim2.fromOffset(12, 30), UDim2.new(1, -24, 0, 22), UiKit.LACQUER)
	ui.elderFill = elderFill
	ui.elderHealth = elderText
	ui.elderHeart = UiKit.label({
		Name = "Heart",
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -170, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = UiKit.HEAVY_FONT,
		TextSize = 17,
		RichText = true,
		Parent = elder,
	})
	ui.elderState = UiKit.label({
		Name = "State",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 56),
		Size = UDim2.fromOffset(150, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 15,
		TextColor3 = UiKit.INK_DIM,
		Parent = elder,
	})
	ui.elder = elder
	ui.announce = UiKit.label({
		Name = "Announcement",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(900, 44),
		Font = UiKit.TITLE_FONT,
		TextSize = 36,
		TextWrapped = true,
		TextTransparency = 1,
		Parent = centre,
	})
	UiKit.textStroke(UiKit.OUTLINE, 3).Parent = ui.announce
end

local function buildMiddle()
	local middle = group("Middle", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.45), Vector2.new(900, 300))
	ui.combo = UiKit.label({
		Name = "ComboCounter",
		Position = UDim2.fromOffset(700, 100),
		Size = UDim2.fromOffset(200, 50),
		Font = UiKit.TITLE_FONT,
		TextSize = 40,
		TextColor3 = UiKit.TRIM,
		TextTransparency = 1,
		Parent = middle,
	})
	UiKit.textStroke(UiKit.OUTLINE, 3).Parent = ui.combo

	local reward = UiKit.panel({
		Name = "RewardPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(450, 150),
		Size = UDim2.fromOffset(520, 170),
		Visible = false,
		Parent = middle,
	})
	ui.reward = reward
	ui.rewardLines = UiKit.label({
		Name = "Lines",
		Size = UDim2.fromScale(1, 1),
		Font = UiKit.TITLE_FONT,
		TextSize = 34,
		TextWrapped = true,
		TextColor3 = UiKit.TRIM,
		Parent = reward,
	})
	UiKit.textStroke(UiKit.OUTLINE, 3).Parent = ui.rewardLines
end

---------------------------------------------------------------------------------------------------
-- Touch controls

local function touchButton(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: number,
	color: Color3
): TextButton
	local button = UiKit.button({
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		Text = text,
		TextSize = math.floor(size * 0.24),
		TextWrapped = true,
		Parent = parent,
	})
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end
	return button
end

local function holdButton(button: TextButton, onChange: (boolean) -> ())
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			onChange(true)
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			onChange(false)
		end
	end)
end

local function buildTouch()
	local touch = group("TouchControls", Vector2.new(1, 1), UDim2.new(1, -8, 1, -8), Vector2.new(440, 470))
	touch.Visible = false
	ui.touch = touch
	-- Centre of the attack button sits above the default jump button (bottom-right).
	local cx, cy = 300, 250
	local attack = touchButton(touch, "TouchAttack", "ATTACK", UDim2.fromOffset(cx, cy), 132, UiKit.LACQUER)
	holdButton(attack, function(on)
		InputController.setM1Held(on)
	end)
	local block = touchButton(touch, "TouchBlock", "BLOCK", UDim2.fromOffset(cx - 140, cy + 30), 96, UiKit.SLOT)
	holdButton(block, function(on)
		InputController.setBlock(on)
	end)
	local dash = touchButton(touch, "TouchDash", "DASH", UDim2.fromOffset(cx + 40, cy - 130), 92, UiKit.SLOT)
	dash.Activated:Connect(function()
		InputController.dash()
	end)
	local arc: { { name: string, slot: string, dx: number, dy: number } } = {
		{ name = "TouchAbility1", slot = "Ability1", dx = -150, dy = -40 },
		{ name = "TouchAbility2", slot = "Ability2", dx = -140, dy = -150 },
		{ name = "TouchAbility3", slot = "Ability3", dx = -60, dy = -220 },
		{ name = "TouchAbility4", slot = "Ability4", dx = 50, dy = -235 },
	}
	ui.touchSlots = {}
	for _, entry in arc do
		local button = touchButton(
			touch,
			entry.name,
			KEY_HINT[entry.slot],
			UDim2.fromOffset(cx + entry.dx, cy + entry.dy),
			88,
			UiKit.PANEL_ALT
		)
		local slot = entry.slot
		button.Activated:Connect(function()
			InputController.pressSlot(slot)
		end)
		ui.touchSlots[slot] = button
	end
	local ult = touchButton(touch, "TouchUlt", "ULT", UDim2.fromOffset(cx - 10, cy - 330), 96, UiKit.PANEL_ALT)
	ult.Activated:Connect(function()
		InputController.pressSlot("Ultimate")
	end)
	ui.touchUlt = ult
	local mend = touchButton(touch, "TouchMend", "MEND", UDim2.fromOffset(cx - 250, cy - 120), 88, UiKit.SLOT)
	holdButton(mend, function(on)
		InputController.setMend(on)
	end)

	local phase = UiKit.button({
		Name = "TouchPhase",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 120),
		Size = UDim2.fromOffset(88, 88),
		Text = "PHASE",
		TextSize = 18,
		Visible = false,
		Parent = gui,
	})
	phase.Activated:Connect(function()
		SelectController.toggle()
	end)
	ui.touchPhase = phase
end

local function updateInputMode()
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	ui.touch.Visible = touch
	ui.touchPhase.Visible = touch
end

---------------------------------------------------------------------------------------------------
-- Messages

local function fadeText(label: TextLabel, text: string, color: Color3?, hold: number)
	local token = number(label:GetAttribute("FadeToken"), 0) + 1
	label:SetAttribute("FadeToken", token)
	label.Text = text
	label.TextColor3 = color or UiKit.INK_LIGHT
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	task.delay(hold, function()
		if label:GetAttribute("FadeToken") ~= token then
			return
		end
		label.TextTransparency = 1
		if stroke then
			stroke.Transparency = 1
		end
	end)
end

function HudController.toast(text: string, color: Color3?)
	fadeText(ui.toast, text, color, 2.2)
end

function HudController.announce(text: string, color: Color3?)
	fadeText(ui.announce, string.upper(text), color or UiKit.TRIM, 4.5)
	SoundController.play("bell", nil, 0.7, 1)
end

local function relationTag(killerFighter: any, victimFighter: any): (string?, Color3?)
	local killer = Fighters.get(if type(killerFighter) == "string" then killerFighter else nil)
	local victim = Fighters.get(if type(victimFighter) == "string" then victimFighter else nil)
	if not killer or not victim then
		return nil, nil
	end
	local relation = Phases.relation(killer.phase, victim.phase)
	if relation == "Neutral" then
		return nil, nil
	end
	return string.upper(relation), UiKit.RELATION[relation]
end

local function addFeedEntry(data: any)
	if type(data) ~= "table" then
		return
	end
	local victim = if type(data.victim) == "string" then data.victim else "?"
	local killer = if type(data.killer) == "string" then data.killer else nil
	local text: string
	if killer then
		text = `{killer}  ›  {victim}`
		local tag, color = relationTag(data.killerFighter, data.victimFighter)
		if tag and color then
			text ..= `  <font color="{UiKit.hex(color)}">({tag})</font>`
		end
	else
		text = `{victim} fell`
	end
	if data.ringOut == true then
		text ..= `  <font color="{UiKit.hex(UiKit.TRIM)}">RING-OUT</font>`
	end
	local line = UiKit.label({
		Name = "Entry",
		Size = UDim2.fromOffset(420, 26),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = UiKit.PANEL,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 16,
		Text = text,
		Parent = ui.feed,
	})
	UiKit.corner(6).Parent = line
	UiKit.padding(4).Parent = line
	table.insert(feedLines, 1, line)
	for index, entry in feedLines do
		entry.LayoutOrder = index
	end
	while #feedLines > 5 do
		local oldest = table.remove(feedLines)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(12, function()
		local index = table.find(feedLines, line)
		if index then
			table.remove(feedLines, index)
		end
		line:Destroy()
	end)
end

local function onNotify(kind: string, data: any)
	if kind == "toast" and type(data) == "table" and type(data.text) == "string" then
		HudController.toast(data.text)
	elseif kind == "announce" and type(data) == "table" and type(data.text) == "string" then
		HudController.announce(data.text, if typeof(data.color) == "Color3" then data.color else nil)
	elseif kind == "kill" then
		addFeedEntry(data)
	end
end

local function onHit(victim: Model?, attacker: Model?, amount: number, flags: number, _position: Vector3)
	local mine = attacker ~= nil and attacker == character()
	if not mine or victim == attacker or type(amount) ~= "number" or type(flags) ~= "number" then
		return
	end
	if amount <= 0 or bit32.btest(flags, Remotes.FLAG_BLOCKED) or bit32.btest(flags, Remotes.FLAG_HEAL) then
		return
	end
	if os.clock() - lastComboAt > 2 then
		comboCount = 0
	end
	comboCount += 1
	lastComboAt = os.clock()
	if comboCount >= 2 then
		ui.combo.Text = `{comboCount} HITS`
		ui.combo.TextTransparency = 0
		local stroke = ui.combo:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
end

local function onElder(kind: string, data: any)
	if kind ~= "fall" or type(data) ~= "table" then
		return
	end
	local earned = false
	if type(data.earned) == "table" then
		for _, name in data.earned do
			if name == localPlayer.Name then
				earned = true
			end
		end
	end
	local crowned = data.top ~= nil and data.top == localPlayer.DisplayName
	if not earned and not crowned then
		return
	end
	local lines = {}
	if earned then
		table.insert(lines, `+{Constants.ELDER_REWARD_PETALS} PETALS`)
		table.insert(lines, `ELDER'S SAP {Constants.ELDER_SAP_SECONDS}s`)
	end
	if crowned then
		table.insert(lines, "YOU WEAR THE LILY CROWN")
	end
	rewardToken += 1
	local token = rewardToken
	ui.rewardLines.Text = table.concat(lines, "\n")
	ui.reward.Visible = true
	SoundController.play("bell", nil, 1, 1.3)
	task.delay(5, function()
		if rewardToken == token then
			ui.reward.Visible = false
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Per-frame refresh

local function refreshSlots(model: Model?)
	local fighter = InputController.fighter()
	local ki = InputController.ki()
	local ready = ki >= Constants.KI_MAX
	for _, slot in SLOTS do
		local view = slotViews[slot]
		local remaining, total: number
		if slot == "M1" then
			remaining, total = 0, 1
			view.icon.Text = if fighter then Phases.INFO[fighter.phase].glyph else "—"
			view.icon.TextColor3 = if fighter then Phases.color(fighter.phase, true) else UiKit.INK_DIM
			view.name.Text = "Strike"
			local index = InputController.comboIndex()
			for pipIndex, pip in view.pips do
				pip.BackgroundColor3 = if pipIndex <= index then UiKit.TRIM else UiKit.SLOT
			end
		else
			remaining, total = InputController.cooldown(slot)
			local move = if fighter then Fighters.moveForSlot(fighter, slot) else nil
			view.name.Text = if move then move.name else ""
			local initials = ""
			if move then
				for word in string.gmatch(move.name, "%a+") do
					if #initials < 2 and string.lower(word) ~= "of" and string.lower(word) ~= "the" then
						initials ..= string.sub(word, 1, 1)
					end
				end
			end
			view.icon.Text = string.upper(initials)
			view.icon.TextColor3 = if fighter then Phases.color(fighter.phase, true) else UiKit.INK_DIM
		end
		local silenced = slot ~= "M1" and model ~= nil and model:GetAttribute("Silenced") == true
		local locked = slot == "Ultimate" and not ready
		view.sweep.Size = UDim2.fromScale(1, if remaining > 0 then math.clamp(remaining / total, 0, 1) else 0)
		view.seconds.Text = if remaining > 0 then string.format("%.1f", remaining) else ""
		view.frame.BackgroundTransparency = if silenced or locked then 0.45 else 0.08
		local stroke = view.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			if slot == "Ultimate" and ready and remaining <= 0 then
				stroke.Color = UiKit.TRIM
				stroke.Thickness = 3 + math.sin(pulse * 6) * 1.5
			else
				stroke.Color = if silenced then UiKit.LACQUER else UiKit.OUTLINE
				stroke.Thickness = 3
			end
		end
	end
	if ui.touchUlt then
		ui.touchUlt.BackgroundColor3 = if ready then UiKit.TRIM else UiKit.PANEL_ALT
		ui.touchUlt.Text = if ready then "ULT!" else "ULT"
	end
end

local function refreshVitals(model: Model?)
	local humanoid = humanoidOf(model)
	local health = if humanoid then humanoid.Health else 0
	local maxHealth = if humanoid then math.max(humanoid.MaxHealth, 1) else 100
	setFill(ui.healthFill, health / maxHealth)
	ui.healthText.Text = `{math.ceil(health)} / {math.floor(maxHealth)}`

	local ki = InputController.ki()
	setFill(ui.kiFill, ki / Constants.KI_MAX)
	local ready = ki >= Constants.KI_MAX
	ui.kiText.Text = if ready then "G READY" else `KI  {math.floor(ki)}`
	ui.kiGlow.Transparency = if ready then 0.2 + math.abs(math.sin(pulse * 4)) * 0.6 else 1

	local guard = number(attribute(model, "Guard"), Constants.GUARD_MAX)
	local blocking = attribute(model, "Blocking") == true
	local mending = attribute(model, "Mending") == true
	setFill(ui.guardFill, guard / Constants.GUARD_MAX)
	ui.guardFrame.Visible = not mending and (blocking or guard < Constants.GUARD_MAX)
	ui.mendFrame.Visible = mending
	if mending then
		setFill(ui.mendFill, 0.5 + math.sin(pulse * 5) * 0.5)
	end

	local fighter = InputController.fighter()
	if fighter then
		local info = Phases.INFO[fighter.phase]
		ui.badgeGlyph.Text = info.glyph
		ui.badgeGlyph.TextColor3 = Phases.color(fighter.phase, true)
		ui.badgePhase.Text = string.upper(fighter.phase)
		ui.badgePhase.TextColor3 = Phases.color(fighter.phase, true)
		ui.badgeFighter.Text = fighter.displayName
	end

	local shown = 0
	for _, spec in STATUS_CHIPS do
		local value = attribute(model, spec.attribute)
		local active = value == true or (type(value) == "number" and value > 0)
		local chip = ui.chips[spec.attribute] :: TextLabel
		chip.Visible = active and shown < 6
		if chip.Visible then
			shown += 1
			chip.Text = if type(value) == "number" then `{spec.label} ×{value}` else spec.label
		end
	end
	-- Fighter passives shown as chips: Rokumon's coins and Hibiki's rhythm.
	local coinsValue = attribute(model, "Coins")
	local rhythm = attribute(model, "Rhythm")
	local beat = attribute(model, "BeatReady") == true
	local extra = ui.passiveChip :: TextLabel?
	if extra then
		if type(coinsValue) == "number" then
			extra.Visible = true
			extra.Text = `COINS {coinsValue}/{Constants.ROKUMON_MAX_COINS}`
			extra.TextColor3 = UiKit.TRIM
		elseif type(rhythm) == "number" then
			extra.Visible = true
			extra.Text = if beat then "BEAT READY" else `RHYTHM {rhythm}/{Constants.HIBIKI_BEAT_EVERY}`
			extra.TextColor3 = if beat then UiKit.KI else UiKit.INK_LIGHT
		else
			extra.Visible = false
		end
	end
end

local function refreshWorld()
	local petals = localPlayer:FindFirstChild("leaderstats")
	local petalValue = if petals then petals:FindFirstChild("Petals") else nil
	ui.petals.Text = if petalValue and petalValue:IsA("IntValue") then commas(petalValue.Value) else "0"
	local streak = number(localPlayer:GetAttribute("Streak"), 0)
	ui.streak.Text = if streak >= 2 then `x{streak}` else ""

	local awake = Workspace:GetAttribute("ElderAwake") == true
	local thirst = number(Workspace:GetAttribute("Thirst"), 0)
	local thirstMax = math.max(number(Workspace:GetAttribute("ThirstMax"), Constants.THIRST_BASE), 1)
	local fraction = if awake then 1 else math.clamp(thirst / thirstMax, 0, 1)
	ui.thirstFill.Size = UDim2.fromScale(1, fraction)
	ui.thirstText.Text = if awake then "AWAKE" else `{math.floor(fraction * 100)}%`

	ui.elder.Visible = awake
	if awake then
		local health = number(Workspace:GetAttribute("ElderHealth"), 0)
		local maxHealth = math.max(number(Workspace:GetAttribute("ElderMaxHealth"), 1), 1)
		setFill(ui.elderFill, health / maxHealth)
		ui.elderHealth.Text = `{commas(math.ceil(health))} / {commas(maxHealth)}`
		local heart = Workspace:GetAttribute("ElderHeart")
		local nextHeart = Workspace:GetAttribute("ElderNextHeart")
		local heartAt = number(Workspace:GetAttribute("ElderHeartAt"), 0)
		local endsAt = number(Workspace:GetAttribute("ElderEndsAt"), 0)
		if type(heart) == "string" and Phases.INFO[heart] then
			local wound = Phases.overcomerOf(heart)
			local heartHex = UiKit.hex(Phases.color(heart, true))
			local woundHex = if wound then UiKit.hex(Phases.color(wound, true)) else "#FFFFFF"
			local nextText = if type(nextHeart) == "string"
				then `   next {string.upper(nextHeart)} in {math.max(0, math.ceil(heartAt - now()))}s`
				else ""
			ui.elderHeart.Text =
				`Heart: <font color="{heartHex}">{Phases.INFO[heart].glyph} {string.upper(heart)}</font>  |  Wound it with <font color="{woundHex}">{string.upper(
					wound or "?"
				)}</font>{nextText}`
		end
		ui.elderTime.Text = clock(endsAt - now())
		local wounded = Workspace:GetAttribute("ElderWounded") == true
		local enraged = Workspace:GetAttribute("ElderEnraged") == true
		ui.elderState.Text = (if wounded then "WOUNDED" else "REGENERATING")
			.. (if enraged then "  ·  ENRAGED" else "")
		ui.elderState.TextColor3 = if wounded then UiKit.TRIM else UiKit.INK_DIM
	end
end

local function step(dt: number)
	pulse += dt
	local model = character()
	refreshSlots(model)
	refreshVitals(model)
	refreshWorld()
	if comboCount > 0 and os.clock() - lastComboAt > 2 then
		comboCount = 0
		ui.combo.TextTransparency = 1
		local stroke = ui.combo:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
end

function HudController.init(_self: any)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	gui = UiKit.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
		Parent = playerGui,
	})
	buildBottom()
	buildTop()
	buildMiddle()
	buildTouch()
	-- One chip for the fighter's own passive counter, appended to the status row.
	local passive = UiKit.label({
		Name = "Passive",
		LayoutOrder = 100,
		Size = UDim2.fromOffset(110, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = UiKit.PANEL,
		Font = UiKit.HEAVY_FONT,
		TextSize = 14,
		Visible = false,
		Parent = (ui.chips.Stunned :: TextLabel).Parent,
	})
	UiKit.corner(6).Parent = passive
	UiKit.stroke(UiKit.TRIM, 2).Parent = passive
	UiKit.padding(4).Parent = passive
	ui.passiveChip = passive
end

function HudController.start(_self: any)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	Remotes.Notify.OnClientEvent:Connect(onNotify)
	Remotes.HitFx.OnClientEvent:Connect(onHit)
	Remotes.ElderFx.OnClientEvent:Connect(onElder)
	InputController.onNotice(function(text)
		HudController.toast(text, UiKit.LACQUER)
	end)
	updateInputMode()
	UserInputService.LastInputTypeChanged:Connect(updateInputMode)
	RunService.RenderStepped:Connect(step)
end

return HudController
