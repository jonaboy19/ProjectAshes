extends "res://scripts/ui/frontend/screen.gd"
## First-launch flow, shown once between the title splash and the main menu:
## 1) language, 2) privacy and terms notice (placeholder text until the real links exist),
## 3) a four-line "how to play" hint. Each step is remembered in user://settings.cfg [flow],
## so an interrupted first launch resumes at the step it stopped on.
##   FirstRun.needed() -> bool          FirstRun.new() emits `finished` when all steps are done.

signal finished

const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const FLOW_SECTION := "flow"

var _col: VBoxContainer


static func needed() -> bool:
	var cf := ConfigFile.new()
	cf.load(SS.PATH)
	return not bool(cf.get_value(FLOW_SECTION, "first_run_done", false))


static func _flag(key: String) -> bool:
	var cf := ConfigFile.new()
	cf.load(SS.PATH)
	return bool(cf.get_value(FLOW_SECTION, key, false))


static func _set_flag(key: String, on := true) -> void:
	var cf := ConfigFile.new()
	cf.load(SS.PATH)
	cf.set_value(FLOW_SECTION, key, on)
	cf.save(SS.PATH)


func _init() -> void:
	super()
	can_back = false


func _ready() -> void:
	add_backdrop("new_game", 0.45)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(700.0, get_viewport_rect().size.x - 40.0), 0)
	center.add_child(panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	panel.add_child(_col)
	FE.fade_in(self, 0.35)
	_next()


func _next() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	if not _flag("lang_done"):
		_step_language()
	elif not _flag("privacy_ok"):
		_step_privacy()
	elif not _flag("tutorial_seen"):
		_step_tutorial()
	else:
		_set_flag("first_run_done")
		finished.emit()


func _step_language() -> void:
	_col.add_child(FE.header(tr("FIRST_LANG_TITLE")))
	_col.add_child(AF.label(tr("FIRST_LANG_BODY"), 18, AF.TEXT_DIM, true))
	var names := ["English", "Nederlands"]
	for i in names.size():
		var idx := i
		_col.add_child(FE.menu_row(names[i], func() -> void:
			var vals := SS.read_all(get_tree())
			vals["language"] = idx
			SS.write_all(vals)
			App.refresh(vals)
			_set_flag("lang_done")
			_next(), 22, 54))
	focus_first(_col)


func _step_privacy() -> void:
	_col.add_child(FE.header(tr("PRIVACY_TITLE")))
	_col.add_child(AF.label(tr("PRIVACY_BODY"), 18, AF.TEXT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_col.add_child(row)
	row.add_child(FE.gold_btn(tr("BTN_ACCEPT"), func() -> void:
		_set_flag("privacy_ok")
		_next(), 240))
	focus_first(_col)


func _step_tutorial() -> void:
	_col.add_child(FE.header(tr("TUT_TITLE")))
	for k: String in ["TUT_MOVE", "TUT_LOOK", "TUT_ACT", "TUT_PAUSE"]:
		_col.add_child(AF.label("•  " + tr(k), 20, AF.TEXT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	_col.add_child(row)
	row.add_child(FE.gold_btn(tr("BTN_CONTINUE"), func() -> void:
		_set_flag("tutorial_seen")
		_next(), 240))
	focus_first(_col)
