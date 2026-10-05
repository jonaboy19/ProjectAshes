extends Node
## Sect disciples near sect halls and a knight captain with a guard squad at the knight academy's town: small friendly
## (team 0) squads that defend the place against raiders, built only while the player is near and freed when far
## (the same pattern as region1_creatures.gd camps). The hosts are education.gd institutions (martial_sect,
## knight_academy), so the patrols stand where the teachers of those paths live.
##
## Budget: at most MAX_PATROLS patrols live at once, a patrol is 3-4 soldiers of which 1-3 are NpcCasters (their
## own world-wide cap, NpcCaster.MAX_ACTIVE, still applies), one 2 s timer, nothing per frame.
## plan() is pure (tests call it); Region1Creatures adds this node.

const Squad := preload("res://scripts/army/squad.gd")
const CasterSpawns := preload("res://scripts/combat/caster_spawns.gd")
const NpcCaster := preload("res://scripts/combat/npc_caster.gd")

const BUILD := 110.0
const FREE := 170.0
const MAX_PATROLS := 2
const CHECK := 2.0
const RESPAWN_DAYS := 2
const KNIGHT_KEEP: Array[String] = ["Knight_Helmet", "1H_Sword", "Round_Shield"]
const LOOKS := {"sect_patrol": ["soldier", "Monk", []], "knight_patrol": ["soldier", "Knight", KNIGHT_KEEP]}

var focus := Vector3.ZERO
var _timer := 1.0
var _plan: Array = []
var _planned := false
var _live: Dictionary = {}           # plan id -> {squad, dead_day}


## Patrol plan from education institutions and settlements: [{id, context, n, pos: Vector2, sid, inst}].
## Minor (village) halls get a smaller patrol; a knight patrol needs a settlement big enough to garrison.
static func plan(institutions: Array, settlements: Array) -> Array:
	var out: Array = []
	for inst: Dictionary in institutions:
		var kind := String(inst.get("kind", ""))
		if kind not in ["martial_sect", "knight_academy"] or bool(inst.get("hidden", false)):
			continue
		var sid := int(inst.get("sid", -1))
		if sid < 0 or sid >= settlements.size():
			continue
		var s: Dictionary = settlements[sid]
		var minor := bool(inst.get("minor", false))
		var ctx := "sect_patrol" if kind == "martial_sect" else "knight_patrol"
		out.append({"id": String(inst["id"]), "context": ctx, "n": (2 if minor else 3) if kind == "martial_sect" else (4 if not minor else 0),
			"pos": (s["pos"] as Vector2) + Vector2(10.0, 8.0), "sid": sid, "inst": String(inst["name"])})
	return out.filter(func(p: Dictionary) -> bool: return int(p["n"]) > 0)


func _process(delta: float) -> void:
	var parent := get_parent()
	if parent and "focus" in parent:
		focus = parent.focus
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK
	if not _planned:
		_planned = true
		var edu: Variant = Life.realm.mod("education") if Life.realm != null and (Life.realm.mods as Dictionary).has("education") else null
		if edu != null:
			_plan = plan(edu.institutions(), WorldGen.settlements)
	_update(Vector2(focus.x, focus.z))


func live_count() -> int:
	var n := 0
	for k: String in _live:
		if _live[k].get("squad") != null:
			n += 1
	return n


func _update(p: Vector2) -> void:
	for e: Dictionary in _plan:
		var id := String(e["id"])
		var st: Dictionary = _live.get(id, {"squad": null, "dead_day": -999})
		_live[id] = st
		var d := p.distance_to(e["pos"])
		var squad: Variant = st["squad"]
		if squad != null and not is_instance_valid(squad):
			squad = null
			st["squad"] = null
		if squad != null:
			if (squad as Squad).alive() <= 0:
				st["dead_day"] = int(WorldSim.day)
				(squad as Squad).queue_free()
				st["squad"] = null
			elif d > FREE:
				for s in (squad as Squad).soldiers.duplicate():
					if is_instance_valid(s):
						s.queue_free()
				(squad as Squad).queue_free()
				st["squad"] = null
		elif d < BUILD and int(WorldSim.day) - int(st["dead_day"]) >= RESPAWN_DAYS and live_count() < MAX_PATROLS:
			st["squad"] = _spawn(e)


func _spawn(e: Dictionary) -> Squad:
	var look: Array = LOOKS[String(e["context"])]
	var casters := CasterSpawns.mix(String(e["context"]), int(e["n"]), hash(String(e["id"])))
	if NpcCaster.active + casters.size() > NpcCaster.MAX_ACTIVE:
		casters = []                 # over the world-wide cap: a plain patrol
	var pos: Vector2 = e["pos"]
	var base := Vector3(pos.x, WorldGen.height(pos.x, pos.y), pos.y)
	var keep: Array[String] = []
	keep.assign(look[2])
	var squad := Squad.new().setup(0, String(look[0]), String(look[1]), keep)
	squad.anchor = base
	squad.aggro_radius = 22.0
	add_child(squad)
	squad.add_soldiers(int(e["n"]), base, casters)
	return squad
