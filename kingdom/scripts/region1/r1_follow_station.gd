extends Station
## One interactable that follows whatever the player can use nearby (package C3/C4/C6): the runestone
## under their hand, the Scar's edge, the ashes of a raid. Like TalkTarget it joins the
## "interactable" group only while `finder` says something is in reach, so the game's normal
## interact button and prompt pick it up and main.gd opens its menu (Station.open).
##
## finder: Callable(player_pos: Vector2) -> {} (nothing) or
##   {"pos": Vector2 (where the station sits; the player's own position works for wide reach),
##    "verb": "Read the stone", "title": "Elder Stone", "menu": Callable() -> menu page Dictionary}

const SCAN_INTERVAL := 0.25

var finder: Callable = Callable()
var hud: Node
var active := false

var _scan := 0.0
var _player: Node3D


func _init(p_name := "R1Follow") -> void:
	super("", "Use", Callable())
	name = p_name


func _ready() -> void:
	# Not Station._ready: no floating name tag; the thing itself is the label.
	add_to_group("station")
	set_process(true)


func _process(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_INTERVAL
	if hud != null and hud.has_method("is_menu_open") and hud.is_menu_open() and active:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var found: Dictionary = {}
	if finder.is_valid():
		found = finder.call(Vector2(_player.global_position.x, _player.global_position.z))
	if found.is_empty():
		if active:
			active = false
			if is_in_group("interactable"):
				remove_from_group("interactable")
			menu = Callable()
		return
	var p: Vector2 = found["pos"]
	global_position = Vector3(p.x, _player.global_position.y if bool(found.get("at_player_height", false)) else WorldGen.height(p.x, p.y), p.y)
	# A prompt that sits on the player (the ashes to kneel at, the Scar's edge) is always at distance 0 and would beat the person standing
	# next to them: Mother at the family door could not be talked to while a death or a memory lay warm there. It ranks as a passer-by instead.
	if bool(found.get("at_player_height", false)):
		set_meta("low_priority", true)
	elif has_meta("low_priority"):
		remove_meta("low_priority")
	verb = String(found.get("verb", "Use"))
	title = String(found.get("title", ""))
	menu = found["menu"]
	if not active:
		active = true
	if not is_in_group("interactable"):
		add_to_group("interactable")


func prompt() -> String:
	return verb
