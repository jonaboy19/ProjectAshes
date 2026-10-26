# Rising Ashes: gameplay mechanics audit (2026-10-26)

Scope: every gameplay mechanic outside animation clips, rated against an AAA checklist (AC / KCD / RDR2 feel).
Ratings: **Missing** = no code. **Stub** = data or partial code only, or nothing for the player. **Works** = playable, below AAA. **AAA** = shipping quality.
Paths are relative to `kingdom/`. This audit comes from grep plus code reading on branch `aaa/finish`. Rows marked *(built)* were changed in this pass.

## 1. World semantics
| Mechanic | Rating | Where / note |
|---|---|---|
| Central surface query (point/ray to kind, material, slope, flags) | Works *(built)* | `scripts/world/surface_query.gd`: `ground()`, `probe()`, `describe()`, `ledge_ahead()`, `tag()` |
| Ground material classification | Works *(built)* | terrain from `WorldGen.color_at` paint weights (the Terrain3D backend paints from the same weights, so this is the control-map lookup), plus biome (snow, marsh = mud), shore = sand, rain on dirt = mud, water depth |
| Collider material tags | Works *(built)* | `SurfaceQuery.tag()` on town walls, building lots, interiors (wood floor), hall (stone), build kit (wood), caves, towers, street props; terrain chunks in group `terrain`; name-hint fallback for the rest |
| Wall / ground / ceiling by normal | Works *(built)* | `kind_for_normal` (walkable 45°, ceiling below n.y −0.5) |
| Climbable / vaultable / ledge flags | Works *(built)*, traversal does not read them yet | flags on colliders (`surface_climbable` / `_vaultable` / `_ledge`); `traversal.gd` still probes geometry only. a93 wires it in S3.2 |
| Walkable slope limit + sliding | Works | `ground_realism.gd` slope slide (40°+), slope lean |
| Step-up | Works | `traversal.gd step_height/step_assist` |
| Water: wading / swimming | Works | `player.gd` SWIM_* (slow wading past knee depth, float + stamina drain past chest depth); no swim animation polish |
| Interaction volumes | Works | `scripts/interaction/` (container, ladder, lever, seat, ground_item, corpse_loot, clue) |

## 2. Surface feedback
| Mechanic | Rating | Where / note |
|---|---|---|
| Footstep audio per material | Works *(built)* | before: the player played grass/stone only. Now `surface_feedback.gd` gives wood/stone/cobble/dirt/leaves/grass/water from colliders + terrain. Snow uses Kenney CC0 `footstep_snow_*` (files staged, need an editor import before commit; falls back to grass until then) |
| Footstep particles (dust/snow/mud/splash) | Works *(built)* | `SurfaceFeedback._puff` (18 m camera range, at most 12/s) |
| Footprint decals | Missing | snow/mud prints would be next (`ground_decals.gd` exists for combat) |
| NPC footsteps by material | Stub | `villager.gd _footstep` uses its own cached `_surface`; switch it to SurfaceQuery (afc/a93 area) |
| Foot IK on slopes/stairs | Works | `procedural_rig.gd` TwoBoneIK legs (a93) |
| Body lean | Works | `ground_realism.gd` slope lean, `player.gd` accel lean |
| Landing impact / fall damage | Works *(feedback built)* | `player.gd _land_jump` (roll / hard land / damage); now with a per-material landing sound + puff |

## 3. Traversal detection (a93 owns)
| Mechanic | Rating | Note |
|---|---|---|
| Vault / mantle / ledge hang / ladder | Works | `traversal.gd` probes + clips (F2 set) |
| Free climbing on climbable walls (AC) | Missing | `climbable` flags now exist; needs a climb state + clips (`Mx_Trav_Climb_*` are probation) |
| Cover | Missing | no cover system (fine for melee-first v1) |
| Doors | Works | `interior_door.gd`, `door_pass.gd`, `dungeon_door.gd` |

## 4. Survival loop
| Mechanic | Rating | Where / note |
|---|---|---|
| Gathering: trees/rocks/plants | Works | `gather_run.gd`, `forage_nodes.gd`, `ore_vein.gd`, `sim/gathering_items.gd` |
| Hunting / fishing | Works | `sim/hunting.gd`, `fishing_spot.gd` (Mixamo fishing clips wired) |
| Inventory + weight | Works *(built)* | `needs.load_ratio` from `menu_data.carry_weight / carry_capacity`; over capacity = speed 0.75 to 0.45 and stamina regen x0.7, HUD shows "Overburdened" |
| Crafting | Works | `sim/crafting.gd`, `ui/crafting_screen.gd` |
| Hunger / fatigue | Works | `sim/needs.gd` |
| Thirst | Works *(built)* | `needs.gd` water (25 h to empty), auto-drink when wading > 0.4 m, damage when parched |
| Body temperature | Works *(built)* | `needs.gd` warmth from night / snow / rain / swim / altitude, shelter (interiors) and fire (`fire_hazard` group within 4 m); penalties to regen and speed, damage when freezing; HUD card shows all four needs |
| Sleep | Works | `needs.sleep`, `bed_prop.gd` |
| Day/night, weather | Works | `world_sim.gd`, `weather.gd` (Markov daily schedule, rain/snow) |
| Weather effects on gameplay | Stub, improved *(built)* | rain now wets you (warmth), dirt turns to mud underfoot; no slippery-surface or visibility gameplay yet |
| Cooking / campfire for the player | Stub | campfires exist in camps/dungeons; no player cooking station |

## 5. Combat
| Mechanic | Rating | Where |
|---|---|---|
| Hit detection, stagger, block/parry, stamina | Works | `combat/hit_resolver.gd`, `combat_stats.gd`, `knockdown_state.gd`, `combat_feel.gd` |
| AI | Works | `npc_fighter.gd`, LimboAI, `creature_attack_tokens.gd` |
| Damage by armour | Works | `combat_stats.gd`, `sim/equipment.gd` |
| Hit sound by surface (sword on stone wall) | Stub | `hit_wood/metal/flesh` exist; misses on walls could use `SurfaceQuery.probe` |

## 6. Interaction and settlement
| Mechanic | Rating | Where |
|---|---|---|
| Unified interact prompt | Works | `interaction_controller.gd`, `interact_label.gd`, `world_prompt_icon.gd` |
| Pickup, containers, doors, NPC talk, trade, recruit | Works | `kinds/*`, `talk_session.gd`, `trade_screen.gd`, `recruitment_ui.gd` |
| Building (Palworld-style kit) | Works | `build/build_mode.gd`, `build_renderer.gd`, `realm/build_kit.gd` |
| Property / homes | Works | `sim/property.gd`, `realm/homes.gd` |
| Drink at wells / water skins | Missing | only wading drinks for now; needs a `well` interaction kind + waterskin item |

## 7. Systems polish
| Mechanic | Rating | Where |
|---|---|---|
| Save/load | Works | `sim/save_manager.gd`; needs water/warmth are saved via `RANeeds.serialize` (old saves default to 85/80) |
| HUD, map, minimap, compass, quests, settings | Works | `ui/hud.gd`, `world_map.gd`, `minimap.gd`, `compass.gd`, `quests/*`, `settings_menu.gd` |
| Audio mix | Works | `audio_director.gd` buses, interior bus, underwater |
| Physics / perf | Works, below target | Jolt; perf is a separate lane (PERF60_BRIEF) |

## Remaining gaps, ranked by player impact
1. Traversal reads the SurfaceQuery flags (climbable / vaultable walls, AC free climb). a93 (S3.2).
2. ~~Encumbrance~~ done (M2).
3. Snow/mud footprint decals, and NPC footsteps on SurfaceQuery.
4. Wells / waterskin drink interaction; player campfire + cooking.
5. Weather gameplay: slippery wet stone (lower slide threshold), rain lowers NPC hearing (`weather.noise_mult` exists).
6. Combat: surface-aware miss/impact sounds and sparks on walls.
7. Cover (low priority for a melee-first game).
