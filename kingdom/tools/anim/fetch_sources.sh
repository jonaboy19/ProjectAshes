#!/usr/bin/env bash
# Download the raw animation sources used by tools/anim/cfg_*.json into $ANIM_SRC
# (default ~/.cache/ashes_anim_src). Raw sources are NOT committed (the Manny .blend
# is 29 MB, the BVHs ~50 MB); only the retargeted GLB libraries are.
#
#   bash tools/anim/fetch_sources.sh
#   pip install bpy==5.0.1 numpy   # (python 3.11) or use Blender 5.x
#   ANIM_SRC=... python tools/anim/retarget_clips_to_ual.py tools/anim/cfg_souls_cat.json
#   ANIM_SRC=... python tools/anim/retarget_clips_to_ual.py tools/anim/cfg_cmu.json
#   python tools/anim/glb_reduce_anim.py assets/incoming/animations/<pack>/<lib>.glb
#   godot --headless --path kingdom --import
#   godot --headless --path kingdom -s tools/anim/verify_clips.gd
set -eu
ANIM_SRC="${ANIM_SRC:-$HOME/.cache/ashes_anim_src}"
mkdir -p "$ANIM_SRC"
cd "$ANIM_SRC"

# 1) Cat Prisbrey, Modular Souls-like Template (Unlicense): MannyAnimations.zip + SoundFX only
if [ ! -f cats-souls-template/MannyAnimations.blend ]; then
  rm -rf cats-repo
  git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template cats-repo
  (cd cats-repo && git sparse-checkout set --no-cone /LICENSE /README.md /MannyAnimations.zip '/audio/SoundFX/')
  mkdir -p cats-souls-template
  unzip -o -q cats-repo/MannyAnimations.zip -d cats-souls-template
  cp cats-repo/LICENSE cats-souls-template/LICENSE
  ln -sfn "$ANIM_SRC/cats-repo/audio/SoundFX" cats-souls-template/SoundFX
fi

# 2) CMU Graphics Lab mocap, BVH conversion by B. Hahne (cgspeed), GitHub mirror
if [ ! -f cmu-mocap/READMEFIRST.txt ]; then
  git clone --depth 1 --filter=blob:none --no-checkout https://github.com/una-dinosauria/cmu-mocap cmu-mocap
fi
cd cmu-mocap
git checkout HEAD -- README.md READMEFIRST.txt cmu-mocap-index-text.txt \
  data/135/135_01.bvh data/135/135_02.bvh data/135/135_04.bvh data/135/135_05.bvh \
  data/135/135_06.bvh data/135/135_07.bvh data/135/135_09.bvh data/135/135_10.bvh \
  data/135/135_11.bvh data/012/12_04.bvh data/002/02_07.bvh data/002/02_08.bvh \
  data/002/02_09.bvh data/125/125_01.bvh data/125/125_06.bvh data/126/126_01.bvh \
  data/143/143_11.bvh data/143/143_19.bvh data/143/143_28.bvh data/113/113_08.bvh
echo "sources ready in $ANIM_SRC"
