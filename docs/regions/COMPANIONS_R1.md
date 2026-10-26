# Named companions, Region 1 (Ready v1, C7)

Three of the eight named companions in `docs/design/RETINUE_SETTLEMENT_ASCENSION.md` §2.8, written as data. Each has a bio, recruit dialogue and a three-step personal quest that finishes through `QuestRunner` (test `kingdom/tests/test_v1_companion_content.gd`). Tone follows `STORY_R1.md` and `CAST_R1.md`: warm, concrete, a little dry, nobody a chosen one.

| Companion | Who | Recruit | Quest | Mechanic reward | Region tie |
|---|---|---|---|---|---|
| **Brannoc Tallow** (male, 34) | Ashen Hand robber from Hollin's Reach, spared at a road ambush | Parole, Ashford inn board; no wage, 10% share | *Ashes of the Hand* (`companion_ashes_of_the_hand`) | Spy role: robber raids telegraph 1 day early (Ashsight, N4) | Duskbriar Wood, the Ashen Hand, Captain Hollis |
| **Sister Oriel Vane** (female, 29) | Dawn Throne healer who left Envoy Lucan's train | Found in Ashford's healer lot; no wage, 10% share | *A Relic Unburned* (`companion_a_relic_unburned`) | Healer role; Church standing becomes a lever | King's Ember Road, Kingsreach, the Ashford ring |
| **Hesk Ironbrow** (male, 52) | Durrow mason exiled by the Hammer Moot | Buy his debt (120 gold) from the Silverford clerk | *The Unfinished Arch* (`companion_the_unfinished_arch`) | Unlocks stone-tier building and the siege engineer | Hollin's Cut, Silverford Guild hall, Odrin Thale |

## Quest shape
Step 1 and 2 are objectives (goto, investigate, collect, talk_to). Step 2 ends in a decision (`choose`), which branches to one of two final steps with different reputation and a `path_*` flag. Every path is exactly three stages. The shared payoff (gold, items, `done` and mechanic flags) pays on completion.

- Brannoc: `law` (hand Mab Larkin to the Guard) or `quiet` (burn the ledger).
- Oriel: `return` (the lamp to the Dawn Throne) or `hide` (into an Ashford stone).
- Hesk: `charter` (pointed arch) or `durrow` (round arch).

## Flag contract (Life.life_path flags, read by dialogue conditions)
- `companion.<id>.recruit_yes`: set by the recruit dialogue; recruitment code should join the follower on it.
- `companion.<id>.quest_asked`, `.done`, `.path_*`, and the mechanic flags (`.spy_role`, `.healer_role`, `.stone_tier`, `.siege_engineer`).
- `companion.<id>.courting` or `.friends_only`: the courtship decision.
- `hero.male` / `hero.female`: **not set anywhere yet.** Courtship is offered only when the hero's flag is the opposite of the companion's (OWNER_DECISIONS 2026-09-29: male-female pairs only). Character creation (or birth) must set one of them.

## Not done (code or art, outside this data-only task)
- Clue props for `duskbriar/ash/cold_hearth|ledger_page|dropped_boot`.
- Spawning `mab_larkin` as a talk target at the Duskbriar fence spot, and `lucan` at the Kingsreach chapel-house (the quest listens for `talk {npc}` events).
- Applying the mechanic flags (spy telegraph, healer ability, stone tier, siege engineer).
