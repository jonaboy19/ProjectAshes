# Region 1 balance report (L18 / C13)

Status: targets met for all five archetypes on 3 seeds each. Simulator: `kingdom/tools_qa/region1/balance_run.gd`. Short CI version: `kingdom/tests/test_balance_r1.gd`.

## 1. Summary

- The first run (the game as it was) missed soul tier, gear tier and career rank for almost every archetype, and had four money exploits.
- After the C13 changes every archetype meets: first house within 25 days (days 4-14), top soldier rank not before day 60 (day 79), soul tier 3, career rank 4-5, gear tier 2, fed on 100% of days.
- No infinite-money loop was found after the fixes (section 6).
- Nothing visual was touched. All changes are numbers, rules, data and one new career.

## 2. Method and player-model assumptions

The simulator runs the real autoloads (Life, economy and market, careers, soul, crafting, quests, story, combat stats). It does not use a separate maths model. A day is driven by emitting `WorldSim.hour_changed` hour by hour. Deterministic by seed (3 seeds per archetype).

Assumptions (all constants at the top of `balance_sim.gd`):
- A game day is 540 real seconds of play, skill 0.7 (a competent but not optimal player).
- Story pace 0.36 steps per day. Discoveries 0.4 per day.
- Fights use a win probability calibrated on the arena rates (goblin .92, wolf .9, bandit .75, guard .53, troll .30), scaled through CombatStats. A loss kills 40% of the time.
- Gear policy: fill empty slots with the cheapest wearable piece, upgrade to the cheapest piece of the best open tier, first house first.
- Only real hooks pay out. `ItemsDB.monster_drops` and `roll_loot` are not wired to kills in the game, so they are not simulated.
- Gear tier is the mean tier of 6 core slots (rounded, .5 down).
- Pickpocket bounties are not modelled headlessly (the Society model stays at 0).

Run: `Godot --headless --path kingdom res://tools_qa/region1/balance_run.tscn -- --days=100 --seeds=3 --arch=all --tag=X --out=DIR [--probe=all]`. Tables: `balance_tables.py`.

## 3. Before and after (100 days, mean of 3 seeds)

### Before (the game as it was, before3)

| Archetype | First house (day) | Career rank at day 100 | Top rank first reached (day) | Soul tier | Gear tier | Level | Gold at 100 | Earned per day (gross) | Net gold per day (1-30 / 31-60 / 61-100) | Deaths | Fed |
|---|---|---|---|---|---|---|---|---|---|---|---|
| farmer | 5 | 2 of 7 (Tenant Farmer) | - | 3 | 5 | 13 | 4271 | 219 | 33 / 23 / 65 | 0.0 | 100% |
| soldier | 10 | 5 of 5 (Lieutenant) | 79 | 2 | 3 | 15 | 1233 | 47 | 14 / 3 / 17 | 0.7 | 100% |
| wardwright | 16-18 | none | - | 2 | 1 | 17 | 393 | 24 | 2 / 1 / 6 | 7.0 | 100% |
| merchant | 8 | 3 of 6 (Caravan Owner) | - | 0 | 3-4 | 13 | 943 | 86 | 6 / 9 / 11 | 0.0 | 100% |
| adventurer | 4-5 | 2-7 of 7 (E-rank) | 68-78 | 2-3 | 3-4 | 18 | 1888 | 96 | 21 / 26 / 10 | 5.3 | 100% |

| Target | farmer | soldier | wardwright | merchant | adventurer |
|---|---|---|---|---|---|
| First house within 25 days | yes | yes | yes | yes | yes |
| Top rank not before day 60 | yes | yes | yes | yes | yes |
| Soul tier 3-4 | yes | NO | NO | NO | NO |
| Career rank 4-5 | NO | yes | NO | NO | NO |
| Gear tier 2 | NO | NO | NO | NO | NO |
| Level 13+ | yes | yes | yes | yes | yes |
| Fed 90%+ of days | yes | yes | yes | yes | yes |

| Archetype | Gold earned in 100 days by source (mean of the seeds) |
|---|---|
| farmer | ledger_trades 12267, farm_work_spot 6000, sales 2355, crop_sales 1244 (total 21866) |
| soldier | ledger_soldier 2428, sales 2086, corpse_gold 229 (total 4743) |
| wardwright | sales 2372 (total 2372) |
| merchant | ledger_trades 7931, trade_goods_sold 620 (total 8551) |
| adventurer | guild_commissions 6177, sales 2067, corpse_gold 1193 (total 9607) |

### After (after2)

| Archetype | First house (day) | Career rank at day 100 | Top rank first reached (day) | Soul tier | Gear tier | Level | Gold at 100 | Earned per day (gross) | Net gold per day (1-30 / 31-60 / 61-100) | Deaths | Fed |
|---|---|---|---|---|---|---|---|---|---|---|---|
| farmer | 14 | 4 of 7 (Employer) | - | 3 | 2 | 15 | 3071 | 54 | 12 / 38 / 39 | 0.0 | 100% |
| soldier | 10 | 5 of 5 (Lieutenant) | 79 | 3 | 2 | 18 | 3431 | 43 | 18 / 39 / 42 | 0.3 | 100% |
| wardwright | 5-6 | 5 of 5 (Elder Warden) | 81 | 3 | 2 | 19 | 3178 | 54 | 28 / 27 / 36 | 4.0 | 100% |
| merchant | 10 | 4 of 6 (Shopkeeper) | - | 3 | 2 | 17 | 1765 | 51 | 5 / 21 / 24 | 0.0 | 100% |
| adventurer | 4-5 | 4-5 of 7 (C-rank) | - | 3 | 2 | 23 | 5081 | 82 | 19 / 68 / 60 | 7.3 | 100% |

| Target | farmer | soldier | wardwright | merchant | adventurer |
|---|---|---|---|---|---|
| First house within 25 days | yes | yes | yes | yes | yes |
| Top rank not before day 60 | yes | yes | yes | yes | yes |
| Soul tier 3-4 | yes | yes | yes | yes | yes |
| Career rank 4-5 | yes | yes | yes | yes | yes |
| Gear tier 2 | yes | yes | yes | yes | yes |
| Level 13+ | yes | yes | yes | yes | yes |
| Fed 90%+ of days | yes | yes | yes | yes | yes |

| Archetype | Gold earned in 100 days by source (mean of the seeds) |
|---|---|
| farmer | ledger_trades 2445, farm_work_spot 1364, crop_sales 1272, sales 352 (total 5433) |
| soldier | ledger_soldier 2982, sales 1053, corpse_gold 252 (total 4287) |
| wardwright | sales 2797, ledger_trades 2642 (total 5440) |
| merchant | ledger_trades 3985, trade_goods_sold 1073 (total 5058) |
| adventurer | guild_commissions 6580, corpse_gold 778, sales 733 (total 8233) |


Milestones after C13 (days): career ranks farmer 15/45/75, soldier 9/23/44/79, Wardwright 11/27/51/81, merchant 28/57/93, adventurer E/D/C at 13-16/30-32/47-50. Soul tier 3 at days 53-77. Gear tier 2 at days 23 (soldier), 51 (adventurer), 63 (Wardwright), 71 (merchant), 85 (farmer). Five Hearts story step at about day 92.

The adventurer earns about 1.5x the others (68/60 net per day) and takes the risk (7 deaths in 100 days). This is intended.

## 4. Targets matrix

See the two matrices above (before: many NO; after: all yes). The same checks are encoded in `data/region1/progression_spine.json` and `scripts/region1/progression_spine.gd` (`evaluate`).

## 5. Problems found and fixed

| Problem | Evidence | Fix |
|---|---|---|
| Farm work spot paid 6 gold per 4 s hold, uncapped | up to ~360 gold/day, 6000 gold in 100 days | `scripts/sim/casual_work.gd`: 2 full-pay jobs per day, 1 at a third, then 0 |
| Trade-task wages grew with mastery | farmer ended with 16k gold at rank 2 | wage formulas capped (level 40) in `career_trades.gd` |
| Gear was not level-gated | farmer reached gear tier 5 | `Equipment.ENFORCE_LEVEL`; issued kit exempt |
| Raider camp bounty 120 + 60n uncapped | | `120 + 40*min(n,5)` up to 8 camps, then 40 |
| Pickpocketing | about 180 gold/day at 40 purses a day | heat rule in `pickpocket.gd`: now 37-39 gold/day (24-27% success) |
| Durable goods drained at the food demand rate | gear price x7.8, fence paid above market for 27 items | `DURABLE_DEMAND 0.1`, `demand_scale`; 0 fence items above market now |
| Adventurer guild S-rank by day 52-78 | | rank points rescaled, B-S gold lowered |
| Soldier lieutenant kit gave tier-4 gear | | Lieutenant kit is steelmail coif + hauberk |
| Soul and XP hooks missing (quests, duties, guild, jobs) | soul tier 0-2 | wired through `award_progress` and `soul.gain` |
| Wardwright had no career | 24 gold/day, no rank | new career (`data/careers/wardwright.json`, ladder, stone work) |
| Bug: `Life.on_wolf_killed` crashed on guild kill ids | | fixed in `life.gd` |
| Bread produce 6 | food security | 12 |

## 6. Money-loop probes

| Probe | Result |
|---|---|
| Same-market buy then sell | 0 profitable items of 278 |
| Fence prices | 27 items above market before, 0 after |
| Crafting arbitrage (list price) | 32 of 715 recipes positive, best +9 gold |
| Craft loop through real systems | at most 56.8 gold/day (healing_potion, 30 crafts/day) |
| Oracle merchant (zero travel, 6 trades/day) | 230 gold/day, flat over 30 days (market purses refill 15/day, cap 600) |
| Quest repeat farming | quests complete once; contracts at most 1 per 3 days, 3 open |
| Pickpocket | 37-39 gold/day after heat rule |
| Money growth check | growth ratio <= 1.6 and no source above 55% of income (spine targets) |

## 7. Town-kit quest rewards (30 towns, 90 quests)

Before: best-path town totals mean 80.6, sd 16.5. Outliers: ironmarch 120, thornfield 115, saltwick 113, kingsreach 112 (z +1.9 to +2.4). The Thornfield bribe paid 60 against 20 for the honest route.

After: honest totals mean 67.7, sd 7.5, max 80, median 67. Best-path max 89. Largest single honest quest 32. Corrupt premium at most 1.35. No outliers (outlier = more than 1.25x or less than 0.75x the median). Rules live in `tools/towns/reward_balance.py` and are applied by `gen_town.py` (`--all --check` passes) and `balance_rewards.py`.

## 8. Soldier pay against the other careers (gold/day)

| Career | Rank 1 to 5 |
|---|---|
| Soldier | 14.2, 21.6, 26.8, 32.8, 41.8 (before: recruit 11.2) |
| Wardwright | 33-47 |
| Farmer (by mastery) | 27.5-40.4 |
| Merchant | 31-54 |
| Old guard seats | 9 / 18 / 30 |

Weekly soldier wages are now [56, 91, 126, 168, 231] (were [35, 56, 84, 126, 196]). The soldier is the safest and most stable career, and pays like the others at equal rank. Top rank comes at day 79.

## 9. Progression spine and Rift gate

`data/region1/progression_spine.json` and `scripts/region1/progression_spine.gd` hold the end-of-region targets (soul 3-4, rank 4-5, gear 2, level 13+, house by day 25, top rank not before day 60, money bounds) and the Rift gate.

Rift gate: story step `a4_five_hearts` done, plus soul tier 3, gear tier 2, level 12. It is enforced by the `if` condition on `a5_rifts_edge` (new dialogue conditions `min_soul_tier`, `min_gear_tier`, `min_level`), and a hint toast fires when Five Hearts completes.

## 10. Existing tests changed on purpose

- `test_quest_objectives.gd`: Thornfield bribe gold 60 to 27 (rebalanced rewards).
- `test_guild_naming.gd`: new rank point thresholds and the 160-point add in the roundtrip.
- `test_economy_hour_jobs.gd`: one reference-algorithm line gained `demand_scale` (the economy CPU-pass test mirrors the market tick; this keeps it equal to the new rule).
- `test_region1_story_full.gd`: now asserts the Rift is shut at Five Hearts, readies the player, then continues.

## 11. Files changed

New: `tools_qa/region1/{balance_sim,balance_run,balance_probe}.gd`, `balance_run.tscn`, `balance_tables.py`; `scripts/sim/casual_work.gd`; `scripts/region1/progression_spine.gd`; `data/region1/progression_spine.json`; `data/careers/wardwright.json`; `tools/towns/{reward_balance,balance_rewards}.py`; `tests/test_balance_r1.gd`.

Modified: `autoload/life.gd`, `scripts/sim/{equipment,adventurer_guild,market,items_db,pickpocket,dialogue_runner}.gd`, `scripts/realm/{soldier,career_trades}.gd`, `scripts/quests/quest_runner.gd`, `scripts/population/crime_watch.gd`, `scripts/world/farm_work_spot.gd`, `scripts/core/main.gd`, `scripts/region1/{region1_glue,r1_story_director}.gd`, `scripts/ui/career_tasks.gd`, `data/careers/{ladders,soldier_career}.json`, `data/region1/quests/r1_main.json`, about 40 `data/quests/**/*.json`, `tools/towns/gen_town.py`, `tools_qa/region1/lint_quests.gd`, the four tests in section 10, and docs (REGION_1_PLAN, PROGRESSION_R1, region1 README).

## 12. Test results

Headless gdUnit. Exit 101 means orphans only.

| Test | Result |
|---|---|
| test_economy | 19 cases, 0 failures |
| test_career_soldier | 51 cases, 0 failures (orphans only) |
| test_careers_ladder | 20 cases, 0 failures |
| test_quest_objectives | 38 cases, 0 failures |
| test_town_kit | 34 cases, 0 failures (orphans only) |
| test_crafting_quality | 10 cases, 0 failures |
| test_balance_r1 (new) | 18 cases, 0 failures, under 60 s |
| Also checked: guild_naming, economy_hour_jobs, region1_story, region1_story_full, career_trades, career_ui, thornfield, realm_work, witness, ownership, items_db, life, soul, progression, homestead, scripts_parse, region1_hooks, hud_modes | all 0 failures |

## 13. Caveats

- The player policy and the fight model are assumptions. Real players will differ, mostly by being slower or faster at the same systems.
- The Wardwright is joined through the career screen only. There is no Legion clerk NPC yet.
- Pickpocket bounties are not modelled headlessly.
- New scripts have no `.uid` files until the editor imports them.
- Another agent's economy CPU pass ran at the same time. Its `test_economy_hour_jobs.gd` got one line changed (section 10).
