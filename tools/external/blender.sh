#!/usr/bin/env bash
# Headless Blender 5.2 with the external add-ons/extensions on the path.
#   tools/external/blender.sh script.py [-- script args]
# Legacy add-ons:  C:\Users\Jonna\Tools\blender-addons\addons\<name>
# Extensions:      C:\Users\Jonna\Tools\blender-ext-headless\user_default  = a directory junction to
#                  %APPDATA%\Blender Foundation\Blender\5.2\extensions\user_default (the official extensions installed
#                  2026-10-28: thebetterbaker, paws_bakery, bake_to_single_material, lod_gen, lodify_optimizer,
#                  texel_density_checker, ivygen, Bagapie, looptools, bool_tool, antlandscape, ...). Module names are
#                  bl_ext.user_default.<id>; --factory-startup does not auto-enable them, so scripts call
#                  addon_utils.enable("bl_ext.user_default.<id>", default_set=True).
# Why a junction and not %APPDATA% directly: with --factory-startup nothing is enabled, and Blender's wheel sync then
# EMPTIES the repo's .local/site-packages (cv2, PIL for the GUI's extensions). The junction gives headless runs their
# own .local next to it, so the GUI install is never touched. Recreate it if missing:
#   cmd /c mklink /J C:\Users\Jonna\Tools\blender-ext-headless\user_default "%APPDATA%\Blender Foundation\Blender\5.2\extensions\user_default"
export BLENDER_USER_SCRIPTS='C:\Users\Jonna\Tools\blender-addons'
if [ -d /c/Users/Jonna/Tools/blender-ext-headless/user_default ]; then
  export BLENDER_USER_EXTENSIONS='C:\Users\Jonna\Tools\blender-ext-headless'
else
  export BLENDER_USER_EXTENSIONS='C:\Users\Jonna\Tools\blender-extensions'   # old location (antlandscape only)
fi
exec "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup -P "$@"
