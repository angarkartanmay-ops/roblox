--!strict
-- Small helpers for building UI in code with a consistent look.

local UiKit = {}

UiKit.INK = Color3.fromRGB(14, 16, 24)
UiKit.INK_SOFT = Color3.fromRGB(28, 31, 44)
UiKit.PAPER = Color3.fromRGB(244, 236, 220)
UiKit.GOLD = Color3.fromRGB(255, 205, 110)
UiKit.RED = Color3.fromRGB(235, 70, 60)
UiKit.TEAL = Color3.fromRGB(60, 240, 225)

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
	return UiKit.new("TextLabel", base)
end

return UiKit
