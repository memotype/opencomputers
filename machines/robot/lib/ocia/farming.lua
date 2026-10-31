local farming = {}

function farming.new(robot, sides, inventoryController)
  assert(type(robot) == "table", "robot API is required")
  assert(type(sides) == "table" and sides.down ~= nil, "sides API is required")

  return {
    till_down = function()
      local ok, detail = robot.useDown()
      return ok, detail or (ok and "tool used downward"
        or "robot.useDown returned failure without a reason"), {
        interaction = tostring(detail or ""),
        world_verification = "operator_required"
      }
    end,

    till_forward_down = function()
      local ok, detail = robot.use(sides.down)
      return ok, detail or (ok and "tool used forward and downward"
        or "robot.use returned failure without a reason"), {
        interaction = tostring(detail or ""),
        interaction_geometry = "forward_down",
        world_verification = "operator_required"
      }
    end,

    plant_down = function(arguments)
      local slot = tonumber(arguments and arguments.slot)
      if not slot then return false, "plant slot is missing" end
      robot.select(slot)
      local before = robot.count(slot)
      if before < 1 then
        return false, "selected planting slot is empty", {
          selected_slot = slot, items_before = before, items_after = before,
          item_consumed = "false"
        }
      end
      local ok, detail = robot.placeDown()
      local after = robot.count(slot)
      return ok, detail or (ok and "selected item placed downward"
        or "robot.placeDown returned failure without a reason"), {
        selected_slot = slot,
        items_before = before,
        items_after = after,
        item_consumed = after == before - 1 and "true" or "false",
        world_verification = "operator_required"
      }
    end,

    plant_forward_down = function(arguments)
      local slot = tonumber(arguments and arguments.slot)
      if not slot then return false, "plant slot is missing" end
      robot.select(slot)
      local before = robot.count(slot)
      if before < 1 then
        return false, "selected planting slot is empty", {
          selected_slot = slot, items_before = before, items_after = before,
          item_consumed = "false"
        }
      end
      if not inventoryController then
        return false, "inventory controller is unavailable for Potato identity verification"
      end
      local stack = inventoryController.getStackInInternalSlot(slot)
      if type(stack) ~= "table" or stack.name ~= "minecraft:potato" then
        return false, "selected planting slot does not contain minecraft:potato", {
          selected_slot = slot,
          items_before = before,
          items_after = before,
          item_name = type(stack) == "table" and tostring(stack.name or "") or "",
          item_consumed = "false"
        }
      end
      local ok, detail = robot.place(sides.down)
      local after = robot.count(slot)
      return ok, detail or (ok and "selected item placed forward and downward"
        or "robot.place returned failure without a reason"), {
        selected_slot = slot,
        items_before = before,
        items_after = after,
        item_name = stack.name,
        item_consumed = after == before - 1 and "true" or "false",
        interaction_geometry = "forward_down",
        world_verification = "operator_required"
      }
    end
  }
end

return farming
