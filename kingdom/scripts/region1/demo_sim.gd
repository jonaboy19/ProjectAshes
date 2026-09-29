class_name Region1DemoSim
extends Region1Sim
## Tiny reference module: an embers-on-a-grid random walk. It is the template for real
## modules (copy it), the sandbox default and the fixture for the scaffold tests.
## Not listed in modules.json, so it never runs in the game.

const SIZE := 32
const SAVE_STATE_VERSION := 2

var cells := PackedByteArray()   # SIZE*SIZE heat values 0..255
var sparks := 0                  # total sparks dropped


func _init() -> void:
	module_name = &"demo_sim"
	state_version = SAVE_STATE_VERSION


func _setup() -> void:
	cells.resize(SIZE * SIZE)
	cells.fill(0)
	sparks = 0


func _step(dt_days: float) -> void:
	# ~8 sparks per day; every cell cools a little.
	var n := int(round(8.0 * dt_days))
	for i in n:
		var idx := rng.randi() % (SIZE * SIZE)
		cells[idx] = mini(255, cells[idx] + 90)
		sparks += 1
		if cells[idx] == 255:
			emit_event(&"flare", {"x": idx % SIZE, "y": idx / SIZE})
	if tick_count % 4 == 0:
		for i in cells.size():
			if cells[i] > 0:
				cells[i] -= 1


func _save_state() -> Dictionary:
	return {"cells": Marshalls.raw_to_base64(cells), "sparks": sparks}


func _load_state(d: Dictionary) -> void:
	cells = Marshalls.base64_to_raw(String(d["cells"])) if d.has("cells") else PackedByteArray()
	if cells.size() != SIZE * SIZE:
		cells.resize(SIZE * SIZE)
		cells.fill(0)
	sparks = int(d.get("sparks", 0))


## Migration stub example: v1 saved `sparks` as `count` at the top level of the state.
func migrate(from_version: int, data: Dictionary) -> Dictionary:
	if from_version == 1:
		var st: Dictionary = data.get("state", {})
		if st.has("count"):
			st["sparks"] = st["count"]
			st.erase("count")
		data["state"] = st
	return data


func debug_image(px: int = 256) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var h := float(cells[y * SIZE + x]) / 255.0
			img.set_pixel(x, y, Color(0.12 + 0.88 * h, 0.1 + 0.5 * h, 0.16))
	img.resize(px, px, Image.INTERPOLATE_NEAREST)
	return img


func summary() -> String:
	return "%s sparks=%d" % [super.summary(), sparks]
