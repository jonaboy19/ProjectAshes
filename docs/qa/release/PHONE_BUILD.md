# Newest build on the S22 (2026-10-05 20:17)

- Source: origin/claude/focused-curie-m09hbd @ 0199e440 (cloud F9/F12 + Watch Post captain).
- Debug APK (non-Gradle, 4.6.stable template via the 4.6.3.stable symlink), installed over com.risingashes.game (was 0.1.0 from 09-30).
- Launch: `adb shell monkey -p com.risingashes.game -c android.intent.category.LAUNCHER 1` (GodotApp is not exported; the launcher activity is GodotAppLauncher).
- Boots to the main menu in about 8 s: `01_main_menu.jpg`.
- APK size: 964 MB (debug, arm64 + armv7). Too big for Play; see RELEASE_READINESS.md (in progress).
- Boot errors seen: GodotGAS gameplay_cue_manager.gd uses EditorInterface (autoload fails), and dialogue_manager settings.gd preloads an excluded test_scene.tscn (DialogueManager fails to compile). Being fixed in the release QA pass.
