--!strict
-- The server's Thirst: every point of damage souls deal each other spills into it. When it fills
-- (ThirstBase + ThirstPerPlayer x players), no earlier than THIRST_FIRST_AWAKE after the server
-- starts and THIRST_COOLDOWN_AFTER_FALL after the Elder last went down, the Thirsting Elder wakes.
-- Clients read `Thirst` and `ThirstMax` from Workspace attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Registry = require("./Registry")

local ThirstService = {}

local thirst = 0
local startedAt = 0
local lastDownAt: number? = nil
local awake = false
local wakeListeners: { () -> () } = {}

local function publish()
	Workspace:SetAttribute("Thirst", math.floor(thirst))
	Workspace:SetAttribute("ThirstMax", CombatMath.thirstThreshold(#Players:GetPlayers()))
end

-- PvP damage spills into the Thirst (nothing spills while the Elder is awake).
function ThirstService.add(amount: number)
	if awake or amount <= 0 or amount ~= amount then
		return
	end
	thirst += amount
	publish()
end

function ThirstService.value(): number
	return thirst
end

function ThirstService.onWake(listener: () -> ())
	table.insert(wakeListeners, listener)
end

-- ElderService reports its state: awake while it fights, and the time it went back down.
function ThirstService.setAwake(isAwake: boolean)
	awake = isAwake
	if not isAwake then
		lastDownAt = Registry.now()
	end
	Workspace:SetAttribute("ElderAwake", isAwake)
end

local function wake()
	thirst = 0
	publish()
	for _, listener in wakeListeners do
		task.spawn(listener)
	end
end

-- Fill the Thirst and wake the Elder now (debug hook and playtests).
function ThirstService.forceWake()
	if not awake then
		wake()
	end
end

local function check()
	if awake then
		return
	end
	local now = Registry.now()
	local players = #Players:GetPlayers()
	local sinceFall = if lastDownAt then now - lastDownAt else nil
	if CombatMath.elderMayWake(thirst, players, now - startedAt, sinceFall) then
		wake()
	end
end

function ThirstService.init(_self: any)
	startedAt = Registry.now()
	publish()
	Workspace:SetAttribute("ElderAwake", false)
	Players.PlayerAdded:Connect(publish)
	Players.PlayerRemoving:Connect(function()
		task.defer(publish)
	end)
end

function ThirstService.start(_self: any)
	while true do
		task.wait(1)
		check()
	end
end

return ThirstService
