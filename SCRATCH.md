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
- Navigation MVP Stages 1 through 3 are implemented and host-validated. `lib/ocia/nav.lua` provides pure minimum-cost nominal routes; `lib/ocia/nav_state.lua` provides the durable controller mission lifecycle; and `home/ocianav.lua` integrates `plan`, `go`, `status`, `return`, and `resume` with the existing transport and robot executor. The first supervised flat Stage 3 round trip passed in Minecraft on 2026-11-02. A repository-only extension now permits vertical movement and bounded reactive local traversal; it has not been deployed or accepted in Minecraft.
- `deploy.lua` provides explicit allowlist deployment to controller, robot, or both. It defaults to dry run, compares bytes, backs up replaced files under `.deploy-backups/`, stages same-directory replacements, and verifies installed bytes. The proposed manifest is now 14 controller files and 11 robot files, including one generated `/etc/ocia.cfg` per role; controller navigation journals and archives remain excluded.
- `deploy.local.lua` is the ignored, authoritative local mapping from logical roles to one world save, two HDD UUIDs, and two confirmed modem UUIDs. The committed `deploy.local.lua.example` contains placeholders only.
- The Stage 3 controller navigation implementation was installed for the successful supervised 2026-11-02 acceptance run. The newer basic-3D source and `nav_probe` protocol/robot changes exist only in the repository and have not been deployed to either live HDD.
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

**Status: overall architecture accepted; Stages 1 and 2 are implemented and host-validated on 2026-11-01. Stages 3–5 remain unimplemented and require separate authorization.** This design builds directly on the successful supervised 3x3 Potato patch: the controller issues one physical operation at a time, Wheatley journals it, and the controller validates the correlated result and expected pose. The navigation MVP adds route choice, bounded reactive detours, durable controller mission state, actual-route breadcrumbs, and supervised return home without replacing that execution path.

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

At Stage 1 completion, no CLI, controller journal, robot/protocol/transport code, sensing, detours, physical execution, configuration, or deployment manifest had changed, and Stage 2 was the next separately authorized candidate. No deployment or Minecraft interaction occurred during that stage.

### Stage 2 implementation result: 2026-11-01

Controller `lib/ocia/nav_state.lua` now implements the narrow Stage 2 mission-state contract independently of Wheatley's physical journal. The proposed runtime path remains `/var/lib/ocia/nav.state`, but Stage 2 neither adds it to configuration/deployment nor accesses a live OpenOS disk. The module exposes pure mission creation and status assessment, a file-backed injected `journalStore`, a host `memoryStore`, exact intent preparation and reconstruction, navigation-specific result classification, durable result/reconciliation transitions, destination and return transitions, terminal outcomes, and explicit terminal-only archive rotation.

The version-1 journal begins with one `mission` record and then appends only bounded transition records: `intent`, `result`, `reconcile`, `destination`, `return_start`, and `terminal`. Records use deterministic scalar-field encoding plus an FNV-style checksum and contiguous journal sequence. Replay rejects a missing mission header, unsupported format, noncontiguous sequence, invalid transition, checksum failure, partial final record, excessive record count, and archive-rotation marker. Normal writes treat successful OpenOS close as no-return-value success while catching exceptional close failure, matching the installed OpenOS behavior already established for the robot journal.

The public state behavior is:

- `createMission(status, specification)` accepts only a ready robot with healthy physical journal, valid epoch, trusted exact `(0,0,0)` North pose, valid destination, and an action limit no greater than 160. It copies caller data and records the robot's existing physical high water.
- `journalStore(path, injected APIs)` and `memoryStore()` provide `create`, `load`, and `append`; the file store additionally provides terminal-only `archive`. Creating over an existing journal is refused. Archive uses a durable `.archive.switch` marker and a mission-ID archive name; any uncertain marker, rename, or cleanup leaves rotation explicitly uncertain.
- `prepareIntent` validates the complete request through the existing protocol, requires the next contiguous `p:<epoch>:<sequence>` identity, derives the expected pose with `ocia.pose`, persists the intent before returning it, and permits only one unresolved physical intent. `requestForPending` reconstructs the identical request and fingerprint after replay. No Stage 2 code sends it.
- `classify` and `recordResult` distinguish success, completed physical failure, definite allocated nonexecution, local non-send, ambiguous send failure, timeout, robot rejection, robot recovery requirement, malformed/correlation failure, and pose contradiction. They inspect the complete transport/reply shape rather than `certainty` alone.
- Only correlated `operation_succeeded` appends an outbound breadcrumb. `operation_failed` and `interrupted_before_execution / not_started` consume their allocated sequence without changing pose or creating a breadcrumb, then require a freshly persisted matching robot-status reconciliation before another intent can be prepared.
- Ambiguous, rejected, malformed, or contradictory observations preserve the exact pending intent, enter `recovery_required`, and prohibit allocation of a new request identity. Status may recommend an identical-request retry but never resolves a pending operation or infers success from coordinates.
- `beginReturn` freezes the actual outbound breadcrumb and requires each return intent to equal `nav.inverse()` for the next breadcrumb. Confirmed return steps are durable and duplicate result application is rejected. Exhausting the return cursor yields `home_pending_reconcile`; exact trusted home pose plus matching epoch/high water in a fresh status record is required for `home_pose_reached`. `charging_verified` remains false because charging is Stage 5.

The controller and robot journals remain independent and nontransactional. A controller intent can be replayed safely only while Wheatley retains authoritative evidence for that exact request. Status alone cannot recover a retired result. Epoch, high-water, readiness, journal-health, or pose disagreement is external interference/manual-recovery evidence, not permission to advance. An owner label supports the future CLI's advisory single-mission convention but does not prevent `ociactl`, `ociafarm`, or `drive` from issuing commands.

Host validation passed `23 tests / 539 assertions` in the focused Stage 2 suite and `75 tests / 13424 assertions` in the integrated host suite. Coverage includes home-only creation, one active mission, exact replay identity, every result class, duplicate suppression, consumed failures/nonexecution, post-failure reconciliation, non-home resume/return, inverse turns/backward movement, retired/stale/interference cases, deterministic replay, malformed/checksum/partial journals, injected create/intent/result open-write-partial-write-flush-exceptional-close failures, archive marker/rename/cleanup failures, and the 160-action envelope. The deployment regression remains unchanged and confirms this module is not deployed.

Implementation defects found and corrected during the Stage 2 test-first pass were: file creation initially attempted to apply its already-materialized mission record twice; result records initially omitted operation/phase fields required to replay breadcrumbs; and the first implementation did not explicitly gate the next sequence on fresh reconciliation after a consumed failed/nonexecution result. All three now have regressions.

No design expansion was required. As approved, Stage 2 has no controller-journal compaction because the mission has a 160-physical-action cap and a 1024-record replay bound. Successful `write`, `flush`, and close still do not prove `fsync`-grade persistence. Normal complete-record restart is covered; sudden JVM termination, host power loss, storage loss, real OpenOS memory/timing, live result retirement, process concurrency, and physical controller/robot crash ordering remain unverified. There is no transaction across the two computers.

### Stage 2 hardening result: 2026-11-01

Independent review of commit `55827da` found three controller recovery defects. Focused failing regressions reproduced all three before correction:

1. The real robot's cached `failed / interrupted_before_execution` result contains `code`, `message`, and `physical_outcome=not_started` but no pose fields. The controller incorrectly required a pose and classified the authoritative result as contradictory. Classification now accepts that exact robot payload, preserves the controller's previously trusted pose, consumes the allocated sequence, creates no breadcrumb, and requires fresh status at the unchanged pose and consumed high water before sequence `+1`. Optional pose evidence is still parsed strictly; partial or contradictory pose fields and missing/non-`not_started` physical-outcome evidence fail closed.
2. A timeout or ambiguous `send_failed` left an exact pending intent but no supported way to authorize retransmission. Stage 2 now separates first-send and retry permission. `canTransmit()` is true only for the freshly persisted initial intent in the current process. `authorizeRetry(store, snapshot, status)` validates and appends a `retry_authorized` record using fresh ready/healthy status; `canRetryPending()` and `retryRequest()` then expose only the original request ID, epoch, sequence, operation, arguments, deployment ID, recipient, and fingerprint. Replay clears both runtime permissions, so a controller restart requires another fresh status authorization even when an older authorization record exists. A cached correlated result is applied once; timeout/send failure during the retry clears authorization; retirement, rejection, ambiguous execution, unhealthy state, or correlation/state mismatch cannot retry or allocate another sequence.
3. The file store previously encoded and appended a transition before `applyRecord()` validated it, so an ordinary invalid call could leave a checksummed but unreplayable journal. Both file and memory stores now copy the bounded snapshot, apply and validate the proposed transition on that candidate, encode/write only a valid record, and publish the candidate only after successful persistence. Invalid destination, return, result, termination, request-sequence, action-limit, and journal-limit transitions leave journal bytes, live state, metrics, and health unchanged; the existing journal remains replayable and later valid transitions still proceed. Write/flush/exceptional-close uncertainty still marks the authoritative live snapshot fail-closed without publishing the candidate transition.

Adjacent review found and corrected two related permission/state defects. A replayed unresolved intent previously regained `canTransmit()` without fresh status; initial-send permission is now runtime-only and cleared by replay. A retained success resolving an ambiguous request previously left the mission phase as `recovery_required`; a confirmed terminal result now restores the pending intent's original outbound/return phase before applying its normal pose, breadcrumb, failure, or return-progress effect.

The retry contract never interprets status coordinates or high water as proof of success. Fresh status only authorizes retransmission of the exact ID through Wheatley's existing at-most-once journal. Only the normally correlated retained result changes controller pose or breadcrumbs. A status at preallocation high water must match the before pose; status at the pending allocated sequence may match before or expected pose because neither proves the result. Any other epoch, high water, pose, readiness, or journal health requires manual recovery. Definite failure and definite nonexecution still consume their sequence and require a separate persisted ordinary reconciliation before a new physical ID is allocated.

Hardening validation passed `28 tests / 703 assertions` in the focused Stage 2 suite, `80 tests / 13588 assertions` in the integrated host suite, and `26 tests / 160 assertions` in the deployment suite. New coverage includes the exact robot recovery payload, optional contradictory pose evidence, missing physical-outcome evidence, complete lost-acknowledgment restart/retry/cached-success recovery with a one-call simulated robot endpoint, ambiguous send retry, stale retry permission after restart, retry interruption, retirement, status contradictions, duplicate result delivery, pre-write rejection invariants for both stores, invalid inverse return attempts, and bounded action/journal limits. Existing open/write/partial-write/flush/exceptional-close and replay-corruption tests remain green after the ordering change.

Stage 2 is ready for another Stage 3 authorization review at the host-test level only. No OpenOS deployment or Minecraft acceptance occurred. The controller still lacks a CLI, transport execution loop, real process-exclusivity enforcement, and live measurements of journal memory/timing. Successful OpenOS calls do not establish `fsync`; sudden JVM/host/power loss and the persistence ordering between independent controller and robot disks remain unproven and may require manual reconciliation.

### Stage 3 Implementation Plan: flat supervised navigation and exact inverse return

**Planning status: complete on 2026-11-01. Readiness verdict: CONDITIONAL GO after independent review and a separate implementation authorization.** The current checkout is commit `6cfaa76619f8652c96feabcfc3d0ab218e9d8845` (`Stage 2 Hardening Round`), matching `origin/master` with a clean worktree before this planning-only documentation update. Stage 1 and Stage 2 provide the required planner, intent journal, result classifier, exact-request retry contract, actual-action breadcrumbs, inverse-return state, and archive rotation. No protocol or robot-side change is required for Stage 3.

The condition is one narrow controller-journal lifecycle correction plus cooperative controller-process ownership:

1. `nav_state.classify()` correctly identifies `local_rejection` as `local_nonsend`, but `applyRecord()` currently treats every classification other than success, completed failure, or definite nonexecution as an ambiguous unresolved intent. This leaves a request proven not to have reached `modem.send` permanently pending, prohibits `terminate()`, and prevents safe archive rotation. Stage 3 must add a durable, host-tested definite-local-nonsend transition that restores the pending intent's original outbound/returning phase, clears the pending intent, and sets `reconciliation_required=true` without advancing robot high water, changing pose, adding a breadcrumb, or counting a physical action. The CLI stops after recording it; a later invocation may move only after fresh status reconciliation. It must not generalize this behavior to `send_failed`, timeout, rejection, recovery-required, malformed, or contradictory results.
2. Port `4242` is globally open on the controller and `event.pull` consumers compete for the same event stream. Current `drive.lua`, `ociactl.lua`, and `ociafarm.lua` have restart-safe port open/close ownership but no process-exclusivity convention. Stage 3 should add one small controller-only cooperative owner module using the installed OpenOS 1.8.8 `process.list` / `process.info().data` process registry, then make all four controller programs acquire it while consuming modem events. Process exit removes the process record, avoiding a persistent stale lock after interruption. This is advisory: it prevents concurrent cooperating repository programs, not arbitrary third-party code. `drive.lua` remains the manual recovery path; interrupt the active OCIA controller process first, then start `drive`.

Neither condition requires redesigning Stage 1 or Stage 2. The local-nonsend correction is the smallest missing state transition, and cooperative ownership is isolated from the protocol and mission journal. Implementation must stop if either change requires robot firmware, a new protocol operation, or a broader navigation architecture.

#### Inspected source contracts and implementation boundaries

The implementation must use the source contracts below rather than historical shorthand:

- `nav.plan(startPose, destination[, options])` returns a deterministic record containing `operations`, `cost`, `movement_count`, `turn_count`, `expected_end`, `inverse_cost`, `distance`, `max_distance`, `terrain_model="unobstructed"`, and `traversability="unknown"`. It accepts nonzero Y and has only the pure dependency `ocia.pose`. Stage 3 execution, not the planner, enforces `destination.y == 0`.
- `nav.inverse(operations)` reverses and inverts turns, forward/backward movement, and vertical movement. Stage 3 return does not invert the original nominal plan directly; `nav_state.prepareIntent()` enforces the inverse of the breadcrumb at `return_state.cursor`.
- `nav_state.createMission(robotStatus, specification)` requires `mode="ready"`, `journal_health="healthy"`, a valid nonempty epoch, trusted exact home `(0,0,0)` North, a valid destination, and an action limit from 1 through 160. It records the robot's existing physical high water but does not create the file; `store.create(snapshot)` must durably write the mission header.
- `prepareIntent(store, snapshot, specification)` validates the operation and complete protocol request, allocates exactly `high_water + 1`, derives the expected pose with `pose.apply`, and appends the intent before returning it. In `returning`, it accepts only the exact inverse of the frozen breadcrumb and requires the expected pose to equal that breadcrumb's `before` pose.
- A newly appended intent has runtime-only `transmit_authorized=true`; `canTransmit()` is the only permission for its first send. `journalStore.load()` deliberately clears both transmit and retry permission. A replayed intent, including one likely persisted before any send, must use fresh status plus `authorizeRetry()` and `retryRequest()` rather than regaining first-send authority.
- `requestForPending()` reconstructs the exact request. The existing `transport:sendRequest(operation, options)` can transmit it by passing the recorded `request_id`, `deployment_id`, and decoded `arguments`. Before doing so, the CLI must confirm that the pending recipient equals the current configured robot address; transport always sends to `config.robot_address` and offers no recipient override.
- `recordResult()` calls the closed `classify()` allowlist and appends a result before publishing its effect. Only correlated `succeeded / operation_succeeded` changes pose or appends a breadcrumb/return step. `failed / operation_failed` and authoritative `interrupted_before_execution / not_started` consume the sequence, count one physical action, preserve pose, clear pending, and set `reconciliation_required=true`.
- `assessStatus()` validates robot readiness, journal health, epoch, high water, and pose. With an eligible pending intent it returns `retry_identical`; status is authorization evidence only and never proof that the physical operation succeeded. Without a pending intent it returns `continue` only for exact epoch/high-water/pose agreement.
- `recordReconciliation()` persists an exact no-pending status match and clears the post-failure reconciliation gate. When inverse return has exhausted its cursor, the same transition is the only path from `home_pending_reconcile` to `home_pose_reached`.
- `authorizeRetry()` durably records fresh status permission for only a pending intent with no observation, timeout, or ambiguous send failure. `canRetryPending()` and `retryRequest()` expose the exact request only in the current process after that authorization. Replay clears permission again.
- `markDestination()` requires outbound phase, no pending request, and a pose satisfying destination coordinates plus optional heading. `beginReturn()` freezes the successful outbound breadcrumb count and may start from outbound, at-destination, or recovery-required only when no intent is pending. `terminate()` requires no pending intent. File-store `archive()` requires a healthy terminal mission and uses `.archive.switch` plus a mission-ID archive filename; any marker, rename, or cleanup uncertainty fails closed.
- `transport:sendRequest()` already validates local request construction, modem delivery, sender/local recipient/port, protocol parsing, and request/reply correlation. Its `certainty` field is intentionally too coarse for navigation; Stage 3 must always pass the complete response to `nav_state.recordResult()`.
- Robot `executor.handle()` already supplies durable `prepared`, `executing`, and `completed` ordering; cached duplicate results; contiguous epoch sequences; structured unchanged-pose failures; and recovery-required ambiguity. `robotd.lua` already dispatches all six Stage 3 movement/turn operations. No sensor request, protocol extension, robot state change, or new executor action is needed.
- The Stage 2 journal is bounded by the 160-physical-action mission limit and 1024 records. Existing tests measured 160 successful physical actions at no more than 321 records and less than 512 KiB. Stage 3 adds no controller-journal compaction.

One source-level difference from the older architecture prose is important: Stage 2 persists the destination and actual breadcrumbs, not the original nominal operation list or an outbound plan index. After a clean no-pending restart, Stage 3 should deterministically call `nav.plan(snapshot.pose, snapshot.destination, ...)` again and continue from the reconciled actual pose. A changed nominal suffix is acceptable because every successful physical action becomes a breadcrumb and return inverts the actual history. A pending operation is never replanned around; it must first resolve under the exact-request contract.

#### Exact implementation scope

Create or modify only the following files during the separately authorized implementation:

| File | Planned Stage 3 responsibility |
|---|---|
| Controller `home/ocianav.lua` | Thin but testable command entrypoint; parse commands, keep `plan` hardware-free, construct live dependencies only for other commands, render status/plan, request confirmations, drive the durable one-operation execution/recovery loops, and guarantee port-owner release. |
| Controller `lib/ocia/controller_owner.lua` (new) | Cooperative per-port process ownership using OpenOS `process.list` and current process data; injected registry seam for host tests; acquire/refuse/release without a disk lock or runtime-state deployment target. |
| Controller `lib/ocia/nav_state.lua` | Minimal definite-`local_nonsend` durable resolution described above; no other classification or replay semantics change. |
| Controller `home/drive.lua` | Acquire/release cooperative controller-port ownership while preserving the legacy command/reply format and manual recovery behavior. |
| Controller `home/ociactl.lua` | Acquire/release cooperative ownership around modem event consumption; otherwise retain the diagnostic probe behavior. |
| Controller `home/ociafarm.lua` | Acquire/release cooperative ownership around its current supervised execution; no farm planner/executor behavior change. |
| `deploy.lua` | Add allowlisted controller entries for `home/ocianav.lua`, `lib/ocia/nav.lua`, `lib/ocia/nav_state.lua`, and `lib/ocia/controller_owner.lua`. Never add `/var/lib/ocia/nav.state`, locks, archives, or other runtime state. |
| `tests/nav_state_cases.lua` | Update the local-nonsend expectation and add exact replay/invariant tests for its durable resolution. |
| `tests/nav_cli_cases.lua` and `tests/nav_cli_test.lua` (new) | Focused parser, preview, orchestration, recovery, ownership, mocked transport, restart, and zero-sensor coverage. |
| `tests/run.lua` | Register the Stage 3 cases in the integrated host suite. |
| `tests/deploy_test.lua` | Assert the expanded controller manifest, source existence, selective installation, and continued protection/preservation of navigation runtime state. |

`nav.lua`, `pose.lua`, `protocol.lua`, `transport.lua`, all robot files, the farm library, configuration templates, and runtime-state formats otherwise remain unchanged. The journal path is the fixed controller-local `/var/lib/ocia/nav.state`; do not overload the existing robot `state_path` configuration key or expand generated configuration merely to hold this one Stage 3 constant.

The `ocianav.lua` implementation should expose a callable `main(arguments, dependencies)` or equivalent injected entry seam while remaining directly executable under OpenOS. Hardware modules (`component`, `event`, `computer`, configuration, modem, filesystem journal, UUID generation, and controller owner) must be required or constructed only after parsing chooses a live command. The `plan` path may load only `ocia.nav` and `ocia.pose`; its isolation test should fail if it touches component, modem, event, filesystem, journal, configuration, UUID, process ownership, or live status.

#### CLI contract

Supported syntax is deliberately closed:

```sh
ocianav plan --x X --y Y --z Z [--heading north|east|south|west]
ocianav go --x X --y 0 --z Z [--heading north|east|south|west]
ocianav status
ocianav return
ocianav resume
```

- Coordinates are required signed base-10 safe integers. Reject duplicates, missing values, fractional/scientific forms, unsupported flags, extra positional arguments, invalid headings, and destination distance beyond `nav.DEFAULT_MAX_DISTANCE`. Use exit `2` for usage/validation failures, `1` for operational/recovery stops, and `0` only for a successfully completed command or an intentional confirmation cancellation before state changes.
- `plan` prints the explicit assumed start `(0,0,0) North`, destination, ordered operations, movement/turn/total/inverse costs, expected end pose, max-distance and 160-action policy limits, `terrain_model=unobstructed`, and `traversability=unknown`. It must state that it contacted no robot and wrote no state. Nonzero Y is permitted in preview.
- `go` rejects nonzero Y before hardware access. It acquires controller-port ownership, loads `/var/lib/ocia/nav.state`, and refuses corrupt, uncertain, active, or unresolved state. A healthy terminal file is not silently overwritten; `resume` or the completion path must archive it first. It requests fresh correlated status and requires Stage 2's healthy ready trusted home contract. It computes the home-based plan and requires `2 * plan.cost <= action_limit` before acceptance. It displays every operation, expected pose, outward and inverse budgets, lack of sensing/obstacle handling, no energy-reserve guarantee, and the fact that arrival does not prove charging. Only literal `NAVIGATE` proceeds. Cancellation occurs before mission creation.
- After confirmation, `go` creates a UUID mission with owner `ocianav`, destination, action/max-distance limits, and diagnostic planned outbound/return costs, then calls `store.create()` before preparing the first physical intent. A zero-operation home destination is still a durable mission: mark destination without sending a physical request.
- `status` acquires the cooperative port owner, sends exactly one nonphysical `status` request, and separately attempts a read-only controller journal load. It prints live certainty/code, ready/recovery state, epoch/high water, pose, energy, and robot journal health; controller journal source/health, mission ID, phase, pose, high water, physical-action count/limit, pending request/classification, reconciliation gate, breadcrumb count, return cursor, home flag, charging flag, terminal outcome, and archive artifact/corruption diagnostics. It does not call `store.create`, `append`, `archive`, `prepareIntent`, `authorizeRetry`, or `recordReconciliation`. Absence is `no active controller mission`, not an invitation to create one.
- `return` requires a healthy existing nonterminal mission and fresh exact status reconciliation. An unresolved pending intent must be handled by `resume`, never bypassed. After displaying the frozen actual-breadcrumb inverse, remaining action budget, current pose, and limitations, only literal `RETURN` calls `beginReturn()`. It may return from a partially completed outbound mission after any required consumed-failure reconciliation. It sends exact inverse steps until home-pending-reconcile or the first non-success. It never plans a nominal route home and never adds return steps to the outbound breadcrumbs.
- `resume` never creates a mission or epoch. It loads the journal, obtains fresh status, and calls `assessStatus()`. It prints the exact proposed recovery/continuation before literal `RESUME` confirmation. With a pending eligible intent it must call `authorizeRetry()`, verify `canRetryPending()`, obtain only `retryRequest()`, and resend that identity. With no pending intent it calls `recordReconciliation()` before further movement, then either replans the outbound suffix from the reconciled pose or continues the frozen return cursor. `at_destination` requires no motion; `home_pending_reconcile` performs only status reconciliation; `home_pose_reached` performs only terminal/archive completion. Robot rejection, recovery-required, retired result, contradictory status, unhealthy state, or a non-retryable pending classification is a manual-recovery stop.
- Every movement command prints mission ID, request ID, operation, before/expected pose, response classification, resulting durable phase/high water, physical action count, energy evidence if returned, and whether execution stopped. Output must distinguish controller persistence failure from robot/transport failure.

#### Durable execution and lifecycle

Use one shared execution helper inside `ocianav.lua`, not a new orchestration framework:

1. Before starting or continuing a route, validate flat execution (`snapshot.pose.y == 0`, destination Y zero, and every recomputed operation horizontal/turn only), journal health, no unhandled reconciliation gate, and sufficient action budget. For outbound continuation, conservatively require capacity for all remaining nominal outbound successes plus return of all existing and prospective breadcrumbs: `physical_actions + remaining_outbound + #breadcrumbs + remaining_outbound <= action_limit`. For return, require `physical_actions + return_state.cursor <= action_limit`.
2. For each operation call `prepareIntent()` with configured robot recipient and empty arguments. If persistence fails, send nothing and stop. Confirm `canTransmit()` and reconstruct with `requestForPending()`; do not retain a separately built request as authority.
3. Transmit through existing `transport:sendRequest()` using exactly the pending operation, ID, deployment ID, and decoded arguments. Pass the complete returned table to `recordResult()` exactly once. A result-persistence failure stops immediately; do not use the uncertain in-memory classification to advance.
4. Continue only when the durably recorded classification is `success`. For `completed_failure` or `definite_nonexecution`, request fresh status and attempt `recordReconciliation()` for the consumed unchanged-pose sequence, then stop the invocation even if reconciliation succeeds. This keeps obstruction/nonexecution supervised and prevents an automatic retry loop.
5. For the new definite `local_nonsend`, durably restore the intent's original phase, clear the unsent pending intent without consuming high water, set the reconciliation gate, and stop with a configuration/programming diagnostic. For `send_ambiguous`, timeout, rejection, recovery-required, malformed, or contradictory results, retain the exact pending identity and stop. Do not automatically call `authorizeRetry()` in the same invocation.
6. After the outbound suffix is exhausted, verify the durable pose satisfies destination and call `markDestination()`. Do not infer arrival solely from the local loop counter.
7. During return, use the operation required by the breadcrumb at `return_state.cursor`; `prepareIntent()` independently verifies the exact inverse and predecessor pose. After cursor zero, request fresh status and call `recordReconciliation()` to reach `home_pose_reached`. Do not set or print `charging_verified=true`.

Normal completion lifecycle is:

```text
outbound -> at_destination -> returning -> home_pending_reconcile
    -> home_pose_reached -> terminal -> archived history
```

If return began before reaching the requested destination, reaching home is a safe abort rather than successful navigation. Determine this from the frozen outbound breadcrumb endpoint (or home for an empty breadcrumb) against the mission destination; record terminal outcome `aborted` with a specific reason. Only a mission whose outbound history reached its destination may terminate as `navigation_complete`. Both outcomes still report `charging_verified=false`. After the terminal record persists, immediately call file-store `archive()`. A crash after terminal but before archive is completed by a later `resume` after fresh consistent status. Archive uncertainty blocks `go`; no active or uncertain journal is overwritten. Archives remain ordinary OpenOS state/history and are not deployment targets.

An operator may leave an active at-destination, partial-outbound, returning, or recovery-required mission for inspection. There is no Stage 3 `abort` command that discards it. Safe ways forward are `return`, `resume`, or manual physical reconciliation under the existing recovery procedure. Never delete, truncate, or rename an active journal by hand as part of ordinary CLI flow.

#### Recovery matrix for the Stage 3 CLI

| Evidence after a persisted intent | Durable state and sequence | Required Stage 3 action |
|---|---|---|
| Newly persisted, current-process intent | Pending; controller high water unchanged; first-send permission runtime-only | Send once only if `canTransmit()`; otherwise stop. |
| Correlated `operation_succeeded` | Result consumes sequence, advances pose, adds exactly one outbound breadcrumb or return step | Continue only after `recordResult()` persists. |
| Correlated `operation_failed` | Consumes sequence, unchanged pose, no breadcrumb, reconciliation required | Fetch fresh status, persist exact reconciliation if possible, then stop. Later supervised `return` or `resume` may proceed after the obstacle is cleared; no detour. |
| `interrupted_before_execution` plus `physical_outcome=not_started` | Consumes sequence, unchanged pose, no breadcrumb, reconciliation required | Reconcile fresh status, stop, and require `resume` confirmation before issuing a new contiguous ID. |
| Proven `local_rejection` before send | With the planned correction: original phase restored, pending clears, high water/pose/action count unchanged, reconciliation required | Diagnose/fix local request/configuration defect, reconcile fresh status, and stop. Never classify it as terrain or ambiguous delivery. |
| `send_failed` | Pending exact request retained; delivery/outcome ambiguous | Stop. On later `resume`, fresh status may authorize only the identical request. |
| Timeout/lost acknowledgment | Pending exact request retained; outcome ambiguous | Stop. Later `resume` uses fresh status, `authorizeRetry()`, and the identical request; only the cached correlated result advances state. |
| Robot `rejected` | Pending retained; rejection does not prove allocation state | Manual recovery/diagnosis. No new ID and no archive while pending. |
| Robot `recovery_required` | Pending retained; physical state may be unknown | Manual physical reconciliation under existing procedure; no automatic movement. |
| Malformed, stale, mismatched, or pose-contradictory response | Pending retained; response is not authority | Stop as recovery-required; no inference from pose/high water. |
| Restart with unresolved intent and no result observation | Replay clears first-send authority | Fresh status plus `authorizeRetry()` and explicit `RESUME`; resend only `retryRequest()`. |
| Restart after timeout/send ambiguity | Same exact pending observation replays; retry permission clears | Fresh authorization and explicit `RESUME` for each retry attempt. |
| Restart after robot success but before controller result persistence | Journal may replay pending, completed, or corrupt depending which complete record reached disk | If pending, exact retry obtains cached robot result; if completed, reconcile; if corrupt/uncertain, stop for manual recovery. |
| Controller intent persistence failure | No permitted send; journal health uncertain | Stop immediately and reload in a new invocation; never repair or continue the live snapshot. |
| Controller result/reconciliation/terminal/archive persistence uncertainty | No effect may be assumed from the live object | Stop; reload and inspect complete records/artifacts. Partial/corrupt state is manual recovery. |
| Robot result retired before controller recovery | Exact retry returns rejection; status cannot reconstruct outcome | Manual recovery; never infer success from current coordinates. |
| External `drive`, `ociactl`, `ociafarm`, epoch rotation, or another physical high-water change | Status disagrees with controller mission | Stop as interference. Legacy movement remains pose-invalidating and requires recommissioning. |

The two journals remain independent. This plan claims safe ordering under validated append/replay and retained-result behavior, not a distributed transaction or `fsync`-grade survival of JVM/host/power loss.

#### Cooperative controller-port ownership

`controller_owner.acquire(port, label)` should inspect the installed OpenOS process registry and place a unique owner record in the current process's `process.info().data`. Registry inspection must use the record's own data (`rawget`) rather than inherited parent-process data, because OpenOS gives child process data an `__index` link to its parent. It refuses when another live cooperating process owns the same port, returns an idempotent release function/token, and never opens or closes the modem itself. All modem-consuming controller programs acquire before `modem.open`/`event.pull` and release on normal return and protected error cleanup. Existing `openedHere` logic remains responsible only for the modem port.

Host tests inject a fake process registry to cover first acquire, conflicting acquire, different ports, same-process behavior, release, and cleanup after an error. The first OpenOS acceptance session must also start one harmless status client while another cooperating client holds the owner and confirm refusal without consuming an event. This mechanism cannot exclude unmodified third-party programs and is therefore diagnostic/advisory, not a safety proof. Do not use a persistent lock file: OpenOS `filesystem.open` supports only `r/rb/w/wb/a/ab`, not exclusive-create mode, and a crash-stale disk lock would obstruct `resume`.

#### Implementation sequence and stopping points

1. **Close the local-nonsend lifecycle gap.** Add focused failing tests first, implement only the definite-local-nonsend transition, and rerun Stage 2 tests. Stop if any ambiguous class becomes clearable or any high-water/pose/breadcrumb value changes.
2. **Add cooperative ownership.** Implement the injected process-registry helper and focused tests, then integrate it into `ociactl`, `ociafarm`, and `drive` without changing their wire behavior. Stop if the manual driver cannot be restored simply by ending the active owner process.
3. **Build pure parsing and preview.** Create the testable `ocianav` entry seam and implement `plan` with no live dependencies. Add exhaustive CLI validation and dependency-boundary tests before any modem orchestration.
4. **Implement read-only status and journal inspection.** Mock status transport and every journal source/health result. Confirm no append/archive or physical ID allocation occurs.
5. **Implement mission creation and one-operation outbound execution.** Add home/status gating, flat-execution and round-trip budget checks, `NAVIGATE`, mission creation, intent-before-send assertions, correlated success, and destination marking. Stop before implementing resume or return and review the exact append/send order.
6. **Implement recovery/resume.** Cover unsent replay, lost acknowledgment, ambiguous send, cached success, consumed failures, result-persistence uncertainty, retired results, and external interference. Require `RESUME` before any recovered or continued physical action.
7. **Implement frozen inverse return and completion.** Add `RETURN`, exact cursor execution, home reconciliation, outcome selection, terminal record, and safe archive continuation after restart.
8. **Expand deployment allowlist and regressions.** Add only the four Stage 3 controller runtime files. Prove `/var/lib/ocia/nav.state`, archive markers/history, robot state, unrelated files, and manual configuration remain untouched by dry-run/apply fixtures.
9. **Run full host gates and independent review.** Require focused Stage 3, integrated, deployment, Lua 5.3 parse, `git diff --check`, and a manifest dry run. Do not deploy or enter Minecraft until the implementation diff receives separate review.

Each step is independently reviewable. No later step may conceal a failed earlier safety invariant by adding recovery heuristics.

#### Host-test matrix

Reuse `tests/nav_cases.lua` for route determinism and inverse math, `tests/nav_state_cases.lua` for journal/replay/fault semantics, its existing virtual-filesystem patterns for injected OpenOS failures, and the existing mocked transport shapes from `tests/run.lua`. New CLI cases should use injected input/output, configuration, owner, store factory, UUID, status sender, and physical sender; they must not depend on real components or the live world.

Required new or extended coverage:

1. Parse all five commands; signed coordinates and all headings; reject missing/duplicate/unknown/noninteger/unsafe values and arguments on status/return/resume.
2. Load `plan` in an environment without component, event, computer, filesystem, config, UUID, process, journal, or modem; assert exact deterministic output and zero writes/sends for flat and nonzero-Y previews.
3. `go` rejects nonzero Y before live dependencies; rejects non-home/untrusted/unready/unhealthy status, absent epoch, invalid high water, active/unresolved/corrupt/uncertain controller journals, and destination beyond policy.
4. Enforce `outbound + inverse <= 160` at creation and the conservative remaining-route/return formula after consumed failures. Test the exact boundary and one action over it.
5. Confirmation mismatch sends no physical request and creates no journal. Literal `NAVIGATE`, `RETURN`, and `RESUME` are case-sensitive.
6. Assert chronological ordering `mission create -> intent append -> modem send -> result append`; inject a failure at each persistence boundary and assert no unauthorized later call.
7. Correlated success advances pose/high water and appends one actual breadcrumb; duplicate result delivery cannot append twice. Wrong request, deployment, operation, fingerprint, payload, or pose fails closed.
8. Outbound restart with no pending recomputes a deterministic suffix from durable actual pose. Restart with pending and no observation cannot use `canTransmit`; it requires fresh `authorizeRetry` and identical `retryRequest`.
9. Definite failure and definite nonexecution consume high water without pose/breadcrumb change, require fresh reconciliation, and stop the invocation even after successful reconciliation.
10. Definite local non-send restores the original phase, clears only the unsent intent, leaves high water/pose/action count unchanged, and gates movement on reconciliation; send failure/timeout/rejection/recovery-required/malformed/contradictory responses remain pending and non-clearable.
11. Lost reply fixture executes a simulated robot endpoint once, restarts the controller, authorizes exact retry, receives cached success, records one breadcrumb, and never makes a second physical call.
12. Restart after simulated physical success but before result persistence covers intent-only replay, complete-result replay, flush/close uncertainty, partial corruption, and retired-result rejection.
13. Exact return inverts actual breadcrumbs containing turns, forward movement, backward movement, and a partial outbound route; no planned-but-unsent or failed operation appears. Restart during return preserves cursor and sends only the next inverse.
14. Home coordinates without fresh reconciliation remain `home_pending_reconcile`; exact status produces `home_pose_reached`; charging remains false. A partial mission returning home terminates `aborted`, while a reached-destination mission terminates `navigation_complete`.
15. Terminal archive succeeds only for healthy no-pending state; restart between terminal and archive resumes rotation; marker/rename/remove faults remain explicit and block a new mission.
16. `status` reports absent, healthy, pending, recovery-required, corrupt, uncertain-write/rotation, terminal, archived, and live-status-unavailable cases without mutation.
17. Controller owner covers conflict, release, error cleanup, and all four cooperating programs; modem close remains limited to the process that opened it.
18. Record every transport operation and assert Stage 3 emits only `status`, `turn_left`, `turn_right`, `move_forward`, and `move_backward`. Assert zero `nav_probe`, `detect`, analyze, scan, swing, place, use, vertical physical execution, or robot-side changes.
19. Deployment tests expect the expanded controller manifest, install all Stage 3 source files selectively, reject any `var/lib/ocia/nav.state` manifest entry, and preserve preexisting navigation state, archives, markers, robot state, and unrelated HDD files byte-for-byte.
20. Run existing Stage 1/2/farm/installer regressions unchanged, both focused Stage 3 tests and the integrated suite, Lua 5.3 syntax checks for every Lua source/test, and `git diff --check`.

Host success authorizes only an implementation review. It is not OpenOS or Minecraft acceptance.

#### Supervised Minecraft acceptance plan

Deploy only after a separately reviewed implementation and an explicit deployment decision. Use the normal dry-run, confirm only the new allowlisted controller files change, apply with backups, restart the controller program as required for loaded Lua modules, and do not modify robot files for Stage 3.

Before any movement:

1. Physically verify Wheatley at commissioned `(0,0,0)` facing North. Confirm the robot journal is healthy/ready/trusted, record execution epoch and high water, and confirm the controller has no active/corrupt/uncertain navigation journal.
2. Visually verify the one-block West target is open and safe. North is occupied by the Charger, South by the supply Ender Chest, and East by the factory wall; do not substitute another initial direction.
3. Run `ocianav plan --x -1 --y 0 --z 0 --heading west`. Record its output and verify it performs no modem request or journal write.
4. Run `ocianav status`, record robot energy/capacity, memory, pose, epoch/high water, journal metrics, and controller journal absence. Confirm status does not change robot high water or physical journal size except for ordinary timing observations.
5. Exercise the cooperative owner with a harmless overlapping controller client and confirm the second client refuses before consuming port traffic. End the first client normally and confirm ownership releases.

First movement fixture:

```text
Start:       (0,0,0) North
Destination: (-1,0,0) West
Outbound:    turn_left, move_forward
Return:      move_backward, turn_right
Final:       (0,0,0) North
```

Run `go` and type `NAVIGATE`. Record mission ID; execution epoch; every request ID/fingerprint; controller and robot high water before/after; intent/result journal sequence; before/expected/reported pose; response code/message; energy; physical observation; and proof that no sensing request occurred. At destination, independently verify `(-1,0,0)` West and inspect `ocianav status` without mutation.

Run `return`, inspect the frozen two-entry breadcrumb inverse, and type `RETURN`. It must send `move_backward` then `turn_right`, reach exact home/North, request fresh status, persist `home_pose_reached`, keep `charging_verified=false`, write the appropriate terminal record, and archive the controller mission. Record the archive path and confirm a subsequent `status` reports no active mission plus live home state. Visible charging particles or an energy rise may be recorded as an observation but must not change Stage 3's charging flag or acceptance claim.

Only after that fixture passes:

1. Repeat a short straight-West trip, then one prepared open-area case where backward movement is nominally cheaper, recording exact inverse behavior.
2. Restart `ocianav` after one completed outbound action and verify fresh status reconciliation plus deterministic continuation from actual pose.
3. Use a safe receive-side harness to lose one successful reply. Verify the controller stops pending, `resume` requires `RESUME`, retransmits the identical ID, Wheatley returns the cached result, and the physical call occurs once.
4. Exercise restart after a persisted unsent intent using a controlled pre-send hook. Verify first-send authority is absent after replay and only fresh exact retry can proceed.
5. Place a safe solid obstruction in a prepared route. Verify one failed movement consumes its sequence, fresh status reconciles unchanged pose/high water, no sensor or detour request occurs, and supervised return uses only successful breadcrumbs after the obstruction is removed or an unblocked inverse exists.
6. Restart during inverse return after one completed inverse and verify the durable cursor selects exactly the next inverse.
7. Inject contradictory status/pose and a controlled persistence fault only through safe hooks or disposable state. Verify no subsequent physical request and preserve artifacts for inspection. Do not kill Minecraft during a physical operation.
8. Measure controller free memory, journal bytes/records, append time, and archive behavior across the short fixtures. These are Stage 3 runtime observations, not general long-mission or power-loss proof.

Acceptance requires physical observation to match every reported pose and request, exact home/North reconciliation, durable archive history, working manual recovery after ending `ocianav`, and zero sensor/probe calls. It does not accept obstacle avoidance, energy reserve, autonomous charging, unattended execution, or generalized outdoor navigation.

#### Open questions, limitations, and authorization gate

No unresolved architecture question prevents coding after review. The following are implementation-review questions whose answers are fixed by this plan and should be verified, not redesigned during coding:

- Confirm the minimal local-nonsend transition clears only a controller-proven pre-send rejection and leaves every possibly delivered request pending.
- Confirm the controller owner uses the installed OpenOS process registry rather than an exclusive file mode that OpenOS 1.8.8 does not expose.
- Confirm the CLI's exact exit codes and cancellation behavior are consistent across direct OpenOS execution and host injection without calling `os.exit` before cleanup.
- Confirm a recomputed outbound suffix is always derived from freshly reconciled durable pose and never used to bypass a pending exact request.
- Confirm the action-budget formula counts consumed failures/nonexecutions and preserves capacity for the full actual breadcrumb return.

Acceptable Stage 3 limitations are advisory rather than hostile-process exclusion, short supervised trips without a measured energy reserve, no sensing or obstacles, no automatic retry after a definite block, bounded retained-result recovery, no `fsync` or cross-computer transaction, no charging proof, and operator recovery after any ambiguous executing boundary. Stage 4 owns probes/detours; Stage 5 owns measured reserve and charging verification.

**Authorization gate:** this section authorizes planning only. It does not authorize source, test, manifest, live-HDD, Minecraft, commit, or push changes. Independent review should first approve the conditional-GO verdict, the narrow local-nonsend correction, cooperative owner scope, execution/recovery ordering, and host/Minecraft gates. Only a later explicit Stage 3 implementation GO may begin step 1 above.

### Stage 3 Implementation Results

**Implementation status on 2026-11-01: complete and host-validated; ready for independent code review, not deployment.** The separately issued Stage 3 GO authorized repository implementation and host validation only. No live HDD was modified, no Minecraft movement or acceptance test occurred, and nothing was committed or pushed.

Implemented files and decisions:

- New controller `home/ocianav.lua` implements the closed `plan`, `go`, `status`, `return`, and `resume` CLI. `plan` loads only `ocia.nav` and `ocia.pose`; every live command constructs dependencies after parsing, holds cooperative port ownership for the whole live context, and releases that ownership plus any `openedHere` modem action through protected cleanup.
- New controller `lib/ocia/controller_owner.lua` uses the OpenOS process registry as an advisory same-port owner. It reads each process's own metadata with `rawget`, so inherited parent metadata cannot masquerade as child ownership, and uses no persistent or automatically cleared disk lock. The implementation matches the official `1.12.2-forge/1.8.8` `process.lua`: `process.list` contains live process records, `findProcess()` returns the current record, child `data` inherits through `__index`, and process close removes the registry entry.
- `drive.lua`, `ociactl.lua`, and `ociafarm.lua` acquire ownership before opening the modem or consuming events, preserve separate `openedHere` close behavior, and release on normal completion, cancellation/early return, or protected error. The legacy interactive driver and existing request formats are unchanged.
- `nav_state.lua` now resolves only definite `local_nonsend` results by restoring the pending intent's original phase, clearing that provably unsent intent, and requiring fresh reconciliation without advancing high water, pose, action count, or breadcrumbs. Every potentially delivered or contradictory class retains the existing unresolved exact-request behavior.
- `ocianav go` takes fresh eligible-home status for preview, requires literal `NAVIGATE`, then takes a second correlated status and requires identical readiness, health, epoch, high water, trusted pose, and home orientation before mission creation. A mismatch creates no journal and sends no physical request.
- Each physical operation follows `prepareIntent -> canTransmit -> requestForPending -> transport -> recordResult`. Replay never regains first-send authority; `resume` requires literal `RESUME`, fresh status, `authorizeRetry`, `canRetryPending`, and `retryRequest` for the identical request. Clean no-pending outbound restart replans only the remaining suffix from freshly reconciled durable pose.
- Return requires fresh preflight status, previews the inverse of successful actual breadcrumbs, requires literal `RETURN`, rechecks status before `beginReturn`, freezes the cursor, and advances only correlated successful inverse results. A second horizontal-only check rejects any pre-existing vertical breadcrumb before Stage 3 can transmit it. Exact home/North requires another fresh reconciliation; charging remains false. Full missions archive as `navigation_complete`, while a successful return after partial outbound execution archives as `aborted`.
- `deploy.lua` now allowlists `ocianav.lua`, `controller_owner.lua`, `nav.lua`, and `nav_state.lua` on the controller only. Deployment regressions reject `var/lib/ocia/nav.state` as a manifest target and preserve active state, archive markers, archive history, robot state, and unrelated files.
- New `tests/nav_cli_cases.lua` and `tests/nav_cli_test.lua` provide injected CLI, transport, process-registry, and in-memory journal fixtures. Existing Stage 2 and deployment cases cover the narrow journal correction and protected runtime files; `tests/run.lua` includes Stage 3.

The approved nine-step sequence was followed without a protocol, robot firmware, configuration schema, journal format, or Stage 4/5 change. One defensive implementation detail was added during final review: Stage 3 rejects a legacy/pre-existing vertical breadcrumb before inverse return transmission, even though its own flat `go` path cannot create one. The CLI uses the Stage 2 persisted destination and breadcrumbs rather than adding a nominal route/index record, so clean outbound continuation is deterministic replanning from reconciled durable pose as anticipated by the plan.

Host validation results:

| Gate | Result |
|---|---|
| `lua5.3 tests/nav_test.lua` | 12 tests, 4,785 assertions, 0 failures |
| `lua5.3 tests/nav_state_test.lua` | 28 tests, 710 assertions, 0 failures |
| `lua5.3 tests/nav_cli_test.lua` | 23 tests, 182 assertions, 0 failures |
| `lua5.3 tests/run.lua` | 103 tests, 13,777 assertions, 0 failures |
| `lua5.3 tests/deploy_test.lua` | 26 tests, 173 assertions, 0 failures |
| `rg --files -g '*.lua' -0 \| xargs -0 -n1 luac5.3 -p` | all repository Lua files parsed successfully |
| `git diff --check` | clean |
| `lua5.3 deploy.lua` | dry run only; expected controller changes, all robot entries unchanged, no files modified |

Host coverage includes pure preview isolation, strict parsing and confirmations, home-only creation, post-confirmation epoch/high-water/pose/readiness/health drift, intent-before-send ordering, success breadcrumbs, definite obstruction, definite local nonsend, persistence faults, unsent replay, lost acknowledgment/cached exact-ID recovery, deterministic outbound continuation, action budgets, frozen inverse return, return restart, partial-mission abort archive, terminal rotation, read-only status, horizontal-only operations, ownership inheritance/conflict/cleanup, all four controller programs, and protected deployment state.

Remaining limitations and review gates are unchanged in substance. Cooperative ownership excludes repository programs but not hostile or unmodified consumers. OpenOS registry cleanup after process exit is not proof that application-level modem cleanup ran. Controller and robot journals are independent and ordinary OpenOS flush/close is not `fsync`; sudden JVM/host/power loss remains a manual-recovery boundary. The 160-action/1024-record limits are host-tested, but live controller memory, timing, and archive behavior are unmeasured. There is no sensing, obstacle avoidance, vertical execution, energy reserve, charging proof, automatic provisioning, or unattended operation.

**Next authorization gate:** independently review the Stage 3 diff and host evidence. If accepted, issue a separate deployment authorization for only the dry-run-listed controller files, then execute the documented supervised one-block-West fixture before any broader navigation test. Do not treat these host results as OpenOS or Minecraft acceptance.

### Stage 3 Independent-Review Hardening Result

**Refinement status on 2026-11-01: complete and host-validated; pending another independent review before deployment.** The review confirmed the major Stage 3 durability, exact-request recovery, actual-breadcrumb return, cooperative ownership, pure-plan, and deployment-boundary architecture. This pass changed only `home/ocianav.lua`, focused Stage 3 tests, and this working record. It did not change Stage 1, Stage 2 journal semantics or format, shared pose/protocol/transport, robot firmware, controller ownership, the deployment manifest, or any live HDD.

The three findings and corrections are:

1. **Pending `resume` lacked Stage 3 operation eligibility.** `runResume()` previously reached `authorizeRetry()` for any Stage 2-valid physical operation, including `move_up` and `move_down`. A shared `validateStage3Mission()` now runs before any resume retry authorization or movement and validates current/destination elevation, the pending operation and its before/expected poses, every successful outbound breadcrumb, completed return history, and all remaining frozen inverse operations. Incompatible state remains intact for read-only `status` and requires supervised manual recovery or a later navigation stage; it is never rewritten, discarded, or transmitted by Stage 3.
2. **Initial return budget read the uninitialized cursor.** `runReturn()` previously called the in-progress `budgetReturn()` while `return_state.cursor` was still zero, then discovered an excess only after persisting `return_start`. Initial return now uses `physical_actions + #breadcrumbs` through a distinct `budgetInitialReturn()` before confirmation and again after post-confirmation reconciliation but before `beginReturn()`. An already-started return still uses `physical_actions + return_state.cursor`, and `completeReturn()` retains its defensive check.
3. **`resume` confirmation lacked a complete action preview.** A phase-aware, read-only preview now precedes literal `RESUME`. Pending recovery prints mission/deployment identity, exact request ID and operation, before/expected poses, observation, same-ID semantics, and conditional outbound or frozen-return continuation. Clean outbound prints the recomputed ordered suffix, poses, consumed actions, round-trip requirement, and unobstructed-terrain assumption. Returning prints the frozen cursor, remaining inverse sequence, and budget. Nonmoving phases explicitly describe reconciliation, terminal, and archive work without calling it physical movement. The second status must exactly match the healthy epoch/high-water/trusted-pose evidence used for the preview. The prepared outbound suffix is reused for execution so an unchanged preview and execution cannot silently diverge.

New focused regressions prove pending `move_up`/`move_down` stop before retry authorization or send; vertical history at flat current/destination poses and frozen vertical return remain nonexecutable while `status` stays read-only; valid flat exact-ID recovery remains intact; initial return succeeds exactly at its limit and rejects an over-by-one case containing a consumed failed action before `return_start`; a partially consumed frozen cursor uses its remaining count; all physical preview classes render before confirmation; nonmoving destination/home/terminal phases describe their actual transitions; cancellation writes and sends nothing; post-confirmation status contradiction stops; and displayed outbound operations equal transmitted operations when evidence is unchanged.

Final host results for this refinement:

| Gate | Result |
|---|---|
| `lua5.3 tests/nav_test.lua` | 12 tests, 4,785 assertions, 0 failures |
| `lua5.3 tests/nav_state_test.lua` | 28 tests, 710 assertions, 0 failures |
| `lua5.3 tests/nav_cli_test.lua` | 31 tests, 283 assertions, 0 failures |
| `lua5.3 tests/run.lua` | 111 tests, 13,878 assertions, 0 failures |
| `lua5.3 tests/deploy_test.lua` | 26 tests, 173 assertions, 0 failures |
| `rg --files -g '*.lua' -0 \| xargs -0 -n1 luac5.3 -p` | all repository Lua files parsed successfully |
| `git diff --check` | clean |
| `lua5.3 deploy.lua` | dry run only; expected controller changes, every robot entry unchanged, no files modified |

All previous live-world limitations remain: cooperative ownership is advisory, OpenOS flush/close is not `fsync`, independent controller/robot journals have no distributed transaction, live memory/timing/interruption behavior is unmeasured, and Stage 3 still provides no sensing, detours, vertical execution, energy reserve, charging proof, or unattended operation. Host success is not OpenOS or Minecraft acceptance.

**Hardening authorization gate:** independently review this narrow correction and its regressions. Only after that review may a separate GO authorize controller deployment and the documented supervised one-block-West fixture. No deployment, commit, push, or Minecraft action was authorized or performed by this pass.

### Stage 3 Final Regression Isolation Result

**Final regression verdict on 2026-11-01: passed; ready for a separate controller-deployment authorization after review.** Independent review accepted the production hardening but found that the pending-vertical regression could be masked by the destination, pose, or breadcrumb checks. The focused test now creates independent generic Stage 2 missions for pending `move_up` and `move_down` with current pose and destination both `(0,0,0)` North/Y=0, healthy epoch/journal/high water, no breadcrumbs, no completed return history, and no frozen return. `nav_state.validate()` accepts each mission and `assessStatus()` explicitly returns `retry_identical`; the pending vertical operation and its expected vertical result are the only Stage 3 incompatibility.

For each operation the test now requires the exact `cannot resume pending operation <operation>` diagnostic, no retry-authorization record, no physical send or execution, unchanged controller/robot high water and pending sequence/identity, a healthy replayable journal, and successful read-only `ocianav status` inspection. Sensitivity was demonstrated with a temporary removal of only the pending-operation branch in `validateStage3Mission()`: the focused suite failed on the exact diagnostic while the remaining mission/plan flatness checks stayed active. The approved branch was immediately restored, `git diff --check` remained clean, and the focused suite returned to green. No production source change remains from this pass; the only lasting code change is stronger test coverage in `tests/nav_cli_cases.lua`.

Final host results are Stage 1 `12 / 4,785`, Stage 2 `28 / 710`, Stage 3 `31 / 345`, integrated `111 / 13,940`, and deployment `26 / 173`, all with zero failures. Every repository Lua file passes `luac5.3 -p`, `git diff --check` is clean, and the final deployment dry run reports only the expected controller creates/updates with every robot entry unchanged and no file modified. Runtime journals, archives, recovery markers, robot files, and other unlisted state remain outside the deployment manifest.

The remaining gates are operational rather than code-design work: independent confirmation of this final regression, separately authorized controller-only deployment, OpenOS ownership/cleanup observation, and the supervised one-block-West round trip. No host result is Minecraft acceptance, and no deployment, commit, push, journal mutation, epoch change, or physical movement occurred in this pass.

### Stage 3 Supervised Minecraft Acceptance: 2026-11-02

**Happy-path verdict: PASSED.** This acceptance is deliberately narrow. It establishes the first supervised flat outbound/inverse-return lifecycle in Minecraft; it does not accept restart recovery, fault injection, generalized navigation, or automatic charging verification.

After an earlier farming run exhausted Wheatley's battery away from home, the operator physically returned him to the charging station and recommissioned `(0,0,0)` North with `ocia-recover.lua reset-origin`. The new execution epoch was `27939d2b-7c4e-4a5c-8f7b-18f12339a96c`.

The controller ran `ocianav plan --x -1 --y 0 --z 0 --heading west`, `go` with the same destination, `status`, `return`, and a final `status`; the operator supplied the literal `NAVIGATE` and `RETURN` confirmations. Mission `ac25ed48-8795-47f7-b87c-63e64d7917d1` executed these physical requests:

| Sequence | Operation | Result |
|---:|---|---|
| 1 | `turn_left` | Success |
| 2 | `move_forward` | Success |
| 3 | `move_backward` | Success |
| 4 | `turn_right` | Success |

Wheatley visibly reached `(-1,0,0)` West and returned to `(0,0,0)` North. The controller recorded the actual outbound breadcrumbs, executed their exact inverse, reconciled the final pose, recorded `navigation_complete`, and archived the mission. Independent final status reported robot mode `ready`, robot journal `healthy`, trusted `(0,0,0)` North, physical high water `4`, no active controller mission, one archived mission, and energy `35497/35500`. `charging_verified=false` was correct: the test observed arrival, not automated charging proof.

### Basic 3D Navigation Implementation Result: 2026-11-02

**Repository status: implemented and host-validated; pending independent review and supervised Minecraft fixtures.** No live HDD, Minecraft world, execution epoch, or runtime journal was changed during this implementation.

The existing controller journal, physical request sequencing, status reconciliation, and actual-action breadcrumbs remain authoritative. `ocianav go` now accepts nonzero Y, executes `move_up` and locally checked `move_down`, and replans from the durable actual pose after every successful action or reactive maneuver. A definite horizontal movement failure can trigger one adjacent categorical `nav_probe`, a one-block climb, or a small left/right lateral detour. Entity failures wait briefly and retry at most twice using new journaled physical request IDs. Every definite failed attempt consumes its sequence and reconciles fresh robot status before another physical request. Ambiguous outcomes retain the exact pending identity and stop under the existing recovery contract.

`nav_probe` is a correlated `s:` request that wraps only classic `robot.detect()`, `detectUp()`, and `detectDown()`. It reports broad adjacent categories and does not change robot pose, high water, recent physical results, or the physical journal. Direct inspection of the installed OpenComputers `1.8.8+8da357f` JAR confirmed those methods and the `air`, `entity`, `replaceable`, `passable`, `solid`, and `liquid` categories used by the implementation.

Return still freezes and reverses only confirmed successful outbound breadcrumbs. Vertical actions and detour turns/movements therefore return through the same existing inverse mechanism. Return retries a temporary entity obstruction twice with new request IDs, but a new solid obstruction stops for operator intervention.

Independent review of commit `c8cdee1` found that reactive outbound actions could consume the capacity reserved for inverse return. The controller now checks the shared outbound request boundary before persisting every new physical intent. It reserves one action for the attempt plus an inverse action for every existing successful breadcrumb and for the new action if it succeeds. Definite failures therefore reduce remaining outbound capacity without increasing return length. When the reservation cannot be maintained, navigation stops before creating or sending another request and the existing breadcrumbs remain returnable. Focused climb, lateral-detour, and entity-retry fixtures exercise this exact boundary and complete supervised inverse return afterward.

Host validation after implementation:

| Gate | Result |
|---|---|
| `lua5.3 tests/nav_cli_test.lua` | 42 tests, 367 assertions, 0 failures |
| `lua5.3 tests/run.lua` | 123 tests, 13,975 assertions, 0 failures |
| `lua5.3 tests/deploy_test.lua` | 26 tests, 173 assertions, 0 failures |
| all repository Lua files through `luac5.3 -p` | passed |
| `git diff --check` | clean |

Material limitations remain intentionally small: no terrain map or general path search; at most one-block reactive climbs; short lateral detours; two entity retries; no excavation, placement, or mob attacks; no automatic return replanning around a new solid obstacle; no measured energy reserve; and no charging verification. Forward travel remains optimistic, while downward movement and reactive detours refuse detected liquid or unknown adjacent terrain. `detectDown()` describes only the cell immediately below Wheatley; it does not prove that a horizontal destination has supporting ground, establish the depth of a drop, or make a route-level ground-support guarantee. Initial Minecraft tests must be short, supervised, and begin with disposable one-step fixtures before the proposed `(-15,+4,-1)` trip.

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
2. **Stage 2 — Durable controller mission journal (complete, hardened and host-validated 2026-11-01).** `nav_state.lua` implements the one-active-mission lifecycle, mandatory home start, intent/result ordering, actual-success breadcrumbs, duplicate-result protection, fresh-status-authorized identical pending-intent replay, consumed failure/nonexecution records, exact inverse-return progress, epoch/high-water/pose reconciliation, pre-write transition validation, checksummed replay, terminal archive rotation, and conservative fault handling. No Minecraft movement or deployment occurred.
3. **Stage 3 — Flat supervised outbound navigation and inverse return (implemented and host-validated 2026-11-01).** `plan`, `go`, `status`, `resume`, and basic `return` use only existing OCIA status/turn/forward/back operations. Home-only creation, post-confirmation status revalidation, durable actual-action breadcrumbs, exact-ID restart recovery, frozen inverse return, terminal archive rotation, horizontal-only enforcement, and cooperative controller ownership pass host tests. No deployment or Minecraft acceptance has occurred; the first one-block-West round trip remains the acceptance gate.
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

Independently review the basic 3D navigation and `nav_probe` diff plus its host evidence. Confirm that every reactive movement still uses the existing intent/result journal, definite failed movements consume and reconcile their request sequence, ambiguous requests retain exact-ID recovery, vertical and detour successes enter the ordinary breadcrumb stack, and return inverts that frozen actual history. Confirm the read-only probe does not consume robot high water or journal records and that manual drive/farming paths remain unchanged.

After review and a separate deployment authorization, begin supervised Minecraft acceptance with one direct `move_up`/inverse return fixture and one single-block climb fixture near home. Then test one ordinary descent, one disposable lateral obstruction, and one temporary-entity stop/retry if practical. Inspect status and journal evidence after each fixture. Only after those pass should the operator preview and attempt the proposed coordinate trip to `(-15,+4,-1)` from a nearly full battery. Keep return confirmed and supervised; stop on any liquid, unknown classification, new solid return obstruction, low-energy concern, or controller/robot inconsistency. The new 3D capability is host-only until those fixtures pass, and `charging_verified` remains false.

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
