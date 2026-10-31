local protocol = require("ocia.protocol")
local pose = require("ocia.pose")
local state = require("ocia.state")

local executor = {}
executor.__index = executor

local function merge(target, source)
  for key, value in pairs(source or {}) do target[key] = value end
  return target
end

local function result(outcome, code, message, payload)
  payload = payload or {}
  payload.code = code
  payload.message = message
  return {outcome = outcome, payload = payload}
end

function executor.new(options)
  assert(type(options) == "table", "executor options are required")
  assert(options.store, "executor store is required")
  assert(type(options.perform) == "function", "perform callback is required")

  local self = setmetatable({
    store = options.store,
    perform = options.perform,
    status_provider = options.status_provider or function() return {} end,
    recent_limit = options.recent_limit or 32,
    compact_records = options.compact_records or 128,
    compact_bytes = options.compact_bytes or 65536
  }, executor)

  self.snapshot, self.load_metadata = self.store.load()
  if self.snapshot.in_flight then
    if self.snapshot.in_flight.phase == "prepared"
        and self.snapshot.journal.health == "healthy" then
      local item = self.snapshot.in_flight
      local payload = protocol.encodeFields({
        code = "interrupted_before_execution",
        message = "request was prepared but physical execution had not begun",
        physical_outcome = "not_started"
      })
      local appended, reason = self.store.append(self.snapshot, {
        kind = "completed", sequence = item.sequence,
        request_id = item.request_id, outcome = "failed", payload = payload,
        pose_trusted = self.snapshot.pose.trusted,
        pose_x = self.snapshot.pose.x, pose_y = self.snapshot.pose.y,
        pose_z = self.snapshot.pose.z, pose_heading = self.snapshot.pose.heading,
        pose_reason = self.snapshot.pose.reason or ""
      })
      if appended then
        self.boot_classification = "not_started"
      else
        self.snapshot.mode = "recovery_required"
        self.snapshot.pose = pose.unknown(self.snapshot.pose,
          "prepared-request recovery could not be persisted")
        self.snapshot.last_error = tostring(reason)
        self.boot_error = tostring(reason)
      end
    else
      self.snapshot.mode = "recovery_required"
      self.snapshot.pose = pose.unknown(self.snapshot.pose,
        "interrupted physical operation")
      self.snapshot.last_error = "physical operation outcome is ambiguous after restart"
      self.boot_classification = "ambiguous"
    end
  elseif self.snapshot.journal.health ~= "healthy" then
    self.boot_classification = self.snapshot.journal.health
  end
  return self
end

function executor:statusPayload()
  local payload = pose.toFields(self.snapshot.pose)
  payload.mode = self.snapshot.mode
  payload.last_error = self.snapshot.last_error or ""
  payload.epoch = self.snapshot.epoch or ""
  payload.high_water = self.snapshot.high_water
  payload.retained_results = #self.snapshot.recent
  payload.journal_health = self.snapshot.journal.health
  payload.journal_generation = self.snapshot.journal.generation
  payload.journal_records = self.snapshot.journal.records
  payload.journal_bytes = self.snapshot.journal.bytes
  payload.last_persist_ms = self.snapshot.journal.last_persist_ms
  if self.snapshot.in_flight then
    payload.in_flight_request = self.snapshot.in_flight.request_id
    payload.in_flight_operation = self.snapshot.in_flight.operation
    payload.in_flight_phase = self.snapshot.in_flight.phase
  end
  local latest = self.snapshot.recent[#self.snapshot.recent]
  if latest then
    payload.last_request = latest.request_id
    payload.last_operation = latest.operation
    payload.last_outcome = latest.outcome
  end
  local ok, extra = pcall(self.status_provider)
  if ok and type(extra) == "table" then merge(payload, extra)
  elseif not ok then payload.status_error = tostring(extra) end
  return payload
end

function executor:lock(reason, detail)
  self.snapshot.mode = "recovery_required"
  self.snapshot.pose = pose.unknown(self.snapshot.pose, reason)
  self.snapshot.last_error = tostring(detail or reason)
  self.snapshot.journal.health = self.store.health or self.snapshot.journal.health
end

function executor:completedReply(entry)
  local payload, reason = protocol.decodeFields(entry.payload_raw)
  if not payload then
    self:lock("cached result is invalid", reason)
    return result("recovery_required", "invalid_cached_result", tostring(reason),
      self:statusPayload())
  end
  payload.duplicate = "true"
  return {outcome = entry.outcome, payload = payload}
end

function executor:inFlightReply(request, identity)
  local item = self.snapshot.in_flight
  if not item or item.sequence ~= identity.sequence then return nil end
  if item.request_id ~= request.request_id or item.fingerprint ~= request.fingerprint then
    return result("rejected", "request_id_conflict",
      "in-flight sequence was already used with different request contents")
  end

  local payload = self:statusPayload()
  if item.phase == "executing" then
    payload.physical_outcome = "unknown"
    return result("recovery_required", "physical_outcome_unknown",
      "matching request may have executed; reconcile physical state before recovery",
      payload)
  end

  payload.physical_outcome = "not_started"
  return result("recovery_required", "prepared_resolution_unpersisted",
    "request did not begin physical execution, but its resolution is not durably authoritative",
    payload)
end

function executor:handle(request)
  if request.operation == "status" then
    return result("succeeded", "status", "fresh status returned", self:statusPayload())
  end

  local identity, identityReason = protocol.parsePhysicalRequestId(request.request_id)
  if not identity then return result("rejected", "invalid_request_id", identityReason) end
  if self.snapshot.epoch == "" then
    return result("recovery_required", "commissioning_required",
      "establish the charging origin before autonomous movement", self:statusPayload())
  end
  if identity.epoch ~= self.snapshot.epoch then
    return result("rejected", "stale_epoch",
      "request belongs to a retired execution epoch", self:statusPayload())
  end

  local inFlight = self:inFlightReply(request, identity)
  if inFlight then return inFlight end

  if identity.sequence <= self.snapshot.high_water then
    local cached = state.findRecent(self.snapshot, identity.sequence)
    if cached then
      if cached.request_id ~= request.request_id or cached.fingerprint ~= request.fingerprint then
        return result("rejected", "request_id_conflict",
          "sequence was already used with different request contents")
      end
      return self:completedReply(cached)
    end
    return result("rejected", "retired_request",
      "request sequence is completed but its full result has been retired",
      self:statusPayload())
  end
  if identity.sequence ~= self.snapshot.high_water + 1 then
    return result("rejected", "sequence_gap",
      "physical requests must be contiguous", self:statusPayload())
  end
  if self.snapshot.journal.health ~= "healthy" then
    return result("recovery_required", "journal_untrusted",
      "physical execution is disabled because the journal is not authoritative",
      self:statusPayload())
  end
  if self.snapshot.mode ~= "ready" or not self.snapshot.pose.trusted then
    return result("recovery_required", "robot_not_ready",
      "physical execution is disabled until pose recovery", self:statusPayload())
  end

  local appended, appendReason = self.store.append(self.snapshot, {
    kind = "prepared", epoch = identity.epoch, sequence = identity.sequence,
    request_id = request.request_id, fingerprint = request.fingerprint,
    deployment_id = request.deployment_id, operation = request.operation
  })
  if not appended then
    self:lock("prepared intent could not be persisted", appendReason)
    return result("rejected", "persistence_failed_before_execution",
      tostring(appendReason), self:statusPayload())
  end

  appended, appendReason = self.store.append(self.snapshot, {
    kind = "executing", sequence = identity.sequence,
    request_id = request.request_id
  })
  if not appended then
    self:lock("execution marker could not be persisted", appendReason)
    return result("rejected", "persistence_failed_before_execution",
      tostring(appendReason), self:statusPayload())
  end

  local callOk, operationOk, detail, operationFields = pcall(
    self.perform, request.operation, request.arguments)
  if not callOk then
    self:lock("operation raised an exception", operationOk)
    return result("recovery_required", "operation_exception",
      tostring(operationOk), self:statusPayload())
  end

  local resultingPose = pose.copy(self.snapshot.pose)
  local outcome, code, message
  if operationOk then
    local nextPose, poseReason = pose.apply(self.snapshot.pose, request.operation)
    if not nextPose then
      self:lock("pose transition failed", poseReason)
      return result("recovery_required", "pose_transition_failed",
        tostring(poseReason), self:statusPayload())
    end
    resultingPose = nextPose
    outcome, code, message = "succeeded", "operation_succeeded", tostring(detail or "OK")
  else
    outcome, code, message = "failed", "operation_failed", tostring(detail or "blocked")
  end

  local payload = pose.toFields(resultingPose)
  payload.mode = "ready"
  payload.code = code
  payload.message = message
  if type(operationFields) == "table" then merge(payload, operationFields) end
  local statusOk, extra = pcall(self.status_provider)
  if statusOk and type(extra) == "table" then merge(payload, extra) end
  local payloadRaw, encodeReason = protocol.encodeFields(payload)
  if not payloadRaw then
    self:lock("operation result could not be encoded", encodeReason)
    return result("recovery_required", "result_encoding_failed",
      tostring(encodeReason), self:statusPayload())
  end

  appended, appendReason = self.store.append(self.snapshot, {
    kind = "completed", sequence = identity.sequence,
    request_id = request.request_id, outcome = outcome, payload = payloadRaw,
    pose_trusted = resultingPose.trusted,
    pose_x = resultingPose.x, pose_y = resultingPose.y, pose_z = resultingPose.z,
    pose_heading = resultingPose.heading, pose_reason = resultingPose.reason or ""
  })
  if not appended then
    self:lock("operation completion could not be persisted", appendReason)
    return result("recovery_required", "completion_persistence_failed",
      tostring(appendReason), self:statusPayload())
  end

  if self.snapshot.journal.records >= self.compact_records
      or self.snapshot.journal.bytes >= self.compact_bytes then
    local compacted, compactReason = self.store.compact(self.snapshot)
    if not compacted then
      self:lock("journal compaction was interrupted", compactReason)
      return result("recovery_required", "compaction_failed",
        tostring(compactReason), self:statusPayload())
    end
  end
  return {outcome = outcome, payload = payload}
end

function executor:beginManualRecovery()
  if self.snapshot.journal.health == "healthy" then
    local appended, reason = self.store.append(self.snapshot, {kind = "manual"})
    if not appended then
      self:lock("manual recovery marker could not be persisted", reason)
      return nil, reason
    end
  else
    self.snapshot.mode = "recovery_required"
    self.snapshot.pose = pose.unknown(self.snapshot.pose, "legacy manual movement")
  end
  return true
end

return executor
