extends Node
## Quality tiers for "runs on any phone" (autoload `Quality`).
##
## LOW / MEDIUM / HIGH / ULTRA, plus AUTO: at first launch the tier is picked
## from the device (GPU name, renderer, RAM, CPU cores), then while playing the
## first ~20 s of frame times step it down if the device can't hold its target.
## The player can override the tier and a 30 fps battery saver in Settings;
## both are saved in user://settings.cfg.
##
## Settings reach the game without touching most game code: every node that
## enters the tree is inspected once (deferred to the end of the frame, after
## its creator has finished configuring it) and adjusted for the tier:
##   SubViewport / root Viewport -> render scale, AA, mesh LOD threshold, anisotropy, omni shadow atlas
##   WorldEnvironment            -> SSAO, SSIL, SDFGI, glow, volumetric fog, SSR
##   DirectionalLight3D          -> shadow on/off, splits, distance
##   OmniLight3D / SpotLight3D   -> shadows, distance fade
##   GeometryInstance3D          -> visibility ranges scaled (props, trees, grass fade)
##   MultiMeshInstance3D         -> grass and undergrowth thinned (terrain scatter only)
##   GPUParticles3D              -> amount ratio
## Game code reads the budgets it owns: `npc_full`, `npc_sprites` (PopulationLOD)
## and `view_radius` (terrain chunks, main.gd).
##
## Launch overrides (not saved, adaptation off): -- --quality=low|medium|high|ultra

signal changed

enum { LOW, MEDIUM, HIGH, ULTRA }
const AUTO := -1
const NAMES := ["Low", "Medium", "High", "Ultra"]
const SETTINGS_PATH := "user://settings.cfg"
## Bump when detect_tier() changes so saved AUTO results are re-detected.
const DETECT_VERSION := 3

## Per-tier settings. `max_3d_height`: the 3D view is rendered at most this many
## pixels tall (0 = native) and upscaled, so a 1440p phone costs no more than a
## 720p one. `range`: visibility-range multiplier. `scatter`: share of grass and
## undergrowth instances kept. `shadow`: 0 off, 1 one low-res split, 2 two splits, 4 four.
const TIERS := [
	{   # LOW: old phones (Mali-G52, Adreno 610, PowerVR, 2-3 GB RAM), Compatibility renderer
		"max_3d_height": 540, "scaling": "bilinear", "fps": 30,
		"shadow": 0, "shadow_size": 1024, "shadow_dist": 0.0, "soft_shadow": 0, "omni_shadows": false,
		"ssao": false, "ssil": false, "sdfgi": false, "glow": false, "vol_fog": false, "ssr": false,
		"lod_threshold": 8.0, "range": 0.55, "scatter": 0.3, "particles": 0.35, "aniso": 0,
		"msaa": 0, "fxaa": false, "npc_full": 6, "npc_sprites": 14, "view_radius": 2, "light_fade": 35.0, "town_far": 420.0,
	},
	{   # MEDIUM: mid-range phones (Adreno 618-650, Mali-G57..G77, Apple A11-A12)
		"max_3d_height": 720, "scaling": "fsr", "fps": 60,
		"shadow": 1, "shadow_size": 2048, "shadow_dist": 55.0, "soft_shadow": 1, "omni_shadows": false,
		"ssao": false, "ssil": false, "sdfgi": false, "glow": false, "vol_fog": false, "ssr": false,
		"lod_threshold": 2.0, "range": 0.75, "scatter": 0.6, "particles": 0.6, "aniso": 1,
		"msaa": 0, "fxaa": false, "npc_full": 10, "npc_sprites": 35, "view_radius": 3, "light_fade": 50.0, "town_far": 600.0,
	},
	{   # HIGH: recent phones (Adreno 7xx, Mali-G710+, Apple A13+), integrated PC GPUs
		"max_3d_height": 900, "scaling": "fsr", "fps": 60,
		"shadow": 2, "shadow_size": 4096, "shadow_dist": 100.0, "soft_shadow": 2, "omni_shadows": true,
		"ssao": true, "ssil": false, "sdfgi": false, "glow": true, "vol_fog": false, "ssr": false,
		"lod_threshold": 1.0, "range": 1.0, "scatter": 1.0, "particles": 1.0, "aniso": 2,
		"msaa": 0, "fxaa": true, "npc_full": 16, "npc_sprites": 55, "view_radius": 4, "light_fade": 80.0, "town_far": 0.0,
	},
	{   # ULTRA: desktop GPUs; the full Forward+ look the game was lit for
		"max_3d_height": 0, "scaling": "bilinear", "fps": 0,
		"shadow": 4, "shadow_size": 4096, "shadow_dist": 140.0, "soft_shadow": 3, "omni_shadows": true,
		"ssao": true, "ssil": true, "sdfgi": true, "glow": true, "vol_fog": true, "ssr": false,
		"lod_threshold": 1.0, "range": 1.0, "scatter": 1.0, "particles": 1.0, "aniso": 3,
		"msaa": 2, "fxaa": true, "npc_full": 20, "npc_sprites": 70, "view_radius": 5, "light_fade": 0.0, "town_far": 0.0,
	},
]

## Saved choice: AUTO or a tier.
var choice := AUTO
## Tier in effect.
var tier := HIGH
var battery_saver := false
## The tier AUTO settled on (saved so the next launch starts there).
var auto_tier := -1
var detected_reason := ""

# Budgets read by game code.
var npc_full := 24
var npc_sprites := 300
var view_radius := 4

var _forced := false           # --quality on the command line
var _pending: Array[Node] = []
var _flush_queued := false
var _viewports: Array[Viewport] = []
var _envs: Array[WorldEnvironment] = []
var _suns: Array[DirectionalLight3D] = []
# Adaptive AUTO measurement.
var _measuring := false
var _measure_time := 0.0
var _frame_sum := 0.0
var _frame_n := 0
const WARMUP := 4.0
const WINDOW := 16.0


func _ready() -> void:
	_load()
	var forced := _cmdline_tier()
	if forced >= 0:
		_forced = true
		tier = forced
	elif choice == AUTO:
		if auto_tier < 0:
			auto_tier = detect_tier()
			_save()
		tier = auto_tier
	else:
		tier = choice
	get_tree().node_added.connect(_on_node_added)
	_apply_globals()
	get_tree().root.size_changed.connect(_apply_viewports)
	_queue(get_tree().root)
	print("Quality: %s (%s)%s" % [NAMES[tier], "forced" if _forced else ("auto" if choice == AUTO else "chosen"),
		(" - " + detected_reason) if detected_reason != "" else ""])


func value(key: String) -> Variant:
	return TIERS[tier][key]


func tier_name() -> String:
	return NAMES[tier]


func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


# --- Player settings ----------------------------------------------------------------

## Set AUTO (-1) or a tier. Saved; applied immediately.
func set_choice(c: int) -> void:
	choice = c
	if c == AUTO:
		if auto_tier < 0:
			auto_tier = detect_tier()
		_set_tier(auto_tier)
	else:
		_measuring = false
		_set_tier(c)
	_save()


func set_battery_saver(on: bool) -> void:
	battery_saver = on
	_apply_globals()
	_save()


func _set_tier(t: int) -> void:
	tier = clampi(t, LOW, ULTRA)
	_apply_globals()
	_apply_viewports()
	for e in _envs:
		if is_instance_valid(e):
			_apply_env(e)
	for s in _suns:
		if is_instance_valid(s):
			_apply_sun(s)
	# Re-apply ranges, scatter and particles to everything already in the world.
	_queue_tree(get_tree().root)
	changed.emit()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	choice = int(cf.get_value("graphics", "choice", AUTO))
	auto_tier = int(cf.get_value("graphics", "auto_tier", -1))
	if int(cf.get_value("graphics", "detect_version", 0)) != DETECT_VERSION:
		auto_tier = -1
	battery_saver = bool(cf.get_value("graphics", "battery_saver", false))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)     # keep other sections
	cf.set_value("graphics", "choice", choice)
	cf.set_value("graphics", "auto_tier", auto_tier)
	cf.set_value("graphics", "detect_version", DETECT_VERSION)
	cf.set_value("graphics", "battery_saver", battery_saver)
	cf.save(SETTINGS_PATH)


func _cmdline_tier() -> int:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--quality="):
			var n := arg.substr(10).to_lower()
			for i in NAMES.size():
				if NAMES[i].to_lower() == n:
					return i
	return -1


# --- Device detection -----------------------------------------------------------------

## First-launch guess from the hardware. Conservative: adaptation only steps down.
func detect_tier() -> int:
	var gpu := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var cores := OS.get_processor_count()
	var ram_gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	var screen := DisplayServer.screen_get_size()
	var t := HIGH
	var why := "%s / %s, %d cores, %.1f GB, %dx%d, %s" % [gpu, vendor, cores, ram_gb, screen.x, screen.y, renderer()]
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		t = _mobile_gpu_tier(gpu)
		if ram_gb > 0.0 and ram_gb < 3.2:
			t = mini(t, LOW)
		elif ram_gb > 0.0 and ram_gb < 5.0:
			t = mini(t, MEDIUM)
		if cores > 0 and cores <= 4:
			t = mini(t, LOW)
	else:
		# Desktop: discrete GPU -> ULTRA, integrated -> MEDIUM (adaptation refines it).
		var type := RenderingServer.get_video_adapter_type()
		var g := gpu.to_lower()
		if type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU or g.contains("rtx") or g.contains("radeon rx") or g.contains("arc a"):
			t = ULTRA
		elif type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			t = MEDIUM
		else:
			t = HIGH if ram_gb >= 8.0 else MEDIUM
	if renderer() == "gl_compatibility":
		# The fallback renderer: an old phone GPU/driver, or a desktop without Vulkan.
		t = LOW if _is_mobile() else mini(t, MEDIUM)
	detected_reason = why
	return t


## GPU family -> tier. Unknown GPUs get MEDIUM (and adaptation fixes the rest).
static func _mobile_gpu_tier(gpu: String) -> int:
	var g := gpu.to_lower()
	var num := _first_number(g)
	if g.contains("adreno"):
		if num >= 730:
			return HIGH
		if num >= 640 or (num >= 700 and num < 730):
			return MEDIUM
		return LOW                                  # 5xx, 610, 612, 616, 618-620 mid-low
	if g.contains("immortalis"):
		return HIGH
	if g.contains("mali"):
		if g.contains("mali-g7") and num >= 710:
			return HIGH                             # G710, G715, G720
		if num >= 57 and num < 200:
			return MEDIUM                           # G57, G68, G72, G76, G77, G78
		if num >= 610:
			return MEDIUM                           # G610, G615
		return LOW                                  # G31, G51, G52, T8xx, 4xx
	if g.contains("apple"):
		# "Apple A15 GPU", "Apple M1"
		if g.contains("apple m"):
			return HIGH
		if num >= 13:
			return HIGH
		return MEDIUM
	if g.contains("xclipse"):
		return HIGH
	if g.contains("powervr") or g.contains("sgx") or g.contains("vivante") or g.contains("tegra"):
		return LOW
	return MEDIUM


static func _first_number(s: String) -> int:
	var digits := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	return int(digits) if digits != "" else 0


# --- Adaptive AUTO -----------------------------------------------------------------------

## Called once the world is playable (after loading). In AUTO mode, measures the
## frame time for ~20 s and steps the tier down while the target isn't held.
func start_adaptive() -> void:
	if _forced or choice != AUTO or tier <= _adapt_floor():
		return
	_measuring = true
	_measure_time = 0.0
	_frame_sum = 0.0
	_frame_n = 0


func _process(delta: float) -> void:
	if not _measuring:
		return
	_measure_time += delta
	if _measure_time < WARMUP:
		return
	if delta < 0.5:           # ignore loading hitches and pauses
		_frame_sum += delta
		_frame_n += 1
	if _measure_time < WARMUP + WINDOW or _frame_n < 30:
		return
	var avg_fps := _frame_n / maxf(_frame_sum, 0.001)
	var target := float(_target_fps())
	if avg_fps < target * 0.85 and tier > _adapt_floor():
		print("Quality: %.1f fps avg at %s (target %d) -> stepping down" % [avg_fps, NAMES[tier], int(target)])
		auto_tier = tier - 1
		_save()
		_set_tier(auto_tier)
		_measuring = tier > _adapt_floor()
		_measure_time = WARMUP * 0.5     # shorter settle after a change
		_frame_sum = 0.0
		_frame_n = 0
	else:
		print("Quality: %.1f fps avg at %s, keeping it" % [avg_fps, NAMES[tier]])
		_measuring = false


func _target_fps() -> int:
	var cap := int(Engine.max_fps)
	if cap <= 0:
		cap = 60
	return mini(cap, 60)


# --- Applying -----------------------------------------------------------------------------

func _apply_globals() -> void:
	var fps: int = value("fps")
	if battery_saver:
		fps = 30
	if fps == 0 and (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		fps = 60
	Engine.max_fps = fps
	npc_full = value("npc_full")
	npc_sprites = value("npc_sprites")
	view_radius = value("view_radius")
	RenderingServer.directional_shadow_atlas_set_size(int(value("shadow_size")), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(value("soft_shadow"))
	RenderingServer.positional_soft_shadow_filter_set_quality(value("soft_shadow"))


func _on_node_added(n: Node) -> void:
	if n is Viewport or n is WorldEnvironment or n is Light3D or n is GeometryInstance3D:
		_pending.append(n)
		if not _flush_queued:
			_flush_queued = true
			_flush.call_deferred()


func _queue(n: Node) -> void:
	_on_node_added(n)


func _queue_tree(root: Node) -> void:
	_queue(root)
	for c in root.find_children("*", "", true, false):
		_queue(c)


func _flush() -> void:
	_flush_queued = false
	var list := _pending
	_pending = []
	for n in list:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if n is Viewport:
			if not _viewports.has(n):
				_viewports.append(n)
				var vp := n as Viewport
				vp.size_changed.connect(func() -> void: _apply_viewport(vp))
			_apply_viewport(n)
		elif n is WorldEnvironment:
			if not _envs.has(n):
				_envs.append(n)
			_apply_env(n)
		elif n is DirectionalLight3D:
			if not _suns.has(n):
				_suns.append(n)
			_apply_sun(n)
		elif n is Light3D:
			_apply_local_light(n)
		elif n is GeometryInstance3D:
			_apply_geometry(n)


func _apply_viewports() -> void:
	for v in _viewports:
		if is_instance_valid(v):
			_apply_viewport(v)


func _apply_viewport(v: Viewport) -> void:
	var compat := renderer() == "gl_compatibility"
	if v == get_tree().root and get_tree().root.find_children("*", "SubViewport", true, false).size() > 0:
		# The world renders in main.gd's SubViewport; the root only draws UI over it.
		# (No FXAA over the text, no MSAA buffers for an empty 3D pass.)
		v.msaa_3d = Viewport.MSAA_DISABLED
		v.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		v.positional_shadow_atlas_size = 0
		return
	var h: float = v.get_visible_rect().size.y if v == get_tree().root else float((v as SubViewport).size.y) if v is SubViewport else 0.0
	var max_h: int = value("max_3d_height")
	var scale := 1.0
	if max_h > 0 and h > 0.0:
		scale = clampf(max_h / h, 0.4, 1.0)
	v.scaling_3d_scale = scale
	if value("scaling") == "fsr" and not compat and scale < 0.99:
		v.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		v.fsr_sharpness = 0.4
	else:
		v.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	v.mesh_lod_threshold = value("lod_threshold")
	v.anisotropic_filtering_level = value("aniso")
	var msaa: int = value("msaa")
	v.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(msaa, 0, 3)] if msaa > 0 else Viewport.MSAA_DISABLED
	v.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if value("fxaa") and not compat else Viewport.SCREEN_SPACE_AA_DISABLED
	v.positional_shadow_atlas_size = 2048 if value("omni_shadows") else 0


func _apply_env(we: WorldEnvironment) -> void:
	var env := we.environment
	if env == null:
		return
	var fwd := renderer() == "forward_plus"
	env.ssao_enabled = value("ssao") and fwd
	env.ssil_enabled = value("ssil") and fwd
	env.sdfgi_enabled = value("sdfgi") and fwd
	env.volumetric_fog_enabled = value("vol_fog") and fwd
	env.volumetric_fog_sky_affect = 0.0   # default 1.0 greys out a clear sky on Ultra
	env.ssr_enabled = value("ssr") and fwd
	env.glow_enabled = value("glow")
	if not env.has_meta("q_fog"):
		env.set_meta("q_fog", env.fog_density)
	var fog: float = env.get_meta("q_fog")
	# Without volumetric fog, plain depth fog carries the aerial perspective: a touch denser.
	env.fog_density = fog if value("vol_fog") else maxf(fog, 0.0009)


func _apply_sun(sun: DirectionalLight3D) -> void:
	var shadow: int = value("shadow")
	if not sun.has_meta("q_shadow"):
		sun.set_meta("q_shadow", sun.shadow_enabled)
	sun.shadow_enabled = shadow > 0 and bool(sun.get_meta("q_shadow"))
	if shadow > 0:
		sun.directional_shadow_mode = {1: DirectionalLight3D.SHADOW_ORTHOGONAL,
			2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS}.get(shadow, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
		sun.directional_shadow_max_distance = value("shadow_dist")


func _apply_local_light(l: Light3D) -> void:
	if not l.has_meta("q_shadow"):
		l.set_meta("q_shadow", l.shadow_enabled)
	l.shadow_enabled = bool(l.get_meta("q_shadow")) and value("omni_shadows")
	var fade: float = value("light_fade")
	l.distance_fade_enabled = fade > 0.0
	if fade > 0.0:
		l.distance_fade_begin = fade
		l.distance_fade_length = fade * 0.25
		l.distance_fade_shadow = minf(fade, 30.0)


func _apply_geometry(g: GeometryInstance3D) -> void:
	var mul: float = value("range")
	# Visibility ranges: remember the author's values once, then scale them.
	if not g.has_meta("q_range"):
		var town := g is MultiMeshInstance3D and _under(g, "SettlementBuilder")
		if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0 or town:
			g.set_meta("q_range", Vector4(g.visibility_range_begin, g.visibility_range_begin_margin, g.visibility_range_end, g.visibility_range_end_margin))
			g.set_meta("q_town", town)
	if g.has_meta("q_range"):
		_set_ranges(g, g.get_meta("q_range"), mul)
		var far: float = value("town_far")
		if g.get_meta("q_town", false) and g.visibility_range_end <= 0.0 and far > 0.0:
			# Whole towns (buildings with no range, far LODs) stop at the fog line on
			# LOW/MEDIUM: from Ashford the capital's ~40 buildings were 600k tris.
			g.visibility_range_end = far
			g.visibility_range_end_margin = far * 0.15
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_small_shadow(g)
	if g is MultiMeshInstance3D:
		_thin_scatter(g as MultiMeshInstance3D)
	elif g is GPUParticles3D:
		(g as GPUParticles3D).amount_ratio = value("particles")
	elif g is CPUParticles3D:
		var cp := g as CPUParticles3D
		if not cp.has_meta("q_amount"):
			cp.set_meta("q_amount", cp.amount)
		cp.amount = maxi(1, int(int(cp.get_meta("q_amount")) * float(value("particles"))))


static func _set_ranges(g: GeometryInstance3D, base: Vector4, mul: float) -> void:
	g.visibility_range_begin = base.x * mul
	g.visibility_range_begin_margin = base.y * mul
	g.visibility_range_end = base.z * mul
	g.visibility_range_end_margin = base.w * mul


## Grass and undergrowth in terrain chunks: keep a share of the instances.
## (Instances are in random order, so a prefix is an even thinning.)
func _thin_scatter(mmi: MultiMeshInstance3D) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null:
		return
	if not mmi.has_meta("q_scatter"):
		if mm.visible_instance_count != -1:
			return                  # managed by its owner (e.g. PopulationLOD sprites)
		var box := mm.mesh.get_aabb()
		if maxf(maxf(box.size.x, box.size.z), box.size.y) >= 3.5 or not _under_terrain(mmi):
			return
		mmi.set_meta("q_scatter", true)
	var keep: float = value("scatter")
	mm.visible_instance_count = -1 if keep >= 0.999 else int(mm.instance_count * keep)


static func _under(n: Node, cls: String) -> bool:
	var p := n.get_parent()
	while p != null:
		if p.get_script() and p.get_script().get_global_name() == cls:
			return true
		p = p.get_parent()
	return false


static func _under_terrain(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is TerrainStreamer:
			return true
		p = p.get_parent()
	return false


static func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Lowest tier adaptation may step down to. A desktop discrete GPU keeps HIGH:
## there the limit is usually the CPU (simulation, draw submission), which
## LOW's 3D settings wouldn't fix, and the player can still pick lower by hand.
func _adapt_floor() -> int:
	if not _is_mobile() and RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return HIGH
	return LOW


## Props under ~1 m (crates, buckets, flowers, clutter) stop casting sun shadows
## below ULTRA: a shadow-map pass for each of them costs more than it shows.
func _small_shadow(g: GeometryInstance3D) -> void:
	if not g.has_meta("q_cast"):
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			mesh = (g as MultiMeshInstance3D).multimesh.mesh
		if mesh == null or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return
		var s := mesh.get_aabb().size * (g as Node3D).global_transform.basis.get_scale()
		if maxf(maxf(s.x, s.y), s.z) >= 1.0 or (g is MeshInstance3D and (g as MeshInstance3D).skin != null):
			return
		g.set_meta("q_cast", g.cast_shadow)
	g.cast_shadow = g.get_meta("q_cast") if tier == ULTRA else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
