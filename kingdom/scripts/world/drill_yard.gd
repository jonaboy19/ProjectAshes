extends Node3D
## The village drill yard (ACADEMY_PLAN "Everyone learns to fight"): a patch of trampled ground
## off Ashford's plaza with straw dummies, a weapon rack and hay-bale targets. Anyone, in any
## career, can train here: the Station lists education.training_options() and train() spends
## the hours (WorldSim.advance_hours) and shows the gain.
##
## Cost model: the spot is found once (data, no random draws); the props are a handful of
## MeshInstance3Ds sharing merged meshes with visibility ranges, built only while the player is
## within BUILD metres and freed past FREE. No _process: the owner (realm_encounters.gd) calls
## refresh() from its 2 s timer.

const REGION := "res://assets/generated/region/"
const GEN := "res://assets/generated/"
const BUILD := 170.0
const FREE := 240.0
const CULL := 140.0
const HOURS := [1, 2, 4, 8]

var hud: Node
var encounters: Node          ## realm_encounters.gd: hints
var settlement := 0
var spot := Vector2.INF       ## world XZ of the yard centre (INF = no room found)
var yaw := 0.0                ## the dummies' row faces this way (toward the plaza)
var _root: Node3D
var _hours_idx := 1


func setup(p_hud: Node, p_encounters: Node, sid := 0) -> void:
	hud = p_hud
	encounters = p_encounters
	settlement = sid
	name = "DrillYard"
	if sid >= 0 and sid < WorldGen.settlements.size():
		var found := find_spot(WorldGen.settlements[sid])
		if not found.is_empty():
			spot = found["pos"]
			yaw = float(found["yaw"])


## Free trampled ground nearest the plaza: clear of streets, lots,
## landmarks, water and slopes. Deterministic; nearest the plaza wins.
static func find_spot(s: Dictionary) -> Dictionary:
	var plan: Dictionary = s["plan"]
	var c: Vector2 = s["pos"]
	var pr := float(plan["plaza_r"])
	var rmax := float(s["radius"]) * 1.3      # a village is packed: the yard ends up on its outer edge
	var ring := pr + 8.0
	while ring <= rmax:
		var n := maxi(24, int(TAU * ring / 4.0))
		for i in n:
			var a := TAU * i / n
			var q := c + Vector2(cos(a), sin(a)) * ring
			if _clear(plan, q):
				return {"pos": q, "yaw": atan2(c.x - q.x, c.y - q.y)}
		ring += 2.0
	return {}


static func _clear(plan: Dictionary, q: Vector2) -> bool:
	if WorldGen.near_water(q.x, q.y, 6.0):
		return false
	if CityPlanner.street_distance(plan, q) < 8.0:
		return false
	for lot: Dictionary in plan["lots"]:
		if q.distance_to(lot["pos"]) < 14.5:
			return false
	for lm: Dictionary in plan["landmarks"]:
		if q.distance_to(lm["pos"]) < 17.0:
			return false
	var e := 3.0
	var dx := WorldGen.height(q.x + e, q.y) - WorldGen.height(q.x - e, q.y)
	var dz := WorldGen.height(q.x, q.y + e) - WorldGen.height(q.x, q.y - e)
	return Vector2(dx, dz).length() / (2.0 * e) < 0.2


## Called from the owner's 2 s timer with the player's XZ position.
func refresh(player_xz: Vector2) -> void:
	if spot == Vector2.INF:
		return
	var d := player_xz.distance_to(spot)
	if _root == null and d < BUILD:
		_build()
	elif _root != null and d > FREE:
		_root.queue_free()
		_root = null


func is_built() -> bool:
	return _root != null and is_instance_valid(_root)


func build_now() -> void:
	if spot != Vector2.INF and not is_built():
		_build()


func _mesh(path: String) -> Mesh:
	return Assets.merged_mesh(path)


func _prop(mesh: Mesh, local: Vector2, ry: float, sc := 1.0, shadow := true) -> Node3D:
	if mesh == null:
		return null
	var basis := Basis(Vector3.UP, yaw)
	var off := basis * Vector3(local.x, 0.0, local.y)
	var x := spot.x + off.x
	var z := spot.y + off.z
	# Settle on the lowest ground under the footprint so nothing floats on the slope.
	var box := mesh.get_aabb()
	var ext := maxf(box.size.x, box.size.z) * 0.5 * sc
	var low := WorldGen.height(x, z)
	for k in 4:
		var a := TAU * k / 4.0 + yaw + ry
		low = minf(low, WorldGen.height(x + cos(a) * ext, z + sin(a) * ext))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.visibility_range_end = CULL
	mi.visibility_range_end_margin = 8.0
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw + ry).scaled(Vector3.ONE * sc), Vector3(x, low - 0.06, z))
	return mi


func _solid(at: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(cs)
	at.add_child(body)


func _build() -> void:
	_root = Node3D.new()
	_root.name = "DrillYardProps"
	add_child(_root)
	var dummy := _mesh(REGION + "farm/scarecrow.glb")
	var rack := _mesh(GEN + "props/weapon_rack.glb")
	var hay := _mesh(GEN + "props/hay_bales.glb")
	var trough := _mesh(GEN + "props/water_trough.glb")
	# Three straw dummies in a row facing the trainee, a rack and hay targets beside them.
	for i in 3:
		var d := _prop(dummy, Vector2(-3.0 + i * 3.0, 3.2), PI, 1.05)
		if d != null:
			_solid(d, Vector3(0.7, 2.0, 0.7))
	var r1 := _prop(rack, Vector2(-5.6, 0.2), PI * 0.5)
	if r1 != null:
		_solid(r1, Vector3(1.0, 1.4, 2.2))
	var h1 := _prop(hay, Vector2(5.6, 1.4), -0.4)
	if h1 != null:
		_solid(h1, Vector3(2.0, 1.2, 1.8))
	var t1 := _prop(trough, Vector2(5.4, -1.6), PI * 0.5)
	if t1 != null:
		_solid(t1, Vector3(0.9, 0.6, 2.2))
	# The interaction point, in the middle of the practice line.
	var st := Station.new("Village Drill Yard", "Train", menu)
	st.name = "DrillStation"
	_root.add_child(st)
	var sp := spot + Vector2(sin(yaw), cos(yaw)) * 0.5
	st.global_position = Vector3(sp.x, WorldGen.height(sp.x, sp.y), sp.y)


# --- the menu ---------------------------------------------------------------------------

func _ctx() -> Dictionary:
	var ctx := {"life": Life}
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		ctx["player_pos"] = pl.global_position
	var war: Variant = Life.get("war")
	if war != null and war.has_method("is_at_war"):
		ctx["at_war"] = war.is_at_war()
	return ctx


func _edu() -> Variant:
	var hub: Variant = Life.get("realm")
	return hub.mod("education") if hub != null else null


func menu() -> Dictionary:
	var edu: Variant = _edu()
	if edu == null:
		return {"title": "Drill Yard", "body": "Straw dummies and wooden blades.", "options": []}
	var hours := int(HOURS[_hours_idx])
	var opts: Array = []
	for o: Dictionary in edu.training_options(_ctx()):
		var ok := bool(o["available"])
		var cost := int(o["cost"]) * hours
		var label := "%s: %d h  (combat +%.2f%s)" % [o["label"], hours, float(o["gain"]["combat"]) * hours, ("  -%d g" % cost) if cost > 0 else ""]
		if not ok:
			label = "%s  (%s)" % [o["label"], o["reason"]]
		opts.append([label, _train.bind(String(o["id"]), hours), ok])
	opts.append(["Session length: %d h  (tap to change)" % hours, _cycle_hours])
	var ability := int(round(float(edu.fighting_ability())))
	return {"title": "Village Drill Yard",
		"body": "Wooden blades, straw dummies and a rack of practice weapons. Anyone may train here, whatever their trade. Combat skill: %d." % ability,
		"options": opts}


func _cycle_hours() -> String:
	_hours_idx = (_hours_idx + 1) % HOURS.size()
	return ""


func _train(option_id: String, hours: int) -> String:
	var edu: Variant = _edu()
	if edu == null:
		return ""
	var res: Dictionary = edu.train(option_id, hours, _ctx())
	if not bool(res.get("ok", false)):
		return String(res.get("reason", "You cannot train now."))
	WorldSim.advance_hours(float(hours))    # the hours pass; Life folds the gain into swordsmanship
	var gain := float(res["gain"]["combat"])
	var msg := "You drill for %d hours. Combat +%.2f (skill %d)." % [hours, gain, int(round(float(edu.fighting_ability())))]
	if hud != null and hud.has_method("notify"):
		hud.notify("info", "Training", "Combat +%.2f" % gain)
	if encounters != null and encounters.has_method("hint"):
		encounters.hint("first_training")
	return msg
