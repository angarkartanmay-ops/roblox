--!strict
-- Keeps the game clearly its own: fails if names from Hell's Paradise: Jigokuraku appear
-- anywhere in the game's source or data (characters, places, factions, powers).

local fs = require("@lune/fs")
local Harness = require("./harness")

local describe, it, expect = Harness.describe, Harness.it, Harness.expect

local BANNED = {
	"jigokuraku",
	"hell's paradise",
	"gabimaru",
	"sagiri",
	"yuzuriha",
	"chobei",
	"nurugai",
	"gantetsusai",
	"tenza",
	"shion",
	"eizen",
	"kisho",
	"asaemon",
	"tensen",
	"rien",
	"jofuku",
	"hoko",
	"shinsenkyo",
	"kotaku",
	"horai",
	"iwagakure",
	"tao",
	"mei",
	"yui",
	"ju fa",
	"mu dan",
	"gui fa",
	"zhu jin",
	"doshi",
	"elixir",
}

local function collectFiles(directory: string, into: { string })
	for _, name in fs.readDir(directory) do
		local path = `{directory}/{name}`
		if fs.isDir(path) then
			collectFiles(path, into)
		elseif string.match(name, "%.luau$") or string.match(name, "%.json$") then
			table.insert(into, path)
		end
	end
end

local function findBanned(text: string): string?
	local lower = string.lower(text)
	for _, term in BANNED do
		local pattern = "%f[%w]" .. term .. "%f[%W]"
		if string.find(lower, pattern) then
			return term
		end
	end
	return nil
end

describe("Originality", function()
	it("detects banned names in sample text", function()
		expect(findBanned("A tribute to Gabimaru") == "gabimaru"):toBeTruthy()
		expect(findBanned("Taoist temple") == nil, "word boundaries respected"):toBeTruthy()
		expect(findBanned("The Tide Warden wakes") == nil):toBeTruthy()
	end)

	local files = {}
	collectFiles("src", files)
	table.insert(files, "default.project.json")

	it("scans every source file", function()
		expect(#files):toBeGreaterThan(10)
	end)

	for _, path in files do
		it(`{path} uses only original names`, function()
			local found = findBanned(fs.readFile(path))
			expect(found == nil, `found "{found}"`):toBeTruthy()
		end)
	end
end)
