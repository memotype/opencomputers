-- Host-side Milestone 1 hardening tests. Run from the repository root with Lua 5.3.
package.path = table.concat({
  "./machines/robot/lib/?.lua",
  "./machines/controller/lib/?.lua",
  package.path
}, ";")

local executor = require("ocia.executor")
local farm = require("ocia.farm")
local farming = require("ocia.farming")
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
local function request(id, operation, deployment, arguments)
  if operation == "status" and not id then
    statusCounter = statusCounter + 1
    id = "s:test-" .. statusCounter
  end
  local parts, reason = protocol.buildRequest({
    request_id = id,
    deployment_id = deployment or "-",
    recipient = robotAddress,
    operation = operation,
    arguments = arguments or {}
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
      close = function()
        local closeFailed = hit("close")
        if closeFailed then error("injected close failure") end
        return true
      end
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

test("farming operations validate their wire arguments", function()
  truthy(physical(1, "till_down"))
  truthy(physical(2, "till_forward_down"))
  local planted = request(assert(protocol.makePhysicalRequestId(epoch, 2)),
    "plant_down", "-", {slot = 3})
  equal(planted.arguments.slot, "3")
  local forward = request(assert(protocol.makePhysicalRequestId(epoch, 3)),
    "plant_forward_down", "-", {slot = 4})
  equal(forward.arguments.slot, "4")

  local parts, reason = protocol.buildRequest({
    request_id = assert(protocol.makePhysicalRequestId(epoch, 3)),
    deployment_id = "-", recipient = robotAddress,
    operation = "plant_down", arguments = {slot = 17}
  })
  equal(parts, nil)
  contains(reason, "between 1 and 16")
  parts, reason = protocol.buildRequest({
    request_id = assert(protocol.makePhysicalRequestId(epoch, 3)),
    deployment_id = "-", recipient = robotAddress,
    operation = "till_down", arguments = {slot = 1}
  })
  equal(parts, nil)
  contains(reason, "does not accept arguments")
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

test("stationary farming operations preserve trusted pose", function()
  local start = pose.new(4, 2, -7, "west")
  truthy(pose.equal(assert(pose.apply(start, "till_down")), start))
  truthy(pose.equal(assert(pose.apply(start, "till_forward_down")), start))
  truthy(pose.equal(assert(pose.apply(start, "plant_down")), start))
  truthy(pose.equal(assert(pose.apply(start, "plant_forward_down")), start))
end)

test("farming hardware routes forward-down tilling and planting with verified Potatoes", function()
  local usedFace, placedFace, selected, count, useDownCalls = nil, nil, nil, 2, 0
  local robot = {
    use = function(face) usedFace = face; return true, "item_placed" end,
    useDown = function() useDownCalls = useDownCalls + 1; return false, "blocked" end,
    select = function(slot) selected = slot end,
    count = function() return count end,
    place = function(face) placedFace = face; count = count - 1; return true, nil end,
    placeDown = function() return true end
  }
  local inventory = {getStackInInternalSlot = function(slot)
    equal(slot, 3)
    return {name = "minecraft:potato", size = count}
  end}
  local actions = farming.new(robot, {down = 42}, inventory)
  local ok, detail, fields = actions.till_forward_down()
  equal(ok, true)
  equal(detail, "item_placed")
  equal(usedFace, 42)
  equal(useDownCalls, 0)
  equal(fields.interaction_geometry, "forward_down")
  equal(actions.till_down(), false)
  equal(useDownCalls, 1)

  ok, detail, fields = actions.plant_forward_down({slot = "3"})
  equal(ok, true)
  equal(detail, "selected item placed forward and downward")
  equal(selected, 3)
  equal(placedFace, 42)
  equal(fields.item_name, "minecraft:potato")
  equal(fields.items_before, 2)
  equal(fields.items_after, 1)
  equal(fields.item_consumed, "true")

  local wrong = farming.new(robot, {down = 42}, {
    getStackInInternalSlot = function() return {name = "minecraft:carrot"} end
  })
  equal(wrong.plant_forward_down({slot = "3"}), false)
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

test("forward planting requests are journaled, deduplicated, and fingerprint their slot", function()
  local store = commissionedMemory()
  local calls, observedSlot = 0
  local instance = executor.new({
    store = store,
    perform = function(operation, arguments)
      calls = calls + 1
      observedSlot = arguments.slot
      return true, "potato placed", {item_consumed = "true", selected_slot = arguments.slot}
    end
  })
  local id = assert(protocol.makePhysicalRequestId(epoch, 1))
  local item = request(id, "plant_forward_down", "-", {slot = 2})
  local first = instance:handle(item)
  equal(first.outcome, "succeeded")
  equal(first.payload.item_consumed, "true")
  equal(observedSlot, "2")
  equal(instance.snapshot.high_water, 1)
  equal(instance:handle(item).payload.duplicate, "true")
  local conflict = request(id, "plant_forward_down", "-", {slot = 3})
  equal(instance:handle(conflict).payload.code, "request_id_conflict")
  equal(calls, 1)
end)

test("failed farming actions are definitive completed failures", function()
  local store = commissionedMemory()
  local instance, calls = makeExecutor(store, {fail_operation = true})
  local reply = instance:handle(request(assert(protocol.makePhysicalRequestId(epoch, 1)),
    "plant_forward_down", "-", {slot = 1}))
  equal(reply.outcome, "failed")
  equal(reply.payload.code, "operation_failed")
  equal(instance.snapshot.high_water, 1)
  equal(instance.snapshot.pose.trusted, true)
  equal(calls(), 1)
end)

test("legacy till_down completed results remain replay-compatible", function()
  local store = commissionedMemory()
  local first, firstCalls = makeExecutor(store)
  local item = physical(1, "till_down")
  equal(first:handle(item).outcome, "succeeded")
  equal(firstCalls(), 1)
  local restarted, restartCalls = makeExecutor(store)
  local duplicate = restarted:handle(item)
  equal(duplicate.outcome, "succeeded")
  equal(duplicate.payload.duplicate, "true")
  equal(restartCalls(), 0)
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
  local conflict = restarted:handle(physical(1, "turn_left"))
  equal(conflict.outcome, "rejected")
  equal(conflict.payload.code, "request_id_conflict")
  local resolved = restarted:handle(item)
  equal(resolved.outcome, "failed")
  equal(resolved.payload.code, "interrupted_before_execution")
  equal(resolved.payload.physical_outcome, "not_started")
  equal(resolved.payload.duplicate, "true")
  equal(restarted.snapshot.pose.trusted, true)
  equal(calls(), 0)
end)

test("prepared recovery persistence failure remains non-executable", function()
  local vfs, store = commissionedFilesystem()
  local snapshot = assert(store.load())
  local item = physical(1, "move_forward")
  assert(store.append(snapshot, {kind = "prepared", epoch = epoch, sequence = 1,
    request_id = item.request_id, fingerprint = item.fingerprint,
    deployment_id = item.deployment_id, operation = item.operation}))
  vfs.setFault("write", 1, false)
  local restarted, calls = makeExecutor(journalStore(vfs))
  vfs.clearFault()
  equal(restarted.snapshot.mode, "recovery_required")
  equal(restarted.snapshot.pose.trusted, false)
  local retry = restarted:handle(item)
  equal(retry.outcome, "recovery_required")
  equal(retry.payload.code, "prepared_resolution_unpersisted")
  equal(retry.payload.physical_outcome, "not_started")
  local conflict = restarted:handle(physical(1, "turn_left"))
  equal(conflict.outcome, "rejected")
  equal(conflict.payload.code, "request_id_conflict")
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
  equal(restarted.snapshot.pose.x, 0)
  equal(restarted.snapshot.pose.z, 0)
  local retry = restarted:handle(item)
  equal(retry.outcome, "recovery_required")
  equal(retry.payload.code, "physical_outcome_unknown")
  equal(retry.payload.physical_outcome, "unknown")
  local duplicate = restarted:handle(item)
  equal(duplicate.outcome, "recovery_required")
  equal(duplicate.payload.code, "physical_outcome_unknown")
  local conflict = restarted:handle(physical(1, "turn_left"))
  equal(conflict.outcome, "rejected")
  equal(conflict.payload.code, "request_id_conflict")
  equal(restarted.snapshot.pose.trusted, false)
  equal(restarted.snapshot.pose.x, 0)
  equal(restarted.snapshot.pose.z, 0)
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
    {"open", false, "ready"}, {"write", false, "ready"},
    {"write", true, "recovery_required"}, {"flush", false, "ready"},
    {"close", false, "ready"}
  }) do
    local vfs, store = commissionedFilesystem()
    local instance, calls = makeExecutor(store)
    vfs.setFault(fault[1], 1, fault[2])
    local reply = instance:handle(physical(1, "move_forward"))
    equal(reply.outcome, "rejected")
    equal(reply.payload.code, "persistence_failed_before_execution")
    equal(calls(), 0)
    vfs.clearFault()
    local restarted, restartCalls = makeExecutor(journalStore(vfs))
    equal(restarted.snapshot.mode, fault[3], fault[1] .. "/" .. tostring(fault[2]))
    equal(restartCalls(), 0)
  end
end)

test("close exceptions at execution boundaries fail closed", function()
  local cases = {
    {1, 0, "journal_untrusted", "failed", "interrupted_before_execution"},
    {2, 0, "prepared_resolution_unpersisted", "recovery_required",
      "physical_outcome_unknown"},
    {3, 1, "physical_outcome_unknown", "succeeded", "operation_succeeded"}
  }
  for _, item in ipairs(cases) do
    local vfs, store = commissionedFilesystem()
    local instance, calls = makeExecutor(store)
    vfs.setFault("close", item[1])
    local reply = instance:handle(physical(1, "move_forward"))
    if item[1] < 3 then
      equal(reply.outcome, "rejected")
      equal(reply.payload.code, "persistence_failed_before_execution")
    else
      equal(reply.outcome, "recovery_required")
      equal(reply.payload.code, "completion_persistence_failed")
    end
    equal(calls(), item[2])
    equal(instance.snapshot.journal.health, "uncertain_write")
    local blocked = instance:handle(physical(1, "move_forward"))
    equal(blocked.outcome, "recovery_required")
    equal(blocked.payload.code, item[3])
    equal(calls(), item[2])

    vfs.clearFault()
    local restarted, restartCalls = makeExecutor(journalStore(vfs))
    local retried = restarted:handle(physical(1, "move_forward"))
    equal(retried.outcome, item[4])
    equal(retried.payload.code, item[5])
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
    local retry = restarted:handle(physical(1, "move_forward"))
    equal(retry.outcome, "recovery_required")
    if not partial then
      equal(retry.payload.code, "physical_outcome_unknown")
      equal(retry.payload.physical_outcome, "unknown")
    end
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

test("compaction failures preserve a safe primary or reconstruct fail-closed", function()
  local cases = {
    {"open", 1}, {"write", 1}, {"flush", 1}, {"close", 1}, {"close", 4},
    {"read", 1},
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
    if fault[1] == "open" and fault[2] == 1 then
      equal(restarted.snapshot.mode, "ready")
      local duplicate = restarted:handle(physical(1))
      equal(duplicate.outcome, "succeeded")
      equal(duplicate.payload.duplicate, "true")
    else
      equal(restarted.snapshot.mode, "recovery_required")
      equal(restarted:handle(physical(1)).outcome, "recovery_required")
    end
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

test("manual recovery preserves ambiguous execution identity across restart", function()
  local vfs, store = commissionedFilesystem()
  local snapshot = assert(store.load())
  local item = physical(1, "move_forward")
  assert(store.append(snapshot, {kind = "prepared", epoch = epoch, sequence = 1,
    request_id = item.request_id, fingerprint = item.fingerprint,
    deployment_id = item.deployment_id, operation = item.operation}))
  assert(store.append(snapshot, {kind = "executing", sequence = 1,
    request_id = item.request_id}))

  local interrupted, interruptedCalls = makeExecutor(journalStore(vfs))
  equal(interrupted.snapshot.mode, "recovery_required")
  equal(interrupted:handle(item).payload.code, "physical_outcome_unknown")
  equal(interruptedCalls(), 0)
  truthy(interrupted:beginManualRecovery())
  equal(interrupted.snapshot.pose.trusted, false)

  local restartedStore = journalStore(vfs)
  local restarted, restartCalls = makeExecutor(restartedStore)
  local retry = restarted:handle(item)
  equal(retry.outcome, "recovery_required")
  equal(retry.payload.code, "physical_outcome_unknown")
  equal(retry.payload.physical_outcome, "unknown")
  equal(restarted.snapshot.pose.trusted, false)
  local conflict = restarted:handle(physical(1, "turn_left"))
  equal(conflict.outcome, "rejected")
  equal(conflict.payload.code, "request_id_conflict")
  equal(restartCalls(), 0)

  local newEpoch = "dddddddd-dddd-dddd-dddd-dddddddddddd"
  truthy(restartedStore.commission(newEpoch, pose.new()))
  local recommissioned, commissionedCalls = makeExecutor(journalStore(vfs))
  local stale = recommissioned:handle(item)
  equal(stale.outcome, "rejected")
  equal(stale.payload.code, "stale_epoch")
  equal(commissionedCalls(), 0)
  equal(recommissioned:handle(physical(1, "turn_right", newEpoch)).outcome,
    "succeeded")
end)

test("manual recovery preserves ordinary bounded result retirement", function()
  local vfs, store = commissionedFilesystem(1)
  local instance, calls = makeExecutor(store, {recent_limit = 1})
  equal(instance:handle(physical(1, "turn_right")).outcome, "succeeded")
  equal(instance:handle(physical(2, "turn_right")).outcome, "succeeded")
  truthy(instance:beginManualRecovery())
  local restarted, restartCalls = makeExecutor(journalStore(vfs, 1),
    {recent_limit = 1})
  local retired = restarted:handle(physical(1, "turn_right"))
  equal(retired.outcome, "rejected")
  equal(retired.payload.code, "retired_request")
  equal(restarted.snapshot.pose.trusted, false)
  equal(calls(), 2)
  equal(restartCalls(), 0)
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

local function readyFarmStatus()
  local value = pose.toFields(pose.new(10, 4, -3, "north"))
  value.mode, value.epoch, value.high_water = "ready", epoch, 0
  return value
end

local localVectors = {
  north = {x = 0, z = 1}, east = {x = 1, z = 0},
  south = {x = 0, z = -1}, west = {x = -1, z = 0}
}
local localTurns = {
  north = {left = "west", right = "east"},
  east = {left = "north", right = "south"},
  south = {left = "east", right = "west"},
  west = {left = "south", right = "north"}
}

local function validateFarmGeometry(plan)
  local x, z, heading = 0, -1, "north"
  local tilled, planted = {}, {}
  local function key(px, pz) return px .. "," .. pz end
  local allowed = {[key(0, -1)] = true,
    [key(plan.local_end.x, plan.local_end.z)] = true}
  for _, target in ipairs(plan.cells) do allowed[key(target.x, target.z)] = true end
  for _, step in ipairs(plan.steps) do
    if step.operation == "turn_left" or step.operation == "turn_right" then
      heading = localTurns[heading][step.operation == "turn_left" and "left" or "right"]
    elseif step.operation == "move_forward" or step.operation == "move_backward" then
      local vector = localVectors[heading]
      local sign = step.operation == "move_forward" and 1 or -1
      local nx, nz = x + vector.x * sign, z + vector.z * sign
      equal(planted[key(nx, nz)], nil, "route entered a planted crop cell")
      equal(allowed[key(nx, nz)], true, "route left its documented clearance")
      x, z = nx, nz
    elseif step.operation == "till_forward_down"
        or step.operation == "plant_forward_down" then
      local vector = localVectors[heading]
      local tx, tz = x + vector.x, z + vector.z
      equal(step.cell.x, tx, "farming action targeted the wrong x coordinate")
      equal(step.cell.z, tz, "farming action targeted the wrong z coordinate")
      local targetKey = key(tx, tz)
      if step.operation == "till_forward_down" then
        equal(tilled[targetKey], nil, "cell was tilled more than once")
        tilled[targetKey] = true
      else
        equal(tilled[targetKey], true, "cell was planted before tilling")
        equal(planted[targetKey], nil, "cell was planted more than once")
        planted[targetKey] = true
      end
    else
      error("unexpected farm route operation " .. tostring(step.operation))
    end
  end
  return x, z, heading, tilled, planted
end

test("farm blueprints generate deterministic one-pass adjacent routes", function()
  local previewCalls = 0
  local single = assert(farm.plan("single", 4))
  equal(#single.steps, 2)
  equal(single.steps[1].operation, "till_forward_down")
  equal(single.steps[2].operation, "plant_forward_down")
  equal(single.steps[2].arguments.slot, 4)
  equal(single.till_count, 1)
  equal(single.plant_count, 1)
  equal(previewCalls, 0, "planning must not send physical requests")
  local start = assert(farm.poseFromStatus(readyFarmStatus()))
  local target = farm.targetForCell(start, single.cells[1])
  equal(target.x, 10)
  equal(target.y, 3)
  equal(target.z, -4)
  truthy(pose.equal(assert(farm.expectedEnd(single, start)), start))

  local plant = assert(farm.plan("single-plant", 4))
  equal(plant.till_count, 0)
  equal(plant.plant_count, 1)
  equal(#plant.steps, 1)
  equal(plant.steps[1].operation, "plant_forward_down")
  equal(plant.steps[1].arguments.slot, 4)
  local plantFinish = assert(farm.expectedEnd(plant, start))
  equal(plantFinish.x, start.x)
  equal(plantFinish.y, start.y)
  equal(plantFinish.z, start.z)
  equal(plantFinish.heading, start.heading)

  local pair = assert(farm.plan("pair", 1))
  local pairX, pairZ, pairHeading, _, pairPlanted = validateFarmGeometry(pair)
  equal(pairX, 1)
  equal(pairZ, -1)
  equal(pairHeading, "north")
  equal(pairPlanted["0,0"], true)
  equal(pairPlanted["1,0"], true)

end)

test("rectangular patches satisfy reverse-serpentine geometry invariants", function()
  local dimensions = {{1, 1}, {1, 3}, {3, 1}, {2, 2}, {2, 3},
    {3, 2}, {3, 3}, {3, 4}, {4, 3}, {5, 5}}
  for _, size in ipairs(dimensions) do
    local width, depth = size[1], size[2]
    local plan = assert(farm.plan("patch", 1, width, depth))
    equal(plan.width, width)
    equal(plan.depth, depth)
    equal(#plan.cells, width * depth)
    equal(plan.till_count, width * depth)
    equal(plan.plant_count, width * depth)
    local endX, endZ, endHeading, tilled, planted = validateFarmGeometry(plan)
    equal(endX, plan.local_end.x)
    equal(endZ, plan.local_end.z)
    equal(endHeading, plan.local_end.heading)
    local seen = {}
    for _, target in ipairs(plan.cells) do
      local targetKey = target.x .. "," .. target.z
      equal(seen[targetKey], nil, "serpentine repeated a target")
      seen[targetKey] = true
      equal(tilled[targetKey], true)
      equal(planted[targetKey], true)
    end
    for _, step in ipairs(plan.steps) do
      truthy(step.operation ~= "move_up" and step.operation ~= "move_down",
        "flat rectangular route must not change elevation")
    end
  end

  equal(farm.plan("patch", 1, 0, 3), nil)
  equal(farm.plan("patch", 1, 3, 17), nil)
  equal(farm.plan("patch", 1, 9, 8), nil)
end)

test("3x3 patch matches the 34-command acceptance fixture", function()
  local plan = assert(farm.plan("patch", 1, 3, 3))
  local expectedCells = {{0, 0}, {0, 1}, {0, 2}, {1, 2}, {1, 1},
    {1, 0}, {2, 0}, {2, 1}, {2, 2}}
  for index, expected in ipairs(expectedCells) do
    equal(plan.cells[index].x, expected[1])
    equal(plan.cells[index].z, expected[2])
  end
  local expectedOperations = {
    "move_forward", "move_forward", "turn_right", "turn_right",
    "till_forward_down", "plant_forward_down", "move_backward",
    "till_forward_down", "plant_forward_down", "turn_right", "move_backward",
    "till_forward_down", "plant_forward_down", "turn_right", "move_backward",
    "till_forward_down", "plant_forward_down", "move_backward",
    "till_forward_down", "plant_forward_down", "turn_left", "move_backward",
    "till_forward_down", "plant_forward_down", "turn_left", "move_backward",
    "till_forward_down", "plant_forward_down", "move_backward",
    "till_forward_down", "plant_forward_down", "move_backward",
    "till_forward_down", "plant_forward_down"
  }
  equal(#plan.steps, 34)
  equal(plan.movement_count, 10)
  equal(plan.turn_count, 6)
  for index, operation in ipairs(expectedOperations) do
    equal(plan.steps[index].operation, operation)
  end
  local endX, endZ, endHeading = validateFarmGeometry(plan)
  equal(endX, 2)
  equal(endZ, 3)
  equal(endHeading, "south")
end)

test("rectangular patch poses rotate with every initial world heading", function()
  local plan = assert(farm.plan("patch", 1, 3, 3))
  local transforms = {
    north = {forward = {x = 0, z = -1}, right = {x = 1, z = 0}, finish = "south"},
    east = {forward = {x = 1, z = 0}, right = {x = 0, z = 1}, finish = "west"},
    south = {forward = {x = 0, z = 1}, right = {x = -1, z = 0}, finish = "north"},
    west = {forward = {x = -1, z = 0}, right = {x = 0, z = -1}, finish = "east"}
  }
  for _, heading in ipairs({"north", "east", "south", "west"}) do
    local startPose = pose.new(20, 7, -20, heading)
    local finish = assert(farm.expectedEnd(plan, startPose))
    local transform = transforms[heading]
    equal(finish.x, startPose.x + transform.forward.x * 4 + transform.right.x * 2)
    equal(finish.y, startPose.y)
    equal(finish.z, startPose.z + transform.forward.z * 4 + transform.right.z * 2)
    equal(finish.heading, transform.finish)
    for _, target in ipairs(plan.cells) do
      local world = farm.targetForCell(startPose, target)
      equal(world.x, startPose.x + transform.forward.x * (target.z + 1)
        + transform.right.x * target.x)
      equal(world.y, startPose.y - 1)
      equal(world.z, startPose.z + transform.forward.z * (target.z + 1)
        + transform.right.z * target.x)
    end
  end
end)

test("farm execution completes the route and stops on uncertain outcomes", function()
  local patch = assert(farm.plan("patch", 1))
  local simulated = pose.new(10, 4, -3, "north")
  local calls = 0
  local report = farm.execute(patch, readyFarmStatus(), function(operation)
    calls = calls + 1
    simulated = assert(pose.apply(simulated, operation))
    local payload = pose.toFields(simulated)
    if operation == "plant_forward_down" then payload.item_consumed = "true" end
    return {certainty = "succeeded", code = "operation_succeeded",
      message = "OK", payload = payload}
  end)
  equal(report.ok, true)
  equal(report.tilled, 9)
  equal(report.planted, 9)
  equal(calls, #patch.steps)

  local single = assert(farm.plan("single", 1))
  calls = 0
  local stopped = farm.execute(single, readyFarmStatus(), function()
    calls = calls + 1
    return {certainty = "unknown", status = "timeout",
      code = "outcome_unknown", message = "timeout"}
  end)
  equal(stopped.ok, false)
  equal(stopped.uncertain, true)
  equal(stopped.tilled, 0)
  equal(stopped.planted, 0)
  equal(calls, 1)

  calls = 0
  local failed = farm.execute(single, readyFarmStatus(), function()
    calls = calls + 1
    return {certainty = "failed", status = "failed",
      code = "operation_failed", message = "blocked"}
  end)
  equal(failed.ok, false)
  equal(failed.uncertain, false)
  contains(failed.reason, "failed / operation_failed")
  equal(failed.planted, 0)
  equal(calls, 1)

  calls = 0
  simulated = pose.new(10, 4, -3, "north")
  local unconsumed = farm.execute(single, readyFarmStatus(), function(operation)
    calls = calls + 1
    simulated = assert(pose.apply(simulated, operation))
    local payload = pose.toFields(simulated)
    if operation == "plant_forward_down" then payload.item_consumed = "false" end
    return {certainty = "succeeded", status = "succeeded",
      code = "operation_succeeded", message = "OK", payload = payload}
  end)
  equal(unconsumed.ok, false)
  equal(unconsumed.uncertain, true)
  equal(unconsumed.tilled, 1)
  equal(unconsumed.planted, 0)
  equal(calls, 2)
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
