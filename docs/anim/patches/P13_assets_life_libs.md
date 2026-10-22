# P13d: assets.gd — optional: life libraries for every humanoid (cloud, 4 lines)

Only needed if the player or soldiers should also use the life clips, for example the player sitting on a bench,
drinking at the bar or playing the lute in a tavern. Villagers get them through `LifeLibrary.install(anim)` (P13a §1).

```gdscript
const UAL_FILES := [ ...,
	UAL_ANIM_DIR + "combat/UAL_Combat.glb",
	# Living world life clips (docs/anim/living_world/HANDOFF.md): work, town, social/ambient, CMU everyday mocap.
	UAL_ANIM_DIR + "life/UAL_Life_Work.glb",
	UAL_ANIM_DIR + "life/UAL_Life_Town.glb",
	UAL_ANIM_DIR + "life/UAL_Life_Social.glb",
	UAL_ANIM_DIR + "life/UAL_Life_Mocap.glb"]
```

Because the files sit under `UAL_ANIM_DIR`, `_ual_for` already disables their `root` position track, so the clips play
in place. If both hooks are applied, `LifeLibrary.install` is a no-op for clips already present.
The cost is about 190 more clips in the shared per-rig library (one copy per skeleton path), measured in HANDOFF.md.
