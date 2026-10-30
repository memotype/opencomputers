-- Local recovery tool. Stop robotd.lua before changing its durable state.
local configModule = require("ocia.config")
local pose = require("ocia.pose")
local state = require("ocia.state")

local command = (...)
local config, configReason = configModule.load("/etc/ocia.cfg", "robot")
if not config then
  io.stderr:write("Configuration error: " .. tostring(configReason) .. "\n")
  os.exit(2)
end

local store = state.fileStore(config.state_path)
local snapshot, loadReason = store.load()

if command == "show" or command == nil then
  if not snapshot then
    io.stderr:write("State cannot be loaded: " .. tostring(loadReason) .. "\n")
    os.exit(1)
  end
  print("Mode: " .. snapshot.mode)
  print(string.format("Pose trusted: %s; (%d, %d, %d) facing %s",
    tostring(snapshot.pose.trusted), snapshot.pose.x, snapshot.pose.y,
    snapshot.pose.z, snapshot.pose.heading))
  print("Reason: " .. tostring(snapshot.pose.reason))
  print("Last error: " .. tostring(snapshot.last_error))
  if snapshot.in_flight then
    print("In flight: " .. snapshot.in_flight.request_id .. " / "
      .. snapshot.in_flight.operation .. " / " .. snapshot.in_flight.phase)
  end
  print("Cached results: " .. #snapshot.completed)
  os.exit(0)
end

if command ~= "reset-origin" then
  io.stderr:write("Usage: ocia-recover [show|reset-origin]\n")
  os.exit(2)
end

print("STOP robotd.lua before continuing.")
print("Place Wheatley at the configured charging origin facing North.")
io.write("Type RESET to trust pose (0,0,0) North: ")
if io.read() ~= "RESET" then
  print("Cancelled")
  os.exit(1)
end

if not snapshot then
  print("Persisted state is invalid; a new state will be created explicitly.")
  snapshot = state.default()
end

snapshot.mode = "ready"
snapshot.pose = pose.new(0, 0, 0, "north")
snapshot.in_flight = nil
snapshot.last_error = ""

local saved, saveReason = store.save(snapshot)
if not saved then
  io.stderr:write("Recovery state could not be saved: " .. tostring(saveReason) .. "\n")
  os.exit(1)
end

print("Origin trusted. Restart robotd.lua before autonomous commands.")
