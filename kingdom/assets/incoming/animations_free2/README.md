# animations_free2 (UAL skeleton clip libraries, second wave)

Retargeted onto the Quaternius UAL 65-bone skeleton like `../animations/` and `../animations_free/`.
Add the GLBs to `Assets.UAL_FILES` (or load them as AnimationLibraries) - clip names are prefixed `Kay_` so they never collide.
Pipeline: `tools/anim/free2/` (`kaykit_make_blend.py`, `make_kaykit_cfgs.py`, `retarget_free2.py`, `build_kaykit.sh`).
Full catalogue, licences and notes: `docs/anim/advanced/README.md`.

| folder | clips | source | licence |
|---|---:|---|---|
| kaykit_life_sim | 33 | KayKit Character Animations 1.1 (Tools + Simulation + General): chop, dig, mine, hammer, saw, lockpick, workbench, fishing (cast/bite/tug/reel/catch), hold item, wave, cheer, interact, pick up | CC0 |
| kaykit_combat_reactions | 15 | KayKit: hit reactions, 2 deaths, block set, stances, 4 dodges, 2H spin | CC0 |
| kaykit_movement_ext | 17 | KayKit: crouch, sneak, backwards walk, strafe runs, walks/runs, jump set, idles | CC0 |
| kaykit_ranged | 14 | KayKit: bow draw/aim/release, pistol, rifle, run holding bow/rifle | CC0 |
| kaykit_undead | 9 | KayKit Special (skeleton enemies): idle, walk, taunt, awaken, collapse, resurrect | CC0 |

KayKit proportions are chibi (short legs, long arms); direction-matched retargeting keeps the poses but
knees look bent and floor/seat contact poses do not fit, so sit/lie/push-up/crawl clips were left out (use UAL `Sitting_*`).
