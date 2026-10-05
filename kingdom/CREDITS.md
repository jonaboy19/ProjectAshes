# Rising Ashes: asset credits

Everything else in the game is CC0, MIT, own work, or generated with a paid Meshy plan (no attribution required).
These CC-BY 3.0 works must be credited in the in-game credits screen:

- **Anglo-Saxons helmets and spears** by **Lotnik**, CC BY 3.0 (guard helmets) — OpenGameArt
- **Knights Character Kit** by **Jacques Fourie**, CC BY 3.0 (wooden boss shield) — https://poly.pizza/m/3r2JcOZShpE
- **Game icons** (UI buttons) by **Lorc**, **Delapouite**, **Felbrigg** — game-icons.net, CC BY 3.0

Further CC-BY packs present in `assets/incoming/` carry their own `LICENSE.txt`; add their lines here when a piece is used in the game
(see `assets/incoming/armor/README.md` and `assets/incoming/README.md` for the full credit list).

Fonts: Cinzel by Natanael Gama, SIL OFL 1.1.

## Added by the open-source audit (2026-09-27, see docs/OPEN_SOURCE_AUDIT.md)

- Chainmail texture on the Anglo-Saxon helmets by **Dejawolf** (part of Lotnik's CC BY 3.0 pack; courtesy credit as noted on the source page).
- **The Milky Way panorama** by **ESO/S. Brunier**, CC BY 4.0 (https://www.eso.org/public/images/eso0932a/), shipped inside the Sky3D addon as `Milkyway.jpg` / `StarField.jpg`; used in original and modified forms.

### Third-party code (MIT licence: the copyright notice and licence text must ship with the game, e.g. a "Licences" page)

- **Godot Engine**, (c) 2014-present Godot Engine contributors, (c) 2007-2014 Juan Linietsky, Ariel Manzur. MIT. Also include Godot's third-party notices (`Engine.get_copyright_info()` / `Engine.get_license_info()`).
- Camera shake (`scripts/actors/camera_shake.gd`) ported from **godotengine/tps-demo**, (c) 2018-present Juan Linietsky and Godot Engine contributors. MIT.
- **GLoot** (c) Peter Kish, MIT. **Dialogue Manager** (c) 2022-present Nathan Hoad and contributors, MIT. **G.U.I.D.E** (c) 2024-present Jan Thomä, MIT.
- **Quest Weaver** (Nexus Quest Weaver, github.com/undomick/godot_nexus_quest_weaver), MIT. **GodotGAS** (c) 2026 Matthew Janes (YulRun.dev), MIT.
- **LimboAI** (c) 2023-2025 Serhii Snitsaruk and contributors, MIT. **Terrain3D** (c) 2023-2026 Cory Petkovsek, Roope Palmroos and contributors, MIT.
- **Sky3D** (c) 2023-2025 Cory Petkovsek and contributors, (c) 2021 J. Cuéllar, MIT; moon map (c) 2019 GPoSM, MIT.
- **Road Generator** (c) 2024 Moo-Ack! Productions, MIT. **ProtonScatter** (c) 2019 HungryProton, MIT.

## Audio (added 2026-09-27, see `assets/audio/README.md` for every file, source and licence)

CC-BY sounds used in the game (credit required):

- **"Fantasy Sound Effects Library"** by **Little Robot Sound Factory** (www.littlerobotsoundfactory.com), CC BY 3.0 — goblin voices, wyvern screeches, coin, menu and fanfare jingles. https://opengameart.org/content/fantasy-sound-effects-library
- **"Footsteps on different surfaces"** by **congusbongus**, CC BY 3.0 — cobblestone footsteps. https://opengameart.org/content/footsteps-on-different-surfaces
- **"Five Armies"** and **"Heroic Age"** by **Kevin MacLeod** (incompetech.com), Licensed under Creative Commons: By Attribution 4.0 License (http://creativecommons.org/licenses/by/4.0/) — boss music and the victory stinger.
- Music by **North Fantasy Music** ("Dark and Mysterious", "New Dawn" from "Fantasy Music and Drum Loops Pack"), CC BY 4.0 — danger / stalk music and the discovery stinger. https://opengameart.org/content/fantasy-music-and-drum-loops-pack

CC0 / public domain (no attribution required; credited with thanks):

- Nature, village, animal, fire, weather and foley recordings by **Joseph Sardin, BigSoundBank** (bigsoundbank.com), CC0.
- **Kenney** (kenney.nl): Impact Sounds, RPG Audio, Interface Sounds, UI Audio, Music Jingles, CC0.
- OpenGameArt CC0: **rubberduck** (80 creature SFX, 100 SFX), **StarNinjas** (sword attacks and clashes), **artisticdude** (RPG Sound Pack, Swishes), **Ogrebane** (battle SFX), **remaxim** (3 melee sounds), **wolfwoot** (Male Adventurer voice clips), **Wolfgang_** (crickets loop), **Ylmir** (rain loop).
- Music (OpenGameArt, CC0): **RandomMind** (Market Day, Minstrel Dance, The Old Tower Inn, The Bard's Tale, King's Feast), **cynicmusic** (Battle Theme A; cynicmusic.com, pixelsphere.org), **Umplix** (Medieval Theme, Medieval Standoff), **Of Far Different Nature** (John Dowland, "If my complaints could passions move", 1597).
- Bellows and spider hiss: generated for the game (filtered noise), no third-party audio.
- Adaptive music percussion stems: synthesized for the game, no third-party audio. Bird, cricket and thunder spots cut from BigSoundBank and Wolfgang_ recordings above (CC0). See `assets/audio/music_interactive/CREDITS.md`.

## Breakable props (added 2026-09-28)

- Breakable barrels, crates and baskets (`scripts/world/breakable.gd`) follow the approach of **godot-destruction-plugin** by **Jummit and contributors** (https://github.com/Jummit/godot-destruction-plugin), (c) 2023 Jummit, MIT: swap the intact prop for cached shard meshes/shapes thrown as rigid bodies, then shrink them out. Rewritten in our style with runtime mesh slicing instead of pre-fractured scenes; no plugin code ships.

## Grass and water shaders (added 2026-09-28)

- `shaders/grass.gdshader`: clump colour/height noise, view-space blade widening, fake subsurface backlight and wind turbulence are ideas from **GodotGrass** by **Ethan Truong (2Retr0)**, (c) 2024, MIT (https://github.com/2Retr0/GodotGrass). Reimplemented for our card clumps; no code copied, but credited under its MIT licence.
- `shaders/water.gdshader`: interaction ripples and shoreline foam bands draw on ideas from **Stylized-Water-Shader** by **Malidos**, CC0 (https://github.com/Malidos/Stylized-Water-Shader). Credited with thanks; no code copied.

## Procedural animation (added 2026-09-28)

- Foot IK in `scripts/actors/procedural_rig.gd` (one downward ray per foot, the hips lowered to the lower foot, feet aligned to the ground normal) follows the approach of **Godot-Foot-IK** by **SeaKrill** (https://github.com/SeaKrill/Godot-Foot-IK), (c) 2023 SeaKrill, MIT. Reimplemented in our style on Godot 4.6's `TwoBoneIK3D`, `LookAtModifier3D` and `SpringBoneSimulator3D` nodes; no code copied, credited under its MIT licence.

## Villager utility AI (added 2026-09-28)

- `scripts/population/utility_brain.gd` follows the design of two MIT utility-AI addons for Godot: **godot-utility-ai** by **John Pennycook** (https://github.com/Pennycook/godot-utility-ai), (c) 2023 John Pennycook, MIT (considerations mapped through binary/linear/exponential/logistic response curves, behaviours aggregated as a product, the best option chosen), and **godot-utility-ai** by **Vinicius Gerevini** (https://github.com/viniciusgerevini/godot-utility-ai), (c) 2023 Vinicius Gerevini, MIT (an agent's actions each scored by multiplied considerations, the top action handed to the game to execute). Reimplemented lean as a const action table with pure static scoring; no code copied, credited under their MIT licences. The product compensation factor is from Dave Mark and Rez Graham, "An Introduction to Utility Theory" (Game AI Pro, ch. 9).

## Living-world ambience (added 2026-09-28)

- `scripts/world/ambient_fx.gd` with `shaders/ambient_*.gdshader` (bird flocks, fireflies, butterflies, falling leaves, dust motes, chimney embers, fish jumps and a school of fish): written for the game. All sprites and silhouettes are procedural (drawn in the shaders or built as meshes in code); no third-party textures or code are used, so nothing was vendored under `assets/incoming/vfx/ambient/`.

## Ragdolls (added 2026-09-28)

- `scripts/actors/ragdoll.gd` (physical deaths and knockdowns) follows the approach of the **3D Ragdoll Physics** demo in **godot-demo-projects** (https://github.com/godotengine/godot-demo-projects/tree/master/3d/ragdoll_physics), (c) 2014-present Godot Engine contributors, MIT: a `PhysicalBoneSimulator3D` under the skeleton, `physical_bones_start_simulation()` and blending its `influence`. Rewritten for our rigs: capsules and joints are built at runtime from the current pose instead of an editor-made physical skeleton; no demo code ships.

## Magic and martial-arts VFX (added 2026-09-28)

- `assets/incoming/vfx/atlas/vfx_atlas.png` (used by `scripts/vfx/` and `shaders/vfx_*.gdshader`) packs 14 sprites from the **Particle Pack** by **Kenney** (www.kenney.nl), CC0, via https://github.com/Calinou/kenney-particle-pack, and 2 textures (radial streaks, swirl) from **Godot-particle-and-vfx-textures** by **Raffaele Picca** (raffaelepicca.com), CC0 (https://github.com/RPicster/Godot-particle-and-vfx-textures). Credit isn't required for CC0 but is given with thanks. Originals and licences are in `assets/incoming/vfx/`.
- `shaders/vfx_fx.gdshader` and `shaders/vfx_ghost.gdshader`: the noise dissolve with a glowing burn edge, the fresnel rim and the UV twist ideas come from **VFEZ-godot** by **Alexander Nikopoulos**, (c) 2025, MIT (https://github.com/alexnikop/VFEZ-godot). The noise-distorted three-colour slash gradient comes from the **Fiery Slash Shader for Godot** by **Priyansh Singh**, (c) 2026, MIT (https://github.com/priyanshsingh102005/Fiery-Slash-Shader-for-Godot-Dynamic-Sword-Trail-VFX-3D-). Both were rewritten in our style, with no code copied, and are credited under their MIT licences. Reference copies with the licence texts are in `assets/incoming/vfx/vfez_reference/` and `fiery_slash_reference/`.
- The rune-circle, crack, tear, orb, column and impact-frame shaders and `vfx_noise.png` were written for the game.

## Combat, magic and martial-arts animations; souls-like foley (added 2026-09-28)

- Souls-like combat, magic-casting, parry, roll and interaction animations (`assets/incoming/animations/souls_cat/`) and the foley SFX in `assets/audio/sfx_souls/` are from the **Modular Souls-like Template** by **Cat Prisbrey** (https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template), Unlicense / CC0. Credit isn't required but is given with thanks. The clips were retargeted onto the UAL skeleton.
- Karate, tai chi, swordplay, swimming, chore and lie-down motion (`assets/incoming/animations/cmu_mocap/`): "Motion capture data from the **CMU Graphics Lab Motion Capture Database** (mocap.cs.cmu.edu), created with funding from NSF EIA-0196217." BVH conversion by **Bruce Hahne** (cgspeed.com). Free for research and commercial use, with no restrictions; the credit line is the one CMU requests.
- Bending clips (`assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb`, 36 Water/Air/Earth/Fire/Lightning/guard clips): same CMU credit line as above, same terms (see `assets/incoming/mocap/cmu/LICENSE`). Not yet used in the game; list the line once they are.
- Bending VFX lab (`scenes/vfx_lab/`): techniques re-written from the MIT-licensed sandbox `achrefelouafi/AvatarCastingAbilitiesThreeJS` (c) 2026 mohamedachrefelouafi (no code copied; courtesy credit, not required).

## Locomotion styles (added 2026-09-28)

- **"100STYLE Dataset"** by **Ian Mason, Sebastian Starke and Taku Komura** (University of Edinburgh), CC BY 4.0 (https://ianxmason.github.io/100style/), retarget rig by **Daniel Holden** (https://github.com/orangeduck/100style-retarget/). 14 clips (walk/run/strafe/backward/sprint/start/stop/turn-in-place plus March, Old, Wounded, Sneak, Shielded and Unarmed-Punch-Idle style variants) retargeted onto the UAL skeleton in `assets/incoming/characters/_library/UAL_Extra_100STYLE.glb`. Only the BVH motion channels were used, never the "Geno" mesh that ships in the same repo (that mesh is separately marked non-commercial-research-only; it was not downloaded or used). See `assets/incoming/characters/100style-retarget/LICENSE.txt`.

## World database (added 2026-09-28)

- `addons/godot-sqlite/` (`kingdom/addons/godot-sqlite/`) is **godot-sqlite** by **Piet Bronders & Jeroen De Geeter**, (c) 2019-2026, MIT (https://github.com/2shady4u/godot-sqlite), vendored at release v4.8 ("Update to Godot 4.6.3"). Vendored binaries: Windows x86_64 (debug + release), Linux x86_64 (debug + release), macOS (debug + release), Android arm64-v8a + x86_64 (debug + release) and iOS arm64 device (debug + release, simulator slices stripped to keep files small); the web/wasm binaries were not vendored (not needed for a mobile/desktop build). Upstream has never shipped an armeabi-v7a (32-bit ARM Android) binary for any Godot 4 GDExtension release; `scripts/core/world_db.gd` degrades gracefully on that architecture (see its header comment) and the game still exports `armeabi-v7a` for older phones. `scripts/core/world_db.gd` is a small first-party wrapper around it (open/exec/query/transactions); it is vendoring only and is not yet wired into the save system.

  ```
  MIT License

  Copyright (c) 2019-2026 Piet Bronders & Jeroen De Geeter

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  ```

## Market goods (added 2026-09-29, see `assets/market_goods/README.md`)

CC0 (no attribution required; credited with thanks): 53 market props (39 + 14 pieces) from **Quaternius'** *Fantasy Props MegaKit* and *Ultimate Food Pack*
(https://quaternius.com), re-authored into one warm-painted atlas (`assets/market_goods/`).

## In-game tabbed menu icons (added 2026-09-29)
- **Game icons** for the inventory, character, skills, quest, map and journal menu (assets/ui/icons/gm and assets/ui/icons/items) from game-icons.net, CC BY 3.0, recoloured to white. Authors: **Lorc**, **Delapouite**, **Skoll**, **Willdabeast**, **Caro Asercion**, **Irongamer**, **SBed**, **Seregacthtuf**, **Zeromancer**.

### Free addons added 2026-09-29 (local PC session; see `docs/addons/README.md`)
- **Phantom Camera** (c) 2023-2026 Marcus Skov (ramokz), MIT (https://github.com/ramokz/phantom-camera), v0.11.0.3, `kingdom/addons/phantom_camera/`.
- **Godot Debug Menu** (c) 2022-2025 Hugo Locurcio and contributors (Calinou), MIT (https://github.com/godot-extended-libraries/godot-debug-menu), `kingdom/addons/debug_menu/`.
- **Godot Material Footsteps** (c) 2025 COOKIE-POLICE, MIT (https://github.com/COOKIE-POLICE/godot-material-footsteps), v1.0.0, `kingdom/addons/godot_material_footsteps/`.
- **SimpleGrassTextured** (c) 2023-2026 IcterusGames, MIT (https://github.com/IcterusGames/SimpleGrassTextured), v2.1.0, `kingdom/addons/simplegrasstextured/`. Its bundled demo texture `textures/grassbushcc008.png` has no recorded source, so it must not ship: use our own grass texture.
- **VoronoiShatter** (c) Robert Varadan, MIT (https://github.com/robertvaradan/voronoishatter), v0.3, `kingdom/addons/voronoishatter/`.
- **Sentry SDK for Godot** (c) Functional Software, Inc. dba Sentry, MIT (https://github.com/getsentry/sentry-godot), v2.2.0. Installed on demand by `tools/install_sentry.sh` (binaries are not committed); no data is sent without a DSN.
- Octahedral impostors (`kingdom/tools/impostors/impostor_baker.gd`, `kingdom/assets/generated/impostors/impostor_octa.gdshader`) are our own implementation of the public octahedral-impostor technique (Ryan Brucks / Shaderbits, https://www.shaderbits.com/blog/octahedral-impostors); the MIT **Godot-Octahedral-Impostors** by wojtekpil (https://github.com/wojtekpil/Godot-Octahedral-Impostors) and its Godot 4.0 port (belzecue) were evaluated as references but not used (they don't run on 4.6). No code copied.
- **KayKit Character Animations 1.1** (Kay Lousberg, https://kaylousberg.com), CC0 1.0. Clips retargeted to the UAL skeleton in `kingdom/assets/incoming/animations_free2/kaykit_*` (prefix `Kay_`); licence copy `animations_free2/LICENSE_KayKit.txt`. Credit optional: "Kay Lousberg, www.kaylousberg.com".
- Traversal clips (ladder, wall, ledge, vault, horse riding) in `animations_free2/traversal_authored/` are our own Blender-IK authored work on the CC0 Quaternius UAL rig.

## Region 1 art: stones and Highwatch Keep kit (added 2026-09-29, work packages L1 and L2)

* `assets/incoming/region1/stones/` (Elder Stone, 4 road stones, ancestor-gold variants): built entirely in Blender by the local session
  (`tools/blender/region1/*.py`); no third-party meshes or textures. Textures are procedurally painted by our scripts. Our own work, released CC0-style with the project.
* `assets/incoming/region1/highwatch/` (Highwatch Keep kit): re-baked/re-graded from **Meshy community models, CC0 1.0** (see
  `assets/incoming/meshy_free/CREDITS.md`; each verified `license: cc0` on its Meshy page): `gate_twin_towers_blue`, `tower_round`,
  `watchtower_stone_small`, `keep_small_on_plinth` (castle), `weapon_rack_swords`, `weapon_racks_spears`, `armour_stand_knight` (interior),
  `shield_dragon_heraldic`, `barrels_crates_stack`, `well_stone_roofed` (props), `torch_stake` (lighting), `hay_bale_lowpoly` (farm).
  Modifications: uniform re-scale, one shared 2048 atlas, colour grading to the Highwatch palette (blue/gold recolour), LOD1 (shipped Meshy LOD1 or decimated).
  Blender-built connectors (curtain wall, banners, conical roofs, training dummies, archery targets, yard, fence) are our own work with procedurally painted textures.
  No attribution is required; credited with thanks to the anonymous Meshy community authors.
## Region 1 audio (added 2026-09-29, L17; full table in `assets/audio/region1/LICENSES.md`)

Credit required (CC BY 4.0, https://creativecommons.org/licenses/by/4.0/):

- "Folk Round", "Minstrel Guild", "Achaidh Cheide", "Lost Time", "Suonatore di Liuto", "Crusade", "Bittersweet", "Skye Cuillin" and "Long Road Ahead" Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution 4.0 License. Region 1 village/farm, guild town, Stagborn glade, rift-touched wilds, night and Antlered Warden boss themes, plus the Region 1 story cues (lament, Kindling Night, finale).
- "Medieval Chateau" by Alexander Nakarada (CreatorChords) | https://creatorchords.com , Royalty Free Music by https://www.free-stock-music.com , Creative Commons / Attribution 4.0 International (CC BY 4.0) https://creativecommons.org/licenses/by/4.0/ . Highwatch Keep theme.

CC0 (credited with thanks):

- Region 1 male barks: "Voice Clip Pack - Male Adventurer RPG" by wolfwoot (Brandon Song), https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg
- Region 1 female barks: "Female RPG Voice Starter Pack" by cicifyre, https://opengameart.org/content/female-rpg-voice-starter-pack
- Stagborn calls layered from Joseph Sardin (BigSoundBank) recordings and the ward-break glass from rubberduck's "100 CC0 SFX".
- Rune hum, ward activate, glyph carve and the Ashen Scar ambience are synthesised for the game (no third-party audio).

### VFX tools added 2026-09-29 (local PC session; see `docs/art/vfx_tools/README.md`)
- **Effekseer for Godot 4** (c) 2020 Effekseer Project, MIT (https://github.com/effekseer/EffekseerForGodot4), v1.80.5.1, `kingdom/addons/effekseer/` (Windows x64 and Android arm32/arm64 binaries only; iOS/macOS/Linux/Web libraries left out, see `tools/vfx/README.md`). Not enabled as an editor plugin, not used by gameplay code.
- **Effekseer sample effect "Aura01"** (Effekseer editor 1.80.7, `Sample/00_Version16`), CC0, credit to Effekseer, `kingdom/assets/vfx/effekseer/`.
- Six baked VFX flipbooks in `kingdom/assets/vfx/flipbooks/` are original project work (Blender + numpy scripts in `tools/vfx/`), no third-party content.
## Stagborn elk and Antlered Warden (added 2026-09-29, L5; see `assets/incoming/ai3d/meshy/creatures/stagborn_README.md`)
- **Quaternius**, *Ultimate Animated Animals* **Stag** (mesh, rig and stock clips: idle, walk, gallop, headbutt, kick, hit, death, eating), **CC0 1.0** (https://quaternius.com, https://creativecommons.org/publicdomain/zero/1.0/; licence file `assets/incoming/quaternius/ultimate-animated-animals/License.txt`). No attribution required; credited with thanks.
- Customisation (Warden antlers, mane, body proportions, painted and rune-emissive textures, authored `attack`, `run_charge` and `roar` clips, retiming, LOD1): own work for Rising Ashes. No Meshy credits and no other third-party material were used.

## Region 1 art: Silverford guild hall, Dawn Throne chapel, rift kit (added 2026-09-29, work packages L3 and L4)

* `assets/incoming/region1/silverford/`: re-graded from **Meshy community models, CC0 1.0** (`meshy_free/buildings/house_two_story_shingle`, `meshy_free/churches/church_white_red_spire`; each verified `license: cc0`, see `assets/incoming/meshy_free/CREDITS.md`). Modifications: HSV recolour of the baked texture (royal-blue roof; white stone with gold roofs), added hand-built banners, sign and Dawn Throne sun emblem, uniform re-scale, LOD1 from the shipped Meshy LOD1. Scripts: `tools/blender/make_r1_exteriors.py`.
* `scenes/interiors/guildhall_interior.tscn`, `chapel_interior.tscn` and their GLBs: Blender-built with the project interior kit; furniture pieces from **Quaternius Fantasy Props MegaKit, CC0 1.0** (already credited above). Everything else is our own work.
* `assets/incoming/region1/rift/`: textures are recolours of the project's own region nature atlases and of the Meshy-generated wolf and boar textures (our own work / the paid Meshy plan, no attribution needed); `crystals/` are re-cut and re-tinted from **Meshy community models, CC0 1.0** (`meshy_free/magic/crystal_purple_pedestal`, `crystal_cyan_pedestal`, `crystal_ice_shard`, pedestals removed); decals are procedural (own work). Scripts: `tools/blender/make_rift_*.py`, `make_scar_crystals.py`.

## Horses and riding (added 2026-09-30; see `docs/anim/horses/HANDOFF.md`)
- **Mesh2Motion** horse mesh (`assets/incoming/characters/mesh2motion/horse-animations.glb`, Scott Petrovic), **CC0** (https://github.com/Mesh2Motion/mesh2motion-app): body shape of the riding horse. Re-welded, subdivided and decimated, old tail removed; new mane, tail, skeleton, skinning, coats, tack, LODs and all 50 horse clips and 57 rider clips are own work (procedural Blender pipeline in `tools/anim/horse/`).
- Skeleton layout from the **Rigify** horse metarig (Blender, GPL tool; generated rigs and output are unencumbered). Gait timings follow published equine biomechanics (footfall order and duty factors), no mocap.

* `assets/incoming/meshy_dl3/` (97 GLBs: town houses, castles, props, magic items, elementals, horse, rigged and static medieval characters): **owner-downloaded Meshy models, licence per the owner's Meshy plan**; re-baked/decimated, rigs kept. See `assets/incoming/meshy_dl3/CREDITS.md` and `docs/art/meshy_dl3/README.md`.
- Poly Haven `rock_face` (CC0) - Rift / cave rock shells (shaders/environment/cave_rock.gdshader)
