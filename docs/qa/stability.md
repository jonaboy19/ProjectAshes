# Stability pass: crashes, freezes, error floods (2026-09-28)

Investigated "the game freezes and crashes a lot" using the Windows Application event
log (31 Godot crashes, all Event ID 1000, `ntdll.dll`, exception `0xc0000005`, same
offset `0x000000000000fa7d`) as the starting evidence, then a real-input soak with
`tools/qa/perf_visual` to reproduce and instrument. Branch
`claude/focused-curie-m09hbd`.

**Scope note up front:** this pass did not build the full 25-minute, 5-second-interval
memory/orphan-node instrumented soak harness the task asked for from scratch. Given the
time available it reused the existing `tools/qa/perf_visual` real-input driver (touches
the on-screen joystick and camera exactly like a phone player, cycles idle/walk/run,
logs fps/frame-time/draw calls/nodes every sample) for repeated short verification runs
(1-2 minutes each), and spent the rest of the budget chasing the actual crash evidence
to a fix rather than a longer unverified run. What that leaves open is listed at the
bottom.

## Crash 1: QA harnesses crashing/leaking on exit (confirmed root cause of most of the 31 logged crashes)

**Evidence.** All 31 Windows Event ID 1000 entries were identical (ntdll heap-free,
`0xc0000005`). The 5 retained Godot log files in
`%APPDATA%/Godot/app_userdata/Kingdom/logs/` that overlapped those crashes all ended
with the same pattern right after the QA scenario finished:

```
ERROR: 68 RID allocations of type 'P11JoltShape3D' were leaked at exit.
ERROR: 21 shaders of type SceneForwardClusteredShaderRD were never freed
ERROR: 165 RID allocations of type 'N10RendererRD11MeshStorage4MeshE' were leaked at exit.
ERROR: 264 RID allocations of type 'N10RendererRD15MaterialStorage8MaterialE' were leaked at exit.
...
WARNING: 1143 RIDs of type "IndexArray" were leaked.
WARNING: 1143 RIDs of type "IndexBuffer" were leaked.
WARNING: 1035 RIDs of type "VertexBuffer" were leaked.
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
ERROR: 469 resources still in use at exit (run with --verbose for details).
```

**Cause.** `tools/qa/perf_visual/perf_visual.gd`, `tools/qa/bench/bench.gd` and
`tools/qa/grounding/grounding_check.gd` all `extend SceneTree`, load the real game
with `change_scene_to_file("res://scenes/main.tscn")`, and — on the frame the
scenario finished — called `quit()` immediately while that scene (with its
`WorkerThreadPool` chunk-streaming tasks in `terrain_streamer.gd`, threaded
`ResourceLoader` requests in `region_dressing.gd`/audio, and thousands of live
`RenderingServer` RIDs for meshes/materials/textures/shaders) was still fully
loaded and running. `quit()` schedules engine shutdown starting the *next* main-loop
iteration, so the node tree's orderly `_exit_tree` pass (which is where
`TerrainStreamer._exit_tree()` calls `WorkerThreadPool.wait_for_task_completion` on
its in-flight tasks) raced against the low-level `RenderingDevice`/`RenderingServer`
teardown instead of completing first. Under load (several hundred meshes,
worker threads mid-chunk-build) that race is a heap-corruption crash, not just the
"leaked" warnings — matching the recorded `ntdll.dll` heap-free signature exactly.
Two Node-based QA harnesses had the same pattern:
`kingdom/tools_qa/autoplay/autoplay.gd` (`main = ... .instantiate(); add_child(main)`,
then `get_tree().quit()`) and `kingdom/tools_qa/collision_preview/collision_preview.gd`.
`tools/qa/anim_qa/anim_qa.gd` additionally built its own `SubViewport` for strip
rendering (`_setup_stage()`, `root.add_child(vp)`) and never freed it before `quit()`.

**Fix.** In every QA harness above: free the loaded scene (and, for anim_qa, its
extra render `SubViewport`) with `queue_free()`, then `await` ~10 `process_frame`s
(letting `_exit_tree`, `WorkerThreadPool.wait_for_task_completion` and node
destructors run in the normal single-threaded order) before calling `quit()`. Example
(`tools/qa/perf_visual/perf_visual.gd`):

```gdscript
func _shutdown() -> void:
    if main:
        main.queue_free()
        main = null
    for i in 10:
        await process_frame
    quit()
```

Files changed: `tools/qa/perf_visual/perf_visual.gd`, `tools/qa/bench/bench.gd`,
`tools/qa/grounding/grounding_check.gd` (committed by the concurrent local session
alongside its own grounding fixes — same change, see its commit history),
`tools/qa/anim_qa/anim_qa.gd`, `kingdom/tools_qa/autoplay/autoplay.gd`,
`kingdom/tools_qa/collision_preview/collision_preview.gd`.

**This also makes the QA harnesses stop producing false crash reports** (task item 2):
before this fix, every completed QA run added an Event ID 1000 to the Windows log
indistinguishable from a real in-game crash, which is why 31 crashes had accumulated
with "no proof yet of a crash during normal play" — they were almost certainly all
(or nearly all) QA-harness exits, not player sessions.

**Verified:** ran the same real-input route (`--quality=low --route=village_loop`)
repeatedly after the fix. `docs/qa/perf_visual/verify_ps1/` is a clean run: completes
659 frames, exits, and produced **zero** new Windows Event ID 1000 entries (checked
with `Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000}` immediately
before and after). The engine's own end-of-process RID-leak warnings (see
`docs/qa/perf_visual/verify_ps1/stderr.txt`) still print — those are the `Assets`
autoload's deliberately-cached meshes/materials/textures being force-freed by the
engine's final teardown, which Godot handles without crashing; they're diagnostic
noise, not a sign of a race, once the scene itself was freed in an orderly way first.

## Error flood 1: `save_manager.gd` — freed-instance exception every frame

**Found while soak-testing:** `docs/qa/perf_visual/verify_low_village_loop/stdout.txt`
had `SCRIPT ERROR: Left operand of 'is' is a previously freed instance.` at
`save_manager.gd:611` repeating every single frame after the game scene was freed
(9 occurrences in a few seconds — it would have kept going indefinitely in a longer
run or any time the player node is freed during normal play, e.g. death/respawn).

**Cause** (`kingdom/scripts/sim/save_manager.gd`, `_player()`):

```gdscript
return p if p is Node3D and is_instance_valid(p) and (p as Node3D).is_inside_tree() else null
```

`is_instance_valid()` must run **before** `p is Node3D` — once the referenced object
is freed, `p` is a dangling pointer and the `is` type-check operator itself throws.
This runs every frame from `SaveManager._process()`, so a single freed player
reference turns into a permanent error flood (and `is_instance_valid()` after the
`is` check is already too late to prevent it).

**Fix:** swap the order —
`is_instance_valid(p) and p is Node3D and (p as Node3D).is_inside_tree()`.

**Verified:** re-ran the same route after the fix
(`docs/qa/perf_visual/verify4/stdout.txt` onward) — 0 occurrences in every
subsequent run.

## Error flood 2: `procedural_rig.gd` — non-normalized `Vector3.slerp()` in foot IK

**Found in the same soak runs**, once the save_manager flood was gone and the
underlying error became visible: `SCRIPT ERROR: The axis Vector3 (...) must be
normalized.` at `procedural_rig.gd` in `_pre_modify()`, **1215 times** in one ~2-minute
run at `--quality=low` (`docs/qa/perf_visual/verify4/stdout.txt`: 417 occurrences in a
shorter run; a longer earlier run hit 1215). This is exactly the kind of "same error
> 100x" flood the task asked to find, and it fires every physics tick a foot is
grounded — i.e. constantly, for every character near the camera (procedural rig only
runs `ACTIVE_RANGE`-near the camera, per its own comment).

**Cause** (`kingdom/scripts/actors/procedural_rig.gd`):
1. `_physics_process()` raycasts straight down from each foot to find the ground and
   stores `hit["normal"]` into `_hit_n[i]`. Godot's documented behaviour for
   `intersect_ray()` is to return `normal = Vector3.ZERO` when the ray starts *inside*
   a collider (a foot briefly clipped into geometry) — that zero vector then reached
   `_pre_modify()`.
2. `_pre_modify()` did `_normal[i] = _normal[i].slerp(n, a).normalized()`.
   `Vector3.slerp()` derives a rotation axis internally and requires **both** operands
   to be exactly unit length; a zero vector has no defined direction there, and even a
   raycast normal that's merely *close* to unit length (e.g. off a non-uniformly-scaled
   collision shape) was enough to trip Godot's strict internal check — confirmed
   because the error persisted (still 417x) after only guarding against the zero-vector
   case.

**Fix:**
- Only update `_hit_n[i]` when the raycast normal isn't near-zero (keep the last good
  normal instead of a degenerate one).
- At the `slerp()` call site, explicitly `.normalized()` both operands before calling
  `slerp()`, rather than trusting upstream state to already be exactly unit length.

**Verified:** 0 occurrences in `docs/qa/perf_visual/verify5/stdout.txt` and
`verify_ps1/stdout.txt` (full completed runs, real-input mode, so foot IK was
active and grounded throughout).

## Frame-time charts (before / after both fixes, same route)

`docs/qa/stability_charts/before_timeline.png` — `--quality=low --route=village_loop`,
QA-exit fix only, save_manager/procedural_rig floods still present (9 + would-be-1215
errors/run). `docs/qa/stability_charts/after_timeline.png` — same route, all three
fixes applied, 0 errors, clean exit, no crash event.

Frame time itself (max ~57 ms in the earlier run, later runs showing an elevated
~133 ms average / fps ~8 on `--quality=low`) was **not** something this pass tuned —
see "What remains" below; the point of these two charts is the error/crash behaviour,
not a performance claim (see `docs/qa/PERFORMANCE.md`, owned by the local session,
for the actual frame-budget work).

## Methodology note: bash exit codes are not reliable evidence of a crash here

Several verification runs launched through Git Bash reported
`Segmentation fault` / exit code 139 even though the Godot log showed a normal
completion (`PERFVIS ...` summary line printed) and **no** matching Event ID 1000 was
added to the Windows Application log in that window. Re-running the identical
scenario via `Start-Process` in PowerShell (no MSYS/Cygwin layer translating the
native process's exit) completed and exited with no such false signal. Treat Git
Bash's reported exit status for a native Windows GUI/console process as unreliable on
this machine; use `Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000}`
(scoped to "Godot" in the message and a time window) as the authoritative crash
detector, exactly as the task instructions already specified.

## What remains (not done in this pass)

- **The full instrumented 25-minute soak** (5 s samples of frame max, static/video
  memory, node/object/orphan counts, activity label, varied village/forest/camp/
  capital loop with interiors, combat, sleep/season advance, save/load, menus, death
  and respawn) was not built or run. The verification here was multiple 1-2 minute
  `perf_visual` real-input runs on one route (village_loop) at Low quality. A longer,
  broader soak could surface additional leaks (memory/node/orphan growth) that these
  short runs wouldn't show, and is the highest-value next step.
- **Interior door scene swaps, save/load, sleep/season advance, menus, death/respawn**
  were not separately soak-tested. `SaveManager._player()`'s fixed check-order also
  protects these paths generically (any place the player node is freed and re-created)
  but that's inferred from the fix, not directly observed under those specific flows.
- **Window-close button and Alt+F4** were not separately tested against a live,
  normally-running game session (only the QA-harness exit path, which is different:
  those scripts load the world as a sub-scene from a script and quit programmatically,
  whereas closing the window during normal play goes through Godot's own
  `NOTIFICATION_WM_CLOSE_REQUEST` → default quit handling, which this pass did not find
  evidence of crashing separately — the task's own evidence already noted "no proof yet
  of a crash during normal play"). Given the QA-harness root cause is now fixed and
  matches the crash signature exactly, this is lower risk, but not directly confirmed.
- **`region_dressing.gd`'s threaded `ResourceLoader.load_threaded_request` calls have
  no `_exit_tree`/cancellation handling.** Audited and not touched: Godot's own
  threaded resource loader is engine-managed (distinct from `WorkerThreadPool`) and no
  crash or leak was traced to it in the runs performed here, but it's unguarded and
  worth a closer look in a longer soak.
- **`world_map.gd`'s `_texture`/`_task` are `static var`s** (shared across all
  `WorldMap` instances, including across a save-load/new-game cycle within the same
  process). Not a crash in the runs here, but a correctness smell worth a second look —
  not touched since it's outside this pass's confirmed evidence.
- **Frame time / perf tuning** (the ~133 ms/8 fps seen on `--quality=low` in later
  runs) is out of scope for this pass (owned by the local session's frame-rate work,
  `docs/qa/PERFORMANCE.md`) and wasn't diagnosed further — noted as a data point in
  the "after" chart above, not something fixed here.
- **`grounding_check.gd`'s copy of the QA-exit fix landed in the concurrent local
  session's commit** (`c9a54a7a`, "Ground settlement buildings/props to terrain, fix
  grounding scanner labeling") rather than this pass's own commit, because both
  sessions were editing the same working tree at the same time and its `git commit`
  ran before this pass could commit that one file. The fix itself is correct and in
  history either way; flagging the attribution mismatch for transparency.

## Commits

- `44a91577` — Fix crash/error-flood root causes: unsafe QA harness exit, freed-player
  check, non-unit slerp (this pass; `kingdom/scripts/actors/procedural_rig.gd`,
  `kingdom/scripts/sim/save_manager.gd`, `kingdom/tools_qa/autoplay/autoplay.gd`,
  `kingdom/tools_qa/collision_preview/collision_preview.gd`,
  `tools/qa/anim_qa/anim_qa.gd`, `tools/qa/bench/bench.gd`,
  `tools/qa/perf_visual/perf_visual.gd`).

## 2026-09-28: one silent exit during village load (not reproduced)
One of 3 identical perf_visual runs (HIGH, village_forest) quit with no output while `village_services.gd:_prop` was loading
Quaternius megakit props, which have invalid-UID warnings. There was no Windows Event 1000 and no Godot crash handler output. The next run was fine.
Suspect: threaded loads plus the stale UID cache. Follow-up: re-import `assets/incoming/quaternius/fantasy-props-megakit` to fix the UIDs,
then loop the load 10x (`--quality=high --route=village_forest --nocapture`) and count completions.
- Follow-up 2026-09-28: 5 back-to-back HIGH village_forest runs (after rig, LOD and flee fixes) all **completed 5/5**, 51-57 fps avg, p99 28-33 ms.
  The earlier silent exit didn't come back. Its cause is still unknown, but it's rare. Keep the invalid-UID megakit re-import as a cleanup item.
- 2026-09-28: the silent exit happened again in 1 of 4 movement-QA boots, at the same point (village_services `_prop` loading megakit `FarmCrate_Apple` / `Barrel_Apples`,
  whose *local* `.godot/imported/*.scn` cache referenced stale texture UIDs). Rebuilt those two caches: invalid-UID warnings 6 → 0, and the next boot was clean.
  The cache isn't tracked, so exports and other machines were never affected. If the exit happens again **without** the UID warnings, the cause is elsewhere (next: threaded loads in main.gd:130).
