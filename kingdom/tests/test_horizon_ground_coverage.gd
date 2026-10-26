extends GdUnitTestSuite

const Horizon := preload("res://scripts/region1/region1_horizon.gd")

class FakeTerrain extends Node:
	var _bridge: Terrain3DBridge
	var _chunks: Dictionary = {}
	var focus := Vector3.ZERO

func test_ground_uses_loaded_regions_and_updates_same_count_replacement() -> void:
	var terrain := FakeTerrain.new()
	var bridge := Terrain3DBridge.new()
	terrain._bridge = bridge
	bridge.region_radius = 0
	bridge._regions[Vector2i(0, 0)] = null
	var h := Horizon.new()
	h._terrain = terrain
	h._ground_mat = ShaderMaterial.new()
	h._ground_mat.shader = load("res://shaders/region1/horizon_ground.gdshader")
	h._update_ground_mask(Vector3.ZERO)
	# Origin is region (-2,-2): each 384m region covers six 64m cells.
	assert_float(h._ground_mask_img.get_pixel(12, 12).r).is_equal(1.0)
	assert_float(h._ground_mask_img.get_pixel(17, 17).r).is_equal(1.0)
	assert_float(h._ground_mask_img.get_pixel(18, 12).r).is_equal(0.0)
	bridge._regions.erase(Vector2i.ZERO)
	bridge._regions[Vector2i(1, 0)] = null
	h._update_ground_mask(Vector3.ZERO)
	assert_float(h._ground_mask_img.get_pixel(12, 12).r).is_equal(0.0)
	assert_float(h._ground_mask_img.get_pixel(18, 12).r).is_equal(1.0)
	h.free()
	bridge.free()
	terrain.free()

func test_canopy_membership_updates_without_count_change() -> void:
	var terrain := FakeTerrain.new()
	var a := Node3D.new()
	var b := Node3D.new()
	terrain._chunks[Vector2i.ZERO] = a
	var h := Horizon.new()
	h._terrain = terrain
	h._built = true
	h._ground_mat = ShaderMaterial.new()
	h._blob_mat = ShaderMaterial.new()
	h._mask_tex = ImageTexture.create_from_image(h._mask_img)
	h._process(0.0)
	assert_float(h._mask_img.get_pixel(8, 8).r).is_equal(1.0)
	terrain._chunks.erase(Vector2i.ZERO)
	terrain._chunks[Vector2i(1, 0)] = b
	h._process(0.0)
	assert_float(h._mask_img.get_pixel(8, 8).r).is_equal(0.0)
	assert_float(h._mask_img.get_pixel(9, 8).r).is_equal(1.0)
	h.free()
	a.free()
	b.free()
	terrain.free()
