extends RefCounted
## READY_V1 C3, the player's "Found a camp" flow (model; the card is scripts/ui/found_camp_card.gd): look at the ground
## (site_card), choose a name, confirm (found) -> BuildKit.claim, which opens the grid + founding record + civilization row (C2).
##   var card := FoundFlow.site_card(Life.realm, Vector2(x, z))     # {ok, reason, rows, verdict, name, ...}
##   var r := FoundFlow.found(Life.realm, Vector2(x, z), "Newhold")  # {ok, gid, fid, name, reason}

const BuildKit := preload("res://scripts/realm/build_kit.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
const NAME_MAX := 24
const SLOPE_WORDS := ["flat ground", "gently rolling", "a noticeable slope", "steep", "a cliff-side scramble"]


## Everything the card shows for ground at `pos` (x, z). `ok` = founding here would succeed right now.
static func site_card(hub: RefCounted, pos: Vector2) -> Dictionary:
	var fd: RefCounted = hub.mod("founding")
	var bk: RefCounted = hub.mod("build_kit")
	var chk: Dictionary = fd.check_site(pos)
	var ev: Dictionary = chk["site"]
	var scores: Dictionary = ev["scores"]
	var lines: Array = ev["lines"]
	var ok := bool(chk["ok"])
	var reason := String(chk["reason"])
	var gid: int = bk.grid_at(Vector3(pos.x, 0.0, pos.y))
	if gid > 0:
		ok = false
		reason = "You already hold this ground: %s." % String(bk.grids[gid]["name"])
	var slope := slope_of(pos)
	var rows: Array = [
		["Water", _after(lines[0]), float(scores["water"])],
		["Slope", "%s (%d%% grade)" % [SLOPE_WORDS[clampi(int(slope * 5.0 / 0.5), 0, 4)], int(round(slope * 100.0))], 1.0 - clampf(slope / 0.5, 0.0, 1.0)],
		["Danger", _after(lines[7]), float(scores["safety"])],
		["Land law", String(ev["legal_words"]), float(scores["legality"])],
		["Food", _after(lines[1]), float(scores["food"])],
		["Trade", _after(lines[4]), float(scores["trade"])],
	]
	return {"ok": ok, "reason": reason, "rows": rows, "verdict": String(ev["verdict"]), "overall": float(ev["overall"]),
		"name": default_name(hub, pos), "slope": slope, "law_block": LandClaim.block_reason(pos), "left": maxi(0, BuildKit.MAX_GRIDS - bk.grids.size()),
		"site": ev}


## Founds the camp. Name is trimmed and capped; blank keeps the founding module's own name. {ok, gid, fid, name, reason}.
static func found(hub: RefCounted, pos: Vector2, camp_name: String) -> Dictionary:
	var bk: RefCounted = hub.mod("build_kit")
	var nm := clean_name(camp_name)
	var card := site_card(hub, pos)
	if not bool(card["ok"]):
		return {"ok": false, "gid": 0, "fid": 0, "name": nm, "reason": String(card["reason"])}
	var r: Dictionary = bk.claim(Vector3(pos.x, 0.0, pos.y), "squat", nm)
	if not bool(r["ok"]):
		return {"ok": false, "gid": 0, "fid": 0, "name": nm, "reason": String(r["reason"])}
	var gid := int(r["gid"])
	var row: Dictionary = hub.settlement_of_grid(gid)
	return {"ok": true, "gid": gid, "fid": int(row.get("fid", 0)), "name": String(bk.grids[gid]["name"]), "reason": ""}


static func clean_name(s: String) -> String:
	var t := s.strip_edges().replace("\n", " ")
	return t.substr(0, NAME_MAX).strip_edges()


static func default_name(hub: RefCounted, pos: Vector2) -> String:
	var fd: RefCounted = hub.mod("founding")
	var r: RandomNumberGenerator = fd._rng("name", 0, int(pos.x * 3.0 + pos.y))
	var a: Array = ["Ash", "Fern", "Stone", "Elder", "Amber", "Gale", "Thorn", "Mist", "Wolf", "Sun"]
	var b: Array = ["stead", "hollow", "rest", "wick", "haven", "field", "mere", "ford"]
	return "%s%s" % [a[r.randi() % a.size()], b[r.randi() % b.size()]]


## Steepest rise per metre within 20 m (0 flat .. 0.5+ cliff).
static func slope_of(pos: Vector2) -> float:
	var h0: float = WorldGen.height(pos.x, pos.y)
	var m := 0.0
	for o in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:
		m = maxf(m, absf(WorldGen.height(pos.x + o.x, pos.y + o.y) - h0) / 20.0)
	return m


static func _after(line: String) -> String:
	var i := line.find(": ")
	return line.substr(i + 2) if i >= 0 else line
