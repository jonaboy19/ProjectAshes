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

Blender evaluated the reference mannequin's skinned mesh at 201 points across the clip after re-importing the exported GLB. Its worst floor penetration changed from 9.65 cm in the original action to 0.09 cm in the adjusted action. This is a source-rig result only. The project's game-loader report measured 5–34 cm across 27 humanoid profiles for the original `Hit_B`; this candidate has **not** yet been measured across those profiles or played in the game. Do not treat the source-rig improvement as proof that it fixes retargeted characters.

## Integration note for Claude

If reviewing in the game, load this clip before `UAL2_Standard.glb` in the animation-library search order so the existing `Hit_Knockback` name wins, while keeping the `Hit_B` alias. Re-run the full humanoid animation QA and inspect player guard-break plus soldier heavy-hit at their actual playback rates. Check both floor contact and any newly visible hovering, hit timing, movement recovery, and LOD transitions. Keep or reject the candidate based on those results; this file does not change game wiring.
