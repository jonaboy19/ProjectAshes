extends RefCounted
## In-world nameplates (Label3D). Screen-constant (fixed_size, so a plate next to the camera can never
## fill the view), distance-limited, and hidden while a dialogue / menu is open (the HUD sets `suppressed`
## from its 0.1 s poll). Plates registered with `style()` are in group "nameplate"; the villager tag
## (population/villager.gd) reads `suppressed` itself.

## Readability pass (visual pass 2026-10): plates fade out between FADE_START and the plate's own max distance (capped at
## FADE_CAP), only the MAX_SHOWN nearest are drawn, they ride up above the town name board (group "world_sign") when their owner stands in front of it, and the
## on-screen font height is an integer number of pixels (>= MIN_PX at 720p) with mipmaps off, so the text is crisp
## instead of a blue smear over roofs and sky. `refresh()` does it all from the HUD's 0.1 s poll.
##
## Reference: pixel_size 0.0022 at font 36 is what army/squad.gd's screen-constant banner uses.
const PX := 0.0016
const MAX_DIST := 12.0      # AAA pass 2026-10-06: names only near the player (was 22)

const FADE_CAP := 14.0          # plates are gone by here (bosses / landmarks that ask for more keep it)
const FADE_LEN := 4.0
const MAX_SHOWN := 3
const MIN_PX := 17.0            # on-screen font height at 720p (scaled with the viewport height, never below this)
const SUB_SCALE := 0.62         # a subtitle line is this fraction of the plate font
const MAX_LIFT := 64.0          # px (at 720p) a plate is raised to clear a town board
const SIGN_MARGIN := 24.0       # px around a town board's rectangle

static var suppressed := false
## AAA pass 3: the resident the HUD has in reach (its interact target); only their name shows, small.
static var focus: Node = null


static func style(tag: Label3D, color: Color, font := 30, max_dist := MAX_DIST) -> Label3D:
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = PX
	tag.font_size = font
	tag.outline_size = 8
	tag.modulate = color
	tag.no_depth_test = false
	tag.visibility_range_end = max_dist
	tag.visibility_range_end_margin = 2.0
	tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	tag.set_meta("np_max", max_dist if max_dist > 30.0 else minf(max_dist, FADE_CAP))
	tag.add_to_group("nameplate")
	tag.visible = not suppressed
	return tag


## A smaller second line (a title such as "Brewmistress") under a plate `tag`: one plate for the owner, not two stacked
## ones. The line is not in group "nameplate" (so it never counts against MAX_SHOWN); `refresh()` and `set_suppressed()`
## drive it from its owner plate through the "np_sub" meta.
static func add_subtitle(tag: Label3D, text: String, color := Color("c8b68a")) -> Label3D:
	var sub := Label3D.new()
	sub.text = text
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.fixed_size = true
	sub.pixel_size = tag.pixel_size
	sub.font_size = maxi(int(round(tag.font_size * SUB_SCALE)), 12)
	sub.outline_size = 6
	sub.modulate = color
	sub.no_depth_test = false
	sub.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sub.visible = tag.visible
	tag.add_child(sub)
	tag.set_meta("np_sub", sub)
	return sub


## Keeps the subtitle glued under its plate (pure: `lift_px` is the plate's offset.y in its own label pixels).
static func place_subtitle(tag: Label3D) -> void:
	if tag == null:
		return
	if not tag.has_meta("np_sub"):
		return
	var sub := tag.get_meta("np_sub") as Label3D
	if sub == null or not is_instance_valid(sub):
		return
	sub.visible = tag.visible
	sub.layers = tag.layers
	sub.transparency = tag.transparency
	sub.pixel_size = tag.pixel_size
	sub.visibility_range_end = tag.visibility_range_end
	sub.visibility_range_end_margin = tag.visibility_range_end_margin
	sub.visibility_range_fade_mode = tag.visibility_range_fade_mode
	# below the plate by half of each line's height (+ a small gap), in label pixels
	sub.offset.y = tag.offset.y - (tag.font_size * 0.5 + sub.font_size * 0.5 + 6.0)


static func set_suppressed(tree: SceneTree, on: bool) -> void:
	if on == suppressed:
		return
	suppressed = on
	tree.call_group("nameplate", "set_visible", not on)
	for t in tree.get_nodes_in_group("nameplate"):
		place_subtitle(t as Label3D)



## 1 inside the near zone, easing to 0 at `max_dist` (the plate's own cap); pure.
static func fade_alpha(dist: float, max_dist: float) -> float:
	return clampf((max_dist - dist) / FADE_LEN, 0.0, 1.0)


## rows: [{id, dist}] -> the ids of the `n` nearest (stable for equal distances). Pure.
static func nearest_ids(rows: Array, n := MAX_SHOWN) -> Array:
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	var out: Array = []
	for r: Dictionary in sorted:
		if out.size() >= n:
			break
		out.append(r["id"])
	return out


## pixel_size that makes `font_size` text exactly a whole number of on-screen pixels tall (>= MIN_PX scaled to the
## viewport height) for a fixed_size label seen through a camera with vertical `fov_deg`. Pure.
static func snapped_pixel_size(font_size: int, viewport_h: float, fov_deg: float) -> float:
	var px_per_unit := viewport_h / (2.0 * tan(deg_to_rad(fov_deg) * 0.5))
	var want := maxf(MIN_PX * viewport_h / 720.0, font_size * PX * px_per_unit)
	return roundf(want) / (float(font_size) * px_per_unit)


## True when the screen point lies inside any of the rects (each grown by SIGN_MARGIN). Pure.
static func hidden_by_sign(at: Vector2, rects: Array) -> bool:
	for r: Rect2 in rects:
		if r.grow(SIGN_MARGIN).has_point(at):
			return true
	return false


## Screen pixels to lift a plate at `at` so it clears every board rectangle (sits just above the top edge of the one it
## overlaps), but never above `min_y` (the top bar); 0 when it is already clear. Pure. A plate must never vanish just because its owner stands in front of a board.
static func sign_lift(at: Vector2, rects: Array, min_y := -INF, max_lift := MAX_LIFT) -> float:
	var lift := 0.0
	for r: Rect2 in rects:
		var g := r.grow(SIGN_MARGIN)
		if g.has_point(at):
			lift = maxf(lift, at.y - (g.position.y - 16.0))
	# Capped: a plate in front of a tall board is nudged up (still legible, still apart from a second plate on the same body)
	# rather than flung to the top of the screen over the compass.
	return minf(minf(lift, max_lift), maxf(at.y - min_y, 0.0))


## The 10 Hz pass: distance fade, nearest-N cull (layers = 0 hides without touching `visible`, which monsters and
## villagers drive themselves), pixel snap, town-board avoidance.
static func refresh(tree: SceneTree, cam: Camera3D) -> void:
	if tree == null or cam == null or not cam.is_inside_tree():
		return
	var plates := tree.get_nodes_in_group("nameplate")
	if plates.is_empty():
		return
	var vp := cam.get_viewport()
	var vh := vp.get_visible_rect().size.y
	var cp := cam.global_position
	var rows: Array = []
	for n in plates:
		var t := n as Label3D
		if t == null or not t.is_inside_tree():
			continue
		rows.append({"id": t.get_instance_id(), "dist": cp.distance_to(t.global_position)})
	var keep := nearest_ids(rows.filter(func(r: Dictionary) -> bool:
		var t := instance_from_id(int(r["id"])) as Label3D
		return t != null and t.visible and float(r["dist"]) < float(t.get_meta("np_max", MAX_DIST)) \
			and not (t.get_parent() != null and bool(t.get_parent().get_meta("np_hide", false)))), MAX_SHOWN)
	var rects: Array = []
	for sgn in tree.get_nodes_in_group("world_sign"):
		var h := sgn as Node3D
		if h == null or not h.has_meta("sign_rect"):
			continue
		var rr: Rect2 = h.get_meta("sign_rect")
		var pts := PackedVector2Array()
		var ok := true
		for c: Vector2 in [rr.position, rr.position + Vector2(rr.size.x, 0), rr.end, rr.position + Vector2(0, rr.size.y)]:
			var w := h.global_transform * Vector3(c.x, c.y, 0.0)
			if cam.is_position_behind(w):
				ok = false
				break
			pts.append(cam.unproject_position(w))
		if ok:
			var box := Rect2(pts[0], Vector2.ZERO)
			for pt in pts:
				box = box.expand(pt)
			rects.append(box)
	for r: Dictionary in rows:
		var t := instance_from_id(int(r["id"])) as Label3D
		if t == null:
			continue
		var d := float(r["dist"])
		var show := keep.has(r["id"]) and not cam.is_position_behind(t.global_position)
		var owner_node := t.get_parent()
		if show and owner_node != null and bool(owner_node.get_meta("np_hide", false)):
			show = false      # this owner already wears a threat plate (ui/threat_plates.gd)
		var lift := 0.0
		if show and not rects.is_empty():
			lift = sign_lift(cam.unproject_position(t.global_position), rects, 84.0 * vh / 720.0, MAX_LIFT * vh / 720.0)
		var a := fade_alpha(d, float(t.get_meta("np_max", MAX_DIST))) if show else 0.0
		t.layers = 1 if a > 0.02 else 0
		t.transparency = 1.0 - a
		t.pixel_size = snapped_pixel_size(t.font_size, vh, cam.fov)
		# Label3D.offset is in label pixels; a fixed_size label shows one label pixel as (pixel_size * px_per_unit) screen pixels.
		t.offset.y = lift / (t.pixel_size * vh / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))) if lift > 0.0 else 0.0
		place_subtitle(t)
