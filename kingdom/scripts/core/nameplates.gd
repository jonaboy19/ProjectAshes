extends RefCounted
## In-world nameplates (Label3D). Screen-constant (fixed_size, so a plate next to the camera can never
## fill the view), distance-limited, and hidden while a dialogue / menu is open (the HUD sets `suppressed`
## from its 0.1 s poll). Plates registered with `style()` are in group "nameplate"; the villager tag
## (population/villager.gd) reads `suppressed` itself.

## Reference: pixel_size 0.0022 at font 36 is what army/squad.gd's screen-constant banner uses.
const PX := 0.0016
const MAX_DIST := 22.0

static var suppressed := false


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
	tag.add_to_group("nameplate")
	tag.visible = not suppressed
	return tag


static func set_suppressed(tree: SceneTree, on: bool) -> void:
	if on == suppressed:
		return
	suppressed = on
	tree.call_group("nameplate", "set_visible", not on)
