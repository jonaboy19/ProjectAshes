# Style G Blender character candidate — 4 October 2026

Status: REVIEW CANDIDATE, not integrated. Existing game hero and Claude's outfit source are unchanged.

After rejecting TripoSR reconstruction, this candidate refines the actual assembled G6/Style G hero in Blender 5.2. One subdivision level on the head and hands, smooth shading on those parts, material roughness differentiation (skin/hands 0.82, boots 0.67, other meshes 0.90). Total 9,912 triangles, one armature. Existing head and hand vertex groups interpolate through subdivision; exporter reduces influences to four and normalizes them. This is not a redesigned face or a final AAA character.

The preview is a T-pose render after reimport. Exporting without animation avoids carrying the entire animation library into a cosmetic candidate; the game already provides its animations. Compatibility of this exported rig with the game's rest-pose, bone naming, animation retargeting and procedural outfit attachment has NOT been checked. Extreme facial/hand deformation and all combat/jump clips still need inspection. Do not automatically replace the hero.

This is one assembled outfit, NOT a complete customization library. The existing game retains modular hair/head/body customization; this static outfit selection does not add new customization options. To ship improvements, transfer approved changes back to the individual visible modular source meshes rather than replacing character_creation with this assembled model.

No texture resolution was increased. The low-detail painted face remains the main limitation; subdivision only rounds geometry. Next art work needs authored facial features, better hand topology, controlled cloth folds, leather stitching and coherent material maps with a mobile texture budget. Validate changes in the real camera, not only a close-up studio render. CPU/GPU and S22 measurements are not available for this candidate.

Source licensing: inherits the G6/hero outfit input asset licenses; audit original notices. Tool: Blender (GPL application license does not impose GPL on exported artistic assets). Height target 1.78 m from lab_chars.hero_g(); exact exported rest bounds not measured in this pass.

Local reproducible files: C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR/refine_rigged_hero.py, export_refined_mesh.py, render_hero_refined.py, hero_refined_rigged.blend. The blend retains the source animation data for further authoring; GLB intentionally excludes clips. Candidate has no collider and is not connected to gameplay.

Correction: actual exported GLB index counts total 9,832 triangles; 9,912 was the Blender scene count including an unexported 80-triangle Icosphere. Mobile refinement and sampled animation compatibility are in docs/concepts/BLENDER_HERO_MOBILE_REVIEW.md.
