"""Build the first-person arms from the Mixamo "Swat Guy" soldier (Ch15) that the
third-person characters use, so the hands in view match the soldiers in the world.

Source: the undecimated character FBX in .tools/user-assets/characters/Ch15_nonPBR.fbx
(downloaded by the user for Stream D; never committed). Processing, in the same frame as
tools/blender/ingest_soldier.py (1.8 m tall, facing -Y, Mixamo prefix stripped):
  - keep the two camo sleeves (trimmed near the shoulder, then continued a short way as
    a plain cloth tube whose vertex alpha fades to nothing, so a shoulder pushed
    forward for a long reach dissolves instead of ending in a flat cut), the gloves and
    the glove cuffs; drop the torso, head, legs and the sci-fi exoskeleton bands and
    rods strapped to the sleeves;
  - fold every non-arm bone weight into the upper arm, so moving an arm's root carries
    the whole sleeve rigidly (the IK never stretches skin);
  - subdivide the gloves once so fingers stay round at first-person distance;
  - keep the Mixamo skeleton (shoulder, arm, forearm, hand, finger bones) and skinning;
  - name the two surfaces FP_Sleeve and FP_Glove. Their textures are the team-coloured
    2K maps Stream D bakes for the third-person soldier (body = sleeves, gear = gloves);
    ViewModel builds the materials from content/manifest/characters.json, so the GLB
    carries no images.

Run: python3 tools/dev.py blender tools/blender/build_fp_arms.py
Output: content/models/arms/fp_arms.glb and content/models/arms/arms.json.
"""
import bpy, bmesh, json, math, re
from pathlib import Path
from mathutils import Matrix, Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / ".tools/user-assets/characters/Ch15_nonPBR.fbx"
OUT = ROOT / "content/models/arms"
HEIGHT = 1.8
CUT = .22          # fraction from shoulder joint to elbow where the sleeve is trimmed (above it the UVs stretch)
EXTEND = .1        # metres of plain cloth-coloured sleeve continued back past the cut, so a shoulder pushed
                   # forward for a long reach never shows the sleeve's open end
TEAM_MAPS = ["body_albedo_blue.jpg", "body_albedo_red.jpg"]
SURFACES = {0: "FP_Sleeve", 1: "FP_Glove"}   # Ch15_body -> sleeves, Ch15_body1 -> gloves


def log(*parts): print("[build_fp_arms]", *parts, flush=True)


def strip_prefix(name): return re.sub(r"^mixamorig\d*:", "", name)


def islands(bm):
    bm.faces.ensure_lookup_table()
    seen, result = set(), []
    for face in bm.faces:
        if face.index in seen: continue
        stack, island = [face], []
        seen.add(face.index)
        while stack:
            current = stack.pop(); island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen: seen.add(other.index); stack.append(other)
        result.append(island)
    return result


def normalise(rig, mesh):
    """Same frame as ingest_soldier.normalise_transform: 180 degree turn to face -Y,
    scaled to 1.8 m, transforms applied, soles on the ground."""
    world = mesh.matrix_world.copy(); mesh.parent = None; mesh.matrix_world = world
    turn = Matrix.Rotation(math.pi, 4, "Z")
    for obj in (rig, mesh): obj.matrix_world = turn @ obj.matrix_world
    bpy.context.view_layer.update()
    points = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
    grow = Matrix.Scale(HEIGHT / (max(p.z for p in points) - min(p.z for p in points)), 4)
    for obj in (rig, mesh): obj.matrix_world = grow @ obj.matrix_world
    bpy.context.view_layer.update()
    for obj in (rig, mesh):
        bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    floor = min(v.co.z for v in mesh.data.vertices)
    for obj in (rig, mesh):
        obj.matrix_world = Matrix.Translation((0, 0, -floor)) @ obj.matrix_world
        bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    mesh.parent = rig; mesh.matrix_parent_inverse = Matrix.Identity(4)
    for modifier in mesh.modifiers:
        if modifier.type == "ARMATURE": modifier.object = rig


def head(rig, name): return rig.matrix_world @ rig.data.bones[name].head_local


def keep_arms(rig, mesh):
    """Whole islands only: the sleeve (material 0) beyond the shoulder, and the glove and
    its cuff (material 1) from just above the wrist outward. Everything material 1
    between shoulder and wrist is exoskeleton hardware strapped over the sleeve."""
    bm = bmesh.new(); bm.from_mesh(mesh.data)
    doomed, kept = [], {}
    for island in islands(bm):
        points = [v.co for f in island for v in f.verts]
        centre = sum(points, Vector()) / len(points)
        material = island[0].material_index
        side = "Left" if (centre - head(rig, "LeftArm")).length < (centre - head(rig, "RightArm")).length else "Right"
        shoulder, elbow, wrist = head(rig, side + "Arm"), head(rig, side + "ForeArm"), head(rig, side + "Hand")
        along = lambda p: (p - shoulder).dot((wrist - shoulder).normalized())
        reach = min(along(p) for p in points)
        span = along(wrist)
        is_sleeve = material == 0 and max(along(p) for p in points) > (elbow - shoulder).length and centre.z > 1.1
        is_glove = material == 1 and reach > span - .045 and centre.z > 1.1
        if is_sleeve or is_glove:
            kept[side + ("Sleeve" if is_sleeve else "Glove")] = kept.get(side + ("Sleeve" if is_sleeve else "Glove"), 0) + len(island)
        else:
            doomed.extend(island)
    bmesh.ops.delete(bm, geom=list(set(doomed)), context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(mesh.data); bm.free()
    log("kept islands (faces):", kept)


def cloth_uv(candidates):
    """The candidate UV whose texel sits closest to the sleeve's average colour on both team
    uniform maps, so the plain tube reads as the same cloth in shade."""
    maps = []
    for name in TEAM_MAPS:
        image = bpy.data.images.load(str(ROOT / "content/models/characters/textures" / name))
        width, height = image.size
        pixels = np.empty(width * height * 4, dtype=np.float32); image.pixels.foreach_get(pixels)
        maps.append((pixels.reshape(height, width, 4), width, height))
    def texel(uv, pixels, width, height):
        return pixels[int((uv[1] % 1) * (height - 1)), int((uv[0] % 1) * (width - 1)), :3]
    means = [np.mean([texel(uv, *m) for uv in candidates], axis=0) for m in maps]
    return min(candidates, key=lambda uv: sum(float(np.linalg.norm(texel(uv, *m) - mean)) for m, mean in zip(maps, means)))


def cut_sleeves(rig, mesh):
    """Trim each sleeve near the shoulder, continue it back as a plain cloth tube and close
    the far end, so the open end stays far out of view wherever the shoulder is moved."""
    bm = bmesh.new(); bm.from_mesh(mesh.data)
    uv = bm.loops.layers.uv.active
    deform = bm.verts.layers.deform.verify()
    # Vertex alpha: opaque cloth everywhere except the added tube, which fades out along its
    # length (the sleeve material uses hashed alpha), so a shoulder pushed into view
    # dissolves instead of ending in a flat polygon.
    fade = bm.loops.layers.color.new("Col")
    for face in bm.faces:
        for loop in face.loops: loop[fade] = (1, 1, 1, 1)
    cuts = {}
    # Both bisects first: a tube already growing past the body's midline would otherwise
    # be caught by the opposite side's plane.
    for side in ("Left", "Right"):
        shoulder, elbow = head(rig, side + "Arm"), head(rig, side + "ForeArm")
        axis = (elbow - shoulder).normalized()
        point = shoulder + (elbow - shoulder) * CUT
        near = [g for g in bm.verts[:] + bm.edges[:] + bm.faces[:]
                if (g.co if isinstance(g, bmesh.types.BMVert) else sum((v.co for v in g.verts), Vector()) / len(g.verts)).dot(Vector((1, 0, 0))) * shoulder.x > 0]
        result = bmesh.ops.bisect_plane(bm, geom=near, plane_co=point, plane_no=axis, clear_inner=True)
        cuts[side] = [e for e in result["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_valid and e.is_boundary]
    for side in ("Left", "Right"):
        cut_edges = cuts[side]
        if not cut_edges: continue
        shoulder, elbow = head(rig, side + "Arm"), head(rig, side + "ForeArm")
        axis = (elbow - shoulder).normalized()
        cloth = cloth_uv([l[uv].uv.copy() for e in cut_edges for f in e.link_faces for l in f.loops])

        def extend(edges, distance, blend):
            """One more ring of sleeve `distance` back along the arm; its fabric fades from the
            edge's own UVs to the plain dark cloth over this single strip."""
            before = set(bm.verts)
            geom = bmesh.ops.extrude_edge_only(bm, edges=edges)["geom"]
            fresh = [g for g in geom if isinstance(g, bmesh.types.BMVert) and g not in before]
            origin = {}
            for vertex in fresh:
                origin[vertex] = next(e.other_vert(vertex) for e in vertex.link_edges if e.other_vert(vertex) not in fresh)
                for group, weight in origin[vertex][deform].items(): vertex[deform][group] = weight
            bmesh.ops.translate(bm, verts=fresh, vec=-axis * distance)
            wall = [g for g in geom if isinstance(g, bmesh.types.BMFace)]
            for face in wall:
                old = [v for v in face.verts if v not in fresh]
                joined = bm.edges.get(old)
                sleeve = next((f for f in joined.link_faces if f not in wall), None) if joined else None
                for loop in face.loops:
                    if loop.vert in fresh or not blend or sleeve is None: loop[uv].uv = cloth
                    else:
                        match = next((l for l in sleeve.loops if l.vert == loop.vert), None)
                        loop[uv].uv = match[uv].uv if match else cloth
                centre = face.calc_center_median()
                outward = (centre - shoulder) - axis * (centre - shoulder).dot(axis)
                if face.normal.dot(outward) < 0: face.normal_flip()
                face.material_index = 0
            return [g for g in geom if isinstance(g, bmesh.types.BMEdge) and all(v in fresh for v in g.verts)], wall

        band, strip = extend(cut_edges, .004, True)
        far, tube = extend(band, EXTEND, False)
        bmesh.ops.triangulate(bm, faces=bmesh.ops.holes_fill(bm, edges=far, sides=0)["faces"])
        rim = {v for e in far for v in e.verts}
        cap = [f for f in bm.faces if all(v in rim for v in f.verts)]   # every triangle of the end cap
        for face in cap:
            if face.normal.dot(-axis) < 0: face.normal_flip()
            face.material_index = 0
            for loop in face.loops: loop[uv].uv = cloth
        point = shoulder + (elbow - shoulder) * CUT
        for face in strip + tube + cap:
            for loop in face.loops:
                loop[fade] = (1, 1, 1, max(0.0, 1.0 - max(0.0, (point - loop.vert.co).dot(axis)) / EXTEND))
    bm.to_mesh(mesh.data); bm.free()


def skin_texels(mesh):
    """Sample each surface's source diffuse map (urban grey camo, black gloves) at every
    kept vertex UV and count skin-toned texels: warm, saturated and reasonably bright."""
    counts, total = {}, 0
    uv = mesh.data.uv_layers.active.data
    for index, slot in enumerate(mesh.material_slots):
        node = next(n for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and "Diffuse" in n.image.filepath)
        image = node.image; width, height = image.size
        pixels = np.empty(width * height * 4, dtype=np.float32); image.pixels.foreach_get(pixels)
        pixels = pixels.reshape(height, width, 4)
        coords = np.array([tuple(uv[l].uv) for p in mesh.data.polygons if p.material_index == index for l in p.loop_indices])
        x = (np.mod(coords[:, 0], 1) * (width - 1)).astype(int); y = (np.mod(coords[:, 1], 1) * (height - 1)).astype(int)
        rgb = pixels[y, x, :3]
        high, low = rgb.max(axis=1), rgb.min(axis=1)
        saturation = (high - low) / np.maximum(high, 1e-4)
        warm = (rgb[:, 0] > rgb[:, 1] * 1.08) & (rgb[:, 1] > rgb[:, 2] * 1.04) & (rgb[:, 0] - rgb[:, 2] > .1)
        skin = warm & (saturation > .18) & (high > .25)
        counts[SURFACES[index]] = int(skin.sum()); total += len(rgb)
    log("skin-toned texels under kept faces:", counts, "of", total)
    return counts, total


def smooth_gloves(mesh):
    """One Catmull-Clark level on the glove surface only (weights interpolate)."""
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT")
    mesh.active_material_index = 1; bpy.ops.object.material_slot_select()
    bpy.ops.mesh.separate(type="SELECTED"); bpy.ops.object.mode_set(mode="OBJECT")
    glove = next(o for o in bpy.context.selected_objects if o != mesh)
    bpy.ops.object.select_all(action="DESELECT"); glove.select_set(True); bpy.context.view_layer.objects.active = glove
    modifier = glove.modifiers.new("smooth", "SUBSURF"); modifier.levels = 1; modifier.render_levels = 1; modifier.quality = 3
    while glove.modifiers[0] != modifier: bpy.ops.object.modifier_move_up(modifier=modifier.name)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True); glove.select_set(True); bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.join()


def rigid_roots(mesh):
    """Fold every weight outside each arm's own chain (spine, neck, shoulder, the other
    side) into that side's upper-arm bone, so moving an arm's root carries the sleeve
    rigidly instead of stretching it toward the torso."""
    names = {g.index: g.name for g in mesh.vertex_groups}
    for side in ("Left", "Right"):
        if side + "Arm" not in mesh.vertex_groups: mesh.vertex_groups.new(name=side + "Arm")
    moved = 0
    for vertex in mesh.data.vertices:
        side = "Left" if vertex.co.x < 0 else "Right"
        upper = mesh.vertex_groups[side + "Arm"]
        spill = 0.0
        for g in list(vertex.groups):
            name = names[g.group]
            if not (name.startswith(side) and ("Arm" in name or "Hand" in name)) and g.weight > 0:
                spill += g.weight; mesh.vertex_groups[name].remove([vertex.index])
        if spill > 0:
            upper.add([vertex.index], spill, "ADD"); moved += 1
    log("weights folded into the upper arm on", moved, "vertices")


def finish(mesh):
    rigid_roots(mesh)
    bpy.ops.object.select_all(action="DESELECT"); mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    for polygon in mesh.data.polygons: polygon.use_smooth = True
    if mesh.data.has_custom_normals: bpy.ops.mesh.customdata_custom_splitnormals_clear()
    mesh.data.use_auto_smooth = True; mesh.data.auto_smooth_angle = math.radians(60)
    # Plain named slots: Godot gives them the third-person soldier's team maps.
    for index, slot in enumerate(mesh.material_slots):
        material = bpy.data.materials.new(SURFACES[index]); material.use_nodes = True
        shader = material.node_tree.nodes["Principled BSDF"]
        shader.inputs["Roughness"].default_value = .8; shader.inputs["Metallic"].default_value = 0
        slot.material = material


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(SOURCE), ignore_leaf_bones=True)
    rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if rig.animation_data: rig.animation_data_clear()
    for action in list(bpy.data.actions): bpy.data.actions.remove(action)
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes: m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1: bpy.ops.object.join()
    mesh = meshes[0]; mesh.name = "FirstPersonArms"; mesh.data.name = "FirstPersonArms"
    normalise(rig, mesh)
    for bone in rig.data.bones: bone.name = strip_prefix(bone.name)
    for group in mesh.vertex_groups: group.name = strip_prefix(group.name)
    rig.name = "Armature"; rig.data.name = "Armature"
    keep_arms(rig, mesh)
    cut_sleeves(rig, mesh)
    skin, sampled = skin_texels(mesh)
    if sum(skin.values()) > sampled * .002: raise SystemExit(f"first-person arms would show skin: {skin}")
    smooth_gloves(mesh)
    finish(mesh)
    for image in list(bpy.data.images): bpy.data.images.remove(image)
    colours = mesh.data.color_attributes
    colours.active_color = colours['Col']; colours.render_color_index = colours.find('Col')   # the exporter writes the render layer as COLOR_0
    triangles = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "fp_arms.glb"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_image_format="NONE", export_materials="EXPORT",
                              export_skins=True, export_animations=False, export_yup=True, export_apply=False,
                              export_all_influences=False, export_def_bones=False, export_morph=False, export_tangents=False,
                              export_colors=True)
    bones = {b.name: {"head": [round(x, 5) for x in b.head_local], "tail": [round(x, 5) for x in b.tail_local]}
             for b in rig.data.bones if any(k in b.name for k in ("Shoulder", "Arm", "Hand"))}
    (OUT / "arms.json").write_text(json.dumps({
        "source": "Mixamo 'Swat Guy' (Ch15) via .tools/user-assets/characters/Ch15_nonPBR.fbx, as used by the third-person soldier",
        "builder": "tools/blender/build_fp_arms.py", "units": "metres, Blender Z-up rest pose (T-pose, palms down)",
        "triangles": triangles, "surfaces": {"FP_Sleeve": "body", "FP_Glove": "gear"},
        "textures": "content/manifest/characters.json soldier.textures (2K team maps baked by tools/blender/ingest_soldier.py)",
        "sleeve_cut": CUT, "skin_texels": skin, "sampled_texels": sampled, "bones": bones}, indent=1, sort_keys=True) + "\n")
    log("FP ARMS PASS", target.name, "triangles", triangles)


main()
