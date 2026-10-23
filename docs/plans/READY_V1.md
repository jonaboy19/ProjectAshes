# Rising Ashes — Ready v1 (PC, Region 1): scope, gaps and cloud tasks

Opus plan, 2026-10-23, from `origin/claude/focused-curie-m09hbd` (caf75b39). Owner: "I want the game ready — playable, all mechanics, animations, things to do."

## Findings
- Code depth isn't the problem (≈100 realm + 70 sim modules, 220 test files). The problems: **reachability**, **joining systems**, and **uneven Acts II–V**.
- Sim-only (no player entry point): **founding a settlement** (`realm/founding.gd`), **taming** (`realm/followers.gd` ~369), holdings/conquest.
- **Two settlement systems** overlap: `founding.gd` and `build_kit.gd`; a claimed build grid never becomes a living settlement (`realm/settlements.gd`, `civilization.gd` not linked).
- Recruitment is E2E (`realm/recruitment.gd`, `ui/recruitment_ui.gd`, hooks in `world/village_services.gd:421,438,1456`); followers sim + Affairs UI (`39238d55`); follower combat/Down/permadeath unverified.
- Lordship path exists but is slow (`sim/lordship.gd grant()`, `sim/nobility.gd:482`, `ui/lord_council.gd`, `world/lord_hall.gd`).
- Act 1 E2E; Acts 2–5 need bot `[HOOK]`s (ageing, Kindling Night, teleports, Rift gate); Act 3 has no founding step.
- Hunting has no loop (corpse loot only). Fishing partial. Settings phone-oriented; no confirmed PC rebinding UI. Tutorial prompts touch-oriented.

## Ready v1 scope (M must, S should, L later)
1. M boot/menu/new game/slots/settings (graphics, audio, PC rebinding, mouse sensitivity)
2. M creator + birth → Ashford tutorial with PC key prompts
3. M Act 1 complete; Acts 2–3 without `[HOOK]` shortcuts; Act 3 contains the founding step
4. S Acts 4–5 to "Region 1 complete"; L finale Great Call
5. M fair combat (wolf, bandit, goblin, one boss), death/respawn
6. M recruit ≥ 3 companions; follow, fight, wait, work; Down + revive; permadeath (story difficulty → injury)
7. M found one camp → settlement row with food/housing/jobs/tiers Camp → Hamlet → Village
8. M lordship milestone (founded village tier 3 or crown grant) → lord hall, council projects, taxes
9. S one raid on your settlement, defended by followers/tamed guards
10. S taming of 1–2 species (Yield → Calm → follow/guard); L full minigame, Rune Bond, pens
11. M things to do: jobs, shops/trade, gathering, crafting, town side quests, discoveries/caves; S hunting loop, fishing, towers
12. M full late-game save/load round-trip
13. M AAA-scale NPC density (being done locally with the perf work)
14. M 60 fps PC HIGH, no freezes (local)
15. M release gate: headless bot plays 1–12
16. L conquest, sieges, tactical war, crown, royal suit, >1 settlement, mobile

## Rules for every CLOUD task
- Repo `github.com/jonaboy19/ProjectAshes`; base each branch on `origin/claude/focused-curie-m09hbd`; one branch per task; open a PR into `claude/focused-curie-m09hbd` (PR description ends with "🤖 Generated with [Claude Code](https://claude.com/claude-code)"); commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Do not edit** (owned by the local session): `kingdom/scripts/actors/player.gd`, `actors/character_animator.gd`, `population/villager.gd`, `army/soldier.gd`, `actors/monster.gd`, `actors/wolf.gd`, `actors/mount_controller.gd`, `actors/critter.gd`; world terrain `world/world_gen.gd`, `world_macro.gd`, `terrain3d_bridge.gd`, `terrain_backend.gd`, `terrain_streamer.gd`, `water_streamer.gd`, `hidden_valley.gd`, `region1/region1_terrain.gd`, `kingdom/data/world/macro/*`, `kingdom/tools/world/*`; `core/quality.gd` and `population/population_lod.gd` (local perf work); anything under `assets/`. If a hook in an owned file is unavoidable: ≤ 3 lines marked `# v1 hook (READY_V1)` and list it in the PR.
- No GPU in the cloud: run `godot --headless --path kingdom` with gdUnit (`-s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/... --ignoreHeadlessMode`), and bot runs `--headless -- --quality=low --qa=res://tools_qa/...`. Skip screenshots headless. The local GPU session verifies visuals after merge.
- Every PR: full gdUnit suite with no new failures, its own tests, 0 `SCRIPT ERROR` in its bot stage, one line in `docs/STATUS_LOCAL.md` under "Ready v1 (cloud)". PC focus only — no mobile work.

## Cloud tasks
**C1 Headless release harness** `claude/v1-harness`: `kingdom/tools_qa/v1/run_v1.sh` imports, runs the whole gdUnit suite headless, then `tools_qa/playtest_bot/playtest_bot.gd` headless with `PLAYTEST_STAGES` from an argument and `PLAYTEST_OUT=$OUT`. Make the bot headless-safe (`DisplayServer.get_name()=="headless"` → skip screenshots/fps sampling, keep CHECKs/errors). Exit non-zero on failed CHECK, SCRIPT ERROR or stuck stage. Check whether `docs/platform/boot_wiring_wip.patch` is applied; report, don't apply blindly. `kingdom/tools_qa/v1/README.md`. Accept: `run_v1.sh boot,intro,menus,st_birth,st_a1` passes headless on a clean checkout.

**C2 One settlement model** `claude/v1-settlement-unify`: `realm/build_kit.gd` `claim()`/`ensure_grid()` creates/attaches a `realm/founding.gd` record (`begin(pos, name, "player")`) and registers a settlement row via `settlements`/`civilization` — one id links grid, founding, settlement. `RealmHub` accessors `player_settlements()`, `settlement_of_grid(gid)`. Keep max-3 cap (taken holdings don't count). Tests `tests/test_v1_settlement_unify.gd`: claim → exactly one founding + one row; abandon clears all three; 4th claim refused; save/load keeps ids. Don't touch `build/build_mode.gd` visuals or `build_renderer.gd`.

**C3 Found-a-camp flow + Act 3 hook** `claude/v1-found-flow` (after C2): "Found a camp" = `B` action + top-level button in `ui/build_menu.gd`; site card from `founding.evaluate_site(pos)` (water, slope, danger, claim law `land_claim.gd`) → confirm → name → C2 claim. Step `a3_found_camp` in `data/region1/quests/r1_main.json` + lines in `r1_act3.json`; tutorial prompt in `tutorial_director.gd`; replace bot `[HOOK]`s for ageing/Kindling Night with an in-game "seasons pass" card (`ui/life_event_popup.gd`) triggered by sleep at story gates; bot stage `v1_found` (walk to valid spot, found, place 3 kit pieces). Accept: step-gate tests, `lint_quests.gd`, `run_v1.sh boot,st_load,v1_found` headless.

**C4 Settlement growth + ledger** `claude/v1-settlement-growth` (after C2): daily tick — labour from followers/settlers on `construction.gd` jobs; food stock/consumption; housing from built kit pieces; contentment; immigration of WorldSim settlers; tiers Camp → Hamlet (6 pop, 2 houses, food ≥ 5 days) → Village (15 pop, well, hall, contentment ≥ 0.5). `ui/settlement_ledger.gd` (`ashes_frame.gd` style): food days, contentment breakdown, jobs, tier checklist; opened from the Affairs tab. Tests: 120-day headless sim `tools_qa/v1/settlement_sim.gd` reaches Village by day 60–90 with 3 followers (CSV); starving lowers contentment; ledger values come from the sim.

**C5 Lordship milestone** `claude/v1-lordship` (after C4): tier Village → `sim/lordship.gd grant(idx, "founded")` once; `world/lord_hall.gd` spawns a hall at the player settlement (reuse `spawn_for`); `ui/lord_council.gd` projects/taxes there; title "Lord of <name>" via `sim/titles.gd` + notification card. Don't change the 0.045 tax value. Tests: grant once; council opens for the founded index; save/load keeps the title. Bot stage `v1_lord` (may `[HOOK]` fast-forward days).

**C6 Companions in combat, Down, the Call** `claude/v1-companions`: in `actors/follower_brain.gd`, `follower_manager.gd`, `realm/followers.gd`: followers engage the player's target via `combat/npc_fighter.gd`; at 0 HP Down 30 s; hold-E revive; otherwise permanent death, or 3-day injury when `Settings.difficulty == "story"`; a "Call" action using the existing summon delay. Animation only via existing signals/`character_animator` APIs; list missing clips in the PR. Tests: Down timer, revive, death/injury by difficulty; headless fight sim (follower + player vs 3 wolves) asserts follower damage. Bot stage `v1_recruit`: recruit 3 at the Ashford inn board, fight wolves together.

**C7 Named companions content** `claude/v1-companion-content`: three companions with bios, recruit dialogue and a 3-step personal quest each (format `data/region1/quests` / `kingdom/dialogue/<town>/`; name NPC, reward, mechanic, region tie; courtship decision: male–female pairs only). Accept: `lint_quests.gd` + gdUnit test each quest completes via `quest_runner`. Data only.

**C8 Taming v1** `claude/v1-taming` (after C6): yielded wolf/Stagborn shows "Calm" prompt (new `interaction/kinds/tame_target.gd`); hold-to-calm meter driven by trust/fear from `followers.gd`; success → tamed, role follow/guard; in the save; guard strength feeds C9. Signals/exports only on creatures — no edits to `wolf.gd`/`critter.gd`/`monster.gd` (3-line rule if unavoidable). Tests: tame-success curve, never-tamable list, save round-trip. Bot stage `v1_tame`.

**C9 Raid on the player settlement** `claude/v1-raid` (after C4 + C6): `realm/player_raids.gd` — weekly chance from `founding.visibility` + wealth, 14-day beginner grace; spawns a bandit `squad.gd` block at the edge + warning toast; defenders = followers + tamed guards; outcomes losses / stolen food / contentment. Tests: 300-day headless sim CSV; grace; size cap by tier; defended raids keep food. Bot stage `v1_raid` (may force via `[HOOK]`).

**C10 Hunting loop** `claude/v1-hunting`: skin/butcher action on animal corpses in `interaction/kinds/corpse_loot.gd`; yield by `sim/skills.gd` hunting; items in `sim/items_db.gd` (pelt, meat, antler); recipes in `sim/crafting.gd` (leather, jerky); a "Hunter" board job. Tests: yield table, skill gain, recipe chain. Bot stage `v1_hunt`.

**C11 PC controls + prompts** `claude/v1-pc-controls`: rebinding screen in `ui/frontend/settings_screen.gd` using `autoload/game.gd` InputMap helpers, conflict detection, reset to default, persisted via `settings_store.gd`; keyboard/mouse + gamepad glyphs for `tutorial_prompt_view.gd`, `interact_label.gd`, `world_prompt_icon.gd`; hide touch-only widgets (`virtual_joystick.gd`) on PC (note: PC HUD work already landed — check `docs/controls.md`, don't redo it). Tests: rebind round-trip, conflict rejection, glyph lookup per device. Don't touch `hud.gd` layout beyond hiding touch widgets.

**C12 Acts 2–5 playthrough fixes** `claude/v1-story-acts` (after C1): run bot `st_a2`…`st_a5` headless with the save chain; fix each blocker in `region1/r1_story_director.gd`, `story_quest.gd`, `data/region1/**`, `quests/**`; reduce `[HOOK]`s to the unavoidable (Rift power gate OK if the requirement is shown). `docs/qa/V1_STORY.md` with hook counts before/after; `st_a5` reaches "Region 1 complete". (C3 merges `r1_main.json` first; rebase.)

**C13 Combat balance numbers** `claude/v1-balance`: headless duel sim `tools_qa/v1/duel_sim.gd` (player level N vs wolf pack, bandits, goblins, via `combat_stats.gd` + `hit_resolver.gd`); targets win rate 70–85 % at the recommended level; wounded wolves flee slower than the player's run; danger tiers `data/region1/danger_tiers.json` + compass shield value. Data and `combat_stats` constants only.

**C14 Whole-state save soak** `claude/v1-save-soak` (last): `tests/test_v1_full_save.gd` builds a late-game state (3 followers incl. one Down, a 40-piece grid, a Village-tier settlement, lordship, 1 tamed wolf, an active raid, Act 3 progress), saves, loads, deep-compares every module via `realm_hub` serialisation. Accept: zero diffs, save ≤ 2 MB.

**C16 Interior doors** `claude/v1-doors`: `InteriorDoor` for every Ashford service lot (inn, smith, trader, guild, healer, manor) per `scenes/interiors/README.md`; fix station-over-door picking in `interaction_picker.gd`. Test: headless walk to each door, press E, interior loads.

(C15 NPC density is done locally inside the perf/freeze work.)

## Lanes
Start now in parallel: C1, C2, C6, C7, C10, C11, C13, C16. After C2: C3, C4. After C4: C5. After C6: C8. After C4 + C6: C9. C12 after C1. C14 last. C2/C3/C4 touch `founding.gd`/`build_kit.gd` → sequential. C3 and C12 both touch `r1_main.json` → C3 first.

## Local (GPU)
L-a after each cloud merge: bot stage windowed on HIGH, screenshots/frame sheets of new flows → `docs/qa/V1_VISUAL.md`. L-b follower/companion animations requested by C6/C8/C9 (revive kneel, Down pose, horn, calm lean-in, tamed wolf follow/guard) in the hot files. L-c NPC density look + perf. L-d running: freeze/60 fps, world W5, AAA mocap + wall/traversal realism. L-e final 60-min windowed v1 bot run on HIGH: fps p95, 0 freezes > 250 ms, flat memory.

## Release gate
`kingdom/tools_qa/v1/run_v1.sh` headless on every PR: `boot, intro, menus, st_birth, st_a1, st_save` → `st_load, v1_recruit, v1_hunt, st_a2, st_a3 (a3_found_camp → v1_found), v1_tame, v1_settle, v1_lord, v1_raid, st_save, st_load, v1_verify` → `st_a4, st_a5` (non-blocking until C12). Pass: all CHECKs, 0 SCRIPT ERROR, no stuck stage, `[HOOK]`s ≤ allow-list `kingdom/tools_qa/v1/hooks_allowed.txt`, gdUnit green. Local gate: same sequence windowed on HIGH, 60 fps p95, no freeze > 250 ms, reviewed screenshots. v1 ships when both pass and every M item is E2E.
