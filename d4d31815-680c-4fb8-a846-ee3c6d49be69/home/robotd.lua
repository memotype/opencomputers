-- Wheatley's Milestone 1 command daemon for OpenComputers 1.8.8 / Lua 5.3.
local component = require("component")
local computer = require("computer")
local event = require("event")
local robot = require("robot")

local configModule = require("ocia.config")
local executorModule = require("ocia.executor")
local legacy = require("ocia.legacy")
local protocol = require("ocia.protocol")
local state = require("ocia.state")

local config = assert(configModule.load("/etc/ocia.cfg", "robot"))
local modem = assert(component.modem, "Robot needs a wireless network card")
assert(modem.isWireless(), "Robot modem is not wireless")
assert(modem.address == config.robot_address,
  "Configured robot address does not match this modem")

local openedHere = false
if not modem.isOpen(config.port) then
  assert(modem.open(config.port), "Cannot open modem port " .. config.port)
  openedHere = true
end

local actions = {
  move_forward = robot.forward,
  move_backward = robot.back,
  turn_left = robot.turnLeft,
  turn_right = robot.turnRight,
  move_up = robot.up,
  move_down = robot.down
}

local store = state.fileStore(config.state_path)
local commandExecutor = executorModule.new({
  store = store,
  cache_size = config.cache_size,
  perform = function(operation)
    local action = actions[operation]
    if not action then return false, "unsupported physical operation" end
    return action()
  end,
  status_provider = function()
    return {
      energy = math.floor(computer.energy()),
      capacity = math.floor(computer.maxEnergy())
    }
  end
})

local function sendProtocolReply(sender, request, reply)
  local parts, reason = protocol.buildReply({
    request_id = request.request_id,
    deployment_id = request.deployment_id,
    operation = request.operation,
    outcome = reply.outcome,
    payload = reply.payload
  })
  if not parts then
    io.stderr:write("Cannot encode reply: " .. tostring(reason) .. "\n")
    return nil
  end
  local callOk, sent, sendReason = pcall(
    modem.send, sender, config.port, table.unpack(parts))
  if not callOk or not sent then
    io.stderr:write("Reply send failed: "
      .. tostring(callOk and sendReason or sent) .. "\n")
    return nil
  end
  return true
end

local function handleProtocol(sender, parts)
  if sender ~= config.controller_address then
    io.stderr:write("Ignored protocol packet from unexpected sender "
      .. tostring(sender) .. "\n")
    return
  end

  local request, code, message = protocol.parseRequest(parts, modem.address)
  if not request then
    io.stderr:write("Rejected malformed protocol packet: " .. tostring(code)
      .. ": " .. tostring(message) .. "\n")
    return
  end

  local dispatchOk, reply = pcall(commandExecutor.handle, commandExecutor, request)
  if not dispatchOk then
    io.stderr:write("Protected dispatch failed: " .. tostring(reply) .. "\n")
    return
  end
  sendProtocolReply(sender, request, reply)
  print(request.request_id .. " " .. request.operation .. " -> " .. reply.outcome
    .. " (" .. tostring(reply.payload and reply.payload.code) .. ")")
end

local function sendLegacyReply(sender, command, ok, detail)
  local energy = math.floor(computer.energy())
  local capacity = math.floor(computer.maxEnergy())
  local callOk, sent, sendReason = pcall(
    modem.send, sender, config.port, "result", command, ok, detail, energy, capacity)
  if not callOk or not sent then
    io.stderr:write("Legacy reply send failed: "
      .. tostring(callOk and sendReason or sent) .. "\n")
  end
  print("legacy " .. command .. " -> " .. tostring(detail)
    .. " [" .. energy .. "/" .. capacity .. "]")
end

local function handleLegacy(sender, command, count)
  if not config.legacy_enabled then return end
  if sender ~= config.controller_address then
    io.stderr:write("Ignored legacy packet from unexpected sender "
      .. tostring(sender) .. "\n")
    return
  end

  local parsed, reason = legacy.parse(command, count)
  if not parsed then
    sendLegacyReply(sender, tostring(command), false, reason)
    return
  end
  if not parsed.physical then
    sendLegacyReply(sender, parsed.command, true, "READY")
    return
  end

  local locked, lockReason = commandExecutor:beginManualRecovery()
  if not locked then
    sendLegacyReply(sender, parsed.command, false,
      "Cannot persist manual recovery state: " .. tostring(lockReason))
    return
  end

  local ok, detail = true, "OK"
  for index = 1, parsed.count do
    local callOk, moved, moveReason = pcall(actions[parsed.operation])
    if not callOk then
      ok = false
      detail = "Step " .. index .. " raised: " .. tostring(moved)
      break
    elseif not moved then
      ok = false
      detail = "Step " .. index .. ": " .. tostring(moveReason or "blocked")
      break
    end
  end
  sendLegacyReply(sender, parsed.command, ok, detail)
end

print("Robot agent listening on port " .. config.port)
print("Autonomous mode: " .. commandExecutor.snapshot.mode)
if commandExecutor.boot_classification then
  print("Startup reconciliation: " .. commandExecutor.boot_classification)
end
if commandExecutor.boot_error then
  io.stderr:write("Durable state unavailable: " .. commandExecutor.boot_error .. "\n")
end

local function run()
  while true do
    local packet = table.pack(event.pull("modem_message"))
    local sender, port = packet[3], packet[4]
    if port == config.port then
      local firstPayload = packet[6]
      if firstPayload == protocol.MAGIC then
        local parts = {}
        for index = 1, protocol.MESSAGE_PARTS do
          parts[index] = packet[5 + index]
        end
        handleProtocol(sender, parts)
      elseif type(firstPayload) == "string" then
        handleLegacy(sender, firstPayload, packet[7])
      end
    end
  end
end

local ok, reason = pcall(run)
if openedHere then modem.close(config.port) end
if not ok then error(reason, 0) end
