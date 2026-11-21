--!strict
-- Minimal test harness for Lune: describe / it / expect, with a shared result tally.

local Harness = {}

local results = { passed = 0, failed = 0, failures = {} :: { string } }
local groupStack: { string } = {}

function Harness.describe(name: string, body: () -> ())
	table.insert(groupStack, name)
	body()
	table.remove(groupStack)
end

function Harness.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	local label = table.concat(groupStack, " > ") .. " > " .. name
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, `{label}\n      {tostring(err)}`)
	end
end

local function describeValue(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

export type Expectation = {
	toBe: (self: Expectation, expected: unknown) -> (),
	toBeNear: (self: Expectation, expected: number, epsilon: number?) -> (),
	toBeTruthy: (self: Expectation) -> (),
	toBeFalsy: (self: Expectation) -> (),
	toBeGreaterThan: (self: Expectation, limit: number) -> (),
	toBeAtLeast: (self: Expectation, limit: number) -> (),
	toBeAtMost: (self: Expectation, limit: number) -> (),
}

function Harness.expect(actual: unknown, context: string?): Expectation
	local suffix = if context then ` ({context})` else ""
	local expectation = {}

	function expectation.toBe(_self: Expectation, expected: unknown)
		if actual ~= expected then
			error(`expected {describeValue(expected)}, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	function expectation.toBeNear(_self: Expectation, expected: number, epsilon: number?)
		local tolerance = epsilon or 1e-6
		if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
			error(`expected {expected} ± {tolerance}, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	function expectation.toBeTruthy(_self: Expectation)
		if not actual then
			error(`expected a truthy value, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	function expectation.toBeFalsy(_self: Expectation)
		if actual then
			error(`expected a falsy value, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	function expectation.toBeGreaterThan(_self: Expectation, limit: number)
		if type(actual) ~= "number" or not (actual > limit) then
			error(`expected > {limit}, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	function expectation.toBeAtLeast(_self: Expectation, limit: number)
		if type(actual) ~= "number" or not (actual >= limit) then
			error(`expected >= {limit}, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	function expectation.toBeAtMost(_self: Expectation, limit: number)
		if type(actual) ~= "number" or not (actual <= limit) then
			error(`expected <= {limit}, got {describeValue(actual)}{suffix}`, 2)
		end
	end

	return (expectation :: any) :: Expectation
end

function Harness.results()
	return results
end

return Harness
