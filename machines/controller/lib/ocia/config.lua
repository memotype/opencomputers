local protocol = require("ocia.protocol")

local config = {}

local defaults = {
  port = 4242,
  protocol_version = protocol.VERSION,
  timeout = 8,
  recent_results = 32,
  compact_records = 128,
  compact_bytes = 65536,
  legacy_enabled = true,
  state_path = "/var/lib/ocia/robot.state"
}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseBoolean(value)
  if value == "true" then return true end
  if value == "false" then return false end
  return nil
end

function config.parse(text)
  if type(text) ~= "string" then return nil, "configuration must be text" end
  local values = {}
  local lineNumber = 0

  for line in (text .. "\n"):gmatch("(.-)\n") do
    lineNumber = lineNumber + 1
    line = trim(line)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
      if not key then
        return nil, "invalid configuration line " .. lineNumber
      end
      if values[key] ~= nil then
        return nil, "duplicate configuration key " .. key
      end
      values[key] = value
    end
  end

  local result = {}
  for key, value in pairs(defaults) do result[key] = value end
  for key, value in pairs(values) do
    if defaults[key] == nil and key ~= "controller_address" and key ~= "robot_address" then
      return nil, "unknown configuration key " .. key
    end
    result[key] = value
  end

  result.port = tonumber(result.port)
  result.protocol_version = tonumber(result.protocol_version)
  result.timeout = tonumber(result.timeout)
  result.recent_results = tonumber(result.recent_results)
  result.compact_records = tonumber(result.compact_records)
  result.compact_bytes = tonumber(result.compact_bytes)
  if type(result.legacy_enabled) == "string" then
    result.legacy_enabled = parseBoolean(result.legacy_enabled)
  end

  return result
end

function config.validate(values, role)
  if type(values) ~= "table" then return nil, "configuration must be a table" end
  if role ~= "controller" and role ~= "robot" then return nil, "invalid configuration role" end
  if not protocol.validAddress(values.controller_address) then
    return nil, "controller_address must be configured with the full modem address"
  end
  if not protocol.validAddress(values.robot_address) then
    return nil, "robot_address must be configured with the full modem address"
  end
  if type(values.port) ~= "number" or values.port ~= math.floor(values.port)
      or values.port < 1 or values.port > 65535 then
    return nil, "port must be an integer from 1 through 65535"
  end
  if values.protocol_version ~= protocol.VERSION then
    return nil, "protocol_version must be " .. protocol.VERSION
  end
  if type(values.timeout) ~= "number" or values.timeout <= 0 or values.timeout > 120 then
    return nil, "timeout must be greater than zero and at most 120 seconds"
  end
  if type(values.recent_results) ~= "number"
      or values.recent_results ~= math.floor(values.recent_results)
      or values.recent_results < 1 or values.recent_results > 64 then
    return nil, "recent_results must be an integer from 1 through 64"
  end
  if type(values.compact_records) ~= "number"
      or values.compact_records ~= math.floor(values.compact_records)
      or values.compact_records < 16 or values.compact_records > 1024 then
    return nil, "compact_records must be an integer from 16 through 1024"
  end
  if type(values.compact_bytes) ~= "number"
      or values.compact_bytes ~= math.floor(values.compact_bytes)
      or values.compact_bytes < 8192 or values.compact_bytes > 262144 then
    return nil, "compact_bytes must be an integer from 8192 through 262144"
  end
  if type(values.legacy_enabled) ~= "boolean" then
    return nil, "legacy_enabled must be true or false"
  end
  if type(values.state_path) ~= "string" or values.state_path:sub(1, 1) ~= "/" then
    return nil, "state_path must be an absolute path"
  end
  return true
end

function config.load(path, role, dependencies)
  path = path or "/etc/ocia.cfg"
  local open = dependencies and dependencies.open or io.open
  local handle, reason = open(path, "r")
  if not handle then
    return nil, "cannot open " .. path .. ": " .. tostring(reason)
  end
  local text = handle:read("*a")
  handle:close()

  local values, parseReason = config.parse(text)
  if not values then return nil, parseReason end
  local ok, validationReason = config.validate(values, role)
  if not ok then return nil, validationReason end
  return values
end

return config

