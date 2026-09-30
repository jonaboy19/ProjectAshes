#!/bin/bash
# usage: run.sh script.py [args after --]
cd /c/Users/Jonna/Documents/PA_wt_horse/kingdom/tools/anim/horse
timeout 900 "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python "$@" 2>&1 | grep -E "^HX|Error|Traceback|line [0-9]|rror:" | head -60
