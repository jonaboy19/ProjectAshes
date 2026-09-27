# Armor and medieval gear (incoming)

Sourced 2026-09-27 from open-source packs (nothing modelled from scratch). Everything is **free for commercial
use**: CC0, or **CC-BY 3.0 with the credit lines below** (copy them into the game credits). Every pack folder has its
`LICENSE.txt` / `LICENSE.md` with the source URL, and a `.gdignore` (repo convention: delete it when wiring a pack in).
57 MB in total; the largest file is 4.2 MB.

**Skeleton:** the game's master skeleton is the **Quaternius UAL skeleton** (65 bones, UE-mannequin names:
`root, pelvis, spine_01..03, neck_01, head, clavicle_l, upperarm_l, lowerarm_l, hand_l, thigh_l, calf_l, foot_l, ...`),
used by the MakeHuman villagers in `kingdom/assets/generated/characters/` and by everything in
`incoming/characters/` (see its README).

**Conversion:** every piece below was re-exported to **GLB** (no Draco, no meshopt) with Blender 5.2 by
`_tools/build.py` (manifest `_tools/manifest.js`, per-file results in `_tools/build_report.jsonl`). Each piece is
scaled to **real-world metres** (helmet ~0.26-0.30 m wide, round shield 0.65 m, kite shield 1.0 m, greave 0.45 m,
chest 0.36-0.5 m). Rigid pieces have their **origin at the bottom centre**, so a helmet can sit on the head bone.
Pieces are **≤ 3.2k tris**; the Quaternius outfit parts were decimated from up to 9.2k. Textures are **≤ 1024 px**:
the Quaternius 4096 px maps were resized to 1024 JPEG, and the old OpenGameArt maps were resized to ≤ 1024 JPEG.
Flat toy colours (Poly Pizza kit, Quaternius items, KayKit atlas) were **toned toward the warm natural palette**:
steel-blue → neutral warm steel, and saturation and brightness capped.

## Previews (look at these first)

All are in `_previews/`. They show a 3/4 view, each model fitted to its tile, with the real size in metres, the tri
count, rig and texture size in the label.

| file | what |
|---|---|
| `armor_helmets.jpg` | 45 helmets, hoods, hats, crowns, plumes (new plus existing packs) |
| `armor_chest.jpg` | chest, cuirass, fauld, belt, tunic-armour, full sets |
| `armor_arms.jpg` | pauldrons, gauntlets, bracers, vambraces, couters, sleeves |
| `armor_legs.jpg` | greaves, sabatons, boots, trousers |
| `armor_shields.jpg` | 27 shields (new plus existing packs) |
| `armor_gear.jpg` | capes, pouches, bags, backpack, bedroll, quiver |
| `armor_fit_on_makehuman_guard.jpg` | **scale and fit check**: pieces on or next to the accepted MakeHuman `guard.glb` (1.86 m) |
| `_raw_knights_kit_parts.jpg`, `_raw_opengameart.jpg` | the raw downloads before cleanup (for reference) |

## Sources

| folder | source / licence | pieces | tris / piece | rig and compatibility | style verdict |
|---|---|---|---|---|---|
| `quaternius/modular-outfits-fantasy/` | Quaternius *Modular Character Outfits - Fantasy*, free Standard version, **CC0**. Converted from the existing `incoming/quaternius/modular-character-outfits-fantasy`. https://quaternius.com/packs/modularcharacteroutfitsfantasy.html | 20 skinned parts. **Ranger** (M/F): hood, body (leather jerkin and belts), arms (bracers), legs, knee boots, pauldron(s). **Peasant** (M/F): body, arms, legs, boots | 1.1k-3.1k | **UAL 65-bone, same bone names as the game.** Loads straight onto the villager `Skeleton3D`. Built for Quaternius' "Regular" body, so on the taller MakeHuman bodies they sit slightly inside or behind the torso (see the fit sheet). Needs a per-body fit: scale the part to the body's hip height, or shrinkwrap in Blender. Hide body faces under the clothes | **Best fit.** Semi-realistic, hand-textured, warm colours. Cloth and leather tier |
| `quaternius/items/` | Quaternius *Animated Knight* plus *Ultimate RPG Items*, **CC0** (existing incoming packs, FBX converted) | 3 knight helmets (sallet, visored, great helm with gold cross), shoulder pads, 5 cuirass pickups (black spiked, gold, leather, 2x steel), glove, pouch, bag, backpack, 2 crowns | 96-2.9k | rigid (attach to a bone) | clean flat low-poly. Fine as **pickups and inventory icons**, and the helmets work on heads. Flat-shaded, so less detailed than the villagers |
| `kaykit/adventurers/glb/` | KayKit *Character Pack: Adventurers 1.0*, **CC0**. https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | 9 shields (badge/heater, round, barbarian round, spiked, square; plain and coloured), knight helmet, barbarian bear-hood, wizard hat, 4 capes | 78-654 | rigid. The KayKit characters use their own 41-bone chibi rig; only the pieces were kept | shields and capes are good. Toy-like chibi proportions: the helmet is oversized for realistic heads. Gradient atlas harmonised |
| `polypizza/cc-by/knights-character-kit/` | **"Knights Character Kit" by Jacques Fourie, CC-BY 3.0**. https://poly.pizza/m/3r2JcOZShpE | **55 parts**: 16 helmets and visors (round, bascinet, conical with grille, barred visor, horned viking, red Roman crest, black horsehair crests, horned visors), bevor, 3 plumes, crown; 7 chest plates, barrel leather torso, 2 faulds, plate belt, jewelled plaque; 6 pauldrons, 3 gauntlets (L, R, spiked), 4 bracers, vambrace, couter; 2 sabatons, 6 greaves (plate and leather-strapped); fur mantle, cape, quiver, wooden round shield with boss | 50-2.9k (most 100-900) | rigid, one uniform scale (x0.45) so the pieces form a matched set. The chest pieces are a little narrow for MakeHuman (0.36 m); scale them x1.1-1.2 per body | **Largest modular plate set.** Flat-colour low-poly; needs a painterly retexture or shared atlas to match the villagers (see Gaps). Colours already toned |
| `polypizza/cc-by/glb/`, `polypizza/cc0/glb/` | Poly Pizza singles. CC-BY 3.0 credits in `polypizza/LICENSE.md` (CreativeTechLab, Poly by Google, Minh Nguyen Tri); CC0 (Quaternius, Kenney) | 2 mail/cloth tunic-armours with belt (CreativeTechLab), round wooden shield, boot, crown, kettle-style hat, coin bag, coin pouch, sacks, bedroll | 154-1.5k | rigid | flat low-poly. Bedroll is mint-coloured: recolour it |
| `opengameart/cc-by/iron-armor-set/glb/` | **"Iron armor set" by Alejandro CG (rogerdv), CC-BY 3.0**. https://opengameart.org/content/iron-armor-set | full set plus 5 separate skinned pieces: helmet (nasal cap), chest (studded leather and iron pauldrons), gloves/bracers, legs, boots. 512 px painted texture | 328-2.9k (full set 2.9k) | **skinned to its own 75-bone rig** (`root, hips, thigh.L, shin.L...`, Rigify-like). Already at human scale (1.84 m) and proportions close to MakeHuman. **Re-skin to UAL**: Blender Data Transfer of weights from a MakeHuman villager body, then parent to the UAL armature | **Good fit**: painted semi-realistic iron and leather. **Mercenary, town guard, bandit tier** |
| `opengameart/cc-by/anglo-saxon-helmets/` | **"Anglo-Saxons helmets and spears" by Lotnik, CC-BY 3.0** (re-export of the existing incoming pack, now with its textures) | 6 nasal and spangen helms, 4 with a mail aventail | 618-728 | rigid, head bone | **Very good fit**: painted, historic. Chainmail and early-medieval helmet tier |
| `opengameart/cc-by/orc-barbarian/` | **"Orc barbarian" by umask007, CC-BY 3.0**. https://opengameart.org/content/orc-barbarian | orc body without weapons (skinned), orc armour faces extracted (plates, belt, skirt, shoes; skinned), shoulder armour (rigid) | 143-959 | own 28-bone rig | very low detail, flat colours, no UVs on the armour. **Placeholder only** for orc armour |
| `opengameart/cc-by/leather-breastplate`, `leather-forearm-armor`, `tower-shield`, `poleaxe-and-shield` | **weaponguy, CC-BY 3.0** (breastplate, forearm guard, tower shield); **Ouren, CC-BY 3.0** (round shield). URLs in each LICENSE | leather breastplate, leather forearm guard, tower shield, painted round shield | 146-448 | rigid | the breastplate and forearm guard have a 150 px texture that maps poorly (they look grey-blue): shape only, retexture. The tower-shield textures are photo-based |
| `opengameart/cc0/*` | **CC0**: LordNeo (kite, spiked shield), gamercat (basic round shield), tigeruppercut (heater), Lucian Pavel (bucket great helm, cartoon knight), olexanders (kettle hat/morion), nisu (viking helmet), urnoev (iron crown), tehbucket (straw hat), defecaterainbows (low-poly plate knight) | kite shield, heater shield, spiked round shield, basic round shield, great helm (bucket), kettle hat/morion, viking helmet, iron crown, straw hat (peasant), plate-knight armour set (27 pieces joined, rigid, 1.85 m), cartoon knight (skinned, 31 bones) | 286-2.5k | rigid, except the cartoon knight (own rig) | mixed. Kite shield and kettle hat are good. **Off-style: great helm and viking helmet** (photo-grunge / PBR textures) and **iron crown** (spiky realistic): retexture before use |

### Already in `incoming/` (checked, not duplicated here)

| pack | verdict |
|---|---|
| `characters/g6-ual/g6_*_modular_all.glb` (other agent) | **Already on the UAL skeleton**: helmets, gloves, boots and a medium leather set on the G6 bodies. Use these first for the leather tier. |
| `quaternius/ultimate-modular-men` / `-women` (King, Soldier, Medieval, Adventurer) | whole characters on Quaternius' older **62-bone** rig (`Root, Body, Hips, Abdomen`). The clothes are not separable armour. Use as NPC reference only |
| `creatus/knight-pack-1` | CC0, knights, king and princess, but **15-29k tris per character** and 4-12k per head. The GLBs are unrigged. **Over the mobile budget**: skip, or decimate heavily for hero/statue use |
| `polypizza/cc0` Quaternius shields, `polypizza/cc-by` helmet, shields, Viking helmet | in the helmet and shield sheets as `[existing]`. The Quaternius shields are 2 m (wrong scale) and the Fuchs Viking helmet is 86 units. Rescale if used |
| `3dassets-dev-ai/blacksmith-forge-and-armoury` | breastplate-on-form, helm-on-form, mail drum: **armoury props only**, AI-generated per the source site |
| `kaykit/fantasy-weapons-bits`, `styloo/the-company` | weapons (the user's domain); Styloo is whole low-poly characters with an unlit style. No separable armour |

### Rejected (licence or style), with reasons

- **Quin-GS "Modular Knights Character Set"** (itch.io, found via Reddit/itch leads): paid, and *"redistribution is not allowed"*. The repo is public: rejected.
- **Quaternius "Bestiary - Dungeon Monsters Kit"** (goblins etc.): *Quaternius Asset License*. It allows commercial use in a product but forbids redistributing the assets themselves, and this repo is public. Not downloaded. It is fine to buy or download it privately and ship it inside the game build.
- **Quaternius Modular Outfits: the other 10 outfits** (knight etc.) exist only in the paid Source version. Not free: skipped.
- OGA **GPL** sets (yd "Armor Set", "Simple Helmets", "Light Wooden Shield"; p0ss "Male Armor Set"), **CC-BY-SA** (Fantasy Breastplate, Iron Buckler, orc-3d, orclowpoly, FPS knight): share-alike/GPL, rejected.
- OGA **"Modular 3d male & female"** (vrs1): armour ripped from other sources, and a comment says it is Unity-Asset-Store derived. Unclear licence: rejected.
- OGA **Orcish Helm** and **Lionguard Shield** (dmitry.porotnikov): Warcraft-derived designs (IP risk) and neon magenta glow. Rejected.
- Sketchfab **"Lowpoly PBR Knight Armour"** (soidev, CC-BY, 9 parts, UE4-rigged): 39k tris and 4K realistic PBR. Over budget, needs a login to download. Not taken.
- Poly Pizza whole characters (Roman centurion, berserker, agile knight, mastjie fighters, goblins, King, Monk): not modular armour, or toy style. Deleted after the preview. Also removed: winged shield (odd, 6.8k tris), OGA "helmet" by LordNeo (actually a cloth shape), work boots (modern), Greatsword Warrior, Little Knight, Skeleton Outlaw (off-scope).
- GitHub searches (`armor` with topic cc0, "medieval armor gltf", "modular character armor") returned **no** CC0/MIT armour repos. itch.io search pages returned 403 to the scripted fetch.

## Credit lines (CC-BY 3.0, required in the game credits)

```
"Knights Character Kit" by Jacques Fourie (poly.pizza/m/3r2JcOZShpE), CC-BY 3.0
"Armor", "Armor Used", "Shield" by CreativeTechLab (poly.pizza), CC-BY 3.0
"Boots", "Crown" by Poly by Google (poly.pizza), CC-BY 3.0
"hat" by Minh Nguyen Tri (poly.pizza/m/4Tdb1s3-kug), CC-BY 3.0
"Iron armor set" by Alejandro CG (rogerdv), made for The Key of the World (opengameart.org), CC-BY 3.0
"Anglo-Saxons helmets and spears" by Lotnik (opengameart.org), CC-BY 3.0
"Leather Breastplate", "Leather ForeArm Armor", "Tower Shield" by weaponguy (opengameart.org), CC-BY 3.0
"Poleaxe and Shield" by Ouren (opengameart.org), CC-BY 3.0
"Orc barbarian" by umask007 (opengameart.org), CC-BY 3.0
```
CC0 packs (Quaternius, KayKit/Kay Lousberg, Kenney, LordNeo, Lucian Pavel, nisu, urnoev, olexanders, gamercat,
tigeruppercut, tehbucket, defecaterainbows) need no credit; crediting them is still courteous.

## How to use on the game's characters

1. **Skinned UAL parts** (`quaternius/modular-outfits-fantasy`, and `characters/g6-ual` modular pieces). Add the
   part's `MeshInstance3D` under the villager's `Skeleton3D` and set its `skeleton` path. The bone names match, so no
   retarget is needed. Scale the part by body height / 1.80 when the body is not Quaternius-sized. Hide or delete
   villager body faces under the part.
2. **Rigid pieces** (everything else). Use `BoneAttachment3D` on the UAL bones: helmet → `head` (the origin is the
   helmet's bottom centre; about -0.10 m on Y from the head bone to seat it over the brow, tune per helmet), pauldron
   → `upperarm_l/r` or `clavicle_*`, gauntlet → `hand_*`, bracer/vambrace → `lowerarm_*`, greave → `calf_*`,
   sabaton → `foot_*`, chest/fauld/belt → `spine_03` / `pelvis`, cape → `spine_03`, shield on the back → `spine_03`
   (rotate 180°), shield in hand → `lowerarm_l`. This is cheap and fine for mobile. Chest plates look stiff when
   bending; re-skin them if needed (see 3).
3. **Re-skin to UAL** (iron armour set, orc armour, any rigid chest piece). In Blender, import a MakeHuman villager
   GLB. Fit the piece. Add *Data Transfer → Vertex Groups* (nearest face interpolated) from the villager body, parent
   it to the UAL armature and export. That gives a deforming piece on the master skeleton.

**Mobile budget check.** Body ~2.1k (MakeHuman, faces under armour deleted) plus a full plate kit (helmet 0.6k,
chest 0.3-0.8k, 2 pauldrons 0.4k, 2 gauntlets 0.5k, 2 greaves 1.1k, 2 sabatons 0.9k, fauld 0.4k, cape 0.9k) comes to
**~7-8k tris**. Body plus a Quaternius Ranger outfit (hood, body, arms, legs, boots) comes to **~12-13k**. Both are
within the 15k per armoured character.

## Style notes (compared with `docs/art_reference/village_target_1.png`)

- **Best style matches**: Quaternius outfits, the Iron armor set and the Anglo-Saxon helms (all painted,
  semi-realistic, warm), and the kettle hat.
- **Needs a shared painterly atlas before release**: the Knights Character Kit, the Quaternius items and the Poly
  Pizza singles (flat colours, no texture detail). They are consistent with each other, so one steel/leather/cloth
  gradient atlas would lift them all.
- **Off-style (flagged)**: great helm "bucket" (photo grunge), viking helmet (PBR realism), iron crown (spiky,
  realistic), tower-shield photo textures, leather breastplate/forearm (texture maps badly), orc armour (crude),
  KayKit knight helmet and bear hood (chibi proportions).

## Gaps (to make, e.g. with Meshy; list for the main session)

Tiered sets still missing or too weak:

1. **Padded gambeson**: quilted torso with sleeves and a high collar (skinnable). The MakeHuman guard has one
   procedurally; a matching standalone piece is still needed. Also a **gambeson with a mail shirt** over it.
2. **Chainmail**: mail hauberk (knee length, short sleeves), **mail coif / hood**, mail chausses (legs), mail
   mittens.
3. **Scale armour**: scale cuirass (bronze/iron scales on leather), scale pauldrons.
4. **Plate, painterly**: full late-medieval plate harness in the game's painted style: breastplate+backplate,
   pauldrons, rerebrace/vambrace, gauntlets, tassets, cuisses, poleyns, greaves, sabatons.
5. **Helmets**: **kettle hat** (hand-painted, not flat), **barbute**, **bascinet with a pointed (houndskull)
   visor**, **great helm with painted heraldry**, padded **arming cap**, cloth/leather **hood with a liripipe**,
   **sallet with bevor** (painted).
6. **Tabards and surcoats** in faction colours (town guard blue, knight order, noble house), plus **capes with a
   fur collar** (noble) and **tattered cloaks** (bandit).
7. **Belts and pouches** worn on the body (belt with buckle, 2 pouches, dagger frog), **baldric**, **quiver on a
   belt**.
8. **Faction variants**:
   - town-guard kettle hat plus a blue gambeson with a city crest
   - noble parade armour with gilded trim
   - bandit mismatched leather with a face scarf and hood
   - mercenary brigandine (riveted cloth over plates)
   - **orc bone armour**: bone chest, skull pauldrons, tusk helmet, hide loincloth, spiked iron bracers
   - orc crude plate (hammered scrap plates)
9. **Shield worn on the back**: a strap version of the heater and round shields (the existing shields can be
   attached, but they have no strap mesh).
10. **Boots**: turnshoes (peasant), riding boots, sabatons in the painted style.

## Rebuild / tools

```
node _tools/manifest.js _tools/_manifest.json                       # writes the manifest (paths are absolute to this PC)
blender -b --factory-startup --python _tools/build.py -- _tools/_manifest.json _tools/build_report.jsonl
node _tools/sheets.js <specdir>                                      # contact-sheet specs from the report
blender -b --factory-startup --python _tools/render_sheet.py -- <specdir>/helmets.json
blender -b --factory-startup --python _tools/inspect.py -- out.jsonl file1.glb file2.fbx ...
```
The KayKit character GLBs (the source of the helmet and capes) and the split kit parts were deleted after
extraction to save space. `manifest.js` expects `kaykit/adventurers/Characters/gltf/*.glb` (re-download from GitHub)
and `polypizza/cc-by/knights-character-kit/_split/` (re-split `_source_Knights_Character_Kit.glb`, one GLB per mesh
sorted by position) if you rebuild those entries.

## Inventory (from `_tools/build_report.jsonl`)

**quaternius/modular-outfits-fantasy/** (20 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| Female_Peasant_Arms.glb | 3104 | 65 bones | 1024 | 1.664 0.131 0.123 | 426 |
| Female_Peasant_Body.glb | 2188 | 65 bones | 1024 | 0.344 0.276 0.531 | 382 |
| Female_Peasant_Feet.glb | 2424 | 65 bones | 1024 | 0.403 0.335 0.465 | 387 |
| Female_Peasant_Legs.glb | 1944 | 65 bones | 1024 | 0.376 0.229 0.655 | 314 |
| Female_Ranger_Acc_Pauldrons.glb | 1376 | 65 bones | 1024 | 0.211 0.189 0.124 | 379 |
| Female_Ranger_Arms.glb | 3102 | 65 bones | 1024 | 1.664 0.137 0.135 | 747 |
| Female_Ranger_Body.glb | 2908 | 65 bones | 1024 | 0.38 0.345 0.622 | 581 |
| Female_Ranger_Feet.glb | 2425 | 65 bones | 1024 | 0.409 0.338 0.561 | 592 |
| Female_Ranger_Head_Hood.glb | 2136 | 65 bones | 1024 | 0.327 0.342 0.32 | 395 |
| Female_Ranger_Legs.glb | 1204 | 65 bones | 1024 | 0.411 0.24 0.65 | 346 |
| Male_Peasant_Arms.glb | 3102 | 65 bones | 1024 | 1.799 0.169 0.164 | 618 |
| Male_Peasant_Body.glb | 2910 | 65 bones | 1024 | 0.747 0.31 0.637 | 424 |
| Male_Peasant_Feet.glb | 2424 | 65 bones | 1024 | 0.351 0.33 0.452 | 385 |
| Male_Peasant_Legs.glb | 1112 | 65 bones | 1024 | 0.423 0.229 0.651 | 299 |
| Male_Ranger_Acc_Pauldron.glb | 1376 | 65 bones | 1024 | 0.233 0.21 0.137 | 349 |
| Male_Ranger_Arms.glb | 3104 | 65 bones | 1024 | 1.799 0.16 0.164 | 655 |
| Male_Ranger_Body.glb | 2908 | 65 bones | 1024 | 0.429 0.343 0.691 | 518 |
| Male_Ranger_Feet_Boots.glb | 2425 | 65 bones | 1024 | 0.363 0.338 0.561 | 559 |
| Male_Ranger_Head_Hood.glb | 2136 | 65 bones | 1024 | 0.303 0.335 0.34 | 385 |
| Male_Ranger_Legs.glb | 1128 | 65 bones | 1024 | 0.363 0.227 0.629 | 337 |

**quaternius/items/** (15 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| Knight_Helmet1.glb | 568 | rigid | - | 0.28 0.277 0.294 | 49 |
| Knight_Helmet2.glb | 772 | rigid | - | 0.28 0.303 0.385 | 42 |
| Knight_Helmet3.glb | 656 | rigid | - | 0.28 0.32 0.412 | 59 |
| Knight_ShoulderPads.glb | 96 | rigid | - | 0.52 0.205 0.091 | 10 |
| Armor_Black.glb | 1040 | rigid | - | 0.5 0.247 0.39 | 57 |
| Armor_Golden.glb | 1040 | rigid | - | 0.5 0.247 0.39 | 56 |
| Armor_Leather.glb | 288 | rigid | - | 0.42 0.289 0.354 | 16 |
| Armor_Metal.glb | 584 | rigid | - | 0.5 0.265 0.329 | 32 |
| Armor_Metal2.glb | 704 | rigid | - | 0.5 0.247 0.357 | 38 |
| Glove.glb | 456 | rigid | - | 0.156 0.25 0.07 | 46 |
| Pouch.glb | 414 | rigid | - | 0.155 0.155 0.18 | 22 |
| Bag.glb | 1232 | rigid | - | 0.45 0.273 0.352 | 65 |
| Backpack.glb | 2910 | rigid | - | 0.55 0.414 0.49 | 137 |
| Crown.glb | 592 | rigid | - | 0.2 0.2 0.118 | 32 |
| Crown2.glb | 840 | rigid | - | 0.2 0.2 0.132 | 45 |

**kaykit/adventurers/** (16 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| shield_badge.glb | 262 | rigid | 1024 | 0.691 0.193 0.8 | 45 |
| shield_badge_color.glb | 262 | rigid | 1024 | 0.691 0.193 0.8 | 44 |
| shield_round.glb | 284 | rigid | 1024 | 0.65 0.244 0.65 | 46 |
| shield_round_barbarian.glb | 284 | rigid | 1024 | 0.65 0.244 0.65 | 49 |
| shield_round_color.glb | 284 | rigid | 1024 | 0.65 0.244 0.65 | 46 |
| shield_spikes.glb | 420 | rigid | 1024 | 0.68 0.31 0.7 | 55 |
| shield_spikes_color.glb | 420 | rigid | 1024 | 0.68 0.31 0.7 | 55 |
| shield_square.glb | 262 | rigid | 1024 | 0.666 0.227 0.9 | 45 |
| shield_square_color.glb | 262 | rigid | 1024 | 0.666 0.227 0.9 | 45 |
| Knight_Helmet.glb | 480 | rigid | 1024 | 0.28 0.308 0.333 | 53 |
| Barbarian_Hat.glb | 654 | rigid | 1024 | 0.327 0.373 0.3 | 57 |
| Mage_Hat.glb | 396 | rigid | 1024 | 0.704 0.686 0.45 | 54 |
| Knight_Cape.glb | 84 | rigid | 1024 | 0.935 0.33 1.1 | 36 |
| Barbarian_Cape.glb | 78 | rigid | 1024 | 0.933 0.329 1.1 | 39 |
| Mage_Cape.glb | 84 | rigid | 1024 | 0.904 0.319 1.1 | 41 |
| Rogue_Cape.glb | 84 | rigid | 1024 | 0.935 0.33 1.1 | 42 |

**polypizza/cc-by/knights-character-kit/** (55 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| fauld_ring.glb | 132 | rigid | - | 0.288 0.252 0.09 | 10 |
| plate_curved.glb | 188 | rigid | - | 0.081 0.149 0.155 | 17 |
| plume_red_a.glb | 50 | rigid | - | 0.189 0.144 0.117 | 5 |
| plume_red_b.glb | 50 | rigid | - | 0.189 0.144 0.117 | 5 |
| fauld_leather_strips.glb | 428 | rigid | - | 0.324 0.293 0.167 | 38 |
| chest_barrel_leather.glb | 268 | rigid | - | 0.297 0.288 0.252 | 24 |
| helmet_round.glb | 264 | rigid | - | 0.216 0.225 0.202 | 25 |
| cape_fur_mantle.glb | 2910 | rigid | - | 0.481 0.596 0.323 | 211 |
| cape_purple.glb | 958 | rigid | - | 0.866 0.602 0.455 | 95 |
| plume_wings_blue.glb | 60 | rigid | - | 0.105 0.063 0.054 | 7 |
| quiver_back.glb | 2184 | rigid | - | 0.489 0.674 0.273 | 197 |
| pauldron_layered_a.glb | 100 | rigid | - | 0.309 0.186 0.063 | 9 |
| pauldron_layered_b.glb | 110 | rigid | - | 0.336 0.197 0.139 | 10 |
| belt_plate.glb | 180 | rigid | - | 0.311 0.315 0.124 | 16 |
| helmet_visor_horned_a.glb | 370 | rigid | - | 0.165 0.228 0.142 | 34 |
| helmet_visor_b.glb | 108 | rigid | - | 0.117 0.151 0.103 | 11 |
| helmet_visor_horned_c.glb | 370 | rigid | - | 0.165 0.228 0.142 | 33 |
| helmet_bascinet_round.glb | 620 | rigid | - | 0.256 0.279 0.245 | 55 |
| helmet_horned_viking.glb | 1424 | rigid | - | 0.291 0.229 0.423 | 108 |
| shield_round_wood_boss.glb | 658 | rigid | - | 0.387 0.565 0.189 | 49 |
| gauntlet_l.glb | 250 | rigid | - | 0.12 0.203 0.103 | 20 |
| gauntlet_r.glb | 250 | rigid | - | 0.12 0.203 0.103 | 20 |
| helmet_red_crest_cloak.glb | 752 | rigid | - | 0.251 0.448 0.457 | 62 |
| helmet_red_crest_roman.glb | 752 | rigid | - | 0.225 0.4 0.471 | 71 |
| couter_elbow.glb | 552 | rigid | - | 0.095 0.177 0.157 | 45 |
| helmet_barred_visor.glb | 938 | rigid | - | 0.128 0.15 0.159 | 78 |
| chest_plate_a.glb | 284 | rigid | - | 0.361 0.36 0.328 | 25 |
| chest_plate_leather_b.glb | 1166 | rigid | - | 0.36 0.427 0.324 | 91 |
| vambrace_square.glb | 296 | rigid | - | 0.112 0.072 0.112 | 23 |
| helmet_yellow_crest.glb | 666 | rigid | - | 0.262 0.237 0.233 | 56 |
| pauldron_red_a.glb | 200 | rigid | - | 0.219 0.306 0.215 | 19 |
| pauldron_red_b.glb | 200 | rigid | - | 0.221 0.306 0.215 | 20 |
| bracer_fur_spikes.glb | 732 | rigid | - | 0.131 0.203 0.104 | 51 |
| helmet_conical_grille.glb | 524 | rigid | - | 0.216 0.252 0.307 | 50 |
| helmet_black_crest_a.glb | 520 | rigid | - | 0.183 0.177 0.268 | 47 |
| helmet_black_crest_b.glb | 520 | rigid | - | 0.183 0.177 0.268 | 47 |
| bevor_neckguard.glb | 230 | rigid | - | 0.135 0.135 0.131 | 20 |
| crown_jewelled.glb | 2910 | rigid | - | 0.244 0.192 0.168 | 216 |
| pauldron_round_c.glb | 292 | rigid | - | 0.248 0.248 0.195 | 29 |
| gauntlet_spiked.glb | 580 | rigid | - | 0.118 0.136 0.145 | 49 |
| bracer_fur.glb | 994 | rigid | - | 0.117 0.108 0.074 | 76 |
| sabaton_boot_a.glb | 460 | rigid | - | 0.135 0.205 0.239 | 41 |
| sabaton_boot_b.glb | 460 | rigid | - | 0.135 0.205 0.239 | 41 |
| greave_plate_a.glb | 558 | rigid | - | 0.133 0.232 0.438 | 47 |
| greave_leather_straps.glb | 1630 | rigid | - | 0.141 0.241 0.453 | 132 |
| chest_plate_dark_c.glb | 844 | rigid | - | 0.333 0.36 0.321 | 78 |
| chest_plate_d.glb | 298 | rigid | - | 0.36 0.427 0.324 | 26 |
| chest_plate_dark_e.glb | 674 | rigid | - | 0.388 0.382 0.322 | 61 |
| pauldron_round_d.glb | 292 | rigid | - | 0.248 0.248 0.195 | 28 |
| plaque_jewelled.glb | 920 | rigid | - | 0.518 0.636 0.236 | 76 |
| greave_plate_b.glb | 558 | rigid | - | 0.132 0.232 0.438 | 46 |
| greave_plate_c.glb | 414 | rigid | - | 0.132 0.232 0.451 | 34 |
| greave_leather_b.glb | 1630 | rigid | - | 0.141 0.241 0.453 | 131 |
| greave_plate_d.glb | 414 | rigid | - | 0.132 0.232 0.451 | 34 |
| bracer_leather.glb | 1736 | rigid | - | 0.252 0.391 0.174 | 126 |

**polypizza/cc-by/** (6 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| Armor_CreativeTechLab_tVYVQc.glb | 316 | rigid | - | 0.5 0.247 0.534 | 24 |
| Armor_Used_CreativeTechLab_EEtHhE.glb | 556 | rigid | - | 0.5 0.228 0.492 | 43 |
| Shield_CreativeTechLab_KtP3XC.glb | 312 | rigid | - | 0.65 0.153 0.65 | 25 |
| Boots_Poly_by_Google_7HbqG8.glb | 154 | rigid | 32 | 0.368 0.197 0.3 | 12 |
| Crown_Poly_by_Google_0seQ0m.glb | 1455 | rigid | - | 0.2 0.218 0.085 | 139 |
| hat_Minh_Nguyen_Tri_4Tdb1s.glb | 228 | rigid | - | 0.36 0.349 0.19 | 21 |

**polypizza/cc0/** (4 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| Coin_Bag_Quaternius_iUpWtN.glb | 976 | rigid | - | 0.25 0.126 0.065 | 52 |
| Coin_Pouch_Quaternius_pTZyPT.glb | 414 | rigid | - | 0.155 0.155 0.18 | 24 |
| Bags_Quaternius_gzvyAQ.glb | 912 | rigid | - | 0.3 0.266 0.119 | 20 |
| Bedroll_Kenney_12PaVp.glb | 424 | rigid | - | 0.7 0.241 0.241 | 31 |

**opengameart/cc-by/iron-armor-set/** (6 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| iron_armor_full.glb | 2905 | 75 bones | 512 | 1.16 0.5 1.84 | 220 |
| iron_chest.glb | 732 | 75 bones | 512 | 0.974 0.31 0.526 | 93 |
| iron_helmet.glb | 328 | 75 bones | 512 | 0.17 0.254 0.281 | 81 |
| iron_gloves.glb | 1028 | 75 bones | 512 | 1.16 0.402 0.306 | 117 |
| iron_legs.glb | 550 | 75 bones | 512 | 0.499 0.254 0.689 | 83 |
| iron_boots.glb | 364 | 75 bones | 512 | 0.509 0.284 0.411 | 78 |

**opengameart/cc-by/leather-breastplate/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| leather_breastplate.glb | 448 | rigid | 150 | 0.42 0.329 0.455 | 20 |

**opengameart/cc-by/leather-forearm-armor/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| leather_forearm_guard.glb | 146 | rigid | 150 | 0.28 0.109 0.12 | 16 |

**opengameart/cc-by/tower-shield/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| tower_shield.glb | 230 | rigid | 800 | 0.766 0.243 1.2 | 833 |

**opengameart/cc-by/poleaxe-and-shield/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| round_shield.glb | 200 | rigid | 1024 | 0.65 0.185 0.65 | 88 |

**opengameart/cc-by/orc-barbarian/** (3 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| orc_barbarian_full.glb | 959 | 28 bones | 256 | 2.688 0.747 2.745 | 96 |
| orc_shoulder_armor.glb | 143 | rigid | 256 | 0.45 0.569 0.439 | 7 |
| orc_armor_skinned.glb | 310 | 28 bones | 256 | 1.38 0.702 1.757 | 37 |

**opengameart/cc0/heater-shield/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| heater_shield.glb | 436 | rigid | - | 0.535 0.068 0.75 | 23 |

**opengameart/cc0/great-kite-shield/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| kite_shield.glb | 1956 | rigid | 894 | 0.5 0.083 1 | 571 |

**opengameart/cc0/spiked-shield/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| spiked_shield.glb | 564 | rigid | - | 0.7 0.447 0.548 | 38 |

**opengameart/cc0/basic-shield/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| basic_round_shield.glb | 414 | rigid | - | 0.6 0.059 0.598 | 26 |

**opengameart/cc0/bucket-helmet/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| great_helm_bucket.glb | 286 | rigid | 512 | 0.26 0.32 0.309 | 417 |

**opengameart/cc0/helmet-olexanders/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| kettle_morion_helmet.glb | 1940 | rigid | - | 0.42 0.358 0.251 | 44 |

**opengameart/cc0/viking-helmet/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| viking_helmet.glb | 2426 | rigid | 1024 | 0.26 0.215 0.182 | 139 |

**opengameart/cc0/iron-crown/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| iron_crown.glb | 636 | rigid | 1024 | 0.2 0.197 0.248 | 105 |

**opengameart/cc0/hats-clothing-props/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| straw_hat.glb | 1934 | rigid | 1024 | 0.45 0.434 0.134 | 190 |

**opengameart/cc0/low-poly-knight/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| plate_knight_armor_set.glb | 1535 | rigid | - | 0.475 0.669 1.85 | 65 |

**opengameart/cc-by/anglo-saxon-helmets/** (6 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| anglo_saxon_helm1.glb | 618 | rigid | 1024 | 0.24 0.32 0.344 | 104 |
| anglo_saxon_helm2.glb | 716 | rigid | 1024 | 0.24 0.323 0.391 | 161 |
| anglo_saxon_helm3.glb | 684 | rigid | 1024 | 0.24 0.287 0.457 | 189 |
| anglo_saxon_helm4.glb | 728 | rigid | 1024 | 0.24 0.299 0.457 | 192 |
| anglo_saxon_helm5.glb | 722 | rigid | 1024 | 0.24 0.294 0.457 | 192 |
| anglo_saxon_helm6.glb | 688 | rigid | 1024 | 0.24 0.287 0.457 | 191 |

**opengameart/cc0/cartoon-medieval-knight/** (1 GLB)

| file | tris | rig | max tex | size m (x y z) | KB |
|---|--:|---|--:|---|--:|
| cartoon_knight_skinned.glb | 2536 | 31 bones | 1024 | 1.995 0.542 1.8 | 233 |
