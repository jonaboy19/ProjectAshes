class_name Terrain3DLook
extends Node
## Gives Terrain3D the world look of the legacy ground shader (phase W3): installs shaders/terrain3d_ground.gdshader as the material's
## shader_override (Terrain3D's default shader + weather wetness, season, snow and Scar Tide corruption) and feeds it Weather.wetness.
## The seasons and the scar mask arrive through RenderingServer global uniforms, exactly as for the legacy terrain.

const SHADER_PATH := "res://shaders/terrain3d_ground.gdshader"
const Weather := preload("res://scripts/world/weather.gd")

var _mat: Terrain3DMaterial
var _sent := -1.0


## Installs the override on `terrain`'s material and returns the driver node (add it to the tree), or null if the shader is missing.
static func apply(terrain: Terrain3D) -> Terrain3DLook:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--t3d_look=off":
			return null
	var shader := load(SHADER_PATH) as Shader
	if shader == null or terrain == null or terrain.material == null:
		return null
	var mat := terrain.material
	mat.shader_override_enabled = true
	mat.shader_override = shader
	var look := Terrain3DLook.new()
	look.name = "Terrain3DLook"
	look._mat = mat
	return look


func _process(_dt: float) -> void:
	var w: float = Weather.wetness
	if absf(w - _sent) > 0.005 or (w == 0.0 and _sent != 0.0):
		_sent = w
		_mat.set_shader_param("wetness", w)
