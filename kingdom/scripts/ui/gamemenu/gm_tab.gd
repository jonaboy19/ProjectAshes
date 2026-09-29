extends Control
## Base class of the game menu's tab pages. game_menu.gd adds one page per tab into
## its body and calls these hooks; a page is a plain Control that fills the body.
##   build()      once, when the menu is first created (widgets)
##   on_show()    every time the tab becomes visible (load data, host things)
##   on_hide()    when the tab is left or the menu closes
##   refresh()    re-read the game data (also called by the menu after actions)
##   handle_key() a key while the tab is visible; return true when handled
##   hints()      bottom-bar key hints: [[key, label, Callable, disabled?], ...]

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const MD := preload("res://scripts/ui/gamemenu/menu_data.gd")

## The GameMenu control that owns this page.
var menu: Control


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func build() -> void:
	pass


func on_show() -> void:
	refresh()


func on_hide() -> void:
	pass


func refresh() -> void:
	pass


func handle_key(_e: InputEventKey) -> bool:
	return false


func hints() -> Array:
	return []


## Ask the menu to rebuild the bottom hint bar (after the selection changed).
func hints_changed() -> void:
	if menu != null and menu.has_method("rebuild_hints"):
		menu.call("rebuild_hints")


## A padded page root: HBox filling the page with the standard gap.
func page_hbox(gap := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", gap)
	add_child(h)
	return h
