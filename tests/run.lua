-- Host-side Milestone 1 tests. Run from the repository root with Lua 5.3.
package.path = table.concat({
  "./d4d31815-680c-4fb8-a846-ee3c6d49be69/lib/?.lua",
  "./d4d31815-680c-4fb8-a846-ee3c6d49be69/lib/?/init.lua",
  "./7762455c-2ffb-4307-ac41-4faa2ae6a3a1/lib/?.lua",
  package.path
}, ";")

local executor = require("ocia.executor")
local legacy = require("ocia.legacy")
local pose = require("ocia.pose")
local protocol = require("ocia.protocol")
local state = require("ocia.state")
local transport = require("ocia.transport")

local controllerAddress = "11111111-1111-1111-1111-111111111111"
local robotAddress = "22222222-2222-2222-2222-222222222222"
local tests = {}
local assertions = 0

local function test(name, callback)
  tests[#tests + 1] = {name = name, callback = callback}
end

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

local function request(id, operation, deployment)
  local parts, reason = protocol.buildRequest({
    request_id = id,
    deployment_id = deployment or "-",
    recipient = robotAddress,
    operation = operation,
    arguments = {}
  })
  truthy(parts, reason)
  return assert(protocol.parseRequest(parts, robotAddress)), parts
end

local function makeExecutor(options)
  options = options or {}
  local calls = 0
  local store = options.store or state.memoryStore(options.initial)
  local instance = executor.new({
    store = store,
    cache_size = options.cache_size or 64,
    perform = function(operation)
      calls = calls + 1
      if options.raise then error("injected robot exception") end
      if options.fail_operation then return false, "blocked" end
      return true, operation .. " complete"
    end,
    status_provider = function() return {energy = 100, capacity = 200} end
  })
  return instance, store, function() return calls end
end

test("protocol accepts a valid request and preserves its identity", function()
  local parsed = request("req-valid", "status", "deploy-1")
  equal(parsed.request_id, "req-valid")
  equal(parsed.deployment_id, "deploy-1")
  equal(parsed.recipient, robotAddress)
  equal(parsed.operation, "status")
end)

test("protocol rejects malformed, missing, and unsupported request fields", function()
  local _, code = protocol.parseRequest("not-a-table", robotAddress)
  equal(code, "malformed_request")
  local _, shortCode = protocol.parseRequest({protocol.MAGIC}, robotAddress)
  equal(shortCode, "malformed_request")

  local _, validParts = request("req-shape", "status")
  local cases = {
    {2, 99, "unsupported_version"},
    {3, "reply", "unexpected_message_type"},
    {4, nil, "invalid_request_id"},
    {6, "not an address", "invalid_recipient"},
    {7, "dance", "unsupported_operation"},
    {8, "steps=2", "invalid_arguments"}
  }
  for _, item in ipairs(cases) do
    local copy = {table.unpack(validParts)}
    copy[item[1]] = item[2]
    local parsed, caseCode = protocol.parseRequest(copy, robotAddress)
    equal(parsed, nil)
    equal(caseCode, item[3])
  end
end)

test("protocol rejects an incorrectly addressed request", function()
  local _, parts = request("req-recipient", "status")
  local parsed, code = protocol.parseRequest(parts, controllerAddress)
  equal(parsed, nil)
  equal(code, "incorrect_recipient")
end)

test("reply parsing rejects request packets and correlation rejects stale replies", function()
  local parsedRequest, requestParts = request("req-correlation", "move_forward", "deploy-2")
  local _, typeCode = protocol.parseReply(requestParts)
  equal(typeCode, "unexpected_message_type")

  local replyParts = assert(protocol.buildReply({
    request_id = "old-request",
    deployment_id = "deploy-2",
    operation = "move_forward",
    outcome = "succeeded",
    payload = {code = "ok"}
  }))
  local reply = assert(protocol.parseReply(replyParts))
  local correlated, reason = protocol.correlate(reply, parsedRequest)
  equal(correlated, nil)
  equal(reason, "request_id_mismatch")
end)

test("field encoding is deterministic and rejects malformed escapes", function()
  equal(assert(protocol.encodeFields({z = "two words", a = 1})), "a=1&z=two%20words")
  local decoded = assert(protocol.decodeFields("a=1&z=two%20words"))
  equal(decoded.z, "two words")
  local value, reason = protocol.decodeFields("bad=%Q0")
  equal(value, nil)
  truthy(reason)
end)

test("wire payloads are bounded locally", function()
  local parts, reason = protocol.buildReply({
    request_id = "req-large", deployment_id = "-", operation = "status",
    outcome = "succeeded", payload = {message = string.rep("x", 5000)}
  })
  equal(parts, nil)
  equal(reason, "result payload is too large")
end)

test("pose turns through all headings and left/right are inverse", function()
  local current = pose.new()
  for _, heading in ipairs({"east", "south", "west", "north"}) do
    current = assert(pose.apply(current, "turn_right"))
    equal(current.heading, heading)
  end
  current = assert(pose.apply(current, "turn_left"))
  current = assert(pose.apply(current, "turn_right"))
  equal(current.heading, "north")
end)

test("pose applies cardinal, inverse, and vertical movement", function()
  local expectations = {
    north = {0, -1}, east = {1, 0}, south = {0, 1}, west = {-1, 0}
  }
  for heading, expected in pairs(expectations) do
    local start = pose.new(4, 2, 7, heading)
    local moved = assert(pose.apply(start, "move_forward"))
    equal(moved.x, 4 + expected[1])
    equal(moved.z, 7 + expected[2])
    local restored = assert(pose.apply(moved, "move_backward"))
    truthy(pose.equal(restored, start))
  end
  local up = assert(pose.apply(pose.new(), "move_up"))
  equal(up.y, 1)
  equal(assert(pose.apply(up, "move_down")).y, 0)
end)

test("failed movement leaves pose unchanged and ambiguity makes it untrusted", function()
  local start = pose.new()
  truthy(pose.equal(pose.afterResult(start, "move_forward", false), start))
  local unknown = pose.unknown(start, "ambiguous")
  equal(unknown.trusted, false)
  local moved, reason = pose.apply(unknown, "move_forward")
  equal(moved, nil)
  equal(reason, "pose is untrusted")
end)

test("successful operation journals, updates pose, and caches completion", function()
  local instance, store, calls = makeExecutor()
  local move = request("req-success", "move_forward")
  local reply = instance:handle(move)
  equal(reply.outcome, "succeeded")
  equal(reply.payload.mode, "ready")
  equal(reply.payload.z, -1)
  equal(calls(), 1)
  equal(store.save_count, 3)
  local persisted = store.peek()
  equal(persisted.mode, "ready")
  equal(#persisted.completed, 1)
  equal(persisted.pose.z, -1)
end)

test("a failed physical operation is definite and does not change pose", function()
  local instance, _, calls = makeExecutor({fail_operation = true})
  local reply = instance:handle(request("req-blocked", "move_forward"))
  equal(reply.outcome, "failed")
  equal(reply.payload.z, 0)
  equal(calls(), 1)
end)

test("completed duplicate returns cached output without physical execution", function()
  local instance, _, calls = makeExecutor()
  local move = request("req-duplicate", "turn_right")
  local first = instance:handle(move)
  local second = instance:handle(move)
  equal(first.outcome, "succeeded")
  equal(second.outcome, "succeeded")
  equal(second.payload.duplicate, "true")
  equal(calls(), 1)
end)

test("request ID reuse with altered contents is rejected", function()
  local instance, _, calls = makeExecutor()
  instance:handle(request("req-conflict", "turn_right"))
  local reply = instance:handle(request("req-conflict", "turn_left"))
  equal(reply.outcome, "rejected")
  equal(reply.payload.code, "request_id_conflict")
  equal(calls(), 1)
end)

test("full completed-result retention fails closed instead of evicting IDs", function()
  local instance, store, calls = makeExecutor({cache_size = 1})
  instance:handle(request("req-retained", "turn_right"))
  local reply = instance:handle(request("req-over-capacity", "turn_left"))
  equal(reply.outcome, "rejected")
  equal(reply.payload.code, "result_cache_full")
  equal(calls(), 1)
  equal(#store.peek().completed, 1)
end)

test("restart with prepared request records definite non-execution", function()
  local initial = state.default()
  local item = request("req-prepared", "move_forward")
  initial.mode = "in_flight"
  initial.in_flight = {
    request_id = item.request_id, fingerprint = item.fingerprint,
    deployment_id = item.deployment_id, operation = item.operation, phase = "prepared"
  }
  local instance, store, calls = makeExecutor({initial = initial})
  equal(instance.boot_classification, "not_started")
  equal(store.peek().mode, "ready")
  local reply = instance:handle(item)
  equal(reply.outcome, "failed")
  equal(reply.payload.code, "interrupted_before_execution")
  equal(calls(), 0)
end)

test("restart with executing request fails closed as ambiguous", function()
  local initial = state.default()
  local item = request("req-executing", "move_forward")
  initial.mode = "in_flight"
  initial.in_flight = {
    request_id = item.request_id, fingerprint = item.fingerprint,
    deployment_id = item.deployment_id, operation = item.operation, phase = "executing"
  }
  local instance, store, calls = makeExecutor({initial = initial})
  equal(instance.boot_classification, "ambiguous")
  equal(store.peek().mode, "recovery_required")
  equal(store.peek().pose.trusted, false)
  local reply = instance:handle(item)
  equal(reply.outcome, "recovery_required")
  equal(reply.payload.in_flight_request, "req-executing")
  equal(reply.payload.in_flight_phase, "executing")
  equal(calls(), 0)
end)

test("restart with completed request preserves duplicate suppression", function()
  local first, store, calls = makeExecutor()
  local item = request("req-restart-complete", "move_up")
  first:handle(item)
  local second = executor.new({
    store = store,
    perform = function() error("must not execute") end
  })
  local reply = second:handle(item)
  equal(reply.outcome, "succeeded")
  equal(reply.payload.duplicate, "true")
  equal(calls(), 1)
end)

test("persistence failures before execution never call the robot", function()
  for _, failurePoint in ipairs({1, 2}) do
    local store = state.memoryStore()
    store.fail_at = failurePoint
    local instance, _, calls = makeExecutor({store = store})
    local reply = instance:handle(request("req-presave-" .. failurePoint, "move_forward"))
    equal(reply.outcome, "rejected")
    equal(calls(), 0)
    equal(instance.snapshot.mode, "recovery_required")
  end
end)

test("completion persistence failure becomes ambiguous after one execution", function()
  local store = state.memoryStore()
  store.fail_at = 3
  local instance, _, calls = makeExecutor({store = store})
  local reply = instance:handle(request("req-postsave", "move_forward"))
  equal(reply.outcome, "recovery_required")
  equal(reply.payload.code, "completion_persistence_failed")
  equal(calls(), 1)
  equal(instance.snapshot.pose.trusted, false)
  local restarted = executor.new({store = store, perform = function() error("must not execute") end})
  equal(restarted.snapshot.mode, "recovery_required")
end)

test("robot exception leaves executing journal and untrusted pose", function()
  local instance, store, calls = makeExecutor({raise = true})
  local reply = instance:handle(request("req-exception", "turn_left"))
  equal(reply.outcome, "recovery_required")
  equal(reply.payload.code, "operation_exception")
  equal(calls(), 1)
  equal(store.peek().in_flight.phase, "executing")
  equal(store.peek().pose.trusted, false)
end)

test("invalid persisted state disables physical execution", function()
  local badStore = {
    load = function() return nil, "corrupt state" end,
    save = function() return nil, "unavailable" end
  }
  local calls = 0
  local instance = executor.new({
    store = badStore,
    perform = function() calls = calls + 1; return true end
  })
  local reply = instance:handle(request("req-corrupt", "move_forward"))
  equal(reply.outcome, "recovery_required")
  equal(reply.payload.code, "persistence_unavailable")
  equal(calls, 0)
end)

test("state codec rejects incomplete persisted data", function()
  local decoded, reason = state.decode("format=1&mode=ready")
  equal(decoded, nil)
  truthy(reason)
end)

local function makeEventQueue(events)
  return {
    pull = function()
      local value = table.remove(events, 1)
      if not value then return nil end
      return table.unpack(value)
    end
  }
end

local function modemEvent(sender, parts, localAddress)
  local value = {"modem_message", localAddress or controllerAddress, sender, 4242, 1}
  for _, part in ipairs(parts) do value[#value + 1] = part end
  return value
end

test("transport ignores wrong senders and stale replies then correlates", function()
  local stale = assert(protocol.buildReply({
    request_id = "stale-id", deployment_id = "-", operation = "status",
    outcome = "succeeded", payload = {code = "stale"}
  }))
  local correct = assert(protocol.buildReply({
    request_id = "active-id", deployment_id = "-", operation = "status",
    outcome = "succeeded", payload = {code = "status", message = "ready"}
  }))
  local sent
  local now = 0
  local client = transport.new({
    modem = {send = function(_, _, ...)
      sent = {...}
      return true
    end},
    event = makeEventQueue({
      modemEvent(controllerAddress, correct),
      modemEvent(robotAddress, stale),
      modemEvent(robotAddress, correct)
    }),
    computer = {uptime = function() now = now + 0.1; return now end},
    config = {
      controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5
    },
    request_id = function() return "active-id" end
  })
  local reply = client:sendRequest("status")
  equal(sent[1], protocol.MAGIC)
  equal(reply.certainty, "succeeded")
  equal(reply.code, "status")
  equal(reply.ignored_messages, 2)
end)

test("transport timeout reports unknown, never definite failure", function()
  local now = 0
  local client = transport.new({
    modem = {send = function() return true end},
    event = makeEventQueue({}),
    computer = {uptime = function() now = now + 0.1; return now end},
    config = {
      controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5
    },
    request_id = function() return "timeout-id" end
  })
  local reply = client:sendRequest("move_forward")
  equal(reply.certainty, "unknown")
  equal(reply.status, "timeout")
  equal(reply.code, "outcome_unknown")
end)

test("transport ignores a duplicate reply left over for the next request", function()
  local firstReply = assert(protocol.buildReply({
    request_id = "sequence-1", deployment_id = "-", operation = "status",
    outcome = "succeeded", payload = {code = "first"}
  }))
  local secondReply = assert(protocol.buildReply({
    request_id = "sequence-2", deployment_id = "-", operation = "status",
    outcome = "succeeded", payload = {code = "second"}
  }))
  local ids = {"sequence-1", "sequence-2"}
  local now = 0
  local client = transport.new({
    modem = {send = function() return true end},
    event = makeEventQueue({
      modemEvent(robotAddress, firstReply),
      modemEvent(robotAddress, firstReply),
      modemEvent(robotAddress, secondReply)
    }),
    computer = {uptime = function() now = now + 0.1; return now end},
    config = {
      controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5
    },
    request_id = function() return table.remove(ids, 1) end
  })
  equal(client:sendRequest("status").code, "first")
  local second = client:sendRequest("status")
  equal(second.code, "second")
  equal(second.ignored_messages, 1)
end)

test("transport converts a modem send exception into a definite local failure", function()
  local client = transport.new({
    modem = {send = function() error("injected modem error") end},
    event = makeEventQueue({}),
    computer = {uptime = function() return 0 end},
    config = {
      controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5
    },
    request_id = function() return "send-error-id" end
  })
  local reply = client:sendRequest("status")
  equal(reply.certainty, "failed")
  equal(reply.status, "send_failed")
end)

test("transport rejects bad local requests before sending", function()
  local sends = 0
  local client = transport.new({
    modem = {send = function() sends = sends + 1; return true end},
    event = makeEventQueue({}),
    computer = {uptime = function() return 0 end},
    config = {
      controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5
    },
    request_id = function() return "bad-local-id" end
  })
  local reply = client:sendRequest("dance")
  equal(reply.certainty, "failed")
  equal(reply.status, "local_rejection")
  equal(sends, 0)
end)

test("legacy and new protocol packets cannot share a command interpretation", function()
  local parsed = assert(legacy.parse("f", 3))
  equal(parsed.count, 3)
  equal(parsed.operation, "move_forward")
  local newPacket, reason = legacy.parse(protocol.MAGIC, 1)
  equal(newPacket, nil)
  equal(reason, "unknown command")
end)

local failures = 0
for _, item in ipairs(tests) do
  local ok, reason = pcall(item.callback)
  if ok then
    io.write("ok - ", item.name, "\n")
  else
    failures = failures + 1
    io.write("not ok - ", item.name, "\n  ", tostring(reason), "\n")
  end
end

io.write(string.format("\n%d tests, %d assertions, %d failures\n",
  #tests, assertions, failures))
if failures > 0 then os.exit(1) end
