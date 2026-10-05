# AAA polish plan (from the owner's 15 reference videos, 2026-10-05)

**Sources:** `docs/research/VIDEO_STUDY_B1.md`, `B2.md`, `B3.md`. The references are Avatar bending, a UE5 elemental-combat trailer, Where Winds Meet, stylized VFX tutorials, a radial weapon wheel and Roblox polish reels. They are reference only: copy no IP, assets or branding. Every item stays inside Style G and the phone budgets (`ashes-performance`, `ashes-style-g`).

## P0: combat feel (cloud code, cheap). Every review ranked it first.
- **Hit-stop, tiered:** light hits get 0, heavy 2 frames, finishers and guard breaks 3, plus a FOV punch, a short camera roll and a 1-frame flash on finishers. Code goes in `combat_feedback.gd` and the signal bus.
- **Layered impact scene, pooled:** flash, ring, slash quads, sparks or embers, dust, a ground splat, with per-element variants. Cap the number active.
- **Hit reactions:** stagger, launch, a ragdoll knockdown that falls, slides and settles, and bodies that persist briefly.
- **Attack magnetism and lunge** toward the locked target (root-motion step-in clips belong to Codex).
- **Telegraph rings** on the ground under enemy heavy attacks and charged casts, and a red highlight on the locked or striking enemy.

## P0: camera and HUD (cloud code, cheap)
- **Responsive chase camera:**
  - FOV and distance grow when sprinting or dashing.
  - Higher framing on rooftops and open ground, lower and tighter in fights.
  - Lock-on framing.
  - Short dramatic cast cameras for big techniques (optional, skippable).
- **World-space objective marker** with distance and a verb line (story leads stay text-only per the owner's no-glowing-markers rule, so markers appear only for player-pinned targets). Floating threat plates on hostiles only.
- **Radial technique/weapon wheel:** slow time while open, a focus glow, a live hub label, and a dissolve on confirm.

## P1: powers and VFX (cloud code + local art)
- **One timing template for every technique:** anticipation hold, then flash with radial blur, glow on the limbs, travel, impact, residue for 0.5–1 s.
- **Toon noise-threshold shader and a 1 s ease-out burst preset.** These form the shared VFX language.
- **Colour and shape language per element and path:** reused by VFX, HUD tint and unlock cards. The palette stays inside Style G's warm range, and bloom is set so only VFX glow.
- **Pooled ground decals:** scorch, frost, cracks, dust, footprints and splashes that fade over time.
- **Torches and braziers:** emissive meshes with a flickering billboard glow and no omni lights.
- **Fake water and ice:** scrolling-normal ribbons, fresnel, foam edges (local GPU tuning).

## P1: world life
- **Spring-bone secondary motion** on cloaks, hair, tails and banners, near actors only (Codex/cloud).
- **Speech-bubble barks** for micro_events, night fireflies, and a dash streak ribbon.
- **Soulbeast quality bar:** hair cards, baked secondary motion, eye detail, an accessory kit (local art).

## P2
- Rooftop traversal.
- A dark-mastery capstone technique per path.
- Whiteout and match-cut transitions.

## Release (when submitting to stores)
Compliance checklist from video 8432f98d: privacy policy, data deletion, children's data, licence audit, no dark patterns or hidden fees.
