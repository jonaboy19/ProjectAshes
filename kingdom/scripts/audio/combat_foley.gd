extends RefCounted
## Combat foley (AAA gap audit 2026-10-28, "Weapon and impact SFX"): layered, positional sounds for every combat event
## on CombatEvents.bus() (scripts/combat/combat_events.gd; the combat code only emits). Owned by the AudioDirector.
##   swing  -> whoosh by weight and blade speed (light / heavy, pitch and level follow speed) + cloth/leather/mail
##             movement layer under heavy swings
##   hit    -> blade-into-target transient by the struck surface (flesh / cloth / leather / metal / wood) + body thud,
##             wet layer on heavy / finisher blows, a body fall when killed
##   block  -> shield (wood) or blade (metal) impact by weight; a broken guard adds a heavy crack and a gear rattle
##   parry  -> steel on steel: a ringing clash, brighter and longer for a perfect parry
##   dodge  -> cloth whoosh + a scuff on the ground
## Degrades gracefully: missing fields fall back (weight "light", surface by event, no victim -> no fall), and every
## layer is optional: a name with no recordings is skipped. Sounds come from the director's library: licensed_local/
## (Sonniss, not in git) when present, else the CC0 set.

const LAYERS := {
	# swing
	"whoosh_light": ["whoosh_light", "swing"],
	"whoosh_heavy": ["whoosh_heavy", "swing_heavy"],
	# hit by surface
	"hit_flesh": ["hit_blade_flesh", "hit_flesh"],
	"hit_cloth": ["hit_blade_flesh", "hit_flesh"],
	"hit_leather": ["hit_leather", "hit_flesh"],
	"hit_metal": ["hit_armor_metal", "hit_metal"],
	"hit_wood": ["block_wood", "hit_wood"],
	"thud": ["hit_body", ""],
	"wet": ["hit_gore", ""],
	"fall": ["body_fall", ""],
	# defence
	"block_wood": ["block_wood", "hit_wood"],
	"block_metal": ["clash_steel", "block"],
	"parry": ["clash_steel", "block"],
	"parry_ring": ["blade_ring", ""],
	"break": ["guard_break", "hit_wood"],
	# movement foley
	"gear": ["foley_gear", ""],
	"cloth": ["foley_cloth", "dodge"],
	"scuff": ["step_scuff", ""],
}
## weight -> [volume dB, pitch jitter]
const WEIGHT := {"light": [-3.0, 0.07], "heavy": [0.0, 0.05], "finisher": [2.0, 0.04]}

var director: Node
var _last := {}        # family -> time of the last event (the director drops duplicate legacy Audio.sfx calls)


func bind(d: Node) -> void:
	director = d
	var bus: Object = preload("res://scripts/combat/combat_events.gd").bus()
	bus.connect("swing", _on_swing)
	bus.connect("hit", _on_hit)
	bus.connect("block", _on_block)
	bus.connect("parry", _on_parry)
	bus.connect("dodge", _on_dodge)


## True when a combat event of this legacy family ("swing", "hit", "clash") played within `window` seconds.
func recent(family: String, window := 0.25) -> bool:
	return _now() - float(_last.get(family, -100.0)) < window


func _on_swing(e: Dictionary) -> void:
	_last["swing"] = _now()
	var w := String(e.get("weight", "light"))
	var speed := float(e.get("speed", 6.0))
	var pos: Variant = e.get("pos")
	var heavy := w != "light"
	# faster blade = brighter and louder air: 4 m/s lazy .. 14 m/s full-power cut
	var k := clampf((speed - 4.0) / 10.0, 0.0, 1.0)
	var pitch := lerpf(0.9, 1.12, k) * (0.94 if heavy else 1.0)
	var kind := String(e.get("kind", "slash"))
	if kind == "thrust":
		pitch *= 1.08
	_play("whoosh_heavy" if heavy else "whoosh_light", pos, lerpf(-6.0, 0.0, k) + _wdb(w), pitch, 0.04)
	if heavy or randf() < 0.35:
		_play("gear" if heavy else "cloth", pos, -10.0 + _wdb(w), randf_range(0.95, 1.05), 0.05)


func _on_hit(e: Dictionary) -> void:
	_last["hit"] = _now()
	var w := String(e.get("weight", "light"))
	var surface := String(e.get("surface", "flesh"))
	if not LAYERS.has("hit_" + surface):
		surface = "flesh"
	var pos: Variant = e.get("pos")
	_play("hit_" + surface, pos, _wdb(w), 1.0, _jit(w))
	if surface != "wood":
		_play("thud", pos, -5.0 + _wdb(w), 0.95 if w != "light" else 1.05, 0.06)
	if w != "light" and surface in ["flesh", "cloth", "leather"]:
		_play("wet", pos, -9.0 + _wdb(w), 1.0, 0.06)
	if bool(e.get("killed", false)):
		var victim: Variant = e.get("victim")
		var at: Variant = (victim as Node3D).global_position if victim is Node3D and is_instance_valid(victim) else pos
		director.get_tree().create_timer(0.55).timeout.connect(func() -> void:
			if is_instance_valid(director):
				_play("fall", at, -3.0, 1.0, 0.05))


func _on_block(e: Dictionary) -> void:
	_last["clash"] = _now()
	var w := String(e.get("weight", "light"))
	var pos: Variant = e.get("pos")
	var surface := String(e.get("surface", "wood"))
	_play("block_wood" if surface == "wood" else "block_metal", pos, _wdb(w), 0.95 if w != "light" else 1.0, _jit(w))
	if bool(e.get("broken", false)):
		_play("break", pos, 1.0, 0.9, 0.04)
		_play("gear", pos, -4.0, 0.95, 0.05)


func _on_parry(e: Dictionary) -> void:
	_last["clash"] = _now()
	var pos: Variant = e.get("pos")
	var perfect := String(e.get("grade", "")) == "perfect"
	_play("parry", pos, 1.0 if perfect else -1.0, 1.04 if perfect else 0.98, 0.04)
	_play("parry_ring", pos, -6.0 if perfect else -11.0, 1.0, 0.03)


func _on_dodge(e: Dictionary) -> void:
	var pos: Variant = e.get("pos")
	_play("cloth", pos, -4.0, randf_range(0.96, 1.06), 0.05)
	director.get_tree().create_timer(0.18).timeout.connect(func() -> void:
		if is_instance_valid(director):
			_play("scuff", pos, -8.0, 1.0, 0.08))


func _play(layer: String, pos: Variant, db: float, pitch: float, jitter: float) -> void:
	for name: String in LAYERS.get(layer, []):
		if name != "" and director.has_sound(name):
			director.call("play_sfx_pitched", name, pos if pos is Vector3 else null, db, pitch, jitter)
			return


func _wdb(w: String) -> float:
	return float(WEIGHT.get(w, WEIGHT["light"])[0])


func _jit(w: String) -> float:
	return float(WEIGHT.get(w, WEIGHT["light"])[1])


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
