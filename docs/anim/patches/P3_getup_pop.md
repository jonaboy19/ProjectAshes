# P3 — Ragdoll knock-down → stand-up pops in ~2 frames (FEEL_AUDIT F11)

**Evidence:** `docs/anim/feel/before/13_get_hit_crop_sheet_001.png` #15 → #17: the orc lies in the
ragdoll pose, then is fully upright one 15-fps sample later (≈ 0.07-0.1 s). The hand-back from
`ragdoll.gd` to the AnimationPlayer has no pose blend, and `monster._get_up()` plays
`stand_up` with a 0.2-0.3 s cross-fade *from the last animated pose* (the pre-hit idle), not
from the ragdoll pose.

**Owner:** Codex (`ragdoll.gd`, `monster.gd`, `wolf.gd`).

**Proposed fix (pose-snapshot blend, standard "ragdoll to get-up"):**
1. In `ragdoll.gd` when simulation stops, copy each `PhysicalBone3D` global pose into
   `Skeleton3D.set_bone_global_pose_override(i, pose, 1.0, true)` (4.6: use a small
   `SkeletonModifier3D` "PoseHold" that writes the stored local poses with an `influence`).
2. Start `stand_up` (monster) / `idle` (wolf) at time 0 immediately, and tween the PoseHold
   `influence` 1 → 0 over **0.35 s** (ease-out). The modifier runs after the mixer, so the
   clip underneath takes over smoothly.
3. Pick the get-up clip by pelvis orientation (face-up vs face-down) when a second clip exists
   (`Kay_*` reactions in `animations_free2/kaykit_combat_reactions` have both).
4. Wolves: no get-up clip on the rig; the same 0.35 s PoseHold fade into `idle` removes the pop.

Cost: one modifier per ragdolled actor (≤ `Ragdoll.MAX_LIVE` = 3), ~0.01 ms.
