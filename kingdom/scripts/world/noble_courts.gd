extends Node3D
## Each noble house's head, standing at a manor door in their fief town or
## village, with a Station offering audience (petition, sponsorship, a lease,
## service, respects, buying a holding). Reuses the Station class the way
## village_services.gd does, but a court is only built near the player (a
## spawn ring, like scripts/world/region_dressing.gd): with houses' fiefs
## scattered across the whole map, keeping every court live at once would be
## wasted nodes and bodies far from the player. main.gd sets `focus` to the
## player's position each frame (see the hook lines in the PR notes); no
## per-frame simulation runs here, only this cheap distance check on a timer.

const RANobility := preload("res://scripts/sim/nobility.gd")
const RAProperty := preload("res://scripts/sim/property.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")

const BUILD_RADIUS := 260.0
const FREE_RADIUS := 340.0
const CHECK_INTERVAL := 1.0

var hud: HUD
var nobility: RANobility
var focus := Vector3.ZERO

## house_id -> {settlement, pos: Vector2, yaw}
var _manor_at: Dictionary = {}
## house_id -> the built Station root, while it's near the player.
var _built: Dictionary = {}
var _timer := 0.0


func setup(p_hud: HUD, p_nobility: RANobility = null) -> void:
	hud = p_hud
	nobility = p_nobility if p_nobility else RANobility.new()


func _ready() -> void:
	if nobility == null:
		nobility = RANobility.new()
	for h: Dictionary in nobility.houses:
		var hid := String(h["id"])
		var settlement := nobility.primary_fief(hid)
		if settlement < 0:
			continue
		var lot := _manor_lot(settlement)
		if lot.is_empty():
			continue
		_manor_at[hid] = {"settlement": settlement, "pos": lot["pos"], "yaw": float(lot["yaw"])}


func _manor_lot(settlement_idx: int) -> Dictionary:
	var s: Dictionary = WorldGen.settlements[settlement_idx]
	var lots: Array = s["plan"].get("lots", [])
	for lot: Dictionary in lots:
		if String(lot["asset"]) == "mhouse_manor":
			return lot
	var best := {}
	var best_tier := -1
	for lot: Dictionary in lots:
		var asset := String(lot["asset"])
		if not BuildingProfiles.is_house(asset):
			continue
		var kind: String = RAProperty.ASSET_KIND.get(asset, RAProperty.DEFAULT_KIND)
		var tier := int(RAProperty.KIND_INFO[kind]["tier"])
		if tier > best_tier:
			best_tier = tier
			best = lot
	return best


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	for hid: String in _manor_at:
		var pos: Vector2 = _manor_at[hid]["pos"]
		var d := Vector2(focus.x, focus.z).distance_to(pos)
		if d < BUILD_RADIUS and not _built.has(hid):
			_built[hid] = _spawn_court(hid)
		elif d > FREE_RADIUS and _built.has(hid):
			(_built[hid] as Node3D).queue_free()
			_built.erase(hid)


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _spawn_court(house_id: String) -> Node3D:
	var info: Dictionary = _manor_at[house_id]
	var pos: Vector2 = info["pos"]
	var yaw: float = info["yaw"]
	var out := Vector2(sin(yaw), cos(yaw))
	var at := pos + out * (BuildingProfiles.size_of("mhouse_manor").z * 0.5 + 2.0)
	var h: Dictionary = nobility.house_by_id(house_id)
	var head: Dictionary = h.get("head", {})
	var title_word := "Lady" if String(head.get("gender", "male")) == "female" else "Lord"
	var title := "%s %s" % [title_word, String(head.get("name", "?"))]
	var root := Node3D.new()
	root.name = "Court_%s" % house_id
	add_child(root)
	var st := Station.new(title, "Audience", _court_menu.bind(house_id))
	root.add_child(st)
	st.global_position = _ground(at)
	var body := Assets.character("Noble", 1.78, [])
	st.add_child(body)
	var anim := Assets.animation_player(body)
	if anim and anim.has_animation("Idle"):
		anim.play("Idle")
	var to := pos - at
	st.rotation.y = atan2(to.x, to.y)
	return root


# --- the court menu --------------------------------------------------------------------

func _court_menu(house_id: String) -> Dictionary:
	var h: Dictionary = nobility.house_by_id(house_id)
	var name := String(h.get("name", "the house"))
	var op := nobility.opinion(house_id)
	var opts: Array = []
	opts.append(["Pay respects", _do_respects.bind(house_id), true])
	opts.append(["Petition for sponsorship", _do_sponsor.bind(house_id), true])
	opts.append(["Ask for a lease at a fair rate", _do_lease.bind(house_id), true])
	opts.append(["Offer service (arranged introduction)", _do_introduction.bind(house_id), true])
	opts.append(["Request a loan for your trading house (100g)", _do_loan.bind(house_id), true])
	if nobility.is_struggling(house_id) and not nobility.fiefs_of(house_id).is_empty():
		opts.append(["Buy a struggling holding", _do_buy.bind(house_id), true])
	return {"title": "%s (standing %d)" % [name, int(round(op))],
		"body": "The %s receives you." % name, "options": opts}


func _do_respects(house_id: String) -> String:
	nobility.change_opinion(house_id, 1.5)
	return "\"Kind of you to call.\" (+opinion)"


func _do_sponsor(house_id: String) -> String:
	var r := nobility.sponsor(house_id)
	if bool(r["ok"]) and Life.get("career_sponsor_tier") != null:
		Life.career_sponsor_tier = maxi(int(Life.career_sponsor_tier), int(r["tier"]))
	return String(r["text"])


func _do_lease(house_id: String) -> String:
	var r := nobility.lease_offer(house_id, RAProperty.KIND_INFO["cottage"]["base"])
	return String(r["text"])


func _do_introduction(house_id: String) -> String:
	return String(nobility.arrange_introduction(house_id)["text"])


func _do_loan(house_id: String) -> String:
	return String(nobility.request_loan(house_id, 100)["text"])


func _do_buy(house_id: String) -> String:
	var fiefs := nobility.fiefs_of(house_id)
	if fiefs.is_empty():
		return "Nothing left to sell."
	return String(nobility.buy_holding(house_id, "settlement", fiefs[0])["text"])
