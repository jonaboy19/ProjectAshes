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
