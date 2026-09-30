class_name VatCrowd
extends Node3D
## Hundreds of animated background villagers for almost nothing: one MultiMesh per baked look
## (VatAsset, res://assets/generated/vat/), animated entirely in the vertex shader
## (shaders/living_world/vat_crowd.gdshader). No nodes, skeletons or AnimationPlayers per person.
##
##   var crowd := VatCrowd.new(); add_child(crowd); crowd.load_looks(["villager_man_a", ...])
##   crowd.put(id, "villager_man_a", xform, "Life_Farm_Hoe")   # add or update (phase random per id)
##   crowd.move(id, xform)                                      # transform only (cheap)
##   crowd.play(id, "Walk", phase_s, speed)                     # change clip; phase_s = clip time now
##   crowd.remove(id)
##   crowd.clip_time(id) -> the clip time the shader is showing now (for a VAT -> skeleton hand-off)
##
## Time: the shader reads the global uniform `vat_time`, advanced here (scaled by Engine.time_scale), so a
## hand-off can compute the exact pose: clip time = vat_time * speed + phase.
## Cost: GDScript only runs when something changes (put/move/play/remove, O(1) each, swap-remove); the GPU
## does the animation. Shadows are off (the far tier is 40+ m away).

const SHADER := preload("res://shaders/living_world/vat_crowd.gdshader")
const VAT_DIR := "res://assets/generated/vat/"
const GROW := 64

var assets: Dictionary = {}          # look -> VatAsset
var cast_shadows := false
var _mm: Dictionary = {}             # look -> MultiMesh
var _mmi: Dictionary = {}            # look -> MultiMeshInstance3D
var _ids: Dictionary = {}            # look -> Array[int] (dense, instance order)
var _where: Dictionary = {}          # id -> [look, index]
var _data: Dictionary = {}           # id -> [clip, phase, speed, tint]
var _time := 0.0

static var _global_ok := false


static func ensure_global() -> void:
	if _global_ok:
		return
	_global_ok = true
	if not RenderingServer.global_shader_parameter_get_list().has(&"vat_time"):
		RenderingServer.global_shader_parameter_add(&"vat_time", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


func _init() -> void:
	ensure_global()


func load_looks(looks: Array) -> void:
	for look: String in looks:
		var p := VAT_DIR + "vat_%s.res" % look
		if ResourceLoader.exists(p):
			add_asset(load(p) as VatAsset)
		else:
			push_warning("VatCrowd: no bake for " + look)


func add_asset(a: VatAsset) -> void:
	if a == null or _mm.has(a.look):
		return
	assets[a.look] = a
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("vat_pos", a.pos_tex)
	mat.set_shader_parameter("vat_nrm", a.nrm_tex)
	mat.set_shader_parameter("vat_fps", a.fps)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = a.mesh
	mm.instance_count = GROW
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Vat_" + a.look
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1500, 10000))
	add_child(mmi)
	_mm[a.look] = mm
	_mmi[a.look] = mmi
	_ids[a.look] = []


func _process(delta: float) -> void:
	_time += delta
	if _time > 3000.0:
		_rebase(3000.0)
	RenderingServer.global_shader_parameter_set(&"vat_time", _time)


## Keeps float precision: shift the clock back and every phase forward by the same amount.
func _rebase(by: float) -> void:
	_time -= by
	for id: int in _data:
		var d: Array = _data[id]
		d[1] = float(d[1]) + by * float(d[2])
		_write_custom(id)


## QA: tint every VAT instance (LOD visualisation); alpha = strength, 0 = off.
func set_debug_tint(c: Color) -> void:
	for look: String in _mmi:
		((_mmi[look] as MultiMeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("debug_tint", c)


func count(look := "") -> int:
	if look != "":
		return (_ids.get(look, []) as Array).size()
	return _where.size()


func has(id: int) -> bool:
	return _where.has(id)


## Add or update person `id`. phase_s < 0 = a stable pseudo-random phase for this id (no lockstep).
func put(id: int, look: String, xform: Transform3D, clip: String, phase_s := -1.0, speed := 1.0, tint := Color(0.5, 0.5, 0.5)) -> void:
	if not _mm.has(look):
		return
	if _where.has(id) and _where[id][0] != look:
		remove(id)
	if not _where.has(id):
		var ids: Array = _ids[look]
		var mm: MultiMesh = _mm[look]
		if ids.size() >= mm.instance_count:
			_grow(look, mm.instance_count + GROW)
		_where[id] = [look, ids.size()]
		ids.append(id)
		mm.visible_instance_count = ids.size()
	var a: VatAsset = assets[look]
	if phase_s < 0.0:
		phase_s = fmod(float(id) * 0.618034, 1.0) * a.clip_length(clip)
	# phase is stored as "clip time at vat_time 0"
	_data[id] = [clip, phase_s - _time * speed, speed, tint]
	move(id, xform)
	_write_custom(id)


func move(id: int, xform: Transform3D) -> void:
	var w: Array = _where.get(id, [])
	if w.is_empty():
		return
	(_mm[w[0]] as MultiMesh).set_instance_transform(w[1], xform)


## Switch clip. phase_s = the clip time to show right now (e.g. the skeletal AnimationPlayer's position).
func play(id: int, clip: String, phase_s := -1.0, speed := 1.0) -> void:
	if not _data.has(id):
		return
	var d: Array = _data[id]
	if d[0] == clip and is_equal_approx(float(d[2]), speed) and phase_s < 0.0:
		return
	var look: String = _where[id][0]
	if phase_s < 0.0:
		phase_s = fmod(float(id) * 0.618034, 1.0) * (assets[look] as VatAsset).clip_length(clip)
	d[0] = clip
	d[1] = phase_s - _time * speed
	d[2] = speed
	_write_custom(id)


## Clip time the shader shows now for `id` (wrapped for loops).
func clip_time(id: int) -> float:
	if not _data.has(id):
		return 0.0
	var d: Array = _data[id]
	var a: VatAsset = assets[_where[id][0]]
	var t := _time * float(d[2]) + float(d[1])
	var c: Dictionary = a.clips.get(d[0], {})
	var length := float(c.get("length", 1.0))
	return fposmod(t, length) if c.get("loop", true) else clampf(t, 0.0, length)


func clip_of(id: int) -> String:
	return String(_data[id][0]) if _data.has(id) else ""


func remove(id: int) -> void:
	var w: Array = _where.get(id, [])
	if w.is_empty():
		return
	var look: String = w[0]
	var i: int = w[1]
	var ids: Array = _ids[look]
	var mm: MultiMesh = _mm[look]
	var last: int = ids.size() - 1
	if i != last:
		var moved: int = ids[last]
		ids[i] = moved
		_where[moved][1] = i
		mm.set_instance_transform(i, mm.get_instance_transform(last))
		mm.set_instance_custom_data(i, mm.get_instance_custom_data(last))
	ids.pop_back()
	mm.visible_instance_count = ids.size()
	_where.erase(id)
	_data.erase(id)


func clear() -> void:
	for id: int in _where.keys():
		remove(id)


func _write_custom(id: int) -> void:
	var w: Array = _where[id]
	var d: Array = _data[id]
	var a: VatAsset = assets[w[0]]
	var c: Dictionary = a.clips.get(d[0], a.clips.get("Idle", a.clips.values()[0] if not a.clips.is_empty() else {}))
	var packed := float(int(c.get("row", 0)) * 1024 + int(c.get("frames", 1)))
	if not c.get("loop", true):
		packed = -packed
	var tint: Color = d[3]
	var tp := float(clampi(int(tint.r * 255.0), 0, 255) * 65536 + clampi(int(tint.g * 255.0), 0, 255) * 256 + clampi(int(tint.b * 255.0), 0, 255))
	(_mm[w[0]] as MultiMesh).set_instance_custom_data(w[1], Color(packed, float(d[1]), float(d[2]), tp))


func _grow(look: String, n: int) -> void:
	var mm: MultiMesh = _mm[look]
	var old := mm.instance_count
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for i in old:
		xf.append(mm.get_instance_transform(i))
		cd.append(mm.get_instance_custom_data(i))
	var vis := mm.visible_instance_count
	mm.instance_count = n
	for i in old:
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])
	mm.visible_instance_count = vis
