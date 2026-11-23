--!strict
-- Each soul's chosen fighter and phase. A soul may change phase at the Ferry Landing, after
-- PHASE_SWITCH_OOC seconds out of combat, or while dead (the death recap's counter-pick applies to
-- the next spawn). Spawning applies the fighter's stats, registers the character for combat and
-- dresses it with its weapon, worn kit, Elder's Sap and the Lily Crown.

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
	if not character.Parent then
		character.AncestryChanged:Wait()
	end
	if character.Parent == nil then
		return
	end
	local fighter = chosenFighter(player)
	humanoid.MaxHealth = fighter.maxHealth
	humanoid.Health = fighter.maxHealth
	humanoid.WalkSpeed = fighter.walkSpeed
	humanoid.BreakJointsOnDeath = false
	-- design/map.json volume.slideSlope: cliff faces over the mist are a slide
	-- into the ring-out, never a ledge to be stranded on (roblox-map T4).
	humanoid.MaxSlopeAngle = 45
	character:SetAttribute("Fighter", fighter.id)
	character:SetAttribute("Phase", fighter.phase)
	player:SetAttribute("Phase", fighter.phase)

	local entity = Registry.register(character, humanoid, root, "Player", player)
	entity.fighterId = fighter.id
	entity.phase = fighter.phase
	entity.baseWalkSpeed = fighter.walkSpeed

	local sap = player:GetAttribute("SapUntil")
	if type(sap) == "number" then
		entity.sapUntil = sap
	end

	Weapons.equip(character, humanoid, fighter)
	if player:GetAttribute("LilyCrown") == true then
		Weapons.crown(character)
	end
end

local function onPlayerAdded(player: Player)
	if player:GetAttribute("Fighter") == nil then
		player:SetAttribute("Fighter", Fighters.DEFAULT_ID)
	end
	player:SetAttribute("Ki", 0)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

local function respawn(player: Player)
	task.spawn(function()
		local ok, err = pcall(function()
			player:LoadCharacterAsync()
		end)
		if not ok then
			warn(`[Fighters] respawn failed for {player.Name}: {err}`)
		end
	end)
end

local function onSelect(player: Player, fighterId: unknown)
	if type(fighterId) ~= "string" or #fighterId > 32 then
		return
	end
	local fighter = Fighters.get(fighterId)
	if not fighter then
		return
	end
	local clock = os.clock()
	if clock - (lastSelect[player] or 0) < Constants.SELECT_COOLDOWN then
		return
	end
	lastSelect[player] = clock

	local entity = Registry.forPlayer(player)
	local alive = entity ~= nil and Registry.isAlive(entity)
	if entity and alive then
		local outOfCombat = Registry.now() - entity.lastCombatAt >= Constants.PHASE_SWITCH_OOC
		if not entity.safe and not outOfCombat then
			StatsService.toast(
				player,
				`Reach the Ferry Landing or stay out of combat for {Constants.PHASE_SWITCH_OOC} s to change phase.`
			)
			return
		end
	end
	player:SetAttribute("Fighter", fighter.id)
	if entity and alive and entity.fighterId == fighter.id then
		return
	end
	if alive then
		respawn(player)
	else
		StatsService.toast(player, `You will return as {fighter.displayName}.`)
	end
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
	StatsService.onCrown(function(holder)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				if player == holder then
					Weapons.crown(character)
				else
					Weapons.uncrown(character)
				end
			end
		end
	end)
end

return FighterService
