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
- Crop-height movement and turning clearance throughout the plot.
- Clear initial staging and final exit cells reported by the preview.
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

## Rectangular reverse-serpentine patch

The `patch` stage accepts a width from left to right and a depth forward from the staging edge. Both default to 3. Each dimension must be from 1 through 16, and a plot may contain at most 64 cells.

```sh
ociafarm plan patch --width 3 --depth 3 --slot 1
ociafarm apply patch --width 3 --depth 3 --slot 1

# Equivalent 3x3 defaults:
ociafarm plan patch --slot 1
```

Wheatley enters only unplanted crop spaces. He farms the block ahead, turns when the serpentine changes direction, and backs into the next unplanted space. Once a cell is planted, he never enters it again. For the 3x3 plan, the planting order viewed from above is:

```text
             North
               ^

          x=0  x=1  x=2

   z=2     3    4    9
   z=1     2    5    8
   z=0     1    6    7
```

From standard staging at local `(0,-1)` facing North, Wheatley moves into the unplanted footprint to local `(0,1)`, turns South, and begins farming. The 3x3 route uses 34 physical commands: 9 tills, 9 plants, 10 movements, and 6 turns. It exits at local `(2,3)` facing South. Thus its only special exterior spaces are the initial staging cell `(0,-1)` and final exit cell `(2,3)`; it does not require a clear exterior ring.

The same generator handles single rows and columns. A 1x1 patch remains stationary. For every size, the preview prints the ordered world-coordinate targets, complete command sequence, expected final pose, and dimension-dependent exit clearance. Inspect all of them before typing `FARM`.

The reverse-serpentine route subsequently completed a supervised 3x3 patch successfully in Minecraft. Continue to clear the entire crop-height footprint, the reported staging cell, and the reported exit cell before each run. The two earlier 3x3 attempts used the retired perimeter route and stopped safely on exterior Dirt; they were not failures of the farming operations or the reverse-serpentine geometry.

## Stop and recover safely

Any local validation failure, unsupported remote operation, definite physical failure, timeout, unknown outcome, recovery-required reply, pose contradiction, wrong item, empty slot, or missing item consumption stops the route.

- A definite failed request is durably consumed; do not reuse its ID for another operation.
- For an unknown outcome, do not allocate a fresh ID or retry blindly.
- Record the request ID, operation, certainty, status, code, message, last trusted pose, inventory count, and visible terrain.
- Query fresh status and inspect Wheatley before deciding whether further trusted movement is safe.
- If pose or physical outcome is ambiguous, use the established reconciliation procedure. Do not recommission merely to erase an error.

An incomplete patch is an acceptable prototype result. A program-reported completion without nine observed Farmland blocks and nine Potato crops is not complete construction.
