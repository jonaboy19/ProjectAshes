# Video study B1 (owner reference clips)

Method: `ashes-video-review` (frames to numbered contact sheets, read in order). Sheets kept in `/tmp/claude-0/videostudy/b1/<id>_sheet.png`.
Tags: owner = CC (cloud code) / PC (local art+GPU) / CX (Codex animation). Mobile (Galaxy S22) = cheap / moderate / expensive. P0-P2.

NOTE: `93ad6fba-RDT_20261005_123635.mp4` is NOT our game. It is a PC capture of a French-UI wuxia open-world action game (looks like Where Winds Meet; HUD text "Ruines du Vieux Village", white-robed hero, oil-paper umbrella glider). Treat it as a competitor/benchmark, not a self-critique.

## 1. 4981c458 (2:57, 576x1024) - "All bending from the unaired ATLA pilot episode"
TikTok compilation (@kionaed1ts) of 2D animated Avatar pilot clips: earth stomp/crack, air scooter/glider, fire jets and big fireball, waterbending bubble and tide, final Zuko vs Aang fight on a dome. No 3D, no gameplay.
What reads premium: (a) every bending move has a clear 3-beat read: wind-up pose, hard-contrast action pose, effect lingering after the body stops; (b) elements are shape-language first: fire = fast hot flare with white core on orange, water = translucent blob that holds a readable silhouette, air = spiral ribbons around the body, earth = chunky debris with dust; (c) camera cuts to a close-up of the face (determined eyes, glowing arrow) right before the power payoff; (d) whole scene tinted by the element (orange fire scenes, blue night); (e) smear/blur frames on fast moves (frame #36 Aang blur).
Takeaways
- Per-element colour grade during a technique (brief 0.3-0.6 s tint/vignette, e.g. orange for fire arts): CC, cheap, P1 (hook in technique_caster.gd cast start/end via a CanvasLayer ColorRect, mobile-safe, no post shader).
- Effect outlives the body: keep trail/residue (embers, ripple ring, dust) 0.5-1 s after the cast animation ends: CC (scripts/combat VFX), cheap, P1.
- Silhouette-readable VFX at phone size: one dominant shape + white-hot core, never noisy particles: CC/PC, cheap, P1 (style_g warm palette ok).
- Smear/stretch frames on dash/swing (1-2 frames of stretched mesh or additive arc): CX (animation) / CC (mesh arc), cheap, P2.
- Face/hero close-up beat before an ultimate: short FOV punch-in + slow-mo 0.15 s: CC, cheap, P2.

## 2. 56f42fc2 (2:26, 576x1024) - "pov: the true potential of average benders if it wasn't a kids show"
TikTok (@awminb) montage of stylised bending fights in animated silhouette style. Four chapters, each with a full-frame element colour wall and a faded giant kanji watermark: green (earth), red (fire, kanji beyond), blue (water/lightning), tan (air). Characters are flat dark silhouettes against the wall; only the effect carries colour.
What reads premium: (a) silhouette-vs-colour-wall staging makes poses legible instantly; (b) hard colour swap between chapters (frame #17 flat red flash, #24 white manga speed-line flash) acts as a transition and an impact frame; (c) ground-line effects (fire sheets, ice spikes, dust clouds, rock chunks) rise from the baseline; (d) giant looming hands/foreground silhouettes at the end for scale (frames #67-#70); (e) lightning drawn as thin neon cyan lines on cold blue.
Takeaways
- Impact-frame flash (1-2 frames white/black with speed lines) on heavy finishers/crits instead of long hit-stop only: CC (HUD overlay + Engine.time_scale), cheap, P1.
- "Technique card" intro: when a rare power/path first activates, show element-coloured wall + kanji/rune watermark for 1.5 s (path unlock, power ritual): CC (HUD) + PC (rune art, free glyphs OFL font), cheap, P2.
- Per-element colour language for power paths (earth green-brown, fire red, water blue, air tan): CC (power_paths.gd palette constants reused by VFX/HUD), cheap, P1.
- Foreground silhouette framing for boss reveals (large hand/shape in the foreground): CC camera, moderate, P2.

## 3. 93ad6fba (0:18, 1280x720) - PC capture of a competitor AAA-style wuxia action game
What it is: third-person open-world action, French UI, ruined fortified village, rain-wet roads, torch fires, red banners, wooden watchtowers and gates. Hero in white robe with blue umbrella glider (frames #0-#8), then ground fight vs one dark-clad enemy (#12-#17), roof/rooftop traversal and wall-running (#18-#52), a thrown log/cart combo (#36-#41), red glowing "mystic art" cast on enemies (#10-#11, #22, #34, #45).
What makes it feel premium
- Camera: mid-height chase cam that swings wide on dashes (#3-#5), pulls high over rooftops (#30-#35), drops low behind the fight (#12-#17); the camera never sits still, always framing the character plus the next goal (gate in distance). Big FOV and real depth layers (foreground plank/pole, mid village, distant cliffs).
- Lighting: hard low sun through gaps casts long shadows and bright wet-ground specular streaks (#12-#17, #23); dark foreground with a bright pocket where the action is; warm torch points (small orange emissive + glow) against cool blue sky/fog; layered mist at distance.
- Ground: puddles, wheel ruts, mud, scattered debris and grass tufts everywhere; no flat plane.
- Combat feel: red energy glow on the target as a lock/mark (#10, #22), enemy knocked flat and ragdolled (#14-#16), clear impact sparks and wide arc trails; fight moves along the lane, character slides into position (gap-closer).
- HUD: restrained. Tiny compass/top icons, quest line top-left, small skill diamonds bottom-right, stamina/health thin bars bottom-left; text small, low contrast, vanishes in action. Object prompts are small floating labels over the thing ("Mécanisme de..."), not a big button.
- Traversal polish: glider umbrella deploy, rooftop clamber animation, wall-run: movement itself is the fun, and the camera follows it.
Gaps vs Rising Ashes (from docs/design/VERTICAL_SLICE.md intent, no code changed): we do not yet have dense debris/puddle dressing, wet specular, long-shadow light direction, a dash-framing chase cam, or a lock-on glow.
Takeaways
- Dash/sprint chase cam: FOV +5-8 deg and distance +10 % on sprint/dash, ease back on stop: CC (camera rig), cheap, P0.
- Target mark glow (red outline/ground ring) on the locked enemy and on the one about to strike: CC (scripts/combat + shader outline already common), cheap, P1.
- Wet-ground look after rain: roughness drop + a few baked puddle decals with sky reflection (SSR not needed, fake with reflection probe cubemap or a bright additive decal): PC (decals/textures), moderate, P1; CC rain trigger hook.
- Torch/brazier = emissive mesh + billboard glow + flicker, no real lights (matches style_g rule "no omni except one lantern"): CC/PC, cheap, P0.
- Low-sun long shadows + dark-foreground/bright-pocket composition around fights: CC style_g sun angle on combat arenas, cheap, P1.
- Knockdown reaction to ragdoll-lite (fall + slide + settle, 1.2 s) rather than a static stagger: CX animation + CC, moderate, P1.
- Hit stop 2-3 frames + camera nudge on heavy hits (visible as tight pairs of near-identical frames at impacts): CC (player.gd combat), cheap, P0.
- Contextual interactable labels floating on world objects, tiny: CC HUD, cheap, P1 (already P0 in slice doc; confirm tiny/world-anchored instead of a big button).
- Roof/clamber traversal: CX animation + CC, expensive (nav/collision authoring), P2.

## 4. cba27a4d (0:10, 960x540) - "bravo.vfx" TikTok live-action power-up VFX
Real person in a field does a crouch charge, bursts with green energy, then a "Full Cowl"-style lightning power-up, a lunge, and a whip-pan strike into a blue sky; ends on black.
Timeline: #0 handheld whip-in blur, #3-#15 (0.75-3.75 s) anticipation crouch with wind-up (quiet, the long hold is what sells it), #16 (4.0 s) green flash + radial zoom blur = release, #18-#20 glow on hands/legs (energy lives on limbs), #21-#23 camera snap away + dust cloud + sky/colour grade change (whole frame brightens), #24 white-out bloom flash, #25-#26 vertical lightning pillar, #29-#30 extreme close-up of eyes glowing then fist, #32-#35 whip-pans with motion blur and lightning trails, #36 hit with blood-red debris/blue flash, cut to black.
Premium cues: long anticipation then very short release; radial blur/zoom on the release frame; bloom flash 1-2 frames; limb-attached glow; camera whip-pans as the transition between beats; colour grade shift (grass-green to cold blue sky) to mark "powered up"; ambient dust and grass displacement.
Takeaways
- Power-up/charge release template: hold 0.5-1 s of anticipation with rising glow, then 1-2 frame white flash + radial blur, then hold aura: CC (technique_caster.gd, radial blur as a cheap CanvasItem shader on a ColorRect, only during the flash), cheap-moderate, P1.
- Limb-attached glow (emissive hand/foot materials + small additive trails, not full-body particle): PC/CX (bone attach points) + CC, cheap, P1.
- Whip-pan/zoom-snap transition for fast travel, dodge or sprint-hit: CC camera, cheap, P2.
- Colour-grade shift during a buff (cooler/brighter via the LUT or a ColorRect tint): CC (style_g adjustment parameters, not on LOW tier), cheap, P2.
- Ground dust/grass kick on release (ring + radial particles, 12-20 sprites): CC, cheap, P1.
- Vertical light-pillar/lightning (2-3 camera-facing additive quads with scrolling noise): CC/PC, cheap, P2.
Technique steps: edited live-action composite; no tool/tutorial content to license-check. Nothing to adopt directly; do not copy the MHA branding.

## 5. 0c359e8b (0:20, 1024x576) - Roblox-style dev showcase of Tokyo Ghoul kagune tentacles (@darkpr1mee)
A character (blocky Roblox rig) with two pink fleshy tentacles and two red tail/wing tentacles, procedurally animated: they sway continuously, lag behind motion, curl and untangle; camera orbits/pulls back (#0-#15 near, #16-#31 far). HUD: round 100 level badge, bars, a bottom skill hotbar of 6 slots, top-right panel (standard hotbar-style Roblox UI). Ends on TikTok end card.
Premium cues: follow-through and overlap on secondary limbs (always moving, never a still pose); varied length/thickness/curl per tentacle; red vs pink colour split reads as "two attack sets"; subtle idle sway means the character feels alive standing still.
Takeaways
- Procedural secondary-motion chains (spring bones) for tails, cloaks, hair, banners, cape, beast tails and magic tendrils: CC/CX; in Blender use Wiggle 2 (GPL-3 add-on, bake to GLB is fine) / in Godot use free `SpringBoneSimulator3D` (built-in, MIT, Godot 4.4+) or `PhysicalBone`-free Verlet chains in GDScript; mobile cheap if <=8 bones per chain, limit to near actors: P1.
- Idle-sway rule: nothing is ever static (cloth, hair, weapon, tail) even in idle: CX/CC, cheap, P1.
- Tentacle/tendril power as a power-path (Soulbeast or dark path) with attack reach, grab, whip, shield: CC design (ashes-ability-system), moderate, P2.
- Skill hotbar of 6 round slots with cooldown sweep and key hints; at phone size keep at most 4 + one primary: CC HUD, cheap, P1.
Free/licence: SpringBoneSimulator3D is Godot core (MIT); no Roblox assets used. Never adopt Higgsfield.

## Ranked top 10 takeaways for Rising Ashes
| # | Takeaway | Owner | Mobile | P |
|---|---|---|---|---|
| 1 | Hit-stop 2-3 frames + tiny camera nudge/FOV kick on hits; stronger on heavy/crit; impact flash frame on finishers | CC (player.gd, scripts/combat) | cheap | P0 |
| 2 | Chase camera that reacts to movement (sprint/dash FOV + distance, high pull over rooftops/low behind fights) | CC | cheap | P0 |
| 3 | Technique cast template: anticipation hold, 1-2 frame flash + radial blur release, limb-attached glow, residue 0.5-1 s | CC (technique_caster.gd) + CX anims | cheap-moderate | P1 |
| 4 | Dense ground storytelling: puddle decals, ruts, debris, wet specular, grass tufts so the plane is never flat | PC art + CC placement hooks | moderate | P1 |
| 5 | Torches/braziers via emissive + billboard glow + flicker (no omni lights); warm points vs cool sky | CC/PC (style_g) | cheap | P0 |
| 6 | Low-sun long shadows and a dark-foreground/bright-pocket composition for combat arenas | CC (style_g sun per tier) | cheap | P1 |
| 7 | Secondary motion everywhere: spring bones on cloaks, hair, tails, banners; idle never static | CX/CC (SpringBoneSimulator3D) | cheap (near actors only) | P1 |
| 8 | Lock/target mark: red glow ring/outline on locked and on striking enemy, plus knockdown that falls, slides and settles | CC + CX | cheap-moderate | P1 |
| 9 | Element colour language per power path (earth green-brown, fire red, water blue, air tan) reused by VFX, HUD flash tint, technique card | CC (power_paths.gd) | cheap | P1 |
| 10 | Restrained world-anchored HUD: small floating interact labels, thin bars, skill diamonds; hide when idle | CC HUD | cheap | P1 |

Not worth it now: rooftop clamber/wall-run (P2, expensive), vertical lightning pillar and technique-intro cards (P2, nice-to-have).
No tutorial videos in this batch, so no tool/technique licence issues; all adoptable items are engine-native or already-approved free tools.
