# Leather stitch experiment — 4 October 2026

Status: experimental; not integrated. Based on mobile Blender hero candidate. Tool: Blender 5.2, procedural skinned thread strips on selected leather-colored boundary edges. No text/image generation prompt. Inherits original hero/G6/Style G input licensing. Height source assembly 1.78 m; exact bounds not newly measured.

Exported GLB: 6,019 triangles, six mesh primitives. 120 stitch dashes / 240 added triangles. Dashes 8 mm long, 1.7 mm wide, offset 1.5 mm. Endpoint bone weights interpolate from the original garment vertices. Joined into existing HeroOutfit mesh and material; no added mesh primitive or material surface. Existing skeleton retained; exported without clips.

Review: detail is very subtle in full-body render. Close-up shows small stitch shadows along the belt, but face, hair and chunky outfit silhouette still dominate quality. This does not justify automatic production adoption. Not checked through the full animation set; flat stitch strips may become hidden or clip under deformation. Preferred production solution for fine stitching is an authored/baked material detail after device measurement, with geometry reserved for features that affect silhouette.

Candidate: kingdom/assets/incoming/ai3d/hero_styleg_leather_experiment.glb. Close-up: docs/concepts/hero_leather_closeup.png. Reproducible script in character_blender_pipeline/detail_hero_leather.py; requires hero_refined_mobile.blend alongside it. Local saved blend C:/Users/Jonna/Documents/Codex/3d-tools/TripoSR/hero_leather_detail.blend. Game player and Claude's outfit script unchanged.
