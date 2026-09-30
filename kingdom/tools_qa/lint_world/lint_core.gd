extends RefCounted
## Headless visual-bug detector for the Rising Ashes world: builds every site's dressing exactly like the game does (no
## rendering, no screenshots) and checks every placed mesh for floating, sinking, standing in water, overlapping,
## blocking a road and for blowing its draw budget. Driven by world_lint.gd (CLI) and tests/test_world_lint.gd.
##
## A "unit" is one placed prop: the direct child of a site root (all its near-LOD meshes merged into one AABB, so a sign
## board on two posts is one thing), or ONE instance of a MultiMesh. Far-LOD meshes (visibility_range_begin > 0) are
## skipped: their LOD0 twin is checked instead.
##
## Must be loaded at runtime (load(...).new()), never named at compile time from a `-s` main script: the autoloads it
## touches do not exist yet when a `-s` script is compiled.

const CFG := preload("res://tools_qa/lint_world/lint_config.gd")
const DRESSING := "res://scripts/world/region_dressing.gd"
const SETTLE := "res://scripts/world/settlement_builder.gd"
const TOWER := "res://scripts/world/towers/tower_site.gd"
const GRID := 16.0
const SKIP_NAMES := ["Horizon", "Region1Horizon"]

var tree: SceneTree
var seed_value := 1066
var filter: Array = ["all"]
var groups: Array = []            # {id, kind, name, pos, roots, loose, builder, wet, road_ok, units, draws, draws_raw, ...}
var issues: Array = []
var allowed: Array = []
var stats := {"units": 0, "instances": 0, "ms_build": 0, "ms_lint": 0}
var untracked: Array = []        # MultiMeshes whose transforms could not be captured (builder script not in PATCH_SCRIPTS)
var _dressing: Variant = null
var _log_fn := Callable()


func log_line(s: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(s)
	else:
		print(s)


func set_logger(c: Callable) -> void:
	_log_fn = c


# =====================================================================================================================
# Driver
# =====================================================================================================================

var _orig_src := {}
var _added: Array = []
var _mesh_names := {}
var _vert_cache := {}
var _corner_cache := {}


## Rewrites (in memory) the builder scripts so MultiMesh transforms survive the dummy renderer; undone by restore().
func patch_builders() -> void:
	var re := RegEx.create_from_string("\\b([A-Za-z_][\\w\\.]*)\\.set_instance_transform\\(")
	var n := 0
	var paths: Array = CFG.PATCH_SCRIPTS.duplicate()
	for k: String in CFG.SOURCE_TWEAKS:
		if not paths.has(k):
			paths.append(k)
	for path: String in paths:
		var sc := load(path) as GDScript
		if sc == null or sc.source_code == "" or _orig_src.has(path) or sc.source_code.contains("_lint_rec_"):
			continue
		var fn := "_lint_rec_%d" % n
		var out := sc.source_code
		if path in CFG.PATCH_SCRIPTS:
			out = re.sub(out, fn + "($1, ", true)
			if out != sc.source_code:
				out += "\n\nstatic func %s(mm: MultiMesh, i: int, t: Transform3D) -> void:\n\tpreload(\"res://tools_qa/lint_world/mm_shim.gd\").rec(mm, i, t)\n" % fn
		for tw: Array in CFG.SOURCE_TWEAKS.get(path, []):
			out = out.replace(String(tw[0]), String(tw[1]))
		if out == sc.source_code:
			continue
		_orig_src[path] = sc.source_code
		sc.source_code = out
		var err := sc.reload()
		if err != OK:
			log_line("world_lint: WARNING could not patch %s (error %d); its MultiMesh props will be invisible to the linter" % [path, err])
			sc.source_code = _orig_src[path]
			sc.reload()
			_orig_src.erase(path)
		n += 1


func restore() -> void:
	for n: Node in _added:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_added.clear()
	for path: String in _orig_src:
		var sc := load(path) as GDScript
		sc.source_code = _orig_src[path]
		sc.reload()
	_orig_src.clear()


func run(p_tree: SceneTree, p_seed: int, p_filter: Array) -> void:
	tree = p_tree
	patch_builders()
	seed_value = p_seed
	filter = p_filter if not p_filter.is_empty() else ["all"]
	var t0 := Time.get_ticks_msec()
	WorldGen.setup(seed_value)
	log_line("world_lint: WorldGen.setup(%d) %d ms, %d sites, %d settlements" % [seed_value, Time.get_ticks_msec() - t0, WorldGen.sites.size(), WorldGen.settlements.size()])
	_build_groups()
	stats["ms_build"] = Time.get_ticks_msec() - t0
	log_line("world_lint: built %d groups in %d ms" % [groups.size(), stats["ms_build"]])
	var t1 := Time.get_ticks_msec()
	for g: Dictionary in groups:
		_lint_group(g)
	_lint_overlaps()
	_finish_draws()
	stats["ms_lint"] = Time.get_ticks_msec() - t1
	issues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	if int(stats.get("rocks_without_faces", 0)) > 0:
		log_line("world_lint: WARNING %d boulders had no readable mesh faces (AABB fallback used)" % int(stats["rocks_without_faces"]))
	log_line("world_lint: linted %d props (%d instances) in %d ms: %d severe, %d major, %d minor, %d allowlisted" % [
		stats["units"], stats["instances"], stats["ms_lint"], count_sev("severe"), count_sev("major"), count_sev("minor"), allowed.size()])


func count_sev(sev: String) -> int:
	var n := 0
	for i: Dictionary in issues:
		if i["severity"] == sev:
			n += 1
	return n


func severe_issues() -> Array:
	return issues.filter(func(i: Dictionary) -> bool: return i["severity"] == "severe")


func _want(kind: String) -> bool:
	return filter.has("all") or filter.has(kind)


# =====================================================================================================================
# Building the world (same entry points the game uses)
# =====================================================================================================================

func _build_groups() -> void:
	_dressing = load(DRESSING).new()
	tree.root.add_child(_dressing)
	_added.append(_dressing)
	for s: Dictionary in WorldGen.sites:
		if _want(String(s["kind"])) and _dressing._in_season(s):
			_build_site(s)
	if _want("r1look"):
		_build_look_groups(_dressing.get_node_or_null("Region1Look"), "r1look", "scripts/region1/region1_look.gd", "Cliffs_")
	if _want("vale"):
		var ed: Variant = _dressing.get_node_or_null("ExplorationDirector")
		if ed != null and ed.get("look") != null:
			_build_look_groups(ed.look, "vale", "scripts/world/vale_look.gd", "ValeCliffs_")
	if _want("caves"):
		var cv: Variant = _dressing.get_node_or_null("RegionCaves")
		if cv != null:
			cv.build_all_now()
			for id: String in cv._built:
				var n: Node3D = cv._built[id]
				var s: Dictionary = cv._sites_by_id[id]
				_add_group("caves:" + id, "caves", String(s["name"]), s["pos"], [n], [], "scripts/world/region_caves_view.gd:_build", false, false)
	var by_name := false
	for st: Dictionary in WorldGen.settlements:
		by_name = by_name or filter.has(String(st["name"]).to_lower())
	if _want("settlement") or by_name:
		var sb: Node3D = load(SETTLE).new()
		tree.root.add_child(sb)
		_added.append(sb)
		for st: Dictionary in WorldGen.settlements:
			var nm := String(st["name"])
			if filter.has("all") or filter.has("settlement") or filter.has(nm.to_lower()):
				var r: Node3D = sb._build(st)
				var g := _add_group("settlement:%s" % nm, "settlement", nm, st["pos"], [r], [], "scripts/world/settlement_builder.gd:_build", false, false)
				g["radius"] = float(st["radius"])
	if _want("tower") or _want("dungeon_tower"):
		var ts: Node3D = load(TOWER).new()
		tree.root.add_child(ts)
		_added.append(ts)
		for tid: String in ts.sites:
			var spire: Node3D = ts.sites[tid]["root"]
			var pos3: Vector3 = ts.sites[tid]["pos"]
			_add_group("tower:" + tid, "tower", "Spire " + tid, Vector2(pos3.x, pos3.z), [], [spire], "scripts/world/towers/tower_site.gd:_build_exterior", false, true)
			var camp: Node3D = ts.build_camp(tid)
			if camp != null:
				_add_group("tower:%s:camp" % tid, "tower", "Camp " + tid, Vector2(pos3.x, pos3.z), [camp], [], "scripts/world/towers/tower_site.gd:build_camp", false, true)


func _add_group(id: String, kind: String, nm: String, pos: Vector2, roots: Array, loose: Array, builder: String, wet: bool, road_ok: bool) -> Dictionary:
	var g := {"id": id, "kind": kind, "name": nm, "pos": pos, "roots": roots, "loose": loose, "builder": builder, "wet": wet or (kind in CFG.WET_SITE_KINDS),
		"road_ok": road_ok or (kind in CFG.ROAD_SITE_KINDS), "units": [], "draw_keys": {}, "draws_raw": 0, "issues": 0, "n_units": 0, "radius": 0.0}
	groups.append(g)
	return g


func _build_site(s: Dictionary) -> void:
	var root: Node3D = _dressing._build(s)
	_dressing._built[s["id"]] = root
	var builder_base := "scripts/world/region_dressing.gd"
	var kind := String(s["kind"])
	for c in root.get_children():
		if c is MultiMeshInstance3D:
			c.set_meta("lint_builder", builder_base + ":_scatter_ground")
		elif kind == "bridge":
			c.set_meta("lint_builder", builder_base + ":_build_bridge")
		else:
			c.set_meta("lint_builder", "scripts/world/region1_extras.gd:build")
	var mine: Array = []
	var rest: Array = []
	for it: Array in _dressing._queue:
		if it[0] == root:
			mine.append(it)
		else:
			rest.append(it)
	_dressing._queue = rest
	for it: Array in mine:
		var before := root.get_child_count()
		if it[2] == "part":
			var part: Array = s["parts"][it[3]]
			_dressing._build_part(root, s, part)
			for k in range(before, root.get_child_count()):
				var n := root.get_child(k)
				if k == before and n is Node3D and not (n is MeshInstance3D):
					n.set_meta("lint_builder", builder_base + ":_build_part")
					n.set_meta("lint_asset", String(part[0]))
				else:
					n.set_meta("lint_builder", builder_base + ":_base_clutter")
					n.set_meta("lint_note", "base clutter of " + String(part[0]))
		else:
			_dressing._build_light(root, s["lights"][it[3]])
	_add_group("site:%d" % int(s["id"]), kind, String(s["name"]), s["pos"], [root], [], builder_base + ":_build", bool(s.get("wet", false)), false)


## Region1Look / ValeLook: far pieces are built in _ready, near pieces per landmark on demand (built here for all).
func _build_look_groups(look: Variant, gkind: String, file: String, cliff_prefix: String) -> void:
	if look == null:
		return
	var lms: Array = look._data.get("landmarks", [])
	var loose: Array = []
	for c in look.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with(cliff_prefix):
			loose.append(c)
	if not loose.is_empty():
		_add_group(gkind + ":cliffs", gkind, gkind + " cliff rocks", Vector2.ZERO, [], loose, file + ":build_vale_cliffs" if gkind == "vale" else file + ":_build_cliffs", false, false)
	for lm: Dictionary in lms:
		var id := String(lm["id"])
		var near := Node3D.new()
		near.name = id + "_near"
		look.add_child(near)
		look._build_parts(near, lm, false)
		_label_look(look, lm, near, false)
		look._build_scatter(near, lm)
		var roots: Array = [near]
		var far: Node = look.get_node_or_null(id + "_far")
		if far != null:
			roots.append(far)
			_label_look(look, lm, far, true)
		var p: Array = lm["pos"]
		var wet := bool(lm.get("wet", false))
		for part: Dictionary in lm.get("parts", []):
			wet = wet or bool(part.get("water", false))       # a landmark that puts parts on the water level is a wet site
		_add_group("%s:%s" % [gkind, id], gkind, id, Vector2(float(p[0]), float(p[1])), roots, [], file + ":_place/_build_scatter", wet, false)


## Names the assets of a landmark's parts on the nodes _build_parts made (same order as the parts/repeats), so tag lists and
## reports can see "lantern_hanging_green" instead of "@Node3D@123". Skipped when the counts do not line up.
func _label_look(look: Variant, lm: Dictionary, root: Node, far_pass: bool) -> void:
	var assets: Array = []
	for part: Dictionary in lm.get("parts", []):
		var is_far := bool(part.get("far", float(part.get("h", 0.0)) >= 7.5)) and not bool(part.get("near", false))
		if is_far != far_pass:
			continue
		for _rep in look._repeats(part):
			assets.append(String(part["a"]))
	var kids := root.get_children()
	if assets.size() > kids.size() or (not far_pass and assets.size() != kids.size()):
		return
	for i in assets.size():
		if kids[i] is Node3D and not String(kids[i].name).begins_with("Falls"):
			kids[i].set_meta("lint_asset", assets[i])


# =====================================================================================================================
# Collecting props
# =====================================================================================================================

## Assets keeps every building / nature mesh it built under a readable key ("house_1", "wall_tower", "nature:fern_b"): reverse it
## so a MultiMesh of those meshes can be named.
func _mesh_name(mesh: Mesh) -> String:
	if _mesh_names.is_empty():
		for k: String in Assets._building_cache:
			var m: Variant = Assets._building_cache[k]
			if m is Mesh:
				_mesh_names[(m as Mesh).get_instance_id()] = k
		_mesh_names[0] = ""
	return String(_mesh_names.get(mesh.get_instance_id(), ""))


func _tags(text: String, list: Array) -> bool:
	for t: String in list:
		if text.contains(t):
			return true
	return false


func _collect(n: Node, meshes: Array, mmis: Array) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if SKIP_NAMES.has(String(n.name)) or String(n.name).to_lower().contains("sail"):
		return           # far horizon mesh; windmill sails (they turn above the building and widen its footprint)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.visibility_range_begin <= 0.01 and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			meshes.append(mi)
	elif n is MultiMeshInstance3D:
		mmis.append(n)
	for c in n.get_children():
		_collect(c, meshes, mmis)


func _note_draws(g: Dictionary, mi: GeometryInstance3D, mesh: Mesh, is_multi: bool) -> void:
	if mesh == null:
		return
	var keys: Dictionary = g["draw_keys"]
	for i in mesh.get_surface_count():
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.get_surface_override_material(i) if mi is MeshInstance3D else null
		if mat == null:
			mat = mesh.surface_get_material(i)
		keys["%d/%d" % [mesh.get_instance_id(), mat.get_instance_id() if mat != null else 0]] = true
		g["draws_raw"] = int(g["draws_raw"]) + 1


func _gather_units(g: Dictionary) -> Array:
	var out: Array = []
	var cands: Array = []
	for r: Node in g["roots"]:
		for c in r.get_children():
			cands.append(c)
	for n: Node in g["loose"]:
		cands.append(n)
	for c: Node in cands:
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		var meshes: Array = []
		var mmis: Array = []
		_collect(c, meshes, mmis)
		for mmi: MultiMeshInstance3D in mmis:
			_multi_units(g, mmi, out)
		if not meshes.is_empty():
			var u := _mesh_unit(g, c, meshes)
			if not u.is_empty():
				out.append(u)
	return out


func _mesh_unit(g: Dictionary, c: Node, meshes: Array) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var pts := PackedVector2Array()
	var text := String(c.name)
	for mi: MeshInstance3D in meshes:
		_note_draws(g, mi, mi.mesh, false)
		var la := mi.get_aabb()
		if la.size == Vector3.ZERO:
			continue
		var gt := mi.global_transform
		for i in 8:
			var w := gt * la.get_endpoint(i)
			lo = lo.min(w)
			hi = hi.max(w)
			if meshes.size() == 1:
				if i in [0, 1, 4, 5]:        # one y-face is enough for a single box (endpoints 0,1,4,5 share a y)
					pts.append(Vector2(w.x, w.z))
			else:
				pts.append(Vector2(w.x, w.z))
		text += " " + String(mi.name) + " " + _mesh_name(mi.mesh) + " " + mi.mesh.resource_name + " " + mi.mesh.resource_path.get_file()
	if lo.x == INF:
		return {}
	var asset := String(c.get_meta("lint_asset", ""))
	text = (text + " " + asset).to_lower()
	var foot := pts
	if meshes.size() > 1 or pts.size() != 4:
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() > 1:
			hull.remove_at(hull.size() - 1)
		foot = hull
	else:
		foot = _order_quad(pts)
	var solid := false
	for b in c.find_children("*", "CollisionObject3D", true, false):
		solid = true
		break
	var un := _make_unit(g, c, "", AABB(lo, hi - lo), foot, text, asset, solid, false)
	if meshes.size() == 1:
		un["mesh"] = (meshes[0] as MeshInstance3D).mesh
		un["xf"] = (meshes[0] as MeshInstance3D).global_transform
	return un


## 4 points of a (yaw-rotated) box face in cyclic order.
func _order_quad(p: PackedVector2Array) -> PackedVector2Array:
	var c := (p[0] + p[1] + p[2] + p[3]) * 0.25
	var arr: Array = [p[0], p[1], p[2], p[3]]
	arr.sort_custom(func(a: Vector2, b: Vector2) -> bool: return (a - c).angle() < (b - c).angle())
	return PackedVector2Array(arr)


func _multi_units(g: Dictionary, mmi: MultiMeshInstance3D, out: Array) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null or mm.transform_format != MultiMesh.TRANSFORM_3D:
		return
	if mmi.visibility_range_begin > 0.01:
		return
	_note_draws(g, mmi, mm.mesh, true)
	var la := mm.mesh.get_aabb()
	if la.size == Vector3.ZERO:
		return
	var xf: Variant = mm.get_meta("lint_xf") if mm.has_meta("lint_xf") else null
	if xf == null:
		untracked.append(_path_of(mmi))
		return
	var xfa: Array = xf
	var n := xfa.size()
	var text := (String(mmi.name) + " " + _mesh_name(mm.mesh) + " " + mm.mesh.resource_name + " " + mm.mesh.resource_path.get_file() + " " + String(mmi.get_meta("lint_asset", "")) + " [%.1fx%.1fx%.1f m]" % [la.size.x, la.size.y, la.size.z]).to_lower()
	var gt0 := mmi.global_transform
	var y0 := la.position.y
	var corners := [Vector3(la.position.x, y0, la.position.z), Vector3(la.end.x, y0, la.position.z),
		Vector3(la.end.x, y0, la.end.z), Vector3(la.position.x, y0, la.end.z)]
	for i in n:
		if xfa[i] == null:
			continue
		var t: Transform3D = gt0 * (xfa[i] as Transform3D)
		var foot := PackedVector2Array()
		for cpt: Vector3 in corners:
			var w := t * cpt
			foot.append(Vector2(w.x, w.z))
		var um := _make_unit(g, mmi, "#%d" % i, t * la, foot, text, "", false, true)
		um["mesh"] = mm.mesh
		um["xf"] = t
		out.append(um)


func _make_unit(g: Dictionary, node: Node, suffix: String, aabb: AABB, foot: PackedVector2Array, text: String, asset: String, solid: bool, multi: bool) -> Dictionary:
	var vol_area := _poly_area(foot)
	var big_dim := maxf(aabb.size.x, aabb.size.z)
	var is_building := _tags(text, CFG.BUILDING)
	var large := is_building or _tags(text, CFG.LARGE) or (aabb.get_volume() >= CFG.LARGE_VOL and big_dim >= CFG.LARGE_FOOT)
	var builder := ""
	var bn: Node = node
	if not multi:
		builder = String(node.get_meta("lint_builder", ""))
	else:
		builder = String(node.get_meta("lint_builder", ""))
		bn = node
	if builder == "":
		builder = String(g["builder"])
	if asset == "":
		asset = String(node.get_meta("lint_asset", node.get_meta("lint_note", "")))
	return {"node": node, "path": _path_of(bn) + suffix, "aabb": aabb, "foot": foot, "area": vol_area, "text": text, "asset": asset,
		"solid": solid or large, "large": large, "building": is_building, "multi": multi, "builder": builder,
		"parent": String(node.get_parent().name).to_lower() if node.get_parent() != null else "", "group": g}


func _path_of(n: Node) -> String:
	if n.is_inside_tree():
		return String(n.get_path())
	return String(n.name)


func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) * 0.5


# =====================================================================================================================
# Per-prop checks
# =====================================================================================================================

func _lint_group(g: Dictionary) -> void:
	_corner_cache.clear()
	var units := _gather_units(g)
	g["units"] = units
	g["n_units"] = units.size()
	stats["units"] = int(stats["units"]) + units.size()
	for u: Dictionary in units:
		if u["multi"]:
			stats["instances"] = int(stats["instances"]) + 1
		_check_ground(g, u)


func _shrunk_samples(u: Dictionary) -> Array:
	var ab: AABB = u["aabb"]
	var c := Vector2(ab.get_center().x, ab.get_center().z)
	var out: Array = [c]
	if float(u["area"]) < 4.0:
		return out
	for q: Vector2 in (u["foot"] as PackedVector2Array):
		out.append(c + (q - c) * CFG.FOOT_SHRINK)
	return out


## True when another prop of the group stands under this one (a roof on its tower, a crate on a cart): its top reaches this
## prop's base and their footprints overlap. Such stacks are designed kits, not floating bugs.
func _supported(g: Dictionary, u: Dictionary) -> bool:
	if not g.has("grid"):
		var grid := {}
		var us: Array = g["units"]
		for i in us.size():
			var ab: AABB = us[i]["aabb"]
			for cx in range(floori(ab.position.x / GRID), floori(ab.end.x / GRID) + 1):
				for cz in range(floori(ab.position.z / GRID), floori(ab.end.z / GRID) + 1):
					var k := Vector2i(cx, cz)
					if not grid.has(k):
						grid[k] = []
					grid[k].append(i)
		g["grid"] = grid
	var ab: AABB = u["aabb"]
	var units: Array = g["units"]
	var grid: Dictionary = g["grid"]
	for cx in range(floori(ab.position.x / GRID), floori(ab.end.x / GRID) + 1):
		for cz in range(floori(ab.position.z / GRID), floori(ab.end.z / GRID) + 1):
			for i: int in grid.get(Vector2i(cx, cz), []):
				var o: Dictionary = units[i]
				if o == u:
					continue
				var ob: AABB = o["aabb"]
				if ob.end.y > ab.position.y - 0.4 and ob.position.y < ab.position.y - 0.05 and ob.size.y > 0.3 \
						and minf(ob.end.x, ab.end.x) - maxf(ob.position.x, ab.position.x) > 0.2 and minf(ob.end.z, ab.end.z) - maxf(ob.position.z, ab.position.z) > 0.2:
					return true
	return false


## (min, max) over ~200 sampled vertices of (vertex y - ground at its x,z). min <= 0: the terrain cuts the mesh (it sits in the
## ground); min > 0: no vertex touches it (hovering), by that many metres; max < 0: every vertex is underground (invisible).
## Falls back to the AABB base when a mesh has no readable faces.
## The terrain as RENDERED: terrain_streamer draws WorldGen.height on a CELL-metre grid, split a-b-c / b-d-c per cell. On sheer
## ground (gorge walls, rims) that triangle surface differs from the height function by metres, which is exactly where a
## boulder placed by WorldGen.height looks like it hovers. Cached per corner.
func _mesh_ground(x: float, z: float) -> float:
	var cell := CFG.TERRAIN_CELL
	var gx := x / cell
	var gz := z / cell
	var i := floori(gx)
	var j := floori(gz)
	var fx := gx - i
	var fz := gz - j
	var ha := _corner(i, j, cell)
	var hb := _corner(i + 1, j, cell)
	var hc := _corner(i, j + 1, cell)
	if fx + fz <= 1.0:
		return ha + fx * (hb - ha) + fz * (hc - ha)
	var hd := _corner(i + 1, j + 1, cell)
	return hd + (1.0 - fx) * (hc - hd) + (1.0 - fz) * (hb - hd)


func _corner(i: int, j: int, cell: float) -> float:
	var k := Vector2i(i, j)
	if _corner_cache.has(k):
		return _corner_cache[k]
	var h := WorldGen.height(i * cell, j * cell)
	_corner_cache[k] = h
	return h


func _vertex_gaps(u: Dictionary) -> Vector2:
	var mesh: Mesh = u.get("mesh")
	var ab: AABB = u["aabb"]
	if mesh == null:
		var d0 := ab.position.y - WorldGen.height(ab.get_center().x, ab.get_center().z)
		return Vector2(d0, d0)
	var key := mesh.get_instance_id()
	if not _vert_cache.has(key):
		var faces := mesh.get_faces()
		var pick := PackedVector3Array()
		if faces.size() > 0:
			var step := maxi(1, faces.size() / 160)
			for i in range(0, faces.size(), step):
				pick.append(faces[i])
			var lows := Array(faces)
			lows.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
			for i in mini(48, lows.size()):
				pick.append(lows[i * maxi(1, lows.size() / 400)] if i * maxi(1, lows.size() / 400) < lows.size() else lows[i])
		_vert_cache[key] = pick
	var verts: PackedVector3Array = _vert_cache[key]
	if verts.is_empty():
		stats["rocks_without_faces"] = int(stats.get("rocks_without_faces", 0)) + 1
		var d1 := ab.position.y - WorldGen.height(ab.get_center().x, ab.get_center().z)
		return Vector2(d1, d1)
	var xf: Transform3D = u["xf"]
	var best := INF
	var worst := -INF
	for v: Vector3 in verts:
		var w := xf * v
		var d := w.y - (_mesh_ground(w.x, w.z) if CFG.ROCK_USE_MESH_GROUND else WorldGen.height(w.x, w.z))
		best = minf(best, d)
		worst = maxf(worst, d)
	return Vector2(best, worst)


func _on_water(p: Vector2, base_y: float) -> bool:
	var lv := WorldGen.water_level_at(p.x, p.y)
	return not is_nan(lv) and base_y <= lv + 0.6


func _check_ground(g: Dictionary, u: Dictionary) -> void:
	var ab: AABB = u["aabb"]
	var text: String = u["text"]
	var samples := _shrunk_samples(u)
	var gc := WorldGen.height(samples[0].x, samples[0].y)
	var gmin := gc
	var gmax := gc
	for i in range(1, samples.size()):
		var h := WorldGen.height(samples[i].x, samples[i].y)
		gmin = minf(gmin, h)
		gmax = maxf(gmax, h)
	u["gc"] = gc
	var miny := ab.position.y
	var maxy := ab.end.y
	var hgt := ab.size.y
	# --- floating: the game snaps every prop to the LOWEST ground under its footprint (minus ~8 cm) and hides the uphill
	# gap with a plinth, so a base more than FLOAT_TOL above the lowest footprint sample is hovering. Stacked props (a roof
	# on its tower, a prop on a plinth) and things resting on water are supported, not floating.
	var soft := _tags(text, CFG.SOFT) or _tags(text, CFG.FOLIAGE)
	if hgt < CFG.THIN_M:
		return       # flat decals, contact-shadow blobs, water sheets: nothing to float or sink
	# Rocks on steep ground are embedded, not snapped: a boulder clinging to a wall legitimately overhangs on the downhill
	# side. Judge them by how much of their box is inside the terrain (columns sampled over the footprint) instead.
	var rocky := _tags(text, CFG.ROCKY) and not soft and not _tags(text, CFG.SINK_OK) and hgt >= 0.5
	if rocky:
		var gaps := _vertex_gaps(u)
		var gap := gaps.x
		if gap > CFG.FLOAT_TOL:
			_add_issue(g, u, "float", "severe" if gap > CFG.FLOAT_SEVERE else ("major" if gap > 0.5 else "minor"), gap,
				"boulder hovers: its lowest sampled vertex is %.2f m above the terrain and none touches it (box %.1f m tall, ground under it %.1f..%.1f m, base %.1f)" % [gap, hgt, gmin, gmax, miny])
		elif gaps.y < -CFG.ROCK_BURIED_DEPTH:
			_add_issue(g, u, "buried", "minor", -gaps.y, "boulder entirely inside the terrain (every sampled vertex is at least %.2f m below ground): invisible" % -gaps.y)
	elif not _tags(text, CFG.FLOAT_OK):
		var gap_lo := miny - gmin
		var gap_hi := miny - gmax
		if gap_lo > (CFG.FLOAT_SOFT_TOL if soft else CFG.FLOAT_TOL) and not _on_water(samples[0], miny) and not _supported(g, u):
			var how := "nothing under it touches the ground" if gap_hi > CFG.FLOAT_TOL else "the downhill side hangs in the air (uphill side touches)"
			var fsev := "severe" if gap_lo > CFG.FLOAT_SEVERE else ("major" if gap_lo > 0.5 else "minor")
			if soft:
				fsev = "minor"       # foliage skirts hide a hanging side: never more than minor
			_add_issue(g, u, "float", fsev, gap_lo,
				"lowest point %.2f m above the lowest ground under its footprint (ground %.2f..%.2f, base %.2f): %s" % [gap_lo, gmin, gmax, miny, how])
	# --- sunken
	if hgt >= CFG.MIN_HEIGHT_FOR_SINK and not _tags(text, CFG.SINK_OK) and not rocky:
		var sink := gc - miny
		if maxy < gc - 0.05:
			_add_issue(g, u, "buried", "minor" if _tags(text, CFG.BURIED_OK) else "major", gc - maxy, "top is %.2f m below the ground (height %.2f m)" % [gc - maxy, hgt])
		elif sink >= CFG.SINK_MIN_M:
			var frac := sink / hgt
			var thr: float = CFG.SINK_FRAC_BURIED_OK if _tags(text, CFG.BURIED_OK) else CFG.SINK_FRAC
			if frac > thr:
				_add_issue(g, u, "sunken", "major" if (frac > 0.85 and not soft) else "minor", frac,
					"%.0f%% of its %.2f m height is below ground (%.2f m sunk, limit %.0f%%)" % [frac * 100.0, hgt, sink, thr * 100.0])
	# --- water
	if not bool(g["wet"]) and not _tags(text, CFG.WET_OK):
		var wet := 0
		for p: Vector2 in samples:
			if WorldGen.is_water(p.x, p.y):
				wet += 1
		if WorldGen.is_water(samples[0].x, samples[0].y) or wet * 2 > samples.size():
			var lv := WorldGen.water_level_at(samples[0].x, samples[0].y)
			var depth := 0.0 if is_nan(lv) else lv - gc
			_add_issue(g, u, "water", "major" if (depth > 0.5 and u["solid"]) else "minor", depth,
				"stands in water (%d/%d footprint samples wet, water %.2f m over the ground at the centre)" % [wet, samples.size(), depth])
	# --- road
	if not bool(g["road_ok"]) and u["solid"] and not _tags(text, CFG.SOFT) and not _tags(text, CFG.ROAD_OK):
		var c: Vector2 = samples[0]
		var near := WorldGen.nearest_settlement(c)
		if not (not near.is_empty() and c.distance_to(near["pos"]) < float(near["radius"])):
			var info := WorldGen.road_info(c.x, c.y)
			var half := float(info["width"]) * 0.5
			var big := maxf(ab.size.x, ab.size.z) >= 1.5 or hgt >= 1.5
			if float(info["dist"]) < half * CFG.ROAD_SEVERE_FRAC:
				_add_issue(g, u, "road", "severe" if big else "minor", half - float(info["dist"]),
					"centre %.2f m from the %s road centreline (road half-width %.2f m)" % [float(info["dist"]), info["tier"], half])
			else:
				var worst := INF
				for i in range(1, samples.size()):
					worst = minf(worst, float(WorldGen.road_info(samples[i].x, samples[i].y)["dist"]))
				if worst < half * 0.75 and big:
					_add_issue(g, u, "road", "major", half - worst, "footprint edge %.2f m from the %s road centreline (half-width %.2f m)" % [worst, info["tier"], half])


# =====================================================================================================================
# Overlaps between large props (per group, spatial hash)
# =====================================================================================================================

func _lint_overlaps() -> void:
	for g: Dictionary in groups:
		var big: Array = []
		for u: Dictionary in g["units"]:
			var ab: AABB = u["aabb"]
			if u["large"] and float(u["area"]) * ab.size.y >= CFG.OVERLAP_MIN_VOL:
				big.append(u)
		if big.size() < 2:
			continue
		var grid := {}
		var cell := 12.0
		for i in big.size():
			var ab: AABB = big[i]["aabb"]
			for cx in range(floori(ab.position.x / cell), floori(ab.end.x / cell) + 1):
				for cz in range(floori(ab.position.z / cell), floori(ab.end.z / cell) + 1):
					var k := Vector2i(cx, cz)
					if not grid.has(k):
						grid[k] = []
					grid[k].append(i)
		var seen := {}
		for k: Vector2i in grid:
			var lst: Array = grid[k]
			for a in lst.size():
				for b in range(a + 1, lst.size()):
					var i: int = lst[a]
					var j: int = lst[b]
					var key := i * 1000003 + j if i < j else j * 1000003 + i
					if seen.has(key):
						continue
					seen[key] = true
					_pair(g, big[i], big[j])


func _pair(g: Dictionary, a: Dictionary, b: Dictionary) -> void:
	var na: Node = a["node"]
	var nb: Node = b["node"]
	if na == nb and not a["multi"]:
		return
	if na != nb and (na.is_ancestor_of(nb) or nb.is_ancestor_of(na)):
		return
	var aa: AABB = a["aabb"]
	var bb: AABB = b["aabb"]
	if not aa.intersects(bb):
		return
	var yo := minf(aa.end.y, bb.end.y) - maxf(aa.position.y, bb.position.y)
	if yo <= 0.05:
		return
	if _tags(a["text"], CFG.OVERLAP_SKIP) or _tags(b["text"], CFG.OVERLAP_SKIP):
		return
	for k: String in CFG.KIT_PARENT_TOKENS:
		if String(a["parent"]).contains(k) and String(a["parent"]) == String(b["parent"]):
			return
	for pr: Array in CFG.OVERLAP_PAIR_OK:
		var ta: String = a["text"]
		var tb: String = b["text"]
		if (ta.contains(pr[0]) and tb.contains(pr[1])) or (ta.contains(pr[1]) and tb.contains(pr[0])):
			return
	var inter := Geometry2D.intersect_polygons(a["foot"], b["foot"])
	var area := 0.0
	for poly: PackedVector2Array in inter:
		area += _poly_area(poly)
	if area < 0.05:
		return
	var va: float = float(a["area"]) * aa.size.y
	var vb: float = float(b["area"]) * bb.size.y
	var frac := area * yo / maxf(minf(va, vb), 0.001)
	if frac > CFG.OVERLAP_FRAC:
		var both_b: bool = a["building"] and b["building"]
		var other := "%s (%s)" % [b["path"], String(b["asset"]) if b["asset"] != "" else String(b["text"]).substr(0, 40)]
		_add_issue(g, a, "overlap", "severe" if both_b else "major", frac,
			"overlaps %s by %.0f%% of the smaller volume (%.1f m2 shared footprint)" % [other, frac * 100.0, area], b)


# =====================================================================================================================
# Issues and reports
# =====================================================================================================================

func _add_issue(g: Dictionary, u: Dictionary, type: String, sev: String, metric: float, detail: String, other: Dictionary = {}) -> void:
	var ab: AABB = u["aabb"]
	var base := 1000.0 if sev == "severe" else (500.0 if sev == "major" else 100.0)
	var issue := {"type": type, "severity": sev, "score": base + minf(absf(metric), 50.0) * 10.0,
		"site": String(g["name"]), "site_id": String(g["id"]), "site_kind": String(g["kind"]), "path": String(u["path"]),
		"builder": String(u["builder"]), "asset": String(u["asset"]), "pos": [snappedf(ab.get_center().x, 0.01), snappedf(ab.position.y, 0.01), snappedf(ab.get_center().z, 0.01)],
		"metric": snappedf(metric, 0.01), "what": String(u["text"]).substr(0, 90).strip_edges(), "detail": detail}
	if not other.is_empty():
		issue["other"] = String(other["path"])
	g["issues"] = int(g["issues"]) + 1
	var hay := "%s | %s | %s" % [issue["path"], issue["asset"], issue["builder"]]
	if not other.is_empty():
		hay += " | %s | %s | %s" % [other["path"], other["asset"], other["text"]]
	hay = hay.to_lower() + " | " + String(u["text"])
	for al: Dictionary in CFG.ALLOW:
		if String(al.get("type", "*")) not in ["*", type]:
			continue
		var sk := String(al.get("site", "*"))
		if sk != "*" and sk != String(g["kind"]) and sk != String(g["id"]) and sk != String(g["name"]):
			continue
		if not hay.contains(String(al.get("match", "")).to_lower()):
			continue
		issue["allowlisted"] = String(al.get("reason", "")) + (" [TODO]" if bool(al.get("todo", false)) else "")
		allowed.append(issue)
		return
	issues.append(issue)


func _finish_draws() -> void:
	for g: Dictionary in groups:
		var budget: int = int(CFG.DRAW_BUDGET_BY_GROUP.get(String(g["kind"]), CFG.DRAW_BUDGET))
		g["draws"] = (g["draw_keys"] as Dictionary).size()
		g["budget"] = budget
		if g["draws"] > budget:
			var u := {"aabb": AABB(Vector3(g["pos"].x, 0.0, g["pos"].y), Vector3.ZERO), "path": String(g["id"]), "builder": String(g["builder"]), "asset": "", "text": ""}
			_add_issue(g, u, "draws", "minor", float(g["draws"] - budget), "%d distinct mesh+material draws (budget %d; %d mesh surfaces drawn raw)" % [g["draws"], budget, g["draws_raw"]])


func to_dict() -> Dictionary:
	var gl: Array = []
	for g: Dictionary in groups:
		gl.append({"id": g["id"], "kind": g["kind"], "name": g["name"], "pos": [snappedf(g["pos"].x, 0.1), snappedf(g["pos"].y, 0.1)],
			"builder": g["builder"], "props": g["n_units"], "draws": g.get("draws", 0), "draw_budget": g.get("budget", 0), "draws_raw": g["draws_raw"], "issues": g["issues"]})
	var by_kind := {}
	for g: Dictionary in groups:
		var k := String(g["kind"])
		if not by_kind.has(k):
			by_kind[k] = {"groups": 0, "props": 0, "severe": 0, "major": 0, "minor": 0, "over_draw_budget": 0}
		by_kind[k]["groups"] += 1
		by_kind[k]["props"] += int(g["n_units"])
		if int(g.get("draws", 0)) > int(g.get("budget", 999)):
			by_kind[k]["over_draw_budget"] += 1
	for i: Dictionary in issues:
		by_kind[i["site_kind"]][i["severity"]] += 1
	return {"seed": seed_value, "sites": filter, "totals": {"groups": groups.size(), "props": stats["units"], "instances": stats["instances"],
		"severe": count_sev("severe"), "major": count_sev("major"), "minor": count_sev("minor"), "allowlisted": allowed.size()},
		"by_kind": by_kind, "untracked_multimeshes": untracked, "groups": gl, "issues": issues, "allowlisted": allowed}


func text_report(top_n := 15) -> String:
	var d := to_dict()
	var t: Dictionary = d["totals"]
	var out := PackedStringArray()
	out.append("=== WORLD LINT  seed=%d  sites=%s ===" % [seed_value, ",".join(PackedStringArray(filter))])
	out.append("%d groups, %d props (%d multimesh instances): %d SEVERE, %d major, %d minor, %d allowlisted" % [t["groups"], t["props"], t["instances"], t["severe"], t["major"], t["minor"], t["allowlisted"]])
	out.append("")
	out.append("Per site kind (severe / major / minor, groups over draw budget):")
	var kinds: Array = (d["by_kind"] as Dictionary).keys()
	kinds.sort_custom(func(a: String, b: String) -> bool:
		var ka: Dictionary = d["by_kind"][a]
		var kb: Dictionary = d["by_kind"][b]
		return ka["severe"] * 1000 + ka["major"] * 10 + ka["minor"] > kb["severe"] * 1000 + kb["major"] * 10 + kb["minor"])
	for k: String in kinds:
		var e: Dictionary = d["by_kind"][k]
		out.append("  %-18s %3d groups %6d props   %3d / %3d / %3d   draw-over %d" % [k, e["groups"], e["props"], e["severe"], e["major"], e["minor"], e["over_draw_budget"]])
	out.append("")
	out.append("Top %d issues (draw-budget findings are listed separately below):" % top_n)
	var shown := 0
	for i: Dictionary in issues:
		if i["type"] == "draws":
			continue
		out.append("  " + _fmt(i))
		shown += 1
		if shown >= top_n:
			break
	out.append("")
	out.append("Draw budget (distinct mesh+material draws per site, worst 10):")
	var gs := groups.duplicate()
	gs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("draws", 0)) - int(a.get("budget", 0)) > int(b.get("draws", 0)) - int(b.get("budget", 0)))
	for k in mini(10, gs.size()):
		var g: Dictionary = gs[k]
		if int(g.get("draws", 0)) > int(g.get("budget", 0)):
			out.append("  %-28s [%s] %d / %d  (%d surfaces raw)" % [g["name"], g["kind"], g["draws"], g["budget"], g["draws_raw"]])
	out.append("")
	out.append("By site (worst first):")
	var by_site := {}
	var order: Array = []
	for i: Dictionary in issues:
		var sid := String(i["site_id"])
		if not by_site.has(sid):
			by_site[sid] = []
			order.append(sid)
		by_site[sid].append(i)
	var gmap := {}
	for g: Dictionary in groups:
		gmap[String(g["id"])] = g
	for sid: String in order:
		var g: Dictionary = gmap[sid]
		out.append("- %s [%s] %s  pos(%.0f, %.0f)  props %d  draws %d/%d  builder %s" % [g["name"], g["kind"], g["id"], g["pos"].x, g["pos"].y, g["n_units"], g.get("draws", 0), g.get("budget", 0), g["builder"]])
		var lst: Array = by_site[sid]
		for k in mini(lst.size(), 12):
			out.append("    " + _fmt(lst[k], false))
		if lst.size() > 12:
			out.append("    ... %d more (see JSON)" % (lst.size() - 12))
	if not allowed.is_empty():
		out.append("")
		out.append("Allowlisted (%d):" % allowed.size())
		var seen := {}
		for i: Dictionary in allowed:
			var key := "%s %s %s" % [i["type"], i["site_kind"], i["allowlisted"]]
			seen[key] = int(seen.get(key, 0)) + 1
		for key: String in seen:
			out.append("  %4d x %s" % [seen[key], key])
	return "\n".join(out)


func _fmt(i: Dictionary, with_site := true) -> String:
	var p: Array = i["pos"]
	var s := "[%s] %-8s %s%s @(%.1f, %.1f, %.1f) %s  -- %s" % [String(i["severity"]).to_upper(), i["type"],
		(String(i["site"]) + " :: ") if with_site else "", i["path"], p[0], p[1], p[2], i["detail"], i["builder"]]
	if i["asset"] != "":
		s += " asset=" + String(i["asset"])
	return s
