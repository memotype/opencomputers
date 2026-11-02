-- Supervised coordinate navigation with reactive local 3D traversal and exact return.
local nav = require("ocia.nav")
local pose = require("ocia.pose")

local cli = {}
local JOURNAL_PATH = "/var/lib/ocia/nav.state"
local ACTION_LIMIT = 160
local ENTITY_RETRIES = 2
local REACTIVE_INCIDENT_LIMIT = 12
local liveCommands = {go = true, status = true, ["return"] = true, resume = true}
local headings = {north = true, east = true, south = true, west = true}
local movementOperations = {
  turn_left = true, turn_right = true,
  move_forward = true, move_backward = true,
  move_up = true, move_down = true
}
local horizontalOperations = {move_forward = true, move_backward = true}
local probeKinds = {
  air = true, entity = true, replaceable = true,
  passable = true, solid = true, liquid = true
}

local function write(dependencies, line)
  if dependencies and dependencies.stdout then dependencies.stdout(line)
  else io.write(line, "\n") end
end

local function writeError(dependencies, line)
  if dependencies and dependencies.stderr then dependencies.stderr(line)
  else io.stderr:write(line, "\n") end
end

local function usage(dependencies)
  writeError(dependencies, "Usage:")
  writeError(dependencies, "  ocianav plan --x X --y Y --z Z [--heading HEADING]")
  writeError(dependencies, "  ocianav go --x X --y Y --z Z [--heading HEADING]")
  writeError(dependencies, "  ocianav status")
  writeError(dependencies, "  ocianav return")
  writeError(dependencies, "  ocianav resume")
end

local function parseInteger(text)
  if type(text) ~= "string" or not text:match("^[+-]?%d+$") then return nil end
  local value = tonumber(text)
  if not value or value ~= math.floor(value) or math.abs(value) > 9007199254740991 then
    return nil
  end
  return value
end

function cli.parse(arguments)
  if type(arguments) ~= "table" then return nil, "arguments must be a table" end
  local command = arguments[1]
  if command ~= "plan" and command ~= "go" and command ~= "status"
      and command ~= "return" and command ~= "resume" then
    return nil, "command must be plan, go, status, return, or resume"
  end
  if command == "status" or command == "return" or command == "resume" then
    if #arguments ~= 1 then return nil, command .. " does not accept options" end
    return {command = command}
  end

  local values, index = {}, 2
  while index <= #arguments do
    local option, raw = arguments[index], arguments[index + 1]
    if option ~= "--x" and option ~= "--y" and option ~= "--z"
        and option ~= "--heading" then
      return nil, "unknown option " .. tostring(option)
    end
    if raw == nil then return nil, "missing value for " .. option end
    if values[option] ~= nil then return nil, "duplicate option " .. option end
    values[option] = raw
    index = index + 2
  end
  for _, option in ipairs({"--x", "--y", "--z"}) do
    if values[option] == nil then return nil, "missing required option " .. option end
  end
  local destination = {}
  for _, axis in ipairs({"x", "y", "z"}) do
    destination[axis] = parseInteger(values["--" .. axis])
    if destination[axis] == nil then return nil, axis .. " must be a signed safe integer" end
  end
  if values["--heading"] then
    if not headings[values["--heading"]] then return nil, "heading is invalid" end
    destination.heading = values["--heading"]
  end
  return {command = command, destination = destination}
end

local function poseText(value)
  if type(value) ~= "table" then return "<missing>" end
  return string.format("(%s,%s,%s) %s%s", tostring(value.x), tostring(value.y),
    tostring(value.z), tostring(value.heading), value.trusted == false and " [untrusted]" or "")
end

local function printPlan(dependencies, plan, label)
  write(dependencies, label or "Navigation plan")
  write(dependencies, "Assumed start: " .. poseText(plan.start_pose))
  write(dependencies, "Destination: " .. poseText(plan.expected_end))
  write(dependencies, string.format("Distance: %d/%d; movements: %d; turns: %d; actions: %d",
    plan.distance, plan.max_distance, plan.movement_count, plan.turn_count, plan.cost))
  write(dependencies, string.format("Inverse return cost: %d; mission action limit: %d",
    plan.inverse_cost, ACTION_LIMIT))
  write(dependencies, "Terrain: " .. plan.terrain_model
    .. "; traversability: " .. plan.traversability)
  write(dependencies, "Physical operations:")
  if #plan.operations == 0 then write(dependencies, "  (none)") end
  for index, operation in ipairs(plan.operations) do
    write(dependencies, string.format("  %d. %s", index, operation))
  end
end

local function planFrom(start, destination, maximum)
  return nav.plan(start, destination, {max_distance = maximum or nav.DEFAULT_MAX_DISTANCE})
end

local function confirmation(dependencies, literal)
  write(dependencies, "Type " .. literal .. " to continue:")
  local value
  if dependencies and dependencies.read then value = dependencies.read()
  else value = io.read() end
  return value == literal
end

local function defaultContext(label)
  local component = require("component")
  local computer = require("computer")
  local event = require("event")
  local filesystem = require("filesystem")
  local uuid = require("uuid")
  local configModule = require("ocia.config")
  local controllerOwner = require("ocia.controller_owner")
  local navState = require("ocia.nav_state")
  local transportModule = require("ocia.transport")

  local config, configReason = configModule.load("/etc/ocia.cfg", "controller")
  if not config then return nil, "configuration error: " .. tostring(configReason) end
  local modem = component.modem
  if not modem or not modem.isWireless() then return nil, "controller wireless modem is unavailable" end
  if modem.address ~= config.controller_address then
    return nil, "configured controller address does not match this modem"
  end
  local lease, ownerReason = controllerOwner.acquire(config.port, label)
  if not lease then return nil, ownerReason end
  local openedHere = false
  local ok, value = xpcall(function()
    if not modem.isOpen(config.port) then
      assert(modem.open(config.port), "cannot open modem port " .. config.port)
      openedHere = true
    end
    local client = transportModule.new({modem = modem, event = event,
      computer = computer, config = config, request_id = uuid.next})
    local context = {config = config, client = client, navState = navState,
      store = navState.journalStore(JOURNAL_PATH), missionId = uuid.next,
      sleep = os.sleep or function(seconds) computer.pullSignal(seconds) end}
    function context.archives()
      local result = {}
      local directory = filesystem.path(JOURNAL_PATH)
      local prefix = filesystem.name(JOURNAL_PATH) .. ".archive."
      if not filesystem.exists(directory) then return result end
      for name in filesystem.list(directory) do
        if name:sub(1, #prefix) == prefix and name ~= prefix .. "switch" then
          result[#result + 1] = filesystem.concat(directory, name)
        end
      end
      table.sort(result)
      return result
    end
    local closed = false
    function context.close()
      if closed then return end
      closed = true
      if openedHere then pcall(modem.close, config.port) end
      lease.release()
    end
    return context
  end, debug.traceback)
  if not ok then
    if openedHere then pcall(modem.close, config.port) end
    lease.release()
    return nil, value
  end
  return value
end

local function openContext(dependencies, label)
  if dependencies and dependencies.contextFactory then
    return dependencies.contextFactory(label)
  end
  return defaultContext(label)
end

local function statusResponse(context)
  local response = context.client:sendRequest("status")
  if type(response) ~= "table" or response.certainty ~= "succeeded"
      or response.status ~= "succeeded" or response.code ~= "status"
      or type(response.payload) ~= "table" then
    return nil, "fresh robot status failed: "
      .. tostring(response and response.status or "no_response") .. " / "
      .. tostring(response and response.code or "unknown") .. ": "
      .. tostring(response and response.message or "no response")
  end
  return response.payload, response
end

local function statusPose(payload)
  if type(payload) ~= "table" then return nil end
  local trusted = payload.pose_trusted == true or payload.pose_trusted == "true"
  local value = {trusted = trusted, x = tonumber(payload.x), y = tonumber(payload.y),
    z = tonumber(payload.z), heading = payload.heading, reason = payload.pose_reason or ""}
  if not pose.validate(value) then return nil end
  return value
end

local function sameStartingStatus(left, right)
  local leftPose, rightPose = statusPose(left), statusPose(right)
  return left.mode == "ready" and right.mode == "ready"
    and left.journal_health == "healthy" and right.journal_health == "healthy"
    and left.epoch == right.epoch
    and tonumber(left.high_water) == tonumber(right.high_water)
    and leftPose and rightPose and pose.equal(leftPose, rightPose)
end

local function printRobotStatus(dependencies, payload)
  if not payload then write(dependencies, "Live robot status: unavailable"); return end
  write(dependencies, "Live robot: " .. tostring(payload.mode)
    .. "; journal " .. tostring(payload.journal_health))
  write(dependencies, "Robot pose: " .. poseText(statusPose(payload)))
  write(dependencies, "Robot epoch/high water: " .. tostring(payload.epoch)
    .. "/" .. tostring(payload.high_water))
  if payload.energy then
    write(dependencies, "Robot energy: " .. tostring(payload.energy)
      .. "/" .. tostring(payload.capacity))
  end
end

local function printMission(dependencies, snapshot, metadata)
  if not snapshot then
    if metadata and metadata.source == "corrupt" then
      write(dependencies, "Controller journal: corrupt: " .. tostring(metadata.error))
    else
      write(dependencies, "Controller journal: no active mission")
    end
    return
  end
  write(dependencies, "Controller journal: " .. tostring(snapshot.journal.health)
    .. "; source " .. tostring(metadata and metadata.source))
  if snapshot.mission_id == "" then return end
  write(dependencies, "Mission: " .. snapshot.mission_id .. "; phase " .. snapshot.phase)
  write(dependencies, "Mission pose: " .. poseText(snapshot.pose))
  write(dependencies, string.format("Mission high water/actions: %s/%s of %s",
    tostring(snapshot.high_water), tostring(snapshot.physical_actions),
    tostring(snapshot.limits.action_limit)))
  write(dependencies, string.format("Breadcrumbs: %d; return cursor: %d; reconcile: %s",
    #snapshot.breadcrumbs, snapshot.return_state.cursor,
    tostring(snapshot.reconciliation_required)))
  if snapshot.pending then
    write(dependencies, "Pending: " .. snapshot.pending.request_id .. " / "
      .. snapshot.pending.operation .. " / "
      .. tostring(snapshot.pending.observation and snapshot.pending.observation.classification
        or "unobserved"))
  end
  write(dependencies, "Home reached: " .. tostring(snapshot.home_pose_reached)
    .. "; charging verified: " .. tostring(snapshot.charging_verified))
  if snapshot.terminal then
    write(dependencies, "Terminal: " .. snapshot.terminal.outcome .. ": "
      .. snapshot.terminal.reason)
  end
end

local function loadMission(context)
  return context.store.load()
end

local function validMovementPlan(plan)
  for _, operation in ipairs(plan.operations) do
    if not movementOperations[operation] then
      return nil, "navigation route contains an unsupported physical operation"
    end
  end
  return true
end

local function validateNavigationMission(snapshot)
  if snapshot.pending then
    if not movementOperations[snapshot.pending.operation] then
      return nil, "navigation cannot resume pending operation "
        .. tostring(snapshot.pending.operation)
        .. "; supervised manual recovery is required"
    end
  end
  for _, entry in ipairs(snapshot.breadcrumbs) do
    if not movementOperations[entry.operation] then
      return nil, "navigation cannot resume incompatible outbound breadcrumb "
        .. tostring(entry.operation)
        .. "; supervised manual recovery is required"
    end
  end
  for _, entry in ipairs(snapshot.return_state.steps) do
    if not movementOperations[entry.operation] then
      return nil, "navigation cannot resume incompatible return history; supervised manual recovery is required"
    end
  end
  if snapshot.return_state.frozen then
    for index = snapshot.return_state.cursor, 1, -1 do
      local operation = assert(nav.inverse({snapshot.breadcrumbs[index].operation}))[1]
      if not movementOperations[operation] then
        return nil, "navigation cannot resume an incompatible frozen return; supervised manual recovery is required"
      end
    end
  end
  return true
end

local function budgetOutbound(snapshot, plan)
  local required = snapshot.physical_actions + plan.cost
    + #snapshot.breadcrumbs + plan.cost
  if required > tonumber(snapshot.limits.action_limit) then
    return nil, "remaining outbound and exact return exceed the physical-action limit"
  end
  return true, required
end

local function budgetReturn(snapshot)
  if snapshot.physical_actions + snapshot.return_state.cursor
      > tonumber(snapshot.limits.action_limit) then
    return nil, "remaining inverse return exceeds the physical-action limit"
  end
  return true
end

local function budgetInitialReturn(snapshot)
  if snapshot.physical_actions + #snapshot.breadcrumbs
      > tonumber(snapshot.limits.action_limit) then
    return nil, "initial inverse return exceeds the physical-action limit"
  end
  return true
end

local function requestText(snapshot)
  local pending = snapshot.pending
  return pending.request_id .. " " .. pending.operation .. " "
    .. poseText(pending.before) .. " -> " .. poseText(pending.expected)
end

local function sendPending(context, snapshot, request, dependencies)
  if request.recipient ~= context.config.robot_address then
    return {status = "local_rejection", code = "recipient_changed",
      message = "configured robot differs from the durably recorded recipient"}
  end
  write(dependencies, "Mission " .. snapshot.mission_id .. " sending: "
    .. requestText(snapshot))
  return context.client:sendRequest(request.operation, {
    request_id = request.request_id,
    deployment_id = request.deployment_id,
    arguments = request.arguments
  })
end

local function reconcileConsumed(context, snapshot, dependencies)
  local fresh, reason = statusResponse(context)
  if not fresh then return nil, reason end
  local reconciled, reconcileReason = context.navState.recordReconciliation(
    context.store, snapshot, fresh)
  if not reconciled then return nil, "post-result reconciliation failed: "
    .. tostring(reconcileReason) end
  return true
end

local function recordAndReport(context, snapshot, response, dependencies)
  local classification, reason = context.navState.recordResult(
    context.store, snapshot, response)
  if not classification then
    return nil, "controller result persistence failed: " .. tostring(reason)
  end
  write(dependencies, "Result: " .. classification.kind .. " / "
    .. tostring(classification.code) .. ": " .. tostring(classification.message))
  if classification.energy ~= nil and classification.energy ~= "" then
    write(dependencies, "Result energy evidence: " .. tostring(classification.energy))
  end
  write(dependencies, "Durable phase/high water/actions: " .. snapshot.phase .. "/"
    .. snapshot.high_water .. "/" .. snapshot.physical_actions)
  if classification.kind == "success" then return classification end
  if classification.kind == "completed_failure"
      or classification.kind == "definite_nonexecution"
      or classification.kind == "local_nonsend" then
    local reconciled, reconcileReason = reconcileConsumed(context, snapshot, dependencies)
    if not reconciled then
      return nil, classification.kind .. "; " .. tostring(reconcileReason)
    end
  end
  return nil, "physical execution stopped after " .. classification.kind, classification
end

local function guardOutboundReturnBudget(snapshot)
  if snapshot.phase ~= "outbound" then return true end
  local limit = tonumber(snapshot.limits.action_limit)
  local requiredIfSuccessful = snapshot.physical_actions + 1
    + #snapshot.breadcrumbs + 1
  if requiredIfSuccessful > limit then
    return nil, "outbound action refused: insufficient physical-action budget "
      .. "to reverse all successful breadcrumbs"
  end
  return true
end

local function executeOperation(context, snapshot, operation, dependencies)
  local budgetOk, budgetReason = guardOutboundReturnBudget(snapshot)
  if not budgetOk then return nil, budgetReason end
  local pending, reason = context.navState.prepareIntent(context.store, snapshot, {
    operation = operation, arguments = {}, recipient = context.config.robot_address
  })
  if not pending then return nil, "intent persistence failed: " .. tostring(reason) end
  if not context.navState.canTransmit(snapshot) then
    return nil, "newly persisted intent is not authorized for first transmission"
  end
  local request, requestReason = context.navState.requestForPending(snapshot)
  if not request then return nil, requestReason end
  return recordAndReport(context, snapshot,
    sendPending(context, snapshot, request, dependencies), dependencies)
end

local function executeRetry(context, snapshot, status, dependencies)
  local authorized, reason = context.navState.authorizeRetry(
    context.store, snapshot, status)
  if not authorized then return nil, "identical retry authorization failed: "
    .. tostring(reason) end
  if not context.navState.canRetryPending(snapshot) then
    return nil, "identical retry permission was not published"
  end
  local request, requestReason = context.navState.retryRequest(snapshot)
  if not request then return nil, requestReason end
  return recordAndReport(context, snapshot,
    sendPending(context, snapshot, request, dependencies), dependencies)
end

local function executeOperations(context, snapshot, operations, dependencies)
  for _, operation in ipairs(operations) do
    local result, reason = executeOperation(context, snapshot, operation, dependencies)
    if not result then return nil, reason end
  end
  return true
end

local function probeResponse(context)
  local response = context.client:sendRequest("nav_probe")
  if type(response) ~= "table" or response.certainty ~= "succeeded"
      or response.status ~= "succeeded" or response.code ~= "nav_probe"
      or type(response.payload) ~= "table" then
    return nil, "navigation probe failed: "
      .. tostring(response and response.status or "no_response") .. " / "
      .. tostring(response and response.code or "unknown") .. ": "
      .. tostring(response and response.message or "no response")
  end
  return response.payload
end

local function probeBlocked(payload, direction)
  local value = payload[direction .. "_blocked"]
  return value == true or value == "true"
end

local function probeKind(payload, direction)
  local value = tostring(payload[direction .. "_kind"] or "unknown"):lower()
  return probeKinds[value] and value or "unknown"
end

local function entityFailure(classification)
  return classification and tostring(classification.message or ""):lower():find(
    "entity", 1, true) ~= nil
end

local function retryEntity(context, snapshot, operation, classification, dependencies)
  local current = classification
  for attempt = 1, ENTITY_RETRIES do
    if not entityFailure(current) then break end
    write(dependencies, string.format(
      "Entity obstructed %s; bounded retry %d/%d", operation, attempt, ENTITY_RETRIES))
    if context.sleep then context.sleep(1) end
    local result, reason, nextClassification = executeOperation(
      context, snapshot, operation, dependencies)
    if result then return true end
    current = nextClassification
    if not current then return nil, reason end
  end
  return nil, "entity remained in the route after bounded retries", current
end

local function safeProbeMove(context, snapshot, operation, direction, dependencies)
  local probe, reason = probeResponse(context)
  if not probe then return nil, reason end
  local kind = probeKind(probe, direction)
  if kind == "liquid" or kind == "solid" or kind == "entity" then
    return nil, "refusing " .. operation .. " toward detected " .. kind
  end
  if kind == "unknown" then
    return nil, "refusing " .. operation .. " with unknown adjacent terrain"
  end
  if probeBlocked(probe, direction) and kind ~= "replaceable" and kind ~= "passable" then
    return nil, "refusing " .. operation .. " toward detected " .. kind
  end
  return executeOperation(context, snapshot, operation, dependencies)
end

local function detourCandidate(context, snapshot, turnOut, turnBack, dependencies)
  local turned, reason = executeOperation(context, snapshot, turnOut, dependencies)
  if not turned then return nil, reason, false end
  local probe, probeReason = probeResponse(context)
  if not probe then return nil, probeReason, false end
  local sideKind = probeKind(probe, "front")
  if sideKind == "liquid" or sideKind == "unknown" then
    local restored, restoreReason = executeOperation(context, snapshot, turnBack, dependencies)
    if not restored then return nil, restoreReason, false end
    return nil, "lateral candidate contains " .. sideKind, true
  end
  local side, sideReason, sideClassification = executeOperation(
    context, snapshot, "move_forward", dependencies)
  if not side then
    local restored, restoreReason = executeOperation(context, snapshot, turnBack, dependencies)
    if not restored then return nil, restoreReason, false end
    return nil, sideReason, true, sideClassification
  end
  local aligned, alignReason = executeOperation(context, snapshot, turnBack, dependencies)
  if not aligned then return nil, alignReason, false end
  local aheadProbe, aheadReason = probeResponse(context)
  if not aheadProbe then return nil, aheadReason, false end
  local aheadKind = probeKind(aheadProbe, "front")
  if aheadKind == "liquid" or aheadKind == "unknown" then
    return nil, "lateral candidate reaches " .. aheadKind, false
  end
  local around, aroundReason, aroundClassification = executeOperation(
    context, snapshot, "move_forward", dependencies)
  if not around then return nil, aroundReason, false, aroundClassification end
  return true
end

local function handleHorizontalFailure(context, snapshot, operation,
    classification, dependencies)
  if entityFailure(classification) then
    return retryEntity(context, snapshot, operation, classification, dependencies)
  end

  -- The probe sees only the front. Turn around after a failed backward move so
  -- it examines the transition that actually failed; both turns remain normal
  -- journaled breadcrumbs.
  if operation == "move_backward" then
    local turned, reason = executeOperations(context, snapshot,
      {"turn_left", "turn_left"}, dependencies)
    if not turned then return nil, reason end
    operation = "move_forward"
  end

  local probe, probeReason = probeResponse(context)
  if not probe then return nil, probeReason end
  local frontKind = probeKind(probe, "front")
  if frontKind == "entity" then
    return retryEntity(context, snapshot, operation,
      {message = "entity"}, dependencies)
  end
  if frontKind == "liquid" then return nil, "detected liquid in the route" end
  if frontKind == "unknown" then return nil, "route classification is unknown" end

  local upKind = probeKind(probe, "up")
  if probeBlocked(probe, "front") and not probeBlocked(probe, "up")
      and upKind ~= "liquid" and upKind ~= "unknown" then
    write(dependencies, "Trying one-block climb over " .. frontKind)
    local climbed, climbReason = executeOperation(
      context, snapshot, "move_up", dependencies)
    if not climbed then return nil, climbReason end
    local across, acrossReason, acrossClassification = executeOperation(
      context, snapshot, "move_forward", dependencies)
    if across then return true end
    if entityFailure(acrossClassification) then
      return retryEntity(context, snapshot, "move_forward",
        acrossClassification, dependencies)
    end
    write(dependencies, "One-block climb did not clear the obstruction; trying a lateral detour.")
  end

  write(dependencies, "Trying bounded left lateral detour.")
  local detoured, detourReason, mayTryOther = detourCandidate(
    context, snapshot, "turn_left", "turn_right", dependencies)
  if detoured then return true end
  if mayTryOther then
    write(dependencies, "Left detour was blocked; trying bounded right lateral detour.")
    local other, otherReason = detourCandidate(
      context, snapshot, "turn_right", "turn_left", dependencies)
    if other then return true end
    return nil, "both lateral detours failed: " .. tostring(otherReason)
  end
  return nil, "lateral detour failed: " .. tostring(detourReason)
end

local function reachedDestination(snapshot)
  local value = snapshot.breadcrumbs[#snapshot.breadcrumbs]
  value = value and value.after or snapshot.home
  return value.x == snapshot.destination.x and value.y == snapshot.destination.y
    and value.z == snapshot.destination.z
    and (not snapshot.destination.heading or value.heading == snapshot.destination.heading)
end

local function finalizeHome(context, snapshot, dependencies)
  if snapshot.phase ~= "home_pose_reached" then
    return nil, "home pose has not been freshly reconciled"
  end
  local completed = reachedDestination(snapshot)
  local outcome = completed and "navigation_complete" or "aborted"
  local reason = completed and "destination reached and exact inverse return reconciled"
    or "returned home before the requested destination was reached"
  local terminated, terminateReason = context.navState.terminate(
    context.store, snapshot, outcome, reason)
  if not terminated then return nil, "terminal persistence failed: "
    .. tostring(terminateReason) end
  local archive, archiveReason = context.store.archive(snapshot)
  if not archive then return nil, "mission archive failed: " .. tostring(archiveReason) end
  write(dependencies, "Mission terminal outcome: " .. outcome)
  write(dependencies, "Mission archive: " .. archive)
  write(dependencies, "Charging verified: false")
  return true
end

local function completeReturn(context, snapshot, dependencies)
  local ok, reason = budgetReturn(snapshot)
  if not ok then return nil, reason end
  while snapshot.return_state.cursor > 0 do
    local entry = snapshot.breadcrumbs[snapshot.return_state.cursor]
    local operation = assert(nav.inverse({entry.operation}))[1]
    if not movementOperations[operation] then
      return nil, "navigation refuses an incompatible inverse return operation"
    end
    local result, operationReason, classification = executeOperation(
      context, snapshot, operation, dependencies)
    if not result and entityFailure(classification) then
      result, operationReason = retryEntity(
        context, snapshot, operation, classification, dependencies)
    end
    if not result then return nil, operationReason end
  end
  local fresh, statusReason = statusResponse(context)
  if not fresh then return nil, statusReason end
  local reconciled, reconcileReason = context.navState.recordReconciliation(
    context.store, snapshot, fresh)
  if not reconciled then return nil, "home reconciliation failed: "
    .. tostring(reconcileReason) end
  return finalizeHome(context, snapshot, dependencies)
end

local function runPlan(parsed, dependencies)
  local plan, reason = planFrom(pose.new(), parsed.destination)
  if not plan then writeError(dependencies, reason); return 2 end
  printPlan(dependencies, plan, "Navigation preview (no hardware or state access)")
  write(dependencies, "Plan only: no robot was contacted and no state was written.")
  return 0
end

local function runStatus(context, dependencies)
  local snapshot, metadata = loadMission(context)
  local payload, response = statusResponse(context)
  if payload then
    write(dependencies, "Live status result: " .. tostring(response.certainty)
      .. " / " .. tostring(response.status) .. " / " .. tostring(response.code))
    printRobotStatus(dependencies, payload)
  else writeError(dependencies, response) end
  printMission(dependencies, snapshot, metadata)
  if not snapshot and context.archives then
    local archives = context.archives()
    if #archives > 0 then
      write(dependencies, "Archived navigation missions: " .. #archives)
      for _, archive in ipairs(archives) do write(dependencies, "  " .. archive) end
    end
  end
  return payload and 0 or 1
end

local continueOutbound

local function runGo(context, parsed, dependencies)
  local existing, metadata = loadMission(context)
  if existing or not metadata or metadata.source ~= "new" then
    printMission(dependencies, existing, metadata)
    return nil, "an active, terminal, corrupt, or uncertain navigation journal exists"
  end
  local previewStatus, statusReason = statusResponse(context)
  if not previewStatus then return nil, statusReason end
  local plan, planReason = planFrom(pose.new(), parsed.destination)
  if not plan then return nil, planReason, 2 end
  local valid, validReason = validMovementPlan(plan)
  if not valid then return nil, validReason end
  local preview, previewReason = context.navState.createMission(previewStatus, {
    mission_id = "preview-status", destination = parsed.destination,
    action_limit = ACTION_LIMIT, owner = "ocianav"
  })
  if not preview then return nil, previewReason end
  if plan.cost + plan.inverse_cost > ACTION_LIMIT then
    return nil, "outbound and exact return exceed the physical-action limit"
  end
  printRobotStatus(dependencies, previewStatus)
  printPlan(dependencies, plan, "Supervised 3D navigation mission preview")
  write(dependencies, "Reactive checks handle one-block climbs, bounded lateral detours, and temporary entities.")
  write(dependencies, "No complete terrain survey, measured energy reserve, or charging proof is included.")
  if not confirmation(dependencies, "NAVIGATE") then
    write(dependencies, "Confirmation cancelled; no mission was created.")
    return true
  end
  local confirmedStatus, confirmedReason = statusResponse(context)
  if not confirmedStatus then return nil, confirmedReason end
  if not sameStartingStatus(previewStatus, confirmedStatus) then
    return nil, "robot status changed after preview; no mission was created"
  end
  local snapshot, createReason = context.navState.createMission(confirmedStatus, {
    mission_id = context.missionId(), destination = parsed.destination,
    action_limit = ACTION_LIMIT, owner = "ocianav",
    limits = {stage = "3d", planned_outbound = plan.cost,
      planned_return = plan.inverse_cost}
  })
  if not snapshot then return nil, createReason end
  local created, persistReason = context.store.create(snapshot)
  if not created then return nil, "mission creation persistence failed: "
    .. tostring(persistReason) end
  local budgetOk, budgetReason = budgetOutbound(snapshot, plan)
  if not budgetOk then return nil, budgetReason end
  local executed, executeReason = continueOutbound(
    context, snapshot, dependencies, plan)
  if not executed then return nil, executeReason end
  return true
end

local function preflightExisting(context, dependencies)
  local snapshot, metadata = loadMission(context)
  if not snapshot or snapshot.mission_id == "" then
    printMission(dependencies, snapshot, metadata)
    return nil, "no healthy active navigation mission is available"
  end
  if snapshot.journal.health ~= "healthy" then
    return nil, "controller navigation journal is not healthy"
  end
  local fresh, statusReason = statusResponse(context)
  if not fresh then return nil, statusReason end
  local assessment = context.navState.assessStatus(snapshot, fresh)
  if not assessment.ok then return nil, assessment.reason end
  return snapshot, fresh, assessment
end

local function runReturn(context, dependencies)
  local snapshot, previewStatus, assessment = preflightExisting(context, dependencies)
  if not snapshot then return nil, previewStatus end
  if snapshot.pending then return nil, "resume must resolve the pending exact request before return" end
  local compatible, compatibilityReason = validateNavigationMission(snapshot)
  if not compatible then return nil, compatibilityReason end
  if snapshot.phase ~= "outbound" and snapshot.phase ~= "at_destination"
      and snapshot.phase ~= "recovery_required" then
    return nil, "return cannot start from phase " .. snapshot.phase .. "; use resume"
  end
  local operations = {}
  for index = #snapshot.breadcrumbs, 1, -1 do
    operations[#operations + 1] = assert(nav.inverse({snapshot.breadcrumbs[index].operation}))[1]
  end
  local valid, validReason = validMovementPlan({operations = operations})
  if not valid then return nil, validReason end
  local budgetOk, budgetReason = budgetInitialReturn(snapshot)
  if not budgetOk then return nil, budgetReason end
  write(dependencies, "Exact inverse return from " .. poseText(snapshot.pose))
  write(dependencies, string.format("Return actions remaining: %d; used/limit: %d/%d",
    #operations, snapshot.physical_actions, snapshot.limits.action_limit))
  write(dependencies, "Return retries temporary entity obstruction but stops on a new solid obstacle.")
  write(dependencies, "Return does not prove charging.")
  for index, operation in ipairs(operations) do
    write(dependencies, string.format("  %d. %s", index, operation))
  end
  if not confirmation(dependencies, "RETURN") then
    write(dependencies, "Confirmation cancelled; return state was not changed.")
    return true
  end
  local confirmedStatus, statusReason = statusResponse(context)
  if not confirmedStatus then return nil, statusReason end
  local confirmed = context.navState.assessStatus(snapshot, confirmedStatus)
  if not confirmed.ok or confirmed.action ~= "continue" then
    return nil, confirmed.reason or "post-confirmation return status is inconsistent"
  end
  local reconciled, reconcileReason = context.navState.recordReconciliation(
    context.store, snapshot, confirmedStatus)
  if not reconciled then return nil, reconcileReason end
  budgetOk, budgetReason = budgetInitialReturn(snapshot)
  if not budgetOk then return nil, budgetReason end
  local begun, beginReason = context.navState.beginReturn(context.store, snapshot)
  if not begun then return nil, beginReason end
  return completeReturn(context, snapshot, dependencies)
end

continueOutbound = function(context, snapshot, dependencies, preparedPlan)
  local plan = preparedPlan
  local incidents = 0
  while not reachedDestination(snapshot) do
    if not plan then
      local reason
      plan, reason = planFrom(snapshot.pose, snapshot.destination,
        tonumber(snapshot.limits.max_distance))
      if not plan then return nil, reason end
    end
    local valid, validReason = validMovementPlan(plan)
    if not valid then return nil, validReason end
    local budgetOk, budgetReason = budgetOutbound(snapshot, plan)
    if not budgetOk then return nil, budgetReason end
    local operation = plan.operations[1]
    if not operation then break end

    local result, operationReason, classification
    if operation == "move_down" then
      result, operationReason, classification = safeProbeMove(
        context, snapshot, operation, "down", dependencies)
    else
      result, operationReason, classification = executeOperation(
        context, snapshot, operation, dependencies)
    end
    if not result then
      if not classification or classification.kind ~= "completed_failure" then
        return nil, operationReason
      end
      incidents = incidents + 1
      if incidents > REACTIVE_INCIDENT_LIMIT then
        return nil, "reactive terrain incident limit exceeded"
      end
      if horizontalOperations[operation] then
        local recovered, recoveryReason = handleHorizontalFailure(
          context, snapshot, operation, classification, dependencies)
        if not recovered then return nil, recoveryReason end
      elseif entityFailure(classification) then
        local retried, retryReason = retryEntity(
          context, snapshot, operation, classification, dependencies)
        if not retried then return nil, retryReason end
      else
        return nil, operationReason
      end
    end
    plan = nil -- Replan from the actual durable pose after every action or detour.
  end
  if not reachedDestination(snapshot) then
    return nil, "navigation stopped without reaching the destination"
  end
  local marked, markReason = context.navState.markDestination(context.store, snapshot)
  if not marked then return nil, markReason end
  write(dependencies, "Destination reached and durably recorded.")
  return true
end

local function returnOperations(snapshot, cursor)
  local operations = {}
  for index = cursor, 1, -1 do
    operations[#operations + 1] = assert(nav.inverse(
      {snapshot.breadcrumbs[index].operation}))[1]
  end
  return operations
end

local function printOperations(dependencies, operations)
  if #operations == 0 then write(dependencies, "  (none)") end
  for index, operation in ipairs(operations) do
    write(dependencies, string.format("  %d. %s", index, operation))
  end
end

local function outboundContinuationPlan(snapshot, startPose)
  local plan, reason = planFrom(startPose, snapshot.destination,
    tonumber(snapshot.limits.max_distance))
  if not plan then return nil, reason end
  local valid, validReason = validMovementPlan(plan)
  if not valid then return nil, validReason end
  return plan
end

local function previewResume(snapshot, dependencies)
  local preview = {phase = snapshot.phase}
  if snapshot.pending then
    local pending = snapshot.pending
    write(dependencies, "Pending exact-request recovery")
    write(dependencies, "Mission/deployment: " .. snapshot.mission_id .. " / "
      .. tostring(pending.deployment_id))
    write(dependencies, "Request: " .. pending.request_id .. " / " .. pending.operation)
    write(dependencies, "Before: " .. poseText(pending.before))
    write(dependencies, "Expected success: " .. poseText(pending.expected))
    write(dependencies, "Pending observation: "
      .. tostring(pending.observation and pending.observation.classification or "none"))
    write(dependencies, "Recovery retransmits the same physical request ID; it does not allocate a new action identity.")
    if pending.phase == "outbound" then
      local plan, reason = outboundContinuationPlan(snapshot, pending.expected)
      if not plan then return nil, reason end
      preview.outbound_plan = plan
      local actionsAfter = snapshot.physical_actions + 1
      local breadcrumbsAfter = #snapshot.breadcrumbs + 1
      local required = actionsAfter + plan.cost + breadcrumbsAfter + plan.cost
      write(dependencies, "Conditional successful recovery: continue outbound from "
        .. poseText(pending.expected) .. " to " .. poseText(plan.expected_end))
      printOperations(dependencies, plan.operations)
      write(dependencies, string.format(
        "Conditional actions used/required-through-return/limit: %d/%d/%d",
        actionsAfter, required, snapshot.limits.action_limit))
      write(dependencies, "Conditional route assumes unobstructed terrain.")
    elseif pending.phase == "returning" then
      local cursor = snapshot.return_state.cursor - 1
      local operations = returnOperations(snapshot, cursor)
      write(dependencies, "Conditional successful recovery: continue frozen inverse return.")
      write(dependencies, "Conditional return cursor: " .. cursor)
      printOperations(dependencies, operations)
      write(dependencies, string.format(
        "Conditional actions used/remaining/limit: %d/%d/%d",
        snapshot.physical_actions + 1, cursor, snapshot.limits.action_limit))
    end
    return preview
  end

  if snapshot.phase == "outbound" then
    local plan, reason = outboundContinuationPlan(snapshot, snapshot.pose)
    if not plan then return nil, reason end
    local budgetOk, required = budgetOutbound(snapshot, plan)
    if not budgetOk then return nil, required end
    preview.outbound_plan = plan
    write(dependencies, "Resume outbound continuation")
    write(dependencies, "Starting pose: " .. poseText(snapshot.pose))
    write(dependencies, "Destination: " .. poseText(plan.expected_end))
    write(dependencies, "Ordered remaining operations:")
    printOperations(dependencies, plan.operations)
    write(dependencies, "Expected ending pose: " .. poseText(plan.expected_end))
    write(dependencies, "Physical actions already consumed: " .. snapshot.physical_actions)
    write(dependencies, string.format(
      "Remaining outbound actions: %d; required through inverse return: %d/%d",
      plan.cost, required, snapshot.limits.action_limit))
    write(dependencies, "Nominal route is unsurveyed; execution uses bounded reactive local checks.")
  elseif snapshot.phase == "returning" then
    local budgetOk, reason = budgetReturn(snapshot)
    if not budgetOk then return nil, reason end
    local operations = returnOperations(snapshot, snapshot.return_state.cursor)
    write(dependencies, "Resume frozen inverse return")
    write(dependencies, "Return cursor: " .. snapshot.return_state.cursor)
    write(dependencies, "Remaining inverse operations:")
    printOperations(dependencies, operations)
    write(dependencies, string.format("Physical actions used/remaining/limit: %d/%d/%d",
      snapshot.physical_actions, snapshot.return_state.cursor,
      snapshot.limits.action_limit))
  elseif snapshot.phase == "at_destination" then
    write(dependencies, "No physical movement: persist fresh status reconciliation, then use return for inverse travel.")
  elseif snapshot.phase == "home_pending_reconcile" then
    write(dependencies, "No physical movement: perform home-pose reconciliation, then persist the terminal record and archive.")
  elseif snapshot.phase == "home_pose_reached" then
    write(dependencies, "No physical movement: persist status reconciliation, terminal record, and archive rotation.")
  elseif snapshot.phase == "terminal" then
    write(dependencies, "No physical movement: persist status reconciliation and complete archive rotation.")
  else
    write(dependencies, "No physical movement: persist fresh status reconciliation; manual recovery remains required for phase "
      .. snapshot.phase .. ".")
  end
  return preview
end

local function runResume(context, dependencies)
  local snapshot, previewStatus, assessment = preflightExisting(context, dependencies)
  if not snapshot then return nil, previewStatus end
  local compatible, compatibilityReason = validateNavigationMission(snapshot)
  if not compatible then return nil, compatibilityReason end
  printMission(dependencies, snapshot, {source = JOURNAL_PATH})
  write(dependencies, "Resume action: " .. assessment.action)
  local preview, previewReason = previewResume(snapshot, dependencies)
  if not preview then return nil, previewReason end
  if not confirmation(dependencies, "RESUME") then
    write(dependencies, "Confirmation cancelled; mission state was not changed.")
    return true
  end
  local confirmedStatus, statusReason = statusResponse(context)
  if not confirmedStatus then return nil, statusReason end
  if not sameStartingStatus(previewStatus, confirmedStatus) then
    return nil, "robot status changed after resume preview; no recovery or continuation was performed"
  end

  if snapshot.pending then
    local confirmed = context.navState.assessStatus(snapshot, confirmedStatus)
    if not confirmed.ok or confirmed.action ~= "retry_identical" then
      return nil, confirmed.reason or "post-confirmation retry status is inconsistent"
    end
    local result, retryReason = executeRetry(
      context, snapshot, confirmedStatus, dependencies)
    if not result then return nil, retryReason end
  else
    local confirmed = context.navState.assessStatus(snapshot, confirmedStatus)
    if not confirmed.ok or confirmed.action ~= "continue" then
      return nil, confirmed.reason or "post-confirmation resume status is inconsistent"
    end
    local reconciled, reconcileReason = context.navState.recordReconciliation(
      context.store, snapshot, confirmedStatus)
    if not reconciled then return nil, reconcileReason end
  end

  if snapshot.phase == "outbound" then
    return continueOutbound(context, snapshot, dependencies, preview.outbound_plan)
  elseif snapshot.phase == "at_destination" then
    write(dependencies, "Mission is already at destination; use return.")
    return true
  elseif snapshot.phase == "returning" then
    return completeReturn(context, snapshot, dependencies)
  elseif snapshot.phase == "home_pending_reconcile" then
    local fresh, freshReason = statusResponse(context)
    if not fresh then return nil, freshReason end
    local reconciled, reconcileReason = context.navState.recordReconciliation(
      context.store, snapshot, fresh)
    if not reconciled then return nil, reconcileReason end
    return finalizeHome(context, snapshot, dependencies)
  elseif snapshot.phase == "home_pose_reached" then
    return finalizeHome(context, snapshot, dependencies)
  elseif snapshot.phase == "terminal" then
    local archive, archiveReason = context.store.archive(snapshot)
    if not archive then return nil, archiveReason end
    write(dependencies, "Archived terminal mission: " .. archive)
    return true
  end
  return nil, "mission phase requires manual recovery: " .. snapshot.phase
end

local function runLive(parsed, context, dependencies)
  if parsed.command == "status" then return runStatus(context, dependencies) end
  local ok, reason, requestedCode
  if parsed.command == "go" then ok, reason, requestedCode = runGo(context, parsed, dependencies)
  elseif parsed.command == "return" then ok, reason = runReturn(context, dependencies)
  else ok, reason = runResume(context, dependencies) end
  if not ok then writeError(dependencies, tostring(reason)); return requestedCode or 1 end
  return 0
end

function cli.main(arguments, dependencies)
  dependencies = dependencies or {}
  local parsed, parseReason = cli.parse(arguments)
  if not parsed then writeError(dependencies, parseReason); usage(dependencies); return 2 end
  if parsed.command == "plan" then return runPlan(parsed, dependencies) end
  local context, contextReason = openContext(dependencies, "ocianav:" .. parsed.command)
  if not context then writeError(dependencies, tostring(contextReason)); return 1 end
  local values = table.pack(xpcall(function()
    return runLive(parsed, context, dependencies)
  end, debug.traceback))
  local closeOk, closeReason = pcall(context.close)
  if not values[1] then
    writeError(dependencies, tostring(values[2]))
    return 1
  end
  if not closeOk then
    writeError(dependencies, "controller cleanup failed: " .. tostring(closeReason))
    return 1
  end
  return values[2]
end

if select("#", ...) == 1 and (...) == "__test_module__" then return cli end
os.exit(cli.main({...}))
