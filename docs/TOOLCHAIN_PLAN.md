# Agent toolchain plan (owner, 2026-10-01)

Goal: agents (Claude, Fable and Codex) should see the editor, change the game, run it, test it, read errors, edit Blender assets and profile the Android build themselves. That saves tokens and owner time.

**Rule: keep exactly one Godot MCP active.** Don't run several MCP servers that do the same job.

## Core stack and status

| # | Tool | Purpose | Status |
|---|---|---|---|
| 1 | DCC-MCP Godot (or Godot MCP 5.0.2 as the alternative, not alongside it) | Agents run the editor: scenes, playing, checking results | to install |
| 2 | DCC-MCP Blender | Meshes, UVs, rigging, LODs, materials, export | to install |
| 3 | Serena MCP | Semantic code search and editing, so agents don't reread large GDScript files | to install |
| 4 | Context7 MCP | Fetch only the docs needed for libraries and plugins | to install |
| 5 | Git and GitHub | Checkpoints | in use. **Git LFS for large binaries: evaluate**, because migrating history is risky with many sessions working |
| 6 | GdUnit4 | Automated tests | installed (`addons/gdUnit4`) |
| 7 | gdtoolkit | Lint, format and parse | installed (`tools/qa/lint.sh`) |
| 8 | Terrain3D | Terrain | installed |
| 9 | ProtonScatter | Scatter props | installed |
| 10 | LimboAI | Nearby AI: guards, enemies, companions, Soulbeasts. The cheap world sim stays for distant NPCs | installed |
| 11 | Debug Draw 3D | Show paths, ranges, zones and streaming cells, including on Android | to install |
| 12 | Dialogue Manager 3 | Dialogue | installed (`addons/dialogue_manager`) |
| 13 | Phantom Camera | Cameras | installed |
| 14 | Jolt Physics | Physics | built into Godot 4.6; use the setting, not the old extension |
| 15 | ADB, scrcpy, Perfetto, AGI, Android Performance Analyzer | Install, launch, logs and profiling on the owner's S22 | scrcpy, Perfetto and AGI installed; Analyzer still to check |
| 16 | RenderDoc | Graphics frame debugging | installed |
| 17 | Meshy → Blender (cleanup and LOD) → Godot | Assets | in use; never import raw Meshy models as final |
| 18 | Substance Painter | Later, only if there's budget | not now |

Install order for what's still missing:
1. DCC-MCP Godot
2. DCC-MCP Blender
3. Serena
4. Context7
5. Debug Draw 3D
6. Android Performance Analyzer
7. An LFS evaluation

## The target loop
Agent → Godot MCP (inspect, edit, play, test) ↔ Blender MCP (assets) ↔ Git (checkpoints) ↔ GdUnit4 (tests) ↔ Android (export APK → install → launch → logs → screenshot → diagnose).

## Codebase audit to do (keep or replace)
For each existing system, record: current system → quality → technical debt → is an external replacement available? → migrate or keep → estimated work saved.

Example: custom NPC behaviour → stays as the cheap world sim; only nearby decision-making moves to LimboAI.

Areas to audit:
- quests, inventory, saves
- spatial audio, weather, roads, procedural buildings
- navmesh streaming, crowds
- localisation
- animation/state helpers, IK, motion matching
- runtime console, crash reporting (Sentry installer exists)
- automated Android testing, asset optimisation

Don't install replacements blindly.
