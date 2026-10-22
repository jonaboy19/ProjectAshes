# Foundation plan: finish the basics before the big simulation

The user decided this on 2026-10-05: **freeze the large-scale features until the foundation is complete and fun.** Frozen until the first milestone ships: the 13 kingdoms, dynamic politics and wars, settlement founding and civilization pressure (`CIVILIZATION.md`), advanced NPC personalities, monster civilizations, Soulbeast evolution, the economy simulation and generational change. Existing code for those stays as it is, and it gets bug fixes only.

**First milestone:** Thornfield village, the surrounding wilderness, one small town, one Rift and one military outpost. In that area the player can move, fight, talk, trade, sleep, eat, steal, work, explore, enter buildings, climb, take quests, meet NPCs, fight monsters, use a few elemental abilities, own basic equipment, live through day and night, and save and load.

The order follows the user's: movement → camera → interaction → animation → combat → abilities → NPCs → navigation → buildings → inventory → economy → crime → reputation → quests → time → save → streaming → village → wilderness → Rift → Soulbeast → career.

## Audit snapshot (2026-10-05)
Statuses come from two read-only code audits. DONE means the code exists and has tests.

| # | Area | Status | Main gaps |
|---|---|---|---|
| 1 | Player movement | PARTIAL | Codex's jump, land, run-stop and pivot were never run in the game. No climb, mantle, vault or ledge code (the clips exist in `UAL_Authored_Traversal.glb`). No stair step-up. No player knockdown or get-up. No walk/run starts or idle turn. |
| 2 | Mobile controls | PARTIAL | No default lock-on button. The context button only switches between attack and talk/take. No hold-for-heavy and no swipe or direction attack. Layout never checked on a portrait phone. |
| 3 | Interaction | PARTIAL | A duck-typed "interactable" group, a hard-coded dispatch in `main.gd`, and 8+ copied `_poll_interact` functions. Missing: ground items, corpse looting, chairs, ladders, village containers. |
| 4 | Buildings | PARTIAL | Interiors are swapped scenes. NPCs vanish at the door. One house layout. No shop interior. Beds only in the inn. Static interior light. |
| 5 | Weapon combat | PARTIAL | Sword only. No heavy attack. No spear, bow or staff. |
| 6 | Ability framework | DONE | No separate active-hit window, no Soul cost key. Projectiles are not pooled. |
| 7 | Animation framework | PARTIAL | Lower, upper and full-body layers and an air state machine exist. No armed (sword-stance) locomotion. No additive hit reactions. |
| 8 | Basic NPC | PARTIAL (strongest) | Utility brain, schedules and smart objects. No indoor navigation, no stairs, no door-to-interior walking. |
| 9 | NPC interaction | PARTIAL | Talk is a full-screen modal. The NPC doesn't turn to face you, and there is no camera shift. |
| 10 | Navigation | PARTIAL | A custom StreetGraph and no NavigationServer. No off-road, indoor or stairs routes. |
| 11 | Inventory | PARTIAL | No item ownership. Weight is not enforced. Categories don't match the design list. |
| 12 | Economy | DONE | No per-merchant stock and no shop hours. The merchant menu is hard-coded. |
| 13 | Crime | PARTIAL | The witness model is real. Missing triggers: theft, pickpocket, trespass. Arrest and jail are unverified. |
| 14 | Reputation | PARTIAL | NPC, city, guild and faction levels exist. No kingdom level. |
| 15 | Quests | PARTIAL | Two parallel systems. No generic composable objectives (Protect, Investigate, Wait, Observe are missing). |
| 16 | Time | DONE | Has hours as a float, with no discrete minute. |
| 17 | Day/night | PARTIAL | Shops never close. Interior light is static. Guards carry no lanterns. |
| 18 | Save | PARTIAL (solid) | Open-world monster kills are not persisted. |
| 19 | Streaming | PARTIAL | Terrain, building and NPC LOD all exist, but not as one cell system. |
| 20 | Pooling | PARTIAL | Hit effects, element effects, rings and ragdolls are pooled. Projectiles, loot, enemies and animals are not. |
| 21–25 | Slice content | PARTIAL | Thornfield has one named NPC and no village quest. No playable Soulbeast companion. Soldier career is not built to Scribe depth. |

## Work packages, in order
Every package ships with gdUnit tests. Phone budgets follow `ashes-performance` (LOW at or under 150 draws). Visual checks run on the local PC session.

**F1 Interaction framework.** One `Interactable` component with a stable id, verb, priority, range and an availability check. One `InteractionPicker` on the player scores the best option, including traversal and mount. Remove the `main.gd` dispatch chain and the copied `_poll_interact`. Add the missing kinds: ground item, corpse loot, chair (sit), bed, container, ladder, lever.

**F2 Traversal and context button.** Ledge, mantle and vault detection with shape casts, plus a traversal state in the player, using the authored clips. Stair step-up. The context button shows Climb, Vault, Talk, Mount, Take or Open from the picker.

**F3 Combat basics.** A hold-for-heavy attack. Move tables for spear, bow (aim and arrows) and staff. Player knockdown and get-up on heavy hits. Pooled projectiles and arrows. A default lock-on button on touch.

**F4 In-world conversation.** A bottom dialogue panel instead of the full-screen modal. The NPC stops and turns toward you (head look), the camera eases slightly, and nearby NPCs keep living.

**F5 Ownership, theft and trespass.** An owner on world items and containers. Taking owned items is theft, but only if someone witnessed it. Pickpocket. Trespass in private interiors at night. Shop hours. The arrest, fine and jail flow.

**F6 Buildings live.** NPCs walk through the door into the interior when the player is inside, using interior nav points. Modular interior layouts: house ×4, shop ×3, tavern ×2. Beds, chairs and containers in each. Interior light follows time of day. Guards carry lanterns at night.

**F7 Generic quest objectives.** One objective library (GoTo, TalkTo, Kill, Collect, Deliver, Escort, Protect, Investigate, Wait, Observe, Choose) used by both radiant and story quests. One Thornfield village quest line built from it.

**F8 Thornfield as a place.** 15–30 named villagers with homes, jobs and schedules, plus a smith, a shop and a tavern with interiors, a farm and livestock, a nearby wolf threat and a village quest.

**F9 Wilderness, Rift and outpost slice.** A road safety gradient, bandits, night danger and hidden spots. One hand-tuned Rift: entrance, safe camp, danger zone, mini-boss, exit. A military outpost for the Soldier career.

**F10 One Soulbeast companion.** Idle, roam, eat, sleep, notice the player, build trust, follow, fight beside the player, defend territory and flee.

**F11 Soldier career at Scribe depth.** Ranks, pay, orders, promotion, a companion squad, and outpost duty.

**F12 Pooling and streaming pass.** Pooled loot, critters and enemies. One cell manager over terrain, buildings and NPCs, with FULL, LOW and UNLOADED tiers.

**Codex (animation owner):** run Codex's nine-step validation of jump, land, run-stop and pivot in the game. Wire walk/run starts, walk stop, sprint skid and idle turn. Add sword-stance locomotion and additive hit reactions. Make the traversal clip timing match F2.

## Status 2026-10-06: all twelve packages landed
All of F1–F12 are on `claude/focused-curie-m09hbd`. A playtest bot played the Thornfield slice through the real main scene and every stage passed: talk, the three brewery quests, interiors, witnessed and unwitnessed theft, shop hours, vault/mantle/ledge/ladder, heavy attack, bow and lock-on, enlisting and muster, the Rift, the Soulbeast's trust, and save/reload. Visual passes followed, checked in the real game. The full suite is 2243 test cases with 0 failures via `tools/qa/run_tests.sh`.

Still open:
- **Codex:** validate the jump, land, run-stop and pivot work in the game; work through the F2/F3 feel list in the handoff; add armed locomotion and additive hits.
- **Local PC:** check touch layout and thumb reach on the S22; GPU look pass on the slice; release-size work (the debug APK is 964 MB).
- **Performance:** 60 buildings finishing near a town in one `catch_up` cost about 600 ms, because each one registers with that town's `StreetGraph`. Batch the registration.
- **Characters:** the noblewoman_cape and soldier_shield_sword Meshy rigs need hand-set landmarks.
- **Rift:** the "indexing did not unpair geometries from light" engine error appears there.
