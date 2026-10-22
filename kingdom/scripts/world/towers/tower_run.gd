extends Node3D
## One floor being played (docs/design/DUNGEON_TOWERS.md). Created by tower_site.gd when the player climbs into a floor and
## freed when they leave. Owns the built interior, its interaction points, the mobs (streamed in and out around the player),
## the boss fight, chests, traps, the party of allies and the explored map.
##
## Gameplay rules live in realm/towers.gd (pure data); this node only applies them to the scene and to Life / Game.

signal floor_cleared(result: Dictionary)
signal ascend_requested
signal descend_requested
signal teleport_requested(floor_n: int)
signal exit_requested

const FG := preload("res://scripts/world/towers/floor_gen.gd")
const TowerData := preload("res://scripts/world/towers/tower_data.gd")
const FloorBoss := preload("res://scripts/world/towers/floor_boss.gd")
const FloorAlly := preload("res://scripts/world/towers/floor_ally.gd")
const TowerPoint := preload("res://scripts/world/towers/tower_point.gd")

const SPAWN_R := 48.0
const FREE_R := 80.0
const FALLBACK_LOOT := {
	1: ["bread", "bandage", "leather", "copper_ingot", "iron_ingot", "stone", "healing_salve", "wolf_pelt"],
	2: ["bandage", "healing_salve", "iron_ingot", "leather_cap", "leather_gloves", "stamina_draught", "antidote", "iron_dagger"],
	3: ["healing_salve", "iron_sword", "leather_jerkin", "leather_boots", "wooden_shield", "copper_ring", "stamina_draught"],
	4: ["iron_sword", "iron_helm", "belt_pouch", "sunstone_oil", "healing_salve", "antidote", "copper_ring"],
}
const LOOT_API_PATHS := ["res://scripts/sim/loot_tables.gd", "res://scripts/sim/loot.gd", "res://data/items/loot_tables.gd"]

var tid := ""
var floor_n := 1
var L: Dictionary = {}
var B: Dictionary = {}
var root: Node3D
var origin := Vector3.ZERO
var realm: RefCounted
var ui: Node
var player: Node3D
var rematch := false
var boss: Node3D = null
var boss_state := "idle"            # idle | fighting | dead
var explored: Dictionary = {}
var found := {"chest": []}
var points: Array[Node3D] = []
var allies: Array[Node3D] = []
var in_safe := false
var reveal_map := false

var _mobs: Array = []               # [{def, node, killed, pos}]
var _chests: Dictionary = {}        # id -> {opened, point}
var _trap_cd: Dictionary = {}
var _timer := 0.0
var _map_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _door: Node3D
var _barrier: MeshInstance3D
var _boss_def: Dictionary = {}
var _engaged := false
var _merchant: Node3D


func start(p_tid: String, p_floor: int, p_origin: Vector3, p_realm: RefCounted, p_ui: Node, p_player: Node3D, arrive := "start") -> void:
	tid = p_tid
	floor_n = p_floor
	origin = p_origin
	realm = p_realm
	ui = p_ui
	player = p_player
	name = "TowerRun"
	_rng.seed = hash([tid, floor_n, "run"])
	L = FG.layout(tid, floor_n)
	var dead: bool = realm != null and realm.boss_dead(tid, floor_n)
	B = FG.build(L, dead)
	root = B["root"]
	add_child(root)
	root.position = origin
	_door = B["door"]
	_barrier = B["barrier"]
	_boss_def = TowerData.floor_info(tid, floor_n)["boss"].duplicate(true)
	boss_state = "dead" if dead else "idle"
	_make_points()
	if realm != null:
		realm.begin_run(tid)
	_spawn_allies()
	explored[L["start"]] = true
	if ui != null:
		ui.show_map(true)
		_update_map()
	_timer = 0.0
	# arrival transform
	var spawn_local: Vector3 = B["spawn"]
	if arrive == "stairs_up":
		for p in B["points"]:
			if p["kind"] == "stairs_up":
				spawn_local = (p["pos"] as Vector3) + Vector3(0, 0.3, 2.5)
	_place_player(spawn_local)


func _place_player(local: Vector3) -> void:
	if player == null:
		return
	var at := origin + local + Vector3(0, 0.25, 0)
	player.global_position = at
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)
	if player.has_method("set_camera"):
		# face along the first open corridor from the start cell
		var m := FG.open_mask(L, L["start"])
		var yaw := PI * 0.5 if (m & FG.E) else PI
		player.call("set_camera", yaw if (m & FG.E) else 0.0, -0.3)
	if player is CharacterBody3D:
		(player as CharacterBody3D).reset_physics_interpolation()


func end() -> void:
	FloorBoss.safe_zone = false
	if ui != null:
		ui.show_map(false)
		ui.set_boss("", 0, 1, 1, false, false)
	for a in allies:
		if is_instance_valid(a):
			a.queue_free()
	queue_free()


# ------------------------------------------------------------------ points

func _make_point(kind: String, local: Vector3, action: String, label: String, data := {}) -> TowerPoint:
	var p := TowerPoint.new()
	p.action = action
	p.label = label
	p.data = data
	p.name = "Pt_" + kind
	root.add_child(p)
	p.position = local
	points.append(p)
	return p


func _make_points() -> void:
	for pt: Dictionary in B["points"]:
		var k: String = pt["kind"]
		var pos: Vector3 = pt["pos"]
		match k:
			"stairs_down":
				_make_point(k, pos, "stairs_down", "Leave the tower" if floor_n == 1 else "Descend to floor %d" % (floor_n - 1))
			"gate":
				_make_point(k, pos, "gate", "Use the teleport gate")
			"rest":
				_make_point(k, pos, "rest", "Rest at the bonfire")
			"merchant":
				_spawn_merchant(pos)
				_make_point(k, pos + Vector3(0, 0.9, 0), "merchant", "Trade with the quartermaster")
			"boss_door":
				_make_point(k, pos, "boss_door", "Examine the boss door")
			"stairs_up":
				var p := _make_point(k, pos, "stairs_up", "Climb to floor %d" % (floor_n + 1))
				p.data = {"open": boss_state == "dead"}
				if boss_state != "dead":
					p.label = "The stairway is sealed"
			"chest":
				var cp := _make_point(k, pos, "chest", "Open the locked chest" if bool(pt["locked"]) else "Open the chest",
					{"id": pt["id"], "tier": pt["tier"], "locked": pt["locked"], "cell": pt["cell"]})
				_chests[pt["id"]] = {"opened": false, "point": cp}
			"trap":
				pass      # traps are proximity checks, no prompt
	# mobs: definitions only, bodies are streamed
	for m: Dictionary in L["mobs"]:
		var c: Vector2i = m["cell"]
		var jit: Vector2 = m["jitter"]
		var pos := FG.cell_center(c) + Vector3(jit.x, 0.0, jit.y)
		_mobs.append({"def": m, "node": null, "killed": false, "pos": pos})


func _spawn_merchant(local: Vector3) -> void:
	var npc: Node3D = Assets.character("Trader", 1.75)
	if npc == null:
		return
	root.add_child(npc)
	npc.position = local
	var ap := Assets.animation_player(npc)
	if ap:
		for a in ["Idle_Talking", "Idle"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				ap.play(a)
				break
	npc.rotation.y = PI * 0.75
	_merchant = npc


func point_named(kind: String) -> Node3D:
	for p in points:
		if p.name == "Pt_" + kind:
			return p
	return null


func point_world(kind: String) -> Vector3:
	var p := point_named(kind)
	return p.global_position if p != null else origin


# ------------------------------------------------------------------ party

func _spawn_allies() -> void:
	var fol: RefCounted = realm.hub.mod("followers") if realm != null and realm.hub != null else null
	if fol == null:
		return
	var level := int(L["level"])
	var slot := 0
	for f: Dictionary in fol.party():
		if slot >= 3:
			break
		if String(f.get("occupation", "")) in ["builder", "priest"] and slot >= 2:
			continue
		var a := FloorAlly.new()
		a.setup(String(f["name"]), String(f.get("occupation", "mercenary")), level, slot)
		root.add_child(a)
		a.global_position = origin + (B["spawn"] as Vector3) + Vector3(1.5 + float(slot), 0.3, 1.0)
		allies.append(a)
		slot += 1


# ------------------------------------------------------------------ per-frame

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_timer -= delta
	_map_timer -= delta
	_check_traps()
	if _timer <= 0.0:
		_timer = 0.4
		_stream_mobs()
		_safe_check()
		_boss_check()
	if _map_timer <= 0.0:
		_map_timer = 0.25
		_explore()
		_update_map()


func local_pos() -> Vector3:
	return player.global_position - origin


func current_cell() -> Vector2i:
	return FG.cell_of(local_pos())


func _explore() -> void:
	var c := current_cell()
	var m := FG.open_mask(L, c)
	explored[c] = true
	for d in 4:
		if m & FG.BITS[d]:
			var n: Vector2i = c + FG.DIRS[d]
			if FG._inside(n):
				explored[n] = true
	for ch in _chests:
		var cp: Node3D = _chests[ch]["point"]
		if cp != null and player.global_position.distance_to(cp.global_position) < 10.0:
			var cc: Vector2i = cp.data["cell"]
			if not (found["chest"] as Array).has(cc) and not bool(_chests[ch]["opened"]):
				(found["chest"] as Array).append(cc)


func _update_map() -> void:
	if ui == null:
		return
	var info := TowerData.floor_info(tid, floor_n)
	var yaw := 0.0
	if player.has_method("forward"):
		var f: Vector3 = player.call("forward")
		yaw = atan2(f.x, f.z)
	ui.map_update(L, explored, found, current_cell(), yaw, "Floor %d · %s\nLv %d" % [floor_n, info["name"], int(info["level"])], reveal_map)


func _safe_check() -> void:
	var was := in_safe
	in_safe = current_cell() == (L["safe_cell"] as Vector2i)
	FloorBoss.safe_zone = in_safe
	if in_safe and not was:
		Game.say("Safe zone. Nothing follows you in here.")


# ------------------------------------------------------------------ mobs

func _stream_mobs() -> void:
	var pp := player.global_position
	for m: Dictionary in _mobs:
		if bool(m["killed"]):
			continue
		var wp: Vector3 = origin + (m["pos"] as Vector3)
		var d := Vector2(pp.x - wp.x, pp.z - wp.z).length()
		var node: Node3D = m["node"]
		if node == null and d < SPAWN_R:
			if (m["def"]["cell"] as Vector2i) == (L["safe_cell"] as Vector2i):
				continue
			m["node"] = _spawn_mob(m)
		elif node != null and is_instance_valid(node):
			var fm := node as FloorBoss
			if d > FREE_R and not fm.active:
				node.queue_free()
				m["node"] = null


func _spawn_mob(m: Dictionary) -> Node3D:
	var kind: String = m["def"]["kind"]
	var sizes := {"giant_rat": 1.8, "blight_rat": 1.7, "spider": 1.3, "wolf": 1.0, "boar": 1.0, "goblin": 1.0, "orc": 1.0, "troll": 0.9,
		"bear": 1.0, "fungal_brute": 0.85, "blackcap_brute": 0.85}
	var info := {"name": kind.replace("_", " ").capitalize(), "kind": kind, "scale": float(sizes.get(kind, 1.0)) * _rng.randf_range(0.94, 1.08),
		"tint": Color(1, 1, 1), "patterns": [], "hp": TowerData.mob_hp(floor_n), "damage": TowerData.mob_damage(floor_n), "level": int(L["level"])}
	var mob := FloorBoss.new()
	mob.setup(info, false, floor_n, tid, [], hash(m["def"]["id"]))
	mob.leash = 14.0
	root.add_child(mob)
	mob.global_position = origin + (m["pos"] as Vector3) + Vector3(0, 0.4, 0)
	mob.home = mob.global_position
	mob.rotation.y = _rng.randf() * TAU
	mob.died.connect(_on_mob_died.bind(m))
	return mob


func _on_mob_died(_who: Node3D, m: Dictionary) -> void:
	m["killed"] = true
	var kind: String = m["def"]["kind"]
	Life.on_monster_killed(kind)
	# drops: a little gold and sometimes a pick from the floor's table
	var tier := int(L["tier"])
	var gold := _rng.randi_range(2, 5) * (1 + floor_n / 3)
	Game.add_gold(gold)
	if realm != null:
		realm.add_run_loot("", 0, gold)
	if _rng.randf() < 0.22:
		var it := _loot_one(tier)
		if it != "":
			_give(it, 1)
			Game.say("%s dropped %s." % [kind.replace("_", " ").capitalize(), Life.item_name(it)])
	var node: Node3D = m["node"]
	if node != null and is_instance_valid(node):
		get_tree().create_timer(6.0).timeout.connect(func() -> void:
			if is_instance_valid(node):
				node.queue_free())


# ------------------------------------------------------------------ traps

func _check_traps() -> void:
	if player == null or ("dead" in player and bool(player.get("dead"))):
		return
	for pt: Dictionary in B["points"]:
		if pt["kind"] != "trap":
			continue
		var id: String = pt["id"]
		if _trap_cd.has(id) and float(_trap_cd[id]) > Time.get_ticks_msec():
			continue
		var tp: Vector3 = origin + (pt["pos"] as Vector3)
		var d := Vector2(player.global_position.x - tp.x, player.global_position.z - tp.z).length()
		if d < 1.5 and player.global_position.y - tp.y < 1.0:
			_trap_cd[id] = Time.get_ticks_msec() + 4000.0
			_trigger_trap(String(pt["trap"]), tp)


func _trigger_trap(kind: String, at: Vector3) -> void:
	var dmg := 6 + int(floor_n * 1.6)
	match kind:
		"spikes":
			VFX.sparks(self, at + Vector3(0, 0.3, 0), Color(0.8, 0.8, 0.85), 18)
			Game.say("Spikes spring from the floor!")
		"flame":
			VFX.burst(self, at + Vector3(0, 0.5, 0), "fire", 0.8)
			Game.say("A gout of flame!")
		_:
			VFX.sparks(self, at + Vector3(0, 1.0, 0), Color(0.9, 0.8, 0.3), 10)
			Game.say("A dart hisses from the wall!")
	if player.has_method("take_damage"):
		player.call("take_damage", dmg, null, Vector3.ZERO)


# ------------------------------------------------------------------ interactions

func interact(p: Node3D) -> void:
	match String(p.get("action")):
		"stairs_down":
			if floor_n == 1:
				exit_requested.emit()
			else:
				descend_requested.emit()
		"gate":
			teleport_menu()
		"rest":
			rest_menu()
		"merchant":
			vendor_menu()
		"boss_door":
			boss_door_menu()
		"stairs_up":
			if boss_state == "dead":
				ascend_requested.emit()
			else:
				Game.say("A rune barrier seals the stairway. The floor boss still lives.")
		"chest":
			open_chest(String(p.data["id"]))


func teleport_menu() -> void:
	if realm == null or ui == null:
		return
	var buttons: Array = [["Base camp", func() -> void: exit_requested.emit()]]
	for e: Dictionary in realm.teleport_menu(tid):
		var f := int(e["floor"])
		if f == floor_n:
			continue
		buttons.append(["Floor %d · %s  (Lv %d)%s" % [f, e["name"], int(e["level"]), "  ✓" if bool(e["cleared"]) else ""],
			func() -> void: teleport_requested.emit(f)])
	ui.menu("Teleport gate", ["Every floor whose gate you have woken can be reached from here. Floors beyond the highest boss you know fallen stay dark."], buttons)


func rest_menu() -> void:
	ui.menu("Safe zone", ["A warded room: the bonfire burns, the quartermaster trades, nothing hunts here. Resting banks everything you carry and saves your progress."],
		[["Rest, bank your loot and save", _do_rest]])


func _do_rest() -> void:
	if player.has_method("heal") and "max_health" in player:
		player.call("heal", int(player.get("max_health")))
	if "stamina" in player:
		player.set("stamina", 100.0)
	if realm != null:
		realm.bank_run()
	for a in allies:
		if is_instance_valid(a) and "downed" in a and bool(a.get("downed")):
			a.call("revive")
	var ok: bool = Life.save_game()
	Game.say("You rest by the fire. %s" % ("Game saved." if ok else "Loot banked."))


func vendor_menu() -> void:
	var stock := ["bandage", "healing_salve", "stamina_draught", "antidote", "bread", "stew", "sunstone_oil"]
	var buttons: Array = []
	for id: String in stock:
		var price: Variant = Life.item_prop(id, "price", null)
		if price == null:
			continue
		var cost := int(ceil(float(price) * 1.6)) + floor_n
		buttons.append(["%s  ·  %d gold" % [Life.item_name(id), cost], _buy.bind(id, cost), Game.gold >= cost])
	ui.menu("Quartermaster", ["Tower prices, but it beats climbing back down. You have %d gold." % Game.gold], buttons)


func _buy(id: String, cost: int) -> void:
	if Game.gold < cost:
		Game.say("Not enough gold.")
		return
	Game.add_gold(-cost)
	Life.give(id, 1)
	Game.say("Bought %s for %d gold." % [Life.item_name(id), cost])


func open_chest(id: String) -> void:
	var st: Dictionary = _chests.get(id, {})
	if st.is_empty() or bool(st["opened"]):
		return
	st["opened"] = true
	var cp: TowerPoint = st["point"]
	cp.enabled = false
	var tier := int(cp.data["tier"])
	var locked := bool(cp.data["locked"])
	var at: Vector3 = cp.global_position
	if locked and _rng.randf() < 0.3:
		Game.say("The lock is trapped!")
		_trigger_trap("dart", at)
	var n := _rng.randi_range(2, 3) + (2 if locked else 0)
	var got: Array[String] = []
	for i in n:
		var it := _loot_one(tier + (1 if locked else 0))
		if it != "":
			_give(it, 1)
			got.append(Life.item_name(it))
	var gold := _rng.randi_range(8, 18) * (tier + 1) * (2 if locked else 1)
	Game.add_gold(gold)
	if realm != null:
		realm.add_run_loot("", 0, gold)
	VFX.sparks(self, at + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.4), 26)
	Game.say("Chest: %d gold, %s." % [gold, ", ".join(got) if not got.is_empty() else "nothing else"])


func _give(item: String, n: int) -> void:
	if Life.item_prop(item, "name", null) == null:
		return
	Life.give(item, n)
	if realm != null:
		realm.add_run_loot(item, n)


## One item id for a tier/theme. Uses the items agent's loot_table(tier, theme) when present, else the local fallback.
func _loot_one(tier: int) -> String:
	var table := loot_table_for(tier, String(L["theme"]))
	if table.is_empty():
		return ""
	return String(table[_rng.randi() % table.size()])


static func loot_table_for(tier: int, theme: String) -> Array:
	for path: String in LOOT_API_PATHS:
		if ResourceLoader.exists(path):
			var s: Script = load(path)
			if s != null and s.has_method("loot_table"):
				var r: Variant = s.call("loot_table", tier, theme)
				var out: Array = []
				if r is Array:
					for e: Variant in r:
						if e is String:
							out.append(e)
						elif e is Dictionary and e.has("id"):
							for i in int(e.get("weight", 1)):
								out.append(String(e["id"]))
				if not out.is_empty():
					return out
	var t := clampi(tier, 1, 4)
	return (FALLBACK_LOOT[t] as Array).duplicate()


# ------------------------------------------------------------------ boss fight

func boss_door_menu() -> void:
	var info := TowerData.floor_info(tid, floor_n)
	var b: Dictionary = info["boss"]
	var known: Array = realm.known_patterns(tid, floor_n) if realm != null else []
	var lines: Array = []
	var scouted: bool = realm != null and realm.has_scouted(tid, floor_n)
	lines.append("Floor %d boss: %s, %s." % [floor_n, b["name"], b["title"]] if (scouted or known.size() > 0 or boss_state == "dead") else
		"Something enormous waits beyond the great door. Nobody here can tell you what." )
	if scouted or boss_state == "dead":
		lines.append("Level %d · about %d health." % [int(info["level"]), int(b["hp"])])
	if known.is_empty():
		lines.append("Known moves: none. You will learn one more with every attempt.")
	else:
		var names: Array = []
		for pid: String in known:
			names.append("%s (%s)" % [TowerData.PATTERNS[pid]["name"], TowerData.PATTERNS[pid]["hint"]])
		lines.append("Known moves: " + "; ".join(names) + ".")
	var att: int = realm.attempts_on(tid, floor_n) if realm != null else 0
	if att > 0:
		lines.append("Attempts on this boss so far (yours and other parties'): %d." % att)
	var party := allies.size()
	if party > 0:
		lines.append("Your party of %d goes in with you; the boss grows tougher for it." % party)
	var buttons: Array = []
	if boss_state == "idle":
		buttons.append(["Open the door and fight", func() -> void: begin_boss(false)])
	elif boss_state == "dead":
		buttons.append(["Face its echo (no first-clear reward)", func() -> void: begin_boss(true)])
	elif boss_state == "fighting":
		lines.append("The fight is already under way.")
	ui.menu("The Boss Door", lines, buttons, "Not yet")


func begin_boss(as_rematch: bool) -> void:
	if boss != null and is_instance_valid(boss):
		return
	rematch = as_rematch
	boss_state = "fighting"
	FG.open_door(_door, self)
	var mult := 1.0 + 0.25 * float(allies.size())
	var info := TowerData.floor_info(tid, floor_n)
	var bi: Dictionary = (info["boss"] as Dictionary).duplicate(true)
	bi["hp"] = int(float(bi["hp"]) * mult * (0.6 if rematch else 1.0))
	bi["level"] = int(info["level"])
	if rematch:
		bi["name"] = "Echo of " + String(bi["name"])
	var known: Array = realm.known_patterns(tid, floor_n) if realm != null else []
	var bz := FloorBoss.new()
	bz.setup(bi, true, floor_n, tid, known, hash([tid, floor_n, realm.attempts_on(tid, floor_n) if realm != null else 0]))
	root.add_child(bz)
	bz.leash = 13.0
	bz.global_position = origin + (B["points"].filter(func(p: Dictionary) -> bool: return p["kind"] == "boss_spawn")[0]["pos"] as Vector3) + Vector3(0, 0.3, 0)
	bz.home = bz.global_position
	bz.rotation.y = atan2(-(FG.DIRS[int(L["door_dir"])].x), -(FG.DIRS[int(L["door_dir"])].y)) + PI
	boss = bz
	_engaged = false
	bz.hp_changed.connect(_on_boss_hp.bind(bz))
	bz.phase_changed.connect(_on_boss_phase)
	bz.pattern_started.connect(_on_boss_pattern)
	bz.enraged.connect(func() -> void: Game.say("%s is enraged!" % bi["name"]))
	bz.summon_requested.connect(_on_boss_summon)
	bz.died.connect(_on_boss_died)
	_on_boss_hp(bz.health, bz.max_health, bz)
	ui.set_boss("%s  ·  %s" % [bi["name"], bi["title"]], bz.health, bz.max_health, 1, false, true)


func _boss_check() -> void:
	if boss == null or not is_instance_valid(boss) or boss_state != "fighting":
		return
	var bz := boss as FloorBoss
	if bz.active and not _engaged:
		_engaged = true
		FG.close_door(_door)
		var learned := ""
		if realm != null:
			learned = realm.record_attempt(tid, floor_n, true)
			if learned != "":
				bz.learn(learned)
				Game.say("Attempt %d. You learn: %s. %s" % [realm.attempts_on(tid, floor_n), TowerData.PATTERNS[learned]["name"], TowerData.PATTERNS[learned]["hint"]])
		Game.say("The great door grinds shut behind you.")
	# the fight resets if everyone is down or the player flees far away (the boss heals and sleeps again)
	if _engaged and not bz.active:
		_engaged = false
		FG.open_door(_door, self)
		ui.set_boss("", 0, 1, 1, false, false)
		Game.say("The boss loses interest and settles back down.")
		bz.queue_free()
		boss = null
		boss_state = "dead" if (realm != null and realm.boss_dead(tid, floor_n)) else "idle"


func _on_boss_hp(hp: int, max_hp: int, bz: Node3D) -> void:
	ui.set_boss("%s  ·  %s" % [(bz as FloorBoss).display_name, (bz as FloorBoss).title], hp, max_hp, (bz as FloorBoss).phase, (bz as FloorBoss).is_enraged, true)


func _on_boss_phase(phase: int) -> void:
	Game.say("The boss changes its stance (phase %d)." % phase)
	var bz := boss as FloorBoss
	if bz != null:
		ui.set_boss("%s  ·  %s" % [bz.display_name, bz.title], bz.health, bz.max_health, phase, bz.is_enraged, true)


func _on_boss_pattern(pid: String, known: bool) -> void:
	var nm: String = TowerData.PATTERNS[pid]["name"]
	ui.boss_call(nm + "!" if known else "?", known)


func _on_boss_summon(count: int, at: Vector3) -> void:
	var kinds: Array = TowerData.theme(String(L["theme"]))["mobs"]
	for i in count:
		var kind: String = kinds[_rng.randi() % kinds.size()]
		var ang := TAU * float(i) / float(maxi(count, 1)) + _rng.randf()
		var info := {"name": kind.replace("_", " ").capitalize(), "kind": kind, "scale": 0.9, "tint": Color(1, 1, 1), "patterns": [],
			"hp": int(TowerData.mob_hp(floor_n) * 0.6), "damage": TowerData.mob_damage(floor_n), "level": int(L["level"])}
		var mob := FloorBoss.new()
		mob.setup(info, false, floor_n, tid, [], _rng.randi())
		mob.leash = 18.0
		root.add_child(mob)
		mob.global_position = at + Vector3(cos(ang) * 5.0, 0.4, sin(ang) * 5.0)
		mob.home = mob.global_position
		mob.engage(player)


func _on_boss_died(who: Node3D) -> void:
	boss_state = "dead"
	ui.set_boss("", 0, 1, 1, false, false)
	for n in get_tree().get_nodes_in_group("tower_enemy"):
		if n != who and n is FloorBoss and (n as FloorBoss).is_inside_tree() and root.is_ancestor_of(n):
			(n as FloorBoss).take_damage(99999, player, Vector3.ZERO)
	FG.open_door(_door, self)
	if _barrier != null:
		_barrier.visible = false
		var body := _barrier.get_node_or_null("StairBarrierBody") as StaticBody3D
		if body:
			body.collision_layer = 0
			for c in body.get_children():
				if c is CollisionShape3D:
					(c as CollisionShape3D).set_deferred("disabled", true)
	var up := point_named("stairs_up")
	if up != null:
		up.label = "Climb to floor %d" % (floor_n + 1) if floor_n < TowerData.floor_count(tid) else "The top of the spire"
		up.data = {"open": true}
	for a in allies:
		if is_instance_valid(a):
			a.call("revive")
	var res := {}
	if realm != null:
		res = realm.boss_defeated(tid, floor_n, "player", rematch)
	_reward(res)
	floor_cleared.emit(res)


func _reward(res: Dictionary) -> void:
	var tier := int(L["tier"])
	var first := bool(res.get("player_first", false))
	var lines: Array[String] = []
	var gold := _rng.randi_range(40, 70) * (tier + floor_n / 2) * (1 if first else 1) / (2 if rematch else 1)
	Game.add_gold(gold)
	if realm != null:
		realm.add_run_loot("", 0, gold)
	lines.append("%d gold" % gold)
	for i in (4 if first else 2):
		var it := _loot_one(tier + 1)
		if it != "":
			_give(it, 1)
			lines.append(Life.item_name(it))
	if first:
		var rel: Dictionary = res.get("relic", {})
		if not rel.is_empty():
			_grant_relic(rel)
			lines.append("%s (first-clear relic: +%s %s)" % [rel["name"], String(rel["value"]), String(rel["stat"]).replace("_", " ")])
		var fame := int(res.get("fame", 0))
		if fame > 0:
			Game.renown += fame
			Life.add_merit(fame, "floor %d cleared" % floor_n)
	Game.say("Spoils: " + ", ".join(lines))
	if realm != null and bool(res.get("first_clear", false)) and realm.hub != null:
		var ann := String(res.get("text", ""))
		if ann != "":
			Game.say(ann)
	if ui != null:
		var sub := "%s has fallen." % String(res.get("boss", _boss_def.get("name", "The boss"))) if not rematch else "The echo fades."
		if first:
			sub += "  First clear: the stairway opens and the realm will hear of it."
		ui.banner("FLOOR %d CLEARED" % floor_n if not rematch else "ECHO DEFEATED", sub, Color("ffd27a"), 5.0)


func _grant_relic(rel: Dictionary) -> void:
	if Life.item_prop(String(rel["id"]), "name", null) != null:
		Life.give(String(rel["id"]), 1)
	Life.equipment.add_buff(String(rel["name"]), String(rel["stat"]), float(rel["value"]), 876000.0)
