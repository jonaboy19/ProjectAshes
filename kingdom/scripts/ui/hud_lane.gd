extends RefCounted
## Preload this script (no class_name: a new global class needs a class-cache rebuild).
## One top-centre layout stack for the transient HUD furniture: the message toast, the tutorial /
## encounter hint pill and the LOCATION DISCOVERED style banners. They used to each pick their own
## y and overprinted each other. Each element reports its height while it is on screen (`report`)
## and asks `y_for` where to sit: stacked in ORDER with a gap, never overlapping. While a menu or a
## conversation sheet is open (`set_menu_open`) banners and hints are held back (`allowed`).
##
## Pure static state + math, so the tests need no scene.

const ORDER := ["toast", "hint", "banner"]
const GAP := 8.0

static var _rects: Dictionary = {}          # id -> Vector2(top y, height) while on screen
static var _menu_open := false
## QA switch: false restores the old behaviour (every element at its own y, never held back) for before / after shots.
static var enabled := true


static func reset() -> void:
	_rects.clear()
	_menu_open = false


## An element is on screen at `y` with this height (px); height <= 0 clears it.
static func report(id: String, y: float, height: float) -> void:
	if height > 0.5:
		_rects[id] = Vector2(y, height)
	else:
		_rects.erase(id)


static func set_menu_open(open: bool) -> void:
	_menu_open = open


static func menu_open() -> bool:
	return _menu_open


## Banners and hints wait while a menu / sheet is up (the toast stays: it is one short line).
static func allowed(id: String) -> bool:
	return not (enabled and _menu_open and id != "toast")


## Top y for `id`: its own preferred `base_y`, pushed below every earlier element in ORDER
## that is on screen (so a banner never overlaps the toast or hint above it).
static func y_for(id: String, base_y: float) -> float:
	if not enabled:
		return base_y
	var y := base_y
	for other: String in ORDER:
		if other == id:
			break
		if _rects.has(other):
			var r: Vector2 = _rects[other]
			y = maxf(y, r.x + r.y + GAP)
	return y
