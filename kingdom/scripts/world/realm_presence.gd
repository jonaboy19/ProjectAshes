extends Node3D
## The realm simulation made visible (docs/design/SIM_HIERARCHY.md "Presentation LOD").
##   Strongholds  compact keeps from existing town/region pieces, faction banners, a few guards.
##   Camps        campfire + tents + one prop per finished structure, for the player's camps.
##   War Room     a map table in the guild hall interior that opens GameMenu "realm".
##   Live battles two small squads while a campaign battle is pending near the player.
## Cost model: static geometry is MultiMesh cells (40 m) with visibility ranges; guards exist only
## within GUARD_IN metres of the player; ownership / camps are polled once per game hour and the
## guards / table / battle on a 2 s Timer. Nothing here runs per frame.

const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
const CasterSpawns := preload("res://scripts/combat/caster_spawns.gd")
const RealmEncounters := preload("res://scripts/world/realm_encounters.gd")
const DistanceCull := preload("res://scripts/core/distance_cull.gd")
const REGION := "res://assets/generated/region/"
const CELL := 40.0
const KEEP_CULL := 600.0
const SMALL_CULL := 180.0
const GUARD_IN := 200.0
const GUARD_OUT := 260.0
const BATTLE_START := 220.0
const BATTLE_END := 300.0
## Eight heraldic tinctures; a faction id hashes into one of them.
const PALETTE := [Color("b3261e"), Color("2f5fb3"), Color("2e8b57"), Color("d4a017"),
	Color("6a3d9a"), Color("e07b1a"), Color("1f8a8a"), Color("d8d2c0")]
const CHOKE_KINDS := ["bridge", "fort", "watchfort", "rift_outpost", "rift", "waystation"]
## Camp structure kind -> [asset, scale]. Assets: BUILDINGS keys, or a full path for region GLBs.
const CAMP_PROPS := {
	"tent": [REGION + "ruins/bandit_tent.glb", 1.0], "campfire": [REGION + "ruins/campfire.glb", 0.8],
	"palisade": [REGION + "ruins/bandit_palisade.glb", 1.4], "watchtower": ["watchtower", 1.0],
	"well": ["well", 1.0], "farm_plot": ["garden_plot", 1.6], "woodcutter": ["woodpile", 1.0],
	"bakery": ["produce_table", 1.3], "smithy": ["anvil_stump", 1.4], "stable": ["hay", 1.5],
	"warehouse": ["crate_stack", 1.4], "market_stall": ["market_stall_red", 1.0],
	"barracks": ["weapon_rack", 1.3],
}

var hud: Node
var _meshes := {}          # asset key -> Mesh (null cached too)
var _banner_meshes := {}   # owner id -> ArrayMesh (wall_banner with the faction cloth)
var _strong: Array = []    # {id, name, pos, root, banners: [MultiMeshInstance3D], guards: [[Vector3, yaw]], live: [Node3D], owner}
var _camp_roots := {}      # camp id -> {root, sig}
var _map_tex: ImageTexture
var _focus := Vector2.INF   # where the stronghold in _build_one actually stands
var _battle := {}          # {id, att, def, att0, def0}
var _timer: Timer
var encounters: Node       # realm_encounters.gd: NPCs walk up with the realm's news


func setup(p_hud: Node) -> void:
	hud = p_hud
	# In-world realm events (call-ups, scouts, offers) and the village drill yard.
	encounters = RealmEncounters.new()
	encounters.setup(p_hud)
	add_child(encounters)
	# Job work spots (scripts/realm/work.gd): idle cost is one 2 s Timer.
	var spots: Node3D = preload("res://scripts/world/work_spots.gd").new()
	spots.setup(p_hud)
	add_child(spots)


func _ready() -> void:
	name = "RealmPresence"
	if _mod("strongholds") == null:
		return
	_build_strongholds()
	_refresh_camps()
	WorldSim.hour_changed.connect(_on_hour)
	_timer = Timer.new()
	_timer.wait_time = 2.0
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()


func _mod(mod_name: String) -> Variant:
	var hub: Variant = Life.get("realm")
	return hub.mod(mod_name) if hub != null else null


func _on_hour(_h: int) -> void:
	_refresh_owners()
	_refresh_camps()
	_check_battle()


func _on_tick() -> void:
	_refresh_guards()
	_check_battle()
	_check_war_table()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


# --- helpers ----------------------------------------------------------------------------

func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh = null
	if key.begins_with("res://"):
		m = Assets.merged_mesh(key)
	elif Assets.BUILDINGS.has(key):
		m = Assets.building_mesh(key)
	_meshes[key] = m
	return m


func _color_of(who: String) -> Color:
	if who == "independent" or who == "":
		return Color("8a8a84")
	if who == "player":
		return Color("e0b040")
	return PALETTE[absi(hash(who)) % PALETTE.size()]


## Shared per-faction cloth: the wall_banner mesh with its cloth surface tinted (one material and
## one mesh per faction, however many strongholds they hold).
func _banner_mesh(who: String) -> Mesh:
	if _banner_meshes.has(who):
		return _banner_meshes[who]
	var src := _mesh("wall_banner") as ArrayMesh
	if src == null:
		return null
	var mesh := src.duplicate() as ArrayMesh
	var base := mesh.surface_get_material(0)
	var mat: StandardMaterial3D = (base.duplicate() as StandardMaterial3D) if base is StandardMaterial3D else StandardMaterial3D.new()
	mat.albedo_color = _color_of(who)
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	_banner_meshes[who] = mesh
	return mesh


## A thin mast, foot at the origin (built once, shared by every stronghold).
func _pole() -> Mesh:
	if _meshes.has("__pole"):
		return _meshes["__pole"]
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.1
	cyl.height = 7.5
	cyl.radial_segments = 6
	cyl.rings = 1
	var arrays := cyl.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += 3.75
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, Assets.flat_material(Color("3d2f22")))
	_meshes["__pole"] = am
	return am


func _xf(c: Vector2, yaw: float, local: Vector2, ry := 0.0, sc := 1.0, dy := 0.0, sink := 0.08) -> Transform3D:
	var off := Basis(Vector3.UP, yaw) * Vector3(local.x, 0.0, local.y)
	var x := c.x + off.x
	var z := c.y + off.z
	return Transform3D(Basis(Vector3.UP, yaw + ry).scaled(Vector3.ONE * sc), Vector3(x, WorldGen.height(x, z) - sink + dy, z))


## Yaw that lays a mesh running along its local x onto direction d.
static func _along(d: Vector2) -> float:
	return atan2(d.x, d.y) + PI * 0.5


static func _slope(p: Vector2) -> float:
	var e := 3.0
	var dx := WorldGen.height(p.x + e, p.y) - WorldGen.height(p.x - e, p.y)
	var dz := WorldGen.height(p.x, p.y + e) - WorldGen.height(p.x, p.y - e)
	return Vector2(dx, dz).length() / (2.0 * e)


func _batch_into(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], cull: float, shadow := true) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	if mesh == null or xforms.is_empty():
		return out
	var groups := {}
	for t: Transform3D in xforms:
		var k := Vector2i(floori(t.origin.x / CELL), floori(t.origin.z / CELL))
		if not groups.has(k):
			groups[k] = []
		(groups[k] as Array).append(t)
	for k: Vector2i in groups:
		var list: Array = groups[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = cull
		mmi.visibility_range_end_margin = cull * 0.08
		if not shadow:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
		out.append(mmi)
	return out


func _add(big: Dictionary, mesh: Mesh, t: Transform3D) -> void:
	if mesh == null:
		return
	if not big.has(mesh):
		big[mesh] = []
	(big[mesh] as Array).append(t)


func _road_at(p: Vector2) -> Dictionary:
	var best := {"dist": INF, "pt": p, "dir": Vector2(0, 1), "width": 4.5}
	for e: Vector2i in WorldGen.roads:
		var a: Vector2 = WorldGen.settlements[e.x]["pos"]
		var b: Vector2 = WorldGen.settlements[e.y]["pos"]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < float(best["dist"]):
			best = {"dist": d, "pt": q, "dir": (b - a).normalized(), "width": float(WorldGen.ROAD_WIDTH[WorldGen.road_tier(e.x, e.y)])}
	return best


## Dry, level ground clear of settlements, camps and other sites (and, if asked, of the road).
func _spot_ok(c: Vector2, r: float, road_w: float, avoid_road: bool, loose := false) -> bool:
	if absf(c.x) > WorldGen.WORLD_HALF - 120.0 or absf(c.y) > WorldGen.WORLD_HALF - 120.0:
		return false
	if WorldGen.near_water(c.x, c.y, r + 3.0):
		return false
	for s in WorldGen.settlements:
		if c.distance_to(s["pos"]) < float(s["radius"]) * 1.15 + r + (2.0 if loose else 8.0):
			return false
	for g in WorldGen.camp_grounds:
		if c.distance_to(g["pos"]) < float(g["radius"]) * 1.6 + r:
			return false
	for site in WorldGen.sites:
		if c.distance_to(site["pos"]) < (r + 3.0 if loose else maxf(float(site["clear"]), 10.0) + r + 4.0):
			return false
	if _slope(c) > (0.7 if loose else 0.35):
		return false
	if avoid_road and WorldGen.road_distance(c.x, c.y) < r + road_w * 0.5 + 2.0:
		return false
	return true


# --- strongholds ------------------------------------------------------------------------

func _build_strongholds() -> void:
	var sm: Variant = _mod("strongholds")
	for s: Dictionary in sm.strongholds():
		var entry := _build_one(s)
		if not entry.is_empty():
			_strong.append(entry)


func _site_near(p: Vector2, kind: String) -> Dictionary:
	if kind in ["pass", "junction"]:
		return {}
	for site in WorldGen.sites:
		if String(site["kind"]) in CHOKE_KINDS and p.distance_to(site["pos"]) < 45.0:
			return site
	return {}


func _build_one(s: Dictionary) -> Dictionary:
	var p: Vector2 = s["pos"]
	var root := Node3D.new()
	root.name = "Stronghold_%d" % int(s["id"])
	add_child(root)
	var guards: Array = []
	var masts: Array[Transform3D] = []
	var flags: Array[Transform3D] = []
	var big := {}
	var towers: Array = []
	var site := _site_near(p, String(s["kind"]))
	_focus = p
	var guard_n := 2 + absi(hash([s["id"], "g"])) % 3
	if not site.is_empty():
		# The region already stands a keep / bridge here: add only the flag and the garrison.
		_focus = site["pos"]
		_dress_site(site, masts, flags, guards, guard_n)
	elif not _place_keep(s, big, masts, flags, guards, towers, guard_n):
		root.queue_free()
		return {}
	for mesh: Mesh in big:
		var list: Array[Transform3D] = []
		list.assign(big[mesh])
		_batch_into(root, mesh, list, KEEP_CULL)
	_batch_into(root, _pole(), masts, SMALL_CULL, false)
	var banners := _batch_into(root, _banner_mesh(String(s["owner"])), flags, SMALL_CULL, false)
	for t: Array in towers:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var ext: float = t[1]
		box.size = Vector3(ext, 9.0, ext)
		cs.shape = box
		var tp: Vector2 = t[0]
		body.position = Vector3(tp.x, WorldGen.height(tp.x, tp.y) + 4.5, tp.y)
		body.add_child(cs)
		root.add_child(body)
	return {"id": int(s["id"]), "name": String(s["name"]), "pos": _focus, "root": root, "banners": banners,
		"guards": guards, "live": [], "owner": String(s["owner"])}


## Nearest spot on any road edge within 360 m of `start` where a gate (both sides clear) or a keep of
## `radius` fits. {} if none.
func _search_road_edges(start: Vector2, gate_design: bool, radius: float, loose: bool) -> Dictionary:
	var best := {}
	var best_d := INF
	for e: Vector2i in WorldGen.roads:
		var pa: Vector2 = WorldGen.settlements[e.x]["pos"]
		var pb: Vector2 = WorldGen.settlements[e.y]["pos"]
		var seg_len := pa.distance_to(pb)
		var sdir := (pb - pa) / maxf(seg_len, 0.001)
		var sperp := Vector2(-sdir.y, sdir.x)
		var rwe := float(WorldGen.ROAD_WIDTH[WorldGen.road_tier(e.x, e.y)])
		var t0 := 0.0
		while t0 <= seg_len:
			var q := pa + sdir * t0
			t0 += 12.0
			var dd := q.distance_to(start)
			if dd > 360.0 or dd >= best_d:
				continue
			if gate_design:
				var gr := 3.0 if loose else 6.0
				if _spot_ok(q + sperp * (rwe * 0.5 + 5.0), gr, rwe, false, loose) and _spot_ok(q - sperp * (rwe * 0.5 + 5.0), gr, rwe, false, loose):
					best_d = dd
					best = {"centre": q, "dir": sdir, "perp": sperp, "gate_dir": sdir, "rw": rwe}
			else:
				for side in [1, -1]:
					var c2: Vector2 = q + sperp * (rwe * 0.5 + radius + 4.0) * float(side)
					if _spot_ok(c2, radius if not loose else radius * 0.7, rwe, true, loose):
						best_d = dd
						best = {"centre": c2, "dir": sdir, "perp": sperp, "gate_dir": -sperp * float(side), "rw": rwe}
						break
	return best


## Flag + garrison for a stronghold that shares a region site (bridge / fort / outpost).
func _dress_site(site: Dictionary, masts: Array[Transform3D], flags: Array[Transform3D], guards: Array, guard_n: int) -> void:
	var sp: Vector2 = site["pos"]
	var yaw: float = site["yaw"]
	var front := Vector2(sin(yaw), cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var clear := maxf(float(site["clear"]), 14.0)
	var mast_at := sp + right * (clear * 0.4) + front * (clear * 0.3)
	var gp: Array[Vector2] = []
	var facing := atan2(front.x, front.y)
	if String(site["kind"]) == "bridge":
		var half := float(site.get("span", 20.0)) * 0.5
		mast_at = sp + right * 3.4 + front * (half - 2.0)
		gp = [sp + front * (half + 1.5) + right * 1.2, sp - front * (half + 1.5) - right * 1.2,
			sp + front * (half + 3.5) - right * 1.4, sp - front * (half + 3.5) + right * 1.4]
	else:
		gp = [sp + front * (clear * 0.7) + right * 3.0, sp + front * (clear * 0.7) - right * 3.0,
			sp + front * (clear * 0.45) + right * 8.0, sp + front * (clear * 0.45) - right * 8.0]
	masts.append(_xf(mast_at, 0.0, Vector2.ZERO, 0.0, 1.0, 0.0, 0.05))
	flags.append(_xf(mast_at + right * 0.66, 0.0, Vector2.ZERO, facing, 1.0, 5.3, 0.0))
	for i in guard_n:
		var g := gp[i]
		var gy := WorldGen.height(g.x, g.y)
		if String(site["kind"]) == "bridge":
			gy = maxf(gy, float(site.get("deck", gy)))
		guards.append([Vector3(g.x, gy, g.y), facing + (0.0 if i % 2 == 0 else PI)])


## Lays out one new stronghold by kind. Returns false when no clear ground was found nearby.
func _place_keep(s: Dictionary, big: Dictionary, masts: Array[Transform3D], flags: Array[Transform3D], guards: Array, towers: Array, guard_n: int) -> bool:
	var kind := String(s["kind"])
	var start: Vector2 = s["pos"]
	var road := _road_at(start)
	var gate_design := kind in ["bridge", "junction"]
	var radius := 4.5 if gate_design else (20.0 if kind in ["fort", "watchfort"] else 11.5)
	var rw := float(road["width"])
	var centre := Vector2.INF
	var dir: Vector2 = road["dir"]
	var perp := Vector2(-dir.y, dir.x)
	var gate_dir := dir
	for d in range(0, 241, 15):
		for sgn in [1, -1]:
			var rd := _road_at(start + dir * float(d * sgn))
			if float(rd["dist"]) > 90.0:
				continue
			var q: Vector2 = rd["pt"]
			var qdir: Vector2 = rd["dir"]
			var qperp := Vector2(-qdir.y, qdir.x)
			rw = float(rd["width"])
			if gate_design:
				if _spot_ok(q + qperp * (rw * 0.5 + 5.0), 6.0, rw, false) and _spot_ok(q - qperp * (rw * 0.5 + 5.0), 6.0, rw, false):
					centre = q
			else:
				for side in [1, -1]:
					var c: Vector2 = q + qperp * (rw * 0.5 + radius + 4.0) * float(side)
					if _spot_ok(c, radius, rw, true):
						centre = c
						gate_dir = -qperp * float(side)
						break
			if centre != Vector2.INF:
				dir = qdir
				perp = qperp
				break
		if centre != Vector2.INF:
			break
	if centre == Vector2.INF:
		# The candidate can sit beside a settlement, off every road (junctions are offset from the town):
		# walk the road edges themselves for the nearest ground the keep or gate fits on, then, failing
		# that, for ground that is merely dry and not too steep.
		for loose in [false, true]:
			var found := _search_road_edges(start, gate_design, radius, loose)
			if not found.is_empty():
				centre = found["centre"]
				dir = found["dir"]
				perp = found["perp"]
				gate_dir = found["gate_dir"]
				rw = float(found["rw"])
				break
	if centre == Vector2.INF:
		return false
	_focus = centre
	var yaw := atan2(gate_dir.x, gate_dir.y)   # local +z = the way the gate faces (road side)
	var tower := _mesh("wall_tower")
	if gate_design:
		var wall := _mesh("wall")
		var off := rw * 0.5 + 5.0
		for sgn: float in [1.0, -1.0]:
			_add(big, tower, _xf(centre + perp * sgn * off, 0.0, Vector2.ZERO, 0.0, 0.8, 0.0, 0.3))
			towers.append([centre + perp * sgn * off, 5.0])
			for j in 2:
				var wc := centre + perp * sgn * (off + 2.9 + 3.6 + j * 6.9)
				_add(big, wall, _xf(wc, 0.0, Vector2.ZERO, _along(perp), 0.85, 0.0, 0.2))
			for fs: float in [1.0, -1.0]:
				flags.append(_xf(centre + perp * sgn * off + dir * fs * 3.0, 0.0, Vector2.ZERO, atan2(dir.x * fs, dir.y * fs), 1.0, 4.5, 0.0))
		if kind == "junction":
			# A toll booth, crates and a weapon rack by the gate so a crossing reads as a garrisoned post.
			var booth := _mesh(REGION + "road/toll_booth.glb")
			var bp := centre + perp * (off - 0.2) + dir * 7.0
			_add(big, booth, _xf(bp, 0.0, Vector2.ZERO, atan2(-perp.x, -perp.y), 1.0, 0.0, 0.1))
			towers.append([bp, 3.2])
			_add(big, _mesh("crate_stack"), _xf(centre - perp * (off - 0.6) - dir * 6.0, 0.0, Vector2.ZERO, 0.5, 1.0, 0.0, 0.05))
			_add(big, _mesh("weapon_rack"), _xf(centre + perp * (off - 0.6) - dir * 6.0, 0.0, Vector2.ZERO, atan2(-perp.x, -perp.y), 1.0, 0.0, 0.05))
		var mast_at := centre + perp * (off + 2.9 + 3.6 + 13.8)
		masts.append(_xf(mast_at, 0.0, Vector2.ZERO, 0.0, 1.0, 0.0, 0.05))
		flags.append(_xf(mast_at + perp * 0.66, 0.0, Vector2.ZERO, atan2(dir.x, dir.y), 1.0, 5.3, 0.0))
		for i in guard_n:
			var side := 1.0 if i % 2 == 0 else -1.0
			var g := centre + perp * side * (rw * 0.5 + 1.6) + dir * float(i / 2) * 3.0
			guards.append([Vector3(g.x, WorldGen.height(g.x, g.y), g.y), atan2(-perp.x * side, -perp.y * side)])
		return true
	var is_fort := kind in ["fort", "watchfort"]
	var pal := _mesh(REGION + "ruins/bandit_palisade.glb")
	var ring_r := radius - 1.0
	var n := int(ceil(TAU * ring_r / 3.9))
	var gate_a := atan2(gate_dir.y, gate_dir.x)
	for i in n:
		var a := TAU * i / n
		if absf(wrapf(a - gate_a, -PI, PI)) < 3.4 / ring_r:
			continue
		var pp := centre + Vector2(cos(a), sin(a)) * ring_r
		_add(big, pal, _xf(pp, 0.0, Vector2.ZERO, _along(Vector2(-sin(a), cos(a))), 1.0, 0.0, 0.25))
	var perp_g := Vector2(-gate_dir.y, gate_dir.x)
	if is_fort:
		_add(big, _mesh("castle"), _xf(centre, yaw, Vector2(0, -3.0), PI, 0.5, 0.0, 0.3))
		towers.append([centre - gate_dir * 3.0, 13.0])
		for sgn: float in [1.0, -1.0]:
			var tp := centre + gate_dir * (ring_r - 0.5) + perp_g * sgn * 4.6
			_add(big, tower, _xf(tp, yaw, Vector2.ZERO, 0.0, 0.55, 0.0, 0.3))
			towers.append([tp, 4.0])
			flags.append(_xf(tp + gate_dir * 2.1, 0.0, Vector2.ZERO, atan2(gate_dir.x, gate_dir.y), 1.0, 3.2, 0.0))
	else:
		_add(big, _mesh("watchtower"), _xf(centre, yaw, Vector2(0, -3.5), PI, 1.0, 0.0, 0.3))
		towers.append([centre - gate_dir * 3.5, 6.0])
		_add(big, _mesh(REGION + "ruins/bandit_lean_to.glb"), _xf(centre, yaw, Vector2(5.5, -1.5), -PI * 0.5, 1.0, 0.0, 0.1))
		_add(big, _mesh("weapon_rack"), _xf(centre, yaw, Vector2(-5.5, 0.5), PI * 0.5, 1.0, 0.0, 0.05))
		_add(big, _mesh("crate_stack"), _xf(centre, yaw, Vector2(-5.0, -4.5), 0.4, 1.0, 0.0, 0.05))
		_add(big, _mesh(REGION + "ruins/campfire.glb"), _xf(centre, yaw, Vector2(0.5, 3.0), 0.0, 0.7, 0.0, 0.05))
	var mast_at2 := centre + gate_dir * (ring_r - 3.5) + perp_g * (7.5 if is_fort else 4.5)
	masts.append(_xf(mast_at2, 0.0, Vector2.ZERO, 0.0, 1.0, 0.0, 0.05))
	flags.append(_xf(mast_at2 + perp_g * 0.66, 0.0, Vector2.ZERO, atan2(gate_dir.x, gate_dir.y), 1.0, 5.3, 0.0))
	for i in guard_n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var g := centre + gate_dir * (ring_r - 2.0 - float(i / 2) * 2.5) + perp_g * side * 2.4
		guards.append([Vector3(g.x, WorldGen.height(g.x, g.y), g.y), atan2(gate_dir.x, gate_dir.y)])
	return true


## Hourly: hand a stronghold's banners to its new owner (a mesh swap on a few MultiMeshes).
func _refresh_owners() -> void:
	var sm: Variant = _mod("strongholds")
	if sm == null:
		return
	for e: Dictionary in _strong:
		var s: Dictionary = sm.stronghold(int(e["id"]))
		if s.is_empty() or String(s["owner"]) == String(e["owner"]):
			continue
		e["owner"] = String(s["owner"])
		var bm := _banner_mesh(String(e["owner"]))
		for mmi: MultiMeshInstance3D in e["banners"]:
			if is_instance_valid(mmi) and bm != null:
				mmi.multimesh.mesh = bm


## Guards exist only near the player: spawned inside GUARD_IN, freed past GUARD_OUT.
func _refresh_guards() -> void:
	var pl := _player()
	if pl == null:
		return
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	for e: Dictionary in _strong:
		var d := pp.distance_to(e["pos"])
		var live: Array = e["live"]
		if d < GUARD_IN and live.is_empty():
			for g: Array in e["guards"]:
				var guard := Assets.character("Guard", 1.8, [])
				if guard == null:
					continue
				(e["root"] as Node3D).add_child(guard)
				guard.global_position = g[0]
				guard.rotation.y = float(g[1])
				var ap := Assets.animation_player(guard)
				if ap:
					ap.play("Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0])
				DistanceCull.attach(guard, 80.0, ap)     # perf round 2: full 7-12k tri guard only up close
				live.append(guard)
		elif d > GUARD_OUT and not live.is_empty():
			for g: Node3D in live:
				if is_instance_valid(g):
					g.queue_free()
			live.clear()


## Screenshot hook: the stronghold nearest a world point, or {}.
func nearest_stronghold(p: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for e: Dictionary in _strong:
		var d := p.distance_to(e["pos"])
		if d < bd:
			bd = d
			best = e
	return best


## Screenshot hook: run the guard LOD now (the player has just been teleported).
func refresh_now() -> void:
	_refresh_guards()


# --- camps ------------------------------------------------------------------------------

func _refresh_camps() -> void:
	var cm: Variant = _mod("camps")
	if cm == null:
		return
	for c: Dictionary in cm.camps():
		if String(c.get("src", "")) == "construction":
			continue   # the player's own holdings are drawn by construction_view.gd
		var id := int(c["id"])
		var sts: Array = c.get("structures", [])
		var done := 0
		for st: Dictionary in sts:
			if int(st["hours_left"]) <= 0:
				done += 1
		var sig := "%d:%d" % [sts.size(), done]
		var rec: Dictionary = _camp_roots.get(id, {})
		if not rec.is_empty() and rec["sig"] == sig:
			continue
		if not rec.is_empty():
			(rec["root"] as Node3D).queue_free()
		var root := Node3D.new()
		root.name = "Camp_%d" % id
		add_child(root)
		_build_camp(root, c)
		_camp_roots[id] = {"root": root, "sig": sig}


func _build_camp(root: Node3D, c: Dictionary) -> void:
	var cp := Vector2(float(c["pos"][0]), float(c["pos"][1]))
	var by_mesh := {}
	var base_yaw := float(absi(hash(c["id"])) % 628) / 100.0
	_add(by_mesh, _mesh(CAMP_PROPS["campfire"][0]), _xf(cp, base_yaw, Vector2.ZERO, 0.0, 0.8, 0.0, 0.05))
	for i in 3:
		var a := base_yaw + TAU * i / 3.0
		_add(by_mesh, _mesh(REGION + "ruins/bandit_tent.glb"), _xf(cp, 0.0, Vector2(cos(a), sin(a)) * 6.0, -a + PI * 0.5, 0.9, 0.0, 0.1))
	var la := base_yaw + 3.6
	_add(by_mesh, _mesh(REGION + "ruins/bandit_lean_to.glb"), _xf(cp, 0.0, Vector2(cos(la), sin(la)) * 4.5, base_yaw, 0.8, 0.0, 0.1))
	var idx := 0
	for st: Dictionary in c.get("structures", []):
		idx += 1
		var kind := String(st["kind"])
		if int(st["hours_left"]) > 0 or not CAMP_PROPS.has(kind) or kind in ["tent", "campfire"] or String(st.get("src", "")) == "construction":
			continue
		var sp := Vector2(float(st["pos"][0]), float(st["pos"][1]))
		if sp == Vector2.ZERO or sp.distance_to(cp) > 60.0:
			var a2 := idx * 2.4 + base_yaw
			sp = cp + Vector2(cos(a2), sin(a2)) * (11.0 + 2.2 * sqrt(float(idx)))
		var spec: Array = CAMP_PROPS[kind]
		_add(by_mesh, _mesh(String(spec[0])), _xf(sp, 0.0, Vector2.ZERO, atan2(cp.x - sp.x, cp.y - sp.y), float(spec[1]), 0.0, 0.05))
	for mesh: Mesh in by_mesh:
		var list: Array[Transform3D] = []
		list.assign(by_mesh[mesh])
		_batch_into(root, mesh, list, 220.0, false)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.6, 0.3)
	fire.light_energy = 1.2
	fire.omni_range = 10.0
	fire.visibility_range_end = 120.0
	root.add_child(fire)
	fire.global_position = Vector3(cp.x, WorldGen.height(cp.x, cp.y) + 1.3, cp.y)


# --- War Room table ---------------------------------------------------------------------

## The guild hall stands in for the lord's hall: while the player is inside it, put the table in.
func _check_war_table() -> void:
	var door := InteriorDoor.active
	if door == null or door.interior == null or not is_instance_valid(door.interior):
		return
	var room := door.interior
	if not String(room.scene_file_path).contains("guild_interior") or room.get_node_or_null("WarTable") != null:
		return
	add_war_table(room, Vector3(3.6, 0.0, -0.4))


## A council table with a painted map of the realm; using it opens the Realm tab (War Room).
func add_war_table(room: Node3D, at: Vector3) -> Station:
	var st := Station.new("War Room", "Study the map", _war_menu)
	st.name = "WarTable"
	st.on_use = func(hud: Node) -> void:
		# the War Room table opens the war map directly, in war-table style (docs/design/WAR_COMMAND_RULEBOOK.md §2)
		var wm: Control = load("res://scripts/ui/war/war_map.gd").open_modal(hud, Life.realm)
		wm.call("set_style", 2)
	room.add_child(st)
	st.position = at
	var table := MeshInstance3D.new()
	table.mesh = _mesh("produce_table")
	table.scale = Vector3(1.7, 1.0, 1.6)
	st.add_child(table)
	var map := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 1.9)
	map.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _map_texture()
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	map.material_override = mat
	map.rotation.x = -PI * 0.5
	map.position = Vector3(0, 1.13, 0)
	st.add_child(map)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.1, 2.2)
	cs.shape = box
	body.position = Vector3(0, 0.55, 0)
	body.add_child(cs)
	st.add_child(body)
	return st


func _war_menu() -> Dictionary:
	return {"title": "War Room", "body": "Maps of the realm are pinned under a lamp: strongholds, camps, armies and roads.",
		"options": [["Study the campaign map", func() -> String:
			if hud and hud.has_method("close_menu"):
				hud.close_menu()
			GameMenu.open(hud, "realm")
			return ""]]}


func _map_texture() -> ImageTexture:
	if _map_tex != null:
		return _map_tex
	var n := 144           # 96 for the 8 km world: the same ~85 m per pixel at 12 km
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var half := WorldGen.WORLD_HALF
	for j in n:
		for i in n:
			var x := (float(i) / (n - 1) * 2.0 - 1.0) * half
			var z := (float(j) / (n - 1) * 2.0 - 1.0) * half
			var col: Color
			if WorldGen.is_water(x, z):
				col = Color("6f95a8")
			else:
				var h := WorldGen.height(x, z)
				col = Color("b9c48a").lerp(Color("8f8a62"), clampf(h / 60.0, 0.0, 1.0)).lerp(Color("d8d2c0"), clampf((h - 60.0) / 90.0, 0.0, 1.0))
			img.set_pixel(i, j, col)
	for s in WorldGen.settlements:
		_dot(img, s["pos"], 2, Color("2b1d14"))
	for e: Dictionary in _strong:
		_dot(img, e["pos"], 1, _color_of(String(e["owner"])))
	_map_tex = ImageTexture.create_from_image(img)
	return _map_tex


func _dot(img: Image, p: Vector2, r: int, col: Color) -> void:
	var n := img.get_width()
	var cx := int(round((p.x / WorldGen.WORLD_HALF * 0.5 + 0.5) * (n - 1)))
	var cy := int(round((p.y / WorldGen.WORLD_HALF * 0.5 + 0.5) * (n - 1)))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < n and y < n:
				img.set_pixel(x, y, col)


# --- live battles -----------------------------------------------------------------------

## Live 3D battles are paused by design (user direction): war is played on the
## map only for now, and campaign.gd auto-resolves clashes. Flip to re-enable.
const LIVE_BATTLES_ENABLED := false


func _check_battle() -> void:
	if not LIVE_BATTLES_ENABLED:
		return
	var cam: Variant = _mod("campaign")
	var pl := _player()
	if cam == null or pl == null:
		return
	var pending: Dictionary = cam.pending_live_battle()
	if pending.is_empty():
		if not _battle.is_empty():
			_free_battle()          # settled elsewhere (timeout): just clear the field
		return
	var pos: Vector2 = pending["pos"]
	var d := Vector2(pl.global_position.x, pl.global_position.z).distance_to(pos)
	if _battle.is_empty():
		if d <= BATTLE_START:
			_start_battle(pending)
		return
	if int(_battle["id"]) != int(pending["id"]):
		_free_battle()
		return
	var att := _battle["att"] as Squad
	var def := _battle["def"] as Squad
	var a_alive := att.alive() if is_instance_valid(att) else 0
	var d_alive := def.alive() if is_instance_valid(def) else 0
	if a_alive > 0 and d_alive > 0 and d <= BATTLE_END:
		return
	var a_frac := float(a_alive) / maxf(1.0, float(_battle["att0"]))
	var d_frac := float(d_alive) / maxf(1.0, float(_battle["def0"]))
	var result := {"winner": "attackers" if a_frac > d_frac else "defenders",
		"attacker_losses": clampf(1.0 - a_frac, 0.0, 1.0), "defender_losses": clampf(1.0 - d_frac, 0.0, 1.0)}
	_free_battle()
	cam.resolve_live_battle(result)


func _start_battle(pending: Dictionary) -> void:
	var pos: Vector2 = pending["pos"]
	var na := clampi(int(pending.get("attacker_strength", 40)) / 8, 4, 10)
	var nd := clampi(int(pending.get("defender_strength", 40)) / 8, 4, 10)
	var att := Squad.new().setup(1, "raider", "Barbarian", ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"])
	att.anchor = _ground(pos - Vector2(24, 0))
	att.facing = Vector3(1, 0, 0)
	att.aggro_radius = 60.0
	add_child(att)
	att.add_soldiers(na, att.anchor, CasterSpawns.mix("raid", na, int(pending["id"])))
	var def := Squad.new().setup(0, "soldier", "Knight", ["Knight_Helmet", "1H_Sword", "Round_Shield"])
	def.anchor = _ground(pos + Vector2(24, 0))
	def.facing = Vector3(-1, 0, 0)
	def.aggro_radius = 60.0
	add_child(def)
	def.add_soldiers(nd, def.anchor, CasterSpawns.mix("garrison", nd, int(pending["id"]) + 7))
	att.command(Squad.Order.CHARGE)
	def.command(Squad.Order.CHARGE)
	_battle = {"id": int(pending["id"]), "att": att, "def": def, "att0": na, "def0": nd}


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _free_battle() -> void:
	for k: String in ["att", "def"]:
		var sq := _battle.get(k) as Squad
		if is_instance_valid(sq):
			for so in sq.soldiers:
				if is_instance_valid(so):
					so.queue_free()
			sq.queue_free()
	_battle = {}
