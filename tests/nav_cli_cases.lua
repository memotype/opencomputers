local cases = {}

function cases.register(harness)
  local test = assert(harness.test)
  local equal = assert(harness.equal)
  local truthy = assert(harness.truthy)
  local contains = assert(harness.contains)

  local controllerOwner = require("ocia.controller_owner")
  local navState = require("ocia.nav_state")
  local pose = require("ocia.pose")
  local protocol = require("ocia.protocol")
  local robotAddress = "22222222-2222-2222-2222-222222222222"
  local epoch = "dddddddd-dddd-dddd-dddd-dddddddddddd"

  local ocianav = assert(loadfile("machines/controller/home/ocianav.lua"))(
    "__test_module__")

  local function processFixture(parentData)
    local parent = {data = parentData}
    local current = {data = setmetatable({}, {__index = parentData})}
    local process = {list = {[{}] = parent, [{}] = current}}
    function process.findProcess() return current end
    return process, current, parent
  end

  test("controller owner coordinates live cooperating processes", function()
    local process, current = processFixture({})
    local first = assert(controllerOwner.acquire(4242, "ocianav",
      {process = process, current = current}))
    equal(first.port, 4242)
    equal(controllerOwner.acquire(4242, "duplicate",
      {process = process, current = current}), nil)

    local other = {data = {}}
    process.list[{}] = other
    local conflict, reason = controllerOwner.acquire(4242, "ociactl",
      {process = process, current = other})
    equal(conflict, nil)
    contains(reason, "owned by ocianav")
    truthy(controllerOwner.acquire(4243, "other-port",
      {process = process, current = other}))
    truthy(first.release())
    truthy(first.release())
    truthy(controllerOwner.acquire(4242, "ociactl",
      {process = process, current = current}))
  end)

  test("controller owner ignores inherited parent metadata", function()
    local parentData = {}
    local process, current, parentProcess = processFixture(parentData)
    local parent = assert(controllerOwner.acquire(4242, "parent",
      {process = process, current = parentProcess}))
    -- The child sees parent fields through __index, but does not own them.
    local childLease, reason = controllerOwner.acquire(4243, "child",
      {process = process, current = current})
    truthy(childLease, reason)
    childLease.release()
    parent.release()
  end)

  test("controller owner cleanup survives protected errors and cancellation", function()
    local process, current = processFixture({})
    local function run(callback)
      local lease = assert(controllerOwner.acquire(4242, "test",
        {process = process, current = current}))
      local values = table.pack(xpcall(callback, debug.traceback))
      lease.release()
      return table.unpack(values, 1, values.n)
    end
    local ok, reason = run(function() error("injected") end)
    equal(ok, false)
    contains(reason, "injected")
    truthy(controllerOwner.acquire(4242, "after-error",
      {process = process, current = current}))
  end)

  local function testStore(events)
    local store = navState.memoryStore()
    local create, append, load = store.create, store.append, store.load
    local created, archived, live = false, nil, nil
    function store.create(snapshot)
      live = snapshot
      events[#events + 1] = "create"
      local ok, reason = create(snapshot)
      if ok then created = true end
      return ok, reason
    end
    function store.append(snapshot, fields)
      live = snapshot
      events[#events + 1] = fields.kind
      return append(snapshot, fields)
    end
    function store.load()
      if not created then return nil, {source = "new"} end
      return load()
    end
    function store.archive(snapshot)
      if snapshot.phase ~= "terminal" or snapshot.pending then
        return nil, "not terminal"
      end
      archived = "/state/nav.state.archive." .. snapshot.mission_id
      snapshot.journal.health = "archived"
      return archived
    end
    function store.snapshot()
      if not created then return nil end
      return select(1, load())
    end
    function store.archived() return archived end
    function store.live() return live end
    return store
  end

  local function endpoint(options)
    options = options or {}
    local value = {pose = pose.new(), high_water = 0, calls = {}, executions = 0,
      status_calls = 0, cache = {}, lost = {}, failed = {}}

    local function statusPayload()
      value.status_calls = value.status_calls + 1
      local payload = pose.toFields(value.pose)
      payload.mode = "ready"
      payload.journal_health = "healthy"
      payload.epoch = epoch
      payload.high_water = value.high_water
      payload.energy = 35000
      payload.capacity = 35500
      if options.status then
        local overrides = options.status(value.status_calls, payload) or {}
        for key, item in pairs(overrides) do payload[key] = item end
      end
      return payload
    end

    local function parsedRequest(operation, requestOptions)
      local parts = assert(protocol.buildRequest({
        request_id = requestOptions.request_id,
        deployment_id = requestOptions.deployment_id,
        recipient = robotAddress,
        operation = operation,
        arguments = requestOptions.arguments or {}
      }))
      return assert(protocol.parseRequest(parts, robotAddress))
    end

    local function response(request, outcome, payload)
      return {certainty = protocol.certainty(outcome), status = outcome,
        code = payload.code, message = payload.message, payload = payload,
        request = request, reply = {version = protocol.VERSION,
          request_id = request.request_id, deployment_id = request.deployment_id,
          operation = request.operation, outcome = outcome, payload = payload}}
    end

    function value.send(operation, requestOptions)
      value.calls[#value.calls + 1] = operation
      if operation == "status" then
        local payload = statusPayload()
        return {certainty = "succeeded", status = "succeeded", code = "status",
          message = "fresh status returned", payload = payload}
      end
      local request = parsedRequest(operation, requestOptions)
      local cached = value.cache[request.request_id]
      if cached then return cached end
      local identity = assert(protocol.parsePhysicalRequestId(request.request_id))
      value.high_water = identity.sequence
      if options.local_rejection and options.local_rejection(operation, value) then
        value.high_water = identity.sequence - 1
        return {certainty = "failed", status = "local_rejection",
          code = "invalid_request", message = "injected local rejection"}
      end
      if options.fail and options.fail(operation, value) then
        local payload = pose.toFields(value.pose)
        payload.code, payload.message = "operation_failed", "solid"
        local failed = response(request, "failed", payload)
        value.cache[request.request_id] = failed
        return failed
      end
      value.executions = value.executions + 1
      value.pose = assert(pose.apply(value.pose, operation))
      local payload = pose.toFields(value.pose)
      payload.code, payload.message = "operation_succeeded", "OK"
      payload.energy = tostring(35000 - value.executions)
      local succeeded = response(request, "succeeded", payload)
      value.cache[request.request_id] = succeeded
      if options.lose and options.lose(operation, value) then
        return {certainty = "unknown", status = "timeout",
          code = "outcome_unknown", message = "injected lost reply", request = request}
      end
      return succeeded
    end
    return value
  end

  local function fixture(options)
    options = options or {}
    local events, output, errors = {}, {}, {}
    local store = options.store or testStore(events)
    local robot = options.robot or endpoint(options.endpoint)
    local closed = 0
    local context = {config = {robot_address = robotAddress}, navState = navState,
      store = store, missionId = function() return options.mission_id or "mission-stage3" end,
      client = {sendRequest = function(_, operation, requestOptions)
        if operation ~= "status" then events[#events + 1] = "send:" .. operation end
        return robot.send(operation, requestOptions or {})
      end}}
    function context.close() closed = closed + 1 end
    local reads = options.reads or {}
    local dependencies = {
      contextFactory = function() return context end,
      stdout = function(line) output[#output + 1] = line end,
      stderr = function(line) errors[#errors + 1] = line end,
      read = function()
        if options.onRead then
          options.onRead({output = output, errors = errors, events = events,
            store = store, robot = robot})
        end
        return table.remove(reads, 1)
      end
    }
    return {events = events, output = output, errors = errors, store = store,
      robot = robot, context = context, dependencies = dependencies,
      closed = function() return closed end}
  end

  local function run(fixtureValue, arguments)
    return ocianav.main(arguments, fixtureValue.dependencies)
  end

  local function createMissionFor(f, missionId, destination, actionLimit)
    local snapshot = assert(navState.createMission({mode = "ready",
      journal_health = "healthy", epoch = epoch, high_water = 0,
      pose = pose.new()}, {mission_id = missionId, destination = destination,
      action_limit = actionLimit or 160, owner = "host-test"}))
    truthy(f.store.create(snapshot))
    return snapshot
  end

  local function recordOperation(f, snapshot, operation)
    assert(navState.prepareIntent(f.store, snapshot, {
      operation = operation, recipient = robotAddress
    }))
    local request = assert(navState.requestForPending(snapshot))
    local response = f.robot.send(request.operation, {
      request_id = request.request_id, deployment_id = request.deployment_id,
      arguments = request.arguments
    })
    return assert(navState.recordResult(f.store, snapshot, response))
  end

  test("navigation CLI parsing and plan remain pure", function()
    local contextCalls, output, errors = 0, {}, {}
    local dependencies = {
      contextFactory = function() contextCalls = contextCalls + 1; error("hardware") end,
      stdout = function(line) output[#output + 1] = line end,
      stderr = function(line) errors[#errors + 1] = line end
    }
    equal(ocianav.main({"plan", "--x", "-1", "--y", "2", "--z", "+3",
      "--heading", "west"}, dependencies), 0)
    equal(contextCalls, 0)
    contains(table.concat(output, "\n"), "no robot was contacted")
    for _, arguments in ipairs({
      {}, {"unknown"}, {"status", "--x", "1"},
      {"plan", "--x", "1", "--y", "0"},
      {"plan", "--x", "1.5", "--y", "0", "--z", "0"},
      {"plan", "--x", "1", "--x", "2", "--y", "0", "--z", "0"},
      {"plan", "--x", "1", "--y", "0", "--z", "0", "--heading", "up"}
    }) do
      equal(ocianav.main(arguments, dependencies), 2)
    end
    equal(contextCalls, 0)
  end)

  test("plan module load has no live dependency", function()
    local required = {}
    local environment = {
      assert = assert, debug = debug, io = io, ipairs = ipairs, math = math,
      os = os, pairs = pairs, pcall = pcall, rawget = rawget, select = select,
      string = string, table = table, tonumber = tonumber, tostring = tostring,
      type = type, xpcall = xpcall,
      require = function(name)
        required[#required + 1] = name
        if name == "ocia.nav" then return require("ocia.nav") end
        if name == "ocia.pose" then return pose end
        error("unexpected live dependency " .. tostring(name))
      end
    }
    local isolated = assert(loadfile("machines/controller/home/ocianav.lua", "t",
      environment))("__test_module__")
    local output = {}
    equal(isolated.main({"plan", "--x", "0", "--y", "1", "--z", "0"}, {
      stdout = function(line) output[#output + 1] = line end,
      stderr = function(line) output[#output + 1] = line end,
      contextFactory = function() error("live context accessed") end
    }), 0)
    equal(table.concat(required, ","), "ocia.nav,ocia.pose")
  end)

  test("go revalidates status after confirmation before mission creation", function()
    local changes = {
      {epoch = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"},
      {high_water = 1},
      {x = -1},
      {mode = "recovery_required"},
      {journal_health = "corrupt"}
    }
    for _, change in ipairs(changes) do
      local f = fixture({reads = {"NAVIGATE"}, endpoint = {status = function(call)
        return call == 2 and change or nil
      end}})
      equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
        "--heading", "west"}), 1)
      equal(f.store.snapshot(), nil)
      equal(f.robot.executions, 0)
      equal(f.closed(), 1)
    end
  end)

  test("go persists intent before each send and records actual breadcrumbs", function()
    local f = fixture({reads = {"NAVIGATE"}})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 0)
    local snapshot = assert(f.store.snapshot())
    equal(snapshot.phase, "at_destination")
    equal(snapshot.high_water, 2)
    equal(#snapshot.breadcrumbs, 2)
    equal(snapshot.breadcrumbs[1].operation, "turn_left")
    equal(snapshot.breadcrumbs[2].operation, "move_forward")
    equal(table.concat(f.events, ","),
      "create,intent,send:turn_left,result,intent,send:move_forward,result,destination")
    equal(f.robot.pose.x, -1)
    equal(f.robot.pose.heading, "west")
    equal(f.closed(), 1)
  end)

  test("controller intent and result persistence faults stop progression", function()
    local intentFault = fixture({reads = {"NAVIGATE"}})
    intentFault.store.fail_at = 1
    equal(run(intentFault, {"go", "--x", "-1", "--y", "0", "--z", "0"}), 1)
    equal(intentFault.robot.executions, 0)
    equal(table.concat(intentFault.events, ","), "create,intent")
    local intentSnapshot = assert(intentFault.store.live())
    equal(intentSnapshot.journal.health, "uncertain_write")
    equal(#intentSnapshot.breadcrumbs, 0)

    local resultFault = fixture({reads = {"NAVIGATE"}})
    resultFault.store.fail_at = 2
    equal(run(resultFault, {"go", "--x", "-1", "--y", "0", "--z", "0"}), 1)
    equal(resultFault.robot.executions, 1)
    equal(table.concat(resultFault.events, ","),
      "create,intent,send:turn_left,result")
    local resultSnapshot = assert(resultFault.store.live())
    equal(resultSnapshot.journal.health, "uncertain_write")
    equal(resultSnapshot.high_water, 0)
    equal(#resultSnapshot.breadcrumbs, 0)
    truthy(resultSnapshot.pending)
  end)

  test("go cancellation and live errors always close controller ownership context", function()
    local cancelled = fixture({reads = {"no"}})
    equal(run(cancelled, {"go", "--x", "-1", "--y", "0", "--z", "0"}), 0)
    equal(cancelled.store.snapshot(), nil)
    equal(cancelled.closed(), 1)

    local failed = fixture({reads = {"NAVIGATE"}})
    failed.context.client.sendRequest = function() error("injected live failure") end
    equal(run(failed, {"go", "--x", "-1", "--y", "0", "--z", "0"}), 1)
    equal(failed.closed(), 1)
  end)

  test("definite obstruction consumes sequence reconciles and stops", function()
    local f = fixture({reads = {"NAVIGATE"}, endpoint = {
      fail = function(operation) return operation == "move_forward" end
    }})
    equal(run(f, {"go", "--x", "0", "--y", "0", "--z", "-1"}), 1)
    local snapshot = assert(f.store.snapshot())
    equal(snapshot.high_water, 1)
    equal(snapshot.physical_actions, 1)
    equal(#snapshot.breadcrumbs, 0)
    equal(snapshot.pending, nil)
    equal(snapshot.reconciliation_required, false)
    equal(snapshot.phase, "outbound")
    equal(f.robot.executions, 0)
  end)

  test("definite local nonsend clears only unsent intent and reconciles", function()
    local f = fixture({reads = {"NAVIGATE"}, endpoint = {
      local_rejection = function(operation) return operation == "turn_left" end
    }})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 1)
    local snapshot = assert(f.store.snapshot())
    equal(snapshot.phase, "outbound")
    equal(snapshot.pending, nil)
    equal(snapshot.high_water, 0)
    equal(snapshot.physical_actions, 0)
    equal(#snapshot.breadcrumbs, 0)
    equal(snapshot.reconciliation_required, false)
    equal(f.robot.executions, 0)
  end)

  test("replayed unsent intent requires status-authorized identical retry", function()
    local f = fixture({reads = {"RESUME"}})
    local status = {mode = "ready", journal_health = "healthy", epoch = epoch,
      high_water = 0, pose = pose.new()}
    local snapshot = assert(navState.createMission(status, {
      mission_id = "mission-unsent", destination = {x = -1, y = 0, z = 0,
        heading = "west"}, action_limit = 160, owner = "host-test"
    }))
    truthy(f.store.create(snapshot))
    local pending = assert(navState.prepareIntent(f.store, snapshot, {
      operation = "turn_left", recipient = robotAddress
    }))
    equal(navState.canTransmit(select(1, f.store.load())), false)
    equal(run(f, {"resume"}), 0)
    local completed = assert(f.store.snapshot())
    equal(completed.phase, "at_destination")
    equal(completed.breadcrumbs[1].request_id, pending.request_id)
    equal(f.robot.executions, 2)
  end)

  test("resume rejects pending vertical requests before retry authorization", function()
    for _, operation in ipairs({"move_up", "move_down"}) do
      local f = fixture({reads = {"RESUME"}})
      local snapshot = createMissionFor(f, "mission-pending-" .. operation,
        {x = 0, y = 0, z = 0})
      local pending = assert(navState.prepareIntent(f.store, snapshot, {
        operation = operation, recipient = robotAddress
      }))
      truthy(navState.validate(snapshot))
      equal(snapshot.pose.y, 0)
      equal(snapshot.destination.y, 0)
      equal(#snapshot.breadcrumbs, 0)
      equal(#snapshot.return_state.steps, 0)
      equal(snapshot.return_state.frozen, false)
      equal(snapshot.return_state.cursor, 0)
      equal(snapshot.journal.health, "healthy")
      equal(snapshot.pending.before.y, 0)
      equal(snapshot.pending.operation, operation)

      local genericStatus = {mode = "ready", journal_health = "healthy",
        epoch = epoch, high_water = 0, pose = pose.new()}
      local genericAssessment = navState.assessStatus(snapshot, genericStatus)
      equal(genericAssessment.ok, true)
      equal(genericAssessment.action, "retry_identical")
      equal(genericAssessment.request.request_id, pending.request_id)

      local eventsBefore = #f.events
      local callsBefore = #f.robot.calls
      equal(run(f, {"resume"}), 1)
      equal(f.robot.executions, 0)
      equal(#f.robot.calls, callsBefore + 1)
      equal(f.robot.calls[#f.robot.calls], "status")
      equal(#f.events, eventsBefore)
      contains(table.concat(f.errors, "\n"),
        "cannot resume pending operation " .. operation)

      local durable = assert(f.store.snapshot())
      equal(durable.high_water, 0)
      equal(durable.physical_actions, 0)
      equal(durable.pending.request_id, pending.request_id)
      equal(durable.pending.sequence, pending.sequence)
      equal(durable.pending.operation, operation)
      equal(durable.pending.retry_authorized, false)
      equal(durable.journal.health, "healthy")
      for _, eventName in ipairs(f.events) do
        truthy(eventName ~= "retry_authorized")
        truthy(eventName:sub(1, 5) ~= "send:")
      end

      local eventsBeforeStatus = #f.events
      equal(run(f, {"status"}), 0)
      equal(#f.events, eventsBeforeStatus)
      equal(f.robot.executions, 0)
      contains(table.concat(f.output, "\n"), pending.request_id)
      contains(table.concat(f.output, "\n"), operation)
      local inspected = assert(f.store.snapshot())
      equal(inspected.pending.request_id, pending.request_id)
      equal(inspected.journal.health, "healthy")
    end
  end)

  test("resume rejects incompatible vertical history while status remains read-only", function()
    local f = fixture({reads = {"RESUME"}})
    local snapshot = createMissionFor(f, "mission-vertical-history",
      {x = 0, y = 0, z = 0})
    recordOperation(f, snapshot, "move_up")
    recordOperation(f, snapshot, "move_down")
    assert(navState.beginReturn(f.store, snapshot))
    local eventsBefore = #f.events
    local executionsBefore = f.robot.executions
    equal(run(f, {"resume"}), 1)
    equal(f.robot.executions, executionsBefore)
    equal(#f.events, eventsBefore)
    equal(snapshot.return_state.cursor, 2)

    local statusCalls = #f.robot.calls
    equal(run(f, {"status"}), 0)
    equal(#f.events, eventsBefore)
    equal(#f.robot.calls, statusCalls + 1)
    equal(f.robot.calls[#f.robot.calls], "status")
  end)

  test("resume replans clean outbound suffix from reconciled durable pose", function()
    local f = fixture({reads = {"RESUME"}})
    local snapshot = assert(navState.createMission({mode = "ready",
      journal_health = "healthy", epoch = epoch, high_water = 0,
      pose = pose.new()}, {mission_id = "mission-clean-restart",
      destination = {x = -1, y = 0, z = 0, heading = "west"},
      action_limit = 160, owner = "host-test"}))
    truthy(f.store.create(snapshot))
    assert(navState.prepareIntent(f.store, snapshot, {
      operation = "turn_left", recipient = robotAddress
    }))
    local request = assert(navState.requestForPending(snapshot))
    local response = f.robot.send(request.operation, {
      request_id = request.request_id, deployment_id = request.deployment_id,
      arguments = request.arguments})
    assert(navState.recordResult(f.store, snapshot, response))
    equal(snapshot.pose.heading, "west")
    equal(run(f, {"resume"}), 0)
    local completed = assert(f.store.snapshot())
    equal(completed.phase, "at_destination")
    equal(completed.breadcrumbs[1].operation, "turn_left")
    equal(completed.breadcrumbs[2].operation, "move_forward")
  end)

  test("resume enforces remaining outbound and return action budget", function()
    local f = fixture({reads = {"RESUME"}})
    local snapshot = assert(navState.createMission({mode = "ready",
      journal_health = "healthy", epoch = epoch, high_water = 0,
      pose = pose.new()}, {mission_id = "mission-budget",
      destination = {x = -1, y = 0, z = 0, heading = "west"},
      action_limit = 1, owner = "host-test"}))
    truthy(f.store.create(snapshot))
    equal(run(f, {"resume"}), 1)
    equal(f.robot.executions, 0)
    equal(assert(f.store.snapshot()).phase, "outbound")
  end)

  test("initial return budget uses actual breadcrumbs before return start", function()
    local exact = fixture({reads = {"RETURN"}})
    local exactSnapshot = createMissionFor(exact, "mission-return-budget-exact",
      {x = 0, y = 0, z = 0, heading = "west"}, 2)
    recordOperation(exact, exactSnapshot, "turn_left")
    assert(navState.markDestination(exact.store, exactSnapshot))
    equal(run(exact, {"return"}), 0)
    local exactCompleted = assert(exact.store.live())
    equal(exactCompleted.physical_actions, 2)
    equal(exactCompleted.return_state.cursor, 0)
    truthy(exact.store.archived())

    local over = fixture({reads = {"RETURN"}, endpoint = {
      fail = function(operation) return operation == "move_forward" end
    }})
    local overSnapshot = createMissionFor(over, "mission-return-budget-over",
      {x = -1, y = 0, z = 0, heading = "west"}, 2)
    recordOperation(over, overSnapshot, "turn_left")
    recordOperation(over, overSnapshot, "move_forward")
    local status = over.robot.send("status", {}).payload
    assert(navState.recordReconciliation(over.store, overSnapshot, status))
    local eventsBefore = #over.events
    local executionsBefore = over.robot.executions
    equal(run(over, {"return"}), 1)
    equal(#over.events, eventsBefore)
    equal(over.robot.executions, executionsBefore)
    equal(overSnapshot.phase, "outbound")
    equal(overSnapshot.return_state.frozen, false)
    contains(table.concat(over.errors, "\n"), "action limit")
  end)

  test("started return budget uses its partially consumed frozen cursor", function()
    local f = fixture({reads = {"RESUME"}})
    local snapshot = createMissionFor(f, "mission-return-budget-cursor",
      {x = -1, y = 0, z = 0, heading = "west"}, 4)
    recordOperation(f, snapshot, "turn_left")
    recordOperation(f, snapshot, "move_forward")
    assert(navState.markDestination(f.store, snapshot))
    assert(navState.beginReturn(f.store, snapshot))
    recordOperation(f, snapshot, "move_backward")
    equal(snapshot.return_state.cursor, 1)
    equal(snapshot.physical_actions, 3)
    equal(run(f, {"resume"}), 0)
    local completed = assert(f.store.live())
    equal(completed.physical_actions, 4)
    equal(completed.return_state.cursor, 0)
    truthy(f.store.archived())
  end)

  test("resume previews clean outbound route before confirmation and cancellation", function()
    local atConfirmation
    local f = fixture({reads = {"cancel"}, onRead = function(state)
      atConfirmation = {output = table.concat(state.output, "\n"),
        events = #state.events, calls = #state.robot.calls}
    end})
    createMissionFor(f, "mission-preview-outbound",
      {x = -1, y = 0, z = 0, heading = "west"})
    local eventsBefore = #f.events
    equal(run(f, {"resume"}), 0)
    truthy(atConfirmation)
    contains(atConfirmation.output, "Resume outbound continuation")
    contains(atConfirmation.output, "1. turn_left")
    contains(atConfirmation.output, "2. move_forward")
    contains(atConfirmation.output, "unobstructed")
    contains(atConfirmation.output, "Physical actions already consumed: 0")
    equal(atConfirmation.events, eventsBefore)
    equal(atConfirmation.calls, 1)
    equal(#f.events, eventsBefore)
    equal(f.robot.executions, 0)
  end)

  test("resume previews exact pending retry and conditional continuation", function()
    local atConfirmation
    local f = fixture({reads = {"cancel"}, onRead = function(state)
      atConfirmation = table.concat(state.output, "\n")
    end})
    local snapshot = createMissionFor(f, "mission-preview-pending",
      {x = -1, y = 0, z = 0, heading = "west"})
    local pending = assert(navState.prepareIntent(f.store, snapshot, {
      operation = "turn_left", recipient = robotAddress
    }))
    local eventsBefore = #f.events
    equal(run(f, {"resume"}), 0)
    contains(atConfirmation, "Pending exact-request recovery")
    contains(atConfirmation, pending.request_id)
    contains(atConfirmation, "turn_left")
    contains(atConfirmation, snapshot.mission_id)
    contains(atConfirmation, "same physical request ID")
    contains(atConfirmation, "Conditional successful recovery")
    contains(atConfirmation, "1. move_forward")
    equal(#f.events, eventsBefore)
    equal(snapshot.pending.retry_authorized, false)
    equal(f.robot.executions, 0)
  end)

  test("resume previews frozen return and nonmoving lifecycle work", function()
    local returningOutput
    local returning = fixture({reads = {"cancel"}, onRead = function(state)
      returningOutput = table.concat(state.output, "\n")
    end})
    local returningSnapshot = createMissionFor(returning,
      "mission-preview-returning", {x = -1, y = 0, z = 0, heading = "west"})
    recordOperation(returning, returningSnapshot, "turn_left")
    recordOperation(returning, returningSnapshot, "move_forward")
    assert(navState.markDestination(returning.store, returningSnapshot))
    assert(navState.beginReturn(returning.store, returningSnapshot))
    recordOperation(returning, returningSnapshot, "move_backward")
    local returnEvents = #returning.events
    equal(run(returning, {"resume"}), 0)
    contains(returningOutput, "Resume frozen inverse return")
    contains(returningOutput, "Return cursor: 1")
    contains(returningOutput, "1. turn_right")
    equal(#returning.events, returnEvents)

    local destinationOutput
    local destination = fixture({reads = {"cancel"}, onRead = function(state)
      destinationOutput = table.concat(state.output, "\n")
    end})
    local destinationSnapshot = createMissionFor(destination,
      "mission-preview-destination", {x = 0, y = 0, z = 0, heading = "west"})
    recordOperation(destination, destinationSnapshot, "turn_left")
    assert(navState.markDestination(destination.store, destinationSnapshot))
    equal(run(destination, {"resume"}), 0)
    contains(destinationOutput, "No physical movement")
    contains(destinationOutput, "status reconciliation")
    contains(destinationOutput, "use return")

    local homeOutput
    local home = fixture({reads = {"cancel", "cancel", "cancel"}, onRead = function(state)
      homeOutput = table.concat(state.output, "\n")
    end})
    local homeSnapshot = createMissionFor(home, "mission-preview-home",
      {x = 0, y = 0, z = 0, heading = "west"})
    recordOperation(home, homeSnapshot, "turn_left")
    assert(navState.markDestination(home.store, homeSnapshot))
    assert(navState.beginReturn(home.store, homeSnapshot))
    recordOperation(home, homeSnapshot, "turn_right")
    equal(homeSnapshot.phase, "home_pending_reconcile")
    equal(run(home, {"resume"}), 0)
    contains(homeOutput, "No physical movement")
    contains(homeOutput, "home-pose reconciliation")
    contains(homeOutput, "terminal record and archive")

    for index = #home.output, 1, -1 do home.output[index] = nil end
    local homeStatus = home.robot.send("status", {}).payload
    assert(navState.recordReconciliation(home.store, homeSnapshot, homeStatus))
    equal(homeSnapshot.phase, "home_pose_reached")
    equal(run(home, {"resume"}), 0)
    contains(homeOutput, "No physical movement")
    contains(homeOutput, "terminal record")
    contains(homeOutput, "archive rotation")

    for index = #home.output, 1, -1 do home.output[index] = nil end
    assert(navState.terminate(home.store, homeSnapshot, "navigation_complete",
      "host terminal preview"))
    equal(run(home, {"resume"}), 0)
    contains(homeOutput, "No physical movement")
    contains(homeOutput, "complete archive rotation")
  end)

  test("resume preview status is revalidated and displayed route matches execution", function()
    local contradictionPreview
    local contradiction = fixture({reads = {"RESUME"}, onRead = function(state)
      contradictionPreview = table.concat(state.output, "\n")
    end, endpoint = {status = function(call)
      if call == 2 then return {high_water = 1} end
    end}})
    createMissionFor(contradiction, "mission-preview-contradiction",
      {x = -1, y = 0, z = 0, heading = "west"})
    local eventsBefore = #contradiction.events
    equal(run(contradiction, {"resume"}), 1)
    contains(contradictionPreview, "1. turn_left")
    equal(#contradiction.events, eventsBefore)
    equal(contradiction.robot.executions, 0)

    local executedPreview
    local executed = fixture({reads = {"RESUME"}, onRead = function(state)
      executedPreview = table.concat(state.output, "\n")
    end})
    createMissionFor(executed, "mission-preview-executed",
      {x = -1, y = 0, z = 0, heading = "west"})
    equal(run(executed, {"resume"}), 0)
    contains(executedPreview, "1. turn_left")
    contains(executedPreview, "2. move_forward")
    equal(table.concat(executed.robot.calls, ","),
      "status,status,turn_left,move_forward")
  end)

  test("lost acknowledgment resume uses identical request and cached result", function()
    local lost = true
    local f = fixture({reads = {"NAVIGATE", "RESUME"}, endpoint = {
      lose = function(operation)
        if lost and operation == "turn_left" then lost = false; return true end
      end
    }})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 1)
    local pending = assert(f.store.snapshot()).pending.request_id
    equal(f.robot.executions, 1)
    equal(run(f, {"resume"}), 0)
    local snapshot = assert(f.store.snapshot())
    equal(snapshot.phase, "at_destination")
    equal(snapshot.breadcrumbs[1].request_id, pending)
    equal(#snapshot.breadcrumbs, 2)
    equal(f.robot.executions, 2)
    local turns = 0
    for _, operation in ipairs(f.robot.calls) do
      if operation == "turn_left" then turns = turns + 1 end
    end
    equal(turns, 2, "lost reply must retry the same operation once")
  end)

  test("return executes frozen exact inverse and archives home result", function()
    local f = fixture({reads = {"NAVIGATE", "RETURN"}})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 0)
    equal(run(f, {"return"}), 0)
    equal(f.robot.pose.x, 0)
    equal(f.robot.pose.z, 0)
    equal(f.robot.pose.heading, "north")
    truthy(f.store.archived())
    local calls = table.concat(f.robot.calls, ",")
    contains(calls, "turn_left,move_forward")
    contains(calls, "move_backward,turn_right")
    for _, operation in ipairs(f.robot.calls) do
      truthy(operation == "status" or operation == "turn_left"
        or operation == "turn_right" or operation == "move_forward"
        or operation == "move_backward", "unsupported Stage 3 operation " .. operation)
    end
  end)

  test("return refuses a preexisting vertical breadcrumb without transmission", function()
    local f = fixture({reads = {"RETURN"}})
    local snapshot = assert(navState.createMission({mode = "ready",
      journal_health = "healthy", epoch = epoch, high_water = 0,
      pose = pose.new()}, {mission_id = "mission-vertical-legacy",
      destination = {x = 0, y = 1, z = 0}, action_limit = 160,
      owner = "host-test"}))
    truthy(f.store.create(snapshot))
    assert(navState.prepareIntent(f.store, snapshot, {
      operation = "move_up", recipient = robotAddress
    }))
    local request = assert(navState.requestForPending(snapshot))
    local response = f.robot.send(request.operation, {
      request_id = request.request_id, deployment_id = request.deployment_id,
      arguments = request.arguments
    })
    assert(navState.recordResult(f.store, snapshot, response))
    assert(navState.markDestination(f.store, snapshot))
    local executions = f.robot.executions
    equal(run(f, {"return"}), 1)
    equal(f.robot.executions, executions)
    equal(snapshot.return_state.frozen, false)
    contains(table.concat(f.errors, "\n"), "Stage 3")
  end)

  test("return revalidates status after confirmation before freezing breadcrumbs", function()
    local f = fixture({reads = {"NAVIGATE", "RETURN"}, endpoint = {
      status = function(call)
        if call == 4 then return {high_water = 99} end
      end
    }})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 0)
    local executions = f.robot.executions
    equal(run(f, {"return"}), 1)
    equal(f.robot.executions, executions)
    local snapshot = assert(f.store.snapshot())
    equal(snapshot.phase, "at_destination")
    equal(snapshot.return_state.frozen, false)
  end)

  test("partial outbound exact return archives an aborted mission", function()
    local f = fixture({reads = {"NAVIGATE", "RETURN"}, endpoint = {
      fail = function(operation) return operation == "move_forward" end
    }})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 1)
    local partial = assert(f.store.snapshot())
    equal(#partial.breadcrumbs, 1)
    equal(partial.pose.heading, "west")
    equal(run(f, {"return"}), 0)
    local live = assert(f.store.live())
    equal(live.terminal.outcome, "aborted")
    equal(f.robot.pose.x, 0)
    equal(f.robot.pose.heading, "north")
    truthy(f.store.archived())
  end)

  test("resume recovers a lost return reply and continues frozen cursor", function()
    local returning, lost = false, true
    local f = fixture({reads = {"NAVIGATE", "RETURN", "RESUME"}, endpoint = {
      lose = function(operation)
        if returning and lost and operation == "move_backward" then
          lost = false
          return true
        end
      end
    }})
    equal(run(f, {"go", "--x", "-1", "--y", "0", "--z", "0",
      "--heading", "west"}), 0)
    returning = true
    equal(run(f, {"return"}), 1)
    local pending = assert(f.store.snapshot()).pending
    equal(pending.operation, "move_backward")
    equal(pending.phase, "returning")
    equal(run(f, {"resume"}), 0)
    equal(f.robot.pose.x, 0)
    equal(f.robot.pose.heading, "north")
    truthy(f.store.archived())
  end)

  test("cooperating controller programs all use owner cleanup", function()
    for _, path in ipairs({
      "machines/controller/home/ocianav.lua",
      "machines/controller/home/ociactl.lua",
      "machines/controller/home/ociafarm.lua",
      "machines/controller/home/drive.lua"
    }) do
      local handle = assert(io.open(path, "r"))
      local source = assert(handle:read("*a"))
      handle:close()
      contains(source, "ocia.controller_owner")
      contains(source, "cleanup")
    end
  end)

  test("legacy controller entrypoints release owner and opened modem", function()
    local function execute(path, arguments, extraModules, input)
      local released, opened, closed = 0, 0, 0
      local modem = {address = "11111111-1111-1111-1111-111111111111"}
      function modem.isWireless() return true end
      function modem.isOpen() return false end
      function modem.open() opened = opened + 1; return true end
      function modem.close() closed = closed + 1; return true end
      function modem.broadcast() return true end
      local modules = {
        component = {modem = modem},
        computer = {uptime = function() return 0 end},
        event = {pull = function() return nil end},
        uuid = {next = function() return "test-uuid" end},
        ["ocia.config"] = {load = function() return {
          port = 4242, controller_address = modem.address,
          robot_address = robotAddress, timeout = 8
        } end},
        ["ocia.controller_owner"] = {acquire = function()
          return {release = function() released = released + 1 end}
        end},
        ["ocia.protocol"] = protocol,
        ["ocia.transport"] = {new = function() return {sendRequest = function()
          return {certainty = "succeeded", status = "succeeded", code = "status",
            message = "ok", payload = {mode = "ready", pose_trusted = "true",
              x = "0", y = "0", z = "0", heading = "north", epoch = epoch,
              high_water = "0", journal_health = "healthy"}}
        end} end}
      }
      for name, module in pairs(extraModules or {}) do modules[name] = module end
      local environment = setmetatable({
        require = function(name) return assert(modules[name], name) end,
        io = {write = function() end, read = function() return input end,
          stderr = {write = function() end}},
        os = {exit = function(code) error({exit = code or 0}, 0) end},
        print = function() end
      }, {__index = _G})
      local chunk = assert(loadfile(path, "t", environment))
      local ok, reason = pcall(chunk, table.unpack(arguments or {}))
      if not ok and not (type(reason) == "table" and reason.exit ~= nil) then
        error(reason)
      end
      return released, opened, closed
    end

    local released, opened, closed = execute(
      "machines/controller/home/drive.lua", {}, nil, "q")
    equal(released, 1); equal(opened, 1); equal(closed, 1)

    released, opened, closed = execute(
      "machines/controller/home/ociactl.lua", {"status"})
    equal(released, 1); equal(opened, 1); equal(closed, 1)

    local farmModule = {
      plan = function() return {stage = "single", width = 1, depth = 1,
        cells = {}, till_count = 0, plant_count = 0, movement_count = 0,
        turn_count = 0, steps = {}, clearance = {start = {x = 0, z = -1},
          finish = {x = 0, z = -1}}} end,
      poseFromStatus = function() return pose.new() end,
      expectedEnd = function() return pose.new() end,
      positionForLocal = function() return {x = 0, y = 0, z = 0} end,
      targetForCell = function() return {x = 0, y = -1, z = 0} end
    }
    released, opened, closed = execute(
      "machines/controller/home/ociafarm.lua", {"plan", "single"},
      {["ocia.farm"] = farmModule})
    equal(released, 1); equal(opened, 1); equal(closed, 1)

    local constructorFailure = {new = function() error("injected constructor failure") end}
    released, opened, closed = execute(
      "machines/controller/home/ociactl.lua", {"status"},
      {["ocia.transport"] = constructorFailure})
    equal(released, 1); equal(opened, 1); equal(closed, 1)

    released, opened, closed = execute(
      "machines/controller/home/ociafarm.lua", {"plan", "single"},
      {["ocia.farm"] = farmModule, ["ocia.transport"] = constructorFailure})
    equal(released, 1); equal(opened, 1); equal(closed, 1)
  end)

  test("status is read-only and nonphysical", function()
    local f = fixture()
    equal(run(f, {"status"}), 0)
    equal(f.store.snapshot(), nil)
    equal(f.robot.executions, 0)
    equal(table.concat(f.robot.calls, ","), "status")
  end)
end

return cases
