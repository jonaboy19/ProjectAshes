# Video mocap previews

Pipeline docs: `kingdom/tools/anim/video_to_bvh/README.md`. Test material is synthetic: the UAL mannequin rendered in Blender
(`Sword_Attack`, `Walk_Loop` RM) as a fake phone video, so recovered motion can be compared with ground truth.

- `sword_source_skeleton_character.png`: per cell = source frame | recovered skeleton front | side | retargeted UAL character. Poses match (lunge, arms out); mean limb-direction error 26 deg vs ground truth (MediaPipe depth limit), retarget direction check 0.9 deg.
- `walk_source_skeleton.png`: walking across frame; first frame is broken because the actor is cut off by the frame edge (documented limitation). Travel 4.11 m recovered vs 3.87 m true.
- `*.bvh` recovered BVH, `Sword_Video_Test_UAL.glb` retargeted 1-clip GLB (not wired into the game).
