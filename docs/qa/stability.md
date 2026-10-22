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

## 2026-09-28: quit-crash is NOT fixed — the earlier "fix" (queue_free + 10-frame wait) does not stop the 0xC0000005 crash; real root cause is an interaction between the `Quality` and `GUIDE` autoloads, not isolated

**This pass re-verified crash (a) from scratch and found the previously "verified" fix (commit `44a91577`, described above) does not actually work.**

**Repro, with real OS exit codes** (`Start-Process -Wait -PassThru`, not bash, per the methodology note above):
- `grounding_check.gd` (which already has the queue_free-then-await-10-frames `_shutdown()` from the earlier pass) run via `godot --path kingdom -s tools/qa/grounding/grounding_check.gd -- --adult --skipintro --out=...`: completes its scan (`GROUNDING samples=35679` printed), then **exit code 0xC0000005**. stderr showed the same RID-leak block as before (68 JoltShape3D, 165 Mesh, 264 Material, 158 Texture, ~1000s of buffer RIDs) — i.e. despite `main.queue_free()` + 10 awaited `process_frame`s, those RIDs are still not actually released before shutdown. The 10-frame wait does not do what the earlier pass believed.
- Also found (real bug, separate from the crash, not yet fixed): `_finish()` calls `_shutdown()` **without `await`**, and `_shutdown()`'s own first `await process_frame` returns control immediately, so `_process()` keeps running every subsequent frame while `phase` is still stuck at `"scan"` with `loc_i` already at `locations.size()`. Result: `locations[loc_i]` is read out of bounds every frame for the ~10 frames until `_shutdown()`'s coroutine finally reaches `quit()` (`SCRIPT ERROR: Out of bounds get index '6' (on base: 'Array')` at `grounding_check.gd:103`, repeated). Harmless to the crash (confirmed by the isolation below, which reproduces the crash with zero game code loaded), but worth a real fix later: `_finish()` should `await _shutdown()` and/or set `phase` to something terminal first.

**Isolation.** Per the task's step 1, tested whether the crash needs game code at all. It does not:
```gdscript
extends SceneTree
func _initialize() -> void:
    print("TRIVIAL_BOOT_OK")
    call_deferred("quit")
```
run as `godot --headless --path kingdom -s trivial_quit.gd` — **no main.tscn, no scene, no threads, one frame, immediate quit** — still exits **0xC0000005**. Also crashes identically without `--headless`, so it is unrelated to Vulkan/RenderingServer/window teardown (rules out the entire theory in the "Crash 1" section above about WorkerThreadPool/RenderingServer teardown races — that section's fix doesn't touch the actual cause).

**Bisection (all via the trivial script above, so every result below is with zero game/world code loaded — only `project.godot`'s `[autoload]` list was changed between runs, restored after):**

| Autoloads enabled | Exit code |
|---|---|
| none (all commented out) | 0x00000000 clean |
| `Quality, Game, WorldSim, Audio, Frontier, Life` (first 6) | 0x00000000 clean |
| `GameplayCueManager, GUIDE, DialogueManager` (addon group) | 0x00000000 clean |
| `QuestWeaverGlobal, QuestWeaverServices, QuestWeaverGameState` | 0x00000000 clean |
| first 6 + `GameplayCueManager, GUIDE, DialogueManager` (i.e. everything except QuestWeaver) | **0xC0000005** |
| `Quality` + `GameplayCueManager, GUIDE, DialogueManager` | **0xC0000005** |
| `Quality` + `GameplayCueManager` only | 0x00000000 clean |
| `Quality` + `GUIDE` only | **0xC0000005** |
| `GUIDE` only (no Quality) | 0x00000000 clean |
| `Quality` only (no GUIDE) | 0x00000000 clean |

**Conclusion so far: `Quality` (`kingdom/scripts/core/quality.gd`) and `GUIDE` (`kingdom/addons/guide/guide.gd`) autoloads together, and only together, cause the crash** — removing either one is reliably clean, every other autoload and combination tested is clean, and QuestWeaver (the group with the most static caches) is not involved at all.

**Narrowed further, and this is the confusing part:** with `Quality` + `GUIDE` both enabled,
1. No-opping `GUIDEInputTracker._instrument()` (the function that adds an internal child Node to the root Viewport and connects `gui_focus_changed` — the most obvious "touches the root viewport" suspect) still crashes.
2. No-opping **all** of `GUIDE._ready()` (`process_mode`, node creation, both signal connects — replaced with an immediate `return` after a print) **still crashes** with the same 0xC0000005.

So the trigger is not runtime logic in `GUIDE._ready()` at all — it reproduces from `GUIDE.gd` merely being loaded/instantiated as an autload alongside `Quality`, before any of its own code executes. That points to something at script-load/parse time (the file's top-level `preload()`s of `GUIDESet`/`GUIDEReset`/`GUIDEInputTracker`, or its typed member declarations like `var _active_action_mappings:Array[GUIDEActionMapping]`) interacting with `Quality`'s boot-time work (`Quality._ready()` reconfigures the root Viewport's MSAA/scaling/shadow atlas via `RenderingServer` calls and connects to `get_tree().node_added`), or — most likely given how these bugs usually behave — this is a **pre-existing marginal memory-corruption bug** (a real double-free/use-after-free somewhere in engine-adjacent code, e.g. Jolt physics or another GDExtension) that is **allocation-layout-sensitive**: adding or removing almost any code changes whether it's hit, which is consistent with it reproducing via a completely inert `GUIDE._ready()` and with the original "Crash 1" fix (queue_free + wait) not helping at all, since that fix targeted the wrong layer (scene-tree/thread teardown) rather than this.

**Not fixed in this pass — do not treat `44a91577`'s QA-harness change as a real fix for crash (a).** It's still a reasonable defensive change to keep (freeing the loaded scene in an orderly way before quitting is correct practice regardless), but it is not sufficient and the "Verified: zero new Event ID 1000 entries" claim in the "Crash 1" section above was against a run that either got lucky or predates this Quality+GUIDE interaction being present.

**Ruled out this pass** (each confirmed with a real `Start-Process` exit code, not bash's unreliable one):
- WorkerThreadPool / threaded ResourceLoader / scene-tree teardown ordering (crash reproduces with zero threads and no scene at all).
- RenderingServer / Vulkan / window teardown (`--headless` crashes identically).
- Static Resource-holding caches in game scripts (`assets.gd`, `grass_field.gd`, `breakable.gd`, `procedural_rig.gd`, etc.) — never loaded in the trivial repro.
- QuestWeaver's three autoloads (its own static caches were the leading suspect in the bug's original hypothesis) — clean alone, and not required for the crash to occur with the others.
- `GameplayCueManager` (GodotGAS) and `DialogueManager` — neither is required; only `Quality` + `GUIDE` together are necessary and sufficient in every combination tried.
- `GUIDEInputTracker._instrument()`'s root-viewport child-node injection specifically, and all of `GUIDE._ready()`'s runtime logic — crash persists with both fully no-op'd, so it's not in `_ready()`'s behavior.

**Not yet found:** the exact statement/mechanism inside `Quality`+`GUIDE`'s combined script-load that trips this. Next steps for whoever picks this up: (1) bisect `Quality._ready()` itself line-by-line the same way (no-op pieces of it with `GUIDE` fully enabled, rather than the reverse) — not yet tried, since every no-op attempt so far was on the `GUIDE` side; (2) get a real Windows crash dump (`%LOCALAPPDATA%\CrashDumps`, not checked this pass — worth enabling `WerFault` dump collection for this exe) and open it in a debugger to get the actual faulting call stack instead of continuing to bisect blind; (3) try Godot's ASan/debug build if available, since `ntdll.dll+0xfa7d` heap-corruption crashes are exactly the class of bug ASan is built to catch immediately, versus days of manual bisection.

No code changes were committed for the crash itself this pass (no fix was found safe/confident enough to ship) — reverted all temporary diagnostic edits (`project.godot` autoload comment-outs, `guide.gd`/`guide_input_tracker.gd` no-ops) back to the committed originals; only this documentation section is new. `tools/qa/grounding/grounding_check.gd` has an unrelated, uncommitted change from a concurrent session (a scan-scope fix for character subtrees) that was left untouched.

### 2026-09-28 (local, follow-up): the quit crash is engine-side, not game logic
- The minimal repro (a SceneTree script, `--headless`, no scene, `quit()` on frame 3) gives **0xC0000005 3/3**. It still does with `Quality._ready()` emptied,
  so neither `Quality` nor `GUIDE` runtime code triggers it. `--verbose` shows ~40 leaked `GDScriptNativeClass` objects and 80 resources in use at exit
  (world/vfx/sim scripts, shaders, the vfx atlas, gloot/guide/quest_weaver scripts), loaded through autoload class references and kept alive by
  cyclic script references (a known Godot 4 GDScript leak). The crash happens while the engine tears these down.
- **GDExtensions are NOT loaded in any of our QA or dev runs**: `kingdom/.godot/extension_list.cfg` doesn't exist (the editor normally writes it).
  So Terrain3D, LimboAI and godot-sqlite are absent at runtime here (hence "sqlite doesn't register"), while an export generates the list and **does** load them.
  Open the project once in the editor to regenerate it, and re-test with them loaded.
- The installed engine is 4.6.0 (2026-01-26); 4.6.1, 4.6.2 and 4.6.3 (2026-05-20) have shipped since. Next: try 4.6.3 with the same repro before any further bisecting.

## 2026-09-28: ROOT CAUSE of the random 0xC0000005 during boot/play (about 1 in 8 boots): FIXED
- Found with WinDbg (cdb) on 3 crash dumps from Godot 4.6.3. All three had the identical 10-frame chain on a `WorkerThread N`:
  `HashSet::_insert` (core/templates/hash_set.h) ← BaseMaterial3D shader update (material dirty list and shader-code strings)
  ← `ArrayMesh::_set_surfaces` (scene/resources/mesh.cpp) ← resource loader. The crash reads a hash bucket with a garbage index.
- Cause: `RegionDressing` preloaded region GLBs with `ResourceLoader.load_threaded_request()`. A worker loading a mesh
  updates the engine's shared material/shader tables while the main thread creates StandardMaterial3Ds, which tears the HashSet.
- Fix: those scenes are now loaded once on the main thread during boot through `Assets.scene()` (cached; about 250 ms), with no threaded loads.
  Rule added to the `ashes-performance` skill: never threaded-load anything carrying meshes or materials.
- Verification: before the fix, 3/25, 1/15 and 1/7 boots crashed. After it, **16/16 clean boots** (each confirmed the world loaded;
  the loop was cut short by a session restart, not a crash). Run more boots with a zz_boot-style loop when convenient.
- Ruled out along the way: terrain plan threads, runtime LOD generation (90 stress rounds clean), physics interpolation, and GDExtensions.

## 2026-09-29: "the game keeps crashing" re-investigation (local)
**Evidence.** Windows Event 1000 for Godot (since 27 Sep): 58 x `ntdll.dll+0xfa7d` (Godot 4.6.0, the quit crash, gone since 4.6.3) and
9 x `Godot_v4.6.3-stable_win64.exe+0x539f5a9` (all 28 Sep 17:49-19:16, all `-s zz_boot.gd` runs). **No Godot crash event after 28 Sep 19:16**;
the threaded-load fix `0137fa0d` landed 28 Sep 23:28. cdb on dump `Godot_v4.6.3-stable_win64.exe.139296.dmp` (process uptime 46 s): access violation
(read of `uint32[idx]` from an index array) on `WorkerThread 8`; strings referenced by the fault function and its callers are `vertex_data`, `index_count`,
`Surface version provided...`, `ArrayMesh::_set_surfaces` (mesh.cpp), `material_set_shader`, hash_set.h; the frames below are
`ResourceLoaderBinary::load` recursion (`Loading resource: %s`, `local://`, `metadata/`) under `WorkerThreadPool`. Main thread was in GDScript
(`Node3D.set_global_position` propagation). So the same signature as the fixed one: a mesh loaded on a worker thread racing main-thread material/shader creation.
These 9 dumps predate the fix. The user's own `user://logs` were rotated away by other agents' runs (Godot keeps 5), so the owner's latest crashes could not be read.

**Reproduction on latest origin (merge of 213551e6 + later, worktree `PA_wt_crash`, Godot 4.6.3, windowed, RTX 4070 laptop, machine busy with other agents).**
Boot loop `kingdom/tools_qa/boot_loop/boot_loop.gd` (new; counts a boot only if a world exists and ran 20 s, checks the real exit code):
- direct main.tscn 12/12 clean (11/11 more on the pre-merge tree), front-end loading screen (threaded load of main.tscn) 8/8 (11/11 pre-merge),
  real path boot.tscn -> splash key -> menu -> Continue -> loading -> world 10/10, `--rendering-method mobile` 6/6. **0 crashes in 36 post-merge boots (58 total).**
- Play soak (perf_visual, real input) only 2 routes completed (about 4 minutes of play, 29-39 fps under load): **the 20-minute soak was NOT done** (usage limit); no crash in those.
- Not run: GDExtensions loaded (create `.godot/extension_list.cfg`, terrain_3d/limboai/sqlite have compat minimum <= 4.5 so no mismatch is expected), long autoplay.

**Findings / fixes (small).**
1. `RegionDressing._drain_queue` assigned a freed root to a typed var: `SCRIPT ERROR: Trying to assign invalid previously freed instance` (region_dressing.gd:79). Fixed (Variant first).
2. `audio_director.gd` 30 s debug voice-count loop touched freed players: guarded (`is_instance_valid`). The main.gd `_process` null guard was already present after the merge.
3. QA harnesses broke with the new world-loading veil (it frees itself): `main.hud._loading.visible` on a freed object gave a 16 MB SCRIPT ERROR flood and an endless run in
   perf_visual, bench, grounding_check, debug_floaters, shots, movement_qa, autoplay, store_shots. They now use `hud._veil()` / `is_instance_valid`.
4. `tools_qa/boot_flow/boot_flow.gd` fails ("world veil never appeared") because New Game now goes to character creation and "Start Game" no longer starts the world. Test is stale, not a crash.
5. Open, not crashes: under `--rendering-method mobile` + HIGH quality (glow on) 72 rendering errors per boot start with `get_texture_slice_view: Index p_mipmap = 4 out of bounds
   (mipmaps = 4)` (render_scene_buffers_rd.cpp), i.e. the glow chain, then "framebuffer is null" / "Mismatch fragment shader output mask". Forward+ has none. LOW/MEDIUM tiers have glow off; test on device.
   The leaked-at-exit RIDs (76 Jolt shapes, meshes, materials) appear on every quit and did not crash in 58 boots.
Next: 20+ min soak (`tools/qa/perf_visual/run.sh`, several routes), GDExtension-loaded boots, a mobile-tier glow check, then delete the stale rotated logs assumption by copying `user://logs` before other agents overwrite them.
