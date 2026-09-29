Batch driver used for the Meshy free community pack (docs/art/meshy_free/README.md).
`spec.py` = per-model table (raw index, category, name, triangle budget, texture px, scale mode, variant); `run_opt.py [idx|idx:variant ...]` runs
tools/meshy/optimize_free.py over it with 4 parallel Blender processes. Paths are hard-coded to the local staging folder
(C:/Users/Jonna/Documents/ProjectAshes_art_staging: work/raw/NNN.glb = numbered copies of meshy_raw, work/out = results).
