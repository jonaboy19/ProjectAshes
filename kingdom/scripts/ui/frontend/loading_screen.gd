extends "res://scripts/ui/frontend/screen.gd"
## Loading screen: logo, backdrop, rotating tips, gold progress bar driven by
## a MAIN-THREAD load of main.tscn (never load_threaded_request: see docs/qa/stability.md) after MIN_TIME, then
## the scene change. `preview` >= 0 freezes the bar there (screenshots / tests).

const Flow := preload("res://scripts/ui/frontend/flow.gd")

const MIN_TIME := 1.4
const TIP_TIME := 4.5
const TIPS := [
	"People remember your actions. Your reputation can open doors, or close them forever.",
	"Different professions open unique opportunities in towns and villages.",
	"Runestones line the major roads. When they dim or crack, the wilds creep closer.",
	"Weak monsters refuse to cross a glowing runestone. Bandits do not care.",
	"Dusk and night are far more dangerous outside the walls. Plan your journey, or find an inn.",
	"Careers accumulate. Switching paths keeps your history, reputation and contacts.",
	"A farmer's work follows the seasons: sow in spring, harvest before the first frost.",
	"Soldiers rise through militia, recruit and veteran to captain and beyond, but promotion needs reputation and open posts.",
	"Merchants earn more on the roads than in the market: watch prices change with war, mines and the weather.",
	"A blacksmith's craft grows with metals, Soulbeast materials and the commissions of generals and nobles.",
	"Soul Power awakens at the Blessing, at age twelve. Your element shapes how others see you.",
	"There are twelve soul tiers. Abilities evolve by how you use them: a smith's fire is not a soldier's fire.",
	"Naming is a rare ritual that shares Soul Power with the one you name.",
	"Nobles own the land. Even a house you build still owes land tax.",
	"Rent a room, then a house, then a manor. Property is a road to becoming a lord.",
	"A lord answers for residents, repairs, taxes, refugees and winter, not just for the view.",
	"War reaches ordinary people: prices climb, horses are requisitioned and recruiters knock at the door.",
	"Families grow across generations. Marriage, children, inheritance and bloodlines carry your name forward.",
	"The world never waits. Neighbours age, marry, rise and die whether you are watching or not.",
	"Strong beasts migrate. When wolves leave the hills, ask what drove them out.",
	"Gates close at night, guards increase and taverns fill. Every settlement keeps its own rhythm.",
	"Rumours travel faster than caravans. Listen at the inn: two stones on the western road stopped glowing.",
	"Journeys take time. Horses, camps, inns and caravans all matter on the long roads.",
	"Winter logistics decide campaigns. Stock your granary before the snow, and your saddlebags before the pass.",
	"Careers are lived, not levelled. What you repeat becomes who you are.",
	"Quicksave with F5 and quickload with F9. The world also autosaves when you enter or leave a settlement.",
]

var target := Flow.MAIN_SCENE
var preview := -1.0
var _bar: ProgressBar
var _pct: Label
var _tip: Label
var _tip_i := 0
var _tip_t := 0.0
var _t := 0.0
var _shown := 0.0
var _frames := 0
var _done := false


static func open(parent: Node, target_scene := Flow.MAIN_SCENE, preview_pct := -1.0) -> Control:
	var s: Variant = load("res://scripts/ui/frontend/loading_screen.gd").new()
	s.target = target_scene
	s.preview = preview_pct
	parent.add_child(s)
	return s


func _init() -> void:
	super()
	can_back = false


func _ready() -> void:
	add_backdrop("loading", 0.2)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 26
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lc := CenterContainer.new()
	lc.add_child(FE.logo(0.7))
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(lc)
	add_child(top)
	# Tip panel + bar, bottom centre.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.offset_left = -400
	bottom.offset_right = 400
	bottom.offset_top = -190
	bottom.offset_bottom = -34
	bottom.add_theme_constant_override("separation", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var pc := PanelContainer.new()
	var sb := AF.panel(Color(0.03, 0.028, 0.025, 0.78), AF.GOLD_DIM, 3, 14)
	sb.shadow_size = 0
	pc.add_theme_stylebox_override("panel", sb)
	bottom.add_child(pc)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	pc.add_child(tv)
	var tl := Label.new()
	tl.text = "TIP"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_override("font", AF.wfont(700))
	tl.add_theme_font_size_override("font_size", 14)
	tl.add_theme_color_override("font_color", AF.GOLD)
	tv.add_child(tl)
	_tip = AF.label("", 19, AF.TEXT)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.custom_minimum_size = Vector2(0, 54)
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tv.add_child(_tip)
	_bar = ProgressBar.new()
	_bar.max_value = 100
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	bottom.add_child(_bar)
	_pct = Label.new()
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pct.add_theme_font_override("font", AF.wfont(500))
	_pct.add_theme_font_size_override("font_size", 15)
	_pct.add_theme_color_override("font_color", AF.TEXT)
	bottom.add_child(_pct)
	_tip_i = randi() % TIPS.size()
	_tip.text = TIPS[_tip_i]
	_update(0.0)
	FE.fade_in(self, 0.3)
	Flow.handoff_tip = _tip_i


func _update(p: float) -> void:
	_bar.value = p * 100.0
	_pct.text = "Loading World...  %d%%" % int(round(p * 100.0))


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	_tip_t += delta
	if _tip_t >= TIP_TIME:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func() -> void: _tip.text = TIPS[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.25)
	if preview >= 0.0:
		_update(preview)
		return
	if _done:
		return
	# Bar creeps to a few percent while the screen holds; main.gd's world veil (same look, same tip)
	# takes over and reports the real world-generation progress.
	_shown = move_toward(_shown, minf(_t / MIN_TIME, 1.0) * 0.03, delta)
	_update(_shown)
	if _t >= MIN_TIME and _frames >= 4:
		_done = true
		_finish()


func _finish() -> void:
	# Main-thread load: main.tscn pulls in scripts that touch meshes and materials, which must never
	# be loaded on a worker thread. The screen has been on display for MIN_TIME, so the hitch is hidden.
	var res := load(target) as PackedScene
	var tree := get_tree()
	Flow.enter_game(tree)
	tree.paused = false
	if res:
		tree.change_scene_to_packed(res)
	else:
		tree.change_scene_to_file(target)
