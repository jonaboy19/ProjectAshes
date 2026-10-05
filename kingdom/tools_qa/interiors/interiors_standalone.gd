extends Node
## Standalone harness (no main scene): renders modular interiors by day and night into one contact sheet.
##   xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan res://tools_qa/interiors/interiors_standalone.tscn -- --out=/path.png
## Columns: 12:00 and 23:00. Rows: the layouts in IDS.

const Layouts := preload("res://scripts/interiors/interior_layouts.gd")
const IDS := ["cottage", "family_loft", "craftsman", "bakery", "general_store", "tavern_inn"]
const HOURS := [12.0, 23.0]
const TILE := Vector2i(560, 315)

var _out := "/tmp/interiors.png"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	get_window().size = Vector2i(TILE.x, TILE.y)
	get_viewport().size = TILE
	var sheet := Image.create(TILE.x * HOURS.size(), TILE.y * IDS.size(), false, Image.FORMAT_RGB8)
	for r in IDS.size():
		for c in HOURS.size():
			var packed := load(Layouts.scene_path(IDS[r])) as PackedScene
			var room := packed.instantiate() as Node3D
			room.set("spawn_npcs", false)
			room.set("live_roster", false)
			add_child(room)
			room.call("build_furniture", "shot_%s" % IDS[r], "household:0:0")
			room.call("apply_hour", HOURS[c])
			var l := Layouts.layout(IDS[r])
			var cam := room.get_node("PreviewCamera") as Camera3D
			cam.fov = 80.0
			cam.position = Vector3(float(l["door_x"]) * 0.3, 1.9, float(l["d"]) * 0.5 - 0.15)
			cam.look_at(Vector3(0, 0.9, -float(l["d"]) * 0.25))
			cam.current = true
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(c * TILE.x, r * TILE.y))
			print("shot ", IDS[r], " ", HOURS[c], " ", room.call("draw_estimate"))
			room.queue_free()
			await get_tree().process_frame
	sheet.save_png(_out)
	print("saved ", _out)
	get_tree().quit()
