---
name: ashes-perception-ai
description: How to build or extend NPC perception in Rising Ashes - vision (cone, light, stance), hearing events, suspicion/alert meter, investigate and search, alert sharing, body/evidence discovery, crime witnessing into Society. Use before touching npc_world.gd, utility_brain.gd, villager.gd witness code, society.commit_crime, or adding guards, stealth, or any "NPC notices X" behaviour.
---

# NPC perception, suspicion, search

Full design and reference notes: `docs/research/MINING_PERCEPTION_INTERACTION.md` (sections 2.1-2.6, 4.1-4.5, gap list 5).
Principles come from The Dark Mod / Amnesia (GPL: read, never copy; see `ashes-reference-mining`).

## What exists (extend, do not duplicate)
- `scripts/population/npc_world.gd`: static incident ring (16 slots), `report(Kind, pos, radius, seconds)`, `report_crime()`, `alarm_at()`, barks via `line()`. This is our "sound/stimulus bus".
- `utility_brain.gd`: utility scoring of acts from 0..1 inputs; `sense_threats` has the ONE global ray budget (`THREAT_RAY_BUDGET` per window). Danger memory `remember_danger/avoids`.
- `villager.gd`: `_gather_inputs`, `_crime_input`, `witness()`, head look, bubbles (max 4).
- `actors/player.gd::noise_radius()` (walk/run/crouch/mounted). wolf.gd/monster.gd already scale aggro by it.
- `smart_objects.gd`: spots + `claim/release` = our "assign unique search spot" primitive.
- `realm/society.gd::commit_crime/add_evidence/bribe_witness`.

## Model to implement (own numbers, tune in the lab)
1. **Alert scalar** per tier-0 NPC (fixed arrays like NpcWorld, no allocation): 0..~30, thresholds notice / suspicious / searching / alarmed, decay when calm, class can drop only one step per few seconds, grace period to ignore repeats of the same source.
2. **Vision** = cone x distance falloff x light term x stance term, evaluated cheaply every think tick (3.3 Hz, staggered). Gates in order: distance^2, cone dot, vis > 0.05, THEN request a ray through the existing queue. Alert gain = base + bonus*vis. Still-and-dark shrinks range (Amnesia idea); crouch halves; run/mounted raises.
3. **Light** for the player: analytic (ambient by hour/weather/indoor + registered lights within ~25 m + lantern), cached at 4 Hz. NEVER a render pass (TDM lightgem is too heavy for phones).
4. **Hearing**: `emit_sound(kind, pos, loudness_m, maker)` into the incident ring; per-kind loudness and alert gain; occlusion class multiplier (same cell 1.0, open door .7, closed door .35, other building .2). Fuzz the origin; if unreachable, the point is the door.
5. **Brain**: add inputs `suspicion`, `alert_class`, `heard`, `evidence_near`; acts NOTICE, INVESTIGATE, SEARCH, ALARM beside FLEE/WATCH/SHELTER. Keep `committed` hysteresis. Do not build a second state machine.
6. **Search**: per-event `Search` record (origin, radius, spot ids, claims, expiry); spots are SmartObjects type `search`; max 2 active searchers, the rest hold guard spots; on expiry write danger memory and return to schedule.
7. **Alert sharing**: every event has an id; each NPC keeps a tiny ring of known ids (no re-reaction); `Kind.CALL_FOR_HELP / BODY_FOUND / SUSPICIOUS`; telling degrades alert x0.6; settlement `guard_alert` 0..3 lives in Society.
8. **Evidence**: registry of bodies/KO/blood/open doors/broken props/missing items; NPCs scan entries near them once per id, random-but-deterministic 0.5-1.5 s reaction delay; civilians flee+alarm, guards investigate+call help; "saw it happen" window = witness.
9. **Crime**: seen = `vis` of the culprit at crime time (not a flat 0.9). Witness ids must be real/anon ids. Reporting is a task: crime commits to Society when a guard is reached/call heard or after a timeout; killing/outrunning all witnesses leaves it unreported (evidence only). Keep old `commit_crime` defaults so existing tests pass.
10. **Feedback**: barks per class transition (cooldown), head glyph for the 3 nearest attentive NPCs only (shared material), one player HUD edge indicator for the most alert watcher.

## Rules
- Determinism: no `randf()`; use `hash([npc_id, tick])` or the existing seeded streams.
- Budgets (S22): perception <= 0.25 ms/frame avg for 24 NPCs, <= 4 rays / 0.5 s global, light <= 0.03 ms, events <= 0.05 ms. Add a cost test with a loose limit.
- Data tier (untethered NPCs) never runs perception; only embodied tier-0 bodies do. WorldSim keeps intent.
- Never add per-NPC UI nodes, per-frame loops over all villagers, or ray-per-NPC-per-frame.
- Add tests: vis table, time-to-alert (crouched shadow = never, lit run < 1.5 s), hearing occlusion ordering, no duplicate search claims, crime unreported when witnesses die, save round-trip of alert-related persistent state (event ids, searches).
- Run the lab (ashes-cloud-testing) for gdUnit; report which budgets were measured.
