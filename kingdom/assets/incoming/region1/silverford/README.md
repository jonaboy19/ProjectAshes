# Silverford guild hall + chapel of the Dawn Throne (Region 1, work package L3)

Two exterior buildings for Silverford (the guild town on the Ashrun) and the Dawn Throne mission chapel (Kingsreach
envoy), plus their two interiors. All Y-up, origin at ground centre, **front (door) = +Z in Godot**. No `.tres` needed:
each GLB carries one baked texture (plus the tiny flat-colour accents described below).

| File | Source (CC0) | Tris LOD0 / LOD1 | Tex LOD0 / LOD1 | Size m (x, y, z) | Materials |
|---|---|---|---|---|---|
| `guildhall_silverford_lod0/1.glb` | `meshy_free/buildings/house_two_story_shingle`, roof recoloured royal blue, x1.3 | 10,096 / 3,080 | 1024 / 512 | 6.9 x 9.2 x 8.8 | baked + 2 flat (blue, silver) |
| `chapel_dawn_throne_lod0/1.glb` | `meshy_free/churches/church_white_red_spire`, red roofs and teal spire recoloured gold, warm-white stone | 12,172 / 3,772 | 1024 / 512 | 7.9 x 13.9 x 11.7 | baked + 1 flat (gold sun) |

Budget (`ashes-asset-pipeline`, house = 20k / 1024, LOD1 = 6k / 512): both inside. Draw calls per building: 2 to 4.

* **Guild hall**: the shingle roof is recoloured to royal blue (the reference's roof colour); cream plaster, timber and stone are
  kept. Two blue-and-silver banners hang from the balcony rail (rune diamond on each) as the Silverford guilds' colours
  (Masons and Runecarvers, Merchants, Adventurers).
* **Chapel**: the Church palette from poster 02: warm white ashlar, gold roofs and spire, gold trim, and a twelve-ray
  **Dawn Throne sun emblem** (`SunEmblem`, gold, faintly emissive) on the tower front above the door.
* LOD1 files are the shipped Meshy LOD1 meshes with the same recolour and the same accents.

Rebuild: `blender -b --python kingdom/tools/blender/make_r1_exteriors.py` (recolour rules and accent placement are in the script).
The door is on -Y in Blender (Godot +Z); the interior door node sits about 1.5 m in front of it (site layout is C1).

## Interiors (`scenes/interiors/`)

Built with the shared interior kit (`tools/blender/interior_kit.py`), the same conventions as the five existing interiors
(`scenes/interiors/README.md`): `PlayerSpawn`, `ExitDoor` (exit door is at +Z), `NPC_*` markers, vertex-baked lighting, box
colliders, at most two unshadowed OmniLights, `interior_room.gd` root.

| Scene | Room | Tris | Materials / draw calls | Lights | NPC markers |
|---|---|---|---|---|---|
| `guildhall_interior.tscn` | Silverford Guild Hall 13 x 10 m, ceiling 4.6 m: merchants' ledger counter with balance scale, runecarver's corner with a standing runestone (cyan glowing runes), mason's bench and stone blocks, contract board, meeting table, hearth, blue-and-silver banners, blue runner | 39,968 room + 8,474 props | see `tools_qa` numbers below | FireLight (flicker), RuneGlow (cyan) | `NPC_Guildmaster`, `NPC_Runecarver`, `NPC_Clerk` |
| `chapel_interior.tscn` | Chapel of the Dawn Throne, nave 9 x 14 m, ceiling 7 m: warm white ashlar, gold beams, cream flagstones with a sun mosaic, red-and-gold runner, six rows of pews, stepped dais and altar under a large gold **Dawn Throne sun** (glowing core), two saint statues, banners, candelabra | 29,960 | see below | AltarLight (flicker), NaveLight | `NPC_Priest` (on the dais), `NPC_Pilgrim` |

Both were checked in Godot with `tools_qa/region1/interior_shot.tscn` (draw calls, lights, colliders): see the numbers and
images in `docs/art/region1/` (`interior_guildhall_*.png`, `interior_chapel_*.png`) and the STATUS entry.

Wiring (cloud, work package C1): add an `InteriorDoor` with `interior_scene = "res://scenes/interiors/guildhall_interior.tscn"`
(or `chapel_interior.tscn`) to the two buildings, as described in `scenes/interiors/README.md`. After that
`--shot=interior_guildhall` and `--shot=interior_chapel` work through main.gd (its `interior_<name>` matcher checks
`interior_scene.contains("<name>_interior")`). Until then use the QA scene:

```
Godot --path kingdom res://tools_qa/region1/interior_shot.tscn --resolution 1600x900 -- \
  --scene=res://scenes/interiors/chapel_interior.tscn --out=docs/art/region1/interior_chapel [--npcs]
```

Rebuild: `RA_SAMPLES=24 blender -b --python kingdom/tools/blender/make_interior_chapel.py` (and `make_interior_guildhall.py`).
The kit gained two emissive material names (`RA_Sun` for the chapel sun, `RA_Rune` for the cyan runes; the preview renderer
treats them like `RA_Ember`).

Licences: see `kingdom/CREDITS.md` (Meshy community CC0 for the two exteriors; Quaternius Fantasy Props MegaKit CC0 furniture).
