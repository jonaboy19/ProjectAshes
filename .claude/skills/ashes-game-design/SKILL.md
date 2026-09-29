---
name: ashes-game-design
description: Standard for writing Rising Ashes game-design docs (new systems, regions, mechanics) - build on existing code, novelty check against competitors, mobile UX, perf budgets, balance targets, and work packages with owners. Use before designing any feature the owner asks for.
---

# Designing a Rising Ashes system

The owner wants **complete, worked-out systems** with **never-seen-before twists**, in a harsh-but-fair medieval life-sim + kingdom + action RPG on phones.

## Always
1. **Build on what exists.** Read these first:
   - `docs/regions/REGION_1_PLAN.md`
   - `docs/design/*`
   - `docs/RISING_ASHES_*`
   - `WORLD_LORE.md`
   - the posters in `docs/art/regions/`
   - the relevant scripts and addons (GodotGAS, LimboAI, gloot, quest_weaver, dialogue_manager, road-generator, terrain_3d)

   Name the existing files you reuse.
2. **Canon:** poster names are on screen and data ids are kept (`docs/regions/OWNER_DECISIONS.md`). Region 1 is the Ashford Vale in Valencious.
3. **Novelty check:** for each mechanic, say how it differs from Mount & Blade/Bannerlord, Palworld, Valheim, Manor Lords, Kingdom Come, Zelda, Genshin, Stardew and Fable. Include at least 3 original twists.
4. **Tie-ins:** connect every system to the Region 1 mechanics (Wardwright, Scar Tide, Ember Legacy, Ashsight) and to the main quest "The Stones Are Dimming".
5. **Mobile:**
   - touch-first UX (≥48 dp targets, one-thumb flows, minimal text);
   - performance budgets (ms, draw calls, instance counts, save size);
   - HIGH and LOW tier behaviour.
6. **Difficulty:** a harsh early game with earned power. Give numbers for early, mid and late game, plus sim tests that validate them.
7. **Output:**
   - tables over prose;
   - work packages sized for one Sonnet agent (1–3 h), with owner L (local: new files, assets, tools), C (cloud: hot-file integration, world layout) or X (Codex: animation behaviour);
   - dependencies, acceptance tests (gdUnit + screenshots + frame sheets) and milestone order.
8. Commit docs only, from a sparse worktree. Then run `ashes-aaa-review` on the design itself: what's missing, and what's generic?
