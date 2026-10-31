# Milestone 1 Operations and Acceptance

This runbook covers the addressed, recoverable command transport implemented for Milestone 1. Durable architecture remains in [CODEX.md](CODEX.md), current project state in [SCRATCH.md](SCRATCH.md), risks in [ISSUES.md](ISSUES.md), and the dependency roadmap in [MVP_PLAN.md](MVP_PLAN.md).

Milestone 1 is implemented, host-tested, deployed, and partially accepted. The core supervised transport and movement checks below have recorded real results; controlled compaction and fault-injection gates remain before full acceptance.

## Protocol Contract

OCIA protocol version 1 uses modem port `4242` and exactly eight packet data parts. Values are ordinary modem arguments; the final argument/result field is a percent-encoded, sorted key/value payload. Received data is parsed and validated, never executed as Lua.

Request:

```text
"OCIA", 1, "request", request_id, deployment_id, recipient, operation, arguments
```

Reply:

```text
"OCIA", 1, "reply", request_id, deployment_id, operation, outcome, result
```

The supported operations are `status`, `turn_left`, `turn_right`, `move_forward`, `move_backward`, `move_up`, and `move_down`. They take no arguments. Each movement or turn is exactly one physical operation. Outcomes are `succeeded`, `failed`, `rejected`, and `recovery_required`; controller certainty is respectively definite success, definite failure, definite failure, and unknown. A controller timeout is also unknown, not failure.

Status request identifiers use `s:<token>`. Physical request identifiers use:

```text
p:<execution-epoch>:<monotonic-sequence>
```

The first physical sequence in an epoch is `1`; every later physical request must use exactly the durable high-water sequence plus one. `ociactl.lua` obtains a fresh status before an automatically numbered physical command and refuses to allocate an identifier unless Wheatley reports a trusted pose, `ready` mode, an epoch, and a numeric high-water marker. `--id` is reserved for deliberate replay and fault tests and must contain a valid identifier in the format above.

The result payload is limited to 4096 encoded bytes, below the installed OpenComputers default packet limit. Both endpoints validate protocol version, message type, identifiers, operation, payload, expected component address, and expected modem sender. Sender matching prevents accidental cross-control; it is not cryptographic authentication.

## Execution Journal and Retention

Wheatley stores an append-only, checksummed journal at `/var/lib/ocia/robot.state`. A journal begins with a versioned checkpoint. Normal physical execution appends these records:

```text
ready checkpoint
  -> append prepared (advances high_water)
  -> append executing
  -> call one Robot API operation
  -> append completed (result and resulting pose)
  -> send reply
```

`high_water` means that a sequence has been durably allocated; it does not by itself prove completion. The executor checks a matching unresolved `in_flight` record before classifying a sequence as retired.

Restart classification is deliberately conservative:

- A healthy journal ending at `prepared` proves the Robot API call had not begun. Startup appends a `failed / interrupted_before_execution` completion with `physical_outcome=not_started`. Only after that completion persists is the result a definite nonexecution result.
- If that prepared-request resolution cannot be persisted, Wheatley remains `recovery_required`; it does not execute the request.
- A journal ending at `executing` cannot prove whether the physical call changed the world. Wheatley marks pose untrusted, reports `recovery_required / physical_outcome_unknown`, and never executes the matching request again.
- A durable legacy-manual recovery record does not erase an unresolved `executing` identity. Manual movement remains available with untrusted pose, but matching retries continue to report unknown outcome and conflicts remain non-executable across restart until explicit origin recommissioning retires the epoch.
- A conflicting reuse of an unresolved sequence is rejected by request identity and fingerprint checks without invoking the Robot API.
- A durable `completed` record returns its original cached outcome when the identical request is delivered again.

The journal retains only a bounded recent-result window, configured by `recent_results` (default `32`, allowed `1..64`). Older full results are retired, but their sequences remain below or equal to the durable high-water marker. A delayed request for such a sequence receives `rejected / retired_request` and cannot execute again. That rejection describes the attempted replay; because the original result has been retired, it is not evidence that the earlier physical operation failed. This permits bounded memory and disk use without forgetting which sequences were allocated.

When `compact_records` (default `128`) or `compact_bytes` (default `65536`) is reached, the daemon writes a replacement journal containing a new checkpoint plus the retained recent results. Replacement uses `.switch`, `.new`, and `.old` artifacts, verifies the candidate journal, and uses same-filesystem renames. Any replacement artifact found at startup is treated as uncertain and requires explicit recovery. A compaction failure before any artifact or primary mutation leaves the prior primary journal authoritative; failures after replacement begins fail closed.

The installed OpenComputers 1.8.8 filesystem callback returns no value for a successful close, so OpenOS `handle:close()` normally returns `nil` on success. An exception raised by the HDD-backed close path is meaningful; journal writes catch it, mark persistence uncertain, and prevent further autonomous execution. The same check applies while writing or verifying replacement journals. This is conservative at-most-once execution, not crash-proof exactly-once execution. Successful OpenOS `write()`, `flush()`, and `close()` calls do not establish hardware-backed `fsync` or transactional Minecraft operations. A crash can still leave physical state requiring operator reconciliation.

## Commissioning and Recovery

Autonomous movement is disabled until an operator explicitly commissions the origin. Commissioning creates a new random execution epoch, resets its high-water marker to zero, and writes a fresh checkpoint. It is never automatic.

With `robotd.lua` stopped, place Wheatley at the configured charging origin `(0,0,0)` facing North, then run locally on Wheatley:

```sh
ocia-recover.lua show
ocia-recover.lua reset-origin
```

Type `RESET` only after physically verifying position and heading. The new epoch permanently makes physical packets from every prior epoch stale. Commissioning may clear incomplete journal replacement artifacts because the operator is explicitly establishing new trusted physical state; do not use it merely to make an error disappear.

Legacy `drive.lua` retains `f/b/l/r/u/d [count]`, `status`, and `q`. Its packet remains broadcast for compatibility, but Wheatley accepts it only from the configured controller address. Before legacy physical movement, Wheatley durably invalidates autonomous pose and enters `recovery_required`. If an unresolved physical request already exists, the manual record preserves its identity and unknown-outcome classification; manual movement does not reconcile it. Restore the physical origin and commission a new epoch before autonomous movement resumes.

Both controller programs and the daemon close port 4242 only if they opened it. Concurrent controller programs still compete for replies on the same event queue and must not be run together.

## Configuration and Diagnostics

On each OpenOS computer, obtain the full local wireless modem address with:

```sh
components modem
```

On the tested OpenOS 1.8.8 installation, `components -l modem` displayed usage rather than the modem address. The Lua alternative is:

```sh
lua -e 'print(require("component").modem.address)'
```

Do not use a UUID-named HDD directory as a modem address. Record both full modem addresses in the Git-ignored host `deploy.local.lua`; the installer renders the role-specific `etc/ocia.cfg.example` templates and installs `/etc/ocia.cfg` on both machines. Direct edits to an installed configuration are replaced, with backup, on the next apply when they differ from the generated file.

Current keys and defaults are:

```text
controller_address=<full controller modem UUID>
robot_address=<full Wheatley modem UUID>
port=4242
protocol_version=1
timeout=8
recent_results=32
compact_records=128
compact_bytes=65536
legacy_enabled=true
state_path=/var/lib/ocia/robot.state
```

Configuration rejects placeholders, unknown keys, invalid bounds, and a local modem address that does not match the configured role. The current bounds are timeout `(0,120]` seconds, recent results `1..64`, compaction records `16..1024`, and compaction bytes `8192..262144`. `ociactl.lua` status displays daemon mode, trusted pose, energy, memory, epoch/high-water, in-flight or latest retained request, journal health, generation, record count, byte count, last persist duration, and retained-result count.

## Safe Repository-to-OpenOS Deployment

The logical source trees under `machines/controller` and `machines/robot` are canonical; live OpenOS disks are deployment targets. `deploy.lua` is a Lua 5.3 host utility and is never installed on OpenOS. It requires LuaFileSystem (`lua-filesystem` on Ubuntu, or `lua-filesystem` in Alpine).

```sh
sudo apt install lua5.3 lua-filesystem
```

For initial local setup, copy the template and fill in the actual world-save path, virtual HDD UUIDs, and wireless modem UUIDs:

```sh
cp deploy.local.lua.example deploy.local.lua
edit deploy.local.lua
```

```lua
return {
  world_save = "/path/to/minecraft/saves/World Name",
  disks = {
    controller = "CONTROLLER_DISK_UUID",
    robot = "ROBOT_DISK_UUID",
  },
  modems = {
    controller = "CONTROLLER_MODEM_UUID",
    robot = "ROBOT_MODEM_UUID",
  },
}
```

`deploy.local.lua` is Git-ignored. HDD UUIDs select directories below `<world_save>/opencomputers`; modem UUIDs identify the wireless components inside Minecraft. The installer does not discover either identity dynamically.

The installer defaults to a nondestructive plan for both machines:

```sh
lua5.3 deploy.lua
lua5.3 deploy.lua --target controller
lua5.3 deploy.lua --target robot
lua5.3 deploy.lua --target all
```

Review `CREATE`, `UPDATE`, and `UNCHANGED` lines, then apply exactly the selected manifest with:

```sh
lua5.3 deploy.lua --apply
lua5.3 deploy.lua --target controller --apply
lua5.3 deploy.lua --target robot --apply
lua5.3 deploy.lua --target all --apply
```

The manifest contains only these paths:

```text
machines/controller -> live controller HDD
  /home/drive.lua
  /home/ociactl.lua
  /lib/ocia/config.lua
  /lib/ocia/pose.lua
  /lib/ocia/protocol.lua
  /lib/ocia/transport.lua
  /etc/ocia.cfg.example
  /etc/ocia.cfg (generated)

machines/robot -> live robot HDD
  /home/robotd.lua
  /home/ocia-recover.lua
  /lib/ocia/config.lua
  /lib/ocia/executor.lua
  /lib/ocia/legacy.lua
  /lib/ocia/pose.lua
  /lib/ocia/protocol.lua
  /lib/ocia/state.lua
  /etc/ocia.cfg.example
  /etc/ocia.cfg (generated)
```

Each generated configuration comes from its role's version-controlled template. Exactly one `CONTROLLER_MODEM_UUID` and one `ROBOT_MODEM_UUID` are replaced with the local values; all other defaults, comments, and formatting remain template-owned. Missing, duplicate, unexpected, or unresolved modem placeholders fail preflight before writes.

Files with identical bytes are skipped. Before replacing an existing file—including a manually configured `/etc/ocia.cfg`—the installer preserves its original bytes and relative path under `.deploy-backups/<run>/<role>/`. It writes and flushes a uniquely named temporary file beside the destination, renames it over the destination, and reads the installed file back for verification. A failure stops later changes and reports any files already installed. Backups are not an automatic runtime rollback mechanism, and a multi-file deployment is not atomic.

The installer never recursively synchronizes or deletes HDD content. Its only managed runtime configuration is the exact generated `/etc/ocia.cfg` entry. It does not target `/var/lib/ocia/robot.state`, any journal replacement artifact, or any unlisted file. Missing HDD directories are errors and are not created. The journal directory remains owned by commissioning/runtime code. After applying, review the completed `INSTALLED` lines and backup location, then run another dry run; all 18 entries should report `UNCHANGED`.

Hot deployment is explicitly supported: Minecraft and OpenOS programs may remain running. The installer does not inspect host processes, stop programs, restart daemons, or reboot computers. An active Lua process may retain already loaded modules, so restart `robotd.lua`, `drive.lua`, or `ociactl.lua` manually when the changed code must take effect. Avoid intentionally deploying during a physical robot operation: individual files cannot be partially copied, but a process loading modules during a multi-file apply can observe a mixture of versions. `filesystem.bufferChanges=false` permits external file changes to become visible, but successful host verification does not prove OpenOS runtime behavior.

For a first deployment or any deliberate pose recovery:

1. Discover both full modem addresses from the OpenOS machines.
2. Populate Git-ignored `deploy.local.lua` with the world, disk, and modem identities.
3. Run the all-target dry run and inspect all 18 actions, especially both generated `/etc/ocia.cfg` entries.
4. Apply the installer, then run another dry run and verify all 18 entries are `UNCHANGED`.
5. Manually restart relevant OpenOS programs when the installed code or configuration must take effect.
6. Put Wheatley at the origin facing North and stop `robotd.lua` before commissioning.
7. Run `ocia-recover.lua show`, then explicitly `reset-origin` on Wheatley.
8. Start `robotd.lua`.
9. Run `ociactl.lua` with no arguments before any physical command.

## Host Test

The Milestone 1 suite requires Lua 5.3. The verified repository command is:

```sh
docker run --rm -v "$PWD:/work:ro" -w /work alpine:3.20 \
  sh -c 'apk add --no-cache lua5.3 >/dev/null && lua5.3 tests/run.lua'
```

On 2026-10-30 the edge-case hardening suite passed `29 tests, 6350 assertions, 0 failures`. It covers protocol rejection/correlation, epochs and sequence gaps, pose math, prepared/executing restart classification, matching and conflicting unresolved retries, manual recovery across restart, retained and retired results, no-replay behavior, append/flush/raised-close/completion failures, corrupted journals, replacement artifacts, compaction faults, bounded scaling, transport timeouts, and legacy separation. These host mocks do not establish real OpenOS filesystem, modem, Robot API, memory, or timing behavior.

The deployment fixture suite additionally requires LuaFileSystem:

```sh
docker run --rm -v "$PWD:/work:ro" -w /work alpine:3.20 \
  sh -c 'apk add --no-cache lua5.3 lua-filesystem >/dev/null && lua5.3 tests/deploy_test.lua'
```

On 2026-10-30 it passed `25 tests, 152 assertions, 0 failures`. It uses disposable temporary worlds only and covers disk/modem validation, deterministic configuration rendering, dry-run purity, target selection, generated create/update/unchanged behavior, backups, protected journal state, idempotence, unsafe paths, nonzero CLI errors, and staged failure handling.

## Supervised In-Game Acceptance

Use a clear, player-loaded test area. Keep Wheatley away from unsafe adjacent blocks during movement and interruption tests. Record commands, identifiers, physical observations, replies, and journal diagnostics.

1. Confirm both full modem addresses in ignored `deploy.local.lua`, apply the reviewed generated configurations, and verify each configured local address against `component.modem.address`; a mismatch must prevent startup.
2. With Wheatley at the origin facing North and `robotd.lua` stopped, run `ocia-recover.lua show`, then `ocia-recover.lua reset-origin` and type `RESET`. Record the new epoch and high water `0`.
3. Start `robotd.lua`. Confirm it reports port 4242 and mode `ready`. Interrupt and restart it once while the port remains open; no port-open assertion may occur.
4. Run controller `ociactl.lua` with no arguments. Expect `Certainty: succeeded`, `Status: succeeded`, a trusted `(0,0,0)` North pose, the commissioned epoch/high water, healthy journal diagnostics, energy, and memory. Wheatley must not move.
5. Run `drive.lua`, issue only `status`, exit with `q`, and repeat `ociactl.lua` status. The legacy read-only path must work without disrupting the port or autonomous pose.
6. In a clear area, run `ociactl.lua left` without `--id`. Record the printed `p:<epoch>:1` identifier. Expect exactly one turn, a successful reply, trusted pose, and high water `1`.
7. Repeat the exact operation with `ociactl.lua left --id <recorded-id>`. Expect the cached result with `duplicate=true` and no second turn.
8. Reuse that identifier with `ociactl.lua right --id <recorded-id>`. Expect `rejected / request_id_conflict` and no movement.
9. Run one clear one-block move without `--id`. Expect the next contiguous sequence, exactly one physical move, one pose transition, and a healthy journal.
10. Exercise enough safe turns, or use a disposable configuration with the minimum allowed compaction threshold, to observe a generation increase. Restart the daemon and verify high water, pose, and retained duplicate behavior survive compaction. Restore production configuration afterward.
11. With a safe receive-side harness, suppress one controller reply after a completed physical request. Expect controller certainty `unknown`; retry only the identical identifier and operation. Expect the cached outcome and no second physical action.
12. Test an interrupted `prepared` record only through a safe hook. On restart, expect definite `failed / interrupted_before_execution`, `physical_outcome=not_started`, trusted unchanged pose, and no Robot API call.
13. Test an interrupted `executing` record only through a disposable safe hook. On restart, expect `recovery_required`, untrusted unchanged recorded pose, and a matching retry with `physical_outcome_unknown`. Neither matching nor conflicting retries may invoke a Robot API call. In the same disposable setup, perform an intentional legacy manual recovery movement, restart again, and retry the original identifier: it must remain `physical_outcome_unknown`, with no autonomous Robot API call; conflicting reuse must remain rejected.
14. After any legacy physical movement or ambiguous test, manually restore Wheatley to the origin facing North, stop the daemon, inspect with `ocia-recover.lua show`, explicitly commission a new epoch, restart, and confirm status. A saved old-epoch request must then receive `stale_epoch`.

### Acceptance results recorded 2026-10-30

The detailed chronological evidence, exact epochs, request IDs, physical observations, energy, and memory readings are preserved in [SCRATCH.md](SCRATCH.md#milestone-1-supervised-in-game-acceptance-session-2026-10-30). Classifications below apply only to what was actually observed.

| Step | Status | Evidence |
|---:|---|---|
| 1 | Passed | Both discovered modem identities were rendered into the generated configurations. The 18-entry manifest installed successfully, all 18 entries were subsequently `UNCHANGED`, both programs loaded configuration, and addressed communication succeeded. Foreign-sender behavior was not part of this step. |
| 2 | Passed | `ocia-recover reset-origin` required `RESET`, created an epoch, and an independent `show` read back trusted origin, high water `0`, and a healthy journal. |
| 3 | Passed for normal restart | The daemon started `ready`, was interrupted while idle, restarted without a port-open assertion, and recovered completed state. The observed `Ctrl+Alt+C` interruption emits a stack trace and is not graceful shutdown. |
| 4 | Passed | Read-only `ociactl` returned correlated success, trusted origin, epoch/high water, journal, energy, and memory without movement or physical sequence allocation. |
| 5 | Partially verified | Legacy `status` and sequential coexistence with OCIA worked, but the session performed legacy physical movement before status. That movement correctly invalidated autonomous pose, so the isolated status-only variant remains untested. |
| 6 | Passed | Automatically allocated sequence 1 turned Wheatley exactly once from North to West and updated trusted heading. |
| 7 | Passed | Repeating sequence 1 with the identical `turn_left` request returned the cached result with `duplicate=true`; no second turn occurred. |
| 8 | Passed | Reusing sequence 1 for `turn_right` returned definitive `request_id_conflict`; no action occurred and pose/high water remained unchanged. |
| 9 | Passed | Automatically allocated sequence 2 moved exactly one block West and changed reported pose from `(0,0,0)` to `(-1,0,0)`. |
| 10 | Pending | No compaction was performed. Observed generation `1` came from commissioning and is not compaction evidence. |
| 11 | Pending | No reply was deliberately suppressed. Normal duplicate replay is not a lost-reply test. |
| 12 | Pending | No controlled interruption after `prepared` was injected. |
| 13 | Pending | No controlled interruption after `executing` or ambiguity-preservation sequence was injected. |
| 14 | Partially verified | Actual legacy movement, durable invalidation, physical return, explicit recommissioning, new epoch, and restart all passed. No old-epoch packet was transmitted, so observed `stale_epoch` rejection remains pending. |

Additional evidence beyond the numbered checklist:

- A normal daemon restart recovered the second epoch, trusted `(-1,0,0)` West pose, high water `2`, and two retained completed results from a healthy seven-record/1825-byte journal. The retained request was not replayed after restart.
- Sequences 3 and 4 moved Wheatley back to `(0,0,0)` and turned him North. These were operator-selected one-step autonomous commands, not route planning.
- Green charging particles and a 303-unit reported energy increase after return provide positive charging evidence, but no controlled charge detector, docking logic, or negative controls were tested.
- The short session completed without an observed out-of-memory failure. Variable free-memory readings do not prove long-running stability or diagnose garbage collection.

Steps 1–9 are ordinary supervised acceptance. Steps 10–14 require controlled setups and must not be improvised by killing Minecraft during a survival-world action. Milestone 1 remains in progress until the pending compaction, lost-reply, interrupted-execution, post-restart duplicate, and stale-epoch gates are completed and the relevant `ISSUES.md` acceptance criteria are satisfied.
