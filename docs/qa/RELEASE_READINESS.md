# Release readiness (S22, Rising Ashes)

Updated 2026-10-05 (release QA pass 2, PC-side fixes; phone runs paused while the owner unplugged the S22).

## Verdict: NO-GO for a public release. OK for owner and closed testing once build C passes the phone checks below.

## APK size (debug, measured)
| Build | Size | Notes |
|---|--:|---|
| A (origin 2be0118e-era, before) | 1,404 MB | arm64 + armv7 |
| B: texture fix + excludes | 945 MB | same, plus the fixes below |
| C: + 512 px phone cap, arm64 only | 650 MB | |
| D: + editor-only addons excluded (sky_3d, gloot, proton_scatter, phantom_camera examples) | **624 MB** | current |

Target is under 500 MB (ideally 300 MB). Still a blocker.

### Why it grew (measured from the APK listing)
- 606 MB were textures imported **lossless** (`compress/mode=0`, not VRAM): every Meshy `*_lod_bake.jpg`, polyhaven and kit textures. On the phone they sat in GPU memory as RGBA8 (4x ETC2). `addons/mobile_texture_limit` only converted textures *larger* than its cap, so the 1024 px Meshy bakes passed through untouched.
- Excluding a GLB does not exclude its extracted sidecar textures (`<glb stem>_<image>.jpg`): `export_filter="all_resources"` still packs them. That shipped `meshy_free/maybe/*` and other excluded models' textures.
- Meshy batch 3 (`meshy_dl3/`, 97 models) is referenced by nothing yet: ~123 MB in build A.
- A 4K polyhaven HDR (33.5 MB, uncompressed) used by nothing.

### Fixes
- `mobile_texture_limit` v4: uncompressed textures of any size are converted to ETC2 (ASTC on iOS) with mipmaps; caps lowered to 512 px (hero content 1024, small 256). Desktop imports are unchanged.
- `tools_qa/asset_use/sidecar_excludes.py --models --apply`: excludes Meshy models (`meshy_dl3/`, `meshy_free/`) that no game file names, plus the sidecar textures of every excluded model. 553 entries added to both presets. **Kept in the repo.** If code starts placing a `meshy_dl3` model, rerun the script (it only excludes unreferenced names) and remove the stale entry.
- Excluded `assets/incoming/polyhaven/hdris/*`.
- Android export: arm64 only (armv7 dropped, -28 MB lib).

### Still in the 624 MB (build D)
Meshes `.scn` ~240 MB (Meshy LOD0s with generated LODs and shadow meshes), already-VRAM textures, VAT bakes 26 MB, audio 64 MB, engine 25 MB. No single culprit left (largest folder: in-use `ai3d/meshy` buildings, 36 MB of meshes). The audit CSV's still-shipped UNREF files are only ~4 MB and sit in kits whose names are built in code, so they were left in. Options to get under 500 MB, each a quality call for the owner: 256 px phone cap for non-hero textures (about -130 MB, blurrier buildings up close on HIGH), music/ambience re-encoded at 96 kbps (about -25 MB), or disabling generated LODs/shadow meshes on Meshy models that ship their own LOD1.

## Boot errors
- GodotGAS (`project_settings.gd` 153/162, `gameplay_cue_manager.gd`): confirmed unused (only comments and the credits list). Plugin and autoload removed; folder excluded from export.
- Also removed as unused, per `docs/TOOLCHAIN_AUDIT.md`: GUIDE (autoload + plugin), Dialogue Manager (autoload + plugin), Road Generator (plugin). QuestWeaver stays: `life.gd`, `menu_data.gd` and `village_services.gd` look it up.
- Headless PC boot of the new tree: no errors from these changes.
- **Old build crash:** build A died with SIGSEGV on `VkThread` right after the first in-game touch (2026-10-05 21:00). Needs a recheck on build C.

## Performance (LOW = what the S22 auto-picks)
| | Before (build A) | After |
|---|---|---|
| LOW fps | 41 avg, p95 33 ms | not measured yet (phone unplugged) |
| Memory (PSS) | 2.6-2.7 GB | not measured yet |
| Thermal | severe (status 3) after ~10 min | not measured yet |
| MED / HIGH | not measured | not measured |

### Fixes so far
- **LOW ran at 60 fps cap.** LOW declares 30, but the settings default `fps_limit=1` (60) overrode it on every phone, so the GPU ran flat out: this is the heat. New option **Auto** (default; old saves with the old default are migrated): follows the tier (LOW 30, MED/HIGH 60).
- **Thermal guard** (`Quality`): reads `PowerManager.getCurrentThermalStatus()` through the `AndroidRuntime` singleton every 5 s (app sysfs reads are denied on Samsung). MODERATE caps at 30 fps; SEVERE also drops the render scale to 75 %. Released after 60 s at LIGHT or better. Runs for the "60" and "Auto" limits.
- Textures now ETC2 with mipmaps on phones (see above): this should cut GPU memory the most.
- Debug builds log a `PERF` line every 10 s (fps, p50/p95/p99, draws, primitives, VRAM, static memory, tier, cap, thermal): `adb logcat -s godot | grep PERF`.

### To do when the phone is back
`bash tools/qa/phone/soak.sh 120 <out>` for 2-minute checks, one 900 s run at the end. Then: draw calls of the 153 placed Meshy models, LOW shadows, VAT crowd cap, particles, impostors too close.
