--!strict
-- Player input (keyboard/mouse, gamepad, touch through HudController), local prediction of the
-- player's own moves (animation, effects and cooldowns start instantly; rolled back if the server
-- never confirms), dashing, blocking, and applying the server's knockback/teleports to our character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Types = require(ReplicatedStorage.Shared.Types)
local Effects = require("../Lib/Effects")
local Remotes = require("../Lib/Remotes")
local AnimationController = require("./AnimationController")
local SelectController = require("./SelectController")
local VfxController = require("./VfxController")

type FighterSpec = Types.FighterSpec

local InputController = {}

local localPlayer = Players.LocalPlayer

local KEYBOARD: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Ability1",
	[Enum.KeyCode.Two] = "Ability2",
	[Enum.KeyCode.Three] = "Ability3",
	[Enum.KeyCode.Four] = "Ability4",
	[Enum.KeyCode.G] = "Ultimate",
	[Enum.KeyCode.ButtonX] = "Ability1",
	[Enum.KeyCode.ButtonY] = "Ability2",
	[Enum.KeyCode.ButtonL1] = "Ability3",
	[Enum.KeyCode.ButtonR1] = "Ability4",
	[Enum.KeyCode.DPadUp] = "Ultimate",
}

-- Local predicted state (server clock)
local readyAt: { [string]: number } = {}
local durations: { [string]: number } = {}
local pending: { [string]: { slot: string, at: number } } = {}
local lockUntil = 0
local m1Index = 0
local lastM1At: number? = nil
local m1ReadyAt = 0
local dashReadyAt = 0
local m1Held = false
local blockHeld = false
local lastBlockSend = 0
local currentMover: Instance? = nil
local notices: { (string) -> () } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function character(): Model?
	return localPlayer.Character
end

local function aliveRoot(): (Model?, Humanoid?, BasePart?)
	local model = character()
	if not model then
		return nil, nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return model, humanoid, root
end

function InputController.fighter(): FighterSpec?
	local model = character()
	local id = if model then model:GetAttribute("Fighter") else nil
	return Fighters.get(if type(id) == "string" then id else nil)
end

local function notify(text: string)
	for _, listener in notices do
		listener(text)
	end
end

-- Listen for short local notices ("Silenced", "Not ready", ...).
function InputController.onNotice(listener: (string) -> ())
	table.insert(notices, listener)
end

local function cameraAim(): Vector3
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
end

local function flat(vector: Vector3): Vector3
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 1e-3 then flattened.Unit else Vector3.new(0, 0, -1)
end

local function faceAim(root: BasePart, aim: Vector3)
	local direction = flat(aim)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
end

local function stunnedOrBusy(model: Model): boolean
	return model:GetAttribute("Stunned") == true or model:GetAttribute("GuardBroken") == true
end

-- Apply a velocity to our own character (we own its physics).
local function applyVelocity(root: BasePart, velocity: Vector3, duration: number)
	if currentMover then
		currentMover:Destroy()
		currentMover = nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "ImpulseAttachment"
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.MaxForce = 1e6
	mover.VectorVelocity = velocity
	mover.Parent = attachment
	attachment.Parent = root
	currentMover = attachment
	task.delay(duration, function()
		attachment:Destroy()
		if currentMover == attachment then
			currentMover = nil
		end
	end)
end

-- Seconds left on a slot's cooldown and its full length (for the HUD).
function InputController.cooldown(slot: string): (number, number)
	local remaining = math.max(0, (readyAt[slot] or 0) - now())
	return remaining, durations[slot] or 1
end

function InputController.dashCooldown(): (number, number)
	return math.max(0, dashReadyAt - now()), Constants.DASH_COOLDOWN
end

-- Try the move in `slot`. Predicts locally, then sends the intent to the server.
function InputController.pressSlot(slot: string)
	if SelectController.isOpen() then
		return
	end
	local model, _, root = aliveRoot()
	local fighter = InputController.fighter()
	if not model or not root or not fighter then
		return
	end
	if stunnedOrBusy(model) or blockHeld then
		return
	end
	local t = now()
	if t < lockUntil - 0.05 then
		return
	end

	local moveId: string
	if slot == "M1" then
		if t < m1ReadyAt - 0.02 then
			return
		end
		local index = CombatMath.nextComboIndex(m1Index, lastM1At, t)
		m1Index = index
		lastM1At = t
		local finisher = index >= Constants.COMBO_HITS
		m1ReadyAt = t + fighter.m1.interval + (if finisher then Constants.FINISHER_LOCK else 0)
		lockUntil = t + fighter.m1.interval * 0.8
		moveId = Fighters.m1MoveId(index)
	else
		if model:GetAttribute("Silenced") == true then
			notify("SILENCED")
			return
		end
		local move = Fighters.moveForSlot(fighter, slot)
		if not move then
			return
		end
		if t < (readyAt[slot] or 0) - 0.05 then
			return
		end
		if slot == "Ultimate" then
			local resonance = localPlayer:GetAttribute("Resonance")
			if type(resonance) ~= "number" or resonance < Constants.RESONANCE_MAX then
				notify("RESONANCE NOT FULL")
				return
			end
		end
		readyAt[slot] = t + move.cooldown
		durations[slot] = math.max(move.cooldown, 0.1)
		lockUntil = t + move.lock
		moveId = move.id
		pending[move.id] = { slot = slot, at = t }
	end

	local aim = cameraAim()
	faceAim(root, aim)
	local facing = flat(aim)
	local extra = nil
	local move = if slot ~= "M1" then Fighters.moveForSlot(fighter, slot) else nil
	if move and move.pointForward then
		extra = { point = Effects.ground(root.Position + facing * move.pointForward, 30) }
	end
	VfxController.markPredicted(moveId)
	VfxController.playMove(model, fighter.id, moveId, t, facing, extra)
	Remotes.Action:FireServer(slot, aim)
end

-- Touch ATTACK button: holding it chains M1s like holding the mouse button.
function InputController.setM1Held(on: boolean)
	m1Held = on
	if on then
		InputController.pressSlot("M1")
	end
end

function InputController.setBlock(on: boolean)
	blockHeld = on
	if not on then
		Remotes.SetBlock:FireServer(false)
		return
	end
	local model = aliveRoot()
	if model and not stunnedOrBusy(model) then
		lastBlockSend = os.clock()
		Remotes.SetBlock:FireServer(true)
	end
end

function InputController.dash()
	if SelectController.isOpen() then
		return
	end
	local model, humanoid, root = aliveRoot()
	local fighter = InputController.fighter()
	if not model or not humanoid or not root then
		return
	end
	local t = now()
	if stunnedOrBusy(model) or blockHeld or t < dashReadyAt or t < lockUntil - 0.05 then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = flat(cameraAim())
	end
	direction = flat(direction)
	dashReadyAt = t + Constants.DASH_COOLDOWN
	applyVelocity(root, direction * Constants.DASH_SPEED + Vector3.new(0, 2, 0), Constants.DASH_DURATION)
	VfxController.markPredicted("Dash")
	VfxController.playMove(model, if fighter then fighter.id else nil, "Dash", t, direction, nil)
	Remotes.Dash:FireServer(direction)
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
		m1Held = true
		InputController.pressSlot("M1")
	elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonL2 then
		InputController.setBlock(true)
	elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonB then
		InputController.dash()
	elseif key == Enum.KeyCode.T or key == Enum.KeyCode.DPadDown then
		SelectController.toggle()
	else
		local slot = KEYBOARD[key]
		if slot then
			InputController.pressSlot(slot)
		end
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	local key = input.KeyCode
	if input.UserInputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
		m1Held = false
	elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonL2 then
		if blockHeld then
			InputController.setBlock(false)
		end
	end
end

-- Hold-to-chain M1, block re-sends, and rollback of unconfirmed predictions.
local function onHeartbeat()
	if m1Held then
		InputController.pressSlot("M1")
	end
	local model = character()
	if blockHeld and model and model:GetAttribute("Blocking") ~= true and os.clock() - lastBlockSend > 0.3 then
		if not stunnedOrBusy(model) then
			lastBlockSend = os.clock()
			Remotes.SetBlock:FireServer(true)
		end
	end
	local t = now()
	for moveId, entry in pending do
		if t - entry.at > 0.9 then
			pending[moveId] = nil
			readyAt[entry.slot] = 0
			lockUntil = 0
		end
	end
end

local function resetState()
	table.clear(readyAt)
	table.clear(pending)
	lockUntil = 0
	m1Index = 0
	lastM1At = nil
	m1ReadyAt = 0
	dashReadyAt = 0
	blockHeld = false
	m1Held = false
	currentMover = nil
end

function InputController.start(_self: any)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.Heartbeat:Connect(onHeartbeat)
	localPlayer.CharacterAdded:Connect(resetState)

	VfxController.onOwnMoveConfirmed(function(moveId)
		pending[moveId] = nil
	end)

	Remotes.Impulse.OnClientEvent:Connect(function(velocity: Vector3, duration: number)
		local _, _, root = aliveRoot()
		if root and typeof(velocity) == "Vector3" and type(duration) == "number" then
			applyVelocity(root, velocity, math.clamp(duration, 0.02, 1))
		end
	end)
	Remotes.Teleport.OnClientEvent:Connect(function(cframe: CFrame)
		local model = aliveRoot()
		if model and typeof(cframe) == "CFrame" then
			model:PivotTo(cframe)
		end
	end)

	SelectController.onToggled(function(open)
		if open then
			m1Held = false
			if blockHeld then
				InputController.setBlock(false)
			end
		end
	end)

	-- Keep prediction honest if the server changes our champion.
	localPlayer:GetAttributeChangedSignal("Fighter"):Connect(function()
		table.clear(readyAt)
		local model = character()
		if model then
			AnimationController.stop(model)
		end
	end)
end

return InputController
