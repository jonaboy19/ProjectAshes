extends Station
## A story character standing at their place (package C7): a Station, so the game's normal interact
## button talks to them. The Region 1 story director builds the conversation page (menu) and spawns
## and frees these by distance, so nobody stands around an empty valley.
##
##   var npc := preload("res://scripts/region1/r1_quest_npc.gd").new()
##   npc.setup("idra_vell", "Warden Idra Vell", "Herbalist", menu_callable)
##   world.add_child(npc); npc.place(Vector2(x, z), facing_point)

var npc_id := ""
var look := "Guard"
var body: Node3D
var spawned_for := ""      ## director bookkeeping: "<npc>@<place>"


func setup(p_id: String, display: String, p_look: String, p_menu: Callable) -> Station:
	npc_id = p_id
	look = p_look
	title = display
	verb = "Talk"
	menu = p_menu
	name = "R1NPC_" + p_id
	return self


func _ready() -> void:
	super._ready()
	if look.begins_with("critter:"):
		# The fawn and other animals: a Critter that stays put (claimed = no wandering), never huntable.
		var cr := Critter.new()
		cr.kind = look.trim_prefix("critter:")
		cr.home = Vector2(global_position.x, global_position.z)
		cr.huntable = false
		cr.claimed = true
		cr.scale = Vector3.ONE * 0.55
		body = cr
		add_child(cr)
	else:
		body = Assets.character(look, 1.72, [])
		if body != null:
			add_child(body)
			var ap := Assets.animation_player(body)
			if ap != null:
				for a in ["Idle_Talking", "Idle", "Idle_A"]:
					if ap.has_animation(a):
						var anim := ap.get_animation(a)
						if anim != null:
							anim.loop_mode = Animation.LOOP_LINEAR
						ap.play(a)
						break
	# A little presence: a soft warm light at the feet so the giver reads at dusk.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 0.35
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 1.0, 0.6)
	add_child(lamp)


func place(at: Vector2, face_to: Vector2) -> void:
	global_position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	var d := face_to - at
	if d.length() > 0.1:
		rotation.y = atan2(d.x, d.y)


## Station.open(): the director's conversation page for this character.
func open() -> Dictionary:
	var page: Dictionary = menu.call(npc_id) if menu.is_valid() else {}
	if body != null and is_instance_valid(body) and page.has("speaker"):
		page["model"] = body
		page["look"] = look
	return page
