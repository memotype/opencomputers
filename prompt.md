# OpenComputers Infrastructure Automation: Session Orientation

Work in the current repository as a software-engineering project targeting classic OpenComputers on Minecraft 1.12.2.

Before doing project work, read these files completely in order:

1. `CODEX.md` — evergreen goals, architecture, runtime constraints, and engineering rules.
2. `ISSUES.md` — active risks and their stable tracking IDs.
3. `SCRATCH.md` — current state, decisions, roadmap, immediate next work, and handoff notes.
4. `MVP_PLAN.md` — implementation dependencies, module boundaries, milestone tests, and recovery behavior for the Potato farm MVP.

Then inspect `git status` and the source files relevant to the requested task. Treat the repository as the source of truth, preserve the working manual remote-control path, and do not overwrite Minecraft HDD targets blindly. Verify version-sensitive game APIs against the classic Minecraft 1.12.2 OpenComputers implementation.

Continue from `SCRATCH.md` unless the user gives a different priority. As work changes project state, update `SCRATCH.md`; as risks change, update `ISSUES.md`; change `CODEX.md` only when the durable design or project contract changes.
