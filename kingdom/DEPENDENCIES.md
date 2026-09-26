# Dependencies (locked)

**Audit date:** 2026-09-26.
**Engine:** Godot **4.6.2-stable** (matches the dev PC; GodotGAS requires 4.6+).
**Method:** each addon was installed alone in a clean 4.6.2 project, the editor
was launched headless twice (first run registers classes), and script errors
were counted. Native (GDExtension) addons were checked by confirming their
classes load. Licences were read from each repo.

Rule: **addons do commodity work; Rising Ashes systems stay ours** (world
simulation, NPC minds, economy, careers, politics, runestones, ecology, war,
rumours, persistence). Important addons are wrapped behind project interfaces
(`RA*` classes) so they can be swapped.

## Adopted

| Addon | Version | Licence | 4.6.2 test | Android | Role in Rising Ashes |
|---|---|---|---|---|---|
| **LimboAI** | 1.8.1 | MIT | ✅ loads (`BTPlayer`) | ✅ arm64 binaries | Behaviour trees and state machines for *near-player* NPCs, monsters, soldiers |
| **Terrain3D** | 1.0.2 | MIT | ✅ loads (`Terrain3D`) | ✅ arm32/arm64 | Overworld terrain and LOD when we move from procedural to sculpted/baked terrain |
| **Sky3D** | 2.1 | MIT | ✅ 0 errors | ✅ (GDScript; Forward/Mobile/Compat) | Sun, moon, stars, clouds, fog and time of day. `RAWeather` drives gameplay effects on top |
| **G.U.I.D.E** | 0.14.0 | MIT | ✅ 0 errors (autoload `GUIDE` must be registered) | ✅ | One input layer for keyboard, controller and touch; gameplay sees actions only |
| **GdUnit4** | 6.2.1 | MIT | ✅ 0 errors | n/a (tests) | **Mandatory** tests for simulation systems |
| **GodotGAS** | 0.9.x (main) | MIT | ✅ 0 errors | ✅ | Tags, attributes, effects and abilities for powers, elements, Echoes, buffs, injuries, beast skills (prototype first) |
| **GLoot** | 3.0.2 | MIT | ✅ 0 errors | ✅ | Containers (backpack, chest, cart, warehouse, shop, loot). The economy owns quantities; GLoot handles item manipulation |
| **Dialogue Manager** | 4.1.0 | MIT | ✅ 0 errors | ✅ | Authored dialogue; our NPC state supplies the conditions |
| **QuestWeaver** | 1.5.0 | MIT | ✅ 0 errors | ✅ | *Authored* quest chains only. Emergent tasks come from `RAOpportunitySystem` |
| **Road Generator** | 0.9.3 (v0.6.0.gd4 tag) | MIT | ✅ 0 script errors | ✅ | Road geometry and intersections (plus Terrain3D shaping). Road safety, traffic and control are simulation data |
| **ProtonScatter** | 4.2.0 | MIT | ✅ 0 script errors (icons import on first open) | ✅ | Editor-time scattering for hand-authored areas (runtime scatter remains ours) |

## On hold (retest before adopting)

| Addon | Why |
|---|---|
| **Phantom Camera** 0.11.0.3 (MIT) | 1 editor-start error (`Dictionary` assigned to `Array`); our camera covers first, third, town and command already |
| **godot-sqlite** (MIT) | Release binary names couldn't be resolved from the cloud; the plan is SQLite as authoritative world state. Fetch the release zip on the PC or build from source |
| **SunshineClouds2** (MIT) | Only if Sky3D clouds aren't enough |
| **func_godot** 2025.12 (MIT) | 0 errors. Optional TrenchBroom workflow for interiors, forts and caves |
| **Gaea** 2.0 beta (MIT), **SimpleXTerrain**, **PCG Forge** | Procedural tools. Study or use editor-time only; not runtime dependencies |
| **GodotIK** 1.3.1 (MIT, last commit 2025-06) | Foot and hand IK later; check maintenance |
| **SaveState** | Borrow its ideas (atomic commit, backups, schema migration, versioning) for `RAPersistence` |

## Rejected (and why)

| Addon | Reason |
|---|---|
| **Beehave** | Duplicates LimboAI (never run two BT frameworks) |
| **Quest System** (shomykohai) | Duplicates QuestWeaver; 1 editor-start error |
| **Yggdrasil** | Uses `DrawableTexture2D`, which isn't in 4.6 (21 parse errors); also conflicts with organic progression. Revisit on a newer engine |
| **Expresso Inventory System** (main) | Now a C++ GDExtension needing a build; GLoot covers it |

## Integration notes

- Plugins that register autoloads in `_enable_plugin` (GUIDE, Dialogue Manager, QuestWeaver) must have the autoload listed in `project.godot`, because headless and CI runs don't call `_enable_plugin`.
- Native binaries included: Windows, Linux, macOS, Android. iOS and Web can be trimmed from exports.
- Keep each addon at its locked version; upgrades go through the same audit.
