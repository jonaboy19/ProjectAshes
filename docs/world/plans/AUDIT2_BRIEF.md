# Execution brief: Rising Ashes presentation audit 2

Planned by Fable 5.1 (2026-10-12), executed by a Sonnet agent.

## 0. Ground truth you must not re-derive

| Item | Value |
|---|---|
| Godot | `C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe` (export `G=` to this) |
| Worktree | `C:/Users/Jonna/Documents/PA_wt_audit`, branch `claude/aaa-audit-2`, at `e6589a0a` = `origin/claude/focused-curie-m09hbd` tip when planned (fetch + merge origin first), `.godot` imported, 317 `*_lod_bake.jpg` sidecars present. Do NOT create another worktree, do NOT re-import. |
| Temp dir | `T="$APPDATA/ashes_audit2"` (= `C:/Users/Jonna/AppData/Roaming/ashes_audit2`). Never `/tmp`. |
| Shell | Git Bash with `export MSYS_NO_PATHCONV=1` as the first line of EVERY bash call (without it `git show rev:path` and `--out=C:/...` get mangled; a past agent wiped folders this way). |
| Target | `docs/art/reference/00_MAIN_kingsreach_gate_market.webp` (read it with the Read tool before scoring anything). Secondary: `03_TARGET_gate_market_detailed.webp`. |
| Resolution / renderer | `--rendering-method mobile --resolution 2340x1080`. Never `--headless` for any render (black frames). |
| Tiers | `-- --quality=high` and `-- --quality=low` (parsed by the `Quality` autoload, `kingdom/scripts/core/quality.gd` `_cmdline_tier`; adaptation is off when forced). ALWAYS pass it: AUTO picks a tier from the GPU. |
| LOW gate budget | ≤ 135 visible draw calls in the `gate` view at full load (pass 14 measured 133–137). |
| Line endings | `core.autocrlf=false`; every inspected file is stored LF. Preserve whatever each file has; never run a formatter; check `git diff` shows only your lines (no whole-file diffs). |
| Faces | Another agent (worktree `PA_wt_faces`, branch `claude/npc-faces`) owns faces. Do not edit: `kingdom/scripts/actors/hero_face_driver.gd`, `kingdom/scripts/actors/hero_tier_a.gd`, the face/head/hair/skin code in `kingdom/scripts/world/assets.gd`, `kingdom/scripts/population/villager.gd` look code, `character_creation.gd::build_model`, anything under `kingdom/assets/incoming/characters/`. |
| Godot processes | Launch as `"$G" ... & GPID=$!; wait $GPID` (or `timeout 600 "$G" ...`). Kill only `$GPID`. Never `taskkill /IM`, never `pkill -f godot`: other agents run Godot on this PC. Before captures: `tasklist | grep -i godot` and note whether an `--export` run is active (if so, wait). |
| Battery | fps on battery is meaningless; draw calls are still valid. |
| Phone | Do not touch the phone. All measurements are PC-side proxies. |

Skills to read first (they are short): `.claude/skills/ashes-aaa-camera-hud/SKILL.md`, `ashes-environment-look`, `ashes-baked-quality`, `ashes-video-review`, `ashes-visual-qa`, `ashes-aaa-review`, `ashes-parallel-commits`.

## 1. Capture recipe

### 1.1 Build ONE harness (new file, allowed): `kingdom/tools_qa/aaa_audit/audit_views.gd` + `audit_views.tscn`

Copy `kingdom/tools_qa/aaa_camera/feel_views.gd` (and its 4-line `.tscn`) and change only what is listed here. Keep: the boot wait (`while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil())`), `_place()`, `yaw_for()`, `_home()`, `_near_lot()`.

Changes:
1. Args: `--out=`, `--tag=`, `--only=a,b,c` (scene ids below), `--hud=0|1` (default 1).
2. Right after the boot wait: `main.weather.auto = false; main.weather.set_weather("clear", 0.1)` (weather is a seeded Markov schedule; unforced captures differ run to run).
3. Pin time EVERY frame while waiting: add `_process(_d): if _pin >= 0.0: WorldSim.time_of_day = _pin` (look_capture does this; feel_views sets it once and the clock drifts).
4. `shot(name)`: after `await RenderingServer.frame_post_draw`, grab `img`, then:
   - `img.save_jpg(out.path_join("%s_%s.jpg" % [tag, name]), 0.92)`
   - print `AUDIT <name> draws=<N> prims=<P> fps=<F>` where `N = main.viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)` (the world SubViewport, not the root; same call `main.gd::_screenshot` uses).
   - if `--hud=0`: `main.hud.visible = false` before the shot and back after.
5. Scenes (ids and exact placement):

| id | Placement (copy from) | Time | Notes |
|---|---|---|---|
| `first_exterior` | feel_views view 1: `main.HOME_SPAWN` (2, 4.5), look toward `_home()["pos"]` | **8.0** (what the player sees after birth: `main.gd` line 278 `maxf(saved_time, 8.0)`) | HUD on |
| `road` | `a = WorldGen.settlements[0]["pos"]` (Ashford), `b = WorldGen.settlements[1]["pos"]` (Kingsreach); `_place(a.lerp(b, 0.55), b - a)`; roads are straight settlement-to-settlement segments (`world_gen.gd` 1195–1206, `WorldGen.roads: Array[Vector2i]` of index pairs) | 11.0 | HUD on |
| `gate` | exactly `main.gd` `"gate"` case (lines 1098–1110): `cap = WorldGen.settlements[1]`; `dir = Vector2(cos(ga), sin(ga))` with `ga = cap["plan"]["gates"][0]`; spot `cap["pos"] + dir * (cap["radius"] - 42.0)`; `main._teleport(spot, 0)`; `player.set_camera(atan2(-dir.x, -dir.y), -0.05)`; then `main.settlements.focus = player.global_position; 4x main.settlements.update_now(); main.settlements.finish_prop_jobs()`; wait 120 frames | 15.0 | The draw-budget scene. Capture both `--hud=1` and `--hud=0` (name `gate` and `gate_nohud`). |
| `dialogue` | feel_views step 7, on the benchmark street spot (`plan["streets"][0]`, `a + dir*22 - dir.orthogonal()*1.5`, look `dir.rotated(0.3)`): `tt = main.services.get("talk_target"); if tt.call("qa_open"): await frames(90)` | 15.5 | Print the partner name as feel_views does. `main.hud.close_menu()` after. |
| `wolf` | `main.gd` `"frontier"` case (1032–1049): `den = Frontier.ecology.dens[0]`, `ws = Frontier.runestones.stones[7]` (or `[0]`), spot `den["pos"] - dir*40 - side*2.5`; `main.frontier.focus = Vector3(den.pos.x, 0, den.pos.y); main.frontier._timer = 0.0; main.frontier._process(0.0)`; move every `Wolf` in group `team1` to `spot + dir*rand(12,22) + side*rand(-7,7)` and `w.state = Wolf.State.STALK`; `player._invulnerable = 9999.0`; wait 90 frames; `player.toggle_lock()`; wait 45; shot `wolf_lock`; also shot `wolf` before locking | 15.0 | LOW caps packs to 2 wolves (`frontier_presence.gd::_spawn_pack`); that is expected. |
| `dusk` | the benchmark-street spot above (same as `p9_6_benchmark_18.png`) | 18.6 | keep comparable with p9 |
| `night` | same spot | 22.0 | |

Each `_place` must be followed by `await frames(150)` then `main.hud.close_menu()` then `await frames(20)` (streaming settles; as in feel_views). Print `AUDIT DONE` and `get_tree().quit()`.

Run (one process per tier; ~2–3 min each):
```bash
export MSYS_NO_PATHCONV=1; G=C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe
T="$APPDATA/ashes_audit2"; mkdir -p "$T/before"
cd /c/Users/Jonna/Documents/PA_wt_audit/kingdom
for q in high low; do
  timeout 600 "$G" --path . --rendering-method mobile --resolution 2340x1080 res://tools_qa/aaa_audit/audit_views.tscn \
    -- --adult --skipintro --quality=$q --out="$T/before" --tag=$q 2>&1 | grep -aE "^AUDIT|SCRIPT ERROR|ERROR" | tee "$T/before/log_$q.txt"
done
```
A segfault AFTER `AUDIT DONE` is a known engine shutdown crash; the files are fine.

### 1.2 Title / menu and character creator (no user args allowed, else boot skips to the game)
```bash
BOOT_FLOW_OUT="$T/before" BOOT_FLOW_TAG="boot_" BOOT_FLOW_FAST=1 BOOT_FLOW_SKIP=1 \
  timeout 600 "$G" --path . --rendering-method mobile --resolution 2340x1080 -s res://tools_qa/boot_flow/boot_flow.gd
```
Stills: `boot_01_intro_fadein`, `02_intro_mid`, `03_splash`, `04..06_first_run_*`, `07_main_menu`, `08_new_game`, `08b_character_creation`, `08c_creation_tab_N`. Tier is irrelevant for 2D screens: run once, file it as `high`. `boot_flow.gd` backs up and restores `user://settings.cfg`; never run two boot_flows at once. For first-minute pacing run it a second time WITHOUT `BOOT_FLOW_FAST` and WITH `--write-movie "$T/pacing/f.png" --fixed-fps 30` (engine args before `-s`), then `SRC_FPS=30 bash tools/qa/video_to_sheets.sh "$T/pacing" "$T/pacing_sheets" 4 4 3 480` and read `sheet_*.png` in order; frame index / 30 = seconds.

### 1.3 Parchment map
```bash
timeout 600 "$G" --path . --rendering-method mobile --resolution 2340x1080 -s res://tools_qa/map/map_capture.gd -- --adult --quality=high --out="$T/before" --tag=map_high --layer
```
(`--layer` = the painted Region 1 parchment via `map_parchment_layer.gd`; add a `--nofog` run too.) Repeat with `--quality=low`.

### 1.4 Motion checks (only for dialogue camera ease, combat lock-on, HUD calm fade)
Movie Maker through the same harness: add `--write-movie "$T/mov/f.png" --fixed-fps 30` before the `.tscn` and `--only=dialogue` (or `wolf`); then `SRC_FPS=30 bash tools/qa/video_to_sheets.sh "$T/mov" "$T/mov_sheets" 10 4 3 480`. Delete frame PNGs after making sheets.

### 1.5 Draw-call confirmation for LOW gate (authoritative number)
```bash
timeout 600 "$G" --path . --rendering-method mobile --resolution 2340x1080 -- --adult --quality=low --shot=gate --hour=15 --weather=clear --out="$T/gate_low_check.png" 2>&1 | grep -aE "^\[perf\]|^\[perf-shadow\]"
```
Run 3 times; report min/max. Add `--drawcensus` when you need to know who owns the draws.

## 2. Rating rubric (score each axis 1–10, scene score = mean; HIGH and LOW scored separately)

| Axis | What to look at | 10 means |
|---|---|---|
| Composition | foreground / mid / far layering, frame edges filled, road width, eye-line | Like the reference: framed edges (foliage/fence/banner), subject on a third, depth in three planes, nothing cut at the frame edge |
| Light | sun warmth vs shadow coolness, exposure, contrast, haze, no clipped sky | Warm key, blue-violet (never grey/black) shadows, sky not blown, far haze visible but the gatehouse still readable |
| Material | roughness/normal read, no plastic glints, no flat untextured faces, no pink/white | Stone/wood/cloth distinguishable at phone size, no crystal thatch, no tiling visible |
| Silhouette | hero and NPC readability, occlusion by props, see-through working | Hero ~40% screen height, outline separates from background, nothing fills the lens |
| HUD | text amount, debug leaks, pill placement, calm fade, dialogue hides chrome | Only the 6 default controls + 1 context pill, no world text except the one name, fade to 22% when calm, chrome hidden in dialogue |
| Motion | (from sheets) camera eases, no pop, lock-on holds both, hitch-free | No bright single tile in `motion.png`, ease in ≤ 0.4 s, no jitter in static objects |
| Pacing | first-minute only | Launch → control ≤ 60 s with one skip tap; no black holds > 1 s; no screen the player cannot dismiss |

Per-scene "10":
- **title_menu**: RISING ASHES dominant, studio credit small, painted backdrop fills 2340 width without stretching, menu column readable.
- **creator**: lit preview reads like a portrait (warm key, cool rim, not flat grey), tabs legible, no clipping of the half-body frame.
- **first_exterior (08:00)**: morning light (longer shadows, warm low sun), Ashford reads as a lived-in village, HUD calm.
- **road**: horizon haze, road reads as a road (ruts/verges), Kingsreach silhouette visible far, hero not hidden by grass.
- **gate (15:00)**: closest to the reference. Red/gold banners, stall rhythm, crowd at several depths, gatehouse dominant, LOW ≤ 135 draws.
- **dialogue**: two-shot, speaker right of centre, faces in top 60%, sheet translucent, world still moving (compare two frames).
- **wolf / wolf_lock**: both fighters in frame, threat plate readable, camera closer/lower than exploration, no pull-out.
- **dusk (18.6)**: orange key, violet shadows, lanterns starting, sky gradient not banded.
- **night (22.0)**: readable silhouettes, warm lamp pools, blue ambient — but it must still look like night (not a dim day).
- **map**: a cartographic object: parchment, roads, fog that fades (no "UNEXPLORED" boxes), labels legible at 2340x1080.

Score the existing baseline images too so the trend is visible: `docs/qa/aaa_feel/p14_gate_high.png` / `p14_gate_low.png` (last scored ~8/10), `p9_7_dialogue.png` (~8.5), `p9_6_benchmark_18.png`, `p9_6_benchmark_22.png` (pass 9, ~8.5), `p10_gate_vs_target.png` (target/HIGH/LOW side by side).

## 3. Ordered fix list

Rules for every fix: read the current value first (docs are stale in places: `ashes-baked-quality` says sun shadows are off on LOW; `Quality.TIERS[LOW]["shadow"]` is actually 1). Change numbers in small steps (≤ 25% per iteration), re-capture only the affected scenes with `--only=`, read the image, keep or revert. One commit per fix.

**F1 — Harness + baseline (no game change).** Files: new `kingdom/tools_qa/aaa_audit/audit_views.gd|.tscn`. Accept: all 10 scenes × 2 tiers exist as JPG, log has no `SCRIPT ERROR`. LOW guard: n/a.

**F2 — Night is a dim day (highest-value grade fix).** File `kingdom/scripts/style_g.gd::apply_daylight`. Current `game_look` floors: `sun.light_energy = maxf(.., 0.85)` and `env.ambient_light_energy = maxf(.., 0.85)` apply at ALL hours, which flattens dusk and night (palette asks sun 0.40, ambient 0.34 at 22:00). Change to a night-aware floor: `sun >= 0.55`, `ambient >= 0.5`, and keep the moon-blue `ambient_color` unmixed at night (the `c4b4a4` warm lerp is already scaled by sun energy, leave it). Expected: night darker with blue cast, lamp pools stand out, characters still readable. Accept: `night` capture — sky band darker than any lit wall, NPC silhouettes still visible, nothing pure black; `dusk` keeps the orange key. LOW guard: value-only, zero cost.

**F3 — Dusk / sky keyframes.** File `style_g.gd::DAY_KEYS` rows 17.0, 18.0, 18.8, 19.8 (columns: hour, sun col, sun E, ambient col, ambient E, fog col, sky top, horizon, ground, cloud, cloud shade, fill E, bg E, sun glow, elevation). Only if the dusk capture shows a banded/over-orange horizon: lower `sun_glow` at 18.0 (1.0 → 0.8) and desaturate `fog` at 18.8. Do NOT touch the 15.0 row (Style G anchor) or 12.0. Accept: `dusk` capture gradient smooth, gate still readable. LOW guard: none needed.

**F4 — Day grade (HIGH) and depth haze.** File `style_g.gd::_game_environment`: `tonemap_exposure 0.86`, `adjustment_saturation 1.08`, `adjustment_contrast 1.32`, LUT `231d28/8e8a88/fff2dc`, `fog_density 0.0021`, `fog_aerial_perspective 0.45`. If `gate_high` reads flat vs the reference: raise `fog_aerial_perspective` to 0.55 first (depth without wash), then contrast 1.32 → 1.38. Note `Quality._apply_env` multiplies fog by `fog_mul` (LOW 1.5, MEDIUM 1.2) and forces ≥ 0.0009 without volumetric fog: LOW is already hazier; check `gate_low` does not wash out (pass 12 reverted 0.0027 for this reason). Accept: `gate_high` and `road_high` show three depth planes; `gate_low` gatehouse edges still crisp. LOW guard: `adjustment_enabled` is already `tier != "low"`; never enable it on LOW (Compatibility renderer has no adjustment pass).

**F5 — Post-process on HIGH only.** `Quality.TIERS[HIGH]`: `glow true`, `ssao true`. On the Mobile renderer `_apply_env` ANDs SSAO/SSIL/SDFGI/vol-fog with `renderer()=="forward_plus"`, so on phones HIGH post = glow + adjustment + LUT + fog, nothing else. Do not try to enable SSAO for mobile. Tunables: `_game_environment` glow `intensity 0.28 / bloom 0.02 / hdr_threshold 1.25` (SOFTLIGHT). Only adjust if lanterns at night look dead (raise intensity to 0.34) or the day frame glows (lower). Accept: no haloing on white plaster in `gate_high`; lantern glow visible in `night_high`. LOW guard: `glow false` on LOW stays.

**F6 — Dialogue framing.** Files `kingdom/scripts/actors/chase_camera.gd` (`TALK_FOV -4`, `TALK_DIST -0.5`, `TALK_LIFT -0.2`, `TALK_TILT 0.13`, `TALK_SHIFT 0.9`, `TALK_TIME 0.4`), `kingdom/scripts/ui/dialogue_sheet.gd` (`SHEET_TOP 0.66`), `player.gd::set_talk_framing`. Adjust only if the `dialogue` capture shows faces below the top 60% or the speaker behind the hero. Accept: both faces in the top 60%, sheet covers ≤ 34%, chrome hidden (`hud._set_chrome_visible(false)` path), sheet from Movie Maker eases in ≤ 0.4 s with no pop. Tests: `kingdom/tests/test_chase_camera.gd`, `test_talk_in_world.gd` must stay green (they assert `CHOICE_H ≥ 48` and talk constants). LOW guard: none (camera maths). NOTE: `player.gd` is CRLF — preserve it.

**F7 — Combat / lock-on framing.** `chase_camera.gd`: `COMBAT_DIST -0.6`, `COMBAT_LIFT -0.15`, `COMBAT_FOV -2`, `lock_frame(gap)` = `{dist: clamp(g*0.12 + max(g-5,0)*0.3, 0, 3.4), shift: clamp(g*0.28, 0, 2.2)}`. If `wolf_lock` shows the wolf clipped or the hero covering it, raise the shift slope (0.28 → 0.32) before touching dist. Accept: `wolf_lock` both bodies fully in frame, threat plate on screen, camera lower than exploration (compare `wolf` vs `wolf_lock` pivot). Tests: `test_chase_camera.gd` has `lock_frame` cases — update expected values in the same commit if you change the formula. LOW guard: none.

**F8 — HUD polish.** `kingdom/scripts/ui/hud.gd`: `CALM_AFTER 7.0`, `CALM_ALPHA 0.22`, `MINIMAP_SIZE 100`, `DOCK_SIZE 52`, `LOCK_BUTTON_AT (450, 296)`; `nameplates.gd` (12 m, 3 shown), `alert_glyphs.gd` 14 m, `villager.gd _say` barks ≤ 2 (do not edit villager.gd — faces agent; report instead). Audit from captures: any world text beyond one name pill, any label stacking ("Market Trader"/"Steward" is a known open item), pill overlapping buttons. Fix only placement/alpha/size constants. Accept: `gate_high` with HUD shows ≤ 7 controls + ≤ 1 pill, no debug line (`--debug-hud` off), and `first_exterior` after 7 s calm shows chrome at 22%. Tests: `test_hud_modes.gd`, `test_hud_lane_hint.gd`. LOW guard: none.

**F9 — Clutter density by composition.** `kingdom/scripts/world/street_benchmark.gd` (market rhythm every ~7 m, picket fence + bushes on the outer verge, `_low()` branch at line 207: LOW adds NO props, by design since pass 14). Only HIGH/MEDIUM may change: move/add kinds in the `lists` dictionary so frame edges of `gate_high` are closed (left/right thirds) and the road centre stays clear. Do not add new kinds to the LOW branch. Accept: `gate_high` edges framed; `gate_low` draw count via §1.5 ≤ 135 on all 3 runs (unchanged); HIGH draws reported, must not rise > 10% (noise band) above 526. Tests: `test_market_dressing.gd`.

**F10 — Menu and creator presentation.** `kingdom/scripts/ui/frontend/main_menu.gd` (title 96 px, credit 18 px, line 38–48) — only spacing/alpha. `kingdom/scripts/ui/portrait.gd::setup` lines 51–76 (ambient `0.5,0.5,0.62 @0.95`, key `1.0,0.86,0.66 @1.7` at (-32,-34), rim `0.62,0.72,1.0 @0.9` at (-18,155), fov 26): for the "firelit room" read lower ambient to ~0.7, warm the key slightly, keep the rim. This changes the HUD portrait and dialogue bust too (same class): re-capture `dialogue`. Do NOT touch `character_creation.gd::build_model` or head/hair lists (faces agent). Accept: `boot_08b_character_creation` preview has visible key/rim separation, no grey flat face; `dialogue` bust still readable. LOW guard: Portrait is a tiny SubViewport, cost unchanged.

**F11 — First-minute pacing.** Measure from the §1.2 movie: intro (`studio_intro.gd` 5 s, `SKIP_AFTER 1.0`), splash, first-run 3 steps, menu, new game, creator, loading, veil, birth cutscene. Only tune constants (`SKIP_AFTER`, fade times in `boot.gd::_fade`, `boot.gd::transition`), never cut screens. Accept: launch → control ≤ 60 s with skip taps; no black hold > 1 s in `motion.png` (a black tile mid-sequence = hold). Tests: boot flow log has `errors=0` (boot_flow prints its error count) and `kingdom/tools_qa/boot_loop/boot_loop.gd` still passes (`-s res://tools_qa/boot_loop/boot_loop.gd` headless is fine for that one, it does not render).

**F12 — Parchment map.** `kingdom/scripts/ui/world_map.gd` (`FOG_ALPHA 0.8`, `FOG_COLOR e3d2a6`, paper/ink constants) and `map_parchment_layer.gd` (`FOG_PAPER`, `FOG_INK`, fog strength). Only if the capture shows hard fog edges or an "Unexplored" box look. Accept: map capture fog fades softly; labels legible at 2340 wide. Tests: `test_world_map.gd`. LOW guard: the parchment texture is one 2048² ETC2 page; do not raise `TEX_SIZE`/`FOG_RES`.

Out of scope (do not do): new 3D assets, VAO/atlas rebakes, `Quality.TIERS` budgets (`npc_full`, `shadow*`, `range`, `scatter`), terrain/grass shaders, `city_planner.gd` (plans change → all shots move), anything in `kingdom/scripts/population/` or faces.

## 4. Naming

All evidence goes to `docs/qa/aaa_feel/audit2_<scene>_<tier>_<before|after>.jpg` with scene ∈ {`title_menu`, `creator`, `first_exterior`, `road`, `gate`, `gate_nohud`, `dialogue`, `wolf`, `wolf_lock`, `dusk`, `night`, `map`}, tier ∈ {`high`, `low`}. Copy/rename from `$T/before` and `$T/after` (`cp` from `$T` only; never write directly into docs from Godot). Sheets: `docs/qa/aaa_feel/audit2_<scene>_<tier>_<before|after>_sheet.png` (one per motion check, max 3 total). Delete all frame PNGs in `$T` after sheets are made; keep `$T` under 500 MB.

## 5. Tests, merge, push, cleanup

```bash
export MSYS_NO_PATHCONV=1; cd /c/Users/Jonna/Documents/PA_wt_audit
bash tools/qa/lint.sh <each touched .gd path>            # gdlint at C:/Users/Jonna/Tools/gdtoolkit (present)
GODOT="$G" bash tools/qa/run_tests.sh 20                  # headless is correct for tests; exit 0 or 101 per batch is OK; any failure blocks the commit
```
Run the full suite once at the end; per fix run the named suites via `--add res://tests/test_chase_camera.gd` etc. with `GdUnitCmdTool.gd` (see `run_tests.sh` for the exact invocation).

Commit per fix. Before each commit: `git diff --name-only | grep '\.import$'` → `git checkout --` those; `git status` must list only your files (`kingdom/tools_qa/aaa_audit/*`, the fix file, `docs/qa/aaa_feel/audit2_*`, `docs/art/AAA_PRESENTATION_REVIEW.md`, `docs/STATUS_LOCAL.md`). Never `git add -A`. Message: what the player sees, files, numbers before → after, "unverified on phone". End every commit message with exactly:
```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
```
Then: `git fetch origin && git merge --no-edit origin/claude/focused-curie-m09hbd` (resolve only your files; if the merge touches `.uid`/`.import` untracked files, delete them and retry), re-run the touched suites, `git push origin HEAD:claude/aaa-audit-2`, then `git push origin HEAD:claude/focused-curie-m09hbd`. Do not push to `main`.

Also add one row to `docs/STATUS_LOCAL.md` "## Done (recent)" table (format `| 10-12 | **AAA audit 2** (...) | files | (this commit) |`) and any leftover gaps as bullets under "## Backlog (from the aaa-review loop)".

Cleanup: delete `$T` frame PNGs and `$T/mov*`; leave the worktree and `kingdom/.godot` in place; report `du -sh "$T"` and free disk on C:.

## 6. Scorecard to append to `docs/art/AAA_PRESENTATION_REVIEW.md`

```
## Audit 2 scorecard (2026-10-12, PC Mobile renderer 2340x1080, target 00_MAIN)

| Scene | Tier | Comp | Light | Mat | Silh | HUD | Motion | Pacing | Mean before | Mean after | Draws before/after | Fixes | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gate | high | 7/8 | 6/8 | 7/7 | 8/8 | 8/9 | - | - | 7.2 | 8.0 | 526/531 | F4 F9 | audit2_gate_high_before.jpg, _after.jpg |
(one row per scene x tier; "-" where an axis does not apply; cells are before/after)

Open after audit 2: <bullets, each a concrete next task>
Not changed on purpose: <bullets with the reason>
```

## 7. Risks a Sonnet agent must not guess at (ask or stop instead)

1. **SSAO/SSIL/volumetric are Forward+ only**; on phones HIGH has none. Never "fix" a flat look by enabling them.
2. **The draw budget is only valid at full load**: `settlements.finish_prop_jobs()` after 4× `update_now()` then 120 frames (pass 14 found earlier 133s were partial loads). Numbers under 10% apart are streaming noise; run 3 times.
3. **Weather and clock drift**: force `weather.auto=false` + `set_weather("clear", 0.1)` and pin `WorldSim.time_of_day` every frame, or two captures will never match.
4. **User args switch the boot path**: any `-- --x` skips splash/menu/creator. Title/creator/pacing must be captured with `boot_flow.gd` and env vars only.
5. **Settlement indices**: Ashford is `WorldGen.settlements[0]`, Kingsreach `[1]` (`world_gen.gd NAMES`); yaw to face direction `d` is `atan2(-d.x, -d.y)`.
6. **`city_planner.gd` or `street_benchmark.gd` lot logic changes move every shot** — compare before/after only on the same plan.
7. **Do not edit `DAY_KEYS` row 15.0**, `SUN_COLOR`, `SUN_ENERGY`, `AMBIENT_HEX`, `FOG_HEX`: they are the Style G anchor every baked `.tres` under `resources/style_g/` was derived from.
8. **Test suite batches that exit 101 are passes** (orphan warnings); an engine `signal 11` at the end of a batch with 0 failures is also known-harmless; a `FAILED` line is not.
9. **Other agents' Godot processes** share the GPU and the user settings file; a capture while an APK export runs is invalid. Check `tasklist | grep -i godot` first; kill only your own PID.
10. **Faces** (list in §0) belong to another agent — a merge conflict there means stop and report, not resolve.
11. **`feel_views.gd` and the p-series images use the Ashford benchmark street for dusk/night and the Kingsreach gate for `gate`**; keep that mapping so scores stay comparable with p2–p14.
12. **No `--headless` for any render, no `/tmp`, no `rm -rf` outside `$T`.** Print the absolute path before any delete.
13. If a capture shows a pure white/pink material, a T-pose, or a missing building, it is an asset/import problem for another owner: record it in the scorecard "Open" list, do not chase it.

### Critical files
- `kingdom/scripts/style_g.gd` (environment, `DAY_KEYS`, `apply_daylight` night floors, `_game_environment` grade)
- `kingdom/tools_qa/aaa_camera/feel_views.gd` (template for the new harness)
- `kingdom/scripts/core/main.gd` (`_screenshot` `gate`/`frontier` cases, `_teleport`, `[perf]` draw print, `--qa=`/`--shot=` flags)
- `kingdom/scripts/actors/chase_camera.gd` (TALK_*, COMBAT_*, `lock_frame`) with `kingdom/tests/test_chase_camera.gd`
- `kingdom/scripts/core/quality.gd` (per-tier env knobs, `_apply_env` renderer gating, `--quality=` parsing)
