local nav = require("ocia.nav")
local pose = require("ocia.pose")
local protocol = require("ocia.protocol")

local state = {
  FORMAT = 1,
  DEFAULT_ACTION_LIMIT = 160,
  MAX_ACTION_LIMIT = 160,
  MAX_RECORDS = 1024
}

local phases = {
  outbound = true,
  at_destination = true,
  returning = true,
  home_pending_reconcile = true,
  home_pose_reached = true,
  recovery_required = true,
  terminal = true
}

local terminalOutcomes = {
  navigation_complete = true,
  aborted = true,
  recovery_required = true
}

local MAX_SAFE_INTEGER = 9007199254740991

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
    and math.abs(value) <= MAX_SAFE_INTEGER
end

local function boolean(value)
  if value == true or value == "true" then return true end
  if value == false or value == "false" then return false end
  return nil
end

local function number(fields, key, minimum)
  local value = tonumber(fields[key])
  if not value or value ~= math.floor(value) or (minimum and value < minimum) then
    return nil, "invalid numeric field " .. key
  end
  return value
end

local function samePose(left, right)
  return pose.equal(left, right) and left.trusted and right.trusted
end

local function homePose()
  return pose.new(0, 0, 0, "north")
end

local function poseFields(prefix, value, fields)
  fields[prefix .. "_trusted"] = value.trusted
  fields[prefix .. "_x"] = value.x
  fields[prefix .. "_y"] = value.y
  fields[prefix .. "_z"] = value.z
  fields[prefix .. "_heading"] = value.heading
  fields[prefix .. "_reason"] = value.reason or ""
end

local function readPose(fields, prefix)
  local trusted = boolean(fields[prefix .. "_trusted"])
  if trusted == nil then return nil, "invalid pose trust " .. prefix end
  local x, reason = number(fields, prefix .. "_x")
  if not x then return nil, reason end
  local y; y, reason = number(fields, prefix .. "_y")
  if not y then return nil, reason end
  local z; z, reason = number(fields, prefix .. "_z")
  if not z then return nil, reason end
  local result = {
    trusted = trusted,
    x = x,
    y = y,
    z = z,
    heading = fields[prefix .. "_heading"],
    reason = fields[prefix .. "_reason"] or ""
  }
  local ok, poseReason = pose.validate(result)
  if not ok then return nil, poseReason end
  return result
end

local function encodeMap(value, label)
  if value == nil then return "" end
  if type(value) ~= "table" then return nil, label .. " must be a table" end
  return protocol.encodeFields(value)
end

local function decodeMap(value, label)
  local decoded, reason = protocol.decodeFields(value or "")
  if not decoded then return nil, label .. ": " .. tostring(reason) end
  return decoded
end

local function checksum(text)
  local hash = 2166136261
  for index = 1, #text do
    hash = ((hash ~ text:byte(index)) * 16777619) & 0xffffffff
  end
  return string.format("%08x", hash)
end

function state.encodeRecord(fields)
  local raw, reason = protocol.encodeFields(fields)
  if not raw then return nil, reason end
  return raw .. "#" .. checksum(raw) .. "\n"
end

function state.decodeRecord(line)
  if type(line) ~= "string" then return nil, "record must be text" end
  local raw, expected = line:match("^(.*)#(%x%x%x%x%x%x%x%x)$")
  if not raw then return nil, "record checksum is missing" end
  if checksum(raw) ~= expected:lower() then return nil, "record checksum mismatch" end
  return protocol.decodeFields(raw)
end

local function validMissionId(value)
  return type(value) == "string" and #value >= 8 and #value <= 64
    and value:match("^[%w%._:%-]+$") ~= nil
end

local function validEpoch(value)
  return type(value) == "string" and #value >= 8 and #value <= 48
    and value:match("^[%x%-]+$") ~= nil
end

local function statusPose(status)
  if type(status) ~= "table" then return nil, "robot status must be a table" end
  if type(status.pose) == "table" then
    local result = copy(status.pose)
    local ok, reason = pose.validate(result)
    if not ok then return nil, reason end
    return result
  end
  local trusted = boolean(status.pose_trusted)
  local result = {
    trusted = trusted,
    x = tonumber(status.x), y = tonumber(status.y), z = tonumber(status.z),
    heading = status.heading,
    reason = status.pose_reason or ""
  }
  local ok, reason = pose.validate(result)
  if not ok then return nil, reason end
  return result
end

local function validateRobotStatus(status)
  if type(status) ~= "table" then return nil, "robot status must be a table" end
  if status.mode ~= "ready" then return nil, "robot is not ready" end
  if status.journal_health ~= "healthy" then return nil, "robot journal is not healthy" end
  if not validEpoch(status.epoch) then return nil, "robot execution epoch is invalid" end
  local highWater = tonumber(status.high_water)
  if not integer(highWater) or highWater < 0 then return nil, "robot high water is invalid" end
  local robotPose, reason = statusPose(status)
  if not robotPose then return nil, reason end
  if not robotPose.trusted then return nil, "robot pose is untrusted" end
  return {epoch = status.epoch, high_water = highWater, pose = robotPose}
end

local function defaultSnapshot()
  return {
    format = state.FORMAT,
    mission_id = "",
    robot_epoch = "",
    home = homePose(),
    destination = nil,
    limits = {},
    owner = "",
    phase = "recovery_required",
    pose = pose.unknown(homePose(), "no mission loaded"),
    high_water = 0,
    reconciliation_required = false,
    physical_actions = 0,
    breadcrumbs = {},
    return_state = {frozen = false, cursor = 0, steps = {}},
    pending = nil,
    failures = {},
    terminal = nil,
    home_pose_reached = false,
    charging_verified = false,
    last_reconciliation = nil,
    journal = {health = "uninitialized", records = 0, bytes = 0,
      last_persist_ms = 0}
  }
end

function state.validate(snapshot)
  if type(snapshot) ~= "table" then return nil, "mission state must be a table" end
  if snapshot.format ~= state.FORMAT then return nil, "unsupported mission state format" end
  if not validMissionId(snapshot.mission_id) then return nil, "invalid mission identity" end
  if not validEpoch(snapshot.robot_epoch) then return nil, "invalid robot epoch" end
  if not phases[snapshot.phase] then return nil, "invalid mission phase" end
  local poseOk, poseReason = pose.validate(snapshot.pose)
  if not poseOk then return nil, poseReason end
  if not samePose(snapshot.home, homePose()) then return nil, "commissioned home pose is invalid" end
  if type(snapshot.destination) ~= "table" or not integer(snapshot.destination.x)
      or not integer(snapshot.destination.y) or not integer(snapshot.destination.z)
      or (snapshot.destination.heading ~= nil
        and not pose.headings[snapshot.destination.heading]) then
    return nil, "invalid mission destination"
  end
  if type(snapshot.limits) ~= "table" then return nil, "mission limits are invalid" end
  local actionLimit = tonumber(snapshot.limits.action_limit)
  if not integer(actionLimit) or actionLimit < 1 or actionLimit > state.MAX_ACTION_LIMIT then
    return nil, "action limit is invalid"
  end
  if not integer(snapshot.high_water) or snapshot.high_water < 0 then
    return nil, "mission high water is invalid"
  end
  if type(snapshot.reconciliation_required) ~= "boolean" then
    return nil, "reconciliation requirement is invalid"
  end
  if not integer(snapshot.physical_actions) or snapshot.physical_actions < 0
      or snapshot.physical_actions > actionLimit then
    return nil, "physical action count is invalid"
  end
  if type(snapshot.breadcrumbs) ~= "table" or #snapshot.breadcrumbs > actionLimit then
    return nil, "outbound breadcrumbs are invalid"
  end
  if type(snapshot.return_state) ~= "table" or type(snapshot.return_state.steps) ~= "table"
      or not integer(snapshot.return_state.cursor) or snapshot.return_state.cursor < 0
      or snapshot.return_state.cursor > #snapshot.breadcrumbs then
    return nil, "return state is invalid"
  end
  if snapshot.pending then
    local item = snapshot.pending
    local identity = protocol.parsePhysicalRequestId(item.request_id)
    if not identity or identity.epoch ~= snapshot.robot_epoch
        or identity.sequence ~= item.sequence or not protocol.isPhysical(item.operation)
        or type(item.arguments_raw) ~= "string" or type(item.fingerprint) ~= "string" then
      return nil, "pending physical intent is invalid"
    end
  end
  if snapshot.phase == "terminal" and not snapshot.terminal then
    return nil, "terminal phase requires a terminal outcome"
  end
  return true
end

local function missionFields(snapshot)
  local limitsRaw = assert(encodeMap(snapshot.limits, "limits"))
  local fields = {
    kind = "mission", format = state.FORMAT,
    mission_id = snapshot.mission_id, robot_epoch = snapshot.robot_epoch,
    owner = snapshot.owner, phase = snapshot.phase,
    high_water = snapshot.high_water,
    destination_x = snapshot.destination.x,
    destination_y = snapshot.destination.y,
    destination_z = snapshot.destination.z,
    destination_heading = snapshot.destination.heading or "",
    limits = limitsRaw
  }
  poseFields("home", snapshot.home, fields)
  poseFields("pose", snapshot.pose, fields)
  return fields
end

function state.createMission(robotStatus, specification)
  specification = specification or {}
  local normalized, statusReason = validateRobotStatus(robotStatus)
  if not normalized then return nil, statusReason end
  if not samePose(normalized.pose, homePose()) then
    return nil, "new navigation mission must start at commissioned home"
  end
  if not validMissionId(specification.mission_id) then return nil, "invalid mission identity" end
  local destination = specification.destination
  if type(destination) ~= "table" then return nil, "destination is required" end
  local plan, planReason = nav.plan(homePose(), destination,
    {max_distance = specification.max_distance or nav.DEFAULT_MAX_DISTANCE})
  if not plan then return nil, planReason end
  local actionLimit = specification.action_limit or state.DEFAULT_ACTION_LIMIT
  if not integer(actionLimit) or actionLimit < 1 or actionLimit > state.MAX_ACTION_LIMIT then
    return nil, "action_limit must be between 1 and " .. state.MAX_ACTION_LIMIT
  end
  local limits = copy(specification.limits or {})
  limits.action_limit = actionLimit
  limits.max_distance = specification.max_distance or nav.DEFAULT_MAX_DISTANCE
  local limitsRaw, limitsReason = encodeMap(limits, "limits")
  if not limitsRaw then return nil, limitsReason end
  local snapshot = defaultSnapshot()
  snapshot.mission_id = specification.mission_id
  snapshot.robot_epoch = normalized.epoch
  snapshot.destination = copy(plan.destination)
  snapshot.limits = limits
  snapshot.owner = specification.owner or ""
  snapshot.phase = "outbound"
  snapshot.pose = pose.copy(normalized.pose)
  snapshot.high_water = normalized.high_water
  snapshot.journal.health = "healthy"
  local ok, reason = state.validate(snapshot)
  if not ok then return nil, reason end
  return snapshot
end

local function breadcrumbFrom(fields)
  local before, reason = readPose(fields, "before")
  if not before then return nil, reason end
  local after; after, reason = readPose(fields, "after")
  if not after then return nil, reason end
  return {
    operation = fields.operation,
    request_id = fields.request_id,
    before = before,
    after = after,
    phase = fields.intent_phase,
    evidence = {code = fields.code or "", message = fields.message or "",
      energy = fields.energy or ""}
  }
end

function state.applyRecord(snapshot, fields)
  if type(fields) ~= "table" then return nil, "record fields must be a table" end
  local kind = fields.kind
  if kind == "mission" then
    if snapshot.mission_id ~= "" then return nil, "duplicate mission record" end
    local format, reason = number(fields, "format", 1)
    if not format then return nil, reason end
    if format ~= state.FORMAT then return nil, "unsupported mission record format" end
    local home; home, reason = readPose(fields, "home")
    if not home then return nil, reason end
    local current; current, reason = readPose(fields, "pose")
    if not current then return nil, reason end
    local highWater; highWater, reason = number(fields, "high_water", 0)
    if not highWater then return nil, reason end
    local limits; limits, reason = decodeMap(fields.limits, "limits")
    if not limits then return nil, reason end
    limits.action_limit = tonumber(limits.action_limit)
    limits.max_distance = tonumber(limits.max_distance)
    snapshot.format = format
    snapshot.mission_id = fields.mission_id
    snapshot.robot_epoch = fields.robot_epoch
    snapshot.home = home
    snapshot.destination = {
      x = tonumber(fields.destination_x), y = tonumber(fields.destination_y),
      z = tonumber(fields.destination_z)
    }
    if fields.destination_heading and fields.destination_heading ~= "" then
      snapshot.destination.heading = fields.destination_heading
    end
    snapshot.limits = limits
    snapshot.owner = fields.owner or ""
    snapshot.phase = fields.phase
    snapshot.pose = current
    snapshot.high_water = highWater
    snapshot.journal.health = "healthy"
  elseif kind == "intent" then
    if snapshot.pending then return nil, "only one physical intent may be pending" end
    if snapshot.phase == "terminal" or snapshot.phase == "recovery_required" then
      return nil, "mission phase cannot allocate a physical intent"
    end
    local sequence, reason = number(fields, "sequence", 1)
    if not sequence then return nil, reason end
    if sequence ~= snapshot.high_water + 1 then return nil, "intent sequence is not contiguous" end
    local before; before, reason = readPose(fields, "before")
    if not before then return nil, reason end
    local expected; expected, reason = readPose(fields, "expected")
    if not expected then return nil, reason end
    if not samePose(before, snapshot.pose) then return nil, "intent starting pose disagrees with mission" end
    snapshot.pending = {
      request_id = fields.request_id, sequence = sequence,
      epoch = fields.epoch, deployment_id = fields.deployment_id,
      recipient = fields.recipient, version = tonumber(fields.version),
      operation = fields.operation, arguments_raw = fields.arguments or "",
      fingerprint = fields.fingerprint, before = before, expected = expected,
      phase = fields.intent_phase, effect = fields.effect,
      observation = nil
    }
  elseif kind == "result" then
    if not snapshot.pending or snapshot.pending.request_id ~= fields.request_id then
      return nil, "result has no matching pending intent"
    end
    local classification = fields.classification
    snapshot.pending.observation = {
      classification = classification, code = fields.code or "",
      message = fields.message or ""
    }
    if classification == "success" or classification == "completed_failure"
        or classification == "definite_nonexecution" then
      local sequence, reason = number(fields, "sequence", 1)
      if not sequence then return nil, reason end
      if sequence ~= snapshot.pending.sequence then return nil, "result sequence mismatch" end
      snapshot.high_water = sequence
      snapshot.physical_actions = snapshot.physical_actions + 1
      if classification == "success" then
        local resulting; resulting, reason = readPose(fields, "after")
        if not resulting then return nil, reason end
        if not samePose(resulting, snapshot.pending.expected) then
          return nil, "successful result pose contradicts intent"
        end
        snapshot.pose = resulting
        if snapshot.pending.effect == "breadcrumb" then
          local entry; entry, reason = breadcrumbFrom(fields)
          if not entry then return nil, reason end
          snapshot.breadcrumbs[#snapshot.breadcrumbs + 1] = entry
        elseif snapshot.pending.effect == "return_step" then
          if not snapshot.return_state.frozen or snapshot.return_state.cursor < 1 then
            return nil, "return result has no frozen breadcrumb"
          end
          snapshot.return_state.steps[#snapshot.return_state.steps + 1] = {
            operation = snapshot.pending.operation,
            request_id = snapshot.pending.request_id,
            before = pose.copy(snapshot.pending.before), after = pose.copy(resulting),
            evidence = {code = fields.code or "", message = fields.message or ""}
          }
          snapshot.return_state.cursor = snapshot.return_state.cursor - 1
          if snapshot.return_state.cursor == 0 then
            snapshot.phase = "home_pending_reconcile"
          end
        end
        snapshot.reconciliation_required = false
      else
        snapshot.reconciliation_required = true
        snapshot.failures[#snapshot.failures + 1] = {
          request_id = fields.request_id, sequence = sequence,
          classification = classification, code = fields.code or "",
          message = fields.message or ""
        }
      end
      snapshot.pending = nil
    else
      snapshot.phase = "recovery_required"
      snapshot.failures[#snapshot.failures + 1] = {
        request_id = fields.request_id, sequence = snapshot.pending.sequence,
        classification = classification, code = fields.code or "",
        message = fields.message or ""
      }
    end
  elseif kind == "reconcile" then
    local highWater, reason = number(fields, "high_water", 0)
    if not highWater then return nil, reason end
    local current; current, reason = readPose(fields, "pose")
    if not current then return nil, reason end
    if fields.epoch ~= snapshot.robot_epoch or highWater ~= snapshot.high_water
        or not samePose(current, snapshot.pose) then
      return nil, "reconciliation record contradicts mission state"
    end
    snapshot.last_reconciliation = {epoch = fields.epoch, high_water = highWater,
      pose = current}
    snapshot.reconciliation_required = false
    if snapshot.phase == "home_pending_reconcile" then
      if snapshot.return_state.cursor ~= 0 or not samePose(current, snapshot.home) then
        return nil, "home reconciliation requirements are not satisfied"
      end
      snapshot.phase = "home_pose_reached"
      snapshot.home_pose_reached = true
    end
  elseif kind == "destination" then
    if snapshot.pending or snapshot.phase ~= "outbound" then
      return nil, "destination transition is not allowed"
    end
    if snapshot.pose.x ~= snapshot.destination.x or snapshot.pose.y ~= snapshot.destination.y
        or snapshot.pose.z ~= snapshot.destination.z
        or (snapshot.destination.heading
          and snapshot.pose.heading ~= snapshot.destination.heading) then
      return nil, "current pose does not satisfy destination"
    end
    snapshot.phase = "at_destination"
  elseif kind == "return_start" then
    if snapshot.pending or (snapshot.phase ~= "outbound"
        and snapshot.phase ~= "at_destination" and snapshot.phase ~= "recovery_required") then
      return nil, "return cannot start in the current mission state"
    end
    snapshot.return_state.frozen = true
    snapshot.return_state.cursor = #snapshot.breadcrumbs
    snapshot.return_state.steps = {}
    snapshot.phase = snapshot.return_state.cursor == 0
      and "home_pending_reconcile" or "returning"
  elseif kind == "terminal" then
    if snapshot.pending then return nil, "cannot terminate with an unresolved intent" end
    if not terminalOutcomes[fields.outcome] then return nil, "invalid terminal outcome" end
    snapshot.phase = "terminal"
    snapshot.terminal = {outcome = fields.outcome, reason = fields.reason or ""}
  else
    return nil, "unsupported navigation journal record " .. tostring(kind)
  end
  return state.validate(snapshot)
end

local function requestFromIntent(intent)
  return {
    version = intent.version,
    request_id = intent.request_id,
    deployment_id = intent.deployment_id,
    recipient = intent.recipient,
    operation = intent.operation,
    arguments_raw = intent.arguments_raw,
    arguments = assert(protocol.decodeFields(intent.arguments_raw)),
    fingerprint = intent.fingerprint
  }
end

local function intentFields(snapshot, specification)
  if snapshot.pending then return nil, "a physical intent is already unresolved" end
  if snapshot.journal.health ~= "healthy" then return nil, "controller journal is not healthy" end
  if snapshot.reconciliation_required then
    return nil, "fresh robot status reconciliation is required before another intent"
  end
  if snapshot.phase ~= "outbound" and snapshot.phase ~= "returning" then
    return nil, "mission phase cannot prepare a physical intent"
  end
  if snapshot.physical_actions >= tonumber(snapshot.limits.action_limit) then
    return nil, "mission physical-action budget is exhausted"
  end
  specification = specification or {}
  local operation = specification.operation
  if not protocol.isPhysical(operation) then return nil, "intent operation must be physical" end
  local sequence = snapshot.high_water + 1
  local requestId = specification.request_id
    or protocol.makePhysicalRequestId(snapshot.robot_epoch, sequence)
  local identity, identityReason = protocol.parsePhysicalRequestId(requestId)
  if not identity then return nil, identityReason end
  if identity.epoch ~= snapshot.robot_epoch or identity.sequence ~= sequence then
    return nil, "intent request identity is not the next mission sequence"
  end
  local requestInput = {
    version = protocol.VERSION, request_id = requestId,
    deployment_id = specification.deployment_id or snapshot.mission_id,
    recipient = specification.recipient, operation = operation,
    arguments = specification.arguments or {}
  }
  if not protocol.validAddress(requestInput.recipient) then return nil, "intent recipient is invalid" end
  local parts, requestReason = protocol.buildRequest(requestInput)
  if not parts then return nil, requestReason end
  local request, _, parseReason = protocol.parseRequest(parts, requestInput.recipient)
  if not request then return nil, parseReason end
  local expected, poseReason = pose.apply(snapshot.pose, operation)
  if not expected then return nil, poseReason end
  local effect = "breadcrumb"
  if snapshot.phase == "returning" then
    local entry = snapshot.breadcrumbs[snapshot.return_state.cursor]
    if not snapshot.return_state.frozen or not entry then return nil, "return state is not frozen" end
    local expectedInverse = assert(nav.inverse({entry.operation}))[1]
    if operation ~= expectedInverse then return nil, "return intent is not the exact inverse operation" end
    if not samePose(expected, entry.before) then return nil, "return intent does not reach breadcrumb predecessor" end
    effect = "return_step"
  end
  local fields = {
    kind = "intent", request_id = requestId, sequence = sequence,
    epoch = snapshot.robot_epoch, version = protocol.VERSION,
    deployment_id = request.deployment_id, recipient = request.recipient,
    operation = operation, arguments = request.arguments_raw,
    fingerprint = request.fingerprint, intent_phase = snapshot.phase, effect = effect
  }
  poseFields("before", snapshot.pose, fields)
  poseFields("expected", expected, fields)
  return fields
end

function state.prepareIntent(store, snapshot, specification)
  local fields, reason = intentFields(snapshot, specification)
  if not fields then return nil, reason end
  local appended, appendReason = store.append(snapshot, fields)
  if not appended then return nil, appendReason end
  return copy(snapshot.pending)
end

function state.requestForPending(snapshot)
  if not snapshot.pending then return nil, "no physical intent is pending" end
  if snapshot.journal.health ~= "healthy" then return nil, "controller journal is not healthy" end
  return requestFromIntent(snapshot.pending)
end

function state.canTransmit(snapshot)
  return snapshot.journal.health == "healthy" and snapshot.pending ~= nil
    and snapshot.pending.observation == nil
    and snapshot.phase ~= "terminal"
end

local function responseCorrelates(intent, response)
  if type(response) ~= "table" or type(response.request) ~= "table"
      or type(response.reply) ~= "table" then return nil, "missing correlated request/reply" end
  local expected = requestFromIntent(intent)
  if response.request.request_id ~= expected.request_id
      or response.request.version ~= expected.version
      or response.request.deployment_id ~= expected.deployment_id
      or response.request.operation ~= expected.operation
      or response.request.recipient ~= expected.recipient
      or response.request.arguments_raw ~= expected.arguments_raw
      or response.request.fingerprint ~= expected.fingerprint then
    return nil, "response request identity contradicts pending intent"
  end
  local correlated, reason = protocol.correlate(response.reply, expected)
  if not correlated then return nil, reason end
  if response.reply.version ~= protocol.VERSION
      or response.status ~= response.reply.outcome
      or type(response.reply.payload) ~= "table"
      or response.code ~= response.reply.payload.code then
    return nil, "response summary contradicts correlated reply"
  end
  local payloadRaw = protocol.encodeFields(response.payload)
  local replyPayloadRaw = protocol.encodeFields(response.reply.payload)
  if not payloadRaw or not replyPayloadRaw or payloadRaw ~= replyPayloadRaw then
    return nil, "response payload contradicts correlated reply"
  end
  return true
end

local function payloadPose(payload)
  if type(payload) ~= "table" then return nil, "reply payload is missing" end
  return statusPose(payload)
end

function state.classify(snapshot, response)
  if not snapshot.pending then return nil, "no physical intent is pending" end
  local intent = snapshot.pending
  if type(response) ~= "table" then
    return {kind = "malformed_response", consumes_sequence = false,
      ambiguous = true, code = "malformed_response", message = "response is not a table"}
  end
  if response.status == "local_rejection" then
    return {kind = "local_nonsend", consumes_sequence = false, ambiguous = false,
      code = response.code or "invalid_request", message = response.message or "local rejection"}
  end
  if response.status == "send_failed" then
    return {kind = "send_ambiguous", consumes_sequence = false, ambiguous = true,
      code = response.code or "send_failed", message = response.message or "send failed"}
  end
  if response.status == "timeout" then
    return {kind = "timeout", consumes_sequence = false, ambiguous = true,
      code = response.code or "outcome_unknown", message = response.message or "timeout"}
  end
  local correlated, correlationReason = responseCorrelates(intent, response)
  if not correlated then
    return {kind = "contradictory_response", consumes_sequence = false, ambiguous = true,
      code = "correlation_failed", message = correlationReason}
  end
  local outcome, code = response.status, response.code
  if outcome == "succeeded" and code == "operation_succeeded" then
    local resulting, reason = payloadPose(response.payload)
    if not resulting or not samePose(resulting, intent.expected) then
      return {kind = "contradictory_response", consumes_sequence = false,
        ambiguous = true, code = "pose_contradiction", message = reason or "success pose contradicts intent"}
    end
    return {kind = "success", consumes_sequence = true, ambiguous = false,
      code = code, message = response.message or "", after = resulting,
      energy = response.payload.energy}
  end
  if outcome == "failed" and code == "operation_failed" then
    local resulting, reason = payloadPose(response.payload)
    if not resulting or not samePose(resulting, intent.before) then
      return {kind = "contradictory_response", consumes_sequence = false,
        ambiguous = true, code = "pose_contradiction", message = reason or "failure pose changed"}
    end
    return {kind = "completed_failure", consumes_sequence = true, ambiguous = false,
      code = code, message = response.message or "", after = resulting}
  end
  if outcome == "failed" and code == "interrupted_before_execution"
      and response.payload and response.payload.physical_outcome == "not_started" then
    local resulting, reason = payloadPose(response.payload)
    if not resulting or not samePose(resulting, intent.before) then
      return {kind = "contradictory_response", consumes_sequence = false,
        ambiguous = true, code = "pose_contradiction", message = reason or "nonexecution pose changed"}
    end
    return {kind = "definite_nonexecution", consumes_sequence = true, ambiguous = false,
      code = code, message = response.message or "", after = resulting}
  end
  if outcome == "rejected" then
    return {kind = "robot_rejection", consumes_sequence = false, ambiguous = true,
      code = code or "rejected", message = response.message or "robot rejected request"}
  end
  if outcome == "recovery_required" then
    return {kind = "robot_recovery_required", consumes_sequence = false, ambiguous = true,
      code = code or "recovery_required", message = response.message or "robot recovery required"}
  end
  return {kind = "malformed_response", consumes_sequence = false, ambiguous = true,
    code = code or "unexpected_result", message = response.message or "unsupported terminal result"}
end

function state.recordResult(store, snapshot, response)
  local classification, reason = state.classify(snapshot, response)
  if not classification then return nil, reason end
  local fields = {
    kind = "result", request_id = snapshot.pending.request_id,
    sequence = snapshot.pending.sequence, classification = classification.kind,
    operation = snapshot.pending.operation, intent_phase = snapshot.pending.phase,
    code = classification.code or "", message = classification.message or "",
    energy = classification.energy or ""
  }
  poseFields("before", snapshot.pending.before, fields)
  poseFields("after", classification.after or snapshot.pending.before, fields)
  local appended, appendReason = store.append(snapshot, fields)
  if not appended then return nil, appendReason end
  return classification
end

function state.assessStatus(snapshot, robotStatus)
  local normalized, reason = validateRobotStatus(robotStatus)
  if not normalized then return {ok = false, action = "manual_recovery", reason = reason} end
  if normalized.epoch ~= snapshot.robot_epoch then
    return {ok = false, action = "manual_recovery", reason = "robot epoch mismatch"}
  end
  if snapshot.pending then
    if normalized.high_water < snapshot.high_water
        or normalized.high_water > snapshot.pending.sequence then
      return {ok = false, action = "manual_recovery", reason = "robot high water contradicts pending intent"}
    end
    if normalized.high_water == snapshot.high_water
        and not samePose(normalized.pose, snapshot.pending.before) then
      return {ok = false, action = "manual_recovery", reason = "robot pose contradicts unallocated intent"}
    end
    if normalized.high_water == snapshot.pending.sequence
        and not samePose(normalized.pose, snapshot.pending.before)
        and not samePose(normalized.pose, snapshot.pending.expected) then
      return {ok = false, action = "manual_recovery", reason = "robot pose contradicts pending outcomes"}
    end
    return {ok = true, action = "retry_identical", request = requestFromIntent(snapshot.pending),
      reason = "pending outcome requires the identical request; status alone is insufficient"}
  end
  if normalized.high_water ~= snapshot.high_water then
    return {ok = false, action = "manual_recovery", reason = "external physical sequence interference"}
  end
  if not samePose(normalized.pose, snapshot.pose) then
    return {ok = false, action = "manual_recovery", reason = "robot pose disagrees with mission"}
  end
  return {ok = true, action = "continue", normalized = normalized}
end

function state.recordReconciliation(store, snapshot, robotStatus)
  local assessment = state.assessStatus(snapshot, robotStatus)
  if not assessment.ok then return nil, assessment.reason end
  if assessment.action ~= "continue" then return assessment end
  local fields = {kind = "reconcile", epoch = assessment.normalized.epoch,
    high_water = assessment.normalized.high_water}
  poseFields("pose", assessment.normalized.pose, fields)
  local appended, reason = store.append(snapshot, fields)
  if not appended then return nil, reason end
  return assessment
end

function state.markDestination(store, snapshot)
  return store.append(snapshot, {kind = "destination"})
end

function state.beginReturn(store, snapshot)
  return store.append(snapshot, {kind = "return_start"})
end

function state.terminate(store, snapshot, outcome, reason)
  return store.append(snapshot, {kind = "terminal", outcome = outcome,
    reason = reason or ""})
end

function state.journalStore(path, options)
  options = options or {}
  local filesystem = options.filesystem or require("filesystem")
  local open = options.open or io.open
  local timer = options.timer or require("computer").uptime
  local archiveMarker = path .. ".archive.switch"
  local store = {health = "uninitialized", records = 0, bytes = 0,
    last_persist_ms = 0}

  local function close(handle)
    local ok, reason = pcall(function() return handle:close() end)
    if not ok then return nil, tostring(reason) end
    return true
  end

  local function writeLine(file, mode, line)
    local handle, reason = open(file, mode)
    if not handle then return nil, "open failed: " .. tostring(reason) end
    local wrote, writeReason = handle:write(line)
    if not wrote then close(handle); return nil, "write failed: " .. tostring(writeReason) end
    local flushed, flushReason = handle:flush()
    if not flushed then close(handle); return nil, "flush failed: " .. tostring(flushReason) end
    local closed, closeReason = close(handle)
    if not closed then return nil, "close failed: " .. tostring(closeReason) end
    return true
  end

  local function fileSize(file)
    local size = filesystem.size(file)
    return type(size) == "number" and size or 0
  end

  local function ensureDirectory()
    local directory = filesystem.path(path)
    if filesystem.exists(directory) then return true end
    return filesystem.makeDirectory(directory)
  end

  function store.load()
    if filesystem.exists(archiveMarker) then
      store.health = "uncertain_rotation"
      local snapshot = defaultSnapshot()
      snapshot.journal.health = store.health
      return snapshot, {source = "archive_artifact"}
    end
    if not filesystem.exists(path) then
      store.health = "uninitialized"
      return nil, {source = "new"}
    end
    local handle, reason = open(path, "r")
    if not handle then
      store.health = "corrupt"
      return nil, {source = "corrupt", error = "open failed: " .. tostring(reason)}
    end
    local snapshot = defaultSnapshot()
    local expected, consumed = 1, 0
    while true do
      local line = handle:read("*l")
      if line == nil then break end
      consumed = consumed + #line + 1
      local fields, decodeReason = state.decodeRecord(line)
      if not fields then close(handle); store.health = "corrupt";
        return nil, {source = "corrupt", error = decodeReason} end
      local sequence, sequenceReason = number(fields, "journal_sequence", 1)
      if not sequence or sequence ~= expected then close(handle); store.health = "corrupt";
        return nil, {source = "corrupt", error = sequenceReason or "journal sequence is not contiguous"} end
      if expected == 1 and fields.kind ~= "mission" then close(handle); store.health = "corrupt";
        return nil, {source = "corrupt", error = "journal does not begin with mission"} end
      local applied, applyReason = state.applyRecord(snapshot, fields)
      if not applied then close(handle); store.health = "corrupt";
        return nil, {source = "corrupt", error = applyReason} end
      expected = expected + 1
      if expected > state.MAX_RECORDS + 1 then close(handle); store.health = "corrupt";
        return nil, {source = "corrupt", error = "journal exceeds bounded record limit"} end
    end
    local closed, closeReason = close(handle)
    if not closed then store.health = "corrupt";
      return nil, {source = "corrupt", error = "close failed: " .. tostring(closeReason)} end
    if expected == 1 then store.health = "corrupt";
      return nil, {source = "corrupt", error = "journal is empty"} end
    if consumed ~= fileSize(path) then store.health = "corrupt";
      return nil, {source = "corrupt", error = "journal has a partial final record"} end
    store.health, store.records, store.bytes = "healthy", expected - 1, fileSize(path)
    snapshot.journal = {health = "healthy", records = store.records,
      bytes = store.bytes, last_persist_ms = store.last_persist_ms}
    return snapshot, {source = path}
  end

  local function persist(snapshot, fields, mode, alreadyApplied)
    if store.records >= state.MAX_RECORDS then return nil, "journal record limit reached" end
    fields.journal_sequence = mode == "w" and 1 or store.records + 1
    local line, encodeReason = state.encodeRecord(fields)
    if not line then return nil, encodeReason end
    local started = timer()
    local wrote, reason = writeLine(path, mode, line)
    store.last_persist_ms = math.floor((timer() - started) * 1000 + 0.5)
    snapshot.journal.last_persist_ms = store.last_persist_ms
    if not wrote then
      store.health = "uncertain_write"
      snapshot.journal.health = store.health
      snapshot.phase = "recovery_required"
      return nil, reason
    end
    if not alreadyApplied then
      local applied, applyReason = state.applyRecord(snapshot, fields)
      if not applied then
        store.health = "invalid_append"
        snapshot.journal.health = store.health
        snapshot.phase = "recovery_required"
        return nil, applyReason
      end
    end
    store.health = "healthy"
    store.records = fields.journal_sequence
    store.bytes = fileSize(path)
    snapshot.journal = {health = store.health, records = store.records,
      bytes = store.bytes, last_persist_ms = store.last_persist_ms}
    return true
  end

  function store.create(snapshot)
    if filesystem.exists(path) or filesystem.exists(archiveMarker) then
      return nil, "an active or uncertain navigation journal already exists"
    end
    local directoryOk, directoryReason = ensureDirectory()
    if not directoryOk then return nil, "directory creation failed: " .. tostring(directoryReason) end
    store.health, store.records = "healthy", 0
    return persist(snapshot, missionFields(snapshot), "w", true)
  end

  function store.append(snapshot, fields)
    if store.health ~= "healthy" or snapshot.journal.health ~= "healthy" then
      return nil, "controller journal is not healthy"
    end
    return persist(snapshot, fields, "a")
  end

  function store.archive(snapshot)
    if store.health ~= "healthy" or snapshot.phase ~= "terminal" or snapshot.pending then
      return nil, "only a healthy terminal mission may be archived"
    end
    local archive = path .. ".archive." .. snapshot.mission_id
    if filesystem.exists(archive) or filesystem.exists(archiveMarker) then
      return nil, "archive destination or marker already exists"
    end
    local markerOk, markerReason = writeLine(archiveMarker, "w", snapshot.mission_id .. "\n")
    if not markerOk then
      store.health = "uncertain_rotation"
      snapshot.journal.health = store.health
      return nil, "archive marker failed: " .. tostring(markerReason)
    end
    local moved, moveReason = filesystem.rename(path, archive)
    if not moved then store.health = "uncertain_rotation"; snapshot.journal.health = store.health;
      return nil, "archive rename failed: " .. tostring(moveReason) end
    local removed, removeReason = filesystem.remove(archiveMarker)
    if not removed then store.health = "uncertain_rotation"; snapshot.journal.health = store.health;
      return nil, "archive marker cleanup failed: " .. tostring(removeReason) end
    store.health, store.records, store.bytes = "uninitialized", 0, 0
    snapshot.journal.health = "archived"
    return archive
  end

  return store
end

function state.memoryStore()
  local stored, records = nil, {}
  local store = {health = "uninitialized", fail_at = nil, append_count = 0}
  function store.create(snapshot)
    if stored then return nil, "an active navigation journal already exists" end
    local fields = missionFields(snapshot)
    fields.journal_sequence = 1
    records = {copy(fields)}
    stored = copy(snapshot)
    stored.journal = {health = "healthy", records = 1,
      bytes = #(assert(state.encodeRecord(fields))), last_persist_ms = 0}
    snapshot.journal = copy(stored.journal)
    store.health = "healthy"
    return true
  end
  function store.append(snapshot, fields)
    store.append_count = store.append_count + 1
    if store.fail_at == store.append_count then
      store.health = "uncertain_write"
      snapshot.journal.health = store.health
      snapshot.phase = "recovery_required"
      return nil, "injected persistence failure"
    end
    fields.journal_sequence = #records + 1
    local applied, reason = state.applyRecord(snapshot, fields)
    if not applied then return nil, reason end
    records[#records + 1] = copy(fields)
    local bytes = 0
    for _, record in ipairs(records) do bytes = bytes + #(assert(state.encodeRecord(record))) end
    snapshot.journal = {health = "healthy", records = #records, bytes = bytes,
      last_persist_ms = 0}
    stored = copy(snapshot)
    store.health = "healthy"
    return true
  end
  function store.load() return stored and copy(stored) or nil, {source = "memory"} end
  function store.records() return copy(records) end
  return store
end

function state.homePose() return homePose() end
function state.copy(snapshot) return copy(snapshot) end

return state
