--!strict
-- Session stats: the leaderboard (Petals, Kills, Streak), kill credit (the last hitter inside the
-- credit window, ring-outs included), the kill feed, server announcements, the death recap with
-- its counter-pick, and the Lily Crown worn by the Elder's top damage dealer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Phases = require(ReplicatedStorage.Shared.Phases)
local Net = require("../Lib/Net")
local Registry = require("./Registry")

type Entity = Registry.Entity

local StatsService = {}

local LILY = Color3.fromRGB(226, 52, 60)
local GOLD = Color3.fromRGB(255, 205, 120)

local crownListeners: { (Player?) -> () } = {}

local function stat(player: Player, name: string): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(name)
	return if value and value:IsA("IntValue") then value else nil
end

function StatsService.addPetals(player: Player, amount: number)
	local value = stat(player, "Petals")
	if value and amount > 0 then
		value.Value += math.floor(amount)
	end
end

function StatsService.petals(player: Player): number
	local value = stat(player, "Petals")
	return if value then value.Value else 0
end

function StatsService.announce(text: string, color: Color3?)
	Net.Notify:FireAllClients("announce", { text = text, color = color or GOLD })
end

function StatsService.toast(player: Player, text: string)
	Net.Notify:FireClient(player, "toast", { text = text })
end

-- The Lily Crown passes to `player` (nil clears it) for the rest of the session.
function StatsService.crown(player: Player?)
	for _, other in Players:GetPlayers() do
		other:SetAttribute("LilyCrown", other == player)
	end
	for _, listener in crownListeners do
		task.spawn(listener, player)
	end
end

function StatsService.onCrown(listener: (Player?) -> ())
	table.insert(crownListeners, listener)
end

local function setStreak(player: Player, streak: number)
	player:SetAttribute("Streak", streak)
	local value = stat(player, "Streak")
	if value then
		value.Value = streak
	end
end

local function setupPlayer(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	for _, name in { "Petals", "Kills", "Streak" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = leaderstats
	end
	leaderstats.Parent = player
	setStreak(player, 0)
	player:SetAttribute("LilyCrown", false)
end

-- The fighter whose phase overcomes `phase`: the death recap's counter-pick.
local function counterPick(phase: string?): string?
	if phase == nil then
		return nil
	end
	local overcomer = Phases.overcomerOf(phase)
	local fighter = if overcomer then Fighters.forPhase(overcomer) else nil
	return if fighter then fighter.id else nil
end

local function sendRecap(victim: Entity, killer: Entity?, ringOut: boolean)
	local player = victim.player
	if not player then
		return
	end
	local sources = {}
	for name, amount in victim.damageTakenBy do
		table.insert(sources, { name = name, amount = math.floor(amount + 0.5) })
	end
	table.sort(sources, function(a, b)
		return a.amount > b.amount
	end)
	local killerPhase = if killer then killer.phase else nil
	Net.Notify:FireClient(player, "recap", {
		killer = Registry.nameOf(killer),
		killerFighter = if killer then killer.fighterId else nil,
		killerPhase = killerPhase,
		ringOut = ringOut,
		sources = sources,
		counter = counterPick(killerPhase),
		respawn = Constants.RESPAWN_SECONDS,
	})
end

local function onPlayerDied(entity: Entity)
	local victimPlayer = entity.player
	if not victimPlayer then
		return
	end
	setStreak(victimPlayer, 0)
	local now = Registry.now()
	local ringOut = entity.model:GetAttribute("RingOut") == true
	local killer = entity.lastAttacker
	local credited = killer ~= nil and killer ~= entity and now - entity.lastAttackedAt <= Constants.KILL_CREDIT_WINDOW
	if not credited then
		killer = nil
	end
	sendRecap(entity, killer, ringOut)

	if killer and killer.player then
		local killerPlayer = killer.player
		local kills = stat(killerPlayer, "Kills")
		if kills then
			kills.Value += 1
		end
		local current = killerPlayer:GetAttribute("Streak")
		local streak = (if type(current) == "number" then current else 0) + 1
		setStreak(killerPlayer, streak)
		StatsService.addPetals(killerPlayer, CombatMath.killReward(streak))
		Net.Notify:FireAllClients("kill", {
			killer = killerPlayer.DisplayName,
			victim = victimPlayer.DisplayName,
			killerFighter = killer.fighterId,
			victimFighter = entity.fighterId,
			ringOut = ringOut,
		})
		if CombatMath.isStreakAnnounced(streak) then
			StatsService.announce(`{killerPlayer.DisplayName} is on a {streak}-soul streak!`, LILY)
		end
	elseif killer then
		Net.Notify:FireAllClients("kill", {
			killer = Registry.nameOf(killer),
			victim = victimPlayer.DisplayName,
			victimFighter = entity.fighterId,
			ringOut = ringOut,
		})
	else
		Net.Notify:FireAllClients("kill", {
			victim = victimPlayer.DisplayName,
			victimFighter = entity.fighterId,
			ringOut = ringOut,
		})
	end
end

function StatsService.init(_self: any)
	Registry.onAdded(function(entity)
		if entity.kind == "Player" then
			entity.humanoid.Died:Once(function()
				onPlayerDied(entity)
			end)
		end
	end)
end

function StatsService.start(_self: any)
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

return StatsService
