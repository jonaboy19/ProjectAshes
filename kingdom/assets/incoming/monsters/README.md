# Monsters (CC0 packs, harmonised with the Meshy creatures)

These are secondary monsters that add variety alongside the 8 Meshy creatures in `../ai3d/meshy/creatures/`.
They come from free Quaternius packs (all CC0). Each one was retextured with a hand-painted 512 px texture
(mottling, directional brush and fur strokes, cavity AO, a painted top light, a darker foot-to-head gradient,
cool shadow tint and painted eyes), reshaped where needed, set to real-world scale, and checked in renders
next to the Meshy goblin and wolf.

- Files: `quaternius/<name>.glb` (LOD0, ≤ 8k tris, 512 px) and `<name>_lod1.glb` (≤ 2.5k tris, 256 px). Both
  have the same skeleton and clips. The GLBs have no Draco or meshopt compression, embedded JPEG textures,
  ≤ 40 bones and ≤ 4 influences per vertex.
- Orientation and origin match the Meshy creatures: metres, origin on the ground under the body, facing the same way as
  `wolf.glb`.
- **Flyers** (`giant_wasp`, `rift_wraith`) have their hover height built in: the body floats that high
  above the origin. Put the origin on the terrain.
- **Clip names match the Meshy creatures:** `idle`, `walk`, `run`, `attack`, `hit`, `death`, plus a few extras.
  Timings are the pack's own and weren't changed. Where a pack lacked a clip, the table says
  whether it's an **alias** (a same-timing copy of another clip) or **synth** (a short procedural clip built from the idle
  pose: hit is a 0.46 s recoil, and the ghoul's death is a 1.5 s forward topple held on the ground). Codex owns
  animation behaviour, so replace any synth or alias clip freely.
- **Rift glow:** `rift_slime`, `rift_wraith` and the ghoul's eyes have an **emissive texture**
  (the glTF `emissiveTexture`, strength 2–2.5). Pulse `emission_energy_multiplier` in Godot for a Rift throb.
- `.gdignore` keeps Godot from importing the folder until the game uses it. Remove it (and commit the generated
  `.import` files) when wiring them in.

| Monster | File | Suggested role (habitat · danger tier · Rift or natural) | Size | LOD0 / LOD1 tris | Bones | Clips (s) | Source | Licence |
|---|---|---|---|---|---|---|---|---|
| Giant rat | `giant_rat` | Cellars, mines, sewers, granaries and farm edges. Pack vermin that spawns near villages. Tier 1, natural | 0.55 m tall, 1.66 m long with tail | 8,000 / 2,500 | 31 | idle 2.38, walk 1.33, run 0.50, attack 0.67, hit 0.46 (synth), death 1.08 | Easy Enemy *Rat* | CC0 |
| Blight rat | `blight_rat` | Dark-forest and old-battlefield variant, soot-black with ember eyes (emissive). Tier 1–2, natural (corrupted) | 0.62 m, 1.87 m | 8,000 / 2,500 | 31 | same as giant rat | Easy Enemy *Rat* | CC0 |
| Bog toad | `bog_toad` | Marshes, riverbanks and mill ponds. Ambush lunge. Tier 1, natural | 0.55 m tall, 1.2 m long | 8,000 / 2,500 | 28 | idle 2.50, walk 0.88 (hop), run 0.88 (alias of walk), attack 0.75, hit 0.46 (synth), death 0.83 | Easy Enemy *Frog* | CC0 |
| Giant wasp | `giant_wasp` | Forest clearings, orchards, hives in ruins. Comes in swarms of 2–4. Tier 1–2, natural | 1.0 m long (antennae to sting), 0.5 m wide; hovers 1.2 m up | 7,998 / 2,500 | 29 | idle 1.50 (flying), walk and run (alias of idle), attack 0.75, hit 0.46 (synth), death 0.75 | Easy Enemy *Wasp* | CC0 |
| Ghoul | `ghoul` | Old battlefields, crypts, plague villages, night roads. Rift-risen dead with violet eye glow. Tier 2, Rift-touched undead | 1.72 m | 8,000 / 2,500 | 40 | idle 5.54, walk 4.00, run 0.79, attack 5.04 (bite/grab), crawl 5.12, hit 0.46 (synth), death 1.50 (synth) | Animated Zombie *Zombie* | CC0 |
| Fungal brute | `fungal_brute` | Deep forest, caves, damp ruins. Slow and heavy puncher. Tier 2, natural | 1.70 m | 7,999 / 2,500 | 39 | idle 1.00, walk 1.00, run 0.57, attack 0.87, hit 0.60, death 0.77 | Ultimate Monsters *MushroomKing* (googly eyes and crown removed, cap shrunk, recoloured) | CC0 |
| Blackcap brute | `blackcap_brute` | Dangerous-forest variant: black cap, mossy body. Tier 2–3, natural | 1.70 m | 7,999 / 2,500 | 39 | same as fungal brute | Ultimate Monsters *MushroomKing* | CC0 |
| Rift slime | `rift_slime` | Near the Rift entrance and unstable runestones. Spawns in numbers when the Rift flares. Tier 1, **Rift** (violet body, cyan glowing veins) | 0.75 m | 1,984 / 1,000 | 12 | idle 2.50, walk 0.83, run 0.83 (alias of walk), attack 0.62, hit 0.46 (synth), death 0.42 (melts flat) | Animated Monster *Slime* (cartoon eyes removed) | CC0 |
| Rift wraith | `rift_wraith` | Rift interiors and night storms around broken runestones. Floating skull-masked spirit. Tier 3, **Rift** (dusk-violet shroud, cyan veins) | 1.9 m; hovers 0.2 m up | 8,000 / 2,500 | 38 | idle 1.17, walk 1.17 (alias of idle), run 0.83, attack 1.17, hit 0.47, death 0.67 (sinks to the ground) | Ultimate Monsters *Ghost_Skull* (head shrunk, recoloured) | CC0 |

Previews (all in `_previews/`):
- `monsters_lineup.png`: every monster to scale next to a 1.75 m human, the Meshy goblin and the Meshy wolf, with height lines.
- `monsters_poses.png`: one row per monster (idle, walk ×2, attack, hit, death end pose).
- `<name>_anim.png`: the single rows.

## Known limitations
- The shapes are still low-poly Quaternius geometry, subdivided once and decimated to 8k. At play distance they
  sit with the Meshy set. Up close they're smoother and simpler than the Meshy sculpts. `rift_wraith` and the two
  brutes are the most stylised; treat them as "otherworldly" or fungal rather than grounded.
- **Flyer deaths:** `giant_wasp.death` ends about 0.8 m above the ground (the pack clip only curls up). Let the body
  fall with physics or a tween. `rift_wraith.death` does reach the ground.
- `fungal_brute` and `blackcap_brute` `death` ends with the cap about 0.2 m under the ground (the pack's own
  clip). Their `run` lifts the root 0.15 m (a hop cycle).
- `ghoul.attack` (5.0 s) and `ghoul.walk` (4.0 s) are long pack clips. The walk is a slow shamble; loop it.
- Synthesised hit clips key every bone from the idle pose, so blend into and out of them (0.1 s or more).
- The wasp wings are opaque painted membranes (no alpha), to keep them cheap on mobile.

## How they were made (re-runnable)
All tools are in `tools/monsters/`. Blender 5.2 runs headless, and every step is data-driven from `specs/<name>.json`:
```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$B" -b --python tools/monsters/harmonise.py -- tools/monsters/specs/giant_rat.json   # build one monster
bash tools/monsters/check.sh giant_rat          # build it and render a check next to the human, goblin and wolf ($TMP/ashes_monsters/)
bash tools/monsters/previews.sh                 # all previews in _previews/
```
`harmonise.py` imports the FBX/glTF, drops props and the cartoon eyes (by material, by atlas colour or by UV box),
recolours the atlas, applies proportion tweaks around a bone (head shrink, body slim), prunes leaf bones to ≤ 40
(merging weights into the parent), strips the armature-object keys the FBX clips carry, renames, aliases or synthesises
clips, then scales, grounds and yaws the rig. It subdivides once, decimates to budget, smart-UV-unwraps and bakes
the painted colour (and emissive) texture with Cycles, then builds LOD1 and exports GLBs. Per-monster stats land in
`tools/monsters/stats/`.

## Rejected (and why)
| Candidate | Pack | Reason |
|---|---|---|
| Skeleton | Animated Monster | Toy anatomy: floating limb segments with no hands or feet, a spiral ribcage and a huge skull. Retextured and head-shrunk, it still read as a toy next to the Meshy goblin. A skeleton warrior should be a Meshy job. |
| Giant bat | Animated Monster | Plush-toy build: a chubby body with stubby legs and slab wings. Even after slimming the body and shrinking the head it clashed with the wolf and goblin. |
| Dragon | Animated Monster | Cartoon, and the Meshy wyvern already covers it. |
| Snake, Snake_angry | Easy Enemy | No death or hit clip. The snake also overlaps the planned beast work. It could be added later with synthesised clips. |
| Spider | Easy Enemy | The Meshy giant spider already covers it. |
| Other 40+ Ultimate Monsters (blobs, demons, yeti, orc, alien, birb, cactoro, ninja, wizard, bunny, dino, fish, frog, monkroose, tribal, armabee, alpaking, glub, goleling, hywirl, squidle, pigeon, cat, dog, chicken…) | Ultimate Monsters | Big googly eyes and cartoon mouths are modelled into the heads, with toy proportions and joke themes (sombrero cactus, ninja, pigeon). They can't be made grounded without remodelling. Goleling (golem) and Hywirl (wisp) were looked at and rejected for the same faces. |
| Bestiary – Dungeon Monsters Kit | Quaternius | Licence gate: paid, under the Quaternius QAL licence (not CC0). |

Raw sources kept (each folder has its `License.txt` and a `.gdignore`): `../quaternius/ultimate-monsters/` (only the models used, plus the
atlas), `../quaternius/easy-enemy/`, `../quaternius/animated-monster/`, `../quaternius/animated-zombie/`.
