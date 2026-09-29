# Incoming assets (to integrate)

Downloaded 2026-09-26 against `DOWNLOAD_LIST.md`, plus extra finds from a sweep of
Reddit, GitHub, itch.io, OpenGameArt and asset sites. Everything here is **free**
and licensed for **commercial use and redistribution** (the repo is public):
CC0 unless marked **CC-BY** (credit required) or OFL/MIT. Each pack keeps its
licence file. About 2.3 GB total, and no single file is over 90 MB, so there's no Git LFS.

**Formats:** glTF/GLB was kept wherever a pack has it. FBX/OBJ/Blend/Unity
duplicates were removed. Older packs without glTF keep **FBX**, which Godot 4.4
imports natively. Every `.blend`-only model now has a **`.glb` next to it**,
converted headless with Blender 5.2 (see "Round 2" below).

> Packs not yet used by the game carry a `.gdignore` (the integration convention).
> Delete a pack's `.gdignore` to enable it.

**Visual previews:** `_previews/*.jpg` holds one contact sheet per new pack (every
model rendered from a 3/4 view, with its file name). Browse these before picking assets.

## Used by the game (2026-09-29)

| Pack | Where it went | Notes |
|---|---|---|
| `quaternius/fantasy-props-megakit` (39 pieces) and `quaternius/ultimate-food` (14 pieces), CC0 | `kingdom/assets/market_goods/` (selected files copied to `source/` with licences, gdignored; atlas + one glb built by `tools/blender/make_market_goods.py`) | market stall goods, shop fronts, crate stacks; see `kingdom/assets/market_goods/README.md` |
| `polyhaven/`, `ambientcg/` textures | not used for decals: the decal library (`assets/art/decals/`) is painted procedurally by `tools/make_town_decals.py` | |

## Round 2 additions (2026-09-26, later): all `.gdignore`d until integrated

| Folder | What | Licence |
|---|---|---|
| `3dassets-dev-ai/` | 12 packs, 867 GLBs: **siege engines** (counterweight trebuchets armed/loosed, mangonel, springald, ram penthouse, siege towers, mantlets, palisade, tents, portcullis, breached walls), castle construction kit (149), tournament ground, watermill and granary, monastery, RTS faction buildings, MMO starter realm, **stables with horses** (riding, draft, pony, foal, donkey; 4 coats; standing, grazing, trotting, rearing; saddles), livestock, blacksmith forge (animated bellows, doors), melee arms, canal town and windmill. `index.json` per pack lists title, triangle count and animations (111 animated). | CC0, but **AI-generated per the source site**. Quality varies: the siege engines and buildings are good; the units are blocky. Modern items (tractor, trailers, show jumps) were removed. |
| `polypizza/` | 76 models: trebuchet, catapult, giant crossbow, tents, market stalls and scene, banners, flags, helmets, shields, bows, arrows, crossbow, horses, pigs, chickens, carts, wagons, saddle | CC0 (`cc0/`) and **CC-BY 3.0** (`cc-by/`); credits in `polypizza/LICENSE.md` |
| `opengameart/models/` (added) | battering ram, merchant tent, archery set, longbow, horse-drawn carriage, rigged dog, chicken, rooster, wooden bridge, modular castle kit (FBX), church and interior, church bell, old windmill, wooden docks (FBX/GLB), 3TD harbour, ruins and starter packs, knight statue, medieval weapon pack, 17 medieval Freeciv units (untextured) | CC0; `LICENSE.txt` in each folder |
| `opengameart/cc-by/models/` | saddle with bedroll, low-poly horses, horse rig, crossbow, catapult, Anglo-Saxon helmets and spears, market stall, animated windmill | **CC-BY 3.0**; credit line in each `LICENSE.txt` |
| `opengameart/sfx/` (added) | male adventurer voice clips, crowd shouting ambience, melee sounds, horse trotting, loopable rain | CC0 |
| `opengameart/cc-by/audio/` | horse gallop on surfaces, gallop loop, crowd cheering, Little Robot "Voices" library | **CC-BY** |
| `opengameart/music/<subfolders>`, `opengameart/cc-by/music/` | Umplix Medieval Theme and Standoff, Dowland 1597 lute (CC0), tricksntraps pack (CC0); Matthew Pablo, Alexandr Zhelanov, Viktor Kraus, Yubatake, TAD tracks (**CC-BY**) | as marked |
| `music-cc-by/` | Scott Buckley "Song Of The Forge", "Honour Among Thieves"; Alexander Nakarada "Medieval Loop One", "Medieval Chateau" | **CC-BY 4.0**; credits in `LICENSE.md` |
| `lowpolyassets/low-poly-medieval-weapons/` | 62 FBX: **siege engines**, swords, axes, maces, bows, shields, spears, farming tools | CC0 |
| `chilly-durango/retro-medieval-building-kit/` | PSX-style modular building parts and furniture (66 pieces in `_parts/`). The meshes ship with flat placeholder colours; apply the 16-colour tileable textures in `Textures/` | CC0 |
| `styloo/the-company/` | 26 low-poly medieval fantasy characters (GLB); the author recommends unlit/emission shading | CC0 |
| `fertile-soil/modular-village-pack/` | 155 OBJ village pieces: roofs, stucco walls, windows, arches, well, cart, boats, waterwheel and flume | CC0 |
| `cc0gameassets/swordtember2022/` | 30 stylised swords (Draco decompressed for Godot) | CC0 |
| `kenney/pirate-kit`, `mini-forest`, `cube-pets`, `watercraft-kit` | ships, fortress walls, animated archer and tents, animated animals, boats | CC0 |
| `quaternius/pirate-kit`, `quaternius/background-posed-humans` | ships, docks, animated characters; 28 static posed humans for crowds | CC0 |
| `polyhaven/models/` (added) | grasses, fern, nettle, dandelion, moss, 4 shrubs, root cluster, large iron gate, gothic statue | CC0 |

**Godot compatibility fixes applied:** 3dassets.dev GLBs used `KHR_mesh_quantization`
and the Swordtember GLBs used Draco. Godot 4.6 refuses both, so they were rewritten
with gltf-transform (dequantized or decompressed, geometry and animations unchanged)
and verified with a headless Godot import. The Poly Haven fir and pine trees
(478 MB and 949 MB meshes) were removed: too heavy for the game and over GitHub's limit.

**.blend conversion notes:** old (pre-2.8) files had textures outside the node tree.
These were re-linked by name with nearest-neighbour filtering, which keeps the pixel look. Prop
packs were also split into one GLB per object (`<name>_parts/`). Some OpenGameArt
files reference textures that weren't in the download (helmets, catapult, crossbow,
windmill, Freeciv units), so those render with flat material colours.

**Still missing:** no free, redistributable riding or mounted humanoid animation was
found. A sit-on-horse pose will have to be authored.

## Where to find the key things

| Need | Where |
|---|---|
| **Horses** (animated) | `quaternius/ultimate-animated-animals/glTF/Horse.gltf`, `Horse_White.gltf`; `quaternius/lowpoly-animated-animals/FBX/` (horse among the farm animals); `creatus/knight-pack-1/` (horse + cart); `opengameart/models/rigged-horse/` (.blend) |
| **Knights / soldiers / peasants** | `quaternius/modular-character-outfits-fantasy/` (knight, peasant, ranger outfits for the Universal Base Characters), `quaternius/universal-base-characters/`, `creatus/knight-pack-1/` (6 knights), `quaternius/lowpoly-animated-knight/`, `quaternius/rpg-characters/`, `quaternius/animated-men/`, `animated-women/`, `ultimate-modular-men/`, `ultimate-modular-women/`, `kaykit/character-pack-skeletons/` (enemies), `kenney/mini-characters/` (cheap crowds) |
| **Animations** | `quaternius/universal-animation-library/` + `universal-animation-library-2/` (one shared rig; sword combos, block, dodge, deaths, farming; see `Godot_Setup.png`), `kaykit/character-animations/` (KayKit rig, which matches the existing KayKit adventurers) |
| **More NPCs + animations on the UAL skeleton** | `characters/` (see `characters/README.md`): G6 villagers/blacksmith/innkeeper/hunter + modular kit, CDmir monk and old lady, and 166 extra UAL clips (bow, climb, dodge, deaths, two-handed, crossbow, fishing, social) from Mesh2Motion (CC0) and System G6 (CC0) |
| **Animals (farm and wild, unified style)** | `animals/` (see `animals/README.md`): 26 CC0 rigged animals (horses, donkey, cow, ox, sheep, pig, goat, deer, stag, fox, dogs, cats, chicken, rooster, duck, goose, pigeon, crow, rabbit, rat, fish) on one shared 256 px palette, at real-world scale, with 30 bones or fewer |
| **Meshy AI buildings and creatures** | `ai3d/meshy/` (paid Meshy plan, so no attribution): hero buildings, 5 house types and 2 market stalls, each with LOD0/LOD1; creatures in `ai3d/meshy/creatures/`; task log in `tasks.tsv` |
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
- Music by **Scott Buckley** (scottbuckley.com.au) and **Alexander Nakarada** (creatorchords.com), CC BY 4.0 (`music-cc-by/LICENSE.md`)
- OpenGameArt CC-BY music: **Matthew Pablo**, **Alexandr Zhelanov**, **Viktor Kraus** (CC BY 3.0); **Yubatake**, **TAD** (CC BY 4.0)
- OpenGameArt CC-BY audio: **congusbongus** (gallop), **AntumDeluge** (gallop loop), **Gregor Quendel** (crowd cheering), **Little Robot Sound Factory** (voices)
- OpenGameArt CC-BY models: **Ouren** (saddle), **jjmoser** (horse), **3D Art** (horse rig), **Lamoot** (crossbow), **Crossmeadow** (catapult), **Lotnik** (helmets and spears), **clericbob** (market stall), **WeaponGuy** (windmill)
- Poly Pizza CC-BY models: one credit per model used (`polypizza/LICENSE.md`)
- Every folder with a `LICENSE.txt` that says "ATTRIBUTION REQUIRED" has its exact credit line in that file
- Optional courtesy credits (CC0): Quaternius, Kenney, Kay Lousberg (KayKit), Creatus, Poly Haven, ambientCG, BigSoundBank (Joseph Sardin), OpenGameArt authors (see `opengameart/LICENSE.md`)

## Not included, and why

- **Mixamo:** needs an Adobe login, and raw files can't be redistributed in a public repo.
- **Freesound:** needs a login. Covered instead by BigSoundBank, OpenGameArt and Kenney.
- **Sonniss GDC bundle:** 20–30 GB, and its licence forbids redistributing the raw files.
- **Synty / Fab paid packs:** not free, and can't go in a public repo.
- **RG Poly "Medieval Props Small Pack":** labelled CC0, but its licence forbids redistributing the files as standalone items, so it can't go in a public repo.
- **LOWPO Fantasy Army, Amir low-poly horses:** their licences forbid redistributing the raw files (or leave it unclear).
- **Quaternius "Pro"/"Source" tiers and KayKit "Extra" tiers:** paid. The free tiers are included.

## Recommended Godot addons (MIT)

**Update 2026-09-27:** Terrain3D, Sky3D, ProtonScatter, LimboAI and Dialogue Manager (plus
GLoot, G.U.I.D.E, QuestWeaver, GodotGAS, Road Generator and GdUnit4) are now vendored in
`kingdom/addons/`; see `kingdom/DEPENDENCIES.md` and `docs/OPEN_SOURCE_AUDIT.md`. The rest of
this list is still only a recommendation.

Terrain3D (TokisanGames) for the 4 × 4 km terrain; Sky3D for day/night; Proton Scatter
or Spatial Gardener for foliage and prop painting; SimpleGrassTextured; Waterways
(rivers); Phantom Camera; Beehave or LimboAI for soldier AI; Dialogue Manager.
Shaders on godotshaders.com: "Stylized Fluffy Tree Leaves" (CC0) and "Stylized
grass with wind and deformation" (MIT).
