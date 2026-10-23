--!strict
-- Minimal describe/it/expect test framework for Lune.
-- Spec files register tests at require time; tests/init.luau runs them.

export type Expectation = {
	toBe: (self: Expectation, expected: any) -> (),
	toEqual: (self: Expectation, expected: any) -> (),
	toBeCloseTo: (self: Expectation, expected: number, epsilon: number?) -> (),
	toBeGreaterThan: (self: Expectation, bound: number) -> (),
	toBeLessThan: (self: Expectation, bound: number) -> (),
	toBeTruthy: (self: Expectation) -> (),
	toBeFalsy: (self: Expectation) -> (),
	toThrow: (self: Expectation, pattern: string?) -> (),
}

type Case = {
	name: string,
	fn: () -> (),
}

local Test = {}

local cases: { Case } = {}
local prefix: { string } = {}

local function fullName(name: string): string
	if #prefix == 0 then
		return name
	end
	return table.concat(prefix, " > ") .. " > " .. name
end

function Test.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function Test.it(name: string, fn: () -> ())
	table.insert(cases, { name = fullName(name), fn = fn })
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

Test.deepEqual = deepEqual

local function fail(message: string)
	error(message, 3)
end

function Test.expect(actual: any): Expectation
	local e = {}

	function e.toBe(_self: Expectation, expected: any)
		if actual ~= expected then
			fail(`expected {show(expected)}, got {show(actual)}`)
		end
	end

	function e.toEqual(_self: Expectation, expected: any)
		if not deepEqual(actual, expected) then
			fail(`expected deep equality with {show(expected)}, got {show(actual)}`)
		end
	end

	function e.toBeCloseTo(_self: Expectation, expected: number, epsilon: number?)
		local eps = epsilon or 1e-9
		if type(actual) ~= "number" or math.abs(actual - expected) > eps then
			fail(`expected {expected} ± {eps}, got {show(actual)}`)
		end
	end

	function e.toBeGreaterThan(_self: Expectation, bound: number)
		if type(actual) ~= "number" or actual <= bound then
			fail(`expected > {bound}, got {show(actual)}`)
		end
	end

	function e.toBeLessThan(_self: Expectation, bound: number)
		if type(actual) ~= "number" or actual >= bound then
			fail(`expected < {bound}, got {show(actual)}`)
		end
	end

	function e.toBeTruthy(_self: Expectation)
		if not actual then
			fail(`expected truthy, got {show(actual)}`)
		end
	end

	function e.toBeFalsy(_self: Expectation)
		if actual then
			fail(`expected falsy, got {show(actual)}`)
		end
	end

	function e.toThrow(_self: Expectation, pattern: string?)
		local ok, err = pcall(actual)
		if ok then
			fail("expected function to throw")
		end
		if pattern and not string.find(tostring(err), pattern) then
			fail(`expected error matching {show(pattern)}, got {show(err)}`)
		end
	end

	return (e :: any) :: Expectation
end

-- Runs every registered case whose name contains `filter` (case-insensitive). Returns passed, failed.
function Test.run(filter: string?): (number, number)
	local needle = if filter then string.lower(filter) else nil
	local passed, failed = 0, 0
	for _, case in cases do
		if needle == nil or string.find(string.lower(case.name), needle, 1, true) then
			local ok, err = pcall(case.fn)
			if ok then
				passed += 1
			else
				failed += 1
				print(`  FAIL  {case.name}\n        {err}`)
			end
		end
	end
	return passed, failed
end

return Test
