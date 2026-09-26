# What the cloud session can and can't do (hand this to the local PC)

The cloud dev session runs in a Linux container **without a GPU or display**,
behind a network allowlist. Here's the split.

## The cloud session CAN do (so don't duplicate these locally)

- Write and refactor all game code (GDScript, shaders, scenes), commit and push.
- Run **Godot 4.6.2 headless** (software rendering): imports, script checks, scripted screenshots and short video captures. Slow (1–5 fps) but correct visuals.
- Run **Blender 5.0 headless** (`bpy` Python module): batch FBX/OBJ/Blend → glTF conversion, generating props and buildings from code, LODs, baking sprite sheets.
- Download from **GitHub** (releases, repos) and **PyPI/npm**. It uses MIT/CC0 projects from there: LimboAI, Dialogue Manager, Phantom Camera, KayKit.
- Use assets pushed to the repo (the `kingdom/assets/incoming/` delivery works well).

## The cloud session CAN'T do: please do these on the PC

| Task | Why the cloud can't | What to do locally |
|---|---|---|
| **Real performance testing** (fps, frame times, memory) | No GPU; software rendering numbers are meaningless | Open `kingdom/` in Godot 4.6, run, press F3/profiler. Report fps in village, capital and battle, plus the GPU model |
| **Phone testing / Android export** | No device, no Android SDK | Install export templates and the Android SDK, export, install on the phone, report fps and heat |
| **Download from asset sites** (Quaternius, Kenney, Poly Haven, ambientCG, itch.io, OpenGameArt, Sketchfab, Fab) | Network allowlist blocks them | Keep using the `kingdom/assets/incoming/` drop (you're already doing this) |
| **Mixamo** (Adobe login) | Needs an account and browser | Optional: download FBX animations; keep the repo private if committed |
| **AI generators on GPU** (Stable Fast 3D, Stable Audio Open, Meshy) | No GPU; some need accounts | Set up PyTorch with CUDA for the RTX 4070; generate, check the licence (see research notes), then push results into `incoming/` |
| **Blender GUI work** (hand modelling, sculpting, painting, rig fixing) | No display | Anything needing an artist's eye; scripts from the cloud can do bulk jobs |
| **Material Maker / Blockbench interactive work** | GUI apps | Author textures or blocky models, export PNG/glTF to `incoming/` |
| **Play-feel judgement** (does combat feel good, is the camera annoying) | Can't hold a controller | Play the build and write short notes in `docs/PLAYTEST_NOTES.md` |
| **Audio listening checks** | No speakers; can only verify files load | Listen to music and SFX mixes and report balance |
| **Terrain3D editor sculpting** | Editor GUI | Later, once we adopt Terrain3D |
| **Signing into services** (Steam, stores, accounts) | Credentials must stay local | Local only |

## Local tooling notes (from your research)

- **gltf-transform** (Node): shrink textures to 256–512 px for mobile, dedupe, validate. **Don't** use Draco or meshopt compression, because Godot can't read them.
- **Blender** on the PC for anything visual; the cloud can generate the batch scripts (`tools/blender/*.py`) for you to run.
- **Godot retargeting** at import (BoneMap + SkeletonProfileHumanoid) lets the UAL animations drive other humanoid rigs (Creatus knights, KayKit). It's set up in the import dialog; the cloud can also write the `.import` config.
- **Licence rules:** CC0/MIT/OFL are fine. CC-BY is fine with credit. Hunyuan3D is **not** allowed (EU excluded). Free tiers of Tripo, Suno and ElevenLabs are **not** allowed commercially. Meshy's free tier needs CC-BY attribution. Stable Fast 3D and Stable Audio Open are fine under $1M revenue.

## Handy commands for the PC

```bash
# run the game
godot --path kingdom
# preview shots exactly like the cloud does (GPU makes it fast)
godot --path kingdom -- --shot=street --out=street.png
# shots: explore, first, town, battle, command, castle, city, street, lineup
```
