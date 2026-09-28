---
name: ashes-performance
description: Make Rising Ashes run at the highest fps with no lag or hitches on any phone. Use whenever the user mentions fps, lag, stutter, hitches, performance, optimization, frame time, or before merging anything that adds per-frame work, streaming, NPCs, or big assets.
---

# Rising Ashes performance workflow

Goal: **60 fps with no hitches** on mid-range phones, a playable **30 fps** on the LOW tier on budget phones (Mali-G52 / Adreno 610 class), and uncapped smoothness on PC. The user said "highest fps, playable without lag". Treat stutter (p99 frame time) as seriously as the average.

## Where the time goes (as of 2026-09-28)
Measured on the RTX 4070 laptop with the Mobile renderer: **GPU 0.7–3.6 ms, CPU 7–16 ms per frame.** The game is **CPU-bound** (GDScript simulation, population LOD, streaming, draw submission). A phone CPU is about 4–6× slower, so every CPU ms on PC is roughly 5 ms on a phone. Fix CPU first.

## Budgets
| | LOW (budget phone) | MEDIUM/HIGH (mid phone) |
|---|---|---|
| Frame | ≤ 33 ms on the phone, so about ≤ 6 ms CPU on PC | ≤ 16.6 ms on the phone, so about ≤ 3 ms CPU on PC |
| p99 frame (hitches) | ≤ 2× the average | ≤ 2× the average |
| Triangles in view | ≤ 300k | ≤ 1.5M |
| Draw calls | ≤ 250 | ≤ 600 |
| Texture memory | ≤ 150 MB | ≤ 300 MB |

## Tools (use all three: numbers, profile, eyes)
1. **Benchmark:** `TIERS="low high" RENDERERS="mobile" SCENES="village city battle" bash tools/qa/bench/run.sh`. Results are appended to `docs/qa/bench_results.jsonl` (fps_avg, ms_p95/p99, cpu_process_ms, gpu_ms_avg, draw_calls, primitives). Close other Godot and Blender instances first, and keep the laptop plugged in.
2. **CPU profile by ablation:** run `bench.gd` with `--profile`. It disables one system at a time (autoloads WorldSim/Life/Frontier/Audio and each world child) and prints `PROFILE <node> saves X ms/frame`. Other flags: `--gpuprof` (per layer GPU cost), `--census` and `--drawcensus` (what's drawn), `--textures`.
3. **VISUAL check (required, the user insists):** numbers alone miss pop-in, hitches, flicker, T-poses, NPCs popping between sprite and model, and LOD swaps. Always:
   - run the playtest bot `kingdom/tools_qa/autoplay/run_autoplay.sh` and/or the visual perf recorder `tools/qa/perf_visual/` (frame strips with a frame-time graph overlay), then **look at the frames with Read**;
   - look at the frames around every frame-time spike (what's on screen when it hitches: a town streaming in, an NPC spawning, a menu opening);
   - compare LOW vs HIGH screenshots of the same view; LOW must still look good.

## Rules for code (tell the other sessions too)
- No heavy work in `_process` or `_physics_process`: use timers, slices spread over frames (a budget in ms per frame), and caches. Never allocate big arrays or dictionaries per frame.
- Streaming and spawning are spread out: at most N instantiations per frame, loaded in the background (`ResourceLoader.load_threaded_request`), with nothing blocking `load()` during play.
- Distant simulation runs at a lower rate (e.g. 2–5 Hz) and uses LOD for AI.
- Skinned characters are costly: cap full models by tier, share animation libraries, use sprites far away (but never within 9 m, see `population_lod.gd`).
- Rendering: MultiMesh for repeated things, cell batching, visibility ranges, shared atlases, no shadows from small props, and no realtime lights beyond the tier's budget.
- Every change gets measured before and after (bench plus the visual check), and the numbers go into `docs/qa/PERFORMANCE.md`.

## Coordination
The cloud session builds features and Codex owns animation behaviour. Frame rate is owned by the local session (see `docs/LOCAL_SESSION_HANDOFF.md`). Before every commit, `git fetch && git merge --no-edit origin/claude/focused-curie-m09hbd`, keep diffs small, commit only your own paths, and revert unrelated `.import` rewrites. Never kill Godot or Blender globally.
