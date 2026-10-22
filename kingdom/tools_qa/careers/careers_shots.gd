extends Node
## Screenshot scene for the career screens (portrait). Builds a hub, puts the scribe at a chosen point of
## the ladder and renders each screen to PNG, then tiles a contact sheet.
##   xvfb-run -a -s "-screen 0 1280x1280x24" godot --path . --rendering-driver vulkan --resolution 540x960 \
##       res://tools_qa/careers/careers_shots.tscn -- --out=/tmp/claude-0/shots

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Biography := preload("res://scripts/sim/biography.gd")
const Data := preload("res://scripts/realm/scribe_data.gd")
const CareerTasks := preload("res://scripts/ui/career_tasks.gd")

var out_dir := "/tmp/claude-0/shots"
var layer: CanvasLayer
var shots: Array = []
var sc: RefCounted
var tr: RefCounted


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var raw := true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--landscape":
			raw = false
	# Portrait phone at 1:1 pixels (the project stretches a 1280x720 landscape base, which shrinks a 540 px wide window).
	if raw:
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute(out_dir)
	WorldGen.setup(2024)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.09, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	layer = CanvasLayer.new()
	add_child(layer)
	_build_state()
	await _run()
	_sheet()
	get_tree().paused = false
	get_tree().quit()


func _build_state() -> void:
	var hub: RefCounted = Hub.new()
	sc = hub.mod("scribe")
	tr = hub.mod("trades")
	var m := Mastery.new()
	var b := Biography.new()
	for d in 70:
		m.gain("scholarship", 2.0, d)
		m.gain("smithing", 1.2, d)
		m.gain("farming", 0.8, d)
	b.change_rep("letters", 24.0)
	b.change_rep("craft", 12.0)
	for mod: RefCounted in [sc, tr]:
		mod.mastery_ref = m
		mod.bio_ref = b
		mod.gold_ref = 260
		mod.sync_life = false
	tr.homestead_ref = preload("res://scripts/sim/homestead.gd").new()
	sc.apply(0, 1, 0.9)
	sc.rank = 2
	sc.since_day = 40
	sc.patron["regard"] = 47.0
	sc.standing = 66.0
	sc.stats.merge({"copies": 9, "forgeries_caught": 1, "tax_audits": 2, "translations": 1, "restricted_reads": 0})
	sc.learn_glyph("orr")
	sc.learn_glyph("sul")
	tr.join("blacksmith", 1)
	tr.ranks["blacksmith"] = "journeyman"
	tr.since["blacksmith"] = 20
	tr.stats["blacksmith"] = {"pieces": 9, "good_pieces": 3}
	tr.join("farmer", 1)
	CareerTasks.modules = {"scribe": sc, "trades": tr, "land": hub.mod("land"), "governance": hub.mod("governance")}
	CareerTasks.day_override = 80


func _open(trade: String) -> Control:
	var s := CareerTasks.open_for(layer, trade)
	return s


func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/careers_%02d_%s.png" % [out_dir, shots.size() + 1, name]
	img.save_png(path)
	shots.append({"name": name, "img": img})
	print("shot ", path, " ", img.get_size())


func _reset(s: Control) -> void:
	s.call("close_screen")
	s.queue_free()
	await get_tree().process_frame


func _run() -> void:
	var s := _open("scribe")
	await _shot("scribe_menu")
	# copy
	sc.hours_used.clear()
	sc.begin("copy", 80)
	s.set("_scratch", {"copy": {"i": 1, "picks": [1], "steady": 0.9}})
	s.call("_render_task")
	await _shot("copy_line")
	sc.abandon_task()
	# forgery
	sc.hours_used.clear()
	var guard := 0
	while guard < 80:
		guard += 1
		sc.begin("forgery", 80 + guard)
		if not (sc.task["doc"]["flaws"] as Dictionary).is_empty():
			break
		sc.abandon_task()
		sc.hours_used.clear()
	var flawed := (sc.task["doc"]["flaws"] as Dictionary).keys()[0] as String
	sc.examine_channel("seal", false)
	sc.examine_channel("date", true)
	sc.examine_channel(flawed, true)
	s.set("_scratch", {"forge": {"named": [flawed], "lens": false}})
	s.call("_render_task")
	await _shot("forgery")
	sc.abandon_task()
	# translate
	sc.hours_used.clear()
	sc.begin("translate", 90)
	s.set("_scratch", {})
	s.call("_render_task")
	await _shot("old_script")
	sc.abandon_task()
	# tax
	sc.hours_used.clear()
	sc.begin("tax", 91)
	s.set("_scratch", {"tax": {"marked": [1, 4]}})
	s.call("_render_task")
	await _shot("tax_ledger")
	# result of a tax audit with the real answers
	var marks: Array = []
	for i in (sc.task["ledger"]["rows"] as Array).size():
		if sc.task["ledger"]["rows"][i]["err"] != "":
			marks.append(i)
	var res: Dictionary = sc.submit_tax(marks)
	var lines: Array = []
	for row: Dictionary in res["rows"]:
		if String(row["err"]) != "":
			lines.append("%s: %s" % [String(row["house"]).capitalize(), String(row["err"])])
	res["texts"] = (res.get("texts", []) as Array) + lines
	s.call("_show_result", res, 2.0)
	await _shot("audit_result")
	# secret
	sc.rank = 3
	sc.hours_used.clear()
	var sec: Dictionary = sc._new_secret("forged_title", 80, 0, false)
	s.call("_render_secret", sec)
	await _shot("noble_secret")
	# ladder
	s.call("_set_tab", "ladder")
	await _shot("scribe_ladder")
	# estate (steward)
	sc.rank = 4
	sc.assign_estate(80)
	sc.estate_week(87)
	s.set("_tab", "work")
	s.call("_render_estate")
	await _shot("estate")
	# embassy
	sc.rank = 5
	sc.patron["regard"] = 70.0
	s.set("_scratch", {})
	s.call("_render_embassy")
	await _shot("embassy")
	await _reset(s)
	# blacksmith: forge step and ladder
	var s2 := _open("blacksmith")
	await _shot("smith_menu")
	var b2: Dictionary = tr.begin("blacksmith", "forge", 80)
	s2.call("_render_trade_step", b2["view"])
	await _shot("smith_forge")
	tr.abandon_task()
	s2.call("_set_tab", "ladder")
	await _shot("smith_ladder")
	await _reset(s2)
	var s3 := _open("farmer")
	var b3: Dictionary = tr.begin("farmer", "sow", 80, "spring")
	s3.call("_render_trade_step", b3["view"])
	await _shot("farmer_sow")
	tr.abandon_task()
	await _reset(s3)


func _sheet() -> void:
	var cols := 5
	var cw := 360
	var ch := 640
	var rows := int(ceil(float(shots.size()) / float(cols)))
	var sheet := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.05))
	for i in shots.size():
		var img: Image = (shots[i]["img"] as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
	sheet.save_png("%s/careers_sheet.png" % out_dir)
	print("sheet ", sheet.get_size())
