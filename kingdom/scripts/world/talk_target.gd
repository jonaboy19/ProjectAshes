extends Station
## "Talk" for villagers, as ONE interactable that follows whichever villager is
## nearest the player (within RANGE metres), instead of a component on every
## villager. Villagers join the "villager" group (scripts/population/villager.gd);
## this node scans that group a few times a second, parks itself on the nearest
## one and joins the "interactable" group only while someone is in range, so
## Player.nearest_interactable() and HUD's prompt pick it up like any Station.
## main.gd's interact handler already opens a Station's menu, so no hook is needed.
##
## While a menu is open the target is held, so a conversation never jumps to a
## villager who happens to walk past.
##
## VillageServices creates it in _ready(); `talk_menu` is VillageServices.talk_menu.

const RANGE := 3.0
const SCAN_INTERVAL := 0.2

var hud: Node          ## HUD (to hold the target while a menu is open)
var talk_menu: Callable    ## (npc: Dictionary) -> menu Dictionary
var current: Node3D = null

var _scan := 0.0
var _player: Node3D


func _init(p_hud: Node = null, p_talk_menu := Callable()) -> void:
	super("", "Talk", Callable())
	hud = p_hud
	talk_menu = p_talk_menu
	name = "TalkTarget"


## Station adds a floating title; villagers already carry their own tag, so this
## node skips it and only manages the groups.
func _ready() -> void:
	add_to_group("station")
	set_process(true)


func _process(delta: float) -> void:
	if current and is_instance_valid(current):
		global_position = current.global_position
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_INTERVAL
	if hud and hud.has_method("is_menu_open") and hud.is_menu_open() and current != null:
		return
	_retarget(_nearest())


func _nearest() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return null
	var from := _player.global_position
	# Services, doors and pickups win: a passer-by must never steal the button from
	# the guild counter or an entrance (playtest: "Villager" instead of the guild).
	for n in get_tree().get_nodes_in_group("interactable"):
		if n != self and n is Node3D and from.distance_squared_to((n as Node3D).global_position) < 3.4 * 3.4:
			return null
	var best: Node3D = null
	var best_d := RANGE * RANGE
	for n in get_tree().get_nodes_in_group("villager"):
		var v := n as Node3D
		if v == null or not v.is_visible_in_tree():
			continue
		var d := from.distance_squared_to(v.global_position)
		if d < best_d:
			best_d = d
			best = v
	return best


func _retarget(v: Node3D) -> void:
	if v == current and (v == null or is_in_group("interactable")):
		return
	current = v
	if v == null:
		if is_in_group("interactable"):
			remove_from_group("interactable")
		menu = Callable()
		title = ""
		return
	global_position = v.global_position
	var npc := npc_of(v)
	title = String(npc.get("name", "Villager"))
	menu = talk_menu.bind(npc) if talk_menu.is_valid() else Callable()
	if not is_in_group("interactable"):
		add_to_group("interactable")


## Identity of a villager node: {id, person, name}. Villagers expose `person`
## (their WorldSim index); anything else in the group falls back to its name.
static func npc_of(v: Node) -> Dictionary:
	var person := int(v.get("person")) if v.get("person") != null else -1
	if person >= 0:
		return {"id": "p%d" % person, "person": person}
	return {"id": "n_" + String(v.name), "person": -1, "name": String(v.name)}


func prompt() -> String:
	return "Talk"
