class_name VFX
extends RefCounted
## Magic and martial-arts effects. Every effect is one static call that spawns
## under `parent` (the world node) and frees itself; looping ones return a node
## you pass to VFX.stop(). Built from one 1024 greyscale atlas (CC0 Kenney +
## RPicster sprites, assets/incoming/vfx/) coloured by hot/tint/edge ramps in
## shaders/vfx_*.gdshader, a procedural rune-circle shader and mesh ribbons.
## Mobile friendly: small GPUParticles3D counts (scaled by the Quality autoload),
## additive unshaded materials, tween-driven shader parameters (no per-frame
## GDScript). Low tier drops lights, smoke and secondary layers.
##
## Primitives
##   VFX.slash(world, pos, yaw, tilt, color, radius)     smear sword arc (player combos)
##   VFX.sparks(world, pos, color, count)                hit sparks
##   VFX.flash(world, pos, color, energy, seconds, range) light pop
##   VFX.core(world, pos, color, size, seconds)          glow sprite
##   VFX.shockwave(world, pos, color, radius, seconds)   ground ring
##   VFX.burst(world, ground_pos, element, power)        elemental burst
##   VFX.aura(node, color, height) -> GPUParticles3D     rising qi streaks (free it)
## Spells
##   VFX.magic_circle(world, pos, element, radius, seconds) -> MeshInstance3D  (seconds <= 0: keep)
##   VFX.cast_sigil(world, hand_pos, dir, element, size)
##   VFX.fireball / wind_blade / qi_palm / stone_bullet / qi_bolt / ice_lance / shuriken / sword_qi
##       (world, from, to, power, speed) -> Node3D missile. Flies itself unless the caller moves it;
##       the impact plays wherever it is when freed (technique_caster.gd contract).
##   VFX.water_whip(world, from, to, power) -> float     lash time
##   VFX.earth_spike(world, from, to, power, radius) -> float  line, or ring when from is above to
##   VFX.lightning_chain(world, from, to, power, extra_points) -> float
##   VFX.fire_pillar / whirlwind / earthquake (world, target, radius, seconds)
##   VFX.tidal_ring(world, target, radius); VFX.thunderstorm(world, target, radius, strikes, seconds)
##   VFX.impact(world, pos, element, power)
## Martial
##   VFX.slash_arc(world, pos, yaw, tilt, element, radius, sweep)
##   VFX.impact_frame(world, at, strength, seconds)      screen-space radial lines
##   VFX.afterimage(world, character, color, count, interval, life)  dash ghosts
##   VFX.qi_flames(character, element, height) -> Node3D  looping, VFX.stop() it
##   VFX.heal(world, pos, power)
## Status / story
##   VFX.status(character, "burning"|"frozen"|"shocked"|"poisoned"|"blessed", seconds, height) -> Node3D
##   VFX.naming(world, pos, height) -> float              golden naming spiral
##   VFX.rift(world, pos, radius, seconds) -> Node3D      Rift cracks, tear and motes
##   VFX.stop(fx)                                         fade out any looping effect
##   VFX.showcase(world, origin) -> float                 every effect in a grid
##   VFX.warmup(world)                                    precompile shaders at load (no first-cast hitch)
## Technique ids (data/skills/*.json "vfx", called by technique_caster.gd with
## world, from = chest, to = ground point, radius / power): see the list at the end.

const SHADER := preload("res://shaders/vfx_glow.gdshader")
const K := preload("res://scripts/vfx/vfx_kit.gd")
const Spells := preload("res://scripts/vfx/vfx_spells.gd")
const Martial := preload("res://scripts/vfx/vfx_martial.gd")
const Status := preload("res://scripts/vfx/vfx_status.gd")
const Tech := preload("res://scripts/vfx/vfx_techniques.gd")
const Showcase := preload("res://scripts/vfx/vfx_showcase.gd")

const ELEMENTS := {
	"fire": {"color": Color(1.0, 0.45, 0.12), "up": 5.0, "gravity": 2.5, "spread": 55.0, "speed": 4.0, "count": 60, "size": 0.35, "life": 0.9},
	"water": {"color": Color(0.35, 0.75, 1.0), "up": 6.0, "gravity": -12.0, "spread": 50.0, "speed": 6.0, "count": 70, "size": 0.22, "life": 0.9},
	"wind": {"color": Color(0.85, 1.0, 0.95), "up": 1.0, "gravity": 0.0, "spread": 180.0, "speed": 9.0, "count": 50, "size": 0.18, "life": 0.6},
	"earth": {"color": Color(0.75, 0.55, 0.3), "up": 7.0, "gravity": -16.0, "spread": 35.0, "speed": 7.0, "count": 40, "size": 0.3, "life": 1.1},
	"lightning": {"color": Color(0.7, 0.8, 1.0), "up": 0.0, "gravity": 0.0, "spread": 180.0, "speed": 14.0, "count": 40, "size": 0.12, "life": 0.25},
	"qi": {"color": Color(1.0, 0.85, 0.35), "up": 2.0, "gravity": 1.5, "spread": 180.0, "speed": 3.0, "count": 50, "size": 0.2, "life": 1.0},
}


static func _material(color: Color, shape := 0, energy := 5.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("energy", energy)
	return m


static func _free_after(node: Node, seconds: float) -> void:
	K.free_after(node, seconds)


# --- primitives (original API, new look) ----------------------------------------

## Smear arc in front of `pos`, sweeping over 0.12 s then burning away.
## `tilt` rolls the arc (0 = horizontal slice, ±1.2 = diagonal).
static func slash(parent: Node, pos: Vector3, yaw: float, tilt := 0.0, color := Color(1.0, 0.9, 0.7), radius := 1.5) -> void:
	Martial.slash_arc(parent, pos, yaw, tilt, K.pal_from(color), radius)


static func sparks(parent: Node, pos: Vector3, color := Color(1.0, 0.75, 0.35), count := 24) -> void:
	var p := K.pal_from(color)
	K.emit(parent, pos, {"amount": count, "life": 0.35, "v": Vector2(4.5, 9.0), "spread": 70.0, "gravity": Vector3(0, -14, 0),
		"damping": Vector2(1, 3), "size": Vector2(0.05, 0.35), "stretch": true, "mat": K.sprite_mat(K.DOT, p, 5.0, {"heat": 1.5})})
	K.glow(parent, pos, p, 1.1, 0.16, K.STAR, 4.0)
	flash(parent, pos, color, 1.5, 0.12)


static func flash(parent: Node, pos: Vector3, color: Color, energy := 2.0, seconds := 0.2, light_range := 5.0) -> void:
	K.light(parent, pos, color, energy, seconds, light_range)


## Big soft glowing sprite that swells and fades: the "read from afar" part of a burst.
static func core(parent: Node, pos: Vector3, color: Color, size := 2.5, seconds := 0.5) -> void:
	K.glow(parent, pos, K.pal_from(color), size, seconds)


## Expanding ring on the ground (landing strikes, qi release, spell impacts).
static func shockwave(parent: Node, pos: Vector3, color := Color(1.0, 0.85, 0.4), radius := 4.0, seconds := 0.45) -> void:
	Tech._ring(parent, pos, K.pal_from(color), radius, seconds)


## Elemental burst at a ground position: the building block for martial arts and spells.
static func burst(parent: Node, pos: Vector3, element := "qi", power := 1.0) -> void:
	Spells.impact(parent, pos + Vector3(0, 0.9, 0), element, power)
	if element == "lightning":
		Spells._bolt(parent, pos + Vector3(0, 9, 0), pos, K.pal("lightning"), 0.14, false)


## Rising qi streaks around a character (cultivation, power-up, martial stance).
## Persistent: free it (or VFX.stop it) yourself.
static func aura(node: Node3D, color := Color(1.0, 0.85, 0.35), height := 1.8) -> GPUParticles3D:
	return K.emit(node, node.global_position + Vector3(0, 0.05, 0), {"amount": 36, "life": 1.2, "one_shot": false, "local": true,
		"shape": "ring", "radius": 0.55, "inner": 0.35, "v": Vector2(height * 0.6, height * 1.1), "spread": 8.0,
		"size": Vector2(0.07, 0.55), "stretch": true, "alpha": "inout", "grow": "flat",
		"mat": K.sprite_mat(K.DOT, K.pal_from(color), 3.0, {"heat": 1.3})})


# --- spells ---------------------------------------------------------------------

static func magic_circle(parent: Node, pos: Vector3, element := "qi", radius := 1.6, seconds := 1.4) -> MeshInstance3D:
	return Spells.magic_circle(parent, pos, element, radius, seconds)


static func cast_sigil(parent: Node, pos: Vector3, dir: Vector3, element := "qi", size := 1.0) -> void:
	Spells.cast_sigil(parent, pos, dir, element, size)


## Elemental hit at `pos`. With `target` (the technique caster's melee point) the
## hit lands between the two and adds an impact frame: punches and kicks.
static func impact(parent: Node, pos: Vector3, element := "qi", power := 1.0, target := Vector3.INF) -> void:
	if target.is_finite():
		var at := pos.lerp(Vector3(target.x, pos.y - 0.1, target.z), 0.7)
		Spells.impact(parent, at, element, power * 0.7)
		Martial.impact_frame(parent, at, 0.6, 0.1)
	else:
		Spells.impact(parent, pos, element, power)


static func fireball(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 16.0) -> Node3D:
	return Spells.fireball(parent, from, to, power, speed)


static func wind_blade(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 22.0) -> Node3D:
	return Spells.wind_blade(parent, from, to, power, speed)


static func qi_palm(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 14.0) -> Node3D:
	return Spells.qi_palm(parent, from, to, power, speed)


## Water lash from the hand to `to` (a ground point is lifted to chest height).
static func water_whip(parent: Node, from: Vector3, to: Vector3, power := 1.0) -> float:
	var end := to
	if end.y < from.y - 0.8:
		end.y = from.y - 0.3
	return Spells.water_whip(parent, from, end, power)


static func earth_spike(parent: Node, from: Vector3, to: Vector3, power := 1.0, radius := 2.5) -> float:
	return Spells.earth_spike(parent, from, to, power, radius)


## Bolt from `from` to `to`, then on through `extra` points (0.07 s per hop).
static func lightning_chain(parent: Node, from: Vector3, to: Vector3, power := 1.0, extra: Array = []) -> float:
	return Spells.lightning_chain(parent, from, [to] + extra, power)


static func fire_pillar(parent: Node, target: Vector3, radius := 1.2, seconds := 1.8) -> void:
	Spells.fire_pillar(parent, target, clampf(radius * 0.55, 0.8, 2.0), seconds)


static func whirlwind(parent: Node, target: Vector3, radius := 1.5, seconds := 2.5) -> void:
	Spells.whirlwind(parent, target, clampf(radius * 0.5, 1.0, 2.5), seconds)


static func tidal_ring(parent: Node, target: Vector3, radius := 4.0) -> void:
	Spells.tidal_ring(parent, target, radius)


static func earthquake(parent: Node, target: Vector3, radius := 4.0, seconds := 2.0) -> void:
	Spells.earthquake(parent, target, radius, seconds)


static func thunderstorm(parent: Node, target: Vector3, radius := 4.0, strikes := 5, seconds := 2.0) -> void:
	Spells.thunderstorm(parent, target, radius, strikes, seconds)


# --- martial --------------------------------------------------------------------

static func slash_arc(parent: Node, pos: Vector3, yaw: float, tilt := 0.0, element := "metal", radius := 1.6, sweep := 0.12) -> void:
	Martial.slash_arc(parent, pos, yaw, tilt, K.pal(element), radius, sweep)


static func impact_frame(parent: Node, at: Vector3, strength := 1.0, seconds := 0.12) -> void:
	Martial.impact_frame(parent, at, strength, seconds)


static func afterimage(parent: Node, character: Node3D, color := Color(0.45, 0.8, 1.0), count := 4, interval := 0.05, life := 0.35) -> void:
	Martial.afterimage(parent, character, color, count, interval, life)


static func qi_flames(character: Node3D, element := "qi", height := 1.8) -> Node3D:
	return Martial.qi_flames(character, K.pal(element), height)


static func heal(parent: Node, pos: Vector3, power := 1.0) -> void:
	Martial.heal(parent, pos, power)


# --- status / story -------------------------------------------------------------

static func status(character: Node3D, kind: String, seconds := 0.0, height := 1.7) -> Node3D:
	return Status.status(character, kind, seconds, height)


static func naming(parent: Node, pos: Vector3, height := 1.6) -> float:
	return Status.naming(parent, pos, height)


static func rift(parent: Node, pos: Vector3, radius := 3.0, seconds := 0.0) -> Node3D:
	return Status.rift(parent, pos, radius, seconds)


static func stop(fx: Variant) -> void:
	Status.stop(fx)


static func showcase(parent: Node, origin: Vector3, seconds := 8.0) -> float:
	return Showcase.showcase(parent, origin, seconds)


## Draw every VFX shader once, invisibly, in front of the camera so the first
## real cast doesn't hitch on pipeline compilation. Call once after the world loads.
static func warmup(parent: Node) -> void:
	var cam := parent.get_viewport().get_camera_3d() if parent.get_viewport() else null
	if cam == null:
		return
	var at := cam.global_position - cam.global_basis.z * 3.0
	var p := K.pal("qi")
	var mats: Array[Material] = [K.sprite_mat(K.DOT, p, 3.0, {"particle": false, "fade": 0.0}),
		K.sprite_mat(K.SMOKE_PUFF, p, 1.0, {"particle": false, "mix": true, "fade": 0.0}),
		K.fx_mat(K.SMEAR, p, 3.0, {"fade": 0.0}), K.shader_mat(K.GHOST), Spells._circle_mat("qi")]
	(mats[3] as ShaderMaterial).set_shader_parameter("fade", 0.0)
	(mats[4] as ShaderMaterial).set_shader_parameter("fade", 0.0)
	for m in mats:
		var mi := K.quad(parent, at, m, 0.05)
		K.free_after(mi, 0.25)
	K.emit(parent, at, {"amount": 1, "life": 0.1, "size": 0.01, "mat": K.sprite_mat(K.DOT, p, 0.0)})
	K.emit(parent, at, {"amount": 1, "life": 0.1, "size": 0.01, "stretch": true, "mat": K.sprite_mat(K.DOT, p, 0.0, {"mix": true})})


# --- technique ids (data/skills/*.json) -----------------------------------------
# technique_caster.gd matches arguments by name: world, from (chest), to (ground
# point or target), radius, power. Projectile ids return the missile Node3D.

static func rally(parent: Node, _from: Vector3, to: Vector3, radius := 8.0) -> void:
	Tech.rally(parent, to, radius)


static func war_cry(parent: Node, from: Vector3, to: Vector3, radius := 8.0) -> void:
	Tech.war_cry(parent, from, to, radius)


static func stone_bullet(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 24.0) -> Node3D:
	return Tech.stone_bullet(parent, from, to, power, speed)


static func stone_skin(parent: Node, _from: Vector3, to: Vector3) -> void:
	Tech.stone_skin(parent, to)


static func quake(parent: Node, _from: Vector3, to: Vector3, radius := 6.0) -> void:
	Spells.earthquake(parent, to, minf(radius, 7.0), 2.0)


static func stone_wall(parent: Node, from: Vector3, to: Vector3, radius := 6.0) -> void:
	Tech.stone_wall(parent, from, to, radius)


static func leaves(parent: Node, _from: Vector3, to: Vector3, radius := 6.0) -> void:
	Tech.leaves(parent, to, radius)


static func rain(parent: Node, _from: Vector3, to: Vector3, radius := 8.0) -> void:
	Tech.rain(parent, to, radius)


static func vines(parent: Node, _from: Vector3, to: Vector3, radius := 6.0) -> void:
	Tech.vines(parent, to, radius)


static func flame_wave(parent: Node, from: Vector3, to: Vector3, radius := 4.0) -> void:
	Tech.flame_wave(parent, from, to, radius)


static func fire_nova(parent: Node, _from: Vector3, to: Vector3, radius := 6.0) -> void:
	Tech.fire_nova(parent, to, radius)


static func iaido_flash(parent: Node, from: Vector3, to: Vector3, radius := 3.0) -> void:
	Tech.iaido_flash(parent, from, to, radius)


static func sword_arc(parent: Node, from: Vector3, to: Vector3, radius := 3.0, color := Color(0.8, 0.9, 1.0)) -> void:
	Tech.sword_arc(parent, from, to, radius, color)


static func sword_qi(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 24.0) -> Node3D:
	return Tech.sword_qi(parent, from, to, power, speed)


static func lightning_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	Tech.lightning_trail(parent, from, to)


static func thunder_strike(parent: Node, _from: Vector3, to: Vector3, radius := 2.5) -> void:
	Tech.thunder_strike(parent, to, radius)


static func qi_aura(parent: Node, _from: Vector3, to: Vector3) -> void:
	Tech.qi_aura(parent, to)


static func qi_bolt(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 20.0) -> Node3D:
	return Tech.qi_bolt(parent, from, to, power, speed)


static func qi_shield(parent: Node, _from: Vector3, to: Vector3, radius := 3.0) -> void:
	Tech.qi_shield(parent, to, radius)


static func qi_nova(parent: Node, _from: Vector3, to: Vector3, radius := 7.0) -> void:
	Tech.qi_nova(parent, to, radius)


static func shuriken(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 28.0) -> Node3D:
	return Tech.shuriken(parent, from, to, power, speed)


static func smoke_bomb(parent: Node, _from: Vector3, to: Vector3, radius := 4.0) -> void:
	Tech.smoke_bomb(parent, to, radius)


static func shadow_step(parent: Node, from: Vector3, to: Vector3) -> void:
	Tech.shadow_step(parent, from, to)


static func shadow_clone(parent: Node, _from: Vector3, to: Vector3, radius := 4.0) -> void:
	Tech.shadow_clone(parent, to, radius)


static func water_heal(parent: Node, _from: Vector3, to: Vector3, radius := 5.0) -> void:
	Tech.water_heal(parent, to, radius)


static func ice_lance(parent: Node, from: Vector3, to: Vector3, power := 1.0, speed := 26.0) -> Node3D:
	return Tech.ice_lance(parent, from, to, power, speed)


static func water_ring(parent: Node, _from: Vector3, to: Vector3, radius := 12.0) -> void:
	Tech.water_ring(parent, to, radius)


static func tidal_wave(parent: Node, from: Vector3, to: Vector3, radius := 8.0) -> void:
	Tech.tidal_wave(parent, from, to, radius)


static func whirlpool(parent: Node, _from: Vector3, to: Vector3, radius := 4.0) -> void:
	Tech.whirlpool(parent, to, radius)


static func wind_trail(parent: Node, from: Vector3, to: Vector3) -> void:
	Tech.wind_trail(parent, from, to)
