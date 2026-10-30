# Issue and Risk Register

This file tracks known defects, design risks, and unresolved operating constraints. Update an entry when evidence, scope, mitigation, or status changes. Move resolved entries to the resolved section rather than deleting their history.

## Status Definitions

- **Open:** The risk is present and has no completed mitigation.
- **In progress:** A mitigation is being implemented or tested.
- **Mitigated:** The planned safeguard is implemented and verified.
- **Accepted:** The limitation is understood and intentionally tolerated.
- **Deferred:** Resolution is intentionally outside the current implementation scope.
- **Superseded:** The original risk no longer applies because an architectural decision replaced the affected workflow; its history remains recorded.

## Active Issues

### OCIA-001: Construction commands are broadcast

- **Status:** In progress
- **Area:** Wireless transport
- **Risk:** Every robot listening on port 4242 may execute a command intended for one robot.
- **Current evidence:** The implemented OCIA transport uses `modem.send` to the configured robot and validates reply sender/local recipient in host tests. Legacy `drive.lua` intentionally remains broadcast for manual compatibility, and the robot restricts it to the configured controller. No two-robot in-game test has run.
- **Required mitigation:** Send construction traffic to a configured robot modem address and reject replies from other senders.
- **Resolution criteria:** A two-robot test demonstrates that only the addressed robot executes a deployment command.

### OCIA-002: Requests have no unique correlation identifier

- **Status:** In progress
- **Area:** Wireless protocol
- **Risk:** A stale, duplicated, or unrelated reply can be mistaken for the result of the current operation.
- **Current evidence:** Version 1 requests/replies include request, deployment, operation, and protocol identity. Host tests show stale replies and wrong senders are ignored. Legacy manual requests still contain only command/count and are not an autonomous state source.
- **Required mitigation:** Add protocol version, request ID, operation name, and deployment ID fields and validate all correlation fields.
- **Resolution criteria:** Delayed and duplicate replies cannot advance controller state incorrectly.

### OCIA-003: Lost acknowledgments make physical actions ambiguous

- **Status:** In progress
- **Area:** Recovery and idempotency
- **Risk:** Retrying a movement or turn after a lost reply may execute the action twice and corrupt the robot pose.
- **Current evidence:** The robot appends `prepared` then `executing`, records completed results, returns retained duplicates without another physical call, and marks restart from `executing` as recovery-required. Hardening fixed source defects that had mislabeled a matching unresolved retry as retired both directly and after a durable legacy-manual recovery record. The unresolved identity now survives manual recovery and restart, returns `physical_outcome_unknown`, preserves untrusted pose, validates conflicts, and never invokes the physical callback. Explicit origin recommissioning retires the old epoch. Filesystem-backed restart and fault injection tests pass; OpenOS persistence, manual-after-ambiguity, and supervised lost-reply behavior are untested in game.
- **Required mitigation:** Journal in-flight and completed requests on the robot, cache completed results, and enter recovery-required state after an interrupted in-flight action.
- **Resolution criteria:** Duplicate completed requests return their original result without repeating the action; interrupted requests are not replayed automatically; and an unresolved executing retry reports unknown outcome rather than definite rejection in a supervised OpenOS test.

### OCIA-004: Controller and robot do not track pose

- **Status:** In progress
- **Area:** Navigation
- **Risk:** Construction planning cannot reliably map relative blueprint coordinates to physical robot actions.
- **Current evidence:** Pure relative-pose logic and robot-side durable pose exist and pass cardinal/turn/failure/ambiguity host tests. The controller probe validates and displays reported pose, but a durable authoritative controller deployment pose and in-game agreement tests do not exist yet.
- **Required mitigation:** Define a relative coordinate system and update controller and robot pose only after successful operations.
- **Resolution criteria:** Movement and turn tests produce matching controller and robot poses, including partial-operation failures.

### OCIA-005: Deployment progress is not durable

- **Status:** In progress
- **Area:** Persistence
- **Risk:** A program, computer, game, or host restart can lose the authoritative step and cause repeated or skipped construction.
- **Current evidence:** Robot request phase, pose, epoch, high water, and recent results use a checksummed append-only journal. Bounded compaction writes and verifies a checkpoint plus retained results using `.switch`, `.new`, `.old`, and same-filesystem renames; incomplete replacement artifacts fail closed. Inspection of the installed 1.8.8 JAR shows successful component close returns no value while an HDD-handle close exception can propagate; journal writes now catch that exception and mark persistence uncertain. Host restart/failure tests cover write, flush, raised close, replacement, and replay boundaries. The host installer now manages generated `/etc/ocia.cfg` files through an exact manifest entry, while fixture tests prove the journal, replacement artifacts, and unlisted files remain untouched. Controller deployment state is not implemented, and host tests cannot prove OpenOS, world-save, `fsync`-equivalent, or power-loss durability.
- **Required mitigation:** Persist versioned controller deployment state and robot execution state using replace-safe writes.
- **Resolution criteria:** Restart tests either resume from an unambiguous checkpoint or stop with an explicit recovery requirement.

### OCIA-006: Robot modem port opening is not restart-safe

- **Status:** In progress
- **Area:** Robot daemon
- **Risk:** Restarting `robotd.lua` can fail when port 4242 is already open.
- **Current evidence:** The repository daemon now checks `isOpen`, records whether it opened the port, and closes only its own open action. Repeated restart has not yet been exercised in OpenOS.
- **Required mitigation:** Check `modem.isOpen` before opening and define whether the daemon owns and closes the port.
- **Resolution criteria:** The daemon can be stopped and restarted repeatedly without a port-open assertion failure.

### OCIA-007: Controller modem port ownership is unclear

- **Status:** In progress
- **Area:** Controller transport
- **Risk:** `drive.lua` closes port 4242 on exit even when another program originally opened it.
- **Current evidence:** Repository `drive.lua` and `ociactl.lua` now track `openedHere` and close only when they opened the port. Concurrent programs still consume a shared event queue and must not be run together; in-game coexistence acceptance is pending.
- **Required mitigation:** Record whether the program opened the port and close it only when it owns that action, or centralize modem ownership.
- **Resolution criteria:** Exiting the manual driver does not disrupt another controller service using port 4242.

### OCIA-008: Robot hardware calls can terminate the daemon

- **Status:** In progress
- **Area:** Error handling
- **Risk:** An unexpected OpenComputers API exception can stop command processing and leave the controller waiting.
- **Current evidence:** New-protocol dispatch and Robot calls use protected calls. An injected exception leaves the executing journal, untrusted pose, and recovery-required result in host tests. Legacy calls are also protected, but actual component exceptions and daemon continuity remain untested in game.
- **Required mitigation:** Wrap dispatch and hardware calls with bounded error handling, record failures, and keep the daemon observable.
- **Resolution criteria:** Injected operation errors produce failure replies and do not silently terminate the daemon.

### OCIA-009: Any wireless sender can command the robot

- **Status:** In progress
- **Area:** Command authorization
- **Risk:** Another computer within range can move the robot or change the world.
- **Current evidence:** Repository `robotd.lua` accepts both OCIA and legacy packets only from the configured controller address and logs other senders. The ignored host configuration now records both confirmed modem identities and deterministically generates each machine's `/etc/ocia.cfg`; deployment of those generated files and the in-game foreign-sender test remain pending. This is routing protection, not authentication.
- **Required mitigation:** Configure an allowed controller address and reject construction traffic from other senders. Define an intentional pairing or recovery procedure.
- **Resolution criteria:** Commands from an unconfigured modem are logged and ignored.

### OCIA-010: Multi-step commands have coarse acknowledgments

- **Status:** In progress
- **Area:** Execution granularity
- **Risk:** A command such as `f 8` can partially succeed, but controller state depends on parsing a human-readable error string.
- **Current evidence:** OCIA autonomous requests expose only one-block movement and one-turn operations with structured results. Legacy manual commands retain counts 1–8 and coarse replies; they invalidate autonomous pose before physical execution. In-game pose/result verification is pending.
- **Required mitigation:** Use one physical operation per construction request or return structured completed-step data.
- **Resolution criteria:** Controller pose is updated from structured results without parsing prose.

### OCIA-011: Robot-carried material identity is not yet verified

- **Status:** Open
- **Area:** Inventory
- **Risk:** The controller can identify RS inventory, but the robot cannot yet prove which carried item or tool is in a slot during physical execution.
- **Current evidence:** Native RS `getItems()` has distinguished registry IDs and metadata successfully. Wheatley now boots with both an Inventory Upgrade and recognized `inventory_controller` component, but detailed internal/external slot inspection has not been exercised. The farm requires switching among several equipped tools.
- **Required mitigation:** For the platform prototype, use declared slots and an unconsumed comparison block. Probe Inventory Controller stack descriptions and slot behavior before terrain preparation, then validate every loaded material against the manifest.
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
- **Current evidence:** Energy is reported but not used as an execution precondition. A conduit-powered OpenComputers Charger has restored Wheatley successfully after a Lever supplied the required redstone activation signal. A Tier 2 Battery Upgrade is installed and boots, but its observed capacity and endurance have not been characterized.
- **Required mitigation:** Measure idle, movement, analyze, scan, excavation, and return energy costs; establish conservative preflight and reserve thresholds; and enter recovery before the reserve is exhausted. Charging-station verification is tracked by OCIA-035.
- **Resolution criteria:** The Battery's observed buffer is recorded, deployment is refused below the configured reserve, tested plans account for return energy, and low-energy execution stops while Wheatley can still reach or be recovered at the station.

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
- **Required mitigation:** Bind each plan to its survey, revalidate affected preconditions before apply, validate immediately before every physical action, and either deterministically replan or stop on drift. Consider site ownership only if concurrent deployments are introduced.
- **Resolution criteria:** A controlled terrain change after survey invalidates the stale plan; the controller produces a new plan or stops, and no obsolete destructive action executes.

### OCIA-019: Modded machines may require specialized placement or configuration

- **Status:** Open
- **Area:** Blueprint execution
- **Risk:** Generic block placement may produce the wrong orientation or fail to configure machines, addons, power, or item routing.
- **Current evidence:** The intended Potato farm contains modded machines and multipart logistics whose robot placement, orientation, and configuration behavior has not been validated.
- **Required mitigation:** Treat machine operations as typed blueprint actions and test each block against the installed mod versions before adding it to an automated blueprint.
- **Resolution criteria:** Every machine used by a production blueprint has documented placement, orientation, configuration, and verification behavior.

### OCIA-020: Network packet limits constrain protocol design

- **Status:** In progress
- **Area:** Wireless protocol
- **Risk:** Large plans or highly structured replies can exceed OpenComputers packet-size or packet-part limits.
- **Current evidence:** Default OpenComputers configuration limits packets to eight data parts and 8192 bytes. Protocol version 1 uses exactly eight parts and rejects encoded request/result payloads over 4096 bytes in host tests. Actual installed packet behavior remains untested.
- **Required mitigation:** Send bounded single-operation messages, serialize compact argument/result payloads, and validate payload size before transmission.
- **Resolution criteria:** Maximum supported requests remain within configured limits and oversized requests fail locally with a clear error.

### OCIA-021: Plant Interactor compatibility with Potatoes is unverified

- **Status:** Open
- **Area:** Farm operation
- **Risk:** The deployed farm may be constructed correctly but never harvest vanilla Potatoes.
- **Current evidence:** Industrial Foregoing 1.12.13 implements the Plant Interactor as a right-click harvester. The installed Quark configuration enables right-click harvesting and explicitly lists mature `minecraft:potatoes:7`, so compatibility is expected but not yet proven with the Interactor's fake player.
- **Required mitigation:** Test the installed Plant Interactor and Quark interaction against mature Potatoes. If it does not harvest them, use a compatible harvesting machine or select another supported crop.
- **Resolution criteria:** An installed-version test harvests a mature Potato, stores the drops, and leaves the field in the intended replanted state.

### OCIA-022: Inventory Controller tool management is operationally unverified

- **Status:** In progress
- **Area:** Robot hardware
- **Risk:** Terrain clearing and tilling require several tools, but component discovery alone does not prove that Wheatley can identify, equip, verify, replace, and return them safely.
- **Current evidence:** Wheatley has been successfully assembled and booted with Inventory and Inventory Controller Upgrades; OpenOS reports `inventory_controller` available. `equip()`, detailed inventory inspection, external access, and replacement-tool flow remain untested. Refined Storage, not the robot, will craft tools.
- **Required mitigation:** Test reversible `equip()` with an inexpensive tool, record internal/external slot structures, verify durability reporting, and exercise replacement and return through the selected dock inventory.
- **Resolution criteria:** The assembled robot can identify, extract, equip, use, replace, and return every tool required by the terrain-preparation plan.

### OCIA-023: Robot loading and Interface inventory mapping need an in-game probe

- **Status:** Open
- **Area:** Material staging
- **Risk:** Incorrect side or slot assumptions could prevent tool withdrawal, mix deployment supplies, or send returned and recovered items to a non-insertable inventory.
- **Current evidence:** Source investigation suggests an 18-slot combined Interface handler, but the installed mapping has not been exercised. Wheatley's existing dock Ender Chest is directly south of his North-facing resting pose. Separate EnderStorage supply and return frequencies are proposed but untested.
- **Required mitigation:** Test native RS extraction into an inside supply chest, transfer through the matching dock chest, robot loading after the required rotation, and a separate return chest feeding an RS Importer. Keep the farm-output white/white/blue frequency isolated.
- **Resolution criteria:** The selected topology reliably loads a known supply and tool, returns one test item, reconciles actual quantities at every inventory, avoids immediate re-import of supplies, and reports a full or invalid destination.

### OCIA-025: Refined Storage crafting API behavior is unverified

- **Status:** Open
- **Area:** Autocrafting integration
- **Risk:** The controller may misinterpret patterns, task handles, failure states, or completion and wait forever or provision the wrong quantity.
- **Current evidence:** `getPatterns`, `getPattern`, `hasPattern`, `scheduleTask`, `getTasks`, `getCraftingTasks`, and `cancelTask` are exposed, but none has been exercised. OpenOS displayed `scheduleTask(stack[, count[, canSchedule]])`; omitted-argument defaults and return behavior are unverified.
- **Required mitigation:** Discover a known cheap pattern, schedule a minimal craft, record returned structures and task transitions, and test missing-material and missing-pattern behavior.
- **Resolution criteria:** An installed-version test suite can distinguish accepted, active, successful, failed, unavailable, and cancelled crafting requests without treating craft completion as construction completion.

### OCIA-026: Native extraction semantics and partial fulfillment are unverified

- **Status:** Open
- **Area:** Material staging
- **Risk:** A query may report stock while extraction moves fewer or no items because of direction, adjacency, stack limits, or destination capacity.
- **Current evidence:** `extractItem(stack[, count[, direction]])` is exposed but has not been called. Omitted-argument defaults, direction constants, returned quantity, large-count behavior, and destination-full behavior are unknown.
- **Required mitigation:** Extract one vanilla Dirt into an adjacent ordinary chest, verify both inventories, then test partial, over-one-stack, and full-destination cases using installed direction constants.
- **Resolution criteria:** The controller records actual delivered quantity and distinguishes complete, partial, and failed extraction without assuming success from prior inventory data.

### OCIA-027: Returning items to Refined Storage is unverified

- **Status:** Open
- **Area:** Resource return
- **Risk:** Empty buckets, recovered blocks, unused supplies, and worn tools may be stranded or mistakenly reported as returned.
- **Current evidence:** The Interface input inventory and `pushItems`, `pullItems`, and generic inventory methods are exposed, but no insertion path has been tested.
- **Required mitigation:** Select a physical return path and verify one test item's transfer, RS inventory increase, rejection behavior, and full-storage handling.
- **Resolution criteria:** Returned quantities are observed in RS and reconciled against robot/staging counts; failed returns remain visible and recoverable.

### OCIA-028: Interrupted inventory operations have ambiguous outcomes

- **Status:** Open
- **Area:** Persistence and inventory transactions
- **Risk:** A restart or lost response between extraction/insertion and checkpointing can cause duplicate requests, resource loss, or incorrect accounting.
- **Current evidence:** No durable RS operation journal or reconciliation procedure exists, and mutation return semantics are not yet known.
- **Required mitigation:** Journal intent before mutation, record observed results after mutation, and reconcile RS, staging, and robot inventories before retrying an interrupted operation.
- **Resolution criteria:** Restart tests at each transaction boundary neither duplicate a transfer nor silently discard a discrepancy.

### OCIA-029: Dynamic material allocation and recovered-resource accounting are undefined

- **Status:** Open
- **Area:** Resource planning
- **Risk:** Concurrent stock changes, partial supply trips, or recovered excavation material can produce over-allocation, shortages, or an incorrect net bill of materials.
- **Current evidence:** The native inventory list is readable, but no reservation ledger or survey-derived manifest implementation exists.
- **Required mitigation:** Maintain separate stored, craftable, allocated, loaded, recovered, consumed, returned, and unaccounted quantities; record accounting completion separately from balance state; and initially limit provisioning to one active deployment. Any operator or policy acceptance must be a durable exception record.
- **Resolution criteria:** A deployment with at least one partial resupply and recovered Dirt reaches `balanced`, while an injected missing-item case reaches `discrepant` and cannot report unconditional mission success. An accepted discrepancy remains visible with its actor or policy and evidence.

### OCIA-030: Refined Storage availability and task failure can stall a deployment

- **Status:** Open
- **Area:** External service reliability
- **Risk:** Network power loss, disconnection, insufficient ingredients, insufficient storage, or a stuck craft can leave the controller waiting indefinitely or send an under-supplied robot.
- **Current evidence:** `isConnected()` and inventory enumeration work while the network is healthy; failure behavior has not been tested.
- **Required mitigation:** Add bounded waits, connectivity checks, task failure detection, clear operator diagnostics, and a safe paused state before physical execution or resupply.
- **Resolution criteria:** Each tested service failure stops or pauses safely, preserves deployment state, and can resume or abort without falsely completing the mission.

### OCIA-031: Deployment request ingress and identity are undefined

- **Status:** Open
- **Area:** Job submission
- **Risk:** Removing processing-pattern job detection leaves no formal contract for starting, identifying, or rejecting duplicate deployment requests.
- **Current evidence:** The controller is now authoritative, but the initial command interface and durable deployment-ID creation flow have not been selected. The Dead Bush may be an optional future trigger only.
- **Required mitigation:** Define an explicit controller-side submission command or file format, generate a durable deployment ID before physical work, and initially allow only one active deployment.
- **Resolution criteria:** Duplicate or stale submissions cannot start a second mission, and a deployment can be inspected and resumed independently of any RS crafting task.

### OCIA-032: Survey evidence may be misclassified by terrain interpretation

- **Status:** Open
- **Area:** Terrain surveying
- **Risk:** Treating obstruction detection, zero density, or a hardness estimate as exact block identity can produce the wrong excavation method, material estimate, or safety decision.
- **Current evidence:** Wheatley's Geolyzer has positively identified adjacent `minecraft:grass` through `analyze()` and produced meaningful 3D density scans. Repeated solid readings varied by as much as `0.087` in one trial; zero cells remained zero. Scan values did not return registry identities, and one repeat is insufficient to define thresholds.
- **Required mitigation:** Preserve raw samples and evidence levels for identified, compared, categorical, density, and unknown observations; probe representative terrain and modded blocks; never infer identity solely from density; and reject plans whose unresolved evidence is safety-critical.
- **Resolution criteria:** A read-only 9x10 survey reports the evidence type at every required observation, distinguishes Dirt and Stone only through proven methods, and prevents `READY TO APPLY` when a required classification remains unsafe or unknown.

### OCIA-033: Geolyzer coordinate mapping and production calibration are incomplete

- **Status:** In progress
- **Area:** Terrain surveying
- **Risk:** Incorrect flat-array order, axis rotation, zero-value interpretation, or noise tolerance can map real blocks to the wrong world coordinates or fabricate occupancy.
- **Current evidence:** Wheatley boots with the Geolyzer and OpenOS reports it available, resolving the original assembly-compatibility concern. Adjacent `analyze()` and three 3x3x1 scan layers succeeded. The results correlate with the known North-facing depot layout, but rotation behavior, exact array-to-coordinate transform, broader noise, range, energy cost, and special-block behavior remain unverified.
- **Required mitigation:** Repeat the asymmetric depot scan at all four headings, place known calibration blocks at selected offsets, characterize repeated measurements and energy use, and test air, zero-hardness blocks, liquids, foliage, entities, and representative modded blocks.
- **Resolution criteria:** Tests establish a deterministic local-to-world transform, documented array order, safe zero/unknown policy, measured operation cost, and calibration policy that reproduces the known fixture without treating density as identity.

### OCIA-034: Inaccessible terrain cannot be fully classified before excavation

- **Status:** Open
- **Area:** Survey completeness
- **Risk:** Hidden voids or unknown subsurface materials can invalidate fill-depth, recoverable-material, tool, and safety estimates after destructive work begins.
- **Current evidence:** Wheatley's detailed Geolyzer analysis is demonstrated but adjacent-only. Demonstrated volume scans report noisy density or hardness rather than registry identity. No proven method identifies every inaccessible block in the five-block support depth.
- **Required mitigation:** Mark inaccessible cells as estimated or unknown, use conservative support/material assumptions, verify newly exposed conditions during apply, and stop or replan when observations exceed the accepted survey contract.
- **Resolution criteria:** A test site containing a hidden void or unexpected subsurface block is either rejected during planning or discovered during bounded apply and causes safe replanning without exceeding the five-block fill policy.

### OCIA-035: Returning to the charging coordinates does not prove charging

- **Status:** Open
- **Area:** Charging and recovery
- **Risk:** The robot may reach the nominal station while misaligned, unpowered, or beside a Charger whose required redstone activation is disabled, then falsely report a successful return.
- **Current evidence:** The conduit-powered Charger directly north of Wheatley's resting pose restored him only after its Lever activated it. The dock geometry is observed, but autonomous return, alignment, energy-increase detection, charge waiting, and resume have not been tested.
- **Required mitigation:** Define a charging pose, verify alignment, sample energy over a bounded interval, handle a full battery separately, require a validated positive charging signal, and stop with a diagnostic when power or redstone is absent.
- **Resolution criteria:** Tests with Lever on, Lever off, incorrect alignment, active charging, and an already-full buffer distinguish successful charging from mere arrival; interrupted work resumes only from a durable safe state.

### OCIA-036: Bounded result retention and epoch lifecycle need OpenOS validation

- **Status:** In progress
- **Area:** Protocol retention
- **Risk:** If high water or epoch identity is not durable across compaction and recovery, a delayed duplicate could become executable; if the bounded journal still exceeds OpenOS memory, disk, or timing limits, Wheatley may fail closed during a mission.
- **Current evidence:** The source now uses explicit execution epochs, contiguous physical sequences, and a durable high-water marker. It retains a bounded recent window (default 32, maximum 64), safely rejects older active-epoch requests as `retired_request`, compacts the journal, and rejects prior-epoch packets after explicit origin recommissioning. Unresolved execution identity survives legacy manual recovery until that deliberate epoch rotation, while ordinary completed-result retirement remains bounded. Host tests run 1000 operations with bounded records/bytes and verify retained duplicates, retired requests, compaction restart, manual-after-ambiguity restart, and stale epochs. OpenOS resource use and filesystem behavior are unmeasured.
- **Required mitigation:** Validate bounded retention, compaction, retired-request rejection, and explicit epoch rotation on Wheatley's OpenOS filesystem. Measure journal size, memory, and persist time under the production configuration. Never create a new epoch except at an explicit safe boundary with physically reconciled pose.
- **Resolution criteria:** An in-game test demonstrates bounded storage across compaction, retained duplicates remain suppressed, retired active-epoch sequences cannot execute, a new epoch is created only through explicit origin recovery, and prior-epoch packets are rejected within measured memory/disk limits.

## Resolved Issues

### OCIA-017: Refined Storage completion can be acknowledged falsely

- **Status:** Superseded
- **Area:** Legacy job completion
- **Original risk:** Returning the Dead Bush before verification would complete an incomplete RS processing job.
- **Disposition:** Native RS integration replaced the token as the required deployment workflow. The controller now owns construction and mission state, and no Dead Bush is returned to complete a deployment. The risk remains relevant only if the optional legacy trigger is reintroduced.

### OCIA-018: Staging contents do not uniquely identify a request

- **Status:** Superseded
- **Area:** Legacy request detection
- **Original risk:** The continuously exported Dead Bush could not prove that a processing request had begun.
- **Disposition:** Staging contents no longer initiate deployments. Deployment intent is controller-owned; staged inventory is fulfillment for an identified deployment. Transfer identity and quantity risks are tracked by OCIA-026 through OCIA-029.

### OCIA-024: Refined Storage can complete before the robot mission ends

- **Status:** Superseded
- **Area:** Legacy completion semantics
- **Original risk:** The RS processing task could complete at token deposit while the robot later failed to return to charge.
- **Disposition:** RS task completion is now only a resource-provisioning event. Deployment state separately records construction verification, reconciliation completion and balance, verified charging return, and mission outcome; no `rs_acknowledged` milestone remains.
