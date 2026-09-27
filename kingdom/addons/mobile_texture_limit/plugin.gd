@tool
extends EditorPlugin
## Registers the mobile texture export step (see mobile_texture_export.gd).

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/mobile_texture_limit/mobile_texture_export.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
