local protocol = require("ocia.protocol")

local transport = {}
transport.__index = transport

function transport.new(options)
  assert(type(options) == "table", "transport options are required")
  assert(options.modem, "modem is required")
  assert(options.event, "event API is required")
  assert(options.computer, "computer API is required")
  assert(options.config, "configuration is required")
  assert(type(options.request_id) == "function", "request ID generator is required")

  return setmetatable({
    modem = options.modem,
    event = options.event,
    computer = options.computer,
    config = options.config,
    request_id = options.request_id
  }, transport)
end

function transport:makeRequest(operation, options)
  options = options or {}
  local request = {
    version = protocol.VERSION,
    request_id = options.request_id or self.request_id(),
    deployment_id = options.deployment_id or protocol.NO_DEPLOYMENT,
    recipient = self.config.robot_address,
    operation = operation,
    arguments = options.arguments or {}
  }
  local parts, reason = protocol.buildRequest(request)
  if not parts then return nil, reason end
  local parsed, code, message = protocol.parseRequest(parts, self.config.robot_address)
  if not parsed then return nil, code .. ": " .. message end
  return parsed, parts
end

function transport:sendRequest(operation, options)
  local request, partsOrReason = self:makeRequest(operation, options)
  if not request then
    return {
      certainty = "failed",
      status = "local_rejection",
      code = "invalid_request",
      message = partsOrReason
    }
  end
  local parts = partsOrReason

  local callOk, sent, sendReason = pcall(
    self.modem.send,
    self.config.robot_address,
    self.config.port,
    table.unpack(parts)
  )
  if not callOk or not sent then
    return {
      certainty = "failed",
      status = "send_failed",
      code = "send_failed",
      message = tostring(callOk and sendReason or sent),
      request = request
    }
  end

  local deadline = self.computer.uptime() + self.config.timeout
  local ignored = 0
  while true do
    local remaining = deadline - self.computer.uptime()
    if remaining <= 0 then
      return {
        certainty = "unknown",
        status = "timeout",
        code = "outcome_unknown",
        message = "no correlated reply before timeout",
        request = request,
        ignored_messages = ignored
      }
    end

    local eventData = table.pack(self.event.pull(remaining, "modem_message"))
    if not eventData[1] then
      return {
        certainty = "unknown",
        status = "timeout",
        code = "outcome_unknown",
        message = "no correlated reply before timeout",
        request = request,
        ignored_messages = ignored
      }
    end

    local localAddress = eventData[2]
    local sender = eventData[3]
    local port = eventData[4]
    if localAddress == self.config.controller_address
        and sender == self.config.robot_address
        and port == self.config.port then
      local replyParts = {}
      for index = 1, protocol.MESSAGE_PARTS do
        replyParts[index] = eventData[6 + index - 1]
      end
      local reply = protocol.parseReply(replyParts)
      if reply then
        local correlated = protocol.correlate(reply, request)
        if correlated then
          return {
            certainty = protocol.certainty(reply.outcome),
            status = reply.outcome,
            code = reply.payload.code,
            message = reply.payload.message,
            payload = reply.payload,
            reply = reply,
            request = request,
            ignored_messages = ignored
          }
        end
      end
    end
    ignored = ignored + 1
  end
end

return transport

