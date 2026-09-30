extends RefCounted
## Creature model table: which GLB each creature wears, how it is scaled, how fast
## its walk/run clips travel over the ground, when its attack clip connects, and
## which clip plays for each role. Preloaded by wolf.gd and monster.gd (no class_name).
##
## Checked with a Godot 4.6.2 headless probe (2026-09-28):
## - Every Meshy creature in assets/incoming/ai3d/meshy/creatures/ is a single skin
##   with clips idle, walk, run (not spider/wyvern), attack, hit, death; all tracks
##   resolve against the skeleton, and each _lod1 shares the skeleton and clips.
##   Real-world scale, origin at the feet, facing +Z like the Quaternius animals.
## - Skinned mesh AABBs of these files are in the rig's unscaled units, so
##   Assets.visual_aabb() would blow them up about 90x; they are used at scale 1.
## - "walk"/"run" are measured ground speeds (planted-foot travel per second);
##   "impact" is when the attack clip's fastest extremity peaks (the contact beat).
## - The Meshy goblin has no kneel clip. The orc's attack_charged starts from a
##   kneel and rises, and both are Meshy auto-rigs with the same 24 bones, so the
##   yield kneel and stand-up are cut from that clip (copying bone rotations
##   gave a 5.6 degree mean bone-direction error against the orc pose).
## Quaternius CC0 monsters in assets/incoming/monsters/quaternius/ follow the
## same clip names; they are used only once Godot has imported them.

const MESHY := "res://assets/incoming/ai3d/meshy/creatures/"
const QUAT := "res://assets/incoming/monsters/quaternius/"
const UAC := "res://assets/incoming/quaternius/ultimate-animated-character/glTF/"
const LIBRARY := "creature"
const KNEEL_SOURCE := "orc"
const KNEEL_CLIP := "attack_charged"
const KNEEL_RANGE := Vector2(0.0, 0.6)       # attack_charged opens kneeling
const STAND_RANGE := Vector2(2.3, 3.4)       # ... and rises to its feet here
const DEFAULT_CLIPS := {"idle": "idle", "walk": "walk", "run": "run", "attack": "attack",
	"hit": "hit", "death": "death"}

## kind -> {path (no extension), scale or fit_height, walk, run, impact, clips overrides}
const MODELS := {
	"wolf": {"path": MESHY + "wolf", "scale": 1.0, "walk": 0.85, "run": 2.6, "impact": 0.27},
	"boar": {"path": MESHY + "boar", "scale": 1.0, "walk": 0.45, "run": 2.7, "impact": 0.21},
	"bear": {"path": MESHY + "bear", "scale": 1.0, "walk": 1.35, "run": 4.0, "impact": 0.27},
	"goblin": {"path": MESHY + "goblin", "scale": 1.0, "walk": 0.87, "run": 2.64, "impact": 0.55,
		"kneel": true},
	"orc": {"path": MESHY + "orc", "scale": 1.0, "walk": 1.7, "run": 5.2, "impact": 1.11,
		"kneel": true},
	"troll": {"path": MESHY + "troll", "scale": 1.0, "walk": 2.4, "run": 6.9, "impact": 1.57,
		"kneel": true},
	"spider": {"path": MESHY + "spider", "scale": 1.0, "walk": 0.26, "run": 0.26, "impact": 0.5,
		"clips": {"run": "walk"}},
	"wyvern": {"path": MESHY + "wyvern", "scale": 1.0, "walk": 0.89, "run": 0.89, "impact": 0.47,
		"clips": {"run": "walk"}},
	"blight_rat": {"path": QUAT + "blight_rat", "scale": 1.0, "walk": 0.33, "run": 2.0, "impact": 0.4},
	"giant_rat": {"path": QUAT + "giant_rat", "scale": 1.0, "walk": 0.3, "run": 1.8, "impact": 0.4},
	"fungal_brute": {"path": QUAT + "fungal_brute", "scale": 1.0, "walk": 1.5, "run": 1.5, "impact": 0.35,
		"clips": {"run": "walk"}},
	"blackcap_brute": {"path": QUAT + "blackcap_brute", "scale": 1.0, "walk": 1.5, "run": 1.5, "impact": 0.35,
		"clips": {"run": "walk"}},
	# Region 1 creatures (package C11, docs/regions/REGION_1_PLAN.md). Speeds and impact beats are first estimates from the
	# clip lengths (Quaternius clips: assets/incoming/monsters/README.md; Stagborn: stagborn_README.md): Codex tunes them (X3/X4).
	"ghoul": {"path": QUAT + "ghoul", "scale": 1.0, "walk": 0.7, "run": 2.4, "impact": 1.3},
	"giant_wasp": {"path": QUAT + "giant_wasp", "scale": 1.0, "walk": 1.4, "run": 3.6, "impact": 0.4,
		"clips": {"walk": "idle", "run": "idle"}},
	"bog_toad": {"path": QUAT + "bog_toad", "scale": 1.0, "walk": 0.5, "run": 1.6, "impact": 0.4,
		"clips": {"run": "walk"}},
	"rift_slime": {"path": QUAT + "rift_slime", "scale": 1.0, "walk": 0.4, "run": 0.4, "impact": 0.3,
		"clips": {"run": "walk"}},
	"rift_wraith": {"path": QUAT + "rift_wraith", "scale": 1.0, "walk": 1.0, "run": 2.6, "impact": 0.6,
		"clips": {"walk": "idle"}},
	"stagborn_elk": {"path": MESHY + "stagborn_elk", "scale": 1.0, "walk": 1.21, "run": 5.2, "impact": 0.97},
	"stagborn_warden": {"path": MESHY + "stagborn_warden", "scale": 1.0, "walk": 1.24, "run": 6.9, "impact": 1.23},
	# Fallback when the Meshy goblin is missing: the old Quaternius character.
	"goblin_uac": {"path": UAC + "Goblin_Male", "ext": ".gltf", "fit_height": 1.1, "walk": 0.65, "run": 1.7,
		"impact": 0.3, "no_lod": true,
		"clips": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "SwordSlash", "hit": "RecieveHit",
			"death": "Death", "kneel": "SitDown", "stand_up": "StandUp"}},
}

static var _kneel_cache := {}     # kind -> AnimationLibrary


static func has(kind: String) -> bool:
	return MODELS.has(kind) and path_for(kind) != ""


## LOD0 normally; the lighter _lod1 (5k tris, 512 px) on Low/Medium quality tiers.
static func path_for(kind: String) -> String:
	if not MODELS.has(kind):
		return ""
	var m: Dictionary = MODELS[kind]
	var ext := String(m.get("ext", ".glb"))
	var base := String(m["path"])
	var low := false
	var tree := Engine.get_main_loop() as SceneTree
	var q: Node = tree.root.get_node_or_null("/root/Quality") if tree else null
	if q != null and q.get("tier") is int:
		low = int(q.get("tier")) <= 1
	if low and not m.get("no_lod", false) and ResourceLoader.exists(base + "_lod1" + ext):
		return base + "_lod1" + ext
	return base + ext if ResourceLoader.exists(base + ext) else ""


static func info(kind: String) -> Dictionary:
	return MODELS.get(kind, {})


static func clips(kind: String) -> Dictionary:
	var out := DEFAULT_CLIPS.duplicate()
	out.merge(info(kind).get("clips", {}), true)
	if info(kind).get("kneel", false):
		out["kneel"] = LIBRARY + "/kneel"
		out["stand_up"] = LIBRARY + "/stand_up"
	return out


## Instantiates and scales the model, loops its locomotion clips and, for
## kneeling kinds, adds the kneel / stand_up clips. Returns null if missing.
static func instance(kind: String) -> Node3D:
	var path := path_for(kind)
	if path == "":
		return null
	var m: Dictionary = MODELS[kind]
	var model: Node3D = Assets.scene(path).instantiate()
	if m.has("fit_height"):
		var box := Assets.visual_aabb(model)
		model.scale = Vector3.ONE * (float(m["fit_height"]) / maxf(box.size.y, 0.01))
	else:
		model.scale = Vector3.ONE * float(m.get("scale", 1.0))
	var ap := Assets.animation_player(model)
	if ap:
		var c := clips(kind)
		for role in ["idle", "walk", "run"]:
			if ap.has_animation(c[role]):
				ap.get_animation(c[role]).loop_mode = Animation.LOOP_LINEAR
		if m.get("kneel", false):
			_add_kneel(kind, model, ap)
	return model


static func _add_kneel(kind: String, model: Node3D, ap: AnimationPlayer) -> void:
	if ap.has_animation_library(LIBRARY):
		return
	if _kneel_cache.has(kind):
		ap.add_animation_library(LIBRARY, _kneel_cache[kind])
		return
	var dst_skel := _skeleton(model)
	var src_path := path_for(KNEEL_SOURCE)
	if dst_skel == null or src_path == "":
		return
	var src_model: Node3D = Assets.scene(src_path).instantiate()
	var src_ap := Assets.animation_player(src_model)
	var src_skel := _skeleton(src_model)
	if src_ap == null or src_skel == null or not src_ap.has_animation(KNEEL_CLIP):
		src_model.free()
		return
	var src := src_ap.get_animation(KNEEL_CLIP)
	var dst_root := ap.get_node_or_null(ap.root_node)
	if dst_root == null:
		src_model.free()
		return
	var skel_path := String(dst_root.get_path_to(dst_skel))
	var hips_src := src_skel.find_bone("Hips")
	var hips_dst := dst_skel.find_bone("Hips")
	var ratio := 1.0
	if hips_src >= 0 and hips_dst >= 0:
		ratio = dst_skel.get_bone_rest(hips_dst).origin.y / maxf(src_skel.get_bone_rest(hips_src).origin.y, 0.001)
	var lib := AnimationLibrary.new()
	lib.add_animation("kneel", _slice(src, src_skel, skel_path, dst_skel, KNEEL_RANGE, ratio))
	lib.add_animation("stand_up", _slice(src, src_skel, skel_path, dst_skel, STAND_RANGE, ratio))
	src_model.free()
	_kneel_cache[kind] = lib
	ap.add_animation_library(LIBRARY, lib)


## Resamples [range.x, range.y] of `src` at 30 fps onto `skel_path`: bone
## rotations copied, positions offset from the rest pose scaled by the hip-height
## ratio, scale dropped.
static func _slice(src: Animation, src_skel: Skeleton3D, skel_path: String, skel: Skeleton3D, time_range: Vector2, ratio: float) -> Animation:
	var out := Animation.new()
	out.length = time_range.y - time_range.x
	var frames := int(ceil(out.length * 30.0))
	for t in src.get_track_count():
		var kind := src.track_get_type(t)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var bone := String(src.track_get_path(t)).get_slice(":", 1)
		var bi := skel.find_bone(bone)
		var si := src_skel.find_bone(bone)
		if bi < 0 or si < 0:
			continue
		var rest_dst := skel.get_bone_rest(bi).origin
		var rest_src := src_skel.get_bone_rest(si).origin
		var nt := out.add_track(kind)
		out.track_set_path(nt, NodePath(skel_path + ":" + bone))
		for f in frames + 1:
			var at := minf(float(f) / 30.0, out.length)
			var st := time_range.x + at
			if kind == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(nt, at, src.rotation_track_interpolate(t, st))
			else:
				out.position_track_insert_key(nt, at, rest_dst + (src.position_track_interpolate(t, st) - rest_src) * ratio)
	return out


static func _skeleton(model: Node) -> Skeleton3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null
