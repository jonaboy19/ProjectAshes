# Collision preview gallery

This small Godot viewer renders the building meshes used by the game with the `BoxShape3D` created by `Assets.building_node()`. The blue wireframe marks the solid collision proxy. It includes Meshy houses, shops, stalls, and major landmarks. This opens only a preview scene; it does not boot the world or modify gameplay scenes.

## Open interactively

From the repository root:

```powershell
& 'C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64.exe' --path kingdom --rendering-driver vulkan --windowed --resolution 1280x800 res://tools_qa/collision_preview/collision_preview.tscn
```

Use left/right arrows to switch assets, drag with the left mouse button to orbit, and Esc to close.

## Generate a browser gallery

```powershell
& 'C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe' --path kingdom --rendering-driver vulkan --windowed --resolution 1280x800 res://tools_qa/collision_preview/collision_preview.tscn -- --capture
```

The capture run writes `docs/qa/collision_preview/index.html` and one PNG per asset. Open the HTML file in a browser. Captures use the production mesh loader and collider builder, so they show the exact static proxy sizes. They do not prove that an actor uses the expected collision layer or that a runtime body is registered; use the gameplay playtest for those checks.
