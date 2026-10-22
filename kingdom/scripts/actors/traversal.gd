extends RefCounted
## Traversal (package F2): vault, mantle, ledge grab / hang / climb / drop, ladder moves and stair step-up.
##
## Two halves:
##  - static detection and planning (probe, classify, plan_for, pose, step_height): ray / shape probes in
##    front of a body, no scene state. All thresholds come from data/movement/traversal.json.
##  - Driver: a small state machine owned by the Player (`_trav`). The Player calls tick() once per physics
##    frame BEFORE its own movement; while tick() returns true the Driver owns the body (the capsule moves along
##    a scripted curve with collisions off and no gravity, the authored clip plays on the animator's full-body
##    slot). It also supplies the context-button candidate (Interaction.add_provider), jump-to-mantle and
##    step-up.
##
## Obstacle probe, in short: a low ray finds the wall, a ray from above finds the top (height), a row of
## downward rays measures the depth of the top, then capsule overlap tests check the room on top and the
## landing spot. Heights are metres above the player's feet.
##
## Clips (UAL_Authored_Traversal.glb, root track disabled): the timings in the JSON are the clips' event
## frames / 30 (docs/anim/traversal_v2_HANDOFF.md). The curves reach the top when the clip's foot lands.

const CONFIG_PATH := "res://data/movement/traversal.json"
const SettingsStore := preload("res://scripts/ui/frontend/settings_store.gd")

const NONE := &"none"
const VAULT := &"vault"
const MANTLE_LOW := &"mantle_low"
const MANTLE_HIGH := &"mantle_high"
const LEDGE := &"ledge"

const DEFAULTS := {
	"bands": {"vault": {"min": 0.5, "max": 1.1, "max_depth": 0.8}, "mantle_low": {"min": 0.6, "max": 1.2, "min_depth": 0.5},
		"mantle_high": {"min": 1.2, "max": 2.0, "min_depth": 0.5}, "ledge": {"min": 2.0, "max": 2.6, "min_depth": 0.5}},
	"probe": {"low_ray_height": 0.45, "reach": 1.3, "button_range": 1.2, "max_wall_angle_deg": 55.0, "top_flat_normal_y": 0.7,
		"depth_step": 0.15, "depth_max": 1.5, "depth_flat_tol": 0.12, "land_offset": 0.55, "land_below_max": 0.8,
		"land_above_max": 0.4, "clear_radius": 0.3, "clear_height": 1.7, "clear_lift": 0.06, "top_inset": 0.4, "mask": 1},
	"step": {"max_height": 0.35, "min_height": 0.04, "probe_dist": 0.45, "min_depth": 0.3, "min_floor_normal_y": 0.85,
		"min_speed": 0.5, "camera_recover": 6.0, "cooldown": 0.05},
}

static var _cfg: Dictionary = {}
static var _clear_shape: CapsuleShape3D


## The merged config (JSON over DEFAULTS), cached.
static func config() -> Dictionary:
	if not _cfg.is_empty():
		return _cfg
	var c: Dictionary = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(CONFIG_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if parsed is Dictionary:
			for k in (parsed as Dictionary):
				if String(k).begins_with("_"):
					continue
				var v: Variant = parsed[k]
				if v is Dictionary and c.get(k) is Dictionary:
					(c[k] as Dictionary).merge(v, true)
				else:
					c[k] = v
	_cfg = c
	return c


static func reload_config() -> Dictionary:
	_cfg = {}
	return config()


# ---- classification (pure) ----------------------------------------------------------------------------------

## Which traversal an obstacle allows. `top_clear`: room to stand on top; `landing_ok`: a free landing beyond;
## `can_jump`: a ledge grab needs a jump (button, jump press), so it is only offered then.
static func classify(height: float, depth: float, top_clear: bool, landing_ok: bool, can_jump := true, cfg: Dictionary = {}) -> StringName:
	var b: Dictionary = (cfg if not cfg.is_empty() else config())["bands"]
	var v: Dictionary = b["vault"]
	var ml: Dictionary = b["mantle_low"]
	var mh: Dictionary = b["mantle_high"]
	var lg: Dictionary = b["ledge"]
	if height >= float(v["min"]) and height <= float(v["max"]) and depth <= float(v["max_depth"]) and landing_ok:
		return VAULT
	if height >= float(ml["min"]) and height <= float(ml["max"]) and depth >= float(ml["min_depth"]) and top_clear:
		return MANTLE_LOW
	if height >= float(mh["min"]) and height <= float(mh["max"]) and depth >= float(mh["min_depth"]) and top_clear:
		return MANTLE_HIGH
	if height > float(mh["max"]) and height <= float(lg["max"]) and can_jump and depth >= float(lg["min_depth"]) and top_clear:
		return LEDGE
	return NONE


static func verb_for(kind: StringName) -> String:
	return "Vault" if kind == VAULT else "Climb"


# ---- probes -------------------------------------------------------------------------------------------------

static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	return space.intersect_ray(q)


## True when a standing capsule fits at `feet` (lifted a little so the floor under it does not count).
static func fits(space: PhysicsDirectSpaceState3D, feet: Vector3, cfg: Dictionary, exclude: Array) -> bool:
	var pr: Dictionary = cfg["probe"]
	if _clear_shape == null:
		_clear_shape = CapsuleShape3D.new()
	_clear_shape.radius = float(pr["clear_radius"])
	_clear_shape.height = float(pr["clear_height"])
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _clear_shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (float(pr["clear_lift"]) + _clear_shape.height * 0.5))
	q.collision_mask = int(pr["mask"])
	q.exclude = exclude
	q.margin = 0.0
	return space.intersect_shape(q, 1).is_empty()


## Probes the obstacle in front of `feet` along `dir` (horizontal). Returns {kind, ...}; `kind` is NONE when
## nothing can be traversed. Other keys of a hit: height, depth, top_y, inward (unit, into the obstacle), perp
## (distance to the face along inward), dist (flat distance to the hit), face_c (face point on the player's
## line), top_spot, inset, top_clear, landing_ok, land (landing spot), side (+1 obstacle to the right), n.
static func probe(space: PhysicsDirectSpaceState3D, feet: Vector3, dir: Vector3, exclude: Array, can_jump := true,
		reach := -1.0, cfg: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var pr: Dictionary = c["probe"]
	var out := {"kind": NONE}
	var d := Vector3(dir.x, 0.0, dir.z)
	if space == null or d.length_squared() < 0.0001:
		return out
	d = d.normalized()
	var mask := int(pr["mask"])
	var r := reach if reach > 0.0 else float(pr["reach"])
	var from := feet + Vector3.UP * float(pr["low_ray_height"])
	var hit := _ray(space, from, from + d * r, mask, exclude)
	if hit.is_empty():
		return out
	var hn: Vector3 = hit["normal"]
	if absf(hn.y) > 0.35:
		return out
	var n := Vector3(hn.x, 0.0, hn.z).normalized()
	if n.dot(-d) < cos(deg_to_rad(float(pr["max_wall_angle_deg"]))):
		return out
	var inward := -n
	var p: Vector3 = hit["position"]
	var flat_hit := Vector3(p.x - feet.x, 0.0, p.z - feet.z)
	var perp := maxf(flat_hit.dot(inward), 0.0)
	var face_c := feet + inward * perp
	out["n"] = n
	out["inward"] = inward
	out["perp"] = perp
	out["dist"] = flat_hit.length()
	out["face_c"] = face_c
	out["hit"] = p
	out["side"] = 1.0 if inward.cross(Vector3.UP).dot(flat_hit) > 0.0 else -1.0
	# Height: a ray from above, just inside the face. A wall taller than the start point starts the ray inside it.
	var bands: Dictionary = c["bands"]
	var top_probe := feet.y + float((bands["ledge"] as Dictionary)["max"]) + 0.35
	var at := face_c + inward * 0.06
	var down := _ray(space, Vector3(at.x, top_probe, at.z), Vector3(at.x, feet.y - 0.05, at.z), mask, exclude)
	if down.is_empty():
		return out
	if float((down["normal"] as Vector3).y) < float(pr["top_flat_normal_y"]):
		return out
	var top_y: float = (down["position"] as Vector3).y
	var height := top_y - feet.y
	out["top_y"] = top_y
	out["height"] = height
	if height < float((bands["vault"] as Dictionary)["min"]) or height > float((bands["ledge"] as Dictionary)["max"]):
		return out
	# Depth of the flat top, measured to centimetres by bisecting the edge.
	var depth := _top_depth(space, face_c, inward, top_y, mask, exclude, pr)
	out["depth"] = depth
	# Room on top (mantle / ledge) and a landing spot beyond (vault).
	var inset := minf(float(pr["top_inset"]), depth * 0.8)
	var top_spot := face_c + inward * inset
	top_spot.y = top_y
	out["top_spot"] = top_spot
	out["inset"] = inset
	var clear := false
	if height >= float((bands["mantle_low"] as Dictionary)["min"]):
		clear = fits(space, top_spot, c, exclude)
	out["top_clear"] = clear
	var landing_ok := false
	var land := Vector3.ZERO
	var vb: Dictionary = bands["vault"]
	if height <= float(vb["max"]) and depth <= float(vb["max_depth"]):
		var lp := face_c + inward * (depth + float(pr["land_offset"]))
		var g := _ray(space, Vector3(lp.x, top_y + 0.3, lp.z), Vector3(lp.x, feet.y - float(pr["land_below_max"]) - 0.1, lp.z), mask, exclude)
		if not g.is_empty() and float((g["normal"] as Vector3).y) >= float(pr["top_flat_normal_y"]):
			var gy: float = (g["position"] as Vector3).y
			if gy >= feet.y - float(pr["land_below_max"]) and gy <= feet.y + float(pr["land_above_max"]):
				land = Vector3(lp.x, gy, lp.z)
				landing_ok = fits(space, land, c, exclude)
	out["landing_ok"] = landing_ok
	out["land"] = land
	out["kind"] = classify(height, depth, clear, landing_ok, can_jump, c)
	return out


static func _top_depth(space: PhysicsDirectSpaceState3D, face_c: Vector3, inward: Vector3, top_y: float, mask: int,
		exclude: Array, pr: Dictionary) -> float:
	var step := float(pr["depth_step"])
	var dmax := float(pr["depth_max"])
	var tol := float(pr["depth_flat_tol"])
	var last_ok := 0.0
	var s := 0.06
	while s <= dmax + 0.0001:
		if not _flat_at(space, face_c + inward * s, top_y, mask, exclude, tol):
			var lo := last_ok
			var hi := s
			for _i in 3:
				var mid := (lo + hi) * 0.5
				if _flat_at(space, face_c + inward * mid, top_y, mask, exclude, tol):
					lo = mid
				else:
					hi = mid
			return lo
		last_ok = s
		s += step
	return dmax


static func _flat_at(space: PhysicsDirectSpaceState3D, at: Vector3, top_y: float, mask: int, exclude: Array, tol: float) -> bool:
	var g := _ray(space, Vector3(at.x, top_y + 0.5, at.z), Vector3(at.x, top_y - 0.3, at.z), mask, exclude)
	return not g.is_empty() and absf((g["position"] as Vector3).y - top_y) <= tol


## Height of a small edge in front of a grounded, moving body that it may step onto, else 0. `reach` is the
## distance from the body centre at which the edge is looked for (radius + this frame's travel + margin).
## Steep tops, tops thinner than min_depth and posts narrower than ~0.35 m are refused.
static func step_height(space: PhysicsDirectSpaceState3D, feet: Vector3, dir: Vector3, reach: float, exclude: Array,
		cfg: Dictionary = {}) -> float:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var st: Dictionary = c["step"]
	var mask := int((c["probe"] as Dictionary)["mask"])
	var d := Vector3(dir.x, 0.0, dir.z)
	if space == null or d.length_squared() < 0.0001:
		return 0.0
	d = d.normalized()
	var max_h := float(st["max_height"])
	var low := feet + Vector3.UP * float(st["min_height"]) * 0.5
	var hit := _ray(space, low, low + d * reach, mask, exclude)
	if hit.is_empty() or absf(float((hit["normal"] as Vector3).y)) > 0.35:
		return 0.0
	var p: Vector3 = hit["position"]
	var side := d.cross(Vector3.UP)
	var top_y := -INF
	# Forward samples: just past the face, and `min_depth` onto the top; lateral samples guard against thin posts.
	var samples := [d * 0.08, d * float(st["min_depth"]), d * 0.08 + side * 0.17, d * 0.08 - side * 0.17]
	for i in samples.size():
		var at: Vector3 = Vector3(p.x, 0.0, p.z) + (samples[i] as Vector3)
		var g := _ray(space, Vector3(at.x, feet.y + max_h + 0.1, at.z), Vector3(at.x, feet.y - 0.1, at.z), mask, exclude)
		if g.is_empty():
			return 0.0
		if float((g["normal"] as Vector3).y) < float(st["min_floor_normal_y"]):
			return 0.0
		var y: float = (g["position"] as Vector3).y
		if i == 0:
			top_y = y
		elif absf(y - top_y) > 0.06:
			return 0.0
	var h := top_y - feet.y
	if h < float(st["min_height"]) or h > max_h:
		return 0.0
	# Head room at the raised position.
	if not fits(space, feet + Vector3.UP * h, c, exclude):
		return 0.0
	return h


# ---- plans (pure) -------------------------------------------------------------------------------------------

static func _ss(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## A scripted move for a probe result, started at `start` with `entry_speed` (m/s). The plan is a Dictionary the
## pose() function evaluates; `duration` is when the scripted part ends and `handover` the real time the clip is
## released (the full-body slot is faded out then).
static func plan_for(res: Dictionary, start: Vector3, entry_speed := 0.0, cfg: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cfg if not cfg.is_empty() else config()
	var kind: StringName = res.get("kind", NONE)
	var inward: Vector3 = res["inward"]
	var perp: float = res["perp"]
	var plan := {"kind": kind, "start": start, "inward": inward, "perp": perp, "top_y": res.get("top_y", start.y),
		"depth": res.get("depth", 0.0), "rate": 1.0, "side": res.get("side", 1.0)}
	match kind:
		VAULT:
			var vc: Dictionary = c["vault"]
			var land: Vector3 = res["land"]
			var ltot: float = perp + float(res["depth"]) + float((c["probe"] as Dictionary)["land_offset"])
			var v0 := clampf(entry_speed, 2.0, 7.0)
			var ve := clampf(v0, float(vc["exit_speed_min"]), float(vc["exit_speed_cap"]))
			var tc := maxf(2.0 * ltot / (v0 + ve), float(vc["min_cover"]))
			var clip := String(vc["clip_b"]) if float(res.get("side", 1.0)) > 0.0 else String(vc["clip"])
			plan.merge({"shape": "vault", "ltot": ltot, "v0": v0, "ve": ve, "land_y": land.y, "exit_speed": ve,
				"apex": float(res["top_y"]) + float(vc["apex_clear"]), "clip": clip}, true)
			_fit_vault(plan, tc)
			var rate := clampf(float(vc["touch_down"]) / float(plan["duration"]), 1.0, 1.6)
			plan["rate"] = rate
			plan["handover"] = float(vc["handover"]) / rate
			plan["end"] = Vector3(start.x, land.y, start.z) + inward * ltot
		MANTLE_LOW, MANTLE_HIGH:
			var mc: Dictionary = c[String(kind)]
			var top: Vector3 = res["top_spot"]
			plan.merge({"shape": "mantle", "clip": String(mc["clip"]), "a": float(mc["approach"]), "r": float(mc["rise_end"]),
				"m": float(mc["move_end"]), "s_a": perp - float(mc["start_dist"]), "s_t": perp + float(res["inset"]),
				"duration": float(mc["move_end"]), "handover": float(mc["handover"]), "exit_speed": 0.0}, true)
			plan["end"] = Vector3(start.x, top.y, start.z) + inward * float(plan["s_t"])
		LEDGE:
			var lc: Dictionary = c["ledge"]
			var hang_y := maxf(float(res["top_y"]) - float(lc["hang_height"]), start.y)
			plan.merge({"shape": "grab", "clip": String(lc["grab_clip"]), "a": float(lc["approach"]), "hc": float(lc["hands_contact"]),
				"s_g": perp - float(lc["hang_dist"]), "hang_y": hang_y, "s_t": perp + float(res["inset"]),
				"duration": float(lc["grab_end"]), "handover": -1.0, "exit_speed": 0.0}, true)
			plan["end"] = Vector3(start.x, float(res["top_y"]), start.z) + inward * float(plan["s_t"])
			plan["hang"] = Vector3(start.x, hang_y, start.z) + inward * float(plan["s_g"])
	return plan


## Picks a start delay and rise time so the capsule is above the obstacle whenever it overlaps it, then
## fixes the plan's duration. Checked on a fine time grid.
static func _fit_vault(plan: Dictionary, tc: float) -> void:
	var perp: float = plan["perp"]
	var depth: float = plan["depth"]
	var top_y: float = plan["top_y"]
	var best_td := 0.0
	var best_up := 0.2
	var found := false
	for td_i in 9:
		var td := 0.05 * td_i
		for up in [0.4, 0.32, 0.25, 0.2]:
			plan["t_delay"] = td
			plan["t_up"] = up
			plan["duration"] = td + tc
			var ok := true
			var steps := int((td + tc) / 0.02) + 1
			for i in steps + 1:
				var t := float(i) * 0.02
				var s := vault_s(plan, t)
				if s > perp - 0.4 and s < perp + depth + 0.4 and vault_y(plan, t, s) < top_y + 0.02:
					ok = false
					break
			if ok:
				best_td = td
				best_up = up
				found = true
				break
		if found:
			break
	plan["t_delay"] = best_td
	plan["t_up"] = best_up
	plan["duration"] = best_td + tc


static func vault_s(plan: Dictionary, t: float) -> float:
	var td: float = plan["t_delay"]
	var tc: float = float(plan["duration"]) - td
	var tt := clampf(t - td, 0.0, tc)
	var v0: float = plan["v0"]
	var ve: float = plan["ve"]
	var raw := v0 * tt + (ve - v0) * tt * tt / (2.0 * tc)
	var norm := 0.5 * (v0 + ve) * tc
	return float(plan["ltot"]) * raw / maxf(norm, 0.0001)


static func vault_y(plan: Dictionary, t: float, s: float) -> float:
	var y0: float = (plan["start"] as Vector3).y
	var apex: float = maxf(float(plan["apex"]), y0)
	var yy := lerpf(y0, apex, _ss(t / float(plan["t_up"])))
	var k2: float = float(plan["perp"]) + float(plan["depth"]) + 0.45
	var ltot: float = plan["ltot"]
	var dn := _ss((s - k2) / maxf(ltot - k2, 0.05))
	return lerpf(yy, float(plan["land_y"]), dn)


## Body position at time `t` of a plan.
static func pose(plan: Dictionary, t: float) -> Vector3:
	var st: Vector3 = plan["start"]
	var inw: Vector3 = plan["inward"]
	var s := 0.0
	var y := st.y
	match String(plan["shape"]):
		"vault":
			s = vault_s(plan, t)
			y = vault_y(plan, t, s)
		"mantle":
			var a: float = plan["a"]
			var r: float = plan["r"]
			var m: float = plan["m"]
			var f := a + 0.8 * (r - a)
			s = lerpf(0.0, float(plan["s_a"]), _ss(t / a))
			if t >= a:
				y = lerpf(st.y, float(plan["top_y"]), _ss((t - a) / (r - a)))
				s = lerpf(float(plan["s_a"]), float(plan["s_t"]), _ss((t - f) / (m - f)))
		"grab":
			var a2: float = plan["a"]
			var hc: float = plan["hc"]
			s = lerpf(0.0, float(plan["s_g"]), _ss(t / a2))
			var up := _ss((t - 0.5 * hc) / (0.5 * hc))
			y = lerpf(st.y, float(plan["hang_y"]), up) + 0.12 * sin(PI * clampf(t / hc, 0.0, 1.0))
		"hang":
			s = float(plan["s_g"])
			y = float(plan["hang_y"])
		"climb":
			var cr: Array = plan["rise"]
			var cm: Array = plan["move"]
			y = lerpf(float(plan["hang_y"]), float(plan["top_y"]), _ss((t - float(cr[0])) / (float(cr[1]) - float(cr[0]))))
			s = lerpf(float(plan["s_g"]), float(plan["s_t"]), _ss((t - float(cm[0])) / (float(cm[1]) - float(cm[0]))))
		"drop":
			s = float(plan["s_g"]) - float(plan["back"]) * _ss(t / float(plan["release"]))
			y = float(plan["hang_y"])
		"ladder":
			return _ladder_pose(plan, t)
	return Vector3(st.x + inw.x * s, y, st.z + inw.z * s)


static func _ladder_pose(plan: Dictionary, t: float) -> Vector3:
	var st: Vector3 = plan["start"]
	var at: Vector3 = plan["at"]
	var dest: Vector3 = plan["dest"]
	var a: float = plan["a"]
	var d: float = plan["d"]
	var e: float = plan["e"]
	if t < a:
		var k := _ss(t / a)
		return Vector3(lerpf(st.x, at.x, k), st.y, lerpf(st.z, at.z, k))
	if t < a + d:
		return Vector3(at.x, lerpf(st.y, dest.y, (t - a) / d), at.z)
	var k2 := _ss((t - a - d) / e)
	return Vector3(lerpf(at.x, dest.x, k2), dest.y, lerpf(at.z, dest.z, k2))


# ---- the state driver ---------------------------------------------------------------------------------------

## The Driver is created by the Player (`_trav = Traversal.Driver.new(self)`) and ticked each physics frame.
class Driver extends RefCounted:
	const T := preload("res://scripts/actors/traversal.gd")

	signal started(kind: StringName)
	signal finished(kind: StringName)

	enum S { IDLE, MOVE, HANG }

	var p: CharacterBody3D
	var cfg: Dictionary
	var state := S.IDLE
	var kind: StringName = &"none"
	var plan: Dictionary = {}
	var t := 0.0
	var auto_vault := true
	var _saved_mask := 1
	var _cooldown := 0.0
	var _tail := -1.0
	var _hang_grace := 0.0
	var _done := Callable()
	var _settings_age := 99.0
	var _step_cooldown := 0.0
	var _step_visual := 0.0
	var _cache_frame := -100
	var _cache_feet := Vector3.INF
	var _cache_dir := Vector3.ZERO
	var _cache_res: Dictionary = {}
	var _provider := Callable()
	var _wants_climb := false
	var _wants_drop := false


	func _init(body: CharacterBody3D) -> void:
		p = body
		cfg = T.config()


	## Registers the context-button provider; removed again when the body leaves the tree.
	func register_provider() -> void:
		var interaction := load("res://scripts/interaction/interaction.gd")
		_provider = Callable(self, "candidates")
		interaction.call("add_provider", _provider)
		if p != null:
			p.tree_exiting.connect(unregister_provider, CONNECT_ONE_SHOT)


	func unregister_provider() -> void:
		if _provider.is_valid():
			var interaction := load("res://scripts/interaction/interaction.gd")
			interaction.call("remove_provider", _provider)
		_provider = Callable()


	# -- queries -------------------------------------------------------------------------------------------

	func busy() -> bool:
		return state != S.IDLE


	func hanging() -> bool:
		return state == S.HANG


	func _space() -> PhysicsDirectSpaceState3D:
		if p == null or not p.is_inside_tree():
			return null
		var w := p.get_world_3d()
		return w.direct_space_state if w else null


	func _exclude() -> Array:
		return [p.get_rid()]


	func _flag(prop: StringName) -> bool:
		var v: Variant = p.get(prop)
		return v != null and bool(v)


	func _num(prop: StringName) -> float:
		var v: Variant = p.get(prop)
		return float(v) if v != null else 0.0


	## May a traversal start now?
	func can_start() -> bool:
		if state != S.IDLE or _cooldown > 0.0:
			return false
		if p == null or not p.is_inside_tree() or _flag(&"dead") or _flag(&"swimming") or p.get("_mount") != null:
			return false
		if _num(&"_dodge") > 0.0 or _num(&"_stunned") > 0.0 or _num(&"_swing") > 0.0:
			return false
		return p.is_on_floor() or _num(&"_air_time") <= 0.12


	func facing_dir() -> Vector3:
		var f := Vector3.ZERO
		if p.has_method("facing"):
			f = p.call("facing")
		else:
			f = -p.global_transform.basis.z
		f.y = 0.0
		return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


	# -- starting a traversal --------------------------------------------------------------------------------

	## Starts the traversal described by a probe result. Returns false when it cannot run.
	func begin(res: Dictionary, entry_speed := 0.0) -> bool:
		var k: StringName = res.get("kind", NONE)
		if k == NONE or not can_start():
			return false
		var cost := float((cfg[String(k)] as Dictionary).get("stamina", 0.0))
		var stam: Variant = p.get("stamina")
		if stam != null and float(stam) < cost:
			return false
		if stam != null and p.has_method("_spend"):
			p.call("_spend", cost)
		plan = T.plan_for(res, p.global_position, entry_speed, cfg)
		kind = k
		_enter_move(String(plan["clip"]), float(plan["rate"]))
		started.emit(k)
		return true


	func _enter_move(clip: String, rate: float) -> void:
		state = S.MOVE
		t = 0.0
		_tail = -1.0
		_wants_climb = false
		_wants_drop = false
		_take_body()
		_play(clip, rate)


	func _take_body() -> void:
		if p.collision_mask != 0:
			_saved_mask = p.collision_mask
		p.collision_mask = 0
		p.velocity = Vector3.ZERO
		for flag in [&"_jump_active", &"_jump_starting", &"_air_visual", &"_jump_falling", &"_land_roll", &"_pivoting"]:
			if p.get(flag) != null:
				p.set(flag, false)
		for timer in [&"_jump_buffer", &"_land_time", &"_land_lock", &"_dodge_buffer"]:
			if p.get(timer) != null:
				p.set(timer, 0.0)
		if p.has_method("_cancel_locomotion_transition"):
			p.call("_cancel_locomotion_transition")
		if p.has_method("_cancel_pivot"):
			p.call("_cancel_pivot")
		p.reset_physics_interpolation()


	func _play(clip: String, rate := 1.0) -> void:
		var a: Variant = p.get("_animator")
		if a == null:
			return
		var pl: Variant = (a as Object).get("player")
		if pl is AnimationPlayer and not (pl as AnimationPlayer).has_animation(clip):
			return
		(a as Object).call("play_full", clip, rate)


	func _stop_clip() -> void:
		var a: Variant = p.get("_animator")
		if a != null:
			(a as Object).call("stop_full")


	# -- per-frame -------------------------------------------------------------------------------------------

	## Called by the Player every physics frame before its own movement. `move_input` is the world-space stick /
	## key direction. Returns true while the Driver owns the body (the Player must skip its own movement).
	func tick(delta: float, move_input := Vector3.ZERO) -> bool:
		_cooldown = maxf(_cooldown - delta, 0.0)
		_step_cooldown = maxf(_step_cooldown - delta, 0.0)
		_settings_age += delta
		_decay_step_visual(delta)
		if _tail >= 0.0:
			_tail -= delta
			if _tail <= 0.0:
				_tail = -1.0
				_stop_clip()
		if state == S.IDLE:
			_try_auto_vault(move_input)
			if state == S.IDLE:
				return false
		if _flag(&"dead"):
			_abort()
			return false
		match state:
			S.MOVE:
				_tick_move(delta)
			S.HANG:
				_tick_hang(delta, move_input)
		if state != S.IDLE:
			_present(delta)
		return state != S.IDLE


	func _present(delta: float) -> void:
		# Face the wall / ladder; keep the animator, foot rig and camera alive while the body is scripted.
		var dir: Vector3 = plan.get("inward", Vector3.ZERO)
		var model: Variant = p.get("_model")
		if dir.length_squared() > 0.01:
			var want := atan2(dir.x, dir.z)
			if model is Node3D:
				var m := model as Node3D
				m.rotation.y += clampf(angle_difference(m.rotation.y, want), -14.0 * delta, 14.0 * delta)
			else:
				p.rotation.y = atan2(-dir.x, -dir.z)
		var rig: Variant = p.get("_rig")
		if rig is Object:
			(rig as Object).call("set_state", 0.0, false, true, true)
		var a: Variant = p.get("_animator")
		if a != null:
			(a as Object).call("update", delta, 0.0, Vector3.ZERO)
		if p.has_method("_update_camera"):
			p.call("_update_camera", delta)


	func _tick_move(delta: float) -> void:
		t += delta
		var dur: float = plan["duration"]
		p.global_position = T.pose(plan, minf(t, dur))
		p.velocity = Vector3.ZERO
		if t < dur:
			return
		match String(plan["shape"]):
			"grab":
				_enter_hang()
			"drop":
				_finish_drop()
			_:
				_finish()


	func _enter_hang() -> void:
		var lc: Dictionary = cfg["ledge"]
		plan["shape"] = "hang"
		state = S.HANG
		t = 0.0
		_hang_grace = 0.25
		p.global_position = T.pose(plan, 0.0)
		_play(String(lc["hang_clip"]), 1.0)


	func _tick_hang(delta: float, move_input: Vector3) -> void:
		t += delta
		p.global_position = T.pose(plan, 0.0)
		p.velocity = Vector3.ZERO
		_hang_grace = maxf(_hang_grace - delta, 0.0)
		var inw: Vector3 = plan["inward"]
		var flat := Vector3(move_input.x, 0.0, move_input.z)
		var along := flat.dot(inw)
		var pull_back := float((cfg["ledge"] as Dictionary)["pull_back_dot"])
		var want_drop := _wants_drop or Input.is_action_just_pressed("crouch") \
				or (flat.length() > 0.5 and along < -pull_back and _hang_grace <= 0.0)
		var want_climb := _wants_climb or (flat.length() > 0.5 and along > 0.6 and _hang_grace <= 0.0)
		if want_drop:
			_start_drop()
		elif want_climb:
			_start_climb()


	func request_climb() -> void:
		_wants_climb = true


	func request_drop() -> void:
		_wants_drop = true


	func _start_climb() -> void:
		var lc: Dictionary = cfg["ledge"]
		plan["shape"] = "climb"
		plan["rise"] = lc["climb_rise"]
		plan["move"] = lc["climb_move"]
		plan["duration"] = float((lc["climb_move"] as Array)[1])
		plan["handover"] = float(lc["climb_handover"])
		plan["exit_speed"] = 0.0
		_enter_move(String(lc["climb_clip"]), 1.0)


	func _start_drop() -> void:
		var lc: Dictionary = cfg["ledge"]
		plan["shape"] = "drop"
		plan["release"] = float(lc["drop_release"])
		plan["back"] = float(lc["drop_back"])
		plan["duration"] = float(lc["drop_release"])
		plan["handover"] = float(lc["drop_handover"])
		plan["exit_speed"] = 0.0
		_enter_move(String(lc["drop_clip"]), 1.0)


	func _finish_drop() -> void:
		# Released: the body falls under normal gravity (collisions back on); the clip finishes its landing.
		var inw: Vector3 = plan["inward"]
		_release_body()
		p.velocity = -inw * 1.2
		state = S.IDLE
		_tail = maxf(float(plan["handover"]) - float(plan["duration"]), 0.0)
		_cooldown = 0.4
		finished.emit(&"ledge_drop")


	func _finish() -> void:
		var k := kind
		var inw: Vector3 = plan["inward"]
		var end: Vector3 = plan.get("end", p.global_position)
		p.global_position = end + Vector3.UP * 0.005
		_release_body()
		var exit_speed := float(plan.get("exit_speed", 0.0))
		p.velocity = inw * exit_speed
		if p.get("_move_speed") != null:
			p.set("_move_speed", exit_speed)
			if exit_speed > 0.0:
				p.set("_move_dir", inw)
		p.apply_floor_snap()
		state = S.IDLE
		_tail = float(plan.get("handover", 0.0)) - t
		if _tail <= 0.0:
			_tail = -1.0
			_stop_clip()
		_cooldown = float((cfg.get("auto_vault", {}) as Dictionary).get("cooldown", 0.6))
		if _done.is_valid():
			var d := _done
			_done = Callable()
			d.call()
		finished.emit(k)


	func _release_body() -> void:
		p.collision_mask = _saved_mask
		p.reset_physics_interpolation()


	func _abort() -> void:
		_release_body()
		_stop_clip()
		state = S.IDLE
		_tail = -1.0
		_done = Callable()


	# -- triggers --------------------------------------------------------------------------------------------

	func _refresh_settings() -> void:
		if _settings_age < 2.0:
			return
		_settings_age = 0.0
		var v: Variant = SettingsStore.get_value("auto_vault")
		auto_vault = bool(v) if v != null else true


	## Sprinting into a vaultable obstacle vaults it (setting "auto_vault").
	func _try_auto_vault(move_input: Vector3) -> void:
		var av: Dictionary = cfg.get("auto_vault", {})
		var spd := _num(&"_move_speed")
		if spd < float(av.get("min_speed", 4.5)) or move_input.length() < 0.3:
			return
		_refresh_settings()
		if not auto_vault or not bool(av.get("enabled", true)) or not can_start():
			return
		var md: Variant = p.get("_move_dir")
		var dir: Vector3 = md if md is Vector3 else facing_dir()
		if move_input.normalized().dot(dir) < float(av.get("min_align", 0.7)):
			return
		var space := _space()
		if space == null:
			return
		var reach := clampf(spd * float(av.get("reach_per_speed", 0.25)), float(av.get("reach_min", 0.9)), float(av.get("reach_max", 1.6)))
		var res := T.probe(space, p.global_position, dir, _exclude(), false, reach, cfg)
		if res["kind"] == VAULT:
			begin(res, spd)


	## The jump button: mantles / grabs a ledge instead of jumping when one is in reach, or climbs while hanging.
	## Returns true when the press was consumed.
	func on_jump_pressed() -> bool:
		if state == S.HANG:
			request_climb()
			return true
		if state != S.IDLE or not can_start():
			return false
		var space := _space()
		if space == null:
			return false
		var res := T.probe(space, p.global_position, facing_dir(), _exclude(), true, -1.0, cfg)
		var k: StringName = res["kind"]
		if k == NONE or float(res["dist"]) > float((cfg["probe"] as Dictionary)["button_range"]):
			return false
		if k == VAULT and _num(&"_move_speed") < 1.0:
			return false
		return begin(res, _num(&"_move_speed"))


	## Interaction provider: a "Vault" / "Climb" candidate when facing a valid obstacle within button range.
	func candidates(player_pos: Vector3, facing: Vector3) -> Array:
		if p == null or not is_instance_valid(p):
			return []
		if state == S.HANG:
			return [{"id": "traversal/pull_up", "pos": player_pos, "verb": "Climb", "target": "", "priority": 5, "range": 4.0,
				"interact": Callable(self, "_ctx_climb")}]
		if state != S.IDLE or not can_start():
			return []
		var space := _space()
		if space == null:
			return []
		var f := Vector3(facing.x, 0.0, facing.z)
		if f.length_squared() < 0.0001:
			return []
		f = f.normalized()
		var frame := Engine.get_physics_frames()
		if frame - _cache_frame > 2 or _cache_feet.distance_squared_to(player_pos) > 0.0004 or _cache_dir.dot(f) < 0.995:
			_cache_frame = frame
			_cache_feet = player_pos
			_cache_dir = f
			_cache_res = T.probe(space, player_pos, f, _exclude(), true, -1.0, cfg)
		var res := _cache_res
		var k: StringName = res["kind"]
		if k == NONE:
			return []
		var rng := float((cfg["probe"] as Dictionary)["button_range"])
		if float(res["dist"]) > rng:
			return []
		var face: Vector3 = res["face_c"]
		face.y = player_pos.y
		return [{"id": "traversal/%s" % String(k), "pos": face, "verb": T.verb_for(k), "target": "", "priority": 0,
			"range": rng + 0.02, "interact": Callable(self, "_ctx_run").bind(f)}]


	func _ctx_run(_player: Node, dir: Vector3) -> void:
		var space := _space()
		if space == null:
			return
		var res := T.probe(space, p.global_position, dir, _exclude(), true, -1.0, cfg)
		begin(res, _num(&"_move_speed"))


	func _ctx_climb(_player: Node) -> void:
		request_climb()


	# -- ladders ---------------------------------------------------------------------------------------------

	## Climbs from the body's position to `dest` over time along a ladder at `ladder_at` (global). `done` runs
	## when the move ends. Returns false when the body cannot start now (the caller may teleport instead).
	func begin_ladder(ladder_at: Vector3, dest: Vector3, to_top: bool, done := Callable()) -> bool:
		if not can_start():
			return false
		var lc: Dictionary = cfg["ladder"]
		var s := p.global_position
		var dist := absf(dest.y - s.y)
		var d := maxf(dist / float(lc["speed"]), float(lc["min_time"]))
		var to_ladder := Vector3(ladder_at.x - s.x, 0.0, ladder_at.z - s.z)
		var inward := to_ladder.normalized() if to_ladder.length() > 0.05 else facing_dir()
		var clip := String(lc["up_clip"]) if to_top else String(lc["down_clip"])
		plan = {"kind": &"ladder", "shape": "ladder", "start": s, "at": Vector3(ladder_at.x, s.y, ladder_at.z), "dest": dest,
			"a": float(lc["align_time"]), "d": d, "e": float(lc["exit_time"]), "inward": inward, "rate": 1.0,
			"duration": float(lc["align_time"]) + d + float(lc["exit_time"]), "handover": 0.0, "exit_speed": 0.0,
			"end": dest, "top_y": dest.y}
		kind = &"ladder"
		_enter_move(clip, float(lc["speed"]) / float(lc["clip_speed"]))
		_done = done
		started.emit(&"ladder")
		return true


	# -- stair step-up ---------------------------------------------------------------------------------------

	## Called by the Player before move_and_slide while grounded and moving. Lifts the body onto a small edge
	## ahead (<= max_height) and eases the camera and model down so the step is not a pop. Returns the height.
	func step_assist(delta: float, move_dir: Vector3, speed: float) -> float:
		var st: Dictionary = cfg["step"]
		if state != S.IDLE or _step_cooldown > 0.0 or speed < float(st["min_speed"]) or not p.is_on_floor():
			return 0.0
		var space := _space()
		if space == null:
			return 0.0
		var reach := 0.35 + speed * delta + 0.06
		var h := T.step_height(space, p.global_position, move_dir, reach, _exclude(), cfg)
		if h <= 0.0:
			return 0.0
		p.global_position.y += h + 0.005
		_step_cooldown = float(st["cooldown"])
		var pivot: Variant = p.get("_pivot")
		if pivot is Node3D:
			(pivot as Node3D).position.y -= h
		_step_visual += h
		_apply_step_visual()
		return h


	func _apply_step_visual() -> void:
		var model: Variant = p.get("_model")
		if model is Node3D and p.get("_mount") == null:
			(model as Node3D).position.y = -_step_visual


	func _decay_step_visual(delta: float) -> void:
		if _step_visual <= 0.0:
			return
		_step_visual = maxf(_step_visual - maxf(_step_visual, 0.05) * float((cfg["step"] as Dictionary)["camera_recover"]) * delta, 0.0)
		_apply_step_visual()
