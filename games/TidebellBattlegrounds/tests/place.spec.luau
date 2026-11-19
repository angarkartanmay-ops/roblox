--!strict
-- Structural check of the assembled place (build/game.rbxl from `rojo build`): scripts, remotes,
-- lighting and workspace settings are where the game expects them.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local PLACE = "build/game.rbxl"

local REMOTES = {
	"Action",
	"SetBlock",
	"Dash",
	"SelectFighter",
	"MoveFx",
	"PhaseFx",
	"HitFx",
	"ProjectileFx",
	"BossFx",
	"Impulse",
	"Teleport",
	"Notify",
}

local SHARED = { "Types", "Constants", "Elements", "CombatMath", "Fighters", "Poses", "VfxCatalog" }

local SERVICES = {
	"Registry",
	"StatusService",
	"CombatService",
	"ProjectileService",
	"FighterService",
	"MapService",
	"DummyService",
	"BossService",
	"StatsService",
}

local SERVER_LIB = { "Net", "Hitbox", "Weapons" }

local CONTROLLERS = {
	"InputController",
	"AnimationController",
	"VfxController",
	"CameraController",
	"SoundController",
	"HudController",
	"SelectController",
}

local CLIENT_LIB = { "UiKit", "Effects", "Rig", "Remotes" }

local function child(parent: any, name: string): any
	local found = parent and parent:FindFirstChild(name)
	if not found then
		error(`missing {name} under {parent and parent:GetFullName() or "nil"}`, 2)
	end
	return found
end

describe("Built place", function()
	if not fs.isFile(PLACE) then
		it("exists (run `rojo build -o build/game.rbxl` first)", function()
			error(`{PLACE} not found`)
		end)
		return
	end

	local game = roblox.deserializePlace(fs.readFile(PLACE))

	it("ships every shared module", function()
		local shared = child(game:GetService("ReplicatedStorage"), "Shared")
		for _, name in SHARED do
			expect(child(shared, name).ClassName, name):toBe("ModuleScript")
		end
	end)

	it("declares every remote statically", function()
		local remotes = child(game:GetService("ReplicatedStorage"), "Remotes")
		for _, name in REMOTES do
			expect(child(remotes, name).ClassName, name):toBe("RemoteEvent")
		end
	end)

	it("has one server entry script with its services", function()
		local server = child(game:GetService("ServerScriptService"), "Server")
		expect(server.ClassName):toBe("Script")
		local services = child(server, "Services")
		for _, name in SERVICES do
			expect(child(services, name).ClassName, name):toBe("ModuleScript")
		end
		local lib = child(server, "Lib")
		for _, name in SERVER_LIB do
			expect(child(lib, name).ClassName, name):toBe("ModuleScript")
		end
	end)

	it("has one client entry script with its controllers", function()
		local playerScripts = child(game:GetService("StarterPlayer"), "StarterPlayerScripts")
		local client = child(playerScripts, "Client")
		expect(client.ClassName):toBe("LocalScript")
		local controllers = child(client, "Controllers")
		for _, name in CONTROLLERS do
			expect(child(controllers, name).ClassName, name):toBe("ModuleScript")
		end
		local lib = child(client, "Lib")
		for _, name in CLIENT_LIB do
			expect(child(lib, name).ClassName, name):toBe("ModuleScript")
		end
	end)

	it("keeps server code out of replicated containers", function()
		for _, descendant in game:GetService("ReplicatedStorage"):GetDescendants() do
			expect(descendant.ClassName ~= "Script", descendant:GetFullName()):toBeTruthy()
		end
	end)

	it("sets up the eclipse-dusk lighting", function()
		local lighting = game:GetService("Lighting")
		expect(lighting.Technology == roblox.Enum.Technology.Future, "Future lighting"):toBeTruthy()
		expect(child(lighting, "Atmosphere").ClassName):toBe("Atmosphere")
		expect(child(lighting, "Bloom").ClassName):toBe("BloomEffect")
		expect(child(lighting, "SunRays").ClassName):toBe("SunRaysEffect")
	end)

	it("disables streaming for the small arena and shortens respawns", function()
		expect(game:GetService("Workspace").StreamingEnabled):toBe(false)
		expect(game:GetService("Players").RespawnTime):toBe(4)
	end)
end)
