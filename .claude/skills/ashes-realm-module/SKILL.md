---
name: ashes-realm-module
description: How to add or change a Rising Ashes realm simulation module (scripts/realm/*) - hub registration, tick tiers, chunked day ticks, gold ledger, determinism, saves and tests. Use for any new living-world, economy, war, society, exploration or progression system that runs over game time.
---

# Adding a realm module

Specs: `docs/design/SIM_HIERARCHY.md` (budgets) and `docs/design/REALM_PLAN.md` (who owns what).

1. **Create** `kingdom/scripts/realm/<name>.gd` extending `realm_module.gd`. It is RefCounted, pure data, with no Node and no `get_tree()`. Don't add `class_name`; callers preload the file.
2. **Implement** `tick_hour`, `tick_day` (or `tick_day_chunks` when the day's work is heavy), `tick_week`, `catch_up(days, ctx)`, and `serialize`/`deserialize`. Make `catch_up` O(entities) and closed-form, never a loop over days.
3. **Register** it in `realm_hub.gd` `MODULES` and `ORDER`. Order matters within a tier: put it after the modules it reads. Tests must not assert "X is last", because later modules get appended.
4. **Siblings:** reach them with `hub.mod("name")`. Reach the game read-only through `ctx["life"]`. Extend existing systems; never duplicate them.
5. **Gold:** never write the player's gold directly. Queue it for `take_pending_gold`, and add the module to the ledger loop in `autoload/life.gd`.
6. **RNG:** use `hash([WorldSim.SEED, tag, day, id])`. State must be JSON-safe (ints, floats, strings, arrays, dicts).
7. **Warm-up:** first-time setup goes in `_ensure*` and gets called from `realm_hub.warm_up()`, so the first day tick doesn't spike.
8. **Budget:** keep each hour tick under 0.3 ms, and each pump job under 0.6 ms (`PUMP_BUDGET_USEC`). Measure it in a test.
9. **Tests:** add `tests/test_realm_<name>.gd` covering ticks, catch_up equivalence, a save round-trip, and a cost check with a loose limit (CI runners are slow).

Pitfall: commit the hub's MODULES and ORDER edit together with the module file. A hub that preloads a missing file breaks every test.
