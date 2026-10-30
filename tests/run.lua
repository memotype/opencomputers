-- Host-side Milestone 1 hardening tests. Run from the repository root with Lua 5.3.
package.path = table.concat({
  "./d4d31815-680c-4fb8-a846-ee3c6d49be69/lib/?.lua",
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
local epoch = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
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

local statusCounter = 0
local function request(id, operation, deployment)
  if operation == "status" and not id then
    statusCounter = statusCounter + 1
    id = "s:test-" .. statusCounter
  end
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

local function physical(sequence, operation, selectedEpoch)
  return request(assert(protocol.makePhysicalRequestId(selectedEpoch or epoch, sequence)),
    operation or "turn_right")
end

local function commissionedMemory(options)
  options = options or {}
  local store = state.memoryStore(nil, {recent_limit = options.recent_limit or 8,
    fail_compact = options.fail_compact})
  assert(store.commission(epoch, pose.new()))
  return store
end

local function makeExecutor(store, options)
  options = options or {}
  local calls = 0
  local instance = executor.new({
    store = store,
    recent_limit = options.recent_limit or 8,
    compact_records = options.compact_records or 128,
    compact_bytes = options.compact_bytes or 65536,
    perform = function(operation)
      calls = calls + 1
      if options.raise then error("injected robot exception") end
      if options.fail_operation then return false, "blocked" end
      return true, operation .. " complete"
    end,
    status_provider = function()
      return {energy = 100, capacity = 200, total_memory = 786432,
        free_memory = 524288}
    end
  })
  return instance, function() return calls end
end

-- Small in-memory OpenOS-like filesystem with operation-level fault injection.
local function virtualFilesystem()
  local v = {files = {}, directories = {["/"] = true, ["/state/"] = true},
    fault = nil, counts = {}}
  local function hit(operation)
    v.counts[operation] = (v.counts[operation] or 0) + 1
    if v.fault and v.fault.operation == operation
        and v.counts[operation] == (v.fault.at or 1) then
      return true, v.fault
    end
    return false
  end
  function v.setFault(operation, at, partial)
    v.fault = {operation = operation, at = at or 1, partial = partial}
    v.counts = {}
  end
  function v.clearFault() v.fault = nil; v.counts = {} end
  function v.exists(path) return v.files[path] ~= nil or v.directories[path] == true end
  function v.size(path) return v.files[path] and #v.files[path] or nil end
  function v.path() return "/state/" end
  function v.makeDirectory(path)
    local failed = hit("mkdir")
    if failed then return nil, "injected mkdir failure" end
    v.directories[path] = true
    return true
  end
  function v.remove(path)
    local failed = hit("remove")
    if failed then return nil, "injected remove failure" end
    v.files[path] = nil
    return true
  end
  function v.rename(from, to)
    local failed = hit("rename")
    if failed then return nil, "injected rename failure" end
    if v.files[from] == nil then return nil, "missing source" end
    if v.files[to] ~= nil then return nil, "destination exists" end
    v.files[to], v.files[from] = v.files[from], nil
    return true
  end
  function v.open(path, mode)
    local failed = hit("open")
    if failed then return nil, "injected open failure" end
    if mode == "r" and v.files[path] == nil then return nil, "missing file" end
    if mode == "w" then v.files[path] = "" end
    if mode == "a" and v.files[path] == nil then v.files[path] = "" end
    local position = 1
    return {
      write = function(_, text)
        local writeFailed, fault = hit("write")
        if writeFailed then
          if fault.partial then
            v.files[path] = v.files[path] .. text:sub(1, math.max(1, math.floor(#text / 2)))
          end
          return nil, "injected write failure"
        end
        v.files[path] = v.files[path] .. text
        return true
      end,
      flush = function()
        local flushFailed = hit("flush")
        if flushFailed then return nil, "injected flush failure" end
        return true
      end,
      read = function(_, format)
        local readFailed = hit("read")
        if readFailed then return nil, "injected read failure" end
        if format == "*a" then
          local value = v.files[path]:sub(position)
          position = #v.files[path] + 1
          return value
        end
        local content = v.files[path]
        if position > #content then return nil end
        local newline = content:find("\n", position, true)
        if newline then
          local value = content:sub(position, newline - 1)
          position = newline + 1
          return value
        end
        local value = content:sub(position)
        position = #content + 1
        return value
      end,
      close = function() return true end
    }
  end
  return v
end

local function journalStore(vfs, recentLimit)
  local clock = 0
  return state.journalStore("/state/robot.state", {
    filesystem = vfs,
    open = vfs.open,
    recent_limit = recentLimit or 8,
    timer = function() clock = clock + 0.001; return clock end
  })
end

local function commissionedFilesystem(recentLimit)
  local vfs = virtualFilesystem()
  local store = journalStore(vfs, recentLimit)
  assert(store.commission(epoch, pose.new()))
  return vfs, store
end

test("protocol enforces status and physical request namespaces", function()
  truthy(request(nil, "status"))
  truthy(physical(1, "move_forward"))
  local parts, reason = protocol.buildRequest({request_id = "ordinary-id",
    deployment_id = "-", recipient = robotAddress, operation = "status"})
  equal(parts, nil)
  contains(reason, "s: namespace")
  parts, reason = protocol.buildRequest({request_id = "s:not-physical",
    deployment_id = "-", recipient = robotAddress, operation = "move_forward"})
  equal(parts, nil)
  contains(reason, "execution epoch")
end)

test("protocol rejects malformed, wrong-version, wrong-recipient, and arguments", function()
  local _, parts = request(nil, "status")
  local cases = {
    {2, 99, "unsupported_version"}, {3, "reply", "unexpected_message_type"},
    {6, controllerAddress, "incorrect_recipient"},
    {7, "dance", "unsupported_operation"}, {8, "steps=2", "invalid_arguments"}
  }
  for _, item in ipairs(cases) do
    local copy = {table.unpack(parts)}
    copy[item[1]] = item[2]
    local parsed, code = protocol.parseRequest(copy, robotAddress)
    equal(parsed, nil)
    equal(code, item[3])
  end
end)

test("field decoding is deterministic, bounded, and rejects malformed escapes", function()
  equal(assert(protocol.encodeFields({z = "two words", a = 1})), "a=1&z=two%20words")
  equal(assert(protocol.decodeFields("z=two%20words")).z, "two words")
  local decoded = protocol.decodeFields("bad=%Q0")
  equal(decoded, nil)
  local reply, reason = protocol.buildReply({request_id = "s:large", deployment_id = "-",
    operation = "status", outcome = "succeeded", payload = {message = string.rep("x", 5000)}})
  equal(reply, nil)
  equal(reason, "result payload is too large")
end)

test("pose math covers headings, inverses, vertical movement, and ambiguity", function()
  local current = pose.new()
  for _, heading in ipairs({"east", "south", "west", "north"}) do
    current = assert(pose.apply(current, "turn_right"))
    equal(current.heading, heading)
  end
  local start = pose.new(4, 2, 7, "west")
  local moved = assert(pose.apply(start, "move_forward"))
  equal(moved.x, 3)
  truthy(pose.equal(assert(pose.apply(moved, "move_backward")), start))
  equal(assert(pose.apply(start, "move_up")).y, 3)
  truthy(pose.equal(pose.afterResult(start, "move_forward", false), start))
  local unknown = pose.unknown(start, "ambiguous")
  equal(unknown.trusted, false)
  equal(pose.apply(unknown, "move_forward"), nil)
end)

test("fresh journal is untrusted and requires explicit commissioning", function()
  local store = state.memoryStore()
  local instance, calls = makeExecutor(store)
  equal(instance.snapshot.mode, "recovery_required")
  equal(instance.snapshot.pose.trusted, false)
  equal(instance.snapshot.epoch, "")
  local reply = instance:handle(physical(1, "move_forward"))
  equal(reply.outcome, "recovery_required")
  equal(reply.payload.code, "commissioning_required")
  equal(calls(), 0)
end)

test("commissioning establishes origin and a new execution epoch", function()
  local store = state.memoryStore()
  local snapshot = assert(store.commission(epoch, pose.new()))
  equal(snapshot.mode, "ready")
  equal(snapshot.pose.trusted, true)
  equal(snapshot.epoch, epoch)
  equal(snapshot.high_water, 0)
end)

test("one thousand status requests do not write or consume physical retention", function()
  local store = commissionedMemory({recent_limit = 4})
  local instance, calls = makeExecutor(store, {recent_limit = 4})
  local before = store.peek()
  for index = 1, 1000 do
    local reply = instance:handle(request("s:poll-" .. index, "status"))
    equal(reply.outcome, "succeeded")
  end
  local after = store.peek()
  equal(#after.recent, 0)
  equal(after.journal.records, before.journal.records)
  equal(after.journal.bytes, before.journal.bytes)
  equal(calls(), 0)
  equal(instance:handle(physical(1)).outcome, "succeeded")
end)

test("status remains available while journal is recovery-required", function()
  local instance = makeExecutor(state.memoryStore())
  local reply = instance:handle(request(nil, "status"))
  equal(reply.outcome, "succeeded")
  equal(reply.payload.mode, "recovery_required")
  equal(reply.payload.journal_health, "uninitialized")
end)

test("completed duplicate returns cached output without a second physical call", function()
  local store = commissionedMemory()
  local instance, calls = makeExecutor(store)
  local item = physical(1, "move_forward")
  equal(instance:handle(item).outcome, "succeeded")
  local duplicate = instance:handle(item)
  equal(duplicate.outcome, "succeeded")
  equal(duplicate.payload.duplicate, "true")
  equal(calls(), 1)
end)

test("sequence collision, gap, and stale epoch are rejected", function()
  local store = commissionedMemory()
  local instance, calls = makeExecutor(store)
  instance:handle(physical(1, "turn_right"))
  equal(instance:handle(physical(1, "turn_left")).payload.code, "request_id_conflict")
  equal(instance:handle(physical(3, "turn_left")).payload.code, "sequence_gap")
  local oldEpoch = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  equal(instance:handle(physical(2, "turn_left", oldEpoch)).payload.code, "stale_epoch")
  equal(calls(), 1)
end)

test("bounded recent results retire safely while monotonic missions continue", function()
  local store = commissionedMemory({recent_limit = 4})
  local instance, calls = makeExecutor(store, {recent_limit = 4,
    compact_records = 25, compact_bytes = 1000000})
  for sequence = 1, 1000 do
    equal(instance:handle(physical(sequence, "turn_right")).outcome, "succeeded")
  end
  equal(calls(), 1000)
  equal(instance.snapshot.high_water, 1000)
  equal(#instance.snapshot.recent, 4)
  truthy(store.compact_count > 0)
  local retired = instance:handle(physical(1, "turn_right"))
  equal(retired.outcome, "rejected")
  equal(retired.payload.code, "retired_request")
  equal(calls(), 1000)
end)

test("new epoch after explicit recovery permanently rejects old packets", function()
  local store = commissionedMemory()
  local first = makeExecutor(store)
  first:handle(physical(1))
  local newEpoch = "cccccccc-cccc-cccc-cccc-cccccccccccc"
  assert(store.commission(newEpoch, pose.new()))
  local second, calls = makeExecutor(store)
  local stale = second:handle(physical(1, "turn_right", epoch))
  equal(stale.payload.code, "stale_epoch")
  equal(calls(), 0)
  equal(second:handle(physical(1, "turn_right", newEpoch)).outcome, "succeeded")
end)

test("restart after prepared records definite non-execution", function()
  local vfs, store = commissionedFilesystem()
  local snapshot = assert(store.load())
  local item = physical(1, "move_forward")
  assert(store.append(snapshot, {kind = "prepared", epoch = epoch, sequence = 1,
    request_id = item.request_id, fingerprint = item.fingerprint,
    deployment_id = item.deployment_id, operation = item.operation}))
  local restarted, calls = makeExecutor(journalStore(vfs))
  equal(restarted.boot_classification, "not_started")
  equal(restarted.snapshot.mode, "ready")
  equal(restarted:handle(item).outcome, "failed")
  equal(calls(), 0)
end)

test("restart after executing is ambiguous and never replays", function()
  local vfs, store = commissionedFilesystem()
  local snapshot = assert(store.load())
  local item = physical(1, "move_forward")
  assert(store.append(snapshot, {kind = "prepared", epoch = epoch, sequence = 1,
    request_id = item.request_id, fingerprint = item.fingerprint,
    deployment_id = item.deployment_id, operation = item.operation}))
  assert(store.append(snapshot, {kind = "executing", sequence = 1,
    request_id = item.request_id}))
  local restarted, calls = makeExecutor(journalStore(vfs))
  equal(restarted.snapshot.mode, "recovery_required")
  equal(restarted.snapshot.pose.trusted, false)
  equal(restarted:handle(item).outcome, "recovery_required")
  equal(calls(), 0)
end)

test("completed result survives daemon restart and suppresses duplicate", function()
  local vfs, store = commissionedFilesystem()
  local first, firstCalls = makeExecutor(store)
  local item = physical(1, "move_up")
  equal(first:handle(item).outcome, "succeeded")
  local second, secondCalls = makeExecutor(journalStore(vfs))
  equal(second:handle(item).payload.duplicate, "true")
  equal(firstCalls(), 1)
  equal(secondCalls(), 0)
  equal(second.snapshot.pose.y, 1)
end)

test("operation exception leaves executing journal and recovery state", function()
  local vfs, store = commissionedFilesystem()
  local instance, calls = makeExecutor(store, {raise = true})
  equal(instance:handle(physical(1)).outcome, "recovery_required")
  equal(calls(), 1)
  local restarted, restartCalls = makeExecutor(journalStore(vfs))
  equal(restarted.snapshot.mode, "recovery_required")
  equal(restartCalls(), 0)
end)

test("append open, write, partial-write, and flush failures fail closed", function()
  for _, fault in ipairs({
    {"open", false}, {"write", false}, {"write", true}, {"flush", false}
  }) do
    local vfs, store = commissionedFilesystem()
    vfs.setFault(fault[1], 1, fault[2])
    local instance, calls = makeExecutor(store)
    local reply = instance:handle(physical(1, "move_forward"))
    equal(reply.outcome, "rejected")
    equal(calls(), 0)
    vfs.clearFault()
    local restarted, restartCalls = makeExecutor(journalStore(vfs))
    if fault[1] == "open" or (fault[1] == "write" and not fault[2]) then
      equal(restarted.snapshot.mode, "ready")
    else
      equal(restarted.snapshot.mode, "recovery_required")
    end
    equal(restartCalls(), 0)
  end
end)

test("completion write interruption never permits a second execution", function()
  for _, partial in ipairs({false, true}) do
    local vfs, store = commissionedFilesystem()
    vfs.setFault("write", 3, partial)
    local instance, calls = makeExecutor(store)
    equal(instance:handle(physical(1, "move_forward")).outcome, "recovery_required")
    equal(calls(), 1)
    vfs.clearFault()
    local restarted, restartCalls = makeExecutor(journalStore(vfs))
    equal(restarted:handle(physical(1, "move_forward")).outcome, "recovery_required")
    equal(restartCalls(), 0)
  end
end)

test("missing or corrupted primary never promotes an old journal", function()
  local vfs = commissionedFilesystem()
  local primary = "/state/robot.state"
  local original = vfs.files[primary]
  vfs.files[primary .. ".old"] = original
  vfs.files[primary] = nil
  local missing, missingCalls = makeExecutor(journalStore(vfs))
  equal(missing.snapshot.journal.health, "uncertain_artifacts")
  equal(missing:handle(physical(1)).outcome, "recovery_required")
  equal(missingCalls(), 0)

  local vfs2 = commissionedFilesystem()
  vfs2.files[primary] = "corrupt\n"
  local corrupt, corruptCalls = makeExecutor(journalStore(vfs2))
  equal(corrupt.snapshot.journal.health, "corrupt")
  equal(corrupt:handle(physical(1)).outcome, "recovery_required")
  equal(corruptCalls(), 0)
end)

test("new, old, or switch artifacts always force explicit recovery", function()
  for _, suffixes in ipairs({{".new"}, {".old"}, {".switch"}, {".new", ".old"}}) do
    local vfs = commissionedFilesystem()
    for _, suffix in ipairs(suffixes) do
      vfs.files["/state/robot.state" .. suffix] = "stale"
    end
    local instance, calls = makeExecutor(journalStore(vfs))
    equal(instance.snapshot.journal.health, "uncertain_artifacts")
    equal(instance:handle(physical(1)).outcome, "recovery_required")
    equal(instance:handle(request(nil, "status")).outcome, "succeeded")
    equal(calls(), 0)
  end
end)

test("all compaction replacement failures reconstruct fail-closed", function()
  local cases = {
    {"open", 1}, {"write", 1}, {"flush", 1}, {"read", 1},
    {"rename", 1}, {"rename", 2}, {"remove", 1}, {"remove", 2}
  }
  for _, fault in ipairs(cases) do
    local vfs, store = commissionedFilesystem(4)
    local instance = makeExecutor(store, {recent_limit = 4,
      compact_records = 1000, compact_bytes = 1000000})
    instance:handle(physical(1))
    vfs.setFault(fault[1], fault[2])
    local compacted = store.compact(instance.snapshot)
    equal(compacted, nil, fault[1] .. "/" .. fault[2])
    vfs.clearFault()
    local restarted, calls = makeExecutor(journalStore(vfs, 4))
    equal(restarted.snapshot.mode, "recovery_required")
    equal(restarted:handle(physical(1)).outcome, "recovery_required")
    equal(calls(), 0)
  end
end)

test("successful compaction preserves high water and bounded duplicate cache", function()
  local vfs, store = commissionedFilesystem(3)
  local instance, calls = makeExecutor(store, {recent_limit = 3,
    compact_records = 1000, compact_bytes = 1000000})
  for sequence = 1, 10 do instance:handle(physical(sequence)) end
  truthy(store.compact(instance.snapshot))
  local restarted, restartCalls = makeExecutor(journalStore(vfs, 3), {recent_limit = 3})
  equal(restarted.snapshot.high_water, 10)
  equal(#restarted.snapshot.recent, 3)
  equal(restarted:handle(physical(10)).payload.duplicate, "true")
  equal(restarted:handle(physical(1)).payload.code, "retired_request")
  equal(calls(), 10)
  equal(restartCalls(), 0)
end)

test("manual legacy movement invalidates pose without sharing protocol dispatch", function()
  local store = commissionedMemory()
  local instance = makeExecutor(store)
  truthy(instance:beginManualRecovery())
  equal(instance.snapshot.mode, "recovery_required")
  equal(instance.snapshot.pose.trusted, false)
  local parsed = assert(legacy.parse("f", 3))
  equal(parsed.count, 3)
  equal(parsed.operation, "move_forward")
  equal(legacy.parse(protocol.MAGIC, 1), nil)
end)

local function eventQueue(events)
  return {pull = function()
    local value = table.remove(events, 1)
    if not value then return nil end
    return table.unpack(value)
  end}
end
local function modemEvent(sender, parts)
  local value = {"modem_message", controllerAddress, sender, 4242, 1}
  for _, part in ipairs(parts) do value[#value + 1] = part end
  return value
end

test("transport correlates status and reports timeout as unknown", function()
  local replyParts = assert(protocol.buildReply({request_id = "s:active",
    deployment_id = "-", operation = "status", outcome = "succeeded",
    payload = {code = "status"}}))
  local now = 0
  local client = transport.new({
    modem = {send = function() return true end},
    event = eventQueue({modemEvent(robotAddress, replyParts)}),
    computer = {uptime = function() now = now + 0.1; return now end},
    config = {controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5},
    request_id = function() return "active" end
  })
  equal(client:sendRequest("status").certainty, "succeeded")

  local timeoutClient = transport.new({
    modem = {send = function() return true end}, event = eventQueue({}),
    computer = {uptime = function() now = now + 0.1; return now end},
    config = {controller_address = controllerAddress, robot_address = robotAddress,
      port = 4242, timeout = 5}, request_id = function() return "timeout" end
  })
  local timeout = timeoutClient:sendRequest("status")
  equal(timeout.certainty, "unknown")
  equal(timeout.code, "outcome_unknown")
  equal(timeoutClient:sendRequest("move_forward").certainty, "failed")
end)

test("journal scaling stays bounded across representative workloads", function()
  local counts = {1, 10, 25, 50, 100, 256, 500, 1000}
  for _, count in ipairs(counts) do
    local store = commissionedMemory({recent_limit = 8})
    local instance, calls = makeExecutor(store, {recent_limit = 8,
      compact_records = 64, compact_bytes = 32768})
    for sequence = 1, count do instance:handle(physical(sequence)) end
    truthy(#instance.snapshot.recent <= 8)
    truthy(instance.snapshot.journal.records < 64)
    truthy(instance.snapshot.journal.bytes < 32768)
    equal(instance.snapshot.high_water, count)
    equal(calls(), count)
  end
end)

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
