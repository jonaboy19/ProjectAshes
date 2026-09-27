# Release builds (Android / iOS)

Presets live in `kingdom/export_presets.cfg` (Android, iOS). They export every
resource the game loads and exclude the imported-but-unused packs from
`docs/OPEN_SOURCE_AUDIT.md` (plus `_previews`, `_raw`, `_work`, `_tools`,
`_sources`, `tools/`, `tests/`, gdUnit4, LimboAI, Terrain3D and the Poly Haven model
sources). `CREDITS.md` and the addons' `LICENSE` files are added with the
include filter, because the in-game **Settings & Credits → Credits & Licences**
screen reads them at runtime.

**When game code starts loading a path that is listed in `exclude_filter`, remove
it from the filter**, or the release build will be missing that asset.

## Export templates

Godot 4.6 templates are installed on the PC in
`%APPDATA%\Godot\export_templates\4.6.stable\` (Android only so far).
To install or update them: Editor → *Manage Export Templates* → *Download and
Install*, or download `Godot_v4.6-stable_export_templates.tpz` from
godotengine.org and use *Install from File*. The iOS template is inside the same
`.tpz`; iOS builds must be finished on a Mac with Xcode.

## Android

- Architectures: `arm64-v8a` + `armeabi-v7a` (older 32-bit phones). x86 off.
- Min SDK 24 (Android 7.0) is the Godot 4.6 template's minimum; target SDK 35.
  (`gradle_build/min_sdk/target_sdk` only take effect with a Gradle build.)
- Landscape (`display/window/handheld/orientation=4`, sensor landscape), immersive mode.
- Textures: `rendering/textures/vram_compression/import_etc2_astc=true` (ETC2/ASTC).
- Renderer: Mobile (Vulkan); devices without usable Vulkan fall back to
  Compatibility (OpenGL ES 3) through `rendering_device/fallback_to_opengl3`.
  `Quality` then starts on LOW.

One-time on the PC: Editor → Editor Settings → Export → Android → **Java SDK Path** =
`C:/Program Files/Microsoft/jdk-21.0.11.10-hotspot` (JDK 21 is installed; the Android SDK
path and debug keystore are already set). Without it the CLI export stops with
"A valid Java SDK path is required" (checked 2026-09-27: the preset itself parses and
passes every other check).

Debug build (uses the editor's debug keystore, already configured on the PC):

```bash
godot --headless --path kingdom --export-debug Android ../build/android/RisingAshes-debug.apk
adb install -r build/android/RisingAshes-debug.apk
```

Release build: **signing fields are left empty on purpose**. Create an upload key
once and keep it OUT of the repo (e.g. `%USERPROFILE%\keys\risingashes-upload.jks`, backed up):

```bash
keytool -genkeypair -v -keystore risingashes-upload.jks -alias risingashes -keyalg RSA -keysize 2048 -validity 10000
```

Then either fill *Keystore → Release / User / Password* in the Export dialog
(stored in `kingdom/.godot/export_credentials.cfg`, git-ignored), or set
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`,
`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` and run
`godot --headless --path kingdom --export-release Android ../build/android/RisingAshes.apk`.
Google Play wants an `.aab`: switch to a Gradle build (`gradle_build/use_gradle_build=true`,
*Project → Install Android Build Template*) and `gradle_build/export_format=1`.

## iOS

Fill in on the Mac, not in the repo: `application/app_store_team_id`,
provisioning profile UUIDs and code-sign identities. Bundle id
`com.risingashes.game`, min iOS 14. LimboAI and Terrain3D are disabled
(`.gdignore` in their folders) because their iOS binaries aren't in the repo.

## Still needed before a store release

- A signed upload keystore (Android) and an Apple developer team + profiles (iOS).
- App icons (`launcher_icons/*`, iOS icons) and store assets.
- A real-device test on a low-end Android phone (Mali-G52 / Adreno 610 class) and an iPhone.
- Privacy policy / data-safety form (the game has no network access: `permissions/internet=false`).
