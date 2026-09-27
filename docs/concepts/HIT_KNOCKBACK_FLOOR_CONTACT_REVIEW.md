# Hit Knockback Floor Contact — Review

This is a candidate cleanup of the Quaternius UAL2 `Hit_Knockback` animation. It raises the reference skeleton slightly during its downward fall so the posed mesh no longer sinks through the floor. The source GLB remains unchanged.

![Blender source-rig comparison at the landing and recovery frames](hit_knockback_floor_contact_preview.jpg)

The original game-loader QA measured 5–34 cm of floor penetration across 27 humanoid profiles. On the UAL2 reference mannequin, Blender measured a worst sample of 9.65 cm before the edit and 0.09 cm after it across 201 samples. This image and measurement use the reference rig; different clothing and character proportions can change the result.

Candidate animation asset and metadata: [`hit_knockback_floor_contact.glb`](../../kingdom/assets/incoming/ai3d/animations/hit_knockback_floor_contact.glb) · [`hit_knockback_floor_contact.md`](../../kingdom/assets/incoming/ai3d/animations/hit_knockback_floor_contact.md).

**Review gate:** Claude should run the full 27-profile game-loader QA on the candidate and inspect player guard-break and soldier heavy-hit in play before integrating it. The current game scripts, scenes, settings, and aliases were not changed for this candidate.
