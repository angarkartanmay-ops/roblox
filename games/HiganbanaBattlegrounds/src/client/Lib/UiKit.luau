--!strict
-- Small helpers for building UI in code with a consistent look.

local UiKit = {}

UiKit.INK = Color3.fromRGB(14, 16, 24)
UiKit.INK_SOFT = Color3.fromRGB(28, 31, 44)
UiKit.PAPER = Color3.fromRGB(244, 236, 220)
UiKit.GOLD = Color3.fromRGB(255, 205, 110)
UiKit.RED = Color3.fromRGB(235, 70, 60)
UiKit.TEAL = Color3.fromRGB(60, 240, 225)

-- design/ui.json theme: lacquer-black panels, bone-white ink, gold trim.
UiKit.PANEL = Color3.fromHex("#1B1A1F")
UiKit.PANEL_ALT = Color3.fromHex("#26232B")
UiKit.SLOT = Color3.fromHex("#2F2B33")
UiKit.OUTLINE = Color3.fromHex("#0F0E12")
UiKit.CREAM = Color3.fromHex("#E8E1D2")
UiKit.INK_LIGHT = Color3.fromHex("#E8E1D2")
UiKit.INK_DIM = Color3.fromHex("#B9B1A2")
UiKit.TRIM = Color3.fromHex("#C99A3B")
UiKit.LACQUER = Color3.fromHex("#C21F2E")
UiKit.GREY = Color3.fromHex("#8C8A93")
UiKit.HEALTH = Color3.fromHex("#7FBF6A")
UiKit.KI = Color3.fromHex("#E0303E")
UiKit.GUARD = Color3.fromHex("#C99A3B")

-- Relation colours (ui.json palette: overcome, resisted, feeding, drawing).
UiKit.RELATION = {
	Overcome = Color3.fromHex("#E0303E"),
	Resisted = Color3.fromHex("#8C8A93"),
	Feeding = Color3.fromHex("#4AA860"),
	Drawing = Color3.fromHex("#C21F2E"),
	Neutral = Color3.fromHex("#E8E1D2"),
} :: { [string]: Color3 }

-- Every screen is laid out at this reference size and scaled to the viewport with a UIScale.
UiKit.REFERENCE = Vector2.new(1280, 720)

UiKit.TITLE_FONT = Enum.Font.Bangers
UiKit.BODY_FONT = Enum.Font.BuilderSansBold
UiKit.HEAVY_FONT = Enum.Font.BuilderSansExtraBold

function UiKit.color(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

-- Create an instance, set properties, parent children, then parent it last.
function UiKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UiKit.corner(radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	return corner
end

function UiKit.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.Thickness = thickness or 2
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return stroke
end

function UiKit.textStroke(color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.Thickness = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return stroke
end

function UiKit.padding(all: number): UIPadding
	local padding = Instance.new("UIPadding")
	local value = UDim.new(0, all)
	padding.PaddingTop = value
	padding.PaddingBottom = value
	padding.PaddingLeft = value
	padding.PaddingRight = value
	return padding
end

function UiKit.list(direction: Enum.FillDirection, gap: number, align: Enum.HorizontalAlignment?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return layout
end

function UiKit.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	return gradient
end

function UiKit.label(props: { [string]: any }): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = UiKit.BODY_FONT,
		TextColor3 = UiKit.PAPER,
		TextSize = 18,
	}
	for key, value in props do
		base[key] = value
	end
	-- Keep a UIScale matched to the viewport so a layout made at REFERENCE fits any screen.
	function UiKit.autoScale(scale: UIScale, minimum: number?, maximum: number?)
		local camera = game:GetService("Workspace").CurrentCamera
		local function refresh()
			local viewport = if camera then camera.ViewportSize else UiKit.REFERENCE
			local factor = math.min(viewport.X / UiKit.REFERENCE.X, viewport.Y / UiKit.REFERENCE.Y)
			scale.Scale = math.clamp(factor, minimum or 0.45, maximum or 1.6)
		end
		refresh()
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
	end

	-- A full-screen ScreenGui whose `Root` frame is REFERENCE-sized, centred and auto-scaled.
	function UiKit.screen(name: string, order: number, parent: Instance): (ScreenGui, Frame)
		local gui = UiKit.new("ScreenGui", {
			Name = name,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = order,
			Parent = parent,
		})
		local root = UiKit.new("Frame", {
			Name = "Root",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(UiKit.REFERENCE.X, UiKit.REFERENCE.Y),
			BackgroundTransparency = 1,
			Parent = gui,
		})
		local scale = Instance.new("UIScale")
		scale.Parent = root
		UiKit.autoScale(scale)
		return gui, root
	end

	-- A lacquer panel with the theme's corner, outline and gold trim.
	function UiKit.panel(props: { [string]: any }): Frame
		local base: { [string]: any } = {
			BackgroundColor3 = UiKit.PANEL,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
		}
		for key, value in props do
			base[key] = value
		end
		local frame = UiKit.new("Frame", base)
		UiKit.corner(12).Parent = frame
		UiKit.stroke(UiKit.OUTLINE, 3).Parent = frame
		return frame
	end

	-- A theme button: dark slot fill, outline, light text. Text stays readable on every fill.
	function UiKit.button(props: { [string]: any }): TextButton
		local base: { [string]: any } = {
			BackgroundColor3 = UiKit.SLOT,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = UiKit.HEAVY_FONT,
			TextColor3 = UiKit.INK_LIGHT,
			TextSize = 24,
		}
		for key, value in props do
			base[key] = value
		end
		local button = UiKit.new("TextButton", base)
		UiKit.corner(10).Parent = button
		UiKit.stroke(UiKit.OUTLINE, 3).Parent = button
		UiKit.textStroke(UiKit.OUTLINE, 2).Parent = button
		return button
	end

	function UiKit.hex(color: Color3): string
		return "#" .. color:ToHex()
	end

	return UiKit.new("TextLabel", base)
end

return UiKit
