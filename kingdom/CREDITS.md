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
