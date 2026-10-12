# NPC and hero faces

One state machine, two renderers, no new art assets.

- `kingdom/scripts/living_world/face_state.gd` (`FaceState`): blink (2-6 s, 0.28 s, 20 % double), mouth flap while speaking (6-9 Hz), 6 moods
  (`neutral happy sad angry fear surprise`) eased in 0.25 s, `mood_for(act, town_mood, opinion, line_mood)`, `say_seconds(text)`, `cards_enabled(tier, renderer)`.
- `kingdom/scripts/living_world/npc_face_card.gd` (`NpcFaceCard`): a 2-triangle quad on a `BoneAttachment3D("FaceCard")` on the Head bone that draws ink brows,
  upper lids and a mouth (`shaders/npc/npc_face_card.gdshader`, shared drawing in `face_card_common.gdshaderinc`, timber ink 4a3220 in linear, unshaded, no shadow).
  - **Villagers**: one shared material, per-instance uniforms (Mobile / Forward+ only). Created on MEDIUM+ with a non-Compatibility renderer, visible only while
    `lod_tier == 0` and inside 12 m. LOW creates nothing.
  - **Hero**: same card with its own material (`hero_face_card.gdshader`, plain uniforms, works in Compatibility), every tier, always visible. It draws the mouth only:
    the brows are a uniform (`face_brow`) on the hero's own copy of `hero_character.gdshader` (existing brow UV rects), the lids are the `Lids` patch (blink + squint).
    The hero mouth could not be done in the shader: the atlas UVs around the mouth are scattered over several islands (probe: `tools_qa/hero/face_uv_probe.gd`).
- `HeroFaceDriver` (`set_mood`, `say(text)`, `talk(s)`), `Player.face_say(text, mood)` / `face_mood(m)`, `Villager.face_say(text, line_mood, opinion)`.

## Dialogue keys

A line may carry `"mood"` (speaker) and `"hero_mood"` (the hero), each one of `FaceState.MOODS`; `DialogueRunner.validate` rejects other values and `pick_line` returns them.
The town generator (`kingdom/tools/towns/gen_town.py`) tags enemy greetings `angry` and friend greetings `happy`. Without a tag the NPC mood comes from
`mood_for` (act, town mood, opinion). `village_services._enter` / `_choose` call the faces; story conversations (`r1_story_director`, Hesta `talk_body`) are not wired yet.

## Calibrating a look

`kingdom/data/living_world/face_offsets.json`, keyed by the picked GLB base name (`model.get_meta("mh_look")`, set in `Assets.mh_character`):
`offset` (card centre from the Head bone, skeleton units), `size`, `layout` = `[mouth_y, mouth_half_width, eye_x, brow_y]` (card-local), or `"disabled": true`.
Run `godot --path kingdom --rendering-method mobile -s tools_qa/living_world/face_card_shots.gd -- --out=C:/tmp/cards --only=<look>` (add `--off=x,y,z --size=w,h --layout=a,b,c,d`
to try values; `<look>_debug.png` is the solid magenta card), read the sheets, then write the numbers into the JSON. The card is under the skeleton, so it scales with the body.
Hero: `tools_qa/hero/face_shots.gd` (moods, dialogue range, blink, talk, debug).

Classes fitted so far: MakeHuman heads (all `villager_*`, elder, child, father, mother, player_young; also cdmir monk / old lady with a lower brow), G6 modular (`g6_*`, flat card at z 0.26:
raised brows can hide behind the forehead, angry / frown / smile read), disabled: helmeted / armoured / hooded / masked looks, `villager_white_shirt`, `villager_hat`.
Known gaps: brows of "happy/fear/surprise" on G6 faces are partly hidden by the receding forehead; the hero reads about 6/10 (mouth + brow nudge, small at dialogue range).
