-- Milestone 1 controller probe. Defaults to a read-only status request.
local component = require("component")
local computer = require("computer")
local event = require("event")
local uuid = require("uuid")

local configModule = require("ocia.config")
local protocol = require("ocia.protocol")
local transportModule = require("ocia.transport")

local aliases = {
  status = "status",
  left = "turn_left",
  right = "turn_right",
  forward = "move_forward",
  back = "move_backward",
  up = "move_up",
  down = "move_down"
}

local arguments = {...}
local command = "status"
local requestId
local deploymentId
local index = 1

if arguments[index] and arguments[index]:sub(1, 2) ~= "--" then
  command = arguments[index]
  index = index + 1
end

while index <= #arguments do
  local option = arguments[index]
  if option == "--id" and arguments[index + 1] then
    requestId = arguments[index + 1]
    index = index + 2
  elseif option == "--deployment" and arguments[index + 1] then
    deploymentId = arguments[index + 1]
    index = index + 2
  else
    io.stderr:write("Unknown or incomplete option: " .. tostring(option) .. "\n")
    os.exit(2)
  end
end

local operation = aliases[command]
if not operation then
  io.stderr:write("Usage: ociactl [status|left|right|forward|back|up|down] [--id ID] [--deployment ID]\n")
  os.exit(2)
end

local config, configReason = configModule.load("/etc/ocia.cfg", "controller")
if not config then
  io.stderr:write("Configuration error: " .. tostring(configReason) .. "\n")
  io.stderr:write("Copy /etc/ocia.cfg.example to /etc/ocia.cfg and set both modem addresses.\n")
  os.exit(2)
end

local modem = assert(component.modem, "Controller needs a wireless network card")
assert(modem.isWireless(), "Controller modem is not wireless")
if modem.address ~= config.controller_address then
  io.stderr:write("Configured controller address does not match this modem.\n")
  io.stderr:write("Actual: " .. tostring(modem.address) .. "\n")
  os.exit(2)
end

local openedHere = false
if not modem.isOpen(config.port) then
  assert(modem.open(config.port), "Cannot open modem port " .. config.port)
  openedHere = true
end

local client = transportModule.new({
  modem = modem,
  event = event,
  computer = computer,
  config = config,
  request_id = uuid.next
})

if protocol.isPhysical(operation) and not requestId then
  local status = client:sendRequest("status")
  if status.certainty ~= "succeeded" or not status.payload
      or status.payload.pose_trusted ~= "true" or status.payload.mode ~= "ready"
      or not status.payload.epoch or status.payload.epoch == "" then
    if openedHere then modem.close(config.port) end
    io.stderr:write("Cannot allocate a physical request: Wheatley is not commissioned and ready.\n")
    os.exit(1)
  end
  local nextSequence = tonumber(status.payload.high_water)
  if not nextSequence then
    if openedHere then modem.close(config.port) end
    io.stderr:write("Cannot allocate a physical request: invalid high-water status.\n")
    os.exit(1)
  end
  requestId = assert(protocol.makePhysicalRequestId(status.payload.epoch, nextSequence + 1))
end

if requestId then print("Sending request: " .. requestId) end
local response = client:sendRequest(operation, {
  request_id = requestId,
  deployment_id = deploymentId
})

if openedHere then modem.close(config.port) end

print("Request: " .. tostring(response.request and response.request.request_id or requestId or "not sent"))
print("Certainty: " .. tostring(response.certainty))
print("Status: " .. tostring(response.status))
print("Code: " .. tostring(response.code))
print("Message: " .. tostring(response.message))

if response.payload then
  if response.payload.mode then print("Robot mode: " .. response.payload.mode) end
  if response.payload.in_flight_request then
    print("In flight: " .. response.payload.in_flight_request .. " / "
      .. tostring(response.payload.in_flight_operation) .. " / "
      .. tostring(response.payload.in_flight_phase))
  elseif response.payload.last_request then
    print("Last retained request: " .. response.payload.last_request .. " / "
      .. tostring(response.payload.last_operation) .. " / "
      .. tostring(response.payload.last_outcome))
  end
  if response.payload.pose_trusted then
    print(string.format("Pose trusted: %s; (%s, %s, %s) facing %s",
      response.payload.pose_trusted,
      tostring(response.payload.x),
      tostring(response.payload.y),
      tostring(response.payload.z),
      tostring(response.payload.heading)))
  end
  if response.payload.energy then
    print("Energy: " .. tostring(response.payload.energy) .. "/" .. tostring(response.payload.capacity))
  end
  if response.payload.total_memory then
    print("Memory free/total: " .. tostring(response.payload.free_memory)
      .. "/" .. tostring(response.payload.total_memory))
  end
  if response.payload.epoch then
    print("Epoch/high water: " .. tostring(response.payload.epoch)
      .. "/" .. tostring(response.payload.high_water))
  end
  if response.payload.journal_health then
    print("Journal: " .. tostring(response.payload.journal_health)
      .. "; generation " .. tostring(response.payload.journal_generation)
      .. "; records " .. tostring(response.payload.journal_records)
      .. "; bytes " .. tostring(response.payload.journal_bytes)
      .. "; last write " .. tostring(response.payload.last_persist_ms) .. " ms")
    print("Retained physical results: " .. tostring(response.payload.retained_results))
  end
  if response.payload.duplicate == "true" then print("Duplicate request: cached result returned") end
end

if response.certainty == "unknown" then
  if protocol.isPhysical(operation) then
    io.stderr:write("Physical outcome may be unknown. Do not retry movement with a new ID until reconciled.\n")
  else
    io.stderr:write("Request outcome is unknown because no conclusive reply was received.\n")
  end
  os.exit(1)
elseif response.certainty == "failed" then
  os.exit(1)
end
