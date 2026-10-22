#!/usr/bin/env bash
# Headless Blender 5.2 with the external add-ons/extensions on the path.
#   tools/external/blender.sh script.py [-- script args]
# Legacy add-ons:  C:\Users\Jonna\Tools\blender-addons\addons\<name>
# Extensions:      C:\Users\Jonna\Tools\blender-extensions\user_default\<id>  (module bl_ext.user_default.<id>)
export BLENDER_USER_SCRIPTS='C:\Users\Jonna\Tools\blender-addons'
export BLENDER_USER_EXTENSIONS='C:\Users\Jonna\Tools\blender-extensions'
exec "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P "$@"
