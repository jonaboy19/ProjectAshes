extends SceneTree
## Bakes the far-building texture atlas: every BUILDINGS mesh stage that is a single Style G surface with its own atlas
## texture (LOD2/LOD3 and 256 px LOD1) gets a 256 px tile on ONE page, so StaticMerge can fuse houses of different kinds into one
## draw call. Writes res://assets/baked/atlas/town_far.png and town_atlas.json (read by scripts/world/town_atlas.gd).
## Run: godot --headless --path kingdom -s res://tools_qa/baked_quality/bake_town_atlas.gd  then  godot --headless --path kingdom --import
## Re-run after a building GLB / texture changes (runtime checks the source texture name and skips stale entries).
const TownAtlas := preload("res://scripts/world/town_atlas.gd")
const TILE := 256
const GUTTER := 4


func _initialize() -> void:
	await process_frame
	TownAtlas.enabled = false          # inspect the stage meshes with their own textures
	var cls = Assets
	var tex_tile := {}                      # texture path -> tile index
	var entries := {}                       # "key:lodN" -> {src, tex}
	var order: Array = []                   # texture paths in tile order
	for key: String in cls.BUILDINGS:
		var entry: Array = cls.BUILDINGS[key]
		for lod in range(1, entry.size() / 2):
			var k := "%s:lod%d" % [key, lod]
			var m: ArrayMesh = cls.building_mesh(k)
			if m == null:
				continue
			var why := TownAtlas.fold_reject(m)
			if why != "":
				print("skip ", k, ": ", why)
				continue
			var tex := TownAtlas.main_texture(m)
			var path := tex.resource_path
			var big := maxi(tex.get_width(), tex.get_height())
			if lod == 1 and big > TILE:
				print("skip ", k, ": near stage with ", big, " px texture")
				continue
			if not tex_tile.has(path):
				tex_tile[path] = order.size()
				order.append(path)
			entries[k] = {"src": path.get_file(), "tex": path}
	var n := order.size()
	var cols := 8
	var size := 2048
	if n > 64:
		cols = 16
		size = 4096
	if n > cols * cols:
		push_error("atlas overflow: %d textures" % n)
		quit(1)
		return
	var page := Image.create(size, size, false, Image.FORMAT_RGBA8)
	page.fill(Color(0.5, 0.5, 0.5, 1.0))
	var content := TILE - 2 * GUTTER
	for i in n:
		var path: String = order[i]
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null or img.is_empty():
			img = (load(path) as Texture2D).get_image()
			if img.is_compressed():
				img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(content, content, Image.INTERPOLATE_LANCZOS)
		var ox := (i % cols) * TILE
		var oy := (i / cols) * TILE
		for y in TILE:      # content centred in the tile, edge pixels replicated outwards (no bleeding between neighbours at mip levels)
			var sy := clampi(y - GUTTER, 0, content - 1)
			for x in TILE:
				page.set_pixel(ox + x, oy + y, img.get_pixel(clampi(x - GUTTER, 0, content - 1), sy))
	var out := {"page": "res://assets/baked/atlas/town_far.png", "size": size, "tile": TILE, "gutter": GUTTER, "entries": {}}
	for k: String in entries:
		var i: int = tex_tile[entries[k]["tex"]]
		var ox := (i % cols) * TILE + GUTTER
		var oy := (i / cols) * TILE + GUTTER
		out["entries"][k] = {"src": entries[k]["src"], "off": [float(ox) / size, float(oy) / size], "scale": float(content) / size}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/baked/atlas"))
	page.save_png(ProjectSettings.globalize_path(out["page"]))
	var f := FileAccess.open("res://assets/baked/atlas/town_atlas.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	var imp := FileAccess.open(out["page"] + ".import", FileAccess.WRITE)
	imp.store_string(IMPORT % out["page"])
	imp.close()
	print("atlas: %d textures, %d mesh stages, page %d px (%d tiles of %d)" % [n, entries.size(), size, cols * cols, TILE])
	quit()


const IMPORT := """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""
