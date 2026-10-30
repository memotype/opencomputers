local pose = {}

pose.headings = {
  north = {x = 0, z = -1, left = "west", right = "east"},
  east = {x = 1, z = 0, left = "north", right = "south"},
  south = {x = 0, z = 1, left = "east", right = "west"},
  west = {x = -1, z = 0, left = "south", right = "north"}
}

local function integer(value)
  return type(value) == "number" and value == math.floor(value)
end

function pose.validate(value)
  if type(value) ~= "table" then return nil, "pose must be a table" end
  if type(value.trusted) ~= "boolean" then return nil, "pose trust must be boolean" end
  if not pose.headings[value.heading] then return nil, "invalid heading" end
  if not integer(value.x) or not integer(value.y) or not integer(value.z) then
    return nil, "pose coordinates must be integers"
  end
  if value.reason ~= nil and type(value.reason) ~= "string" then
    return nil, "pose reason must be a string"
  end
  return true
end

function pose.new(x, y, z, heading)
  local value = {
    trusted = true,
    x = x or 0,
    y = y or 0,
    z = z or 0,
    heading = heading or "north",
    reason = ""
  }
  local ok, reason = pose.validate(value)
  if not ok then error(reason, 2) end
  return value
end

function pose.copy(value)
  return {
    trusted = value.trusted,
    x = value.x,
    y = value.y,
    z = value.z,
    heading = value.heading,
    reason = value.reason or ""
  }
end

function pose.unknown(value, reason)
  local result = pose.copy(value or pose.new())
  result.trusted = false
  result.reason = reason or "unknown"
  return result
end

function pose.equal(left, right)
  return type(left) == "table"
    and type(right) == "table"
    and left.trusted == right.trusted
    and left.x == right.x
    and left.y == right.y
    and left.z == right.z
    and left.heading == right.heading
end

function pose.apply(value, operation)
  local ok, reason = pose.validate(value)
  if not ok then return nil, reason end
  if not value.trusted then return nil, "pose is untrusted" end

  local result = pose.copy(value)
  local heading = pose.headings[result.heading]

  if operation == "turn_left" then
    result.heading = heading.left
  elseif operation == "turn_right" then
    result.heading = heading.right
  elseif operation == "move_forward" then
    result.x = result.x + heading.x
    result.z = result.z + heading.z
  elseif operation == "move_backward" then
    result.x = result.x - heading.x
    result.z = result.z - heading.z
  elseif operation == "move_up" then
    result.y = result.y + 1
  elseif operation == "move_down" then
    result.y = result.y - 1
  else
    return nil, "operation does not change pose"
  end

  return result
end

function pose.afterResult(value, operation, succeeded)
  if not succeeded then return pose.copy(value) end
  return pose.apply(value, operation)
end

function pose.toFields(value)
  return {
    pose_trusted = value.trusted and "true" or "false",
    x = value.x,
    y = value.y,
    z = value.z,
    heading = value.heading,
    pose_reason = value.reason or ""
  }
end

return pose

