-- OpenComputers 1.12.x: remote robot agent.
-- Run this file on the robot: robotd.lua
local component = require("component")
local computer = require("computer")
local event = require("event")
local robot = require("robot")

local PORT = 4242
local modem = assert(component.modem, "Robot needs a wireless network card")
assert(modem.isWireless(), "Robot modem is not wireless")
assert(modem.open(PORT), "Cannot open modem port " .. PORT)

local actions = {
  f = robot.forward,
  b = robot.back,
  l = robot.turnLeft,
  r = robot.turnRight,
  u = robot.up,
  d = robot.down
}

print("Robot agent listening on port " .. PORT)

while true do
  local _, _, sender, port, _, command, count = event.pull("modem_message")
  if port == PORT and type(command) == "string" then
    local ok, detail = true, "OK"
    if command == "status" then
      detail = "READY"
    elseif actions[command] then
      count = tonumber(count) or 1
      if count < 1 or count > 8 or count ~= math.floor(count) then
        ok, detail = false, "Step count must be 1..8"
      else
        for i = 1, count do
          local success, reason = actions[command]()
          if not success then
            ok = false
            detail = "Step " .. i .. ": " .. tostring(reason or "blocked")
            break
          end
        end
      end
    else
      ok, detail = false, "Unknown command"
    end

    local energy = math.floor(computer.energy())
    local capacity = math.floor(computer.maxEnergy())
    modem.send(sender, PORT, "result", command, ok, detail, energy, capacity)
    print(command .. " -> " .. detail .. " [" .. energy .. "/" .. capacity .. "]")
  end
end
