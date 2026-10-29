# Issue and Risk Register

This file tracks known defects, design risks, and unresolved operating constraints. Update an entry when evidence, scope, mitigation, or status changes. Move resolved entries to the resolved section rather than deleting their history.

## Status Definitions

- **Open:** The risk is present and has no completed mitigation.
- **In progress:** A mitigation is being implemented or tested.
- **Mitigated:** The planned safeguard is implemented and verified.
- **Accepted:** The limitation is understood and intentionally tolerated.
- **Deferred:** Resolution is intentionally outside the current implementation scope.

## Active Issues

### OCIA-001: Construction commands are broadcast

- **Status:** Open
- **Area:** Wireless transport
- **Risk:** Every robot listening on port 4242 may execute a command intended for one robot.
- **Current evidence:** The controller uses `modem.broadcast` for remote-driving commands.
- **Required mitigation:** Send construction traffic to a configured robot modem address and reject replies from other senders.
- **Resolution criteria:** A two-robot test demonstrates that only the addressed robot executes a deployment command.

### OCIA-002: Requests have no unique correlation identifier

- **Status:** Open
- **Area:** Wireless protocol
- **Risk:** A stale, duplicated, or unrelated reply can be mistaken for the result of the current operation.
- **Current evidence:** Requests contain only a command and count; replies are matched by command name.
- **Required mitigation:** Add protocol version, request ID, operation name, and deployment ID fields and validate all correlation fields.
- **Resolution criteria:** Delayed and duplicate replies cannot advance controller state incorrectly.

### OCIA-003: Lost acknowledgments make physical actions ambiguous

- **Status:** Open
- **Area:** Recovery and idempotency
- **Risk:** Retrying a movement or turn after a lost reply may execute the action twice and corrupt the robot pose.
- **Current evidence:** The controller times out without a request journal or robot-side result cache.
- **Required mitigation:** Journal in-flight and completed requests on the robot, cache completed results, and enter recovery-required state after an interrupted in-flight action.
- **Resolution criteria:** Duplicate completed requests return their original result without repeating the action, and interrupted requests are not replayed automatically.

### OCIA-004: Controller and robot do not track pose

- **Status:** Open
- **Area:** Navigation
- **Risk:** Construction planning cannot reliably map relative blueprint coordinates to physical robot actions.
- **Current evidence:** Neither script records position or orientation.
- **Required mitigation:** Define a relative coordinate system and update controller and robot pose only after successful operations.
- **Resolution criteria:** Movement and turn tests produce matching controller and robot poses, including partial-operation failures.

### OCIA-005: Deployment progress is not durable

- **Status:** Open
- **Area:** Persistence
- **Risk:** A program, computer, game, or host restart can lose the authoritative step and cause repeated or skipped construction.
- **Current evidence:** All control state exists only in Lua process memory.
- **Required mitigation:** Persist versioned controller deployment state and robot execution state using replace-safe writes.
- **Resolution criteria:** Restart tests either resume from an unambiguous checkpoint or stop with an explicit recovery requirement.

### OCIA-006: Robot modem port opening is not restart-safe

- **Status:** Open
- **Area:** Robot daemon
- **Risk:** Restarting `robotd.lua` can fail when port 4242 is already open.
- **Current evidence:** The robot unconditionally asserts that `modem.open(4242)` returns true.
- **Required mitigation:** Check `modem.isOpen` before opening and define whether the daemon owns and closes the port.
- **Resolution criteria:** The daemon can be stopped and restarted repeatedly without a port-open assertion failure.

### OCIA-007: Controller modem port ownership is unclear

- **Status:** Open
- **Area:** Controller transport
- **Risk:** `drive.lua` closes port 4242 on exit even when another program originally opened it.
- **Current evidence:** The program conditionally opens the port but closes it unconditionally.
- **Required mitigation:** Record whether the program opened the port and close it only when it owns that action, or centralize modem ownership.
- **Resolution criteria:** Exiting the manual driver does not disrupt another controller service using port 4242.

### OCIA-008: Robot hardware calls can terminate the daemon

- **Status:** Open
- **Area:** Error handling
- **Risk:** An unexpected OpenComputers API exception can stop command processing and leave the controller waiting.
- **Current evidence:** Robot actions are invoked without a protected call or top-level recovery boundary.
- **Required mitigation:** Wrap dispatch and hardware calls with bounded error handling, record failures, and keep the daemon observable.
- **Resolution criteria:** Injected operation errors produce failure replies and do not silently terminate the daemon.

### OCIA-009: Any wireless sender can command the robot

- **Status:** Open
- **Area:** Command authorization
- **Risk:** Another computer within range can move the robot or change the world.
- **Current evidence:** The robot accepts any string command received on port 4242.
- **Required mitigation:** Configure an allowed controller address and reject construction traffic from other senders. Define an intentional pairing or recovery procedure.
- **Resolution criteria:** Commands from an unconfigured modem are logged and ignored.

### OCIA-010: Multi-step commands have coarse acknowledgments

- **Status:** Open
- **Area:** Execution granularity
- **Risk:** A command such as `f 8` can partially succeed, but controller state depends on parsing a human-readable error string.
- **Current evidence:** The robot sends one reply after the movement loop.
- **Required mitigation:** Use one physical operation per construction request or return structured completed-step data.
- **Resolution criteria:** Controller pose is updated from structured results without parsing prose.

### OCIA-011: Material identity cannot be inspected with current hardware

- **Status:** Open
- **Area:** Inventory
- **Risk:** The robot can count known slots but cannot read detailed item identities without an Inventory Controller Upgrade.
- **Current evidence:** The robot has an Inventory Upgrade but no Inventory Controller Upgrade. The farm requirements call for switching among multiple equipped tools.
- **Required mitigation:** For the platform prototype, use declared slots and an unconsumed comparison block. Before terrain preparation, install and validate an Inventory Controller Upgrade or adopt a workflow that does not require automatic tool swapping.
- **Resolution criteria:** The prototype detects incorrect material before reporting success, and the robot can identify required materials and select every required tool safely.

### OCIA-012: Placement can fail without a supporting surface

- **Status:** Open
- **Area:** World interaction
- **Risk:** Standard robot placement cannot generally place a block into unsupported air.
- **Current evidence:** Classic OpenComputers placement follows Minecraft placement rules unless an Angel Upgrade is available.
- **Required mitigation:** Require known supporting terrain for the initial platform and encode placement preconditions in later blueprints.
- **Resolution criteria:** The platform site contract is documented and an unsupported-site test fails safely before material is consumed.

### OCIA-013: Placement success is not sufficient verification

- **Status:** Open
- **Area:** Verification
- **Risk:** Treating the return value of `robot.placeDown` as complete proof can miss an unexpected resulting block or inventory outcome.
- **Current evidence:** No placement or comparison commands exist in the robot daemon.
- **Required mitigation:** Check target state, placement result, inventory delta, resulting solidity, and `robot.compareDown` against a reserved material sample.
- **Resolution criteria:** Every platform coordinate has a structured verified result, and incorrect or obstructed targets prevent completion.

### OCIA-014: Energy exhaustion can strand the robot

- **Status:** Open
- **Area:** Power management
- **Risk:** A deployment may begin with insufficient energy and stop away from its recovery location.
- **Current evidence:** Energy is reported but not used as an execution precondition.
- **Required mitigation:** Establish conservative preflight and reserve thresholds before long deployments; later add charging and return-to-base behavior.
- **Resolution criteria:** Deployment is refused below the configured reserve and tested plans account for return or recovery energy.

### OCIA-015: Chunk unloading can interrupt unattended deployment

- **Status:** Open
- **Area:** Runtime environment
- **Risk:** The controller, robot, or build site may unload when no player is nearby.
- **Current evidence:** No chunk-loading strategy is defined.
- **Required mitigation:** Keep initial tests player-loaded and evaluate a Chunkloader Upgrade or fixed chunk-loading infrastructure before unattended long-range work.
- **Resolution criteria:** The operating envelope explicitly states its chunk-loading requirements and unattended tests behave predictably.

### OCIA-016: External world changes can invalidate the plan

- **Status:** Open
- **Area:** Concurrency and safety
- **Risk:** Players, mobs, machines, fluids, or other robots may change the site between planning and execution.
- **Current evidence:** No site reservation or repeated precondition validation exists.
- **Required mitigation:** Validate immediately before every physical action and stop on unexpected state. Consider site ownership only if concurrent deployments are introduced.
- **Resolution criteria:** A changed target produces a safe obstruction result rather than replacement or continued blind execution.

### OCIA-017: Refined Storage completion can be acknowledged falsely

- **Status:** Open
- **Area:** Job completion
- **Risk:** Returning the Dead Bush before construction is fully verified causes Refined Storage to mark an incomplete job complete.
- **Current evidence:** The token workflow is proven manually but is not connected to authoritative deployment state.
- **Required mitigation:** Permit token return only from the terminal verified-success state. Never return it for failed or ambiguous deployments.
- **Resolution criteria:** Failure and restart tests leave the processing job pending; only verified success returns the token.

### OCIA-018: Staging contents do not uniquely identify a request

- **Status:** Open
- **Area:** Refined Storage integration
- **Risk:** The reusable Dead Bush is normally present in staging and cannot prove that a processing request has started.
- **Current evidence:** The Exporter continuously returns the token to the staging chest.
- **Required mitigation:** Detect a request from a validated material manifest or direct Refined Storage job data and initially permit only one active deployment.
- **Resolution criteria:** An idle staging chest cannot trigger construction, while a complete supported manifest triggers exactly one deployment.

### OCIA-019: Modded machines may require specialized placement or configuration

- **Status:** Open
- **Area:** Blueprint execution
- **Risk:** Generic block placement may produce the wrong orientation or fail to configure machines, addons, power, or item routing.
- **Current evidence:** The intended Potato farm contains modded machines and multipart logistics whose robot placement, orientation, and configuration behavior has not been validated.
- **Required mitigation:** Treat machine operations as typed blueprint actions and test each block against the installed mod versions before adding it to an automated blueprint.
- **Resolution criteria:** Every machine used by a production blueprint has documented placement, orientation, configuration, and verification behavior.

### OCIA-020: Network packet limits constrain protocol design

- **Status:** Open
- **Area:** Wireless protocol
- **Risk:** Large plans or highly structured replies can exceed OpenComputers packet-size or packet-part limits.
- **Current evidence:** Default OpenComputers configuration limits packets to eight data parts and 8192 bytes.
- **Required mitigation:** Send bounded single-operation messages, serialize compact argument/result payloads, and validate payload size before transmission.
- **Resolution criteria:** Maximum supported requests remain within configured limits and oversized requests fail locally with a clear error.

### OCIA-021: Plant Interactor compatibility with Potatoes is unverified

- **Status:** Open
- **Area:** Farm operation
- **Risk:** The deployed farm may be constructed correctly but never harvest vanilla Potatoes.
- **Current evidence:** Industrial Foregoing 1.12.13 implements the Plant Interactor as a right-click harvester. The installed Quark configuration enables right-click harvesting and explicitly lists mature `minecraft:potatoes:7`, so compatibility is expected but not yet proven with the Interactor's fake player.
- **Required mitigation:** Test the installed Plant Interactor and Quark interaction against mature Potatoes. If it does not harvest them, use a compatible harvesting machine or select another supported crop.
- **Resolution criteria:** An installed-version test harvests a mature Potato, stores the drops, and leaves the field in the intended replanted state.

### OCIA-022: Required robot tool upgrades are not finalized

- **Status:** In progress
- **Area:** Robot hardware
- **Risk:** Terrain clearing and tilling require several tools, but the assembled robot cannot currently switch its equipped tool or craft replacements autonomously.
- **Current evidence:** The robot already contains an Inventory Upgrade. The user is adding an Inventory Controller Upgrade for automatic equipment swapping. Refined Storage, not the robot, will craft and stock replacement tools.
- **Required mitigation:** Install the Inventory Controller Upgrade, verify robot component capacity, and test `equip` plus external inventory access after reassembly.
- **Resolution criteria:** The assembled robot can identify, extract, equip, use, replace, and return every tool required by the terrain-preparation plan.

### OCIA-023: Refined Storage Interface slot mapping needs an in-game probe

- **Status:** Open
- **Area:** Material staging
- **Risk:** Incorrect slot assumptions could prevent tool withdrawal or cause the robot to return the Dead Bush or reusable items to a non-insertable slot.
- **Current evidence:** Refined Storage 1.6.16 source exposes an 18-slot combined item handler: nine import slots followed by nine export slots. OpenComputers uses one-based external slot numbers, implying import slots 1–9 and stocked export slots 10–18.
- **Required mitigation:** Probe the installed Interface with `getInventorySize`, `getStackInSlot`, `suckFromSlot`, and `dropIntoSlot` from each relevant side before encoding the mapping.
- **Resolution criteria:** An in-game test extracts a known tool from its stocked export slot and deposits a test item into an import slot that Refined Storage accepts.

### OCIA-024: Refined Storage can complete before the robot mission ends

- **Status:** Accepted
- **Area:** Completion semantics
- **Risk:** The Dead Bush can complete the external processing request even if the robot later becomes stranded while returning to charge.
- **Current evidence:** The required contract defines token deposit as Refined Storage completion and arrival at the charging station as robot mission completion.
- **Required mitigation:** Track `construction_verified`, `rs_acknowledged`, and `returned_to_charge` separately. Continue monitoring and report a recovery alert after acknowledgment until the robot reaches its origin.
- **Resolution criteria:** A failed return trip leaves Refined Storage complete but records the robot mission as recovery-required rather than complete.

## Resolved Issues

No issues have been resolved in the tracked implementation yet.
