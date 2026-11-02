local owner = {}

local OWNER_KEY = "ocia_controller_port_owner"

local function integer(value)
  return type(value) == "number" and value == math.floor(value)
end

function owner.acquire(port, label, dependencies)
  if not integer(port) or port < 1 or port > 65535 then
    return nil, "controller owner port must be an integer from 1 through 65535"
  end
  if type(label) ~= "string" or label == "" then
    return nil, "controller owner label must be nonempty text"
  end

  local process = dependencies and dependencies.process or require("process")
  local current = dependencies and dependencies.current or process.findProcess()
  if type(current) ~= "table" or type(current.data) ~= "table" then
    return nil, "current OpenOS process is unavailable"
  end

  local existing = rawget(current.data, OWNER_KEY)
  if existing then
    return nil, "current process already owns controller port " .. tostring(existing.port)
  end

  for _, candidate in pairs(process.list or {}) do
    if candidate ~= current and type(candidate) == "table"
        and type(candidate.data) == "table" then
      local held = rawget(candidate.data, OWNER_KEY)
      if held and held.port == port then
        return nil, "controller port " .. port .. " is owned by "
          .. tostring(held.label or "another OCIA process")
      end
    end
  end

  local record = {port = port, label = label, token = {}}
  rawset(current.data, OWNER_KEY, record)
  local released = false
  local lease = {}

  function lease.release()
    if released then return true end
    if rawget(current.data, OWNER_KEY) == record then
      rawset(current.data, OWNER_KEY, nil)
    end
    released = true
    return true
  end

  lease.port = port
  lease.label = label
  return lease
end

return owner
