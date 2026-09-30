class_name LifeProps
extends RefCounted
## Hand props for life clips (hoe, hammer, mug, lute ...), attached with the GRIP CONTRACT shared with the
## Blender authoring tools (tools/anim/life/life_common.py):
##
##   hand frame on the REST skeleton:
##     f = normalize(middle_01 - hand)                              fingers / knuckle direction
##     t = normalize(index_01 - pinky_01) made orthogonal to f       thumb side = grip axis
##     n = right: t x f, left: f x t                                palm normal
##   fist centre g = hand + f * 0.68 k + n * 0.30 k   (k = |middle_01 - hand|)
##   The prop's native grip_axis follows t, its front_axis follows f (data/living_world/life_props.json,
##   axes given in Blender coordinates and converted here: (x, y, z) -> (x, z, -y)).
##
##   var h := LifeProps.Holder.new(skeleton)        # one per character
##   h.show_for_clip("Life_Smith_Hammer")           # attaches/hides props listed in the clip's sidecar
##   h.clear()
## Prop scenes are cached; a character keeps its attachments and only toggles visibility when clips change,
## so switching activities never instantiates during play after the first use.

const CATALOGUE := "res://data/living_world/life_props.json"

static var _cat: Dictionary = {}
static var _scenes: Dictionary = {}


static func catalogue() -> Dictionary:
	if _cat.is_empty() and FileAccess.file_exists(CATALOGUE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
		if typeof(d) == TYPE_DICTIONARY:
			_cat = d
	return _cat


static func entry(id: String) -> Dictionary:
	return (catalogue().get("hand", {}) as Dictionary).get(id, {})


static func _blender_to_godot(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[2]), -float(v[1]))


## Local transform (in the hand bone's global-rest frame) that seats a prop in the fist.
static func grip_transform(skeleton: Skeleton3D, side: String, grip_axis: Vector3, front_axis: Vector3) -> Transform3D:
	var hb := skeleton.find_bone("hand_" + side)
	var mb := skeleton.find_bone("middle_01_" + side)
	var ib := skeleton.find_bone("index_01_" + side)
	var pb := skeleton.find_bone("pinky_01_" + side)
	if hb < 0 or mb < 0 or ib < 0 or pb < 0:
		return Transform3D.IDENTITY
	var hand := skeleton.get_bone_global_rest(hb)
	var h := hand.origin
	var k := (skeleton.get_bone_global_rest(mb).origin - h).length()
	var f := (skeleton.get_bone_global_rest(mb).origin - h).normalized()
	var t := skeleton.get_bone_global_rest(ib).origin - skeleton.get_bone_global_rest(pb).origin
	t = (t - f * t.dot(f)).normalized()
	var n := t.cross(f) if side == "r" else f.cross(t)
	var g := h + f * (k * 0.68) + n * (k * 0.30)
	# native frame (grip, front, grip x front) -> skeleton frame (t, f, t x f)
	var ga := grip_axis.normalized()
	var fa := (front_axis - ga * front_axis.dot(ga)).normalized()
	var src := Basis(ga, fa, ga.cross(fa))
	var dst := Basis(t, f, t.cross(f))
	var world := Transform3D(dst * src.inverse(), g)
	var hand_o := Transform3D(hand.basis.orthonormalized(), h)
	return hand_o.affine_inverse() * world


static func instantiate(id: String) -> Node3D:
	var e := entry(id)
	if e.is_empty():
		return null
	var path := String(e["file"])
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _scenes[path]
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	for mi in n.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## Attach prop `id` to the hand (`side` "r"/"l"; empty = the catalogue default). Returns the BoneAttachment3D.
static func attach(skeleton: Skeleton3D, id: String, side := "") -> BoneAttachment3D:
	var e := entry(id)
	if e.is_empty():
		return null
	if side == "":
		side = String(e.get("hand", "r"))
	var prop := instantiate(id)
	if prop == null:
		return null
	var att := BoneAttachment3D.new()
	att.name = "Prop_%s_%s" % [id, side]
	att.bone_name = "hand_" + side
	skeleton.add_child(att)
	prop.transform = grip_transform(skeleton, side, _blender_to_godot(e["grip_axis"]), _blender_to_godot(e["front_axis"]))
	# Props are modelled in metres: undo the scale inside the imported character scene (skeleton up to its owner),
	# keep the character's own height scale (a child's hoe is a little smaller).
	var internal := _internal_scale(skeleton)
	if absf(internal - 1.0) > 0.001:
		prop.scale = Vector3.ONE / internal
	att.add_child(prop)
	return att


## Product of the scales from the skeleton up to the root of its imported scene (skeleton.owner).
static func _internal_scale(skeleton: Skeleton3D) -> float:
	var sc := 1.0
	var n: Node = skeleton
	while n != null:
		if n is Node3D:
			sc *= (n as Node3D).scale.x
		if n == skeleton.owner or n.get_parent() == null:
			break
		n = n.get_parent()
	return maxf(sc, 0.0001)


## One character's props: shows the props a clip needs, hides the rest (attachments are reused).
class Holder:
	var skeleton: Skeleton3D
	var _att: Dictionary = {}     # "id|side" -> BoneAttachment3D
	var _shown: Array = []

	func _init(sk: Skeleton3D) -> void:
		skeleton = sk

	func show_for_clip(clip: String) -> void:
		var want: Array = LifeLibrary.info(clip).get("props", [])
		show_props(want)

	func show_props(want: Array) -> void:
		var keys := []
		for p: Dictionary in want:
			var id := String(p.get("id", ""))
			var side := String(p.get("hand", LifeProps.entry(id).get("hand", "r")))
			var k := id + "|" + side
			keys.append(k)
			if not _att.has(k):
				_att[k] = LifeProps.attach(skeleton, id, side)
			if _att[k]:
				(_att[k] as Node3D).visible = true
		for k: String in _att:
			if not keys.has(k) and _att[k]:
				(_att[k] as Node3D).visible = false
		_shown = keys

	func clear() -> void:
		show_props([])

	func shown() -> Array:
		return _shown
