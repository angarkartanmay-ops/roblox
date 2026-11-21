--!strict
-- Camera feel: trauma-style shake, tinted flashes, dark beats before big impacts, FOV punches.
-- Flashes are rate-limited (photosensitivity: at most 3 per second).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local trauma = 0
local seed = math.random() * 1000
local grade: ColorCorrectionEffect? = nil
local flashTimes: { number } = {}
local baseFov = 70
local fovTween: Tween? = nil

local function camera(): Camera?
	return Workspace.CurrentCamera
end

local function getGrade(): ColorCorrectionEffect?
	local cam = camera()
	if not cam then
		return nil
	end
	local existing = grade
	if existing and existing.Parent == cam then
		return existing
	end
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "CombatGrade"
	effect.Parent = cam
	grade = effect
	return effect
end

-- Add shake; `amount` around 0.2 (light hit) to 2 (ultimate).
function CameraController.shake(amount: number)
	trauma = math.min(trauma + amount, 2.5)
end

-- Shake scaled by the local character's distance from `position`.
function CameraController.shakeAt(position: Vector3, amount: number, radius: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local distance = (root.Position - position).Magnitude
	if distance < radius then
		CameraController.shake(amount * (1 - distance / radius))
	end
end

function CameraController.flash(color: Color3, duration: number, brightness: number?)
	local now = os.clock()
	local recent = {}
	for _, time in flashTimes do
		if now - time < 1 then
			table.insert(recent, time)
		end
	end
	flashTimes = recent
	if #flashTimes >= 3 then
		return
	end
	table.insert(flashTimes, now)
	local effect = getGrade()
	if not effect then
		return
	end
	effect.TintColor = Color3.new(1, 1, 1):Lerp(color, 0.55)
	effect.Brightness = brightness or 0.25
	TweenService:Create(effect, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TintColor = Color3.new(1, 1, 1),
		Brightness = 0,
	}):Play()
end

-- A short darkening right before the brightest frame of a big move.
function CameraController.darkBeat(duration: number)
	local effect = getGrade()
	if not effect then
		return
	end
	effect.Brightness = -0.3
	effect.Saturation = -0.5
	TweenService:Create(effect, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Brightness = 0, Saturation = 0 })
		:Play()
end

function CameraController.fovPunch(amount: number, duration: number)
	local cam = camera()
	if not cam then
		return
	end
	if fovTween then
		fovTween:Cancel()
	end
	cam.FieldOfView = baseFov + amount
	local tween = TweenService:Create(
		cam,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = baseFov }
	)
	fovTween = tween
	tween:Play()
end

function CameraController.start(_self: any)
	local cam = camera()
	if cam then
		baseFov = cam.FieldOfView
	end
	RunService:BindToRenderStep("CombatShake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if trauma <= 0.001 then
			trauma = 0
			return
		end
		local current = camera()
		if not current then
			return
		end
		local t = os.clock() * 22
		local power = trauma * trauma
		local pitch = math.noise(seed, t) * 0.018 * power
		local yaw = math.noise(seed + 10, t) * 0.018 * power
		local roll = math.noise(seed + 20, t) * 0.03 * power
		current.CFrame = current.CFrame * CFrame.Angles(pitch, yaw, roll)
		trauma = math.max(0, trauma - dt * 2.4)
	end)
end

return CameraController
