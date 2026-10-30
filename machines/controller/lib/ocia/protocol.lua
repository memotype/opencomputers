local protocol = {}

protocol.MAGIC = "OCIA"
protocol.VERSION = 1
protocol.MESSAGE_PARTS = 8
protocol.MAX_WIRE_PAYLOAD = 4096
protocol.NO_DEPLOYMENT = "-"

protocol.operations = {
  status = {physical = false},
  turn_left = {physical = true},
  turn_right = {physical = true},
  move_forward = {physical = true},
  move_backward = {physical = true},
  move_up = {physical = true},
  move_down = {physical = true}
}

protocol.outcomes = {
  succeeded = true,
  failed = true,
  rejected = true,
  recovery_required = true
}

local function isInteger(value)
  return type(value) == "number" and value == math.floor(value)
end

local function validToken(value, maximum)
  return type(value) == "string"
    and #value >= 1
    and #value <= maximum
    and value:match("^[%w%._:%-]+$") ~= nil
end

function protocol.validAddress(value)
  return type(value) == "string"
    and #value >= 8
    and #value <= 64
    and value:match("^[%x%-]+$") ~= nil
end

function protocol.escape(value)
  value = tostring(value)
  return (value:gsub("([^%w%-%._~])", function(character)
    return string.format("%%%02X", string.byte(character))
  end))
end

function protocol.unescape(value)
  if type(value) ~= "string" then
    return nil, "encoded value must be a string"
  end
  if value:gsub("%%%x%x", ""):find("%", 1, true) then
    return nil, "invalid percent escape"
  end
  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function protocol.encodeFields(fields)
  if fields == nil then
    return ""
  end
  if type(fields) ~= "table" then
    return nil, "fields must be a table"
  end

  local keys = {}
  for key, value in pairs(fields) do
    if not validToken(key, 32) then
      return nil, "invalid field name"
    end
    local valueType = type(value)
    if valueType ~= "string" and valueType ~= "number" and valueType ~= "boolean" then
      return nil, "field values must be strings, numbers, or booleans"
    end
    keys[#keys + 1] = key
  end
  table.sort(keys)

  local encoded = {}
  for _, key in ipairs(keys) do
    encoded[#encoded + 1] = protocol.escape(key) .. "=" .. protocol.escape(fields[key])
  end
  return table.concat(encoded, "&")
end

function protocol.decodeFields(encoded)
  if type(encoded) ~= "string" then
    return nil, "field payload must be a string"
  end
  if encoded == "" then
    return {}
  end

  local fields = {}
  local start = 1
  while start <= #encoded do
    local separator = encoded:find("&", start, true)
    local item
    if separator then
      item = encoded:sub(start, separator - 1)
      start = separator + 1
    else
      item = encoded:sub(start)
      start = #encoded + 1
    end

    local equals = item:find("=", 1, true)
    if not equals then
      return nil, "field is missing '='"
    end
    local key, keyReason = protocol.unescape(item:sub(1, equals - 1))
    if not key then return nil, keyReason end
    local value, valueReason = protocol.unescape(item:sub(equals + 1))
    if not value then return nil, valueReason end
    if not validToken(key, 32) then
      return nil, "invalid field name"
    end
    if fields[key] ~= nil then
      return nil, "duplicate field"
    end
    fields[key] = value
  end
  return fields
end

function protocol.isPhysical(operation)
  local definition = protocol.operations[operation]
  return definition and definition.physical or false
end

function protocol.parsePhysicalRequestId(requestId)
  if type(requestId) ~= "string" then return nil, "request ID must be a string" end
  local epoch, sequenceText = requestId:match("^p:([%x%-]+):(%d+)$")
  if not epoch or #epoch < 8 or #epoch > 48 then
    return nil, "physical request ID must contain a valid execution epoch"
  end
  local sequence = tonumber(sequenceText)
  if not sequence or sequence < 1 or sequence ~= math.floor(sequence)
      or sequence > 9007199254740991 then
    return nil, "physical request sequence is invalid"
  end
  return {epoch = epoch, sequence = sequence}
end

function protocol.makePhysicalRequestId(epoch, sequence)
  local value = "p:" .. tostring(epoch) .. ":" .. tostring(sequence)
  local parsed, reason = protocol.parsePhysicalRequestId(value)
  if not parsed then return nil, reason end
  return value
end

function protocol.validStatusRequestId(requestId)
  return validToken(requestId, 64) and requestId:match("^s:[%w%._:%-]+$") ~= nil
end

local function validateRequestIdentity(requestId, operation)
  if operation == "status" then
    if not protocol.validStatusRequestId(requestId) then
      return nil, "status request ID must use the s: namespace"
    end
  else
    local parsed, reason = protocol.parsePhysicalRequestId(requestId)
    if not parsed then return nil, reason end
  end
  return true
end

function protocol.fingerprint(request)
  return table.concat({
    tostring(request.version),
    request.deployment_id,
    request.recipient,
    request.operation,
    request.arguments_raw
  }, "|")
end

function protocol.buildRequest(request)
  if type(request) ~= "table" then
    return nil, "request must be a table"
  end
  local arguments, reason = protocol.encodeFields(request.arguments or {})
  if not arguments then return nil, reason end
  if #arguments > protocol.MAX_WIRE_PAYLOAD then return nil, "argument payload is too large" end
  local parts = {
    protocol.MAGIC,
    request.version or protocol.VERSION,
    "request",
    request.request_id,
    request.deployment_id or protocol.NO_DEPLOYMENT,
    request.recipient,
    request.operation,
    arguments
  }
  local parsed, code, message = protocol.parseRequest(parts, request.recipient)
  if not parsed then
    return nil, code .. ": " .. message
  end
  return parts
end

function protocol.parseRequest(parts, localAddress)
  if type(parts) ~= "table" then
    return nil, "malformed_request", "message must be a table"
  end
  if #parts ~= protocol.MESSAGE_PARTS then
    return nil, "malformed_request", "request must contain exactly eight parts"
  end
  if parts[1] ~= protocol.MAGIC then
    return nil, "wrong_protocol", "protocol marker does not match"
  end
  if not isInteger(parts[2]) or parts[2] ~= protocol.VERSION then
    return nil, "unsupported_version", "unsupported protocol version"
  end
  if parts[3] ~= "request" then
    return nil, "unexpected_message_type", "expected request"
  end
  if not validToken(parts[4], 64) then
    return nil, "invalid_request_id", "invalid request identifier"
  end
  if not validToken(parts[5], 64) then
    return nil, "invalid_deployment_id", "invalid deployment identifier"
  end
  if not protocol.validAddress(parts[6]) then
    return nil, "invalid_recipient", "invalid recipient address"
  end
  if localAddress and parts[6] ~= localAddress then
    return nil, "incorrect_recipient", "request is addressed to another component"
  end
  if type(parts[7]) ~= "string" or not protocol.operations[parts[7]] then
    return nil, "unsupported_operation", "operation is not supported"
  end
  local identityOk, identityReason = validateRequestIdentity(parts[4], parts[7])
  if not identityOk then
    return nil, "invalid_request_id", identityReason
  end
  local arguments, reason = protocol.decodeFields(parts[8])
  if not arguments then
    return nil, "invalid_arguments", reason
  end
  if #parts[8] > protocol.MAX_WIRE_PAYLOAD then
    return nil, "invalid_arguments", "argument payload is too large"
  end
  if next(arguments) ~= nil then
    return nil, "invalid_arguments", "initial operations do not accept arguments"
  end

  local request = {
    version = parts[2],
    request_id = parts[4],
    deployment_id = parts[5],
    recipient = parts[6],
    operation = parts[7],
    arguments = arguments,
    arguments_raw = parts[8]
  }
  request.fingerprint = protocol.fingerprint(request)
  return request
end

function protocol.buildReply(reply)
  if type(reply) ~= "table" then
    return nil, "reply must be a table"
  end
  if not protocol.outcomes[reply.outcome] then
    return nil, "invalid reply outcome"
  end
  local payload, reason = protocol.encodeFields(reply.payload or {})
  if not payload then return nil, reason end
  if #payload > protocol.MAX_WIRE_PAYLOAD then return nil, "result payload is too large" end

  local parts = {
    protocol.MAGIC,
    reply.version or protocol.VERSION,
    "reply",
    reply.request_id,
    reply.deployment_id or protocol.NO_DEPLOYMENT,
    reply.operation,
    reply.outcome,
    payload
  }
  local parsed, code, message = protocol.parseReply(parts)
  if not parsed then
    return nil, code .. ": " .. message
  end
  return parts
end

function protocol.parseReply(parts)
  if type(parts) ~= "table" or #parts ~= protocol.MESSAGE_PARTS then
    return nil, "malformed_reply", "reply must contain exactly eight parts"
  end
  if parts[1] ~= protocol.MAGIC then
    return nil, "wrong_protocol", "protocol marker does not match"
  end
  if not isInteger(parts[2]) or parts[2] ~= protocol.VERSION then
    return nil, "unsupported_version", "unsupported protocol version"
  end
  if parts[3] ~= "reply" then
    return nil, "unexpected_message_type", "expected reply"
  end
  if not validToken(parts[4], 64) then
    return nil, "invalid_request_id", "invalid request identifier"
  end
  if not validToken(parts[5], 64) then
    return nil, "invalid_deployment_id", "invalid deployment identifier"
  end
  if type(parts[6]) ~= "string" or not protocol.operations[parts[6]] then
    return nil, "unsupported_operation", "reply operation is not supported"
  end
  local identityOk, identityReason = validateRequestIdentity(parts[4], parts[6])
  if not identityOk then
    return nil, "invalid_request_id", identityReason
  end
  if not protocol.outcomes[parts[7]] then
    return nil, "invalid_outcome", "reply outcome is not supported"
  end
  local payload, reason = protocol.decodeFields(parts[8])
  if not payload then
    return nil, "invalid_result", reason
  end
  if #parts[8] > protocol.MAX_WIRE_PAYLOAD then
    return nil, "invalid_result", "result payload is too large"
  end
  return {
    version = parts[2],
    request_id = parts[4],
    deployment_id = parts[5],
    operation = parts[6],
    outcome = parts[7],
    payload = payload,
    payload_raw = parts[8]
  }
end

function protocol.correlate(reply, request)
  if reply.request_id ~= request.request_id then
    return nil, "request_id_mismatch"
  end
  if reply.deployment_id ~= request.deployment_id then
    return nil, "deployment_id_mismatch"
  end
  if reply.operation ~= request.operation then
    return nil, "operation_mismatch"
  end
  return true
end

function protocol.certainty(outcome)
  if outcome == "succeeded" then return "succeeded" end
  if outcome == "failed" or outcome == "rejected" then return "failed" end
  return "unknown"
end

return protocol

