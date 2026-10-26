extends GdUnitTestSuite
## Imported HUD images may be compressed. Both icon paths rasterise them at runtime.

const HudArt := preload("res://scripts/ui/hud_art.gd")


func test_round_face_accepts_imported_compressed_glyph() -> void:
	var icon := HudArt.icon("attack")
	assert_bool(icon != null).is_true()
	var face := HudArt.round_face(128, Color("181510"), icon, false, 0.66)
	assert_bool(face != null).is_true()


func test_bake_accepts_imported_compressed_icon() -> void:
	var icon := HudArt.icon("attack")
	assert_bool(icon != null).is_true()
	var baked := HudArt.bake(icon, 96)
	assert_bool(baked != null).is_true()
