# Milestone 1 Operations and Acceptance

This runbook covers the addressed, recoverable command transport implemented for Milestone 1. Durable architecture remains in [CODEX.md](CODEX.md), current project state in [SCRATCH.md](SCRATCH.md), risks in [ISSUES.md](ISSUES.md), and the dependency roadmap in [MVP_PLAN.md](MVP_PLAN.md).

Milestone 1 is implemented and host-tested. It is not accepted until the supervised OpenOS and Minecraft checks below have recorded real results.

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

On each OpenOS computer, obtain the full local wireless modem address with `components -l modem` or:

```sh
lua -e 'print(require("component").modem.address)'
```

Do not use a UUID-named HDD directory as a modem address. Copy the supplied example to `/etc/ocia.cfg` on both machines and set the same real controller and robot addresses:

```sh
cp /etc/ocia.cfg.example /etc/ocia.cfg
edit /etc/ocia.cfg
```

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

The repository snapshots are canonical; live OpenOS disks are deployment targets. Stop `robotd.lua`, `drive.lua`, and `ociactl.lua` before replacing files. Never replace Wheatley's daemon during a physical request. Stop Minecraft, or otherwise establish that no OpenOS process is using the target files, before copying.

Synchronize only these application paths:

```text
controller snapshot -> live controller HDD
  /home/drive.lua
  /home/ociactl.lua
  /lib/ocia/config.lua
  /lib/ocia/pose.lua
  /lib/ocia/protocol.lua
  /lib/ocia/transport.lua
  /etc/ocia.cfg.example

robot snapshot -> live robot HDD
  /home/robotd.lua
  /home/ocia-recover.lua
  /lib/ocia/config.lua
  /lib/ocia/executor.lua
  /lib/ocia/legacy.lua
  /lib/ocia/pose.lua
  /lib/ocia/protocol.lua
  /lib/ocia/state.lua
  /etc/ocia.cfg.example
```

Do not copy repository runtime state, do not overwrite `/etc/ocia.cfg`, and do not synchronize whole HDD trees blindly. The journal directory is created by commissioning when needed. `filesystem.bufferChanges=false` permits external file changes to become visible, but a successful host copy does not prove OpenOS persistence behavior.

For a first deployment or any deliberate pose recovery:

1. Put Wheatley at the origin facing North.
2. Configure `/etc/ocia.cfg` on both computers.
3. Run `ocia-recover.lua show`, then explicitly `reset-origin` on Wheatley.
4. Start `robotd.lua`.
5. Run `ociactl.lua` with no arguments before any physical command.

## Host Test

The suite requires Lua 5.3. The verified repository command is:

```sh
docker run --rm -v "$PWD:/work:ro" -w /work alpine:3.20 \
  sh -c 'apk add --no-cache lua5.3 >/dev/null && lua5.3 tests/run.lua'
```

On 2026-10-30 the edge-case hardening suite passed `29 tests, 6350 assertions, 0 failures`. It covers protocol rejection/correlation, epochs and sequence gaps, pose math, prepared/executing restart classification, matching and conflicting unresolved retries, manual recovery across restart, retained and retired results, no-replay behavior, append/flush/raised-close/completion failures, corrupted journals, replacement artifacts, compaction faults, bounded scaling, transport timeouts, and legacy separation. These host mocks do not establish real OpenOS filesystem, modem, Robot API, memory, or timing behavior.

## Supervised In-Game Acceptance

Use a clear, player-loaded test area. Keep Wheatley away from unsafe adjacent blocks during movement and interruption tests. Record commands, identifiers, physical observations, replies, and journal diagnostics.

1. Confirm both full modem addresses and configure both `/etc/ocia.cfg` files. Verify each configured local address against `component.modem.address`; a mismatch must prevent startup.
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

Steps 1–9 are ordinary supervised acceptance. Steps 10–14 require controlled setups and must not be improvised by killing Minecraft during a survival-world action. Milestone 1 remains in progress until actual results are recorded in `SCRATCH.md` and the relevant `ISSUES.md` acceptance criteria are satisfied.
