"""Prepare reusable CC0 combat meshes. One-time Blender conversion, not runtime."""
import bpy, json, math
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'content/models/realism'
import sys
sys.path.insert(0,str(ROOT/'tools'))
legacy={'ar_a4':'m4','ar_k47':'ak47','ar_b56':'l85','lmg_l762':'g3a3','dmr_d14':'dragunov','sniper_s90':'mosin9130','pistol_p45':'m1911'}
rows=json.loads((ROOT/'content/asset_manifest.json').read_text())['assets']
report={}
for weapon_id,entry in rows.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path=ROOT/'.tools/realism-source/converted'/(legacy[weapon_id]+'.glb') if weapon_id in legacy else ROOT/entry['path']
    bpy.ops.import_scene.gltf(filepath=str(path))
    objects=list(bpy.context.scene.objects);meshes=[o for o in objects if o.type=='MESH']
    for rig in [o for o in objects if o.type=='ARMATURE']:
        rig.animation_data_clear();rig.data.pose_position='REST'
    bpy.context.view_layer.update()
    # Bake skinning and object transforms into the static weapon vertices. A
    # transformed armature can otherwise cancel its parent normalization in
    # glTF, so the drawn gun and its AABB disagree (especially the AK model).
    depsgraph=bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        world=obj.matrix_world.copy()
        mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph),depsgraph=depsgraph)
        mesh.transform(world)
        obj.modifiers.clear();obj.parent=None;obj.matrix_world=Matrix.Identity(4);obj.data=mesh
    for obj in objects:
        if obj not in meshes:bpy.data.objects.remove(obj,do_unlink=True)
    objects=meshes
    points=[v.co for o in meshes for v in o.data.vertices]
    lower=Vector([min(p[a] for p in points) for a in range(3)]);upper=Vector([max(p[a] for p in points) for a in range(3)])
    axis=max(range(2),key=lambda a:upper[a]-lower[a]);length=upper[axis]-lower[axis]
    all_points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
    other=[a for a in range(3) if a!=axis]
    def end_area(sign):
        subset=[p for p in all_points if (p[axis]<lower[axis]+length*.14 if sign<0 else p[axis]>upper[axis]-length*.14)]
        return math.prod(max(p[a] for p in subset)-min(p[a] for p in subset)+.001 for a in other)
    sign=-1 if end_area(-1)<end_area(1) else 1
    # The inspected Quaternius pack uses +X for every muzzle. Folding stocks
    # are thinner than some SMG barrels, so area alone reverses those models.
    if weapon_id not in legacy:sign=1
    # The muzzle points +Y in Blender, becoming -Z in glTF/Godot.
    desired=Vector((0,1,0));current=Vector((sign,0,0)) if axis==0 else Vector((0,sign,0))
    turn=current.rotation_difference(desired).to_matrix().to_4x4()
    transform=Matrix.Scale(1/length,4)@turn@Matrix.Translation(-(lower+upper)*.5)
    if weapon_id=='pistol_p45':transform=Matrix.Rotation(-math.pi/2,4,'Y')@transform
    for obj in meshes:obj.data.transform(transform)
    for obj in meshes:
        bpy.context.view_layer.objects.active=obj
        bevel=obj.modifiers.new('Machined edge bevel','BEVEL');bevel.width=.0015;bevel.segments=2;bevel.limit_method='ANGLE';bevel.angle_limit=.65
        bevel.affect='EDGES'
        try:bpy.ops.object.modifier_apply(modifier=bevel.name)
        except RuntimeError:obj.modifiers.remove(bevel)
        for face in obj.data.polygons:face.use_smooth=True
        normal=obj.modifiers.new('Weighted surface normals','WEIGHTED_NORMAL');normal.keep_sharp=True;normal.weight=40
        try:bpy.ops.object.modifier_apply(modifier=normal.name)
        except RuntimeError:obj.modifiers.remove(normal)
        for material in obj.data.materials:
            if not material:continue
            if weapon_id in legacy:
                old=material.diffuse_color;wood=old[0]>old[1]*1.15 and old[0]>old[2]*1.25
                if wood:color=(.16,.07,.035,1);metallic=0;name='WeaponWood'
                else:
                    value=max(old[:3]);shade=.13 if value>.4 else (.055 if value>.1 else .025)
                    color=(shade*.92,shade,shade*1.03,1);metallic=.8 if value>.1 else .05;name='WeaponMetal' if metallic>.5 else 'WeaponPolymer'
                material.name=name;material.use_nodes=True
                shader=material.node_tree.nodes.get('Principled BSDF');shader.inputs['Base Color'].default_value=color;shader.inputs['Metallic'].default_value=metallic;shader.inputs['Roughness'].default_value=.46 if metallic>.5 else .75
    out=OUT/(weapon_id+'.glb')
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_apply=False)
    if weapon_id=='dmr_d14':
        from prepare_weapon_optics import prepare
        prepare(out)
    report[weapon_id]={'source':str(path.relative_to(ROOT)),'output':str(out.relative_to(ROOT)),'vertices':sum(len(o.data.vertices) for o in meshes),'muzzle_axis':axis,'muzzle_sign':sign}
# Preserve original skin binds and animation tracks; refine normals in place.
import sys
sys.path.insert(0,str(ROOT/'tools'))
from refine_operator import main as refine_operator
refine_operator()
(ROOT/'.artifacts/refined-art.json').write_text(json.dumps(report,indent=2))
print('REFINED 15 WEAPONS AND ANIMATED OPERATOR',flush=True)
