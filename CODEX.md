# Minecraft OpenComputers Infrastructure Automation

## Purpose

This project implements an autonomous infrastructure deployment system inside a modded Minecraft survival world.

OpenComputers robots act as construction workers. A stationary OpenComputers controller plans, supervises, and records deployments. Refined Storage is the inventory and autocrafting service used to provision those deployments.

Conceptually, this is a Terraform-like Infrastructure as Code platform operating inside Minecraft, with the controller as its control plane and Refined Storage as its resource backend:

```text
deployment request
    -> blueprint desired state
    + robot terrain survey observed state
    -> controller plan and diff
    -> Refined Storage inventory and autocrafting
    -> staged robot supplies
    -> apply terrain and construction plan
    -> resurvey and verify convergence
    -> resource reconciliation
    -> verified robot charging return
```

The ultimate goal is to request a structure or machine installation, have the required materials provisioned and collected automatically, and have one or more robots navigate to the site, construct and verify the deployment, and report success without treating an incomplete build as successful.

The primary objective is reusable autonomous surveying, terrain preparation, and construction. A farm is the first full application, not a reason to assume a pre-cleared site.

The current incremental implementation path, module boundaries, experiments, and milestone acceptance tests are maintained in [MVP_PLAN.md](MVP_PLAN.md); they may evolve without changing this durable architecture.

## Runtime Target

All runtime software must remain compatible with the installed Minecraft environment:

- Minecraft 1.12.2
- The 1.12.2 Pack: Perfectly Complex 1.6.6
- Forge 14.23.5.2860
- Java 8u312
- Biomes O' Plenty world generation
- Survival game mode
- FTB App launcher
- OpenComputers classic `1.8.8+8da357f`
- OpenOS 1.8.8
- Lua 5.3
- Industrial Foregoing `1.12.13-237`
- Extra Utilities 2 `1.9.9`
- EnderStorage `2.4.6.137`
- Refined Storage 1.6.16
- Refined Storage Addons 0.4.5
- Approximately 768 KiB of RAM per OpenComputers machine
- Tier 2 wireless network cards using port 4242

Relevant installed mods include Storage Drawers, EnderStorage, Industrial Foregoing, Extra Utilities 2, Ender IO, Mekanism, and Forestry.

Modern Minecraft APIs, OpenComputers II behavior, and arbitrary native Lua libraries must not be assumed to exist.

Primary OpenComputers references are:

- <https://github.com/MightyPirates/OpenComputers>
- <https://github.com/MightyPirates/OpenComputers/wiki>
- <https://ocdoc.cil.li/>

When API behavior is uncertain, verify it against the classic Minecraft 1.12.2 implementation and the installed version rather than silently assuming behavior from a newer project.

The local Git repository is the source of truth. Project-owned OpenOS files are organized by logical role under `machines/controller` and `machines/robot`; these paths are source trees, not complete disk images and not identifiers for any particular world. Installed OpenOS paths remain `/home`, `/lib`, and `/etc` on each machine.

The Git source trees, local deployment mapping, live virtual HDDs, and persistent runtime state are distinct concerns. Git-ignored `deploy.local.lua` maps logical roles to one local world save plus physical HDD and wireless modem UUIDs. The role-specific `etc/ocia.cfg.example` files contain version-controlled OpenOS defaults; the installer substitutes the local modem identities and manages each live `/etc/ocia.cfg`. `/var/lib/ocia` remains OpenOS-owned execution state and is never a deployment target.

Source changes occur in Git and reach live HDDs only through an explicit, allowlisted deployment operation. The host installer defaults to a dry run, backs up files it replaces, stages individual writes, and does not synchronize or delete unrelated disk contents. Host-side tools may run syntax checks and tests for pure Lua logic, but OpenComputers component behavior must be tested in Minecraft.

Development-time deployment while Minecraft and OpenOS programs are running is permitted. The installer does not inspect, stop, restart, or coordinate processes. An active Lua process may retain loaded code, so the developer restarts the relevant OpenOS program manually when needed. Individual file replacement is staged, but a multi-file deployment is not one atomic transaction and may briefly expose mixed versions to a process loading modules during the copy.

## Robot Hardware Principles

The active construction robot is a Tier 2 OpenComputers robot. Its Tier 2 APU supplies both processor and GPU functionality; a separate Graphics Card is redundant when the APU GPU is present and verified. Do not reintroduce one as a requirement merely because a conventional computer build would contain a separate card.

The current Tier 2 assembly has successfully booted with an Inventory Upgrade, Inventory Controller Upgrade, Geolyzer, Tier 2 Battery Upgrade, Tier 2 Wireless Network Card, internal disk drive, screen, keyboard, and storage. Component availability proves assembly compatibility, not full operational behavior. Tool swapping, inventory transfer, energy capacity, endurance, and autonomous charging still require method-level acceptance tests.

Robot disassembly is costly and carries survival-world risk. New hardware must have a demonstrated requirement, an available compatible slot and complexity budget, and a concrete acceptance test before another rebuild is recommended.

## System Responsibilities

### Refined Storage

Refined Storage is a materials service, not the deployment state machine. The controller reaches the installed Refined Storage 1.6.16 network through the native `refinedstorage_interface` component exposed by a standard OpenComputers Adapter adjacent to an RS Interface. No additional integration mod or Refined Storage-specific adapter is required in the verified installation.

The intended Refined Storage service contract is:

- Reporting stored items and their quantities.
- Exposing available crafting patterns.
- Scheduling and reporting autocrafting work when a recipe exists.
- Extracting requested supplies into a physically accessible staging inventory.
- Accepting recovered, unused, and residual materials returned by the robot workflow.

Inventory identity is based on registry name plus relevant metadata and NBT, not display labels. An API method being exposed does not establish its semantics; each inventory, crafting, extraction, and insertion operation must be exercised against the installed version before production use.

An RS crafting task only provisions a resource. Its completion says nothing about the physical construction result or the robot's safe return.

### Controller

The stationary controller is authoritative for deployment intent and orchestration. It is responsible for:

- Detecting and validating staged deployment materials.
- Receiving deployment intent independently of RS crafting tasks.
- Directing the robot's bounded site survey and interpreting its observations.
- Computing a deterministic, inspectable difference between observed terrain and blueprint desired state.
- Refusing to apply plans containing unresolved unknowns or unsafe site conditions.
- Computing terrain changes and a survey-derived bill of materials from the accepted plan.
- Querying stored and craftable resources, calculating deficits, and scheduling missing supplies.
- Monitoring crafting, extraction, delivery, returns, and partial fulfillment.
- Selecting a blueprint and deployment origin.
- Converting blueprint data into an executable construction plan.
- Assigning work to a known robot.
- Tracking expected robot position and orientation.
- Monitoring progress, inventory, and energy.
- Correlating every command with its response.
- Recording deployment progress durably.
- Stopping safely when execution becomes ambiguous.
- Verifying all completion criteria.
- Reconciling allocated, loaded, recovered, consumed, returned, and missing resources.
- Declaring construction and mission completion independently of RS task state.

Higher-level planning belongs on the controller unless a robot needs local logic for safety or recovery.

### Robot

The robot is a lightweight, defensive execution agent. It is responsible for:

- Accepting commands only through the defined wireless protocol.
- Executing bounded movement and interaction operations.
- Placing blocks from its inventory.
- Inspecting the immediate environment where supported.
- Retrieving materials from staging inventories when required by the workflow.
- Surveying the bounded deployment footprint and reporting observations.
- Distinguishing positively observed facts from estimates, categorical detections, and unknown conditions.
- Loading supplies, unloading recovered materials, and requesting resupply through the controller.
- Tracking relative position and orientation.
- Checking local preconditions before changing the world.
- Reporting actual operation results rather than transmission success.
- Reporting obstruction, inventory, energy, and recovery state.
- Retaining enough durable state to prevent blind command replay.
- Returning to a staging or charging location when required and safely possible.
- Remaining usable through manual recovery commands.

The robot must not perform unrequested excavation or indiscriminate block replacement.

## Blueprint Model

A blueprint is data, not a hardcoded movement script. It describes the desired world state independently of the route used to construct it.

A blueprint may define:

- Name and schema version.
- Deployment origin and orientation.
- Dimensions and relative block coordinates.
- Required block or item at each coordinate.
- Material quantities.
- Placement constraints and orientation.
- Optional machine configuration steps.
- Verification requirements.

The controller translates relative blueprint coordinates into a sequence of bounded robot operations. Navigation strategy, retries, and robot assignment are planner concerns and should not be embedded in the blueprint.

## Survey, Plan, Apply, and Verify

The deployment model follows a deliberately small Terraform-style reconciliation loop:

```text
blueprint desired state + terrain survey observed state
    -> deterministic plan and diff
    -> resource plan
    -> bounded apply operations
    -> verification survey
    -> converged state or remaining differences
```

The initial terrain survey is read-only. It records coordinate-indexed observations for the deployment footprint, including surface elevation, encountered materials where they can be identified, obstructions and clearance, holes and support, required excavation, required fill, surface replacement, estimated recoverable material, and unsafe or unknown conditions. Survey records must identify the evidence behind each fact. A categorical obstruction result, a noisy density estimate, and a positively identified adjacent block are not interchangeable observations.

A plan is deterministic for a given blueprint and survey. It is inspectable before execution and explicitly states blocks to destroy, add, or change; resource requirements; recoverable materials; unknowns; and conditions that prevent safe apply. Planning itself does not change the world.

An operator-facing summary may use Terraform-like language such as `Plan: 143 to destroy, 217 to add, 12 to change`, followed by recovered and additional resource estimates and either `READY TO APPLY` or a blocking reason. Such figures are plan output, never assumed constants.

A saved plan is not permission to assume the world remained unchanged. Before and during apply, the controller validates relevant preconditions against the current world. If they differ from the survey, it either creates a new plan from new observations or stops without blindly applying stale operations.

Verification repeats the necessary observations after apply and compares the resulting world with the blueprint. Success means the supported desired state converged; unsupported observations and remaining differences are reported rather than silently accepted. This analogy guides the architecture without requiring a general-purpose Terraform clone.

### Survey capability boundaries

In classic OpenComputers 1.8.8, the base Robot detection methods inspect only the immediately adjacent front, upper, or lower space and return broad categories such as solid, replaceable, liquid, air, or entity. Item comparison can test an adjacent block against a carried sample, but the installed Robot API does not provide a general arbitrary-block `inspect` call.

The Inventory Controller Upgrade provides detailed item-stack and inventory inspection plus equipped-tool swapping. It does not by itself identify world terrain.

A Geolyzer is installed and recognized in the current robot. Its `scan` operation has demonstrated approximate, noisy block density or hardness over a bounded three-dimensional volume; it is useful for discovering structure but does not prove block registry identity. Its `analyze` operation has positively identified a directly adjacent block and returned registry name, metadata, properties, hardness, harvesting requirements, and color data.

Detailed analysis remains adjacent-only. Exact identification of inaccessible underground blocks must remain unknown unless the robot can safely reach and analyze them or another installed-version capability is proven. Scan-axis transformation, orientation behavior, energy cost, noise thresholds, zero-value semantics, and modded-block results must be calibrated before survey output can authorize terrain changes.

Raw scan samples, positively identified blocks, interpreted terrain, and controller-generated plans are separate records. Interpretation may add conclusions and uncertainty, but it must never rewrite a density estimate as if the sensor returned a registry identity.

## Coordinate Convention

The controller uses configurable dead reckoning from a known charging-station origin. Unless a blueprint explicitly declares otherwise:

- The origin is `(0, 0, 0)`.
- The robot begins facing North.
- North is negative Z.
- East is positive X.
- Up is positive Y.

For example, moving forward from the origin produces `(0, 0, -1)`. Turning right faces East; moving forward then produces `(1, 0, -1)`. Moving up produces `(1, 1, -1)`.

Absolute navigation may be added later. Until then, the configured origin, initial heading, and every acknowledged movement form the authoritative pose chain.

## Command and State Model

Wireless commands use a versioned request/reply protocol on port 4242. Construction traffic should be sent directly to a configured robot modem address rather than broadcast.

Every state-changing request must include a unique request identifier. Replies must identify the protocol version, request, operation, success state, and relevant result data. The controller must validate the reply sender and correlation fields before changing authoritative state.

Execution is journaled at the command level; physical Minecraft operations are not transactional:

1. The controller records the next intended operation.
2. The robot records the request as in progress.
3. The robot executes one bounded physical operation.
4. The robot records the result and updated pose.
5. The robot returns the result to the controller.
6. The controller advances only after validating the acknowledgment.

Retained completed request identifiers may be replayed safely by returning their recorded results. Retired identifiers remain non-executable even when their full result is no longer retained. An operation found in progress after a restart is ambiguous and requires reconciliation; it must not be executed again automatically.

Durable request history must fail closed rather than silently make an allocated physical request executable again. The robot may retain only a bounded window of full results, but it must durably preserve an execution epoch and monotonic high-water sequence so retired requests in the active epoch remain non-replayable. A new epoch may be established only at an explicit recovery boundary after position and heading are physically reconciled; packets from earlier epochs remain stale.

The existing interactive remote-driving workflow remains available for diagnosis and manual recovery. Protocol evolution must preserve that capability or provide an equivalent recovery path. Because legacy movement has no request correlation, any manual physical command invalidates autonomous pose and requires an explicit origin/heading recalibration before autonomous execution resumes.

## Construction Safety and Verification

Sending a command is not evidence that it succeeded. A successful deployment requires evidence from the physical operation and from the resulting world state.

For block placement, the executor should:

- Inspect the target before placement.
- Refuse unexpected solid blocks, liquids, or unsafe replaceable blocks.
- Recognize an existing matching block as already satisfied where safe.
- Confirm that the placement call succeeded.
- Confirm the expected inventory change.
- Compare the resulting block with the intended material when supported.

Position and orientation are relative to an explicitly established deployment origin. Controller and robot pose should agree after every acknowledged navigation operation. If they cannot be reconciled, automated work stops.

Construction and mission completion are distinct states. At minimum, durable deployment state distinguishes:

- Construction verified.
- Resource reconciliation process completed.
- Resource balance is `balanced`, `discrepant`, or `accepted_discrepancy`.
- Robot reached the configured charging pose.
- Charging verified from observed energy behavior or another validated signal.
- Mission outcome recorded as successful, successful with an accepted exception, or recovery required.

A balanced ledger may satisfy the resource-success condition. Merely detecting or reporting missing, extra, or unexplained material completes the accounting attempt but does not make it reconciled successfully. An operator or explicit policy may accept a discrepancy, but the exception, actor or policy, and evidence remain durable; the mission must not be reported as unconditionally successful.

A failure during the return or charging check does not invalidate verified construction, but it remains an incomplete mission requiring recovery. RS crafting-task completion is only a provisioning event and must never advance one of these construction milestones by itself.

## Charging and Recovery

The verified charging station consists of an OpenComputers Charger supplied by the factory's Ender IO energy-conduit network. The Charger requires an activating redstone signal in its normal mode; an installed Lever has successfully activated it and restored a depleted Robot sufficiently for normal boot.

This proves stationary charging hardware, not autonomous docking. Reaching the configured charging coordinates is necessary but insufficient. `returned_to_charge` requires both the expected robot pose and evidence that charging is functioning, such as a measured energy increase over a bounded observation interval. A full buffer needs a separately validated full-charge condition. A powerless Charger, disabled redstone input, incorrect alignment, or otherwise unexplained lack of energy gain must not be reported as a successful charging return.

Autonomous navigation to the station, alignment, charge detection, target-level waiting, and safe resume after recharging remain implementation responsibilities.

## Survey-Driven Provisioning and Resource Accounting

The controller surveys before committing to a terrain material manifest. It derives required excavation, clearance, fill, surface replacement, tools, and installation materials from observed conditions. This permits multiple supply trips and avoids encoding an unknown site into a fixed crafting recipe.

Provisioning must handle unavailable patterns, missing ingredients, network power loss, delayed or failed crafts, partial extraction, full destination inventories, and interruptions between inventory mutation and acknowledgment. Reported stock is not proof of successful delivery.

The controller accounts separately for:

- Materials stored in RS.
- Materials craftable through RS.
- Materials allocated to the active deployment.
- Materials physically loaded onto the robot.
- Materials recovered from excavation.
- Materials consumed by construction.
- Materials returned to storage.
- Materials lost or otherwise unaccounted for.

Recovered material can offset gross fill requirements, but only after it has been observed and accounted for. Durable inventory transactions and reconciliation must prevent silent duplication, loss, or double allocation after a restart.

Resource reconciliation records both whether the accounting pass finished and whether the ledger balanced. Construction may verify successfully while reconciliation remains discrepant, but mission success must expose that discrepancy until it is resolved or explicitly accepted under a recorded policy.

## Initial Validation Scenario

The reference vertical slice is a 3x3 dirt platform constructed from a known starting position and orientation.

This scenario validates the complete control loop:

- A data-defined blueprint.
- Controller-side route generation.
- Versioned wireless requests and correlated acknowledgments.
- Robot movement and downward block placement.
- Relative pose tracking.
- Per-block verification.
- Failure and obstruction reporting.
- Verified deployment completion.

The platform should be built above known supporting terrain so ordinary OpenComputers placement rules are sufficient. It does not require generic terrain clearing, absolute navigation, or autonomous material loading. It is a low-level control-loop test, not a substitute for the terrain-preparation MVP.

## Engineering Principles

- Preserve working behavior before extending it.
- Prefer small modules with explicit responsibilities; separate wireless transport, robot operations, navigation, blueprints, inventory management, and deployment orchestration where it improves maintainability.
- Keep protocol and persisted-state formats versioned.
- Treat retries of physical actions as potentially destructive.
- Fail closed when state is incomplete or contradictory.
- Keep plans deterministic and observable.
- Log meaningful identifiers, operations, poses, and failure reasons.
- Validate external APIs against the installed mod version.
- Keep memory and packet sizes appropriate for OpenOS hardware.
- Test pure planning and state logic on the development host.
- Validate OpenComputers hardware interactions inside Minecraft.
- Add complexity only when it improves a demonstrated workflow.
- Keep interruption, inspection, and manual recovery practical.
- Build robustly without overengineering away the enjoyment of the project.
- Design explicitly for missed wireless messages, obstruction, incomplete inventory, and exhausted energy.

## Farm Deployment Direction

The same architecture should support several farms and machine installations by changing blueprint data and supplied materials rather than rewriting the movement engine.

The first complete farm target is a conventional 9x9 Potato field with central irrigation and a southern machinery row. It exists to establish reusable algorithms for surveying, excavation, filling, terrain leveling, tilling, planting, machine placement, dynamic material handling, and end-to-end verification. It must not require a manually cleared or leveled field.

Crop-specific designs are expected. Sugar Cane, Cactus, trees, and other plants with nonstandard soil, spacing, water, or harvesting rules must use specialized blueprints rather than being forced into the conventional farmland layout.

A longer-term production use case is renewable Sugar for Hootch production. The production design uses apples supplied by a Forestry Multifarm. The intended process is:

```text
Apples + Sugar + Water
    -> Ender IO Vat
    -> Hootch
    -> Combustion Generators
    -> Factory power
```

Farm blueprints may require terrain preparation, soil or substrate placement, crop planting, water placement, an appropriate Industrial Foregoing machine, a Range Addon, power distribution, a Wireless RF Transmitter or another energy connection, item collection, logistics, and remote item return through EnderStorage. Every modded block must have its placement, orientation, interaction, and verification behavior tested before generic automation is assumed.

Potential extensions include richer dry-run reporting, collision and obstruction detection, safe retry, idempotent operations, progress tracking, persistent deployment history, autonomous docking and recharge recovery, multiple robots, multiple deployment sites, machine orientation and configuration, and EnderStorage logistics.

These extensions must build on verified command execution and truthful completion reporting rather than bypassing them.

## Historical Dead Bush Protocol

The Dead Bush MacGuffin was a successful integration experiment, not a failed design. A tested RS processing pattern accepted 64 Dirt and declared one reusable Dead Bush as output. A Crafter staged the Dirt, an Exporter kept the token in the staging chest, and returning the token through an RS Interface completed the pending processing job. A pattern that both consumed and produced the token was correctly rejected as circular.

This demonstrated that processing patterns can bridge an external asynchronous process. It is superseded as the primary deployment architecture because fixed recipe inputs do not fit survey-derived requirements, finite pattern inputs make diverse deployments awkward, and a crafting monitor is not the authoritative lifecycle for a robot mission. The exact practical per-slot input limit was not established and must not be stated as fact.

The protocol may return later as an optional Crafting Grid trigger. It must not be required to provision resources, verify construction, or declare mission completion. Dead vegetation earned its place in project history, but it no longer runs the platform.
