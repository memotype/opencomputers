# Working Memory and Roadmap

This file contains current planning, progress, decisions under consideration, and handoff context. It is intentionally stateful and may be rewritten as the project evolves.

The evergreen project purpose, architecture, and engineering constraints are defined in [CODEX.md](CODEX.md). Known defects and risks are tracked by stable identifiers in [ISSUES.md](ISSUES.md). The milestone dependency tree, module boundaries, survey design, recovery matrix, and farm implementation path are maintained in [MVP_PLAN.md](MVP_PLAN.md). Do not duplicate durable design rules here when they belong in `CODEX.md`, and do not close a risk here without updating `ISSUES.md`.

## Current State

- The repository contains project-owned OpenOS source trees organized as `machines/controller` and `machines/robot`; it no longer treats world-specific full HDD snapshots as source.
- Controller program: `machines/controller/home/drive.lua`
- Robot program: `machines/robot/home/robotd.lua`
- Wireless port: `4242`
- Milestone 1 command transport, relative-pose math, append-only robot execution journaling, bounded result retention, and journal compaction are implemented, host-tested, and installed on the live HDDs. Core supervised transport, movement, duplicate/conflict handling, commissioning, and normal restart tests passed on 2026-10-30; compaction and fault-injection acceptance remain pending, so Milestone 1 is partially accepted rather than complete.
- The remaining Milestone 1 compaction and fault-injection acceptance is deliberately deferred while the project prioritizes a supervised, playable construction vertical slice: Wheatley's first 3x3 Potato patch. Milestone 1 is not complete.
- Navigation MVP Stage 1 is implemented as the pure controller module `lib/ocia/nav.lua`. It plans minimum-cost nominal routes from any explicit trusted pose, uses backward movement where beneficial, remains independent of OpenComputers/runtime state, and passes exhaustive bounded host-oracle checks. It is not in the deployment manifest and has not been installed or exercised in Minecraft. Stage 2 controller mission persistence is not implemented.
- `deploy.lua` provides explicit allowlist deployment to controller, robot, or both. It defaults to dry run, compares bytes, backs up replaced files under `.deploy-backups/`, stages same-directory replacements, and verifies installed bytes. The corrected prototype manifest is now 10 controller files and 11 robot files, including one generated `/etc/ocia.cfg` per role; journal state remains excluded.
- `deploy.local.lua` is the ignored, authoritative local mapping from logical roles to one world save, two HDD UUIDs, and two confirmed modem UUIDs. The committed `deploy.local.lua.example` contains placeholders only.
- The full 18-entry manifest is installed in the live world. Both generated `/etc/ocia.cfg` files loaded successfully in OpenOS, and a post-apply dry run reported all 18 entries `UNCHANGED`.
- The 21-entry one-pass Potato prototype demonstrated adjacent journaled till-and-plant behavior in the single-cell and two-cell stages. Two full 3x3 attempts then stopped safely on Dirt outside the plot, exposing the old perimeter route's excessive clearance requirement. Its parameterized reverse-serpentine replacement was deployed and completed the supervised 3x3 patch successfully in game. [POTATO_PATCH.md](POTATO_PATCH.md) is the operator runbook.
- Wheatley has demonstrated adjacent block analysis and three-dimensional Geolyzer scans, but no autonomous survey route or coordinate mapper exists yet.
- The factory already has a Forestry Multifarm producing apples.
- The first full farm target is now a conventional Potato farm. Sugar Cane and other special crops are deferred to crop-specific blueprints.
- `CODEX.md`, `ISSUES.md`, and this roadmap are the first repository documentation added during the current work.

### Development environment

- Physical host: Ubuntu 26.04 with KDE Plasma.
- Development tools: VS Code and Codex.
- The local Minecraft world and controller/robot HDD UUIDs are intentionally not recorded here; `deploy.local.lua` supplies them for each developer.
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

The construction robot is named **Wheatley**. He has been rebuilt through the Electronics Assembler, boots successfully, and currently contains:

- Tier 2 APU.
- Two Tier 2 memory modules.
- Tier 2 2 MB HDD with OpenOS.
- Lua BIOS EEPROM.
- Tier 1 screen.
- Keyboard.
- Tier 2 Wireless Network Card.
- Inventory Upgrade.
- Inventory Controller Upgrade.
- Geolyzer.
- Tier 2 Battery Upgrade.
- Internal disk drive.

The former separate Tier 1 Graphics Card was removed because the Tier 2 APU already supplies GPU functionality. Wheatley booted normally with working screen and keyboard, and this probe succeeded:

```lua
c = require("component")
print("GPU:", c.isAvailable("gpu"))
-- GPU: true

print("Geolyzer:", c.isAvailable("geolyzer"))
-- Geolyzer: true

print("Inventory Controller:", c.isAvailable("inventory_controller"))
-- Inventory Controller: true
```

Do not restore the redundant Graphics Card to the required configuration. The robot can be disassembled with the OpenComputers Disassembler, but disassembly and reassembly are expensive and inconvenient. The current configuration proves that the Geolyzer, Inventory Controller, and Tier 2 Battery fit and boot together; additional upgrades still require a demonstrated need and capacity check.

Component discovery does not prove method behavior. Battery capacity/endurance, scan and excavation energy cost, Inventory Controller inspection, `equip()`, automatic tool swapping, loading/unloading, sustained navigation, and autonomous charging return remain unverified unless recorded below.

The charging station now has verified hardware:

- OpenComputers Charger.
- Existing Ender IO energy-conduit supply.
- Lever supplying the Charger's activation signal.

In-game testing showed that adjacency and conduit power were insufficient while the Charger lacked redstone. After a Lever was installed and activated, the Charger restored enough Robot energy for it to boot normally. This verifies stationary charging and the normal-mode redstone requirement, not autonomous docking, alignment, charge detection, target-level waiting, or deployment resume.

### Wheatley's depot

Wheatley's observed resting pose is outdoors beside the factory wall, facing North:

```text
                     North (-Z)
                         |
                    [ Charger ]
                         |
West (-X)           [ Wheatley ]           East (+X)
open space                                  factory wall
                         |
                  [ Ender Chest ]
                         |
                     South (+Z)
```

- The Charger is directly in front of Wheatley and has the activating Lever.
- The existing EnderStorage chest is directly behind him.
- The factory wall is directly east; west is open.
- Grass Blocks are beneath the robot.
- The wall uses Chiseled Stone or factory-style blocks.

This asymmetric geometry is a useful fixed fixture for calibrating Geolyzer array order, axes, heading behavior, and density readings. It also means Wheatley must rotate or use a verified side interaction before loading from the chest behind him.

### Working remote control

`drive.lua` provides the following interactive controller commands:

- `f`, `b`, `u`, and `d` move forward, backward, up, and down.
- `l` and `r` turn left and right.
- `status` requests robot status.
- `q` or `quit` exits the driver.
- Movement accepts an optional count from 1 through 8, such as `f 4`.

The legacy path remains `(command, count)` with reply `("result", command, ok, detail, energy, capacity)`. The repository version of `robotd.lua` also supports the isolated OCIA version 1 protocol, addressed single-operation dispatch, durable duplicate suppression, and explicit recovery state. Core legacy compatibility, OCIA status/movement, retained duplicate suppression, conflict rejection, and normal restart behavior are now demonstrated in Minecraft; the controlled fault cases remain pending.

This path has been tested successfully in Minecraft. For example, `drive> f 4` returned `OK: OK`, reported battery state, and physically moved the robot four blocks.

The controller originally asserted an unconditional `modem.open(4242)`, which failed when the port was already open. Repository versions of `drive.lua`, `ociactl.lua`, and `robotd.lua` now check `modem.isOpen(4242)` and close the port only when that process opened it. In-game acceptance demonstrated an idle `robotd` interruption and normal restart without a port-open assertion, resumed wireless status service, and sequential `ociactl`, `drive`, then `ociactl` use. The hard interruption emitted a stack trace rather than shutting down gracefully; concurrent event consumers, concurrent port ownership, and broader ownership/interruption edge cases remain untested under OCIA-006 and OCIA-007.

Do not replace or substantially rewrite this working control path without inspecting and preserving its recovery value.

### Milestone 1 implementation partially accepted in game

Implemented logical source paths:

- Shared `lib/ocia/config.lua`, `pose.lua`, and `protocol.lua` on both disks.
- Controller `lib/ocia/transport.lua`, `home/ociactl.lua`, and compatible `home/drive.lua`.
- Robot `lib/ocia/state.lua`, `executor.lua`, `legacy.lua`, `home/robotd.lua`, and `home/ocia-recover.lua`.
- Address placeholders and runtime limits in `etc/ocia.cfg.example` on both disks.
- Pure host suite in `tests/run.lua`; operational contract and supervised procedure in [MILESTONE1.md](MILESTONE1.md).

Protocol version 1 uses eight modem parts and a bounded encoded payload. It supports read-only `status` plus one-operation turns, moves, and the supervised farming interactions. The controller unicasts to the configured robot, validates the reply sender and correlation fields, and reports `succeeded`, `failed`, or `unknown`; a timeout is `unknown`.

Physical requests use `p:<execution-epoch>:<monotonic-sequence>`. Explicit origin commissioning creates the epoch and begins at high water zero. Before a physical call, Wheatley appends `prepared`—which allocates and advances the high-water sequence—and then `executing`. A completed record preserves the result and resulting pose. Restart from a healthy `prepared` record appends a definite nonexecution result; restart from `executing`, an operation exception, or failure to persist completion becomes `recovery_required` with untrusted pose and an unknown physical outcome.

The final hardening passes corrected two certainty defects. First, a matching retry of an unresolved `executing` request was classified as `rejected / retired_request` because the handler consulted high water before the in-flight record. Second, a durable legacy-manual record erased that unresolved identity, allowing the same false classification after manual recovery and restart. The executor now preserves and validates matching versus conflicting unresolved identity through manual recovery, reports `recovery_required / physical_outcome_unknown` for `executing`, and never calls the physical operation again. Manual movement remains available but leaves pose untrusted. Failure to persist a prepared-request resolution also remains recovery-required and non-executable; only explicit origin recommissioning retires the old epoch and its unresolved request.

Full results are bounded by `recent_results` (default 32, maximum 64). Older results may be retired, but the epoch and high-water marker keep their sequences non-replayable. The journal compacts at configured record or byte thresholds (defaults 128 records or 65536 bytes) into a verified checkpoint plus retained results. Explicit recovery at a physically verified origin creates a new epoch; packets from prior epochs are rejected as stale.

Host result on 2026-10-30: the prior hardening pass ended at 26 tests / 6262 assertions. This edge-case pass began with the same clean baseline. Adding the manual-recovery regression before the implementation fix reproduced the concern as 1 failure in 28 tests / 6280 assertions: the post-restart retry returned `retired_request`. After correction and regression expansion, `tests/run.lua` passed 29 tests / 6350 assertions in an Alpine 3.20 Lua 5.3 container.

The installed `OpenComputers-MC1.12.2-1.8.8+8da357f.jar` was inspected directly for close semantics. The filesystem component's successful `close` callback returns no values, and the OpenOS buffered handle therefore normally returns `nil` on success; `nil` cannot be treated as a failure indicator. The HDD-backed handle calls `RandomAccessFile.close()`, and a raised close exception propagates through the component invocation. Journal writes now catch that exceptional path and fail closed as an uncertain write; journal verification also rejects a raised close error. Host fault tests cover close exceptions at `prepared`, `executing`, `completed`, and compaction boundaries. This handling does not provide `fsync`, power-loss durability, or proof of real OpenOS behavior, which remain in-game acceptance concerns.

Deployment installer result on 2026-10-30: `tests/deploy_test.lua` passes 25 tests / 152 assertions with Lua 5.3 and LuaFileSystem. Fixtures cover disk and modem validation, deterministic template rendering, dry-run purity, role selection, generated create/update/unchanged behavior, byte-preserving backups, journal and unlisted-file preservation, idempotence, unsafe paths, nonzero CLI errors, and injected staging/backup/replacement failures. Those fixture results used no live world; the subsequent supervised session below separately deployed and loaded the generated configuration.

### Supervised Potato-patch vertical slice: 2026-10-31

Development priority shifted temporarily from exhaustive Milestone 1 acceptance to getting Wheatley visibly building. The first 20-file farm prototype deployed cleanly and was byte-idempotent. Its first apply was rejected locally because the controller had cached an older protocol module; after the controller reboot, Wheatley's still-running daemon rejected the new operation until Wheatley was also rebooted. Filesystem visibility did not replace already-loaded Lua modules.

With both machines current, request `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:11` reached `till_down` and completed as definite `failed / operation_failed`; the controller stopped before moving or planting. Local inspection showed `robot.durability()` at `1.0`, a visibly equipped Stone Hoe, and `geolyzer.analyze(sides.down)` identifying the target as `minecraft:grass` metadata 0 with `snowy=false`.

From an adjacent pose facing suitable Grass, the manual REPL call `robot.use(sides.down)` visibly converted the forward soil to WAILA-identified `minecraft:farmland`. Its return values were not captured. This proves the physical forward/downward interaction, not an autonomous journaled operation; it did not move Wheatley or change tracked pose. The directly-downward failure is likely related to Wheatley occupying the future crop space, but that internal cause is not independently proven.

The journaled `till_forward_down` follow-up then succeeded as request `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:15`, returned `operation_succeeded / item_placed`, left Wheatley's pose unchanged, and visibly produced WAILA-identified Farmland. The eight-operation aerial `single-plant` route also completed and visibly produced a Potato crop at 0% growth, proving `plant_down` but exposing needless navigation.

After removing that crop, the operator stopped `robotd`, selected slot 1 in the local Lua REPL, and ran `robot.place(sides.down)` from the same adjacent crop-height pose. It returned `true, nil`, consumed one Potato, and produced another WAILA-identified Potato crop at 0% growth. This manual action was outside OCIA and did not change tracked pose. It decisively removed the need for overhead planting.

The adjacent one-pass source was subsequently deployed, and the single-cell and two-cell stages completed successfully in game. Two attempts at the old 57-command 3x3 perimeter route then encountered surrounding Dirt. The first stopped at request sequence 63 on a definite `move_forward / operation_failed / solid` after 20 of 57 commands, with 3 of 9 cells tilled and planted and trusted pose `(-2,0,-2)` North. The second stopped at sequence 101 with the same definite movement failure after 33 of 57 commands, with 5 of 9 cells tilled and planted and trusted pose `(-5,0,-3)` West. In both cases the executor stopped without retrying, retained its trusted pose, and left the successfully planted crops in place. These were route-clearance failures, not failures of the farming primitives or journal.

The controller source now replaces that perimeter route with a dimensioned reverse-serpentine generator. It walks into only unplanted crop spaces, farms forward/downward, and backs through the remaining unplanted cells before exiting beyond the final cell. Width and depth default to 3, each is limited to 1–16, and the plot is limited to 64 cells. The 3x3 fixture follows `(0,0)`, `(0,1)`, `(0,2)`, `(1,2)`, `(1,1)`, `(1,0)`, `(2,0)`, `(2,1)`, `(2,2)` and uses 34 physical commands, ending outside at local `(2,3)` facing South. The controller still requires live ready/trusted status, previews without physical requests, requires `FARM`, and stops on non-success or uncertainty. After deployment, the reverse-serpentine 3x3 route completed successfully in the supervised Minecraft test. See [POTATO_PATCH.md](POTATO_PATCH.md).

Host verification for the reverse-serpentine revision passed `40 tests, 8100 assertions, 0 failures`; deployment fixtures remained `26 tests, 160 assertions, 0 failures`. All Lua sources compile with Lua 5.3. No live journal or world file was modified during implementation.

### Milestone 1 Supervised In-Game Acceptance Session: 2026-10-30

This session exercised the installed Milestone 1 software in the established survival world using Minecraft 1.12.2, The 1.12.2 Pack 1.6.6, OpenComputers `1.8.8+8da357f`, OpenOS 1.8.8, Lua 5.3, the Tier 2 stationary controller, and Wheatley with Tier 2 wireless networking on port 4242. Both machines have approximately 768 KiB RAM. The Ubuntu 26.04 host deployed directly into the world-save HDD directories with `deploy.lua` while Minecraft remained running.

The working installed command for modem discovery was:

```sh
components modem
```

`components -l modem` displayed usage information on this OpenOS installation and must not be used in the runbook. The Lua alternative also remains valid:

```sh
lua -e 'print(require("component").modem.address)'
```

The discovered machine identities were recorded only in ignored `deploy.local.lua`; no local disk/modem UUID or world path belongs in tracked documentation.

#### Deployment and generated configuration

Before apply, the 18-entry dry run reported:

| Action | Controller | Robot | Total |
|---|---:|---:|---:|
| `UNCHANGED` | 6 | 8 | 14 |
| `UPDATE` | 1 | 1 | 2 |
| `CREATE` | 1 | 1 | 2 |
| Total | 8 | 10 | 18 |

The updates were the two role-specific `etc/ocia.cfg.example` files; the creates were the generated controller and robot `etc/ocia.cfg` files. The operator ran `lua5.3 deploy.lua --apply`. The installer reported all four changed files installed and verified, and created a backup run for the replaced templates. A subsequent `lua5.3 deploy.lua` reported all 18 entries `UNCHANGED` and made no changes.

```text
INSTALLED controller etc/ocia.cfg.example
INSTALLED controller etc/ocia.cfg (generated)
INSTALLED robot etc/ocia.cfg.example
INSTALLED robot etc/ocia.cfg (generated)
Apply complete: 4 file(s) installed and verified.
```

**Result: passed.** This demonstrated the real role-to-HDD mapping, generated configuration installation, post-copy verification, content idempotency, and preservation of the other 14 files. It did not exercise live-world installer fault handling or arbitrary crash consistency; those remain host-fixture evidence only.

#### Initial fail-closed state and commissioning

The first `robotd` start loaded the installed modules and generated configuration, validated the local modem, listened on port 4242, and reported:

```text
Autonomous mode: recovery_required
Startup reconciliation: uninitialized
```

This was the expected uncommissioned state. With the daemon stopped, `ocia-recover show` reported untrusted placeholder pose `(0,0,0)` North, empty epoch, high water `0`, no retained results, and an uninitialized zero-record journal. No physical request had executed.

The operator physically verified Wheatley at the charging origin facing North, with the Charger north, Ender Chest south, and factory wall east. `ocia-recover reset-origin` required the literal `RESET` confirmation and created the first epoch:

```text
5257242e-2809-4721-a076-560475398dcc
```

An independent `ocia-recover show` then reported `ready`, trusted `(0,0,0)` North, high water `0`, zero retained results, and a healthy generation-1 journal with one record and 213 bytes. This is durable OpenOS readback after a normal command completion, not proof of power-loss or interrupted-write durability.

#### Daemon interruption convention

Ordinary `Ctrl+C` did not stop `robotd` while it was blocked in `event.pull("modem_message")`. On this installation, `Ctrl+Alt+C` interrupted it and returned to the shell with an `interrupted` stack trace near the event loop. This is a hard operational interrupt, not a graceful shutdown implementation and not evidence of journal corruption. It was used only while the daemon was idle.

#### First OCIA status exchange

After restart, `robotd` reported `ready`. Running `ociactl` with no operation returned `Certainty: succeeded`, `Status: succeeded`, trusted `(0,0,0)` North, energy `35499/35500`, memory `493066/786432`, the first epoch at high water `0`, and a healthy one-record/213-byte generation-1 journal. Wheatley did not move and the physical sequence remained zero.

**Result: passed.** Addressed request/reply transport, parsing, diagnostics, configured identities, and read-only sequence behavior worked in game. Foreign-sender rejection and multiple-robot isolation were not tested.

#### Legacy compatibility, durable pose invalidation, and recommissioning

The legacy driver ran `l`, `f 2`, `status`, then `q`. Wheatley physically turned left and moved two blocks West; the driver returned successful legacy replies and battery readings. The legacy `READY` status is its own convention and does not mean autonomous pose remained trusted.

A following `ociactl` status reported `recovery_required`, untrusted last-recorded `(0,0,0)` North, the first epoch still at high water `0`, a healthy journal with three records/293 bytes, and no retained physical results. Legacy movement therefore invalidated autonomous pose without consuming an autonomous sequence.

The operator used legacy controls to return Wheatley physically to the dock facing North. After an idle `Ctrl+Alt+C`, `ocia-recover show` still reported `legacy manual movement`, untrusted pose, the first epoch at high water `0`, and a healthy five-record/373-byte journal. The invalidation survived daemon stop and independent recovery inspection.

After physical verification, another confirmed `reset-origin` created the second epoch:

```text
0284cd90-3f91-4238-bd8d-13e8aa37070b
```

Recovery readback and a fresh controller status both reported trusted `(0,0,0)` North, high water `0`, and a healthy one-record/213-byte generation-1 journal. The first epoch was deliberately superseded. An old first-epoch packet was not actually transmitted, so in-game `stale_epoch` rejection remains pending.

#### Autonomous request ledger and replay tests

All successful autonomous physical requests in the second epoch were:

| Sequence | Request ID / operation | Observed and reported final pose | Result |
|---:|---|---|---|
| 1 | `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:1` / `turn_left` | `(0,0,0)` West | Succeeded |
| 2 | `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:2` / `move_forward` | `(-1,0,0)` West | Succeeded |
| 3 | `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:3` / `move_backward` | `(0,0,0)` West | Succeeded |
| 4 | `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:4` / `turn_right` | `(0,0,0)` North | Succeeded |

The full first request ID was `p:0284cd90-3f91-4238-bd8d-13e8aa37070b:1`. `ociactl left` turned Wheatley exactly once from North to West and returned `operation_succeeded` with trusted pose. Repeating the same operation with the same ID returned the cached result with `duplicate=true`; Wheatley did not turn again.

Reusing sequence 1 for `right` returned the successful negative result `rejected / request_id_conflict` with the message that the sequence had different request contents. No right turn occurred. Status remained trusted `(0,0,0)` West at high water `1`, with one retained result and a healthy four-record/1015-byte journal.

`ociactl forward` automatically allocated sequence 2. Wheatley physically moved exactly one block West, and the reported pose changed to `(-1,0,0)` West. A following status showed high water `2`, two retained results, and a healthy seven-record/1825-byte journal whose latest request was sequence 2 `move_forward / succeeded`.

#### Normal daemon restart recovery

With Wheatley idle at `(-1,0,0)` West, the daemon was interrupted with `Ctrl+Alt+C` and restarted. It returned to `ready`; status recovered the same second epoch, high water `2`, trusted pose, both retained results, and the same healthy journal dimensions. Wireless communication resumed without recommissioning or a port-open assertion.

**Result: passed for normal restart after completed operations.** This does not cover an interrupted `prepared` or `executing` record, sudden power loss, or crash consistency. The retained sequence-1 request was not replayed after this restart, so post-restart duplicate suppression remains a separate pending test.

#### Commanded return to the dock and charging evidence

`ociactl back` allocated sequence 3 and moved Wheatley one block East to `(0,0,0)` West. `ociactl right` allocated sequence 4 and turned him North. Physical observation agreed with the final trusted origin pose. These were manually selected one-step autonomous commands, not an autonomous route planner or return-to-base decision.

Green charging particles were visible after return. Reported energy fell from `35415/35500` before daemon restart to `35196/35500` after the backward return, then rose to `35499/35500` at the final turn response—a 303-unit increase while at the dock. This is positive evidence that the active Charger restored energy, but it is not controlled charge-rate measurement, alignment detection, full-charge detection, low-energy policy, or automatic docking/resume.

#### Runtime resource observations

The robot reported total memory `786432` bytes. Representative free-memory readings were `493066`, `377473`, `495304`, `145915`, `368588`, and `486397` bytes at different points. No out-of-memory failure occurred during this short session. The variation may involve garbage collection, but the session did not measure collector activity and does not establish either a leak or long-running memory stability. Similarly, displayed `last write 0 ms` values have limited timer resolution and do not prove instantaneous or crash-durable storage.

#### Acceptance conclusion and remaining gates

Milestone 1 is **partially accepted**. The live session passed deployment/configuration, fail-closed initialization, explicit commissioning, addressed status, legacy compatibility and durable invalidation, manual recovery/recommissioning, first turn and translation, retained duplicate suppression, conflicting-ID rejection, contiguous sequencing through 4, normal completed-state restart recovery, and commanded physical return to the dock.

Still pending:

1. Retry an identical retained request after a normal daemon restart and confirm cached response with no movement.
2. Send a recorded old-epoch request and observe `stale_epoch` with no movement.
3. Exercise journal compaction in a controlled setup, then verify generation, bounded size, restart, retained and retired behavior, and restore production settings.
4. Suppress a successful reply in a safe harness; verify controller certainty `unknown` and identical-ID recovery without another physical action.
5. Inject interruption after durable `prepared`; verify `interrupted_before_execution`, `physical_outcome=not_started`, unchanged trusted pose, and no replay.
6. Inject interruption after durable `executing`; verify unknown physical outcome, untrusted pose, matching/conflicting retry behavior, persistence through legacy recovery/restart, and explicit-epoch retirement.
7. Separately test foreign senders, a second addressed robot, malformed live packets, component exceptions, sustained memory/disk behavior, and power-loss boundaries.

The fault-injection tests must use controlled hooks or disposable setups. Killing Minecraft during a survival-world physical action is not a test harness; it is just a creative way to manufacture ambiguity.

### OpenOS REPL behavior

The OpenOS `lua` interpreter is useful for small probes but has two confirmed pitfalls:

- A variable declared with `local` in one submitted statement is not available in a later statement. Use a persistent global such as `c = require("component")` for multi-command exploration.
- Pasting a multiline program as one interactive block can produce a stack trace and `end` syntax error because the REPL does not treat the paste as one complete source chunk.

Individual statements and single-line loops work reliably. Maintain real programs as `.lua` files from the Ubuntu host rather than pasting substantial code into the REPL.

### Verified Geolyzer behavior

The installed `OpenComputers-MC1.12.2-1.8.8+8da357f.jar` establishes the base API boundary: `robot.detect*` returns adjacent occupancy categories, `robot.compare*` requires a selected sample, no general `robot.inspect*` exists, and the Inventory Controller inspects items rather than terrain. Wheatley's installed Geolyzer now provides demonstrated detailed adjacent analysis and volume scanning.

Persistent REPL setup:

```lua
c = require("component")
g = c.geolyzer
sides = require("sides")
ser = require("serialization")
```

The block beneath Wheatley was analyzed with:

```lua
print(ser.serialize(g.analyze(sides.down)))
```

Actual result:

```lua
{
  color = 8368696,
  harvestTool = "shovel",
  harvestLevel = 0,
  metadata = 0,
  properties = {snowy = false},
  hardness = 0.60000002384186,
  name = "minecraft:grass"
}
```

This positively identified the adjacent Minecraft 1.12.2 Grass Block; `minecraft:grass` is not tall grass. The demonstrated result includes registry identity, metadata, properties, hardness, harvesting tool and level, and color. `analyze()` remains adjacent-only.

The tested scan signature was `g.scan(x, z, y, width, depth, height)`. Its `x, z, y` order is intentionally recorded because it is easy to misread as conventional `x, y, z`.

Ground layer at `Y=-1`:

```lua
scan = g.scan(-1,-1,-1,3,3,1)
```

```text
 0.57   0.55   1.46
 0.57   0.65   1.44
 0.64   0.58   1.40
```

The western and center measurements are consistent with the known Grass Block hardness. The eastern column is consistent with the known factory wall. Only the center block was positively identified by `analyze()`.

Upper layer at `Y=+1`:

```lua
upper = g.scan(-1,-1,1,3,3,1)
```

```text
 0.00   0.54   1.56
 0.00   0.00   1.44
 0.00   0.00   1.47
```

The zeros correlate with known open space, and the eastern column correlates with the wall. The northern center value may be the Lever or Charger assembly, but that identity is speculative. A zero scan value is not proof of air.

Middle layer at `Y=0`:

```lua
middle = g.scan(-1,-1,0,3,3,1)
```

```text
 0.00    2.04    1.55
 0.00    2.00    1.55
 0.00   19.99    1.46
```

While Wheatley faced North, this correlated with the known depot geometry:

```text
                 West       Center        East
North            0.00        2.04         1.55
                             Charger      wall
Center           0.00        2.00         1.55
                             Wheatley     wall
South            0.00       19.99         1.46
                             Ender Chest  wall
```

The labels come from known physical geometry, not from `scan()` itself. Scan array order and whether axes rotate with robot heading remain unverified.

A repeated unchanged middle-layer scan produced these deltas from the first result:

```text
1    0.000
2   -0.087
3   -0.046
4    0.000
5    0.000
6   -0.034
7    0.000
8    0.045
9    0.041
```

The four zero cells remained zero. Solid readings varied slightly, with a largest observed absolute difference of `0.087` in this one experiment. This is evidence of scan noise, not a universal maximum or a production tolerance.

The survey model therefore retains these distinct evidence types:

1. Positive identity from adjacent `analyze()`.
2. Comparison with a known carried sample.
3. Categorical adjacent detection.
4. Approximate density or hardness from `scan()`.
5. Unknown or insufficiently characterized state.

Volume scans are demonstrated and useful for a preliminary three-dimensional model. They do not convert a value near `1.5` into `minecraft:stone`, and zero does not automatically mean air. Production use still requires heading/axis calibration, more noise samples, energy measurements, zero-value tests, and scan behavior for liquids, foliage, entities, and modded blocks.

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

### Proposed dock supply and return flow

The preferred material path keeps the controller, OC Adapter, and RS Interface inside the factory while using EnderStorage to bridge the wall:

```text
RS Interface -> inside supply staging -> supply Ender Chest
    == shared EnderStorage inventory ==
outside dock Ender Chest -> Wheatley
```

This topology is proposed, not validated. The existing Ender Chest is directly south of Wheatley's resting pose, so the loading procedure must include a verified rotation or side interaction.

A separate EnderStorage color frequency is preferred for returns:

```text
Wheatley -> outside return Ender Chest
    == separate EnderStorage inventory ==
inside return Ender Chest -> RS Importer -> RS network
```

Separating supply and return prevents an RS Importer from immediately reclaiming newly staged supplies. Neither channel may conflict with the white/white/blue frequency reserved for finished farm output.

The first dock experiment should use one expendable item and record every inventory delta. Inventory Controller side and slot behavior, chest access from the resting pose, RS extraction into the inside chest, return Importer behavior, and whether one or two physical dock chests are simplest remain open.

### Superseded Dead Bush workflow

The Dead Bush MacGuffin processing-pattern cycle was manually tested successfully: 64 Dirt was staged as input, a reusable Dead Bush was declared as output and kept in staging by an Exporter, and returning it through an Interface completed the pending job. A pattern consuming and producing the same token was rejected as circular.

That mechanism is no longer the primary architecture. A survey-derived material requirement does not fit a fixed processing recipe, and RS task completion is not construction or mission completion. The protocol remains a proven historical technique and possible optional Crafting Grid trigger; deployments must neither require nor return a Dead Bush.

### Pending local configuration

The following values still need to be recorded when required by implementation:

- Robot-accessible staging and return inventory locations plus remaining component addresses.
- Supply, return, and farm-output EnderStorage color frequencies and final dock chest layout.
- Deployment origins, headings, and site coordinates.
- Initial controller-side deployment submission interface.

HDD and modem UUIDs are separate fields in `deploy.local.lua`. The installer renders both confirmed modem identities into each role's `/etc/ocia.cfg`; the installed files still require a separate reviewed apply.

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
- Preserve raw Geolyzer samples separately from interpreted observations and plans; never promote scan density to block identity.
- Survey and produce a deterministic terrain plan before calculating the bill of materials; do not let the initial survey modify blocks.
- Revalidate plan preconditions before apply, then resurvey after apply to prove convergence or report remaining differences.
- Allow staged extraction, multiple supply trips, recovered-material credit, and explicit reconciliation after the plan establishes requirements.
- Validate the proposed EnderStorage supply and separate return channels one item at a time before adopting them for manifests.
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
- Wheatley has both an Inventory Upgrade and Inventory Controller Upgrade. Automatic equipped-tool swapping still requires an operational `equip()` test.
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

- Preserve project-owned application files under logical controller and robot roles.
- Keep machine-local deployment mapping, backups, runtime configuration, and runtime state out of Git.
- Deploy only an explicit application manifest with dry-run planning, backups, staged replacement, and verification.
- Keep the confirmed installed mod versions recorded with the runtime environment when the pack changes.

Related risks: OCIA-005, OCIA-006, OCIA-007.

Implementation status: complete. The semantic `machines/` trees are canonical, `.gitignore` excludes deployment-local data and runtime state, and the tested selective installer procedure is documented in [MILESTONE1.md](MILESTONE1.md).

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

Implementation status: repository code, host tests, generated modem configuration, deployment, and core supervised request/reply acceptance are complete for the Milestone 1 subset. Foreign-sender/two-robot isolation and the remaining fault-tolerance gates are pending.

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

Implementation status: the Milestone 1 subset—relative pose, append-only physical-request journal, explicit epoch commissioning, bounded recent-result cache, safe retirement, compaction, protected movement dispatch, and local origin reset—is host-tested. Commissioning, physical turn/translation pose, duplicate/conflict behavior, legacy invalidation/recommissioning, and normal completed-state restart recovery are also demonstrated in game. Compaction, retirement/stale replay, lost reply, interrupted execution, controller deployment checkpoints, and broader hardware primitives remain pending.

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

- Complete representative `robot.detect*` and `robot.compare*` probes, Inventory Controller inspection tests, and Geolyzer calibration against the installed version.
- Calibrate Geolyzer flat-array order, local axes, heading rotation, repeatability, zero readings, and energy cost using the known depot geometry.
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
- Validate the proposed inside-to-outside EnderStorage supply channel and a separate return channel before selecting the final dock inventory layout.
- Verify the robot loading path, including chest side/slot mapping, the Inventory Controller Upgrade, and tool switching.
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

## Navigation MVP: Proposed Architecture and Implementation Plan

**Status: overall architecture accepted; Stage 1 pure nominal planning implemented and host-validated on 2026-11-01. Stages 2–5 remain unimplemented and require separate authorization.** This design builds directly on the successful supervised 3x3 Potato patch: the controller issues one physical operation at a time, Wheatley journals it, and the controller validates the correlated result and expected pose. The navigation MVP adds route choice, bounded reactive detours, durable controller mission state, actual-route breadcrumbs, and supervised return home without replacing that execution path.

### Stage 1 implementation result: 2026-11-01

Controller `lib/ocia/nav.lua` now exposes `plan(startPose, destination[, options])` and `inverse(operations)`. The library accepts any explicit validated trusted pose; this is a pure planning capability for later route segments and does not change the future CLI's home-only mission-start policy. Destination coordinates are signed finite safe integers, optional `destination.heading` constrains final orientation, and `options.max_distance` defaults to the proposed 32-movement Manhattan planning radius. This is a configurable MVP policy limit, not an OpenComputers hardware limit.

The planner enumerates X-then-Z and Z-then-X horizontal orders and, for every nonempty horizontal segment, both useful execution headings: travel forward while facing the displacement or backward while facing its opposite. It emits one direct vertical run after horizontal travel, adds the shortest final turn when required, simulates every operation through `ocia.pose`, and selects by total actions, turns, temporary elevation changes, then the stable operation order `turn_left`, `turn_right`, `move_forward`, `move_backward`, `move_up`, `move_down`. A 180-degree tie uses two left turns under that final ordering. The returned compact record includes copied start/destination values, operations, counts/cost, expected end, inverse cost, configured distance, and explicit `terrain_model="unobstructed"` / `traversability="unknown"` qualifications.

Focused host tests use an independent bounded breadth-first oracle rather than the production enumeration. They compare minimum cost for 1,500 combinations spanning four initial headings, signed X/Z offsets `-2..2`, Y offsets `-1..1`, and unconstrained or four required final headings. This exposed one incorrect hand-written test expectation: backward travel satisfied a required final heading without the extra turn the test expected. The expectation was corrected after inspecting the independently optimal route; no architectural expansion was needed.

Validation results:

- `tests/nav_test.lua`: 12 tests, 4785 assertions, 0 failures.
- Full `tests/run.lua`: 52 tests, 12885 assertions, 0 failures.
- `tests/deploy_test.lua`: 26 tests, 160 assertions, 0 failures.
- All Lua sources/tests parse under Lua 5.3, and `git diff --check` passes.
- The isolated dependency-boundary test loads `nav.lua` with only `ocia.pose` available; component, modem, filesystem, journal, world, inventory, energy, sensor, and mutable mission-state dependencies are absent.

No CLI, controller journal, robot/protocol/transport code, sensing, detours, physical execution, configuration, or deployment manifest changed. No deployment or Minecraft interaction occurred. Stage 2 durable controller mission state is the next implementation candidate, pending an explicit separate GO.

### Purpose, operating envelope, and non-goals

The first navigation target is short, supervised travel through mostly open Shrubland: modest hills, grass and shrubs, isolated trees, shallow depressions, and occasional structures. Wheatley should leave the commissioned home pose, reach a coordinate in the commissioned-origin frame, negotiate an ordinary small obstruction when possible, retain the actual route he traveled, and return to `(0,0,0)` facing North.

The guiding rule is **move optimistically, investigate reactively, and remember the route home**. Ordinary forward, backward, vertical, and turning actions are sent without a preceding sensor call. A correlated physical failure or an explicit safety condition may trigger a bounded investigation. Planning output describes a nominal route through unsurveyed space; it never claims that route is traversable.

The MVP is deliberately not a general pathfinder. It does not include arbitrary-maze solving, A*, a persistent world map, routine per-step detection, excavation, vegetation removal, material provisioning, multiple robots, unattended operation, or automatic farm orchestration. Navigation may cross a shallow depression or remain one level above a rise briefly, but it must not turn bounded countryside travel into unrestricted long-distance flight. It never authorizes `swing`, `use`, or `place` to clear a route.

The initial implementation remains supervised and permits manual recovery after any ambiguous physical outcome. Reaching the home pose and proving that charging works are separate results: `home_pose_reached` requires the commissioned coordinates and North heading, while `charging_verified` remains false or untested until the separate OCIA-035 energy-rise check is implemented and accepted.

Every new MVP mission begins at the commissioned home pose. `ocianav go` requires fresh robot status showing trusted `(0,0,0)` North, a nonempty execution epoch, mode `ready`, and robot journal health `healthy`. The new controller mission record captures that exact epoch, and a pre-send reconciliation must still match it. `go` refuses any other starting pose or an unresolved older controller mission. This restriction makes the inverse of the actual outbound breadcrumb a route home rather than merely a route to an arbitrary starting point. Arbitrary trusted-pose mission starts are deferred.

The future `ocianav plan` command is different: it is a pure host/OpenOS calculation with no modem request, component access, mission-journal write, or dependency on live status. For this MVP the CLI will supply the commissioned start `(0,0,0)` North and print that assumption prominently. The implemented pure library accepts an explicit trusted start so later route segments can plan from actual poses without duplicating planner logic. `return` and `resume` will operate only on an existing durable mission and must reconcile its actual state; they do not require Wheatley already to be home.

### Findings from the current implementation

The repository code, rather than the older milestone prose, establishes these integration facts:

- `pose.lua` is byte-identical on the controller and robot. It already models all six movement/turn operations in the commissioned frame: North is `-Z`, East is `+X`, and successful stationary farming operations preserve pose.
- `protocol.lua` is also byte-identical on both machines. Version 1 uses one eight-part request per operation and distinguishes robot outcomes `succeeded`, `failed`, `rejected`, and `recovery_required`. Controller transport maps the last outcome and timeouts to certainty `unknown` and maps both `failed` and `rejected` to certainty `failed`, so navigation must inspect both `response.certainty` and `response.status`; certainty alone is insufficient.
- `transport.lua` also returns `certainty="failed"` for `local_rejection` and `send_failed`. Neither is a correlated terminal robot outcome. A local request-build rejection proves only that this controller invocation did not send; the current modem send failure path does not prove non-delivery and must be treated as ambiguous for a physical request.
- Physical request IDs are `p:<epoch>:<sequence>`. `executor.lua` durably appends `prepared`, `executing`, and `completed`. A definite failed Robot call is still a completed, consumed sequence with unchanged pose. The robot high water advances when `prepared` persists, not only when movement succeeds.
- `farm.execute` advances its local high water only after success and stops on every failure. That is correct for the farming prototype, but navigation cannot copy it verbatim: after a correlated `failed` movement it must treat the request sequence as consumed, validate unchanged pose, reconcile fresh status, and allocate the following sequence before probing or replanning.
- A `rejected` request is different. It may have been rejected before allocation, may refer to an already consumed sequence, or may be stale/conflicting. Navigation must stop and reconcile status rather than infer high-water advancement from the controller certainty value.
- A timeout, `recovery_required`, contradictory reply pose, or failure to persist a controller result is not a navigable obstacle. It is an ambiguity boundary and stops autonomous movement.
- The robot journal supplies durable at-most-once physical execution and robot pose. There is no durable controller deployment/navigation journal today. `MVP_PLAN.md` proposes controller persistence, but the implemented `state.lua` is robot-specific and is installed only on Wheatley.
- `status` is read-only, uses the `s:` request namespace, does not consume robot high water, and is proven by host tests not to append journal records. The current protocol identity validator special-cases the literal operation name `status`, and `transport.makeRequest()` automatically creates an `s:` ID only for that same literal name. Adding `nav_probe` therefore requires small changes at both sites plus read-only executor dispatch; adding only an operation-table entry would be incomplete.
- The controller and robot cannot safely have concurrent programs consuming port 4242 events. An active navigation mission must be the sole autonomous controller workflow. Legacy physical driving remains available but deliberately makes robot pose untrusted and therefore terminates navigable mission state until explicit physical reconciliation and recommissioning.
- The farm planner's local plot convention is intentionally separate from world coordinates. `ocianav` must accept only the established commissioned-origin coordinates and must not reuse farm-local `z` semantics.
- The current deployment manifest contains 21 files, not the historical 18-file count recorded for the earlier acceptance session. Stage 1 deliberately did not add `nav.lua` to that manifest. The current host suites pass 52 tests / 12885 assertions and 26 deployment tests / 160 assertions; older totals in `MILESTONE1.md` are dated historical results.
- Direct inspection of the installed `OpenComputers-MC1.12.2-1.8.8+8da357f.jar` confirms that the OpenOS robot library implements `detect`, `detectUp`, and `detectDown` as adjacent calls. The classic implementation returns a boolean plus a broad category such as `air`, `entity`, `replaceable`, `passable`, `solid`, or `liquid`. Movement can return reasons including those obstruction categories, `already moving`, `impossible move`, and `not enough energy`. These strings are useful evidence, not a complete navigation ontology, and require small in-game fixtures before policy relies on every category.

The documentation's `Immediate Next Work` opening sentence still described the already-completed Potato prototype. This proposal replaces that stale next-step statement while preserving the experiment and deferred acceptance history below.

### Nominal route planner and cost model

The controller owns route generation. The robot remains a defensive executor of one operation. For every route:

```text
route_cost = movement_count + turn_count
```

Each `move_forward`, `move_backward`, `move_up`, `move_down`, `turn_left`, and `turn_right` costs one. Sensor calls, persistence writes, and waiting are reported separately and do not alter nominal route cost in the first version.

The nominal planner does not need grid search. Its pure API starts simulation from the caller's explicit validated trusted pose; the future MVP CLI supplies `{x=0,y=0,z=0,heading="north"}` for a new mission. For an unobstructed coordinate goal it enumerates the small finite set of axis-aligned candidates:

1. Horizontal segment order: X then Z, or Z then X, omitting zero-length axes.
2. For each horizontal segment, the two useful execution headings, choosing forward or backward travel accordingly.
3. The direct vertical run, placed deterministically before, between, or after horizontal runs when these choices have equal physical cost.
4. An optional required final heading. Destination heading is unconstrained by default; return home always requires North.

Each candidate is simulated with `pose.apply`. Rank candidates by total action cost, then fewer turns, then fewer temporary/unnecessary elevation changes, then a documented lexicographic operation order so identical inputs produce identical output. This enumeration naturally chooses backing South while still facing North when it is cheaper than turning around. It also avoids consecutive 180-degree turns unless the full candidate really is cheapest.

The plan records a copy of the explicit start pose, destination coordinate and optional heading, action list, movements, turns, cost, expected end pose, direct inverse-return cost, configured limits, and the warning that terrain is unsurveyed. `plan` performs no modem send, live status request, component lookup, or mission-state write. Coordinates use the commissioned frame—North `-Z`, East `+X`, Up `+Y`—and never the Potato prototype's farm-local axes.

### Optimistic execution and definite-failure escalation

For each physical action, the controller first durably records intent, sends one existing OCIA request, and passes the transport result through a navigation-specific classifier. The shared `transport.certainty` contract remains unchanged; navigation uses the complete response shape and a closed allowlist of terminal codes:

| Observed controller/robot result | Navigation classification | Sequence and continuation rule |
|---|---|---|
| `local_rejection` before `modem.send` | Definite local non-send | No robot allocation is established. Record the validation/configuration defect and stop; it is not terrain and should not be retried as a new physical action until corrected. |
| `send_failed` | Ambiguous delivery/outcome | The current modem API result does not prove that no packet was delivered. Preserve the pending intent, allocate no new ID, and reconcile only by the identical request/status procedure. |
| Timeout/no correlated reply | Ambiguous outcome | Preserve the pending intent, allocate no new ID, and retry only the exact request identity during reconciliation. |
| Correlated `succeeded / operation_succeeded` | Definite physical success | Require trusted reported pose equal to `pose.apply(before, operation)`, record the consumed sequence/result once, update actual pose, and append the successful action to the breadcrumb. |
| Correlated `failed / operation_failed` | Definite completed physical failure | The Robot API returned failure after durable allocation/executing and Wheatley persisted completion. Require trusted unchanged pose, record the consumed sequence, then reconcile fresh status before sequence `+1`. Only an allowlisted obstruction/entity movement reason may enter terrain handling. |
| Correlated `failed / interrupted_before_execution` with `physical_outcome=not_started` | Definite completed nonexecution | The request sequence was allocated and then durably completed as not started. It consumes the sequence but creates no obstacle or breadcrumb. Stop the current run; after status reconciliation, supervised resume may decide whether to issue the operation under a new contiguous ID. |
| Correlated `rejected` | Definite rejection, allocation unresolved by rejection alone | Record it, inspect its code and fresh status for diagnosis, and stop. Never treat rejection as movement failure or infer whether this request advanced high water. |
| Correlated `recovery_required`, including `physical_outcome_unknown`, `prepared_resolution_unpersisted`, persistence/encoding/compaction errors, or operation exceptions | Ambiguous or untrusted physical state | Stop, preserve pending evidence, and allocate no new ID. Manual reconciliation is required unless the existing identical-request recovery contract yields an authoritative result. |
| Malformed, mismatched, or pose-contradictory response | Ambiguous/untrusted response | Ignore it as authority, stop at timeout or contradiction, and allocate no new ID. |

A result is a correlated terminal robot result only when sender, recipient, port, protocol version, request ID, deployment ID, operation, outcome, payload, and expected pose semantics validate. `response.certainty="failed"` by itself never establishes a definite failed physical operation.

After `operation_failed`, fresh status must report the same epoch, `ready`, healthy robot journal, trusted unchanged pose, and high water exactly equal to the failed request sequence. Only then may navigation persist reconciliation and allocate sequence `+1`. If status is missing, ahead, behind, untrusted, unhealthy, or contradictory, the mission stops. The same reconciliation rule applies to definite `interrupted_before_execution`, but that result is not evidence of terrain.

Only a definite correlated `operation_failed` movement with an allowlisted obstruction or entity reason enters obstacle handling. A failed turn normally indicates energy or an implementation/runtime problem rather than terrain and stops after status reconciliation. `not enough energy` immediately enters recovery-required handling; it is never treated as a reason to try a different direction. `already moving`, `impossible move`, unknown detail strings, or component exceptions stop initially unless an accepted in-game test establishes a safe narrower policy.

For a definite obstruction/entity failure:

1. Record the directed blocked transition keyed by before-pose plus operation and inferred target. Do not retry the same transition during the mission merely because a new plan rediscovered it.
2. Use the movement detail if it answers the immediate question.
3. If more evidence is required, issue one correlated read-only categorical probe for front/up/down.
4. Generate deterministic, bounded alternatives, each ending at a concrete bypass waypoint pose, and rank each as `detour actions + nominal remaining route cost` using the same tie-breakers.
5. Durably select one waypoint and commit to it. Execute its actions one physical operation at a time without comparing the original destination again after each success. A new definite obstruction or safety/limit failure may interrupt the committed detour; ambiguity stops.

Entities are transient, but blind repeated bumping is not useful. The proposed policy permits at most one explicitly logged retry after a fresh probe reports the entity no longer present; otherwise it chooses a detour or stops. Persistent solid, liquid, and unsafe/unknown classifications are avoided, not modified.

### Terrain handling and bounded detours

The initial detour generator is a deterministic set of small maneuvers, not a world search. Each candidate ends at a temporary waypoint containing exact `x`, `y`, `z`, and required heading when the next corridor segment depends on orientation. Selecting it writes the waypoint, originating blocked transition, chosen candidate, action budget, lateral/vertical bounds, planned actions, progress index, and selection reason to the controller mission journal before the first detour action.

- Same-level bypasses try left and right offsets around a blocked horizontal transition, including the turns needed to leave and rejoin the nominal corridor. Candidate cost includes all turns, so a seemingly short zigzag does not beat a straighter route accidentally.
- A rise candidate may move up one block, continue horizontally, and remain elevated briefly rather than immediately descending onto the obstacle. Successful actions advance the committed waypoint plan; they do not cause a fresh comparison against the final destination.
- A second upward level is allowed only within the configured vertical envelope and after the first-level maneuver cannot proceed.
- Automatic downward detours are conservative. A downward move is considered only within the vertical envelope and after an adjacent downward categorical probe rules out liquid or a known unsafe target. Repeated descent beyond the envelope is prohibited.
- The route may bridge a shallow depression or stay elevated over a short obstacle, but an elevated-run budget prevents indefinite flight. It must return to the requested destination Y coordinate.
- Candidate routes containing a known blocked directed transition, a visited failure state, or a limit violation are discarded before execution.

When the exact waypoint pose is reached, the controller durably marks the detour complete, clears the active waypoint, and resumes nominal planning from that pose to the original destination. A new definite failure during the detour durably marks the candidate interrupted or abandoned before another candidate can be selected. Abandoned candidate identity and visited/blocked transitions remain in mission state, so the controller cannot oscillate between the nominal corridor and the same failed bypass. Candidate count, per-detour action budget, total failure budget, and total mission-action cap bound all reselection. No success step by itself permits abandoning a committed waypoint merely because the original route has become superficially cheaper.

Proposed initial policy defaults, all explicitly **unverified tuning values rather than hardware limits**, are:

| Limit | Proposed starting value | Purpose |
|---|---:|---|
| Destination Manhattan distance from mission start | 32 blocks | Keep first trips short and logs reviewable. |
| Lateral deviation from the current nominal corridor | 3 blocks | Bypass one tree or narrow wall without exploring. |
| Temporary vertical deviation | 2 blocks | Handle modest rises without general flight. |
| Consecutive definite movement failures | 3 | Stop a bad local maneuver quickly. |
| Total definite movement failures | 8 | Bound the full mission's trial-and-error. |
| Local detour physical-action budget | 24 | Bound turns and movement spent on one incident. |
| Elevated horizontal run | 8 movements | Allow a short bridge while preventing indefinite unsupported travel. |
| Return recovery anchors skipped | 3 breadcrumb states | Permit a small bypass around a newly blocked return cell. |
| Total physical actions | 160 | Bound journal, memory, time, and energy exposure. |
| Categorical probes per incident | 2 | Obtain only evidence needed for the immediate choice. |

The CLI prints these limits before confirmation. Host tests should make them configurable so smaller fixtures exercise every boundary. Minecraft experiments may revise them. Exceeding any limit produces a named bounded-stop reason and preserves the mission for inspection/return or manual recovery.

Energy is not folded into nominal cost until measurements justify it. Before terrain trials, measure conservative energy deltas for move, turn, detect, and status under the installed configuration. The controller then enforces a configurable absolute reserve using:

```text
required_energy = measured_upper_bound_per_action
                * (remaining_inverse_breadcrumb_actions + return_detour_allowance)
                + charging_approach_margin
```

Until those measurements exist, navigation is limited to the smallest supervised fixtures from a nearly full battery; the proposed numeric route limits are not evidence of return-energy feasibility. Each physical reply's energy reading is logged, and a reserve breach prevents further outbound movement.

### Sensor strategy

Stages 1–3, including the first flat outbound trip and inverse return, need no new sensor operation. Stage 4 obstacle negotiation introduces one narrow extension, proposed as nonphysical `nav_probe`:

```text
nav_probe -> front_blocked/front_kind,
             up_blocked/up_kind,
             down_blocked/down_kind
```

The robot implementation would call only `robot.detect()`, `robot.detectUp()`, and `robot.detectDown()` under `pcall`. It would not analyze, scan, move, turn, or mutate inventory/world state. Both `status` and `nav_probe` use correlated `s:` request IDs, existing modem addressing, sender/recipient validation, reply correlation, and protocol version 1. Neither allocates physical high water nor mutates Wheatley's physical execution journal. The controller mission journal records the returned observation because it influenced a decision, while the robot execution journal remains reserved for physical at-most-once actions.

Supporting this cleanly requires two coordinated ID-generation/validation changes:

1. The shared protocol validator classifies request namespaces through `protocol.isPhysical(operation)` (or one equivalent centralized operation classification): physical operations require `p:<epoch>:<sequence>`, while every supported nonphysical operation requires `s:<token>`.
2. `transport.makeRequest()` automatically generates an `s:` ID for any supported nonphysical operation, not only the literal name `status`; physical operations continue to require an explicit epoch/sequence ID.

The executor/daemon then dispatches supported nonphysical operations before physical-ID parsing and journaling. This must not create a second modem protocol or route around sender validation. A probe exception returns a definite read-only failure diagnostic and cannot change pose trust; navigation may stop because evidence is insufficient. Host tests must prove that neither `status` nor `nav_probe` changes robot high water, recent physical results, journal records, or pose.

Geolyzer `analyze()` and `scan()` are outside the first navigation slice. Adjacent analysis may later distinguish a persistent obstacle when identity changes policy, but ordinary detouring needs only occupancy class. Volume scans add orientation, noise, energy, and coordinate-calibration dependencies without helping the common case. They remain disabled until the OCIA-033 calibration tests establish axes, array order, energy, zero semantics, and safe interpretation. Density never becomes registry identity, and zero never becomes verified air.

### Actual-route breadcrumbs and durable controller mission state

The outbound breadcrumb is the sequence of **confirmed successful physical actions actually executed**, including turns and vertical moves. Planned but unsent actions and definite failures never enter it. Each entry retains operation, request ID, before pose, after pose, phase, and energy/result evidence. Its inverse is defined exactly as:

| Actual outbound action | Return action |
|---|---|
| `move_forward` | `move_backward` |
| `move_backward` | `move_forward` |
| `move_up` | `move_down` |
| `move_down` | `move_up` |
| `turn_left` | `turn_right` |
| `turn_right` | `turn_left` |

The controller needs a narrow append-only navigation journal, proposed at `/var/lib/ocia/nav.state`, separate from Wheatley's `/var/lib/ocia/robot.state`. A single active mission record contains schema version, mission ID, robot epoch, fixed home/start pose, destination, limits, phase, last reconciled robot high water, actual outbound breadcrumb, return progress, blocked transitions, active committed waypoint and progress, abandoned detour identities, probe evidence, energy samples, and terminal reason.

Before every physical send, the controller appends and flushes an `intent` containing the exact request ID/fingerprint inputs, operation, phase, before pose, expected success pose, and intended breadcrumb effect. After a correlated terminal reply it appends a `result`. Replaying the checksummed records reconstructs mission state. Writes use the robot journal's conservative open/write/flush/exceptional-close handling and fail closed on a partial final record or replacement artifact. The first bounded MVP does not need controller-journal compaction: one mission is capped at 160 physical actions. A new `go` may replace/archive a prior mission only after that mission has a durable terminal record, Wheatley is freshly verified at healthy home, and the prior file is preserved through replace-safe rotation; it must never silently overwrite an active, incomplete, or uncertain mission.

This ordering handles the important crash window:

```text
persist controller intent
    -> send one physical request
    -> robot prepared/executing/completed journal
    -> correlated reply
    -> persist controller result/breadcrumb effect
```

- Normal restart after a completed controller result: replay reconstructs the recorded mission pose and breadcrumb, then fresh robot status must agree before continuation.
- Crash before a durable controller intent: nothing may be sent.
- Crash after intent but before robot allocation: resume sends the exact same ID and contents.
- Lost acknowledgment or crash after robot completion but before controller result: resume sends the exact same ID and contents; if Wheatley retains the completed result, it returns that result without re-execution, after which the controller records the breadcrumb once.
- Restart after robot `prepared` but before execution: the existing robot startup path may durably classify `interrupted_before_execution`; navigation records a consumed, definite nonexecution only after receiving and validating that retained result and reconciling status.
- Restart from robot `executing`, an uncertain completion write, or another `physical_outcome_unknown` boundary: pose/outcome remain ambiguous and navigation stops for manual reconciliation. It does not infer success from coordinates or send a new ID.
- Crash after a durable controller result: journal replay already contains the authoritative breadcrumb effect; duplicate result application is rejected by request ID.
- If the matching robot result has already been retired, the epochs/high water disagree, a different controller program used a later sequence, or either journal is uncertain, automatic resume stops. Status alone cannot reconstruct whether a retired movement succeeded.

At resume, `ocianav` first loads the controller journal, requests fresh robot status, and requires matching epoch, ready/trusted pose, and a high-water relationship consistent with either the last terminal result or exactly one pending intent. It reconciles a pending intent only by resending its identical request. No fresh physical ID is allocated until the pending result is authoritative. This is supervised recovery with durable reconciliation, not a claim of transactional execution.

These guarantees cover validated append/replay behavior and normal completed-operation restarts. OpenOS `write`, `flush`, and normal close do not establish `fsync`-grade persistence. A partial/corrupt controller record or replacement artifact fails closed. Sudden Minecraft/JVM termination, host power loss, or storage loss may leave controller and robot journals whose ordering cannot be proven; those cases require inspection and may require manual physical reconciliation. The design claims neither transactions across two computers nor crash consistency beyond the evidence established by fault tests and supervised OpenOS runs.

Only one navigation mission and one OCIA controller process may be active. The CLI should use an advisory ownership marker to prevent two `ocianav` instances, but it cannot prevent an operator from launching `ociactl`, `ociafarm`, or `drive`. Any unexpected high-water or pose change is therefore treated as external interference and stops the mission. Legacy movement makes pose untrusted as it does today.

### Return execution and obstruction recovery

On `return`, freeze the outbound breadcrumb and walk it backward. For each top entry, compute its inverse, expected predecessor pose, and request ID intent; execute it through ordinary OCIA rules. A confirmed inverse success durably marks that breadcrumb entry satisfied. Arrival requires an empty outbound stack plus exact `(0,0,0)` North pose and matching trusted robot status. Stage 3 implements this basic inverse playback and stops safely on any definite return obstruction; it does not wait for obstacle handling to make a flat round trip useful.

Stage 4 adds changed-world recovery; return is still not treated as infallible playback. If an inverse movement definitely fails, leave that breadcrumb entry unsatisfied and invoke the same bounded local detour logic with a **breadcrumb anchor pose** as the committed temporary waypoint:

1. First try to reach the immediate predecessor pose, including heading, without using the now-blocked transition.
2. If that pose itself is occupied or unreachable, consider at most the next three earlier breadcrumb poses as anchors.
3. Choose the lowest-cost bounded candidate, durably commit to its exact anchor pose/heading and budgets, execute it one operation at a time, and log successful return-detour actions in the mission event history but not in the frozen outbound stack.
4. Only after Wheatley reaches an anchor's exact pose may the corresponding covered breadcrumb entries be marked satisfied and ordinary inverse playback resume.

This separation prevents a return detour from being accidentally appended to the outbound stack and then inverted away from home. The mission always retains current actual pose, the fixed home destination, the frozen outbound route, the selected recovery anchor, and every detour action. If the bounded anchor recovery fails, stop with `return_route_blocked`; do not discard breadcrumbs or declare arrival.

A transient entity may receive the single probe-confirmed retry described above. World changes that make all nearby breadcrumb anchors inaccessible require operator recovery. Construction verification, home-pose arrival, and charging verification remain independent statuses.

### Proposed modules and interfaces

Keep the new code small and reuse existing modules:

| File | Proposed responsibility |
|---|---|
| Controller `lib/ocia/nav.lua` | Pure nominal candidate enumeration, cost/tie ranking, inverse operations, blocked-transition keys, bounded detour candidates, and pose simulation using `ocia.pose`. No components or files. |
| Controller `lib/ocia/nav_state.lua` | Versioned append-only controller mission journal, replay/validation, pending-intent reconciliation state, breadcrumbs, committed detour waypoint/progress, return progress, and terminal status. |
| Controller `home/ocianav.lua` | CLI, fresh status/reconciliation, explicit confirmation, one-operation execution loop, probe requests, diagnostics, resume, and return. |
| Robot `lib/ocia/sense.lua` | Optional first-obstacle-milestone wrapper for protected adjacent `detect`, `detectUp`, and `detectDown` only. |
| Shared `lib/ocia/protocol.lua` | In Stage 4, add `nav_probe` as nonphysical and validate `s:` versus `p:` IDs from the operation's physical flag. Both copies remain byte-identical. |
| Controller `lib/ocia/transport.lua` | In Stage 4, generate `s:` IDs for any supported nonphysical operation; retain existing addressing/correlation and the shared certainty contract. |
| Robot `lib/ocia/executor.lua` / `home/robotd.lua` | Minimal correlated read-only dispatch before physical sequence allocation; all existing physical execution remains unchanged. |

`pose.lua` remains the only coordinate/heading implementation. `transport.lua` remains the only addressed request/reply client; navigation adds a more precise response classifier above it rather than changing the transport certainty contract during the first slice. `farm.lua` remains independent and unchanged; it is a successful specialized route orchestrator, not the navigation mission store. The robot physical action table and journal remain the sole movement path.

The proposed minimal CLI is:

```sh
ocianav plan --x 12 --y 0 --z -8 [--heading north]
ocianav go --x 12 --y 0 --z -8 [--heading north]
ocianav return
ocianav resume
ocianav status
```

`plan` is pure/read-only, assumes `(0,0,0)` North, prints that assumption, and never contacts Wheatley. `go` refuses an active mission or any live start other than healthy, ready, trusted home; after fresh status it records that robot epoch in the new mission, displays nominal actions/cost/end pose/limits/unsurveyed warning, and requires the literal `NAVIGATE`. `return` displays remaining inverse cost and requires `RETURN` during initial testing. `return` and `resume` reconcile the existing mission at its actual pose and never impose the new-mission home precondition. `resume` never creates a new epoch. `status` shows both robot status and controller mission state. Coordinates are signed integers in the commissioned-origin frame. Initially permit at most one optional destination heading from `north|east|south|west`.

### Development milestones and acceptance gates

Implementation should be authorized and tested in these five stages:

1. **Stage 1 — Pure nominal route planner (complete, host-validated 2026-11-01).** `nav.lua` accepts an explicit trusted start pose, validates signed commissioned-frame coordinates, enumerates heading/axis/backward choices, minimizes movement plus turns, honors an optional final heading, applies deterministic tie-breakers, and reports inverse cost. It has no component, transport, protocol, filesystem, or live-status dependency. The future CLI remains responsible for supplying home for a new mission.
2. **Stage 2 — Durable controller mission journal.** Implement `nav_state.lua` and host fault tests for one-active-mission lifecycle, the mandatory home start invariant, intent/result ordering, actual-success breadcrumbs, duplicate-result protection, pending-intent resume, definite failure/nonexecution records, epoch/high-water mismatch, partial records, write/flush/exceptional-close faults, and conservative recovery. No Minecraft movement occurs in this stage.
3. **Stage 3 — Flat supervised outbound navigation and inverse return.** Implement `plan`, `go`, `status`, `resume`, and basic `return` using only the existing physical OCIA operations. `go` starts only from fresh healthy/ready/trusted home status and temporarily restricts executable destinations to `y=0`; pure `plan` may still describe a nonzero-Y nominal route for later stages. No `nav_probe`, detours, automatic obstacle handling, or vertical terrain negotiation is included. Accept a short unobstructed outbound trip, durable actual-action breadcrumbs, normal restart/pending-intent reconciliation, and exact inverse return to `(0,0,0)` North. A definite obstruction stops safely. Instrumentation must show zero sensing requests, and arrival must not claim charging verification.
4. **Stage 4 — Reactive obstacle handling.** Introduce work in independently testable increments: first generalize nonphysical `s:` IDs in protocol and transport; then add protected categorical `nav_probe`; then classify installed-version obstruction evidence; then add committed bounded lateral waypoints; then bounded elevation waypoints; finally return-obstruction recovery through committed breadcrumb anchors. Accept only after a definite `operation_failed` movement consumes its sequence, fresh status reconciles high water/pose, the next request is contiguous, committed waypoints cannot oscillate, an impassable fixture stops within limits, and return detours preserve the frozen outbound stack.
5. **Stage 5 — Energy and charging integration.** Measure movement, turn, status, and probe energy costs; establish conservative preflight/return reserves and short-trip limits from evidence; then implement charging verification independently of home-pose arrival. Until this stage passes, all trips remain short and supervised and explicitly lack a validated energy-reserve guarantee.

Milestone 1's pending compaction/lost-reply/interrupted-execution tests remain relevant dependencies. The flat navigation slice can be developed against the existing host-proven semantics, but navigation must not be called fully recovery-accepted until the applicable live lost-reply and restart behavior has been demonstrated.

### Host and supervised Minecraft test sequence

Host tests should be added with the stage that needs them:

1. **Stage 1 planner:** signed coordinate validation; straight X/Z/vertical candidates from the home assumption; behind/perpendicular destinations where backward travel wins; optional final heading; equal-cost turn/elevation/lexical tie-breaks; exact action cost/end pose/inverse; deterministic repeated output; and proof that `plan` performs no modem, component, filesystem, or live-status call.
2. **Stage 2 journal and classifier:** only fresh `(0,0,0)` North status may create a mission; `return`/`resume` may reconcile a non-home active mission; actual successes rather than planned actions form breadcrumbs; `operation_failed` and `interrupted_before_execution` consume sequences without changing pose or adding breadcrumbs; local rejection, send failure, timeout, rejected, recovery-required, malformed reply, and pose contradiction follow their distinct classification rules; the next ID is prohibited until required reconciliation completes.
3. **Stage 2 fault boundaries:** controller failure before intent, after intent/before send, after send, after retained robot completion, and after controller result; exact-ID duplicate-result recovery; partial/corrupt records; open/write/flush/exceptional-close faults; retired robot results; unexpected high water/epoch/pose; concurrent-process evidence; bounded record/memory use; and explicit failure of any unsupported power-loss inference.
4. **Stage 3 flat execution/return:** home-only `go`, coordinate/heading route execution, actual breadcrumb inversion for turns and forward/backward movement, exact home/North completion, safe stop on definite obstruction, normal completed restart, pending-intent resume, and zero `nav_probe` calls on every unobstructed outbound/return route.
5. **Stage 4 read-only protocol:** both `status` and `nav_probe` automatically receive `s:` IDs; physical operations still require `p:` IDs; malformed probes and hardware exceptions are bounded; addressing/correlation remains intact; and neither read-only operation changes high water, pose, recent physical results, or robot journal size.
6. **Stage 4 detours:** known blocked transitions are not reproposed; selected waypoint pose/heading remains committed across successful steps; destination replanning occurs only after waypoint completion; interrupted/abandoned candidates cannot be reselected indefinitely; left/right and one/two-level bounds, failure budgets, action caps, entity retry, and descent gates work; return anchor recovery never pushes detour actions onto the frozen outbound stack.
7. **Stage 5 energy/charging:** measured-cost configuration validation, reserve calculations including remaining inverse route and detour allowance, low-reserve outbound refusal, exact home without charging, active charging, full buffer, Lever-off, and misalignment outcomes remain distinct.

Supervised Minecraft acceptance should proceed in the same order:

1. **Stage 3 depot status and pure preview:** verify fresh status at `(0,0,0)` North with healthy robot journal. Preview the first trip without sending a modem request. The Charger blocks North, the Ender Chest constrains South, and the factory wall blocks East, so do not use the former forward fixture.
2. **Stage 3 one-block West round trip:** after visually confirming West is open, use destination `(-1,0,0)` with required heading West so the deterministic outbound candidate is `turn_left`, `move_forward`. Basic `return` must execute the exact inverse `move_backward`, `turn_right`, ending at `(0,0,0)` North. Record all four request IDs, high-water transitions, controller records, physical observations, and confirm zero sensor requests.
3. **Stage 3 expansion:** only after the one-block fixture passes, extend to a short straight West trip, then controlled behind/perpendicular cost cases in a prepared open area. Confirm `go` refuses a non-home new mission while `return` and `resume` still work away from home.
4. **Stage 3 recovery:** restart after a normally completed operation and reconcile a safely injected lost acknowledgment with the identical ID. A contradictory pose, send failure, rejected request, or ambiguous executing boundary must produce no subsequent physical request. Inspect partial-history behavior, journal size, and free memory.
5. **Stage 4 sensing fixtures:** record installed-version `nav_probe` results for air, solid, safe replaceable vegetation, liquid, and an entity if practical; verify status/high water and robot physical journal are unchanged.
6. **Stage 4 terrain fixtures:** test one controlled rise/descent, then one narrow solid obstruction with a committed lateral waypoint. Confirm a definite failed movement consumes its sequence, fresh status reconciles it, and the following request is contiguous.
7. **Stage 4 bounded failure:** use a wall wider/taller than configured limits and verify a named bounded stop without oscillation or excavation.
8. **Stage 4 actual-route return:** travel a route containing turns, elevation, and an outbound detour, then return through the actual breadcrumb. In a separate test, obstruct one return transition and exercise a committed anchor detour while retaining home as the destination.
9. **Stage 5 energy and charging:** only after cost calibration, test reserve refusal and supervised return; then distinguish exact home pose from Lever-on active charging, Lever-off, misalignment, and already-full behavior.

For each test, record the mission ID, epoch, request IDs, robot/controller high water, before/after poses, operation details, sensor call count, energy, controller journal state, active waypoint if any, visible terrain, and whether evidence is host-only or demonstrated in Minecraft. Do not combine rise, obstruction, restart, and return recovery into the first outdoor trip.

### Risks, tradeoffs, and unresolved questions

- **Controller durability versus simplicity:** an in-memory breadcrumb is simpler but unsafe across the acknowledged controller crash window. A narrow append-only controller journal is justified; generalizing the robot journal into a framework is not.
- **Home-only mission start:** requiring `(0,0,0)` North makes inverse playback semantically equal to return home and removes an avoidable first-version ambiguity. Arbitrary trusted-pose starts are a later feature and would need an explicit distinction between mission start and charger home.
- **Transport versus robot failure:** current `transport.certainty="failed"` covers local rejection, send failure, robot rejection, and robot `failed`; navigation therefore uses a separate closed classifier. Shared transport semantics need not change merely to support navigation.
- **Exact inverse versus goal replanning:** pure inverse playback is cheap and deterministic but can be obstructed later. Bounded anchor detours retain its simplicity while allowing a small changed-world recovery. If this proves brittle, evidence may justify a small bounded path search later, not before.
- **Waypoint commitment versus greedy replanning:** committing to a bounded bypass waypoint prevents turn-back oscillation. It can temporarily follow a route that no longer looks globally cheapest, but the bounded waypoint/action budget makes that cost predictable and preferable to unstable decisions.
- **Categorical probe versus Geolyzer:** `nav_probe` answers the immediate occupancy question with minimal cost and no calibration dependency. It cannot identify blocks or guarantee distant support. That limitation is acceptable for supervised short-range detouring.
- **Backward optimization versus observation:** backward movement is cost-effective, but base detection has no back-facing wrapper. Normal backward moves remain optimistic; after a definite backward failure, Wheatley can turn only if a probe is needed, and those turns themselves become real breadcrumb actions. A direct component-side back detection should not be assumed without installed-version proof.
- **Ground support policy:** robots can move vertically and horizontally through air, so a cost-optimal route can behave like flight. The proposed vertical/elevated-span bounds are policy, not sensed terrain truth. Minecraft tests must decide whether occasional downward support probes or stricter elevation rules are needed for the actual Shrubland.
- **Movement reason stability:** classic source establishes broad return strings, but mod interactions may vary. Decisions should key first on terminal outcome and probe evidence, with raw reason retained for diagnostics.
- **Result retention:** Wheatley retains 32 full results by default. Immediate pending-intent reconciliation should stay within that window, but external physical commands could retire evidence. Retirement is a manual-recovery condition, not permission to infer a result from pose alone.
- **Persistence ceiling:** normal append/replay and retained-result recovery are design targets; `flush` and close are not `fsync`. Sudden JVM/host/power loss remains a separate unproven boundary and must not be described as automatically recoverable.
- **Process exclusivity:** an advisory navigation lock cannot prevent `ociactl`, `ociafarm`, or `drive`. Unexpected epoch/high-water/pose remains the authoritative interference detector.
- **Energy thresholds:** operation energy costs and conservative reserve are unverified. They must be measured before accepting a meaningful outdoor radius.
- **Liquids, foliage, passable blocks, and entities:** record actual `detect*` and failed-movement results in small fixtures before assigning automatic policies to every category.
- **Return anchor breadth:** skipping up to three breadcrumb states and detouring within three lateral/two vertical blocks is proposed. Test evidence may show these bounds are too small or unnecessarily generous.
- **Destination semantics:** default coordinate-only arrival minimizes actions; callers that require machine-facing orientation must supply `--heading`. Return home always requires North.
- **Charging integration:** arrival and charging remain separate until Lever-off, misalignment, active-charge, and full-buffer tests define a reliable detector.

No unresolved architectural choice blocks Stages 1–3: home-only starts, coordinate-only default destination semantics, controller journal ownership, exact inverse return, and conservative physical-result classification are now explicit. The exact starting detour bounds, movement-reason allowlist, support/descent policy, entity behavior, energy coefficients, reserve margin, and charging signal thresholds are empirical Stage 4–5 calibration questions. If testing shows that a committed waypoint cannot handle ordinary Shrubland obstacles within the proposed bounds, changing to any broader search strategy requires a new design review rather than an implementation-time assumption.

If this design is accepted, `MVP_PLAN.md` should gain a navigation milestone before autonomous terrain preparation, `ISSUES.md` should extend OCIA-004/005/014/016/035 and consider a distinct controller-navigation-history/concurrency risk, and durable navigation principles may later be summarized in `CODEX.md`. Those files are intentionally unchanged during this planning task.

## Immediate Next Work

Review the completed Stage 1 planner and host evidence. Stage 2 durable controller mission persistence is the next implementation candidate but remains unauthorized until a separate explicit GO. Do not bundle Stage 3 execution or Stage 4 sensing/detours into that persistence work. The already-completed supervised Potato prototype remains the physical-orchestration evidence on which the later execution design is based.

The deferred Milestone 1 acceptance queue remains:

1. While Wheatley is idle in a safe pose, restart `robotd` and retry an exactly retained request ID/operation; confirm a cached response and no physical action.
2. Send a recorded physical request ID from the superseded first epoch; confirm `stale_epoch` and no movement without recommissioning merely to arrange the test.
3. Exercise compaction with safe turns or a controlled minimum threshold. Verify generation increase, bounded records/bytes, pose/epoch/high-water persistence, retained/retired behavior, restart recovery, then restore production configuration.
4. Use a safe receive-side harness to suppress one successful reply. Confirm controller certainty `unknown`, then retry only the identical ID/operation and observe the cached result without another action.
5. Use controlled hooks for interrupted-`prepared` and interrupted-`executing` boundaries. Verify the exact classifications and no-replay guarantees in [MILESTONE1.md](MILESTONE1.md); do not improvise by killing Minecraft during a physical action.
6. Complete the ambiguous-execution legacy/manual/restart test, then physically reconcile and explicitly commission a new epoch. Keep foreign-sender, second-robot isolation, malformed live packet, component-error, sustained-resource, and power-loss tests visible as separate remaining coverage.

The next Refined Storage validation session should execute Phase 6 Tests A through F in order. Tests A and B are read-only; Test C should use an inexpensive recipe; Tests D and E should move one ordinary Dirt through a dedicated adjacent chest. Record exact return values, side constants, physical inventory changes, and failure behavior before writing the provisioning module.

The next Wheatley hardware session should run small supervised probes at the dock or in a disposable test area:

1. Enumerate Inventory Controller methods and record internal and external inventory results.
2. Equip and restore one inexpensive tool, recording slots and equipped-state evidence.
3. Record `robot.detect*` and `robot.compare*` behavior for representative safe targets.
4. Repeat the depot scan while facing all four headings to establish Geolyzer array order and rotation behavior.
5. Record scan/analyze energy cost, additional noise samples, zero-value behavior, and selected modded-block results.
6. Characterize the Tier 2 Battery through observed `computer.maxEnergy()` and operation endurance.
7. Load and return one expendable item through the dock Ender Chest before designing manifest transfers.
8. Determine which 9x10 observations are positive identifications, comparisons, categories, density estimates, or unavoidable unknowns.
9. Run the first complete survey-and-plan acceptance test with world-changing operations disabled.

For charging, measure robot energy at the expected charging pose with the Lever on and off. Establish the observation interval and minimum positive energy delta that will prove charging without confusing ordinary energy use or a full buffer with failure.

## Handoff Notes

- Existing source and unrelated user changes must be preserved carefully.
- Robot daemon restart and resumed communication after an idle interruption, plus sequential legacy and OCIA controller use, are demonstrated in OpenOS. Broader concurrency, graceful shutdown, and unusual port-ownership failure cases remain untested.
- Legacy physical driving intentionally marks autonomous pose untrusted. Return to origin facing North and use the local recovery tool before autonomous work resumes.
- Full completed results are retained only for the configured recent window. OpenOS now demonstrates epoch creation/rotation, contiguous high water through sequence 4, retained duplicate suppression before restart, and two retained results across a normal restart. Retirement, stale-packet rejection, compaction, and sustained memory/disk cost remain unverified in game.
- Official OpenComputers source for the `1.12.2-forge/1.8.8` tag confirms that `robot.compareDown` is available without an Inventory Controller Upgrade.
- Detailed item-stack inspection requires the now-installed Inventory Controller Upgrade; its operational methods remain untested.
- The Inventory Controller Upgrade does not identify terrain blocks.
- Installed 1.8.8 code exposes no general `robot.inspect*`; detailed adjacent block analysis belongs to Wheatley's installed Geolyzer.
- Geolyzer density scans and adjacent analysis are demonstrated, but coordinate mapping and production thresholds are not.
- Ordinary robot placement requires a supporting surface unless Angel placement is available.
- The verified Charger requires redstone activation in normal mode. Charging particles and an energy increase were observed after commanded return to the dock, but controlled charge-rate/negative tests and autonomous docking remain untested.
- OpenComputers defaults permit at most eight packet data parts and 8192 bytes per packet; keep messages compact.
- Do not implement mandatory Dead Bush return logic; it is an optional legacy trigger only.
