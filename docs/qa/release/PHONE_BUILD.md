# Newest build on the S22 (2026-10-05 20:17)

- Source: origin/claude/focused-curie-m09hbd @ 0199e440 (cloud F9/F12 + Watch Post captain).
- Debug APK (non-Gradle, 4.6.stable template via the 4.6.3.stable symlink), installed over com.risingashes.game (was 0.1.0 from 09-30).
- Launch: `adb shell monkey -p com.risingashes.game -c android.intent.category.LAUNCHER 1` (GodotApp is not exported; the launcher activity is GodotAppLauncher).
- Boots to the main menu in about 8 s: `01_main_menu.jpg`.
- APK size: 964 MB (debug, arm64 + armv7). Too big for Play; see RELEASE_READINESS.md (in progress).
- Boot errors seen: GodotGAS gameplay_cue_manager.gd uses EditorInterface (autoload fails), and dialogue_manager settings.gd preloads an excluded test_scene.tscn (DialogueManager fails to compile). Being fixed in the release QA pass.

## Release QA, partial (stopped at usage limit, 2026-10-05 20:45)
Fixed (in build A, untested on device yet):
- GodotGAS `gameplay_cue_manager.gd`: bare `EditorInterface` failed to parse in exports, so the GameplayCueManager autoload failed. Now `Engine.get_singleton(&"EditorInterface")`, which only runs in the editor.
- `export_presets.cfg`: removed `res://addons/dialogue_manager/test_scene.tscn` from the excludes. `settings.gd` preloads it, so DialogueManager failed to compile on device.
Measured (debug APK, S22, Auto = LOW, already hot): 41 fps avg, p50 16 ms, p95/p99 33 ms; PSS 2.6-2.7 GB; SKIN 43 C, thermal status 3 (severe) after about 10 min; new-game load about 60-90 s. MED/HIGH not measured.
Worked: boot, menus, character creator, story start, joystick, camera, radial menu, Android back opens Pause, autosave, manual save to Slot 1, settings.
Found: APK is 964 MB (blocker). The creator preview crops the head. An unrequested carpenter job popup opens on spawn and overlaps the tutorial. The pause icon in the radial does nothing. The loading tip says F5/F9 on a phone.
Build note: meshy_free `*_lod_bake.jpg` files are gitignored and generated on import. A build reusing another worktree's cache must copy them, or the models fail to load.
The SAFE audit excludes are already in effect (.gdignore or existing entries); a blanket `meshy_free/maybe/*` would break 3 promoted models.
Verdict so far: NO-GO for a public release (size, heat, memory); fine for owner and closed testing once build A is checked.
