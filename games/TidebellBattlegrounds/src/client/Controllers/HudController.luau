--!strict
-- The HUD: health / resonance / guard meters, ability bar with cooldowns, status chips, champion
-- badge, kill feed, announcements, Tide Warden health bar, combo counter, callouts, damage numbers
-- and on-screen touch controls.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Elements = require(ReplicatedStorage.Shared.Elements)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Effects = require("../Lib/Effects")
local Remotes = require("../Lib/Remotes")
local UiKit = require("../Lib/UiKit")
local InputController = require("./InputController")
local SelectController = require("./SelectController")

local HudController = {}

local localPlayer = Players.LocalPlayer

local SLOT_ORDER = { "Ability1", "Ability2", "Ability3", "Ability4", "Ultimate" }
local SLOT_KEYS: { [string]: string } =
	{ Ability1 = "1", Ability2 = "2", Ability3 = "3", Ability4 = "4", Ultimate = "G" }
local STATUS_CHIPS = {
	{ attribute = "Stunned", text = "STUNNED", color = Color3.fromRGB(255, 196, 70) },
	{ attribute = "Silenced", text = "SILENCED", color = Color3.fromRGB(170, 130, 255) },
	{ attribute = "Slowed", text = "SLOWED", color = Color3.fromRGB(120, 210, 255) },
	{ attribute = "Burning", text = "BURNING", color = Color3.fromRGB(255, 120, 60) },
	{ attribute = "Armored", text = "STONE SKIN", color = Color3.fromRGB(214, 160, 90) },
	{ attribute = "Warding", text = "WARD", color = Color3.fromRGB(190, 160, 255) },
	{ attribute = "Blessed", text = "TIDE-BLESSED", color = UiKit.TEAL },
	{ attribute = "Safe", text = "SAFE ZONE", color = Color3.fromRGB(150, 255, 170) },
}

type Slot = {
	button: TextButton,
	name: TextLabel,
	key: TextLabel,
	shade: Frame,
	timer: TextLabel,
	stroke: UIStroke,
}

local screen: ScreenGui
local healthFill: Frame
local healthText: TextLabel
local resonanceFill: Frame
local resonanceText: TextLabel
local guardBar: Frame
local guardFill: Frame
local slots: { [string]: Slot } = {}
local chips: { [string]: TextLabel } = {}
local badgeGlyph: TextLabel
local badgeName: TextLabel
local badgeTitle: TextLabel
local feed: Frame
local banner: TextLabel
local bossFrame: Frame
local bossFill: Frame
local bossText: TextLabel
local comboFrame: Frame
local comboCount: TextLabel
local callout: TextLabel
local toast: TextLabel
local touchFrame: Frame
local hint: TextLabel

local shownFighterId: string? = nil
local combo = 0
local lastComboHit = 0
local bossModel: Model? = nil
local feedOrder = 0

local function hex(color: Color3): string
	return color:ToHex()
end

local function fighterColor(id: unknown): Color3
	local fighter = Fighters.get(if type(id) == "string" then id else nil)
	return if fighter then UiKit.color(fighter.color) else UiKit.PAPER
end

---------------------------------------------------------------------------------------------------
-- Build

local function meter(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): (Frame, Frame)
	local back = UiKit.new("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = UiKit.INK,
		BackgroundTransparency = 0.15,
		Parent = parent,
	}, { UiKit.corner(6), UiKit.stroke(Color3.new(0, 0, 0), 1.5, 0.3) })
	local fill = UiKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Parent = back,
	}, { UiKit.corner(6), UiKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) })
	return back, fill
end

local function buildBottom()
	local panel = UiKit.new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(0.46, 0, 0, 152),
		BackgroundTransparency = 1,
		Parent = screen,
	}, { UiKit.new("UISizeConstraint", { MinSize = Vector2.new(330, 152), MaxSize = Vector2.new(720, 152) }) })

	local statusRow = UiKit.new("Frame", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UiKit.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Left) })
	for index, chip in STATUS_CHIPS do
		chips[chip.attribute] = UiKit.new("TextLabel", {
			Name = chip.attribute,
			LayoutOrder = index,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			BackgroundColor3 = UiKit.INK,
			BackgroundTransparency = 0.1,
			Text = chip.text,
			Font = UiKit.HEAVY_FONT,
			TextSize = 13,
			TextColor3 = chip.color,
			Visible = false,
			Parent = statusRow,
		}, { UiKit.corner(5), UiKit.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
	end

	local healthBack
	healthBack, healthFill =
		meter(panel, "Health", UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 24), Color3.fromRGB(110, 220, 120))
	healthText = UiKit.label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = UiKit.HEAVY_FONT,
		TextSize = 16,
		Parent = healthBack,
		ZIndex = 2,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 1.5).Parent = healthText

	local resonanceBack
	resonanceBack, resonanceFill =
		meter(panel, "Resonance", UDim2.fromOffset(0, 54), UDim2.new(1, 0, 0, 10), UiKit.GOLD)
	resonanceText = UiKit.label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(220, 14),
		Text = "",
		TextSize = 12,
		Font = UiKit.HEAVY_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
		Parent = resonanceBack,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 1.2).Parent = resonanceText

	guardBar, guardFill =
		meter(panel, "Guard", UDim2.fromOffset(0, 67), UDim2.new(1, 0, 0, 6), Color3.fromRGB(150, 210, 255))
	guardBar.Visible = false

	local row = UiKit.new("Frame", {
		Name = "Abilities",
		Position = UDim2.fromOffset(0, 78),
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UiKit.list(Enum.FillDirection.Horizontal, 6) })
	for index, slotName in SLOT_ORDER do
		local stroke = UiKit.stroke(Color3.fromRGB(70, 70, 82), 1.5)
		local button = UiKit.new("TextButton", {
			Name = slotName,
			LayoutOrder = index,
			Size = UDim2.new(0.2, -5, 1, 0),
			BackgroundColor3 = UiKit.INK,
			BackgroundTransparency = 0.1,
			Text = "",
			AutoButtonColor = true,
			Parent = row,
		}, { UiKit.corner(10), stroke })
		local key = UiKit.label({
			Position = UDim2.fromOffset(6, 4),
			Size = UDim2.fromOffset(22, 18),
			Text = SLOT_KEYS[slotName],
			Font = UiKit.HEAVY_FONT,
			TextSize = 15,
			TextColor3 = UiKit.GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})
		local name = UiKit.label({
			Position = UDim2.fromOffset(6, 22),
			Size = UDim2.new(1, -12, 1, -26),
			Text = "",
			TextScaled = true,
			TextWrapped = true,
			Font = UiKit.HEAVY_FONT,
			Parent = button,
		})
		UiKit.new("UITextSizeConstraint", { MaxTextSize = 16, Parent = name })
		local shade = UiKit.new("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			ZIndex = 3,
			Parent = button,
		}, { UiKit.corner(10) })
		local timer = UiKit.label({
			Size = UDim2.fromScale(1, 1),
			Text = "",
			Font = UiKit.TITLE_FONT,
			TextSize = 26,
			ZIndex = 4,
			Parent = button,
		})
		button.Activated:Connect(function()
			InputController.pressSlot(slotName)
		end)
		slots[slotName] = { button = button, name = name, key = key, shade = shade, timer = timer, stroke = stroke }
	end
end

local function buildTop()
	local badge = UiKit.new("TextButton", {
		Name = "Champion",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(270, 62),
		BackgroundColor3 = UiKit.INK,
		BackgroundTransparency = 0.12,
		Text = "",
		Parent = screen,
	}, { UiKit.corner(12), UiKit.stroke(Color3.fromRGB(70, 70, 82), 1.5) })
	badge.Activated:Connect(function()
		SelectController.open()
	end)
	badgeGlyph = UiKit.new("TextLabel", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = UiKit.GOLD,
		Text = "",
		Font = UiKit.HEAVY_FONT,
		TextSize = 30,
		TextColor3 = UiKit.INK,
		Parent = badge,
	}, { UiKit.corner(23) })
	badgeName = UiKit.label({
		Position = UDim2.fromOffset(62, 6),
		Size = UDim2.new(1, -70, 0, 26),
		Text = "",
		Font = UiKit.TITLE_FONT,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = badge,
	})
	badgeTitle = UiKit.label({
		Position = UDim2.fromOffset(62, 34),
		Size = UDim2.new(1, -70, 0, 18),
		Text = "",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(196, 190, 178),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = badge,
	})

	feed = UiKit.new("Frame", {
		Name = "KillFeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(340, 170),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		UiKit.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})

	banner = UiKit.label({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.56, 0, 0, 40),
		Text = "",
		Font = UiKit.TITLE_FONT,
		TextScaled = true,
		TextTransparency = 1,
		Parent = screen,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 2).Parent = banner

	bossFrame = UiKit.new("Frame", {
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.new(0.42, 0, 0, 40),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, { UiKit.new("UISizeConstraint", { MinSize = Vector2.new(280, 40) }) })
	bossText = UiKit.label({
		Size = UDim2.new(1, 0, 0, 18),
		Text = "水  THE TIDE WARDEN",
		Font = UiKit.TITLE_FONT,
		TextSize = 20,
		TextColor3 = UiKit.TEAL,
		Parent = bossFrame,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 1.5).Parent = bossText
	local _bossBack
	_bossBack, bossFill = meter(bossFrame, "Health", UDim2.fromOffset(0, 20), UDim2.new(1, 0, 0, 14), UiKit.TEAL)
end

local function buildMiddle()
	comboFrame = UiKit.new("Frame", {
		Name = "Combo",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.45, 0),
		Size = UDim2.fromOffset(170, 96),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	comboCount = UiKit.label({
		Size = UDim2.new(1, 0, 0, 70),
		Text = "",
		Font = UiKit.TITLE_FONT,
		TextSize = 64,
		TextColor3 = UiKit.GOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = comboFrame,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 3).Parent = comboCount
	local comboLabel = UiKit.label({
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "HIT COMBO",
		Font = UiKit.TITLE_FONT,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = comboFrame,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 2).Parent = comboLabel

	callout = UiKit.label({
		Name = "Callout",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.new(0.6, 0, 0, 64),
		Text = "",
		Font = UiKit.TITLE_FONT,
		TextScaled = true,
		TextTransparency = 1,
		Parent = screen,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 3).Parent = callout

	toast = UiKit.label({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -172),
		Size = UDim2.new(0.6, 0, 0, 26),
		Text = "",
		Font = UiKit.HEAVY_FONT,
		TextSize = 18,
		TextTransparency = 1,
		Parent = screen,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 1.5).Parent = toast

	hint = UiKit.label({
		Name = "Controls",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -10),
		Size = UDim2.fromOffset(330, 40),
		Text = "LMB attack (hold to chain) · F block · Q dash\n1-4 abilities · G ultimate · T champions",
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.25,
		Parent = screen,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 1).Parent = hint
end

local function touchButton(name: string, text: string, position: UDim2, size: number, color: Color3): TextButton
	return UiKit.new("TextButton", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.2,
		Text = text,
		Font = UiKit.TITLE_FONT,
		TextSize = math.floor(size * 0.24),
		TextColor3 = UiKit.INK,
		Parent = touchFrame,
	}, { UiKit.corner(math.floor(size / 2)), UiKit.stroke(Color3.new(0, 0, 0), 2, 0.3) })
end

local function buildTouch()
	touchFrame = UiKit.new("Frame", {
		Name = "Touch",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	})
	local attack = touchButton("Attack", "ATTACK", UDim2.new(1, -190, 1, -170), 96, UiKit.GOLD)
	local block = touchButton("Block", "BLOCK", UDim2.new(1, -300, 1, -110), 72, Color3.fromRGB(150, 210, 255))
	local dash = touchButton("Dash", "DASH", UDim2.new(1, -205, 1, -285), 72, Color3.fromRGB(200, 255, 210))

	attack.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.setM1Held(true)
		end
	end)
	attack.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.setM1Held(false)
		end
	end)
	block.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.setBlock(true)
		end
	end)
	block.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			InputController.setBlock(false)
		end
	end)
	dash.Activated:Connect(function()
		InputController.dash()
	end)
end

---------------------------------------------------------------------------------------------------
-- Messages

local function fadeText(label: TextLabel, text: string, color: Color3?, hold: number)
	label.Text = text
	if color then
		label.TextColor3 = color
	end
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local previous = label:GetAttribute("FadeToken")
	local token = (if type(previous) == "number" then previous else 0) + 1
	label:SetAttribute("FadeToken", token)
	task.delay(hold, function()
		if label:GetAttribute("FadeToken") ~= token then
			return
		end
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
	end)
end

local function showCallout(text: string, color: Color3)
	fadeText(callout, text, color, 0.6)
	local scale = callout:FindFirstChildOfClass("UIScale") or UiKit.new("UIScale", { Parent = callout })
	scale.Scale = 1.35
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
end

function HudController.toast(text: string)
	fadeText(toast, text, UiKit.PAPER, 2.5)
end

local function addFeedEntry(richText: string)
	feedOrder -= 1
	local entry = UiKit.label({
		LayoutOrder = feedOrder,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = UiKit.INK,
		BackgroundTransparency = 0.25,
		RichText = true,
		Text = richText,
		TextSize = 15,
		Font = UiKit.HEAVY_FONT,
		Parent = feed,
	})
	UiKit.corner(6).Parent = entry
	UiKit.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = entry })
	local entries: { TextLabel } = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(entries, child)
		end
	end
	table.sort(entries, function(a: TextLabel, b: TextLabel): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 6, #entries do
		entries[index]:Destroy()
	end
	task.delay(9, function()
		if entry.Parent then
			TweenService:Create(entry, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.delay(0.65, function()
				entry:Destroy()
			end)
		end
	end)
end

local function onNotify(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "announce" and type(data.text) == "string" then
		fadeText(banner, data.text, if typeof(data.color) == "Color3" then data.color else UiKit.GOLD, 3.5)
	elseif kind == "toast" and type(data.text) == "string" then
		HudController.toast(data.text)
	elseif kind == "kill" then
		local victim = tostring(data.victim or "?")
		local victimColor = hex(fighterColor(data.victimFighter))
		if data.killer then
			local killerColor = if data.killerFighter then hex(fighterColor(data.killerFighter)) else hex(UiKit.TEAL)
			addFeedEntry(
				`<font color="#{killerColor}">{tostring(data.killer)}</font>  ⚔  <font color="#{victimColor}">{victim}</font>`
			)
			if data.killer == localPlayer.DisplayName then
				showCallout("KNOCKOUT!", UiKit.GOLD)
			end
		else
			addFeedEntry(`<font color="#{victimColor}">{victim}</font> was claimed by the sea`)
		end
	end
end

local function damageNumber(position: Vector3, text: string, color: Color3, big: boolean)
	local anchor = Effects.part({
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(position + Vector3.new(math.random() * 2 - 1, 1.5, math.random() * 2 - 1)),
		Transparency = 1,
	})
	local billboard = UiKit.new("BillboardGui", {
		Size = UDim2.fromOffset(if big then 140 else 100, if big then 56 else 40),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 120,
		Parent = anchor,
	})
	local label = UiKit.label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = UiKit.TITLE_FONT,
		TextScaled = true,
		TextColor3 = color,
		Parent = billboard,
	})
	UiKit.textStroke(Color3.new(0, 0, 0), 2).Parent = label
	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 3, 0),
	}):Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
	end)
	Effects.clean(anchor, 0.85)
end

local function onHit(victim: Model?, attacker: Model?, amount: number, flags: number, position: Vector3)
	if typeof(position) ~= "Vector3" or type(amount) ~= "number" or type(flags) ~= "number" then
		return
	end
	local character = localPlayer.Character
	local mine = attacker ~= nil and attacker == character
	local onMe = victim ~= nil and victim == character

	if bit32.btest(flags, Remotes.FLAG_PARRIED) then
		if onMe then
			showCallout("PARRY!", Color3.fromRGB(150, 210, 255))
		elseif mine then
			showCallout("PARRIED", Color3.fromRGB(255, 120, 100))
		end
		return
	end
	if bit32.btest(flags, Remotes.FLAG_GUARD_BREAK) and (mine or onMe) then
		showCallout("GUARD BREAK!", Color3.fromRGB(150, 210, 255))
	end
	if bit32.btest(flags, Remotes.FLAG_COUNTER) and (mine or onMe) then
		showCallout("COUNTER!", Color3.fromRGB(200, 170, 255))
	end

	local blocked = bit32.btest(flags, Remotes.FLAG_BLOCKED)
	if amount > 0 and (mine or onMe or (victim ~= nil and victim:HasTag("Npc"))) then
		local text = tostring(math.floor(amount * 10 + 0.5) / 10)
		local color = Color3.new(1, 1, 1)
		if blocked then
			color = Color3.fromRGB(150, 210, 255)
		elseif onMe then
			color = Color3.fromRGB(255, 96, 86)
		elseif bit32.btest(flags, Remotes.FLAG_ADVANTAGE) then
			text ..= "!"
			color = Color3.fromRGB(255, 170, 60)
		elseif bit32.btest(flags, Remotes.FLAG_DISADVANTAGE) then
			color = Color3.fromRGB(170, 170, 170)
		elseif mine then
			color = UiKit.GOLD
		end
		if bit32.btest(flags, Remotes.FLAG_BURN) then
			color = Color3.fromRGB(255, 140, 70)
		end
		damageNumber(position, text, color, amount >= 10)
	end

	if mine and not blocked and amount > 0 and not bit32.btest(flags, Remotes.FLAG_BURN) then
		local t = os.clock()
		combo = if t - lastComboHit < 1.6 then combo + 1 else 1
		lastComboHit = t
		if combo >= 2 then
			comboFrame.Visible = true
			comboCount.Text = `x{combo}`
			local scale = comboCount:FindFirstChildOfClass("UIScale") or UiKit.new("UIScale", { Parent = comboCount })
			scale.Scale = 1.3
			TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 1 }):Play()
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Per-frame refresh

local function refreshFighter()
	local fighter = InputController.fighter()
	local id = if fighter then fighter.id else nil
	if id == shownFighterId then
		return
	end
	shownFighterId = id
	if not fighter then
		return
	end
	local tint = UiKit.color(fighter.color)
	local info = Elements.INFO[fighter.element]
	badgeGlyph.Text = info.glyph
	badgeGlyph.BackgroundColor3 = tint
	badgeName.Text = string.upper(fighter.displayName)
	badgeName.TextColor3 = tint
	badgeTitle.Text = `{fighter.element} {fighter.role} · tap or T to change`
	healthFill.BackgroundColor3 = tint
	for _, slotName in SLOT_ORDER do
		local slot = slots[slotName]
		local move = Fighters.moveForSlot(fighter, slotName)
		slot.name.Text = if move then move.name else ""
	end
end

local function refresh()
	refreshFighter()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		healthFill.Size = UDim2.fromScale(fraction, 1)
		healthText.Text = `{math.ceil(humanoid.Health)} / {math.floor(humanoid.MaxHealth)}`
	end

	local resonance = localPlayer:GetAttribute("Resonance")
	local resonanceValue = if type(resonance) == "number" then resonance else 0
	local full = resonanceValue >= Constants.RESONANCE_MAX
	resonanceFill.Size = UDim2.fromScale(math.clamp(resonanceValue / Constants.RESONANCE_MAX, 0, 1), 1)
	resonanceText.Text = if full then "ULTIMATE READY — G" else `RESONANCE {math.floor(resonanceValue)}%`

	local guard = if character then character:GetAttribute("Guard") else nil
	local blocking = character ~= nil and character:GetAttribute("Blocking") == true
	local guardValue = if type(guard) == "number" then guard else Constants.GUARD_MAX
	guardBar.Visible = blocking or guardValue < Constants.GUARD_MAX
	guardFill.Size = UDim2.fromScale(math.clamp(guardValue / Constants.GUARD_MAX, 0, 1), 1)

	for _, slotName in SLOT_ORDER do
		local slot = slots[slotName]
		if slotName == "Ultimate" then
			slot.shade.Size = UDim2.fromScale(1, 1 - math.clamp(resonanceValue / Constants.RESONANCE_MAX, 0, 1))
			slot.timer.Text = ""
			slot.stroke.Color = if full then UiKit.GOLD else Color3.fromRGB(70, 70, 82)
			slot.stroke.Thickness = if full then 3 else 1.5
		else
			local remaining, total = InputController.cooldown(slotName)
			slot.shade.Size = UDim2.fromScale(1, if remaining > 0 then math.clamp(remaining / total, 0, 1) else 0)
			slot.timer.Text = if remaining > 0 then string.format("%.1f", remaining) else ""
		end
	end

	for attribute, chip in chips do
		chip.Visible = character ~= nil and character:GetAttribute(attribute) == true
	end

	if comboFrame.Visible and os.clock() - lastComboHit > 1.6 then
		comboFrame.Visible = false
		combo = 0
	end

	local boss = bossModel
	if boss and boss.Parent then
		local bossHumanoid = boss:FindFirstChildOfClass("Humanoid")
		if bossHumanoid and bossHumanoid.Health > 0 then
			bossFrame.Visible = true
			bossFill.Size =
				UDim2.fromScale(math.clamp(bossHumanoid.Health / math.max(bossHumanoid.MaxHealth, 1), 0, 1), 1)
			bossText.Text = `水  THE TIDE WARDEN  ·  {math.ceil(bossHumanoid.Health)}`
		else
			bossFrame.Visible = false
		end
	else
		bossFrame.Visible = false
	end
end

local function updateInputMode()
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	touchFrame.Visible = touch
	hint.Visible = not touch
	for slotName, slot in slots do
		slot.key.Text = if touch then "" else SLOT_KEYS[slotName]
	end
end

function HudController.init(_self: any)
	screen = UiKit.new("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	buildBottom()
	buildTop()
	buildMiddle()
	buildTouch()
	screen.Parent = localPlayer:WaitForChild("PlayerGui")
end

function HudController.start(_self: any)
	Remotes.Notify.OnClientEvent:Connect(onNotify)
	Remotes.HitFx.OnClientEvent:Connect(onHit)
	InputController.onNotice(function(text)
		showCallout(text, Color3.fromRGB(200, 170, 255))
	end)
	for _, model in CollectionService:GetTagged("TideWarden") do
		if model:IsA("Model") then
			bossModel = model
		end
	end
	CollectionService:GetInstanceAddedSignal("TideWarden"):Connect(function(model)
		if model:IsA("Model") then
			bossModel = model
		end
	end)
	SelectController.onToggled(function(open)
		screen.Enabled = not open
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(updateInputMode)
	updateInputMode()
	RunService.RenderStepped:Connect(refresh)
end

return HudController
