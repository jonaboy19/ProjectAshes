---
name: ashes-cloud-testing
description: Exact commands and pitfalls for testing and rendering Rising Ashes inside the cloud container - gdUnit runs, class-cache errors, exit codes, xvfb screenshots, the shared-memory OOM problem and standalone harnesses. Use before running Godot in a cloud session or briefing an agent that will.
---

# Testing in the cloud container

Godot is `G=/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64`. Run everything from `kingdom/`.

- **One test file:** `timeout 900 $G --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/test_x.gd --ignoreHeadlessMode`
- **Full suite:** the same with `--add res://tests` and `timeout 1800`. Prefer CI (`ashes-ci`).
- **Exit codes:** 0 is a pass; 101 is orphan warnings only (a pass); 100 means failures, so grep `FAILED`.
- **"Could not find type" / class cache errors:** run `$G --headless --path . --import` once, then retry.
- **Parse check one script:** `$G --headless --path . --check-only -s res://path.gd`

## Screenshots and captures
- Always `xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan ...`. Never use `--headless` for images; it renders nothing.
- Main-scene shots: `-- --shot=NAME --out=/path.png --hour=15` (see `match shot` in `scripts/core/main.gd`).
- xvfb picks the LOW quality tier, so fps is meaningless. Judge draw calls, primitives and skinned counts instead.
- Tile the frames into a contact sheet and READ it before reporting (see `ashes-visual-qa`).

## Memory: the #1 cause of lost time
- The container has about 15 GB shared by every agent. A full game boot grows to about 4.5 GB, so three parallel renders OOM-kill each other. 19 lost runs in one day.
- **Gate every render** on free memory:
  `for i in $(seq 100); do [ $(free -m | awk '/Mem:/{print $7}') -gt 8500 ] && break; sleep 5; done`
- Brief render-heavy agents so only one does full-game captures at a time. Use **standalone harness scenes** (`tools_qa/<topic>/*_standalone.gd`) that build only the thing under test; they use far less memory.
- Heavy visual QA is better done by the **local PC session** (GPU and RAM). Hand it off (see `ashes-handoff`).

## Processes
Kill only by PID (`kill <pid>`). Never `pkill -f godot`: it kills other agents' runs.
