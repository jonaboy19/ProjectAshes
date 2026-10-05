extends Node3D
## One interactable spot of the tower world (door, gate, bonfire, chest, vendor...). It carries an Interactable
## component (scripts/interaction/interactable.gd) so the HUD shows its prompt() on the interact button; the
## press reaches use(), which hands it to the owning tower_site.gd (`use_point`), which dispatches via `action`
## and `data`. Plain data + a prompt: no per-frame work at all.

var action := ""
var label := ""
var data: Dictionary = {}
var enabled := true:
	set(v):
		enabled = v
		if _ic != null:
			_ic.enabled = v

var _ic: Interactable


func _ready() -> void:
	add_to_group("tower_point")
	set_meta("tower_point", true)
	_ic = Interactable.attach(self, {"id_fn": func() -> String: return "tower/%s/%s" % [String(name), action],
		"verb": "Use", "enabled": enabled, "do": func(_pl: Node) -> void: use(),
		"label": func() -> String: return prompt()})


func prompt() -> String:
	return label


## The interact key: the owning tower_site (an ancestor with `use_point`) dispatches by `action`.
func use() -> void:
	var n := get_parent()
	while n != null:
		if n.has_method("use_point"):
			n.call("use_point", self)
			return
		n = n.get_parent()
