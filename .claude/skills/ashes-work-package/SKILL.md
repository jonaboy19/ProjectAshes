---
name: ashes-work-package
description: How to execute one work package (L*/C*/X*) from docs/regions/REGION_1_PLAN.md or docs/design/*.md for Rising Ashes - module layout, hooks, sandbox, tests, verification and handoff. Use whenever implementing a planned system or content package.
---

> **Mandatory for every task (owner rules, 2026-10-28):** (1) `ashes-best-tool-first` — use every fitting Godot built-in, installed addon, external tool (Blender, ffmpeg, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload instead of hand-rolling; (2) `ashes-aaa-gate` — nothing is done or sent until it passes the AAA gate against `docs/plans/ref_aaa/`. The game is **PC-only** (min-spec: regular PC, possibly integrated GPU); ignore any mobile/phone wording below.

# Executing a work package

1. **Read the package row** and its dependencies in the plan, plus the Integration rules. Also read `docs/regions/OWNER_DECISIONS.md`, `docs/regions/HOOKS_FOR_CLOUD.md` and the L0 scaffold (`kingdom/scripts/region1/`: `Region1Sim`, `Region1State`, `Region1Root`).
2. **Worktree:** use one per agent. Use a sparse worktree (`--no-checkout` + `sparse-checkout set --no-cone <paths>`) when you don't need Godot. Check free disk space before any import (a full import is ~7 GB). Delete `kingdom/.godot` and the worktree at the end.
3. **New files only:**
   - `scripts/region1/` (pure `RefCounted` sims + small Node presenters)
   - `data/region1/` (JSON tuning)
   - `scenes/region1/`, `shaders/region1/`
   - `tests/test_region1_*.gd`
   - `tools_qa/region1/`

   Hot files (`main.gd`, `life.gd`, `player.gd`, `hud.gd`, `world_gen.gd`, `assets.gd`, `quality.gd`, …) are no-touch. Write the exact hook code into `HOOKS_FOR_CLOUD.md` instead.
4. **Sims:**
   - Deterministic by seed.
   - `tick(dt_days)` plus signals.
   - `snapshot`/`restore` via `Region1State`, versioned.
   - Tuning lives in JSON.
   - Report a cost budget in ms per frame.
5. **Prove it:**
   - gdUnit tests, run headless (`-c --ignoreHeadlessMode`).
   - A sandbox scene in `tools_qa/region1/`.
   - Windowed Movie Maker capture → `ashes-video-review` frame sheets, which you READ.
   - Screenshots at 2400×1080 and 4:3 for UI.
6. **Hand off:**
   - Update `docs/STATUS_LOCAL.md` (Done row + backlog).
   - Update the handoff doc for the cloud/Codex.
   - Commit only your paths; merge origin, then push.
   - Run `ashes-aaa-review` before reporting.
