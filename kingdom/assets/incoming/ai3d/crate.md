# TripoSR crate reconstruction — experimental, not approved

- Name: crate.glb
- Tool: official TripoSR revision 107cefdc244c39106fa830359024f6a2f1c78871, local CUDA inference on RTX 4070 Laptop GPU; CPU scikit-image extraction adapter; Blender 5.2 decimation/export.
- Input/prompt: no text prompt. A 512px Blender render of this project's existing `assets/generated/props/crate.glb`, showing a wooden plank crate in three-quarter view against gray.
- License: TripoSR source and pretrained model are MIT licensed. Input is derived from the existing ProjectAshes asset; retain its original ownership/license. MIT notice is supplied beside this result. This note does not establish independent ownership of the source crate.
- Real-world size: 0.800 × 0.798 × 0.786 metres (Blender XYZ after export preparation).
- Budget: 2,700 triangles, one material, vertex colors; no image textures. Raw reconstruction: 47,556 triangles.
- Measurements: second CUDA run about 2.95s inference and 0.76s mesh extraction, excluding environment startup/downloads.
- Quality: REJECTED for automatic game replacement. Preview shows soft geometry, pale color and questionable orientation. Existing source crate is the better asset. No collision or gameplay scene was added.

This verifies a free local generation/export route, not a production quality improvement. Keep in incoming for review. Check orientation, normals, color handling and an unrelated prop before approving this pipeline for asset production.
