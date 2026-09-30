---
name: ashes-agent-briefs
description: Template and rules for briefing, monitoring, resuming and reviewing Rising Ashes subagents from a cloud session (Opus plans, Sonnet executes). Use whenever spawning a work agent, when one is stopped or hits a usage limit, or when its report arrives.
---

# Briefing and running agents

Use `model: sonnet` for execution. Opus plans and reviews. Run agents in the background, and never poll their transcript files.

## Brief template (every brief has all five parts)
1. **Goal and scope:** what the player gets, the spec doc to read (`docs/design/*`, `docs/regions/*`), and the exact files it owns.
2. **Coordination:** which other agents are running and which files they own. "Re-read shared files right before a minimal edit; key hooks by lookups that start working once the other agent's data appears."
3. **Verify:** the tests to add, headless tests to run, screenshots (xvfb, gated on memory, see `ashes-cloud-testing`), and a contact sheet path in `/tmp/claude-0/shots/`. It must READ the sheet.
4. **Rules:** NEVER run git; kill only its own PIDs, never `pkill -f`; no `class_name`; free assets only (CC0/MIT/OFL, CC-BY with credit); never Higgsfield; checkpoint notes in `/tmp/claude-0/<topic>/NOTES.md`.
5. **Report:** brief, covering what works, what is unverified, test results, files changed outside its own, and hooks other agents still need.

## While they run
- A usage limit (429) or container restart: resume with `SendMessage` to the same agent id once limits reset.
- Stopped by the user by accident: SendMessage can't resume it. Spawn a new agent with the old brief summary, point it at the old NOTES.md and logs, and name the exact step it stopped on.
- An agent that keeps re-sending the same report is draining its background shells. Ignore the repeats; don't re-review.
- Route cross-agent hooks to the agent that owns the file (SendMessage), not to yourself.

## When a report lands
1. Look at its contact sheet yourself and list visual bugs (floating props, void horizon, blank icons, overlaps).
2. Diff the shared files it touched. Run its tests, plus the two it most likely broke.
3. Commit (see `ashes-parallel-commits`), send the user the sheet (SendUserFile), and summarise in plain words what the player can now do.
4. Queue the follow-ups: missing hooks, visual fixes, local-session tasks.
