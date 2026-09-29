extends SceneTree
## Wardlines story board (headless): writes coverage PNGs of one scripted story and a 2x2 sheet.
##
##   Godot --headless --path kingdom -s res://tools_qa/region1/wardlines_demo.gd -- --out=<dir> [--seed=1] [--px=512]
##
## 1 baseline   2 a road is cut, a village goes dark   3 mended + ward / lure / alarm / bless carved
## 4 a hundred and fifty days without help. The log lists the rumours after each step.
## Blue glow = protection, gold rings = Elder Stones, dark dots = dead stones, red dashes = cut links,
## teal = player links, coloured ring = carved glyph (blue ward, pink lure, yellow alarm, green bless).

const Ward := preload("res://scripts/region1/wardlines.gd")


func _init() -> void:
	var out := "user://wardlines_demo"
	var seed_value := 1
	var px := 512
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a.begins_with("--px="):
			px = int(a.substr(5))
	DirAccess.make_dir_recursive_absolute(out)
	var w: Ward = Ward.new()
	w.setup(seed_value)
	var imgs: Array[Image] = []
	print("stones=%d elders=%d links=%d" % [w.stone_count(), w.elder_ids.size(), w.links.size()])
	_snap(w, imgs, out, "1_baseline", px)

	# 2: cut the road to Eastmere, a dead-end village
	var key := "1>Eastmere"
	var ids := w.road_stones(key)
	var mid := (ids.size() - 1) / 2
	w.cut_link(ids[mid], ids[mid + 1])
	for i in 16:
		w.tick(0.5)
	_snap(w, imgs, out, "2_cut_road", px)
	print("  road coverage %s: %s" % [key, w.road_coverage(key)])

	# 3: mend it, then carve glyphs
	w.mend_link(ids[mid], ids[mid + 1])
	for i in 16:
		w.tick(0.5)
	var ash := w.nearest_stone(Vector2(60, 40))
	w.carve(ash, "ward")
	w.carve(w.nearest_stone(Vector2(-60, 40)), "ward")
	w.carve(w.nearest_stone(Vector2(360, 620), 200.0), "lure")
	w.carve(w.nearest_stone(Vector2(290, -260), 200.0), "alarm")
	w.carve(w.nearest_stone(Vector2(-330, -230), 200.0), "bless")
	for i in 12:
		w.tick(0.5)
	_snap(w, imgs, out, "3_glyphs", px)
	print("  lures: %d  bless yield at Millbrook: %.2f" % [w.lure_points().size(), w.bless_at(Vector2(-330, -280))])

	# 4: 150 days with only the crews
	for i in 300:
		w.tick(0.5)
	_snap(w, imgs, out, "4_day150", px)
	print("  ", w.summary())

	var sheet := Image.create(px * 2, px * 2, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, px, px), Vector2i((i % 2) * px, (i / 2) * px))
	sheet.save_png(out.path_join("wardlines_sheet.png"))
	print("wrote ", ProjectSettings.globalize_path(out))
	quit(0)


func _snap(w: Ward, imgs: Array[Image], out: String, tag: String, px: int) -> void:
	var img := w.debug_image(px)
	imgs.append(img)
	img.save_png(out.path_join("wardlines_%s.png" % tag))
	print("[%s] day %.0f  %s" % [tag, w.day_f, w.summary()])
	for r in w.rumours():
		print("    rumour: ", r)
