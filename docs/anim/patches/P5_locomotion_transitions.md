# P5 — Start / stop / pivot transition clips (FEEL_AUDIT F1, F2, F7 follow-up)

Tuning in this pass (player.gd constants) removed the worst pops: the run stop now takes
0.43 s over ~1.4 m instead of 0.2 s, walk starts reach speed in ~5 frames instead of 2, and
the idle turn is 14 rad/s instead of 20. What is still missing is *authored* transition
motion: none of the loaded libraries (UAL, `animations_free*`, KayKit) has a run-stop,
walk-start or 180° pivot clip (`grep -i "stop|start|pivot"` in `docs/anim/free_library/clip_tables.md`).

**Proposal for the clip pipeline (local session) + state wiring (Codex):**
- Source: 100STYLE (CC BY 4.0) has "Neutral" start/stop/turn takes; CMU #69/#91 have walk
  starts/stops. Retarget with `tools/anim/retarget_bvh.py`, trim to
  `Loco_Run_Stop_L/R` (0.5 s, plant on the left/right foot), `Loco_Walk_Start` (0.35 s),
  `Loco_Pivot_180_L/R` (0.45 s).
- Wiring (CharacterAnimator): a `stop` OneShot between `loco` and `stance`, fired when the
  stick is released above 4 m/s; pick L/R from `_phase` (< 0.5 = left foot planted);
  fade in 0.08 s, out 0.2 s; the body keeps using `STOP_BRAKE_RUN` so the clip and the
  capsule agree (clip travel ≈ 1.3 m at 6.5 m/s entry).
- Pivot: fire `Loco_Pivot_180_*` from `player._steer` when `_pivoting` becomes true above
  3 m/s (the braking already lasts ~0.15 s).
