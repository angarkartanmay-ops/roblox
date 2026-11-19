--!strict
-- Champion selection and spawning: applies the chosen champion's stats, registers the character
-- for combat and dresses it with weapon, sash and aura.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Fighters = require(ReplicatedStorage.Shared.Fighters)
local Net = require("../Lib/Net")
local Weapons = require("../Lib/Weapons")
local Registry = require("./Registry")
local StatsService = require("./StatsService")

local FighterService = {}

local lastSelect: { [Player]: number } = {}

local function chosenFighter(player: Player)
	local value = player:GetAttribute("Fighter")
	return Fighters.getOrDefault(if type(value) == "string" then value else nil)
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	if character.Parent == nil then
		return
	end
	local fighter = chosenFighter(player)
	humanoid.MaxHealth = fighter.maxHealth
	humanoid.Health = fighter.maxHealth
	humanoid.WalkSpeed = fighter.walkSpeed
	character:SetAttribute("Fighter", fighter.id)
	character:SetAttribute("Element", fighter.element)

	local entity = Registry.register(character, humanoid, root, "Player", player)
	entity.fighterId = fighter.id
	entity.element = fighter.element
	entity.baseWalkSpeed = fighter.walkSpeed

	Weapons.equip(character, humanoid, fighter)
end

local function onPlayerAdded(player: Player)
	if player:GetAttribute("Fighter") == nil then
		player:SetAttribute("Fighter", Fighters.DEFAULT_ID)
	end
	player:SetAttribute("Resonance", 0)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

local function onSelect(player: Player, fighterId: unknown)
	if type(fighterId) ~= "string" or #fighterId > 32 then
		return
	end
	local fighter = Fighters.get(fighterId)
	if not fighter then
		return
	end
	local now = os.clock()
	if now - (lastSelect[player] or 0) < Constants.SELECT_COOLDOWN then
		return
	end
	lastSelect[player] = now

	local entity = Registry.forPlayer(player)
	if entity and Registry.isAlive(entity) and Registry.now() - entity.lastCombatAt < Constants.COMBAT_TAG_TIME then
		StatsService.toast(player, "You can't switch champions mid-fight. Break away for a few seconds.")
		return
	end
	player:SetAttribute("Fighter", fighter.id)
	if entity and Registry.isAlive(entity) and entity.fighterId == fighter.id then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn(`[Fighters] respawn failed for {player.Name}: {err}`)
		end
	end)
end

function FighterService.start(_self: any)
	Net.SelectFighter.OnServerEvent:Connect(onSelect)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSelect[player] = nil
	end)
end

return FighterService
