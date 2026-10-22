# Cloud session → local PC session: what landed (2026-10-06)

Local session: read this after pulling. It mirrors `LOCAL_SUMMARY_FOR_CLOUD.md`. Everything listed is on `claude/focused-curie-m09hbd`. The full suite runs with `tools/qa/run_tests.sh 20` (batched; a single process crashes near the end) and currently gives 2316 test cases, 0 failures.

## Read first
- `docs/design/FOUNDATION_PLAN.md`: the owner's foundation-first freeze, F1–F12, and the status section at the end.
- `docs/regions/HOOKS_FOR_CLOUD.md`, section "Cloud status (2026-10-06)": your hook requests, all applied except device-only work.
- `docs/LOCAL_SESSION_HANDOFF.md`, section "Cloud LOW budget audit": what the cloud cut on LOW, and the biggest LOW costs it found in older content.

## What the cloud built (gameplay; the visuals are yours to judge)
- **Foundation F1–F12:**
  - one Interactable system (`scripts/interaction/`)
  - traversal: vault, mantle, ledge, ladder and step-up (`scripts/actors/traversal.gd`)
  - heavy attack, spear, bow and staff, knockdown and get-up (`player_arms.gd`)
  - in-world talk sheet
  - ownership, witnessed theft, pickpocket, trespass, shop hours and arrest
  - modular interiors with households
  - quest objective library (`scripts/quests/`)
  - the Thornfield slice and its wilds, the bandit camp, the Rift and the Watch Post
  - one Soulbeast; the Soldier career
  - node pooling and the cell streamer
- **Town kit** (`scripts/world/town_kit/`, `data/region1/towns/*.json`, generator `tools/towns/gen_town.py`): all 30 Region 1 settlements have named residents, forced lots, named keepers, a three-quest line and a local threat. Hubs sleep outside their cell.
- **Meshy batch 3:** 31 models placed (`meshy3_sites.json`); 7 characters re-rigged to UAL as villager looks (`characters_ual/`); 19 rejects excluded from the export.
- **Playtest bot** (`tools_qa/playtest_bot/`): stages `tf_*` for the Thornfield slice, `towns` and `townsweep`. Run it with `PLAYTEST_ARGS="--adult" run_playtest.sh "boot,adult,tf_talk"`.

## Please verify on the GPU or the S22 (the cloud only has software GL)
1. **LOW cost:** run `tools_qa/perf/low_budget.gd` (`--qa=`, `--quality=low`), which prints real `measured_draws` and `measured_prims` per view on the PC. The cloud only had census counts. The biggest single LOW cost it found is `HorizonGround` (region1_look), at 57.8k tris in every view.
2. **The 196 Meshy models with no LOD1** (list in `data/region1/world/model_tris.json`) need a Blender decimate pass. The engine can't make LODs for flat-shaded unique vertices.
3. **Look checks** in the real renderer:
   - interiors at day and night (the cut-away walls, warm backdrop, lamp between lens and player)
   - the Rift lighting and the swirl exit portal
   - the held weapons (length fit per type)
   - the HUD lane (toasts, hint pill, banner and the new offer card)
   - nameplates (fade by 25 m, nearest 6, a subtitle line)
4. **Feel** (Codex): the feel list in `LOCAL_SESSION_HANDOFF.md` from F2/F3. Traversal clip timing, the knockdown to get-up pose pop, staff clips and the bow hold loop are all data-driven: `data/movement/traversal.json` and `data/combat/player_weapons.json`.

## Still open on the cloud side
- A town name mismatch between the HUD and the discovery banner (Ironmarch/Silverford, Oakvale/Greenhollow), a shirtless villager look, and the hint pill sometimes inside the banner. Being fixed now.
- Save size is about 1.42 MB before any kit town (realm 482 KB, world 448 KB, economy 373 KB). The town kit adds about 57 KB.

## Respecting your priorities
The owner's order (hero → locomotion → camera → lighting → … → LOD) and the Ashford benchmark street are yours. The cloud adds no new dressing, lights or meshes to towns, gates its own decoration on LOW, and leaves visual judgement to you.
