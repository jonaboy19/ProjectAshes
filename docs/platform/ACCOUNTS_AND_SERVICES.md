# Accounts and platform services (Play Games / Game Center)

Research retrieved 2026-09-29. Verify version numbers again before installing.

## 1. Abstraction

`kingdom/scripts/core/platform_services.gd` (to be registered as autoload `PlatformServices`).

- The autoload node exposes: `sign_in()`, `sign_out()`, `unlock(id)`, `increment(id, steps)`, `submit_score(board, score)`, `show_achievements()`, `show_leaderboard(board)`, `upload_cloud_save(slot, bytes)`, `download_cloud_save(slot, cb)`, `is_signed_in()`, `backend_name()`, `player_name()`. Signals: `signed_in_changed`, `achievement_unlocked`, `cloud_save_synced`.
- Inner classes: `Backend` (interface, all no-ops), `NullBackend`, `GooglePlayBackend` and `GameCenterBackend` (documented skeletons with TODOs).
- `_ready()` picks the backend: Android + singleton `GodotPlayGameServices` -> Google Play; iOS + ClassDB class `GameCenterManager` -> Game Center; otherwise Null. It prints `[services] backend=null`.
- Everything is a silent no-op while signed out. Plugin classes are never referenced statically, only via `Engine.has_singleton()` / `ClassDB`, so desktop parsing never breaks.
- Logical achievement names live in the `ACHIEVEMENTS` const (`first_steps`, `first_kill`, `reach_militia`, `discover_10_places`, `survive_first_winter`), leaderboards in `LEADERBOARDS`. Each maps to `{android, ios}` ids; empty string = skipped.
- To swap in a backend: fill the TODOs in the matching inner class (override `sign_in`, `unlock_achievement`, ...) or add a new `Backend` subclass and return it from `_pick_backend()`. Game code does not change.
- The exact Android singleton name and method names of the Play Games plugin were NOT verified against a build (the plugin is Kotlin and node-based since v3.0). Check the installed addon's GDScript and adjust `SINGLETON` and the calls.

## 2. WARNING: no Android-only binaries in the repo yet

Do not commit the Play Games addon (Android AAR/Kotlin plugin) into `kingdom/addons/` yet. It is an Android-only editor plugin: enabling it breaks or spams desktop runs, it needs a custom Gradle build, and it interferes with iOS export. Install it in a release branch or a gitignored local copy when preparing an Android build. The Apple addon (GodotApplePlugins) ships desktop stubs, but adds large Apple binaries; same advice.

## 3. Plugins found (from the repos, 2026-09-29)

| Purpose | Name | Version | Licence | Notes |
|---|---|---|---|---|
| Google Play Games v2 | [godot-sdk-integrations/godot-play-game-services](https://github.com/godot-sdk-integrations/godot-play-game-services) (maintainer Iakobs / Jacob Ibanez Sanchez) | v3.4.0 (2026-07-20), wraps Play Games SDK v2 21.0.0 | MIT | README: Godot 4.3+, badge Android API 35, addon path `addons/GodotPlayGameServices/`, requires custom Gradle build. Release notes mention builds with Godot 4.5.1. Not explicitly stated for 4.6: test it. Also on the [Godot Asset Store](https://store.godotengine.org/asset/jacob-ibanez-sanchez/google-play-games-services-for-godot/). |
| Apple Game Center (recommended) | [migueldeicaza/GodotApplePlugins](https://github.com/migueldeicaza/GodotApplePlugins) | rolling builds only, latest `build-bfade13...` (2026-09-02), no semver tags | MIT | GDExtension for macOS/iOS/visionOS: GameCenter, StoreKit2, Sign in with Apple. Needs iOS 17+. Empty stubs on Windows/Linux. Asset Library id 4552. Docs: [GameCenterGuide](https://github.com/migueldeicaza/GodotApplePlugins/blob/main/Sources/GodotGameCenter/GameCenterGuide.md). Needs the `com.apple.developer.game-center` entitlement. |
| Apple (official, older) | [godotengine/godot-ios-plugins](https://github.com/godotengine/godot-ios-plugins) (`plugins/gamecenter`) | last GitHub release 3.5-stable (2022); repo pushed 2026-07-10 | MIT | Old iOS-plugin system, must be built from source, no ready binaries. Not recommended. |

The Godot Foundation says it is improving the Play Games and StoreKit plugins ([Godot Mobile update, Apr 2026](https://godotengine.org/article/godot-mobile-update-apr-2026/)).

## 4. Android next steps

1. Install JDK 17 and the Android SDK. The Godot 4.6 docs list Platform 35, Build-Tools 35.0.1, Platform-Tools 35+, NDK r28b, CMake 3.10.2.4988404: [Godot 4.6 Android export](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html). Set both paths in Editor Settings.
2. Project > Install Android Build Template (creates `res://android/build/`). In the export preset enable Use Gradle Build and Export Format = AAB.
3. Target API: Play requires **API 36 for new apps and updates from 2026-08-31** (extension to 2026-11-01 possible; existing apps stay available with API 35): [Google](https://developer.android.com/google/play/requirements/target-sdk). The 4.6 docs list SDK 35; a forum answer says Godot 4.7 defaults to target 36. Verify `targetSdk` in `android/build/config.gradle` and the preset, or upgrade the engine, before release.
4. Download `addons.zip` from the plugin releases into `kingdom/addons/GodotPlayGameServices/`, enable it in Project Settings > Plugins, add the Play Games game ID in the Android export preset (v3.3.0+ has this field). Initialise the plugin node manually (no auto sign-in since v3.0).
5. Play Console: create the app, then Play Games Services > Setup: create credentials (OAuth Android client with package name and SHA-1 of the upload/debug key AND of the Play App Signing key), configure the OAuth consent screen, add testers, create achievements and leaderboards, publish them.
6. Map ids: paste each achievement id into `ACHIEVEMENTS[...]["android"]` in platform_services.gd, leaderboards into `LEADERBOARDS`.
7. Call `PlatformServices.sign_in()` once after the main menu is shown (not on the first frame) and add a manual "Sign in" button in Settings; never block gameplay on it.
8. Export with a release keystore, "Export With Debug" off, enrol in Play App Signing, test on the internal testing track.

## 5. iOS next steps

1. Export needs a Mac with Xcode; the iOS simulator is not supported. The preset needs App Store Team ID and a unique Bundle Identifier: [Godot 4.6 iOS export](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_ios.html).
2. Apple Developer Program membership; register the App ID with the Game Center capability; create the app in App Store Connect, enable Game Center and create achievements and leaderboards; put their ids in the `"ios"` fields.
3. Put the GodotApplePlugins addons zip contents into `kingdom/addons/GodotApplePlugins/`, export, open the Xcode project and add the Game Center entitlement.
4. Only include the libraries you use (README: fewer libraries, fewer Apple review questions).
5. Privacy manifest: ship a `PrivacyInfo.xcprivacy` declaring required-reason APIs. Apple enforces manifests and signatures for listed third-party SDKs ([Apple](https://developer.apple.com/support/third-party-SDK-requirements/)); check that Godot's iOS export produces one for the engine (not verified here).
6. In App Store Connect: App Privacy labels, age rating (12+/17+ were replaced by 13+/16+/18+; the new questionnaire had to be answered by 2026-01-31 to keep submitting updates: [Apple](https://developer.apple.com/news/?id=ks775ehf)), privacy policy URL.
7. Sign in with Apple is only required if you offer third-party social login (Google, Facebook, ...). Game Center alone does not trigger it. ATT prompt is not needed if nothing tracks users.
8. Test with TestFlight.

## 6. Cloud-save design note

`kingdom/scripts/sim/save_manager.gd` writes `user://saves/`. Plan:

- After each successful local save, call `PlatformServices.upload_cloud_save(slot, bytes)` with the latest slot's JSON (make sure the JSON header carries `playtime_s` and `saved_at`). Android: Play Games Saved Games snapshots. iOS: iCloud key-value store (small, about 1 MB total limit) or Saved Games via GameKit.
- On sign-in or app start: `download_cloud_save(slot, cb)` and compare with local.
- Conflict rule: newest playtime wins, but ask the player when both sides differ ("Use cloud save (12 h) or this device (10 h)?"). Never overwrite silently; keep a local backup of the replaced save.
- Cloud save is optional: the game must be fully playable signed out.

## 7. Store basics still missing (checklist)

- [ ] Privacy policy URL (required by both stores, public web page)
- [ ] Terms of service / EULA
- [ ] Age rating: IARC questionnaire (Play) and the new Apple questionnaire
- [ ] Google Play Data safety form (declare all data: Play Games ids, crash data, ads/analytics if any)
- [ ] Apple App Privacy labels and `PrivacyInfo.xcprivacy`
- [ ] App icon (512 px Play, 1024 px iOS), feature graphic 1024x500, phone screenshots (tablet too if targeted)
- [ ] Store listing text in en and nl (title, short and full description, what is new)
- [ ] Support email / contact address (shown publicly)
- [ ] Content rating and target audience declaration (avoid targeting children unless deliberate: COPPA, Play Families, Apple Kids rules)
- [ ] Crash reporting decision (Play Console vitals only, or Sentry/Firebase; each changes the privacy forms)
- [ ] Account deletion: if users can create an account, Play requires an in-app deletion path plus a web URL, and Apple requires in-app deletion ([Google](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en)). Play Games / Game Center sign-in is platform-managed; re-check if you add your own accounts.
- [ ] GDPR (owner in the Netherlands): controller identity, legal basis, retention, right to erasure, processor list, consent if analytics or ads
- [ ] Release keystore (backed up offline) plus Play App Signing enrolment
- [ ] iOS bundle id, team id, certificates, provisioning profiles
- [ ] Internal testing (Play) and TestFlight (Apple); check Play's current closed-testing requirements for new personal developer accounts before planning a launch
- [ ] Target API 36 build (section 4)
