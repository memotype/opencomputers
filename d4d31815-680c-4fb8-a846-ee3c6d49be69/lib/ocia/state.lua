local protocol = require("ocia.protocol")
local pose = require("ocia.pose")

local state = {}

state.FORMAT = 1
state.modes = {
  ready = true,
  in_flight = true,
  recovery_required = true
}

local function copyTable(source)
  if type(source) ~= "table" then return source end
  local result = {}
  for key, value in pairs(source) do
    result[key] = copyTable(value)
  end
  return result
end

function state.default()
  return {
    format = state.FORMAT,
    mode = "ready",
    pose = pose.new(0, 0, 0, "north"),
    in_flight = nil,
    completed = {},
    last_error = ""
  }
end

function state.copy(snapshot)
  return copyTable(snapshot)
end

local function validCompleted(entry)
  return type(entry) == "table"
    and type(entry.request_id) == "string"
    and type(entry.fingerprint) == "string"
    and type(entry.deployment_id) == "string"
    and type(entry.operation) == "string"
    and protocol.operations[entry.operation] ~= nil
    and protocol.outcomes[entry.outcome] ~= nil
    and type(entry.payload_raw) == "string"
end

function state.validate(snapshot)
  if type(snapshot) ~= "table" then return nil, "state must be a table" end
  if snapshot.format ~= state.FORMAT then return nil, "unsupported state format" end
  if not state.modes[snapshot.mode] then return nil, "invalid state mode" end
  local poseOk, poseReason = pose.validate(snapshot.pose)
  if not poseOk then return nil, poseReason end
  if type(snapshot.completed) ~= "table" then return nil, "completed cache must be a table" end
  for index, entry in ipairs(snapshot.completed) do
    if not validCompleted(entry) then
      return nil, "invalid completed entry " .. index
    end
  end
  if snapshot.in_flight ~= nil then
    local item = snapshot.in_flight
    if type(item) ~= "table"
        or type(item.request_id) ~= "string"
        or type(item.fingerprint) ~= "string"
        or type(item.deployment_id) ~= "string"
        or not protocol.operations[item.operation]
        or (item.phase ~= "prepared" and item.phase ~= "executing") then
      return nil, "invalid in-flight request"
    end
  end
  if snapshot.mode == "in_flight" and snapshot.in_flight == nil then
    return nil, "in-flight mode requires a request"
  end
  if snapshot.mode == "ready" and snapshot.in_flight ~= nil then
    return nil, "ready mode cannot contain an in-flight request"
  end
  if type(snapshot.last_error) ~= "string" then return nil, "last_error must be a string" end
  return true
end

function state.encode(snapshot)
  local ok, reason = state.validate(snapshot)
  if not ok then return nil, reason end

  local fields = {
    format = snapshot.format,
    mode = snapshot.mode,
    pose_trusted = snapshot.pose.trusted,
    pose_x = snapshot.pose.x,
    pose_y = snapshot.pose.y,
    pose_z = snapshot.pose.z,
    pose_heading = snapshot.pose.heading,
    pose_reason = snapshot.pose.reason or "",
    last_error = snapshot.last_error or "",
    completed_count = #snapshot.completed
  }

  if snapshot.in_flight then
    fields.in_request_id = snapshot.in_flight.request_id
    fields.in_fingerprint = snapshot.in_flight.fingerprint
    fields.in_deployment_id = snapshot.in_flight.deployment_id
    fields.in_operation = snapshot.in_flight.operation
    fields.in_phase = snapshot.in_flight.phase
  end

  for index, entry in ipairs(snapshot.completed) do
    local prefix = "c" .. index .. "_"
    fields[prefix .. "request_id"] = entry.request_id
    fields[prefix .. "fingerprint"] = entry.fingerprint
    fields[prefix .. "deployment_id"] = entry.deployment_id
    fields[prefix .. "operation"] = entry.operation
    fields[prefix .. "outcome"] = entry.outcome
    fields[prefix .. "payload"] = entry.payload_raw
  end

  return protocol.encodeFields(fields)
end

local function required(fields, key)
  if fields[key] == nil then return nil, "missing state field " .. key end
  return fields[key]
end

local function parseInteger(fields, key)
  local raw, reason = required(fields, key)
  if raw == nil then return nil, reason end
  local value = tonumber(raw)
  if not value or value ~= math.floor(value) then
    return nil, "invalid integer state field " .. key
  end
  return value
end

function state.decode(text)
  if type(text) ~= "string" then return nil, "state text must be a string" end
  text = text:gsub("%s+$", "")
  local fields, reason = protocol.decodeFields(text)
  if not fields then return nil, reason end

  local format, formatReason = parseInteger(fields, "format")
  if not format then return nil, formatReason end
  local x, xReason = parseInteger(fields, "pose_x")
  if not x then return nil, xReason end
  local y, yReason = parseInteger(fields, "pose_y")
  if not y then return nil, yReason end
  local z, zReason = parseInteger(fields, "pose_z")
  if not z then return nil, zReason end
  local count, countReason = parseInteger(fields, "completed_count")
  if not count then return nil, countReason end
  if count < 0 or count > 256 then return nil, "invalid completed cache size" end

  local trustedRaw, trustedReason = required(fields, "pose_trusted")
  if not trustedRaw then return nil, trustedReason end
  local trusted
  if trustedRaw == "true" then trusted = true
  elseif trustedRaw == "false" then trusted = false
  else return nil, "invalid pose trust state" end

  local snapshot = {
    format = format,
    mode = fields.mode,
    pose = {
      trusted = trusted,
      x = x,
      y = y,
      z = z,
      heading = fields.pose_heading,
      reason = fields.pose_reason or ""
    },
    completed = {},
    last_error = fields.last_error or ""
  }

  if fields.in_request_id or fields.in_fingerprint or fields.in_operation or fields.in_phase then
    snapshot.in_flight = {
      request_id = fields.in_request_id,
      fingerprint = fields.in_fingerprint,
      deployment_id = fields.in_deployment_id,
      operation = fields.in_operation,
      phase = fields.in_phase
    }
  end

  for index = 1, count do
    local prefix = "c" .. index .. "_"
    snapshot.completed[index] = {
      request_id = fields[prefix .. "request_id"],
      fingerprint = fields[prefix .. "fingerprint"],
      deployment_id = fields[prefix .. "deployment_id"],
      operation = fields[prefix .. "operation"],
      outcome = fields[prefix .. "outcome"],
      payload_raw = fields[prefix .. "payload"]
    }
  end

  local ok, validationReason = state.validate(snapshot)
  if not ok then return nil, validationReason end
  return snapshot
end

function state.findCompleted(snapshot, requestId)
  for _, entry in ipairs(snapshot.completed) do
    if entry.request_id == requestId then return entry end
  end
end

function state.addCompleted(snapshot, entry, maximum)
  if #snapshot.completed >= maximum then
    return nil, "completed-result cache is full"
  end
  snapshot.completed[#snapshot.completed + 1] = copyTable(entry)
  return true
end

function state.reconcileAfterLoad(snapshot, cacheSize)
  if not snapshot.in_flight then return false end
  local item = snapshot.in_flight

  if item.phase == "prepared" then
    local payload = assert(protocol.encodeFields({
      code = "interrupted_before_execution",
      message = "request was journaled but physical execution had not begun"
    }))
    local added, addReason = state.addCompleted(snapshot, {
      request_id = item.request_id,
      fingerprint = item.fingerprint,
      deployment_id = item.deployment_id,
      operation = item.operation,
      outcome = "failed",
      payload_raw = payload
    }, cacheSize)
    if not added then
      snapshot.mode = "recovery_required"
      snapshot.last_error = tostring(addReason)
      return true, "retention_full"
    end
    snapshot.in_flight = nil
    snapshot.mode = "ready"
    snapshot.last_error = "interrupted before physical execution"
    return true, "not_started"
  end

  snapshot.mode = "recovery_required"
  snapshot.pose = pose.unknown(snapshot.pose, "interrupted physical operation")
  snapshot.last_error = "physical operation outcome is ambiguous after restart"
  return true, "ambiguous"
end

local function readAll(open, path)
  local handle, reason = open(path, "r")
  if not handle then return nil, reason end
  local content = handle:read("*a")
  handle:close()
  return content
end

function state.fileStore(path, dependencies)
  dependencies = dependencies or {}
  local filesystem = dependencies.filesystem or require("filesystem")
  local open = dependencies.open or io.open

  local store = {}

  function store.load()
    local candidates = {path, path .. ".bak"}
    local errors = {}
    for _, candidate in ipairs(candidates) do
      if filesystem.exists(candidate) then
        local text, readReason = readAll(open, candidate)
        if text then
          local snapshot, decodeReason = state.decode(text)
          if snapshot then
            return snapshot, {source = candidate}
          end
          errors[#errors + 1] = candidate .. ": " .. tostring(decodeReason)
        else
          errors[#errors + 1] = candidate .. ": " .. tostring(readReason)
        end
      end
    end

    if #errors > 0 then
      return nil, table.concat(errors, "; ")
    end
    return state.default(), {source = "new"}
  end

  function store.save(snapshot)
    local encoded, reason = state.encode(snapshot)
    if not encoded then return nil, reason end

    local directory = filesystem.path(path)
    if not filesystem.exists(directory) then
      local made, makeReason = filesystem.makeDirectory(directory)
      if not made then return nil, "cannot create state directory: " .. tostring(makeReason) end
    end

    local temporary = path .. ".new"
    local backup = path .. ".bak"
    if filesystem.exists(temporary) then filesystem.remove(temporary) end

    local handle, openReason = open(temporary, "w")
    if not handle then return nil, "cannot open temporary state: " .. tostring(openReason) end
    local wrote, writeReason = handle:write(encoded .. "\n")
    if not wrote then
      handle:close()
      filesystem.remove(temporary)
      return nil, "cannot write temporary state: " .. tostring(writeReason)
    end
    local flushed, flushReason = handle:flush()
    if not flushed then
      handle:close()
      filesystem.remove(temporary)
      return nil, "cannot flush temporary state: " .. tostring(flushReason)
    end
    handle:close()

    local verificationText, verifyReadReason = readAll(open, temporary)
    if not verificationText then
      filesystem.remove(temporary)
      return nil, "cannot verify temporary state: " .. tostring(verifyReadReason)
    end
    local verified, verifyReason = state.decode(verificationText)
    if not verified then
      filesystem.remove(temporary)
      return nil, "temporary state verification failed: " .. tostring(verifyReason)
    end

    if filesystem.exists(backup) then filesystem.remove(backup) end
    local movedCurrent = false
    if filesystem.exists(path) then
      local moved, moveReason = filesystem.rename(path, backup)
      if not moved then
        filesystem.remove(temporary)
        return nil, "cannot preserve previous state: " .. tostring(moveReason)
      end
      movedCurrent = true
    end

    local installed, installReason = filesystem.rename(temporary, path)
    if not installed then
      if movedCurrent and filesystem.exists(backup) and not filesystem.exists(path) then
        filesystem.rename(backup, path)
      end
      return nil, "cannot install new state: " .. tostring(installReason)
    end
    return true
  end

  return store
end

function state.memoryStore(initial)
  local snapshot = initial and state.copy(initial) or state.default()
  local store = {save_count = 0, fail_at = nil}

  function store.load()
    return state.copy(snapshot), {source = "memory"}
  end

  function store.save(value)
    store.save_count = store.save_count + 1
    if store.fail_at == store.save_count then
      return nil, "injected persistence failure"
    end
    snapshot = state.copy(value)
    return true
  end

  function store.peek()
    return state.copy(snapshot)
  end

  return store
end

return state

