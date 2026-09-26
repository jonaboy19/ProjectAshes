# Incoming assets (to integrate)

Downloaded 2026-09-26 against `DOWNLOAD_LIST.md`, plus extra finds from a sweep of
Reddit, GitHub, itch.io, OpenGameArt and asset sites. Everything here is **free**
and licensed for **commercial use and redistribution** (the repo is public):
CC0 unless marked **CC-BY** (credit required) or OFL/MIT. Each pack keeps its
licence file. About 2.3 GB total, and no single file is over 90 MB, so there's no Git LFS.

**Formats:** glTF/GLB was kept wherever a pack has it. FBX/OBJ/Blend/Unity
duplicates were removed. Older packs without glTF keep **FBX**, which Godot 4.4
imports natively. A few OpenGameArt models are `.blend` only (these need Blender for
import, or a one-time export to glTF).

> Godot imports everything under `res://`. This folder is large, so the first
> editor open will take a while. If needed, drop a `.gdignore` into packs you're
> not using yet.

## Where to find the key things

| Need | Where |
|---|---|
| **Horses** (animated) | `quaternius/ultimate-animated-animals/glTF/Horse.gltf`, `Horse_White.gltf`; `quaternius/lowpoly-animated-animals/FBX/` (horse among the farm animals); `creatus/knight-pack-1/` (horse + cart); `opengameart/models/rigged-horse/` (.blend) |
| **Knights / soldiers / peasants** | `quaternius/modular-character-outfits-fantasy/` (knight, peasant, ranger outfits for the Universal Base Characters), `quaternius/universal-base-characters/`, `creatus/knight-pack-1/` (6 knights), `quaternius/lowpoly-animated-knight/`, `quaternius/rpg-characters/`, `quaternius/animated-men/`, `animated-women/`, `ultimate-modular-men/`, `ultimate-modular-women/`, `kaykit/character-pack-skeletons/` (enemies), `kenney/mini-characters/` (cheap crowds) |
| **Animations** | `quaternius/universal-animation-library/` + `universal-animation-library-2/` (one shared rig; sword combos, block, dodge, deaths, farming; see `Godot_Setup.png`), `kaykit/character-animations/` (KayKit rig, which matches the existing KayKit adventurers) |
| **Full cities (modular)** | `quaternius/medieval-village-megakit/` (walls, roofs, doors, windows, stairs), `quaternius/modular-medieval-buildings/`, `quaternius/medieval-village-pack/`, `quaternius/ultimate-textured-buildings/`, `quaternius/ultimate-fantasy-rts/` (barracks, archery, houses by age/level), `kenney/fantasy-town-kit/`, `kenney/retro-fantasy-kit/` |
| **Castles / ruins / dungeons** | `kenney/castle-kit/`, `quaternius/ultimate-modular-ruins/`, `quaternius/medieval-dungeon/`, `kaykit/dungeon-remastered/`, `kenney/modular-dungeon-kit/`, `polyhaven/models/large_castle_door/` |
| **Nature** | `quaternius/stylized-nature-megakit/`, `kaykit/forest-nature-pack/`, `kenney/nature-kit/`, `quaternius/textured-lowpoly-trees/`, `quaternius/ultimate-crops/` (farm fields), Poly Haven stumps/rocks |
| **Weapons / props / economy** | `quaternius/fantasy-props-megakit/`, `quaternius/lowpoly-medieval-weapons/`, `kaykit/fantasy-weapons-bits/`, `kaykit/rpg-tools-bits/`, `kaykit/resource-bits/`, `quaternius/ultimate-rpg-items/` (with icons), `quaternius/ultimate-food/`, `quaternius/survival/`, `quaternius/lowpoly-farm-buildings/`, `kaykit/furniture-bits/`, `kaykit/restaurant-bits/`, `kenney/survival-kit/`, `kenney/graveyard-kit/`, `quaternius/ships/`, `opengameart/models/` (pixel-textured cart, trough, hitching post, tavern) |
| **Photoreal props** (1K glTF, 48) | `polyhaven/models/`: kite shield, medieval dagger/mace, castle door, lanterns, barrels, crates, buckets, baskets, axes, tools, spinning wheel, bowls, jugs, stools, tables, benches, pier, stumps, mossy rocks |
| **Sky / lighting** | `polyhaven/hdris/`: 4K `.hdr`: clear (kloofendal_43d), partly cloudy (kloofendal_48d), overcast (kloofendal_overcast), 2 sunsets (qwantani, belfast) |
| **Terrain textures** (2K) | `polyhaven/textures/`: forest_ground_04, forest_leaves_02, leafy_grass, sparse_grass, grass_path_2, dirt, rocky_terrain_02, brown_mud_02, cobblestone_floor_01, grassy_cobblestone |
| **Building textures** (2K) | `polyhaven/textures/`: castle_brick_07, castle_wall_slates, medieval_blocks_02, mossy_stone_wall, clay_plaster, damaged_plaster, brown_planks_05, medieval_wood, clay_roof_tiles, red_slate_roof_tiles_01, thatch_roof_angled, reed_roof_04. Also `ambientcg/`: fabrics for banners/tabards, roofing tiles, wood siding, planks, bark (each with a Godot `.tres` material). Poly Haven maps: `diff`, `nor_gl`, `arm` (= Godot ORM), `disp` |
| **Music** | `incompetech/` (12 Kevin MacLeod tracks, **CC-BY**; the licence file suggests village/tavern/battle/castle/night picks), `opengameart/music/` (RandomMind seamless loops: Market Day, Minstrel Dance, King's Feast, Bard's Tale, Old Tower Inn; cynicmusic battle theme; CC0), `opengameart/cc-by/fantasy-music-drum-loops-northfantasymusic/` (**CC-BY**), `kenney/music-jingles/` |
| **Combat SFX** | `opengameart/sfx/` (sword swings and clashes, swishes, battle SFX, wood/metal impacts, soldier yells, death/pain grunts), `bigsoundbank/` (sword, sword cut, whooshes), `kenney/impact-sounds/`, `kenney/rpg-audio/`, `kenney/voiceover-pack-fighter/` |
| **Horse / town SFX** | `bigsoundbank/`: gallop, trot, walk, neighs, breath, hooves, chewing hay, anvil/blacksmith, church bell, bell tower, herd bells |
| **Ambience** | `opengameart/ambience/` (forest day, night crickets), `opengameart/cc-by/nature-ambient-pack-vol1-jcsounds/` (**CC-BY**), `opengameart/cc-by/fantasy-sound-library-littlerobotsoundfactory/` (**CC-BY**), `opengameart/cc-by/footsteps-congusbongus/` (**CC-BY**) |
| **UI** | `fonts/` (Cinzel, IM Fell English + SC, MedievalSharp, Almendra; OFL), `kenney/ui-pack-rpg-expansion/`, `kenney/fantasy-ui-borders/`, `kenney/game-icons/`, `kenney/cursor-pack/`, `kenney/medieval-rts/` (2D unit and minimap icons), `game-icons/` (4000+ SVG icons, **CC-BY**), `kenney/ui-audio/`, `kenney/interface-sounds/` |
| **VFX** | `kenney/particle-pack/`, `kenney/smoke-particles/`, `kenney/splat-pack/` (blood/dirt decals) |
| **Shaders** | `shaders/pixelart-outline-leopeltola/` (MIT; 3D pixel-art outline/highlight post-process, built for this kind of renderer) |

## Attribution required (CC-BY): put these in the credits screen

- Music by **Kevin MacLeod** (incompetech.com), CC BY 4.0 (one line per track used; see `incompetech/LICENSE.txt`)
- "Fantasy Music and Drum Loops" by **NorthFantasyMusic**, CC BY 4.0
- "Nature Ambient Pack Vol 1" by **JC Sounds**, CC BY 4.0
- "Fantasy Sound Effects Library" by **Little Robot Sound Factory**, CC BY 3.0
- "Footsteps on different surfaces" by **congusbongus**, CC BY 3.0
- Icons from **game-icons.net** (Lorc, Delapouite and contributors), CC BY 3.0
- Optional courtesy credits (CC0): Quaternius, Kenney, Kay Lousberg (KayKit), Creatus, Poly Haven, ambientCG, BigSoundBank (Joseph Sardin), OpenGameArt authors (see `opengameart/LICENSE.md`)

## Not included, and why

- **Mixamo:** needs an Adobe login, and raw files can't be redistributed in a public repo.
- **Freesound:** needs a login. Covered instead by BigSoundBank, OpenGameArt and Kenney.
- **Sonniss GDC bundle:** 20–30 GB, and its licence forbids redistributing the raw files.
- **Synty / Fab paid packs:** not free, and can't go in a public repo.
- **RG Poly "Medieval Props Small Pack":** labelled CC0, but its licence forbids redistributing the files as standalone items, so it can't go in a public repo.
- **LOWPO Fantasy Army, Amir low-poly horses:** their licences forbid redistributing the raw files (or leave it unclear).
- **Quaternius "Pro"/"Source" tiers and KayKit "Extra" tiers:** paid. The free tiers are included.

## Recommended Godot addons (MIT; not vendored, add through the AssetLib if wanted)

Terrain3D (TokisanGames) for the 4 × 4 km terrain; Sky3D for day/night; Proton Scatter
or Spatial Gardener for foliage and prop painting; SimpleGrassTextured; Waterways
(rivers); Phantom Camera; Beehave or LimboAI for soldier AI; Dialogue Manager.
Shaders on godotshaders.com: "Stylized Fluffy Tree Leaves" (CC0) and "Stylized
grass with wind and deformation" (MIT).
