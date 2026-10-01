extends RefCounted
## Style G hero outfit (target 03 "hooded traveller"): adds SKINNED garment pieces to a G6/UAL character so they
## follow every animation clip (Codex's animation code is untouched; nothing here plays or edits clips).
## Pieces: green tunic skirt with folds and a hem band, leather belt + buckle, hood rolled down as a collar plus a
## back drape, bracers on both forearms, satchel on the right hip with a diagonal strap, small belt pouch.
## Every piece is built in skeleton space from the bone rest poses and fitted to the visible body mesh, so it
## works at any model scale. Cost: 1 extra skinned MeshInstance3D (one surface, ~1.3k tris).
## Usage: HeroOutfit.dress(model)   (model = Assets.mh_character / CharacterCreation.build_model result)

const TUNIC := Color("44692c")
const TUNIC_DARK := Color("31501f")
const LEATHER := Color("5c381f")
const LEATHER_DARK := Color("3f2614")
const BRASS := Color("b08a3c")

static var _sk: Skeleton3D
static var _body_pts: PackedVector3Array


## Tints the G6 "Villager Tunic" body mesh to the target's green tunic (sleeves + skirt read as one garment).
static func tint_tunic(model: Node3D) -> void:
	for n in model.find_children("*light_armor*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if mat is BaseMaterial3D:
				var t := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				t.albedo_color = Color(0.62, 0.86, 0.5)
				m.set_surface_override_material(si, t)
	for n in model.find_children("*hair*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var mat := m.get_active_material(si)
			if mat is BaseMaterial3D:
				var t := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				t.albedo_color = Color("8a5a32")     # warm chestnut (G6 tints read grey under the lab_char grade)
				m.set_surface_override_material(si, t)


static func dress(model: Node3D) -> MeshInstance3D:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	_sk = sks[0] as Skeleton3D
	if _sk.has_node("HeroOutfit"):
		return _sk.get_node("HeroOutfit") as MeshInstance3D
	_body_pts = _collect_body_points(model)
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pel := _b(["pelvis", "Hips", "hips"])
	var sp1 := _b(["spine_01", "Spine", "spine"])
	var sp3 := _b(["spine_03", "Spine2", "chest", "spine_02"])
	var neck := _b(["neck_01", "Neck", "neck"])
	var thl := _b(["thigh_l", "LeftUpLeg"])
	var thr := _b(["thigh_r", "RightUpLeg"])
	var cal := _b(["calf_l", "LeftLeg"])
	var lal := _b(["lowerarm_l", "LeftForeArm"])
	var lar := _b(["lowerarm_r", "RightForeArm"])
	var hal := _b(["hand_l", "LeftHand"])
	var har := _b(["hand_r", "RightHand"])
	if pel < 0 or thl < 0 or thr < 0:
		push_warning("HeroOutfit: skeleton has no UAL bones")
		return null
	var p_pel := _pos(pel)
	var p_thl := _pos(thl)
	var p_thr := _pos(thr)
	var p_knee := _pos(cal) if cal >= 0 else p_thl + Vector3(0, -0.45, 0)
	var unit := absf(p_thl.y - p_knee.y) / 0.45        # 1.0 = a 0.45 m thigh
	var up := Vector3.UP
	var waist_y := p_pel.y + 0.10 * unit
	var hem_y := lerpf(p_thl.y, p_knee.y, 0.55)
	var cx := (p_thl.x + p_thr.x) * 0.5
	var cz := p_pel.z
	# --- tunic skirt (fitted to the body at the waist, flared and folded at the hem) --------------------------
	var rw := _fit(waist_y, Vector2(0.16, 0.12) * unit) * 1.06
	var rh := _fit(hem_y, Vector2(0.2, 0.14) * unit)
	rh = Vector2(maxf(rh.x * 1.25, rw.x * 1.3), maxf(rh.y * 1.35, rw.y * 1.3))
	var segs := 20
	var rings := 5
	for r in rings:
		var t0 := float(r) / rings
		var t1 := float(r + 1) / rings
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var q := [[t0, a0], [t1, a0], [t1, a1], [t0, a1]]
			var vs: Array = []
			for k in q:
				var t: float = k[0]
				var a: float = k[1]
				var fold := 1.0 + sin(a * 7.0) * 0.045 * t
				var rad := rw.lerp(rh, pow(t, 0.8)) * fold
				var p := Vector3(cx + cos(a) * rad.x, lerpf(waist_y, hem_y, t), cz + sin(a) * rad.y)
				var side := clampf(cos(a) * 1.4, -1.0, 1.0)     # +x = character's left (UAL faces +z)
				var wl := t * 0.85 * clampf(0.5 + side * 0.5, 0.0, 1.0)
				var wr := t * 0.85 * clampf(0.5 - side * 0.5, 0.0, 1.0)
				var col := TUNIC_DARK if t > 0.86 else TUNIC.lerp(TUNIC_DARK, 0.25 * (1.0 - absf(sin(a * 7.0))))
				vs.append([p, [pel, thl, thr], [1.0 - wl - wr, wl, wr], col])
			_quad(st, vs[0], vs[1], vs[2], vs[3], false)
	# --- belt + buckle ---------------------------------------------------------------------------------------
	var belt_y := waist_y + 0.015 * unit
	var rb := _fit(belt_y, rw) * 1.09
	_ring(st, Vector3(cx, belt_y, cz), rb, 0.035 * unit, 0.012 * unit, [pel], [1.0], LEATHER_DARK, 20)
	_box(st, Vector3(cx, belt_y, cz + rb.y + 0.01 * unit), Vector3(0.05, 0.045, 0.012) * unit, 0.0, [pel], [1.0], BRASS)
	# --- satchel on the right hip + flap + diagonal strap to the left shoulder --------------------------------
	var bag_c := Vector3(cx - rb.x * 1.05, belt_y - 0.13 * unit, cz + rb.y * 0.35)
	_box(st, bag_c, Vector3(0.07, 0.2, 0.24) * unit, 0.12, [pel, thr], [0.7, 0.3], LEATHER)
	_box(st, bag_c + Vector3(-0.03, 0.06, 0.0) * unit, Vector3(0.025, 0.1, 0.25) * unit, 0.12, [pel, thr], [0.7, 0.3], LEATHER_DARK)
	_box(st, bag_c + Vector3(-0.045, 0.02, 0.0) * unit, Vector3(0.012, 0.03, 0.03) * unit, 0.12, [pel, thr], [0.7, 0.3], BRASS)
	if sp3 >= 0:
		var p_sh := _pos(sp3)
		var steps := 14
		var prev_f := Vector3.ZERO
		var prev_b := Vector3.ZERO
		for i in steps + 1:
			var t := float(i) / steps
			var y := lerpf(bag_c.y + 0.1 * unit, p_sh.y + 0.12 * unit, t)
			var rr := _fit(y, rb) * 1.08
			var x := lerpf(-rr.x * 0.8, rr.x * 0.5, t)       # right hip -> left shoulder
			var zz := sqrt(maxf(0.15, 1.0 - pow(x / rr.x, 2.0))) * rr.y + 0.012 * unit
			var f := Vector3(cx + x, y, cz + zz)
			var bk := Vector3(cx + x, y, cz - zz)
			var wu := clampf((y - waist_y) / maxf(0.01, p_sh.y - waist_y), 0.0, 1.0)
			if i > 0:
				pass   # strap disabled: fins through the arms in the walk cycle (TODO: lay it on the jerkin shell)
			prev_f = f
			prev_b = bk
	# --- pouch on the left front of the belt --------------------------------------------------------------------
	_box(st, Vector3(cx + rb.x * 0.62, belt_y - 0.06 * unit, cz + rb.y * 0.92), Vector3(0.09, 0.09, 0.04) * unit, 0.0, [pel, thl], [0.8, 0.2], LEATHER)
	# --- leather jerkin over the green tunic: open at the front, waist to armpits ------------------------------------
	if sp3 >= 0 and sp1 >= 0:
		var y0 := belt_y + 0.02 * unit
		var y1 := _pos(sp3).y + 0.1 * unit
		var vr := 6
		var vs_n := 22
		var r_lo := _fit(y0, Vector2(0.15, 0.11) * unit)
		var r_hi := _fit(y1 - 0.06 * unit, Vector2(0.17, 0.12) * unit)
		var r_mid := _fit(lerpf(y0, y1, 0.5), Vector2(0.16, 0.12) * unit)
		for j in vr:
			var t0 := float(j) / vr
			var t1 := float(j + 1) / vr
			for i in vs_n:
				var a0 := lerpf(PI * 0.5 + 0.42, PI * 2.5 - 0.42, float(i) / vs_n)    # skip +-24 deg around +z (front)
				var a1 := lerpf(PI * 0.5 + 0.42, PI * 2.5 - 0.42, float(i + 1) / vs_n)
				var vs: Array = []
				for k in [[t0, a0], [t1, a0], [t1, a1], [t0, a1]]:
					var y := lerpf(y0, y1, k[0])
					var rb2: Vector2 = r_lo.lerp(r_mid, k[0] * 2.0) if k[0] < 0.5 else r_mid.lerp(r_hi, k[0] * 2.0 - 1.0)
					var rr := rb2 * 1.08 + Vector2(0.006, 0.01) * unit
					var p := Vector3(cx + cos(k[1]) * rr.x, y, cz + sin(k[1]) * rr.y)
					var wu: float = k[0]
					var col := LEATHER.lerp(LEATHER_DARK, 0.3 * absf(sin(k[1] * 5.0)) * (1.0 - wu))
					vs.append([p, [sp1, sp3], [1.0 - wu, wu], col])
				_quad(st, vs[0], vs[1], vs[2], vs[3], true)
	# --- hood rolled down: thick collar ring around the neck base + a drape down the back -----------------------
	if neck >= 0 and sp3 >= 0:
		var p_n := _pos(neck)
		var cy := p_n.y - 0.02 * unit
		var rn := Vector2(0.095, 0.09) * unit
		_ring(st, Vector3(p_n.x, cy, p_n.z - 0.01 * unit), rn, 0.07 * unit, 0.055 * unit, [neck, sp3], [0.4, 0.6], LEATHER, 16)
		var top := cy - 0.01 * unit
		var bot := cy - 0.26 * unit
		var w := 9
		for j in 4:
			var t0 := float(j) / 4.0
			var t1 := float(j + 1) / 4.0
			for i in w:
				var u0 := float(i) / w
				var u1 := float(i + 1) / w
				var vs: Array = []
				for k in [[t0, u0], [t1, u0], [t1, u1], [t0, u1]]:
					var y := lerpf(top, bot, k[0])
					var rr := _fit(y, Vector2(0.15, 0.11) * unit) * 1.12 + Vector2(0.02, 0.035) * unit
					var half := lerpf(0.95, 0.35, pow(k[0], 1.4))          # pointed hood tip
					var a := PI + lerpf(-half, half, k[1]) + PI * 0.5        # centred on -z (back)
					var p := Vector3(p_n.x + cos(a) * rr.x, y, p_n.z + sin(a) * rr.y)
					vs.append([p, [sp3, neck], [0.8, 0.2], LEATHER.lerp(LEATHER_DARK, k[0] * 0.5)])
				_quad(st, vs[0], vs[1], vs[2], vs[3], false)
	# --- bracers on both forearms ---------------------------------------------------------------------------------
	for pair in [[lal, hal], [lar, har]]:
		if pair[0] < 0 or pair[1] < 0:
			continue
		var a := _pos(pair[0])
		var b := _pos(pair[1])
		var ax := (b - a)
		var r := _fit_axis(a.lerp(b, 0.7), ax.normalized(), 0.04 * unit) * 1.18
		_tube(st, a.lerp(b, 0.42), a.lerp(b, 0.9), r, r * 1.12, [pair[0]], [1.0], LEATHER, 12)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HeroOutfit"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.set_meta("role", "hero_new")
	_sk.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = _sk.create_skin_from_rest_transforms()
	return mi


# --- helpers ---------------------------------------------------------------------------------------------------------

static func _b(names: Array) -> int:
	for n in names:
		var i := _sk.find_bone(n)
		if i >= 0:
			return i
	return -1


static func _pos(i: int) -> Vector3:
	return _sk.get_bone_global_rest(i).origin


## Skeleton-space rest points of the visible body meshes (for fitting garments).
static func _collect_body_points(model: Node3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if not m.visible or m.mesh == null or m.skin == null or m.name == "HeroOutfit":
			continue
		var bind_bone := -1
		var sk := m.skin
		if sk.get_bind_count() == 0:
			continue
		bind_bone = sk.get_bind_bone(0)
		if bind_bone < 0:
			bind_bone = _sk.find_bone(sk.get_bind_name(0))
		if bind_bone < 0:
			continue
		var xf := _sk.get_bone_global_rest(bind_bone) * sk.get_bind_pose(0)
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in range(0, v.size(), 2):
				pts.append(xf * v[i])
	return pts


## Ellipse radii (x, z) of the body at height y around the body's centre; `fallback` if nothing is there.
static func _fit(y: float, fallback: Vector2) -> Vector2:
	var mx := 0.0
	var mz := 0.0
	var n := 0
	for p in _body_pts:
		if absf(p.y - y) < 0.025 and absf(p.x) < 0.2 and absf(p.z) < 0.3:   # torso band only, no arms
			mx = maxf(mx, absf(p.x))
			mz = maxf(mz, absf(p.z))
			n += 1
	if n < 12:
		return fallback
	return Vector2(maxf(mx, fallback.x * 0.6), maxf(mz, fallback.y * 0.6))


## Radius of the limb around `c` along axis `ax`.
static func _fit_axis(c: Vector3, ax: Vector3, fallback: float) -> float:
	var r := 0.0
	for p in _body_pts:
		var d := p - c
		var along := d.dot(ax)
		if absf(along) < 0.03:
			var rad := (d - ax * along).length()
			if rad < 0.09:
				r = maxf(r, rad)
	return r if r > 0.01 else fallback


static func _vert(st: SurfaceTool, v: Array) -> void:
	var bones := PackedInt32Array([0, 0, 0, 0])
	var weights := PackedFloat32Array([0, 0, 0, 0])
	var bs: Array = v[1]
	var ws: Array = v[2]
	var tot := 0.0
	for i in bs.size():
		if bs[i] >= 0:
			tot += float(ws[i])
	for i in mini(bs.size(), 4):
		if bs[i] >= 0:
			bones[i] = bs[i]
			weights[i] = float(ws[i]) / maxf(tot, 0.0001)
	st.set_color(v[3])
	st.set_bones(bones)
	st.set_weights(weights)
	st.add_vertex(v[0])


static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array, flip: bool) -> void:
	if flip:
		for v in [a, c, b, a, d, c]:
			_vert(st, v)
	else:
		for v in [a, b, c, a, c, d]:
			_vert(st, v)


static func _ring(st: SurfaceTool, c: Vector3, r: Vector2, h: float, th: float, bs: Array, ws: Array, col: Color, segs: int) -> void:
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var pts := []
		for a in [a0, a1]:
			var o := Vector3(cos(a) * r.x, 0, sin(a) * r.y)
			var o2 := Vector3(cos(a) * (r.x + th), 0, sin(a) * (r.y + th))
			pts.append([c + o + Vector3(0, h * 0.5, 0), c + o2 + Vector3(0, h * 0.3, 0), c + o2 - Vector3(0, h * 0.3, 0), c + o - Vector3(0, h * 0.5, 0)])
		for k in 3:
			_quad(st, [pts[0][k], bs, ws, col], [pts[0][k + 1], bs, ws, col], [pts[1][k + 1], bs, ws, col], [pts[1][k], bs, ws, col], false)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, bs: Array, ws: Array, col: Color, segs: int) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.UP).normalized()
	var v := ax.cross(u)
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		_quad(st, [a + d0 * r0, bs, ws, col], [b + d0 * r1, bs, ws, col], [b + d1 * r1, bs, ws, col], [a + d1 * r0, bs, ws, col], true)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float, bs: Array, ws: Array, col: Color) -> void:
	var h := size * 0.5
	var bas := Basis(Vector3.UP, yaw)
	var cs := []
	for i in 8:
		cs.append(c + bas * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_quad(st, [cs[f[0]], bs, ws, col], [cs[f[1]], bs, ws, col], [cs[f[2]], bs, ws, col], [cs[f[3]], bs, ws, col], false)


static func _strap(st: SurfaceTool, p0: Vector3, p1: Vector3, w: float, out: Vector3, b0: int, b1: int, wu: float, col: Color) -> void:
	var dir := (p1 - p0).normalized()
	var side := dir.cross(out).normalized() * w * 0.5
	var bs := [b0, b1]
	var ws := [1.0 - wu, wu]
	_quad(st, [p0 - side, bs, ws, col], [p1 - side, bs, ws, col], [p1 + side, bs, ws, col], [p0 + side, bs, ws, col], false)
