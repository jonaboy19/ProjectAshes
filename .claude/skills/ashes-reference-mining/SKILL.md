---
name: ashes-reference-mining
description: The process for "systems mining" - studying shipped open-source games as a reference textbook and turning the lessons into Rising Ashes designs, without copying GPL/AGPL/NC code or assets. Includes the approved reference-project table with licences and what each is good for. Use when a new system needs prior art, before designing AI, interaction, networking-free simulation, crafting, combat or save systems.
---

# Reference mining (read, understand, re-design)

## LICENCE RULE (strict)
Reference code is GPL/AGPL and assets are NC or proprietary. NEVER copy code, data tables, def files, strings, constants lists or assets into the repo, and do not transliterate function bodies line by line. Read, understand, close the file, then write the principle in your own words and design a Godot-native version. Numbers (thresholds, ranges) are orders of magnitude only; our values are tuned in our lab. Record each project's licence in the notes.

## Process
1. **Requirement**: one sentence, with the player-visible outcome and the mobile budget.
2. **Find references**: pick 1-3 projects from the table; search by feature words (`grep -rniE` on class/function names), read headers and comments first.
3. **Clone cheaply**: check `df -h /tmp` first (cloud disk can be tight). `git clone --depth 1 --filter=blob:none --sparse <url> /tmp/claude-0/mining/<name>`, then `git sparse-checkout set <only the source dirs>`. NEVER run git inside `/home/user/ProjectAshes` for this; clone only under `/tmp`.
4. **Compare**: read our code for the same system first (`ashes-collab`, file list in the task). Write a table: topic / best reference / RA now / verdict.
5. **Extract principles** (prose): how it works, why, strengths, weaknesses, cost, what breaks on mobile. Cite file/function names as pointers only.
6. **Licence check**: confirm the licence of code AND assets in the repo (LICENSE/COPYING headers); note extra terms. Anything that is more than an idea needs the owner's approval; default is idea-level only.
7. **Godot-native design**: reuse existing RA primitives (NpcWorld bus, SmartObjects claims, Society, WorldState deltas, realm hub); define data in JSON; budgets in ms; determinism; save keys with defaults.
8. **Lab test**: a gdUnit test or headless harness with a loose cost limit (`ashes-cloud-testing`), plus a screenshot/video review if visible (`ashes-visual-qa`, `ashes-video-review`).
9. **Deliver**: `docs/research/MINING_<topic>.md` (prose, tables, gap list with P0-P3) and, if reusable, a skill under `.claude/skills/`. Delete `/tmp/claude-0/mining/*` clones at the end. Kill only your own PIDs.

## Approved reference projects
| Project | Code licence | Assets | Good for | Status |
|---|---|---|---|---|
| The Dark Mod (stgatilov/darkmod_src, `game/`) | GPL-3.0 | CC BY-NC-SA 3.0 | stealth AI: alert levels, vision+light, sound propagation, search, guard comms, body discovery, frob doors/locks/lockpicking, stim/response | mined: `docs/research/MINING_PERCEPTION_INTERACTION.md` |
| Amnesia: The Dark Descent (FrictionalGames, `amnesia/src/game`) | GPL-3.0 | proprietary (not in repo) | physical interaction states (grab/push/slide/lever/door), entity connections, per-entity save data, simple enemy sight/dark/crouch/hear model | mined (same doc) |
| Penumbra Overture (FrictionalGames) | GPL-3.0 | proprietary (not in repo) | AttackHandler (line/shape/splash), timed trigger volumes, interaction modes, global save | mined (same doc) |
| Doom 3 BFG (id-Software, `neo/d3xp`, `neo/framework`) | GPL-3.0 + id additional terms | not in repo | entity/spawnArgs/decl architecture, event queue, two-phase save/restore, triggers, anim blending channels, com_speeds profiling, level-load resource marking | mined (same doc) |
| Lumberyard StarterGame (Amazon) | Apache-2.0 / MIT style (verify per file); assets under Lumberyard terms | verify | sample game structure, component/entity layout, gameplay samples | covered by another agent: check their notes |
| Ryzom Core | AGPL-3.0 | CC BY-SA/NC mix (verify) | MMO crafting, gathering, skills, persistence | covered by another agent; see `ashes-rpg-economy-systems` |
| Jedi Academy (Raven/id) | GPL-2.0 | proprietary (not in repo) | saber/melee combat feel, force powers, NPC/AI scripting, entity system | covered by another agent: check their notes |

Add rows only after reading the repo's LICENSE; mark "verify" when unsure and never import from a "verify" row.

## Output quality bar
- Each subsystem: how they do it (prose), strengths/weaknesses, applicability to a mobile living-world RPG, concrete Godot design, budget, tests.
- A gap list vs our code with priorities (P0 blocks others, P1 core, P2 depth, P3 polish).
- Do not implement game code in a mining task unless asked; hand the design to `ashes-work-package`.
