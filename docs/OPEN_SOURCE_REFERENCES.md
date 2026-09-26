# Open-source code worth using (checked for licence and fit)

All of these are public on GitHub and were reachable from the dev environment.
**MIT** means we can copy the code into a commercial game as long as we keep
the copyright notice (put it in the credits / a `THIRD_PARTY.md`).

## Already used in Kingdom

| Project | Licence | What we took |
|---|---|---|
| [godotengine/tps-demo](https://github.com/godotengine/tps-demo) | Code MIT, art CC-BY 3.0 | Camera trauma shake (ported to `kingdom/scripts/actors/camera_shake.gd`); AnimationTree blend-space pattern for locomotion |
| [GDQuest/godot-4-3d-third-person-controller](https://github.com/GDQuest/godot-4-3d-third-person-controller) | MIT | Reference for camera-relative movement, "last strong direction" facing, attack impulse. Our player already follows the same structure |

## Recommended next (by topic)

### Body movement and animation
- **Engine built-ins (no download, strongest option):**
  - `AnimationTree` blend spaces and one-shots: in use (`character_animator.gd`)
  - `LookAtModifier3D` (4.4): head tracking, in use
  - `SkeletonIK3D` / `SkeletonModifier3D`: foot placement on slopes, reaching
  - `PhysicalBoneSimulator3D`: ragdoll deaths (needs physical bones generated per rig)
- [GuilhermeGSousa/godot-motion-matching](https://github.com/GuilhermeGSousa/godot-motion-matching) (MIT): motion matching, the technique behind AAA locomotion. C++ GDExtension and experimental, and it needs lots of motion-capture data. Not for a mobile MVP; revisit for the Unreal version, where it's built in.
- [expressobits/character-controller](https://github.com/expressobits/character-controller) (MIT): first-person movement abilities (crouch, swim, fly, head bob, footsteps). Useful for our first-person mode.

### AI and mechanics
- [bitbrain/beehave](https://github.com/bitbrain/beehave) (MIT, pure GDScript): **behaviour trees** with a visual debugger. Best fit for villager and soldier decision-making (flee, regroup, patrol, trade).
- [limbonaut/limboai](https://github.com/limbonaut/limboai) (MIT, C++): behaviour trees and state machines, faster than GDScript, has Android builds. Choose this over Beehave if AI becomes a performance bottleneck with big armies.
- [derkork/godot-statecharts](https://github.com/derkork/godot-statecharts) (MIT, GDScript): statecharts for character states (idle/attack/block/stagger). Good when the combat state logic grows.

### Camera and world
- [Ramokz/phantom-camera](https://github.com/Ramokz/phantom-camera) (MIT): cinematic camera system (framing, transitions, cutscenes). Useful for battle cinematics and dialogue.
- [HungryProton/scatter](https://github.com/HungryProton/scatter) (MIT): editor tool to paint forests, rocks and grass.
- [TokisanGames/Terrain3D](https://github.com/TokisanGames/Terrain3D) (MIT, C++): high-end sculptable terrain. Check its mobile support before adopting; our streamed low-poly terrain already fits the pixel style.

### Starter kits (MIT code + CC0 art)
- [KenneyNL/Starter-Kit-FPS](https://github.com/KenneyNL/Starter-Kit-FPS), [Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer): simple, clean references.

## Not reachable here / needs your PC

- Quaternius packs (CC0 animals, **horses**, animation library): the site is blocked in the cloud environment. Download on a PC and push to the repo.
- Mixamo animations: free for games, but not redistributable as raw files, so keep them out of a public repo.

## Honest take

Most "advanced" feel comes from technique, not from a magic library: layered
animation, input buffering, hit-stop, camera shake, i-frames and
target assist. Those are now in the game. Libraries help most for AI
(behaviour trees) and later for big-budget features (motion matching, IK).
