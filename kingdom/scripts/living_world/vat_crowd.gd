class_name VatCrowd
extends Node3D
## Hundreds of animated background villagers for almost nothing: MultiMeshes per baked look
## (VatAsset, res://assets/generated/vat/), animated entirely in the vertex shader
## (shaders/living_world/vat_crowd.gdshader). No nodes, skeletons or AnimationPlayers per person.
##
##   var crowd := VatCrowd.new(); add_child(crowd); crowd.load_looks(["villager_man_a", ...])
##   crowd.camera = cam                                         # optional: enables the far mesh LOD
##   crowd.put(id, "villager_man_a", xform, "Life_Farm_Hoe")   # add or update (phase random per id)
##   crowd.move(id, xform)                                      # transform only (cheap)
##   crowd.play(id, "Walk", phase_s, speed)                     # change clip; phase_s = clip time now
##   crowd.remove(id)
##   crowd.clip_time(id) -> the clip time the shader is showing now (for a VAT -> skeleton hand-off)
##
## Two mesh LODs per look share one set of textures: the near mesh (~1300 tris) and, beyond `far_split` metres
## from the camera, the coarser meshoptimizer LOD re-indexed onto the same vertex columns (~650 tris). People
## migrate between the two MultiMeshes on a sliced distance check (1/8 of them per frame).
## Time: the shader reads the global uniform `vat_time`, advanced here, so a hand-off can compute the exact pose:
## clip time = vat_time * speed + phase.
## Cost: GDScript only runs when something changes (put/move/play/remove, O(1) each, swap-remove) plus the LOD
## slice; the GPU does the animation. Shadows are off (the VAT tier is 25-40 m+ away).

const SHADER := preload("res://shaders/living_world/vat_crowd.gdshader")
const VAT_DIR := "res://assets/generated/vat/"
const GROW := 64
const LOD_SLICES := 8

var assets: Dictionary = {}          # look -> VatAsset
var cast_shadows := false
var camera: Camera3D
var far_split := 60.0
var _mm: Dictionary = {}             # bucket "look|lod" -> MultiMesh
var _mmi: Dictionary = {}            # bucket -> MultiMeshInstance3D
var _ids: Dictionary = {}            # bucket -> Array[int] (dense, instance order)
var _where: Dictionary = {}          # id -> [bucket, index, look]
var _data: Dictionary = {}           # id -> [clip, phase, speed, tint]
var _time := 0.0
var _slice := 0

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
	if a == null or assets.has(a.look):
		return
	assets[a.look] = a
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("vat_pos", a.pos_tex)
	mat.set_shader_parameter("vat_nrm", a.nrm_tex)
	mat.set_shader_parameter("vat_fps", a.fps)
	for lod in 2:
		var mesh: ArrayMesh = a.mesh if lod == 0 else a.mesh_far
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = GROW
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Vat_%s_%d" % [a.look, lod]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mmi.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1500, 10000))
		add_child(mmi)
		var b := _bucket(a.look, lod)
		_mm[b] = mm
		_mmi[b] = mmi
		_ids[b] = []


static func _bucket(look: String, lod: int) -> String:
	return "%s|%d" % [look, lod]


func _process(delta: float) -> void:
	_time += delta
	if _time > 3000.0:
		_rebase(3000.0)
	RenderingServer.global_shader_parameter_set(&"vat_time", _time)
	if camera and is_instance_valid(camera) and not _where.is_empty():
		_lod_slice()


## 1/LOD_SLICES of the people per frame: move them between the near and far mesh with a 10 % hysteresis.
func _lod_slice() -> void:
	_slice = (_slice + 1) % LOD_SLICES
	var cam := camera.global_position
	var near2 := (far_split * 0.9) * (far_split * 0.9)
	var far2 := (far_split * 1.1) * (far_split * 1.1)
	var k := 0
	for id: int in _where.keys():
		k += 1
		if k % LOD_SLICES != _slice:
			continue
		var w: Array = _where[id]
		var look: String = w[2]
		if not _mm.has(_bucket(look, 1)):
			continue
		var xf := (_mm[w[0]] as MultiMesh).get_instance_transform(w[1])
		var d2 := xf.origin.distance_squared_to(cam)
		var lod := 1 if w[0] == _bucket(look, 1) else 0
		var want := lod
		if lod == 0 and d2 > far2:
			want = 1
		elif lod == 1 and d2 < near2:
			want = 0
		if want != lod:
			_detach(id)
			_attach(id, look, want)
			move(id, xf)
			_write_custom(id)


func _lod_for(look: String, xform: Transform3D) -> int:
	if camera == null or not is_instance_valid(camera) or not _mm.has(_bucket(look, 1)):
		return 0
	return 1 if xform.origin.distance_to(camera.global_position) > far_split else 0


## Keeps float precision: shift the clock back and every phase forward by the same amount.
func _rebase(by: float) -> void:
	_time -= by
	for id: int in _data:
		var d: Array = _data[id]
		d[1] = float(d[1]) + by * float(d[2])
		_write_custom(id)


## QA: tint every VAT instance (LOD visualisation); alpha = strength, 0 = off.
func set_debug_tint(c: Color) -> void:
	for b: String in _mmi:
		((_mmi[b] as MultiMeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("debug_tint", c)


func count(look := "") -> int:
	if look != "":
		var n := 0
		for lod in 2:
			n += (_ids.get(_bucket(look, lod), []) as Array).size()
		return n
	return _where.size()


## Instances drawn with the far mesh (QA).
func count_far() -> int:
	var n := 0
	for b: String in _ids:
		if b.ends_with("|1"):
			n += (_ids[b] as Array).size()
	return n


func has(id: int) -> bool:
	return _where.has(id)


## Add or update person `id`. phase_s < 0 = a stable pseudo-random phase for this id (no lockstep).
func put(id: int, look: String, xform: Transform3D, clip: String, phase_s := -1.0, speed := 1.0, tint := Color(0.5, 0.5, 0.5)) -> void:
	if not assets.has(look):
		return
	if _where.has(id) and _where[id][2] != look:
		remove(id)
	if not _where.has(id):
		_attach(id, look, _lod_for(look, xform))
	var a: VatAsset = assets[look]
	if phase_s < 0.0:
		phase_s = fmod(float(id) * 0.618034, 1.0) * a.clip_length(clip)
	# phase is stored as "clip time at vat_time 0"
	_data[id] = [clip, phase_s - _time * speed, speed, tint]
	move(id, xform)
	_write_custom(id)


func _attach(id: int, look: String, lod: int) -> void:
	var b := _bucket(look, lod)
	var ids: Array = _ids[b]
	var mm: MultiMesh = _mm[b]
	if ids.size() >= mm.instance_count:
		_grow(b, mm.instance_count + GROW)
	_where[id] = [b, ids.size(), look]
	ids.append(id)
	mm.visible_instance_count = ids.size()


## Swap-remove the instance slot (keeps _data).
func _detach(id: int) -> void:
	var w: Array = _where.get(id, [])
	if w.is_empty():
		return
	var b: String = w[0]
	var i: int = w[1]
	var ids: Array = _ids[b]
	var mm: MultiMesh = _mm[b]
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
	var look: String = _where[id][2]
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
	var a: VatAsset = assets[_where[id][2]]
	var t := _time * float(d[2]) + float(d[1])
	var c: Dictionary = a.clips.get(d[0], {})
	var length := float(c.get("length", 1.0))
	return fposmod(t, length) if c.get("loop", true) else clampf(t, 0.0, length)


func clip_of(id: int) -> String:
	return String(_data[id][0]) if _data.has(id) else ""


func remove(id: int) -> void:
	_detach(id)
	_data.erase(id)


func clear() -> void:
	for id: int in _where.keys():
		remove(id)


func _write_custom(id: int) -> void:
	var w: Array = _where[id]
	var d: Array = _data[id]
	var a: VatAsset = assets[w[2]]
	var c: Dictionary = a.clips.get(d[0], a.clips.get("Idle", a.clips.values()[0] if not a.clips.is_empty() else {}))
	var packed := float(int(c.get("row", 0)) * 1024 + int(c.get("frames", 1)))
	if not c.get("loop", true):
		packed = -packed
	var tint: Color = d[3]
	var tp := float(clampi(int(tint.r * 255.0), 0, 255) * 65536 + clampi(int(tint.g * 255.0), 0, 255) * 256 + clampi(int(tint.b * 255.0), 0, 255))
	(_mm[w[0]] as MultiMesh).set_instance_custom_data(w[1], Color(packed, float(d[1]), float(d[2]), tp))


func _grow(b: String, n: int) -> void:
	var mm: MultiMesh = _mm[b]
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
