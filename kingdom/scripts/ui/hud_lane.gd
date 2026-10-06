extends RefCounted
## Preload this script (no class_name: a new global class needs a class-cache rebuild).
## One top-centre layout stack for the transient HUD furniture: the message toast, the tutorial /
## encounter hint pill, the LOCATION DISCOVERED style banners and the compact job-offer card. They used to each pick their own
## y and overprinted each other. Each element reports its height while it is on screen (`report`)
## and asks `y_for` where to sit: stacked in ORDER with a gap, never overlapping. While a menu or a
## conversation sheet is open (`set_menu_open`) banners and hints are held back (`allowed`).
##
## Pure static state + math, so the tests need no scene.

const ORDER := ["toast", "hint", "banner", "offer"]
const GAP := 8.0
## Preferred top y (720p px) of the banner: just under the compass, so the screen centre stays clear.
const BANNER_Y := 58.0
## Preferred top y (720p px) of the job-offer card (work_spots.gd): under the compass and the toast, nothing in the middle of the screen.
const OFFER_Y := 96.0

## id -> {owner key -> Vector2(top y, height)} while on screen. Several nodes may report under one id (two hint views:
## the tutorial's and the realm hints'), so an idle one clearing its own entry never erases the live one's.
static var _rects: Dictionary = {}
static var _menu_open := false
## QA switch: false restores the old behaviour (every element at its own y, never held back) for before / after shots.
static var enabled := true


static func reset() -> void:
	_rects.clear()
	_menu_open = false


## An element is on screen at `y` with this height (px); height <= 0 clears it. `owner` tells apart several nodes that
## share one id (pass the reporting node's instance id): each clears only its own entry.
static func report(id: String, y: float, height: float, owner := 0) -> void:
	var by_owner: Dictionary = _rects.get(id, {})
	if height > 0.5:
		by_owner[owner] = Vector2(y, height)
		_rects[id] = by_owner
	else:
		by_owner.erase(owner)
		if by_owner.is_empty():
			_rects.erase(id)


## Lowest bottom edge (y + height) of everything reported under `id`, or -INF when nothing is on screen.
static func bottom_of(id: String) -> float:
	var bottom := -INF
	for r: Vector2 in (_rects.get(id, {}) as Dictionary).values():
		bottom = maxf(bottom, r.x + r.y)
	return bottom


static func set_menu_open(open: bool) -> void:
	_menu_open = open


static func menu_open() -> bool:
	return _menu_open


## Banners and hints wait while a menu / sheet is up (the toast stays: it is one short line).
static func allowed(id: String) -> bool:
	if enabled and id == "offer" and (_rects.has("banner") or _rects.has("toast")):
		return false          # the job-offer card waits until the location banner and the toast above it are gone: the arrival view stays clear
	# (a tutorial hint can stay for a long while, so it does not hold the card back: the lane stacks the card under it)
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
			y = maxf(y, bottom_of(other) + GAP)
	return y
