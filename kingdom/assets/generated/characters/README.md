# MakeHuman villagers (rigged on the UAL skeleton)

Realistic-but-clean medieval characters that replace the chunky low-poly villagers
and player. Generated headlessly by `tools/blender/make_humans.py` (+ `mh_core.py`,
`ual_rig.py`) from the MakeHuman / MPFB2 base mesh and targets (CC0), with
procedural clothes and hair and ambientCG fabric textures (CC0).

```
python3 tools/blender/make_humans.py            # all characters + previews (~20 min, Cycles CPU)
python3 tools/blender/make_humans.py --only guard,mother --no-preview
python3 tools/blender/make_humans.py --closeups # also face / body close-ups
python3 tools/blender/make_humans.py --turn     # front / 3/4 / side / back per character (debug)
```

Needs the MPFB2 data at `/tmp/claude-0/mh/mpfb2/src/mpfb/data` (override with
`MPFB_DATA`) and the MakeHuman 1.x `data/` folder for the eye mesh (`MH_DATA`).

## Files

Previews: `docs/kingdom/blender_previews/characters.png` (lineup at natural
heights, Cycles), `characters_faces.png`, `characters_outfits.png`, and the
Godot captures `characters_godot_lineup.png` / `characters_godot_clips.png`.

`build_report.txt` is rewritten on every run (name, LOD0 triangles, LOD1
triangles, natural height, metres per model unit).

| file | LOD0 tris | `_lod1` tris | natural height | outfit |
|---|---:|---:|---:|---|
| `villager_man_a.glb` | 5349 | 2137 | 1.75 m | green linen tunic, belt + pouch, trousers, boots, short hair |
| `villager_man_b.glb` | 5350 | 2140 | 1.78 m | rust wool tunic (short sleeves), trousers, boots, short black hair; African/European mix |
| `villager_woman_a.glb` | 5263 | 2104 | 1.61 m | blue wool dress + linen apron, bun and braid |
| `villager_woman_b.glb` | 5909 | 2363 | 1.52 m | red linen dress, brown cloak with hood down, bun and braid; East Asian/European mix |
| `elder_man.glb` | 6199 | 2479 | 1.71 m | ochre tunic, green cloak (hood down), horseshoe grey hair |
| `elder_woman.glb` | 5945 | 2378 | 1.48 m | plum dress + apron, cloak with the hood up |
| `child_boy.glb` | 5136 | 2053 | 1.35 m | 8 yrs, blue tunic, trousers, boots, tousled hair |
| `child_girl.glb` | 4835 | 1934 | 1.27 m | 8 yrs, green dress + apron, bob |
| `guard.glb` | 5596 | 2238 | 1.86 m | blue quilted gambeson (high collar, long sleeves), belt + pouch, trousers, boots |
| `player_young.glb` | 5346 | 2138 | 1.66 m | 18 yrs, neutral tan tunic, trousers, boots, short hair (base for the player) |
| `mother.glb` | 5259 | 2102 | 1.64 m | teal linen dress + apron, bun and braid (birth cutscene) |
| `father.glb` | 5348 | 2139 | 1.74 m | red wool tunic, tan trousers, boots, short hair (birth cutscene) |

Every GLB holds one skinned mesh (one surface, one material `CharacterAtlas`)
and the 65-bone UAL armature (`Armature/Skeleton3D`), no animations. All
characters share the same three textures in `textures/` (1024 px atlas:
skin, linen, wool, coarse wool, check, felt, quilting, leather, hair, eyes,
metal): the GLBs reference them by relative URI, so Godot loads each PNG once
and every villager uses the same textures. Per-character colour (skin tone,
clothing palette, hem dirt, hair colour) lives in the vertex colours
(COLOR_0), which Godot's glTF importer applies as albedo
(`vertex_color_use_as_albedo = true`). Roughness/metal/AO come from
`character_orm.png` (skin 0.5, cloth 0.93-0.98, leather 0.55-0.8, hair 0.58,
buckles metallic), normals from `character_normal.png`.

The ambientCG fabrics (Fabric061 linen, Fabric066 homespun wool, Fabric083
check) are baked into 256-512 px tiles of that atlas (softened and
desaturated for the painterly look, colour comes from the vertex colours);
leather, felt, quilting, hair strands and the skin are generated
procedurally (skin painted in MakeHuman UV space using the MPFB lip / lid /
nail / ear masks, with analytic eyebrows, cheeks and eye sockets). Changing
the look of every villager at once = editing three PNGs.

Budgets: 4.9k-6.2k triangles per character (body ~2.1k incl. head and hands,
clothes 1.5-3k, hair 0.3-0.6k, eyes 172). Body faces hidden under clothing
are deleted before decimation.

## Skeleton and animation compatibility

* Bone names, hierarchy (`Armature > root > pelvis > ...`, 65 bones incl. the
  `*_leaf` bones) and **rest orientations are copied exactly from
  `UAL1_Standard.glb`**; bone *positions* are fitted to each MakeHuman body.
  The GLB is written directly (not via Blender's exporter) so the rest
  rotations are bit-for-bit the UAL ones.
* The UAL clips (as Godot imports them) contain rotation tracks for every bone
  and a single position track on `pelvis`. Rotations are absolute local
  rotations, so they play correctly on any skeleton with the same rest
  orientations. To keep the pelvis track valid each body is posed into the UAL
  T-pose (MakeHuman's own `game_engine` rig weights, whose names already match
  UE/UAL) and uniformly scaled so the hip joints sit at the UAL height
  (0.932 m); the pelvis is 1.5 cm below / 5 cm behind the hips like UAL. Feet
  therefore stay on the floor during walk / jog / crouch / sit.
* Skin weights: body and shell garments use MakeHuman's `weights.game_engine`
  weights (via the body vertex each garment vertex came from); skirts, the
  cloak and the belt get hand-built pelvis/thigh/calf and spine blends (so a
  skirt does not split between the legs); hair, eyes and hoods are 100 % `Head`;
  the braid blends Head -> neck -> spine.
* **Verified in Godot 4.6.2** (scratch project, same importer settings, the
  exact `_ual_for` track-path rewrite over `UAL1_Standard.glb` +
  `UAL2_Standard.glb`): `Idle`, `Walk`, `Jog_Fwd`, `Sword_Attack`,
  `Sword_Regular_A`, `Sword_Regular_C`, `Idle_Shield`, `Roll`, `Sitting_Idle`
  and `Death01` all drive the new meshes (adults, elders and both children)
  with no explosions or stretched vertices; see
  `docs/kingdom/blender_previews/characters_godot_lineup.png` and
  `characters_godot_clips.png` (flat test lighting, so colours look harsher
  than in the game or the Cycles previews).
* **Children** (8 years) use the same skeleton with child proportions
  (shorter legs relative to the head). Because the model is normalised to the
  UAL hip height, the game's "scale whole model to height" path works: ask for
  ~1.25 m and the child's hips land at child height and the pelvis track is
  scaled with it. Walk/jog look right; arm swings are adult-sized relative to
  the shorter arms, which reads fine at game distance.
* Every GLB is normalised to a hip height of 0.932 model units, so the models
  are *not* at their natural size (a child GLB is as tall in the legs as an
  adult one). Always scale by the head bone like `Assets.humanoid` does. The
  natural heights are in `build_report.txt` (men ~1.75 m, women ~1.6 m,
  elders ~1.5-1.7 m, children ~1.3 m, guard 1.86 m).

## How `assets.gd` should load these

Add a GLB branch next to `humanoid()` (no other changes are needed, the
existing `_ual_for` cache is reused because the skeleton path is the same
`Armature/Skeleton3D` as the Superhero bodies):

```gdscript
const MH_DIR := "res://assets/generated/characters/"
## Look names -> MakeHuman character GLBs (one is picked at random).
const MH_LOOKS := {
	"Rogue_Hooded": ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "elder_man", "elder_woman"],
	"Barbarian": ["villager_man_a", "villager_man_b", "father"],
	"Mage": ["villager_woman_a", "villager_woman_b", "mother", "elder_woman"],
	"Rogue": ["villager_man_b", "elder_man", "villager_man_a"],
	"Knight": ["guard"],
	# new look names the callers can start using:
	"Player": ["player_young"], "Guard": ["guard"],
	"Mother": ["mother"], "Father": ["father"],
	"Child_Boy": ["child_boy"], "Child_Girl": ["child_girl"],
	"Elder_Man": ["elder_man"], "Elder_Woman": ["elder_woman"],
}
const USE_MAKEHUMAN := true

static func character(file_name: String, height: float, keep: Array[String] = []) -> Node3D:
	if USE_MAKEHUMAN and MH_LOOKS.has(file_name):
		var files: Array = MH_LOOKS[file_name]
		return mh_character(files[randi() % files.size()], height, keep)
	if USE_REALISTIC and LOOKS.has(file_name):
		return humanoid(LOOKS[file_name], height, keep)
	... (unchanged)

## A MakeHuman GLB on the UAL skeleton, `height` metres tall, with the UAL clips.
static func mh_character(file: String, height: float, keep: Array[String] = [], lod1 := false) -> Node3D:
	var root := Node3D.new()
	var base: Node3D = (load(MH_DIR + file + ("_lod1" if lod1 else "") + ".glb") as PackedScene).instantiate()
	root.add_child(base)
	var skeleton: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	for part in keep:      # same props as humanoid(); the rig is in metres, _rig_scale() == 1
		if part.contains("Helmet"):
			_attach(skeleton, "Head", HELMET, 0.3, Vector3(0, 0.08, 0.02), Vector3.ZERO)
		elif part.contains("Axe"):
			_attach(skeleton, "hand_r", WEAPONS + "Axe_Bronze.gltf", 0.75, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("2H_Sword"):
			_attach(skeleton, "hand_r", WEAPONS + "Sword_Bronze.gltf", 1.3, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("Sword"):
			_attach(skeleton, "hand_r", WEAPONS + "Sword_Bronze.gltf", 0.95, Vector3(0.05, 0.02, 0), Vector3(0, 0, -90))
		elif part.contains("Shield"):
			_attach(skeleton, "lowerarm_l", WEAPONS + "Shield_Wooden.gltf", 0.62, Vector3(0.12, 0, 0.08), Vector3(0, 90, 0))
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	base.add_child(anim)
	anim.root_node = anim.get_path_to(base)
	anim.add_animation_library("", _ual_for(base.get_path_to(skeleton)))
	var head := skeleton.find_bone("Head")
	var native := skeleton.get_bone_global_rest(head).origin.y * 1.1
	root.scale = Vector3.ONE * (height / maxf(native, 0.01))
	return root
```

Callers that want the dedicated models: `main.gd` birth cutscene ->
`"Mother"` (1.64 m) / `"Father"` (1.80 m); `player.gd` -> `"Player"`
(1.8 m); children -> `"Child_Boy"` / `"Child_Girl"` at ~1.25 m; guards ->
`"Guard"`. The existing `Knight` / `Rogue` / `Mage` / `Rogue_Hooded` /
`Barbarian` callers work unchanged through the map above. The impostor
baker picks the new models up automatically because it goes through
`Assets.character`.

The prop offsets were tuned for the Superhero head/hands; they are close but
may want a 1-2 cm nudge (the MakeHuman head is slightly smaller).

## LOD

* `*_lod1.glb`: the same character decimated to 40 % (1.9k-2.5k triangles),
  identical skeleton, so it takes the same `_ual_for` library. Swap LOD0 ->
  LOD1 at **~18 m** (the face stops reading at that distance), and hand over
  to the existing impostor sprites at `PopulationLOD.FULL_RANGE` (45 m).
  With `GeometryInstance3D.visibility_range_*` on two instances, or simply
  spawn `mh_character(..., lod1 = true)` for villagers beyond 18 m.
* Godot's own auto-LOD also works on these (the `.import` files keep
  `meshes/generate_lods=true`, which Godot applies to skinned meshes too); it
  switches by screen size, so the explicit LOD1 is only needed when you want
  a deterministic distance switch or to save the LOD0 memory.

## Known issues

* Clothes are shells fitted in the T-pose and skinned to the body; extreme
  poses (deep crouch, roll) can make long skirts and the cloak intersect the
  legs a little, and a tunic's front splits slightly over the thighs in a
  wide stride. There is no cloth simulation.
* No facial bones (UAL has none) - faces are static; eyes are fixed.
* Eyebrows are painted into the shared skin texture (dark neutral), so they
  do not follow the hair colour (fine for grey elders, slightly dark on the
  red-haired girl).
* The hood (elder woman) and hair are opaque shells (no alpha cards) to keep
  mobile overdraw low; they read as stylised volumes rather than strands.
* Vertex colours are clamped to 0-1 by Godot, so very light skin/fabric tones
  can lose a little saturation compared with the Blender previews.
* Source MakeHuman data is fetched outside the repo (MPFB2 git clone); the
  generator needs it to run, the committed GLBs/PNGs do not.

## Credits

MakeHuman / MPFB2 base mesh, targets, rig weights, eye mesh and texture
masks: CC0 (makehumancommunity.org). ambientCG Fabric061 / Fabric066 /
Fabric083: CC0 (ambientcg.com). UAL skeleton and clips: Quaternius, CC0.
