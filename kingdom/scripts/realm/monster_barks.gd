extends RefCounted
## MN-11 gossip by status: picks a line from data/world/barks_status.json by (situation, band of the SUBJECT's status as the speaker reads
## it, culture, species). Deterministic; an NPC never speaks twice inside 3 game hours; at most BUDGET lines per hour near the player.

const Data := preload("res://scripts/realm/mn_data.gd")
const GAP_HOURS := 3
const BUDGET := 24

var seed_value := 1
var _last: Dictionary = {}     # npc id -> absolute hour of the last line
var _hour_key := -1
var _spoken := 0


static func lines_for(band: String, situation: String, culture: String, species: String) -> Array:
	var out: Array = []
	for l: Variant in Data.table("barks_status").get("lines", []):
		var d: Dictionary = l
		if d["b"] != band or d["s"] != situation:
			continue
		if d["c"] != "*" and d["c"] != culture:
			continue
		if d["sp"] != "*" and d["sp"] != species:
			continue
		out.append(d)
	return out


## Returns {line, ok}. `abs_hour` = day * 24 + hour. Specific (culture or species) lines are preferred over generic ones.
func pick(npc: String, band: String, situation: String, culture: String, species: String, abs_hour: int) -> Dictionary:
	if abs_hour != _hour_key:
		_hour_key = abs_hour
		_spoken = 0
	if _spoken >= BUDGET:
		return {"ok": false, "line": "", "why": "budget"}
	if _last.has(npc) and abs_hour - int(_last[npc]) < GAP_HOURS:
		return {"ok": false, "line": "", "why": "recent"}
	var all := lines_for(band, situation, culture, species)
	var specific: Array = all.filter(func(d: Dictionary) -> bool: return d["c"] != "*" or d["sp"] != "*")
	var pool: Array = specific if not specific.is_empty() and absi(hash([seed_value, npc, abs_hour])) % 3 != 0 else all
	if pool.is_empty():
		return {"ok": false, "line": "", "why": "none"}
	var d: Dictionary = pool[absi(hash([seed_value, npc, abs_hour, band, situation])) % pool.size()]
	_last[npc] = abs_hour
	_spoken += 1
	return {"ok": true, "line": String(d["t"])}
