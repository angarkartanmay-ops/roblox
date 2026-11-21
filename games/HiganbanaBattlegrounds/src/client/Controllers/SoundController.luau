--!strict
-- Sound effects. Uses sounds that ship with the Roblox client as placeholders; replace the ids with
-- Creator Store sounds (see the roblox-sfx skill). Any sound that fails to preload is skipped
-- silently afterwards instead of warning on every play.

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

type SoundDef = { id: string, volume: number, pitch: number? }

local SOUNDS: { [string]: SoundDef } = {
	swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.45 },
	lunge = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.5 },
	hit = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, pitch = 1.5 },
	heavy = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 1, pitch = 0.6 },
	water = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.7 },
	whoosh = { id = "rbxasset://sounds/action_falling.mp3", volume = 0.35, pitch = 1.8 },
	bell = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.55, pitch = 0.5 },
	ui = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.3, pitch = 1.2 },
}

local SoundController = {}

local templates: { [string]: Sound } = {}
local unavailable: { [string]: boolean } = {}
local holderFolder: Folder? = nil

local function holder(): Folder
	local existing = holderFolder
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientSounds"
	folder.Parent = Workspace
	holderFolder = folder
	return folder
end

-- Play a named sound; positional when `position` is given.
function SoundController.play(name: string, position: Vector3?, volumeScale: number?, pitchScale: number?)
	local template = templates[name]
	if not template or unavailable[name] then
		return
	end
	local definition = SOUNDS[name]
	local sound = template:Clone()
	sound.Volume = definition.volume * (volumeScale or 1)
	sound.PlaybackSpeed = (definition.pitch or 1) * (pitchScale or 1)
	if position then
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = holder()
		sound.RollOffMaxDistance = 200
		sound.RollOffMinDistance = 12
		sound.Parent = anchor
		sound:Play()
		task.delay(4, function()
			anchor:Destroy()
		end)
	else
		sound.Parent = SoundService
		sound:Play()
		task.delay(4, function()
			sound:Destroy()
		end)
	end
end

function SoundController.init(_self: any)
	local folder = Instance.new("Folder")
	folder.Name = "SoundTemplates"
	folder.Parent = SoundService
	for name, definition in SOUNDS do
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = definition.id
		sound.Volume = definition.volume
		sound.Parent = folder
		templates[name] = sound
	end
end

function SoundController.start(_self: any)
	local list: { Instance } = {}
	local nameById: { [string]: { string } } = {}
	for name, sound in templates do
		table.insert(list, sound)
		local id = SOUNDS[name].id
		nameById[id] = nameById[id] or {}
		table.insert(nameById[id], name)
	end
	pcall(function()
		ContentProvider:PreloadAsync(list, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				for _, name in nameById[contentId] or ({} :: { string }) do
					unavailable[name] = true
				end
			end
		end)
	end)
end

return SoundController
