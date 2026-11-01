local cases = {}

function cases.register(harness)
  local test = assert(harness.test)
  local equal = assert(harness.equal)
  local truthy = assert(harness.truthy)
  local contains = assert(harness.contains)

  local nav = require("ocia.nav")
  local pose = require("ocia.pose")

  local navigationActions = {
    "move_forward", "move_backward", "move_up", "move_down",
    "turn_left", "turn_right"
  }

  local function actionsText(operations)
    return table.concat(operations, ",")
  end

  local function simulate(start, operations)
    local current = pose.copy(start)
    for _, operation in ipairs(operations) do
      current = assert(pose.apply(current, operation))
    end
    return current
  end

  local function poseKey(value)
    return table.concat({value.x, value.y, value.z, value.heading}, ":")
  end

  -- Independent bounded breadth-first oracle. This deliberately does not use
  -- nav's axis or heading candidate enumeration.
  local function minimumCost(start, destination)
    local minimumX = math.min(start.x, destination.x) - 1
    local maximumX = math.max(start.x, destination.x) + 1
    local minimumY = math.min(start.y, destination.y) - 1
    local maximumY = math.max(start.y, destination.y) + 1
    local minimumZ = math.min(start.z, destination.z) - 1
    local maximumZ = math.max(start.z, destination.z) + 1
    local queue, first = {{value = pose.copy(start), cost = 0}}, 1
    local visited = {[poseKey(start)] = true}

    while first <= #queue do
      local item = queue[first]
      first = first + 1
      local value = item.value
      if value.x == destination.x and value.y == destination.y
          and value.z == destination.z
          and (not destination.heading or value.heading == destination.heading) then
        return item.cost
      end
      for _, operation in ipairs(navigationActions) do
        local nextPose = assert(pose.apply(value, operation))
        if nextPose.x >= minimumX and nextPose.x <= maximumX
            and nextPose.y >= minimumY and nextPose.y <= maximumY
            and nextPose.z >= minimumZ and nextPose.z <= maximumZ then
          local key = poseKey(nextPose)
          if not visited[key] then
            visited[key] = true
            queue[#queue + 1] = {value = nextPose, cost = item.cost + 1}
          end
        end
      end
    end
    return nil
  end

  local function assertPlanCounts(plan, movements, turns, cost)
    equal(plan.movement_count, movements)
    equal(plan.turn_count, turns)
    equal(plan.cost, cost)
    equal(#plan.operations, cost)
    equal(plan.inverse_cost, cost)
  end

  test("navigation planner handles straight axes from arbitrary poses", function()
    local start = pose.new(5, 3, -7, "north")

    local north = assert(nav.plan(start, {x = 5, y = 3, z = -10}))
    equal(actionsText(north.operations), "move_forward,move_forward,move_forward")
    assertPlanCounts(north, 3, 0, 3)
    truthy(pose.equal(north.expected_end, pose.new(5, 3, -10, "north")))
    equal(north.version, 1)
    equal(north.max_distance, 32)
    equal(north.terrain_model, "unobstructed")
    equal(north.traversability, "unknown")
    equal(north.operation_order,
      "turn_left,turn_right,move_forward,move_backward,move_up,move_down")

    local south = assert(nav.plan(start, {x = 5, y = 3, z = -4}))
    equal(actionsText(south.operations), "move_backward,move_backward,move_backward")
    assertPlanCounts(south, 3, 0, 3)

    local east = assert(nav.plan(start, {x = 8, y = 3, z = -7}))
    equal(actionsText(east.operations),
      "turn_left,move_backward,move_backward,move_backward")
    assertPlanCounts(east, 3, 1, 4)
    truthy(pose.equal(east.expected_end, pose.new(8, 3, -7, "west")))

    local vertical = assert(nav.plan(pose.new(-4, -2, 9, "east"),
      {x = -4, y = 1, z = 9}))
    equal(actionsText(vertical.operations), "move_up,move_up,move_up")
    assertPlanCounts(vertical, 3, 0, 3)
    truthy(pose.equal(vertical.expected_end, pose.new(-4, 1, 9, "east")))
  end)

  test("navigation planner exploits backward travel", function()
    local north = pose.new(0, 0, 0, "north")
    local behind = assert(nav.plan(north, {x = 0, y = 0, z = 4}))
    equal(actionsText(behind.operations),
      "move_backward,move_backward,move_backward,move_backward")
    assertPlanCounts(behind, 4, 0, 4)

    local west = assert(nav.plan(pose.new(7, 1, 2, "west"),
      {x = 10, y = 1, z = 2}))
    equal(actionsText(west.operations), "move_backward,move_backward,move_backward")
    assertPlanCounts(west, 3, 0, 3)
  end)

  test("navigation planner chooses deterministic diagonal segment order", function()
    local plan = assert(nav.plan(pose.new(0, 0, 0, "north"),
      {x = 1, y = 0, z = -2}))
    equal(actionsText(plan.operations),
      "move_forward,move_forward,turn_left,move_backward")
    assertPlanCounts(plan, 3, 1, 4)
    truthy(pose.equal(plan.expected_end, pose.new(1, 0, -2, "west")))

    local repeated = assert(nav.plan(pose.new(0, 0, 0, "north"),
      {x = 1, y = 0, z = -2}))
    equal(actionsText(repeated.operations), actionsText(plan.operations))
  end)

  test("navigation planner honors optional destination headings", function()
    local start = pose.new(2, 4, 6, "north")
    local east = assert(nav.plan(start, {x = 3, y = 4, z = 6, heading = "east"}))
    equal(actionsText(east.operations), "turn_right,move_forward")
    assertPlanCounts(east, 1, 1, 2)
    equal(east.expected_end.heading, "east")
    equal(east.destination.heading, "east")

    local same = assert(nav.plan(start, {x = 2, y = 4, z = 6}))
    equal(#same.operations, 0)
    assertPlanCounts(same, 0, 0, 0)
    equal(same.expected_end.heading, "north")

    local turn = assert(nav.plan(start, {x = 2, y = 4, z = 6, heading = "south"}))
    equal(actionsText(turn.operations), "turn_left,turn_left")
    assertPlanCounts(turn, 0, 2, 2)
    equal(turn.expected_end.heading, "south")
  end)

  test("navigation planner places one direct vertical run deterministically", function()
    local plan = assert(nav.plan(pose.new(-3, 5, 8, "south"),
      {x = -1, y = 3, z = 10, heading = "north"}))
    local text = actionsText(plan.operations)
    contains(text, "move_down,move_down")
    equal(plan.operations[#plan.operations - 1], "move_down")
    equal(plan.operations[#plan.operations], "move_down")
    equal(plan.temporary_elevation_changes, 0)
    equal(plan.vertical_policy, "single_direct_run_after_horizontal_segments")
    truthy(pose.equal(plan.expected_end, pose.new(-1, 3, 10, "north")))
  end)

  test("navigation inverse returns to arbitrary starting pose", function()
    local start = pose.new(11, -2, -9, "east")
    local plan = assert(nav.plan(start, {x = 8, y = 1, z = -5, heading = "west"}))
    local inverse = assert(nav.inverse(plan.operations))
    equal(#inverse, plan.inverse_cost)
    truthy(pose.equal(simulate(plan.expected_end, inverse), start))
    equal(nav.inverse({"move_forward", "dance"}), nil)
    equal(nav.inverse("move_forward"), nil)
  end)

  test("navigation plans cover signed and zero coordinate components", function()
    local fixtures = {
      {pose.new(-8, -3, 0, "south"), {x = 0, y = -3, z = 0}},
      {pose.new(0, 0, 0, "west"), {x = -4, y = 0, z = 5}},
      {pose.new(3, 2, -6, "east"), {x = 3, y = -2, z = 0}},
      {pose.new(-1, 0, 1, "north"), {x = 0, y = 0, z = 0}}
    }
    for _, fixture in ipairs(fixtures) do
      local plan = assert(nav.plan(fixture[1], fixture[2]))
      equal(plan.expected_end.x, fixture[2].x)
      equal(plan.expected_end.y, fixture[2].y)
      equal(plan.expected_end.z, fixture[2].z)
      equal(plan.distance, math.abs(fixture[2].x - fixture[1].x)
        + math.abs(fixture[2].y - fixture[1].y)
        + math.abs(fixture[2].z - fixture[1].z))
    end
  end)

  test("navigation planner rejects malformed and out-of-limit inputs", function()
    local valid = pose.new()
    local _, reason = nav.plan(nil, {x = 0, y = 0, z = 0})
    contains(reason, "starting pose")
    _, reason = nav.plan(pose.unknown(valid, "test"), {x = 0, y = 0, z = 0})
    contains(reason, "trusted")
    _, reason = nav.plan({trusted = true, x = 0, y = 0, z = 0,
      heading = "up", reason = ""}, {x = 0, y = 0, z = 0})
    contains(reason, "heading")
    _, reason = nav.plan({trusted = true, x = math.huge, y = 0, z = 0,
      heading = "north", reason = ""}, {x = 0, y = 0, z = 0})
    contains(reason, "finite")
    _, reason = nav.plan(valid, nil)
    contains(reason, "destination")
    _, reason = nav.plan(valid, {x = 0.5, y = 0, z = 0})
    contains(reason, "finite")
    _, reason = nav.plan(valid, {x = 0 / 0, y = 0, z = 0})
    contains(reason, "finite")
    _, reason = nav.plan(valid, {x = 0, y = 0, z = 0, heading = "up"})
    contains(reason, "heading")
    _, reason = nav.plan(valid, {x = 0, y = 0, z = 0, extra = true})
    contains(reason, "unsupported")
    _, reason = nav.plan(valid, {x = 33, y = 0, z = 0})
    contains(reason, "max_distance")
    truthy(nav.plan(valid, {x = 33, y = 0, z = 0}, {max_distance = 33}))
    truthy(nav.plan(valid, {x = 0, y = 0, z = 0}, {max_distance = 0}))
    _, reason = nav.plan(valid, {x = 1, y = 0, z = 0}, {max_distance = 0})
    contains(reason, "max_distance")
    _, reason = nav.plan(valid, {x = 0, y = 0, z = 0}, {unknown = true})
    contains(reason, "unsupported")
    _, reason = nav.plan(valid, {x = 0, y = 0, z = 0}, {max_distance = -1})
    contains(reason, "max_distance")
    _, reason = nav.plan(valid, {x = 0, y = 0, z = 0}, {max_distance = 1.5})
    contains(reason, "max_distance")
    _, reason = nav.plan(valid, {x = 0, y = 0, z = 0}, "wide")
    contains(reason, "options")
  end)

  test("navigation planner does not mutate caller tables", function()
    local start = pose.new(4, 2, -5, "west")
    local destination = {x = -2, y = 3, z = 1, heading = "south"}
    local options = {max_distance = 20}
    local plan = assert(nav.plan(start, destination, options))
    equal(start.x, 4)
    equal(start.y, 2)
    equal(start.z, -5)
    equal(start.heading, "west")
    equal(destination.x, -2)
    equal(destination.heading, "south")
    equal(options.max_distance, 20)
    truthy(plan.start_pose ~= start)
    truthy(plan.destination ~= destination)
    plan.start_pose.x = 99
    plan.destination.x = 99
    equal(start.x, 4)
    equal(destination.x, -2)
  end)

  test("navigation planning is repeatable", function()
    local start = pose.new(-2, 3, 4, "south")
    local destination = {x = 3, y = 1, z = -1, heading = "east"}
    local first = assert(nav.plan(start, destination, {max_distance = 20}))
    local expected = actionsText(first.operations)
    for _ = 1, 50 do
      local nextPlan = assert(nav.plan(start, destination, {max_distance = 20}))
      equal(actionsText(nextPlan.operations), expected)
      equal(nextPlan.cost, first.cost)
      equal(nextPlan.expected_end.heading, first.expected_end.heading)
    end
  end)

  test("navigation planner matches an independent exhaustive oracle", function()
    local headings = {"north", "east", "south", "west"}
    local requiredHeadings = {false, "north", "east", "south", "west"}
    local startX, startY, startZ = 3, -2, 5
    for _, startHeading in ipairs(headings) do
      local start = pose.new(startX, startY, startZ, startHeading)
      for dx = -2, 2 do
        for dy = -1, 1 do
          for dz = -2, 2 do
            for _, required in ipairs(requiredHeadings) do
              local destination = {x = startX + dx, y = startY + dy, z = startZ + dz}
              if required then destination.heading = required end
              local plan = assert(nav.plan(start, destination))
              local oracleCost = minimumCost(start, destination)
              truthy(oracleCost, "oracle did not find a bounded route")
              equal(plan.cost, oracleCost, "planner cost disagrees with exhaustive oracle")
              truthy(pose.equal(simulate(start, plan.operations), plan.expected_end))
            end
          end
        end
      end
    end
  end)

  test("navigation module has a pure dependency boundary", function()
    local dependencies = {}
    local environment = {
      assert = assert,
      ipairs = ipairs,
      math = math,
      pairs = pairs,
      require = function(name)
        dependencies[#dependencies + 1] = name
        if name == "ocia.pose" then return pose end
        error("unexpected dependency " .. tostring(name))
      end,
      table = table,
      tostring = tostring,
      type = type
    }
    local chunk = assert(loadfile("machines/controller/lib/ocia/nav.lua", "t", environment))
    local isolated = chunk()
    local plan = assert(isolated.plan(pose.new(8, 1, -3, "west"),
      {x = 6, y = 1, z = -3}))
    equal(actionsText(plan.operations), "move_forward,move_forward")
    equal(#dependencies, 1)
    equal(dependencies[1], "ocia.pose")
    equal(environment.component, nil)
    equal(environment.filesystem, nil)
    equal(environment.io, nil)
    equal(environment.os, nil)
  end)
end

return cases
