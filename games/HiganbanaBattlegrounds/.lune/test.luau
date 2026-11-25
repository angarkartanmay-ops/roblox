--!strict
-- Test runner: `lune run test` from the game folder. Exits non-zero on any failure.

local process = require("@lune/process")
local Harness = require("../tests/harness")

require("../tests/phases.spec")
require("../tests/combatmath.spec")
require("../tests/constants.spec")
require("../tests/fighters.spec")
require("../tests/poses.spec")
require("../tests/farshore.spec")
require("../tests/wilds.spec")
require("../tests/originality.spec")
require("../tests/place.spec")

local results = Harness.results()
for _, failure in results.failures do
	print(`FAIL  {failure}`)
end
print(`\n{results.passed} passed, {results.failed} failed`)
if results.failed > 0 then
	process.exit(1)
end
