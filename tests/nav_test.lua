-- Focused host tests for the pure navigation planner. Run from repository root.
package.path = table.concat({
  "./machines/controller/lib/?.lua",
  "./?.lua",
  package.path
}, ";")

local tests, assertions = {}, 0

local function test(name, callback) tests[#tests + 1] = {name, callback} end
local function equal(actual, expected, message)
  assertions = assertions + 1
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end
local function truthy(value, message)
  assertions = assertions + 1
  if not value then error(message or "expected a truthy value", 2) end
end
local function contains(value, fragment)
  assertions = assertions + 1
  if type(value) ~= "string" or not value:find(fragment, 1, true) then
    error("expected " .. tostring(value) .. " to contain " .. fragment, 2)
  end
end

require("tests.nav_cases").register({
  test = test,
  equal = equal,
  truthy = truthy,
  contains = contains
})

local failures = 0
for _, item in ipairs(tests) do
  local ok, reason = pcall(item[2])
  if ok then io.write("ok - ", item[1], "\n")
  else
    failures = failures + 1
    io.write("not ok - ", item[1], "\n  ", tostring(reason), "\n")
  end
end
io.write(string.format("\n%d tests, %d assertions, %d failures\n",
  #tests, assertions, failures))
if failures > 0 then os.exit(1) end
