# Progression spine: Region 1 balance

Owner systems: `scripts/sim/progression.gd` (level 1-500), `scripts/realm/cultivation.gd` (10 realms x 9 stages, hub module `cultivation`),
data in `data/progression/levels.json` and `data/progression/cultivation.json`.
Sim: `docs/balance/data/progression_sim.gd` (headless, no world). Tests: `tests/test_progression.gd`, `tests/test_cultivation.gd`.

Design brief: "no matter the path you always need to cultivate"; Region 1 caps at level 50-60; nobody clears Region 1 in a few hours, it takes weeks.

## 1. Level curve

`xp_to_next(L) = round(70 * L^p(L) + 120 * L, 10)`, p = 1.75 up to level 60, rising smoothly to 2.25 at 500. Stored as a 499-entry table.

| Level | XP to next | Total XP to reach |
|---|---|---|
| 10 | 5,140 | 17,800 |
| 30 | 30,520 | 332,540 |
| 50 | 71,810 | 1,310,860 |
| 55 | 84,360 | 1,694,670 |
| 60 | 97,740 | 2,142,900 |
| 100 | 394,230 | 11,186,250 |
| 500 | (cap) | about 8.2 billion |

An award is `xp_to_next(content_level) * activity.frac * magnitude * diff * repetition * saturation * pace * global_scale`:

* **Activities** (fraction of a level, before scaling): kill .0035, discovery .03 (once per place), quest .07 (once per id), job shift .010, craft .0014, build .020, drill/school session .0055, cultivation breakthrough .06 (once per stage, magnitude grows with realm), meditation hour .0004, gather .0007, lore .02 (once), rift encounter .05.
* **Diff factor**: content 1 level under you pays -10 percent per level (floor 5 percent); content above you pays +4 percent per level (max 1.4).
* **Repetition decay** (same activity + subject, per in-game day; half the count fades per day for kills): kills x0.955 per repeat (floor 6 percent), crafts x0.97 (floor 5 percent), job shifts x0.45 (floor 10 percent), drill sessions x0.72, builds x0.80. Discoveries, lore and breakthroughs pay once per id.
* **Pace curve**: multiplier 1.4 at level 1 easing to 0.7 at 55 (and falling beyond), so hours per level rise from about 0.5 h to about 2.5 h.
* **Region saturation** (Region 1): 100 percent to level 50, easing to 60 percent at 55, then a cliff: 15 percent at 56, 4 percent at 57, 1 percent floor from 58, and **0 at the hard cap, level 60**. Regions 2-7 and the Far Reaches have their own soft/hard caps (110/120, 170/185, 235/250, 300/315, 360/375, 430/445, 500).
* **Level gives little**: +7 HP, +1.5 stamina, +0.6 attack, +0.45 defence per level, 1 attribute point per level plus 2 every 5 levels, and `power_share = 1 + 0.006 * (L-1)` (level 50 = x1.29). Cultivation and gear are the big multipliers.

Grind check (unit test): 12 in-game days of 600 wolf kills per day stay under level 25.

## 2. Cultivation ladder

Ten universal realms, nine stages each: Body Tempering, Qi Gathering, Foundation, Core Formation, Nascent Soul, Spirit Severing, Void Sovereign, Ascendant, Immortal Ascension, Origin Dao.
Each path renames them (sect keeps the donghua names; magic = Attunement, Mana Awakening, Circle Foundation, Mana Core...; bending = Breath Discipline, Elemental Attunement...; knight = Conditioning, Aura Awakening...; beast = Bond Sensing, Bond Awakening...) and has its own diagram.

| Realm | Meditation hours per stage at density 1.0 (stage 1 -> 9 grows x1.8) | Level gate (stage 1 -> 9) | Base success | Boundary insight | Boundary catalyst |
|---|---|---|---|---|---|
| 1 Body Tempering | 28 | 1 -> 9 | 80% | 5 | none |
| 2 Qi Gathering | 110 | 10 -> 28 | 72% | 20 | 3 spirit herbs (grade 1+) |
| 3 Foundation | 340 | 30 -> 54 | 65% | 60 | 2 monster cores (grade 1+) |
| 4 Core Formation | 760 | 62 -> 92 | 58% | 160 | 1 pill (grade 2+) |
| 5-10 | 1,800 ... 112,000 | 95 ... 500 | 52% ... 25% | 400 ... 9,000 | rarer cores and pills |

* Level 62 is needed to enter Core Formation and Region 1 hard-caps at 60, so **Region 1 covers realms 1-3**.
* **Meditation**: hours x location density x path affinity x path speed. Daily absorption curve: first 4 h full, next 4 h at 35 percent, then 10 percent, so skipping time cannot replace play. Locations: town 0.6, wilds 1.0, drill yard 1.0 (+0.5 knight), library 1.1 (+0.5 magic), river shrine 1.4 (+0.6 bending), wild grove 1.4 (+0.6 beast), waterfall 1.6, sect hall 1.8 (+0.6 sect, needs sect access), crystal spring 2.0, the Hidden Vale 2.2 (+0.2 to +0.3), rift edge 3.2 (14 percent backlash per 4 h, needs the rift seen).
* **Resources**: a grade-g herb/core/pill is worth 3/5.4/9 x 3^(g-1) meditation hours regardless of realm; toxicity builds (0.15/0.20/0.35 each, -0.3 per day) and over 1.0 gains fall to 30 percent with a deviation risk. Beast bond cores x1.5.
* **Insight** (exploration 0.8 per new place, lore 2, quest 1.5, teacher 3, trial 2): spent at minor bottlenecks (stages 3 and 6, 20 percent of the realm cost) and at realm boundaries.
* **Breakthrough chance** = base - 1 percent per stage - 10 percent at a boundary + up to 15 percent qi overflow + 2 percent per extra insight + 12 percent breakthrough pill + 5-8 percent qi-rich place + 5 percent master present + 4 percent per previous failure - 15 percent strain - 10 percent toxic - 10 percent second path +/- 15 percent tribulation result. Clamped to 5-97 percent.
* **Failure** never kills and never loses the stage: setback (-30 percent qi), strain (-40 percent qi, 6 days of half speed and worse odds), qi deviation (-60 percent, 12 days no cultivation), backlash (-80 percent, 20 days, insight loss; only after a boundary attempt about 5 percent of failures, minor about 1 percent). Insight is half-refunded.
* **Tribulation trial** at realm boundaries is optional; clearing it with a score of 0.6+ grants a permanent "tempered" bonus (+3 percent power).
* **Second path**: speed x0.35 (third x0.12, floor 0.08) and it cannot enter a realm above the primary's.
* **Techniques** need a manual (academy, teacher, sect hall, dungeon, tower) AND their realm/stage. Chantless casting needs Core Formation.
* **Power**: `1 + 0.055 * stage_index` for the best path (realm 3 stage 1 = x2.05), plus 15 percent of other paths, plus tempering, times level share (x1.29 at 50) times gear.

## 3. Simulated play (3 archetypes, 3 seeds, `hours=140`)

Model: 1 game day = 12 real minutes; archetypes spend their minutes on activities at fixed rates, picking finite content (45 quests, 160 discoveries, levels 1-56) in level order. These are efficient players: real players take about 1.3-1.6x.

| Archetype (path, meditation/day) | Level 10 | Level 30 | Level 50 | Level 55 | Cultivation at level 30 / 55 |
|---|---|---|---|---|---|
| Brawler (knight, 2 h) | 9.4-9.8 h | 42-46 h | 86-94 h | 103-114 h | R2 stage 6-7 / R3 stage 4-5 (end of run R3 stage 6-8) |
| Explorer (magic, 4 h) | 7.9-8.8 h | 36-40 h | 76-88 h | 98-111 h | R3 stage 1 / R3 perfected |
| Cultivator (sect, 8 h + teacher) | 7.7-8.7 h | 36-41 h | 84-96 h | 102-117 h | R3 stage 1 / R3 stage 6-7 (perfected by the end of the run) |

Breakthrough success rate 69-93 percent (attempted the moment the gates open).
Targets: level 10 in under 12 h, level 30 in 35-50 h, level 50 in 75-110 h, level 55 (effective cap) in 95-120 h; realm 3 reached by everyone, finished by the dedicated. All met. At about 3 h a day that is 5-7 weeks of play; a blitz is impossible because of repetition decay, finite once-only content, the level gates on every stage and the saturation cliff.

## 4. Tuning knobs
`levels.json`: `global_scale`, `pace`, each activity's `frac/decay/floor/recover`, region `soft_start/soft_cap/hard_cap/sat_step`.
`cultivation.json`: `realms[].eff_hours/level_gate/level_span/base_success/insight_cost/catalyst`, `med_schedule`, `cross_step`, location densities, resource `eff`.
Re-run: `/tmp/claude-0/cultivation/sim.sh hours=140 seeds=3` or
`godot --headless --path kingdom -s <repo>/docs/balance/data/progression_sim.gd -- hours=140 seeds=3 arch=brawler|explorer|cultivator`.

## 5. Hooks other systems must call (not wired; life.gd, main.gd and work.gd belong to other agents)
`var cult = Life.realm.mod("cultivation")`; `cult.prog` is the character level.

* Kill: `cult.prog.award("kill", {"subject": species, "content_level": monster.level, "magnitude": 1 (elite 4, boss 25), "day": WorldSim.day, "region": "region1"})`
* New place / lore: `prog.award("discovery", {"id": place_id, "content_level": n})`, `cult.add_insight(1.0, "discovery", place_id)`; lore/inscription: `award("lore", {"id": ...})` and `add_insight(1.0, "lore", id)`.
* Quest done: `prog.award("quest", {"id": quest_id, "content_level": quest.level})` plus `cult.add_insight(1.0, "quest", quest_id)`; radiant quests: same without `id`.
* Work shift finished (work.gd `finish`): `prog.award("job_shift", {"subject": job_id, "content_level": ...})`.
* Crafting (crafting.gd result): `award("craft", {"subject": recipe_id})`; gathering: `award("gather", {"subject": node_kind})`; building done: `award("build", {"subject": kind})`.
* Drill yard / school session: `award("train", {"subject": trainer_id})`.
* Rift encounter: `award("rift", {"content_level": n})` and `cult.add_insight(1.0, "rift")`.
* Drops: `cult.add_resource("herb"|"core"|"pill", grade, n)`; teacher lesson: `add_insight(1.0, "teacher")`; manuals from schools/dungeons/towers: `cult.learn_manual(id)`.
* Flags: `cult.set_flag("vale_found" | "sect_access" | "rift_seen")` unlocks meditation places.
* `Life.player_level()` should return `Life.realm.mod("cultivation").prog.level`.
* Gear: pass the gear multiplier to `cult.combined_power(gear_mult)`; technique use should check `cult.technique_unlocked(id)`.
* Tribulation: an encounter can pass its 0-1 score as `attempt_breakthrough(path, {"score": s})`; until then the UI uses `trial_score_estimate`.

## 6. Hooks wired by the Region 1 balance pass (C13, 2026-10-06)
The section 5 list was not wired for the career systems. Now (see `docs/regions/BALANCE_R1.md`):

* Finished `career_trades` task (farmer, merchant, blacksmith, Wardwright stone work): `award("job_shift", {"subject": "<career>_<kind>"})` and Soul Power (`SOUL_SOURCE`: farm, forge, meditate).
* Finished soldier duty: `award("job_shift", {"subject": "soldier_<kind>"})` and 3.2 Soul Power (combat).
* Guild commission handed in: `award("quest", {"subject": "guild_commission"})` (no id, so repeated commissions decay like radiant quests).
* Library quest completed (QuestRunner, the 90 town-kit quests): `award("quest", {"id": quest_id, "magnitude": 0.4})`. Errands pay 0.4 of a story step because the town kit alone has 90 of them (the design counted 45 quests); private runners (soldier duties) opt out with `awards_xp = false`.
* Gear needs its level (`Equipment.ENFORCE_LEVEL`), so level 6 / 12 / 22 open tier 1 / 2 / 3 kit. With the story at about 0.36 steps a day and 0.4 discoveries a day every archetype is level 15 to 23 on day 100 (target 13+).
