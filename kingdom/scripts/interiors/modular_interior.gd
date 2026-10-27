extends "res://scripts/interiors/interior_room.gd"
## A building interior generated from a layout (scripts/interiors/interior_layouts.gd) with the box kit
## (scripts/interiors/interior_kit.gd). Package F6. One scene per layout (scenes/interiors/modular/<id>.tscn) only sets
## `layout_id`; everything else is built in code:
##
##   _ready            shell, furniture meshes (4 batched draws: solid / glass / fire / lamp), colliders, PlayerSpawn,
##                     ExitDoor (a trigger that contains the spawn point), NPC_* markers, 2 lights, WorldEnvironment
##   build_furniture   the interactables: Sleep (bed_prop.gd), Sit (Seat), Open (Container, owned), Climb (Ladder), the
##                     hearth and, in shops, the counter Station. Runs deferred in-game (the door has set the owner
##                     and the lot by then) or by hand in tests with an explicit building id and owner.
##   apply_hour        window glass, room light, hearth, lamp and ambient follow the hour (interior_light.gd)
##   sync_roster       the household members the schedule puts here appear as bodies and act (household.gd)

const Kit := preload("res://scripts/interiors/interior_kit.gd")
const Layouts := preload("res://scripts/interiors/interior_layouts.gd")
const Light := preload("res://scripts/interiors/interior_light.gd")
const Household := preload("res://scripts/interiors/household.gd")
const IndoorActor := preload("res://scripts/interiors/indoor_actor.gd")
const BedProp := preload("res://scripts/interiors/bed_prop.gd")
const Ownership_ := preload("res://scripts/sim/ownership.gd")
const Seat_ := preload("res://scripts/interaction/kinds/seat.gd")
const Container_ := preload("res://scripts/interaction/kinds/container.gd")
const ShopScreen_ := preload("res://scripts/ui/shop_screen.gd")
const ShopHours_ := preload("res://scripts/sim/shop_hours.gd")

const PLASTER := Color(0.74, 0.66, 0.52)
const WOOD := Color(0.42, 0.28, 0.16)
const DARK := Color(0.26, 0.17, 0.10)
const FLOOR := Color(0.36, 0.26, 0.17)
const STONE := Color(0.46, 0.44, 0.41)
## Interior pass 2 (coordinator gate 2026-10-28, KCD-like rooms): dark oak frame timbers (posts, sill, plate, joists; the
## solid shader gives them beam_wall_01 grain), undyed bedding, straw rushes on the floor.
const BEAM := Color(0.2, 0.14, 0.09)
const LINEN := Color(0.8, 0.74, 0.6)
const WOOL := Color(0.5, 0.41, 0.31)
const RUSH := Color(0.6, 0.5, 0.3)
const CLOTHS := [Color(0.62, 0.22, 0.18), Color(0.2, 0.32, 0.55), Color(0.55, 0.45, 0.2), Color(0.3, 0.45, 0.28)]

@export var layout_id := "cottage"

var layout: Dictionary = {}
var kit: RefCounted = null
var building_id := ""
var building_owner := ""
var furniture := {"beds": [], "seats": [], "containers": [], "stations": [], "ladders": [], "hearths": []}
var exit_door: InteriorDoor = null
var bodies := {}                       # person -> Node3D
var live_roster := true                # false in tests that place bodies by hand
var _env: Environment = null
var _room_light: OmniLight3D = null
var _hearth_light: OmniLight3D = null
var _hearth_base := 1.0
var _night_k := 0.0                    # 0 day .. 1 night: how far the room light has left the ceiling to ride beside the player (dark clothes read black under the ambient alone)
var _hearth_phase := 0.0
var _ikit_group: Array = []     # [group, GeometryInstance3D]: kit pieces that fade with their wall (joined after kit.build)
## Draw budget (test_draw_budget_per_interior <= 60): every kit piece / clutter prop is batched per (mesh, fade group) into one
## MultiMeshInstance3D, so 40 posts, beams and pots cost a handful of draws.
var _batches := {}              # "meshid|group" -> {mesh, group, xforms: Array[Transform3D]}
var _shaft: SpotLight3D = null     # HIGH: daylight shaft through the first window (energy by hour)
var _kit_nodes := {}
var _clock := 0.0
var _last_hour := -1.0
var _furnished := false
var _flick := 0.0
var _group_nodes := {}                 # wall / ceiling group -> Array[MeshInstance3D] (see InteriorKit "group")
var _group_fade := {}                  # group -> 0 shown .. 1 hidden (eased toward wall_fade_targets)

## The cut-away camera: a wall (with its windows), or the ceiling, fades out while the camera is on its outer side or
## within WALL_FADE_MARGIN of it, so the chase camera never films the back of a wall or the roof slab.
const WALL_FADE_MARGIN := 0.6
const WALL_FADE_RATE := 6.0


func _ready() -> void:
	layout = Layouts.layout(layout_id)
	if layout.is_empty():
		push_warning("ModularInterior: unknown layout %s" % layout_id)
		return
	set_meta("title", String(layout["title"]))
	set_meta("layout", layout_id)
	_build_shell()
	_build_markers()
	_build_lights()
	super()
	set_process(true)
	apply_hour(WorldSim.time_of_day)
	_late_setup.call_deferred()


func _late_setup() -> void:
	if not is_inside_tree() or _furnished:
		return
	var door := InteriorDoor.active
	if door != null and door.has_meta("lot_pos"):
		var lp: Variant = door.get_meta("lot_pos")
		if lp is Vector2:
			building_id = "b%d_%d" % [roundi(lp.x), roundi(lp.y)]
	if building_id == "":
		building_id = layout_id
	var owner := String(get_meta("building_owner")) if has_meta("building_owner") else ""
	build_furniture(building_id, owner)
	sync_roster(WorldSim.time_of_day, true)
	var sm := Kit._solid_detail()
	if sm is ShaderMaterial:      # soot round this room's fire, grime from this room's floor (one room is entered at a time)
		var hs: Array = furniture["hearths"]
		(sm as ShaderMaterial).set_shader_parameter("hearth_pos", to_global(hs[0]) if not hs.is_empty() else Vector3(0, -1000, 0))
		(sm as ShaderMaterial).set_shader_parameter("floor_y", global_position.y)
	_add_room_gi()


## AAA gap audit P0 (2026-10-28): interiors had no bounce light and no reflections (flat blue-grey). The rooms are built
## at runtime from layouts, so a LightmapGI cannot be pre-baked per room; VoxelGI can bake at runtime, so a small room
## gets one (subdiv 64, ~0.1-0.3 s, once, after the furniture is in) plus a ReflectionProbe (update once, box
## projection). Forward+ MEDIUM and up only; LOW / Compatibility keep the old lights. --nogi disables both (A/B).
func _add_room_gi() -> void:
	if not bool(get_meta("embedded", false)) or OS.get_cmdline_user_args().has("--nogi"):
		return
	var tier := int(Quality.tier)
	if tier < 1 or RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	var w := float(layout["w"])
	var d := float(layout["d"])
	var h := float(layout["h"])
	var size := Vector3(w + 0.6, h + 0.4, d + 0.6)
	var centre := Vector3(0.0, h * 0.5, 0.0)
	var probe := ReflectionProbe.new()
	probe.name = "RoomReflection"
	probe.size = size
	probe.position = centre
	probe.box_projection = true
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(probe)
	var gi := VoxelGI.new()
	gi.name = "RoomGI"
	gi.size = size
	gi.position = centre
	gi.subdiv = VoxelGI.SUBDIV_64
	add_child(gi)
	gi.bake()
	# light shafts: a thin volumetric haze in the room's own Environment (HIGH+), so the window daylight and the
	# hearth read as beams through dust (audit P0 "FogVolume / interior light shafts"; LOW and MEDIUM off)
	if tier >= 2 and not (layout["windows"] as Array).is_empty():
		# one daylight shaft through the first window: a soft spot from outside the pane, angled down into the room;
		# its volumetric energy draws the beam in the haze (by day only, apply_hour scales it)
		var win: Dictionary = layout["windows"][0]
		var wpos := Vector3(float(win["at"]), (float(win["y0"]) + float(win["y1"])) * 0.5, 0.0)
		var inward := Vector3(0, 0, 1)
		match String(win["wall"]):
			"N": wpos.z = -d * 0.5
			"S":
				wpos.z = d * 0.5
				inward = Vector3(0, 0, -1)
			"E":
				wpos = Vector3(w * 0.5, wpos.y, float(win["at"]))
				inward = Vector3(-1, 0, 0)
			"W":
				wpos = Vector3(-w * 0.5, wpos.y, float(win["at"]))
				inward = Vector3(1, 0, 0)
		_shaft = SpotLight3D.new()
		_shaft.name = "WindowShaft"
		_shaft.light_color = Color(1.0, 0.93, 0.8)
		_shaft.spot_range = maxf(w, d) + 2.0
		_shaft.spot_angle = 16.0
		_shaft.spot_angle_attenuation = 1.6
		_shaft.shadow_enabled = true
		_shaft.light_volumetric_fog_energy = 6.0
		add_child(_shaft)
		_shaft.position = wpos - inward * 1.2 + Vector3(0, 1.0, 0)
		_shaft.look_at(to_global(wpos + inward * 2.5 + Vector3(0, -1.3, 0)), Vector3.UP)
		apply_hour(_last_hour)
	if tier >= 2 and _env != null:
		_env.volumetric_fog_enabled = true
		_env.volumetric_fog_density = 0.035
		_env.volumetric_fog_albedo = Color(0.95, 0.88, 0.76)
		_env.volumetric_fog_length = maxf(w, d) + 4.0
		_env.volumetric_fog_gi_inject = 0.6
		_env.volumetric_fog_anisotropy = 0.6
	if gi.data != null:
		gi.data.energy = 1.2
		gi.data.interior = true
		gi.data.use_two_bounces = true

# ------------------------------------------------------------------ geometry
func _wall_t(wall: String, at: float, w: float, d: float) -> float:
	match wall:
		"N": return at + w * 0.5
		"S": return w * 0.5 - at
		"E": return at + d * 0.5
	return d * 0.5 - at       # W


func _build_shell() -> void:
	kit = Kit.new()
	var w := float(layout["w"])
	var d := float(layout["d"])
	var h := float(layout["h"])
	var t := Kit.WALL_T * 0.5
	var hw := w * 0.5 + t         # wall centre lines: the inner faces are exactly w x d apart
	var hd := d * 0.5 + t
	# floor, ceiling, beams
	kit.solid(Vector3(0, -0.1, 0), Vector3(w + 0.44, 0.2, d + 0.44), FLOOR)
	kit.ceiling_solid(Vector3(0, h + 0.1, 0), Vector3(w + 0.44, 0.2, d + 0.44), DARK, "ceil")
	var beams := maxi(3, int(d / 1.1))
	var beam_mesh := _ikit_mesh("beam_4m")
	for i in beams:
		var z := -d * 0.5 + d * (float(i) + 0.5) / float(beams)
		if beam_mesh != null:
			var bb := beam_mesh.get_aabb()
			_ikit_piece(beam_mesh, Vector3(-(w + 0.1) * 0.5, h - 0.11 - (bb.position.y + bb.size.y * 0.5), z), 0.0,
				Vector3((w + 0.1) / maxf(bb.size.x, 0.1), 1.0, 1.0), "ceil")
		else:
			kit.box(Vector3(0, h - 0.11, z), Vector3(w + 0.1, 0.2, 0.16), BEAM, "solid", 0.0, "ceil")
	# outer walls with window and door openings
	var opens := {"N": [], "S": [], "E": [], "W": []}
	for win: Dictionary in layout["windows"]:
		var wall := String(win["wall"])
		(opens[wall] as Array).append({"at": _wall_t(wall, float(win["at"]), w, d), "w": float(win["w"]),
			"y0": float(win["y0"]), "y1": float(win["y1"])})
	(opens["S"] as Array).append({"at": _wall_t("S", float(layout["door_x"]), w, d), "w": 1.2, "y0": 0.0, "y1": 2.1})
	# one mesh per outer wall (with its windows): the wall between the camera and the room fades out (_fade_walls)
	kit.wall(Vector2(-hw, -hd), Vector2(hw, -hd), h, PLASTER, opens["N"], Kit.WALL_T, 0.0, "wN")
	kit.wall(Vector2(hw, -hd), Vector2(hw, hd), h, PLASTER, opens["E"], Kit.WALL_T, 0.0, "wE")
	kit.wall(Vector2(hw, hd), Vector2(-hw, hd), h, PLASTER, opens["S"], Kit.WALL_T, 0.0, "wS")
	kit.wall(Vector2(-hw, hd), Vector2(-hw, -hd), h, PLASTER, opens["W"], Kit.WALL_T, 0.0, "wW")
	_build_frame(w, d, h, opens)
	_build_rushes(w, d)
	# window panes + frames (the pane is the emissive "glass" the light driver colours)
	for win: Dictionary in layout["windows"]:
		_build_window(win, w, d)
	# doorway frame + the leaf standing open against the wall
	var dx := float(layout["door_x"])
	kit.box(Vector3(dx - 0.65, 1.05, hd), Vector3(0.1, 2.1, 0.3), WOOD, "solid", 0.0, "wS")
	kit.box(Vector3(dx + 0.65, 1.05, hd), Vector3(0.1, 2.1, 0.3), WOOD, "solid", 0.0, "wS")
	kit.box(Vector3(dx - 0.25, 1.0, hd - 0.55), Vector3(0.9, 2.0, 0.05), DARK, "solid", PI * 0.5 + 0.0)
	# partitions
	for part: Dictionary in layout["partitions"]:
		kit.wall(part["a"], part["b"], float(part["h"]), PLASTER, part["openings"], 0.14)
	# loft
	var loft: Dictionary = layout["loft"]
	if not loft.is_empty():
		_build_loft(loft)
	# props
	for p: Dictionary in layout["props"]:
		_build_prop(p)
	if not CityPlanner.towns_off():
		_build_clutter(w, d, h, opens)
	_kit_nodes = kit.build(self)
	for key: String in _kit_nodes:
		if key.contains("|"):
			var g := key.get_slice("|", 1)
			if not _group_nodes.has(g):
				_group_nodes[g] = []
				_group_fade[g] = 0.0
			(_group_nodes[g] as Array).append(_kit_nodes[key])
	_flush_batches()
	for e: Array in _ikit_group:
		var g2 := String(e[0])
		if not _group_nodes.has(g2):
			_group_nodes[g2] = []
			_group_fade[g2] = 0.0
		(_group_nodes[g2] as Array).append(e[1])


static var _mesh_cache := {}     # path -> Mesh: one Mesh per piece, so the batches share it (merged_mesh builds a new one per call)


static func _cached_mesh(path: String) -> Mesh:
	if not _mesh_cache.has(path):
		_mesh_cache[path] = Assets.merged_mesh(path, false) if ResourceLoader.exists(path) else null
	return _mesh_cache[path]


static func _ikit_mesh(name: String) -> Mesh:
	if CityPlanner.towns_off():
		return null
	return _cached_mesh(IKIT % [name, name])


## One kit piece (posts, beams, windows) in room space; `scale` stretches it to the slot; `group` = the wall it fades with.
func _ikit_piece(mesh: Mesh, pos: Vector3, yaw: float, scale: Vector3, group: String) -> void:
	_batch(mesh, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), pos), group)


func _batch(mesh: Mesh, xf: Transform3D, group: String) -> void:
	var key := "%d|%s" % [mesh.get_instance_id(), group]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "group": group, "xforms": []}
	(_batches[key]["xforms"] as Array).append(xf)


func _flush_batches() -> void:
	for key: String in _batches:
		var b: Dictionary = _batches[key]
		var xs: Array = b["xforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b["mesh"]
		mm.instance_count = xs.size()
		for i in xs.size():
			mm.set_instance_transform(i, xs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		if String(b["group"]) != "":
			_ikit_group.append([b["group"], mmi])
	_batches.clear()


## Exposed timber frame on the inner face of the four outer walls: sill beam, top plate, posts every ~2 m (none across a
## door or window), a brace in every other bay. Each piece joins its wall's fade group.
func _build_frame(w: float, d: float, h: float, opens: Dictionary) -> void:
	var inset := 0.07
	for wall: String in ["N", "E", "S", "W"]:
		var length := w if wall in ["N", "S"] else d
		var g := "w" + wall
		var yaw := 0.0 if wall in ["N", "S"] else PI * 0.5
		var mid := _frame_point(wall, length * 0.5, 0.0, inset, w, d)
		# sill, plate, studs and rail are kit boxes (merged into the wall's own mesh: no extra draws, beam_wall_01 grain from
		# the solid shader); only the diagonal braces use the kit post (a box cannot roll) - draw budget
		var beam_mesh: Mesh = null
		var post_mesh: Mesh = null
		var brace_mesh := _ikit_mesh("post_3m")
		if beam_mesh != null:
			# kit beams run along +X from their origin end: start at tt = 0, turned so +X follows the wall's tt direction
			var dir_yaw := {"N": 0.0, "S": PI, "E": -PI * 0.5, "W": PI * 0.5}[wall] as float
			var bb := beam_mesh.get_aabb()
			var sx := length / maxf(bb.size.x, 0.1)
			var cy := bb.position.y + bb.size.y * 0.5
			for y_at: float in [0.11, h - 0.32]:
				_ikit_piece(beam_mesh, _frame_point(wall, 0.0, y_at - cy, inset, w, d), dir_yaw, Vector3(sx, 1.0, 1.0), g)
		else:
			kit.box(Vector3(mid.x, 0.11, mid.z), Vector3(length, 0.22, 0.14), BEAM, "solid", yaw, g)          # sill
			kit.box(Vector3(mid.x, h - 0.32, mid.z), Vector3(length, 0.2, 0.14), BEAM, "solid", yaw, g)       # top plate
		if brace_mesh != null:
			_frame_rails_and_braces(wall, length, h, inset, w, d, yaw, g, opens[wall], null, brace_mesh)
		var n := maxi(2, int(round(length / 1.05)))      # studs about a metre apart (half-timber close studding)
		for i in n + 1:
			var tt := clampf(length * float(i) / float(n), 0.1, length - 0.1)
			var blocked := false
			for o: Dictionary in opens[wall]:
				if absf(tt - float(o["at"])) < float(o["w"]) * 0.5 + 0.16:
					blocked = true
			if blocked:
				continue
			if post_mesh != null:
				var pb := post_mesh.get_aabb()
				_ikit_piece(post_mesh, _frame_point(wall, tt, 0.0, inset, w, d), yaw, Vector3(1.0, (h - 0.2) / maxf(pb.size.y, 0.1), 1.0), g)
			else:
				kit.box(_frame_point(wall, tt, (h - 0.2) * 0.5, inset, w, d), Vector3(0.16, h - 0.2, 0.14), BEAM, "solid", yaw, g)


## Mid rail at 0.85 m (broken at the door) and a diagonal brace in every other bay between the studs.
func _frame_rails_and_braces(wall: String, length: float, h: float, inset: float, w: float, d: float, yaw: float, g: String,
		opens: Array, beam_mesh: Mesh, post_mesh: Mesh) -> void:
	var dir_yaw := {"N": 0.0, "S": PI, "E": -PI * 0.5, "W": PI * 0.5}[wall] as float
	# spans of the wall free of openings that reach below the rail
	var cuts: Array = [[0.0, 0.0]]
	for o: Dictionary in opens:
		if float(o["y0"]) < 0.95:
			cuts.append([float(o["at"]) - float(o["w"]) * 0.5 - 0.05, float(o["at"]) + float(o["w"]) * 0.5 + 0.05])
	cuts.append([length, length])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in cuts.size() - 1:
		var a0 := float(cuts[k][1])
		var a1 := float(cuts[k + 1][0])
		if a1 - a0 > 0.3:
			var rm := _frame_point(wall, (a0 + a1) * 0.5, 0.85, inset + 0.01, w, d)
			kit.box(rm, Vector3(a1 - a0, 0.16, 0.12), BEAM, "solid", yaw, g)
	# braces: from the sill at one stud to the plate at the next, every other bay, clear of openings
	var pb := post_mesh.get_aabb()
	var n := maxi(2, int(round(length / 1.05)))
	var bay := length / float(n)
	var rise := h - 0.6
	for i in n:
		if i % 2 == 1:
			continue
		var t0 := bay * float(i)
		var t1 := t0 + bay
		var clear := true
		for o: Dictionary in opens:
			if float(o["at"]) + float(o["w"]) * 0.5 + 0.1 > t0 and float(o["at"]) - float(o["w"]) * 0.5 - 0.1 < t1:
				clear = false
		if not clear:
			continue
		var diag := sqrt(bay * bay + rise * rise)
		var ang := atan2(bay, rise) * (1.0 if (i / 2) % 2 == 0 else -1.0)
		var foot := _frame_point(wall, t0 + bay * 0.5, 0.22 + rise * 0.5, inset + 0.02, w, d)
		var bas := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), ang) * Basis.from_scale(Vector3(0.8, diag / maxf(pb.size.y, 0.1), 0.8))
		_batch(post_mesh, Transform3D(bas, foot - bas * Vector3(0, pb.position.y + pb.size.y * 0.5, 0)), g)


## Lived-in clutter: 25-40 pieces in clusters along the walls (not in front of doors, windows at floor level, or furniture),
## the hearth corner (firewood, hay, pots, bucket), a peg rail of cloaks, the herb rack over the hearth, a spinning wheel by
## a window, a skin by each bed. Deterministic per building id.
func _build_clutter(w: float, d: float, h: float, opens: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layout_id) ^ 0x7c1
	var taken: Array = []     # [Vector2 centre, radius]
	for p: Dictionary in layout["props"]:
		var f: Vector2 = Layouts.FOOT.get(String(p["t"]), Vector2(0.5, 0.5))
		if int(p.get("level", 0)) == 0 and String(p["t"]) != "rug":
			taken.append([p["p"], maxf(f.x, f.y) * 0.55 + 0.15])
	taken.append([Vector2(float(layout["door_x"]), d * 0.5 - 0.6), 1.1])        # the way in
	var hearth := Vector3.INF
	var hearth_yaw := 0.0
	for p: Dictionary in layout["props"]:
		if String(p["t"]) in ["hearth", "oven"]:
			hearth = Vector3((p["p"] as Vector2).x, 0.0, (p["p"] as Vector2).y)
			hearth_yaw = deg_to_rad(float(p.get("y", 0.0)))
	var placed := 0
	# hearth corner: firewood stack + hay, pots on the hearth front, a bucket and a cauldron-like pot
	if hearth != Vector3.INF:
		var hb := Basis(Vector3.UP, hearth_yaw)
		for e: Array in [["@woodpile", Vector3(1.35, 0, 0.1)], ["@hay", Vector3(-1.4, 0, 0.25)], ["ceramic_pot", Vector3(0.45, 0, 0.75)],
				["jug_01", Vector3(-0.5, 0, 0.8)], ["wooden_bucket_01", Vector3(1.0, 0, 0.9)], ["wooden_bowl_01", Vector3(-0.15, 0, 0.95)]]:
			var at := hearth + hb * (e[1] as Vector3)
			if _clutter_put(String(e[0]), Vector2(at.x, at.z), rng.randf() * TAU, taken, w, d, rng):
				placed += 1
		# herb rack on the wall above the hearth's side
		var rack := _ikit_mesh("herbs_rack")
		if rack != null:
			var rp := hearth + hb * Vector3(1.1, 1.75, -0.2)
			_ikit_piece(rack, rp, hearth_yaw, Vector3.ONE, "")
			placed += 1
	# clusters along the walls
	var walls := ["N", "E", "S", "W"]
	var target := 45
	var tries := 0
	while placed < target and tries < 900:
		tries += 1
		var wall: String = walls[rng.randi() % 4]
		var length := w if wall in ["N", "S"] else d
		var tt := rng.randf_range(0.4, length - 0.4)
		var blocked := false
		for o: Dictionary in opens[wall]:
			if float(o["y0"]) < 1.2 and absf(tt - float(o["at"])) < float(o["w"]) * 0.5 + 0.35:
				blocked = true
		if blocked:
			continue
		var c3 := _frame_point(wall, tt, 0.0, 0.42, w, d)
		var n_cluster := rng.randi_range(3, 5)
		for k in n_cluster:
			var pick := _clutter_pick(rng)
			var jitter := Vector2(rng.randf_range(-0.7, 0.7), rng.randf_range(-0.15, 0.45))
			var along := Vector2(1, 0) if wall in ["N", "S"] else Vector2(0, 1)
			var inn := Vector2(0, 1) if wall == "N" else (Vector2(0, -1) if wall == "S" else (Vector2(-1, 0) if wall == "E" else Vector2(1, 0)))
			var q := Vector2(c3.x, c3.z) + along * jitter.x + inn * jitter.y
			var yaw := rng.randf() * TAU
			if String(pick[2]) == "lean":
				yaw = {"N": 0.0, "S": PI, "E": -PI * 0.5, "W": PI * 0.5}[wall]
			if _clutter_put(String(pick[0]), q, yaw, taken, w, d, rng, String(pick[2]) == "lean"):
				placed += 1
	# a peg rail with cloaks and a hat on the first free wall stretch
	for wall: String in ["W", "E", "N"]:
		var length2 := w if wall in ["N", "S"] else d
		var tt2 := length2 * 0.5
		var ok := true
		for o: Dictionary in opens[wall]:
			if absf(tt2 - float(o["at"])) < float(o["w"]) * 0.5 + 0.9:
				ok = false
		if not ok:
			continue
		var yaw2 := 0.0 if wall in ["N", "S"] else PI * 0.5
		var rp2 := _frame_point(wall, tt2, 1.72, 0.2, w, d)
		kit.box(rp2, Vector3(1.4, 0.06, 0.05), BEAM, "solid", yaw2, "w" + wall)
		for k in 3:
			var off := (float(k) - 1.0) * 0.45
			var cp := _frame_point(wall, tt2 + off, 1.25, 0.24, w, d)
			kit.box(cp, Vector3(0.38, 0.9, 0.06), CLOAKS[(k + absi(hash(layout_id))) % CLOAKS.size()], "solid", yaw2, "w" + wall)
			kit.box(cp + Vector3(0, 0.42, 0), Vector3(0.2, 0.08, 0.1), CLOAKS[(k + 1) % CLOAKS.size()].darkened(0.2), "solid", yaw2, "w" + wall)
		placed += 4
		break
	# skins / rag rugs beside the beds, a spinning wheel near the first window
	for p: Dictionary in layout["props"]:
		if String(p["t"]) in ["bed", "cot"] and int(p.get("level", 0)) == 0:
			var by := deg_to_rad(float(p.get("y", 0.0)))
			var side := (p["p"] as Vector2) + Vector2(cos(by), -sin(by)) * 0.95
			kit.box(Vector3(side.x, 0.012, side.y), Vector3(0.75, 0.02, 1.2), Color(0.42, 0.33, 0.24), "solid", by + 0.12)
			placed += 1
	var wheel := PH % ["spinning_wheel_01", "spinning_wheel_01"]
	if ResourceLoader.exists(wheel) and not (layout["windows"] as Array).is_empty():
		var win: Dictionary = layout["windows"][0]
		var wall3 := String(win["wall"])
		var tt3 := _wall_t(wall3, float(win["at"]), w, d) + 0.9
		var wp := _frame_point(wall3, tt3, 0.0, 0.75, w, d)
		if _clutter_put("spinning_wheel_01", Vector2(wp.x, wp.z), rng.randf() * TAU, taken, w, d, rng):
			placed += 1
	set_meta("clutter_count", placed)


var _clutter_set: Array = []      # this room's 7 clutter kinds (each kind is one batched draw: draw budget)


func _clutter_pick(rng: RandomNumberGenerator) -> Array:
	if _clutter_set.is_empty():
		var all := CLUTTER.duplicate()
		for i in range(all.size() - 1, 0, -1):     # seeded shuffle
			var j := rng.randi() % (i + 1)
			var tmp: Variant = all[i]
			all[i] = all[j]
			all[j] = tmp
		_clutter_set = all.slice(0, 5 if String(layout.get("category", "")) == "tavern" else 7)     # taverns already carry many furniture kinds
	var total := 0
	for e: Array in _clutter_set:
		total += int(e[1])
	var r := rng.randi() % total
	for e: Array in _clutter_set:
		r -= int(e[1])
		if r < 0:
			return e
	return _clutter_set[0]


## Places one clutter piece standing on the floor at q (room-local), unless it would overlap furniture or other clutter.
func _clutter_put(name: String, q: Vector2, yaw: float, taken: Array, w: float, d: float, rng: RandomNumberGenerator, lean := false) -> bool:
	var mesh: Mesh = null
	if name.begins_with("@"):
		var key := name.substr(1)
		if Assets.BUILDINGS.has(key):
			mesh = Assets.building_mesh(key)
	else:
		mesh = _cached_mesh(PH % [name, name])
	if mesh == null:
		return false
	var bb := mesh.get_aabb()
	var r := maxf(bb.size.x, bb.size.z) * 0.5
	if bb.size.y > 2.2 or r > 1.4:
		return false          # a full haystack or stack is too big for a room
	if absf(q.x) > w * 0.5 - r - 0.05 or absf(q.y) > d * 0.5 - r - 0.05:
		return false
	for t: Array in taken:
		if (t[0] as Vector2).distance_to(q) < float(t[1]) * 0.8 + r * 0.6:
			return false
	taken.append([q, r])
	var b := Basis(Vector3.UP, yaw)
	if lean:
		b = b * Basis(Vector3(1, 0, 0), -0.22)     # tilted back against the wall
	_batch(mesh, Transform3D(b, Vector3(q.x, 0.0, q.y) - b * Vector3(bb.position.x + bb.size.x * 0.5, bb.position.y, bb.position.z + bb.size.z * 0.5)), "")
	return true


## A point on the inner face of an outer wall: `tt` metres along it (same direction as _wall_t), `inn` metres into the room.
func _frame_point(wall: String, tt: float, y: float, inn: float, w: float, d: float) -> Vector3:
	match wall:
		"N": return Vector3(tt - w * 0.5, y, -d * 0.5 + inn)
		"S": return Vector3(w * 0.5 - tt, y, d * 0.5 - inn)
		"E": return Vector3(w * 0.5 - inn, y, tt - d * 0.5)
	return Vector3(-w * 0.5 + inn, y, d * 0.5 - tt)


## Strewn rushes and straw on the floor (a medieval floor was never bare boards): thin flat strands, thicker along the
## walls, a trodden path from the door stays bare. Deterministic per layout.
func _build_rushes(w: float, d: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(layout_id) ^ 0x5157
	var rush_mesh := _ikit_mesh("floor_rushes")
	if rush_mesh != null:      # the kit's rush mats, sparingly: along the walls and by the hearth, never on the door path
		for i in maxi(2, int(w * d / 7.0)):
			var rx := rng.randf_range(-w * 0.5 + 0.6, w * 0.5 - 0.6)
			var rz := rng.randf_range(-d * 0.5 + 0.6, d * 0.5 - 0.6)
			if absf(rx - float(layout.get("door_x", 0.0))) < 0.9 and rz > 0.0:
				continue
			if absf(rx) < w * 0.25 and absf(rz) < d * 0.25:
				continue
			_ikit_piece(rush_mesh, Vector3(rx, 0.0, rz), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.1), "")
		return
	var n := int(w * d * 9.0)
	for i in n:
		var x := rng.randf_range(-w * 0.5 + 0.15, w * 0.5 - 0.15)
		var z := rng.randf_range(-d * 0.5 + 0.15, d * 0.5 - 0.15)
		var edge := minf(minf(w * 0.5 - absf(x), d * 0.5 - absf(z)), 2.0) / 2.0
		if absf(x - float(layout.get("door_x", 0.0))) < 0.6 and rng.randf() < 0.85:
			continue       # the worn path from the door
		if rng.randf() < edge * 0.75:
			continue       # thinner toward the middle of the room
		var c := RUSH.lerp(Color(0.42, 0.34, 0.2), rng.randf())
		kit.box(Vector3(x, 0.006 + rng.randf() * 0.01, z), Vector3(rng.randf_range(0.3, 0.7), 0.014, rng.randf_range(0.03, 0.07)), c, "solid", rng.randf() * TAU)


func _build_window(win: Dictionary, w: float, d: float) -> void:
	var wall := String(win["wall"])
	var at := float(win["at"])
	var ww := float(win["w"])
	var y0 := float(win["y0"])
	var y1 := float(win["y1"])
	var pos := Vector3.ZERO
	var yaw := 0.0
	match wall:
		"N": pos = Vector3(at, 0, -d * 0.5 - Kit.WALL_T * 0.5)
		"S": pos = Vector3(at, 0, d * 0.5 + Kit.WALL_T * 0.5)
		"E":
			pos = Vector3(w * 0.5 + Kit.WALL_T * 0.5, 0, at)
			yaw = PI * 0.5
		"W":
			pos = Vector3(-w * 0.5 - Kit.WALL_T * 0.5, 0, at)
			yaw = PI * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var mid := (y0 + y1) * 0.5
	var gh := y1 - y0
	var wmesh := _ikit_mesh("window_open")
	if wmesh != null:
		# kit window: bottom-centre on the wall face, shutters opening inward; stretched to the opening. The pane stays the
		# light driver's emissive "glass" (warm horn by day) behind the leaded lattice.
		var face_yaw := {"N": 0.0, "S": PI, "E": -PI * 0.5, "W": PI * 0.5}[wall] as float
		var inward := Basis(Vector3.UP, face_yaw) * Vector3(0, 0, 1)
		var wb := wmesh.get_aabb()
		kit.box(pos + Vector3(0, mid, 0), Vector3(ww - 0.06, gh - 0.06, 0.04), Color.WHITE, "glass", yaw, "w" + wall)
		_ikit_piece(wmesh, pos + inward * (Kit.WALL_T * 0.25) + Vector3(0, y0 - wb.position.y * (gh / maxf(wb.size.y, 0.1)), 0), face_yaw,
			Vector3(ww / maxf(wb.size.x, 0.1), gh / maxf(wb.size.y, 0.1), 1.0), "w" + wall)
		return
	# The pane (emissive "glass", tinted by the hour in apply_hour) sits inside a full frame: sill, head, both jambs, a centre
	# mullion and a transom, so it reads as a window in the wall and never as a floating white card.
	kit.box(pos + Vector3(0, mid, 0), Vector3(ww - 0.06, gh - 0.06, 0.04), Color.WHITE, "glass", yaw, "w" + wall)
	kit.box(pos + Vector3(0, y0, 0), Vector3(ww + 0.14, 0.07, 0.34), WOOD, "solid", yaw, "w" + wall)
	kit.box(pos + Vector3(0, y1, 0), Vector3(ww + 0.14, 0.07, 0.30), WOOD, "solid", yaw, "w" + wall)
	for sx: float in [-1.0, 1.0]:
		kit.box(pos + basis * Vector3(sx * (ww * 0.5 + 0.01), 0, 0) + Vector3(0, mid, 0), Vector3(0.07, gh, 0.30), WOOD, "solid", yaw, "w" + wall)
	kit.box(pos + Vector3(0, mid, 0), Vector3(0.05, gh, 0.1), WOOD, "solid", yaw, "w" + wall)
	kit.box(pos + Vector3(0, mid + gh * 0.12, 0), Vector3(ww, 0.04, 0.1), WOOD, "solid", yaw, "w" + wall)
	# small horn panes in a lead lattice (the glass material is tinted warm horn in apply_hour)
	for k in 3:
		var fx := (float(k) + 1.0) / 4.0 - 0.5
		kit.box(pos + basis * Vector3(fx * ww, 0, 0) + Vector3(0, mid, 0), Vector3(0.018, gh - 0.06, 0.06), DARK, "solid", yaw, "w" + wall)
		kit.box(pos + Vector3(0, mid + fx * gh, 0), Vector3(ww - 0.06, 0.018, 0.06), DARK, "solid", yaw, "w" + wall)
	# board shutters folded open against the inner wall either side
	var inward := Vector3(0, 0, 1)
	match wall:
		"S": inward = Vector3(0, 0, -1)
		"E": inward = Vector3(-1, 0, 0)
		"W": inward = Vector3(1, 0, 0)
	for sx: float in [-1.0, 1.0]:
		var sp := pos + inward * (Kit.WALL_T * 0.5 + 0.03) + basis * Vector3(sx * (ww * 0.75 + 0.08), 0, 0) + Vector3(0, mid, 0)
		kit.box(sp, Vector3(ww * 0.5, gh, 0.04), WOOD, "solid", yaw, "w" + wall)
		for by: float in [0.3, -0.3]:
			kit.box(sp + inward * 0.025 + Vector3(0, gh * by, 0), Vector3(ww * 0.5, 0.08, 0.02), BEAM, "solid", yaw, "w" + wall)


func _build_loft(loft: Dictionary) -> void:
	var x0 := float(loft["x0"])
	var x1 := float(loft["x1"])
	var z0 := float(loft["z0"])
	var z1 := float(loft["z1"])
	var y := float(loft["y"])
	kit.solid(Vector3((x0 + x1) * 0.5, y - 0.075, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.15, z1 - z0), WOOD)
	# railing along the open edge (z1) with a gap where the ladder comes up
	var lx := (loft["ladder_top"] as Vector3).x
	var gap := {"at": lx - x0, "w": 1.3, "y0": 0.0, "y1": 3.0}
	kit.wall(Vector2(x0, z1), Vector2(x1, z1), y + 1.0, DARK, [gap], 0.08, y + 0.85)
	var rail_a := lx - 0.65 - x0
	var rail_b := x1 - (lx + 0.65)
	for seg: Array in [[x0, rail_a], [lx + 0.65, rail_b]]:
		if float(seg[1]) > 0.1:
			kit.collider(Vector3(float(seg[0]) + float(seg[1]) * 0.5, y + 0.5, z1), Vector3(float(seg[1]), 1.0, 0.1))
	for px: float in [x0 + 0.05, x1 - 0.05, lx - 0.65, lx + 0.65]:
		kit.box(Vector3(px, y + 0.5, z1), Vector3(0.08, 1.0, 0.08), DARK)


# ---- props -----------------------------------------------------------------
## A box in a prop's own frame (+Z front), turned by the prop's yaw.
func _pb(p: Dictionary, local: Vector3, size: Vector3, col: Color, mat := "solid", collide := false) -> void:
	var pos: Vector2 = p["p"]
	var yaw := deg_to_rad(float(p.get("y", 0.0)))
	var base_y := float((layout["loft"] as Dictionary).get("y", 0.0)) if int(p.get("level", 0)) > 0 else 0.0
	var centre := Vector3(pos.x, base_y, pos.y) + Basis(Vector3.UP, yaw) * local
	if collide:
		kit.solid(centre, size, col, mat, yaw)
	else:
		kit.box(centre, size, col, mat, yaw)


func _cloth(p: Dictionary, k := 0) -> Color:
	var pos: Vector2 = p["p"]
	return CLOTHS[absi(hash("%s%d" % [pos, k])) % CLOTHS.size()]


## Benchmark slice (AAA gate: no flat-colour props): prop types that have a gated real-scan / Meshy model use it (natural size,
## box collider), everything else keeps the box build below. `--townsoff` keeps the old boxes for A/B recordings.
const REAL_PROPS := {"hearth": "ms_hearth", "table": "ms_table", "barrel": "ph_barrel", "crate": "ph_crate"}
const STOOL_PATH := "res://assets/cc0/props/painted_wooden_stool/painted_wooden_stool_1k.gltf"
## Refined interior kit (Blender worker, props_refined/interior/<name>/<name>.glb; origins at the feet, beams along +X from
## one end, windows bottom-centre on the wall face). Layout prop type -> kit piece; a missing file keeps the box build.
const IKIT := "res://assets/props_refined/interior/%s/%s.glb"
const IKIT_PROPS := {"bed": "bed_rope", "cot": "bed_rope", "stool": "stool_three_leg", "chair": "chair_woven",
	"chest": "chest_iron", "cupboard": "shelf_pottery", "shelf": "shelf_pottery", "rack": "herbs_rack"}
## Lived-in clutter (coordinator gate 2026-10-28, KCD rooms are packed): real-scan / refined pieces clustered along the walls
## and round the hearth. [path or Assets key, weight, kind]; kind: floor (stands on the floor), lean (against a wall).
const PH := "res://assets/incoming/polyhaven/models/%s/%s_1k.gltf"
const CLUTTER := [
	["wicker_basket_01", 3, "floor"], ["wicker_basket_02", 2, "floor"], ["wooden_bucket_01", 2, "floor"], ["wooden_bucket_02", 1, "floor"],
	["wooden_crate_01", 2, "floor"], ["wooden_crate_02", 1, "floor"], ["ceramic_pot", 2, "floor"],
	["jug_01", 2, "floor"], ["wooden_bowl_01", 1, "floor"], ["wicker_basket_01", 2, "floor"], ["@hay", 1, "floor"],
	["@crate_stack", 1, "floor"], ["@pr_barrel_rack", 1, "floor"], ["@woodpile", 1, "floor"], ["wooden_barrels_01", 1, "floor"],
	["wooden_broom", 1, "lean"], ["rusted_spade_01", 1, "lean"], ["hatchet", 1, "floor"], ["wooden_axe", 1, "lean"],
]
const CLOAKS := [Color(0.36, 0.29, 0.21), Color(0.3, 0.32, 0.27), Color(0.45, 0.38, 0.28), Color(0.26, 0.22, 0.2)]


func _real_prop(p: Dictionary, t: String) -> bool:
	if CityPlanner.towns_off():
		return false
	var mesh: Mesh = null
	var turn := 0.0
	if IKIT_PROPS.has(t) and _ikit_mesh(String(IKIT_PROPS[t])) != null:
		mesh = _ikit_mesh(String(IKIT_PROPS[t]))
		# the layout footprint is w (x) by dd (z); a kit piece modelled the other way round is turned a quarter
		var foot: Vector2 = Layouts.FOOT.get(t, Vector2(0.5, 0.5))
		var mb := mesh.get_aabb()
		if (foot.y > foot.x * 1.3) != (mb.size.z > mb.size.x * 1.3):
			turn = PI * 0.5
	elif REAL_PROPS.has(t):
		mesh = Assets.building_mesh(REAL_PROPS[t])
	elif t == "stool" and ResourceLoader.exists(STOOL_PATH):
		mesh = _cached_mesh(STOOL_PATH)
	if mesh == null:
		return false
	var bb := mesh.get_aabb()
	var yaw := deg_to_rad(float(p.get("y", 0.0)))
	var off := Basis(Vector3.UP, turn) * Vector3(-(bb.position.x + bb.size.x * 0.5), -bb.position.y, -(bb.position.z + bb.size.z * 0.5))
	var at := _world_centre(p, off)
	_batch(mesh, Transform3D(Basis(Vector3.UP, yaw + turn), at), "")      # same pieces share one draw
	if turn != 0.0:
		bb = AABB(Vector3.ZERO, Vector3(bb.size.z, bb.size.y, bb.size.x))
	if t != "stool":
		kit.collider(_world_centre(p, Vector3(0, bb.size.y * 0.5, 0)), bb.size, yaw)
	return true


func _build_prop(p: Dictionary) -> void:
	var t := String(p["t"])
	var f: Vector2 = Layouts.FOOT.get(t, Vector2(0.5, 0.5))
	var w := float(p.get("w", f.x))
	var dd := float(p.get("dd", f.y))
	if _real_prop(p, t):
		if t == "hearth":
			_pb(p, Vector3(0, 0.3, 0.45), Vector3(0.5, 0.25, 0.03), Color.WHITE, "fire")     # keep the fire glow the hearth use reads
		return
	match t:
		"bed", "cot":
			# a plain box bed on four stout legs, straw tick, linen bolster, undyed wool blanket (no dyed sheets)
			_pb(p, Vector3(0, 0.24, 0), Vector3(w, 0.12, dd), WOOD, "solid", true)
			for lx: float in [-1.0, 1.0]:
				for lz: float in [-1.0, 1.0]:
					_pb(p, Vector3(lx * (w * 0.5 - 0.05), 0.12, lz * (dd * 0.5 - 0.05)), Vector3(0.09, 0.24, 0.09), BEAM)
			_pb(p, Vector3(0, 0.37, 0.05), Vector3(w - 0.1, 0.14, dd - 0.1), LINEN.darkened(0.12))
			_pb(p, Vector3(0, 0.49, -dd * 0.5 + 0.35), Vector3(w * 0.6, 0.1, 0.35), LINEN)
			_pb(p, Vector3(0, 0.46, dd * 0.12), Vector3(w - 0.1, 0.07, dd * 0.55), WOOL.lerp(Color(0.38, 0.33, 0.27), float(absi(hash(p["p"])) % 100) / 100.0))
			_pb(p, Vector3(0, 0.3, -dd * 0.5 + 0.03), Vector3(w, 0.6, 0.06), BEAM)     # low headboard: the bed clips lie across it
		"table":
			_pb(p, Vector3(0, 0.75, 0), Vector3(w, 0.06, dd), WOOD, "solid", false)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_pb(p, Vector3(sx * (w * 0.5 - 0.08), 0.36, sz * (dd * 0.5 - 0.08)), Vector3(0.07, 0.72, 0.07), DARK)
			kit.collider(_world_centre(p, Vector3(0, 0.4, 0)), Vector3(w, 0.8, dd), deg_to_rad(float(p.get("y", 0.0))))
		"chair":
			_pb(p, Vector3(0, 0.45, 0), Vector3(0.42, 0.05, 0.42), WOOD)
			_pb(p, Vector3(0, 0.74, -0.2), Vector3(0.42, 0.5, 0.05), WOOD)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_pb(p, Vector3(sx * 0.18, 0.22, sz * 0.18), Vector3(0.05, 0.44, 0.05), DARK)
		"stool":
			_pb(p, Vector3(0, 0.45, 0), Vector3(0.34, 0.05, 0.34), WOOD)
			_pb(p, Vector3(0, 0.22, 0), Vector3(0.24, 0.44, 0.24), DARK)
		"bench":
			_pb(p, Vector3(0, 0.45, 0), Vector3(w, 0.05, 0.38), WOOD)
			for sx in [-1.0, 1.0]:
				_pb(p, Vector3(sx * (w * 0.5 - 0.08), 0.22, 0), Vector3(0.05, 0.44, 0.34), DARK)
		"chest":
			_pb(p, Vector3(0, 0.18, 0), Vector3(w, 0.36, dd), WOOD, "solid", true)
			_pb(p, Vector3(0, 0.43, 0), Vector3(w, 0.14, dd), DARK)
			_pb(p, Vector3(0, 0.3, dd * 0.5 + 0.01), Vector3(0.08, 0.14, 0.02), Color(0.7, 0.6, 0.25))
		"cupboard":
			_pb(p, Vector3(0, 0.8, 0), Vector3(w, 1.6, dd), WOOD, "solid", true)
			for sx in [-1.0, 1.0]:
				_pb(p, Vector3(sx * w * 0.24, 0.85, dd * 0.5 + 0.01), Vector3(w * 0.42, 1.35, 0.03), DARK)
		"barrel":
			_pb(p, Vector3(0, 0.4, 0), Vector3(0.5, 0.8, 0.5), WOOD, "solid", true)
			kit.box(_world_centre(p, Vector3(0, 0.4, 0)), Vector3(0.5, 0.8, 0.5), WOOD, "solid", deg_to_rad(float(p.get("y", 0.0))) + PI * 0.25)
			_pb(p, Vector3(0, 0.55, 0), Vector3(0.58, 0.05, 0.58), DARK)
		"crate":
			_pb(p, Vector3(0, 0.27, 0), Vector3(0.6, 0.54, 0.6), Color(0.5, 0.36, 0.2), "solid", true)
			_pb(p, Vector3(0, 0.27, 0), Vector3(0.64, 0.08, 0.64), DARK)
		"hearth", "oven":
			var hw2 := w
			var oven := t == "oven"
			_pb(p, Vector3(0, 0.5, 0), Vector3(hw2, 1.0, dd), STONE, "solid", true)
			_pb(p, Vector3(0, 0.38, dd * 0.5 + 0.005), Vector3(hw2 * 0.5, 0.52, 0.04), Color(0.05, 0.04, 0.04))
			_pb(p, Vector3(0, 0.3, dd * 0.5 + 0.03), Vector3(hw2 * 0.34, 0.26, 0.03), Color.WHITE, "fire")
			_pb(p, Vector3(0, 1.05, 0.05), Vector3(hw2 + 0.15, 0.1, dd + 0.1), DARK)
			_pb(p, Vector3(0, 1.9 if not oven else 1.7, -dd * 0.15), Vector3(hw2 * 0.6, 1.8, dd * 0.55), STONE)
			if oven:
				_pb(p, Vector3(0, 1.25, 0), Vector3(hw2 * 0.8, 0.4, dd * 0.8), Color(0.55, 0.5, 0.44))
		"shelf":
			var back := Vector3(0, 0.9, -0.12)
			_pb(p, back, Vector3(w, 1.8, 0.04), DARK)
			for sy in [0.5, 1.0, 1.5]:
				_pb(p, Vector3(0, sy, 0), Vector3(w, 0.04, 0.28), WOOD)
			for sx in [-1.0, 1.0]:
				_pb(p, Vector3(sx * (w * 0.5 - 0.02), 0.9, 0), Vector3(0.04, 1.8, 0.28), WOOD)
			var n := int(w * 4.0)
			for i in n:
				var col: Color = CLOTHS[(i + int(absf((p["p"] as Vector2).x * 3.0))) % CLOTHS.size()]
				var x := -w * 0.5 + 0.12 + (w - 0.24) * float(i) / float(maxi(n - 1, 1))
				_pb(p, Vector3(x, 0.5 + 0.5 * float(i % 3) + 0.1, 0.0), Vector3(0.14, 0.18, 0.14), col)
			kit.collider(_world_centre(p, Vector3(0, 0.9, 0)), Vector3(w, 1.8, 0.3), deg_to_rad(float(p.get("y", 0.0))))
		"counter", "bar":
			_pb(p, Vector3(0, 0.48, 0), Vector3(w, 0.96, dd), WOOD, "solid", true)
			_pb(p, Vector3(0, 0.99, 0.03), Vector3(w + 0.1, 0.06, dd + 0.12), Color(0.55, 0.4, 0.24))
			if t == "bar":
				_pb(p, Vector3(0, 0.15, dd * 0.5 + 0.1), Vector3(w, 0.05, 0.05), Color(0.6, 0.5, 0.2))
		"workbench":
			_pb(p, Vector3(0, 0.88, 0), Vector3(w, 0.08, dd), WOOD)
			for sx in [-1.0, 1.0]:
				_pb(p, Vector3(sx * (w * 0.5 - 0.1), 0.42, 0), Vector3(0.08, 0.84, dd - 0.1), DARK)
			_pb(p, Vector3(-w * 0.35, 1.0, 0.1), Vector3(0.16, 0.18, 0.2), Color(0.3, 0.3, 0.32))
			_pb(p, Vector3(w * 0.1, 0.96, -0.1), Vector3(0.5, 0.06, 0.14), Color(0.5, 0.36, 0.2))
			kit.collider(_world_centre(p, Vector3(0, 0.5, 0)), Vector3(w, 1.0, dd), deg_to_rad(float(p.get("y", 0.0))))
		"form":
			_pb(p, Vector3(0, 0.04, 0), Vector3(0.4, 0.04, 0.4), DARK)
			_pb(p, Vector3(0, 0.6, 0), Vector3(0.06, 1.2, 0.06), DARK)
			_pb(p, Vector3(0, 1.25, 0), Vector3(0.34, 0.5, 0.2), _cloth(p, 1))
			kit.collider(_world_centre(p, Vector3(0, 0.7, 0)), Vector3(0.45, 1.4, 0.45))
		"loom":
			for sx in [-1.0, 1.0]:
				_pb(p, Vector3(sx * 0.5, 0.75, 0), Vector3(0.1, 1.5, 0.6), WOOD)
			_pb(p, Vector3(0, 1.45, 0), Vector3(1.1, 0.1, 0.6), WOOD)
			_pb(p, Vector3(0, 0.8, 0.05), Vector3(0.9, 0.9, 0.02), _cloth(p, 2))
			kit.collider(_world_centre(p, Vector3(0, 0.75, 0)), Vector3(1.1, 1.5, 0.8), deg_to_rad(float(p.get("y", 0.0))))
		"rack":
			_pb(p, Vector3(0, 1.2, 0), Vector3(w, 0.9, 0.05), DARK)
			for i in 4:
				_pb(p, Vector3(-0.45 + 0.3 * float(i), 1.2, 0.07), Vector3(0.05, 0.6, 0.05), Color(0.5, 0.5, 0.52))
		"rug":
			_pb(p, Vector3(0, 0.012, 0), Vector3(w, 0.024, dd), Color(0.5, 0.2, 0.17))
			_pb(p, Vector3(0, 0.026, 0), Vector3(w * 0.8, 0.012, dd * 0.75), Color(0.66, 0.5, 0.28))
		"lamp":
			var top := float(layout["h"]) if not (layout["loft"] as Dictionary).is_empty() else Layouts.CEIL
			var pos2: Vector2 = p["p"]
			kit.box(Vector3(pos2.x, top - 0.25, pos2.y), Vector3(0.012, 0.5, 0.012), DARK)
			# A lantern, not a glowing slab: dark iron caps and posts around a small amber core.
			var ly := top - 0.55
			kit.box(Vector3(pos2.x, ly + 0.13, pos2.y), Vector3(0.24, 0.03, 0.24), DARK)
			kit.box(Vector3(pos2.x, ly - 0.13, pos2.y), Vector3(0.22, 0.03, 0.22), DARK)
			for cx: float in [-0.095, 0.095]:
				for cz: float in [-0.095, 0.095]:
					kit.box(Vector3(pos2.x + cx, ly, pos2.y + cz), Vector3(0.025, 0.24, 0.025), DARK)
			kit.box(Vector3(pos2.x, ly, pos2.y), Vector3(0.11, 0.16, 0.11), Color(1.0, 0.74, 0.38), "lamp")
			p["_top"] = top


func _world_centre(p: Dictionary, local: Vector3) -> Vector3:
	var pos: Vector2 = p["p"]
	var yaw := deg_to_rad(float(p.get("y", 0.0)))
	var base_y := float((layout["loft"] as Dictionary).get("y", 0.0)) if int(p.get("level", 0)) > 0 else 0.0
	return Vector3(pos.x, base_y, pos.y) + Basis(Vector3.UP, yaw) * local


# ------------------------------------------------------------------ markers, lights, environment
func _build_markers() -> void:
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	add_child(spawn)
	spawn.position = Layouts.spawn_point(layout)
	var box := Layouts.exit_box(layout)
	exit_door = InteriorDoor.new()
	exit_door.name = "ExitDoor"
	exit_door.is_exit = true
	exit_door.prompt_text = "Leave"
	exit_door.collision_layer = 0
	exit_door.collision_mask = 1 | InteriorDoor.PLAYER_TRIGGER_LAYER
	exit_door.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	cs.shape = bs
	cs.position.y = box.size.y * 0.5
	exit_door.add_child(cs)
	add_child(exit_door)
	exit_door.position = Vector3(box.position.x + box.size.x * 0.5, 0.0, box.position.z + box.size.z * 0.5)
	var npcs := Node3D.new()
	npcs.name = "NPCs"
	add_child(npcs)
	for n: Dictionary in layout["npcs"]:
		var m := Marker3D.new()
		m.name = "NPC_" + String(n["role"]).capitalize()
		m.set_meta("role", String(n["role"]))
		m.set_meta("look", String(n["look"]))
		m.set_meta("height", 1.75)
		m.set_meta("anim", "Idle")
		npcs.add_child(m)
		var p: Vector2 = n["p"]
		m.position = Vector3(p.x, 0.0, p.y)
		# markers face -Z; the character model gets turned PI by InteriorRoom._spawn_npcs
		m.rotation.y = deg_to_rad(float(n["y"]))
	# a free corner for the HomeChest of a player-owned house (village_services._furnish_home)
	for p: Dictionary in layout["props"]:
		if String(p["t"]) == "chest" and int(p.get("level", 0)) == 0:
			var sm := Marker3D.new()
			sm.name = "StorageMarker"
			add_child(sm)
			var pp: Vector2 = p["p"]
			sm.position = Vector3(pp.x, 0.0, pp.y)
			break


func _build_lights() -> void:
	var w := float(layout["w"])
	var d := float(layout["d"])
	_room_light = OmniLight3D.new()
	_room_light.name = "RoomLight"
	_room_light.shadow_enabled = false
	_room_light.omni_range = maxf(w, d) * 0.95
	_room_light.position = Vector3(0, Layouts.CEIL - 0.5, 0)
	add_child(_room_light)
	var hp := Vector3(0, 1.0, 0)
	for p: Dictionary in layout["props"]:
		var t := String(p["t"])
		if t == "hearth" or t == "oven":
			var pos: Vector2 = p["p"]
			var fr := Layouts.front(float(p.get("y", 0.0)), 0.9)
			hp = Vector3(pos.x + fr.x, 0.8, pos.y + fr.y)
			furniture["hearths"].append(hp)
			break
	_hearth_light = OmniLight3D.new()
	_hearth_light.name = "HearthLight"
	_hearth_light.shadow_enabled = int(Quality.tier) >= 1        # soft firelight shadows (MEDIUM+)
	_hearth_light.shadow_blur = 2.5
	_hearth_light.shadow_bias = 0.06
	_hearth_light.light_color = Color(1.0, 0.58, 0.28)
	_hearth_light.omni_range = 9.0
	_hearth_light.omni_attenuation = 1.35        # warm pool round the fire that falls off instead of a hard disc
	_hearth_light.position = hp
	add_child(_hearth_light)
	_hearth_phase = randf() * TAU
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Light.BACKDROP_NIGHT     # the cut-away room floats in a warm dark tone, not a black void (apply_hour tints it)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(1, 0.9, 0.78)
	_env.ambient_light_energy = 0.6
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.15
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	add_child(we)
	if bool(get_meta("embedded", false)):
		return       # in the game the player's chase camera drives (a fixed preview camera over the door hid the player)
	var cam := Camera3D.new()
	cam.name = "PreviewCamera"
	add_child(cam)
	cam.position = Vector3(0, float(layout["h"]) - 0.4, d * 0.5 - 0.3)
	cam.look_at_from_position(cam.position, Vector3(0, 0.8, -d * 0.2))
	cam.current = true


# ------------------------------------------------------------------ light by hour
func apply_hour(hour: float) -> void:
	if layout.is_empty():
		return
	_last_hour = hour
	var s := Light.state(hour, layout_id)
	var mats: Dictionary = kit.materials if kit != null else {}
	if mats.has("glass"):
		var gm: StandardMaterial3D = mats["glass"]
		var wc: Color = s["window_color"]
		gm.emission = wc
		gm.emission_energy_multiplier = float(s["window_energy"])
		# Unshaded glass shows its albedo too: dark navy at night, pale sky by day (it used to be white either way).
		gm.albedo_color = Light.NIGHT_GLASS.lerp(Light.DAY_GLASS, float(s["daylight"]))
		if not CityPlanner.towns_off():      # horn panes: warm translucent amber by day, near black by night
			gm.albedo_color = Color(0.07, 0.05, 0.035).lerp(Color(0.86, 0.72, 0.5), float(s["daylight"]))
			gm.emission = wc * Color(1.0, 0.86, 0.62)
			gm.emission_energy_multiplier = float(s["window_energy"]) * 0.35     # horn glows, it does not blaze
	if mats.has("fire"):
		(mats["fire"] as StandardMaterial3D).emission_energy_multiplier = float(s["fire_glow"])
	if mats.has("lamp"):
		(mats["lamp"] as StandardMaterial3D).emission_energy_multiplier = 1.8 if bool(s["lamp_on"]) else 0.05
	var dl_e := float(s["day_light_energy"])
	var lamp_e := float(s["lamp_energy"])
	var tot := dl_e + lamp_e
	_room_light.light_energy = tot
	_room_light.visible = tot > 0.02
	if tot > 0.0:
		_room_light.light_color = (s["window_color"] as Color).lerp(Color(1.0, 0.82, 0.55), lamp_e / tot)
	_night_k = 1.0 - float(s["daylight"])
	_hearth_base = Light.HEARTH_LIGHT * float(s["hearth_energy"])
	var dim := not CityPlanner.towns_off()      # interior pass 2: dim, firelit rooms (KCD), darker and warmer than outside
	if dim:
		_hearth_base = maxf(_hearth_base * 1.6, Light.HEARTH_LIGHT * 0.45)     # embers glow even when the fire is banked
		_room_light.light_energy = tot * 0.55
	_hearth_light.light_energy = _hearth_base
	_hearth_light.visible = _hearth_base > 0.02
	if _shaft != null:
		_shaft.light_energy = 3.0 * float(s["daylight"])
		_shaft.visible = float(s["daylight"]) > 0.05
	if _env != null:
		_env.ambient_light_color = s["ambient_color"]
		_env.ambient_light_energy = maxf(Light.NIGHT_FLOOR, float(s["ambient_energy"]) * 0.6) if dim else float(s["ambient_energy"])
		_env.background_color = Light.BACKDROP_NIGHT.lerp(Light.BACKDROP_DAY, float(s["daylight"]))


## What the light driver last applied, for tests and tools: {room_energy, hearth_energy, ambient_energy, window_energy}.
func light_report() -> Dictionary:
	var gm: StandardMaterial3D = (kit.materials as Dictionary).get("glass", null)
	return {"room_energy": _room_light.light_energy if _room_light.visible else 0.0,
		"hearth_energy": _hearth_light.light_energy if _hearth_light.visible else 0.0,
		"ambient_energy": _env.ambient_light_energy if _env != null else 0.0,
		"window_energy": gm.emission_energy_multiplier if gm != null else 0.0,
		"window_color": gm.emission if gm != null else Color.BLACK}


## Pure: which groups should be hidden for a camera at `cam` (room-local coordinates) in a w x d x h room.
static func wall_fade_targets(cam: Vector3, w: float, d: float, h: float) -> Dictionary:
	var m := WALL_FADE_MARGIN
	return {
		"wN": 1.0 if cam.z < -d * 0.5 + m else 0.0,
		"wS": 1.0 if cam.z > d * 0.5 - m else 0.0,
		"wE": 1.0 if cam.x > w * 0.5 - m else 0.0,
		"wW": 1.0 if cam.x < -w * 0.5 + m else 0.0,
		"ceil": 1.0 if cam.y > h - 0.3 else 0.0,
	}


## Eases each group toward its target and applies it (instance transparency; hidden when fully faded). Colliders stay.
func _fade_walls(delta: float, cam_local: Vector3) -> void:
	var targets := wall_fade_targets(cam_local, float(layout["w"]), float(layout["d"]), float(layout["h"]))
	for g: String in _group_nodes:
		var cur := move_toward(float(_group_fade[g]), float(targets.get(g, 0.0)), delta * WALL_FADE_RATE)
		if is_equal_approx(cur, float(_group_fade[g])):
			continue
		_group_fade[g] = cur
		for mi: GeometryInstance3D in _group_nodes[g]:
			mi.transparency = cur
			mi.visible = cur < 0.98


func wall_fade_state() -> Dictionary:
	return _group_fade.duplicate()


func _process(delta: float) -> void:
	_clock += delta
	if not _group_nodes.is_empty():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_fade_walls(delta, to_local(cam.global_position))
			if _night_k > 0.01 and _room_light != null:
				# Night: the lamp light rides between the lens and the player (a lantern at hand) instead of hanging in the
				# ceiling centre, so the player and the household in view are lit from the camera's side. Same one light.
				var who := get_tree().get_first_node_in_group("player") as Node3D
				var focus := who.global_position + Vector3(0, 1.4, 0) if who != null else cam.global_position
				var ride := to_local(cam.global_position.lerp(focus, 0.45) + Vector3(0, 0.5, 0))
				var hang := Vector3(0, Layouts.CEIL - 0.5, 0)
				_room_light.position = hang.lerp(ride, _night_k)
	if _hearth_light != null and _hearth_light.visible:
		_hearth_light.light_energy = _hearth_base * (1.0 + 0.08 * sin(_clock * 7.1 + _hearth_phase) + 0.05 * sin(_clock * 12.9))
	_flick += delta
	if _flick >= 1.0:
		_flick = 0.0
		var h := WorldSim.time_of_day
		if absf(h - _last_hour) > 0.02:
			apply_hour(h)
		if live_roster and _furnished and floorf(h * 2.0) != floorf(_last_roster_hour * 2.0):
			sync_roster(h, false)


# ------------------------------------------------------------------ furniture (interactables)
## Places every interactable. `bid` is the stable building id (container and bed ids derive from it), `owner` the
## owner string every owned thing gets ("household:..", "shop:..", "player", or "" for public).
func build_furniture(bid: String, owner: String) -> void:
	if _furnished or layout.is_empty():
		return
	_furnished = true
	building_id = bid
	building_owner = owner
	var root := Node3D.new()
	root.name = "Furniture"
	add_child(root)
	var n_bed := 0
	var n_cont := 0
	for p: Dictionary in layout["props"]:
		var t := String(p["t"])
		var pos: Vector2 = p["p"]
		var yaw := float(p.get("y", 0.0))
		var base_y := float((layout["loft"] as Dictionary).get("y", 0.0)) if int(p.get("level", 0)) > 0 else 0.0
		var gpos := to_global(Vector3(pos.x, base_y, pos.y))
		var gyaw := global_rotation.y + deg_to_rad(yaw)
		match t:
			"bed", "cot":
				var b := BedProp.spawn(root, gpos + Vector3(0, 0.45, 0), "%s/%d" % [bid, n_bed], owner)
				furniture["beds"].append(b)
				n_bed += 1
			"chair", "stool", "bench":
				var s: Node3D = Seat_.spawn(root, gpos, gyaw, "bench" if t == "bench" else "chair", false)
				furniture["seats"].append(s)
			"chest", "cupboard", "barrel", "crate":
				if owner == Ownership_.PLAYER and String(p.get("slot", "")) in ["chest", "loft_chest"]:
					continue     # the HomeChest of your own house stands here instead
				var slot := String(p.get("slot", "%s%d" % [t, n_cont]))
				var c: Node3D = Container_.spawn(root, gpos, "%s/%s" % [bid, slot], _container_title(t, slot), [], "", owner, false)
				c.add_to_group("interior_container")
				furniture["containers"].append(c)
				n_cont += 1
	if not (layout["loft"] as Dictionary).is_empty():
		var lf: Dictionary = layout["loft"]
		var lad: Node3D = Ladder.spawn(root, to_global(lf["ladder_bottom"]), to_global(lf["ladder_top"]))
		furniture["ladders"].append(lad)
	_build_hearth_use(root)
	_build_counter_station(root)
	if owner != "":
		set_meta("building_owner", owner)


func _container_title(t: String, slot: String) -> String:
	match t:
		"chest": return "Chest"
		"cupboard": return "Cupboard"
		"barrel": return "Ale barrel" if slot.begins_with("ale") else "Barrel"
	return "Crate"


func _build_hearth_use(root: Node3D) -> void:
	for hp: Vector3 in furniture["hearths"]:
		var n := Node3D.new()
		n.name = "HearthUse"
		root.add_child(n)
		n.global_position = to_global(hp)
		Interactable.attach(n, {"id_fn": func() -> String: return "hearth/%s" % building_id, "verb": "Warm up", "target": "Hearth", "range": 2.6,
			"can": func(_p: Node) -> bool: return _hearth_light != null and _hearth_light.visible,
			"do": func(_p: Node) -> void:
				var g := get_node_or_null("/root/Game")
				if g != null and g.has_method("say"):
					g.call("say", "You warm your hands at the fire.")})
		break


## Shops: a Station at the counter marker that opens the shop screen for the layout's shop_kind (closed outside hours).
func _build_counter_station(root: Node3D) -> void:
	var kind := String(layout["shop_kind"])
	if String(layout["category"]) != "shop" or kind == "":
		return
	for m in find_children("NPC_Merchant", "Marker3D", true, false):
		var title := String(layout["title"])
		var menu := func() -> Dictionary:
			var refusal := ShopHours_.refusal(kind)
			if refusal != "":
				return {"title": title, "body": "\"%s\"\n(%s)" % [refusal, ShopHours_.hours_text(kind)], "options": []}
			var hud := Interaction.hud(self)
			return {"title": title, "body": "\"Have a look, nothing here is stolen.\"",
				"options": [ShopScreen_.menu_option(hud, kind, Life.market, 1, "Browse wares", title)]}
		var st := Station.new("Shopkeeper", "Shop", menu)
		st.hours_kind = kind
		st.name = "Service_Merchant"
		st.add_to_group("shop_counter")
		root.add_child(st)
		st.global_position = (m as Marker3D).global_position
		furniture["stations"].append(st)


## The interactive node count by kind, for tests: {beds, seats, containers, ladders, stations}.
func furniture_counts() -> Dictionary:
	return {"beds": furniture["beds"].size(), "seats": furniture["seats"].size(), "containers": furniture["containers"].size(),
		"ladders": furniture["ladders"].size(), "stations": furniture["stations"].size()}


# ------------------------------------------------------------------ people inside
var _last_roster_hour := -10.0


func _spawn_npcs() -> void:
	# The proprietor stands behind the counter unless a real household member works it right now.
	_suppress_merchant = live_roster and _counter_worker_present()
	super()


var _suppress_merchant := false


## Markers the base class spawns static characters for (the merchant is left out when a real person works the counter).
func npc_markers() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for m in super():
		if _suppress_merchant and String(m.get_meta("role", "")) == "merchant":
			continue
		out.append(m)
	return out


func _counter_worker_present() -> bool:
	var info := _lot_info()
	if info.is_empty():
		return false
	for e: Dictionary in Household.roster_for_lot(info, WorldSim.time_of_day, String(layout["category"])):
		if String(e["act"]) == "counter":
			return true
	return false


func _lot_info() -> Dictionary:
	var door := InteriorDoor.active
	if door != null and door.has_meta("lot_pos"):
		var lp: Variant = door.get_meta("lot_pos")
		if lp is Vector2:
			return Household.lot_at(lp)
	return {}


## Desired bodies for `hour`: [{person, act, role, wp}], placed on distinct waypoints.
func desired_roster(hour: float, info := {}) -> Array[Dictionary]:
	var li: Dictionary = info if not info.is_empty() else _lot_info()
	var raw := Household.roster_for_lot(li, hour, String(layout["category"]))
	return Household.place(raw, layout["waypoints"])


## Brings the bodies in line with the schedule at `hour`. People who are no longer here walk to the door and leave,
## new ones come in through it and walk to their spot, changed acts walk to the new spot. `instant` places bodies
## without walking (when the player first enters).
func sync_roster(hour: float, instant := false, info := {}) -> void:
	_last_roster_hour = hour
	var want := desired_roster(hour, info)
	var by_person := {}
	for e: Dictionary in want:
		by_person[int(e["person"])] = e
	var door_at := Layouts.spawn_point(layout) + Vector3(0, 0, 0.9)
	for person: int in bodies.keys():
		if not by_person.has(person):
			var b: Node3D = bodies[person]
			bodies.erase(person)
			if is_instance_valid(b):
				_walk_out(b, door_at, instant)
	for e: Dictionary in want:
		var person := int(e["person"])
		var wp: Dictionary = e["wp"]
		var act := String(e["act"])
		if bodies.has(person):
			var cur: Node3D = bodies[person]
			if is_instance_valid(cur) and String(cur.get_meta("act", "")) != act:
				_walk_to(cur, act, wp, false)
			continue
		var body := IndoorActor.make(person)
		if body == null:
			continue
		add_child(body)
		bodies[person] = body
		if instant:
			IndoorActor.pose(self, body, act, wp)
		else:
			body.position = door_at
			_walk_to(body, act, wp, true)


func _walk_to(body: Node3D, act: String, wp: Dictionary, entering: bool) -> void:
	# A sleeper in a kit bed gets up first (Life_Mz_Wake_Bed), then walks.
	if bool(body.get_meta("in_bed", false)):
		body.set_meta("in_bed", false)
		var ap := Assets.animation_player(body)
		if ap != null and ap.has_animation(IndoorActor.BED_WAKE):
			ap.play(IndoorActor.BED_WAKE, 0.2)
			body.set_meta("act", act)
			get_tree().create_timer(ap.get_animation(IndoorActor.BED_WAKE).length).timeout.connect(func() -> void:
				if is_instance_valid(body) and String(body.get_meta("act", "")) == act:
					_walk_to(body, act, wp, entering))
			return
	body.set_meta("act", act)
	var dest: Vector3 = wp["p"]
	var dist := body.position.distance_to(dest)
	var secs := maxf(dist / Household.WALK, 0.1)
	IndoorActor.play(body, IndoorActor.CLIPS["walk"])
	if dist > 0.05:
		body.rotation.y = atan2(dest.x - body.position.x, dest.z - body.position.z)
	var tw := body.create_tween()
	tw.tween_property(body, "position", dest, secs)
	tw.finished.connect(func() -> void:
		if is_instance_valid(body):
			IndoorActor.pose(self, body, act, wp))


func _walk_out(body: Node3D, door_at: Vector3, instant: bool) -> void:
	if instant:
		body.queue_free()
		return
	body.remove_from_group("interior_npc")
	IndoorActor.play(body, IndoorActor.CLIPS["walk"])
	body.rotation.y = atan2(door_at.x - body.position.x, door_at.z - body.position.z)
	var tw := body.create_tween()
	tw.tween_property(body, "position", door_at, maxf(body.position.distance_to(door_at) / Household.WALK, 0.1))
	tw.finished.connect(func() -> void:
		if is_instance_valid(body):
			body.queue_free())


# ------------------------------------------------------------------ budget report
## Draw-call estimate: visible mesh surfaces in the room shell and furniture (bodies counted separately).
func draw_estimate() -> Dictionary:
	var shell := 0
	var people := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var surfaces := m.mesh.get_surface_count()
		var on_body := false
		var up := m.get_parent()
		while up != null and up != self:
			if up.is_in_group("interior_npc"):
				on_body = true
				break
			up = up.get_parent()
		if on_body:
			people += surfaces
		else:
			shell += surfaces
		if OS.has_environment("DRAWS_DEBUG") and not on_body:
			print("DRAW mi ", m.name, " ", m.get_parent().name, " ", m.mesh.resource_name, " ", surfaces)
	for mmi in find_children("*", "MultiMeshInstance3D", true, false):      # batched kit pieces and clutter: one draw per surface
		var mm := (mmi as MultiMeshInstance3D).multimesh
		if (mmi as Node3D).is_visible_in_tree() and mm != null and mm.mesh != null:
			shell += mm.mesh.get_surface_count()
			if OS.has_environment("DRAWS_DEBUG"):
				print("DRAW mm ", mm.mesh.resource_name, " ", mm.mesh.get_surface_count(), " x", mm.instance_count)
	return {"shell": shell, "people": people, "lights": int(_room_light.visible) + int(_hearth_light.visible)}
