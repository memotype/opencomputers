local legacy = {}

legacy.commands = {
  f = {operation = "move_forward", physical = true},
  b = {operation = "move_backward", physical = true},
  l = {operation = "turn_left", physical = true},
  r = {operation = "turn_right", physical = true},
  u = {operation = "move_up", physical = true},
  d = {operation = "move_down", physical = true},
  status = {operation = "status", physical = false}
}

function legacy.parse(command, count)
  if type(command) ~= "string" then return nil, "command must be a string" end
  local definition = legacy.commands[command]
  if not definition then return nil, "unknown command" end

  count = tonumber(count) or 1
  if count ~= math.floor(count) or count < 1 or count > 8 then
    return nil, "step count must be 1..8"
  end
  if command == "status" then count = 1 end

  return {
    command = command,
    operation = definition.operation,
    physical = definition.physical,
    count = count
  }
end

return legacy

