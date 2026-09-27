# Open-world pattern study for Rising Ashes

**Reviewed:** 2026-09-27  
**Purpose:** identify mature world, NPC, movement, and scale patterns worth adapting to the existing game. This is a source study, not an instruction to import third-party code, models, animation, music, textures, dialogue, or maps.

## Recommendation

Keep Rising Ashes' Godot world, `WorldSim`, `CityPlanner`, population LOD, actors, combat, and art direction. The current pain is concentrated at system boundaries: schedule targets become straight-line motion, near/far representations do not share route constraints, building bounds become coarse boxes, and animation playback speed does not match actual movement. Fix those seams in small steps before considering a framework replacement.

The most useful ideas are:

1. **Connected local route graphs** for streets, gates, and verified building entrances.
2. **Clear simulation and embodiment tiers** so distant people remain cheap and close people can collide and react.
3. **Separate movement intent from movement execution** so the schedule selects a goal, route/steering selects a safe direction, and physics resolves the body.
4. **Authoring/debugging tools** that show paths, doors, collision shapes, schedules, and animation metrics without opening a full game session for every isolated question.

## Projects worth studying

| Project | Current status and license | Pattern to study | What not to assume |
|---|---|---|---|
| [OpenMW](https://github.com/OpenMW/openmw) | Open-world RPG engine/reimplementation; repository lists GPLv3. It requires the original Morrowind game files to play that game. | Its editor uses connected pathgrid points within world cells and connects important routes for NPC wandering. Map that idea onto `CityPlanner` street segments and gates; add entrance anchors only after checking each building's collision profile. | It is an engine for an existing game, not a ready-made Rising Ashes world. Its source license and Bethesda's world data are separate things. Do not copy Morrowind maps, scripts, art, or dialogue. |
| [Veloren](https://github.com/veloren/veloren) | Open-world voxel RPG in active development; GPLv3. Its code separates world, simulation (`rtsim`), client, and common systems. | Study how world-scale population work can stay separate from close character presentation, and how systems/data boundaries are organized. Preserve Rising Ashes' schedule truth while activating full bodies only nearby. | It uses Rust and voxel terrain and is a different visual/game design. It is a reference, not a drop-in architecture or art pack. Verify the exact license of any individual file before considering reuse. |
| [Skelerealms](https://github.com/SlashScreen/skelerealms) | Godot 4 open-world RPG framework; its README describes it as active and alpha, and links an MIT license. It provides composable actors, schedules, patrol paths, perception, and GOAP behavior, but explicitly lacks terrain, chunks/LOD, dialogue, quests, and combat. | Compare its actor packages, schedule/behavior ownership, and patrol concepts with Rising Ashes' existing `WorldSim` + near-actor split. Reproduce only the useful boundaries with Rising Ashes' own anchors, physics, navigation, and art. | It is not an advanced finished game or a plug-in world simulation. Its alpha API may break, and it does not solve this project's collision, streamed terrain, or LOD needs. Check individual file terms before any code reuse. |
| [godotdetour](https://github.com/TheSHEEEP/godotdetour) | Recast/Detour navigation and crowd implementation for Godot 3; repository says maintenance mode and admits testing was limited beyond its demo. MIT license. | Its historic separation of navmesh, agents, temporary obstacles, and debug drawing is useful when evaluating crowd/navigation requirements. | It uses Godot 3/GDNative assumptions, has limited testing, and predates Godot 4's integrated `NavigationServer`. Study the problem decomposition; do not add it as a dependency to the Godot 4.6 game without a demonstrated built-in limitation and a maintained compatible fork. |
| [Ryzom Core](https://github.com/ryzom/ryzomcore) | Community MMORPG framework; its repository states AGPLv3 for source and dual CC-BY-SA 3.0 / Free Art License 1.3 for art. | Study separation of authoring tools, client, server, and runtime simulation, plus the value of developer-facing world tools. | The source and art have distinct copyleft terms. It is not a license-safe pool of medieval models to recolor, and its MMO/server stack is beyond the needs of this local Godot project. |
| [OpenGothic](https://github.com/Try/OpenGothic) | MIT-licensed reimplementation focused on Gothic II; the README says Gothic 2 data is required and that the project supplies no game assets or scripts. | Inspect how a dense authored world can use persistent NPC states, world events, and scripts to make places feel authored. Keep any lesson at the system-design level. | Reimplementation code being MIT does not grant rights to Gothic's art, scripts, maps, dialogue, or other game data. Don't import those files. |
| [REGoth](https://github.com/REGoth-project/REGoth) → [REGoth-bs](https://github.com/REGoth-project/REGoth-bs) | The older GitHub repository says the project was restarted in a new repository; the old repo is GPLv3 and the successor lists MIT. The successor is still an engine reimplementation, not a standalone Gothic content pack. | Use the history as a reminder to check whether an apparently abandoned project has simply moved or restarted before treating it as discontinued. Its documented state/dialogue experiments can suggest questions for Rising Ashes' own behavior model. | An archived or superseded repository does not make its game content free to use. Do not copy Gothic assets or scripts. |
| [0 A.D. GitHub mirror](https://github.com/0ad/0ad) | This GitHub mirror is archived after the project migrated code hosting; 0 A.D. itself still publishes releases. The official site lists GPLv2 for code and CC-BY-SA 3.0 for art. It is an RTS, not an open-world RPG. | The unit-motion interface separates a request to move from the component that executes movement. Apply that ownership boundary: schedule chooses a target, route/avoidance returns intent, body movement resolves it. | GitHub's archive badge refers to this mirror, not a discontinued game. The code and art licenses are not interchangeable; CC-BY-SA art does not become proprietary simply by editing it. |

### What the “discontinued game” search found

The best-fitting projects from this scan are active RPG engines/games or reimplementations that depend on another game's separately owned content. The clearest archived GitHub example, 0 A.D., is an archived mirror whose project continues elsewhere. REGoth's predecessor says development restarted in a successor repository. I did not find a self-contained, retired, AAA-feature-complete open-world game whose code and complete art set can simply be brought into Rising Ashes. An archive badge by itself is not evidence that the whole project ended or that its assets are available for reuse.

Use these projects to learn how to structure routes, simulation tiers, authored events, and movement ownership. Keep the playable content original. Changing the colors, mesh density, or surface of someone else's model does not by itself clear its license or ownership conditions. For a future asset, record the actual source and terms beside the asset and check that the terms fit the game's distribution plans.

## Adaptation map for the current game

| Existing Rising Ashes owner | Adapted pattern | Proposed result |
|---|---|---|
| `CityPlanner` | Authored connected routes | Convert street endpoints/junctions and gates into a deterministic settlement graph. Connect to verified entrance/service anchors; test every edge against solid building profiles. |
| `WorldSim` | Large-scale schedule and persistent state | Keep schedule/goal selection inexpensive. Do not move all inhabitants as physics nodes. Store a stable goal identity and world position for representation changes. |
| `PopulationLOD` | Fidelity tiers | Preserve data/impostor tiers at distance. Only a capped near set gets full body collision, detailed animation, local reactions, and avoidance. Promote before an impostor reaches arm's length. |
| `Villager` and other actor controllers | Intent → route/steering → physics | A near body follows a route and safe velocity in the physics step; the resolved position flows back to the simulation when ownership changes. Never let straight-line schedule catch-up snap a visible person through a wall. |
| `SettlementBuilder` and `Assets` | Authored, inspectable collision profiles | Keep collision independent of render triangles. Use a few shapes around walls/posts, preserving doors and covered walk space; preview the real fitted mesh and proxy together. |
| Existing animation QA | Measurement before polish | Match clip ground speed to movement, inspect foot contact and transitions across every rig, and test the player route visually before approving shared clip changes. |

## References

- [OpenMW pathgrids](https://github.com/OpenMW/openmw/blob/master/docs/source/manuals/openmw-cs/tables-world.rst#pathgrids) and [OpenMW FAQ/data requirement](https://openmw.org/faq/)
- [Veloren repository](https://github.com/veloren/veloren) and its `LICENSE` / `rtsim` / `world` tree
- [Skelerealms README](https://github.com/SlashScreen/skelerealms) and [MIT license](https://github.com/SlashScreen/skelerealms/blob/master/LICENSE)
- [godotdetour README](https://github.com/TheSHEEEP/godotdetour) and [MIT license](https://github.com/TheSHEEEP/godotdetour/blob/master/LICENSE)
- [Ryzom Core license statement](https://github.com/ryzom/ryzomcore/blob/core4/README.md)
- [OpenGothic README and MIT license](https://github.com/Try/OpenGothic)
- [REGoth predecessor notice](https://github.com/REGoth-project/REGoth) and [successor repository/license](https://github.com/REGoth-project/REGoth-bs)
- [Archived 0 A.D. GitHub mirror](https://github.com/0ad/0ad) and [official 0 A.D. licensing/release page](https://play0ad.com/)
- [Godot 4.6 navigation overview](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_introduction_3d.html): navigation regions, agents, and movement are separate responsibilities.
