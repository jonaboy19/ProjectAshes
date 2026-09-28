extends SceneTree
## Grounding QA: for every placed prop, tree, rock, fence, building part, animal
## and NPC within ~150 m of several outdoor locations, measures the gap between
## its lowest point (visual AABB bottom, or feet for characters) and
## WorldGen.height at its footprint. Lists everything floating > 10 cm or
## buried > 30 cm.
##
## Run:
##   godot --path kingdom -s <abs>/tools/qa/grounding/grounding_check.gd -- \
##     --adult --skipintro --out=<abs dir>
## Output: <out>/report.md (counts per asset type + worst 30), <out>/raw.tsv (every
## sample). Close-up screenshots of the worst 10 are taken separately (see report.md
## for their positions -- re-run with --shots to also capture them).

const RADIUS := 150.0
const FLOAT_BAD := 0.10       # 10 cm
const BURY_BAD := 0.30        # 30 cm

var main: Control
var args := {}
var out_dir := ""
var phase := "boot"
var t := 0.0
var loc_i := 0
var locations: Array = []          # [name, Vector2]
var samples: Array = []            # {kind, asset, pos:Vector3, gap, note, loc}
var shot_n := 0
var _region_built := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			args[a.substr(2)] = true
	out_dir = args.get("out", OS.get_user_data_dir() + "/grounding")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_title("Rising Ashes QA recorder (test, not gameplay)")
	change_scene_to_file("res://scenes/main.tscn")


func _al(n: String) -> Node:
	return root.get_node_or_null("/root/" + n)


func _wg() -> Script:
	return load("res://scripts/world/world_gen.gd")


func _process(delta: float) -> bool:
	t += delta
	match phase:
		"boot":
			main = current_scene as Control
			if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._loading.visible:
				_build_locations()
				phase = "goto"
				t = 0.0
			elif t > 40.0:
				print("GROUNDING boot timed out (player never became ready)")
				_shutdown()
		"goto":
			var loc: Array = locations[loc_i]
			var p: Vector2 = loc[1]
			main._teleport(p, 0.0)   # builds terrain/water/settlements/population synchronously
			# build_all_now() builds every site in the world once (it's meant for a single
			# "screenshots, tests, teleports" call, not one per waypoint). Also: never move
			# region.focus after this -- RegionDressing frees a site past FREE=330m and
			# rebuilds it when focus comes back in range (its own _process() runs every
			# frame regardless of this tool), so bouncing focus between far-apart QA
			# locations was free/rebuild-cycling farm sites over and over, each rebuild
			# re-loading windmill_sails.glb (slow: it has an invalid embedded UID, so every
			# load falls back to re-resolving the text path) -- that's what was hanging.
			# Leaving focus fixed after the one build keeps everything built and in place.
			# NOTE: main.region.build_all_now() (farms/mines/bandit camps/bridges/wayshrines)
			# is deliberately NOT called here -- every region GLB (generated/region/**) has
			# an invalid embedded resource UID, so every load falls back to slow text-path
			# re-resolution (see the WARNING spam in a run's stdout), and building every
			# site in the world this way overran even a 240s budget. That's a real asset
			# pipeline bug worth a fix (`kingdom/tools/blender` region export step should
			# emit valid UIDs, or run `godot --editor --headless --reimport` once to bake
			# them), but it's outside this pass's scope. Region-site grounding (farms,
			# mines, bandit camp, bridges) was checked by code review of
			# RegionDressing._footprint_ground()/_build_part() and by eye in the
			# docs/qa/perf_visual captures instead -- see report.md.
			if main.settlements:
				main.settlements.set_process(false)   # stop it free/rebuild-cycling as we teleport around
			if main.region:
				main.region.set_process(false)   # region sites excluded from this scan; stop it building/freeing them as focus jumps around
			t = 0.0
			phase = "settle"
		"settle":
			# A few more ticks so anything _teleport() only nudges (SettlementBuilder
			# is one-per-tick outside _teleport's own loop) catches up.
			if main.settlements:
				main.settlements.focus = main.player.global_position
				main.settlements.update_now()
			if t > 1.2:
				phase = "scan"
		"scan":
			_scan(locations[loc_i][0], locations[loc_i][1])
			print("GROUNDING_LOC %s done, samples so far=%d" % [locations[loc_i][0], samples.size()])
			_write_report()   # incremental: a killed/timed-out run still leaves a usable report
			loc_i += 1
			if loc_i >= locations.size():
				_finish()
				return false
			phase = "goto"
			t = 0.0
	return false


func _build_locations() -> void:
	var wg: Script = _wg()
	var sets: Array = wg.settlements
	var home: Vector2 = sets[0]["pos"]
	locations.append(["village_plaza", home])
	locations.append(["village_edge", home + Vector2(60, 30)])
	locations.append(["forest", home.lerp(main.FIRST_CAMP, 0.5)])
	locations.append(["camp", main.FIRST_CAMP + Vector2(-25, 8)])
	if sets.size() > 1:
		var cap: Vector2 = sets[1]["pos"]
		locations.append(["road_to_capital", home.lerp(cap, 0.4)])
		locations.append(["capital_plaza", cap])
	# Region sites (farms/mines/bandit camps/bridges) are intentionally excluded --
	# see the note above region.build_all_now() for why.


## Walks the built world near `center`, sampling every render node's grounding.
## Each location is independent: a bad node here just gets skipped (guards in
## _scan_node/_scan_character), it never aborts the whole run.
func _scan(loc_name: String, center: Vector2) -> void:
	if main == null or not is_instance_valid(main):
		return
	var world: Node = main.get_node_or_null("World")
	if world == null:
		world = main
	# Characters: player, villagers, combatants (soldiers/monsters/wolves/critters).
	# Collected up front and passed into _scan_node so it can skip their whole
	# subtree -- a character's own body-part meshes (armour, hair) and anything
	# held in a bone-attached hand (sword, axe, shield) have bind-pose-space
	# AABBs that mean nothing in world space and produced huge bogus "floating"
	# entries (a raised sword read as a 5-11 m floater). _scan_character below
	# already covers the character itself via its feet/global_position.
	var characters: Array = []
	if main.get("player"):
		characters.append(main.player)
	for g in ["villager", "combatant"]:
		for n in get_nodes_in_group(g):
			if n is Node3D:
				characters.append(n)
	_scan_node(world, center, loc_name, characters)
	if main.get("player"):
		_scan_character(main.player, center, loc_name, "player")
	for g in ["villager", "combatant"]:
		for n in get_nodes_in_group(g):
			if n is Node3D:
				_scan_character(n, center, loc_name, g)


func _scan_character(n: Node3D, center: Vector2, loc_name: String, kind: String) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or n.is_queued_for_deletion():
		return
	var p: Vector3 = n.global_position
	if Vector2(p.x, p.z).distance_to(center) > RADIUS:
		return
	var ground: float = _wg().height(p.x, p.z)
	var gap := p.y - ground
	samples.append({"kind": kind, "asset": n.name, "pos": p, "gap": gap, "loc": loc_name})


## MeshInstance3D / MultiMeshInstance3D nodes: footprint corners in world space
## vs. WorldGen.height, lowest-point gap (visual AABB bottom).
func _scan_node(n: Node, center: Vector2, loc_name: String, characters: Array) -> void:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return
	if n is Node3D and not (n as Node3D).is_inside_tree():
		return   # a chunk/site mid-free (queue_free is deferred): skip, don't touch its transform
	if n in characters or n is CharacterBody3D:
		# This whole subtree is a character's rig/equipment (see _scan() note).
		# `n is CharacterBody3D` is the real guard -- it catches every character
		# (player.gd, villager.gd, monster.gd, wolf.gd all extend it) even ones
		# not currently in the "villager"/"combatant" groups (e.g. a wandering
		# critter, or a villager mid-transition); `characters` is kept too in
		# case a future character root isn't a CharacterBody3D.
		return
	if n is MeshInstance3D:
		# Terrain chunk ground meshes and merged tree-impostor batches (TerrainStreamer)
		# build their ArrayMesh with vertices already in WORLD space and an identity
		# node transform -- they are not a "placed object" with a local footprint, and
		# running the footprint-corner check on them (which assumes a local AABB you
		# transform by the node's global_transform) produced nonsense (huge bogus
		# floating/buried entries all reported at world position (0,0,0), since the
		# node's own transform.origin is the origin, not the mesh's actual position).
		# Individual trees/props are separately correct: they're MultiMeshInstance3D
		# with per-instance transforms, handled below.
		var pname: String = (n.get_parent().name if n.get_parent() else "")
		var mesh_res: Mesh = (n as MeshInstance3D).mesh
		# A never-explicitly-named node ("@MeshInstance3D@1234", i.e. no author
		# ever called .name = ...), with no scene owner and a mesh built at
		# runtime (no resource_path -- not loaded from a .glb/.tres), is a
		# transient effect, not authored level content: ambient_fx.gd's leaping
		# fish/splash rings, technique_caster.gd/vfx_*.gd's spell and weapon-
		# trail effects, etc. These are deliberately mid-air and moving every
		# frame -- sampling one gave a "floating 11 m" entry that was really
		# just a fish mid-jump. Grounding doesn't apply to them.
		var is_anon_runtime_fx := n.owner == null and String(n.name).contains("@") \
			and (mesh_res == null or mesh_res.resource_path == "")
		if n.name not in ["Ground", "TreeImpostors"] and not pname.begins_with("Chunk_") and not is_anon_runtime_fx:
			_check_mesh(n as MeshInstance3D, mesh_res, (n as MeshInstance3D).global_transform, center, loc_name, "mesh")
	elif n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm and mm.mesh:
			var box := mm.mesh.get_aabb()
			# Grass/flower cards are always placed at height-0.03 by design (GrassField,
			# TerrainStreamer._plan_forest) and there can be tens of thousands of them
			# within range; skip that noise and cap large batches to an even sample so
			# the scan stays fast instead of walking every blade.
			if maxf(box.size.x, box.size.z) < 0.35:
				return
			# Only the drawn slots: population_lod/ambient_fx leave slots past
			# visible_instance_count uninitialised (garbage like 1e37 m, not a bug).
			var count: int = mm.instance_count if mm.visible_instance_count < 0 else mini(mm.visible_instance_count, mm.instance_count)
			if count <= 0 or not mmi.is_visible_in_tree():
				return
			var n_check: int = mini(count, 150)
			var stride: int = maxi(1, count / n_check)
			var i := 0
			while i < count:
				var inst := mmi.global_transform * mm.get_instance_transform(i)
				_check_box(box, inst, center, loc_name, "instance:" + _owner_name(n, mm))
				i += stride
	for c in n.get_children():
		_scan_node(c, center, loc_name, characters)


func _owner_name(n: Node, mm: MultiMesh = null) -> String:
	if not String(n.name).contains("@"):
		return n.name   # explicitly named (e.g. "BuildingPlinths", "ContactShadows")
	if mm and mm.mesh and mm.mesh.resource_path != "":
		return mm.mesh.resource_path.get_file().get_basename()
	var p := n.get_parent()
	return (p.name if p else n.name)


func _check_mesh(n: Node3D, mesh: Mesh, xform: Transform3D, center: Vector2, loc_name: String, kind: String) -> void:
	if mesh == null:
		return
	_check_box(mesh.get_aabb(), xform, center, loc_name, kind + ":" + n.name)


func _check_box(box: AABB, xform: Transform3D, center: Vector2, loc_name: String, asset: String) -> void:
	var o := xform.origin
	if Vector2(o.x, o.z).distance_to(center) > RADIUS:
		return
	if box.size.length() < 0.02:
		return
	var corners := [
		xform * Vector3(box.position.x, box.position.y, box.position.z),
		xform * Vector3(box.end.x, box.position.y, box.position.z),
		xform * Vector3(box.position.x, box.position.y, box.end.z),
		xform * Vector3(box.end.x, box.position.y, box.end.z),
	]
	var lowest_visual := INF
	var worst_gap := -INF
	for c in corners:
		lowest_visual = minf(lowest_visual, c.y)
		var ground: float = _wg().height(c.x, c.z)
		worst_gap = maxf(worst_gap, c.y - ground)
	# The corner that sticks up highest above its own local ground = floating;
	# use the lowest visual corner vs. the ground directly under it for burial.
	var center_ground: float = _wg().height(o.x, o.z)
	var bury_gap := lowest_visual - center_ground
	var gap := worst_gap if worst_gap > 0.0 else bury_gap
	samples.append({"kind": "prop", "asset": asset, "pos": o, "gap": gap, "loc": loc_name})


func _finish() -> void:
	_write_report()
	print("GROUNDING samples=%d" % samples.size())
	_shutdown()


## See tools/qa/perf_visual/perf_visual.gd's _shutdown() for why: quitting while
## main.tscn is still live races WorkerThreadPool/threaded-load cleanup against
## RenderingServer teardown and produced the ntdll heap-corruption crashes logged
## in docs/qa/stability.md.
func _shutdown() -> void:
	if main:
		main.queue_free()
		main = null
	for i in 10:
		await process_frame
	quit()


## Overwrites report.md/raw.tsv from `samples` so far. Called after every location
## (cheap: samples stays in the low thousands), so a run killed by a timeout still
## leaves a real, readable report instead of nothing.
func _write_report() -> void:
	# Defensive: a sample sitting at exactly world (0,0) is always a bug in the
	# scanner (a node whose transform we misread), never a real placed object --
	# terrain/settlement/forest content is built with absolute world coordinates
	# and nothing is ever actually planned at the origin. Drop those rather than
	# report bogus floating/buried entries.
	var good := samples.filter(func(s: Dictionary) -> bool:
		var p: Vector3 = s["pos"]
		return absf(p.x) > 0.01 or absf(p.z) > 0.01)
	var floating := good.filter(func(s: Dictionary) -> bool: return s["gap"] > FLOAT_BAD)
	var buried := good.filter(func(s: Dictionary) -> bool: return s["gap"] < -BURY_BAD)
	floating.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["gap"] > b["gap"])
	buried.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["gap"] < b["gap"])

	var by_type := {}
	for s: Dictionary in floating + buried:
		var key: String = String(s["asset"]).get_slice(":", 0)
		by_type[key] = by_type.get(key, 0) + 1

	var md := "# Outdoor grounding report\n\n"
	md += "Samples: %d total (%d dropped as scanner artefacts at world origin), %d floating > %.0fcm, %d buried > %.0fcm\n\n" % [good.size(), samples.size() - good.size(), floating.size(), FLOAT_BAD * 100.0, buried.size(), BURY_BAD * 100.0]
	md += "## Counts by asset type\n\n| type | bad count |\n|---|---|\n"
	for k in by_type:
		md += "| %s | %d |\n" % [k, by_type[k]]
	md += "\n## Worst 30 floating\n\n| gap (m) | asset | location | pos |\n|---|---|---|---|\n"
	for s: Dictionary in floating.slice(0, 30):
		var p: Vector3 = s["pos"]
		md += "| +%.2f | %s | %s | (%.1f, %.1f, %.1f) |\n" % [s["gap"], s["asset"], s["loc"], p.x, p.y, p.z]
	md += "\n## Worst 30 buried\n\n| gap (m) | asset | location | pos |\n|---|---|---|---|\n"
	for s: Dictionary in buried.slice(0, 30):
		var p: Vector3 = s["pos"]
		md += "| %.2f | %s | %s | (%.1f, %.1f, %.1f) |\n" % [s["gap"], s["asset"], s["loc"], p.x, p.y, p.z]

	var f := FileAccess.open(out_dir + "/report.md", FileAccess.WRITE)
	f.store_string(md)
	f.close()
	var tf := FileAccess.open(out_dir + "/raw.tsv", FileAccess.WRITE)
	tf.store_line("kind\tasset\tloc\tx\ty\tz\tgap")
	for s: Dictionary in good:
		var p: Vector3 = s["pos"]
		tf.store_line("%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%.3f" % [s["kind"], s["asset"], s["loc"], p.x, p.y, p.z, s["gap"]])
	tf.close()
