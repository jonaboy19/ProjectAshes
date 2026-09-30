extends RefCounted
## Region 1 world packages C1 (region layout), C2 (settlement identity) and C10 (border teases): plans the poster's
## places as RegionSites-format sites. One line at the end of RegionSites.plan() appends them (after every older site,
## on their own deterministic search, so no existing site id or position moves).
##
## Data (tools/region1/gen_world_data.py writes it, the JSON is the source of truth):
##   data/region1/world/settlements.json  one landmark, trade, named NPC and rumour set per settlement (20)
##   data/region1/world/sites.json        Highwatch Keep, Greyseam and Elden Elder Stones, Crownstead's Steward's Hall,
##                                        the Eastern Gate, Grimfen Pass, the Scar Mouth Arena, the Dawn Throne chapel,
##                                        the Solkar caravan camp (summer)
## A site is {name, kind, pos, yaw, clear, flatten, parts, lights} plus
##   r1id     stable id ("highwatch_keep", "landmark_millbrook"): Region1World.site(id) finds it in WorldGen.sites
##   x        bodies RegionDressing hands to scripts/world/region1_extras.gd (name board, named NPCs, people, doors, snow)
##   town     the settlement it belongs to; locked/hint: a closed exit the map explains; season: built only then
## The look agent's landmarks (Stagborn Glade, Crownstead Mill Hill, Hollin's Reach, ...) come from
## scripts/region1/region1_landmarks.gd and are not duplicated here.

const DIR := "res://data/region1/world/"
const EAST := 0.0

static var _cache: Dictionary = {}


static func data(file: String) -> Dictionary:
	if not _cache.has(file):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + file)) if FileAccess.file_exists(DIR + file) else {}
		_cache[file] = d if d is Dictionary else {}
	return _cache[file]


## Appends the Region 1 world sites to `out` (RegionSites.plan calls this after the academy and the look landmarks).
static func plan(out: Array[Dictionary], _seed_value: int) -> void:
	if OS.get_cmdline_user_args().has("--r1worldoff"):      # QA A/B
		return
	var sites: Array = data("sites.json").get("sites", [])
	var by_id := {}
	for s: Dictionary in sites:
		by_id[String(s["id"])] = s
	# Canon sites first (they claim their ground), then one landmark per settlement.
	for id: String in ["highwatch_keep", "elder_highwatch", "crownstead_estate", "elder_greyseam", "elder_elden", "dawn_chapel", "eastern_gate",
			"grimfen_pass", "scar_arena", "solkar_camp"]:
		if by_id.has(id):
			var site := _place(by_id[id], out)
			if not site.is_empty():
				out.append(site)
	var elden := _find("elder_elden", out)
	if not elden.is_empty():
		_elden_road(elden, out)
	for st: Dictionary in data("settlements.json").get("settlements", []):
		var s := _settlement_named(String(st["name"]))
		if s.is_empty():
			continue
		var lm: Dictionary = st["landmark"]
		var spec := {"id": "landmark_" + String(st["name"]).to_lower(), "name": lm["name"], "kind": "landmark", "clear": lm["clear"], "flatten": true,
			"parts": lm["parts"], "lights": lm["lights"], "x": lm["x"], "town": st["name"],
			"search": {"center": "settlement:" + String(st["name"]), "d": [float(s["radius"]) * 1.15 + float(lm["clear"]) + 4.0, float(s["radius"]) * 1.15 + float(lm["clear"]) + 70.0],
				"a": [-3.14159, 3.14159], "r": float(lm["clear"]), "slope": 0.2, "prefer_high": 0.0, "d_pref": 0.0, "face": "center", "gate": true}}
		# The named NPC tells the town's rumours too.
		var x: Dictionary = (spec["x"] as Dictionary).duplicate(true)
		for n: Dictionary in x.get("npcs", []):
			n["lines"] = (n.get("lines", []) as Array) + (st.get("rumours", []) as Array)
		spec["x"] = x
		var site := _place(spec, out)
		if site.is_empty():
			site = _place(spec, out, true)        # last resort: looser ground
		if not site.is_empty():
			out.append(site)


# --- placement -------------------------------------------------------------------------

static func _settlement_named(n: String) -> Dictionary:
	for s in WorldGen.settlements:
		if String(s["name"]) == n:
			return s
	return {}


static func _find(r1id: String, out: Array[Dictionary]) -> Dictionary:
	for s in out:
		if String(s.get("r1id", "")) == r1id:
			return s
	return {}


## The site with this r1id in the live world (WorldGen.sites), or {}.
static func site(r1id: String) -> Dictionary:
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) == r1id:
			return s
	return {}


static func _center(c: Variant, out: Array[Dictionary]) -> Vector2:
	if c is Array:
		return Vector2(float(c[0]), float(c[1]))
	var t := String(c)
	if t.begins_with("settlement:"):
		var s := _settlement_named(t.substr(11))
		return s["pos"] if not s.is_empty() else Vector2.INF
	if t.begins_with("site:"):
		for s in out:
			if String(s["name"]) == t.substr(5):
				return s["pos"]
	return Vector2.INF


## Turns one JSON spec into a site at the best free ground of its search block ({} when nothing fits).
static func _place(spec: Dictionary, out: Array[Dictionary], loose := false) -> Dictionary:
	var sr: Dictionary = spec["search"]
	var pos := Vector2.INF
	var c := Vector2.INF
	var rel_yaw := 0.0
	if sr.has("relative_to"):        # fixed offset in another site's frame (the Highwatch Elder Stone stands before the gate)
		var base := _find(String(sr["relative_to"]), out)
		if base.is_empty():
			return {}
		var off: Array = sr["offset"]
		rel_yaw = float(base["yaw"])
		pos = (base["pos"] as Vector2) + Vector2(float(off[0]), float(off[1])).rotated(-rel_yaw)
		c = base["pos"]
	else:
		c = _center(sr["center"], out)
		if c == Vector2.INF:
			return {}
		pos = _search(c, sr, float(spec["clear"]), out, loose)
	if pos == Vector2.INF:
		push_warning("Region1World: no ground for %s" % spec["name"])
		return {}
	var yaw := 0.0
	match String(sr.get("face", "none")):
		"center": yaw = RegionSites._yaw_to((c - pos).normalized())
		"west": yaw = RegionSites._yaw_to(Vector2(-1, 0))
		"east": yaw = RegionSites._yaw_to(Vector2(1, 0))
		"south": yaw = RegionSites._yaw_to(Vector2(0, 1))
		"rift": yaw = RegionSites._yaw_to((c - pos).normalized())
		_: yaw = rel_yaw if sr.has("relative_to") else float(spec.get("yaw", 0.0))
	var site := RegionSites._site(String(spec["name"]), String(spec["kind"]), pos, yaw, float(spec["clear"]), bool(spec.get("flatten", true)))
	site["r1id"] = String(spec["id"])
	for k: String in ["town", "hint", "hooks"]:
		if spec.has(k):
			site[k] = spec[k]
	for k: String in ["locked", "season"]:
		if spec.has(k):
			site[k] = spec[k]
	for p: Array in spec.get("parts", []):
		RegionSites._part(site, String(p[0]), Vector2(float(p[1]), float(p[2])), deg_to_rad(float(p[3])), int(p[4]) != 0)
		if float(p[5]) != 0.0:
			(site["parts"][site["parts"].size() - 1] as Array).append(float(p[5]))
	for l: Array in spec.get("lights", []):
		var col: Array = l[3]
		site["lights"].append([Vector3(float(l[0]), float(l[1]), float(l[2])), Color(float(col[0]), float(col[1]), float(col[2])), float(l[4]), bool(l[5])])
	if spec.has("x"):
		site["x"] = spec["x"]
	return site


## Best ground in an annulus/arc around `c`: dry, off roads, clear of everything planned so far, gentle.
## Score: nearer the preferred distance, flatter, (optionally) higher, (optionally) toward the settlement's gate.
static func _search(c: Vector2, sr: Dictionary, clear: float, out: Array[Dictionary], loose: bool) -> Vector2:
	var d: Array = sr["d"]
	var a: Array = sr["a"]
	var r := float(sr.get("r", clear))
	var slope_max := float(sr.get("slope", 0.2)) * (1.6 if loose else 1.0)
	var wh := float(sr.get("prefer_high", 0.0))
	var d_pref := float(sr.get("d_pref", 0.0))
	var gate := INF
	if bool(sr.get("gate", false)):
		for s in WorldGen.settlements:
			if s["pos"] == c:
				var gs := WorldGen.gate_angles(s)
				if not gs.is_empty():
					gate = gs[0]
	var best := Vector2.INF
	var best_score := -INF
	var n_ang := 48
	var n_d := 9
	for ia in n_ang + 1:
		var ang := lerpf(float(a[0]), float(a[1]), float(ia) / n_ang)
		for idd in n_d:
			var dist := lerpf(float(d[0]), float(d[1]), float(idd) / (n_d - 1))
			var q := c + Vector2(cos(ang), sin(ang)) * dist
			if not RegionSites._free(q, r, out, 4.0 if loose else 8.0):
				continue
			var sl := RegionSites._slope(q)
			if sl > slope_max:
				continue
			var score := -sl * 18.0 + wh * WorldGen.height(q.x, q.y)
			if d_pref > 0.0:
				score -= absf(dist - d_pref) / 140.0
			if gate != INF:
				score -= absf(angle_difference(ang, gate)) * 0.9
			score -= WorldGen.forest_density(q.x, q.y) * 1.5
			if score > best_score:
				best_score = score
				best = q
	return best


## The Elden Road: a waymark every ~70 m from the Shrine of the Sleeping Flame to the Elden Elder Stone (kind "waystone",
## so the map does not list each one).
static func _elden_road(elder: Dictionary, out: Array[Dictionary]) -> void:
	var shrine := Vector2.INF
	for s in out:
		if String(s.get("kind", "")) == "shrine":
			shrine = s["pos"]
	if shrine == Vector2.INF:
		return
	var end: Vector2 = elder["pos"]
	var line := end - shrine
	var n := int(line.length() / 70.0)
	var kinds := ["a_slab", "d_pillar", "b_menhir", "c_squat"]
	for i in range(1, n):
		var p := shrine + line * (float(i) / n)
		p += Vector2(-line.y, line.x).normalized() * (9.0 if i % 2 == 0 else -9.0)
		if WorldGen.near_water(p.x, p.y, 4.0) or not RegionSites._free(p, 1.5, out, 3.0, true):
			continue
		var st := RegionSites._site("Elden Waymark", "waystone", p, RegionSites._yaw_to(-line.normalized()))
		st["r1id"] = "elden_waymark_%d" % i
		RegionSites._part(st, "r1:stones/road_stone_" + String(kinds[i % kinds.size()]), Vector2.ZERO, 0.0, true)
		out.append(st)
