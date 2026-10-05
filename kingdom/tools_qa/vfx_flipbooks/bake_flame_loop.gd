extends SceneTree
## Bakes assets/vfx/flipbooks/flame_loop.png: a seamless 32-frame (8x4) looping flame flipbook, 128 px cells, made from
## two scrolling noise fields cross-faded over the loop so frame 31 flows into frame 0. RGB = premultiplied fire colour,
## A = coverage. Used by shaders/brazier_fire.gdshader (additive, unshaded) on braziers and torches. CC0 (made here).
##   Godot_console.exe --headless --path kingdom -s res://tools_qa/vfx_flipbooks/bake_flame_loop.gd

const COLS := 8
const ROWS := 4
const CELL := 128
const OUT := "res://assets/vfx/flipbooks/flame_loop.png"


func _initialize() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 3
	var img := Image.create(COLS * CELL, ROWS * CELL, false, Image.FORMAT_RGBA8)
	var frames := COLS * ROWS
	for f in frames:
		var ph := float(f) / frames
		var ox := (f % COLS) * CELL
		var oy := (f / COLS) * CELL
		for y in CELL:
			var t := 1.0 - float(y) / CELL          # 0 bottom .. 1 top
			for x in CELL:
				var u := (float(x) / CELL - 0.5) * 2.0
				# loop: two copies of the field scrolling up, offset by one loop length, cross-faded
				var s1 := n.get_noise_3d(x * 1.0, y + ph * 140.0, 0.0)
				var s2 := n.get_noise_3d(x * 1.0, y + (ph - 1.0) * 140.0, 0.0)
				var turb := lerpf(s1, s2, ph)
				var sway := sin((ph + t * 0.6) * TAU) * 0.06 * t
				var width := pow(maxf(1.0 - t, 0.0), 0.7) * 0.5 + 0.03
				var d := absf(u - sway - turb * 0.7 * pow(t, 0.8)) / width
				var body := clampf(1.0 - d, 0.0, 1.0) * smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.3, 0.85, t + turb * 0.6))
				var heat := clampf(body * body * 2.2 - t * 0.6, 0.0, 1.0)
				var col := Color(0.55, 0.08, 0.02).lerp(Color(1.0, 0.45, 0.08), smoothstep(0.0, 0.45, heat)).lerp(Color(1.0, 0.86, 0.5), smoothstep(0.5, 0.95, heat))
				var a := clampf(body * 1.8, 0.0, 1.0)
				img.set_pixel(ox + x, oy + y, Color(col.r * a, col.g * a, col.b * a, a))
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("FLAME baked ", OUT)
	quit()
