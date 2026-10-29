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
- The Sugar Cane farm blueprint and its material quantities have not been finalized.
- `CODEX.md`, `ISSUES.md`, and this roadmap are the first repository documentation added during the current work.

### Development environment

- Physical host: Ubuntu 26.04 with KDE Plasma.
- Development tools: VS Code and Codex.
- OpenComputers virtual HDDs are directories inside the Minecraft world save and can be edited from Linux.
- OpenComputers configuration has `bufferChanges=false`.
- Minecraft has been restarted since that configuration change, so external edits can be observed without using the OpenOS editor.

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

- Minecraft instance path.
- World save path.
- Actual controller HDD deployment path.
- Actual robot HDD deployment path.
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

## Roadmap

### Phase 0: Establish the repository baseline

Goal: make future changes reviewable without disturbing the known working scripts.

- Record the existing disk snapshots as the baseline once the user is ready to create Git history.
- Add a focused `.gitignore` for runtime checkpoint files, logs, and host-generated temporary files.
- Decide whether the UUID disk trees remain the canonical deployable layout or are generated from a separate `src` tree.
- Document the safe synchronization command from repository source to each Minecraft HDD target.
- Confirm the exact installed OpenComputers mod version in addition to the OpenOS version.

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
- Decide whether an Inventory Controller Upgrade is required before robot-side loading.

Related risks: OCIA-011, OCIA-018.

### Phase 7: Connect the Dead Bush acknowledgment

Goal: make Refined Storage processing completion truthfully represent verified construction.

- Bind a supported material manifest to one blueprint and version.
- Claim the reusable token only as part of an accepted deployment request.
- Keep the token under controller authority during execution.
- Deposit the token into the Refined Storage Interface only from verified-success state.
- Retain the token and leave the processing job pending after failure or ambiguity.
- Test success, obstruction, missing materials, restart, and manual cancellation.

Related risks: OCIA-017, OCIA-018.

### Phase 8: Develop the Sugar Cane farm blueprint

Goal: extend the proven deployment system to the production use case.

- Finalize farm dimensions, site contract, and bill of materials.
- Test placement and orientation for Sugar Cane, water, Plant Gatherer, Range Addon, power, and logistics blocks.
- Decide whether water uses buckets, a Tank Upgrade, or prepared site infrastructure.
- Define machine configuration and verification as typed actions.
- Determine power and EnderStorage connection requirements.
- Evaluate charging, chunk loading, and return-to-base needs for the selected site.
- Implement the farm only from individually verified block and machine behaviors.

Related risks: OCIA-014, OCIA-015, OCIA-019.

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
