extends Node3D
## Runtime of one built dungeon instance (created by dungeon_build.gd, freed when the player leaves).
## Owns: gate state, the flow field creatures follow, the light the player carries, flicker, the
## distance-based sleep of creatures, looted/harvested/killed bookkeeping (written straight into
## `state`, a plain Dictionary owned by the exploration realm module, so saving is automatic) and the
## boss reward.

signal gate_opened(gate_id: int, how: String)
signal lead_revealed(lead_id: String)
signal boss_defeated(boss: Dictionary)
signal cleared

const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const Items := preload("res://scripts/interiors/dungeon_items.gd")
const ACTIVE_RANGE := 34.0
const SHOW_RANGE := 48.0

var g: Dictionary = {}
var state: Dictionary = {}
var floor_y := 0.0
var things: Dictionary = {}          # id -> dungeon_thing.gd
var gates: Dictionary = {}           # gate id -> Node3D (door / rockfall)
var creatures: Array = []
var flicker: Array = []              # [OmniLight3D, base energy, phase]
var carried: OmniLight3D = null
var _flow := PackedInt32Array()
var _flow_origin := Vector2i(-1, -1)
var _t := 0.0
var _slow := 0.0
var _player: Node3D = null
var _boss_pos := Vector3.ZERO
var day := 1


func _ready() -> void:
	floor_y = global_position.y
	carried = OmniLight3D.new()
	carried.name = "CarriedLight"
	carried.shadow_enabled = false
	carried.light_color = Color(1.0, 0.78, 0.5)
	add_child(carried)
	refresh_light()
	set_process(true)


func refresh_light() -> void:
	if carried == null:
		return
	var life := get_node_or_null("/root/Life")
	var torch := life != null and int(life.call("count", "torch")) > 0
	var dark: bool = g.get("dark", true)
	if torch:
		carried.omni_range = 11.0
		carried.light_energy = 1.7
		carried.light_color = Color(1.0, 0.72, 0.42)
	elif dark:
		carried.omni_range = 6.5          # no torch: still enough to read the hero and the floor around him (a torch reaches 11 m)
		carried.light_energy = 1.4
		carried.light_color = Color(0.72, 0.74, 1.0)
	else:
		carried.omni_range = 6.5
		carried.light_energy = 0.9
		carried.light_color = Color(1.0, 0.85, 0.65)


func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null and carried != null:
		# a little toward the camera, so the hero's back (the side the player looks at) catches the light too
		var toward_cam := Vector3.ZERO
		var cam: Camera3D = _player.get("camera") as Camera3D if _player.get("camera") is Camera3D else null
		if cam != null:
			toward_cam = Vector3(cam.global_basis.z.x, 0.0, cam.global_basis.z.z).normalized() * 1.1
		carried.global_position = _player.global_position + Vector3(0, 1.7, 0) + toward_cam
	for f: Array in flicker:
		var l := f[0] as OmniLight3D
		if is_instance_valid(l):
			l.light_energy = float(f[1]) * (0.85 + 0.15 * sin(_t * 8.1 + float(f[2])) * sin(_t * 3.3 + float(f[2]) * 2.0))
	_slow -= delta
	if _slow > 0.0:
		return
	_slow = 0.4
	_update_flow()
	_update_creatures()


# --- state ------------------------------------------------------------------------------------

func mark_looted(id: String) -> void:
	state["looted"][id] = true


func mark_harvested(id: String) -> void:
	state["harvested"][id] = day


## Resource nodes are drawn by per-kind MultiMeshes; a harvested one shrinks to nothing.
var node_batches: Dictionary = {}     # kind -> {"mm": MultiMesh, "idx": {id: int}, "pos": {id: Vector3}}


func hide_node(id: String, kind: String) -> void:
	var b: Dictionary = node_batches.get(kind, {})
	if b.is_empty() or not (b["idx"] as Dictionary).has(id):
		return
	(b["mm"] as MultiMesh).set_instance_transform(int(b["idx"][id]), Transform3D(Basis().scaled(Vector3.ZERO), b["pos"][id]))


func mark_read(id: String) -> bool:
	var first: bool = not state["read"].has(id)
	state["read"][id] = true
	return first


func reveal_lead(lead_id: String) -> void:
	lead_revealed.emit(lead_id)


func is_open(gate_id: int) -> bool:
	return state["opened"].has(str(gate_id))


func open_gate(gate_id: int, how: String) -> void:
	state["opened"][str(gate_id)] = how
	var node: Node3D = gates.get(gate_id)
	if node != null and is_instance_valid(node):
		# disable collision at once, then sink / crumble the visual
		for c in node.find_children("*", "CollisionShape3D", true, false):
			(c as CollisionShape3D).set_deferred("disabled", true)
		var tw := create_tween()
		tw.tween_property(node, "position:y", node.position.y - 4.2, 1.1 if how != "collapse" else 0.8).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(node.queue_free)
	gate_opened.emit(gate_id, how)


# --- creatures --------------------------------------------------------------------------------

func register_creature(c: Node) -> void:
	creatures.append(c)
	c.connect("died", _on_creature_died)


func _on_creature_died(c: Node) -> void:
	var cid := String(c.get("cid"))
	state["killed"][cid] = true
	if bool(c.get("boss")):
		state["boss_dead"] = true
		_boss_pos = (c as Node3D).global_position
		var b: Dictionary = (g["content"] as Dictionary).get("boss", {})
		boss_defeated.emit(b)
		var game := get_node_or_null("/root/Game")
		if game != null:
			game.call("say", "%s is defeated. Something glints in the dust." % String(b.get("name", "The guardian")))
		spawn_boss_chest((c as Node3D).global_position)
		# the rest of the dungeon stirs: nothing is required, but the danger is over for now
	var alive := 0
	for cc in creatures:
		if is_instance_valid(cc) and not bool(cc.get("dead")) and not state["killed"].has(String(cc.get("cid"))):
			alive += 1
	if alive == 0 and not bool(state.get("cleared", false)):
		state["cleared"] = true
		cleared.emit()
		var game2 := get_node_or_null("/root/Game")
		if game2 != null:
			game2.call("say", "The dungeon falls quiet. Nothing here will trouble you now.")


func spawn_boss_chest(at: Vector3) -> void:
	var key := "boss_chest"
	if state["looted"].has(key) or things.has(key):
		return
	var boss: Dictionary = g["content"]["boss"]
	var t := preload("res://scripts/interiors/dungeon_thing.gd").new()
	add_child(t)
	t.setup("boss_chest", {"id": key, "loot": g["content"]["boss_loot"], "tier": int(boss["tier"]) + 1, "label": "Champion's chest",
		"trophy": String(boss["trophy"]), "vault": true}, self, String(g["theme"]))
	t.global_position = at + Vector3(0, 0.05, 0) + Vector3(1.6, 0, 0)
	things[key] = t


func on_boss_awake(_boss: Node) -> void:
	# nearby sleepers hear the roar
	for c in creatures:
		if is_instance_valid(c) and not bool(c.get("dead")) and (c as Node3D).global_position.distance_to((_boss as Node3D).global_position) < 18.0:
			c.call("alert")


## Flow field: steps from the player's cell over open cells, recomputed when the player changes cell.
func _update_flow() -> void:
	if _player == null:
		return
	var local := _player.global_position - global_position
	var cell := Gen.cell_at(g, local)
	if cell == _flow_origin:
		return
	_flow_origin = cell
	var side: int = g["w"]
	_flow.resize(side * side)
	_flow.fill(-1)
	if not Gen.is_open(g, cell):
		return
	var cells: PackedByteArray = g["cells"]
	var queue: Array[Vector2i] = [cell]
	_flow[cell.y * side + cell.x] = 0
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var dv := _flow[c.y * side + c.x]
		if dv >= 26:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= side or q.y >= side:
				continue
			var qi := q.y * side + q.x
			if _flow[qi] >= 0 or cells[qi] == Gen.ROCK:
				continue
			# sealed gates block the walk until opened
			if _blocked(q):
				continue
			_flow[qi] = dv + 1
			queue.append(q)


func _blocked(c: Vector2i) -> bool:
	for gt: Dictionary in g["gates"]:
		if gt["cell"] == c and not is_open(int(gt["id"])):
			return true
	return false


func flow_dir(world_pos: Vector3) -> Vector3:
	if _flow.is_empty():
		return Vector3.ZERO
	var side: int = g["w"]
	var cell := Gen.cell_at(g, world_pos - global_position)
	if cell.x < 0 or cell.y < 0 or cell.x >= side or cell.y >= side:
		return Vector3.ZERO
	var here := _flow[cell.y * side + cell.x]
	if here < 0:
		return Vector3.ZERO
	var best := here
	var best_c := cell
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var q: Vector2i = cell + d
		if q.x < 0 or q.y < 0 or q.x >= side or q.y >= side:
			continue
		var v := _flow[q.y * side + q.x]
		if v >= 0 and v < best:
			# diagonal steps must not clip a rock corner
			if d.x != 0 and d.y != 0 and (not Gen.is_open(g, Vector2i(cell.x + d.x, cell.y)) or not Gen.is_open(g, Vector2i(cell.x, cell.y + d.y))):
				continue
			best = v
			best_c = q
	if best_c == cell:
		return Vector3.ZERO
	var target := global_position + Gen.cell_pos(g, best_c)
	var dir := target - world_pos
	dir.y = 0.0
	return dir.normalized()


func _update_creatures() -> void:
	if _player == null:
		return
	for c in creatures:
		if not is_instance_valid(c):
			continue
		var d := (c as Node3D).global_position.distance_to(_player.global_position)
		var awake := d < ACTIVE_RANGE or (c.get("state") != null and int(c.get("state")) in [2, 3])
		var want := Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
		if c.process_mode != want:
			c.process_mode = want
		(c as Node3D).visible = d < SHOW_RANGE
