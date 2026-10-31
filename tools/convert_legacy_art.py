"""One-time, offline conversion of inspected CC0 legacy sources. Run with local Blender.
The release and normal preparation use committed GLBs, never .blend files.
"""
import bpy, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCES=ROOT/'.tools/realism-source'
DEST=ROOT/'content/models/realism'
DEST.mkdir(parents=True,exist_ok=True)
report={}
for name,source in [('arms',SOURCES/'arms/FPS ARMS RIG 1.blend'),*[(p.stem,p) for p in sorted((SOURCES/'smallarms').glob('*.blend'))]]:
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
        objects=[o for o in bpy.context.scene.objects if o.type in {'MESH','ARMATURE'}]
        for o in bpy.context.scene.objects:o.select_set(o in objects)
        meshes=[o for o in objects if o.type=='MESH']
        bones={o.name:[b.name for b in o.data.bones] for o in objects if o.type=='ARMATURE'}
        images=[{'name':i.name,'path':i.filepath,'packed':bool(i.packed_file)} for i in bpy.data.images]
        materials=[{'name':m.name,'color':list(m.diffuse_color)} for m in bpy.data.materials]
        # Old Blender Internal materials do not carry their texture slots into
        # glTF; bind packed/adjacent source images through Principled explicitly.
        if name=='arms':
            image=bpy.data.images.load(str(SOURCES/'arms/new_diff.png'),check_existing=True)
            material=bpy.data.materials.new('AnatomicalSkin');material.use_nodes=True
            shader=material.node_tree.nodes.get('Principled BSDF');shader.inputs['Roughness'].default_value=.68
            tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
            material.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
            for mesh in meshes:
                mesh.data.materials.clear();mesh.data.materials.append(material)
        for mesh in meshes:
            for polygon in mesh.data.polygons:polygon.use_smooth=True
        folder=DEST if name=='arms' else SOURCES/'converted'
        folder.mkdir(parents=True,exist_ok=True)
        out=folder/(name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=True,export_apply=False,export_yup=True)
        report[name]={'source':str(source.relative_to(ROOT)),'output':str(out.relative_to(ROOT)),'meshes':[{ 'name':o.name,'vertices':len(o.data.vertices)} for o in meshes],'bones':bones,'actions':[a.name for a in bpy.data.actions],'images':images,'materials':materials}
        print('CONVERTED',name,json.dumps(report[name]),flush=True)
    except Exception as error:
        report[name]={'error':str(error)};print('CONVERSION FAILED',name,str(error),flush=True)
(ROOT/'.artifacts/legacy-art-inspection.json').write_text(json.dumps(report,indent=2))
