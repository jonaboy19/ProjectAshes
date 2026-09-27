import bpy, os
from mathutils import Vector

def reset(fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    bpy.context.scene.render.fps = fps

def import_new(path):
    before = set(bpy.data.objects); acts = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    sc = bpy.context.scene.objects
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.name.startswith("Icosphere") and o.parent is None:
            new.remove(o); bpy.data.objects.remove(o)
    return [o for o in new], [a for a in bpy.data.actions if a not in acts]

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)

def world_bbox(objs, depsgraph=None):
    pts = []
    for o in objs:
        if depsgraph:
            ev = o.evaluated_get(depsgraph); me = ev.to_mesh()
            pts += [ev.matrix_world @ v.co for v in me.vertices]; ev.to_mesh_clear()
        else:
            pts += [o.matrix_world @ v.co for v in o.data.vertices]
    mn = Vector([min(p[i] for p in pts) for i in range(3)]); mx = Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx

def add_nla(arm, name, action, start=None):
    ad = arm.animation_data or arm.animation_data_create()
    tr = ad.nla_tracks.new(); tr.name = name
    s = int(start if start is not None else action.frame_range[0])
    st = tr.strips.new(name, s, action)
    try:
        if action.slots: st.action_slot = action.slots[0]
    except Exception as e: print("slot warn", e)
    action.name = name
    action.use_fake_user = True
    tr.mute = False
    return tr

def decimate_to(obj, target):
    t = tris(obj)
    if t <= target: return t
    bpy.context.view_layer.objects.active = obj
    for o in bpy.data.objects: o.select_set(o == obj)
    m = obj.modifiers.new("dec", 'DECIMATE'); m.ratio = target / t; m.use_collapse_triangulate = True
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
    return tris(obj)

def cap_images(px):
    for img in bpy.data.images:
        if img.size[0] > px or img.size[1] > px:
            img.scale(min(px, img.size[0]), min(px, img.size[1]))

def export(path, objs):
    for o in bpy.data.objects: o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
        export_image_format='JPEG', export_jpeg_quality=88, export_animation_mode='ACTIONS',
        export_skins=True, export_draco_mesh_compression_enable=False, export_apply=False,
        export_anim_single_armature=True, export_def_bones=False)
    print("EXPORTED", path, os.path.getsize(path)//1024, "KB")
