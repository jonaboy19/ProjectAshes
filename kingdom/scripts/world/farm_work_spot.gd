extends Node3D
## Field hand work at a village's farm (the WorldGen site of kind "farm" that
## RegionSites plants outside every village, e.g. Ashford's). Hold "interact"
## while standing at the spot to fill a short progress bar; finishing pays a
## small wage and records farming mastery (Life.record("farmed", ...)). The
## job named — and its animation — follows the season, matching
## scripts/sim/seasons.gd: sowing in spring, weeding in summer, bringing in
## the harvest in autumn, repairs and hauling in winter.
##
## Spawned by scripts/world/homestead_view.gd's ring (within player reach),
## the same way it already gives the player's own plots a body, so main.gd
## needs no extra dispatcher. Self-contained like fishing_spot.gd: always in
## the "interactable" group with prompt() and use(); it polls "interact"
## itself (held, not tapped) while it is the player's nearest interactable.

const SeasonsScript := preload("res://scripts/sim/seasons.gd")
const WORK_TIME := 4.0
const WAGE := 6
const MASTERY_XP := 1.0
const LEAVE_DISTANCE := 4.5
const TASK_NAMES := {
	SeasonsScript.SPRING: "Sow the fields",
	SeasonsScript.SUMMER: "Weed the fields",
	SeasonsScript.AUTUMN: "Bring in the harvest",
	SeasonsScript.WINTER: "Repair fences and haul feed",
}

## The farm site this spot belongs to ({name, pos, yaw, ...}, see region_sites.gd).
var site: Dictionary = {}

var _working := false
var _progress := 0.0
var _menu_was_open := false
var _ui: CanvasLayer
var _fill: ColorRect
var _label: Label


func _ready() -> void:
	add_to_group("interactable")


func _current_season() -> int:
	return SeasonsScript.season_of(WorldSim.seasons.current_day() if WorldSim.seasons else int(WorldSim.day))


func _task_name() -> String:
	return String(TASK_NAMES.get(_current_season(), "Work the fields"))


func prompt() -> String:
	return "%s (hold)" % _task_name() if not _working else _task_name()


## Taps do nothing; the hold in _process drives the work. Kept so any
## dispatcher that calls use() on tap does no harm.
func use() -> void:
	pass


func _process(delta: float) -> void:
	var p := _player()
	var dead := p != null and bool(p.get("dead"))
	var near := p != null and not dead and p.global_position.distance_to(global_position) <= LEAVE_DISTANCE
	var menu_open := _menu_open()
	if not near or menu_open:
		if _working:
			_stop(false)
		_menu_was_open = menu_open
		return
	var nearest: bool = p.has_method("nearest_interactable") and p.call("nearest_interactable") == self
	var holding: bool = nearest and Input.is_action_pressed("interact")
	if holding and not _working:
		_start()
	elif not holding and _working:
		_stop(false)
	if _working:
		_progress += delta / WORK_TIME
		_update_ui()
		if _progress >= 1.0:
			_finish()
	_menu_was_open = menu_open


func _start() -> void:
	_working = true
	_progress = 0.0
	_build_ui()
	_play_farm_anim()


func _stop(finished: bool) -> void:
	_working = false
	_progress = 0.0
	if not finished and _ui:
		_ui.queue_free()
		_ui = null


func _finish() -> void:
	Game.add_gold(WAGE)
	Life.record("farmed", MASTERY_XP)
	Game.say("A day's field work: %d gold." % WAGE)
	_stop(true)
	if _ui:
		_ui.queue_free()
		_ui = null


func _update_ui() -> void:
	if _fill:
		_fill.size.x = clampf(_progress, 0.0, 1.0) * 220.0
	if _label:
		_label.text = "%s — %d%%" % [_task_name(), int(round(clampf(_progress, 0.0, 1.0) * 100.0))]


func _build_ui() -> void:
	if _ui:
		_ui.queue_free()
	_ui = CanvasLayer.new()
	_ui.layer = 30
	add_child(_ui)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_box())
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(260, 0)
	panel.offset_left = -130.0
	panel.offset_right = 130.0
	panel.offset_top = -230.0
	panel.offset_bottom = -170.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_label = Label.new()
	_label.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(_label)
	var track := Control.new()
	track.custom_minimum_size = Vector2(220, 14)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.clip_contents = true
	box.add_child(track)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.08)
	bg.size = Vector2(220, 14)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bg)
	_fill = ColorRect.new()
	_fill.color = UITheme.OK
	_fill.size = Vector2(0, 14)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_fill)
	_update_ui()


## Plays a full-body "Farm_Harvest" loop on the player if its animator
## exposes play_full (villager.gd's JOB_CLIPS use the same clip name).
func _play_farm_anim() -> void:
	var p := _player()
	if p == null:
		return
	var anim: Variant = p.get("_animator")
	if anim is Object and (anim as Object).has_method("play_full"):
		(anim as Object).call("play_full", "Farm_Harvest", 0.9)


func _player() -> Node3D:
	var pl: Variant = Life.player
	if pl is Node3D and is_instance_valid(pl):
		return pl
	return get_tree().get_first_node_in_group("player") as Node3D


func _menu_open() -> bool:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	return hud is Object and is_instance_valid(hud) and (hud as Object).has_method("is_menu_open") \
		and bool((hud as Object).call("is_menu_open"))
