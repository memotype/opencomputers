local cases = {}

function cases.register(harness)
  local test = assert(harness.test)
  local equal = assert(harness.equal)
  local truthy = assert(harness.truthy)
  local contains = assert(harness.contains)

  local navState = require("ocia.nav_state")
  local pose = require("ocia.pose")
  local protocol = require("ocia.protocol")

  local epoch = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
  local otherEpoch = "cccccccc-cccc-cccc-cccc-cccccccccccc"
  local robotAddress = "22222222-2222-2222-2222-222222222222"
  local missionCounter = 0

  local function robotStatus(overrides)
    local value = {
      mode = "ready", journal_health = "healthy", epoch = epoch,
      high_water = 0, pose = pose.new()
    }
    for key, item in pairs(overrides or {}) do value[key] = item end
    return value
  end

  local function mission(store, overrides, status)
    missionCounter = missionCounter + 1
    local specification = {
      mission_id = "mission-" .. missionCounter,
      destination = {x = -2, y = 0, z = 0, heading = "west"},
      action_limit = 160,
      owner = "host-test"
    }
    for key, value in pairs(overrides or {}) do specification[key] = value end
    local snapshot, reason = navState.createMission(status or robotStatus(), specification)
    truthy(snapshot, reason)
    truthy(store.create(snapshot))
    return snapshot
  end

  local function intent(store, snapshot, operation, arguments)
    return assert(navState.prepareIntent(store, snapshot, {
      operation = operation or "turn_left", arguments = arguments or {},
      recipient = robotAddress
    }))
  end

  local function resultResponse(snapshot, outcome, code, resultingPose, extra)
    local pending = assert(snapshot.pending)
    local request = assert(navState.requestForPending(snapshot))
    truthy(request.fingerprint)
    local payload = pose.toFields(resultingPose or pending.expected)
    payload.code = code
    payload.message = (extra and extra.message) or code
    if extra then
      for key, value in pairs(extra) do payload[key] = value end
    end
    return {
      certainty = protocol.certainty(outcome), status = outcome, code = code,
      message = payload.message, payload = payload, request = request,
      reply = {
        version = protocol.VERSION, request_id = request.request_id,
        deployment_id = request.deployment_id, operation = request.operation,
        outcome = outcome, payload = payload
      }
    }
  end

  local function wireResponse(snapshot, outcome, payload)
    local request = assert(navState.requestForPending(snapshot))
    return {
      certainty = protocol.certainty(outcome), status = outcome,
      code = payload.code, message = payload.message, payload = payload,
      request = request,
      reply = {
        version = protocol.VERSION, request_id = request.request_id,
        deployment_id = request.deployment_id, operation = request.operation,
        outcome = outcome, payload = payload
      }
    }
  end

  local function success(snapshot)
    return resultResponse(snapshot, "succeeded", "operation_succeeded",
      snapshot.pending.expected)
  end

  local function reload(store)
    local loaded, metadata = store.load()
    truthy(loaded, metadata and metadata.error)
    return loaded
  end

  local function sameValue(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
      if not sameValue(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
      if left[key] == nil then return false end
    end
    return true
  end

  local function replayComparable(value)
    local result = navState.copy(value)
    if result.pending then
      result.pending.transmit_authorized = false
      result.pending.retry_authorized = false
    end
    return result
  end

  local function virtualFilesystem()
    local v = {files = {}, directories = {["/"] = true, ["/state/"] = true},
      fault = nil, counts = {}}
    local function hit(operation)
      v.counts[operation] = (v.counts[operation] or 0) + 1
      if v.fault and v.fault.operation == operation
          and v.counts[operation] == (v.fault.at or 1) then return true, v.fault end
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
      if hit("mkdir") then return nil, "injected mkdir failure" end
      v.directories[path] = true
      return true
    end
    function v.remove(path)
      if hit("remove") then return nil, "injected remove failure" end
      v.files[path] = nil
      return true
    end
    function v.rename(from, to)
      if hit("rename") then return nil, "injected rename failure" end
      if v.files[from] == nil then return nil, "missing source" end
      if v.files[to] ~= nil then return nil, "destination exists" end
      v.files[to], v.files[from] = v.files[from], nil
      return true
    end
    function v.open(path, mode)
      if hit("open") then return nil, "injected open failure" end
      if mode == "r" and v.files[path] == nil then return nil, "missing file" end
      if mode == "w" then v.files[path] = "" end
      if mode == "a" and v.files[path] == nil then v.files[path] = "" end
      local position = 1
      return {
        write = function(_, text)
          local failed, fault = hit("write")
          if failed then
            if fault.partial then
              v.files[path] = v.files[path] .. text:sub(1, math.max(1, math.floor(#text / 2)))
            end
            return nil, "injected write failure"
          end
          v.files[path] = v.files[path] .. text
          return true
        end,
        flush = function()
          if hit("flush") then return nil, "injected flush failure" end
          return true
        end,
        read = function(_, format)
          if hit("read") then return nil, "injected read failure" end
          local content = v.files[path]
          if format == "*a" then
            local value = content:sub(position)
            position = #content + 1
            return value
          end
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
          if hit("close") then error("injected close failure") end
          return true
        end
      }
    end
    return v
  end

  local function fileStore(vfs, options)
    options = options or {}
    local clock = 0
    return navState.journalStore("/state/nav.state", {
      filesystem = vfs, open = vfs.open,
      max_records = options.max_records,
      timer = function() clock = clock + 0.001; return clock end
    })
  end

  test("navigation mission creation enforces healthy commissioned home", function()
    local valid = assert(navState.createMission(robotStatus(), {
      mission_id = "create-valid", destination = {x = 1, y = 0, z = 0}
    }))
    equal(valid.phase, "outbound")
    equal(valid.robot_epoch, epoch)
    equal(valid.high_water, 0)
    equal(valid.limits.action_limit, 160)
    truthy(pose.equal(valid.pose, navState.homePose()))

    local invalid = {
      {mode = "recovery_required"},
      {journal_health = "corrupt"},
      {epoch = ""},
      {pose = pose.unknown(pose.new(), "test")},
      {pose = pose.new(-1, 0, 0, "west")}
    }
    for _, override in ipairs(invalid) do
      local created = navState.createMission(robotStatus(override), {
        mission_id = "create-invalid", destination = {x = 1, y = 0, z = 0}
      })
      equal(created, nil)
    end
  end)

  test("one active journal cannot be silently overwritten", function()
    local store = navState.memoryStore()
    local first = mission(store)
    local second = assert(navState.createMission(robotStatus(), {
      mission_id = "second-mission", destination = {x = 1, y = 0, z = 0}
    }))
    equal(store.create(second), nil)
    equal(reload(store).mission_id, first.mission_id)
    truthy(navState.terminate(store, first, "aborted", "test terminal"))
    equal(store.create(second), nil)
  end)

  test("intent persistence preserves exact request identity across replay", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    local prepared = intent(store, snapshot, "turn_left")
    equal(prepared.request_id, "p:" .. epoch .. ":1")
    equal(prepared.sequence, 1)
    equal(snapshot.high_water, 0)
    truthy(navState.canTransmit(snapshot))
    local request = assert(navState.requestForPending(snapshot))
    local restarted = reload(store)
    local replay = assert(navState.requestForPending(restarted))
    equal(replay.request_id, request.request_id)
    equal(replay.fingerprint, request.fingerprint)
    equal(replay.arguments_raw, request.arguments_raw)
    equal(replay.deployment_id, snapshot.mission_id)
    equal(navState.prepareIntent(store, snapshot, {operation = "move_forward",
      recipient = robotAddress}), nil)
  end)

  test("confirmed success updates pose and breadcrumb exactly once", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    local classified = assert(navState.recordResult(store, snapshot, success(snapshot)))
    equal(classified.kind, "success")
    equal(snapshot.high_water, 1)
    equal(snapshot.physical_actions, 1)
    equal(#snapshot.breadcrumbs, 1)
    equal(snapshot.breadcrumbs[1].operation, "turn_left")
    equal(snapshot.pose.heading, "west")
    equal(navState.recordResult(store, snapshot, {}), nil)
    equal(#snapshot.breadcrumbs, 1)
    local restarted = reload(store)
    equal(#restarted.breadcrumbs, 1)
    equal(restarted.high_water, 1)
  end)

  test("completed movement failure consumes sequence without breadcrumb", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "move_forward")
    local response = resultResponse(snapshot, "failed", "operation_failed",
      snapshot.pending.before, {message = "solid"})
    local classified = assert(navState.recordResult(store, snapshot, response))
    equal(classified.kind, "completed_failure")
    equal(snapshot.high_water, 1)
    equal(snapshot.physical_actions, 1)
    equal(#snapshot.breadcrumbs, 0)
    truthy(pose.equal(snapshot.pose, pose.new()))
    equal(snapshot.pending, nil)
    equal(snapshot.reconciliation_required, true)
    equal(navState.prepareIntent(store, snapshot, {
      operation = "turn_left", recipient = robotAddress}), nil)
    truthy(navState.recordReconciliation(store, snapshot,
      robotStatus({high_water = 1, pose = snapshot.pose})))
    equal(snapshot.reconciliation_required, false)
    truthy(intent(store, snapshot, "turn_left"))
  end)

  test("interrupted prepared execution consumes sequence without movement", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_right")
    local response = resultResponse(snapshot, "failed", "interrupted_before_execution",
      snapshot.pending.before, {physical_outcome = "not_started"})
    local classified = assert(navState.recordResult(store, snapshot, response))
    equal(classified.kind, "definite_nonexecution")
    equal(snapshot.high_water, 1)
    equal(#snapshot.breadcrumbs, 0)
    equal(snapshot.pose.heading, "north")
    equal(snapshot.reconciliation_required, true)
  end)

  test("real robot prepared-recovery payload is definite nonexecution", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "move_forward")
    local response = wireResponse(snapshot, "failed", {
      code = "interrupted_before_execution",
      message = "request was prepared but physical execution had not begun",
      physical_outcome = "not_started"
    })
    local classified = assert(navState.recordResult(store, snapshot, response))
    equal(classified.kind, "definite_nonexecution")
    equal(snapshot.high_water, 1)
    truthy(pose.equal(snapshot.pose, navState.homePose()))
    equal(#snapshot.breadcrumbs, 0)
    equal(navState.prepareIntent(store, snapshot, {
      operation = "turn_left", recipient = robotAddress}), nil)

    local invalidStatuses = {
      {pose = pose.new(1, 0, 0, "north")}, {epoch = otherEpoch},
      {mode = "recovery_required"}, {journal_health = "corrupt"},
      {high_water = 0}, {high_water = 2}
    }
    for _, override in ipairs(invalidStatuses) do
      equal(navState.recordReconciliation(store, snapshot,
        robotStatus(override)), nil)
    end
    truthy(navState.recordReconciliation(store, snapshot,
      robotStatus({high_water = 1, pose = navState.homePose()})))
    local nextIntent = intent(store, snapshot, "turn_left")
    equal(nextIntent.request_id, "p:" .. epoch .. ":2")

    local contradictoryStore = navState.memoryStore()
    local contradictory = mission(contradictoryStore)
    intent(contradictoryStore, contradictory, "move_forward")
    local contradictoryPayload = {
      code = "interrupted_before_execution", message = "not started",
      physical_outcome = "not_started", pose_trusted = "true",
      x = "1", y = "0", z = "0", heading = "north", pose_reason = ""
    }
    equal(assert(navState.recordResult(contradictoryStore, contradictory,
      wireResponse(contradictory, "failed", contradictoryPayload))).kind,
      "contradictory_response")

    for _, physicalOutcome in ipairs({false, "unknown"}) do
      local invalidStore = navState.memoryStore()
      local invalid = mission(invalidStore)
      intent(invalidStore, invalid, "move_forward")
      local payload = {code = "interrupted_before_execution", message = "bad evidence"}
      if physicalOutcome then payload.physical_outcome = physicalOutcome end
      equal(assert(navState.recordResult(invalidStore, invalid,
        wireResponse(invalid, "failed", payload))).kind,
        "contradictory_response")
      truthy(invalid.pending)
      equal(invalid.high_water, 0)
    end
  end)

  test("ambiguous result recovery authorizes only an identical retry", function()
    local vfs = virtualFilesystem()
    local store = fileStore(vfs)
    local snapshot = mission(store)
    intent(store, snapshot, "move_forward")
    local original = assert(navState.requestForPending(snapshot))
    local physicalCalls, cached = 0, nil
    local function robotEndpoint(request)
      if not cached then
        physicalCalls = physicalCalls + 1
        cached = success(snapshot)
      end
      equal(request.request_id, original.request_id)
      equal(request.fingerprint, original.fingerprint)
      return cached
    end

    robotEndpoint(original) -- result is deliberately lost
    assert(navState.recordResult(store, snapshot, {
      status = "timeout", code = "outcome_unknown", message = "lost reply"
    }))
    equal(physicalCalls, 1)
    equal(navState.canTransmit(snapshot), false)

    local restartedStore = fileStore(vfs)
    snapshot = reload(restartedStore)
    equal(navState.canTransmit(snapshot), false)
    equal(navState.canRetryPending(snapshot), false)
    local authorization = assert(navState.authorizeRetry(restartedStore, snapshot,
      robotStatus({high_water = 1, pose = snapshot.pending.expected})))
    equal(authorization.action, "retry_identical")
    local retry = assert(navState.retryRequest(snapshot))
    equal(retry.request_id, original.request_id)
    equal(retry.fingerprint, original.fingerprint)

    local cachedResult = robotEndpoint(retry)
    assert(navState.recordResult(restartedStore, snapshot, cachedResult))
    equal(physicalCalls, 1)
    equal(snapshot.high_water, 1)
    equal(#snapshot.breadcrumbs, 1)
    truthy(pose.equal(snapshot.pose, pose.new(0, 0, -1, "north")))
    equal(navState.recordResult(restartedStore, snapshot, cachedResult), nil)
    local nextIntent = intent(restartedStore, snapshot, "turn_left")
    equal(nextIntent.request_id, "p:" .. epoch .. ":2")
  end)

  test("retry authorization is fresh exact and fail-closed", function()
    local vfs = virtualFilesystem()
    local store = fileStore(vfs)
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    assert(navState.recordResult(store, snapshot, {
      status = "send_failed", code = "send_failed", message = "ambiguous send"
    }))

    for _, override in ipairs({
      {epoch = otherEpoch}, {mode = "recovery_required"},
      {journal_health = "corrupt"}, {high_water = 2},
      {high_water = 0, pose = pose.new(1, 0, 0, "north")}
    }) do
      equal(navState.authorizeRetry(store, snapshot, robotStatus(override)), nil)
      equal(navState.canRetryPending(snapshot), false)
    end

    truthy(navState.authorizeRetry(store, snapshot, robotStatus()))
    truthy(navState.canRetryPending(snapshot))
    local replayedStore = fileStore(vfs)
    local replayed = reload(replayedStore)
    equal(navState.canRetryPending(replayed), false)
    equal(navState.retryRequest(replayed), nil)
    truthy(navState.authorizeRetry(replayedStore, replayed, robotStatus()))
    local exact = assert(navState.retryRequest(replayed))
    equal(exact.request_id, snapshot.pending.request_id)
    equal(exact.fingerprint, snapshot.pending.fingerprint)

    assert(navState.recordResult(replayedStore, replayed, {
      status = "timeout", code = "outcome_unknown", message = "retry reply lost"
    }))
    equal(navState.canRetryPending(replayed), false)
    truthy(navState.authorizeRetry(replayedStore, replayed, robotStatus()))
    local retired = resultResponse(replayed, "rejected", "retired_request",
      replayed.pending.before)
    equal(assert(navState.recordResult(replayedStore, replayed, retired)).kind,
      "robot_rejection")
    equal(navState.canRetryPending(replayed), false)
    equal(navState.assessStatus(replayed, robotStatus()).action, "manual_recovery")

    local failureStore = navState.memoryStore()
    local failed = mission(failureStore)
    intent(failureStore, failed, "turn_left")
    assert(navState.recordResult(failureStore, failed, {
      status = "timeout", code = "outcome_unknown", message = "lost"
    }))
    failureStore.fail_at = failureStore.append_count + 1
    equal(navState.authorizeRetry(failureStore, failed, robotStatus()), nil)
    equal(failed.journal.health, "uncertain_write")
    equal(navState.canRetryPending(failed), false)
  end)

  test("invalid transitions are rejected before filesystem writes", function()
    local vfs = virtualFilesystem()
    local store = fileStore(vfs)
    local snapshot = mission(store)

    local function unchanged(callback)
      local bytes = vfs.files["/state/nav.state"]
      local before = navState.copy(snapshot)
      local records = snapshot.journal.records
      local ok, reason = callback()
      equal(ok, nil)
      truthy(reason)
      equal(vfs.files["/state/nav.state"], bytes)
      truthy(sameValue(snapshot, before))
      equal(snapshot.journal.health, "healthy")
      equal(snapshot.journal.records, records)
      local replayed = reload(fileStore(vfs))
      replayed.journal.last_persist_ms = snapshot.journal.last_persist_ms
      truthy(sameValue(replayed, replayComparable(snapshot)))
    end

    unchanged(function() return navState.markDestination(store, snapshot) end)
    unchanged(function()
      return store.append(snapshot, {kind = "result", request_id = "none",
        sequence = 1, classification = "success"})
    end)
    intent(store, snapshot, "turn_left")
    unchanged(function() return navState.beginReturn(store, snapshot) end)
    unchanged(function() return navState.terminate(store, snapshot, "aborted", "bad") end)
    unchanged(function()
      return store.append(snapshot, {kind = "result", request_id = "wrong",
        sequence = 1, classification = "success"})
    end)
    unchanged(function()
      return navState.prepareIntent(store, snapshot, {operation = "move_forward",
        recipient = robotAddress, request_id = "p:" .. epoch .. ":2"})
    end)
    assert(navState.recordResult(store, snapshot, success(snapshot)))
    truthy(navState.beginReturn(store, snapshot))
    unchanged(function() return navState.beginReturn(store, snapshot) end)
    unchanged(function()
      return navState.prepareIntent(store, snapshot, {
        operation = "turn_left", recipient = robotAddress})
    end)
    truthy(intent(store, snapshot, "turn_right"))
  end)

  test("action and journal limits reject without changing authoritative state", function()
    local actionStore = navState.memoryStore()
    local limited = mission(actionStore, {action_limit = 1})
    intent(actionStore, limited, "turn_left")
    assert(navState.recordResult(actionStore, limited, success(limited)))
    local actionBefore = navState.copy(limited)
    local actionRecords = actionStore.records()
    equal(navState.prepareIntent(actionStore, limited, {
      operation = "turn_right", recipient = robotAddress}), nil)
    truthy(sameValue(limited, actionBefore))
    truthy(sameValue(actionStore.records(), actionRecords))

    local vfs = virtualFilesystem()
    local boundedStore = fileStore(vfs, {max_records = 2})
    local bounded = mission(boundedStore)
    intent(boundedStore, bounded, "turn_left")
    local bytes = vfs.files["/state/nav.state"]
    local before = navState.copy(bounded)
    equal(navState.recordResult(boundedStore, bounded, success(bounded)), nil)
    equal(vfs.files["/state/nav.state"], bytes)
    truthy(sameValue(bounded, before))
    equal(bounded.journal.health, "healthy")
    local replayed = reload(fileStore(vfs, {max_records = 2}))
    replayed.journal.last_persist_ms = bounded.journal.last_persist_ms
    truthy(sameValue(replayed, replayComparable(bounded)))
  end)

  test("transport and robot failure classes retain distinct policies", function()
    do
      local store = navState.memoryStore()
      local snapshot = mission(store)
      intent(store, snapshot, "turn_left")
      local classified = assert(navState.recordResult(store, snapshot,
        {status = "local_rejection", code = "invalid_request", message = "bad"}))
      equal(classified.kind, "local_nonsend")
      equal(classified.ambiguous, false)
      equal(snapshot.phase, "outbound")
      equal(snapshot.pending, nil)
      equal(snapshot.high_water, 0)
      equal(snapshot.physical_actions, 0)
      equal(#snapshot.breadcrumbs, 0)
      equal(snapshot.reconciliation_required, true)
      equal(navState.prepareIntent(store, snapshot, {
        operation = "turn_left", recipient = robotAddress}), nil)
      truthy(navState.recordReconciliation(store, snapshot, robotStatus()))
      local nextIntent = intent(store, snapshot, "turn_left")
      equal(nextIntent.request_id, "p:" .. epoch .. ":1")
      local replayed = reload(store)
      equal(replayed.high_water, 0)
      equal(replayed.pending.request_id, nextIntent.request_id)
    end

    local fixtures = {
      {{status = "send_failed", code = "send_failed", message = "down"},
        "send_ambiguous", true},
      {{status = "timeout", code = "outcome_unknown", message = "late"},
        "timeout", true}
    }
    for _, fixture in ipairs(fixtures) do
      local store = navState.memoryStore()
      local snapshot = mission(store)
      intent(store, snapshot, "turn_left")
      local classified = assert(navState.recordResult(store, snapshot, fixture[1]))
      equal(classified.kind, fixture[2])
      equal(classified.ambiguous, fixture[3])
      equal(snapshot.phase, "recovery_required")
      truthy(snapshot.pending)
      equal(snapshot.high_water, 0)
      equal(#snapshot.breadcrumbs, 0)
      equal(navState.canTransmit(snapshot), false)
    end

    for _, outcome in ipairs({"rejected", "recovery_required"}) do
      local store = navState.memoryStore()
      local snapshot = mission(store)
      intent(store, snapshot, "turn_left")
      local response = resultResponse(snapshot, outcome,
        outcome == "rejected" and "retired_request" or "physical_outcome_unknown",
        snapshot.pending.before)
      local classified = assert(navState.recordResult(store, snapshot, response))
      equal(classified.kind, outcome == "rejected"
        and "robot_rejection" or "robot_recovery_required")
      truthy(snapshot.pending)
      equal(snapshot.high_water, 0)
    end
  end)

  test("contradictory success pose and correlation fail closed", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    local wrongPose = resultResponse(snapshot, "succeeded", "operation_succeeded",
      pose.new(1, 0, 0, "west"))
    local classified = assert(navState.recordResult(store, snapshot, wrongPose))
    equal(classified.kind, "contradictory_response")
    truthy(snapshot.pending)
    equal(snapshot.phase, "recovery_required")

    local secondStore = navState.memoryStore()
    local second = mission(secondStore)
    intent(secondStore, second, "turn_left")
    local mismatch = success(second)
    mismatch.reply.request_id = "p:" .. epoch .. ":99"
    classified = assert(navState.recordResult(secondStore, second, mismatch))
    equal(classified.kind, "contradictory_response")
    equal(second.high_water, 0)
  end)

  test("status reconciliation distinguishes consistency pending work and interference", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    local consistent = navState.assessStatus(snapshot, robotStatus())
    equal(consistent.action, "continue")
    truthy(navState.recordReconciliation(store, snapshot, robotStatus()))

    intent(store, snapshot, "turn_left")
    local pending = navState.assessStatus(snapshot, robotStatus())
    equal(pending.action, "retry_identical")
    equal(pending.request.request_id, snapshot.pending.request_id)
    local allocated = navState.assessStatus(snapshot, robotStatus({high_water = 1,
      pose = snapshot.pending.expected}))
    equal(allocated.action, "retry_identical")
    local ahead = navState.assessStatus(snapshot, robotStatus({high_water = 2}))
    equal(ahead.action, "manual_recovery")
    local stale = navState.assessStatus(snapshot, robotStatus({epoch = otherEpoch}))
    equal(stale.action, "manual_recovery")
    local contradiction = navState.assessStatus(snapshot,
      robotStatus({high_water = 0, pose = pose.new(1, 0, 0, "north")}))
    equal(contradiction.action, "manual_recovery")
  end)

  test("restart before result preserves pending identity and after result preserves effect", function()
    local vfs = virtualFilesystem()
    local store = fileStore(vfs)
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    local restartedStore = fileStore(vfs)
    local restarted = reload(restartedStore)
    equal(restarted.pending.request_id, snapshot.pending.request_id)
    local retry = navState.assessStatus(restarted, robotStatus())
    equal(retry.action, "retry_identical")
    assert(navState.recordResult(restartedStore, restarted, success(restarted)))
    local completed = reload(fileStore(vfs))
    equal(completed.pending, nil)
    equal(completed.high_water, 1)
    equal(#completed.breadcrumbs, 1)
  end)

  test("retained duplicate response cannot apply a result twice", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    local response = success(snapshot)
    assert(navState.recordResult(store, snapshot, response))
    equal(navState.recordResult(store, snapshot, response), nil)
    equal(snapshot.high_water, 1)
    equal(snapshot.physical_actions, 1)
    equal(#snapshot.breadcrumbs, 1)
  end)

  test("retired stale epoch and external commands require manual recovery", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    local retired = resultResponse(snapshot, "rejected", "retired_request",
      snapshot.pending.before)
    equal(assert(navState.recordResult(store, snapshot, retired)).kind, "robot_rejection")
    equal(navState.assessStatus(snapshot, robotStatus({high_water = 8})).action,
      "manual_recovery")

    local otherStore = navState.memoryStore()
    local other = mission(otherStore)
    equal(navState.assessStatus(other, robotStatus({epoch = otherEpoch})).action,
      "manual_recovery")
    equal(navState.assessStatus(other, robotStatus({high_water = 1})).action,
      "manual_recovery")
  end)

  test("inverse return freezes breadcrumbs and records exact progress", function()
    local store = navState.memoryStore()
    local snapshot = mission(store, {destination = {x = 1, y = 0, z = -1}})
    for _, operation in ipairs({"move_forward", "turn_right", "move_forward"}) do
      intent(store, snapshot, operation)
      assert(navState.recordResult(store, snapshot, success(snapshot)))
    end
    equal(#snapshot.breadcrumbs, 3)
    truthy(navState.beginReturn(store, snapshot))
    equal(snapshot.phase, "returning")
    equal(snapshot.return_state.cursor, 3)
    for _, operation in ipairs({"move_backward", "turn_left", "move_backward"}) do
      intent(store, snapshot, operation)
      assert(navState.recordResult(store, snapshot, success(snapshot)))
    end
    equal(snapshot.return_state.cursor, 0)
    equal(snapshot.phase, "home_pending_reconcile")
    truthy(pose.equal(snapshot.pose, navState.homePose()))
    equal(snapshot.home_pose_reached, false)
    equal(snapshot.charging_verified, false)
    truthy(navState.recordReconciliation(store, snapshot,
      robotStatus({high_water = 6, pose = navState.homePose()})))
    equal(snapshot.phase, "home_pose_reached")
    equal(snapshot.home_pose_reached, true)
    equal(snapshot.charging_verified, false)
    equal(#snapshot.return_state.steps, 3)
  end)

  test("return and resume allow non-home state but new missions do not", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    assert(navState.recordResult(store, snapshot, success(snapshot)))
    truthy(navState.recordReconciliation(store, snapshot,
      robotStatus({high_water = 1, pose = snapshot.pose})))
    truthy(navState.beginReturn(store, snapshot))
    equal(snapshot.phase, "returning")
    local created = navState.createMission(robotStatus({high_water = 1,
      pose = snapshot.pose}), {mission_id = "away-start", destination = {x = 0, y = 0, z = 0}})
    equal(created, nil)
  end)

  test("journal replay rejects truncation checksum corruption and invalid schema", function()
    local variants = {}
    do
      local vfs, store = virtualFilesystem()
      store = fileStore(vfs)
      mission(store)
      variants[#variants + 1] = {vfs = vfs, mutate = function(value)
        return value:sub(1, #value - 4)
      end}
    end
    do
      local vfs = virtualFilesystem()
      local store = fileStore(vfs)
      mission(store)
      variants[#variants + 1] = {vfs = vfs, mutate = function(value)
        return "X" .. value:sub(2)
      end}
    end
    for _, fixture in ipairs(variants) do
      fixture.vfs.files["/state/nav.state"] = fixture.mutate(
        fixture.vfs.files["/state/nav.state"])
      local loaded, metadata = fileStore(fixture.vfs).load()
      equal(loaded, nil)
      equal(metadata.source, "corrupt")
    end

    local vfs = virtualFilesystem()
    local bad = assert(navState.encodeRecord({journal_sequence = 1,
      kind = "mission", format = 99}))
    vfs.files["/state/nav.state"] = bad
    local loaded, metadata = fileStore(vfs).load()
    equal(loaded, nil)
    contains(metadata.error, "unsupported")
  end)

  test("append open write flush and close faults fail closed", function()
    for _, fixture in ipairs({
      {"open", false}, {"write", false}, {"write", true},
      {"flush", false}, {"close", false}
    }) do
      local vfs = virtualFilesystem()
      local store = fileStore(vfs)
      local snapshot = mission(store)
      vfs.setFault(fixture[1], 1, fixture[2])
      local prepared = navState.prepareIntent(store, snapshot, {
        operation = "turn_left", recipient = robotAddress
      })
      equal(prepared, nil)
      equal(snapshot.journal.health, "uncertain_write")
      equal(snapshot.phase, "recovery_required")
      equal(navState.canTransmit(snapshot), false)
    end
  end)

  test("mission creation persistence faults do not produce an eligible journal", function()
    for _, fixture in ipairs({
      {"open", false}, {"write", false}, {"write", true},
      {"flush", false}, {"close", false}
    }) do
      local vfs = virtualFilesystem()
      local store = fileStore(vfs)
      local snapshot = assert(navState.createMission(robotStatus(), {
        mission_id = "create-fault-" .. fixture[1] .. tostring(fixture[2]),
        destination = {x = 1, y = 0, z = 0}
      }))
      vfs.setFault(fixture[1], 1, fixture[2])
      equal(store.create(snapshot), nil)
      equal(snapshot.journal.health, "uncertain_write")
      equal(navState.canTransmit(snapshot), false)
    end
  end)

  test("result persistence faults never apply an uncertain completion in memory", function()
    for _, fixture in ipairs({
      {"open", false}, {"write", false}, {"write", true},
      {"flush", false}, {"close", false}
    }) do
      local vfs = virtualFilesystem()
      local store = fileStore(vfs)
      local snapshot = mission(store)
      intent(store, snapshot, "turn_left")
      local response = success(snapshot)
      vfs.setFault(fixture[1], 1, fixture[2])
      equal(navState.recordResult(store, snapshot, response), nil)
      truthy(snapshot.pending)
      equal(snapshot.high_water, 0)
      equal(#snapshot.breadcrumbs, 0)
      equal(snapshot.journal.health, "uncertain_write")
      equal(navState.canTransmit(snapshot), false)

      local loaded, metadata = fileStore(vfs).load()
      if fixture[1] == "write" and fixture[2] then
        equal(loaded, nil)
        equal(metadata.source, "corrupt")
      elseif fixture[1] == "flush" or fixture[1] == "close" then
        truthy(loaded)
        equal(loaded.high_water, 1)
        equal(#loaded.breadcrumbs, 1)
      else
        truthy(loaded)
        truthy(loaded.pending)
        equal(loaded.high_water, 0)
      end
    end
  end)

  test("terminal archive rotation is explicit and fails closed on artifacts", function()
    local vfs = virtualFilesystem()
    local store = fileStore(vfs)
    local snapshot = mission(store)
    truthy(navState.terminate(store, snapshot, "aborted", "operator stop"))
    equal(snapshot.phase, "terminal")
    local archive = assert(store.archive(snapshot))
    truthy(vfs.exists(archive))
    equal(vfs.exists("/state/nav.state"), false)
    equal(snapshot.journal.health, "archived")

    local vfs2 = virtualFilesystem()
    local store2 = fileStore(vfs2)
    local snapshot2 = mission(store2)
    truthy(navState.terminate(store2, snapshot2, "aborted", "test"))
    vfs2.setFault("rename", 1)
    equal(store2.archive(snapshot2), nil)
    equal(snapshot2.journal.health, "uncertain_rotation")
    local loaded, metadata = fileStore(vfs2).load()
    truthy(loaded)
    equal(metadata.source, "archive_artifact")
    equal(loaded.journal.health, "uncertain_rotation")
  end)

  test("archive marker and cleanup faults preserve an explicit uncertain artifact", function()
    for _, fault in ipairs({"open", "write", "flush", "close", "remove"}) do
      local vfs = virtualFilesystem()
      local store = fileStore(vfs)
      local snapshot = mission(store)
      truthy(navState.terminate(store, snapshot, "aborted", "rotation fault"))
      vfs.setFault(fault, 1)
      equal(store.archive(snapshot), nil)
      equal(snapshot.journal.health, "uncertain_rotation")
      if fault ~= "open" then
        truthy(vfs.exists("/state/nav.state.archive.switch"), fault)
        local loaded, metadata = fileStore(vfs).load()
        truthy(loaded)
        equal(metadata.source, "archive_artifact")
      end
    end
  end)

  test("journal remains bounded for the approved mission envelope", function()
    local store = navState.memoryStore()
    local snapshot = mission(store, {action_limit = 160,
      destination = {x = 0, y = 0, z = 0}})
    for sequence = 1, 160 do
      local operation = sequence % 2 == 1 and "turn_left" or "turn_right"
      intent(store, snapshot, operation)
      assert(navState.recordResult(store, snapshot, success(snapshot)))
    end
    equal(snapshot.physical_actions, 160)
    equal(#snapshot.breadcrumbs, 160)
    truthy(snapshot.journal.records <= 321)
    truthy(snapshot.journal.bytes < 512000)
    equal(navState.prepareIntent(store, snapshot, {
      operation = "turn_left", recipient = robotAddress}), nil)
    local restarted = reload(store)
    equal(restarted.physical_actions, 160)
    equal(#restarted.breadcrumbs, 160)
  end)

  test("caller data is preserved and replay is deterministic", function()
    local status = robotStatus()
    local specification = {mission_id = "immutable-input",
      destination = {x = 2, y = 0, z = -1, heading = "east"},
      limits = {custom_limit = 3}}
    local snapshot = assert(navState.createMission(status, specification))
    equal(status.pose.x, 0)
    equal(specification.destination.x, 2)
    equal(specification.limits.custom_limit, 3)
    snapshot.destination.x = 99
    equal(specification.destination.x, 2)

    local vfs = virtualFilesystem()
    local store = fileStore(vfs)
    snapshot = assert(navState.createMission(status, specification))
    truthy(store.create(snapshot))
    intent(store, snapshot, "turn_left")
    assert(navState.recordResult(store, snapshot, success(snapshot)))
    local first = reload(fileStore(vfs))
    local second = reload(fileStore(vfs))
    equal(first.mission_id, second.mission_id)
    equal(first.high_water, second.high_water)
    equal(type(first.limits.action_limit), "number")
    equal(type(first.limits.max_distance), "number")
    equal(first.pose.heading, second.pose.heading)
    equal(first.breadcrumbs[1].request_id, second.breadcrumbs[1].request_id)
  end)

  test("controller persistence uncertainty prohibits forward progress", function()
    local store = navState.memoryStore()
    local snapshot = mission(store)
    intent(store, snapshot, "turn_left")
    store.fail_at = store.append_count + 1
    equal(navState.recordResult(store, snapshot, success(snapshot)), nil)
    equal(snapshot.journal.health, "uncertain_write")
    equal(snapshot.phase, "recovery_required")
    truthy(snapshot.pending)
    equal(navState.canTransmit(snapshot), false)
    equal(navState.prepareIntent(store, snapshot, {
      operation = "move_forward", recipient = robotAddress}), nil)
  end)
end

return cases
