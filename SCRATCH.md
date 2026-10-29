# Working Memory and Roadmap

This file contains current planning, progress, decisions under consideration, and handoff context. It is intentionally stateful and may be rewritten as the project evolves.

The evergreen project purpose, architecture, and engineering constraints are defined in [CODEX.md](CODEX.md). Known defects and risks are tracked by stable identifiers in [ISSUES.md](ISSUES.md). Do not duplicate durable design rules here when they belong in `CODEX.md`, and do not close a risk here without updating `ISSUES.md`.

## Current State

- Repository: `/home/isaac/dev/opencomputers`
- The repository contains snapshots of two OpenOS disks and has no Git commits.
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

The robot can be disassembled with the OpenComputers Disassembler, but disassembly and reassembly are expensive and inconvenient. Confirm that an additional hardware upgrade is actually required before recommending a rebuild. The robot operates from an internal energy buffer; long-range deployment will require a battery-management and charging strategy.

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

### Proven Refined Storage completion workflow

The reusable Dead Bush completion mechanism has been manually tested end to end with Refined Storage 1.6.16.

The proof-of-concept processing pattern is:

- Input: 64 Dirt.
- Output: 1 Dead Bush.
- An RS Crafter points into a material-staging chest.
- An RS Exporter points into the same chest and continuously exports Dead Bushes, so the token normally remains in staging rather than available in Refined Storage.

The validated cycle is:

1. The player requests one Dead Bush from the RS Crafting Grid.
2. Refined Storage sends 64 Dirt into the staging chest.
3. The Crafting Monitor shows the processing job as pending.
4. The Exporter has already placed the reusable Dead Bush in staging.
5. An external worker collects the materials and Dead Bush.
6. After completing the external work, the worker deposits the Dead Bush into an RS Interface.
7. Refined Storage recognizes the expected output and completes the processing job.
8. The Exporter returns the Dead Bush to staging for reuse.

A processing pattern that both consumed and produced the Dead Bush was tested and rejected by Refined Storage as a circular dependency. The token must remain output-only. Its ordinary presence in staging does not indicate a pending job, so the controller must validate the material manifest or obtain another authoritative request signal. Initially, only one deployment may be active, and no failed or incomplete deployment may return the token.

### Pending local configuration

The following values still need to be recorded when required by implementation:

- Controller modem address.
- Robot modem address.
- Staging inventory location and component addresses.
- Deployment origins, headings, and site coordinates.

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
- Defer Refined Storage automation until standalone construction completes reliably.
- Investigate historical direct Refined Storage/OpenComputers integration separately; do not make it a prerequisite for the initial staging workflow.

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
- Receive 80 Potatoes from the Refined Storage processing pattern and plant one Potato in each of the 80 tilled positions.
- Return the empty bucket to the return Interface after deployment.
- Treat missing Potatoes, failed planting, or an unverified crop position as deployment failure; do not return the Dead Bush token.

### Machine and logistics construction

- Place the Industrial Foregoing Plant Interactor facing North.
- Install the RS-supplied Tier 4 Range Addon if robot interaction permits it.
- Rely on the Interactor's default all-sides item output unless installed-version testing disproves that assumption.
- Place the Transfer Node by sneak-right-clicking the Interactor's east face with the node item.
- Place the Transfer Pipe into the same multipart block space by sneak-right-clicking the Transfer Node with the pipe item.
- Place the preconfigured white/white/blue EnderStorage chest immediately east of the pipe.
- Place the Wireless RF Transmitter on top of the Interactor.

### Materials and tools

- Building materials, machine blocks, the Tier 4 Range Addon, water bucket, exactly 80 Potatoes, and stone tools are intended to come from Refined Storage staging.
- Reusable or residual items, including the empty bucket, return through the RS Interface used for completion handling.
- The user intends automatic tool switching and replacement stone tools.
- The robot already has an Inventory Upgrade. The user is adding an Inventory Controller Upgrade for automatic equipped-tool swapping.
- The robot will not craft tools. The RS Interface will have a Refined Storage Crafting Upgrade and will stock finished tools through its configured export/provider slots.
- Refined Storage 1.6.16 source exposes the Interface externally as 18 slots. From OpenComputers' one-based perspective, slots 1–9 should be the import/return inventory and slots 10–18 should be the stocked export inventory. The export filter row and four upgrade slots are not externally exposed through this item handler.
- Verify that mapping from the robot with an in-game probe before hardcoding slot numbers or sides.

### MVP completion intent

Verify as much as the installed APIs reasonably permit, including terrain shape, Dirt/farmland state, water placement, machine positions and orientation, logistics placement, addon installation, power availability, planted crop state, item extraction, returned bucket, and robot recovery or return state. Unsupported verification must be reported explicitly rather than silently treated as success.

Completion has three explicit milestones:

1. `construction_verified`: the farm satisfies all supported construction and functional checks.
2. `rs_acknowledged`: the robot deposits the Dead Bush MacGuffin token, completing the Refined Storage processing job.
3. `returned_to_charge`: the robot returns to the configured charging-station origin; only then is the robot mission complete.

If return fails after token deposit, construction and Refined Storage remain complete, but the robot mission enters recovery-required state.

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

### Phase 6: Integrate material staging

Goal: replace manual dirt loading with a controlled staging workflow.

- Confirm the staging inventory geometry and controller component access.
- Evaluate a Transposer for inventory inspection and transfer.
- Decide whether the robot loads itself or the controller transfers into a fixed loading inventory.
- Validate a complete manifest before starting a deployment.
- Ensure idle staging contents cannot trigger a job.
- Keep only one active deployment request until request identity is unambiguous.
- Install and validate the confirmed Inventory Controller Upgrade.
- Probe the Interface's expected 1–9 import and 10–18 export slot mapping from the robot.

Related risks: OCIA-011, OCIA-018, OCIA-022, OCIA-023.

### Phase 7: Connect the Dead Bush acknowledgment

Goal: make Refined Storage processing completion truthfully represent verified construction.

- Bind a supported material manifest to one blueprint and version.
- Claim the reusable token only as part of an accepted deployment request.
- Keep the token under controller authority during execution.
- Deposit the token into the Refined Storage Interface only from verified-success state.
- Retain the token and leave the processing job pending after failure or ambiguity.
- Continue the robot mission after acknowledgment until it returns to the charging origin.
- Distinguish a successful RS job with a failed return trip from complete robot mission success.
- Test success, obstruction, missing materials, restart, and manual cancellation.

Related risks: OCIA-017, OCIA-018, OCIA-024.

### Phase 8: Develop the Potato farm MVP

Goal: extend the proven deployment system to the production use case.

- Finalize the 9x10 site contract and variable bill of materials for terrain fill.
- Test clearing, five-block fill, surface replacement, tilling, and Potato planting.
- Validate receipt and successful planting of all 80 processing-pattern Potatoes.
- Test placement and orientation for water, the selected harvester, Tier 4 Range Addon, Wireless RF Transmitter, multipart Transfer Node/Pipe, and Ender Chest.
- Test source-water placement from the supplied bucket and return of the empty bucket.
- Define machine configuration and verification as typed actions.
- Determine power and EnderStorage connection requirements.
- Evaluate charging, chunk loading, and return-to-base needs for the selected site.
- Implement the farm only from individually verified block and machine behaviors.

Related risks: OCIA-011, OCIA-014, OCIA-015, OCIA-019, OCIA-021, OCIA-022.

### Phase 9: Add specialized crop blueprints

Goal: support crops whose placement or harvesting rules differ from ordinary farmland.

- Define crop-specific site and substrate requirements.
- Add a Sugar Cane layout with water adjacency rather than tilled farmland.
- Add a Cactus layout with spacing and adjacency safety.
- Select and verify appropriate harvesting machinery per crop family.
- Reuse common terrain, navigation, logistics, recovery, and completion modules.

Related risks: OCIA-019, OCIA-021.

## Immediate Next Work

The next implementation session should begin with Phase 0 and Phase 1:

1. Inspect any repository-layout preference supplied by the user.
2. Define protocol version 1 and configuration files.
3. Add tests for the pure protocol logic.
4. Update `robotd.lua` with compatible dispatch and safe port handling.
5. Add a minimal controller probe that unicasts `status` and validates the correlated reply.
6. Test legacy `drive.lua` and the new status probe in Minecraft before adding physical construction operations.

## Handoff Notes

- Existing source files are uncommitted user-owned files; preserve them carefully.
- The controller-side port-open guard is present and known to work.
- The same guard is absent from the robot daemon.
- Official OpenComputers source for the `1.12.2-forge/1.8.8` tag confirms that `robot.compareDown` is available without an Inventory Controller Upgrade.
- Detailed item-stack inspection does require an Inventory Controller Upgrade.
- Ordinary robot placement requires a supporting surface unless Angel placement is available.
- OpenComputers defaults permit at most eight packet data parts and 8192 bytes per packet; keep messages compact.
- Do not connect Dead Bush return logic until the standalone construction success state is reliable.
