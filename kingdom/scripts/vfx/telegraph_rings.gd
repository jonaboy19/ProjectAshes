extends Node3D
## Pooled ground telegraph rings under enemy heavy attacks and charged casts. A fixed rim marks the strike
## radius and an inner ring swells to meet it exactly when the blow lands, so the player reads "now" from the
## ground. MAX_ACTIVE slots, two unlit additive quads each, no lights; the rings follow their actor while
## active and the node only processes while one is. Preload, no class_name:
##   const Rings := preload("res://scripts/vfx/telegraph_rings.gd")
##   Rings.at(world).begin(actor, radius, windup_seconds, "physical")  /  .end(actor)

const K := preload("res://scripts/vfx/vfx_kit.gd")

const NODE_NAME := "TelegraphRings"
const MAX_ACTIVE := 4
const HOSTILE := {"tint": Color(1.0, 0.24, 0.1), "hot": Color(1.0, 0.7, 0.45), "edge": Color(0.45, 0.04, 0.02)}

var _slots: Array[Dictionary] = []
var _serial := 0


static func at(world: Node) -> Node3D:
	var found := world.get_node_or_null(NODE_NAME)
	if found:
		return found
	var pool: Node3D = (load("res://scripts/vfx/telegraph_rings.gd") as GDScript).new()
	pool.name = NODE_NAME
	world.add_child(pool)
	return pool


func _ready() -> void:
	top_level = true
	set_process(false)
	for i in MAX_ACTIVE:
		_slots.append(_build_slot())


func slot_count() -> int:
	return _slots.size()


func active_count() -> int:
	var n := 0
	for s: Dictionary in _slots:
		if _live(s):
			n += 1
	return n


func node_count() -> int:
	return find_children("*", "", true, false).size()


func _build_slot() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var s := {"root": root, "actor": null, "serial": 0, "tween": null}
	for key: String in ["rim", "fill"]:
		var m := K.fx_mat(K.GROUND_RING, HOSTILE, 2.2, {"progress": 0.92, "fade": 1.0, "width": 0.3, "noise_amt": 0.05})
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		mi.mesh = plane
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)
		s[key] = mi
		s[key + "_mat"] = m
	return s


## Starts a ring under `actor`; a second call for the same actor restarts it. Returns false when the cap is
## full (the nameplate cue still shows). `element` "" or "physical" is the hostile red; others use their palette.
func begin(actor: Node3D, radius: float, seconds: float, element := "", heavy := true) -> bool:
	var slot := _slot_for(actor)
	if slot.is_empty():
		return false
	_serial += 1
	slot["serial"] = _serial
	slot["actor"] = actor
	var pal: Dictionary = HOSTILE if element == "" or element == "physical" else K.pal(element)
	var root: Node3D = slot["root"]
	root.visible = true
	_follow(slot)
	var scale := 2.0 * maxf(radius, 0.5) / 0.95
	for key: String in ["rim", "fill"]:
		var mi: MeshInstance3D = slot[key]
		mi.scale = Vector3.ONE * scale
		var m: ShaderMaterial = slot[key + "_mat"]
		m.set_shader_parameter("tint", pal["tint"])
		m.set_shader_parameter("hot", pal["hot"])
		m.set_shader_parameter("edge", pal["edge"])
	var rim_m: ShaderMaterial = slot["rim_mat"]
	rim_m.set_shader_parameter("progress", 0.92)
	rim_m.set_shader_parameter("fade", 0.0)
	rim_m.set_shader_parameter("energy", 2.4 if heavy else 1.6)
	var fill_m: ShaderMaterial = slot["fill_mat"]
	fill_m.set_shader_parameter("progress", 0.2)
	fill_m.set_shader_parameter("fade", 0.0)
	fill_m.set_shader_parameter("energy", 3.2 if heavy else 2.2)
	var old: Tween = slot["tween"]
	if old and old.is_valid():
		old.kill()
	var t := create_tween().set_parallel(true)
	slot["tween"] = t
	var dur := maxf(seconds, 0.15)
	t.tween_property(rim_m, "shader_parameter/fade", 0.8, minf(0.12, dur * 0.4))
	t.tween_property(fill_m, "shader_parameter/fade", 1.0, minf(0.12, dur * 0.4))
	t.tween_property(fill_m, "shader_parameter/progress", 0.92, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	var serial := _serial
	t.chain().tween_callback(func() -> void:
		if int(slot["serial"]) == serial and slot["actor"] == actor:
			end(actor))              # the blow lands: the ring is done
	set_process(true)
	return true


## Windup finished or cancelled: the ring fades and frees its slot.
func end(actor: Node3D) -> void:
	for s: Dictionary in _slots:
		if s["actor"] == actor and actor != null:
			var serial := int(s["serial"])
			var old: Tween = s["tween"]
			if old and old.is_valid():
				old.kill()
			var t := create_tween().set_parallel(true)
			s["tween"] = t
			t.tween_property(s["rim_mat"], "shader_parameter/fade", 0.0, 0.12)
			t.tween_property(s["fill_mat"], "shader_parameter/fade", 0.0, 0.12)
			t.chain().tween_callback(_free_slot.bind(s, serial))
			s["actor"] = null
			s["ending"] = true
			return


func _free_slot(slot: Dictionary, serial: int) -> void:
	if int(slot["serial"]) == serial and slot["actor"] == null:
		(slot["root"] as Node3D).visible = false


func _slot_for(actor: Node3D) -> Dictionary:
	for s: Dictionary in _slots:
		if s["actor"] == actor and actor != null:
			return s
	for s: Dictionary in _slots:
		if not _live(s):
			return s
	return {}


func _live(slot: Dictionary) -> bool:
	return slot["actor"] != null and is_instance_valid(slot["actor"])


func _follow(slot: Dictionary) -> void:
	var a: Variant = slot["actor"]
	if a is Node3D and is_instance_valid(a):
		(slot["root"] as Node3D).global_position = (a as Node3D).global_position + Vector3(0, 0.07, 0)


func _process(_delta: float) -> void:
	var any := false
	for s: Dictionary in _slots:
		var a: Variant = s["actor"]
		if a == null:
			continue
		if not is_instance_valid(a) or not (a as Node3D).is_inside_tree() or (a as Node3D).get("dead") == true:
			s["actor"] = null           # the actor died or left: drop the ring
			(s["root"] as Node3D).visible = false
			continue
		_follow(s)
		any = true
	if not any:
		set_process(false)
