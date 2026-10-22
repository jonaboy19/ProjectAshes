class_name Interactable
extends Node
## One usable thing in the world. A component: attach it as a child of any Node3D (`Interactable.attach`),
## or let a legacy node wrap itself: any member of the "interactable" group with prompt()/use() gets a wrapper
## child automatically the first time the picker sees it (`Interactable.for_node`).
##
## It carries a stable id ("<site>/<kind>/<index>"), verb, target name, priority, range, an availability check
## (`can_interact(player)`), the action (`interact(player)`) and an optional `hold_time` (seconds the button must
## be held; 0 = tap). The player's InteractionController and the HUD never look at what the host is.
##
## Dynamic text: set `label_fn` (Callable() -> {verb, target} or "Verb — Target") when the label changes.

signal interacted(player: Node)
signal hold_started(player: Node)
signal hold_progress(player: Node, fraction: float)
signal hold_cancelled(player: Node)

const META := &"interactable_component"
const GROUP := &"interactable"

var id := ""
var verb := "Use"
var target_name := ""
var priority := 0
var max_range := 3.2
var hold_time := 0.0
var low_priority := false
var is_mount := false
var enabled := true:
	set(v):
		enabled = v
		_sync_group()
## Callable() -> String: a stable id that is only known once the host is placed.
var id_fn := Callable()
## Callable(player) -> bool. Unset means always available.
var can_fn := Callable()
## Callable(player). The action.
var do_fn := Callable()
## Callable() -> Dictionary {verb, target} | String.
var label_fn := Callable()
## True for the automatic wrapper around a legacy prompt()/use() node.
var legacy := false


## Registers `host` as interactable. `opts` keys: id, verb, target, priority, range, hold_time, low_priority,
## mount, can (Callable), do (Callable), label (Callable), enabled.
static func attach(host: Node3D, opts: Dictionary = {}) -> Interactable:
	var c := Interactable.new()
	c.name = "Interactable"
	c.id = String(opts.get("id", ""))
	c.verb = String(opts.get("verb", "Use"))
	c.target_name = String(opts.get("target", ""))
	c.priority = int(opts.get("priority", 0))
	c.max_range = float(opts.get("range", InteractionPicker.DEFAULT_RANGE))
	c.hold_time = float(opts.get("hold_time", 0.0))
	c.low_priority = bool(opts.get("low_priority", false))
	c.is_mount = bool(opts.get("mount", false))
	c.id_fn = opts.get("id_fn", Callable())
	c.can_fn = opts.get("can", Callable())
	c.do_fn = opts.get("do", Callable())
	c.label_fn = opts.get("label", Callable())
	c.enabled = bool(opts.get("enabled", true))
	host.set_meta(META, c)
	host.add_child(c)
	return c


## Pooled hosts: turns a host's availability on or off (its component's `enabled`; for a host with no
## component, plain "interactable" group membership as before).
static func set_active(host: Node, on: bool) -> void:
	var c := component_of(host)
	if c != null:
		c.enabled = on
	elif on:
		host.add_to_group(GROUP)
	elif host.is_in_group(GROUP):
		host.remove_from_group(GROUP)


## The component driving `n`: its attached one, else a (cached) legacy wrapper. null for a node with neither a
## component nor a use() method.
static func for_node(n: Node) -> Interactable:
	if n == null or not is_instance_valid(n):
		return null
	var m: Variant = n.get_meta(META) if n.has_meta(META) else null
	if m is Interactable and is_instance_valid(m):
		return m
	if not (n is Node3D) or not (n.has_method("use") or n.has_method("rideable")):
		return null
	var w := Interactable.new()
	w.name = "LegacyInteractable"
	w.legacy = true
	n.set_meta(META, w)
	n.add_child(w)
	return w


## The explicit (non-legacy) component of `n`, or null.
static func component_of(n: Node) -> Interactable:
	if n == null or not is_instance_valid(n):
		return null
	var m: Variant = n.get_meta(META) if n.has_meta(META) else null
	if m is Interactable and is_instance_valid(m) and not (m as Interactable).legacy:
		return m
	return null


func _ready() -> void:
	var h := get_parent()
	if h != null:
		h.set_meta(META, self)
		if not legacy:
			_sync_group()


func _exit_tree() -> void:
	var h := get_parent()
	if h != null and h.has_meta(META) and h.get_meta(META) == self:
		h.remove_meta(META)


func host() -> Node3D:
	return get_parent() as Node3D


func stable_id() -> String:
	if id != "":
		return id
	if id_fn.is_valid():
		return String(id_fn.call())
	var h := host()
	return String(h.name) if h != null else ""


func can_interact(player: Node = null) -> bool:
	var h := host()
	if h == null or not is_instance_valid(h):
		return false
	if legacy:
		return true
	if not enabled:
		return false
	return not can_fn.is_valid() or bool(can_fn.call(player))


func interact(player: Node = null) -> void:
	var h := host()
	if legacy:
		if h == null:
			return
		if h.has_method("rideable") and bool(h.call("rideable")):
			if player != null and player.has_method("toggle_mount"):
				player.call("toggle_mount", h)
		elif h.has_method("use"):
			h.call("use")
	elif do_fn.is_valid():
		do_fn.call(player)
	interacted.emit(player)


## The candidate the picker scores. Legacy hosts keep their old meta/rideable conventions.
func candidate() -> Dictionary:
	var h := host()
	var lp := low_priority
	var mount := is_mount
	if legacy and h != null:
		lp = h.has_meta("low_priority")
		mount = h.has_method("rideable") and bool(h.call("rideable"))
	return {"id": stable_id(), "pos": h.global_position if h != null else Vector3.ZERO, "priority": priority,
		"range": max_range, "low_priority": lp, "mount": mount, "hold_time": hold_time, "source": self}


## {verb, target, text, icon} for the HUD. Legacy hosts derive it from their old conventions.
func label() -> Dictionary:
	var InteractLabel := load("res://scripts/ui/interact_label.gd")
	if label_fn.is_valid():
		var raw: Variant = label_fn.call()
		if raw is Dictionary and String((raw as Dictionary).get("verb", "")) != "":
			return InteractLabel.call("pack", String(raw["verb"]), String(raw.get("target", "")))
		if raw is String and raw != "":
			return InteractLabel.call("from_text", raw)
	if legacy:
		return InteractLabel.call("legacy", host())
	return InteractLabel.call("pack", verb, target_name)


func _sync_group() -> void:
	if not is_inside_tree() or legacy:
		return
	var h := get_parent()
	if h == null:
		return
	if enabled and not h.is_in_group(GROUP):
		h.add_to_group(GROUP)
	elif not enabled and h.is_in_group(GROUP):
		h.remove_from_group(GROUP)
