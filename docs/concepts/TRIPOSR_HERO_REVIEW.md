# Style G hero — TripoSR experiment, 4 October 2026

Status: REJECTED for production. No playable character, scene, animation or outfit was replaced.

Real local image-to-3D generation using VAST TripoSR (MIT code and weights), RTX 4070 Laptop, CUDA inference and the local CPU marching-cubes adapter described in TRIPOSR_LOCAL_PIPELINE_HANDOFF.md. This is TripoSR, not the hosted Tripo3D service.

Input: Blender render of the actual assembled Style G hero, built through lab_chars.hero_g(), including the existing modular G6 character and HeroOutfit. No newly generated concept art. Original game assets retain their original licensing; MIT generator licensing does not relicense input assets. Audit the source asset notices before distributing derivatives commercially.

Prompt: image-conditioned reconstruction; no text prompt. Green traveller tunic, brown hair, belt, pouches, boots. Single front reference cannot establish accurate back anatomy or clothing.

Two runs: first reference too loosely framed, visibly poor anatomy; second tighter and brighter. Second raw mesh 23,380 triangles; Blender reduction 11,998 triangles. Height 1.80 metres; width 0.739 m, depth 0.819 m. One vertex-color material, no texture images, no skeleton, weights, animation or customization pieces. Orientation is generator-native and still needs forward-axis correction for Godot. No collider.

Review: second silhouette recognizable, but face/fingers, leather edges, cloth shape and colors are inferior to the existing hero. Reconstructing the existing low-detail model does not invent reliable high-detail anatomy. Do not batch-replace NPCs using this result.

Recommended next production work: improve the existing rigged modular character in Blender, retain skeleton and skin weights, add controlled face/hand detail and garment folds, preserve interchangeable body/hair/outfit parts, then inspect all extreme animation poses. TripoSR may help with standalone prop blockouts after separate review; it has not demonstrated a hero upgrade here.

References: docs/concepts/triposr_hero_source.png and triposr_hero_candidate.png. Model: kingdom/assets/incoming/ai3d/hero_styleg_triposr_experiment.glb.

Reproduction scripts and full raw models: C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR. Export helper: kingdom/tools_qa/export_triposr_hero.gd. Blender did not support Godot's KHR_node_visibility extension; fix_hero_gltf.py removed meshes from explicitly hidden nodes before stripping that extension. Simply stripping visibility exposes every hidden customization option and gives a wrong reference.
