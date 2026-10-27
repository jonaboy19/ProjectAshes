extends RefCounted
## Raids you can fight (READY_V1 C9). founding.gd already raises a "raid" problem on a player settlement when monster and
## bandit pressure beat its defence (and resolves it off-screen with lost people and treasury). This picks the open raid to
## stage live when the player is near the settlement: a raider band at the edge, a warning, and on victory
## founding.defend_raid() closes the problem. Grace: no live raid in the first GRACE_DAYS after founding.

const NEAR := 300.0          # player within this many metres of the settlement centre
const GRACE_DAYS := 14
const EDGE := 55.0           # raiders gather this far out


## {fid, name, at: Vector2, count, key} for the first open raid to stage, or {}. `seen` holds keys already staged.
static func due(founding: Object, player_pos: Vector2, day: int, seen: Dictionary) -> Dictionary:
	if founding == null:
		return {}
	for fid: int in founding.call("ids", true):
		var f: Dictionary = founding.call("get_founding", fid)
		if String(f.get("who", "")) != "player" or String(f.get("node", "")) == "":
			continue
		if day - int(f.get("born", 0)) < GRACE_DAYS:
			continue
		var c := Vector2(float(f["pos"][0]), float(f["pos"][1]))
		if c.distance_to(player_pos) > NEAR:
			continue
		for p: Dictionary in founding.call("problems", fid):
			if String(p["kind"]) != "raid":
				continue
			var key := "%d:%d" % [fid, int(p["day"])]
			if seen.has(key):
				continue
			var sc := int(f.get("sc", 0))
			var ang := float(hash(key) % 628) / 100.0
			return {"fid": fid, "name": String(f["name"]), "at": c + Vector2(cos(ang), sin(ang)) * EDGE,
				"count": band_size(sc, int(p.get("severity", 1))), "key": key}
	return {}


## Raiders in the band: grows with the settlement scale and the problem's severity, capped for a fair fight.
static func band_size(scale: int, severity: int) -> int:
	return clampi(3 + 2 * scale + severity, 4, 14)
