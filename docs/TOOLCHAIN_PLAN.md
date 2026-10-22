# Agent toolchain plan (owner, 2026-10-01)

Goal: agents (Claude, Fable and Codex) should see the editor, change the game, run it, test it, read errors, edit Blender assets and profile the Android build themselves. That saves tokens and owner time.

**Rule: keep exactly one Godot MCP active.** Don't run several MCP servers that do the same job.

## Core stack and status

| # | Tool | Purpose | Status |
|---|---|---|---|
| 1 | DCC-MCP Godot 0.9.0 (MIT; Godot MCP 5.0.2 not needed and not installed) | Agents run the editor: scenes, playing, checking results | **installed and proven 2026-10-01** (opt-in per checkout, see tools/README_EXTERNAL_TOOLS.md) |
| 2 | DCC-MCP Blender 0.2.12 (MIT) | Meshes, UVs, rigging, LODs, materials, export | **installed and proven 2026-10-01** (headless Blender 5.2, own launcher) |
| 3 | Serena MCP 1.7.0 (app GPL-3.0-or-later, dev tool only) | Semantic code search and editing, so agents don't reread large GDScript files | **installed and proven 2026-10-01** (GDScript through the Godot editor LSP on port 6008) |
| 4 | Context7 MCP 4.1.1 (MIT) | Fetch only the docs needed for libraries and plugins | **installed and proven 2026-10-01** (no key, no account) |
| 5 | Git and GitHub | Checkpoints | in use. **Git LFS: evaluated 2026-10-01, do not migrate now (see "Git LFS evaluation" below)**, because migrating history is risky with many sessions working |
| 6 | GdUnit4 | Automated tests | installed (`addons/gdUnit4`) |
| 7 | gdtoolkit | Lint, format and parse | installed (`tools/qa/lint.sh`) |
| 8 | Terrain3D | Terrain | installed |
| 9 | ProtonScatter | Scatter props | installed |
| 10 | LimboAI | Nearby AI: guards, enemies, companions, Soulbeasts. The cheap world sim stays for distant NPCs | installed |
| 11 | Debug Draw 3D 1.7.3 (MIT, asset 1766) | Show paths, ranges, zones and streaming cells, including on Android | **installed 2026-10-01** in `kingdom/addons/debug_draw_3d` (Windows, Linux, Android arm32/arm64 libs only) |
| 12 | Dialogue Manager 3 | Dialogue | installed (`addons/dialogue_manager`) |
| 13 | Phantom Camera | Cameras | installed |
| 14 | Jolt Physics | Physics | built into Godot 4.6; use the setting, not the old extension |
| 15 | ADB, scrcpy, Perfetto, AGI, Android Performance Analyzer | Install, launch, logs and profiling on the owner's S22 | scrcpy, Perfetto and AGI installed. Android Performance Analyzer 0.9.0: no account needed, but a 562 MB Android SDK-licence download that needs the owner to accept the licence; **not installed**, see below |
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

---

## Status update, 2026-10-01 (local session)

Install order 1 to 6 is done, 7 is written below. Setup, commands, proofs and the Codex and cloud notes are in `tools/README_EXTERNAL_TOOLS.md` ("Agent MCP toolchain"). The codebase audit is `docs/TOOLCHAIN_AUDIT.md`. Project-scope MCP registration is `.mcp.json` at the repo root (no secrets in it).

Things that differ from the plan, so nobody is surprised:
- **One Godot MCP only**: DCC-MCP Godot works on 4.6.3 (verified with the installer's own `verify`, `directly_usable: true`), so Godot MCP 5.0.2 was not installed.
- DCC-MCP Godot is **opt-in per checkout**: its editor plugin registers an autoload in `project.godot`, so the plugin is not committed or enabled in the repo (it would ship in every build). `tools/mcp/dcc_mcp_start.ps1` installs and enables it locally. Never commit that `project.godot` line.
- DCC-MCP Blender runs from its own launcher on Blender 5.2 with `--factory-startup`; nothing was installed into Blender's own Python or the user profile, so other agents' `tools/external/blender.sh` runs are unaffected.
- Serena needs the Godot editor open (headless is fine) with the language server on port 6008 to understand GDScript. Without it, its code tools fail.
- Debug Draw 3D is committed in `kingdom/addons/debug_draw_3d`, trimmed to the platforms we use (11 MB). Release export templates load a no-op library, so calls compile away in shipping builds. The editor library sends anonymous usage statistics unless `debug_draw_3d/settings/telemetry_state` is set to "Refuse"; see the README.
- **Android Performance Analyzer 0.9.0** (open beta): downloadable without an account from `dl.google.com/android/apa/ide-zips/v0.9.0/android-performance-analyzer-windows.zip` (562 MB), but it is under the Android SDK licence agreement, which the owner must accept. Google's compatibility page says the frame profiler works best on Pixel 6 or newer; other phones "may have issues", and the S22 is not listed. It reads Perfetto traces, which we already record. Decision: not installed; the owner can say "install APA" and an agent will do it into `C:\Users\Jonna\Tools\apa`.

## Git LFS evaluation (no migration done)

Measured on origin/claude/focused-curie-m09hbd:
- 37,798 tracked files, **5.7 GB** at the tip; the local pack is 4.4 GiB; 686 commits on the branch.
- 68 percent of the tree is `kingdom/assets/incoming` (3.9 GB of third-party packs). `kingdom/assets/generated` 0.39 GB, `docs/kingdom/blender_previews` 0.28 GB.
- By type: PNG 1.8 GB (4,888 files), JPG 0.96 GB, GLB 0.9 GB, GLTF 0.21 GB, .blend 0.17 GB, OGG 0.16 GB.
- No file over 50 MB; 25 files over 10 MB (420 MB). The largest is a 42 MB iOS library.
- There is no `.gitattributes`; `git-lfs` 3.7.0 is installed on this PC.

Recommendation: **do not migrate history to LFS now.**
1. Many sessions (local, Codex, cloud) share the branch. `git lfs migrate import` rewrites every commit, so every clone and worktree would need re-cloning and any unpushed work would be orphaned.
2. LFS would not fix the real problem: the size is mostly raw third-party packs that the game does not ship. Moving them to LFS keeps the cost (quota and bandwidth on every CI checkout, and the Actions billing is already locked) instead of removing it.
3. Cheaper, safe steps first, none of which touch history: (a) agents use sparse worktrees (as in `ashes-agent-orchestration`) or a partial clone (`git clone --filter=blob:none`); (b) stop committing new raw packs into `assets/incoming`: keep the originals under `C:\Users\Jonna\Tools\_assets` or as GitHub release assets and commit only what the game imports plus the licence; (c) an audit of which `incoming` packs are referenced by any scene or script, then `git rm` the unused ones (history keeps them, the checkout shrinks); (d) a size gate in `tools/qa` that fails a commit adding a file over 25 MB.
4. Revisit LFS if a single large binary (over 50 MB) becomes routine, or the repo passes about 8 GB. If it is ever done: freeze all sessions for a day, run `git lfs migrate import --everything --include="*.glb,*.blend,*.hdr,*.flac"`, force-push once, and have every session re-clone. Check the GitHub plan's LFS storage and bandwidth quota first, because 5 GB of tracked binaries and CI checkouts can exhaust a small free quota quickly.
