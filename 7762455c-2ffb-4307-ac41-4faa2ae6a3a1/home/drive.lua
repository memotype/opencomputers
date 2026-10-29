-- OpenComputers 1.12.x: run this on the stationary controller.
-- Commands: f, b, l, r, u, d; optionally a step count, e.g. f 3.
local component = require("component")
local computer = require("computer")
local event = require("event")

local PORT = 4242
local modem = assert(component.modem, "Controller needs a wireless network card")
assert(modem.isWireless(), "Controller modem is not wireless")
if not modem.isOpen(PORT) then
    assert(modem.open(PORT), "Cannot open modem port " .. PORT)
end

local valid = { f=true, b=true, l=true, r=true, u=true, d=true, status=true }
print("Remote robot drive: f/b/l/r/u/d, status, q")
print("Example: f 3 (three blocks forward), then l, then f 3")

while true do
  io.write("drive> ")
  local line = io.read()
  if not line or line == "q" or line == "quit" then
    modem.close(PORT)
    break
  end

  local command, countText = line:match("^%s*(%a+)%s*(%d*)%s*$")
  if not command or not valid[command] then
    print("Unknown command. Try f, b, l, r, u, d, status, or q.")
  else
    local count = tonumber(countText) or 1
    if count < 1 or count > 8 then
      print("Step count must be 1..8")
    else
      modem.broadcast(PORT, command, count)
      local deadline = computer.uptime() + 20
      local received = false
      repeat
        local timeLeft = deadline - computer.uptime()
        if timeLeft <= 0 then break end
        local _, _, sender, port, _, tag, reply, ok, detail, energy, capacity =
          event.pull(timeLeft, "modem_message")
        if port == PORT and tag == "result" and reply == command then
          print((ok and "OK" or "FAILED") .. ": " .. tostring(detail))
          print("Robot battery: " .. tostring(energy) .. "/" .. tostring(capacity))
          received = true
        end
      until received
      if not received then print("No reply: check robot agent and radio range") end
    end
  end
end
print("Driver stopped")
