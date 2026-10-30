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
    cache_size = options.cache_size or 64,
    persistence_available = true
  }, executor)

  local snapshot, metadata = self.store.load()
  if not snapshot then
    self.snapshot = state.default()
    self.snapshot.mode = "recovery_required"
    self.snapshot.pose = pose.unknown(self.snapshot.pose, "persisted state could not be loaded")
    self.snapshot.last_error = tostring(metadata)
    self.persistence_available = false
    self.boot_error = tostring(metadata)
    return self
  end

  self.snapshot = snapshot
  local changed, classification = state.reconcileAfterLoad(self.snapshot, self.cache_size)
  if changed then
    local saved, reason = self.store.save(self.snapshot)
    if not saved then
      self.snapshot.mode = "recovery_required"
      self.snapshot.pose = pose.unknown(self.snapshot.pose, "startup reconciliation could not be persisted")
      self.snapshot.last_error = tostring(reason)
      self.persistence_available = false
      self.boot_error = tostring(reason)
    else
      self.boot_classification = classification
    end
  end

  return self
end

function executor:statusPayload()
  local payload = pose.toFields(self.snapshot.pose)
  payload.mode = self.snapshot.mode
  payload.last_error = self.snapshot.last_error or ""
  if self.snapshot.in_flight then
    payload.in_flight_request = self.snapshot.in_flight.request_id
    payload.in_flight_operation = self.snapshot.in_flight.operation
    payload.in_flight_phase = self.snapshot.in_flight.phase
  end
  local latest = self.snapshot.completed[#self.snapshot.completed]
  if latest then
    payload.last_request = latest.request_id
    payload.last_operation = latest.operation
    payload.last_outcome = latest.outcome
  end

  local ok, extra = pcall(self.status_provider)
  if ok and type(extra) == "table" then
    merge(payload, extra)
  elseif not ok then
    payload.status_error = tostring(extra)
  end
  return payload
end

function executor:saveOrLock(reason)
  local saved, saveReason = self.store.save(self.snapshot)
  if saved then return true end
  self.persistence_available = false
  self.snapshot.mode = "recovery_required"
  self.snapshot.pose = pose.unknown(self.snapshot.pose, reason)
  self.snapshot.last_error = tostring(saveReason)
  return nil, saveReason
end

function executor:completedReply(entry)
  local payload, reason = protocol.decodeFields(entry.payload_raw)
  if not payload then
    self.snapshot.mode = "recovery_required"
    self.snapshot.pose = pose.unknown(self.snapshot.pose, "cached result is invalid")
    self.snapshot.last_error = tostring(reason)
    return result("recovery_required", "invalid_cached_result", tostring(reason), self:statusPayload())
  end
  payload.duplicate = "true"
  return {outcome = entry.outcome, payload = payload}
end

function executor:recordCompletion(request, outcome, payload)
  local payloadRaw, encodeReason = protocol.encodeFields(payload)
  if not payloadRaw then return nil, encodeReason end
  local added, addReason = state.addCompleted(self.snapshot, {
    request_id = request.request_id,
    fingerprint = request.fingerprint,
    deployment_id = request.deployment_id,
    operation = request.operation,
    outcome = outcome,
    payload_raw = payloadRaw
  }, self.cache_size)
  if not added then return nil, addReason end
  return true
end

function executor:handle(request)
  local cached = state.findCompleted(self.snapshot, request.request_id)
  if cached then
    if cached.fingerprint ~= request.fingerprint then
      return result("rejected", "request_id_conflict",
        "request identifier was already used with different contents")
    end
    return self:completedReply(cached)
  end

  if self.snapshot.in_flight and self.snapshot.in_flight.request_id == request.request_id then
    if self.snapshot.in_flight.fingerprint ~= request.fingerprint then
      return result("rejected", "request_id_conflict",
        "in-flight request identifier has different contents")
    end
    return result("recovery_required", "request_in_flight",
      "request outcome is not safely repeatable", self:statusPayload())
  end

  if #self.snapshot.completed >= self.cache_size then
    return result("rejected", "result_cache_full",
      "completed request retention is full; no new request will execute",
      self:statusPayload())
  end

  if request.operation == "status" then
    local payload = self:statusPayload()
    payload.code = "status"
    payload.message = "status returned"
    local recorded, recordReason = self:recordCompletion(request, "succeeded", payload)
    if not recorded then
      return result("rejected", "result_encoding_failed", tostring(recordReason))
    end
    local saved, saveReason = self:saveOrLock("status result could not be persisted")
    if not saved then
      return result("rejected", "persistence_failed", tostring(saveReason), self:statusPayload())
    end
    return {outcome = "succeeded", payload = payload}
  end

  if not self.persistence_available then
    return result("recovery_required", "persistence_unavailable",
      "physical execution is disabled because durable state is unavailable", self:statusPayload())
  end
  if self.snapshot.mode ~= "ready" then
    return result("recovery_required", "robot_not_ready",
      "physical execution is disabled until recovery", self:statusPayload())
  end
  if not protocol.isPhysical(request.operation) then
    return result("rejected", "unsupported_operation", "operation is not physical")
  end

  self.snapshot.mode = "in_flight"
  self.snapshot.in_flight = {
    request_id = request.request_id,
    fingerprint = request.fingerprint,
    deployment_id = request.deployment_id,
    operation = request.operation,
    phase = "prepared"
  }
  local prepared, prepareReason = self:saveOrLock("prepared intent could not be persisted")
  if not prepared then
    return result("rejected", "persistence_failed_before_execution",
      tostring(prepareReason), self:statusPayload())
  end

  self.snapshot.in_flight.phase = "executing"
  local executing, executingReason = self:saveOrLock("execution marker could not be persisted")
  if not executing then
    return result("rejected", "persistence_failed_before_execution",
      tostring(executingReason), self:statusPayload())
  end

  local executingSnapshot = state.copy(self.snapshot)
  local callOk, operationOk, detail = pcall(self.perform, request.operation)
  if not callOk then
    self.snapshot = executingSnapshot
    self.snapshot.mode = "recovery_required"
    self.snapshot.pose = pose.unknown(self.snapshot.pose, "operation raised an exception")
    self.snapshot.last_error = tostring(operationOk)
    self.store.save(self.snapshot)
    return result("recovery_required", "operation_exception",
      tostring(operationOk), self:statusPayload())
  end

  local outcome
  local code
  local message
  if operationOk then
    local nextPose, poseReason = pose.apply(self.snapshot.pose, request.operation)
    if not nextPose then
      self.snapshot = executingSnapshot
      self.snapshot.mode = "recovery_required"
      self.snapshot.pose = pose.unknown(self.snapshot.pose, "pose transition failed")
      self.snapshot.last_error = tostring(poseReason)
      self.store.save(self.snapshot)
      return result("recovery_required", "pose_transition_failed",
        tostring(poseReason), self:statusPayload())
    end
    self.snapshot.pose = nextPose
    outcome = "succeeded"
    code = "operation_succeeded"
    message = tostring(detail or "OK")
  else
    outcome = "failed"
    code = "operation_failed"
    message = tostring(detail or "blocked")
  end

  self.snapshot.mode = "ready"
  self.snapshot.in_flight = nil
  self.snapshot.last_error = ""
  local payload = self:statusPayload()
  payload.code = code
  payload.message = message

  local recorded, recordReason = self:recordCompletion(request, outcome, payload)
  if not recorded then
    self.snapshot = executingSnapshot
    self.snapshot.mode = "recovery_required"
    self.snapshot.pose = pose.unknown(self.snapshot.pose, "operation result could not be encoded")
    self.snapshot.last_error = tostring(recordReason)
    self.store.save(self.snapshot)
    return result("recovery_required", "result_encoding_failed",
      tostring(recordReason), self:statusPayload())
  end

  local saved, saveReason = self.store.save(self.snapshot)
  if not saved then
    self.snapshot = executingSnapshot
    self.snapshot.mode = "recovery_required"
    self.snapshot.pose = pose.unknown(self.snapshot.pose, "operation result could not be persisted")
    self.snapshot.last_error = tostring(saveReason)
    self.persistence_available = false
    return result("recovery_required", "completion_persistence_failed",
      tostring(saveReason), self:statusPayload())
  end

  return {outcome = outcome, payload = payload}
end

function executor:beginManualRecovery()
  self.snapshot.mode = "recovery_required"
  self.snapshot.pose = pose.unknown(self.snapshot.pose, "legacy manual movement")
  self.snapshot.last_error = "legacy manual movement invalidated autonomous pose"
  local saved, reason = self.store.save(self.snapshot)
  if not saved then
    self.persistence_available = false
    return nil, reason
  end
  return true
end

return executor

