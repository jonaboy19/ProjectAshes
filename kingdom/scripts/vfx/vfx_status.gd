extends RefCounted
## Status effects (small looping emitters parented to a character), the golden
## naming spiral and Rift energy. Called through VFX (scripts/vfx/vfx.gd).

const K := preload("res://scripts/vfx/vfx_kit.gd")
const Spells := preload("res://scripts/vfx/vfx_spells.gd")

const KINDS := ["burning", "frozen", "shocked", "poisoned", "blessed"]


## Attach a looping status emitter to `node` (a character, origin at the feet).
## `seconds` > 0 removes it by itself; otherwise pass the result to VFX.stop().
static func status(node: Node3D, kind: String, seconds := 0.0, height := 1.7) -> Node3D:
	var root := Node3D.new()
	root.name = "Status_" + kind
	node.add_child(root)
	var o := root.global_position
	# Emit from a shell around the body, not inside it, so the mesh doesn't hide it.
	var body := {"shape": "ring", "radius": 0.45, "inner": 0.32, "height": height * 0.75, "one_shot": false, "local": false}
	var mid := o + Vector3(0, height * 0.5, 0)
	var glow_col := {"burning": "fire", "frozen": "frost", "shocked": "lightning", "poisoned": "poison", "blessed": "holy"}
	if glow_col.has(kind):
		# Soft tinted halo that reads the status from afar (3 big dim sprites).
		K.emit(root, mid, {"amount": 3, "life": 1.2, "one_shot": false, "local": true, "v": Vector2.ZERO,
			"size": height * 1.2, "grow": "flat", "alpha": "inout", "mat": K.sprite_mat(K.DOT, K.pal(glow_col[kind]), 0.5, {"cool": 0.3})})
	match kind:
		"burning":
			var p := K.pal("fire")
			K.emit(root, mid, body.merged({"amount": 18, "life": 0.6, "v": Vector2(0.8, 1.8), "spread": 10.0,
				"gravity": Vector3(0, 2.0, 0), "size": Vector2(0.6, 0.8), "scale": Vector2(0.6, 1.0),
				"mat": K.sprite_mat(K.BLOB, p, 2.8, {"distort": 0.25, "cool": 0.8, "heat": 1.2})}))
			K.emit(root, mid, body.merged({"amount": 8, "life": 0.9, "v": Vector2(1.0, 2.5), "spread": 20.0,
				"size": Vector2(0.04, 0.18), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.4})}))
			if not K.lite():
				K.emit(root, o + Vector3(0, height, 0), {"amount": 5, "life": 1.3, "one_shot": false, "v": Vector2(0.4, 1.0),
					"spread": 20.0, "size": 0.7, "grow": "grow", "alpha": "inout", "spin": true,
					"mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.2, 0.18, 0.17), "hot": Color(0.35, 0.3, 0.27), "edge": Color(0.08, 0.07, 0.07)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
		"frozen":
			var p := K.pal("frost")
			# Ice shards hugging the legs and body, slowly glinting.
			K.emit(root, o + Vector3(0, height * 0.35, 0), {"amount": 16, "life": 2.0, "one_shot": false, "local": true,
				"shape": "ring", "radius": 0.45, "inner": 0.35, "height": height * 0.6, "v": Vector2(0.0, 0.05),
				"size": Vector2(0.28, 0.7), "grow": "pop", "alpha": "inout", "spin": true,
				"mat": K.sprite_mat(K.SHARD, p, 2.2, {"spin": true, "heat": 1.1, "cool": 0.2})})
			K.emit(root, mid, body.merged({"amount": 8, "life": 1.6, "v": Vector2(0.05, 0.25), "spread": 180.0,
				"gravity": Vector3(0, -0.3, 0), "size": 0.9, "grow": "grow", "alpha": "inout", "spin": true,
				"mat": K.sprite_mat(K.SMOKE_PUFF, p, 0.8, {"spin": true, "cool": 0.3})}))
			K.emit(root, mid, body.merged({"amount": 6, "life": 1.0, "v": Vector2(0.0, 0.2), "size": 0.22, "spin": true,
				"alpha": "inout", "grow": "pop", "mat": K.sprite_mat(K.SPARKLE, p, 4.0, {"spin": true})}))
		"shocked":
			var p := K.pal("lightning")
			K.emit(root, mid, body.merged({"amount": 8, "life": 0.14, "v": Vector2.ZERO, "size": 0.9, "spin": true,
				"grow": "flat", "explosive": 0.0, "randomness": 1.0, "mat": K.sprite_mat(K.BRANCH, p, 4.0, {"spin": true, "cool": 0.0})}))
			K.emit(root, mid, body.merged({"amount": 10, "life": 0.3, "v": Vector2(2.0, 4.0), "spread": 180.0,
				"gravity": Vector3(0, -6, 0), "size": Vector2(0.03, 0.2), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.5})}))
		"poisoned":
			var p := K.pal("poison")
			K.emit(root, mid, body.merged({"amount": 14, "life": 1.2, "v": Vector2(0.3, 0.8), "spread": 15.0,
				"gravity": Vector3(0, 0.4, 0), "size": 0.28, "scale": Vector2(0.5, 1.0), "grow": "pop", "alpha": "inout",
				"mat": K.sprite_mat(K.SOFT_RING, p, 2.5, {"heat": 1.2})}))
			if not K.lite():
				K.emit(root, o + Vector3(0, height * 0.3, 0), {"amount": 6, "life": 1.6, "one_shot": false, "shape": "box",
					"extents": Vector3(0.3, 0.3, 0.3), "v": Vector2(0.1, 0.4), "spread": 60.0, "size": 0.8, "grow": "grow",
					"alpha": "inout", "spin": true,
					"mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.35, 0.55, 0.12), "hot": Color(0.6, 0.85, 0.3), "edge": Color(0.22, 0.08, 0.25)}, 1.0, {"mix": true, "spin": true, "cool": 0.0})})
		"blessed":
			var p := K.pal("holy")
			K.emit(root, o + Vector3(0, 0.1, 0), {"amount": 14, "life": 1.8, "one_shot": false, "shape": "ring", "radius": 0.55,
				"inner": 0.4, "v": Vector2(0.5, 1.1), "spread": 5.0, "size": 0.3, "spin": true, "alpha": "inout", "grow": "pop",
				"mat": K.sprite_mat(K.SPARKLE, p, 3.5, {"spin": true})})
			var hm := K.sprite_mat(K.RING, p, 2.5, {"particle": false})
			var halo := K.quad(root, o + Vector3(0, height + 0.25, 0), hm, 0.6)
			halo.rotation.x = -PI * 0.5
			var tw := halo.create_tween().set_loops()
			tw.tween_property(hm, "shader_parameter/fade", 0.55, 0.8).set_trans(Tween.TRANS_SINE)
			tw.tween_property(hm, "shader_parameter/fade", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	if seconds > 0.0:
		var tw := root.create_tween()
		tw.tween_interval(seconds)
		tw.tween_callback(stop.bind(root))
	return root


## Fade out any effect container made by this library (status, qi flames, rift,
## persistent circles): stops its emitters and frees it once they have faded.
static func stop(fx: Variant) -> void:
	if not is_instance_valid(fx) or not (fx is Node):
		return
	var node := fx as Node
	var longest := 0.1
	for e in node.find_children("*", "GPUParticles3D", true, false):
		(e as GPUParticles3D).emitting = false
		longest = maxf(longest, (e as GPUParticles3D).lifetime)
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
		longest = maxf(longest, (node as GPUParticles3D).lifetime)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m and m.shader != null:
			node.create_tween().tween_property(m, "shader_parameter/fade", 0.0, 0.3)
	if node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		node.create_tween().tween_property((node as MeshInstance3D).material_override, "shader_parameter/fade", 0.0, 0.3)
	K.free_after(node, longest + 0.1)


## The naming rite: a golden rune circle, two ribbons spiralling up around the
## monster, sparkles drawn into the spiral and a soft bloom at the crown.
static func naming(parent: Node, pos: Vector3, height := 1.6) -> float:
	var p := K.pal("holy")
	var dur := 2.2
	Spells.magic_circle(parent, pos, "holy", 1.5, dur + 0.4)
	# Ground swirl (RPicster effect_4) turning slowly under the circle.
	var sm := K.sprite_mat(K.SWIRL, p, 2.0, {"particle": false})
	var swirl := K.ground(parent, pos + Vector3(0, 0.02, 0), sm, 3.2)
	swirl.create_tween().tween_property(swirl, "rotation:y", -TAU * 0.8, dur + 0.4)
	K.anim(swirl, sm, "fade", 0.0, 1.0, 0.4)
	K.anim(swirl, sm, "fade", 1.0, 0.0, 0.5, dur - 0.1)
	K.free_after(swirl, dur + 0.45)
	var top := height * 1.25
	for k in 2:
		var pts := K.helix_points(0.95, 0.25, top, 2.25, 56)
		var off := k * PI
		for i in pts.size():
			var v := pts[i]
			pts[i] = pos + Vector3(v.x * cos(off) - v.z * sin(off), v.y + 0.05, v.x * sin(off) + v.z * cos(off))
		var m := K.fx_mat(K.SMEAR, p, 2.2, {"tail": 0.5, "noise_amt": 0.35, "speed": 2.0})
		var mi := K.world_mesh(parent, K.path_mesh(pts, 0.2, Vector3.ZERO, true, pos), m)
		K.anim(mi, m, "progress", 0.0, 1.15, dur * 0.7, 0.1, Tween.EASE_IN_OUT, Tween.TRANS_SINE)
		K.anim(mi, m, "dissolve", 0.0, 1.0, 0.5, dur * 0.72)
		K.free_after(mi, dur + 0.3)
	# Sparkles spiralling upward (tangential accel around the upward gravity).
	var sp := K.emit(parent, pos + Vector3(0, 0.1, 0), {"amount": 26, "life": 1.4, "one_shot": false, "shape": "ring",
		"radius": 1.1, "inner": 0.8, "v": Vector2(0.8, 1.4), "spread": 5.0, "gravity": Vector3(0, 0.6, 0),
		"tangent": Vector2(4.0, 6.0), "radial": Vector2(-1.2, -0.8), "size": 0.2, "spin": true, "alpha": "inout",
		"mat": K.sprite_mat(K.SPARKLE, p, 4.0, {"spin": true, "heat": 1.2})})
	var tw := parent.create_tween()
	tw.tween_interval(dur * 0.75)
	tw.tween_callback(K.stop.bind(sp))
	tw.tween_callback(_naming_bloom.bind(parent, pos + Vector3(0, top * 0.8, 0), p))
	return dur


static func _naming_bloom(parent: Node, at: Vector3, p: Dictionary) -> void:
	K.glow(parent, at, p, 3.2, 0.7, K.STAR, 3.5)
	K.glow(parent, at, p, 4.5, 0.5, K.RADIAL, 2.2)
	K.light(parent, at, p["tint"], 3.0, 0.8, 8.0)
	K.emit(parent, at, {"amount": 24, "life": 1.2, "v": Vector2(1.0, 3.0), "spread": 180.0, "gravity": Vector3(0, -0.8, 0),
		"damping": Vector2(1.5, 2.5), "size": 0.2, "spin": true, "alpha": "late", "mat": K.sprite_mat(K.SPARKLE, p, 4.0, {"spin": true})})


## Rift energy: violet ground fissures, a floating tear in space, motes drawn in
## and ink-dark wisps. Persistent (landmark) unless `seconds` > 0; VFX.stop() it.
static func rift(parent: Node, pos: Vector3, radius := 3.0, seconds := 0.0) -> Node3D:
	var p := K.pal("rift")
	var root := Node3D.new()
	root.name = "RiftFX"
	K.add(parent, root, pos)
	var cm := K.fx_mat(K.CRACK, p, 2.6, {"progress": 1.0, "width": 0.8, "speed": 0.6})
	var crack := K.ground(root, pos, cm, radius * 2.0)
	K.anim(crack, cm, "progress", 0.05, 1.0, 0.8)
	var th := radius * 1.1
	for k in 2:
		var tm := K.fx_mat(K.TEAR, p, 3.0, {"width": 0.5, "speed": 1.0})
		var tear := K.quad(root, pos + Vector3(0, th * 0.5 + 0.6, 0), tm, 1.0)
		tear.scale = Vector3(th * 0.45, th, 1.0)
		tear.rotation.y = k * PI * 0.5
		K.anim(tear, tm, "fade", 0.0, 1.0, 0.6)
	K.emit(root, pos + Vector3(0, 0.3, 0), {"amount": 24, "life": 2.4, "one_shot": false, "shape": "disc", "radius": radius,
		"v": Vector2(0.3, 0.9), "spread": 20.0, "radial": Vector2(-1.2, -0.6), "gravity": Vector3(0, 0.4, 0),
		"size": 0.2, "alpha": "inout", "grow": "pop", "mat": K.sprite_mat(K.DOT, p, 4.0, {"heat": 1.2}), "cull": radius * 3.0})
	K.emit(root, pos + Vector3(0, th * 0.5 + 0.6, 0), {"amount": 5, "life": 0.18, "one_shot": false, "shape": "box",
		"extents": Vector3(0.4, th * 0.4, 0.4), "v": Vector2.ZERO, "size": 1.0, "spin": true, "grow": "flat", "randomness": 1.0,
		"mat": K.sprite_mat(K.BRANCH, p, 3.5, {"spin": true, "cool": 0.0}), "cull": radius * 3.0})
	if not K.lite():
		K.emit(root, pos + Vector3(0, 0.4, 0), {"amount": 10, "life": 2.5, "one_shot": false, "shape": "disc", "radius": radius * 0.8,
			"v": Vector2(0.2, 0.6), "spread": 30.0, "gravity": Vector3(0, 0.3, 0), "size": 1.4, "grow": "grow", "alpha": "inout",
			"spin": true, "mat": K.sprite_mat(K.SMOKE_PUFF, {"tint": Color(0.16, 0.05, 0.25), "hot": Color(0.4, 0.15, 0.6), "edge": Color(0.05, 0.01, 0.08)}, 1.0, {"mix": true, "spin": true, "cool": 0.0}),
			"cull": radius * 3.0})
	if K.rich():
		var l := OmniLight3D.new()
		l.light_color = p["tint"]
		l.light_energy = 1.6
		l.omni_range = radius * 2.5
		root.add_child(l)
		l.position = Vector3(0, 1.5, 0)
	if seconds > 0.0:
		var tw := root.create_tween()
		tw.tween_interval(seconds)
		tw.tween_callback(stop.bind(root))
	return root
