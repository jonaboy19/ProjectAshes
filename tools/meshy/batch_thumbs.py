"""Batch thumbnail + stats for many GLBs (triage).

Usage: blender -b --python tools/meshy/batch_thumbs.py -- <out_dir> <res_px> <a.glb> [<b.glb> ...]
Writes <out_dir>/<stem>.png (one 3/4 view, neutral light) and appends a JSON line
{stem, tris, dims, tex} to <out_dir>/stats_<pid>.jsonl.
"""
import bpy, sys, math, mathutils, os, json

args = sys.argv[sys.argv.index("--") + 1:]
out_dir, res, files = args[0], int(args[1]), args[2:]
os.makedirs(out_dir, exist_ok=True)
statf = open(os.path.join(out_dir, f"stats_{os.getpid()}.jsonl"), "a")

for f in files:
    stem = os.path.splitext(os.path.basename(f))[0]
    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sc = bpy.context.scene
        bpy.ops.import_scene.gltf(filepath=f)
        ms = [o for o in sc.objects if o.type == 'MESH']
        tris = 0
        for o in ms:
            o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
        pts = [o.matrix_world @ mathutils.Vector(c) for o in ms for c in o.bound_box]
        mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
        mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
        ctr = (mn + mx) / 2; rad = (mx - mn).length / 2
        texsz = max([max(i.size) for i in bpy.data.images] + [0])
        w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
        bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.8, 0.85, 0.92, 1); bg.inputs[1].default_value = 1.0
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sun.data.energy = 3.0
        sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(sun)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
        cam.data.lens = 50
        eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
        sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in eng else 'BLENDER_EEVEE_NEXT'
        sc.render.resolution_x = res; sc.render.resolution_y = res
        sc.view_settings.view_transform = 'Standard'
        a = math.radians(-35); dist = rad * 3.0
        cam.location = ctr + mathutils.Vector((math.sin(a) * dist, -math.cos(a) * dist, rad * 0.9))
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, stem + ".png")
        bpy.ops.render.render(write_still=True)
        statf.write(json.dumps(dict(stem=stem, tris=tris, dims=[round(d, 3) for d in (mx - mn)], tex=texsz)) + "\n"); statf.flush()
        print("OK", stem, tris)
    except Exception as e:
        print("FAIL", stem, e)
        statf.write(json.dumps(dict(stem=stem, error=str(e))) + "\n"); statf.flush()
