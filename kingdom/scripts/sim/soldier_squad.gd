extends RefCounted
## The player's squad (F11): 2-4 named soldiers at corporal and above. Pure data, JSON-safe save, no scene access.
## Members persist across saves, are wounded (out of the fight until they heal), and when one dies a replacement
## is posted after a few days. The body (scripts/actors/squad_soldier.gd) asks this class where to stand
## (follow_slot) and what to do in a fight (fighter(i) is an NpcFighter, scripts/combat/npc_fighter.gd).
##
## member = {id, name, hp, max_hp, state: "ready"|"wounded"|"dead", until (day a wound heals / a replacement
##           arrives), kills, seed, joined (day)}

const Career := preload("res://scripts/sim/soldier_career.gd")
const NpcFighter := preload("res://scripts/combat/npc_fighter.gd")

var members: Array = []
var target_size := 0
var fallen: Array = []          # names of members lost, newest last (the memorial line)
var rank_idx := 0
var _fighters: Dictionary = {}  # member id -> NpcFighter (not saved; rebuilt from the member's seed)
var _next := 0


static func cfg() -> Dictionary:
	return Career.data()["squad"]


static func max_hp_for(rank: int) -> int:
	return int(cfg()["base_hp"]) + int(cfg()["hp_per_rank"]) * rank


## Deterministic named soldier from a seed.
func _recruit(day: int, seed_value: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var c := cfg()
	var used := {}
	for m: Dictionary in members:
		used[String(m["name"])] = true
	var nm := ""
	for _try in 12:
		nm = "%s %s" % [String((c["first"] as Array)[r.randi() % (c["first"] as Array).size()]), String((c["last"] as Array)[r.randi() % (c["last"] as Array).size()])]
		if not used.has(nm):
			break
	_next += 1
	return {"id": "sq%d" % _next, "name": nm, "hp": max_hp_for(rank_idx), "max_hp": max_hp_for(rank_idx), "state": "ready", "until": -1, "kills": 0,
		"seed": r.randi(), "joined": day}


## Sets the squad size for a rank (grow immediately, shrink from the newest). Returns the names added.
func set_rank(rank: int, day: int, seed_base: int) -> Array:
	rank_idx = rank
	target_size = Career.squad_size(rank)
	var added: Array = []
	# Existing members get the rank's better endurance.
	for m: Dictionary in members:
		m["max_hp"] = max_hp_for(rank)
		if String(m["state"]) == "ready":
			m["hp"] = m["max_hp"]
	while _alive_or_pending() < target_size:
		var m := _recruit(day, hash([seed_base, day, _next]))
		members.append(m)
		added.append(String(m["name"]))
	while _alive_or_pending() > target_size:
		var gone: Dictionary = members.pop_back()
		_fighters.erase(String(gone["id"]))
	return added


func _alive_or_pending() -> int:
	return members.size()


func clear() -> void:
	members.clear()
	_fighters.clear()
	target_size = 0


func size() -> int:
	return members.size()


func member(i: int) -> Dictionary:
	return members[i] if i >= 0 and i < members.size() else {}


func find(id: String) -> int:
	for i in members.size():
		if String(members[i]["id"]) == id:
			return i
	return -1


func ready() -> Array:
	return members.filter(func(m: Dictionary) -> bool: return String(m["state"]) == "ready")


func ready_count() -> int:
	return ready().size()


func wounded_count() -> int:
	return members.filter(func(m: Dictionary) -> bool: return String(m["state"]) == "wounded").size()


func dead_count() -> int:
	return members.filter(func(m: Dictionary) -> bool: return String(m["state"]) == "dead").size()


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in members:
		out.append(String(m["name"]))
	return out


## One blow of `amount` on member i. Below the wound threshold the soldier is wounded (out for `wound_days`);
## at 0 HP they die. Returns "ready" | "wounded" | "dead" (the state afterwards) or "" for a bad index.
func damage(i: int, amount: int, day: int) -> String:
	if i < 0 or i >= members.size() or String(members[i]["state"]) != "ready":
		return ""
	var m: Dictionary = members[i]
	m["hp"] = maxi(0, int(m["hp"]) - amount)
	if int(m["hp"]) <= 0:
		return kill(i, day)
	if float(m["hp"]) <= float(m["max_hp"]) * float(cfg()["wound_hp_fraction"]):
		m["state"] = "wounded"
		m["until"] = day + int(cfg()["wound_days"])
		return "wounded"
	return "ready"


## The member dies; a replacement arrives `replace_days` later (see tick_day).
func kill(i: int, day: int) -> String:
	if i < 0 or i >= members.size():
		return ""
	var m: Dictionary = members[i]
	m["state"] = "dead"
	m["hp"] = 0
	m["until"] = day + int(cfg()["replace_days"])
	fallen.append(String(m["name"]))
	if fallen.size() > 12:
		fallen.pop_front()
	_fighters.erase(String(m["id"]))
	return "dead"


func credit_kill(i: int) -> void:
	if i >= 0 and i < members.size():
		members[i]["kills"] = int(members[i]["kills"]) + 1


## A new day: wounds heal, the dead are replaced. Returns lines for the log.
func tick_day(day: int, seed_base: int) -> Array:
	var out: Array = []
	for i in members.size():
		var m: Dictionary = members[i]
		var st := String(m["state"])
		if st == "wounded" and day >= int(m["until"]):
			m["state"] = "ready"
			m["hp"] = m["max_hp"]
			out.append("%s is fit for duty again." % String(m["name"]))
		elif st == "dead" and day >= int(m["until"]):
			var old := String(m["name"])
			var fresh := _recruit(day, hash([seed_base, day, _next, old]))
			members[i] = fresh
			out.append("%s is posted to your squad in place of %s." % [String(fresh["name"]), old])
	return out


## Resting at the post heals the wounded at once (a medic's visit) and tops everyone up.
func rest_all() -> void:
	for m: Dictionary in members:
		if String(m["state"]) == "wounded":
			m["state"] = "ready"
		if String(m["state"]) == "ready":
			m["hp"] = m["max_hp"]


## Where ready member i should stand: a staggered column behind the leader (leader_dir is the way the leader faces).
func follow_slot(i: int, leader_pos: Vector2, leader_dir: Vector2) -> Vector2:
	var dir := leader_dir.normalized() if leader_dir.length() > 0.01 else Vector2(0, -1)
	var side := Vector2(-dir.y, dir.x)
	var gap := float(cfg()["follow_gap"])
	var rank_back := float(i / 2 + 1) * gap
	var lateral := (-1.0 if i % 2 == 0 else 1.0) * gap * 0.8
	return leader_pos - dir * rank_back + side * lateral


## The member's NpcFighter (built on first use, deterministic from its seed). Skill follows the leader's rank.
func fighter(i: int) -> RefCounted:
	var m := member(i)
	if m.is_empty():
		return null
	var id := String(m["id"])
	if not _fighters.has(id):
		_fighters[id] = NpcFighter.make(String(cfg()["archetype"]), int(m["seed"]), clampi(2 + rank_idx, 0, 10))
	return _fighters[id]


## One think for member i against a foe (NpcFighter.think ctx). Wounded and dead soldiers hold.
func think(i: int, dt: float, ctx: Dictionary) -> Dictionary:
	var m := member(i)
	if m.is_empty() or String(m["state"]) != "ready":
		return {"intent": NpcFighter.Intent.HOLD, "move": null, "feint_at": 0.0}
	var c := ctx.duplicate()
	c["own_hp_frac"] = float(m["hp"]) / maxf(1.0, float(m["max_hp"]))
	return fighter(i).think(dt, c)


func serialize() -> Dictionary:
	return {"members": members.duplicate(true), "target": target_size, "fallen": fallen.duplicate(), "rank": rank_idx, "next": _next}


func deserialize(d: Dictionary) -> void:
	members = (d.get("members", []) as Array).duplicate(true)
	for m: Dictionary in members:
		for k: String in ["hp", "max_hp", "until", "kills", "seed", "joined"]:
			m[k] = int(m.get(k, 0))
	target_size = int(d.get("target", 0))
	fallen = (d.get("fallen", []) as Array).duplicate()
	rank_idx = int(d.get("rank", 0))
	_next = int(d.get("next", 0))
	_fighters.clear()
