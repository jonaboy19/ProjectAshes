extends Node
## Occluder fade for the chase camera (AAA camera pass 2026-10-06, skill ashes-aaa-camera-hud).
## Physics only knows colliders, so the thatch roofs, awnings, banners and pots that have no collision (or only a
## camera-blocker proxy) used to fill the screen. This asks the RENDERER instead: RenderingServer.instances_cull_ray between
## the lens and the hero's shoulder, plus a small box around the lens, at 12 Hz. Every visual instance found there (minus the
## hero, characters, labels, terrain and anything huge) eases to `FADE` transparency and back when it leaves.
## Cost: two BVH queries at 12 Hz and a handful of property writes; no shader changes, works on Mobile and Compatibility.

const HZ := 1.0 / 12.0
const FADE := 0.72            # GeometryInstance3D.transparency while in the way
const SPEED := 6.0            # 1/s ease in and out
const NEAR_BOX := 0.7         # half size (m) of the box around the lens: things the lens is inside of
const MAX_SIZE := 28.0        # an AABB longer than this is terrain / a town batch: never fade it

var ignore_root: Node
var _acc := 0.0
var _faded := {}              # instance id -> {node, orig, k, hit}
var enabled := true


func step(delta: float, cam: Vector3, pivot: Vector3, active: bool) -> void:
	_acc += delta
	if _acc >= HZ:
		_acc = 0.0
		_scan(cam, pivot, active and enabled)
	for id: int in _faded.keys():
		var e: Dictionary = _faded[id]
		var gi := e["node"] as GeometryInstance3D
		if not is_instance_valid(gi):
			_faded.erase(id)
			continue
		var want := 1.0 if bool(e["hit"]) else 0.0
		e["k"] = move_toward(float(e["k"]), want, SPEED * delta)
		gi.transparency = lerpf(float(e["orig"]), maxf(float(e["orig"]), FADE), float(e["k"]))
		if float(e["k"]) <= 0.0 and not bool(e["hit"]):
			gi.transparency = float(e["orig"])
			_faded.erase(id)


func _scan(cam: Vector3, pivot: Vector3, active: bool) -> void:
	for id: int in _faded:
		_faded[id]["hit"] = false
	if not active:
		return
	var vp := get_viewport()
	if vp == null or vp.find_world_3d() == null:
		return
	var scen := vp.find_world_3d().scenario
	# stop a little short of the shoulder so the hero's own surroundings (the ground he stands on) are not tested
	var to := pivot.lerp(cam, 0.12)
	var ids := RenderingServer.instances_cull_ray(cam, to, scen)
	ids.append_array(RenderingServer.instances_cull_aabb(AABB(cam - Vector3.ONE * NEAR_BOX, Vector3.ONE * NEAR_BOX * 2.0), scen))
	for oid in ids:
		var gi := instance_from_id(oid) as GeometryInstance3D
		if gi == null or not _fadeable(gi, pivot):
			continue
		var key := gi.get_instance_id()
		if not _faded.has(key):
			_faded[key] = {"node": gi, "orig": gi.transparency, "k": 0.0, "hit": true}
		else:
			_faded[key]["hit"] = true


func _fadeable(gi: GeometryInstance3D, pivot: Vector3) -> bool:
	if not gi.visible or gi is MultiMeshInstance3D or gi is Label3D or gi is SpriteBase3D or gi is GPUParticles3D or gi is CPUParticles3D:
		return false
	if gi.has_meta("no_camera_fade"):
		return false
	var box := gi.global_transform * gi.get_aabb()
	if box.get_longest_axis_size() > MAX_SIZE or box.has_point(pivot):
		return false
	# skip the hero; villagers, horses and monsters between the lens and the hero DO fade (an NPC head filled the lens)
	var n: Node = gi
	for i in 8:
		n = n.get_parent()
		if n == null:
			break
		if n == ignore_root:
			return false
	return true


func _exit_tree() -> void:
	for id: int in _faded:
		var gi := _faded[id]["node"] as GeometryInstance3D
		if is_instance_valid(gi):
			gi.transparency = float(_faded[id]["orig"])
	_faded.clear()
