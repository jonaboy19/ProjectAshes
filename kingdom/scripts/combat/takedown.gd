extends RefCounted
## Knock-out and kill path for people (villagers, guards) so a witness can be SILENCED (villager.gd silence() ->
## Witness.silence): a non-lethal takedown from behind while the victim has not noticed anything, or a kill when
## their health runs out. Either leaves a body as Evidence (evidence.gd), and a seen takedown is still a crime
## (NpcWorld.report_crime), so killing a witness without being seen leaves the case "unreported" (witness.gd)
## but the body can be found.
##
## Pure static rules + a small registry of who is down (so PopulationLOD does not respawn or draw them); the
## villager node does the lying-down. No class_name: preload this script.

const Perception := preload("res://scripts/population/perception.gd")
const Witness := preload("res://scripts/population/witness.gd")
const Evidence := preload("res://scripts/population/evidence.gd")
const NPC_WORLD := "res://scripts/population/npc_world.gd"

enum Kind { KO, KILL }
const KIND_NAMES := ["ko", "dead"]

## How close the attacker must be, and how far behind the victim's facing (dot of facing with the way to the attacker).
const REACH := 2.0
const BEHIND_DOT := -0.2
## A KO'd person wakes after this long (their body stays Evidence until then).
const KO_SECONDS := 120.0
## Civilian health; a guard's is Perception-independent (villager.gd takes both from here).
const HP_CIVILIAN := 30
const HP_GUARD := 120

## person -> {kind, until_ms (KO only), pos: Vector2, sid, evidence: id}
static var _down := {}
static var takedowns := 0


static func reset() -> void:
	_down.clear()
	takedowns = 0


static func hp_for(guard: bool, person: int) -> int:
	return HP_GUARD if guard else HP_CIVILIAN + person % 10


## Is `attacker` positioned for a silent takedown on a victim at `victim_pos` facing `victim_facing`?
## `victim_class` is the victim's Perception.Cls: only someone who has NOT noticed anything (calm / notice) can be
## taken from behind. Guards are alert professionals: they must be calm.
static func can_takedown(attacker: Vector2, victim_pos: Vector2, victim_facing: Vector2, victim_class: int, victim_is_guard := false) -> bool:
	var to := attacker - victim_pos
	var d := to.length()
	if d > REACH:
		return false
	var limit := Perception.Cls.CALM if victim_is_guard else Perception.Cls.NOTICE
	if victim_class > limit:
		return false
	if d < 0.05 or victim_facing == Vector2.ZERO:
		return true
	return victim_facing.normalized().dot(to / d) <= BEHIND_DOT


static func is_down(person: int) -> bool:
	return _down.has(person)


static func is_dead(person: int) -> bool:
	return _down.has(person) and int(_down[person]["kind"]) == Kind.KILL


static func down_count() -> int:
	return _down.size()


static func body_pos(person: int) -> Vector2:
	return _down[person]["pos"] if _down.has(person) else Vector2.INF


static func evidence_of(person: int) -> int:
	return int(_down[person]["evidence"]) if _down.has(person) else 0


## `person` goes down at `pos` (`kind`): registered, silenced as a witness, and left as Evidence (a BODY and blood for a
## kill, a KO body for a knock-out). `soc` is Society (duck-typed) for the Witness commit rules. Returns the evidence id.
static func down(person: int, kind: int, pos: Vector2, sid: int, now_ms: int, soc: RefCounted = null, source := "") -> int:
	if _down.has(person):
		return int(_down[person]["evidence"])
	var eid := 0
	if kind == Kind.KILL:
		eid = Evidence.add(Evidence.Kind.BODY, pos, sid, now_ms, source if source != "" else "murder")
		Evidence.add(Evidence.Kind.BLOOD, pos, sid, now_ms, source if source != "" else "murder")
	else:
		eid = Evidence.add(Evidence.Kind.KO, pos, sid, now_ms, source if source != "" else "assault")
	_down[person] = {"kind": kind, "until_ms": now_ms + int(KO_SECONDS * 1000.0) if kind == Kind.KO else 0,
		"pos": pos, "sid": sid, "evidence": eid}
	takedowns += 1
	Witness.silence(person, now_ms, soc)
	return eid


## KO'd people stand up when their time is over (or on demand). Returns the persons who woke; their body evidence goes.
static func tick(now_ms: int) -> Array:
	var woke: Array = []
	for p: int in _down.keys():
		var row: Dictionary = _down[p]
		if int(row["kind"]) == Kind.KO and now_ms >= int(row["until_ms"]):
			woke.append(p)
	for p: int in woke:
		wake(p)
	return woke


static func wake(person: int) -> bool:
	if not _down.has(person) or int(_down[person]["kind"]) != Kind.KO:
		return false
	Evidence.remove(int(_down[person]["evidence"]))
	_down.erase(person)
	return true


## The attacker's side of it, used by player.gd: swing `damage` at the villager node `victim` from the player at
## `attacker`. A silent takedown knocks them out; otherwise the blow hurts (and kills at 0 HP). Returns
## {"ok", "kind": "ko"|"hit"|"kill"|""}.
static func strike(_tree: SceneTree, victim: Node3D, attacker: Node3D, damage: int) -> Dictionary:
	if victim == null or not is_instance_valid(victim) or not victim.has_method("take_damage"):
		return {"ok": false, "kind": ""}
	victim.call("take_damage", damage, attacker, Vector3.ZERO)
	var kind := "ko" if bool(victim.call("is_down")) and not bool(victim.call("is_dead")) else ("kill" if bool(victim.call("is_dead")) else "hit")
	return {"ok": true, "kind": kind}


## After a person went down: whoever saw it is a witness of an assault / murder (the downed one is already out of
## the "villager" group, so they do not count themselves). The traces were already left by down(), so none are added.
static func witnessed_by_others(tree: SceneTree, kind: int, pos: Vector2, sid: int) -> Dictionary:
	return (load(NPC_WORLD) as GDScript).call("report_crime", tree, "murder" if kind == Kind.KILL else "assault", pos, sid, true, false)


## Persistence: the dead stay dead; KO'd people wake on load (they are not worth saving).
static func serialize() -> Array:
	var out: Array = []
	for p: int in _down:
		if int(_down[p]["kind"]) == Kind.KILL:
			out.append([p, snappedf(Vector2(_down[p]["pos"]).x, 0.1), snappedf(Vector2(_down[p]["pos"]).y, 0.1), int(_down[p]["sid"])])
	return out


static func deserialize(rows: Variant, now_ms := -1) -> void:
	_down.clear()
	if not rows is Array:
		return
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	for r: Variant in rows:
		if not r is Array or (r as Array).size() < 4:
			continue
		var a: Array = r
		var eid := Evidence.add(Evidence.Kind.BODY, Vector2(float(a[1]), float(a[2])), int(a[3]), now, "murder")
		_down[int(a[0])] = {"kind": Kind.KILL, "until_ms": 0, "pos": Vector2(float(a[1]), float(a[2])), "sid": int(a[3]), "evidence": eid}
