-- Host-side tests for deploy.lua. Requires Lua 5.3 and LuaFileSystem.
package.path = "./?.lua;" .. package.path

local lfs = require("lfs")
local deploy = require("deploy")

local tests, assertions = {}, 0
local function test(name, callback) tests[#tests + 1] = {name, callback} end
local function truthy(value, message)
  assertions = assertions + 1
  if not value then error(message or "expected a truthy value", 2) end
end
local function equal(actual, expected, message)
  assertions = assertions + 1
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end
local function contains(value, fragment)
  assertions = assertions + 1
  if type(value) ~= "string" or not value:find(fragment, 1, true) then
    error("expected " .. tostring(value) .. " to contain " .. fragment, 2)
  end
end

local function join(left, right) return left .. "/" .. right end

local function mkdir(path)
  local ok, err = lfs.mkdir(path)
  if not ok and lfs.attributes(path, "mode") ~= "directory" then error(err) end
end

local function mkdirs(path)
  local current = path:sub(1, 1) == "/" and "/" or ""
  for part in path:gmatch("[^/]+") do
    current = current == "/" and (current .. part)
      or (current == "" and part or current .. "/" .. part)
    mkdir(current)
  end
end

local function write(path, content)
  mkdirs(path:match("^(.*)/[^/]+$") or ".")
  local handle = assert(io.open(path, "wb"))
  assert(handle:write(content))
  assert(handle:close())
end

local function read(path)
  local handle = assert(io.open(path, "rb"))
  local content = assert(handle:read("*a"))
  assert(handle:close())
  return content
end

local function remove_tree(path)
  local mode = lfs.symlinkattributes(path, "mode")
  if not mode then return end
  if mode == "directory" then
    for name in lfs.dir(path) do
      if name ~= "." and name ~= ".." then remove_tree(join(path, name)) end
    end
    assert(lfs.rmdir(path))
  else
    assert(os.remove(path))
  end
end

local fixture_counter = 0
local controller_uuid = "11111111-1111-4111-8111-111111111111"
local robot_uuid = "22222222-2222-4222-8222-222222222222"
local manifest = {
  controller = {"home/controller.lua", "etc/ocia.cfg.example"},
  robot = {"home/robot.lua", "lib/ocia/state.lua", "etc/ocia.cfg.example"},
}

local function fixture()
  fixture_counter = fixture_counter + 1
  local root = os.tmpname() .. "-ocia-deploy-" .. fixture_counter
  os.remove(root)
  mkdirs(join(root, "repo/machines/controller/home"))
  mkdirs(join(root, "repo/machines/controller/etc"))
  mkdirs(join(root, "repo/machines/robot/home"))
  mkdirs(join(root, "repo/machines/robot/lib/ocia"))
  mkdirs(join(root, "repo/machines/robot/etc"))
  local world = join(root, "temporary-world")
  mkdirs(join(world, "opencomputers/" .. controller_uuid))
  mkdirs(join(world, "opencomputers/" .. robot_uuid))
  write(join(root, "repo/machines/controller/home/controller.lua"), "controller-v1\n")
  write(join(root, "repo/machines/controller/etc/ocia.cfg.example"), "controller-example\n")
  write(join(root, "repo/machines/robot/home/robot.lua"), "robot-v1\n")
  write(join(root, "repo/machines/robot/lib/ocia/state.lua"), "state-v1\n")
  write(join(root, "repo/machines/robot/etc/ocia.cfg.example"), "robot-example\n")
  return {
    root = root, repo = join(root, "repo"), world = world,
    controller = join(world, "opencomputers/" .. controller_uuid),
    robot = join(world, "opencomputers/" .. robot_uuid),
    config = {world_save = world, disks = {controller = controller_uuid, robot = robot_uuid}},
  }
end

local function run(f, args, options)
  local output = {}
  options = options or {}
  options.repo_root = f.repo
  options.config = options.config or f.config
  options.manifest = options.manifest or manifest
  options.emit = function(line) output[#output + 1] = line end
  local result, err, partial = deploy.run(args or {}, options)
  return result, err, partial, table.concat(output, "\n")
end

local function count_files(path)
  local count = 0
  local mode = lfs.symlinkattributes(path, "mode")
  if not mode then return 0 end
  if mode ~= "directory" then return 1 end
  for name in lfs.dir(path) do
    if name ~= "." and name ~= ".." then count = count + count_files(join(path, name)) end
  end
  return count
end

test("configuration validation rejects incomplete, placeholder, and unsafe values", function()
  local f = fixture()
  local result, err = run(f, {}, {config = {world_save = "relative", disks = {}}})
  equal(result, nil); contains(err, "absolute path")
  result, err = run(f, {}, {config = {world_save = f.world,
    disks = {controller = "CONTROLLER_DISK_UUID", robot = robot_uuid}}})
  equal(result, nil); contains(err, "placeholder")
  result, err = run(f, {}, {config = {world_save = f.world,
    disks = {controller = "../escape", robot = robot_uuid}}})
  equal(result, nil); contains(err, "canonical HDD UUID")
  remove_tree(f.root)
end)

test("missing world, OpenComputers directory, and disk are rejected", function()
  local f = fixture()
  local result, err = run(f, {}, {config = {world_save = join(f.root, "missing"), disks = f.config.disks}})
  equal(result, nil); contains(err, "world save")
  local empty_world = join(f.root, "empty-world"); mkdir(empty_world)
  result, err = run(f, {}, {config = {world_save = empty_world, disks = f.config.disks}})
  equal(result, nil); contains(err, "OpenComputers directory")
  assert(lfs.rmdir(f.robot))
  result, err = run(f, {"--target", "robot"})
  equal(result, nil); contains(err, "robot HDD")
  remove_tree(f.root)
end)

test("invalid target and unknown arguments fail before deployment", function()
  local f = fixture()
  local result, err = run(f, {"--target", "server"})
  equal(result, nil); contains(err, "unsupported target")
  result, err = run(f, {"--wat"})
  equal(result, nil); contains(err, "unknown argument")
  remove_tree(f.root)
end)

test("CLI errors return a nonzero process status", function()
  local ok, reason, code = os.execute(
    "lua5.3 deploy.lua --target unsupported >/dev/null 2>&1")
  equal(ok, nil)
  equal(reason, "exit")
  equal(code, 1)
end)

test("default dry run reports a plan and creates no artifacts", function()
  local f = fixture()
  local before = count_files(f.root)
  local result, _, _, output = run(f)
  truthy(result and result.dry_run)
  contains(output, "CREATE")
  contains(output, "Dry run: no files modified")
  equal(count_files(f.root), before)
  equal(lfs.attributes(join(f.controller, "home")), nil)
  equal(lfs.attributes(join(f.repo, ".deploy-backups")), nil)
  remove_tree(f.root)
end)

test("initial apply creates only manifest files", function()
  local f = fixture()
  local result = assert(run(f, {"--apply"}))
  equal(#result.installed, 5)
  equal(read(join(f.controller, "home/controller.lua")), "controller-v1\n")
  equal(read(join(f.robot, "lib/ocia/state.lua")), "state-v1\n")
  equal(lfs.attributes(join(f.controller, "bin")), nil)
  equal(lfs.attributes(join(f.repo, ".deploy-backups")), nil)
  remove_tree(f.root)
end)

test("changed files are updated and original bytes are backed up", function()
  local f = fixture()
  write(join(f.controller, "home/controller.lua"), "old\0bytes\n")
  local result = assert(run(f, {"--target", "controller", "--apply"}))
  equal(read(join(f.controller, "home/controller.lua")), "controller-v1\n")
  truthy(result.backup_run)
  equal(read(join(f.repo, ".deploy-backups/" .. result.backup_run
    .. "/controller/home/controller.lua")), "old\0bytes\n")
  remove_tree(f.root)
end)

test("identical files are skipped and repeated apply is idempotent", function()
  local f = fixture()
  assert(run(f, {"--apply"}))
  local before = count_files(f.root)
  local result, _, _, output = run(f, {"--apply"})
  equal(#result.installed, 0)
  contains(output, "UNCHANGED")
  equal(count_files(f.root), before)
  remove_tree(f.root)
end)

test("controller-only and robot-only selections remain isolated", function()
  local f = fixture()
  assert(run(f, {"--target", "controller", "--apply"}))
  truthy(lfs.attributes(join(f.controller, "home/controller.lua")))
  equal(lfs.attributes(join(f.robot, "home/robot.lua")), nil)
  assert(run(f, {"--target", "robot", "--apply"}))
  truthy(lfs.attributes(join(f.robot, "home/robot.lua")))
  remove_tree(f.root)
end)

test("runtime configuration, journal artifacts, and unlisted files are preserved", function()
  local f = fixture()
  write(join(f.controller, "etc/ocia.cfg"), "live-controller-config\n")
  write(join(f.robot, "etc/ocia.cfg"), "live-robot-config\n")
  write(join(f.robot, "var/lib/ocia/robot.state"), "journal\n")
  write(join(f.robot, "var/lib/ocia/robot.state.new"), "new\n")
  write(join(f.robot, "var/lib/ocia/robot.state.old"), "old\n")
  write(join(f.robot, "var/lib/ocia/robot.state.switch"), "switch\n")
  write(join(f.robot, "home/user-note.txt"), "keep me\n")
  assert(run(f, {"--apply"}))
  equal(read(join(f.controller, "etc/ocia.cfg")), "live-controller-config\n")
  equal(read(join(f.robot, "etc/ocia.cfg")), "live-robot-config\n")
  equal(read(join(f.robot, "var/lib/ocia/robot.state")), "journal\n")
  equal(read(join(f.robot, "var/lib/ocia/robot.state.new")), "new\n")
  equal(read(join(f.robot, "var/lib/ocia/robot.state.old")), "old\n")
  equal(read(join(f.robot, "var/lib/ocia/robot.state.switch")), "switch\n")
  equal(read(join(f.robot, "home/user-note.txt")), "keep me\n")
  remove_tree(f.root)
end)

test("unsafe and protected manifest destinations are rejected", function()
  local f = fixture()
  local result, err = run(f, {}, {manifest = {controller = {"../escape"}, robot = {}}})
  equal(result, nil); contains(err, "unsafe manifest path")
  result, err = run(f, {"--target", "robot"},
    {manifest = {controller = {}, robot = {"var/lib/ocia/robot.state"}}})
  equal(result, nil); contains(err, "protected runtime path")
  remove_tree(f.root)
end)

test("symbolic-link destination paths are rejected", function()
  local f = fixture()
  assert(os.execute("ln -s /tmp " .. string.format("%q", join(f.robot, "home"))))
  local result, err = run(f, {"--target", "robot"})
  equal(result, nil); contains(err, "symbolic links are not allowed")
  remove_tree(f.root)
end)

test("staging failure stops without replacing the destination", function()
  local f = fixture()
  local result, err = run(f, {"--target", "controller", "--apply"},
    {inject_failure = "stage"})
  equal(result, nil); contains(err, "staging failure")
  equal(lfs.attributes(join(f.controller, "home/controller.lua")), nil)
  remove_tree(f.root)
end)

test("backup failure prevents replacement", function()
  local f = fixture()
  write(join(f.controller, "home/controller.lua"), "original\n")
  local result, err = run(f, {"--target", "controller", "--apply"},
    {inject_failure = "backup"})
  equal(result, nil); contains(err, "backup failure")
  equal(read(join(f.controller, "home/controller.lua")), "original\n")
  remove_tree(f.root)
end)

test("replacement failure is nonzero, preserves destination, and keeps backup", function()
  local f = fixture()
  write(join(f.controller, "home/controller.lua"), "original\n")
  local result, err, partial = run(f, {"--target", "controller", "--apply"},
    {inject_failure = "replace"})
  equal(result, nil); contains(err, "replacement failure")
  equal(read(join(f.controller, "home/controller.lua")), "original\n")
  truthy(partial and partial.backup_run)
  equal(read(join(f.repo, ".deploy-backups/" .. partial.backup_run
    .. "/controller/home/controller.lua")), "original\n")
  remove_tree(f.root)
end)

test("partial failure reports files already installed and stops later work", function()
  local f = fixture()
  local result, err, partial = run(f, {"--target", "robot", "--apply"},
    {inject_failure = {operation = "replace", relative = "lib/ocia/state.lua"}})
  equal(result, nil); contains(err, "lib/ocia/state.lua")
  equal(#partial.installed, 1)
  equal(partial.installed[1], "robot:home/robot.lua")
  equal(lfs.attributes(join(f.robot, "etc/ocia.cfg.example")), nil)
  remove_tree(f.root)
end)

for _, item in ipairs(tests) do
  local ok, err = pcall(item[2])
  if ok then
    io.write("ok - ", item[1], "\n")
  else
    io.write("not ok - ", item[1], "\n", tostring(err), "\n")
    os.exit(1)
  end
end

io.write(string.format("\n%d tests, %d assertions, 0 failures\n", #tests, assertions))
