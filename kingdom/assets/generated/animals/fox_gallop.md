# Fox gallop cleanup

- **Source:** `assets/incoming/animals/quaternius/fox.glb`, Quaternius Ultimate Animated Animals, CC0 (see `assets/incoming/animals/README.md`).
- **Tool:** Blender 5.2 and `kingdom/tools/blender/fix_fox_gallop.py`.
- **Change:** removed one vertical location curve from `Tail1` in the 14-frame `Run` clip. The source curve moved this bone by 0.127 m while its rest length is about 1.047 m. This reduces the QA tail stretch from 30.3% to 1.7%. The source GLB is unchanged.
- **Game use:** `Critter.KINDS.fox` loads this derived GLB. Model geometry and other clips carry through from the CC0 source.
- **Real-world game scale:** 0.51 m tall, inherited from the source; no model geometry or transform scaling was applied.
- **Review:** targeted metrics are in `docs/qa/anim_qa_report_only_animal_fox.md`. The run clip still needs visual gait-speed review because the foot-contact sampler finds no grounded interval.
