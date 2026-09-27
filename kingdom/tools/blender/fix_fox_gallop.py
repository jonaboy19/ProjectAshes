"""Remove the fox Run clip's erroneous vertical translation on Tail1.

Source: assets/incoming/animals/quaternius/fox.glb (Quaternius Ultimate Animated
Animals, CC0). This creates a new derived GLB and never edits the source file.

Run with Blender 5.2:
  blender --background --python kingdom/tools/blender/fix_fox_gallop.py -- [src.glb] [dst.glb]
"""

import bpy
import sys
from pathlib import Path


def cli_paths() -> tuple[Path, Path]:
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	repo = Path(__file__).resolve().parents[2]
	source = Path(args[0]).resolve() if args else repo / "assets/incoming/animals/quaternius/fox.glb"
	destination = Path(args[1]).resolve() if len(args) > 1 else repo / "assets/generated/animals/fox_gallop.glb"
	return source, destination


def main() -> None:
	source, destination = cli_paths()
	if not source.is_file():
		raise FileNotFoundError(source)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=str(source))
	run = next((action for action in bpy.data.actions if action.name == "Run"), None)
	if run is None:
		raise RuntimeError("Fox source has no Run action")
	removed = 0
	for layer in run.layers:
		for strip in layer.strips:
			for slot in run.slots:
				bag = strip.channelbag(slot)
				if bag is None:
					continue
				for curve in list(bag.fcurves):
					if curve.data_path == 'pose.bones["Tail1"].location' and curve.array_index == 1:
						bag.fcurves.remove(curve)
						removed += 1
	if removed != 1:
		raise RuntimeError("Expected to remove exactly one Tail1 vertical-translation curve; removed %d" % removed)
	destination.parent.mkdir(parents=True, exist_ok=True)
	bpy.ops.export_scene.gltf(
		filepath=str(destination),
		export_format="GLB",
		export_animations=True,
		export_animation_mode="ACTIONS",
		export_draco_mesh_compression_enable=False,
		export_yup=True,
		export_image_format="JPEG",
		export_jpeg_quality=88,
	)
	print("FOX_GALLOP_DERIVED", source, "->", destination, "tail_curve_removed=1")


if __name__ == "__main__":
	main()
