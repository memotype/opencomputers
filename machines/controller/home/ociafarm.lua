-- Supervised Potato-patch vertical slice for OpenComputers 1.8.8 / Lua 5.3.
local component = require("component")
local computer = require("computer")
local event = require("event")
local uuid = require("uuid")

local configModule = require("ocia.config")
local farm = require("ocia.farm")
local transportModule = require("ocia.transport")

local function usage()
  io.stderr:write("Usage: ociafarm <plan|apply> <single|single-plant|pair|patch> [--slot 1-16]\n")
end

local arguments = {...}
local mode, stage, slot = arguments[1], arguments[2], 1
if mode ~= "plan" and mode ~= "apply" then usage(); os.exit(2) end
if not stage then usage(); os.exit(2) end
local index = 3
while index <= #arguments do
  if arguments[index] == "--slot" and arguments[index + 1] then
    slot = tonumber(arguments[index + 1])
    index = index + 2
  else
    io.stderr:write("Unknown or incomplete option: " .. tostring(arguments[index]) .. "\n")
    usage()
    os.exit(2)
  end
end

local plan, planReason = farm.plan(stage, slot)
if not plan then io.stderr:write(planReason .. "\n"); usage(); os.exit(2) end

local config, configReason = configModule.load("/etc/ocia.cfg", "controller")
if not config then io.stderr:write("Configuration error: " .. tostring(configReason) .. "\n"); os.exit(2) end
local modem = assert(component.modem, "Controller needs a wireless network card")
assert(modem.isWireless(), "Controller modem is not wireless")
assert(modem.address == config.controller_address,
  "Configured controller address does not match this modem")

local openedHere = false
if not modem.isOpen(config.port) then
  assert(modem.open(config.port), "Cannot open modem port " .. config.port)
  openedHere = true
end
local client = transportModule.new({
  modem = modem, event = event, computer = computer, config = config,
  request_id = uuid.next
})

local function closePort() if openedHere then modem.close(config.port) end end
local function poseText(value)
  return string.format("(%d,%d,%d) %s", value.x, value.y, value.z, value.heading)
end

local function run()
  local statusResponse = client:sendRequest("status")
  if statusResponse.certainty ~= "succeeded" then
    return nil, "Cannot read ready status: " .. tostring(statusResponse.code)
      .. ": " .. tostring(statusResponse.message)
  end
  local startPose, statusReason = farm.poseFromStatus(statusResponse.payload)
  if not startPose then return nil, statusReason end
  local endPose, endReason = farm.expectedEnd(plan, startPose)
  if not endPose then return nil, endReason end

  print("Potato prototype: " .. plan.stage)
  print("Start: " .. poseText(startPose))
  print("Expected end: " .. poseText(endPose))
  local summary = string.format("Cells: %d; till actions: %d; plant actions: %d",
    #plan.cells, plan.till_count, plan.plant_count)
  if plan.plant_count > 0 then summary = summary .. "; potato slot: " .. plan.slot end
  print(summary)
  print("Total physical commands: " .. #plan.steps)
  print("Geometry: each cell is tilled and planted forward/downward from one adjacent pose.")
  print("Target soil cells relative to the live start pose:")
  for number, cell in ipairs(plan.cells) do
    local target = farm.targetForCell(startPose, cell)
    print(string.format("  %d: (%d,%d,%d)", number, target.x, target.y, target.z))
  end
  print("Physical request plan:")
  for number, step in ipairs(plan.steps) do
    local cell = step.cell and string.format(" cell(%d,%d)", step.cell.x, step.cell.z) or ""
    local planting = step.operation == "plant_down"
      or step.operation == "plant_forward_down"
    local selected = planting and " slot=" .. plan.slot or ""
    print(string.format("%2d  %-13s%s%s", number, step.operation, cell, selected))
  end
  if mode == "plan" then
    print("Plan only: no physical request was sent.")
    return true
  end

  io.write("Type FARM to execute this supervised stage: ")
  if io.read() ~= "FARM" then return nil, "Confirmation did not match; nothing executed." end
  local report = farm.execute(plan, statusResponse.payload,
    function(operation, options) return client:sendRequest(operation, options) end,
    function(record)
      local response = record.response or {}
      print(string.format("%s  %s  %s / %s / %s: %s",
        record.request_id, record.operation,
        tostring(response.certainty), tostring(response.status),
        tostring(response.code), tostring(response.message)))
    end)
  print(string.format("Result: %s; attempted %d/%d; tilled %d/%d; planted %d/%d",
    report.ok and "complete" or "STOPPED", report.attempted, #plan.steps,
    report.tilled, plan.till_count, report.planted, plan.plant_count))
  if report.last_pose then print("Last trusted planned pose: " .. poseText(report.last_pose)) end
  if not report.ok then
    local warning = report.uncertain and " Physical outcome may be uncertain; do not retry with a new ID." or ""
    return nil, tostring(report.reason) .. warning
  end
  print("Robot calls completed. Visually verify farmland and Potato crops before declaring success.")
  return true
end

local ok, result, reason = pcall(run)
closePort()
if not ok then io.stderr:write("Farm prototype error: " .. tostring(result) .. "\n"); os.exit(1) end
if not result then io.stderr:write("Farm prototype stopped: " .. tostring(reason) .. "\n"); os.exit(1) end
