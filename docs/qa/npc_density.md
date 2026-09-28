# NPC density pass (2026-09-28)

User report: "there are way too many NPCs walking around", plus villagers cost ~10 ms/frame CPU
in the capital (measured worse: see below). Design target (`docs/RISING_ASHES_OPEN_WORLD.md`):
30-50 physical NPCs in the starting village, 50-100 visible characters total, not hundreds
walking the streets.

## Root cause

`kingdom/scripts/population/population_lod.gd` `refresh()` capped sprite NPCs **per job look**
(peasant / worker / merchant / guard, one `MultiMesh` each) instead of as a single shared budget:

```gdscript
var n: int = used[look]
if n >= mini(MAX_SPRITES, Quality.npc_sprites):
    continue
```

With `MAX_SPRITES = 300` and 4 looks, the real ceiling was **up to 1200 sprites** rendered at
once — confirmed by the benchmark (`npc_sprites: 1200` in the capital, hours 9 and 18). The code
even had a comment acknowledging "up to 1200 sprites every refresh made a 4 Hz spike" without
fixing the cap itself, only caching the per-sprite ground placement. That 1200-sprite spike is
also why the capital dropped to 8.6 fps / 117 ms average frame time at hour 18 — far worse than
the reported "~10 ms/frame".

## Changes

1. **`population_lod.gd`**: the sprite loop now tracks one running `sprite_total` across all
   looks and stops once `mini(MAX_SPRITES, Quality.npc_sprites)` is reached (list is already
   sorted nearest-first, so it keeps the closest people). `MAX_SPRITES` lowered 300 -> 140 as a
   hard ceiling; the "9 m always gets a full model" rule (`NEAR_ALWAYS`, `FULL_RANGE`) is
   untouched.
2. **`quality.gd`** (`Quality` autoload) tier budgets, `npc_full` / `npc_sprites`:

   | Tier | npc_full before -> after | npc_sprites before -> after |
   |---|---|---|
   | LOW | 8 -> 6 | 40 -> 14 |
   | MEDIUM | 12 -> 10 | 120 -> 35 |
   | HIGH | 24 -> 16 | 300 -> 55 |
   | ULTRA | 24 -> 20 | 300 -> 70 |

3. **`daily_rhythm.gd`**: `MAX_DELAY` (per-person stagger behind the shared work/market/home
   clock) raised 0.9 h -> 2.0 h, so a schedule boundary (e.g. everyone going to market at 17:00)
   empties and fills the street over about two minutes instead of a few seconds, avoiding a
   momentary wall of people even when the raw budget would allow it.

None of these touch animation code, `character_animator.gd`, `player.gd`, `villager.gd`
locomotion, or WorldSim's population counts/economy (`world_sim.gd` population arrays,
careers, wages are untouched) — only how many of the existing population are drawn and how
they're paced outdoors.

## Measurements

Bench: `tools/qa/bench/bench.gd` via `Godot_v4.6-stable_win64_console.exe --scene=<village|city>
--hour=<H> --quality=high --uncapped`, mobile renderer, RTX 4070 laptop. `npc_full` /
`npc_sprites` are `PopulationLOD.full_count` / `sprite_count` at that instant.

### Counts (village)

| Hour | npc_full before | npc_sprites before | npc_full after | npc_sprites after |
|---|---|---|---|---|
| 9 | 24 | 287 | 16 | 55 |
| 13 | 24 | 287 | 16 | 55 |
| 18 | 24 | 296 | 16 | 55 |
| 22 | 5-6 | 0 | 6 | 0 |

### Counts (capital / city)

| Hour | npc_full before | npc_sprites before | npc_full after | npc_sprites after |
|---|---|---|---|---|
| 9 | 24 | 1200 | 16 | 55 |
| 13 | 24 | 1200 | 16 | 55 |
| 18 | 24 | 1200 | 16 | 55 |
| 22 | 4-7 | 0-4 | 7 | 4 |

Sprite count is cut from ~287-1200 to 55 (village and capital both hit the HIGH-tier budget of
55 during the day) — well over the required 50%+ cut, and the 1200-sprite capital spike is gone
entirely. `npc_full` (nearby full models) dropped from the 24-model cap to 16.

### Capital frame time (city, hour 18 — the worst before/after pair)

| | cpu_process_ms | ms_avg (frame) | fps_avg |
|---|---|---|---|
| Before | 150.8 | 116.8 | 8.6 |
| After (run 1) | 50.4 | 16.0 | 62.6 |
| After (run 2, repeat) | 52.6 | 15.9 | 62.9 |

Best-of-two "after" run: **~50 ms -> ~16 ms average frame time (about 3x), 8.6 fps -> ~63 fps.**
The original "~10 ms/frame" estimate undersold it: the per-look sprite cap bug meant the capital
was actually spiking to 100+ ms frames whenever the 17:00-19:30 market phase put every non-farm
resident outside at once.

Raw JSON lines: `docs/qa/npc_density_before.jsonl`, `docs/qa/npc_density_after.jsonl`.

### Screenshots (`docs/qa/npc_density_shots/`)

- `before_village_13.png` / `after_village_13.png` — village plaza, midday.
- `before_city_13.png` / `after_city_13.png` — capital street near the gate, midday.
- `before_village_22.png` / `after_village_22.png` — village plaza, night.
- `before_city_22.png` / `after_city_22.png` — capital, night.

Looking at the midday pairs: the village plaza before had 287 sprites in range but the visible
frame wasn't dramatically more crowded than after (most of the excess was sprites stacked beyond
camera framing / behind buildings) — the after shot still reads as a lived-in plaza (guard,
market stalls, several walking villagers, no empty-town feel) while the capital's 1200-sprite
before-state was the one causing the severe frame-time spike, not primarily an extra-crowded
screenshot composition. Night shots (22:00) are appropriately close to empty in both before and
after, since almost everyone is already home by then; the fix mainly affects mid-day/market-hour
crowd size and the resulting CPU cost.

## Follow-up (not done here)

- `npc_full`/`npc_sprites` are the same for village and capital today (tier-only, not
  scene-aware); the village plaza and the capital street ended up at the same combined 71
  (16+55) near the player because both scenes have enough population within `SPRITE_RANGE` to
  fill the shared budget. If a future pass wants the village plaza specifically lower than the
  capital street, that needs a per-scene or per-settlement-size budget rather than a purely
  tier-based one.
- Farmers/laborers/woodcutters working fields/forest edge are still always "outdoors" in
  `WorldSim.is_indoors()` (only shop workers job 1/2 get a partial-indoors rule); left alone here
  since they're naturally far from the plaza and not the reported problem.
