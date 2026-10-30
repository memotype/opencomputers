local protocol = require("ocia.protocol")
local pose = require("ocia.pose")

local state = {}

state.FORMAT = 2
state.modes = {ready = true, in_flight = true, recovery_required = true}

local function copyTable(source)
  if type(source) ~= "table" then return source end
  local result = {}
  for key, value in pairs(source) do result[key] = copyTable(value) end
  return result
end

local function integer(value)
  return type(value) == "number" and value == math.floor(value)
end

local function timed(timer, callback)
  local started = timer()
  local values = table.pack(callback())
  local elapsed = math.floor((timer() - started) * 1000 + 0.5)
  return elapsed, table.unpack(values, 1, values.n)
end

function state.default(reason, health)
  return {
    format = state.FORMAT,
    mode = "recovery_required",
    pose = pose.unknown(pose.new(), reason or "origin commissioning required"),
    epoch = "",
    high_water = 0,
    in_flight = nil,
    recent = {},
    last_error = reason or "origin commissioning required",
    journal = {
      health = health or "uninitialized",
      generation = 0,
      records = 0,
      bytes = 0,
      last_persist_ms = 0
    }
  }
end

function state.copy(snapshot)
  return copyTable(snapshot)
end

local function validRecent(entry)
  return type(entry) == "table"
    and integer(entry.sequence) and entry.sequence >= 1
    and type(entry.request_id) == "string"
    and type(entry.fingerprint) == "string"
    and type(entry.deployment_id) == "string"
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
  if type(snapshot.epoch) ~= "string" then return nil, "epoch must be a string" end
  if snapshot.epoch ~= "" and not snapshot.epoch:match("^[%x%-]+$") then
    return nil, "invalid execution epoch"
  end
  if not integer(snapshot.high_water) or snapshot.high_water < 0 then
    return nil, "invalid high-water sequence"
  end
  if type(snapshot.recent) ~= "table" then return nil, "recent cache must be a table" end
  for index, entry in ipairs(snapshot.recent) do
    if not validRecent(entry) then return nil, "invalid recent entry " .. index end
  end
  if snapshot.in_flight then
    local item = snapshot.in_flight
    if type(item) ~= "table" or not integer(item.sequence)
        or type(item.request_id) ~= "string"
        or type(item.fingerprint) ~= "string"
        or type(item.deployment_id) ~= "string"
        or not protocol.isPhysical(item.operation)
        or (item.phase ~= "prepared" and item.phase ~= "executing") then
      return nil, "invalid in-flight request"
    end
  end
  if snapshot.mode == "in_flight" and not snapshot.in_flight then
    return nil, "in-flight mode requires a request"
  end
  if snapshot.mode == "ready" and (snapshot.in_flight or not snapshot.pose.trusted
      or snapshot.epoch == "") then
    return nil, "ready mode requires commissioned trusted state"
  end
  if type(snapshot.last_error) ~= "string" then return nil, "last error must be text" end
  if type(snapshot.journal) ~= "table" then return nil, "journal metrics are missing" end
  return true
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

local function numberField(fields, key)
  local value = tonumber(fields[key])
  if not value or value ~= math.floor(value) then
    return nil, "invalid numeric field " .. key
  end
  return value
end

local function booleanField(value)
  if type(value) == "boolean" then return value end
  if value == "true" then return true end
  if value == "false" then return false end
  return nil
end

local function addRecent(snapshot, entry, maximum)
  snapshot.recent[#snapshot.recent + 1] = entry
  while #snapshot.recent > maximum do table.remove(snapshot.recent, 1) end
end

function state.findRecent(snapshot, sequence)
  for _, entry in ipairs(snapshot.recent) do
    if entry.sequence == sequence then return entry end
  end
end

function state.applyRecord(snapshot, fields, recentLimit)
  recentLimit = recentLimit or 32
  local kind = fields.kind
  if kind == "checkpoint" then
    local generation, reason = numberField(fields, "generation")
    if not generation then return nil, reason end
    local highWater, highReason = numberField(fields, "high_water")
    if not highWater then return nil, highReason end
    local x, xReason = numberField(fields, "pose_x")
    if not x then return nil, xReason end
    local y, yReason = numberField(fields, "pose_y")
    if not y then return nil, yReason end
    local z, zReason = numberField(fields, "pose_z")
    if not z then return nil, zReason end
    local trusted = booleanField(fields.pose_trusted)
    if trusted == nil then return nil, "invalid checkpoint pose trust" end
    if not fields.epoch or not fields.epoch:match("^[%x%-]+$") then
      return nil, "invalid checkpoint epoch"
    end
    snapshot.format = state.FORMAT
    snapshot.mode = fields.mode
    snapshot.pose = {
      trusted = trusted, x = x, y = y, z = z,
      heading = fields.pose_heading, reason = fields.pose_reason or ""
    }
    snapshot.epoch = fields.epoch
    snapshot.high_water = highWater
    snapshot.in_flight = nil
    snapshot.recent = {}
    snapshot.last_error = fields.last_error or ""
    snapshot.journal.generation = generation
  elseif kind == "retained" then
    local sequence, reason = numberField(fields, "sequence")
    if not sequence then return nil, reason end
    if sequence > snapshot.high_water then return nil, "retained result exceeds high water" end
    addRecent(snapshot, {
      sequence = sequence,
      request_id = fields.request_id,
      fingerprint = fields.fingerprint,
      deployment_id = fields.deployment_id,
      operation = fields.operation,
      outcome = fields.outcome,
      payload_raw = fields.payload
    }, recentLimit)
  elseif kind == "prepared" then
    local sequence, reason = numberField(fields, "sequence")
    if not sequence then return nil, reason end
    if fields.epoch ~= snapshot.epoch or sequence ~= snapshot.high_water + 1 then
      return nil, "prepared sequence or epoch is not contiguous"
    end
    snapshot.high_water = sequence
    snapshot.mode = "in_flight"
    snapshot.in_flight = {
      sequence = sequence,
      request_id = fields.request_id,
      fingerprint = fields.fingerprint,
      deployment_id = fields.deployment_id,
      operation = fields.operation,
      phase = "prepared"
    }
  elseif kind == "executing" then
    local sequence, reason = numberField(fields, "sequence")
    if not sequence then return nil, reason end
    if not snapshot.in_flight or snapshot.in_flight.sequence ~= sequence
        or snapshot.in_flight.request_id ~= fields.request_id
        or snapshot.in_flight.phase ~= "prepared" then
      return nil, "executing record has no matching prepared record"
    end
    snapshot.in_flight.phase = "executing"
  elseif kind == "completed" then
    local sequence, reason = numberField(fields, "sequence")
    if not sequence then return nil, reason end
    if not snapshot.in_flight or snapshot.in_flight.sequence ~= sequence
        or snapshot.in_flight.request_id ~= fields.request_id then
      return nil, "completion has no matching in-flight request"
    end
    local x, xReason = numberField(fields, "pose_x")
    if not x then return nil, xReason end
    local y, yReason = numberField(fields, "pose_y")
    if not y then return nil, yReason end
    local z, zReason = numberField(fields, "pose_z")
    if not z then return nil, zReason end
    local trusted = booleanField(fields.pose_trusted)
    if trusted == nil then return nil, "invalid completed pose trust" end
    snapshot.pose = {
      trusted = trusted, x = x, y = y, z = z,
      heading = fields.pose_heading, reason = fields.pose_reason or ""
    }
    addRecent(snapshot, {
      sequence = sequence,
      request_id = fields.request_id,
      fingerprint = snapshot.in_flight.fingerprint,
      deployment_id = snapshot.in_flight.deployment_id,
      operation = snapshot.in_flight.operation,
      outcome = fields.outcome,
      payload_raw = fields.payload
    }, recentLimit)
    snapshot.mode = "ready"
    snapshot.in_flight = nil
    snapshot.last_error = ""
  elseif kind == "manual" then
    snapshot.mode = "recovery_required"
    snapshot.pose = pose.unknown(snapshot.pose, "legacy manual movement")
    snapshot.last_error = "legacy manual movement invalidated autonomous pose"
  else
    return nil, "unsupported journal record " .. tostring(kind)
  end
  return state.validate(snapshot)
end

local function checkpointFields(snapshot, generation)
  return {
    kind = "checkpoint", generation = generation, mode = snapshot.mode,
    epoch = snapshot.epoch, high_water = snapshot.high_water,
    pose_trusted = snapshot.pose.trusted, pose_x = snapshot.pose.x,
    pose_y = snapshot.pose.y, pose_z = snapshot.pose.z,
    pose_heading = snapshot.pose.heading, pose_reason = snapshot.pose.reason or "",
    last_error = snapshot.last_error or ""
  }
end

local function retainedFields(entry)
  return {
    kind = "retained", sequence = entry.sequence,
    request_id = entry.request_id, fingerprint = entry.fingerprint,
    deployment_id = entry.deployment_id, operation = entry.operation,
    outcome = entry.outcome, payload = entry.payload_raw
  }
end

function state.journalStore(path, options)
  options = options or {}
  local filesystem = options.filesystem or require("filesystem")
  local open = options.open or io.open
  local timer = options.timer or require("computer").uptime
  local recentLimit = options.recent_limit or 32
  local temporary, old, switch = path .. ".new", path .. ".old", path .. ".switch"
  local store = {current_sequence = 0, health = "uninitialized", last_persist_ms = 0}

  local function ensureDirectory()
    local directory = filesystem.path(path)
    if filesystem.exists(directory) then return true end
    return filesystem.makeDirectory(directory)
  end

  local function fileSize(file)
    local value = filesystem.size(file)
    return type(value) == "number" and value or 0
  end

  local function closeHandle(handle)
    local closed, reason = pcall(function() return handle:close() end)
    if not closed then return nil, tostring(reason) end
    return true
  end

  local function writeLine(file, mode, line)
    local handle, reason = open(file, mode)
    if not handle then return nil, "open failed: " .. tostring(reason) end
    local wrote, writeReason = handle:write(line)
    if not wrote then
      closeHandle(handle)
      return nil, "write failed: " .. tostring(writeReason)
    end
    local flushed, flushReason = handle:flush()
    if not flushed then
      closeHandle(handle)
      return nil, "flush failed: " .. tostring(flushReason)
    end
    local closed, closeReason = closeHandle(handle)
    if not closed then return nil, "close failed: " .. tostring(closeReason) end
    return true
  end

  local function loadFile(file)
    local handle, reason = open(file, "r")
    if not handle then return nil, "open failed: " .. tostring(reason) end
    local snapshot = state.default("journal has no checkpoint", "loading")
    local expectedSequence, consumed, sawCheckpoint = 1, 0, false
    while true do
      local line = handle:read("*l")
      if line == nil then break end
      consumed = consumed + #line + 1
      local fields, decodeReason = state.decodeRecord(line)
      if not fields then closeHandle(handle); return nil, decodeReason end
      local sequence, sequenceReason = numberField(fields, "journal_sequence")
      if not sequence then closeHandle(handle); return nil, sequenceReason end
      if sequence ~= expectedSequence then
        closeHandle(handle); return nil, "journal sequence is not contiguous"
      end
      if not sawCheckpoint then
        if fields.kind ~= "checkpoint" then
          closeHandle(handle); return nil, "journal does not begin with a checkpoint"
        end
        sawCheckpoint = true
      elseif fields.kind == "checkpoint" then
        closeHandle(handle); return nil, "unexpected checkpoint in journal"
      end
      local applied, applyReason = state.applyRecord(snapshot, fields, recentLimit)
      if not applied then closeHandle(handle); return nil, applyReason end
      expectedSequence = expectedSequence + 1
    end
    local closed, closeReason = closeHandle(handle)
    if not closed then return nil, "close failed: " .. tostring(closeReason) end
    if not sawCheckpoint then return nil, "journal is empty" end
    local bytes = fileSize(file)
    if consumed ~= bytes then return nil, "journal has a partial final record" end
    snapshot.journal.health = "healthy"
    snapshot.journal.records = expectedSequence - 1
    snapshot.journal.bytes = bytes
    snapshot.journal.last_persist_ms = store.last_persist_ms
    return snapshot, expectedSequence - 1
  end

  local function artifactsPresent()
    return filesystem.exists(temporary) or filesystem.exists(old) or filesystem.exists(switch)
  end

  function store.load()
    if artifactsPresent() then
      store.health = "uncertain_artifacts"
      return state.default("journal replacement artifacts require explicit recovery",
        store.health), {source = "artifacts"}
    end
    if not filesystem.exists(path) then
      store.health = "uninitialized"
      return state.default("origin commissioning required", store.health), {source = "new"}
    end
    local snapshot, sequenceOrReason = loadFile(path)
    if not snapshot then
      store.health = "corrupt"
      return state.default("journal cannot be trusted: " .. tostring(sequenceOrReason),
        store.health), {source = "corrupt", error = sequenceOrReason}
    end
    store.current_sequence = sequenceOrReason
    store.health = "healthy"
    return snapshot, {source = path}
  end

  function store.append(snapshot, fields)
    if store.health ~= "healthy" then return nil, "journal is not healthy" end
    fields.journal_sequence = store.current_sequence + 1
    local line, encodeReason = state.encodeRecord(fields)
    if not line then return nil, encodeReason end
    local elapsed, wrote, writeReason = timed(timer, function()
      return writeLine(path, "a", line)
    end)
    store.last_persist_ms = elapsed
    snapshot.journal.last_persist_ms = elapsed
    if not wrote then
      store.health = "uncertain_write"
      snapshot.journal.health = store.health
      return nil, writeReason
    end
    local applied, applyReason = state.applyRecord(snapshot, fields, recentLimit)
    if not applied then
      store.health = "invalid_append"
      snapshot.journal.health = store.health
      return nil, applyReason
    end
    store.current_sequence = store.current_sequence + 1
    snapshot.journal.records = store.current_sequence
    snapshot.journal.bytes = fileSize(path)
    snapshot.journal.health = "healthy"
    return true
  end

  local function removeIfPresent(file)
    if not filesystem.exists(file) then return true end
    local removed, reason = filesystem.remove(file)
    if not removed then return nil, reason end
    return true
  end

  local function writeReplacement(snapshot, generation, clearArtifacts)
    if clearArtifacts then
      for _, file in ipairs({temporary, old, switch}) do
        local removed, reason = removeIfPresent(file)
        if not removed then return nil, "artifact cleanup failed: " .. tostring(reason) end
      end
    elseif artifactsPresent() then
      return nil, "replacement artifacts already exist"
    end
    local directoryOk, directoryReason = ensureDirectory()
    if not directoryOk then return nil, "directory creation failed: " .. tostring(directoryReason) end
    local markerOk, markerReason = writeLine(switch, "w", "replacement-in-progress\n")
    if not markerOk then return nil, "switch marker failed: " .. tostring(markerReason) end

    local sequence = 1
    local fields = checkpointFields(snapshot, generation)
    fields.journal_sequence = sequence
    local line = assert(state.encodeRecord(fields))
    local wrote, reason = writeLine(temporary, "w", line)
    if not wrote then return nil, "checkpoint write failed: " .. tostring(reason) end
    for _, entry in ipairs(snapshot.recent) do
      sequence = sequence + 1
      fields = retainedFields(entry)
      fields.journal_sequence = sequence
      line = assert(state.encodeRecord(fields))
      wrote, reason = writeLine(temporary, "a", line)
      if not wrote then return nil, "retained write failed: " .. tostring(reason) end
    end

    local verified, verifySequence = loadFile(temporary)
    if not verified then return nil, "replacement verification failed: " .. tostring(verifySequence) end
    if filesystem.exists(path) then
      local moved, moveReason = filesystem.rename(path, old)
      if not moved then return nil, "primary preservation failed: " .. tostring(moveReason) end
    end
    local installed, installReason = filesystem.rename(temporary, path)
    if not installed then return nil, "replacement install failed: " .. tostring(installReason) end
    local oldRemoved, oldReason = removeIfPresent(old)
    if not oldRemoved then return nil, "old journal removal failed: " .. tostring(oldReason) end
    local markerRemoved, markerRemoveReason = removeIfPresent(switch)
    if not markerRemoved then return nil, "switch marker removal failed: " .. tostring(markerRemoveReason) end

    store.current_sequence = verifySequence
    store.health = "healthy"
    snapshot.journal.generation = generation
    snapshot.journal.records = verifySequence
    snapshot.journal.bytes = fileSize(path)
    snapshot.journal.health = "healthy"
    return true
  end

  function store.compact(snapshot)
    if store.health ~= "healthy" then return nil, "journal is not healthy" end
    if snapshot.mode ~= "ready" then return nil, "compaction requires ready state" end
    local elapsed, ok, reason = timed(timer, function()
      return writeReplacement(snapshot, snapshot.journal.generation + 1, false)
    end)
    store.last_persist_ms = elapsed
    snapshot.journal.last_persist_ms = elapsed
    if not ok then
      store.health = "uncertain_compaction"
      snapshot.journal.health = store.health
      return nil, reason
    end
    return true
  end

  function store.commission(epoch, commissionedPose)
    local snapshot = state.default("", "commissioning")
    snapshot.mode = "ready"
    snapshot.pose = pose.copy(commissionedPose)
    snapshot.epoch = epoch
    snapshot.high_water = 0
    snapshot.last_error = ""
    snapshot.journal.generation = 1
    local ok, reason = writeReplacement(snapshot, 1, true)
    if not ok then
      store.health = "uncertain_commissioning"
      return nil, reason
    end
    return snapshot
  end

  function store.metrics()
    return {
      health = store.health, records = store.current_sequence,
      bytes = filesystem.exists(path) and fileSize(path) or 0,
      last_persist_ms = store.last_persist_ms
    }
  end

  return store
end

function state.memoryStore(initial, options)
  options = options or {}
  local snapshot = state.copy(initial or state.default())
  local store = {append_count = 0, compact_count = 0, fail_at = nil,
    health = snapshot.journal.health, current_sequence = snapshot.journal.records or 0}

  function store.load() return state.copy(snapshot), {source = "memory"} end

  function store.append(target, fields)
    store.append_count = store.append_count + 1
    if store.fail_at == store.append_count then
      store.health = "uncertain_write"
      target.journal.health = store.health
      return nil, "injected persistence failure"
    end
    fields.journal_sequence = store.current_sequence + 1
    local applied, reason = state.applyRecord(target, fields, options.recent_limit or 32)
    if not applied then return nil, reason end
    store.current_sequence = fields.journal_sequence
    target.journal.health = "healthy"
    target.journal.records = store.current_sequence
    target.journal.bytes = target.journal.bytes + #(assert(state.encodeRecord(fields)))
    snapshot = state.copy(target)
    store.health = "healthy"
    return true
  end

  function store.compact(target)
    store.compact_count = store.compact_count + 1
    if options.fail_compact then return nil, "injected compaction failure" end
    target.journal.generation = target.journal.generation + 1
    target.journal.records = 1 + #target.recent
    target.journal.bytes = 200
    store.current_sequence = target.journal.records
    snapshot = state.copy(target)
    return true
  end

  function store.commission(epoch, commissionedPose)
    snapshot = state.default("", "healthy")
    snapshot.mode = "ready"
    snapshot.pose = pose.copy(commissionedPose)
    snapshot.epoch = epoch
    snapshot.last_error = ""
    snapshot.journal = {health = "healthy", generation = 1, records = 1,
      bytes = 200, last_persist_ms = 0}
    store.current_sequence = 1
    store.health = "healthy"
    return state.copy(snapshot)
  end

  function store.peek() return state.copy(snapshot) end
  function store.metrics() return copyTable(snapshot.journal) end
  return store
end

return state
