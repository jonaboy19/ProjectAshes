class_name ElementEffect
extends Node3D
## Root script of every scene in scenes/vfx/elements/. Owns the timeline of one pooled
## elemental effect: drives shader parameters / scale / position of its mesh children from
## `anims` metadata, starts delayed particle emitters, flashes the (HIGH+ only) light, applies
## the Quality tier and converts GPUParticles3D to CPUParticles3D on the Compatibility renderer.
## Spawn through ElementFX, not directly.
##
## Child metadata (set by tools_qa/vfx_gallery/build_element_scenes.gd):
##   anims       Array of {p, a, b, t0, t1, e}   p = shader param | "scale" | "y" | "rot_y" | "pos_z"
##   emit_delay  float   particle emitters start this many seconds after play
##   tier_min    int     hidden below this Quality tier (0 low, 1 medium, 2 high)
##   flash       {e, t}  OmniLight3D peak energy and decay time (light also needs tier_min = 2)
## Root exports: duration (0 = loops until stop()), fade_out.

signal finished(effect: ElementEffect)

@export var duration := 1.0
@export var fade_out := 0.25
@export var kind: StringName = &""
@export var element: StringName = &""

var _t := 0.0
var _active := false
var _stopping := false
var _stop_t := 0.0
var _prepared := false
var _anims: Array = []
var _emitters: Array = []      # [node, delay, started]
var _mats: Array[ShaderMaterial] = []
var _lights: Array = []        # [OmniLight3D, energy, decay]
var _max_life := 0.0
var _tier := 2
var pooled_key := ""


func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	for n in find_children("*", "GPUParticles3D", true, false):
		if compat:
			_to_cpu(n as GPUParticles3D)
	_collect(self)
	set_process(false)


func _to_cpu(g: GPUParticles3D) -> void:
	var c := CPUParticles3D.new()
	c.convert_from_particles(g)
	c.name = g.name
	c.transform = g.transform
	c.amount = mini(c.amount, 24)
	for k in g.get_meta_list():
		c.set_meta(k, g.get_meta(k))
	var parent := g.get_parent()
	var idx := g.get_index()
	parent.add_child(c)
	parent.move_child(c, idx)
	g.free()


func _collect(n: Node) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			if mi.material_override is ShaderMaterial:
				# Instances of one PackedScene share sub-resources: own copy so parameters animate per instance.
				var m := (mi.material_override as ShaderMaterial).duplicate() as ShaderMaterial
				mi.material_override = m
				_mats.append(m)
			if mi.has_meta("anims"):
				for a: Dictionary in mi.get_meta("anims"):
					_anims.append({"n": mi, "m": mi.material_override, "a": a})
		elif ch is GPUParticles3D or ch is CPUParticles3D:
			_emitters.append([ch, float(ch.get_meta("emit_delay", 0.0)), false])
			_max_life = maxf(_max_life, float(ch.lifetime))
			if ch is GPUParticles3D and (ch as GPUParticles3D).process_material is ParticleProcessMaterial:
				(ch as GPUParticles3D).process_material = (ch as GPUParticles3D).process_material.duplicate()
		elif ch is OmniLight3D and ch.has_meta("flash"):
			var f: Dictionary = ch.get_meta("flash")
			_lights.append([ch, float(f.get("e", 2.0)), float(f.get("t", 0.25)), float(f.get("d", 0.0))])
		if ch is Node3D and ch.has_meta("anims") and not (ch is MeshInstance3D):
			for a: Dictionary in ch.get_meta("anims"):
				_anims.append({"n": ch, "m": null, "a": a})
		_collect(ch)


## Set tier gates, restart everything and start the timeline.
func play_fx(tier: int) -> void:
	_prepare()
	_tier = tier
	_t = 0.0
	_stop_t = 0.0
	_stopping = false
	_active = true
	visible = true
	var ratio: float = [0.5, 0.75, 1.0, 1.0][clampi(tier, 0, 3)]
	for c in find_children("*", "Node3D", true, false):
		if c.has_meta("tier_min"):
			c.visible = tier >= int(c.get_meta("tier_min"))
	for e in _emitters:
		var p: Node = e[0]
		e[2] = false
		var on: bool = p.visible and (not p.has_meta("tier_min") or tier >= int(p.get_meta("tier_min")))
		if p is GPUParticles3D:
			(p as GPUParticles3D).amount_ratio = ratio
		if on and e[1] <= 0.0:
			_restart(p)
			e[2] = true
		else:
			p.emitting = false
	for m in _mats:
		m.set_shader_parameter("master", 0.0 if duration <= 0.0 else 1.0)
		m.set_shader_parameter("progress", 0.0)
	_eval_anims()
	for l in _lights:
		(l[0] as OmniLight3D).light_energy = (l[1] if l[3] <= 0.0 else 0.0) if tier >= 2 else 0.0
	set_process(true)


func _restart(p: Node) -> void:
	if p is GPUParticles3D:
		(p as GPUParticles3D).restart()
	elif p is CPUParticles3D:
		(p as CPUParticles3D).restart()
	p.emitting = true


## Fade a looping effect out (and release it once the last particle has died).
func stop_fx(fade := -1.0) -> void:
	if not _active or _stopping:
		return
	_stopping = true
	_stop_t = 0.0
	if fade >= 0.0:
		fade_out = fade
	for e in _emitters:
		(e[0] as Node).emitting = false


func is_playing() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	for e in _emitters:
		if not e[2] and _t >= e[1] and e[1] > 0.0:
			var p: Node = e[0]
			if p.visible and (not p.has_meta("tier_min") or _tier >= int(p.get_meta("tier_min"))):
				_restart(p)
			e[2] = true
	_eval_anims()
	for l in _lights:
		var k := clampf((_t - l[3]) / maxf(l[2], 0.01), 0.0, 1.0)
		(l[0] as OmniLight3D).light_energy = (l[1] * pow(1.0 - k, 2.0) if _t >= l[3] else 0.0) if _tier >= 2 else 0.0
	if duration > 0.0 and not _stopping:
		if _t >= duration:
			_stopping = true
			_stop_t = 0.0
			for e in _emitters:
				(e[0] as Node).emitting = false
			return
	if duration <= 0.0 and not _stopping:
		var f := clampf(_t / 0.2, 0.0, 1.0)
		for m in _mats:
			m.set_shader_parameter("master", f)
	if _stopping:
		_stop_t += delta
		if duration <= 0.0:
			var k := clampf(_stop_t / maxf(fade_out, 0.01), 0.0, 1.0)
			for m in _mats:
				m.set_shader_parameter("master", 1.0 - k)
			if _stop_t >= maxf(fade_out, _max_life):
				_finish()
		elif _stop_t >= _max_life + 0.05:
			_finish()


func _finish() -> void:
	_active = false
	_stopping = false
	set_process(false)
	visible = false
	for e in _emitters:
		(e[0] as Node).emitting = false
	finished.emit(self)


func _eval_anims() -> void:
	for it in _anims:
		var a: Dictionary = it["a"]
		var t0 := float(a.get("t0", 0.0))
		var t1 := float(a.get("t1", 1.0))
		var k := clampf((_t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
		match String(a.get("e", "lin")):
			"out":
				k = 1.0 - pow(1.0 - k, 3.0)
			"in":
				k = k * k * k
			"inout":
				k = k * k * (3.0 - 2.0 * k)
			"back":
				var c := 1.70158
				var x := k - 1.0
				k = 1.0 + (c + 1.0) * x * x * x + c * x * x
		var v: Variant = lerp(a["a"], a["b"], k)
		var n: Node3D = it["n"]
		var p := String(a["p"])
		match p:
			"scale":
				n.scale = v if v is Vector3 else Vector3.ONE * float(v)
			"y":
				n.position.y = v
			"rot_y":
				n.rotation.y = v
			"pos_z":
				n.position.z = v
			"vis":
				n.visible = _t >= t0 and _t < t1
			_:
				if it["m"] is ShaderMaterial:
					(it["m"] as ShaderMaterial).set_shader_parameter(p, v)


## Re-colour a generic effect (slashes, sparks, dash, level up) with an element palette.
func tint(pal: Dictionary) -> void:
	_prepare()
	for m in _mats:
		m.set_shader_parameter("col_core", pal["core"])
		m.set_shader_parameter("col_mid", pal["mid"])
		m.set_shader_parameter("col_edge", pal["edge"])
	for e in _emitters:
		var p: Node = e[0]
		if p is GPUParticles3D and (p as GPUParticles3D).process_material is ParticleProcessMaterial:
			var pm := (p as GPUParticles3D).process_material as ParticleProcessMaterial
			var tinted: bool = p.has_meta("tint")
			if tinted:
				pm.color = pal["mid"].lerp(Color.WHITE, float(p.get_meta("tint_white", 0.0)))
		elif p is CPUParticles3D and p.has_meta("tint"):
			(p as CPUParticles3D).color = pal["mid"]


## Stop immediately (no fade) and return to the pool.
func halt() -> void:
	if _active:
		_finish()
