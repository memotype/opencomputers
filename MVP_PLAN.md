# Potato Farm MVP Implementation Plan

This document is the actionable path from the working remote driver to the first complete autonomous Potato farm deployment. Durable architecture and safety rules remain in [CODEX.md](CODEX.md). Current test evidence and hardware state remain in [SCRATCH.md](SCRATCH.md). Risks and acceptance gates use the stable identifiers in [ISSUES.md](ISSUES.md).

The approved lifecycle is unchanged:

```text
blueprint desired state + surveyed observed state
    -> deterministic plan
    -> resource provisioning
    -> bounded apply operations
    -> resurvey and verification
    -> resource reconciliation
    -> verified return to charge
    -> mission outcome
```

## Capability Classification

Implementation decisions must preserve four evidence classes:

- **Demonstrated:** Observed successfully in the installed survival world.
- **Source-verified:** Present in the installed OpenComputers or Refined Storage implementation but not yet exercised successfully.
- **Proposed:** A design selected for testing but not yet proven.
- **Unknown:** Behavior that requires an experiment before it can safely influence implementation.

Current demonstrated foundations are remote robot movement, wireless acknowledgments, Charger activation and stationary charging, native RS connectivity and inventory enumeration, Wheatley's integrated APU GPU, Inventory Controller and Geolyzer component discovery, adjacent Geolyzer analysis, and small three-dimensional Geolyzer scans.

The RS mutation APIs, inventory transfer, tool swapping, autonomous pose tracking, survey coordinate transforms, terrain modification, machine placement, autonomous docking, and end-to-end recovery are not yet demonstrated.

## Feasibility Assessment

The Potato farm MVP is technically plausible with the installed mods and Wheatley's current assembly. No new mod is presently justified. The project has demonstrated the three hardest architectural interfaces at least at read-only or manual level: wireless physical control, terrain sensing, and native RS inventory access.

The remaining feasibility gates are operational rather than architectural:

| Capability | Assessment | Gate before full deployment |
|---|---|---|
| Terrain observation | Feasible; adjacent identity and volume density are demonstrated. | Calibrate coordinates, noise, zero values, energy, and safe routes. |
| Terrain planning | Feasible as pure controller logic. | Define deterministic data contracts and unknown-cell policy. |
| Excavation and fill | Likely feasible with Robot actions and installed tool control. | Verify `equip()`, durability, drops, inventory pressure, and per-block evidence. |
| Dynamic RS provisioning | API surface exists; read access is demonstrated. | Exercise crafting, extraction, partial delivery, insertion, and restart ambiguity. |
| Dock logistics | EnderStorage topology is physically plausible. | Demonstrate one-item supply and return without channel conflict. |
| 3x3 construction | Straightforward once verified placement and pose exist. | Complete correlated one-step execution and placement tests. |
| Potato field operations | Likely feasible but interaction-specific. | Test hoe, planting, bucket, lighting, and resulting block states. |
| Modded machinery | Plausible but not generic. | Test orientation, addon insertion, multipart logistics, RF power, and output. |
| Long mission energy | Improved by the installed Tier 2 Battery and working Charger. | Measure capacity/costs, reserve policy, docking, and charge verification. |
| Unattended recovery | Deliberately limited for MVP. | Durable safe stop, diagnostics, and manual reconciliation are sufficient initially. |

The most likely rabbit holes are modded multipart placement, Plant Interactor behavior through Quark's fake-player path, inventory/drop handling during excavation, and ambiguous physical outcomes after lost acknowledgments. Each is isolated behind a smaller acceptance test before the full farm milestone.

## Technical Dependency Chain

```text
addressed correlated protocol
    -> durable request state and one-step execution
    -> authoritative relative pose
    -> safe sensor and world-interaction primitives
    -> calibrated survey coordinate transform
    -> raw survey records
    -> interpreted observed terrain
    -> deterministic desired-state diff
    -> survey-derived material manifest
    -> verified RS extraction and dock transfer
    -> bounded terrain apply
    -> resurvey and convergence check
    -> farm-specific interactions
    -> resource reconciliation
    -> verified return and charging
```

Important dependency traps:

- A sophisticated survey is not useful until controller and robot pose agree.
- A large scan cannot be mapped safely until scan axes, result order, and rotation behavior are calibrated.
- A resource manifest cannot be trusted until raw observations and planning rules are deterministic.
- Reported RS stock is not delivered inventory; extraction and dock loading need separate evidence.
- Tool availability is not tool control; `equip()` and durability behavior must be tested before excavation.
- A physical operation cannot be retried safely merely because its acknowledgment was lost.
- A successful terrain plan does not prove that modded machines can be placed, oriented, configured, or verified.
- Arrival at the dock does not prove charging.

## Proposed Lua Structure

Keep the implementation small and explicit. Modules should return tables of functions and data; avoid a plugin framework, dependency injection container, or large object system.

### Shared modules

| Module | Responsibility |
|---|---|
| `lib/ocia/protocol.lua` | Versioned request/reply schemas, validation, compact serialization, and correlation fields. |
| `lib/ocia/pose.lua` | Coordinate and heading math with no component calls. |
| `lib/ocia/model.lua` | Validation helpers for observations, plans, manifests, and durable status values. |
| `lib/ocia/state.lua` | Versioned append-only journal, checkpoint loading, compaction, and replace-safe recovery boundaries. |

### Controller modules

| Module | Responsibility |
|---|---|
| `lib/ocia/transport.lua` | Addressed modem send/receive, timeouts, sender validation, and reply correlation. |
| `lib/ocia/blueprint.lua` | Load and validate desired-state blueprint data. |
| `lib/ocia/survey.lua` | Request survey primitives, preserve raw results, and transform robot-relative samples into deployment coordinates. |
| `lib/ocia/terrain.lua` | Interpret raw evidence into coordinate-indexed terrain observations without upgrading estimates into facts. |
| `lib/ocia/planner.lua` | Deterministic desired-versus-observed diff and ordered logical operations. |
| `lib/ocia/manifest.lua` | Gross requirements, estimated recovery, net requirements, and tool demand. |
| `lib/ocia/rs.lua` | Narrow wrapper around the verified `refinedstorage_interface` behavior. |
| `lib/ocia/ledger.lua` | Allocated, staged, loaded, recovered, consumed, returned, and unexplained quantities. |
| `lib/ocia/orchestrator.lua` | Deployment state machine and milestone transitions. |

### Robot modules

| Module | Responsibility |
|---|---|
| `lib/ocia/robot_ops.lua` | Protected single-step movement, detection, analysis, scan, compare, swing, use, and placement wrappers. |
| `lib/ocia/robot_state.lua` | Pose, energy, active deployment, in-flight request, and completed-result cache. |
| `lib/ocia/inventory.lua` | Internal slot descriptions, external inventory probes, loading, unloading, and quantity evidence. |
| `lib/ocia/tools.lua` | `equip()`, durability checks, expected-tool validation, and replacement requests. |
| `lib/ocia/energy.lua` | Preflight reserve, operation sampling, return budget, and charging verification. |

Programs should remain thin:

- `robotd.lua` dispatches protocol operations to robot modules and preserves the legacy manual command format during migration.
- `drive.lua` remains the manual recovery tool.
- A new controller program, provisionally `deploy.lua`, owns plan, apply, status, abort, and reconcile commands.

The controller should store large survey and plan data on disk rather than embedding it in modem packets or retaining every structure in memory. Wireless messages should carry one bounded operation or one chunk of survey data. OpenOS packet and memory limits make compact records and streaming preferable to transmitting an entire 9x10 three-dimensional map at once.

## Data Contracts

### Raw sensor record

Each raw measurement should contain enough provenance to reinterpret it later:

```lua
{
  surveyId = "...",
  sampleId = 42,
  sensor = "geolyzer.scan",
  robotPose = {x=0, y=0, z=0, heading="north"},
  localCoord = {x=1, y=-1, z=0},
  value = 0.58,
  sequence = 7
}
```

An `analyze` record preserves the returned table without discarding fields. A detect or compare record preserves the exact result and selected comparison sample.

### Interpreted observation

```lua
{
  coord = {x=1, y=-1, z=0},
  evidence = "identified", -- identified|compared|categorical|density|unknown
  state = "solid",
  name = "minecraft:grass",
  metadata = 0,
  hardness = 0.6,
  sourceSamples = {42},
  uncertainty = nil
}
```

Density values never populate `name`. Zero density never becomes `air` without corroborating evidence. Conflicting overlapping samples remain conflict records until an explicit interpretation rule resolves them.

### Logical plan operation

```lua
{
  id = 18,
  kind = "change", -- destroy|add|change|clearance|inspect
  coord = {x=1, y=0, z=2},
  before = {evidence="identified", name="minecraft:stone", metadata=0},
  after = {name="minecraft:dirt", metadata=0},
  preconditions = {...},
  physicalSteps = {...},
  materialDelta = {...},
  verification = {...}
}
```

One logical change may require several physical actions. The plan remains inspectable at the logical level while apply checkpoints every physical step.

## Initial Survey Strategy

### Calibration before mapping

Use the known dock geometry as a calibration fixture. Wheatley begins facing North with the Charger north, Ender Chest south, wall east, and open space west.

1. Scan the same asymmetric 3x3 layer while facing North, East, South, and West.
2. Record whether scan coordinates rotate with Wheatley or remain world-aligned.
3. Place or use known blocks at selected offsets to establish flat-array ordering.
4. Repeat unchanged scans enough times to characterize variation by material and distance; the observed `0.087` difference is one sample, not a threshold.
5. Measure energy before and after equal-volume scans and movement operations.
6. Confirm how entities, Wheatley's own cell, multipart blocks, liquids, foliage, and zero-hardness blocks appear.

Do not implement the world-coordinate transform until this test produces an unambiguous mapping.

### Survey layers

Separate three products:

1. **Raw scan volume:** Immutable density measurements plus pose and scan metadata.
2. **Observed terrain:** Coordinate-indexed evidence with surface candidates, clearance, support estimates, identities, and unknowns.
3. **Plan:** Desired-state differences and resource estimates derived by the controller.

This separation allows better calibration rules to reinterpret stored raw surveys without pretending the original sensor reported more than it did.

### Observation route

Start with one or a few stationary scans from known safe positions. A Geolyzer scan does not require line of sight, so an elevated route is useful only when it improves volume coverage, keeps Wheatley out of obstacles, or permits adjacent analysis; elevation is not automatically necessary.

The first 9x10 survey should:

- Scan a bounded vertical band covering the five-block support depth, target surface, crop clearance, and machinery clearance.
- Use overlapping stationary volumes only when one installed-version scan cannot cover the required band safely or within energy limits.
- Transform and merge results on the controller.
- Mark candidate surface elevation from density transitions as estimated until corroborated.
- Navigate only through cells proven traversable by local detection and pose checks.
- Use `analyze()` on safely reachable surface blocks and suspicious obstacles that materially affect the plan.
- Use known carried samples with compare operations when that is cheaper than repositioning for analysis.
- Leave inaccessible subsurface identities unknown while retaining density evidence and the five-block support estimate.

Perimeter observation is safer than crossing unknown terrain but may not provide adjacent access to every cell. A serpentine interior route should be introduced only after a safe surface corridor is established. If a representative site cannot be surveyed without entering an unverified hole or destroying a block, the read-only survey fails safely.

### Scan merge rules

- Key samples by deployment-relative coordinate after applying the calibrated transform.
- Preserve every raw sample; do not average away conflicting evidence.
- For density-only duplicates, retain count, minimum, maximum, mean, and spread for planning diagnostics.
- Prefer positive adjacent analysis over comparison, comparison over categorical detection, and categorical detection over density only when the observations address the same state and do not conflict.
- A newer observation does not silently erase older disagreement; it records supersession and reason.
- Revalidate operation preconditions immediately before apply because the survey is a snapshot, not a lock on the world.

## Implementation Milestones

These milestones refine, rather than replace, the phase summary in `SCRATCH.md`. The crosswalk is:

| Detailed milestone | `SCRATCH.md` phase |
|---|---|
| 1 | Phase 1 protocol |
| 2 | Phase 2 execution state plus hardware characterization |
| 3 | Phase 3 verified primitives |
| 4 | Phases 4–5 planner and 3x3 platform |
| 5 | Phase 6 RS validation and the dock portion of Phase 8 |
| 6 | Phase 7 read-only survey and plan |
| 7 | Small-scale entry to Phase 9 terrain apply |
| 8 | Phase 9 full terrain preparation |
| 9 | Farm-action portion of Phase 10 |
| 10 | Complete Phase 10 Potato farm deployment |

### Milestone 1: Addressed and recoverable command transport

**Status:** Implemented in the repository and host-tested on 2026-10-30; supervised OpenOS/Minecraft acceptance is pending. Do not treat this milestone as complete yet.

**Goal:** Execute one correlated, bounded request without breaking manual control.

**Prerequisites:** Current working `drive.lua` and `robotd.lua`.

**Implementation:** Protocol version 1, execution epochs and monotonic physical sequences, deployment ID, configured controller/robot addresses, sender validation, single-step operations, protected dispatch, restart-safe port ownership, an append-only execution journal with bounded recent results and compaction, relative pose, controller probe, and explicit local commissioning/recovery now exist in the disk snapshots. Legacy `(command, count)` handling remains available to `drive.lua`; legacy physical movement deliberately invalidates autonomous pose.

**In-game test:** Send addressed status, turn, and one-step movement requests. Delay or duplicate a request and restart the daemon with the port already open.

**Acceptance:** Only Wheatley executes the addressed command; replies correlate exactly; a duplicate completed request returns its cached result; malformed or unauthorized traffic changes nothing; legacy driving still works.

**Failure/recovery:** Timeout leaves the controller in an ambiguous state until status reconciliation. A restart from `prepared` records definite nonexecution if that resolution persists. A restart from `executing` reports unknown physical outcome, invalidates trusted pose, and never replays the request.

**Unresolved dependencies:** Controller and robot modem UUIDs must be recorded; the new daemon, append-only journal, compaction, epoch commissioning, actual modem behavior, duplicate and retired-request handling, movement, and recovery path require the supervised procedure in [MILESTONE1.md](MILESTONE1.md). OpenOS memory, disk, flush, rename, and timing behavior remain unmeasured.

### Milestone 2: Durable pose, energy, and hardware primitives

**Goal:** Establish truthful robot status and characterize installed upgrades at the dock.

**Prerequisites:** Milestone 1.

**Implementation:** Add relative pose transitions, checkpointing, energy sampling, Geolyzer wrappers, Inventory Controller read-only wrappers, tool equip wrapper, and structured evidence replies.

**In-game test:** Run controlled pose loops; enumerate internal and external inventories; inspect known slots; equip and restore a cheap stone tool; repeat calibrated scans; measure movement and scan energy; compare maximum energy with and without known charging states.

**Acceptance:** Controller and Wheatley agree on pose; installed component methods return recorded structures; tool swap is reversible and verified; battery capacity and operation costs are measured; errors do not terminate the daemon.

**Failure/recovery:** Any pose mismatch stops automation. Failed tool restoration leaves an explicit recovery state. No terrain is modified during hardware characterization.

**Unresolved dependencies:** Exact Inventory Controller side/slot behavior, Tier 2 Battery contribution, scan transform, noise distribution, and energy costs.

### Milestone 3: Verified one-block physical operations

**Goal:** Safely inspect, place, break, and interact with one controlled target.

**Prerequisites:** Milestones 1–2 and a supervised disposable test fixture.

**Implementation:** Add preconditions, selected-slot validation, tool validation, one swing/place/use operation, inventory deltas, adjacent `analyze`, comparison, and postcondition evidence.

**In-game test:** Exercise air, matching Dirt, wrong solid, liquid, foliage, empty slot, incorrect tool, and intentionally blocked targets.

**Acceptance:** Every operation returns structured before/after evidence; unexpected state prevents mutation; placement verifies material and inventory change; excavation reports recovered items and tool durability.

**Failure/recovery:** Lost reply makes the operation ambiguous; controller inspects before deciding whether to advance. It never blindly repeats a destructive call.

**Unresolved dependencies:** Actual block-drop pickup behavior, tool wear semantics, and safe handling of modded or unbreakable blocks.

### Milestone 4: Standalone 3x3 Dirt platform

**Goal:** Complete the existing low-level construction vertical slice.

**Prerequisites:** Milestones 1–3.

**Implementation:** Minimal blueprint, deterministic serpentine route, nine Dirt placements, per-step checkpoints, and final coordinate verification.

**In-game test:** Build above known support from a known pose; inject an obstruction, a low-energy stop, and a lost reply in separate supervised runs.

**Acceptance:** All nine cells match desired state; pose and material counts reconcile; failures stop at the exact operation with manual recovery available through `drive.lua`.

**Failure/recovery:** Resume only from an unambiguous checkpoint or after operator reconciliation.

**Unresolved dependencies:** None beyond the verified primitive behavior; RS and autonomous loading remain out of scope.

### Milestone 5: Native RS and dock supply loop

**Goal:** Move one known item from RS to Wheatley and one item back without confusing supply and return flows.

**Prerequisites:** Milestone 2 inventory probes and existing Phase 6 RS API tests.

**Implementation:** Verify `getItem`, patterns, cheap craft scheduling, task monitoring, `extractItem`, insertion, partial fulfillment, and transaction journaling. Test the proposed inside RS Interface to supply Ender Chest path and the outside dock chest. Evaluate a distinct return frequency feeding an RS Importer.

**In-game test:** Extract one vanilla Dirt to the supply channel, load exactly one item into Wheatley, unload one test item through the return channel, and verify all inventory deltas. Repeat with full destination and insufficient stock.

**Acceptance:** Actual transferred counts reconcile at RS, staging, Ender Chest, and robot; supply is not immediately re-imported; return does not contaminate the farm-output white/white/blue frequency.

**Failure/recovery:** Journal intent before mutation and reconcile all visible inventories after timeout or restart. Partial delivery never becomes a full manifest.

**Unresolved dependencies:** Final chest placement, EnderStorage color frequencies, RS direction constants, Importer behavior, and whether one or two dock inventories are operationally simpler.

### Milestone 6: Read-only 9x10 survey and plan

**Goal:** Survey a representative uneven footprint and produce a deterministic plan without modifying blocks.

**Prerequisites:** Milestones 1–2 and calibrated scan mapping.

**Implementation:** Raw scan persistence, coordinate transforms, overlapping-scan merge, adjacent analysis route, terrain interpretation, blueprint diff, unsafe/unknown gating, and inspectable plan output.

**In-game test:** Survey a supervised uneven test site containing elevation changes, Dirt or Grass, Stone, foliage, a shallow hole, a deeper unsupported condition, and at least one deliberately ambiguous cell.

**Acceptance:** Report contains coordinate-indexed observations, excavation, fill, replacement, clearance, estimated recovery, additional resources, unknowns, and blockers. Replanning the same input is byte-for-byte or semantically deterministic. No world-changing operation occurs.

**Failure/recovery:** Unsafe navigation or insufficient evidence stops the survey or produces `NOT READY`. Partial raw data remains inspectable and cannot authorize apply.

**Unresolved dependencies:** Practical scan coverage, safe observation routes, thresholds, and how much positive identification is necessary for the MVP policy.

### Milestone 7: Small terrain plan/apply/resurvey loop

**Goal:** Prove reconciliation on a tiny controlled patch before scaling to 9x10.

**Prerequisites:** Milestones 3, 5, and 6.

**Implementation:** Pre-apply drift check, ordered destroy/add/change actions, tool and material preflight, actual recovery tracking, resupply request, and verification resurvey.

**In-game test:** Use a small patch with one raised block, one shallow hole, one wrong surface, and one clearance obstruction. Change one cell after planning in a separate run.

**Acceptance:** Stale plan is rejected; accepted plan converges the patch; actual resource deltas are recorded; resurvey reports no supported differences.

**Failure/recovery:** Stop on tool break, unexpected block, inventory full, low reserve, or ambiguous action. Resume only after survey and ledger reconciliation.

**Unresolved dependencies:** Drop collection, inventory overflow policy, tool replacement timing, and dynamic resupply latency.

### Milestone 8: Autonomous 9x10 terrain preparation

**Goal:** Survey, plan, provision, apply, and verify the full Potato-farm footprint.

**Prerequisites:** Milestone 7 and demonstrated return-to-dock navigation reserve.

**Implementation:** Scale the same pipeline to vegetation removal, excavation, five-block-limited fill, Dirt surface replacement, crop clearance, machinery-row clearance, multiple supply trips, and balanced resource reconciliation.

**In-game test:** Prepare a supervised representative uneven site. Include at least one tree or foliage obstruction, recoverable Dirt, non-Dirt surface, shallow fill, and a controlled five-block-limit failure in a separate rejected site.

**Acceptance:** Prepared 9x10 surface and clearance converge to the terrain target; unsupported sites are rejected; resource ledger balances or records a non-success discrepancy; Wheatley returns to the charging pose and proves charging.

**Failure/recovery:** Durable checkpoints identify the last physical operation. Manual recovery remains acceptable, but the system must diagnose pose, plan step, inventory, tool, energy, and discrepancy state.

**Unresolved dependencies:** Sustained energy budget, chunk-loading operating envelope, multiple resupply trips, and autonomous dock alignment.

### Milestone 9: Farm-specific interaction primitives

**Goal:** Prove each farm operation individually on prepared test fixtures.

**Prerequisites:** Verified one-block operations and tool swapping.

**Implementation:** Typed actions for hoe use, Potato planting, bucket use, machine placement/orientation, Range Addon insertion, sneaky multipart placement, Ender Chest placement, and RF transmitter placement.

**In-game test:** Test each action independently against the installed mod versions. Grow and harvest mature Potatoes with the Plant Interactor and verify output reaches the intended chest without changing its configured frequency.

**Acceptance:** Each action has documented preconditions, result evidence, failure behavior, and restoration procedure. Plant Interactor compatibility and output flow are demonstrated, not assumed.

**Failure/recovery:** A failed specialized action stops the farm phase without invalidating verified terrain preparation. Manual correction is recorded before resume.

**Unresolved dependencies:** Quark fake-player harvesting behavior, addon GUI interaction, multipart placement semantics, light level, RF delivery, and functional machine verification.

### Milestone 10: Complete Potato farm deployment

**Goal:** Execute the approved lifecycle from deployment request through verified charging return.

**Prerequisites:** Milestones 1–9.

**Implementation:** Compose the verified modules and actions under the controller state machine. Do not add new generic abstractions during this milestone.

**In-game test:** Submit one supervised farm deployment at a selected undeveloped site. Preserve logs, survey, plan, manifest, checkpoints, verification results, ledger, and mission outcome.

**Acceptance:** Terrain converges; water, 80 tilled positions, 80 Potatoes, machinery, addon, logistics, power, and output behavior verify; ledger is balanced or explicitly non-successful; Wheatley returns and charging verifies. Any unsupported verification remains visible and prevents an unconditional success claim.

**Failure/recovery:** Stop at the first failed invariant. Report construction, resource, pose, inventory, energy, and recovery status independently. No Dead Bush acknowledgment is required.

**Unresolved dependencies:** Only issues explicitly accepted for the supervised MVP may remain; their acceptance must be recorded before apply.

## Recovery Matrix

| Failure | Initial MVP behavior |
|---|---|
| Lost wireless reply | Query request/result cache; otherwise mark physical outcome ambiguous and stop. |
| Pose mismatch | Stop immediately; establish pose manually and record reconciliation. |
| Restart during physical operation | Load journal, mark in-flight action ambiguous, inspect before resume. |
| RS extraction failure or partial delivery | Record actual count, keep manifest unsatisfied, retry only after inventory reconciliation. |
| Missing craft ingredients or pattern | Pause before departure with a specific provisioning diagnostic. |
| Tool breaks or wrong tool is equipped | Stop before the next mutation, request replacement, and verify equip. |
| Inventory unexpectedly full | Stop collection/apply, report slot state, unload or reconcile manually. |
| Unbreakable or unknown block | Stop and mark the plan blocked; never substitute indiscriminate excavation. |
| Energy below reserve | Stop work while return remains possible and enter return/recovery workflow. |
| Chunk unload | Initial unattended operation is unsupported until the operating envelope is tested. |
| Charger disabled or misaligned | Keep mission recovery-required; arrival alone does not satisfy return. |
| World changed after planning | Invalidate affected plan preconditions and replan or stop. |

## Immediate Coding Milestone

Milestone 1 code is implemented and host-tested: 26 Lua 5.3 tests with 6262 assertions pass after the final hardening pass on 2026-10-30. The next gate is supervised deployment and the in-game acceptance procedure in [MILESTONE1.md](MILESTONE1.md), not more protocol scope.

After that acceptance passes, proceed to Milestone 2 hardware characterization and durable controller-side pose/session work. Do not add Geolyzer routing, RS calls, planning, or construction until the transport's actual OpenOS filesystem, modem, duplicate, timeout, and recovery behavior is recorded.

## Immediate In-Game Experiments

Hardware experiments can proceed in parallel with protocol development because they do not require autonomous apply:

1. Enumerate Inventory Controller methods and record internal/external slot descriptions at the dock.
2. Equip and restore one inexpensive tool; record inventory and equipped-state evidence.
3. Calibrate Geolyzer scan axes and returned array order across all four headings.
4. Repeat known-volume scans enough times to characterize noise and zero readings without inventing a universal threshold.
5. Measure energy deltas for idle, movement, `analyze`, and equal-volume scans; characterize the Tier 2 Battery's observed maximum buffer.
6. Load one expendable item from the dock Ender Chest and return it.
7. Complete native RS Tests A through F with cheap items and a dedicated staging inventory.
8. Test Charger verification with Lever on, Lever off, incorrect alignment, active charging, and full buffer.

Each experiment should record the exact command, physical arrangement, returned values, inventory or energy before and after, and whether the result is demonstrated, source-verified, proposed, or still unknown.
