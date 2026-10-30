# Working Memory and Roadmap

This file contains current planning, progress, decisions under consideration, and handoff context. It is intentionally stateful and may be rewritten as the project evolves.

The evergreen project purpose, architecture, and engineering constraints are defined in [CODEX.md](CODEX.md). Known defects and risks are tracked by stable identifiers in [ISSUES.md](ISSUES.md). Do not duplicate durable design rules here when they belong in `CODEX.md`, and do not close a risk here without updating `ISSUES.md`.

## Current State

- Repository: `/home/isaac/dev/opencomputers`
- The repository contains snapshots of two OpenOS disks and is under Git version control.
- Controller disk: `7762455c-2ffb-4307-ac41-4faa2ae6a3a1`
- Robot disk: `d4d31815-680c-4fb8-a846-ee3c6d49be69`
- Controller program: `home/drive.lua`
- Robot program: `home/robotd.lua`
- Wireless port: `4242`
- No construction, blueprint, pose, persistence, or Refined Storage orchestration code has been implemented.
- The factory already has a Forestry Multifarm producing apples.
- The first full farm target is now a conventional Potato farm. Sugar Cane and other special crops are deferred to crop-specific blueprints.
- `CODEX.md`, `ISSUES.md`, and this roadmap are the first repository documentation added during the current work.

### Development environment

- Physical host: Ubuntu 26.04 with KDE Plasma.
- Development tools: VS Code and Codex.
- Minecraft instance: `/home/isaac/.ftba/instances/the 1122 pack perfectly complex`
- World save: `/home/isaac/.ftba/instances/the 1122 pack perfectly complex/saves/The 1_12_2 Pack`
- Live controller HDD: `/home/isaac/.ftba/instances/the 1122 pack perfectly complex/saves/The 1_12_2 Pack/opencomputers/7762455c-2ffb-4307-ac41-4faa2ae6a3a1`
- Live robot HDD: `/home/isaac/.ftba/instances/the 1122 pack perfectly complex/saves/The 1_12_2 Pack/opencomputers/d4d31815-680c-4fb8-a846-ee3c6d49be69`
- OpenComputers virtual HDDs are directories inside the Minecraft world save and can be edited from Linux.
- OpenComputers configuration has `bufferChanges=false`.
- OpenComputers configuration has `allowItemStackInspection=true`, permitting Inventory Controller stack descriptions.
- Minecraft has been restarted since that configuration change, so external edits can be observed without using the OpenOS editor.

Relevant installed JAR versions confirmed from the instance are:

- OpenComputers `1.8.8+8da357f`.
- Industrial Foregoing `1.12.13-237`.
- Extra Utilities 2 `1.9.9`.
- EnderStorage `2.4.6.137`.
- Refined Storage `1.6.16`.
- Refined Storage Addons `0.4.5`.
- Quark `r1.6-185-technic`; its enabled right-click-harvest configuration explicitly includes mature Potatoes.

### Installed hardware

The stationary controller is built, boots successfully, and contains:

- Tier 2 computer case.
- Tier 2 APU.
- Tier 2 memory.
- Tier 2 HDD with OpenOS.
- Lua BIOS EEPROM.
- Tier 2 Wireless Network Card.
- External Tier 2 screen.
- Keyboard.
- External disk drive.

The construction robot is built through the Electronics Assembler, boots successfully, and contains:

- Tier 2 APU.
- Two Tier 2 memory modules.
- Tier 2 HDD with OpenOS.
- Lua BIOS EEPROM.
- Tier 1 screen.
- Keyboard.
- Tier 2 Wireless Network Card.
- Inventory Upgrade.
- Internal disk drive.

The robot can be disassembled with the OpenComputers Disassembler, but disassembly and reassembly are expensive and inconvenient. Confirm that an additional hardware upgrade is actually required and fits the Tier 2 complexity/component limits before recommending a rebuild.

The charging station now has verified hardware:

- OpenComputers Charger.
- Existing Ender IO energy-conduit supply.
- Lever supplying the Charger's activation signal.

In-game testing showed that adjacency and conduit power were insufficient while the Charger lacked redstone. After a Lever was installed and activated, the Charger restored enough Robot energy for it to boot normally. This verifies stationary charging and the normal-mode redstone requirement, not autonomous docking, alignment, charge detection, target-level waiting, or deployment resume.

### Working remote control

`drive.lua` provides the following interactive controller commands:

- `f`, `b`, `u`, and `d` move forward, backward, up, and down.
- `l` and `r` turn left and right.
- `status` requests robot status.
- `q` or `quit` exits the driver.
- Movement accepts an optional count from 1 through 8, such as `f 4`.

`robotd.lua` listens on port 4242, executes the movement through the OpenComputers Robot API, and returns an acknowledgment containing battery status. The current request is `(command, count)`. The current reply is `("result", command, ok, detail, energy, capacity)`.

This path has been tested successfully in Minecraft. For example, `drive> f 4` returned `OK: OK`, reported battery state, and physically moved the robot four blocks.

The controller originally asserted an unconditional `modem.open(4242)`, which failed when the port was already open. `drive.lua` now checks `modem.isOpen(4242)` first and closes the port on normal shutdown. Port ownership is still tracked as OCIA-007, and the equivalent restart guard is still absent from `robotd.lua` under OCIA-006.

Do not replace or substantially rewrite this working control path without inspecting and preserving its recovery value.

### Survey capability research

The installed `OpenComputers-MC1.12.2-1.8.8+8da357f.jar` and its bundled English manual establish these API boundaries. They have not yet been exercised by this robot in-game:

- `robot.detect()`, `detectUp()`, and `detectDown()` examine only the adjacent space and return occupancy plus a broad category such as `entity`, `solid`, `replaceable`, `liquid`, or `air`.
- `robot.compare()`, `compareUp()`, and `compareDown()` compare an adjacent block with the selected inventory item. They do not return arbitrary block identity.
- No general `robot.inspect*` method appears in the installed 1.8.8 Robot library.
- The Inventory Controller Upgrade provides detailed item-stack and external-inventory inspection, targeted inventory transfer, and `equip()` for tool swapping. It is not a terrain scanner.
- A Geolyzer can be installed in a robot. Its documented component methods include `scan(...)`, which reports approximate noisy density or hardness for a bounded volume, and `analyze(side[, options])`, which reports information about one directly adjacent block.
- Installed callback documentation records `scan(x, z[, y, w, d, h][, ignoreReplaceable|options])` and `analyze(side[, options])`. Exact return tables, range under this configuration, energy use, noise behavior, and modded-block data still require in-game probes.
- `allowItemStackInspection=true` is enabled; installed bytecode gates Geolyzer `analyze()` behind that setting. Its actual returned block fields still need to be recorded in-game.

A Geolyzer may materially improve surface mapping and clearance discovery, but density scans do not establish registry identity. Blocks that are neither adjacent nor safely reachable may remain estimates or unknowns. Do not rebuild the robot for a Geolyzer until its value, required slot, and compatibility with the current Tier 2 assembly are established.

### Confirmed native Refined Storage integration

The stationary Tier 2 controller is connected to the powered Refined Storage 1.6.16 network through this tested adjacent-block topology:

```text
[OC Computer Case] -> [OC Adapter] -> [RS Interface] -> [RS Cable] -> [RS Network]
```

The Adapter connects directly to the Computer Case; no OC Cable or additional integration mod was needed. It is the standard OpenComputers `Adapter` (`opencomputers:adapter`, ore dictionary `oc:adapter`), not an RS-specific item.

OpenOS `components` discovered:

```text
refinedstorage_interface
775ac4ed-4249-433f-88d9-9c93625f4421
```

The following interactive tests succeeded against the actual factory network:

```lua
rs = require("component").refinedstorage_interface
print("Connected:", rs.isConnected())
-- Connected: true

items = rs.getItems()
print("Item types:", #items)
-- Item types: 396

for i=1,math.min(#items,10) do local v=items[i]; print(v.label or v.name, v.size or v.count) end
```

The first ten returned entries were:

```text
Mining Multitool          1
Anvil                     1
Nether Wart             120
Terracotta                1
Oak Wood Planks           3
Bronze Sharpening Kit     1
Raw Calamari              7
Magic Wax                 1
Amnesic Wax               1
Oak Trim                  3
```

Filtering Dirt variants with

```lua
for _,v in ipairs(items) do if (v.label or ""):lower():find("dirt",1,true) then print(v.label,v.name,v.damage,v.size) end end
```

returned:

```text
Purple Slimy Dirt  tconstruct:slime_dirt  2  144
Green Slimy Dirt   tconstruct:slime_dirt  0  136
Dirt               minecraft:dirt         0  2448
```

This verifies component discovery, network connectivity, inventory enumeration, quantities, registry identifiers, and metadata discrimination. Material matching should use registry identifiers plus relevant metadata/NBT rather than display labels.

`components -l refinedstorage_interface` also exposed these methods:

- Network and inventory: `isConnected`, `getItems`, `getItem`, `getMetadata`, `getStorages`, `getNetworkEnergyStored`, `getNetworkEnergyUsage`, `getNodeEnergyUsage`, `getEnergyUsage`, and `listAvailableItems`.
- Autocrafting: `getPatterns`, `getPattern`, `hasPattern`, `scheduleTask`, `getCraftingTasks`, `getTasks`, and `cancelTask`.
- Item transfer: `extractItem`, `pullItems`, and `pushItems`.
- Generic inventory: `size`, `suck`, `drop`, and `list`.
- Fluids: `getFluids`, `getFluid`, `getFluidPatterns`, `getFluidPattern`, `hasFluidPattern`, `scheduleFluidTask`, `cancelFluidTask`, and `extractFluid`.
- Utility: `getDocs`.

Visible help included these signatures:

```lua
getItems():table
getItem(stack:table[, compareMeta:boolean[, compareNBT:boolean]]):table
scheduleTask(stack:table[, count:number[, canSchedule:boolean]]):table
extractItem(stack:table[, count:number[, direction:number]]):table
```

Only `isConnected()` and `getItems()` have been exercised successfully. Individual item queries, pattern discovery, craft scheduling and monitoring, physical extraction, insertion, direction semantics, optional arguments, and return structures remain unverified.

The OpenOS REPL produced a stack trace and `end` syntax error when a multiline program was pasted as one block. Individual statements using persistent globals worked. Prefer host-maintained `.lua` probes over multiline REPL pastes.

### Superseded Dead Bush workflow

The Dead Bush MacGuffin processing-pattern cycle was manually tested successfully: 64 Dirt was staged as input, a reusable Dead Bush was declared as output and kept in staging by an Exporter, and returning it through an Interface completed the pending job. A pattern consuming and producing the same token was rejected as circular.

That mechanism is no longer the primary architecture. A survey-derived material requirement does not fit a fixed processing recipe, and RS task completion is not construction or mission completion. The protocol remains a proven historical technique and possible optional Crafting Grid trigger; deployments must neither require nor return a Dead Bush.

### Pending local configuration

The following values still need to be recorded when required by implementation:

- Controller modem address.
- Robot modem address.
- Robot-accessible staging and return inventory locations plus remaining component addresses.
- Deployment origins, headings, and site coordinates.
- Initial controller-side deployment submission interface.

The UUID-named repository directories identify the captured disk trees; do not assume they are modem addresses or live deployment paths.

## Current Design Direction

These choices are proposed for the first implementation and should be revised here if testing disproves them:

- Preserve `drive.lua` as a manual recovery and debugging tool.
- Extend `robotd.lua` without removing its legacy command format.
- Add a separate controller deployment program rather than turning the interactive driver into an orchestrator.
- Use unicast, versioned construction messages with request IDs on port 4242.
- Send one physical operation per construction request.
- Track relative pose from a known deployment origin and heading.
- Persist controller and robot checkpoints after every state transition relevant to recovery.
- Stop for manual reconciliation when an interrupted operation has an ambiguous physical result.
- Represent blueprints as block-coordinate data and generate movement on the controller.
- Build the first platform one block above known supporting terrain.
- Carry nine consumable dirt blocks plus one reserved dirt comparison block for exact verification.
- Keep the controller authoritative for deployment state; use native RS integration only as an inventory and autocrafting service.
- Treat blueprint data as desired state, a read-only survey as observed state, and the controller-generated diff as the inspectable plan.
- Survey and produce a deterministic terrain plan before calculating the bill of materials; do not let the initial survey modify blocks.
- Revalidate plan preconditions before apply, then resurvey after apply to prove convergence or report remaining differences.
- Allow staged extraction, multiple supply trips, recovered-material credit, and explicit reconciliation after the plan establishes requirements.
- Continue validating the standalone 3x3 control loop before coupling physical construction to automated provisioning.

## Potato Farm MVP Requirements

These requirements supersede the earlier Sugar Cane assumption for the first complete farm.

### Dead-reckoning frame

- The configurable charging station is the navigation origin `(0, 0, 0)`.
- The robot begins at the origin facing North.
- North is `-Z`, East is `+X`, and Up is `+Y`.
- Example pose chain: `forward()` gives `(0, 0, -1)`; `turnRight()` faces East; `forward()` gives `(1, 0, -1)`; `up()` gives `(1, 1, -1)`.
- A deployment command supplies the target coordinate of the central water block.

### Farm geometry

Relative to the central water block `W = (0, 0, 0)`:

- The 9x9 field occupies `X=-4..4`, `Z=-4..4`.
- The southern service row is at `Z=+5`.
- The Plant Interactor occupies `(0, 0, +5)` and faces North toward the field.
- The Transfer Node and center Transfer Pipe share `(+1, 0, +5)`, east of the Interactor.
- The Transfer Node attaches to the Interactor's east side and faces West.
- The preconfigured white/white/blue Ender Chest occupies `(+2, 0, +5)`.
- The Extra Utilities 2 Wireless RF Transmitter is placed on top of the Plant Interactor.

Plan view, with North at the top:

```text
DDDDDDDDD
DDDDDDDDD
DDDDDDDDD
DDDDDDDDD
DDDDWDDDD
DDDDDDDDD
DDDDDDDDD
DDDDDDDDD
DDDDDDDDD
....PTE..
```

`D` is tilled Dirt, `W` is a source-water block, `P` is the Plant Interactor, `T` is the shared Transfer Node/Transfer Pipe space, and `E` is the Ender Chest.

### Terrain preparation

- Level the 9x10 footprint to the target surface elevation.
- Remove elevated Dirt or Stone that occupies the intended field volume.
- Remove trees within the required footprint and clearance volume.
- Replace non-Dirt surface blocks beneath plant positions with Dirt.
- Leave the plant block space and the block above each plant clear for crop growth and lighting.
- Fill holes beneath the target surface with Dirt to a maximum depth of five blocks.
- Do not attempt to fill deeper voids to bedrock; stop and report a site failure when the five-block limit cannot produce supported terrain.
- This MVP is supervised and uses user-selected coordinates, so it does not require special preservation rules for valuable blocks or block entities. API failures and unbreakable blocks must still stop safely.

### Field construction

- Leave or excavate the central position for water.
- Place a source block using the RS-supplied water bucket.
- Till the remaining 80 Dirt blocks with a Hoe.
- Provision 80 Potatoes through the controller's native Refined Storage workflow and plant one Potato in each of the 80 tilled positions.
- Return the empty bucket to the return Interface after deployment.
- Treat missing Potatoes, failed planting, or an unverified crop position as deployment failure.

### Machine and logistics construction

- Place the Industrial Foregoing Plant Interactor facing North.
- Install the RS-supplied Tier 4 Range Addon if robot interaction permits it.
- Rely on the Interactor's default all-sides item output unless installed-version testing disproves that assumption.
- Place the Transfer Node by sneak-right-clicking the Interactor's east face with the node item.
- Place the Transfer Pipe into the same multipart block space by sneak-right-clicking the Transfer Node with the pipe item.
- Place the preconfigured white/white/blue EnderStorage chest immediately east of the pipe.
- Place the Wireless RF Transmitter on top of the Interactor.

### Materials and tools

- Building materials, machine blocks, the Tier 4 Range Addon, water bucket, exactly 80 Potatoes, and stone tools are provisioned from Refined Storage after the controller computes the survey-derived requirements.
- Reusable, recovered, or residual items, including the empty bucket, return to Refined Storage through a verified insertion workflow.
- The user intends automatic tool switching and replacement stone tools.
- The robot already has an Inventory Upgrade. The user is adding an Inventory Controller Upgrade for automatic equipped-tool swapping.
- The robot will not craft tools. The controller should request finished replacement tools through RS and make them physically available to the robot.
- Earlier source investigation suggests that the Interface exposes an 18-slot external inventory with import/return and stocked-export regions, but the robot-side slot and side mapping is not verified. Native extraction to a dedicated adjacent staging chest may avoid depending on those provider slots; test both loading and return paths before choosing one.

### MVP completion intent

Verify as much as the installed APIs reasonably permit, including terrain shape, Dirt/farmland state, water placement, machine positions and orientation, logistics placement, addon installation, power availability, planted crop state, item extraction, returned bucket, and robot recovery or return state. Unsupported verification must be reported explicitly rather than silently treated as success.

Completion records separate outcomes:

1. `construction_verified`: the farm satisfies all supported construction and functional checks.
2. `resource_reconciliation_complete`: the accounting pass has finished.
3. `resource_balance`: `balanced`, `discrepant`, or `accepted_discrepancy`. Only `balanced` is unconditional resource success; acceptance records the operator or policy and evidence separately.
4. `returned_to_charge`: the robot is at its configured charging pose and a bounded observation proves that charging is functioning.
5. `mission_outcome`: successful, successful with an accepted exception, or recovery required.

Construction may verify while resources remain discrepant or the return fails. Neither case is unconditional mission success. RS crafting tasks and the optional Dead Bush trigger do not define these milestones.

## Roadmap

### Phase 0: Establish the repository baseline

Goal: make future changes reviewable without disturbing the known working scripts.

- Record the existing disk snapshots as the baseline once the user is ready to create Git history.
- Add a focused `.gitignore` for runtime checkpoint files, logs, and host-generated temporary files.
- Decide whether the UUID disk trees remain the canonical deployable layout or are generated from a separate `src` tree.
- Document the safe synchronization command from repository source to each Minecraft HDD target.
- Keep the confirmed installed mod versions recorded with the runtime environment when the pack changes.

Related risks: OCIA-005, OCIA-006, OCIA-007.

### Phase 1: Introduce a compatible protocol layer

Goal: provide correlated, addressed requests while retaining manual driving.

- Define compact version 1 request and reply schemas.
- Add request ID and deployment ID generation.
- Configure controller and robot modem addresses outside source logic.
- Send construction requests by unicast.
- Validate sender, port, protocol version, request ID, and operation in both directions.
- Keep legacy `(command, count)` handling for `drive.lua`.
- Make modem port opening and ownership restart-safe.
- Return structured results rather than requiring prose parsing.
- Add host-side tests for protocol encoding, validation, and malformed payload rejection.

Related risks: OCIA-001, OCIA-002, OCIA-006, OCIA-007, OCIA-009, OCIA-010, OCIA-020.

### Phase 2: Add robot execution state and safe primitives

Goal: turn `robotd.lua` into a recoverable execution agent.

- Define the relative coordinate and heading convention.
- Add single-step move and turn operations.
- Add status reporting for pose, energy, inventory counts, daemon state, and last request.
- Journal in-flight and completed requests.
- Cache completed request results for duplicate delivery.
- Enter `recovery_required` after finding an interrupted in-flight operation.
- Protect dispatch and hardware calls from daemon-terminating errors.
- Add explicit begin-session, end-session, and recovery controls.
- Keep physical operations bounded and reject invalid arguments before acting.
- Test pose transitions and journal logic on the host; test robot APIs in Minecraft.

Related risks: OCIA-003, OCIA-004, OCIA-005, OCIA-008, OCIA-010, OCIA-014.

### Phase 3: Implement verified dirt placement

Goal: place one dirt block safely and prove the resulting state.

- Reserve known inventory slots for consumable dirt and a comparison sample.
- Inspect the block below before placement.
- Reject solids that do not match, liquids, and unsafe replaceable targets.
- Treat an existing matching dirt block as already satisfied.
- Record the consumable slot count before placement.
- Execute `robot.placeDown`.
- Verify the inventory delta, resulting solidity, and `robot.compareDown` result.
- Return structured evidence to the controller.
- Test air, existing dirt, unexpected solid, liquid, wrong material, and empty-slot cases in Minecraft.

Related risks: OCIA-011, OCIA-012, OCIA-013, OCIA-016.

### Phase 4: Build the blueprint and controller planner

Goal: convert a 3x3 dirt blueprint into deterministic robot operations.

- Define a minimal versioned blueprint schema.
- Express the platform as nine relative dirt coordinates.
- Validate blueprint coordinates and material totals.
- Generate a serpentine visit order for the platform layer.
- Generate turns and forward steps from the current relative pose.
- Simulate the complete plan without OpenComputers APIs.
- Report the expected ending pose, operation count, material consumption, and estimated energy margin.
- Add tests for route generation, orientation changes, invalid blueprints, and deterministic output.

Related risks: OCIA-004, OCIA-014, OCIA-020.

### Phase 5: Execute the standalone 3x3 deployment

Goal: complete the reference vertical slice defined in `CODEX.md`.

- Establish the robot at the declared origin and heading.
- Confirm sufficient energy and the required dirt-slot counts.
- Persist the controller deployment record before sending the first action.
- Execute the generated plan one request at a time.
- Advance controller pose and step only after a validated reply.
- Stop immediately on obstruction, state mismatch, timeout, or low energy.
- Verify each of the nine target coordinates during placement.
- Mark the deployment complete only when every coordinate is verified.
- Exercise manual recovery through `drive.lua` after an intentional failure.
- Run restart and lost-reply tests before considering the slice reliable.

Related risks: OCIA-003, OCIA-004, OCIA-005, OCIA-013, OCIA-014, OCIA-015, OCIA-016.

### Phase 6: Validate the native Refined Storage API

Goal: turn discovered component methods into a tested, version-specific inventory service contract.

- Test A — call `getItem()` for `{name="minecraft:dirt", damage=0}` and record the returned structure plus metadata/NBT matching behavior.
- Test B — use `hasPattern()`, `getPattern()`, or `getPatterns()` for a simple known autocraftable item and record its output representation.
- Test C — schedule one inexpensive craft and determine accepted arguments, omitted-argument defaults, task handles, monitoring through `getTasks()` or `getCraftingTasks()`, and behavior with missing ingredients or no pattern.
- Test D — place an ordinary chest adjacent to the Interface and extract one vanilla Dirt. Determine omitted-argument defaults, installed-version direction constants, stack format, physical adjacency, return quantity, chest receipt, RS inventory delta, and partial-extraction behavior.
- Test E — return one item to RS through the appropriate Interface inventory or exposed method and verify both the physical transfer and RS inventory increase.
- Test F — exercise or safely simulate network disconnection, absent materials, insufficient storage, a craft that cannot proceed, a full destination, extraction beyond one stack, and controller/game restart during an inventory operation.
- Keep the first craft and transfer deliberately cheap and small.
- Capture actual structures and errors in this file and convert durable behavior into tests or `CODEX.md` guidance.
- Do not promote a discovered method to a supported project capability until its observed behavior is recorded.

Related risks: OCIA-025, OCIA-026, OCIA-027, OCIA-028, OCIA-030.

### Phase 7: Survey terrain and produce a read-only plan

Goal: observe a representative uneven 9x10 site and compute the desired-versus-observed terrain diff without modifying any block.

- Probe `robot.detect*`, `robot.compare*`, Inventory Controller inspection, and Geolyzer `scan`/`analyze` behavior against the installed version.
- Decide whether the Geolyzer is necessary and fits the existing Tier 2 robot before any rebuild.
- Define a coordinate-indexed survey record with explicit observation kinds such as identified, compared, detected category, density estimate, and unknown.
- Record surface elevation, accessible material identity, trees and foliage, holes and unsupported terrain, elevated terrain, replacement surfaces, crop/machinery clearance, and five-block-limit failures.
- Preserve raw observations separately from controller-derived conclusions.
- Produce a deterministic plan with destroy, add, and change operations; estimated recovered and additional materials; unsafe conditions; and unsupported observations.
- Reject `READY TO APPLY` when an unknown or unsafe condition affects execution safety or the material estimate beyond the accepted policy.
- Confirm that repeating the planner with the same blueprint and survey produces the same ordered plan.
- The acceptance run must perform no `swing`, `place`, `use`, or other world-changing operation.

Acceptance report must contain:

1. A terrain map or equivalent coordinate-indexed observations.
2. Excavation requirements.
3. Fill requirements.
4. Surface replacement requirements.
5. Obstruction and clearance requirements.
6. Estimated recoverable materials.
7. Estimated additional materials.
8. Unsupported or uncertain observations with evidence level.
9. Conditions preventing safe execution.

Related risks: OCIA-004, OCIA-015, OCIA-016, OCIA-020, OCIA-032, OCIA-033, OCIA-034.

### Phase 8: Implement survey-driven resource provisioning

Goal: compute and fulfill a dynamic manifest from an accepted plan without coupling deployment completion to an RS crafting job.

- Define the initial controller-side submission contract and persist a deployment ID before surveying or provisioning.
- Derive the gross and net bill of materials from the accepted terrain plan, not directly from an assumed flat blueprint site.
- Credit recoverable excavation material only after it is observed, recovered, and allocated.
- Track stored, craftable, allocated, loaded, recovered, consumed, returned, missing, and unexplained quantities separately.
- Reserve resources for one active deployment and detect changes between inventory query, crafting, and extraction.
- Stage verified quantities in a dedicated accessible inventory and support partial fulfillment and multiple resupply trips.
- Choose and verify the robot loading path, including the Inventory Controller Upgrade and tool switching.
- Return the empty bucket, recovered blocks, unused supplies, and worn tools through the tested insertion path.
- Journal inventory mutations so restart ambiguity leads to reconciliation rather than blind replay.
- Record accounting completion separately from `balanced`, `discrepant`, or explicitly accepted discrepancy outcomes.
- Keep the Dead Bush workflow outside the required provisioning and completion state machines.

Related risks: OCIA-011, OCIA-022, OCIA-023, OCIA-026, OCIA-027, OCIA-028, OCIA-029, OCIA-030, OCIA-031.

### Phase 9: Apply and verify autonomous terrain preparation

Goal: complete the first major site-preparation milestone by surveying an uneven 9x10 footprint, applying its accepted terrain plan, and proving the result matches the target surface.

- Revalidate surveyed preconditions before the first destructive operation; replan or stop if the site drifted.
- Execute clearing, tree and foliage removal, excavation, five-block-limited filling, surface replacement, and required crop/machinery clearance as bounded operations.
- Verify every operation result and update actual recovered, consumed, and remaining material counts.
- Support controlled resupply when the verified execution result changes the estimated material requirement.
- Stop safely on unbreakable blocks, unsupported terrain below the fill limit, ambiguous pose, unexpected material, insufficient tools, or energy reserve breach.
- Resurvey the prepared footprint without modifying it and compare the observed result with the terrain target.
- Report remaining destroy/add/change differences; declare terrain convergence only when all supported requirements pass.
- Return to the charging pose and prove energy is increasing before `returned_to_charge` succeeds.

Related risks: OCIA-003, OCIA-004, OCIA-005, OCIA-014, OCIA-015, OCIA-016, OCIA-022, OCIA-029, OCIA-032, OCIA-034, OCIA-035.

### Phase 10: Develop the Potato farm MVP

Goal: use the converged terrain-preparation system to construct and verify useful infrastructure.

- Use the verified 9x10 terrain-preparation result; a manually prepared field is not a substitute for the end-to-end MVP.
- Test tilling, water placement, and Potato planting after terrain convergence.
- Validate provisioning, receipt, and successful planting of all 80 Potatoes.
- Test placement and orientation for water, the selected harvester, Tier 4 Range Addon, Wireless RF Transmitter, multipart Transfer Node/Pipe, and Ender Chest.
- Test source-water placement from the supplied bucket and return of the empty bucket.
- Define machine configuration and verification as typed actions.
- Determine power and EnderStorage connection requirements.
- Evaluate chunk-loading and return-to-charge needs for the selected site.
- Implement the farm only from individually verified block and machine behaviors.

Related risks: OCIA-011, OCIA-014, OCIA-015, OCIA-019, OCIA-021, OCIA-022, OCIA-029, OCIA-035.

### Phase 11: Add specialized crop blueprints

Goal: support crops whose placement or harvesting rules differ from ordinary farmland.

- Define crop-specific site and substrate requirements.
- Add a Sugar Cane layout with water adjacency rather than tilled farmland.
- Add a Cactus layout with spacing and adjacency safety.
- Select and verify appropriate harvesting machinery per crop family.
- Reuse common terrain, navigation, logistics, recovery, and completion modules.

Related risks: OCIA-019, OCIA-021.

## Immediate Next Work

The next software implementation session should continue with Phase 1 while preserving the committed repository baseline:

1. Define protocol version 1 and configuration files.
2. Add tests for the pure protocol logic.
3. Update `robotd.lua` with compatible dispatch and safe port handling.
4. Add a minimal controller probe that unicasts `status` and validates the correlated reply.
5. Test legacy `drive.lua` and the new status probe in Minecraft before adding physical construction operations.

The next Refined Storage validation session should execute Phase 6 Tests A through F in order. Tests A and B are read-only; Test C should use an inexpensive recipe; Tests D and E should move one ordinary Dirt through a dedicated adjacent chest. Record exact return values, side constants, physical inventory changes, and failure behavior before writing the provisioning module.

Before implementing the terrain survey, run small supervised API probes in a disposable test area:

1. Record `robot.detect*` results for air, Dirt, Stone, foliage, liquid, and an entity where safe.
2. Record `robot.compare*` behavior with matching and nonmatching block samples.
3. Install or test a Geolyzer only after confirming assembly capacity; record `scan` and `analyze` return tables, range, noise, energy cost, and modded-block behavior.
4. Determine which 9x10 observations are positive identifications, comparisons, categories, density estimates, or unavoidable unknowns.
5. Run the first complete survey-and-plan acceptance test with world-changing operations disabled.

For charging, measure robot energy at the expected charging pose with the Lever on and off. Establish the observation interval and minimum positive energy delta that will prove charging without confusing ordinary energy use or a full buffer with failure.

## Handoff Notes

- Existing source and unrelated user changes must be preserved carefully.
- The controller-side port-open guard is present and known to work.
- The same guard is absent from the robot daemon.
- Official OpenComputers source for the `1.12.2-forge/1.8.8` tag confirms that `robot.compareDown` is available without an Inventory Controller Upgrade.
- Detailed item-stack inspection does require an Inventory Controller Upgrade.
- The Inventory Controller Upgrade does not identify terrain blocks.
- Installed 1.8.8 code exposes no general `robot.inspect*`; detailed adjacent block analysis belongs to the optional Geolyzer.
- Geolyzer density scans are noisy estimates; `analyze` is limited to a directly adjacent block.
- Ordinary robot placement requires a supporting surface unless Angel placement is available.
- The verified Charger requires redstone activation in normal mode; autonomous docking and positive charging verification remain untested.
- OpenComputers defaults permit at most eight packet data parts and 8192 bytes per packet; keep messages compact.
- Do not implement mandatory Dead Bush return logic; it is an optional legacy trigger only.
