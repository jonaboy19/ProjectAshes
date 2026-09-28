# Open-world pattern study for Rising Ashes

**Reviewed:** 2026-09-27  
**Purpose:** identify proven ideas that can improve Rising Ashes while keeping its world, code and art original. This is a source study, not an instruction to import another game's code or assets.

## Recommendation

Do not replace Rising Ashes with another project. Keep its current Godot world, `WorldSim`, `CityPlanner`, actors, animation and art. Adapt a few architectural ideas: authored route graphs for distant people, strict simulation/rendering tiers, and movement requests that are separate from physical movement. Prove each change in the existing settlement route and on the target phone tier.

This repository checkout has no root `LICENSE` file. Before copying any third-party source code, confirm the project's distribution/license policy and review that code's exact license and dependencies. A model does not become free to reuse because it is recolored, remeshed or edited; art reuse needs a compatible grant. This study recommends original implementations and no external models or source files.

## Best-fit references

| Project | What the official sources show | Useful Rising Ashes pattern | Status and licence |
|---|---|---|---|
| [OpenMW](https://github.com/OpenMW/openmw) | The world editor documents per-cell pathgrids as connected waypoints. They complement navigation meshes, and their off-mesh links support NPC `AiWander`. | Build resident routes from the generated street graph, door paths and gate links. Keep those routes deterministic and local to a settlement; use physical navigation only for actors near the player. | Active open-world RPG engine. GPL-3.0. It requires the original Morrowind game data to play. Study the pathgrid concept; do not transplant code or game content. |
| [Veloren](https://github.com/Veloren/veloren) | The repository describes an actively developed open-world RPG; its code tree separates `world`, `rtsim`, `client`, `common` and server concerns. | Keep large-population schedules and world state cheap and separate from loaded character visuals. Promote only nearby people to detailed actors, preserving state during LOD changes. | Active community RPG. GPL-3.0. Rust/voxel architecture; useful for boundaries and scale, not a Godot drop-in. |
| [Ryzom Core](https://github.com/ryzom/ryzomcore) | Its official repository contains the MMORPG client, server and tools, and describes the project as community-maintained. | Study how authored data, runtime simulation and developer tools are kept distinct. This is useful for thinking about a future world-state/debug layer, not for importing its MMO stack. | Community project. Source is AGPL-3.0; art is dual-licensed CC-BY-SA-3.0 and FAL-1.3. Do not copy source or art without an explicit compatibility review. |
| [OpenGothic](https://github.com/Try/OpenGothic) | An open reimplementation of Gothic II; its README requires the original game data and says the project has replicated the original game. | Use it as a reference for how authored world events and NPC state can support a dense open-world RPG. Inspect specific systems before applying a pattern; the engine is C++ and Rising Ashes already has its own schedule/combat owners. | MIT-licensed engine code; the README requires separately owned Gothic II game data. No Gothic models, textures, dialogue or scripts should enter Rising Ashes. |
| [0 A.D. unit motion](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpUnitMotion.cpp) | The motion interface separates simulation requests from unit movement execution. | Keep intent (destination, schedule, reaction) separate from the movement method (route following, steering, `move_and_slide`). Preserve `WorldSim` as population truth. | The GitHub source mirror is archived after migration to Wildfire Games' Gitea; the game remains active (Release 28, Feb 2026). Most source is GPL-2.0-or-later; art is CC-BY-SA-3.0. Use the movement boundary as an idea; do not paste code into this repository. |

## The discontinued-project question

The older [REGoth repository](https://github.com/REGoth-project/REGoth) says the project was restarted and points to [REGoth-bs](https://github.com/REGoth-project/REGoth-bs). That makes the old repository a superseded predecessor, not a complete abandoned game to adopt. The replacement is an MIT-licensed Gothic I/II reimplementation and still depends on the original game's data. It may be useful for studying authored NPC state and world scripting, but it does not provide a legally self-contained game or art pack for Rising Ashes.

The GitHub mirror of [0 A.D.](https://github.com/0ad/0ad) is also archived, but the project itself is continuing on Wildfire Games' Gitea and shipped Release 28 in February 2026. It is an RTS rather than an open-world RPG, so its useful contribution here is the separation between unit intent and movement execution. The archived mirror is still useful for browsing historical code, not as a live upstream.

The mature open-world projects found in this review are mostly reimplementations, active community RPGs or engines whose runtime depends on another game's proprietary data. They can teach us how to organize a large world, but copying their characters or environments and editing them would not remove their licence or ownership conditions. Keep Rising Ashes' visual identity original and record any future asset's actual source and licence.

## Applying the ideas to the current handoff

1. **Navigation:** treat `CityPlanner`'s `streets`, `paths`, `lots` and gates as authored data. Add a deterministic route layer for distant simulated residents and verify every segment against actual collider footprints. Do not trust straight-line paths or rough circle tests as proof a building is clear.
2. **Crowd tiers:** preserve one authoritative destination/position in `WorldSim`. Keep distant people as data/impostors, mid-range people lightweight, and only a capped near set as physical actors. On promotion/demotion, preserve world position, heading and current intent.
3. **Motion ownership:** let AI choose intent, a route/steering layer choose a safe direction, and the actor controller resolve physical movement. Feed resolved position back to the authoritative simulation so it cannot pull someone through a wall on the next update.
4. **Animation and response:** choose animation from resolved movement and action state. Tie stun, dodge, knockdown, hit windows, movement slowdown and recovery to the clip timeline; measure foot contact at the actual game speed and inspect the result in a visual motion board and live route capture.
5. **Tools:** keep small debug views for routes, collision proxies, active physics counts, schedule states and animation samples. The existing collision-proxy gallery and animation review board are preferable to repeatedly opening the full game to inspect an isolated asset.

## Sources

- [OpenMW pathgrids and NPC wandering](https://github.com/OpenMW/openmw/blob/master/docs/source/manuals/openmw-cs/tables-world.rst#pathgrids)
- [Veloren repository and GPL-3.0 statement](https://github.com/Veloren/veloren)
- [Ryzom Core project description and code/art licences](https://github.com/ryzom/ryzomcore)
- [OpenGothic README and MIT code licence](https://github.com/Try/OpenGothic)
- [REGoth predecessor repository](https://github.com/REGoth-project/REGoth) and [replacement repository](https://github.com/REGoth-project/REGoth-bs)
- [0 A.D. unit motion interface](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpUnitMotion.cpp), [archive/migration note](https://github.com/0ad/0ad), and [current release/licensing](https://play0ad.com/)
- [Godot NavigationAgent guide](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html): navigation and avoidance are separate from physical collision.
