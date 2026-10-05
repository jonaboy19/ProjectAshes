class_name Station
extends Node3D
## Something in the world you can use: a merchant, an inn bed, a notice board,
## a recruiter. Shows a floating name; `menu` builds the options when used.
## menu: Callable() -> {title, body, options: [[label, Callable() -> String]]}

const Nameplates := preload("res://scripts/core/nameplates.gd")
var title := ""
var verb := "Use"
var menu: Callable
var model_path := ""
var model_height := 0.0
## Optional override: Callable(hud) run instead of opening `menu` (the War Room table opens the war map).
var on_use := Callable()


func _init(station_title := "", station_verb := "Use", station_menu := Callable()) -> void:
	title = station_title
	verb = station_verb
	menu = station_menu


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("station")
	var tag := Label3D.new()
	tag.text = title
	Nameplates.style(tag, Color("f0e0b0"), 28)
	tag.position.y = 2.4
	add_child(tag)


func prompt() -> String:
	return verb


## The interact key (via Interactable's legacy wrapper): open the menu, or run `on_use`.
func use() -> void:
	var hud := Interaction.hud(self)
	if hud == null:
		return
	if on_use.is_valid():
		on_use.call(hud)
	else:
		hud.call("show_menu", open)


func open() -> Dictionary:
	return menu.call() if menu.is_valid() else {}
