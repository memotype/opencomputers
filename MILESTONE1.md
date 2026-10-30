# Milestone 1 Operations and Acceptance

This runbook covers the addressed, recoverable command transport implemented for Milestone 1. Durable architecture remains in [CODEX.md](CODEX.md), current project state in [SCRATCH.md](SCRATCH.md), risks in [ISSUES.md](ISSUES.md), and the dependency roadmap in [MVP_PLAN.md](MVP_PLAN.md).

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

The result payload is limited to 4096 encoded bytes, below the installed OpenComputers default packet limit. Both endpoints validate protocol version, message type, identifiers, operation, payload, expected component address, and expected modem sender. Sender matching prevents accidental cross-control; it is not cryptographic authentication.

## Execution Journal

Wheatley persists `/var/lib/ocia/robot.state` with a verified temporary file, previous-file backup, and same-filesystem rename. For a physical operation, the transitions are:

```text
ready
  -> persist prepared
  -> persist executing
  -> call one Robot API operation
  -> persist result, pose, and completed request
  -> send reply
```

A restart from `prepared` proves the Robot API call had not begun and records a definite failed result. A restart from `executing` cannot prove whether the call changed the world, so the daemon marks pose untrusted and enters `recovery_required`. It does not execute the request again.

Completed request records include the request fingerprint and original result. Repeating an identical retained request returns the cached result. Reusing its ID with different content is rejected. Version 1 retains up to the configured number of completed records (default 256) and fails closed when full; it never silently evicts an ID and thereby permits replay. There is intentionally no automatic cache-clearing procedure yet. Retention lifecycle/epoch management is required before long deployments can exceed this bound.

This is conservative at-most-once execution, not crash-proof exactly-once execution. OpenOS exposes buffered file operations but no guarantee equivalent to a hardware-backed `fsync`; a host, game, or storage failure at an unfortunate point can still require physical reconciliation. The journal makes known failure windows explicit instead of retrying optimistically.

## Manual Compatibility

`drive.lua` retains `f/b/l/r/u/d [count]`, `status`, and `q`. Its legacy packet remains broadcast for compatibility, but Wheatley accepts it only from the configured controller address. Protocol packets begin with `OCIA` and are never dispatched through the legacy parser.

Legacy physical commands do not have request IDs or duplicate suppression. Before executing one, Wheatley durably marks autonomous pose untrusted and enters `recovery_required`. This keeps manual driving useful for recovery while preventing later autonomous work from trusting manual movement. Restore Wheatley physically to the charging origin facing North, stop `robotd.lua`, run `ocia-recover.lua reset-origin` locally, and restart the daemon before resuming autonomous motion.

Both controller programs and the daemon record whether they opened port 4242 and close it only when they own that open action. Concurrent controller programs still compete for replies on the same event queue and should not be run together.

## Configuration

On each OpenOS computer, use `components -l modem` or `lua -e 'print(require("component").modem.address)'` to obtain the full local wireless modem address. Do not use the UUID-named HDD directory as a modem address.

Copy the supplied example to `/etc/ocia.cfg` on both machines and replace both placeholders with the same real addresses:

```sh
cp /etc/ocia.cfg.example /etc/ocia.cfg
edit /etc/ocia.cfg
```

`controller_address` must be the controller modem; `robot_address` must be Wheatley's modem. Keep protocol version 1 and port 4242. Configuration loading fails rather than accepting placeholders or unknown keys.

## Safe Deployment

The repository snapshots are canonical. The live disks are deployment targets. Stop `robotd.lua`, `drive.lua`, and `ociactl.lua` before replacing files; never replace Wheatley's daemon while a physical command is active. With Minecraft stopped, or after otherwise ensuring no OpenOS process is using the files, synchronize only the listed application paths:

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

Create `/lib/ocia` and `/var/lib/ocia` if needed. Do not overwrite a configured `/etc/ocia.cfg` with the example. `filesystem.bufferChanges=false` permits external edits to become visible, but a successful host copy is not proof that a running OpenOS process durably checkpointed its state.

On Wheatley:

```sh
robotd.lua
```

On the controller, `ociactl` defaults to a read-only status request:

```sh
ociactl.lua
ociactl.lua left
ociactl.lua forward
```

Movement and turn subcommands are world-changing and execute only when explicitly supplied. `--id ID` permits a supervised duplicate-request test; never reuse an ID for a different operation. `--deployment ID` supplies a deployment correlation identifier.

## Host Test

The repository test suite requires Lua 5.3. If it is not installed on the host, the tested container command is:

```sh
docker run --rm -v "$PWD:/work:ro" -w /work alpine:3.20 \
  sh -c 'apk add --no-cache lua5.3 >/dev/null && lua5.3 tests/run.lua'
```

It tests protocol rejection/correlation, pose math, duplicate handling, request-ID conflicts, journal restart classification, injected persistence failures, cached restart behavior, transport filtering/timeouts, payload bounds, and legacy/protocol separation. These mocks do not establish in-game modem, filesystem, or movement behavior.

## Supervised In-Game Acceptance

Use a clear, player-loaded test area. Record both modem addresses first. Do not conduct movement or interruption tests at the charger if the adjacent block is unsafe.

1. Boot Wheatley normally and confirm OpenOS sees the wireless modem and expected hardware. Expected: normal shell and no component errors.
2. Configure both `/etc/ocia.cfg` files. Start `robotd.lua`. Expected: it reports port 4242 and mode `ready` (or accurately reports a pre-existing recovery state).
3. Interrupt and restart the daemon while port 4242 remains open. Expected: no port-open assertion failure.
4. Compare each configured address with `component.modem.address`. Expected: exact full-address matches; a mismatch prevents startup.
5. Run `ociactl.lua` with no arguments. Expected: `Certainty: succeeded`, `Status: succeeded`, energy, daemon mode, and pose; Wheatley does not move.
6. Send an unrelated/stale reply from another computer if available, then repeat status. Expected: the probe ignores it and accepts only the correlated Wheatley reply.
7. Run `drive.lua` and issue `status`. Expected: the legacy `READY` and battery reply still arrives. Exit with `q` and confirm other port users remain functional.
8. In a clear area, record Wheatley's heading and run `ociactl.lua left --id acceptance-turn-1`. Expected: one left turn, one successful reply, and the reported heading changes once.
9. Select one unobstructed block and run one explicit movement such as `ociactl.lua forward --id acceptance-move-1`. Expected: exactly one block of motion and one pose transition.
10. Repeat the exact command with the exact same ID. Expected: the cached result says `duplicate=true`; Wheatley does not move or turn again. Reusing that ID with another operation must be rejected.
11. Simulate a lost reply by temporarily preventing the controller from receiving after a supervised request, without sending a new ID. Expected: the controller reports `Certainty: unknown`. Retrying the same retained ID returns the cached result without repeating motion.
12. For restart recovery, use a disposable test and deliberately stop after the durable `executing` marker only if a safe test hook/procedure has been established. Expected: restart enters `recovery_required`, reports an untrusted pose, and refuses further autonomous motion. Do not manufacture this condition by killing Minecraft during a survival-world action merely to pass acceptance.

After any manual movement or ambiguous result, physically return Wheatley to the charging origin `(0,0,0)` facing North. Stop the daemon, run `ocia-recover.lua show`, then `ocia-recover.lua reset-origin`, type `RESET`, and restart the daemon. Confirm with status before another movement.

Steps 1–10 are ordinary supervised acceptance. Steps 11–12 require deliberate fault setup and may remain pending until a safe harness is available. Milestone 1 is not complete until the relevant in-game evidence is recorded.
