# Blender add-ons (Blender 5.2.0 LTS) - Rising Ashes

Blender: `C:\Program Files\Blender Foundation\Blender 5.2`
User config: `%APPDATA%\Blender Foundation\Blender\5.2`
Downloads (zips + helper scripts): `C:\Users\Jonna\Tools\blender-downloads\`
Updated: 2026-10-26

## Installed and enabled (this session, verified headless)

| Add-on | Version | Source | Licence | How enabled | Use in Rising Ashes |
|---|---|---|---|---|---|
| Rigify | 0.6.10 (bundled) | Bundled with Blender (`scripts/addons_core/rigify`) | GPL-3.0+ | Enabled in prefs | Auto-rig humanoid/creature skeletons, control rigs for animation |
| AnimAll | 0.14.0 | https://extensions.blender.org/add-ons/animall/ (Blender 5.0+) | GPL-3.0+ | Extension, repo `user_default` | Keyframe mesh/shape/vertex data (facial, soft-body style deformation) |
| Copy Attributes Menu | 0.6.3 | https://extensions.blender.org/add-ons/copy-attributes-menu/ | GPL-3.0+ | Extension, repo `user_default` | Copy transforms/modifiers/constraints between objects or bones (Ctrl+C in 3D view) |
| TexTools | 1.6.1 (as `TexTools_1_6_1`, legacy add-on) | https://github.com/franMarz/TexTools-Blender/releases/tag/v1.6.1 (continuation of SavMartin/TexTools-Blender) | GPL (LICENSE.txt is GPL) | Legacy add-on in `scripts/addons/TexTools_1_6_1` | UV tools, texel density, atlas/bake helpers for creature and prop textures. Panel: UV Editor > Sidebar > TexTools. Operators register fine on 5.2; a harmless KeyError is logged when Blender exits (unregister of the icon previews). |

Downloaded zips: `animall.zip`, `copy_attributes_menu.zip` (SHA-256 matched the extension index), `TexTools_1_6_1.zip`.

## Skipped

- **Animation Layers (Tal Hershkovich)**: no free official release. It is sold on Superhive/Blender Market (GPL, ~$30, supports 3.2-5.1; not on extensions.blender.org, no public GitHub release). Not installed since it is not a free source; buy it if wanted, or use NLA + Blender's built-in animation layers features.
- **Godot Game Tools (vini-guerrero)**: the repo named `godot-game-tools` is not reachable (404), the only matching add-on found is GPL-2.0 (not MIT), last updated 2022, with no 5.x release. Skipped. Alternatives on extensions.blender.org that are installable on request: "Goblend: Export to Godot" (`goblend`), "Game Tools" (`blender_game_tools`, GPL-3.0+), "PROTO Game Asset Tools".
- **Bone Selection Sets**: not in the official extensions list and not bundled in Blender 5.2, so nothing to install.

## Pre-existing (not touched, status checked)

| Add-on | Version | Source | Licence | State / how to enable | Use |
|---|---|---|---|---|---|
| MPFB | 2.0.17 | http://static.makehumancommunity.org/mpfb.html (extension `user_default/mpfb`) | GPL (see its manifest) | Installed + enabled | Generate human characters (MakeHuman pipeline) |
| Expy Kit | 0.6.1 | https://github.com/ (Paolo Acampora, Balls & Ninjas), folder `C:\Users\Jonna\Tools\blender-addons\addons\expy_kit` | GPL | NOT enabled in prefs. Enable via Preferences > Add-ons > Install from Disk / add that folder to Preferences > File Paths > Scripts | Retarget/remap rigs, Mixamo-style skeleton conversion, game export |
| Bone Dynamics | 1.3.0 | Folder `...\blender-addons\addons\bone_dynamics` (maintainer Experience Elysian) | GPL-3.0+ | NOT enabled (extension-format manifest; install with `blender.exe -b --command extension install-file -r user_default -e <zip>` or from folder) | Spring physics on bone chains (tails, capes), bakeable |
| Wiggle 2 | 2.2.3 | `...\blender-addons\addons\wiggle_2.py` (Steve Miller) | GPL-3.0+ | Prefs reference `bl_ext.user_default.wiggle_2` but it is NOT installed there, so Blender prints "Add-on not loaded" at start. Install it as an extension/legacy add-on to clear the warning | Secondary-motion jiggle on bones |
| ANT Landscape | - | Not found on disk in Blender 5.2 or user config | GPL | Not installed (not found; install from extensions.blender.org `ant_landscape` if needed) | Procedural terrain |
| dcc_mcp_blender | 0.2.12 | https://github.com/dcc-mcp/dcc-mcp-blender, files in `C:\Users\Jonna\Tools\dcc-mcp\blender-site` | MIT | Python site-package, loaded via the dcc-mcp setup (not a Blender prefs add-on) | MCP bridge so agents can drive Blender |

## Commands

- List extensions: `blender.exe -b --command extension list`
- Install extension zip: `blender.exe -b --command extension install-file -r user_default -e <zip>`
- Enable a legacy add-on headless: `blender.exe -b --python-expr "import addon_utils,bpy; addon_utils.enable('<module>',default_set=True,persistent=True); bpy.ops.wm.save_userpref()"`
- Verify: `blender.exe -b --python-expr "import bpy; print(sorted(bpy.context.preferences.addons.keys()))"`
