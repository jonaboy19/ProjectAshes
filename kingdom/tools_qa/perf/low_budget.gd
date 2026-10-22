extends Node
## LOW budget audit (cloud, 2026-10-06): draws / triangles at fixed views, attributed to cloud-added content versus older content.
## Run under xvfb with a software Vulkan driver (counts are CPU-side, fps is meaningless):
##   xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path kingdom --rendering-driver vulkan --rendering-method mobile -- \
##     --adult --quality=low --qa=res://tools_qa/perf/low_budget.gd [--views=ashford,thornfield,redwater,meshy3] [--out=/tmp/x.json]
## Per view: Performance monitors (real draw calls and primitives of the last frame, shadow pass included) and a census of
## every GeometryInstance3D the camera draws (frustum + visibility range, like town_route.gd), by source class:
##   cloud:meshy3 / cloud:fill / cloud:townkit / cloud:wilds / cloud:site (other fill kinds)   vs   old:<owner>   vs   chars
## Prints `LOWB view=<v> class=<c> surf=<n> tris=<n> shadow=<n>` lines and `LOWB_TOTAL`, and writes a JSON when --out= is given.
var main: Node
var views: Array = []
var only: PackedStringArray = []
var out_path := ""
var results := {}
var site_class := {}        # RegionDressing site root name -> class


func run(m: Node) -> void:
	main = m
	print("LOWB run() entered")
	for raw in Array(OS.get_cmdline_user_args()):
		var a := String(raw)
		if a.begins_with("--views="):
			only = a.substr(8).split(",", false)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	WorldSim.time_of_day = 15.0
	for s: Dictionary in WorldGen.sites:
		var cls := "old:site"
		if bool(s.get("fill", false)):
			cls = "cloud:meshy3" if String(s.get("fill_id", "")).begins_with("m3_") else "cloud:fill"
		site_class[String(s["name"]).replace(" ", "") + str(s["id"])] = cls
	_views()
	_go.call_deferred()


func _town(nm: String) -> Dictionary:
	for s: Dictionary in WorldGen.settlements:
		if String(s["name"]) == nm:
			return s
	return {}


func _views() -> void:
	var ash: Dictionary = WorldGen.settlements[0]
	var st: Dictionary = (ash["plan"]["streets"] as Array)[0]
	var a: Vector2 = st["a"]
	var d := ((st["b"] as Vector2) - a).normalized()
	views.append(["ashford", a + d * 6.0, atan2(-d.x, -d.y)])
	var th := _town("Thornfield")
	if not th.is_empty():
		var pr: float = float(th["plan"]["plaza_r"])
		var p: Vector2 = th["pos"]
		views.append(["thornfield", p + Vector2(0, pr + 4.0), 0.0])
	var rw := _town("Redwater")
	if not rw.is_empty():
		var pr2: float = float(rw["plan"]["plaza_r"])
		var p2: Vector2 = rw["pos"]
		views.append(["redwater", p2 + Vector2(pr2 + 4.0, 0), PI * 0.5])
	var Wl := preload("res://scripts/world/thornfield/wilds.gd")
	var camp: Vector2 = Wl.at(Wl.data()["bandit_camp"]["offset"])
	if camp != Vector2.INF:
		views.append(["camp", camp + Vector2(0, 16.0), 0.0])
	var rift: Vector2 = Wl.at(Wl.data()["rift"]["entrance_offset"])
	if rift != Vector2.INF:
		views.append(["rift", rift + Vector2(0, 14.0), 0.0])
	var best := {}
	for s: Dictionary in WorldGen.sites:
		if bool(s.get("fill", false)) and String(s.get("fill_id", "")) == "m3_thornfield_lane":
			best = s
	if not best.is_empty():
		var q: Vector2 = best["pos"]
		views.append(["meshy3", q + Vector2(0, 16.0), 0.0])


func _go() -> void:
	for v: Array in views:
		if not only.is_empty() and not only.has(String(v[0])):
			continue
		await _view(String(v[0]), v[1], float(v[2]))
	_materials()
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	get_tree().quit(0)


func _view(nm: String, at: Vector2, yaw: float) -> void:
	print("LOWB view start ", nm)
	main.call("_teleport", at, yaw)
	var t0 := Time.get_ticks_msec()
	for i in 900:      # let the dressing queue drain and the streamers settle
		await get_tree().process_frame
		if i > 420 and (main.region as RegionDressing)._queue.is_empty():
			break
	for i in 12:
		await get_tree().process_frame
	var dr := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var pr := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var cen := _census()
	cen["measured_draws"] = dr
	cen["measured_prims"] = pr
	cen["tex_mb"] = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)
	cen["static_mb"] = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	results[nm] = cen
	var cloud := [0, 0]
	for k: String in cen["classes"]:
		if k.begins_with("cloud:") or k == "chars:meshy3":
			cloud[0] += int(cen["classes"][k][0])
			cloud[1] += int(cen["classes"][k][1])
	print("LOWB_TOTAL view=%s measured_draws=%d measured_prims=%d census_surf=%d census_tris=%d shadow_surf=%d cloud_surf=%d cloud_tris=%d tex_mb=%d static_mb=%d settle_ms=%d" % [
		nm, dr, pr, cen["surf"], cen["tris"], cen["shadow"], cloud[0], cloud[1], cen["tex_mb"], cen["static_mb"], Time.get_ticks_msec() - t0])
	for k: String in cen["classes"]:
		var c: Array = cen["classes"][k]
		print("LOWB view=%s class=%s surf=%d tris=%d shadow=%d nodes=%d" % [nm, k, c[0], c[1], c[2], c[3]])
	print("LOWB view=%s rejected %s" % [nm, str(cen["rej"])])
	var rows: Array = cen["top"]
	for r in rows:
		print("LOWB view=%s top %s" % [nm, r])


static func _tris_of(mesh: Mesh) -> int:
	var tris := 0
	if mesh is ArrayMesh:
		for si in mesh.get_surface_count():
			var n_idx: int = (mesh as ArrayMesh).surface_get_array_index_len(si)
			tris += n_idx / 3 if n_idx > 0 else (mesh as ArrayMesh).surface_get_array_len(si) / 3
	return tris


func _census() -> Dictionary:
	var cam := main.viewport.get_camera_3d() as Camera3D
	var cp := cam.global_position
	var planes := cam.get_frustum()
	var sd := 40.0
	for l in main.world.find_children("*", "DirectionalLight3D", true, false):
		if (l as DirectionalLight3D).shadow_enabled:
			sd = (l as DirectionalLight3D).directional_shadow_max_distance
	var rej := {}
	var dbg := 0
	var cls := {}
	var mesh_d := {}
	var tot := [0, 0, 0]
	for n in main.world.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			rej["hidden"] = int(rej.get("hidden", 0)) + 1
			continue
		var box: AABB = g.global_transform * g.get_aabb()
		var d := box.get_center().distance_to(cp)
		if (g.visibility_range_end > 0.0 and d > g.visibility_range_end) or d < g.visibility_range_begin:
			if d < 70.0 and dbg < 12 and _class_of(g) == "old:SettlementBuilder":
				dbg += 1
				print("LOWB dbg near-but-ranged d=%.0f begin=%.0f end=%.0f %s mesh=%s" % [d, g.visibility_range_begin, g.visibility_range_end, g.name, (g as MeshInstance3D).mesh.resource_path if g is MeshInstance3D and (g as MeshInstance3D).mesh else "-"])
			rej["range:" + _class_of(g)] = int(rej.get("range:" + _class_of(g), 0)) + 1
			continue
		var c := box.get_center()
		var e := box.size * 0.5
		var inside := true
		for pl in planes:
			if pl.distance_to(c) > absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z:
				inside = false
				break
		var mesh: Mesh = null
		var inst := 1
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm := (g as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			inst = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		var surf := mesh.get_surface_count() if mesh else 1
		var shadow := g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and d < sd + e.length()
		if not inside and not shadow:
			rej["frustum:" + _class_of(g)] = int(rej.get("frustum:" + _class_of(g), 0)) + 1
			continue
		var tris := _tris_of(mesh) if mesh != null else 0
		var klass := _class_of(g)
		var o: Array = cls.get(klass, [0, 0, 0, 0])
		var vis := surf if inside else 0
		var vt := tris * inst if inside else 0
		cls[klass] = [o[0] + vis, o[1] + vt, o[2] + (surf if shadow else 0), o[3] + 1]
		tot = [tot[0] + vis, tot[1] + vt, tot[2] + (surf if shadow else 0)]
		if inside:
			var mn := (mesh.resource_path.get_file() if mesh != null and mesh.resource_path != "" else String(g.name)).left(30)
			var k := "%-14s %-30s" % [klass.right(14), mn]
			var m: Array = mesh_d.get(k, [0, 0, 0])
			mesh_d[k] = [m[0] + vis, m[1] + vt, m[2] + 1]
	var mk := mesh_d.keys()
	mk.sort_custom(func(a, b) -> bool: return mesh_d[a][1] > mesh_d[b][1])
	var top: Array = []
	for k in mk.slice(0, 24):
		top.append("%s surf=%d tris=%d n=%d" % [k, mesh_d[k][0], mesh_d[k][1], mesh_d[k][2]])
	return {"surf": tot[0], "tris": tot[1], "shadow": tot[2], "classes": cls, "top": top, "rej": rej}


## Source class of a geometry instance, from its ancestry.
func _class_of(g: Node) -> String:
	var p := g.get_parent()
	var chain: Array[Node] = []
	while p != null and p != main.world and p != get_tree().root:
		chain.push_front(p)
		p = p.get_parent()
	if g is MeshInstance3D and ((g as MeshInstance3D).skin != null or g.get_parent() is Skeleton3D):
		var mp := (g as MeshInstance3D).mesh.resource_path if (g as MeshInstance3D).mesh != null else ""
		return "chars:meshy3" if mp.contains("meshy_dl3") else "chars"
	for n: Node in chain:
		var nm := String(n.name)
		if n.get_parent() is RegionDressing:
			return String(site_class.get(nm, "old:region_look"))
		if nm.begins_with("TownHub_") or nm.ends_with("Pens") or nm.begins_with("Stash_"):
			return "cloud:townkit"
		if nm == "WildsHub":
			return "cloud:wilds"
		if n.get_script() != null and String(n.get_script().get_global_name()) == "TownHub":
			return "cloud:townkit"
	if chain.size() > 0:
		var n0: Node = chain[0]
		var s0 := String(n0.get_script().get_global_name()) if n0.get_script() != null else ""
		return "old:" + (s0 if s0 != "" else String(n0.name).rstrip("0123456789_-"))
	return "old:world"


## Material / texture audit of everything built in the world tree: unique materials and textures per source class, textures wider
## than 512 px (the phone caps to 512 on export, so the "est MB" uses min(side, 512), ETC2/ASTC 8 bpp + mips).
func _materials() -> void:
	var per := {}
	for n in main.world.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		var klass := _class_of(g)
		var e: Dictionary = per.get(klass, {"inst": 0, "mats": {}, "tex": {}})
		e["inst"] += 1
		var mats: Array = []
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			for i in (g as MeshInstance3D).mesh.get_surface_count():
				mats.append((g as MeshInstance3D).get_active_material(i))
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null and (g as MultiMeshInstance3D).multimesh.mesh != null:
			var mmesh := (g as MultiMeshInstance3D).multimesh.mesh
			for i in mmesh.get_surface_count():
				mats.append(mmesh.surface_get_material(i))
		if g.material_override != null:
			mats.append(g.material_override)
		for m in mats:
			if m == null:
				continue
			(e["mats"] as Dictionary)[m.get_instance_id()] = true
			for t: Texture2D in _textures(m):
				(e["tex"] as Dictionary)[t.get_instance_id()] = [t.get_width(), t.get_height()]
		per[klass] = e
	var out := {}
	for k: String in per:
		var e: Dictionary = per[k]
		var big := 0
		var mb := 0.0
		for id in e["tex"]:
			var wh: Array = e["tex"][id]
			if maxi(wh[0], wh[1]) > 512:
				big += 1
			var sc := minf(1.0, 512.0 / float(maxi(maxi(wh[0], wh[1]), 1)))
			mb += float(wh[0]) * sc * float(wh[1]) * sc * 1.33 / 1048576.0
		out[k] = {"inst": e["inst"], "mats": (e["mats"] as Dictionary).size(), "tex": (e["tex"] as Dictionary).size(), "tex_over_512": big, "est_mb_at_cap": snappedf(mb, 0.1)}
		print("LOWB mats class=%s inst=%d unique_mats=%d unique_tex=%d tex_over_512=%d est_mb_at_cap=%.1f" % [k, e["inst"], (e["mats"] as Dictionary).size(), (e["tex"] as Dictionary).size(), big, mb])
	results["_materials"] = out


static func _textures(m: Material) -> Array:
	var out: Array = []
	if m is BaseMaterial3D:
		for prop in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
			var t = m.get(prop)
			if t is Texture2D:
				out.append(t)
	elif m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		for u: Dictionary in (m as ShaderMaterial).shader.get_shader_uniform_list():
			var v = (m as ShaderMaterial).get_shader_parameter(String(u["name"]))
			if v is Texture2D:
				out.append(v)
	return out
