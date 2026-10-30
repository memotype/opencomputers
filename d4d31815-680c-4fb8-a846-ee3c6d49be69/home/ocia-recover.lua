-- Local recovery tool. Stop robotd.lua before changing its durable state.
local configModule = require("ocia.config")
local pose = require("ocia.pose")
local state = require("ocia.state")
local uuid = require("uuid")

local command = (...)
local config, configReason = configModule.load("/etc/ocia.cfg", "robot")
if not config then
  io.stderr:write("Configuration error: " .. tostring(configReason) .. "\n")
  os.exit(2)
end

local store = state.journalStore(config.state_path, {
  recent_limit = config.recent_results
})
local snapshot, loadReason = store.load()

if command == "show" or command == nil then
  print("Mode: " .. snapshot.mode)
  print(string.format("Pose trusted: %s; (%d, %d, %d) facing %s",
    tostring(snapshot.pose.trusted), snapshot.pose.x, snapshot.pose.y,
    snapshot.pose.z, snapshot.pose.heading))
  print("Reason: " .. tostring(snapshot.pose.reason))
  print("Last error: " .. tostring(snapshot.last_error))
  print("Epoch: " .. tostring(snapshot.epoch))
  print("High water: " .. tostring(snapshot.high_water))
  print("Retained results: " .. #snapshot.recent)
  print("Journal health: " .. snapshot.journal.health)
  print("Journal generation: " .. snapshot.journal.generation)
  print("Journal records/bytes: " .. snapshot.journal.records .. "/" .. snapshot.journal.bytes)
  if snapshot.in_flight then
    print("In flight: " .. snapshot.in_flight.request_id .. " / "
      .. snapshot.in_flight.operation .. " / " .. snapshot.in_flight.phase)
  end
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

local epoch = uuid.next()
local commissioned, saveReason = store.commission(epoch, pose.new(0, 0, 0, "north"))
if not commissioned then
  io.stderr:write("Recovery state could not be saved: " .. tostring(saveReason) .. "\n")
  os.exit(1)
end

print("Origin trusted under new execution epoch: " .. epoch)
print("Old-epoch physical requests are now permanently stale.")
print("Restart robotd.lua before autonomous commands.")
