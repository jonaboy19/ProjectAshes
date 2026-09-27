# Rising Ashes: store listing kit

Everything needed for the Google Play and Apple App Store listings. All images come from the
game's own assets or the real game running at Ultra quality on the RTX 4070. No third-party art:
the fonts are Cinzel and IM Fell English (SIL OFL, in `kingdom/assets/incoming/fonts`), and the
icon uses the project's own Meshy runestone.

## Files and where they go

| File | What | Upload to |
|---|---|---|
| `icon/icon_master_1024.png` | 1024×1024 master icon, opaque | Source for everything else; App Store Connect uses the one in the iOS set |
| `icon/play_store_icon_512.png` | 512×512, 32-bit PNG | **Play Console** → Grow → Store presence → Main store listing → App icon |
| `icon/android/adaptive_foreground_432.png` | Adaptive icon foreground (transparent). The ring sits inside the 66 dp safe circle; the runestone runs out of the bottom edge on purpose | Already set in `kingdom/export_presets.cfg` (see below) |
| `icon/android/adaptive_background_432.png` | Adaptive background: navy with ember glow | Same |
| `icon/android/adaptive_monochrome_432.png` | Monochrome layer for Android 13+ themed icons | Same |
| `icon/android/main_192.png` | Legacy launcher icon | Same |
| `icon/ios/AppIcon.appiconset/` | Every iPhone/iPad size plus the 1024 marketing icon, all opaque, with `Contents.json` | Godot builds the iOS icons from `icons/icon_1024x1024` in the preset. For a hand-made Xcode project, drop this folder into `Assets.xcassets` |
| `icon/checks/` | The icon at 48 px and 96 px, and under circle/squircle masks and a themed tint | Review only |
| `feature_graphic/play_feature_graphic_1024x500.png` | Play feature graphic: in-game key art of Ashford with the title logo | **Play Console** → Main store listing → Feature graphic |
| `logo/rising_ashes_logo.png` | Title logo, transparent PNG, 2752×452 | Press kit, trailer end card, website, in-game title screen |
| `screenshots/phone_1920x1080/01…08_*.png` | 8 clean landscape screenshots (16:9) | **Play Console** → Phone screenshots (2 to 8). Also fine for 7" and 10" tablet slots |
| `screenshots/iphone65_2688x1242/01…08_*.png` | The same 8 moments rendered natively at 2688×1242 | **App Store Connect** → iPhone 6.5" Display screenshots (up to 10) |
| `screenshots/captioned/<size>/` | Copies with caption banners | Use these **or** the clean set in each store, not both. Captioned usually converts better |
| `listing.md` | Title, subtitle, short and full descriptions, keywords, category, content-rating draft, privacy answers and policy text | Copy into both consoles |
| `_work/` | Intermediate layers (icon foreground/background/mono at 1024, the key-art frame) | Not uploaded; kept so icons can be re-exported without re-rendering |

**Screenshot contents** (all Ultra quality, the fps/chunks debug line and world name tags hidden):
01 village market and villagers · 02 combat at the Mossfang goblin warren (HUD) ·
03 the Adventurers' Guild hall · 04 a runestone with the danger/protection readout (HUD) ·
05 armoured town guards (the player's squad) · 06 the inn interior at night ·
07 the plaza under lamp light · 08 aerial view of Ashford and its fields.

App Store note: 6.5" screenshots are accepted for the iPhone requirement; if App Store Connect
asks for 6.9" (1320×2868 / 2868×1320) as well, rerun the capture at that size (below).

## Export presets (done)

`kingdom/export_presets.cfg` wasn't being edited by anyone (clean in `git status`, last
touched by the presets commit), so the icon paths are filled in. The files are copies of the
icons above, inside the Godot project so they have `res://` paths:

```
[Android]  launcher_icons/main_192x192              = res://assets/generated/app_icon/icon_192.png
           launcher_icons/adaptive_foreground_432x432 = res://assets/generated/app_icon/adaptive_foreground_432.png
           launcher_icons/adaptive_background_432x432 = res://assets/generated/app_icon/adaptive_background_432.png
           launcher_icons/adaptive_monochrome_432x432 = res://assets/generated/app_icon/adaptive_monochrome_432.png
[iOS]      icons/icon_1024x1024                      = res://assets/generated/app_icon/icon_1024.png
```

`project.godot` (`config/icon`, the desktop/editor icon) was left alone. Point it at
`res://assets/generated/app_icon/icon_1024.png` if you want the same icon there.

## Regenerating

All scripts are in `tools/store/` (Git Bash; needs Godot 4.6, Blender 5.x and ffmpeg):

| Script | Makes |
|---|---|
| `make_icon.py` (Blender) | Icon layers in `store/_work/` |
| `make_icons.sh` | All icon sizes, the iOS set, the Android layers and the checks, plus the copies in `kingdom/assets/generated/app_icon/`. `RERENDER=1` re-renders the Blender layers first |
| `make_logo.py` (Blender) | `store/logo/rising_ashes_logo.png` |
| `store_shots.gd` / `store_shots.tscn` | Screenshot driver: boots the real `main.tscn` (like the playtest bot) with `--quality=ultra`, stages each shot through the game's own systems, hides the debug line, supersamples HUD-less shots, and saves PNGs |
| `make_screenshots.sh` | Runs the driver: `make_screenshots.sh <outdir> <W> <H> "$(paste -sd, tools/store/shotlist.txt)"` |
| `shotlist.txt` | The 8 shots and their camera parameters |
| `make_captions.sh` + `captions.txt` | The captioned copies |
| `make_feature.sh` | The feature graphic (key art + logo) |

The capture only reads game state at runtime and changes nothing in the game's files. Two
runtime presentation tweaks, both in `store_shots.gd`: on Ultra, volumetric fog also fogs the
sky (`volumetric_fog_sky_affect` defaults to 1), which turns the clear HDRI sky flat grey, so the
driver sets it to 0 (phones never run volumetric fog); and the full-model NPC budget is raised to
48 so more villagers are fully modelled. The inn's `NPC_*` markers are populated with villagers
because the game doesn't spawn them there yet.

More runtime tweaks (all in `store_shots.gd`, no game files touched):
- **Sky**: the imported `kloofendal_43d_clear_puresky_4k.hdr` (its `.import` has
  `size_limit=2048`) decodes as an all-black texture, so the game's sky is black and the depth
  fog paints it flat grey. The driver checks the panorama at boot and, if it is black, loads the
  source `.hdr` at runtime (`STORE: sky panorama was black…` in the log). `--nosky_fix` turns
  this off. (The game itself still has the black sky until that import is fixed.)
- **Crowd sprites**: flat villager impostors look pixelated up close, so before each capture the
  crowd LOD is frozen and sprites within 32 m of the camera are dropped (`sprite_hide=<m>`,
  0 keeps them). `clear=<m>` also hides full-model villagers within that distance of the camera
  (used on `night` and `knight` so passers-by don't block the shot).
- `env_<property>=<value>` sets any `Environment` property for a shot (sticks for later shots).

Picks: `02` is burst frame 2, `05` burst frame 0. The 2688×1242 `05` is shot on its own
(`make_screenshots.sh <out> 2688 1242 "$(grep ^knight tools/store/shotlist.txt)" --seed=7`)
because the soldiers' looks depend on the RNG sequence; rerun with another `--seed` if a
soldier or villager comes out wrong. Key art for the feature graphic:
`make_screenshots.sh <out> 2048 1000 "aerial:tag=keyart:hour=11:ax=55:ay=28:az=62:alx=0:alz=-12:fov=50"`,
copy it to `store/_work/keyart_2048x1000.png`, then run `make_feature.sh`.

## Checklist: what you have to do yourself

**Accounts and legal**
- [ ] Google Play Console developer account (one-time $25; identity verification). New
      personal accounts must run a **closed test with at least 12 testers for 14 days** before
      production access.
- [ ] Apple Developer Program membership ($99/year) and App Store Connect access; sign the
      Paid Apps agreement if the game will cost money.
- [ ] Publish a **privacy policy at a public URL** (text suggestion in `listing.md`) and enter
      it in both consoles.
- [ ] Support email (both stores) and, for Apple, a support URL and optional marketing URL.
- [ ] Decide the seller/publisher name and your contact address (shown publicly on Play for
      monetised apps / trader status in the EU).

**Signing and builds**
- [ ] Create an Android **upload keystore**, keep it and its passwords outside git
      (see `docs/RELEASE.md`); enrol in **Play App Signing**.
- [ ] Build an **AAB** for Play (Gradle build in the Android preset); the current preset
      exports an APK for testing.
- [ ] Apple: signing certificate, App ID `com.risingashes.game`, provisioning profile and team
      ID, set in Godot's export dialog (never committed). iOS builds need a Mac with Xcode.
- [ ] Bump `version/code` and `application/version` for every upload.

**Store forms**
- [ ] Pricing (free or paid) and countries.
- [ ] Content rating questionnaire (IARC on Play, age rating on Apple): draft answers in
      `listing.md`.
- [ ] Play **Data safety** form and Apple **App Privacy**: "no data collected" per
      `listing.md` (re-check if you add ads, analytics or cloud saves).
- [ ] Play target audience (13+ recommended), ads declaration (no ads), app access (no login).
- [ ] Export compliance (Apple): the game uses no encryption beyond the OS, so answer "No"
      / set `ITSAppUsesNonExemptEncryption = false`.
- [ ] Optional: a promo video (YouTube link for Play; an App Preview for Apple).

**Before submitting**
- [ ] Check that the screenshots still match the current build (both stores reject misleading
      screenshots). Rerun `tools/store/make_screenshots.sh` after big visual changes.
- [ ] Make sure the `CREDITS.md` licences screen ships (it does via the preset's
      `include_filter`).
