# Dungeon Towers (Aincrad-style)

Status: implemented (Region 1: the Ashfall Spire). Natural dungeons/caves are a different system (dungeon_gen.gd).

## Fantasy
A colossal ancient spire of stone and glowing runes stands over Region 1, visible from Kingsreach and far beyond.
Every floor is a self-contained labyrinth with its own theme, a SAFE ZONE (rest, save, merchant) and a BOSS ROOM behind a
great door. Beat the floor boss and the next stairway opens, a teleport gate wakes, the whole realm hears of it.
Floors are NOT natural caves: they are built architecture (corridor grids, vaults, halls) dressed in a theme.

## Structure
- Ashfall Spire: 20 floors, floor level 5 -> 60 (`TowerData.floor_level`). Data-driven (`TowerData.TOWERS`), a second
  tower is one more row.
- Base camp at the foot: vendors, scout, teleport gate, NPC adventurer parties, door into floor 1.
- Floor = seeded grid maze (recursive backtracker + loops) of 8 m cells. Fixed rooms: arrival stairs (+gate), safe zone
  (dead end near the start), boss arena (3x3 cells, big door, unlocks stairs up). Chests, traps, mobs seeded per floor.
- Themes (cycled): forest, flooded, crystal, clockwork, snow, ruins. Each has palette, fog/ambient, props and mobs.

## Rules
1. Floor f is enterable when floor f-1's boss is dead (by the player OR by an NPC party).
2. Teleport gates: the gate in each floor's arrival room (and at base camp) lists every ACTIVATED floor (reached by stairs
   or teleport). Gates only ever reach floors <= highest cleared + 1.
3. First clear (whoever does it first) is recorded once. The player's first clear gives the Last-Attack style unique drop
   (a relic with a passive bonus), fame, a floor-clear banner and a rumour (`society.add_rumour("tower_clear")`).
   A party's first clear makes the rumour about them and opens the stairs, but the relic is gone. Rematch ("echo") is
   always possible on cleared floors: normal loot, no relic.
4. NPC parties (4 named, seeded) climb on the day tick, race the player, fail and die/recover, learn from every failed
   attempt (shared boss attempts raise everyone's odds).
5. Death in the tower: lose ~10% gold and ~30% of the loot gathered this run, a minor injury, wake at base camp. No
   permadeath. Leaving via safe zone stairs banks the loot.
6. Bosses have patterns with telegraphs, phases at 66/33% HP, an enrage timer or 15% HP. Patterns are learned: each
   attempt (or scout report, or a party's debrief) reveals one; known patterns show their name and give a longer warning.
   Knowledge is stored as `society.learn("tower:<id>:<floor>:<pattern>")`.
7. Party: followers.party() members come along as allies (abstract fighters), boss HP scales with party size.

## Performance
- Spire: near mesh (full), mid mesh (simple) and a billboard impostor by visibility ranges; always built at boot (one
  MeshInstance each, 3 draw calls in total when far), camera far raised to 3.6 km (only ever raised).
- Floors are built on entry and freed on exit, merged meshes per material + MultiMesh props, <=150 draws, <=10 lights,
  build time budget tested (`tests/test_towers.gd`).

## Modules
| file | role |
|---|---|
| scripts/realm/towers.gd | realm module: progress, gates, first clears, NPC parties, knowledge, relics, save |
| scripts/world/towers/tower_data.gd | static data: floors, themes, bosses, levels |
| scripts/world/towers/floor_gen.gd | layout (pure, deterministic) + interior builder |
| scripts/world/towers/floor_boss.gd | bosses and floor mobs (phases, telegraphs, enrage, HP bars) |
| scripts/world/towers/tower_site.gd | exterior spire, base camp, runtime (enter/leave, party, death) |
| scripts/world/towers/tower_ui.gd | floor map, door prompt, clear banner, teleport menu, vendor |
| scripts/world/towers/tower_planner.gd | region site planner (own RNG stream) |

## Hooks other owners must add (one line each)
- main.gd: `world.add_child(preload("res://scripts/world/towers/tower_site.gd").new())` after the Region1 hook.
- society.gd DEED_TEXT: `"tower_clear": [...]` lines (falls back to "generic" until then).
- items: `loot_table(tier, theme)` (optional), relic prototypes `tower_relic_<n>` (optional).
