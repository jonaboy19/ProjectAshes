> **SUPERSEDED (2026-09-30, package C0).** This document predates the current game (Godot 4.6, 3D storybook look, Region 1 = the Ashford Vale of Valencious). The live design is `docs/RISING_ASHES_OPEN_WORLD.md` and `docs/regions/REGION_1_PLAN.md`; canon names are in `docs/regions/OWNER_DECISIONS.md`. Kept for history only.

# Kingdom — Design & Architecture (v0.1)

## Vision

A **pixel-rendered 3D** medieval sandbox. The world is real 3D (hills,
castles, stairs, first-person combat), rendered at low resolution with a
limited palette so it reads as pixel art. You start as a peasant and can end
as king, and the same world scales from walking into a tavern to commanding
thousands.

Style: low-poly geometry, small textures, 1/3 internal resolution upscaled with
nearest-neighbour, colour quantisation and dithering, directional sprite
impostors for distant crowds, modern light and fog.

## Camera scales (one world, no separate strategy map)

| Scale | Use | Status |
|---|---|---|
| First person | duels, archery, sieges | ✅ sword viewmodel |
| Third person | exploring villages | ✅ |
| Town | overview of a settlement or skirmish | ✅ |
| Command | army positions, banners | ✅ banners with unit counts |
| Realm map | regions and armies moving | ⏳ later |

## Simulation tiers

The key rule: **not every person is a node.**

```
WORLD DATABASE    all people, packed arrays, sliced updates     WorldSim (✅ ~5k now, built to scale to 100k)
LOCAL REGION      people of settlements within ~220 m           people_near() (✅)
VISIBLE           directional sprite impostors in MultiMeshes   PopulationLOD (✅ ≤300 per look)
NEAR PLAYER       ~24 animated, named characters                Villager (✅)
```

A person is a row: home, job, position, target, money, health, schedule phase.
They walk to work, earn wages, spend at market and go home at night. Indoors
people aren't drawn. Names are derived from their id, so they cost no storage.

## Armies

- **Squad** = one brain per formation: anchor, facing, order (Follow / Hold /
  Charge), slot grid. Enemy squads charge when hostiles enter their aggro radius.
- **Soldier** = cheap unit (not a physics body): walks to its slot, separates
  from neighbours, engages the nearest enemy, fights with KayKit animations.
- **LOD**: animated model within 45 m of the camera, 4-direction sprite beyond.
- Next: world-level armies as data (like people), sprite-only mid distance,
  archers, cavalry, morale and routing, and formation shapes (line, wedge, square).

## World

- 8 × 8 km (was 4 × 4 km; `WorldGen.WORLD_HALF = 4096`), deterministic from a seed; 64 m chunks streamed around the player (the streamed radius, LOD and memory do not depend on world size).
- Settlements are placed by rules (spacing, flat ground) and connected by a road
  network (minimum spanning tree); terrain is flattened for towns and cut for roads.
- Settlement meshes build within 520 m and free beyond 700 m.

## Progression

Peasant → Militia → Sergeant → Captain → Commander → Lord → King.
Rank caps army size; gold buys recruits (20 each). Clearing raider camps
gives gold and promotion; new camps appear near other settlements.

## Roadmap (basics → full game)

1. ✅ **Foundation:** pixel pipeline, streaming world, sim database, crowd LOD, squads, combat, 4 camera scales
2. **Combat depth:** blocking, stamina, archers and projectiles, hit reactions, better enemy AI
3. **Horses and mounted combat:** needs a CC0 horse (Quaternius has them; must be downloaded on a PC)
4. **Interiors:** enter taverns, homes and castle halls (KayKit Furniture Bits is CC0 and reachable)
5. **Economy and politics:** prices, trade caravans, taxes, lords and factions, owning land
6. **Big battles:** 500+ soldiers using data armies and sprite-only mid LOD, siege weapons
7. **Save/load**, a realm map, quests
8. **Mobile tuning:** profiling on a real phone, texture atlases, LOD distances

## Moving to Unreal later

What carries over directly:
- **Assets:** glTF/FBX models and animations import into Unreal as-is
- **Data:** settlement rules, job tables, rank tables (move them to JSON/CSV → DataTables)
- **Architecture:** the tiers above map to Unreal **Mass Entity** (data-driven crowds),
  **World Partition** (chunk streaming), Niagara (impostors and effects) and
  post-process materials (the pixel look)

What must be rewritten:
- All GDScript. Behaviour ports to C++/Blueprints, but it has to be written again.

Guideline: keep game rules in data files and keep systems small and separate
(as they are now), so the port is a translation job, not a redesign.
