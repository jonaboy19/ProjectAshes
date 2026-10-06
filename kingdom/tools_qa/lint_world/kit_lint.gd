extends RefCounted
## Headless lint of what the town kit places by hand in all 30 towns (data/region1/towns/*.json): clues, stashes, livestock groups,
## rail-fence pens, the den of the local threat and the draw cost of the hub's own nodes. The settlement builder's buildings and props
## are linted by lint_core.gd; this covers the part the hubs build afterwards (town_hub.gd), which the core never sees.
##
##   issue {type, severity, town, what, pos [x, z], detail}
##   water    a clue / stash / group / pen / den in or next to water               severe (pens, clues, stashes, groups), major (den)
##   steep    ground under it is too uneven (town_ground.gd limits)                 severe above 2x the limit, else major
##   piece    a pen fence piece whose ends are > PEN_MAX_PIECE_DROP apart           major (floating / buried rail end)
##   road     a pen fence piece on the road                                         major
##   building a clue / stash / pen inside a building's lot                           severe
##   draws    the hub's props (clues + stashes + pens) draw more than KIT_DRAWS      minor
## `run(tree)` returns the issues; `severe(issues)` filters. Needs the autoloads (call it from a test or from kit_lint_cli.gd).

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const TownLivestock := preload("res://scripts/world/town_kit/town_livestock.gd")
const TownClues := preload("res://scripts/world/town_kit/town_clues.gd")
const TownThreat := preload("res://scripts/world/town_kit/town_threat.gd")
const Ground := preload("res://scripts/world/town_kit/town_ground.gd")
const KIT_DRAWS := 24                   # a hub's clues + stashes + pens (phone budget: the whole town view stays under 150 draws)

var issues: Array = []
var stats := {"moved": 0, "dropped": 0, "towns": 0, "clues": 0, "stashes": 0, "pens": 0, "groups": 0, "dens": 0, "fence_pieces": 0}
var notes: Array = []                 # "town what: moved N m / dropped"
var per_town: Dictionary = {}           # tid -> {clues, stashes, pens, groups, draws}


func _add(type: String, sev: String, tid: String, what: String, p: Vector2, detail: String) -> void:
	issues.append({"type": type, "severity": sev, "town": tid, "what": what, "pos": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)], "detail": detail})


func severe() -> Array:
	return issues.filter(func(i: Dictionary) -> bool: return i["severity"] == "severe")


func count(sev: String) -> int:
	return issues.filter(func(i: Dictionary) -> bool: return i["severity"] == sev).size()


## Lints every town file (or just `only` = [tid, ...]). `scene_parent` = a Node to build the hub props under for the draw count
## (null = skip the draw check).
func run(scene_parent: Node = null, only: Array = []) -> void:
	for tid: String in TownData.ids():
		if not only.is_empty() and not only.has(tid):
			continue
		stats["towns"] += 1
		per_town[tid] = {"clues": 0, "stashes": 0, "pens": 0, "groups": 0, "draws": 0}
		_lint_town(tid)
		if scene_parent != null:
			_lint_draws(tid, scene_parent)
	issues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _rank(a) > _rank(b))


static func _rank(i: Dictionary) -> int:
	return {"severe": 3, "major": 2, "minor": 1}.get(String(i["severity"]), 0)


func _lint_town(tid: String) -> void:
	var doc := TownData.town(tid)
	for kind: String in ["clues", "stashes"]:
		for d: Dictionary in doc.get(kind, []):
			var w := TownPlaces.resolve(tid, d)
			if w == Vector2.INF:
				continue
			stats[kind] += 1
			per_town[tid][kind] += 1
			var what := "%s %s" % [kind.trim_suffix("es").trim_suffix("s"), String(d["id"])]
			var spot := TownClues.spot(tid, d)
			if spot == Vector2.INF:
				stats["dropped"] += 1
				notes.append("%s %s dropped (no level dry ground within 12 m)" % [tid, what])
				continue
			if spot != w:
				stats["moved"] += 1
				notes.append("%s %s moved %.1f m" % [tid, what, spot.distance_to(w)])
			_lint_prop(tid, what, spot)
	for g: Dictionary in TownLivestock.groups(tid):
		stats["groups"] += 1
		per_town[tid]["groups"] += 1
		_lint_group(tid, g)
	_lint_pens(tid, doc)
	var t: Dictionary = doc.get("threat", {})
	if not t.is_empty():
		var s := TownPlaces.settlement(tid)
		if not s.is_empty():
			var ring := Vector2(float(t["den_ring"][0]), float(t["den_ring"][1])) if t.has("den_ring") else TownThreat.DEN_RING
			var site := TownThreat.den_site(s["pos"], ring)
			if site != Vector2.INF:
				stats["dens"] += 1
				_lint_den(tid, site)


func _lint_prop(tid: String, what: String, w: Vector2) -> void:
	if WorldGen.near_water(w.x, w.y, 0.5) or WorldGen.is_water(w.x, w.y):
		_add("water", "severe", tid, what, w, "stands in or at the edge of water")
	var rel := Ground.relief_ring(w, Ground.PROP_RING)
	if rel > Ground.PROP_LINT_RELIEF:
		_add("steep", "severe" if rel > 2.0 * Ground.PROP_LINT_RELIEF else "major", tid, what, w,
			"%.2f m of ground relief under a %.1f m footprint (limit %.2f)" % [rel, Ground.PROP_RING * 2.0, Ground.PROP_LINT_RELIEF])
	if Ground.inside_building(tid, w, 0.0):
		_add("building", "severe", tid, what, w, "inside a building's footprint")


func _lint_group(tid: String, g: Dictionary) -> void:
	var p: Vector2 = g["pos"]
	var what := "livestock %s" % String(g["tag"])
	if WorldGen.near_water(p.x, p.y, Ground.WET):
		_add("water", "severe", tid, what, p, "group centre within %.0f m of water" % Ground.WET)
	var rel := Ground.relief_ring(p, Ground.GROUP_RING)
	if rel > Ground.GROUP_MAX_RELIEF:
		_add("steep", "severe" if rel > 2.0 * Ground.GROUP_MAX_RELIEF else "major", tid, what, p, "%.1f m of relief within %.0f m (limit %.1f)" % [rel, Ground.GROUP_RING, Ground.GROUP_MAX_RELIEF])


func _lint_pens(tid: String, doc: Dictionary) -> void:
	for p: Dictionary in (doc.get("livestock", {}) as Dictionary).get("pens", []):
		var frame := TownPlaces.frame(tid, String(p.get("anchor", "")))
		if frame.is_empty():
			continue
		stats["pens"] += 1
		per_town[tid]["pens"] += 1
		var size := Vector2(float(p["size"][0]), float(p["size"][1]))
		var yaw := float(frame["yaw"]) + float(p.get("yaw", 0.0))
		var centre := TownPlaces.to_world(frame, Vector2(float(p["at"][0]), float(p["at"][1])))
		var what := "pen %s" % String(p.get("anchor", ""))
		var placed := TownLivestock.pen_spot(tid, p)
		if placed.is_empty():
			stats["dropped"] += 1
			notes.append("%s %s dropped (no level dry ground within 40 m)" % [tid, what])
			continue          # skipped by the kit on purpose (steep or wet all around): not a bug
		if (placed["pos"] as Vector2).distance_to(centre) > 0.01:
			stats["moved"] += 1
			notes.append("%s %s moved %.1f m" % [tid, what, (placed["pos"] as Vector2).distance_to(centre)])
		centre = placed["pos"]
		yaw = placed["yaw"]
		if WorldGen.near_water(centre.x, centre.y, 3.0) or Ground.rect_wet(centre, size, yaw):
			_add("water", "severe", tid, what, centre, "pen footprint touches water")
		var rel := Ground.relief_rect(centre, size, yaw)
		if rel > Ground.PEN_MAX_RELIEF:
			_add("steep", "severe" if rel > 2.0 * Ground.PEN_MAX_RELIEF else "major", tid, what, centre,
				"%.1f m of ground relief under a %dx%d m pen (limit %.1f)" % [rel, int(size.x), int(size.y), Ground.PEN_MAX_RELIEF])
		if Ground.near_building(tid, centre, maxf(size.x, size.y) * 0.5):
			_add("building", "severe", tid, what, centre, "pen overlaps a building lot")
	for xf: Transform3D in TownLivestock.pen_transforms(tid):
		stats["fence_pieces"] += 1
		var drop := TownLivestock.piece_drop(xf)
		if drop > Ground.PEN_MAX_PIECE_DROP:
			_add("piece", "major", tid, "fence piece", Vector2(xf.origin.x, xf.origin.z), "ends %.2f m apart in height (limit %.2f)" % [drop, Ground.PEN_MAX_PIECE_DROP])
		if Ground.on_road(Vector2(xf.origin.x, xf.origin.z), 0.0):
			_add("road", "major", tid, "fence piece", Vector2(xf.origin.x, xf.origin.z), "fence piece on the road")


func _lint_den(tid: String, p: Vector2) -> void:
	if WorldGen.near_water(p.x, p.y, 8.0):
		_add("water", "major", tid, "den", p, "den site within 8 m of water")
	var rel := Ground.relief_ring(p, 8.0)
	if rel > Ground.DEN_MAX_RELIEF:
		_add("steep", "major", tid, "den", p, "%.1f m of relief within 8 m (limit %.1f)" % [rel, Ground.DEN_MAX_RELIEF])


## Builds the hub's own props under `parent` and counts the distinct mesh + material surfaces.
func _lint_draws(tid: String, parent: Node) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	var nodes: Array = TownClues.build_clues(tid, root) + TownClues.build_stashes(tid, root)
	var pens := TownLivestock.build_pens(tid, root)
	var seen := {}
	for n: Node in [root]:
		_collect(n, seen)
	per_town[tid]["draws"] = seen.size()
	if seen.size() > KIT_DRAWS:
		_add("draws", "minor", tid, "hub props", Vector2.ZERO, "%d distinct draws from %d clue/stash props and %s (budget %d)" % [seen.size(), nodes.size(), str(pens != null), KIT_DRAWS])
	root.free()


func _collect(n: Node, seen: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.material_override if mi.material_override != null else mi.mesh.surface_get_material(s)
			seen["%d|%d" % [mi.mesh.get_instance_id(), m.get_instance_id() if m != null else 0]] = true
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			for s in mm.mesh.get_surface_count():
				var m2: Material = mm.mesh.surface_get_material(s)
				seen["%d|%d" % [mm.mesh.get_instance_id(), m2.get_instance_id() if m2 != null else 0]] = true
	for c in n.get_children():
		_collect(c, seen)


func text() -> String:
	var lines: Array[String] = []
	lines.append("(%d props/pens moved to better ground, %d dropped)" % [stats["moved"], stats["dropped"]])
	lines.append("KIT LINT: %d towns, %d clues, %d stashes, %d pens (%d fence pieces), %d livestock groups, %d dens: %d severe, %d major, %d minor" % [
		stats["towns"], stats["clues"], stats["stashes"], stats["pens"], stats["fence_pieces"], stats["groups"], stats["dens"], count("severe"), count("major"), count("minor")])
	for i: Dictionary in issues:
		lines.append("  [%s] %-8s %-12s %-24s @(%s, %s)  %s" % [String(i["severity"]).to_upper(), i["type"], i["town"], i["what"], i["pos"][0], i["pos"][1], i["detail"]])
	for n: String in notes:
		lines.append("  note: " + n)
	var worst: Array = per_town.keys()
	worst.sort_custom(func(a: String, b: String) -> bool: return int(per_town[a]["draws"]) > int(per_town[b]["draws"]))
	lines.append("hub prop draws (worst 5): " + ", ".join(worst.slice(0, 5).map(func(t: String) -> String: return "%s %d" % [t, per_town[t]["draws"]])))
	return "\n".join(lines)
