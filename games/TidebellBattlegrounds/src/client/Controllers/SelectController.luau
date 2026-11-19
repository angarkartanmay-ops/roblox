--!strict
-- Champion select: five cards, the chosen champion's moves, the element wheel, and a FIGHT button.
-- Opens on first spawn, with T / D-pad down, or at the Altar of the Five Schools.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Elements = require(ReplicatedStorage.Shared.Elements)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require("../Lib/Remotes")
local UiKit = require("../Lib/UiKit")
local SoundController = require("./SoundController")

type FighterSpec = Types.FighterSpec

local SelectController = {}

local localPlayer = Players.LocalPlayer
local KEY_LABEL: { [string]: string } = {
	Ability1 = "1",
	Ability2 = "2",
	Ability3 = "3",
	Ability4 = "4",
	Ultimate = "G",
}

local screen: ScreenGui
local cards: { [string]: TextButton } = {}
local detailName: TextLabel
local detailTitle: TextLabel
local detailBlurb: TextLabel
local detailMoves: Frame
local detailHeader: Frame
local fightButton: TextButton
local selectedId = Fighters.DEFAULT_ID
local openListeners: { (boolean) -> () } = {}

local function color(rgb: { number }): Color3
	return UiKit.color(rgb)
end

local function stars(count: number): string
	return string.rep("★", count) .. string.rep("☆", 3 - count)
end

local function refreshDetails()
	local fighter = Fighters.getOrDefault(selectedId)
	local tint = color(fighter.color)
	local info = Elements.INFO[fighter.element]
	detailHeader.BackgroundColor3 = tint
	detailName.Text = `{info.glyph}  {string.upper(fighter.displayName)}`
	detailTitle.Text = `{fighter.title}  ·  {fighter.element} {fighter.role}  ·  {stars(fighter.difficulty)}`
	detailBlurb.Text = fighter.blurb
	fightButton.Text = `FIGHT AS {string.upper(fighter.displayName)}`

	for _, child in detailMoves:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, move in fighter.moves do
		local row = UiKit.new("Frame", {
			Name = move.id,
			LayoutOrder = index,
			Size = UDim2.new(0.5, -6, 0, 54),
			BackgroundColor3 = UiKit.INK_SOFT,
			BackgroundTransparency = 0.1,
			Parent = detailMoves,
		}, { UiKit.corner(8) })
		UiKit.new("TextLabel", {
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.fromOffset(8, 10),
			BackgroundColor3 = if move.slot == "Ultimate" then UiKit.GOLD else tint,
			Text = KEY_LABEL[move.slot] or "?",
			Font = UiKit.HEAVY_FONT,
			TextSize = 20,
			TextColor3 = UiKit.INK,
			Parent = row,
		}, { UiKit.corner(8) })
		UiKit.label({
			Size = UDim2.new(1, -54, 0, 20),
			Position = UDim2.fromOffset(50, 5),
			Text = move.name,
			Font = UiKit.HEAVY_FONT,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		UiKit.label({
			Size = UDim2.new(1, -56, 0, 28),
			Position = UDim2.fromOffset(50, 24),
			Text = move.description,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(205, 200, 190),
			Parent = row,
		})
	end

	for id, card in cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if id == selectedId then UiKit.GOLD else Color3.fromRGB(60, 60, 70)
			stroke.Thickness = if id == selectedId then 3 else 1.5
		end
	end
end

local function buildCard(parent: Instance, fighter: FighterSpec, order: number): TextButton
	local tint = color(fighter.color)
	local info = Elements.INFO[fighter.element]
	local card = UiKit.new("TextButton", {
		Name = fighter.id,
		LayoutOrder = order,
		Size = UDim2.fromScale(0.19, 1),
		BackgroundColor3 = UiKit.INK,
		BackgroundTransparency = 0.05,
		AutoButtonColor = true,
		Text = "",
		Selectable = true,
		Parent = parent,
	}, {
		UiKit.corner(12),
		UiKit.stroke(Color3.fromRGB(60, 60, 70), 1.5),
	})
	local header = UiKit.new("Frame", {
		Size = UDim2.fromScale(1, 0.42),
		BackgroundColor3 = tint,
		Parent = card,
	}, { UiKit.corner(12), UiKit.gradient(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)) })
	UiKit.label({
		Size = UDim2.fromScale(1, 1),
		Text = info.glyph,
		Font = UiKit.HEAVY_FONT,
		TextScaled = true,
		TextColor3 = UiKit.INK,
		Parent = header,
	})
	UiKit.label({
		Position = UDim2.fromScale(0.05, 0.45),
		Size = UDim2.fromScale(0.9, 0.18),
		Text = string.upper(fighter.displayName),
		Font = UiKit.TITLE_FONT,
		TextScaled = true,
		TextColor3 = tint,
		Parent = card,
	})
	UiKit.label({
		Position = UDim2.fromScale(0.05, 0.64),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = `{fighter.element} · {fighter.role}`,
		TextScaled = true,
		Parent = card,
	})
	UiKit.label({
		Position = UDim2.fromScale(0.05, 0.78),
		Size = UDim2.fromScale(0.9, 0.12),
		Text = stars(fighter.difficulty),
		TextScaled = true,
		TextColor3 = UiKit.GOLD,
		Parent = card,
	})
	card.Activated:Connect(function()
		selectedId = fighter.id
		SoundController.play("ui")
		refreshDetails()
	end)
	return card
end

local function wheelText(): string
	local parts = {}
	for _, element in Elements.ORDER do
		local beats = Elements.beatsList(element)
		table.insert(parts, `{Elements.INFO[element].glyph} {element} ▸ {table.concat(beats, ", ")}`)
	end
	return "ELEMENT WHEEL   " .. table.concat(parts, "     ")
end

local function build()
	screen = UiKit.new("ScreenGui", {
		Name = "ChampionSelect",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})

	local backdrop = UiKit.new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 8, 14),
		BackgroundTransparency = 0.25,
		Parent = screen,
	})
	local panel = UiKit.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.94),
		BackgroundTransparency = 1,
		Parent = backdrop,
	}, { UiKit.new("UISizeConstraint", { MaxSize = Vector2.new(1180, 760) }) })

	UiKit.label({
		Name = "Title",
		Size = UDim2.fromScale(1, 0.08),
		Text = "CHOOSE YOUR CHAMPION",
		Font = UiKit.TITLE_FONT,
		TextScaled = true,
		TextColor3 = UiKit.GOLD,
		Parent = panel,
	})
	UiKit.label({
		Name = "Lore",
		Position = UDim2.fromScale(0, 0.08),
		Size = UDim2.fromScale(1, 0.05),
		Text = "When the Tide Bell rises, Kanejima rises with it. The last one standing strikes it — and calls back one thing the sea has taken.",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(200, 196, 186),
		Parent = panel,
	})

	local row = UiKit.new("Frame", {
		Name = "Cards",
		Position = UDim2.fromScale(0, 0.15),
		Size = UDim2.fromScale(1, 0.3),
		BackgroundTransparency = 1,
		Parent = panel,
	}, { UiKit.list(Enum.FillDirection.Horizontal, 10) })
	for index, fighter in Fighters.LIST do
		cards[fighter.id] = buildCard(row, fighter, index)
	end

	local detail = UiKit.new("Frame", {
		Name = "Detail",
		Position = UDim2.fromScale(0, 0.47),
		Size = UDim2.fromScale(1, 0.44),
		BackgroundColor3 = UiKit.INK,
		BackgroundTransparency = 0.05,
		Parent = panel,
	}, { UiKit.corner(14), UiKit.stroke(Color3.fromRGB(70, 70, 82), 1.5) })
	detailHeader = UiKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = UiKit.GOLD,
		BorderSizePixel = 0,
		Parent = detail,
	})
	detailName = UiKit.label({
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.new(0.6, 0, 0, 34),
		Font = UiKit.TITLE_FONT,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = detail,
	})
	detailTitle = UiKit.label({
		Position = UDim2.fromOffset(18, 46),
		Size = UDim2.new(1, -36, 0, 20),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UiKit.GOLD,
		Parent = detail,
	})
	detailBlurb = UiKit.label({
		Position = UDim2.fromOffset(18, 68),
		Size = UDim2.new(1, -36, 0, 22),
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.BuilderSans,
		TextColor3 = Color3.fromRGB(220, 214, 200),
		Parent = detail,
	})
	detailMoves = UiKit.new("ScrollingFrame", {
		Name = "Moves",
		Position = UDim2.fromOffset(14, 96),
		Size = UDim2.new(1, -28, 1, -104),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = detail,
	}, {
		UiKit.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 54),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	fightButton = UiKit.new("TextButton", {
		Name = "Fight",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(250, 48),
		BackgroundColor3 = UiKit.GOLD,
		Text = "FIGHT",
		Font = UiKit.TITLE_FONT,
		TextSize = 26,
		TextColor3 = UiKit.INK,
		Selectable = true,
		Parent = detail,
	}, { UiKit.corner(10) })
	fightButton.Activated:Connect(function()
		SoundController.play("ui", nil, 1, 0.8)
		Remotes.SelectFighter:FireServer(selectedId)
		SelectController.close()
	end)

	UiKit.label({
		Name = "Wheel",
		Position = UDim2.fromScale(0, 0.93),
		Size = UDim2.fromScale(1, 0.05),
		Text = wheelText(),
		TextScaled = true,
		TextColor3 = Color3.fromRGB(190, 186, 176),
		Parent = panel,
	})

	local close = UiKit.new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = UiKit.INK_SOFT,
		Text = "✕",
		Font = UiKit.HEAVY_FONT,
		TextSize = 22,
		TextColor3 = UiKit.PAPER,
		Selectable = true,
		Parent = backdrop,
	}, { UiKit.corner(22) })
	close.Activated:Connect(function()
		SelectController.close()
	end)

	screen.Parent = localPlayer:WaitForChild("PlayerGui")
	refreshDetails()
end

function SelectController.isOpen(): boolean
	return screen ~= nil and screen.Enabled
end

function SelectController.onToggled(listener: (boolean) -> ())
	table.insert(openListeners, listener)
end

function SelectController.open()
	local current = localPlayer:GetAttribute("Fighter")
	if type(current) == "string" and Fighters.get(current) then
		selectedId = current
	end
	refreshDetails()
	screen.Enabled = true
	if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
		GuiService.SelectedObject = cards[selectedId]
	end
	for _, listener in openListeners do
		listener(true)
	end
end

function SelectController.close()
	screen.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then
		GuiService.SelectedObject = nil
	end
	for _, listener in openListeners do
		listener(false)
	end
end

function SelectController.toggle()
	if SelectController.isOpen() then
		SelectController.close()
	else
		SelectController.open()
	end
end

local function hookAltar(altar: Instance)
	local prompt = altar:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Triggered:Connect(function(player)
			if player == localPlayer then
				SelectController.open()
			end
		end)
	end
end

function SelectController.init(_self: any)
	build()
end

function SelectController.start(_self: any)
	for _, altar in CollectionService:GetTagged("FighterAltar") do
		hookAltar(altar)
	end
	CollectionService:GetInstanceAddedSignal("FighterAltar"):Connect(hookAltar)
	-- First visit: show the roster once the character exists.
	if not localPlayer.Character then
		localPlayer.CharacterAdded:Wait()
	end
	task.wait(1)
	SelectController.open()
end

return SelectController
