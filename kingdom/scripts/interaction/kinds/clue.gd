class_name Clue
extends Node3D
## A searchable clue (spoiled sack, boot prints, a forced lock). "Examine" fires `interact {id}` on the quest bus,
## which Investigate objectives count. It is always examinable, shows no marker or glow, and remembers it was
## examined (`examined`) so the prompt turns into "Examined". Only the quest decides whether it mattered.

signal examined_now(clue_id: String)

var clue_id := ""
var note := ""
var examined := false


static func spawn(parent: Node, pos: Vector3, id: String, text := "", target := "Something odd") -> Clue:
	var c := Clue.new()
	c.clue_id = id
	c.note = text
	c.name = "Clue_" + id.replace("/", "_")
	c.set_meta("target", target)
	parent.add_child(c)
	c.global_position = pos
	return c


func _ready() -> void:
	Interactable.attach(self, {"id_fn": func() -> String: return clue_id, "verb": "Examine", "range": 2.4,
		"target": String(get_meta("target", "Something odd")),
		"do": func(_p: Node) -> void: examine(),
		"label": func() -> Dictionary: return {"verb": "Examined" if examined else "Examine", "target": String(get_meta("target", "Something odd"))}})


func examine() -> void:
	examined = true
	if note != "":
		var game := get_node_or_null("/root/Game")
		if game != null:
			game.call("say", note)
	QuestBus.shared().emit_event(&"interact", {"id": clue_id})
	examined_now.emit(clue_id)
