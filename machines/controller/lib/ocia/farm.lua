local pose = require("ocia.pose")
local protocol = require("ocia.protocol")

local farm = {}
local headingOrder = {north = 1, east = 2, south = 3, west = 4}
local vectors = {
  north = {x = 0, z = 1}, east = {x = 1, z = 0},
  south = {x = 0, z = -1}, west = {x = -1, z = 0}
}

local function builder(slot)
  local value = {slot = slot, x = 0, z = -1, heading = "north", steps = {}}

  function value:add(operation, arguments, cell)
    self.steps[#self.steps + 1] = {
      operation = operation,
      arguments = arguments or {},
      cell = cell and {x = cell.x, z = cell.z} or nil,
      robot = {x = self.x, z = self.z, heading = self.heading}
    }
  end

  function value:turn(wanted)
    local difference = (headingOrder[wanted] - headingOrder[self.heading]) % 4
    if difference == 1 then self:add("turn_right")
    elseif difference == 2 then self:add("turn_right"); self:add("turn_right")
    elseif difference == 3 then self:add("turn_left") end
    self.heading = wanted
  end

  function value:forward(count)
    for _ = 1, count or 1 do
      self:add("move_forward")
      local vector = vectors[self.heading]
      self.x, self.z = self.x + vector.x, self.z + vector.z
    end
  end

  function value:target(cell)
    local vector = vectors[self.heading]
    assert(self.x + vector.x == cell.x and self.z + vector.z == cell.z,
      "farming target is not forward from the robot")
  end

  function value:farm(cell)
    self:target(cell)
    self:add("till_forward_down", nil, cell)
    self:add("plant_forward_down", {slot = self.slot}, cell)
  end

  function value:plant(cell)
    self:target(cell)
    self:add("plant_forward_down", {slot = self.slot}, cell)
  end

  return value
end

local function cell(x, z) return {x = x, z = z} end

local function singlePlan(slot, plantingOnly)
  local route = builder(slot)
  local target = cell(0, 0)
  if plantingOnly then route:plant(target) else route:farm(target) end
  return route, {target}
end

local function pairPlan(slot)
  local route = builder(slot)
  local cells = {cell(0, 0), cell(1, 0)}
  route:farm(cells[1])
  route:turn("east"); route:forward(); route:turn("north")
  route:farm(cells[2])
  return route, cells
end

local function patchPlan(slot)
  local route = builder(slot)
  local cells = {
    cell(0, 0), cell(1, 0), cell(2, 0),
    cell(0, 1), cell(1, 1), cell(2, 1),
    cell(0, 2), cell(1, 2), cell(2, 2)
  }

  -- Enter through the unplanted bottom-middle crop space, farm the otherwise
  -- inaccessible center, and exit before sealing that access cell.
  route:turn("east"); route:forward(); route:turn("north"); route:forward()
  route:farm(cells[5])
  route:turn("south"); route:forward(); route:turn("north")

  -- Complete the perimeter from the exterior ring. No later movement enters a
  -- target crop space, so every planted cell remains outside the robot path.
  route:farm(cells[2])
  route:turn("east"); route:forward(); route:turn("north"); route:farm(cells[3])
  route:turn("east"); route:forward(); route:turn("north"); route:forward(2)
  route:turn("west"); route:farm(cells[6])
  route:turn("north"); route:forward(); route:turn("west"); route:farm(cells[9])
  route:turn("north"); route:forward(); route:turn("west"); route:forward(2)
  route:turn("south"); route:farm(cells[8])
  route:turn("west"); route:forward(); route:turn("south"); route:farm(cells[7])
  route:turn("west"); route:forward(); route:turn("south"); route:forward(2)
  route:turn("east"); route:farm(cells[4])
  route:turn("south"); route:forward(); route:turn("east"); route:farm(cells[1])
  return route, cells
end

function farm.plan(stage, slot)
  stage = stage or "single"
  if stage ~= "single" and stage ~= "single-plant"
      and stage ~= "pair" and stage ~= "patch" then
    return nil, "stage must be single, single-plant, pair, or patch"
  end
  slot = tonumber(slot or 1)
  if not slot or slot ~= math.floor(slot) or slot < 1 or slot > 16 then
    return nil, "potato slot must be an integer from 1 through 16"
  end

  local route, cells
  if stage == "single" then route, cells = singlePlan(slot, false)
  elseif stage == "single-plant" then route, cells = singlePlan(slot, true)
  elseif stage == "pair" then route, cells = pairPlan(slot)
  else route, cells = patchPlan(slot) end

  local tillCount = stage == "single-plant" and 0 or #cells
  return {stage = stage, slot = slot, cells = cells, steps = route.steps,
    till_count = tillCount, plant_count = #cells,
    local_end = {x = route.x, z = route.z, heading = route.heading},
    assumptions = "prepared_clearance_and_exterior_access_required"}
end

function farm.poseFromStatus(status)
  if type(status) ~= "table" then return nil, "status payload is missing" end
  if status.mode ~= "ready" or status.pose_trusted ~= "true" then
    return nil, "Wheatley must be ready with a trusted pose"
  end
  if type(status.epoch) ~= "string" or status.epoch == "" then
    return nil, "status does not contain an execution epoch"
  end
  local highWater = tonumber(status.high_water)
  if not highWater or highWater < 0 or highWater ~= math.floor(highWater) then
    return nil, "status contains an invalid physical high water"
  end
  local current = {trusted = true, x = tonumber(status.x), y = tonumber(status.y),
    z = tonumber(status.z), heading = status.heading, reason = ""}
  local ok, reason = pose.validate(current)
  if not ok then return nil, "status contains an invalid pose: " .. tostring(reason) end
  return current, status.epoch, highWater
end

function farm.targetForCell(startPose, target)
  local forward = assert(pose.headings[startPose.heading])
  local right = assert(pose.headings[forward.right])
  return {x = startPose.x + forward.x * (target.z + 1) + right.x * target.x,
    y = startPose.y - 1,
    z = startPose.z + forward.z * (target.z + 1) + right.z * target.x}
end

function farm.expectedEnd(plan, startPose)
  local current = pose.copy(startPose)
  for _, step in ipairs(plan.steps) do
    local nextPose, reason = pose.apply(current, step.operation)
    if not nextPose then return nil, reason end
    current = nextPose
  end
  return current
end

local function payloadPose(payload)
  if type(payload) ~= "table" or payload.pose_trusted ~= "true" then return nil end
  local value = {trusted = true, x = tonumber(payload.x), y = tonumber(payload.y),
    z = tonumber(payload.z), heading = payload.heading, reason = ""}
  if not pose.validate(value) then return nil end
  return value
end

function farm.execute(plan, status, send, onResult)
  local current, epoch, highWater = farm.poseFromStatus(status)
  local report = {ok = false, attempted = 0, tilled = 0, planted = 0,
    records = {}, last_pose = current}
  if not current then report.reason = epoch; return report end
  if type(send) ~= "function" then report.reason = "send callback is required"; return report end

  for _, step in ipairs(plan.steps) do
    local requestId = assert(protocol.makePhysicalRequestId(epoch, highWater + 1))
    local expected, poseReason = pose.apply(current, step.operation)
    if not expected then report.reason = tostring(poseReason); return report end
    local response = send(step.operation, {request_id = requestId,
      deployment_id = "potato-" .. plan.stage, arguments = step.arguments})
    report.attempted = report.attempted + 1
    local record = {operation = step.operation, request_id = requestId, response = response}
    report.records[#report.records + 1] = record
    if onResult then onResult(record) end

    if type(response) ~= "table" or response.certainty ~= "succeeded" then
      report.reason = type(response) == "table"
        and (tostring(response.status or "request_failed") .. " / "
          .. tostring(response.code) .. ": " .. tostring(response.message))
        or "transport returned no response"
      report.uncertain = type(response) ~= "table" or response.certainty == "unknown"
      return report
    end

    local observed = payloadPose(response.payload)
    if not observed or not pose.equal(observed, expected) then
      report.reason = "reply pose contradicts the planned transition"
      report.uncertain = true
      return report
    end
    if (step.operation == "plant_down" or step.operation == "plant_forward_down")
        and response.payload.item_consumed ~= "true" then
      report.reason = "planting call did not verify consumption of exactly one selected item"
      report.uncertain = true
      return report
    end

    highWater, current = highWater + 1, expected
    report.last_pose = current
    if step.operation == "till_forward_down" then report.tilled = report.tilled + 1 end
    if step.operation == "plant_forward_down" then report.planted = report.planted + 1 end
  end
  report.ok = true
  return report
end

return farm
