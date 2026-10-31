# Wheatley's First Potato Patch

This is a supervised vertical slice, not the autonomous Potato Farm MVP. Every controller-issued movement, turn, till, and planting interaction uses the existing OCIA execution journal.

## Verified farming mechanics

Classic OpenComputers 1.8.8 uses the front blockspace as the primary target for these calls and calibrates the simulated interaction downward:

```lua
robot.use(sides.down)   -- equipped hoe tills forward/downward
robot.place(sides.down) -- selected Potato plants forward/downward
```

Both work from the same adjacent crop-height pose. Wheatley does not need to fly over the field.

The journaled `till_forward_down` operation succeeded in Minecraft as physical request sequence 15, returned `operation_succeeded` with `item_placed`, left pose unchanged, and visibly produced WAILA-identified Farmland. The older `till_down` behavior remains distinct because its definite failed request is part of real journal history.

The original eight-operation `single-plant` aerial route also succeeded and visibly produced a Potato crop at 0% growth. It proved `plant_down`, but its movement was unnecessary. A later manual REPL experiment from the adjacent pose used:

```lua
local robot = require("robot")
local sides = require("sides")
robot.select(1)
local ok, reason = robot.place(sides.down)
print(ok, reason)
```

The observed result was `true, nil`; one Potato was consumed and WAILA identified the resulting crop as Potato at 0% growth. That manual action was outside OCIA and did not change tracked pose. The new `plant_forward_down` operation journals the same verified interaction, validates that the selected slot contains `minecraft:potato`, and requires a one-item count decrease before the controller proceeds.

Robot API success and item consumption still do not independently identify the resulting world block. Visually inspect the crop before declaring construction successful.

## Deployment and module reload

The allowlisted manifest contains 21 files: 10 controller and 11 robot. Review and apply only by explicit operator decision:

```sh
lua5.3 deploy.lua
lua5.3 deploy.lua --apply
lua5.3 deploy.lua
```

The last dry run should report all 21 entries `UNCHANGED`. Host writes are visible without restarting Minecraft, but Lua's `require()` cache does not replace loaded modules. After deploying shared protocol or farming code:

1. Stop `robotd` only while idle.
2. Reboot Wheatley.
3. Reboot the controller.
4. Start `robotd` and confirm `ready`.
5. Run a fresh `ociactl` status request.

Do not recommission automatically. Every farm run allocates from the epoch and high water returned by fresh status; never hardcode an observed sequence.

## Common staging geometry

Wheatley starts in the crop-height air block immediately south of the patch's southwest target, facing into the patch. In plan-local coordinates he starts at `(0,-1)` facing North; the southwest soil target is `(0,0)`, one block forward and one block down.

Prepare:

- Dirt or Grass target soil with irrigation in range.
- A Stone Hoe equipped.
- Enough ordinary Potatoes in the selected slot.
- Empty crop spaces above every target.
- Crop-height movement clearance around the full one-block exterior ring.
- Manual supervision and a fresh `ready`, trusted status.

The coordinate frame rotates with Wheatley's live heading. The preview prints actual target coordinates and the expected final pose.

## Single cell

`single` performs exactly two stationary physical requests against the same forward/downward target:

```sh
ociafarm plan single --slot 1
ociafarm apply single --slot 1
```

The preview must show one `till_forward_down`, followed by one `plant_forward_down`, with identical cell coordinates and unchanged expected pose. Type `FARM` only after inspecting the live plan.

For Farmland prepared by an earlier test, planting alone is one stationary request:

```sh
ociafarm plan single-plant --slot 1
ociafarm apply single-plant --slot 1
```

## Pair

The pair occupies the southwest and southeast-adjacent cells of the first row. Wheatley farms the first from the initial staging block, moves one block east along the exterior south edge, turns north, and farms the second. He never enters either crop space.

```sh
ociafarm plan pair --slot 1
ociafarm apply pair --slot 1
```

## Complete 3x3 patch

The center cannot be reached from the exterior. The fixed route therefore:

1. Moves along the south exterior and enters the still-unplanted bottom-middle crop space.
2. Tills and plants the center from there.
3. Exits through the same unplanted access cell.
4. Tills and plants that access cell from the south exterior.
5. Completes the other seven perimeter cells while remaining on the exterior ring.

No movement enters a cell after it has been planted. The expected final local pose is `(-1,0)` facing East: outside the west edge beside the southwest target.

```sh
ociafarm plan patch --slot 1
ociafarm apply patch --slot 1
```

Inspect every movement, turn, target coordinate, and the final pose before typing `FARM`. The route is host-validated but has not yet been physically run as a complete patch; exterior clearance, robot movement above the temporarily unplanted access soil, and the full sequence remain supervised acceptance assumptions.

## Stop and recover safely

Any local validation failure, unsupported remote operation, definite physical failure, timeout, unknown outcome, recovery-required reply, pose contradiction, wrong item, empty slot, or missing item consumption stops the route.

- A definite failed request is durably consumed; do not reuse its ID for another operation.
- For an unknown outcome, do not allocate a fresh ID or retry blindly.
- Record the request ID, operation, certainty, status, code, message, last trusted pose, inventory count, and visible terrain.
- Query fresh status and inspect Wheatley before deciding whether further trusted movement is safe.
- If pose or physical outcome is ambiguous, use the established reconciliation procedure. Do not recommission merely to erase an error.

An incomplete patch is an acceptable prototype result. A program-reported completion without nine observed Farmland blocks and nine Potato crops is not complete construction.
