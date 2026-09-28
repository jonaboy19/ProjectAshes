---
name: ashes-release
description: Build, test on device and ship Rising Ashes to Google Play and the App Store. Use for APK/AAB/IPA builds, export presets, signing, store listing, store screenshots, age rating, privacy, or "put it on my phone".
---

# Rising Ashes release

## What exists
- `kingdom/export_presets.cfg`: Android (arm64 + armv7, min SDK 24, target 35, ETC2/ASTC, landscape, immersive) and iOS (arm64, iOS 14+). The exclude list keeps unused `incoming/` packs, previews, `_raw`, `_work`, tools and tests out of the build. **If code starts loading something under an excluded path, remove that exclude.**
- `docs/RELEASE.md`: signing, export templates and steps.
- `store/`: icons (Android adaptive + iOS set), logo, feature graphic, 8 screenshots × 2 sizes plus captioned copies, `listing.md` (texts, rating draft, privacy: no data collected), `README.md` (upload map and the user's to-do list). Regenerate with `tools/store/*` (`make_screenshots.sh` drives the real game at Ultra).
- The Credits & Licences screen (MIT/CC-BY notices must ship) reads `kingdom/CREDITS.md`. Add a credit line for every new CC-BY asset.
- `addons/mobile_texture_limit` caps textures for Android/iOS exports.

## Build a phone test APK
1. The Godot editor needs Editor Settings → Export → Android → Java SDK Path = `C:/Program Files/Microsoft/jdk-21.0.11.10-hotspot` (JDK 21 is installed; the Android SDK and debug keystore are in place). **This is the user's editor setting: ask before changing it.**
2. `godot --headless --path kingdom --export-debug "Android" build/rising_ashes_debug.apk`.
3. Install it with `adb install -r` if a phone is connected with USB debugging (ask the user), or send the APK to the user.
4. On the device: run the bench scenes and watch for heat or throttling after 10 minutes.

## Only the user can do
Google Play developer account and the closed test with 12 testers, the upload keystore (never commit it or type its passwords), an Apple developer account plus a Mac for iOS signing, pricing, the privacy-policy URL, the content-rating and data-safety forms. Guide them step by step; never enter credentials yourself.

## Before every release build
Run `ashes-performance` (the bench plus the visual check), the playtest bot, `tools/qa/anim_qa` and `docs/OPEN_SOURCE_AUDIT.md` for new packs, then re-shoot the store screenshots if the look changed.
