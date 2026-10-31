"""Blender: simplify the project's existing CC0 boulder scan, retaining its UVs."""
import bpy
import bmesh
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'content/models/props/boulder_01/boulder_01_1k.gltf'))
rock = next(obj for obj in bpy.context.scene.objects if obj.type == 'MESH')
# glTF splits vertices at UV/normal seams; weld positions before decimation.
# UVs remain per-loop, so the photographed texture coordinates are retained.
bm = bmesh.new()
bm.from_mesh(rock.data)
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0001)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(rock.data)
bm.free()
rock.data.update()
modifier = rock.modifiers.new('Glacier gameplay LOD', 'DECIMATE')
modifier.ratio = 0.06
modifier.use_collapse_triangulate = True
obj = rock.evaluated_get(bpy.context.evaluated_depsgraph_get())
mesh = obj.to_mesh()
mesh.calc_loop_triangles()
normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
uvs = mesh.uv_layers.active.data
rows = []
for triangle in mesh.loop_triangles:
    for vertex_id, loop_id in zip(triangle.vertices, triangle.loops):
        point = obj.matrix_world @ mesh.vertices[vertex_id].co
        normal = (normal_matrix @ mesh.vertices[vertex_id].normal).normalized()
        uv = uvs[loop_id].uv
        rows.append([point.x, point.z, -point.y, normal.x, normal.z, -normal.y, uv.x, 1-uv.y])
output = root/'.artifacts/glacier_overhaul/moraine_scan.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(rows, separators=(',',':')))
print('MORAINE SCAN LOD:', len(rows)//3, 'triangles')
