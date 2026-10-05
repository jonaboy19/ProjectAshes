@tool
extends EditorExportPlugin
## Android/iOS exports only: textures under res://assets/ larger than the cap are
## downscaled (Lanczos, fresh mipmaps) and stored as ETC2 (Android) / ASTC (iOS)
## PortableCompressedTexture2D. The editor and desktop exports keep the imported
## full-size textures, so HIGH/ULTRA on PC stay sharp while a 3 GB phone gets
## 1024 px (4x less VRAM than 2048) and 512 px for small clutter.
## Rules: MAX_PX by default, SMALL_PX for paths in SMALL. HDR/float textures and
## UI are left alone. Change the numbers, then re-export (the export cache keys on
## _get_customization_configuration_hash).

const MAX_PX := 256
const SMALL_PX := 256
const HERO_PX := 1024
## Hero content keeps up to 2K on phones (the art reference is judged up close):
## characters, the hand-painted material set, shared building/foliage atlases.
const HERO := ["res://assets/generated/characters/", "res://assets/incoming/characters/", "res://assets/art/textures/",
	"res://assets/generated/region/textures/", "res://assets/generated/village_tex/"]
## Small props and critters: never seen larger than a few hundred pixels on a phone.
const SMALL := ["res://assets/generated/scan/", "res://assets/incoming/animals/"]
const SKIP := ["res://assets/ui/", "res://assets/generated/app_icon/"]

var _active := false
var _mode := PortableCompressedTexture2D.COMPRESSION_MODE_ETC2
var _count := 0


func _get_name() -> String:
	return "MobileTextureLimit"


func _begin_customize_resources(platform: EditorExportPlatform, features: PackedStringArray) -> bool:
	_active = features.has("android") or features.has("ios")
	_mode = PortableCompressedTexture2D.COMPRESSION_MODE_ETC2
	if features.has("ios") and ClassDB.class_has_integer_constant("PortableCompressedTexture2D", "COMPRESSION_MODE_ASTC"):
		_mode = ClassDB.class_get_integer_constant("PortableCompressedTexture2D", "COMPRESSION_MODE_ASTC")
	_count = 0
	return _active


func _get_customization_configuration_hash() -> int:
	return hash("mobile_texture_limit v5 %d %d %d %s %s" % [MAX_PX, SMALL_PX, HERO_PX, str(SMALL), str(HERO)])


func _customize_resource(resource: Resource, path: String) -> Resource:
	if not _active or path == "" or not path.begins_with("res://assets/") or not resource is CompressedTexture2D:
		return null
	for s in SKIP:
		if path.begins_with(s):
			return null
	var cap := MAX_PX
	for s in HERO:
		if path.begins_with(s):
			cap = HERO_PX
	for s in SMALL:
		if path.begins_with(s):
			cap = SMALL_PX
	var tex := resource as CompressedTexture2D
	var w := tex.get_width()
	var h := tex.get_height()
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	var oversize := maxi(w, h) > cap
	if not oversize:
		# Within the cap: VRAM-compressed imports already have an ETC2/ASTC copy.
		# Lossless/lossy imports (most Meshy *_lod_bake.jpg) would ship as PNG/WebP
		# and sit in GPU memory as RGBA8 (4x ETC2): convert those too (2026-10-05,
		# they were ~600 MB of the 1.4 GB APK). Tiny textures (gradients, ramps) stay.
		if img.is_compressed() or maxi(w, h) < 128:
			return null
	if img.is_compressed() and img.decompress() != OK:
		return null
	if img.get_format() >= Image.FORMAT_RF and img.get_format() <= Image.FORMAT_RGBE9995:
		return null                                     # HDR / float: leave as imported
	img.clear_mipmaps()
	if oversize:
		var k := float(cap) / float(maxi(w, h))
		img.resize(maxi(1, int(round(w * k))), maxi(1, int(round(h * k))), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var normal := img.get_format() == Image.FORMAT_RG8 or _is_normal(path)
	var out := PortableCompressedTexture2D.new()
	out.create_from_image(img, _mode, normal)
	_count += 1
	return out


func _end_customize_resources() -> void:
	if _active:
		print("MobileTextureLimit: %d textures capped for mobile" % _count)


static func _is_normal(path: String) -> bool:
	var f := path.get_file().to_lower()
	return f.contains("normal") or f.contains("_nor_") or f.contains("_nor.")
