# Rising Ashes PC Renderer Upgrade, Phase 1: Execution Brief (Opus plan, Sonnet execution, 2026-10-20)

All findings come from read-only exploration of `C:\Users\Jonna\Documents\PA_wt_audit` at commit `ce8972f2`.

Repo root: `C:\Users\Jonna\Documents\PA_wt_audit`. Godot project: `kingdom\`. Godot executable: `C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe`. In bash, always `export MSYS_NO_PATHCONV=1` first. Quote Windows paths when creating worktrees (`"C:/Users/Jonna/Documents/PA_wt_x"`), or MSYS mangles them into `C:\c\...`.

Every commit ends with:
```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

General rules: never `rm -rf` outside your own worktree/temp dir; kill only Godot PIDs you started (never `taskkill /IM`); never `--headless` for renders; never commit `kingdom/.godot/` or stray `.import`/`.uid` churn (except WP2's deliberate `.import` commit); CRLF files stay CRLF (`player.gd`, `hero_face_driver.gd`); check disk (`df -h /c`) first and stop if < 15 GB.

---

## 0. Corrections to the original assumptions

1. **The PC build already runs Forward+.** `kingdom/project.godot` has `config/features=PackedStringArray("4.6", "Forward Plus")` and no `rendering_method` key, so desktop uses `forward_plus`; Android/iOS use `rendering_method.mobile="mobile"`. The Audit 2 captures forced the Mobile renderer with `--rendering-method mobile`. Work = make it explicit, add a Windows export preset, add PC tiers.
2. **There is no Windows export preset.** `kingdom/export_presets.cfg` has only `preset.0` Android and `preset.1` iOS.
3. **Texture caps are not in `.import` files.** All 4250 texture imports have `process/size_limit=0`. Phone caps are applied at export time by `kingdom/addons/mobile_texture_limit/mobile_texture_export.gd` (MAX_PX 512, SMALL_PX 256, HERO_PX 1024, ETC2/ASTC), active only for `android`/`ios` feature tags. Permanent caps are baked into GLB sources by `tools/meshy/optimize_glb.py` (`BUDGETS` lod0 512–2048 px; 514 `*_lod0.glb`). Raw Meshy sources are **not in the repo**.
4. **Desktop has no mouse-look and no gamepad stick movement.** Camera look works only because `pointing/emulate_touch_from_mouse=true` turns mouse drags into `InputEventScreenDrag` on the HUD look area (`hud.gd:192-198`). `move_*` actions are keys only (`autoload/game.gd:79-80`). Attack is `KEY_J`; no mouse button.
5. **Water is a transparent shader** (`shaders/water.gdshader:338` writes `ALPHA`). Environment SSR does not reflect on transparent surfaces; water reflections need shader-side work (WP3).
6. **The world renders in a SubViewport** (`main.gd:65-80`). 3D scaling and AA go on that SubViewport. `settings_store.gd:141-145` overwrites the SubViewport's MSAA/FXAA after Quality applies its own (conflict).

---

## 1. Ground truth

| Item | Path | Current value / behaviour |
|---|---|---|
| Renderer | `kingdom/project.godot` `[application]` | `"Forward Plus"` feature, no explicit `rendering_method` |
| AA | `project.godot [rendering]` | `msaa_3d=2`, `screen_space_aa=1`, `soft_shadow_filter_quality=3`, `import_etc2_astc=true` (no explicit `import_s3tc_bptc`) |
| Touch emulation | `project.godot [input_devices]` | `pointing/emulate_touch_from_mouse=true` |
| Physics | `project.godot [physics]` | Jolt, `physics_interpolation=true`; Hz from `Quality.value("physics_hz")` (LOW 30, others 60) |
| Window | `project.godot [display]` | 1280x720, `canvas_items`, `expand`, `handheld/orientation=4` |
| Export presets | `kingdom/export_presets.cfg` | Android, iOS only. `exclude_filter` read by `tools/qa/texture_vram.py` (first match) |
| Tiers | `kingdom/scripts/core/quality.gd:54-83` `TIERS` | 4 phone rows LOW/MEDIUM/HIGH/ULTRA. Enum `{LOW, MEDIUM, HIGH, ULTRA}`, `NAMES`, `GROUPS`, `DETECT_VERSION := 4` |
| Desktop detection | `quality.gd:300-309` | discrete or "rtx" → ULTRA; integrated → MEDIUM. `_adapt_floor()` = HIGH on discrete desktop |
| Env application | `quality.gd:605-621` `_apply_env` | SSAO/SSIL/SDFGI/vol fog/SSR only if `forward_plus`; fog density from meta `q_fog` × `fog_mul` |
| Viewport application | `quality.gd:574-602` | `max_3d_height`, FSR1 (`"fsr"`), `mesh_lod_threshold`, aniso, mip bias, MSAA, FXAA, omni atlas 2048 |
| Mobile-only geometry culls | `quality.gd:660-685` | `tier == LOW` / `tier <= MEDIUM`: town_far, impostor 150/220 m, small-prop caps 28/60/90 m, loose mesh 80/160 m |
| Thermal guard | `quality.gd:446-488` | already mobile-only (`_is_mobile()`); leave alone |
| Perf log | `quality.gd:376,424-443` | debug build + `--perflog` prints `PERF fps p50 p95 p99 draws prims vram tex ...` every 10 s |
| Style G env | `kingdom/scripts/style_g.gd:88-141` | ambient COLOR `aab8ee` @0.48, Filmic, LUT; game: exposure 0.86, LUT `231d28/8e8a88/fff2dc`, vol fog albedo `f2e2c0` density 0.0015 length 64 |
| Day cycle | `style_g.gd:165-178` `DAY_KEYS` (15 cols), `apply_daylight` 232-272 | sun, fill energy, ambient (day warm-lerp, night floor 0.5), fog colour, bg energy, sky shader |
| Fake GI | `style_g.gd:308-317` `make_fill` | `BounceG` shadowless warm directional, 0.3 (overwritten per hour by `fill_energy`) |
| Env build | `kingdom/scripts/core/main.gd:567-586` | forces `ssil/sdfgi/volumetric_fog=false`; `sun.light_volumetric_fog_energy=1.4` |
| Weather | `kingdom/scripts/world/weather.gd:424-430,485` | `_mul` on `fog_density`, `volumetric_fog_density`, `ambient_light_energy` from captured base |
| Baked VAO | `kingdom/scripts/world/baked_vao.gd`; `shaders/style_lab/lab_polished(.gdshader,_lite)` line 111 | `c *= ao * mix(1.0, COLOR.a, vao_strength)` |
| Static merge | `kingdom/scripts/world/static_merge.gd:36` | runs only when `StyleG.current_tier() == "low"` |
| Settlement LOW/MED gates | `kingdom/scripts/world/settlement_builder.gd:625-635` (`_is_low`/`_is_medium`), 799, 1838 | larger cells, range caps on LOW |
| Crowd anim LOD | `kingdom/scripts/living_world/crowd_anim_lod.gd:31-36` `BUDGETS[tier]` | ULTRA: near_max 12, near 18, mid 50, far 180, shadow 24 |
| Population | `kingdom/scripts/population/population_lod.gd` | `MAX_FULL 24`, `NEAR_HARD_CAP 12`, `MAX_SPRITES 140`; VAT only if `Quality.tier >= 1` (line 117) |
| Streaming | `kingdom/scripts/core/cell_streamer.gd:31-41` | `CELL 64`; per-tier arrays; population full 45 / load 220 |
| Grass | `kingdom/scripts/world/grass_field.gd:13` | `CLUMPS_PER_CHUNK 3300`; thinned by `scatter` |
| Other tier gates | `critter.gd:143,329`; `distance_cull.gd:32`; `villager.gd:430,1133`; `frontier_presence.gd:62,196`; `lakeside.gd:124`; `region_dressing.gd:538,586`; `ambient_life.gd:155`; `water_streamer.gd:208-223`; `low_budget.gd` (disabled) | |
| Input map | `kingdom/autoload/game.gd:78-99` `KEYS`/`PADS`, `_setup_input` 101 | keyboard + few mouse/joy buttons; no axes |
| Look | `kingdom/scripts/actors/player.gd:606-617` `add_look(relative)` | yaw −0.006/px, pitch −0.004/px; `App.look_scale` (`app_services.gd:15,62`) |
| Touch HUD | `kingdom/scripts/ui/hud.gd:179-215` | look area + `VirtualJoystick` + buttons always built; `_touch = HudArt.touch_mode()` gates only technique ring (264); `controls.visible` setter at 922 |
| Touch mode | `kingdom/scripts/ui/hud_art.gd:306` | `--touch` or a mobile feature |
| Settings AA | `kingdom/scripts/ui/frontend/settings_store.gd:141-145` | writes MSAA/FXAA to every SubViewport, overriding Quality |
| Audit harness | `kingdom/tools_qa/aaa_audit/audit_views.gd` | scenes `first_exterior, road, gate, dialogue, wolf, dusk, night`; output `"%s_%s.jpg" % [tag, name]` |
| Audit 2 scorecard | `docs/art/AAA_PRESENTATION_REVIEW.md:70-95` | gate high 7.6, dusk 7.4, night 7.4 (Mobile renderer) |
| Tests coupled to TIERS | `kingdom/tests/test_pooling_streaming.gd:264,317`, `test_market_dressing.gd:129` | read `TIERS[HIGH]["view_radius"]`, iterate LOW..ULTRA |

---

## 2. Architecture decision (contract all WPs depend on)

**Profiles, not new enum values.** `Quality.tier` stays ordinal 0..3. Add `Quality.profile` (`"mobile"` or `"pc"`). `value()` reads `TIERS` (mobile, **values unchanged**) or new `PC_TIERS`. In the PC profile, tier 0..3 = PC_LOW / PC_MED / PC_HIGH / PC_ULTRA.

Profile choice: `"mobile"` if `_is_mobile()` or cmdline `--profile=mobile`; `"mobile"` if `--rendering-method mobile` or `gl_compatibility` is active and no explicit `--profile=pc`; otherwise `"pc"`.

Phone hacks become capability keys present in **both** tables (mobile rows reproduce today's behaviour exactly):

| Key | Mobile LOW / MED / HIGH / ULTRA | PC (all four) | Meaning |
|---|---|---|---|
| `draw_merge` | true / false / false / false | false | StaticMerge + larger settlement cells |
| `prop_cull` | 1 / 2 / 0 / 0 | 0 | quality.gd small-prop + loose-mesh caps (1 = LOW numbers, 2 = MED numbers, 0 = off) |
| `impostor_cap` | 150 / 220 / 0 / 0 | 0 | tree impostor range end (0 = author value) |
| `vat_crowd` | false / true / true / true | true | `population_lod.gd:117` |
| `lite_world` | true / false / false / false | false | replaces `Quality.tier <= 0` decorative gates |
| `lod1_dressing` | true / true / false / false | false | `region_dressing.gd:538` (`tier <= 1`) |
| `stream_mul` | 1 / 1 / 1 / 1 | PC rows | multiplier on CellStreamer population/dressing/ambient/settlement full/load |
| `grass_mul` | 1 / 1 / 1 / 1 | PC rows | multiplier on `CLUMPS_PER_CHUNK` |
| `crowd` | absent | dict, PC rows | CrowdAnimLOD budget row override |

New accessors in quality.gd: `var profile := "mobile"`, `func is_pc() -> bool`, `func has_value(key: String) -> bool`. `value(key)` uses `PC_TIERS` when `profile == "pc"`.

New global shader uniform (WP1 owns, WP3 consumes): `ashes_gi_on` (float, default 0.0) in `project.godot [shader_globals]`. Quality sets 1.0 when SDFGI is effectively on.

---

## 3. PC tier rows (WP1 writes verbatim into `PC_TIERS`)

Reasoning: Style G is flat-albedo storybook, so shadows, GI, volumetric fog and density read more than texture detail or native resolution. PC_HIGH = FSR2 at 0.77 → ~1971x1108 internal at 1440p, ~12–14 ms on the 4070 Laptop with SDFGI. MSAA off with FSR2. VRAM PC_HIGH ≈ 4 GB (shadow atlas 64 MB, omni 64 MB, SDFGI ~350 MB, vfog ~25 MB, FSR2 ~60 MB, textures ≤ 1.5 GB after WP2, meshes ~1.5 GB).

```gdscript
const PC_TIERS := [
	{   # PC_LOW: integrated / GTX 16xx class
		"max_3d_height": 0, "scale": 0.75, "scaling": "fsr", "taa": false, "fps": 0, "physics_hz": 60,
		"shadow": 2, "shadow_size": 2048, "shadow_dist": 90.0, "soft_shadow": 1, "omni_shadows": false, "shadow_min": 1.5,
		"ssao": false, "ssao_half": true, "ssil": false, "sdfgi": false, "sdfgi_cascades": 4, "sdfgi_cell": 0.3, "sdfgi_rays": 1, "sdfgi_converge": 1, "gi_half": true,
		"glow": true, "vol_fog": false, "vfog_size": 64, "vfog_depth": 64, "ssr": false, "ssr_steps": 0, "water_ssr": 0,
		"lod_threshold": 1.5, "range": 1.0, "scatter": 0.8, "particles": 0.7, "aniso": 2, "tex_bias": 0.0, "fog_mul": 1.0,
		"msaa": 0, "fxaa": true, "npc_full": 16, "rig_budget": 6, "npc_sprites": 60, "view_radius": 4, "light_fade": 80.0, "town_far": 0.0,
		"draw_merge": false, "prop_cull": 0, "impostor_cap": 0, "vat_crowd": true, "lite_world": false, "lod1_dressing": false,
		"stream_mul": 1.0, "grass_mul": 1.0,
		"crowd": {"near_max": 8, "near_dist": 14.0, "mid_dist": 40.0, "far_dist": 160.0, "shadow_dist": 18.0, "steps": [2, 3, 4]},
	},
	{   # PC_MED: RTX 3050/4050 laptop, GTX 1070-1080
		"max_3d_height": 0, "scale": 0.67, "scaling": "fsr2", "taa": false, "fps": 0, "physics_hz": 60,
		"shadow": 4, "shadow_size": 4096, "shadow_dist": 160.0, "soft_shadow": 2, "omni_shadows": true, "shadow_min": 1.0,
		"ssao": true, "ssao_half": true, "ssil": false, "sdfgi": false, "sdfgi_cascades": 4, "sdfgi_cell": 0.3, "sdfgi_rays": 1, "sdfgi_converge": 1, "gi_half": true,
		"glow": true, "vol_fog": true, "vfog_size": 96, "vfog_depth": 64, "ssr": false, "ssr_steps": 0, "water_ssr": 16,
		"lod_threshold": 1.0, "range": 1.25, "scatter": 1.0, "particles": 1.0, "aniso": 3, "tex_bias": 0.0, "fog_mul": 1.0,
		"msaa": 0, "fxaa": false, "npc_full": 20, "rig_budget": 8, "npc_sprites": 90, "view_radius": 5, "light_fade": 120.0, "town_far": 0.0,
		"draw_merge": false, "prop_cull": 0, "impostor_cap": 0, "vat_crowd": true, "lite_world": false, "lod1_dressing": false,
		"stream_mul": 1.15, "grass_mul": 1.2,
		"crowd": {"near_max": 10, "near_dist": 16.0, "mid_dist": 48.0, "far_dist": 190.0, "shadow_dist": 22.0, "steps": [1, 2, 3]},
	},
	{   # PC_HIGH: RTX 4070 Laptop target, 60 fps @ 2560x1440
		"max_3d_height": 0, "scale": 0.77, "scaling": "fsr2", "taa": false, "fps": 0, "physics_hz": 60,
		"shadow": 4, "shadow_size": 4096, "shadow_dist": 220.0, "soft_shadow": 3, "omni_shadows": true, "shadow_min": 0.5,
		"ssao": true, "ssao_half": false, "ssil": false, "sdfgi": true, "sdfgi_cascades": 4, "sdfgi_cell": 0.3, "sdfgi_rays": 2, "sdfgi_converge": 1, "gi_half": true,
		"glow": true, "vol_fog": true, "vfog_size": 128, "vfog_depth": 96, "ssr": true, "ssr_steps": 48, "water_ssr": 32,
		"lod_threshold": 1.0, "range": 1.5, "scatter": 1.0, "particles": 1.0, "aniso": 4, "tex_bias": 0.0, "fog_mul": 1.0,
		"msaa": 0, "fxaa": false, "npc_full": 28, "rig_budget": 12, "npc_sprites": 140, "view_radius": 6, "light_fade": 0.0, "town_far": 0.0,
		"draw_merge": false, "prop_cull": 0, "impostor_cap": 0, "vat_crowd": true, "lite_world": false, "lod1_dressing": false,
		"stream_mul": 1.3, "grass_mul": 1.5,
		"crowd": {"near_max": 14, "near_dist": 20.0, "mid_dist": 60.0, "far_dist": 220.0, "shadow_dist": 28.0, "steps": [1, 2, 3]},
	},
	{   # PC_ULTRA: RTX 4080+ desktop
		"max_3d_height": 0, "scale": 1.0, "scaling": "fsr2", "taa": false, "fps": 0, "physics_hz": 60,
		"shadow": 4, "shadow_size": 8192, "shadow_dist": 300.0, "soft_shadow": 4, "omni_shadows": true, "shadow_min": 0.0,
		"ssao": true, "ssao_half": false, "ssil": true, "sdfgi": true, "sdfgi_cascades": 6, "sdfgi_cell": 0.25, "sdfgi_rays": 3, "sdfgi_converge": 2, "gi_half": false,
		"glow": true, "vol_fog": true, "vfog_size": 160, "vfog_depth": 128, "ssr": true, "ssr_steps": 64, "water_ssr": 48,
		"lod_threshold": 0.75, "range": 2.0, "scatter": 1.0, "particles": 1.0, "aniso": 4, "tex_bias": 0.0, "fog_mul": 1.0,
		"msaa": 0, "fxaa": false, "npc_full": 36, "rig_budget": 16, "npc_sprites": 200, "view_radius": 7, "light_fade": 0.0, "town_far": 0.0,
		"draw_merge": false, "prop_cull": 0, "impostor_cap": 0, "vat_crowd": true, "lite_world": false, "lod1_dressing": false,
		"stream_mul": 1.5, "grass_mul": 2.0,
		"crowd": {"near_max": 18, "near_dist": 24.0, "mid_dist": 70.0, "far_dist": 260.0, "shadow_dist": 34.0, "steps": [1, 1, 2]},
	},
]
```

Mappings: `aniso` → `Viewport.ANISOTROPY_*` (0 off, 1=2x, 2=4x, 3=8x, 4=16x; current code passes the int, correct). `sdfgi_rays` → `RenderingServer.ENV_SDFGI_RAY_COUNT_*` (0=4, 1=8, 2=16, 3=32). `sdfgi_converge` → `ENV_SDFGI_CONVERGE_IN_*` (0=5, 1=10, 2=15 frames). `soft_shadow` 4 = `SHADOW_QUALITY_SOFT_ULTRA`.

Add the capability keys to the 4 mobile rows with the mobile values from §2; leave all other mobile values untouched. Add the new PC keys to `GROUPS`: `view` += `stream_mul, grass_mul, crowd, prop_cull, impostor_cap`; `effects` += `sdfgi_cascades, sdfgi_cell, sdfgi_rays, sdfgi_converge, gi_half, ssao_half, vfog_size, vfog_depth, ssr_steps, water_ssr`.

---

## WP0: QA harness (land first)

**Files (only):** `kingdom/tools_qa/aaa_audit/audit_views.gd`

1. `--pattern=` with `{tag}` and `{scene}` placeholders; default `"{tag}_{scene}"` keeps old names.
2. `--bench=SECONDS` (default 0): after each shot hold the view N s; at startup when bench > 0 set `DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)` and `Engine.max_fps = 0`; collect frame deltas, skip first 2 s; print `AUDITPERF <scene> tier=<Quality.tier_name()> profile=<Quality.get("profile") or "n/a"> renderer=<RenderingServer.get_current_rendering_method()> fps_avg=.. ft_p50=..ms ft_p95=..ms ft_p99=..ms vram_mb=<Performance RENDER_VIDEO_MEM_USED/1048576> tex_mb=<RENDER_TEXTURE_MEM_USED/1048576> draws=.. prims=.. gpu=<RenderingServer.get_video_adapter_name()>`.
3. Header doc comment with the Forward+ command (QA recipe).

Acceptance: base-commit run produces `pc1_gate_high_before.jpg` + an `AUDITPERF` line; with no new args, old file names are identical.

---

## WP1: Renderer and PC tiers

**Files (owned):** `kingdom/project.godot`, `kingdom/export_presets.cfg`, `kingdom/scripts/core/quality.gd`, `kingdom/scripts/ui/frontend/settings_store.gd`, `kingdom/scripts/ui/frontend/settings_screen.gd` (AA labels only), new `kingdom/tests/test_quality_pc.gd`.

1. **project.godot** `[rendering]` add (keep existing lines):
```
renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
textures/vram_compression/import_s3tc_bptc=true
textures/default_filters/anisotropic_filtering_level=4
anti_aliasing/quality/msaa_3d=0
anti_aliasing/quality/screen_space_aa=0
global_illumination/gi/use_half_resolution=true
environment/volumetric_fog/volume_size=128
environment/volumetric_fog/volume_depth=96
lights_and_shadows/directional_shadow/size=4096
```
Keep `import_etc2_astc=true`. `main.gd:78-79` hard-sets MSAA 2x + FXAA on the SubViewport, then Quality overrides; leave it. `[shader_globals]` add `ashes_gi_on={ "type": "float", "value": 0.0 }`. Do NOT change `emulate_touch_from_mouse` (WP5 does it at runtime).

2. **export_presets.cfg**: add `[preset.2]` + `[preset.2.options]` after preset.1: `name="Windows Desktop"`, `platform="Windows Desktop"`, `runnable=true`, `custom_features="pc_build"`, `export_filter="all_resources"`, `include_filter`/`exclude_filter` copied verbatim from preset.0, `export_path="../build/windows/RisingAshes.exe"`; options `binary_format/embed_pck=false`, `texture_format/s3tc_bptc=true`, `texture_format/etc2_astc=false`, `binary_format/architecture="x86_64"`, `application/console_wrapper_icon=""`, `debug/export_console_wrapper=1`. Leave preset.0/1 byte-identical.

3. **quality.gd**:
- `profile`, `PC_TIERS`, `is_pc()`, `has_value()`, `_table()`; `value()` returns `_table()[t][key]`.
- Profile resolution in `_ready()` before `_load()`'s tier is used: `--profile=` → `_is_mobile()` → renderer check (§2).
- `DETECT_VERSION := 5`. `detect_tier()` PC branch: ULTRA for names containing `"rtx 4080"`, `"rtx 4090"`, `"rtx 50"`, `"rx 79"`; HIGH for any other discrete or `"rtx"` (the 4070 Laptop → HIGH); integrated → LOW; Compatibility → `mini(t, MEDIUM)`.
- `_adapt_floor()` on PC → MEDIUM.
- `_apply_globals()` PC only: `RenderingServer.environment_set_sdfgi_ray_count(value("sdfgi_rays"))`, `environment_set_sdfgi_frames_to_converge(value("sdfgi_converge"))`, `gi_set_use_half_resolution(value("gi_half"))`, `environment_set_volumetric_fog_volume_size(value("vfog_size"), value("vfog_depth"))`, `environment_set_ssao_quality(ENV_SSAO_QUALITY_HIGH if not value("ssao_half") else ENV_SSAO_QUALITY_MEDIUM, value("ssao_half"), 0.5, 2, 50, 300)`; set global `ashes_gi_on` = `1.0 if (value("sdfgi") and renderer()=="forward_plus") else 0.0`; `ashes_ground_detail` = `0.0 if (not is_pc() and tier == LOW) else (0.5 if (not is_pc() and tier == MEDIUM) else 1.0)`.
- `_apply_viewport()` PC: scale = `value("scale") * render_scale` clamped 0.5..1.0; `"fsr2"` → `SCALING_3D_MODE_FSR2`, `"fsr"` → FSR, else bilinear; `use_taa = value("taa") and value("scaling") != "fsr2"`; FSR2 active → `msaa_3d = MSAA_DISABLED`, `screen_space_aa = DISABLED`; omni atlas 4096 when `omni_shadows`. Mobile path unchanged.
- `_apply_env()`: when `sdfgi` on → `sdfgi_cascades`, `sdfgi_min_cell_size`, `sdfgi_use_occlusion=false`, `sdfgi_read_sky_light=true`, `sdfgi_bounce_feedback=0.4`, `sdfgi_energy=0.75`, `sdfgi_y_scale=SDFGI_Y_SCALE_75_PERCENT`; `ssr_max_steps=value("ssr_steps")`, `ssr_fade_in=0.15`, `ssr_fade_out=2.0`, `ssr_depth_tolerance=0.3`. Don't touch tonemap/LUT/ambient/fog colours.
- `_apply_geometry()`: replace `tier == LOW`/`tier <= MEDIUM` at 660-685 with keys: `impostor_cap > 0` at 666 (use its value instead of 150/220); `prop_cull` 1/2 at 670-685. Mobile behaviour byte-identical.
- `set_aa_mode(aa: int)`: 0 tier default, 1 FXAA (forces `"fsr"`), 2 TAA (bilinear + use_taa), 3 FSR2; in memory only; calls `_apply_viewports()`.

4. **settings_store.gd 141-145**: if `Quality.is_pc()`, don't write msaa/ssaa; call `q.call("set_aa_mode", aa)`. Saved aa 2/3 (old MSAA meaning) → treat as Auto. Mobile branch unchanged.

5. **settings_screen.gd 162**: labels `["Auto", "FXAA", "TAA", "FSR 2"]` when `Quality.is_pc()`.

Tests `kingdom/tests/test_quality_pc.gd` (gdUnit4, style of `test_pooling_streaming.gd`): every PC row has all `TIERS[0]` keys + capability keys; every mobile row has capability keys; PC rows `draw_merge == false`, `prop_cull == 0`; `GROUPS` keys exist in both tables; snapshot of the 4 original mobile dicts unchanged.

Acceptance: `--profile=pc --quality=high` logs `Quality: High ...`, renderer `forward_plus`, `AUDITPERF` shows `profile=pc`; `--rendering-method mobile --quality=low` → profile `mobile`, gate draws within ±3 of 129-132; gdUnit green.

Must NOT touch: `style_g.gd`, `main.gd`, shaders, `game.gd`, `player.gd`, `hud*.gd`, `scripts/world|population|living_world`, `.import`, `tools/`.

---

## WP2: Textures

**Files:** `tools/qa/texture_vram.py`, `tools/meshy/optimize_glb.py`, `kingdom/addons/mobile_texture_limit/mobile_texture_export.gd` (comment + one guard), `kingdom/assets/**/*.import` (bulk), `docs/qa/PERFORMANCE.md` ("PC textures" section, also document `--rendering-method gl_compatibility` / `rendering_method.web` for a later Compatibility build).

1. `texture_vram.py --pc`: every texture `.import` under `kingdom/assets/` not export-excluded, except `SKIP_PREFIX` (UI icons lossless); `compress/mode=2`, `mipmaps/generate=true`, normal-map detection as today; `compress/high_quality=true` for the addon's `HERO` paths (copy list as constant, comment "keep in sync with mobile_texture_export.gd HERO"); skip `assets/incoming/ai3d/meshy/_work`, `_previews`, `_input` via a local SKIP list. Default mode unchanged.
2. `mobile_texture_export.gd`: `_begin_customize_resources` returns false when `features.has("pc_build")`; header comment "PC exports (custom feature pc_build) are never capped." Don't change MAX_PX/SMALL_PX/HERO_PX.
3. `optimize_glb.py`: `BUDGETS_PC` (hero 4096/2048, house 2048/1024, prop 1024/512, small 1024/512, thin 2048/512, landmark 2048/1024, creature 2048/1024) via trailing `--pc`; keep the 4-arg form. Do NOT re-run on existing assets.
4. Re-import:
```
py tools/qa/texture_vram.py --pc            # dry run, record count
py tools/qa/texture_vram.py --pc --write
"<godot>" --headless --path kingdom --import
git status --short kingdom/assets | wc -l     # only .import files may change
```
Never commit `.godot/`. Any non-`.import` change → stop and report. Commit the `.import` rewrite alone: "textures: VRAM-compress all shipped 3D textures for PC (BC/BPTC + mips)".
5. Verify: `--export-pack "Windows Desktop" ../build/pc_test.pck` (no MobileTextureLimit line) and `--export-pack "Android" ../build/a_test.pck` (`MobileTextureLimit: N textures capped`, N ≈ before). Windows check needs WP1.

Acceptance: gate PC_HIGH `tex_mb` ≤ 900; VRAM < 6.5 GB; hero/gate-stone crops not blurrier at 1440p; Android gate LOW tex ±5 %.

Must NOT touch: `quality.gd`, `project.godot`, `export_presets.cfg`, any `.gd` outside the addon, any `.glb/.png/.jpg` source.

---

## WP3: Lighting and GI (Style G) — merge last

**Files:** `kingdom/scripts/style_g.gd`, `kingdom/scripts/core/main.gd` (`_build_environment` 567-586 only), `kingdom/shaders/style_lab/lab_polished.gdshader`, `lab_polished_lite.gdshader`, `kingdom/shaders/water.gdshader`, `kingdom/shaders/water/clear_water.gdshader`, `kingdom/scripts/world/water_streamer.gd`.

Decision: **SDFGI**, not VoxelGI (camera-centred, no bake, streams, reads the sky).

Style G rules: shadows cool blue-violet (never grey/black), warm bounce, Filmic, same LUT; must still match `00_MAIN_kingsreach_gate_market.webp` at a glance.

1. Shaders (both lab_polished): `global uniform float ashes_gi_on;` replace line 111 with
```glsl
float gi_k = 1.0 - 0.45 * ashes_gi_on;
c *= mix(1.0, ao, gi_k) * mix(1.0, COLOR.a, vao_strength * gi_k);
```
For baked-VAO meshes (AO in `COLOR.rgb`, `baked_vao.gd:81`), where the shader multiplies `COLOR.rgb` apply `vc = mix(vc, vec3(max(vc.r, max(vc.g, vc.b))), 0.45 * ashes_gi_on);`.
2. `apply_daylight` when `env.sdfgi_enabled`: `fill.light_energy *= 0.35`; `ssao_intensity = 1.6`, `ssao_light_affect = 0.0` (else restore 2.8/0.2); `ambient_light_energy *= 0.8` (keep colour). Constants in `const GI_COMP := {...}` near `SHADOW`.
3. Volumetric fog per hour: `const VFOG_KEYS := [[hour, sun_vol_energy, albedo_hex, anisotropy, emission_hex, emission_energy], ...]` — dawn 5.8–7.0: 2.2, `ffd8b0`, 0.6; day 9.5–15: 1.0, `f2e2c0`, 0.3; golden/dusk 17–18.8: 2.6, `ffc890`, 0.7; night: 0.6, `8a9ad8`, 0.2, emission `1a2142` @0.02. Lerp like `palette_at`; write `sun.light_volumetric_fog_energy`, `volumetric_fog_albedo`, `volumetric_fog_anisotropy`, `volumetric_fog_emission(_energy)` only when `env.volumetric_fog_enabled`. **Never write `volumetric_fog_density`**; grep weather.gd for each property first and skip any weather owns. In `main.gd` remove the hard `light_volumetric_fog_energy = 1.4` and the three `= false` lines for ssil/sdfgi/vfog.
4. Soft shadows: keep `shadow_blur = 1.0`, `light_angular_distance = 0.35`; add `directional_shadow_blend_splits = true`, `directional_shadow_fade_start = 0.85`. Don't change `SHADOW` distances.
5. Water SSR: in `water.gdshader` and `water/clear_water.gdshader` add `uniform int ssr_steps = 0;` and a view-space linear ray march along `reflect(-VIEW, NORMAL)` using the declared screen/depth textures, thickness 0.5 m, fallback to sky/fresnel on miss, 10 % edge fade. `water_streamer.gd apply_quality()`: if `Quality.has_value("water_ssr")` and full shader → `set_shader_parameter("ssr_steps", int(Quality.value("water_ssr")))`. Lite shader gains no screen texture.

Acceptance (gate/dusk/night 2560x1440 `--profile=pc --quality=high`): sun-shadow cobble 32x32 patch mean has b > r and b > g, hue 220–275°, luminance ±12 % of `pc1_gate_ultra_before.jpg` (measure with PIL from the scratchpad); mean frame luminance ±10 %; dusk god rays visible; night violet-blue not grey; scene ratings ≥ Audit 2 HIGH (7.6/7.4/7.4).
Test `tests/test_style_g_vfog.gd`: `palette_at` keys unchanged (15), VFOG lerp at 18.0 between neighbours; `apply_daylight` safe with `env == null`.
Must NOT touch: `quality.gd`, `project.godot`, `weather.gd`, `DAY_KEYS`, LUT, `PALETTE`, `baked_vao.gd`, VAO blobs. If violet can't be kept under SDFGI: ship PC_HIGH `sdfgi:false, ssil:true` and report (that's a WP1 file — hand off, don't edit).

---

## WP4: World density

**Files:** `population_lod.gd`, `villager.gd` (1133 only), `crowd_anim_lod.gd`, `cell_streamer.gd`, `static_merge.gd`, `settlement_builder.gd`, `grass_field.gd`, `critter.gd`, `frontier_presence.gd`, `lakeside.gd`, `region_dressing.gd`, `ambient_life.gd`, `low_budget.gd` (one line), tests.

Rule: re-gate, never delete.

| Site | Today | Change |
|---|---|---|
| `static_merge.gd:36` | skip unless tier "low" | skip unless `_q_value("draw_merge", current_tier()=="low")` (guarded `/root/Quality` lookup via `Engine.get_main_loop()`, old test when absent) |
| `settlement_builder.gd:625-635` | `q.tier == q.LOW/MEDIUM` | `and not q.is_pc()` |
| `population_lod.gd:117` | `tier >= 1` | `bool(Quality.value("vat_crowd"))` |
| `population_lod.gd` caps | `MAX_FULL 24`, `MAX_SPRITES 140` | `MAX_FULL 40`, `MAX_SPRITES 220`; NEAR_HARD_CAP unchanged |
| `crowd_anim_lod.gd` BUDGETS pick | `BUDGETS[tier]` | `Quality.value("crowd") if Quality.has_value("crowd") else BUDGETS[tier]` |
| `cell_streamer.gd distance()` | per-tier arrays | × `stream_mul` on full/load/hyst for population, dressing, ambient, settlement only |
| `grass_field.gd:13` use | `CLUMPS_PER_CHUNK` | `int(CLUMPS_PER_CHUNK * float(Quality.value("grass_mul")))` |
| `critter.gd:143` | `Quality.tier > 0` | `not Quality.value("lite_world")` |
| `frontier_presence.gd:62,196`, `lakeside.gd:124`, `region_dressing.gd:586`, `ambient_life.gd:155` | `tier <= 0` | `Quality.value("lite_world")` |
| `region_dressing.gd:538` | `tier <= 1` | `Quality.value("lod1_dressing")` |
| `villager.gd:1133` | `int(Quality.tier) == 0` | `bool(Quality.value("lite_world"))` |
| `low_budget.gd low()` | | add `and not Quality.is_pc()` (guarded) |

Tests: extend `test_pooling_streaming.gd` (mobile `distance()` unchanged all tiers); new `test_density_pc.gd` (profile "pc": StaticMerge `begin()` returns `{}`, `_is_low()` false at tier 0); `test_market_dressing.gd:129` passes.
Acceptance (PC_HIGH 1440p): gate ≥ 24 full NPCs, VAT crowd to ~220 m, denser grass in road shot, fps p50 ≥ 60, p95 ≤ 20 ms; phone LOW gate draws within ±3 of 129-132.
Must NOT touch: `quality.gd` (missing key → fail loudly, don't add), `style_g.gd`, shaders, input/HUD.

---

## WP5: PC input and HUD

**Files:** `kingdom/autoload/game.gd`, `kingdom/scripts/actors/player.gd` (input/look only, CRLF!), `kingdom/scripts/ui/hud.gd`, `kingdom/scripts/ui/hud_art.gd`, `kingdom/scripts/core/app_services.gd`, `docs/controls.md`, new `kingdom/tests/test_input_pc.gd`.

1. `hud.gd _ready()` if `not _touch`: `Input.emulate_touch_from_mouse = false`; `stick.visible = false`; look Control `mouse_filter = MOUSE_FILTER_IGNORE`; build but hide attack/jump/dodge/block/lock_combat/dash buttons (grep every `_buttons[` use first). `--touch` keeps the phone HUD.
2. Mouse look (player.gd): in `_unhandled_input`, when `Input.mouse_mode == MOUSE_MODE_CAPTURED` and `InputEventMouseMotion` → `add_look(event.relative * App.look_scale * MOUSE_K)`, `const MOUSE_K := 0.6`. Capture on game start and on click into the 3D view when no menu (`_menu_open()` at player.gd:457); release when `_menu_open()` becomes true, on `ui_cancel`, on focus-out; re-capture on focus-in only without a menu. Edge-detect `_menu_open()` in `_process`; don't modify menu scripts. Never capture in touch mode.
3. Bindings: extend PADS to `[[mouse], [joy buttons], [joy axes as [axis, sign]]]`, `_setup_input` adds `InputEventJoypadMotion` with `axis_value = sign`:

| Action | Keyboard / mouse | Gamepad (Xbox) |
|---|---|---|
| move_forward/back/left/right | WASD + arrows | Left stick |
| look_left/right/up/down (new) | mouse | Right stick |
| attack | J + Mouse Left | X |
| block | L + Mouse Right | LT |
| jump | Space | A |
| dodge | K | B |
| interact | E | Y |
| sprint | Shift | RT |
| lock_on | Q, Middle mouse | R3 |
| crouch | C | L3 |
| ability_dash | R | LB |
| technique_wheel | T | RB |
| journal | Tab | Back |
| world_map | M | D-pad Up |
| menu_inventory | I | D-pad Down |
| zoom_in/out | wheel, = / − | D-pad Right/Left |

Right-stick look in player `_process`: `var v := Input.get_vector("look_left","look_right","look_up","look_down")`; `add_look(v * 900.0 * delta * App.look_scale)` when `v.length() > 0.15`. Keep lock-switch flicks (player.gd:1079). Deadzone 0.2 on new axis actions. `technique_wheel.gd:275` reads sticks directly; wheel must still work (look suppressed while `_menu_open()`). Don't change `App.look_scale` defaults.
4. PC HUD (desktop only): bottom-left health/stamina; bottom-centre hotbar with key glyphs; bottom-right keybind hint strip ("LMB attack · RMB block · Space jump · K dodge") switching to gamepad glyph text after the last `InputEventJoypad*`. `_safe_rect` unchanged. Nothing moves when `_touch`.
5. `docs/controls.md`: the table.

Tests `test_input_pc.gd`: after `Game._setup_input()`, `move_forward` has JoypadMotion axis 1 sign −1; `attack` has `MOUSE_BUTTON_LEFT`; no two actions share a key or mouse button.
Acceptance: mouse look captured, Esc/menu frees cursor; Xbox pad moves/looks/attacks/jumps/dodges; no touch controls; `--touch` restores phone HUD; audit gate with `--hud=1` → `pc1_gate_pc_high_hud_after.jpg`.
Must NOT touch: `quality.gd`, `settings_*`, `project.godot`, `main.gd`, world/population, shaders.

---

## QA recipe

`G=C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe`. GPU only, never `--headless` for captures. Laptop on AC; NVIDIA "High-performance processor" for the exe; no other Godot running; log must show `NVIDIA GeForce RTX 4070 Laptop GPU` (if iGPU → stop).

Before (base + WP0):
```
"$G" --path kingdom --rendering-method forward_plus --resolution 2560x1440 res://tools_qa/aaa_audit/audit_views.tscn \
  -- --adult --skipintro --quality=ultra --out=C:/Users/Jonna/Documents/PA_wt_audit/docs/qa/aaa_feel \
  --pattern=pc1_{scene}_{tag} --tag=ultra_before --only=gate,dusk,night --hud=0 --bench=20
```
and `--quality=high --tag=high_before`.

After, T in low, medium, high, ultra: `... --profile=pc --quality=$T --tag=pc_${T}_after --only=gate,dusk,night --hud=0 --bench=20`; 3 runs each, report medians; `-- --profile=pc --quality=high --perflog` 2-min road walk; `nvidia-smi --query-gpu=memory.used --format=csv -l 1` alongside.

Phone regression: `--rendering-method mobile --profile=mobile --quality=low --resolution 2340x1080 --tag=low_regress --only=gate` → draws 129-135.

Acceptance: PC_HIGH 1440p gate/dusk/night `fps_avg ≥ 60`, `ft_p95 ≤ 20 ms`; VRAM < 6656 MB and nvidia-smi peak < 6.5 GB; PC_ULTRA renders without error; visual rating each scene ≥ Audit 2 HIGH and ≥ its `ultra_before`; Style G shadow hue check passes; phone LOW draws ≤ 135; gdUnit green (exit 0 or 101 orphans only). Integrator appends a "PC1 scorecard" under Audit 2 in `docs/art/AAA_PRESENTATION_REVIEW.md`.

## Merge order
1. WP0 → take before shots on base + WP0.
2. WP1 (contract).
3. WP2, WP5 (WP2's Windows export check needs WP1).
4. WP4 (needs WP1 keys).
5. WP3 last (needs `ashes_gi_on`; tune with final density/textures).

## Risks (stop and report, don't guess)
1. Mobile behaviour must stay identical: no change to original `TIERS` values, `CellStreamer.PROFILES`, `BUDGETS` rows, MobileTextureLimit constants. Phone regression run is mandatory.
2. SDFGI vs custom ambient colour: tune only `GI_COMP` and `sdfgi_energy`; never DAY_KEYS/LUT/PALETTE. If violet is lost → PC_HIGH `sdfgi:false, ssil:true`, report.
3. Weather owns base values for `fog_density`, `volumetric_fog_density`, `ambient_light_energy` — no new writers; grep `_base_of` first.
4. FSR2 ghosting on VAT crowds / grass wind / water → PC_HIGH `"scaling":"fsr"`, `"taa":true`, report; don't edit VAT shaders.
5. No raw Meshy sources: no GLB re-bakes or AI upscaling in phase 1.
6. `.import` bulk rewrite: single isolated commit; never `.godot/`; never hand-edit `.import`.
7. Optimus laptops may run on the iGPU → fps invalid unless the log shows the RTX.
8. No enum values beyond ULTRA (arrays/tests assume 0..3).
9. `App.look_scale` is touch-tuned; mouse uses `MOUSE_K`.
10. Never MSAA together with FSR2.
11. `directional_shadow_atlas_set_size(8192, true)` on ULTRA; cap at 4096 if it fails or VRAM over budget. Don't raise `shadow_dist` beyond rows.
12. Scope discipline: a needed change in another WP's file → hand-off note in the report, never edit.
