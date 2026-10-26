# Labyrinths (Aincrad-style multi-floor dungeons)

Owner brief: SAO-like labyrinth floors, each floor themed, with a safe room, a mid-boss, a boss room behind a big door; killing the boss unlocks the next floor; monsters, traps, treasure, secret rooms; difficulty rises per floor.

## Code (`kingdom/scripts/dungeon/`, no class_names, preload like the rest of the repo)
| File | Job |
|---|---|
| `labyrinth_data.gd` | Floor themes (creature pools per tier, trap kinds, boss tables, SurfaceQuery materials), 16 hand-designed ASCII room templates, trap catalogue, scaling formulas, the 3 labyrinth definitions. |
| `labyrinth_gen.gd` | `generate_floor(labyrinth_id, world_seed, floor_index)` -> layout dictionary. Pure data, deterministic. |
| `labyrinth_state.gd` | Progress + save: floors unlocked, mid-boss/boss cleared, warp stones, chests, traps, secret doors, kills (monsters respawn after 14 days, bosses never). `serialize()` / `deserialize()` JSON-safe. Layouts are never saved: id + seed + flags rebuild the world. |
| `labyrinth_sites.gd` | Entrance hooks (`labyrinth_for_site(site)`, `plan(sites)`) and the per-save registry (`state(id)`, `enter(id, floor)`, `serialize()`). |
| `labyrinth_build.gd` | Placeholder geometry: 2 merged meshes per floor, tagged StaticBody3D colliders (SurfaceQuery), markers (creatures, chests, traps, stairs, warp), gate nodes (boss door, secret doors), baked NavigationMesh. |

## Generator rules
- Chain: start (arrival stairs) -> combat -> **safe room (warp stone)** -> combat -> **mid-boss** -> combat -> **boss** (stairs down in the arena). Built room by room, so the path exists by construction; `validate()` re-checks it on the grid.
- Side rooms: 1-2 treasure vaults, 1-2 trap galleries, 0-2 extra combat, 1-2 **secret rooms** (hidden door in a room wall, never needed for progress, a loose-brick tell cell in the corridor).
- Boss room has exactly one entrance, a big door (`boss_door`) that stays shut until the mid-boss dies. Reachability honours gates (`reachable(layout, {"secret": bool, "boss_door": bool})`).
- Corridors are A* routed around every room box with a one-cell ring, so a corridor only touches a room through its own door cell (tested). Rooms keep >= 3 cells apart. Optional loops add shortcuts (never to start, safe, boss or secret rooms).
- Content per floor `f`: creature count, trap damage and loot budget scale `1 + 0.09 f`; tier (1-4) climbs across the labyrinth; level = `level_base + f * level_step`; elites grow 5% -> 35%; boss hp x`5(1+0.09f)`, mid-boss x`2.5(1+0.09f)`. Loot comes from `DungeonGen.roll_loot` (existing item table), creature kinds are those of `interiors/dungeon_creature.gd` (a test checks every kind exists).
- Labyrinths: `deepdark` (10 floors, Deepdark Warren / Dunhallow), `ironmarch_deeps` (8, the Ironmarch mines), `rift_ruins` (8, Riftglass / Scarlight / rift ruins). `labyrinth_sites.plan(WorldGen.sites)` finds an entrance for the mines and the Rift today; Deepdark is a camp in `data/world/real/layout.json` only (not yet in `WorldGen.sites`).

## Not done here (needs a runtime pass, listed in the PR)
- A runtime director that instantiates `DungeonCreature` / chests / trap Areas from the markers and the entrance door in the world; this PR ships the data, state and geometry layers and their tests.
- Wiring `Sites` registry into the save (`Life.realm` / exploration) and the entrance doors into `region_caves_view.gd`.
- Art: swap the box meshes for the KayKit Dungeon Remastered kit (`floor_tile_*`, `wall_*`, `pillar`, `column`, `stairs`, `chest`, `barrel`, banners, `torch`); every needed piece is already in `assets/incoming/kaykit/dungeon-remastered` (needs an editor import and a `.gdignore` removal / copy to `assets/kaykit/`).
