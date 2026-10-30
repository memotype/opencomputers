-- Host-side installer for the project-owned OpenOS application files.
-- Requires Lua 5.3 and LuaFileSystem. This file is not deployed to OpenOS.

local lfs_ok, lfs = pcall(require, "lfs")
if not lfs_ok then
  io.stderr:write("deploy.lua: LuaFileSystem is required (Ubuntu package: lua-filesystem)\n")
  os.exit(1)
end

local M = {}

M.manifest = {
  controller = {
    "home/drive.lua",
    "home/ociactl.lua",
    "lib/ocia/config.lua",
    "lib/ocia/pose.lua",
    "lib/ocia/protocol.lua",
    "lib/ocia/transport.lua",
    "etc/ocia.cfg.example",
    {destination = "etc/ocia.cfg", template = "etc/ocia.cfg.example",
      generated = "ocia_config"},
  },
  robot = {
    "home/robotd.lua",
    "home/ocia-recover.lua",
    "lib/ocia/config.lua",
    "lib/ocia/executor.lua",
    "lib/ocia/legacy.lua",
    "lib/ocia/pose.lua",
    "lib/ocia/protocol.lua",
    "lib/ocia/state.lua",
    "etc/ocia.cfg.example",
    {destination = "etc/ocia.cfg", template = "etc/ocia.cfg.example",
      generated = "ocia_config"},
  },
}

local protected = {
  ["etc/ocia.cfg"] = true,
  ["var/lib/ocia/robot.state"] = true,
  ["var/lib/ocia/robot.state.new"] = true,
  ["var/lib/ocia/robot.state.old"] = true,
  ["var/lib/ocia/robot.state.switch"] = true,
}

local function dirname(path)
  local value = path:match("^(.*)/[^/]*$")
  return value == "" and "/" or (value or ".")
end

local function normalize(path)
  local absolute = path:sub(1, 1) == "/"
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local result = table.concat(parts, "/")
  if absolute then result = "/" .. result end
  if result == "" then return absolute and "/" or "." end
  return result
end

local function join(left, right)
  if left == "/" then return normalize("/" .. right) end
  return normalize(left .. "/" .. right)
end

local function absolute(path)
  if path:sub(1, 1) == "/" then return normalize(path) end
  return normalize(lfs.currentdir() .. "/" .. path)
end

local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local default_root = dirname(absolute(source))

local function path_error(label, path, detail)
  return string.format("%s %s: %s", label, path, detail or "invalid path")
end

local function attributes(path, symlink)
  local method = symlink and lfs.symlinkattributes or lfs.attributes
  local value, err = method(path)
  return value, err
end

local function require_directory(path, label)
  local link = attributes(path, true)
  if not link then return nil, path_error(label, path, "does not exist") end
  if link.mode == "link" then return nil, path_error(label, path, "symbolic links are not allowed") end
  local attr = attributes(path)
  if not attr or attr.mode ~= "directory" then
    return nil, path_error(label, path, "is not a directory")
  end
  return true
end

local function valid_relative(path)
  if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/" then return false end
  if path:find("//", 1, true) or path:sub(-1) == "/" then return false end
  for part in path:gmatch("[^/]+") do
    if part == "" or part == "." or part == ".." then return false end
  end
  return true
end

local function protected_path(path, generated)
  if path == "etc/ocia.cfg" and generated == "ocia_config" then return false end
  if path == "etc/ocia.cfg.example" and generated == nil then return false end
  return protected[path] or path == "etc" or path:match("^etc/") ~= nil
    or path == "var" or path:match("^var/") ~= nil
end

local function valid_uuid(value)
  return type(value) == "string"
    and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

local function count_plain(value, needle)
  local count, position = 0, 1
  while true do
    local found = value:find(needle, position, true)
    if not found then return count end
    count = count + 1
    position = found + #needle
  end
end

function M.render_ocia_config(template, modems)
  if type(template) ~= "string" then return nil, "OpenOS configuration template must be a string" end
  if type(modems) ~= "table" then return nil, "modem configuration must be a table" end
  local placeholders = {
    CONTROLLER_MODEM_UUID = modems.controller,
    ROBOT_MODEM_UUID = modems.robot,
  }
  for token in template:gmatch("[%u][%u%d_]*MODEM[%u%d_]*UUID[%u%d_]*") do
    if placeholders[token] == nil then
      return nil, "unexpected modem placeholder in OpenOS configuration template: " .. token
    end
  end
  local rendered = template
  for _, placeholder in ipairs({"CONTROLLER_MODEM_UUID", "ROBOT_MODEM_UUID"}) do
    local count = count_plain(rendered, placeholder)
    if count ~= 1 then
      return nil, string.format("OpenOS configuration template must contain exactly one %s (found %d)",
        placeholder, count)
    end
    rendered = rendered:gsub(placeholder, placeholders[placeholder])
  end
  local unresolved = rendered:match("[%u][%u%d_]*MODEM[%u%d_]*UUID[%u%d_]*")
  if unresolved then
    return nil, "unresolved modem placeholder in OpenOS configuration template: " .. unresolved
  end
  return rendered
end

local function read_file(path)
  local handle, open_err = io.open(path, "rb")
  if not handle then return nil, path_error("cannot read", path, open_err) end
  local ok, content = pcall(handle.read, handle, "*a")
  local close_ok, close_result, close_err = pcall(handle.close, handle)
  if not ok then return nil, path_error("cannot read", path, content) end
  if not close_ok then return nil, path_error("cannot close", path, close_result) end
  if close_result == nil then return nil, path_error("cannot close", path, close_err) end
  return content
end

local function write_file(path, content)
  local handle, open_err = io.open(path, "wb")
  if not handle then return nil, path_error("cannot open for writing", path, open_err) end
  local write_result, write_err = handle:write(content)
  if not write_result then
    pcall(handle.close, handle)
    return nil, path_error("cannot write", path, write_err)
  end
  local flush_result, flush_err = handle:flush()
  if not flush_result then
    pcall(handle.close, handle)
    return nil, path_error("cannot flush", path, flush_err)
  end
  local close_ok, close_result, close_err = pcall(handle.close, handle)
  if not close_ok then return nil, path_error("cannot close", path, close_result) end
  if not close_result then return nil, path_error("cannot close", path, close_err) end
  return true
end

local function inspect_relative(root, relative, include_leaf)
  local current = root
  local parts = {}
  for part in relative:gmatch("[^/]+") do parts[#parts + 1] = part end
  local limit = include_leaf and #parts or (#parts - 1)
  for index = 1, limit do
    current = join(current, parts[index])
    local attr = attributes(current, true)
    if attr then
      if attr.mode == "link" then
        return nil, path_error("unsafe path", current, "symbolic links are not allowed")
      end
      if index < #parts and attr.mode ~= "directory" then
        return nil, path_error("unsafe path", current, "parent is not a directory")
      end
    else
      break
    end
  end
  return true
end

local function ensure_relative_directories(root, relative)
  local current = root
  for part in relative:gmatch("[^/]+") do
    current = join(current, part)
    local attr = attributes(current, true)
    if attr then
      if attr.mode == "link" then
        return nil, path_error("unsafe directory", current, "symbolic links are not allowed")
      end
      if attr.mode ~= "directory" then
        return nil, path_error("unsafe directory", current, "is not a directory")
      end
    else
      local ok, err = lfs.mkdir(current)
      if not ok then return nil, path_error("cannot create directory", current, err) end
    end
  end
  return true
end

local function load_config(path)
  local chunk, load_err = loadfile(path, "t", {})
  if not chunk then return nil, path_error("cannot load configuration", path, load_err) end
  local ok, config = pcall(chunk)
  if not ok then return nil, path_error("configuration failed", path, config) end
  if type(config) ~= "table" then return nil, "configuration must return a table" end
  return config
end

function M.validate_config(config, selected_roles)
  if type(config) ~= "table" then return nil, "configuration must be a table" end
  if type(config.world_save) ~= "string" or config.world_save == "" then
    return nil, "configuration world_save must be a nonempty absolute path"
  end
  if config.world_save:sub(1, 1) ~= "/" then
    return nil, "configuration world_save must be an absolute path"
  end
  local world = normalize(config.world_save)
  local ok, err = require_directory(world, "world save")
  if not ok then return nil, err end
  local opencomputers = join(world, "opencomputers")
  ok, err = require_directory(opencomputers, "OpenComputers directory")
  if not ok then return nil, err end
  if type(config.disks) ~= "table" then return nil, "configuration disks must be a table" end
  if config.disks.controller == config.disks.robot and config.disks.controller ~= nil then
    return nil, "controller and robot must not use the same disk UUID"
  end
  local targets = {}
  for _, role in ipairs(selected_roles) do
    local disk = config.disks[role]
    if type(disk) == "string" and disk:find("DISK_UUID", 1, true) then
      return nil, string.format("configuration disks.%s still contains a placeholder", role)
    end
    if not valid_uuid(disk) then
      return nil, string.format("configuration disks.%s must be a canonical HDD UUID", role)
    end
    local target = join(opencomputers, disk)
    if dirname(target) ~= opencomputers then
      return nil, string.format("unsafe %s target path", role)
    end
    ok, err = require_directory(target, role .. " HDD")
    if not ok then return nil, err end
    targets[role] = {disk = disk, root = target}
  end
  if type(config.modems) ~= "table" then return nil, "configuration modems must be a table" end
  local modems = {}
  for _, role in ipairs({"controller", "robot"}) do
    local modem = config.modems[role]
    if type(modem) ~= "string" then
      return nil, string.format("configuration modems.%s must be a string", role)
    end
    if modem:find("MODEM_UUID", 1, true) then
      return nil, string.format("configuration modems.%s still contains a placeholder", role)
    end
    if modem:find("[%z\1-\31\127]") then
      return nil, string.format("configuration modems.%s contains a control character", role)
    end
    if not valid_uuid(modem) then
      return nil, string.format("configuration modems.%s must be a canonical modem UUID", role)
    end
    modems[role] = modem
  end
  if modems.controller == modems.robot then
    return nil, "controller and robot must not use the same modem UUID"
  end
  return {world = world, opencomputers = opencomputers, targets = targets, modems = modems}
end

local function parse_args(args)
  local result = {target = "all", apply = false}
  local index = 1
  while index <= #args do
    local value = args[index]
    if value == "--apply" then
      result.apply = true
    elseif value == "--help" or value == "-h" then
      result.help = true
    elseif value == "--target" then
      index = index + 1
      if not args[index] then return nil, "--target requires controller, robot, or all" end
      result.target = args[index]
    elseif value == "--config" then
      index = index + 1
      if not args[index] then return nil, "--config requires a path" end
      result.config = args[index]
    else
      return nil, "unknown argument: " .. tostring(value)
    end
    index = index + 1
  end
  if result.target ~= "controller" and result.target ~= "robot" and result.target ~= "all" then
    return nil, "unsupported target: " .. tostring(result.target)
  end
  return result
end

local function selected_roles(target)
  if target == "all" then return {"controller", "robot"} end
  return {target}
end

local function preflight(root, manifest, validated, roles)
  local plan = {}
  for _, role in ipairs(roles) do
    if type(manifest[role]) ~= "table" then return nil, "manifest is missing role " .. role end
    for _, item in ipairs(manifest[role]) do
      local relative, source_relative, generated
      if type(item) == "string" then
        relative, source_relative = item, item
      elseif type(item) == "table" then
        relative, source_relative, generated = item.destination, item.template, item.generated
        if generated ~= "ocia_config" then
          return nil, "unsupported generated manifest entry for " .. role .. ": " .. tostring(relative)
        end
        if relative ~= "etc/ocia.cfg" or source_relative ~= "etc/ocia.cfg.example" then
          return nil, "generated OpenOS configuration must use etc/ocia.cfg.example -> etc/ocia.cfg"
        end
      else
        return nil, "invalid manifest entry for " .. role
      end
      if not valid_relative(relative) then return nil, "unsafe manifest path for " .. role .. ": " .. tostring(relative) end
      if not valid_relative(source_relative) then
        return nil, "unsafe manifest source for " .. role .. ": " .. tostring(source_relative)
      end
      if protected_path(relative, generated) then return nil, "manifest targets protected runtime path: " .. relative end
      local source_path = join(join(root, "machines/" .. role), source_relative)
      local source_attr = attributes(source_path, true)
      if not source_attr or source_attr.mode ~= "file" then
        return nil, path_error("manifest source", source_path, "is missing or is not a regular file")
      end
      local content, read_err = read_file(source_path)
      if not content then return nil, read_err end
      if generated == "ocia_config" then
        content, read_err = M.render_ocia_config(content, validated.modems)
        if not content then return nil, role .. " configuration rendering failed: " .. read_err end
      end
      local target_root = validated.targets[role].root
      local safe, safe_err = inspect_relative(target_root, relative, true)
      if not safe then return nil, safe_err end
      local destination = join(target_root, relative)
      local destination_attr = attributes(destination, true)
      local action = "CREATE"
      if destination_attr then
        if destination_attr.mode ~= "file" then
          return nil, path_error("destination", destination, "is not a regular file")
        end
        local existing, existing_err = read_file(destination)
        if not existing then return nil, existing_err end
        action = existing == content and "UNCHANGED" or "UPDATE"
      end
      plan[#plan + 1] = {
        role = role, relative = relative, source = source_path,
        destination = destination, content = content, action = action,
        generated = generated ~= nil,
      }
    end
  end
  return plan
end

local function unique_run_id(backup_root)
  local base = os.date("!%Y%m%dT%H%M%SZ")
  for suffix = 1, 9999 do
    local candidate = string.format("%s-%04d", base, suffix)
    if not attributes(join(backup_root, candidate), true) then return candidate end
  end
  return nil, "could not allocate a unique backup run directory"
end

local temp_counter = 0
local function stage_path(entry)
  local parent = dirname(entry.destination)
  for _ = 1, 1000 do
    temp_counter = temp_counter + 1
    local name = string.format(".ocia-deploy-%d-%06d.tmp", os.time(), temp_counter)
    local candidate = join(parent, name)
    if not attributes(candidate, true) then return candidate end
  end
  return nil, "could not allocate a unique staging filename"
end

local function should_inject(inject, operation, entry)
  if inject == operation then return true end
  return type(inject) == "table" and inject.operation == operation
    and (inject.relative == nil or inject.relative == entry.relative)
    and (inject.role == nil or inject.role == entry.role)
end

local function make_backup(entry, root, backup_root, run_id, inject)
  if should_inject(inject, "backup", entry) then return nil, "injected backup failure" end
  local role_root = join(join(backup_root, run_id), entry.role)
  local ok, err = ensure_relative_directories(root,
    ".deploy-backups/" .. run_id .. "/" .. entry.role)
  if not ok then return nil, err end
  local parent_relative = dirname(entry.relative)
  if parent_relative ~= "." then
    ok, err = ensure_relative_directories(role_root, parent_relative)
    if not ok then return nil, err end
  end
  local original, read_err = read_file(entry.destination)
  if not original then return nil, read_err end
  local backup = join(role_root, entry.relative)
  local ok, write_err = write_file(backup, original)
  if not ok then return nil, write_err end
  local verified, verify_err = read_file(backup)
  if not verified then return nil, verify_err end
  if verified ~= original then return nil, "backup verification failed: " .. backup end
  return backup
end

local function install_entry(entry, target_root, root, backup_root, run_id, inject)
  local parent_relative = dirname(entry.relative)
  if parent_relative ~= "." then
    local ok, err = ensure_relative_directories(target_root, parent_relative)
    if not ok then return nil, err end
  end
  if entry.action == "UPDATE" then
    local backup, backup_err = make_backup(entry, root, backup_root, run_id, inject)
    if not backup then return nil, backup_err end
    entry.backup = backup
  end
  local temporary, temp_err = stage_path(entry)
  if not temporary then return nil, temp_err end
  if should_inject(inject, "stage", entry) then return nil, "injected staging failure" end
  local ok, write_err = write_file(temporary, entry.content)
  if not ok then
    os.remove(temporary)
    return nil, write_err
  end
  local staged, staged_err = read_file(temporary)
  if not staged then
    os.remove(temporary)
    return nil, staged_err
  end
  if staged ~= entry.content then
    os.remove(temporary)
    return nil, "staged file verification failed: " .. temporary
  end
  if should_inject(inject, "replace", entry) then
    os.remove(temporary)
    return nil, "injected replacement failure"
  end
  local renamed, rename_err = os.rename(temporary, entry.destination)
  if not renamed then
    os.remove(temporary)
    return nil, path_error("cannot replace", entry.destination, rename_err)
  end
  local installed, verify_err = read_file(entry.destination)
  if not installed then return nil, verify_err end
  if installed ~= entry.content then
    return nil, "post-install verification failed: " .. entry.destination
  end
  return true
end

local usage = [[Usage: lua5.3 deploy.lua [--target controller|robot|all] [--apply]
       lua5.3 deploy.lua --help

Defaults to --target all and a nondestructive dry run. Configuration is read
from deploy.local.lua beside this script. --config PATH selects another config
file, primarily for disposable test fixtures.]]

function M.run(args, options)
  options = options or {}
  local emit = options.emit or print
  local parsed, parse_err = parse_args(args or {})
  if not parsed then return nil, parse_err end
  if parsed.help then emit(usage); return {help = true} end
  local root = absolute(options.repo_root or default_root)
  local roles = selected_roles(parsed.target)
  local config = options.config
  if not config then
    local config_path = absolute(parsed.config or join(root, "deploy.local.lua"))
    config, parse_err = load_config(config_path)
    if not config then return nil, parse_err end
  end
  local validated, validation_err = M.validate_config(config, roles)
  if not validated then return nil, validation_err end
  local manifest = options.manifest or M.manifest
  local plan, plan_err = preflight(root, manifest, validated, roles)
  if not plan then return nil, plan_err end

  for _, role in ipairs(roles) do
    emit("Target: " .. role)
    emit("World: " .. validated.world)
    emit("Disk: " .. validated.targets[role].disk)
    for _, entry in ipairs(plan) do
      if entry.role == role then
        emit(string.format("%-9s %s%s", entry.action, entry.relative,
          entry.generated and " (generated)" or ""))
      end
    end
    emit("")
  end
  if not parsed.apply then
    emit("Dry run: no files modified.")
    emit("Use --apply to install.")
    return {dry_run = true, plan = plan, installed = {}}
  end

  local changed = 0
  for _, entry in ipairs(plan) do if entry.action ~= "UNCHANGED" then changed = changed + 1 end end
  if changed == 0 then
    emit("Apply complete: all selected files were already unchanged.")
    return {dry_run = false, plan = plan, installed = {}}
  end

  local backup_root = join(root, ".deploy-backups")
  local backup_attr = attributes(backup_root, true)
  if backup_attr and (backup_attr.mode == "link" or backup_attr.mode ~= "directory") then
    return nil, path_error("backup location", backup_root, "must be a real directory")
  end
  local run_id, run_err = unique_run_id(backup_root)
  if not run_id then return nil, run_err end
  local installed = {}
  for _, entry in ipairs(plan) do
    if entry.action ~= "UNCHANGED" then
      local ok, install_err = install_entry(entry, validated.targets[entry.role].root,
        root, backup_root, run_id, options.inject_failure)
      if not ok then
        return nil, string.format("%s %s failed: %s", entry.role, entry.relative, install_err), {
          plan = plan, installed = installed, failed = entry, backup_run = run_id,
        }
      end
      installed[#installed + 1] = entry.role .. ":" .. entry.relative
      emit("INSTALLED " .. entry.role .. " " .. entry.relative
        .. (entry.generated and " (generated)" or ""))
    end
  end
  emit(string.format("Apply complete: %d file(s) installed and verified.", #installed))
  local has_backup = false
  for _, entry in ipairs(plan) do if entry.backup then has_backup = true end end
  if has_backup then
    emit("Backup run: " .. join(backup_root, run_id))
  else
    emit("Backup run: none (no existing files were replaced).")
  end
  return {dry_run = false, plan = plan, installed = installed,
    backup_run = has_backup and run_id or nil}
end

function M.main(args, options)
  local result, err, partial = M.run(args, options)
  if result then return 0 end
  io.stderr:write("deploy.lua: " .. tostring(err) .. "\n")
  if partial and #partial.installed > 0 then
    io.stderr:write("Already installed before failure:\n")
    for _, item in ipairs(partial.installed) do io.stderr:write("  " .. item .. "\n") end
  else
    io.stderr:write("No files were installed.\n")
  end
  return 1
end

local invoked_as_script = type(arg) == "table" and type(arg[0]) == "string"
  and absolute(arg[0]) == absolute(source)
if not invoked_as_script then return M end
os.exit(M.main(arg))
