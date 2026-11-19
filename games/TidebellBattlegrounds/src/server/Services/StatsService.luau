--!strict
-- Session stats: leaderboard (Kills, Shards), kill streaks, kill feed and announcements.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatMath = require(ReplicatedStorage.Shared.CombatMath)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Net = require("../Lib/Net")
local Registry = require("./Registry")

type Entity = Registry.Entity

local StatsService = {}

local GOLD = Color3.fromRGB(255, 200, 90)

local function stat(player: Player, name: string): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild(name)
	return if value and value:IsA("IntValue") then value else nil
end

function StatsService.addShards(player: Player, amount: number)
	local value = stat(player, "Shards")
	if value and amount > 0 then
		value.Value += math.floor(amount)
	end
end

function StatsService.announce(text: string, color: Color3?)
	Net.Notify:FireAllClients("announce", { text = text, color = color or GOLD })
end

function StatsService.toast(player: Player, text: string)
	Net.Notify:FireClient(player, "toast", { text = text })
end

local function setupPlayer(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = leaderstats
	local shards = Instance.new("IntValue")
	shards.Name = "Shards"
	shards.Parent = leaderstats
	leaderstats.Parent = player
	player:SetAttribute("Streak", 0)
end

local function onPlayerDied(entity: Entity)
	local victimPlayer = entity.player
	if not victimPlayer then
		return
	end
	victimPlayer:SetAttribute("Streak", 0)
	local now = Registry.now()
	local killer = entity.lastAttacker
	local credited = killer ~= nil and killer ~= entity and now - entity.lastAttackedAt <= Constants.KILL_CREDIT_WINDOW

	if credited and killer and killer.player then
		local killerPlayer = killer.player
		local kills = stat(killerPlayer, "Kills")
		if kills then
			kills.Value += 1
		end
		local current = killerPlayer:GetAttribute("Streak")
		local streak = (if type(current) == "number" then current else 0) + 1
		killerPlayer:SetAttribute("Streak", streak)
		StatsService.addShards(killerPlayer, CombatMath.killReward(streak))
		Net.Notify:FireAllClients("kill", {
			killer = killerPlayer.DisplayName,
			victim = victimPlayer.DisplayName,
			killerFighter = killer.fighterId,
			victimFighter = entity.fighterId,
		})
		if CombatMath.isStreakAnnounced(streak) then
			StatsService.announce(`{killerPlayer.DisplayName} is on a {streak}-kill streak!`)
		end
	elseif credited and killer and killer.kind == "Boss" then
		Net.Notify:FireAllClients("kill", {
			killer = "The Tide Warden",
			victim = victimPlayer.DisplayName,
			victimFighter = entity.fighterId,
		})
	else
		Net.Notify:FireAllClients("kill", { victim = victimPlayer.DisplayName, victimFighter = entity.fighterId })
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
