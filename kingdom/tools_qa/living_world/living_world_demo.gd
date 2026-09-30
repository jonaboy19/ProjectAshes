extends Node3D
## LIVING WORLD demo + proof: a lively village square built from the real town assets (smithy, well, market,
## tavern front, chapel, houses, fields) with villagers that work, trade, drink, pray, play and chat, using the
## life clip library, smart objects, props, ambient behaviour and the crowd animation LOD
## (NEAR skeletal -> MID stepped skeletal -> FAR VAT -> farthest sprites).
##
##   Godot --path kingdom --rendering-method mobile res://tools_qa/living_world/living_world_demo.tscn -- [options]
##   --mode=showcase    scripted camera through the square, then a crane out over the whole crowd (default)
##   --mode=stress      100+ NPC stress view (all LOD levels visible), camera slowly orbits
##   --mode=bench       per-tier cost: ms per NPC for NEAR / MID / FAR(VAT) / data-VAT / sprite; prints a table
##   --tier=low|medium|high|ultra   (CrowdAnimLOD + Quality budgets)   --hour=9.5   --rain   --tiers (tint by LOD)
##   --no_overlay   --nolod (everyone full skeletal every frame: the "before")   --seconds=N (auto quit)
## Capture: --write-movie out.avi --fixed-fps 30  (see docs/anim/living_world/HANDOFF.md)

const Tier := CrowdAnimLOD.Tier
const VAT_LOOKS := ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "elder_man",
	"villager_farmer", "villager_guard", "child_boy", "child_girl"]
const ADULTS := ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "villager_farmer",
	"villager_merchant", "villager_baker", "father", "mother"]

var args := {}
var mode := "showcase"
var cam: Camera3D
var lod: CrowdAnimLOD
var crowd: VatCrowd
var so: SmartObjects
var actors: Array = []
var hour := 10.0
var rain := false
var overlay: Label
var _t := 0.0
var _id := 0
var _data_crowd: Array = []        # [{id, look, pos, dir, a, b, speed, clip}]
var _sprites: Array = []           # MultiMesh per look
var _sprite_count := 0
var _groups: Array = []            # conversation groups: {members: Array[LifeActor], speaker, next}
var _fps_hist: Array = []
var _tint_tiers := false
var _shots: Array = []
var _baker: ImpostorBaker
var _frame_ms: Array = []
var _bench_done := false
var _ready_done := false
var t_start := 0
var t_end := 0


class EndMark extends Node:
	var demo: Node

	func _process(_d: float) -> void:
		demo.t_end = Time.get_ticks_usec()
var _beh_ms := 0.0
var _beh_acc := 0
var _beh_n := 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	mode = String(args.get("mode", "showcase"))
	process_priority = -100000
	var em := EndMark.new()
	em.demo = self
	em.process_priority = 100000
	add_child(em)
	hour = float(args.get("hour", "10.0"))
	rain = args.has("rain")
	_tint_tiers = args.has("tiers")
	seed(1234)
	_build_environment()
	_build_village()
	crowd = VatCrowd.new()
	crowd.name = "VatCrowd"
	add_child(crowd)
	crowd.load_looks(VAT_LOOKS)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 600.0
	add_child(cam)
	lod = CrowdAnimLOD.new()
	lod.vat = crowd
	lod.camera = cam
	crowd.camera = cam
	add_child(lod)
	var tiers := {"low": 0, "medium": 1, "high": 2, "ultra": 3}
	if args.has("tier"):
		lod.set_tier(tiers.get(String(args["tier"]), 2))
	if args.has("nolod"):
		lod.enabled = false
	_build_overlay()
	if mode == "bench":
		_run_bench.call_deferred()
		return
	_populate_square()
	_populate_far()
	await _populate_sprites()
	_setup_shots()
	_t = 0.0
	_ready_done = true


# ================================================================= world
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.38, 0.62, 0.92) if not rain else Color(0.45, 0.5, 0.56)
	pm.sky_horizon_color = Color(0.92, 0.88, 0.78) if not rain else Color(0.62, 0.64, 0.66)
	pm.ground_bottom_color = Color(0.35, 0.42, 0.28)
	pm.ground_horizon_color = pm.sky_horizon_color
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = pm.sky_horizon_color
	env.fog_density = 0.0010 if not rain else 0.006
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.78)
	sun.light_energy = 1.5 if not rain else 0.6
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(700, 700)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.46, 0.6, 0.3)
	gmat.roughness = 1.0
	ground.material_override = gmat
	add_child(ground)
	var plaza := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 15.0
	pc.bottom_radius = 15.0
	pc.height = 0.04
	pc.radial_segments = 48
	plaza.mesh = pc
	var cob := StandardMaterial3D.new()
	cob.albedo_texture = load("res://assets/art/textures/cobblestone.png")
	cob.uv1_scale = Vector3(0.4, 0.4, 0.4)
	cob.uv1_triplanar = true
	cob.normal_enabled = true
	cob.normal_texture = load("res://assets/art/textures/cobblestone_normal.png")
	cob.normal_scale = 1.2
	cob.albedo_color = Color(0.92, 0.86, 0.78)
	cob.roughness = 0.95
	plaza.material_override = cob
	plaza.position.y = 0.0
	add_child(plaza)
	for road: Array in [[Vector3(0, 0.01, 40), 6.0, 55.0, 0.0], [Vector3(45, 0.01, 0), 5.0, 70.0, 90.0]]:
		var r := MeshInstance3D.new()
		var rm := PlaneMesh.new()
		rm.size = Vector2(road[1], road[2])
		r.mesh = rm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.62, 0.52, 0.38)
		rmat.roughness = 1.0
		r.material_override = rmat
		r.position = road[0]
		r.rotation_degrees.y = road[3]
		add_child(r)


func _place(node: Node3D, pos: Vector3, yaw_deg: float) -> Node3D:
	if node == null:
		return null
	add_child(node)
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).get_aabb().size.length() < 2.5:
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _building(key: String, pos: Vector3, yaw: float) -> void:
	_place(Assets.building_node(key, false), pos, yaw)


func _prop(path: String, pos: Vector3, yaw: float) -> Node3D:
	if not ResourceLoader.exists(path):
		push_warning("demo: missing prop " + path)
		return null
	return _place((load(path) as PackedScene).instantiate() as Node3D, pos, yaw)


func _life_prop(name: String, pos: Vector3, yaw: float) -> Node3D:
	return _prop("res://assets/generated/life_props/%s.glb" % name, pos, yaw)


func _gen_prop(name: String, pos: Vector3, yaw: float) -> Node3D:
	return _prop("res://assets/generated/props/%s.glb" % name, pos, yaw)


func _build_village() -> void:
	so = SmartObjects.new()
	# square
	_building("well", Vector3(0, 0, 0), 0)
	so.add("well", _xf(Vector3(0, 0, 0), 0))
	_building("blacksmith", Vector3(-21, 0, -4), 90)
	_building("inn", Vector3(21, 0, -6), -90)
	_building("chapel", Vector3(0, 0, -30), 0)
	_building("market_stand_1", Vector3(-6.5, 0, 10), 180)
	_building("market_stand_2", Vector3(0, 0, 11), 180)
	_building("market_stand_3", Vector3(6.5, 0, 10), 180)
	for p: Vector3 in [Vector3(-6.5, 0, 10), Vector3(0, 0, 11), Vector3(6.5, 0, 10)]:
		so.add("market_stall", _xf(p, 180))
	var houses := [["house_1", -24, 16, 45], ["house_2", 24, 16, -45], ["house_5", -30, -18, 60], ["house_6", 29, -20, -60],
		["house_3", -12, -24, 15], ["house_7", 13, -25, -15], ["house_4", -34, 4, 90], ["house_8", 35, 6, -90]]
	for h: Array in houses:
		_building(h[0], Vector3(h[1], 0, h[2]), h[3])
	# smithy yard
	_gen_prop("anvil_stump", Vector3(-13.2, 0, -5.0), -90)
	so.add("anvil", _xf(Vector3(-13.2, 0, -5.0), -90))
	_life_prop("bellows", Vector3(-15.6, 0, -1.6), 90)
	so.add("bellows", _xf(Vector3(-15.6, 0, -1.6), 90))
	_gen_prop("water_trough", Vector3(-15.8, 0, -8.2), 90)
	_gen_prop("weapon_rack", Vector3(-16.6, 0, 1.8), 90)
	_life_prop("chopping_block", Vector3(-11.5, 0, 3.2), 60)
	so.add("chopping_block", _xf(Vector3(-11.5, 0, 3.2), 60))
	_gen_prop("woodpile", Vector3(-13.8, 0, 5.4), 20)
	_life_prop("sawhorse", Vector3(-9.0, 0, -9.5), 120)
	so.add("sawhorse", _xf(Vector3(-9.0, 0, -9.5), 120))
	# tavern front
	_life_prop("bar_counter", Vector3(14.0, 0, -6.0), -90)
	so.add("bar_counter", _xf(Vector3(14.0, 0, -6.0), -90))
	_life_prop("table", Vector3(12.0, 0, -1.2), 0)
	so.add("tavern_table", _xf(Vector3(12.0, 0, -1.2), 0))
	for s: Vector3 in [Vector3(12.0, 0, -0.5), Vector3(12.0, 0, -1.9), Vector3(12.9, 0, -1.2)]:
		_life_prop("stool", s, 0)
	_gen_prop("barrel", Vector3(15.2, 0, -10.0), 0)
	_gen_prop("barrel", Vector3(15.8, 0, -9.1), 40)
	so.add("musician_spot", _xf(Vector3(12.6, 0, -10.5), -60))
	_life_prop("cook_pot", Vector3(9.5, 0, -13.5), -30)
	so.add("cook_pot", _xf(Vector3(9.5, 0, -13.5), -30))
	# plaza furniture
	_gen_prop("bench", Vector3(5.5, 0, -3.5), -130)
	so.add("bench", _xf(Vector3(5.5, 0, -3.5), -130))
	_gen_prop("bench", Vector3(-5.8, 0, -4.2), 130)
	so.add("bench", _xf(Vector3(-5.8, 0, -4.2), 130))
	_gen_prop("notice_board", Vector3(7.5, 0, -13.0), -20)
	so.add("notice_board", _xf(Vector3(7.5, 0, -13.0), -20))
	_life_prop("wash_tub", Vector3(-3.4, 0, -2.4), 150)
	so.add("wash_tub", _xf(Vector3(-3.4, 0, -2.4), 150))
	_life_prop("hopscotch", Vector3(-4.0, 0.01, 4.0), 90)
	so.add("hopscotch", _xf(Vector3(-5.9, 0, 4.0), 90))
	so.add("play_area", _xf(Vector3(-9.0, 0, 11.0), 0))
	_gen_prop("crate_stack", Vector3(10.5, 0, 12.5), 20)
	_gen_prop("sack_pile", Vector3(-10.8, 0, 12.0), -10)
	_gen_prop("hay_bales", Vector3(26, 0, 12), 30)
	_gen_prop("lamp_post", Vector3(8, 0, 6), 0)
	_gen_prop("lamp_post", Vector3(-8, 0, -8), 0)
	so.add("conversation", _xf(Vector3(3.2, 0, 4.2), 0))
	so.add("conversation", _xf(Vector3(-2.5, 0, -10.0), 0))
	so.add("conversation", _xf(Vector3(9.0, 0, 3.0), 0))
	so.add("shrine_stand", _xf(Vector3(-2.0, 0, -23.0), 0))
	so.add("chapel_kneel", _xf(Vector3(2.5, 0, -24.5), 0))
	so.add("guard_post", _xf(Vector3(-3.0, 0, 19.0), 180))
	so.add("sweep_area", _xf(Vector3(-22.0, 0, 10.0), 30))
	# fields east of the square
	for r in 4:
		var fz := 20.0 + r * 7.0
		_soil(Vector3(38, 0.02, fz), Vector2(12.0, 5.0))
		so.add("field_row", _xf(Vector3(36.5, 0, fz - 0.8), 90))
	# trees
	var trees := [[-40, -35, "CommonTree_1"], [-46, 20, "CommonTree_3"], [44, -30, "CommonTree_2"], [-20, 38, "CommonTree_4"],
		[22, 40, "CommonTree_5"], [-55, -5, "Pine_2"], [60, -40, "Pine_1"], [-38, 48, "CommonTree_2"]]
	for t: Array in trees:
		var m := Assets.nature_mesh(t[2])
		if m:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			_place(mi, Vector3(t[0], 0, t[1]), float(absi(hash(t)) % 360))


## A tilled field bed: dark soil with furrows (a striped albedo), cheap and readable from far away.
func _soil(p: Vector3, size: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	var img := Image.create(4, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		var c := Color(0.36, 0.25, 0.16) if (y / 4) % 2 == 0 else Color(0.46, 0.33, 0.2)
		for x in 4:
			img.set_pixel(x, y, c)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(size.x, size.y / 2.0, 1.0)
	m.roughness = 1.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = p


func _xf(p: Vector3, yaw_deg: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), p)


# ================================================================= people
func _actor(look: String, pos: Vector3, yaw_deg := 0.0, child := false, height := 1.72) -> LifeActor:
	_id += 1
	var a := LifeActor.create(_id, look, height if not child else 1.25, child)
	a.hour = hour
	a.weather = "rain" if rain else ("hot" if hour > 12.0 and hour < 16.0 else "clear")
	add_child(a)
	a.global_position = pos
	a.rotation.y = deg_to_rad(yaw_deg)
	a._yaw = a.rotation.y
	actors.append(a)
	var vat_look := VatResidents.look_of_model(a.model)
	lod.register(a.person, a, a.model, a.anim, a.look_mod, vat_look)
	return a


func _spot_task(type: String, near: Vector3, slot_pref := -1) -> Dictionary:
	var best := -1
	var bd := INF
	for sp: Dictionary in so.spots:
		if sp["type"] != type:
			continue
		var d := (sp["xform"] as Transform3D).origin.distance_to(near)
		if d < bd:
			bd = d
			best = sp["id"]
	if best < 0:
		return {"wait": 3.0}
	var slot := slot_pref if slot_pref >= 0 else 0
	if slot_pref < 0:
		var h: Array = so.spots[best]["holders"]
		for k in h.size():
			if h[k] == -1:
				slot = k
				break
	return {"spot": [best, slot], "so": so}


func _populate_square() -> void:
	# smith + helper
	var smith := _actor("villager_smith", Vector3(-12, 0, -5), -90)
	smith.set_routine([_spot_task("anvil", Vector3(-14, 0, -5)), _spot_task("bellows", Vector3(-15, 0, -2)), _spot_task("anvil", Vector3(-14, 0, -5))])
	var wood := _actor("villager_man_b", Vector3(-10, 0, 4), 180)
	wood.set_routine([_spot_task("chopping_block", Vector3(-11, 0, 3))])
	var carp := _actor("father", Vector3(-8, 0, -8), 180)
	carp.set_routine([_spot_task("sawhorse", Vector3(-9, 0, -9.5))])
	# market: 3 vendors, customers wandering stall to stall
	for i in 3:
		var p: Vector3 = [Vector3(-6.5, 0, 10), Vector3(0, 0, 11), Vector3(6.5, 0, 10)][i]
		var v := _actor(["villager_merchant", "villager_baker", "villager_woman_b"][i], p + Vector3(0, 0, 1.5), 180)
		v.set_routine([_spot_task("market_stall", p, 0)])
	for i in 4:
		var c := _actor(ADULTS[(i * 3) % ADULTS.size()], Vector3(-4 + i * 2.5, 0, 5), 0)
		var stalls := [Vector3(-6.5, 0, 10), Vector3(0, 0, 11), Vector3(6.5, 0, 10)]
		c.set_routine([_spot_task("market_stall", stalls[i % 3], 1 + i % 2), {"to": Vector3(randf_range(-6, 6), 0, randf_range(2, 6))},
			{"wait": 3.0 + i}, _spot_task("market_stall", stalls[(i + 1) % 3], 1 + (i + 1) % 2)])
	# well: water carriers
	for i in 2:
		var w := _actor(["villager_woman_a", "mother"][i], Vector3(2 + i * 2, 0, 3), 0)
		var home: Vector3 = [Vector3(-20, 0, 12), Vector3(24, 0, 12)][i]
		w.set_routine([_spot_task("well", Vector3.ZERO, i), {"to": home, "carry": "Life_Carry_Bucket_Upper", "keep_carry": true},
			{"wait": 4.0}, {"to": Vector3(1.5 - i * 3.0, 0, 3.5)}])
	# laundry, sweeper, cook
	_actor("villager_woman_b", Vector3(-4, 0, -4), 150).set_routine([_spot_task("wash_tub", Vector3(-3.4, 0, -2.4))])
	_actor("elder_woman", Vector3(-21, 0, 9), 30).set_routine([_spot_task("sweep_area", Vector3(-22, 0, 10))])
	_actor("villager_baker", Vector3(9, 0, -12), -30).set_routine([_spot_task("cook_pot", Vector3(9.5, 0, -13.5))])
	# tavern front
	_actor("villager_man_a", Vector3(12.8, 0, -6.2), 90).set_routine([_spot_task("bar_counter", Vector3(14, 0, -6), 0)])
	_actor("father", Vector3(12.8, 0, -4.8), 90).set_routine([_spot_task("bar_counter", Vector3(14, 0, -6), 1)])
	_actor("villager_farmer", Vector3(11, 0, 0), 0).set_routine([_spot_task("tavern_table", Vector3(12, 0, -1.2), 0)])
	_actor("villager_man_b", Vector3(11, 0, -2), 0).set_routine([_spot_task("tavern_table", Vector3(12, 0, -1.2), 1)])
	_actor("villager_man_a", Vector3(12.5, 0, -10), -60).set_routine([_spot_task("musician_spot", Vector3(12.6, 0, -10.5))])
	# benches, notice board, chapel
	_actor("elder_man", Vector3(5, 0, -2), -130).set_routine([_spot_task("bench", Vector3(5.5, 0, -3.5), 0)])
	_actor("villager_woman_a", Vector3(-5, 0, -3), 130).set_routine([_spot_task("bench", Vector3(-5.8, 0, -4.2), 1)])
	_actor("villager_merchant", Vector3(7, 0, -11), -20).set_routine([_spot_task("notice_board", Vector3(7.5, 0, -13)), {"wait": 3.0},
		{"to": Vector3(3, 0, -6)}, {"wait": 5.0}])
	_actor("elder_woman", Vector3(-2, 0, -21), 0).set_routine([_spot_task("shrine_stand", Vector3(-2, 0, -23))])
	_actor("mother", Vector3(2.5, 0, -22), 0).set_routine([_spot_task("chapel_kneel", Vector3(2.5, 0, -24.5), 0)])
	# guards: one at the post, one patrolling
	_actor("villager_guard", Vector3(-3, 0, 18), 180).set_routine([_spot_task("guard_post", Vector3(-3, 0, 19))])
	var patrol := _actor("guard", Vector3(10, 0, 14), 0)
	patrol.amb.walk_style = "Life_Guard_Patrol_Walk"
	patrol.set_routine([{"to": Vector3(14, 0, 8)}, {"to": Vector3(14, 0, -14)}, {"wait": 2.0}, {"to": Vector3(-12, 0, -16)}, {"to": Vector3(-12, 0, 14)}, {"wait": 2.0}])
	# elder with cane, a drunk, a carrier with a sack
	var elder := _actor("elder_man", Vector3(-10, 0, 14), 90)
	elder.amb.walk_style = "Life_Walk_Cane"
	elder.amb.walk_speed = 0.62
	elder.set_routine([{"to": Vector3(8, 0, 14)}, {"wait": 4.0}, {"to": Vector3(-10, 0, 14)}, {"wait": 4.0}])
	var sack := _actor("villager_man_b", Vector3(-8, 0, 13), 90)
	sack.set_routine([{"to": Vector3(13, 0, -3), "carry": "Life_Carry_Sack_Upper", "keep_carry": true}, {"wait": 2.0},
		{"to": Vector3(-8, 0, 13)}, {"wait": 2.0}])
	# conversation groups (3 each) at the conversation spots
	for sp: Dictionary in so.spots:
		if sp["type"] != "conversation":
			continue
		var center: Vector3 = (sp["xform"] as Transform3D).origin
		var g := {"members": [], "speaker": 0, "next": 0.0}
		for k in 3:
			var sx := so.stand_xform(sp["id"], k)
			var m := _actor(ADULTS[(k + sp["id"]) % ADULTS.size()], sx.origin, 0)
			var face := atan2(center.x - sx.origin.x, center.z - sx.origin.z)
			m.rotation.y = face
			m._yaw = face
			m.chat_with(center, face, _speaking_fn(g))
			g["members"].append(m)
		_groups.append(g)
	# kids: hopscotch + tag in the play area
	var k1 := _actor("child_girl", Vector3(-4.2, 0, 2.2), 0, true)
	k1.set_routine([_spot_task("hopscotch", Vector3(-5.9, 0, 4), 0)])
	var k2 := _actor("child_boy", Vector3(-3.2, 0, 2.8), 0, true)
	k2.set_routine([_spot_task("hopscotch", Vector3(-5.9, 0, 4), 1)])
	for i in 3:
		var kid := _actor(["child_boy", "child_girl", "child_boy"][i], Vector3(-9 + i, 0, 11 + i * 0.5), 0, true)
		kid.amb.walk_style = "Life_Kid_Run_Play"
		kid.amb.walk_speed = 2.2 + 0.2 * i
		var pts := []
		for j in 5:
			pts.append({"to": Vector3(-9 + sin(i * 2.0 + j * 1.3) * 4.5, 0, 11 + cos(i * 1.7 + j * 1.1) * 3.5)})
		pts.append(_spot_task("play_area", Vector3(-9, 0, 11), i))
		kid.set_routine(pts)
	# farmers at the near field rows
	for sp: Dictionary in so.spots:
		if sp["type"] == "field_row":
			var f := _actor(["villager_farmer", "villager_man_a", "villager_woman_a"][sp["id"] % 3], (sp["xform"] as Transform3D).origin + Vector3(-2, 0, 0), 90)
			f.set_routine([{"spot": [sp["id"], 0], "so": so}])


func _speaking_fn(g: Dictionary) -> Callable:
	return func(person: int) -> bool:
		var now := Time.get_ticks_msec() / 1000.0
		if now > float(g["next"]):
			g["speaker"] = (int(g["speaker"]) + 1) % maxi(1, (g["members"] as Array).size())
			g["next"] = now + 4.0 + fmod(float(person) * 1.7, 3.0)
		var m: Array = g["members"]
		return not m.is_empty() and m[int(g["speaker"]) % m.size()].person == person


## The data tier: residents that never get a node. VatCrowd instances driven by a tiny straight-line sim
## (what WorldSim + population_lod would do for the 45-150 m band).
func _populate_far() -> void:
	var looks := ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "villager_farmer", "elder_man"]
	var work := ["Life_Farm_Hoe", "Life_Farm_Harvest", "Farm_Harvest", "Life_Farm_Sow", "Life_Mocap_Dig", "TreeChopping"]
	# far fields: rows of workers
	for f in 6:
		var base := Vector3(62 + (f % 3) * 22, 0, -30 + (f / 3) * 55)
		_soil(base + Vector3(0, 0.02, 0), Vector2(16.0, 13.0))
		for w in 9:
			_id += 1
			var p := base + Vector3(randf_range(-7, 7), 0, randf_range(-6, 6))
			var look: String = looks[_id % looks.size()]
			var a: VatAsset = crowd.assets.get(look)
			if a == null:
				continue
			var clip: String = work[_id % work.size()]
			if not a.has_clip(clip):
				clip = "Farm_Harvest" if a.has_clip("Farm_Harvest") else "Idle"
			var s := 1.72 / a.height * (0.94 + 0.12 * randf())
			crowd.put(_id, look, Transform3D(Basis(Vector3.UP, randf_range(-0.6, 0.6) + PI * 0.5).scaled(Vector3.ONE * s), p), clip, -1.0,
				randf_range(0.92, 1.08), Color(randf_range(0.38, 0.62), randf_range(0.38, 0.62), randf_range(0.38, 0.62)))
			_data_crowd.append({"id": _id, "look": look, "pos": p, "static": true})
	# road walkers and far plaza-goers
	for i in 50:
		_id += 1
		var look: String = looks[i % looks.size()] if i % 9 != 0 else "villager_guard"
		var a: VatAsset = crowd.assets.get(look)
		if a == null:
			continue
		var ang := randf() * TAU
		var r := randf_range(48.0, 120.0)
		var p0 := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var p1 := p0 + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		var walk := "Walk"
		for w: String in ["Life_Walk_Happy", "Life_Walk_Tired", "Life_Walk_Elder", "Walk+Life_Carry_Bucket_Upper", "Walk+Life_Carry_Sack_Upper"]:
			if a.has_clip(w) and randf() < 0.18:
				walk = w
		var sp := randf_range(1.0, 1.35)
		var s := 1.72 / a.height * (0.94 + 0.12 * randf())
		crowd.put(_id, look, Transform3D(Basis().scaled(Vector3.ONE * s), p0), walk, -1.0, sp / 0.98 * 0.98 / 1.2 * 1.0,
			Color(randf_range(0.38, 0.62), randf_range(0.38, 0.62), randf_range(0.38, 0.62)))
		_data_crowd.append({"id": _id, "look": look, "pos": p0, "a": p0, "b": p1, "speed": sp, "scale": s, "static": false, "t": randf()})


func _populate_sprites() -> void:
	_baker = ImpostorBaker.new()
	add_child(_baker)
	var looks := {"peasant": "Rogue_Hooded", "worker": "Barbarian", "merchant": "Mage"}
	for k: String in looks:
		await _baker.bake(k, looks[k], [] as Array[String], "Idle")
	for k: String in looks:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ImpostorBaker.quad()
		mm.instance_count = 40
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _baker.materials.get(k)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-400, -10, -400), Vector3(800, 40, 800))
		add_child(mmi)
		for i in 40:
			var ang := randf() * TAU
			var r := randf_range(150.0, 230.0)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, randf() * TAU), Vector3(cos(ang) * r, 0, sin(ang) * r)))
		_sprites.append(mmi)
		_sprite_count += 40


# ================================================================= frame
func _process(delta: float) -> void:
	t_start = Time.get_ticks_usec()
	if mode == "bench" or not _ready_done:
		return
	_t += delta
	_tick_data_crowd(delta)
	_update_camera()
	_update_overlay(delta)
	if (_tint_tiers or (mode == "showcase" and _t > float(args.get("tint_at", "52.0")))) and Engine.get_process_frames() % 15 == 0:
		_apply_tier_tint(true)
	if args.has("shot") and not has_meta("shot_done") and _t > float(args.get("shot_at", "5")):
		set_meta("shot_done", true)
		get_viewport().get_texture().get_image().save_png(String(args["shot"]))
		print("SHOT ", args["shot"])
		for a: LifeActor in actors.slice(0, 3):
			print("ACTOR %s pos=%s tier=%d clip=%s phase=%s visible=%s" % [a.look_file, a.global_position, lod.tier_of(a.person), a._clip,
				str(a.session.phase) if a.session else "-", a.model.visible])
	if args.has("seconds") and _t > float(args["seconds"]):
		get_tree().quit()


func _tick_data_crowd(delta: float) -> void:
	for d: Dictionary in _data_crowd:
		if d["static"]:
			continue
		var a: Vector3 = d["a"]
		var b: Vector3 = d["b"]
		var len := maxf(a.distance_to(b), 1.0)
		d["t"] = float(d["t"]) + delta * float(d["speed"]) / len
		var u := fposmod(float(d["t"]), 2.0)
		var fwd := u < 1.0
		var p := a.lerp(b, u if fwd else 2.0 - u)
		var dir := (b - a) if fwd else (a - b)
		var yaw := atan2(dir.x, dir.z)
		crowd.move(d["id"], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(d["scale"])), p))


func _apply_tier_tint(on: bool) -> void:
	if not on:
		return
	var cols := [Color(0.2, 1.0, 0.3, 0.35), Color(1.0, 0.85, 0.1, 0.35)]
	for a: LifeActor in actors:
		var t := lod.tier_of(a.person)
		var want: Material = null
		if t <= Tier.MID:
			var m: StandardMaterial3D = StandardMaterial3D.new() if not a.has_meta("tint_m") else a.get_meta("tint_m")
			m.albedo_color = cols[t]
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			a.set_meta("tint_m", m)
			want = m
		for g in a.model.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_overlay = want
	crowd.set_debug_tint(Color(0.25, 0.55, 1.0, 0.45))


# ================================================================= camera
func _setup_shots() -> void:
	if mode == "stress":
		_shots = [{"t": 0.0, "pos": Vector3(0, 30, 70), "look": Vector3(10, 0, 0)}, {"t": 60.0, "pos": Vector3(0, 30, 70), "look": Vector3(10, 0, 0)}]
		return
	# showcase: [start time, camera position, look target]; the timeline starts once everything is spawned
	_shots = [
		{"t": 0.0, "pos": Vector3(18, 6, 26), "look": Vector3(-2, 1, -2)},
		{"t": 6.5, "pos": Vector3(12, 4, 19), "look": Vector3(-4, 1, -4)},
		{"t": 7.0, "pos": Vector3(-9.0, 1.6, -2.4), "look": Vector3(-13.8, 1.0, -5.0)},
		{"t": 11.0, "pos": Vector3(-9.6, 1.5, -2.9), "look": Vector3(-13.8, 0.9, -5.0)},
		{"t": 13.5, "pos": Vector3(-8.5, 1.5, -0.2), "look": Vector3(-12.0, 0.9, 2.8)},
		{"t": 14.0, "pos": Vector3(-1.0, 1.3, 8.5), "look": Vector3(-5.5, 0.6, 4.5)},
		{"t": 20.0, "pos": Vector3(0.5, 1.4, 5.5), "look": Vector3(-3.5, 0.7, -2.0)},
		{"t": 20.5, "pos": Vector3(0.0, 1.7, 4.0), "look": Vector3(0.0, 1.2, 11.0)},
		{"t": 27.0, "pos": Vector3(4.0, 1.7, 5.0), "look": Vector3(6.5, 1.2, 10.5)},
		{"t": 27.5, "pos": Vector3(6.0, 1.7, -0.5), "look": Vector3(13.0, 1.1, -5.0)},
		{"t": 34.0, "pos": Vector3(8.0, 1.7, -6.0), "look": Vector3(13.0, 1.1, -10.0)},
		{"t": 34.5, "pos": Vector3(0.5, 1.7, -15.0), "look": Vector3(0.0, 1.0, -24.0)},
		{"t": 40.0, "pos": Vector3(-1.0, 1.7, -8.0), "look": Vector3(-2.5, 1.2, -10.0)},
		{"t": 40.5, "pos": Vector3(45.0, 2.4, 15.0), "look": Vector3(35.0, 0.8, 27.0)},
		{"t": 46.0, "pos": Vector3(46.0, 2.8, 22.0), "look": Vector3(35.0, 0.8, 34.0)},
		{"t": 46.5, "pos": Vector3(10.0, 8.0, 30.0), "look": Vector3(0.0, 0.0, 0.0)},
		{"t": 56.0, "pos": Vector3(-14.0, 24.0, 56.0), "look": Vector3(14.0, 0.0, 4.0)},
		{"t": 60.0, "pos": Vector3(-14.0, 24.0, 56.0), "look": Vector3(14.0, 0.0, 4.0)},
		{"t": 60.5, "pos": Vector3(15.0, 3.4, 7.0), "look": Vector3(-6.0, 0.8, -4.0)},
		{"t": 68.0, "pos": Vector3(17.0, 3.8, 9.0), "look": Vector3(-6.0, 0.8, -6.0)},
	]


func _update_camera() -> void:
	if _shots.is_empty():
		return
	if mode == "stress":
		var ang := _t * 0.08
		cam.position = Vector3(sin(ang) * 75.0, 32.0, cos(ang) * 75.0)
		cam.look_at(Vector3(10, 0, 0))
		return
	var i := 0
	while i < _shots.size() - 1 and _t >= float(_shots[i + 1]["t"]):
		i += 1
	var a: Dictionary = _shots[i]
	var b: Dictionary = _shots[mini(i + 1, _shots.size() - 1)]
	var span := maxf(float(b["t"]) - float(a["t"]), 0.001)
	var u := clampf((_t - float(a["t"])) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)
	var p: Vector3 = (a["pos"] as Vector3).lerp(b["pos"], u)
	var l: Vector3 = (a["look"] as Vector3).lerp(b["look"], u)
	cam.position = p
	cam.look_at(l)


# ================================================================= overlay
func _build_overlay() -> void:
	if args.has("no_overlay"):
		return
	var cl := CanvasLayer.new()
	add_child(cl)
	overlay = Label.new()
	overlay.position = Vector2(12, 10)
	overlay.add_theme_font_size_override("font_size", 15)
	overlay.add_theme_color_override("font_color", Color(1, 1, 1))
	overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	overlay.add_theme_constant_override("outline_size", 5)
	cl.add_child(overlay)


func _update_overlay(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	_beh_acc += LifeActor.usec_total
	LifeActor.usec_total = 0
	_beh_n += 1
	if _beh_n >= 30:
		_beh_ms = _beh_acc / 1000.0 / _beh_n
		_beh_acc = 0
		_beh_n = 0
	if _frame_ms.size() > 60:
		_frame_ms.pop_front()
	if overlay == null or Engine.get_process_frames() % 10 != 0:
		return
	var avg := 0.0
	for v: float in _frame_ms:
		avg += v
	avg /= maxf(_frame_ms.size(), 1)
	var c: Array = lod.counts
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	overlay.text = "LIVING WORLD  %s  tier %s   %.0f fps  cpu %.1f ms\nskeletal NEAR %d  MID %d   VAT %d (%d from actors)   sprites %d   = %d people\nanim-LOD %.2f ms (advance %.2f, tiering %.2f)  behaviour %.2f ms  skel updates/frame %d  draw %d" % [
		mode, ["LOW", "MEDIUM", "HIGH", "ULTRA"][lod.tier_index], Engine.get_frames_per_second(), proc,
		c[0], c[1], crowd.count(), c[2], _sprite_count, actors.size() + _data_crowd.size() + _sprite_count,
		lod.cpu_usec / 1000.0, lod.advance_usec / 1000.0, lod.retier_usec / 1000.0, _beh_ms, lod.skeleton_updates,
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))]


# ================================================================= bench
## Cost per NPC per LOD tier. Each row is measured as a PAIR on the same machine state: N NPCs in view (tier forced)
## for F frames, then the same scene with them removed for F frames; cost = (p50 with - p50 without) / N. Each
## pair runs `reps` times and the median is reported, so a background process (other Godot / Blender jobs)
## shifts both halves alike. "anim only" pauses the actors' behaviour script.
func _run_bench() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var n := int(args.get("n", "40"))
	var frames := int(args.get("frames", "240"))
	var reps := int(args.get("reps", "3"))
	cam.position = Vector3(0, 3.0, 16)
	cam.look_at(Vector3(0, 0.8, 0))
	await _settle(90)
	var looks := ["villager_man_a", "villager_man_b", "villager_woman_a", "villager_woman_b", "villager_farmer", "elder_man"]
	var rows := []
	var specs := [["NEAR full skeletal + look-at + behaviour", Tier.NEAR, false], ["MID stepped skeletal + behaviour", Tier.MID, false],
		["FAR VAT twin (actor node kept) + behaviour", Tier.FAR, false], ["NEAR anim only", Tier.NEAR, true],
		["MID anim only", Tier.MID, true], ["FAR anim only", Tier.FAR, true]]
	for spec: Array in specs:
		var per: Array = []
		var extra := {}
		for r in reps:
			lod.force_tier = spec[1]
			for i in n:
				var a := _actor(looks[i % looks.size()], Vector3(-6 + (i % 8) * 1.7, 0, -4 + (i / 8) * 1.7), 180)
				a.set_routine([{"wait": 9999.0}])
				a._play(["Idle", "Idle_Talking", "Farm_Harvest", "TreeChopping", "Life_Farm_Hoe", "Life_Talk_Explain"][i % 6], 0.0)
				a.paused = spec[2]
			await _settle(90)
			var with_m := await _measure(frames)
			for a: LifeActor in actors:
				lod.unregister(a.person)
				a.queue_free()
			actors.clear()
			await _settle(45)
			var without := await _measure(frames)
			per.append([(float(with_m["proc"]) - float(without["proc"])) * 1000.0 / n, (float(with_m["rest"]) - float(without["rest"])) * 1000.0 / n,
				(float(with_m["p50"]) - float(without["p50"])) * 1000.0 / n])
			extra = {"beh": float(with_m["beh_us"]) / n, "lod": float(with_m["lod_us"]) / n, "p50": with_m["p50"], "base": without["p50"],
				"p99": with_m["p99"]}
		lod.force_tier = -1
		rows.append([spec[0], n, _best(per), extra])
	# data-tier VAT only (no nodes), walking in place
	var nv := n * 10
	var per_v: Array = []
	var ev := {}
	for r in reps:
		for i in nv:
			var look: String = looks[i % looks.size()]
			var va: VatAsset = crowd.assets.get(look)
			if va:
				crowd.put(100000 + i, look, Transform3D(Basis().scaled(Vector3.ONE * (1.72 / va.height)), Vector3(-20 + (i % 25) * 1.6, 0, -30 + (i / 25) * 1.6)), "Walk")
		await _settle(60)
		var w := await _measure(frames)
		crowd.clear()
		await _settle(30)
		var wo := await _measure(frames)
		per_v.append([(float(w["proc"]) - float(wo["proc"])) * 1000.0 / nv, (float(w["rest"]) - float(wo["rest"])) * 1000.0 / nv,
			(float(w["p50"]) - float(wo["p50"])) * 1000.0 / nv])
		ev = {"beh": 0.0, "lod": 0.0, "p50": w["p50"], "base": wo["p50"], "p99": w["p99"]}
	rows.append(["data VAT (MultiMesh, no nodes)", nv, _best(per_v), ev])
	var lines := ["| tier | NPCs | main-thread process us / NPC | deferred + render-submit us / NPC | CPU total us / NPC | frame (wall) us / NPC | of which behaviour script | of which anim-LOD script |",
		"|---|---:|---:|---:|---:|---:|---:|---:|"]
	for row: Array in rows:
		var e: Dictionary = row[3]
		var c: Array = row[2]
		lines.append("| %s | %d | %.1f | %.1f | **%.1f** | %.1f | %.1f | %.1f |" % [row[0], row[1], c[0], c[1], c[0] + c[1], c[2], e["beh"], e["lod"]])
	lines.append("")
	lines.append("Each row: best (lowest) of %d paired runs of %d frames with / without the NPCs; vsync off. Process = first to last _process of the frame (AnimationMixer + scripts); deferred = the rest of the main-thread frame (skeleton updates, render setup, GPU wait)." % [reps, frames])
	var txt := "
".join(lines)
	print("BENCH_TABLE tier=%s
%s" % [["LOW", "MEDIUM", "HIGH", "ULTRA"][lod.tier_index], txt])
	var out := String(args.get("out", ""))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(txt + "
")
	get_tree().quit()


## Lowest process+deferred cost over the repeated pairs (the run least disturbed by other processes).
func _best(pairs: Array) -> Array:
	var best: Array = pairs[0]
	for p: Array in pairs:
		if float(p[0]) + float(p[1]) < float(best[0]) + float(best[1]):
			best = p
	return best


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _measure(frames: int) -> Dictionary:
	var gpu := 0.0
	var lodu := 0
	var vp := get_viewport().get_viewport_rid()
	var ft: Array = []
	var pt: Array = []
	var rt: Array = []
	var lodl: Array = []
	await get_tree().process_frame
	LifeActor.usec_total = 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var f := (now - last) / 1000.0
		var pr := (t_end - t_start) / 1000.0
		ft.append(f)
		pt.append(pr)
		rt.append(f - pr)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		lodl.append(lod.cpu_usec)
	var beh := LifeActor.usec_total
	lodl.sort()
	lodu = lodl[lodl.size() / 2] * frames
	ft.sort()
	pt.sort()
	rt.sort()
	return {"frame": (Time.get_ticks_usec() - t0) / 1000.0 / frames, "p50": ft[ft.size() / 2], "p99": ft[int(ft.size() * 0.99)],
		"proc": pt[pt.size() / 2], "rest": rt[rt.size() / 2], "gpu": gpu / frames,
		"beh_us": float(beh) / frames, "lod_us": float(lodu) / frames}
