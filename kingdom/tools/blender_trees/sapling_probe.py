"""Probe the installed tree extensions (blender -b -P sapling_probe.py): operators and Sapling presets."""
import bpy, os, addon_utils
for m in addon_utils.modules():
    n = m.__name__
    if any(k in n for k in ("sapling", "modular_tree", "space_colon", "leaf_gen")):
        print("ADDON", n, addon_utils.check(n))
for cat in ("curve", "mod_tree", "leaf_gen", "object"):
    ops = getattr(bpy.ops, cat, None)
    if ops:
        names = [o for o in dir(ops) if any(k in o.lower() for k in ("tree", "leaf", "sapling"))]
        print("OPS", cat, names)
for root, dirs, files in os.walk(os.path.expandvars(r"%APPDATA%\Blender Foundation\Blender\5.2\extensions")):
    if "presets" in root.lower() and "sapling" in root.lower():
        print("PRESETS", root, files[:40])
