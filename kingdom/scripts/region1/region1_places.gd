extends RefCounted
## Story place ids (data/region1/quests/r1_registry.json) -> positions in the running world.
##
## The quest data names places by registry id (`miller_stone`, `greenhollow_farm`, `elder_glade`, ...).
## Some exist as WorldGen settlements or discovery places today; the rest are placed by the world
## layout work (C1) and may not exist yet. Resolution order, per id:
##   1. an explicit override (`set_override`, tests and the layout agent);
##   2. a named place in Life.discovery (settlements, region sites, lore places, camps) matching one of
##      the id's known names or keywords (`NAMES`), e.g. greenhollow = "Greenhollow" or the old "Oakvale";
##   3. a place in data/world/first_region.json with that id;
##   4. the registry's proposed position, in metres from Ashford (Ashford = WorldGen.settlements[0]).
## So triggers keyed by these ids keep working when a better site appears: the lookup is repeated
## (cached per 5 s), not baked in.

const REGISTRY := "res://data/region1/quests/r1_registry.json"
const CACHE_SECONDS := 5.0

## id -> candidate discovery names / keyword lists ("a+b" = all keywords present, lower case).
const NAMES := {
	"ashford": ["Ashford"],
	"kingsreach": ["Kingsreach"],
	"greenhollow": ["Greenhollow", "Oakvale"],
	"silverford": ["Silverford"],
	"highwatch_keep": ["Highwatch Keep", "Highwatch", "Highcliff"],
	"greyseam_mine": ["Greyseam Mine"],
	"rifts_edge_camp": ["Rift's Edge Camp"],
	"ashen_scar": ["The Ashen Scar", "Ashen Scar"],
	"rift_mouth": ["The Rift"],
	"crownstead": ["Crownstead"],
	"stagborn_glade": ["Stagborn Glade"],
	"elden_road": ["Elden Road", "The Elden Road"],
	"duskbriar_wood": ["Duskbriar Wood"],
	"duskbriar_bandit_camp": ["Bandit Camp+duskbriar", "Bandit Camp"],
	"grimfen_pass": ["Grimfen Pass"],
	"elder_glade": ["elder+stagborn", "elder+glade"],
	"elder_greyseam": ["elder+greyseam"],
	"elder_highwatch": ["elder+highwatch"],
	"elder_crownstead": ["elder+crownstead"],
	"elder_elden": ["elder+elden"],
}
## Trigger radius in metres when the source place does not carry a useful one.
const RADIUS := {
	"ashford_ring": 26.0, "miller_stone": 22.0, "old_mill_staff_yard": 24.0, "greenhollow_farm": 50.0,
	"greenhollow_south_fields": 70.0, "greenhollow_road": 60.0, "silverford_guild_hall": 30.0, "silverford_market": 40.0,
	"kingsreach_council_hall": 35.0, "greyseam_seam": 30.0, "highwatch_gate": 40.0, "rift_mouth": 60.0,
	"ashen_scar": 120.0, "rifts_edge_camp": 60.0, "stagborn_glade": 70.0, "elden_road": 70.0,
	"duskbriar_bandit_camp": 60.0, "crownstead": 90.0, "greyseam_mine": 70.0,
}
const DEFAULT_RADIUS := 45.0
## Short names for text leads.
const LEAD_NAMES := {
	"ashford": "Ashford", "ashford_ring": "the runestone circle", "miller_stone": "the Miller's Stone",
	"old_mill_staff_yard": "the Old Mill staff yard",
}

static var _overrides: Dictionary = {}
static var _cache: Dictionary = {}
static var _cache_at := -1000.0
static var _registry: Dictionary = {}


static func clear() -> void:
	_overrides.clear()
	_cache.clear()
	_cache_at = -1000.0


static func set_override(id: String, pos: Vector2, radius := -1.0) -> void:
	_overrides[id] = {"pos": pos, "radius": radius if radius > 0.0 else float(RADIUS.get(id, DEFAULT_RADIUS)), "source": "override"}
	_cache.erase(id)


static func registry() -> Dictionary:
	if _registry.is_empty() and FileAccess.file_exists(REGISTRY):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
		if d is Dictionary:
			_registry = d
	return _registry


static func place_name(id: String) -> String:
	if LEAD_NAMES.has(id):
		return String(LEAD_NAMES[id])
	var p: Dictionary = (registry().get("places", {}) as Dictionary).get(id, {})
	return String(p.get("name", id.replace("_", " ").capitalize()))


## {pos: Vector2, radius: float, source: String} or {} when the id is unknown everywhere.
static func resolve(id: String) -> Dictionary:
	if _overrides.has(id):
		return _overrides[id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - _cache_at > CACHE_SECONDS:
		_cache.clear()
		_cache_at = now
	if _cache.has(id):
		return _cache[id]
	var r := _lookup(id)
	_cache[id] = r
	return r


static func position_of(id: String) -> Variant:
	var r := resolve(id)
	return r["pos"] if not r.is_empty() else null


static func _home() -> Vector2:
	return (WorldGen.settlements[0]["pos"] as Vector2) if not WorldGen.settlements.is_empty() else Vector2.ZERO


static func _lookup(id: String) -> Dictionary:
	var rad := float(RADIUS.get(id, DEFAULT_RADIUS))
	# 2. discovery places by name
	var life: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Life") if Engine.get_main_loop() is SceneTree else null
	var places: Array = life.discovery.places if life != null and life.get("discovery") != null else []
	for cand: String in NAMES.get(id, []):
		var keys := cand.to_lower().split("+")
		for pl: Dictionary in places:
			var nm := String(pl["name"]).to_lower()
			var ok := true
			for k in keys:
				if not nm.contains(k):
					ok = false
			if ok:
				var src_r := float(pl.get("radius", rad))
				return {"pos": pl["pos"], "radius": maxf(rad, minf(src_r, 140.0)) if not RADIUS.has(id) else rad, "source": "discovery:" + String(pl["name"])}
	# 3. first_region.json
	for pl: Dictionary in _first_region_places():
		if String(pl.get("id", "")) == id:
			var p: Array = pl["pos"]
			return {"pos": Vector2(float(p[0]), float(p[1])), "radius": rad, "source": "first_region"}
	# 4. the registry proposal, metres from Ashford
	var reg_place: Dictionary = (registry().get("places", {}) as Dictionary).get(id, {})
	if reg_place.has("pos"):
		var q: Array = reg_place["pos"]
		return {"pos": _home() + Vector2(float(q[0]), float(q[1])), "radius": rad, "source": "registry"}
	return {}


static var _first_cache: Array = []


static func _first_region_places() -> Array:
	if _first_cache.is_empty():
		var path := "res://data/world/first_region.json"
		if FileAccess.file_exists(path):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				_first_cache = d.get("places", [])
	return _first_cache


## Registry id of the place the point is inside (smallest radius wins), or "".
static func place_at(p: Vector2) -> String:
	var best := ""
	var best_r := INF
	for id: String in (registry().get("places", {}) as Dictionary):
		var r := resolve(id)
		if r.is_empty():
			continue
		var d: float = p.distance_to(r["pos"])
		if d <= float(r["radius"]) and float(r["radius"]) < best_r:
			best_r = float(r["radius"])
			best = id
	return best


## "Stones: 240 m north-west" style hint from `from` to a place. Vague beyond 1 km.
static func lead_text(from: Vector2, id: String) -> String:
	var r := resolve(id)
	if r.is_empty():
		return ""
	var d: Vector2 = (r["pos"] as Vector2) - from
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var dir := String(names[int(round(fposmod(atan2(d.x, -d.y), TAU) / (TAU / 8.0))) % 8])
	var dist := d.length()
	if dist < float(r["radius"]):
		return "You are here"
	if dist < 150.0:
		return "a short walk %s" % dir
	if dist < 600.0:
		return "about %d m %s" % [int(round(dist / 50.0)) * 50, dir]
	return "%.1f km %s" % [snappedf(dist / 1000.0, 0.5), dir]
