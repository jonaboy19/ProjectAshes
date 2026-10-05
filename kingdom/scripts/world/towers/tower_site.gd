extends Node3D
## The dungeon tower on the map (docs/design/DUNGEON_TOWERS.md): a colossal rune-lit spire that stays on the skyline, the
## base camp at its foot, and the runtime that carries the player up into its floors.
##
## HOOK (one line, main.gd, after the Region1 hook): world.add_child(preload("res://scripts/world/towers/tower_site.gd").new())
##
## Exterior, always built at boot (3 meshes per LOD, one impostor, no per-frame work): near (<1.2 km), mid (<2.7 km) and a
## painted billboard beyond that, so the spire reads from Kingsreach and from the far corners of the map. The camera far
## plane is raised to reach it (only ever raised).
## Base camp, streamed within 420 m of the player: stalls, tents, bonfire, teleport gate, notice board, scout, NPC parties
## resting between climbs (hire them), and the great door into floor 1.
## Interior: tower_run.gd builds a floor from floor_gen.gd, high above the world (like interior_door.gd), hides the exterior
## and swaps the camera Environment; leaving frees everything. Death inside costs loot and gold and wakes you at the camp.

const Spire := preload("res://scripts/world/towers/tower_spire.gd")
const FG := preload("res://scripts/world/towers/floor_gen.gd")
const TowerData := preload("res://scripts/world/towers/tower_data.gd")
const TowerRun := preload("res://scripts/world/towers/tower_run.gd")
const TowerUI := preload("res://scripts/world/towers/tower_ui.gd")
const TowerPoint := preload("res://scripts/world/towers/tower_point.gd")
const FloorAlly := preload("res://scripts/world/towers/floor_ally.gd")

const CAMP_DIST := 100.0
const CAMP_BUILD := 420.0
const CAMP_FREE := 560.0
const ENTRY_DIST := 66.0
const INTERIOR_LIFT := 400.0
const FAR_PLANE := 5200.0
const NEAR_END := 1200.0
const MID_END := 2700.0
const ASSETS := "res://assets/generated/"
const MAX_PARTY := 3
const PORTAL_ARCHES := ["res://assets/incoming/meshy_free/magic/portal_blue_arch_lod0.glb", "res://assets/incoming/meshy_free/magic/portal_ice_arch_lod0.glb"]

var focus := Vector3.ZERO
var ui: Node
var run: Node = null
var sites: Dictionary = {}           # tower id -> {pos: Vector3, yaw, root, camp, camp_sig, impostor_mat, spire: Node3D}
var current_tower := ""
var _player: Node3D
var _hidden: Array[Node3D] = []
var _cam: Camera3D
var _saved_env: Environment = null
var _saved_view := -1
var _falling := false
var _tick := 0.0
var _slow := 0.0
var _connected := false
var inside := false


func _ready() -> void:
	name = "TowerSite"
	add_to_group("tower_site")
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "dungeon_tower":
			_build_exterior(s)
	ui = TowerUI.new()
	add_child(ui)
	if sites.is_empty():
		set_process(false)
	_raise_far_plane()


func realm() -> RefCounted:
	return Life.realm.mod("towers") if Life != null and Life.realm != null else null


func player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func _raise_far_plane() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null and cam.far < FAR_PLANE:
		cam.far = FAR_PLANE


# ====================================================================== exterior

func _build_exterior(s: Dictionary) -> void:
	var tid: String = String(s.get("tower", TowerData.DEFAULT_TOWER))
	var p2: Vector2 = s["pos"]
	var h := WorldGen.height(p2.x, p2.y)
	var root := Node3D.new()
	root.name = "Spire_" + tid
	add_child(root)
	root.position = Vector3(p2.x, h - 1.0, p2.y)
	root.rotation.y = float(s["yaw"])
	var near_m := Spire.near()
	var mid_m := Spire.mid()
	var lod := Node3D.new()
	lod.name = "Near"
	root.add_child(lod)
	_mesh(lod, near_m["lit"], 0.0, NEAR_END)
	_mesh(lod, near_m["glow"], 0.0, NEAR_END, true)
	var mid := Node3D.new()
	mid.name = "Mid"
	root.add_child(mid)
	_mesh(mid, mid_m["lit"], NEAR_END - 60.0, MID_END)
	_mesh(mid, mid_m["glow"], NEAR_END - 60.0, MID_END, true)
	var imp := MeshInstance3D.new()
	imp.name = "Impostor"
	imp.mesh = Spire.impostor_mesh()
	var imat := Spire.impostor_material()
	imp.material_override = imat
	imp.visibility_range_begin = MID_END - 60.0
	imp.visibility_range_end = 0.0
	imp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(imp)
	# collision: the shaft's base; the apron is walkable ground
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Spire.BASE_R * 0.96
	cyl.height = 70.0
	cs.shape = cyl
	cs.position.y = 34.0
	body.add_child(cs)
	root.add_child(body)
	# the door point and the glow of the arch are part of the camp (streamed), the spire itself stays
	sites[tid] = {"pos": Vector3(p2.x, h, p2.y), "yaw": float(s["yaw"]), "root": root, "camp": null, "camp_sig": "", "imat": imat,
		"name": String(s.get("name", TowerData.tower(tid).get("name", "The Spire")))}


func _mesh(parent: Node3D, m: Mesh, vmin: float, vmax: float, no_shadow := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.visibility_range_begin = vmin
	mi.visibility_range_end = vmax
	if no_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func front_of(tid: String) -> Vector3:
	var yaw: float = sites[tid]["yaw"]
	return Vector3(sin(yaw), 0, cos(yaw))


func site_ground(tid: String, dist: float) -> Vector3:
	var p: Vector3 = sites[tid]["pos"] + front_of(tid) * dist
	p.y = WorldGen.height(p.x, p.z)
	return p


# ====================================================================== process

func _process(delta: float) -> void:
	if not _connected:
		var pl := player()
		if pl != null and pl.has_signal("health_changed"):
			pl.health_changed.connect(_on_health)
			_connected = true
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var pl := player()
	if pl == null:
		return
	if not inside:
		focus = pl.global_position
		for tid: String in sites:
			_stream_camp(tid)
		# a save made inside the tower loads you up in the clouds: bring the player down to the camp
		var any_y := -1.0e9
		for tid: String in sites:
			any_y = maxf(any_y, float(sites[tid]["pos"].y))
		# (not while a building/dungeon interior is open: InteriorDoor rooms sit 300 m up, which used to read as "in the
		# clouds" and threw the player to the tower camp the moment they entered any inn, smithy, guild or house)
		if run == null and InteriorDoor.active == null and any_y > -1.0e8 and pl.global_position.y > any_y + INTERIOR_LIFT * 0.5:
			_teleport_to_camp(current_tower if current_tower != "" else String(sites.keys()[0]))
	_slow_update()


func _slow_update() -> void:
	# impostor brightness follows the day
	var t := 12.0
	if WorldSim != null:
		t = float(WorldSim.time_of_day)
	var day := clampf(smoothstep(4.5, 7.5, t) * (1.0 - smoothstep(18.0, 21.0, t)), 0.0, 1.0)
	var k := lerpf(0.4, 1.0, day)
	for tid: String in sites:
		(sites[tid]["imat"] as StandardMaterial3D).albedo_color = Color(k, k, k * 1.04, 1.0)
	_raise_far_plane()


# ====================================================================== base camp

func _stream_camp(tid: String) -> void:
	var s: Dictionary = sites[tid]
	var c: Vector3 = site_ground(tid, CAMP_DIST)
	var d := Vector2(focus.x - c.x, focus.z - c.z).length()
	if s["camp"] == null and d < CAMP_BUILD:
		build_camp(tid)
	elif s["camp"] != null and d > CAMP_FREE:
		(s["camp"] as Node3D).queue_free()
		s["camp"] = null
	elif s["camp"] != null:
		var r := realm()
		if r != null:
			var sig := _camp_sig(r, tid)
			if sig != String(s["camp_sig"]):
				_build_camp_npcs(tid)


func _camp_sig(r: RefCounted, tid: String) -> String:
	var names: Array = []
	for a: Dictionary in r.camp_adventurers(tid):
		names.append(String(a["name"]))
	return ",".join(names)


func _prop(parent: Node3D, path: String, pos: Vector3, yaw := 0.0, sc := 1.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := Assets.scene(path)
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * sc
	return n


func _ground_at(tid: String, local_fwd: float, local_right: float) -> Vector3:
	var s: Dictionary = sites[tid]
	var f := front_of(tid)
	var right := Vector3(f.z, 0, -f.x)
	var p: Vector3 = s["pos"] + f * local_fwd + right * local_right
	p.y = WorldGen.height(p.x, p.z)
	return p


func _point(parent: Node3D, tid: String, action: String, label: String, world_pos: Vector3, data := {}) -> TowerPoint:
	var p := TowerPoint.new()
	p.action = action
	p.label = label
	data["tower"] = tid
	p.data = data
	parent.add_child(p)
	p.global_position = world_pos
	return p


func build_camp(tid: String) -> Node3D:
	var s: Dictionary = sites[tid]
	if s["camp"] != null:
		return s["camp"]
	var camp := Node3D.new()
	camp.name = "BaseCamp"
	add_child(camp)
	s["camp"] = camp
	var yaw: float = s["yaw"]
	# bonfire at the centre
	var fire := _ground_at(tid, CAMP_DIST, 0.0)
	_prop(camp, ASSETS + "region/ruins/campfire.glb", fire, 0.0, 1.6)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.68, 0.36)
	fl.light_energy = 2.4
	fl.omni_range = 26.0
	fl.position = fire + Vector3(0, 2.2, 0)
	fl.set_meta("flicker", true)
	camp.add_child(fl)
	# tents ring (back side, toward the spire), stalls on the flanks, lamp posts and banners
	for i in 5:
		var a := -1.1 + float(i) * 0.55
		var p := _ground_at(tid, CAMP_DIST - 13.0 - 6.0 * absf(sin(a)), 22.0 * sin(a) * 1.4)
		_prop(camp, ASSETS + "region/ruins/bandit_tent.glb", p, yaw + PI + a * 0.4, 1.2)
	_prop(camp, ASSETS + "market_stall_red.glb", _ground_at(tid, CAMP_DIST + 4.0, -15.0), yaw + PI * 0.5, 1.3)
	_prop(camp, ASSETS + "market_stall_green.glb", _ground_at(tid, CAMP_DIST + 4.0, 15.0), yaw - PI * 0.5, 1.3)
	_prop(camp, ASSETS + "barrel_cluster.glb", _ground_at(tid, CAMP_DIST + 4.0, -19.0), yaw, 1.2)
	_prop(camp, ASSETS + "hand_cart.glb", _ground_at(tid, CAMP_DIST + 8.0, 19.0), yaw + 0.7, 1.2)
	for sgn in [-1.0, 1.0]:
		for k in 3:
			var pz := _ground_at(tid, CAMP_DIST - 14.0 + float(k) * 13.0, sgn * 26.0)
			_prop(camp, ASSETS + "lamp_post.glb", pz, yaw, 1.3)
			var bl := OmniLight3D.new()
			bl.light_color = Color(1.0, 0.8, 0.5)
			bl.light_energy = 1.0
			bl.omni_range = 11.0
			bl.position = pz + Vector3(0, 3.4, 0)
			camp.add_child(bl)
	for sgn in [-1.0, 1.0]:
		_prop(camp, ASSETS + "banner_pole.glb", _ground_at(tid, ENTRY_DIST + 6.0, sgn * 12.0), yaw, 2.4)
	# the road of flagstones from camp to the great door
	var road := _road_mesh(tid)
	camp.add_child(road)
	# teleport gate: a stone ring with a rune pillar
	var gpos := _ground_at(tid, CAMP_DIST - 4.0, -9.0)
	var gate := _gate_mesh()
	camp.add_child(gate)
	gate.global_position = gpos
	gate.rotation.y = yaw
	var gl := OmniLight3D.new()
	gl.light_color = Color(0.5, 0.85, 1.0)
	gl.light_energy = 1.6
	gl.omni_range = 14.0
	gl.position = gpos + Vector3(0, 2.4, 0)
	camp.add_child(gl)
	_point(camp, tid, "camp_gate", "Use the teleport gate", gpos + Vector3(0, 0.4, 0))
	# notice board
	var bpos := _ground_at(tid, CAMP_DIST + 2.0, 6.0)
	var nb := _prop(camp, ASSETS + "notice_board.glb", bpos, yaw + PI, 1.4)
	_point(camp, tid, "board", "Read the raid board", bpos + Vector3(0, 0.6, 0))
	# the great door
	var door := _ground_at(tid, ENTRY_DIST, 0.0)
	_point(camp, tid, "enter", "Enter %s" % TowerData.tower(tid).get("name", "the tower"), door + Vector3(0, 0.6, 0))
	# Meshy free pack portal arch over the approach to the great door (docs/qa/ASSET_AUDIT.md section A, magic/)
	var arch: Node3D = Assets.static_model(PORTAL_ARCHES[absi(tid.hash()) % PORTAL_ARCHES.size()])
	if arch != null:
		camp.add_child(arch)
		arch.position = door + Vector3(0, -0.05, 0)
		arch.rotation.y = yaw
		arch.scale = Vector3.ONE * 1.5
	# scout and quartermaster NPCs
	var scout_pos := _ground_at(tid, CAMP_DIST - 9.0, 11.0)
	_npc(camp, "Hunter", scout_pos, yaw + PI * 0.8, "Idle_Listening")
	_point(camp, tid, "scout", "Talk to the scout", scout_pos + Vector3(0, 0.9, 0))
	var qm_pos := _ground_at(tid, CAMP_DIST + 1.5, -12.5)
	_npc(camp, "Trader", qm_pos, yaw + PI * 0.3, "Idle_Talking")
	_point(camp, tid, "camp_vendor", "Trade with the quartermaster", qm_pos + Vector3(0, 0.9, 0))
	_build_camp_npcs(tid)
	return camp


func _npc(parent: Node3D, look: String, pos: Vector3, yaw: float, anim := "Idle") -> Node3D:
	var n: Node3D = Assets.character(look, 1.75)
	if n == null:
		return null
	parent.add_child(n)
	n.global_position = pos
	n.rotation.y = yaw
	var ap := Assets.animation_player(n)
	if ap:
		for a in [anim, "Idle"]:
			if ap.has_animation(a):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				ap.play(a)
				break
	return n


## Adventurer parties resting in the camp, standing around the fire (changes as the race goes on).
func _build_camp_npcs(tid: String) -> void:
	var s: Dictionary = sites[tid]
	var camp: Node3D = s["camp"]
	if camp == null:
		return
	var old := camp.get_node_or_null("Adventurers")
	if old != null:
		old.free()
	var holder := Node3D.new()
	holder.name = "Adventurers"
	camp.add_child(holder)
	var r := realm()
	s["camp_sig"] = _camp_sig(r, tid) if r != null else ""
	if r == null:
		return
	var list: Array = r.camp_adventurers(tid)
	var yaw: float = s["yaw"]
	for i in mini(list.size(), 12):
		var a: Dictionary = list[i]
		var ang := TAU * float(i) / float(maxi(list.size(), 1)) + 0.4
		var p := _ground_at(tid, CAMP_DIST + cos(ang) * 6.5, sin(ang) * 6.5)
		var look: String = FloorAlly.LOOKS.get(String(a["job"]), "Mercenary")
		var n := _npc(holder, look, p, atan2(-cos(ang), -sin(ang)) + yaw * 0.0, "Idle_Talking" if i % 2 == 0 else "Idle")
		if n != null:
			n.rotation.y = atan2(-(p.x - _ground_at(tid, CAMP_DIST, 0.0).x), -(p.z - _ground_at(tid, CAMP_DIST, 0.0).z))
			_point(holder, tid, "adventurer", "Talk to %s" % a["name"], p + Vector3(0, 0.9, 0), {"adv": a})


func _road_mesh(tid: String) -> MeshInstance3D:
	var mb := FG.MB.new()
	var f := front_of(tid)
	var right := Vector3(f.z, 0, -f.x)
	var base: Vector3 = sites[tid]["pos"]
	var steps := 24
	for i in steps:
		var d0 := ENTRY_DIST + 2.0 + (CAMP_DIST - ENTRY_DIST - 4.0) * float(i) / float(steps)
		var d1 := ENTRY_DIST + 2.0 + (CAMP_DIST - ENTRY_DIST - 4.0) * float(i + 1) / float(steps)
		var w := 4.5
		var a := base + f * d0 - right * w
		var b := base + f * d0 + right * w
		var c := base + f * d1 + right * w
		var e := base + f * d1 - right * w
		a.y = WorldGen.height(a.x, a.z) + 0.06
		b.y = WorldGen.height(b.x, b.z) + 0.06
		c.y = WorldGen.height(c.x, c.z) + 0.06
		e.y = WorldGen.height(e.x, e.z) + 0.06
		var col := Color(0.5, 0.47, 0.42) if i % 2 == 0 else Color(0.44, 0.41, 0.37)
		mb.quad(a, e, c, b, col)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.mesh(FG.lit_material())
	mi.name = "FlagstoneRoad"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _gate_mesh() -> Node3D:
	var n := Node3D.new()
	n.name = "CampGate"
	var lit := FG.MB.new()
	var glow := FG.MB.new()
	var stone := Color(0.42, 0.4, 0.38)
	lit.prism(Vector3.ZERO, 2.6, 2.3, 0.5, 10, stone.darkened(0.15))
	for sgn in [-1.0, 1.0]:
		lit.box(Vector3(sgn * 2.0, 2.3, 0), Vector3(0.7, 4.6, 0.8), stone)
	lit.box(Vector3(0, 4.8, 0), Vector3(5.0, 0.7, 0.9), stone.lightened(0.05))
	glow.box(Vector3(0, 2.6, 0), Vector3(3.2, 3.6, 0.12), Color(0.35, 0.7, 1.0, 1.0))
	glow.ring(Vector3(0, 0.53, 0), 1.2, 1.8, 20, Color(0.5, 0.85, 1.0))
	var a := MeshInstance3D.new()
	a.mesh = lit.mesh(FG.lit_material())
	n.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = glow.mesh(FG.glow_material(1.3))
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(b)
	return n


# ====================================================================== input and dispatch

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if ui != null and ui.menu_open:
		return
	var pl := player()
	if pl == null or not pl.has_method("nearest_interactable"):
		return
	var target: Node3D = pl.call("nearest_interactable")
	if target != null and target.is_in_group("tower_point"):
		handle_point(target)
		get_viewport().set_input_as_handled()


func handle_point(p: Node3D) -> void:
	var tid := String(p.data.get("tower", current_tower if current_tower != "" else TowerData.DEFAULT_TOWER))
	match String(p.get("action")):
		"enter":
			enter_from_camp(tid)
		"camp_gate":
			camp_gate_menu(tid)
		"board":
			board_menu(tid)
		"scout":
			scout_menu(tid)
		"camp_vendor":
			camp_vendor_menu(tid)
		"adventurer":
			adventurer_menu(tid, p.data["adv"])
		_:
			if run != null and is_instance_valid(run):
				(run as TowerRun).interact(p)


func _say(t: String) -> void:
	Game.say(t)


# ---- camp menus -------------------------------------------------------------------------

func enter_from_camp(tid: String) -> void:
	var r := realm()
	if r == null:
		return
	current_tower = tid
	# enter at the floor the player last cleared + 1 (or floor 1): the stairs of the tower lead up from the camp
	enter_floor(tid, 1, "start")


func camp_gate_menu(tid: String) -> void:
	var r := realm()
	var buttons: Array = []
	for e: Dictionary in r.teleport_menu(tid):
		var f := int(e["floor"])
		buttons.append(["Floor %d · %s  (Lv %d)%s" % [f, e["name"], int(e["level"]), "  ✓" if bool(e["cleared"]) else ""], func() -> void: teleport_to(tid, f)])
	var lines := ["A ring of rune-stone. Floors whose gate you have woken can be reached from here."]
	if buttons.is_empty():
		lines.append("No gate is awake yet. Climb the stairs of floor 1 and touch the gate in its arrival room.")
	ui.menu("Teleport gate", lines, buttons)


func board_menu(tid: String) -> void:
	var r := realm()
	var lines: Array = []
	lines.append("Highest boss felled: floor %d. Yours: floor %d." % [r.world_highest(tid), r.highest_cleared(tid)])
	for row: Dictionary in r.race():
		lines.append("%s%s: floor %d%s" % [row["name"], " (raid)" if row["raid"] else "", int(row["floor"]), "  resting" if row["state"] == "camp" else ""])
	var news: Array = r.announcements
	for i in range(maxi(0, news.size() - 3), news.size()):
		lines.append("Day %d: %s" % [int(news[i]["day"]), news[i]["text"]])
	if not r.relics.is_empty():
		lines.append("Your relics: " + ", ".join(r.relics.map(func(x: Dictionary) -> String: return String(x["name"]))))
	ui.menu("Raid board", lines, [])


func scout_menu(tid: String) -> void:
	var r := realm()
	var top := mini(TowerData.floor_count(tid), maxi(r.highest_cleared(tid), r.world_highest(tid)) + 1)
	var buttons: Array = []
	for f in range(top, 0, -1):
		if buttons.size() >= 8:
			break
		var cost: int = r.scout_cost(tid, f)
		var done: bool = r.has_scouted(tid, f)
		buttons.append(["Floor %d boss report  ·  %s" % [f, "known" if done else "%d gold" % cost], _buy_report.bind(tid, f, cost), (not done) and Game.gold >= cost])
	ui.menu("Scout", ["I have watched the boss doors for weeks. Gold buys what I saw: its name, strength and moves. Every attempt teaches you more on your own, too."], buttons)


func _buy_report(tid: String, f: int, cost: int) -> void:
	if Game.gold < cost:
		return
	Game.add_gold(-cost)
	var res: Dictionary = realm().scout_report(tid, f)
	_say("Scout's report: " + String(res["text"]))
	ui.menu("Scout's report, floor %d" % f, [res["text"]], [])


func camp_vendor_menu(tid: String) -> void:
	var stock := ["bandage", "healing_salve", "stamina_draught", "antidote", "bread", "stew", "iron_dagger", "leather_cap"]
	var buttons: Array = []
	for id: String in stock:
		var price: Variant = Life.item_prop(id, "price", null)
		if price == null:
			continue
		var cost := int(ceil(float(price) * 1.2))
		buttons.append(["%s  ·  %d gold" % [Life.item_name(id), cost], _camp_buy.bind(id, cost), Game.gold >= cost])
	ui.menu("Quartermaster", ["Supplies for the climb. You have %d gold." % Game.gold], buttons)


func _camp_buy(id: String, cost: int) -> void:
	if Game.gold < cost:
		return
	Game.add_gold(-cost)
	Life.give(id, 1)
	_say("Bought %s for %d gold." % [Life.item_name(id), cost])


func adventurer_menu(tid: String, adv: Dictionary) -> void:
	var r := realm()
	var fol: RefCounted = Life.realm.mod("followers")
	var party_n: int = fol.party().size()
	var level := TowerData.floor_level(tid, maxi(1, r.highest_cleared(tid) + 1))
	var cost := 25 + level * 3
	var lines := ["%s, %s of the %s." % [adv["name"], String(adv["job"]), adv["party_name"]]]
	if int(adv["hurt"]) > 0:
		lines.append("Still nursing wounds (%d days)." % int(adv["hurt"]))
	lines.append("Will climb with you for 3 days for %d gold. Your party: %d / %d." % [cost, party_n, MAX_PARTY])
	ui.menu(String(adv["name"]), lines, [["Hire for 3 days  ·  %d gold" % cost, _hire.bind(adv, cost), Game.gold >= cost and party_n < MAX_PARTY and int(adv["hurt"]) == 0]])


func _hire(adv: Dictionary, cost: int) -> void:
	var fol: RefCounted = Life.realm.mod("followers")
	if Game.gold < cost or fol.party().size() >= MAX_PARTY:
		return
	Game.add_gold(-cost)
	var fid: String = fol.hire_temp(String(adv["job"]), "s0", 72, "tower_" + String(adv["name"]))
	var f: Dictionary = fol.get_follower(fid)
	if not f.is_empty():
		f["name"] = adv["name"]
	_say("%s joins your party for three days." % adv["name"])


# ====================================================================== entering and leaving

func teleport_to(tid: String, f: int) -> void:
	var r := realm()
	if r == null or not r.can_teleport_to(tid, f):
		_say("That gate is not awake yet.")
		return
	enter_floor(tid, f, "start")


func interior_origin(tid: String) -> Vector3:
	var p: Vector3 = sites[tid]["pos"]
	return Vector3(p.x - 44.0, p.y + INTERIOR_LIFT, p.z - 44.0)


## Builds and enters floor `f`. Works from the camp, from another floor and for the stairs/gate transitions.
func enter_floor(tid: String, f: int, arrive := "start") -> bool:
	var r := realm()
	var pl := player()
	if r == null or pl == null or not sites.has(tid):
		return false
	if not r.is_floor_open(tid, f):
		_say("The stairway to floor %d is sealed. Its boss guards the way." % f)
		return false
	current_tower = tid
	if run != null and is_instance_valid(run):
		var old := run
		run = null
		(old as TowerRun).end()
	if not inside:
		_enter_interior_mode(tid)
	var rn := TowerRun.new()
	add_child(rn)
	run = rn
	rn.floor_cleared.connect(_on_floor_cleared)
	rn.ascend_requested.connect(func() -> void: enter_floor(tid, f + 1, "start"))
	rn.descend_requested.connect(func() -> void: enter_floor(tid, f - 1, "stairs_up"))
	rn.teleport_requested.connect(func(ff: int) -> void: teleport_to(tid, ff))
	rn.exit_requested.connect(leave_tower)
	rn.start(tid, f, interior_origin(tid), r, ui, pl, arrive)
	if _cam != null:
		_cam.environment = FG.environment(String(rn.L["theme"]))
	var info := TowerData.floor_info(tid, f)
	var fresh: bool = r.activate_gate(tid, f)
	ui.banner("FLOOR %d" % f, "%s · recommended level %d" % [info["name"], int(info["level"])], UITheme.ACCENT_2, 3.0)
	if fresh:
		_say("The teleport gate of floor %d awakens." % f)
	if arrive == "start" and f > 1 and not r.boss_dead(tid, f - 1):
		pass
	# leaving the camp banks nothing: the run log keeps counting until a safe route
	return true


func _enter_interior_mode(tid: String) -> void:
	inside = true
	var pl := player()
	var host := get_parent()
	_hidden.clear()
	for c in host.get_children():
		if c == pl or c == self or not (c is Node3D) or c.is_ancestor_of(self):
			continue
		var n := c as Node3D
		if n.visible:
			n.visible = false
			_hidden.append(n)
	# the exterior (spire, camp) hides too: the interior sits inside its altitude range
	for t: String in sites:
		(sites[t]["root"] as Node3D).visible = false
		if sites[t]["camp"] != null:
			(sites[t]["camp"] as Node3D).visible = false
	_cam = pl.get("camera") as Camera3D if "camera" in pl else get_viewport().get_camera_3d()
	if _cam != null:
		_saved_env = _cam.environment
	if "view" in pl and pl.has_method("set_view"):
		_saved_view = int(pl.get("view"))
		pl.call("set_view", 1)


func leave_tower() -> void:
	if not inside:
		return
	var pl := player()
	var tid := current_tower
	var r := realm()
	if run != null and is_instance_valid(run):
		var old := run
		run = null
		(old as TowerRun).end()
	if r != null:
		r.bank_run()
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	for t: String in sites:
		(sites[t]["root"] as Node3D).visible = true
		if sites[t]["camp"] != null:
			(sites[t]["camp"] as Node3D).visible = true
	if _cam != null and is_instance_valid(_cam):
		_cam.environment = _saved_env
	if _saved_view >= 0 and pl != null:
		pl.call("set_view", _saved_view)
	_saved_view = -1
	inside = false
	ui.close_menu()
	_teleport_to_camp(tid)


func _teleport_to_camp(tid: String) -> void:
	var pl := player()
	if pl == null or not sites.has(tid):
		return
	var at := site_ground(tid, ENTRY_DIST + 9.0)
	pl.global_position = at + Vector3(0, 0.6, 0)
	if "velocity" in pl:
		pl.set("velocity", Vector3.ZERO)
	var look := front_of(tid)
	if pl.has_method("set_camera"):
		pl.call("set_camera", atan2(look.x, look.z), -0.2)
	if pl is CharacterBody3D:
		(pl as CharacterBody3D).reset_physics_interpolation()


# ====================================================================== events

func _on_floor_cleared(res: Dictionary) -> void:
	# the world hears: society gets the rumour from realm.boss_defeated; here only a nudge for the log
	if bool(res.get("first_clear", false)):
		Game.say(String(realm().rumour_line(current_tower, int(res["floor"]), "player" if bool(res.get("player_first", false)) else "someone")))


func _on_health(current: int, _maximum: int) -> void:
	if current > 0 or run == null or _falling:
		return
	_falling = true
	await get_tree().create_timer(1.7).timeout
	_apply_death()


## The cost of falling in the tower: ~10% of the purse, ~30% of the loot gathered this climb, a minor injury; you wake at
## the camp. No permadeath.
func _apply_death() -> void:
	var r := realm()
	var pl := player()
	_falling = false
	if r == null or pl == null or not inside:
		return
	var loss: Dictionary = r.death_losses(Game.gold)
	if int(loss["gold"]) > 0:
		Game.add_gold(-int(loss["gold"]))
	var lost: Array = []
	for id: String in loss["items"]:
		if Life.take(id, int(loss["items"][id])):
			lost.append("%d %s" % [int(loss["items"][id]), Life.item_name(id)])
	var inj: String = loss["injury"]
	if not Life.injuries.has(inj):
		Life.injuries.add(inj, WorldSim.day)
		Life.magicules.apply_effects(Life.injuries.effects())
	leave_tower()
	if pl.has_method("revive"):
		pl.call("revive", false)
	var text := "You wake at the tower camp, bruised."
	if int(loss["gold"]) > 0:
		text += " %d gold is gone." % int(loss["gold"])
	if not lost.is_empty():
		text += " Lost: " + ", ".join(lost) + "."
	Game.say(text)
	ui.banner("YOU FELL", text, Color("ff8f8f"), 5.0)


# ====================================================================== shots / tests

## Enter floor f directly (QA): opens the stairs as far as needed.
func debug_enter(tid: String, f: int) -> bool:
	var r := realm()
	for k in range(1, f):
		if not r.boss_dead(tid, k):
			r.world_cleared[tid] = k
	return enter_floor(tid, f, "start")
