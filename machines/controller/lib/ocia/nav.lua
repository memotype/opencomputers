local pose = require("ocia.pose")

local nav = {
  PLAN_VERSION = 1,
  DEFAULT_MAX_DISTANCE = 32
}

local MAX_SAFE_INTEGER = 9007199254740991
-- Equal candidates use this stable order after cost, turn count, and temporary
-- elevation changes. Horizontal order enumeration is X/Z then Z/X; a required
-- direct vertical run is emitted after horizontal segments.
local headingIndex = {north = 0, east = 1, south = 2, west = 3}
local opposite = {north = "south", east = "west", south = "north", west = "east"}
local inverseOperation = {
  move_forward = "move_backward",
  move_backward = "move_forward",
  move_up = "move_down",
  move_down = "move_up",
  turn_left = "turn_right",
  turn_right = "turn_left"
}
local operationRank = {
  turn_left = 1,
  turn_right = 2,
  move_forward = 3,
  move_backward = 4,
  move_up = 5,
  move_down = 6
}

local function integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
    and math.abs(value) <= MAX_SAFE_INTEGER
end

local function validateKeys(value, allowed, label)
  for key in pairs(value) do
    if not allowed[key] then return nil, label .. " contains unsupported field " .. tostring(key) end
  end
  return true
end

local function copyPose(value)
  return {
    trusted = value.trusted,
    x = value.x,
    y = value.y,
    z = value.z,
    heading = value.heading,
    reason = value.reason or ""
  }
end

local function validateStart(value)
  local ok, reason = pose.validate(value)
  if not ok then return nil, "invalid starting pose: " .. tostring(reason) end
  if not value.trusted then return nil, "starting pose must be trusted" end
  if not integer(value.x) or not integer(value.y) or not integer(value.z) then
    return nil, "starting pose coordinates must be finite safe integers"
  end
  return copyPose(value)
end

local function validateDestination(value)
  if type(value) ~= "table" then return nil, "destination must be a table" end
  local keysOk, keysReason = validateKeys(value,
    {x = true, y = true, z = true, heading = true}, "destination")
  if not keysOk then return nil, keysReason end
  if not integer(value.x) or not integer(value.y) or not integer(value.z) then
    return nil, "destination coordinates must be finite safe integers"
  end
  if value.heading ~= nil and not pose.headings[value.heading] then
    return nil, "destination heading is invalid"
  end
  local result = {x = value.x, y = value.y, z = value.z}
  if value.heading then result.heading = value.heading end
  return result
end

local function validateOptions(value)
  if value == nil then return {max_distance = nav.DEFAULT_MAX_DISTANCE} end
  if type(value) ~= "table" then return nil, "options must be a table" end
  local keysOk, keysReason = validateKeys(value, {max_distance = true}, "options")
  if not keysOk then return nil, keysReason end
  local maximum = value.max_distance
  if maximum == nil then maximum = nav.DEFAULT_MAX_DISTANCE end
  if not integer(maximum) or maximum < 0 then
    return nil, "max_distance must be a nonnegative finite safe integer"
  end
  return {max_distance = maximum}
end

local function appendOperation(candidate, operation)
  local nextPose, reason = pose.apply(candidate.current, operation)
  if not nextPose then return nil, reason end
  candidate.operations[#candidate.operations + 1] = operation
  candidate.current = nextPose
  if operation == "turn_left" or operation == "turn_right" then
    candidate.turn_count = candidate.turn_count + 1
  else
    candidate.movement_count = candidate.movement_count + 1
  end
  return true
end

local function appendTurns(candidate, wanted)
  local current = headingIndex[candidate.current.heading]
  local target = headingIndex[wanted]
  local difference = (target - current) % 4
  if difference == 1 then
    return appendOperation(candidate, "turn_right")
  elseif difference == 2 then
    local ok, reason = appendOperation(candidate, "turn_left")
    if not ok then return nil, reason end
    return appendOperation(candidate, "turn_left")
  elseif difference == 3 then
    return appendOperation(candidate, "turn_left")
  end
  return true
end

local function operationFor(direction, executionHeading)
  if executionHeading == direction then return "move_forward" end
  if executionHeading == opposite[direction] then return "move_backward" end
  return nil
end

local function appendSegment(candidate, segment, executionHeading)
  local ok, reason = appendTurns(candidate, executionHeading)
  if not ok then return nil, reason end
  local operation = assert(operationFor(segment.direction, executionHeading))
  for _ = 1, segment.length do
    ok, reason = appendOperation(candidate, operation)
    if not ok then return nil, reason end
  end
  return true
end

local function appendVertical(candidate, delta)
  if delta == 0 then return true end
  local operation = delta > 0 and "move_up" or "move_down"
  for _ = 1, math.abs(delta) do
    local ok, reason = appendOperation(candidate, operation)
    if not ok then return nil, reason end
  end
  return true
end

local function compareOperations(left, right)
  local count = math.min(#left, #right)
  for index = 1, count do
    local leftRank, rightRank = operationRank[left[index]], operationRank[right[index]]
    if leftRank ~= rightRank then return leftRank < rightRank end
  end
  return #left < #right
end

local function better(left, right)
  if not right then return true end
  if left.cost ~= right.cost then return left.cost < right.cost end
  if left.turn_count ~= right.turn_count then return left.turn_count < right.turn_count end
  if left.temporary_elevation_changes ~= right.temporary_elevation_changes then
    return left.temporary_elevation_changes < right.temporary_elevation_changes
  end
  return compareOperations(left.operations, right.operations)
end

local function segmentFor(axis, delta)
  if delta == 0 then return nil end
  if axis == "x" then
    return {axis = axis, length = math.abs(delta), direction = delta > 0 and "east" or "west"}
  end
  return {axis = axis, length = math.abs(delta), direction = delta > 0 and "south" or "north"}
end

local function axisOrders(xSegment, zSegment)
  if xSegment and zSegment then return {{xSegment, zSegment}, {zSegment, xSegment}} end
  if xSegment then return {{xSegment}} end
  if zSegment then return {{zSegment}} end
  return {{}}
end

local function evaluateHeadings(order, index, selected, callback)
  if index > #order then callback(selected); return end
  local direction = order[index].direction
  selected[index] = direction
  evaluateHeadings(order, index + 1, selected, callback)
  selected[index] = opposite[direction]
  evaluateHeadings(order, index + 1, selected, callback)
  selected[index] = nil
end

local function buildCandidate(startPose, destination, order, headings)
  local candidate = {
    current = copyPose(startPose),
    operations = {},
    movement_count = 0,
    turn_count = 0,
    temporary_elevation_changes = 0
  }
  for index, segment in ipairs(order) do
    local ok, reason = appendSegment(candidate, segment, headings[index])
    if not ok then return nil, reason end
  end
  local ok, reason = appendVertical(candidate, destination.y - startPose.y)
  if not ok then return nil, reason end
  if destination.heading then
    ok, reason = appendTurns(candidate, destination.heading)
    if not ok then return nil, reason end
  end
  candidate.cost = #candidate.operations
  return candidate
end

function nav.inverse(operations)
  if type(operations) ~= "table" then return nil, "operations must be a table" end
  local result = {}
  for index = #operations, 1, -1 do
    local inverse = inverseOperation[operations[index]]
    if not inverse then
      return nil, "unsupported navigation operation at index " .. tostring(index)
    end
    result[#result + 1] = inverse
  end
  return result
end

function nav.plan(startPose, destination, options)
  local start, startReason = validateStart(startPose)
  if not start then return nil, startReason end
  local target, targetReason = validateDestination(destination)
  if not target then return nil, targetReason end
  local settings, settingsReason = validateOptions(options)
  if not settings then return nil, settingsReason end

  local dx, dy, dz = target.x - start.x, target.y - start.y, target.z - start.z
  local distance = math.abs(dx) + math.abs(dy) + math.abs(dz)
  if distance > settings.max_distance then
    return nil, "destination Manhattan distance exceeds max_distance"
  end

  local xSegment, zSegment = segmentFor("x", dx), segmentFor("z", dz)
  local best, buildReason
  for _, order in ipairs(axisOrders(xSegment, zSegment)) do
    evaluateHeadings(order, 1, {}, function(headings)
      local candidate, reason = buildCandidate(start, target, order, headings)
      if not candidate then buildReason = reason
      elseif better(candidate, best) then best = candidate end
    end)
  end
  if not best then return nil, buildReason or "no nominal route candidate" end

  if best.current.x ~= target.x or best.current.y ~= target.y
      or best.current.z ~= target.z
      or (target.heading and best.current.heading ~= target.heading) then
    return nil, "internal route simulation did not reach the destination"
  end

  return {
    version = nav.PLAN_VERSION,
    start_pose = copyPose(start),
    destination = target,
    operations = best.operations,
    movement_count = best.movement_count,
    turn_count = best.turn_count,
    cost = best.cost,
    expected_end = copyPose(best.current),
    inverse_cost = best.cost,
    distance = distance,
    max_distance = settings.max_distance,
    temporary_elevation_changes = best.temporary_elevation_changes,
    terrain_model = "unobstructed",
    traversability = "unknown",
    tie_breaker = "cost,turns,temporary_elevation_changes,operation_order",
    operation_order = "turn_left,turn_right,move_forward,move_backward,move_up,move_down",
    vertical_policy = "single_direct_run_after_horizontal_segments"
  }
end

return nav
