# Hit Knockback Floor Contact Candidate

- **File:** `hit_knockback_floor_contact.glb`
- **Asset type:** single-action humanoid animation library on the Quaternius UAL2 reference rig.
- **Prompt:** none; this is a non-generative cleanup of an existing clip.
- **Tool:** Blender 5.2, glTF import/export.
- **Source:** `kingdom/assets/incoming/quaternius/universal-animation-library-2/Unreal-Godot/UAL2_Standard.glb`, action `Hit_Knockback`.
- **Licence:** CC0 1.0 Universal, as stated in the adjacent UAL2 `README.txt`.
- **Reference mannequin size:** approximately 1.83 m tall in Blender's metre-based scene.
- **Clip duration:** approximately 0.83 s at 24 fps (frames 0–20 in the source).

## Change

The source action has no vertical translation on its `root` bone. A smoothed, low-amplitude root-height curve was added during the downward/ground-contact portion. The peak lift is about 7.8 cm on the reference rig. No other bones, action timing, meshes, materials, or source files were changed. The exported GLB contains one animation named `Hit_Knockback`.

## Measurement

Blender re-imported the exported GLB successfully. On the reference mannequin, 201 skinned-mesh samples reduced the worst floor penetration from 9.65 cm to 0.09 cm.

A scratch copy of the Godot game-loader animation QA harness injected the candidate clip into the same `AnimationLibrary` used by 27 humanoid profiles. The run reached `ANIM_QA_DONE`; Godot then crashed during shutdown with resources still in use, consistent with the existing harness shutdown issue. The measurements were written before shutdown. Floor penetration improved for all 27, with the worst case moving from 34.3 cm to 27.8 cm and the median from 12.3 cm to 7.4 cm. **Fourteen profiles still penetrate at least 5 cm.** Maximum planted-foot slip rose from 64.4 to 84.8 cm/s. This is not a finished shared-clip fix. The foot metrics are imperfect for a lying pose, but the remaining mesh penetration is clear.

See the interactive [retarget review board](../../../../../docs/concepts/HIT_KNOCKBACK_RETARGET_REVIEW.html) for every profile and the [Blender source-rig comparison](../../../../../docs/concepts/hit_knockback_floor_contact_preview.jpg).

## Integration status

**Do not replace the shared `Hit_B` alias with this candidate as-is.** It demonstrates that a single shared root-height curve reduces penetration, but the correction needed varies substantially by character profile. Keep the current game wiring unchanged until a retarget-aware correction or better authored action passes the full avatar QA and live combat review.

The asset is retained as a non-integrated experiment for further animation work. The original UAL2 clip and all game scripts remain unchanged.
