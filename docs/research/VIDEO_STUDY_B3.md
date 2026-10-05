# Video study B3 (owner reference videos)

Method: ashes-video-review (frames 1.5-3 fps, numbered/timestamped sheets, read in order). Sheets: `/tmp/claude-0/videostudy/b3/<video>_sheet*.png`.
Note: e7de2418 and b2121564 are byte-identical (same md5); studied once. Only 2 of 4 are game-relevant; one is off-topic.
All four are TikTok screen-captures (creator handles burned in), so none is a full AAA game: they are Roblox-Studio-grade UI/VFX showpieces. The lesson is *polish technique*, not scope.

## 1. e7de2418 / b2121564 (0:49) - "Equip a Weapon" radial menu, @gfxcomet (gfxcomet.com), Roblox Studio
- Content: two radial weapon-selector UIs on a dummy in a blue grid void. V1 (0-10 s): four ink-brush "torn paper" arcs (axe, bow, sword, hammer-like) around the character, centre label "EQUIP A WEAPON"; the focused arc flashes purple with a yellow slash-glint, others stay black ink. V2 (10-32 s): 8-segment Japanese-ink wheel (Wakizashi, Yumi Bow, Katana, Kunai), kanji watermark in hub, hub label changes to the highlighted weapon name, highlighted wedge floods blood-red with speckle splatter and ink-dust particles; wheel bursts out/dissolves into red droplets onto the character on confirm (s 14, 20, 32). 34-48 s: the character idles with the chosen sword on the back, then TikTok end card.
- Why it feels premium: every UI element is textured (brush-edge masks, ink grain, particle dust), has anticipation (wheel spins/scales in with slight overshoot, frames s 27 shows tilt/blur mid-spin), a strong single accent colour for selection, a live hub label, and a confirm "payoff" (particle dissolve) tied to the 3D character. Implied audio: ink whoosh on open, tick per segment, slash on select.
- Takeaways:
  - T1 Weapon/technique radial (hold-to-open, flick to select, time-slow while open): scripts/ HUD + `ashes-ability-system` hotbar. Owner: cloud code (logic) + Codex/local art (brush-mask textures). Mobile: cheap. Priority: P1.
  - T2 Selection payoff: dissolve into themed particles (embers/ash for us) and character equip animation on confirm. Owner: cloud (GPUParticles2D/CPU particles) . Cheap. P1.
  - T3 Style fit: use warm parchment/charcoal "ash and ink" textures, accent = ember orange/rust red rather than purple; keeps Style G. Owner: local art. Cheap. P2.
  - Tool: it is a Roblox Studio UI build (no tutorial steps shown). Nothing to licence; do not copy the art (creator's asset, kanji and weapons).

## 2. 8432f98d (0:30) - "20 things to have Claude do so your app doesn't get sued" (@millee.md)
- Content: talking-head listicle with live captions and a counter filling a 1-20 list: privacy policy, terms of service, refund policy, cookie policy, cookie consent banner, check form consents, no unnecessary data, audit third-party SDKs, remove dark patterns, remove hidden fees, remove fake reviews, remove unsupported claims, accessibility alt text, fix colour contrast, keyboard navigation, add business details, age consent for kids' data, unsubscribe link in emails, license fonts/images, data deletion request/option.
- Premium cues: none for games (list builds in sync with captions - good pacing for tutorials only).
- Not a visual reference. Useful as a **store/legal checklist** for release (ashes-release): privacy policy and data deletion (Google Play Data Safety, account/data deletion requirement), age rating and kids' data (COPPA/Families policy if any under-13 audience), licence audit of fonts/images (our free CC0/MIT/OFL rule already covers this), no dark patterns or hidden fees in any future IAP/shop (also Play policy), remove unsupported marketing claims in the store listing. Owner: cloud code/docs. Cheap (docs). Priority: P2 now, P0 before store submission. Not legal advice.

## 3. b3b07f8a (0:25, 576x1024, stored rotated 90 degrees) - Waterbending (Avatar style) VFX composite, @arcomade
- Content: a live-action/performance-captured figure in a blue Water Tribe parka on a snowy ice palace deck with a dark sea behind; she whips water: ribbon wraps around her (s 1-2), water orb pulled from the sea (s 4.5-7), splash/impact bursts, an ice slab forms and is shoved (s 12-13), final giant crystal-clear ice X-ribbons wrap the screen then whiteout transition (s 15-17.5). Camera cuts between 4-5 angles, low/side angles, fast whip-pans.
- Premium cues: believable fluid (translucent refractive ribbons with foam and droplets), VFX interacts with the body (wraps, drags the cloth), secondary particles (sea spray, snow kick-up, ice shards), cold desaturated blue grade with white highlights, hard cuts on motion with a whiteout match transition, snow footprints for ground contact. Implied audio: water whooshes, ice crack, sea roar.
- Takeaways:
  - Elemental/bending powers (`power_paths.gd`, `technique_caster.gd`): author each technique as (anticipation pull -> travel ribbon -> impact burst -> lingering residue). Owner: cloud code for timing hooks, local art for flipbooks. Moderate. P1.
  - Cheap fluid look on mobile: scrolling-normal-map ribbon mesh (trail/Path3D tube) with fresnel + refraction fake (screen-texture sample or cube-reflect), foam sprite at the edges; no sim. Owner: local art/GPU. Moderate (one transparent pass; cap overdraw). P2.
  - Whiteout/flash match-cut transition for big powers and scene changes: full-screen additive flash, 2-4 frames. Cheap. P2 (cloud).
  - Ground contact decals (footprints in snow/mud/ash, splash decals) and ambient spray particles: `style_g` dressing + decals. Cheap-moderate. P1 (aligns with VERTICAL_SLICE P0 foot traffic).
  - Camera: multi-angle cutscene-style cinematics for ultimate abilities (short 1-2 s dramatic camera on cast, then return). Cloud code. Cheap. P2.
  - Not a tutorial, no tool named; likely After Effects/Blender-type composite; nothing to licence.

## 4. ddd58254 (0:15) - Green energy / "VysVEX" VFX reel, @vysdev, Roblox Studio (window chrome visible)
- Content: dark scene, a figure charges: green aura ground ring, shard/blade slashes radiating (s 1-3), huge swirling ribbons around a black silhouette character (hammer-wielding), shattered-rock debris, shockwave sphere (s 5), glowing orb with spiralling rings (s 6-8), then ground-slam pillar of light with splashing ink-shaped liquid and radiating speed lines (s 8-10.3). Strong camera work: fisheye/very close, rolls and zooms through the effect.
- Premium cues: stylised hand-drawn-looking VFX (anime/Spider-Verse shapes: sharp slash meshes, ink splashes, speed lines), one dominant hue plus near-black background for max contrast and glow, layers at several scales (core, rings, sparks, debris), camera FOV punches, frame-by-frame snappy timing with hold frames, screen-space bloom. Implied audio: charge hum rising, impact boom, glass-shard crack.
- Takeaways:
  - Our combat hit/impact stack (`combat_feedback.gd`, `hit_resolver.gd`): add layered impact = flash core + ring shockwave + 6-12 sharp slash-quads + debris chips, 6-10 frames. Owner: cloud code (spawn rules) + local art (textures). Cheap-moderate (pooled quads, additive, short life). P0-P1 for heavy attacks.
  - Camera punch: 3-6 degree FOV kick, 1-2 frame hit-stop, short roll on heavy hits and charges. `player.gd` camera + `combat_feedback.gd`. Cloud. Cheap. P0.
  - Charge-up tell with ground ring decal + rising particles (also an enemy telegraph for readability): npc_fighter attack tokens. Cloud + local art. Cheap. P1.
  - Contrast discipline: the effect reads on phones because it is one saturated hue vs dark; in Style G keep VFX in the warm palette (ember/gold) with cool sky fill, bloom threshold at 1.0 so only VFX glow. Owner: local PC. Cheap. P1.
  - Stylised slash meshes and ink splashes are cheap to make as CC0-free hand-built textures (Blender/Krita); never copy the creator's assets.

## Ranked top-10 takeaways for Rising Ashes
1. Hit-stop (1-3 frames) + FOV kick + short camera roll on heavy hits/casts (v4, v3). Cloud, cheap, P0.
2. Layered impact VFX (flash, ring, slash-quads, debris, ground splat), pooled and additive (v4). Cloud + local art, cheap-moderate, P0/P1.
3. Technique timing template: anticipation -> travel -> impact -> residue for every power path (v3, v4). Cloud, cheap, P1.
4. Ground-contact life: footprint/splash/kick-up decals and spray particles (v3). Cloud + local, cheap-moderate, P1.
5. Charge/telegraph ground rings for player casts and enemy attacks (v4). Cloud, cheap, P1.
6. Radial weapon/technique wheel with slow-time, focus glow, live hub label, dissolve-on-confirm payoff (v1). Cloud + Codex/local art, cheap, P1.
7. Warm-hue VFX grading: one saturated accent, bloom only above threshold, near-dark surround (v4, v3 desaturated cold contrast). Local PC, cheap, P1.
8. Fake-fluid/ice ribbon shader (scrolling normals, fresnel, fake refraction, foam edge) for water/ice powers (v3). Local art/GPU, moderate, P2.
9. Match-cut / whiteout flash transitions and brief dramatic cast cameras (v3). Cloud, cheap, P2.
10. Release compliance checklist (privacy policy, data deletion, kids' data, licence audit, no dark patterns) before store submission (v2). Cloud docs, cheap, P0 at release.

Licence note: none of the videos is a tool tutorial; no software or paid generator is needed. Everything above is buildable with Godot built-ins and free CC0/MIT/OFL assets. No Higgsfield.
