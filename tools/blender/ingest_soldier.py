"""Ingest the Mixamo soldier: one GLB with a clean rig, named in-place clips and team textures.

Runs inside the pinned Blender (headless, auto-exec disabled) as the characters pipeline step:
  python3 tools/dev.py ingest --domain characters
or directly:
  python3 tools/dev.py blender tools/blender/ingest_soldier.py --character <fbx> --pack <dir> [--pack <dir>] --out <dir>

Input (raw Mixamo FBX, kept in git-ignored .tools/; never committed):
  --character  the skinned T-pose character (FBX Binary, with skin)
  --pack       folders of rifle-pack clips downloaded "without skin" on that character; when two packs
               contain the same clip the first wins and the copies are compared and reported

Output (committed):
  <out>/soldier.glb                 mesh (LOD0 <= 30k triangles; Godot builds LOD1/LOD2 on import),
                                    prefix-free Mixamo skeleton, 1.8 m tall, facing -Z, and named
                                    in-place clips (root motion removed, ground speed recorded)
  <out>/textures/<part>_<map>.jpg   2K PBR maps per material: normal, orm (R=1, G=roughness,
                                    B=metallic) and albedo_blue / albedo_red, where the urban digital
                                    camo is recoloured to woodland (Blue) or desert (Red) and the
                                    black load-bearing gear to ranger green / coyote
  content/manifest/characters.json  "soldier" entry: clip table, rig facts, triangle counts
"""
import bpy, bmesh, json, math, re, sys, time
from pathlib import Path
from mathutils import Matrix, Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
FPS = 30
HEIGHT = 1.8
LOD0_BUDGET = 29500
TEXTURE_SIZE = 2048
DIRECTIONS = {"f": "forward", "b": "backward", "l": "left", "r": "right",
              "fl": "forward left", "fr": "forward right", "bl": "backward left", "br": "backward right"}
# canonical clip -> (source clip stem, kind). Names avoid Godot's '_loop' import suffix. Kinds: loop (cyclic, root motion removed), once
# (root motion removed), death (root motion kept as a backup to the ragdoll).
CLIPS = {"idle": ("idle aiming", "loop"), "idle_relaxed": ("idle", "loop"),
         "crouch_idle": ("idle crouching aiming", "loop"),
         "jump_up": ("jump up", "once"), "airborne": ("jump loop", "loop"), "jump_down": ("jump down", "once"),
         "turn_l": ("turn 90 left", "once"), "turn_r": ("turn 90 right", "once"),
         "death_front": ("death from the front", "death"), "death_back": ("death from the back", "death"),
         "death_front_head": ("death from front headshot", "death"), "death_back_head": ("death from back headshot", "death"),
         "death_right": ("death from right", "death"), "death_crouch": ("death crouching headshot front", "death")}
for key, words in DIRECTIONS.items():
    CLIPS["walk_" + key] = ("walk " + words, "loop")
    CLIPS["run_" + key] = ("run " + words, "loop")
    CLIPS["crouch_" + key] = ("walk crouching " + words, "loop")
for key in ["f", "fl", "fr"]:
    CLIPS["sprint_" + key] = ("sprint " + DIRECTIONS[key], "loop")
# Team palettes (sRGB). Camo levels run light -> dark; gear is the plate carrier/belt colour.
TEAMS = {
    "blue": {"camo": ["8f8d6a", "6b6c4a", "4a4c34", "2f3223"], "gear": "4b5038"},   # woodland / ranger green
    "red": {"camo": ["cdb995", "ad9670", "84704f", "5e4d38"], "gear": "8a6c48"},    # desert / coyote
}

def log(*parts):
    print("[ingest_soldier]", *parts, flush=True)

def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = {"character": None, "pack": [], "out": "content/models/characters"}
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-")
        if key == "pack": result["pack"].append(argv[i + 1])
        else: result[key] = argv[i + 1]
        i += 2
    if not result["character"] or not result["pack"]:
        raise SystemExit("usage: ingest_soldier.py --character <fbx> --pack <dir> [--pack <dir>] [--out <dir>]")
    return result

def absolute(path):
    path = Path(path)
    return path if path.is_absolute() else ROOT / path

def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(path), ignore_leaf_bones=True, use_anim=True)
    return [o for o in bpy.data.objects if o not in before]

def strip_prefix(name):
    return re.sub(r"^mixamorig\d*:", "", name)

# ---------------------------------------------------------------- character

def load_character(path):
    objects = import_fbx(path)
    rig = next(o for o in objects if o.type == "ARMATURE")
    meshes = [o for o in objects if o.type == "MESH"]
    if rig.animation_data: rig.animation_data_clear()
    for action in list(bpy.data.actions): bpy.data.actions.remove(action)
    return rig, meshes

def mesh_islands(bm):
    bm.faces.ensure_lookup_table()
    seen, islands = set(), []
    for face in bm.faces:
        if face.index in seen: continue
        stack, island = [face], []
        seen.add(face.index)
        while stack:
            current = stack.pop(); island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen: seen.add(other.index); stack.append(other)
        islands.append(island)
    return islands

def remove_exoskeleton(mesh_object):
    """The 'Swat Guy' outfit carries a sci-fi exoskeleton (leg struts and heel pistons, a glowing spine,
    hip arcs and arm rods). Each is a separate loose part, so whole islands are dropped by where they sit on the
    T-posed body (metres, Z up, character facing -Y as imported)."""
    world = mesh_object.matrix_world
    bm = bmesh.new(); bm.from_mesh(mesh_object.data)
    removed, kept = 0, 0
    doomed = []
    for island in mesh_islands(bm):
        points = [world @ v.co for f in island for v in f.verts]
        lo = Vector([min(p[i] for p in points) for i in range(3)]); hi = Vector([max(p[i] for p in points) for i in range(3)])
        c = (lo + hi) * .5; size = hi - lo
        leg_strut = abs(c.x) > .17 and hi.z < 1.0 and lo.z > .1 and size.z > .25
        spine = lo.y > .07 and abs(c.x) < .12 and lo.z > .95 and hi.z < 1.5
        back_hub = lo.y > .07 and abs(c.x) < .12 and lo.z > .85 and hi.z < 1.5 and size.y < .13
        hip_arc = lo.y > .02 and .7 < lo.z and hi.z < 1.0 and .05 < abs(c.x) < .3 and size.y < .13 and size.x > .1
        shoulder_rod = lo.y > .08 and lo.z > 1.38 and hi.z < 1.52 and .12 < abs(c.x) < .36
        arm_rod = lo.y > .04 and lo.z > 1.42 and hi.z < 1.52 and abs(c.x) > .3 and size.z < .06 and size.y < .06
        heel_piston = not leg_strut and .08 < lo.z and hi.z < .34 and size.length < .14 and (abs(c.x) > .19 or lo.y > .09)
        if leg_strut or spine or back_hub or hip_arc or shoulder_rod or arm_rod or heel_piston:
            doomed.extend(island); removed += sum(len(f.verts) - 2 for f in island)
        else:
            kept += sum(len(f.verts) - 2 for f in island)
    bmesh.ops.delete(bm, geom=list(set(doomed)), context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh_object.data); bm.free()
    log(f"exoskeleton removed: {removed} triangles, kept {kept}")
    return removed

def triangle_count(mesh_object):
    return sum(len(p.vertices) - 2 for p in mesh_object.data.polygons)

def reduce_to_budget(mesh_object):
    bpy.context.view_layer.objects.active = mesh_object
    for obj in bpy.context.selected_objects: obj.select_set(False)
    mesh_object.select_set(True)
    before = triangle_count(mesh_object)
    planar = mesh_object.modifiers.new("planar", "DECIMATE")
    planar.decimate_type = "DISSOLVE"; planar.angle_limit = math.radians(1.0)
    planar.delimit = {"MATERIAL", "SEAM", "SHARP", "UV"}
    bpy.ops.object.modifier_apply(modifier=planar.name)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(); bpy.ops.object.mode_set(mode="OBJECT")
    after_planar = triangle_count(mesh_object)
    if after_planar > LOD0_BUDGET:
        collapse = mesh_object.modifiers.new("collapse", "DECIMATE")
        collapse.decimate_type = "COLLAPSE"; collapse.ratio = LOD0_BUDGET / after_planar
        collapse.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=collapse.name)
    log(f"triangles {before} -> planar {after_planar} -> {triangle_count(mesh_object)}")
    # Four influences per vertex (glTF's single set), renormalised.
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    for poly in mesh_object.data.polygons: poly.use_smooth = True
    if mesh_object.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    mesh_object.data.use_auto_smooth = True; mesh_object.data.auto_smooth_angle = math.radians(50)

def normalise_transform(rig, meshes):
    """Bake the FBX's 90-degree/0.01 object transform, a 180-degree turn (face -Y in Blender, which
    exports as Godot's -Z forward) and the 1.8 m height into the data. Returns the scale applied to
    bone-local translations."""
    for mesh in meshes:
        world = mesh.matrix_world.copy(); mesh.parent = None; mesh.matrix_world = world
    turn = Matrix.Rotation(math.pi, 4, "Z")
    rig.matrix_world = turn @ rig.matrix_world
    for mesh in meshes: mesh.matrix_world = turn @ mesh.matrix_world
    bpy.context.view_layer.update()
    points = [m.matrix_world @ v.co for m in meshes for v in m.data.vertices]
    height = max(p.z for p in points) - min(p.z for p in points)
    factor = HEIGHT / height
    grow = Matrix.Scale(factor, 4)
    rig.matrix_world = grow @ rig.matrix_world
    for mesh in meshes: mesh.matrix_world = grow @ mesh.matrix_world
    bpy.context.view_layer.update()
    object_scale = rig.matrix_world.to_scale().x
    for obj in [rig] + meshes:
        for other in bpy.context.selected_objects: other.select_set(False)
        obj.select_set(True); bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # Boot soles sit 2-3 cm below the rig's ground; lift everything so they touch y=0.
    floor = min((m.matrix_world @ v.co).z for m in meshes for v in m.data.vertices)
    lift = Matrix.Translation((0, 0, -floor))
    for obj in [rig] + meshes:
        obj.matrix_world = lift @ obj.matrix_world
        for other in bpy.context.selected_objects: other.select_set(False)
        obj.select_set(True); bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    for mesh in meshes:
        mesh.parent = rig; mesh.matrix_parent_inverse = Matrix.Identity(4)
        for modifier in mesh.modifiers:
            if modifier.type == "ARMATURE": modifier.object = rig
    log(f"source height {height:.3f} m -> {HEIGHT} m (bone translation scale {object_scale:.5f}); lifted {-floor:.4f} m")
    return object_scale

def rename_bones(rig, meshes):
    for bone in rig.data.bones: bone.name = strip_prefix(bone.name)
    for mesh in meshes:
        for group in mesh.vertex_groups: group.name = strip_prefix(group.name)

# ---------------------------------------------------------------- animation

def find_clip(packs, stem):
    for pack in packs:
        candidate = pack / (stem + ".fbx")
        if candidate.exists(): return candidate
    return None

def action_signature(action):
    values = []
    for fc in sorted(action.fcurves, key=lambda f: (f.data_path, f.array_index))[:60]:
        values.extend(round(k.co[1], 4) for k in fc.keyframe_points[:12])
    return values

def load_clip(path):
    objects = import_fbx(path)
    rig = next(o for o in objects if o.type == "ARMATURE")
    action = rig.animation_data.action
    for obj in objects:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            if isinstance(data, bpy.types.Armature): bpy.data.armatures.remove(data)
    return action

def clean_action(action, translation_scale):
    """Strip the mixamorig prefix, drop scale channels, shift to start at frame 0 and convert bone
    translations to the baked metre scale."""
    start = action.frame_range[0]
    for fc in list(action.fcurves):
        if fc.data_path.endswith(".scale"):
            action.fcurves.remove(fc); continue
        match = re.match(r'pose\.bones\["([^"]+)"\]\.(.*)', fc.data_path)
        if match: fc.data_path = f'pose.bones["{strip_prefix(match.group(1))}"].{match.group(2)}'
        if fc.group is not None: fc.group.name = strip_prefix(fc.group.name)
        is_location = fc.data_path.endswith(".location")
        for key in fc.keyframe_points:
            key.co[0] -= start; key.handle_left[0] -= start; key.handle_right[0] -= start
            if is_location:
                key.co[1] *= translation_scale; key.handle_left[1] *= translation_scale; key.handle_right[1] *= translation_scale

def strip_root_motion(rig, action, kind):
    """Remove the hips' horizontal travel (a linear ramp plus the start offset) so clips play in place.
    Keeps the vertical bob and the residual sway. Returns the removed ground velocity in character
    space (right, forward) in m/s."""
    hips = rig.data.bones["Hips"]
    basis = hips.matrix_local.to_3x3().normalized()
    inverse = basis.inverted()
    curves = [action.fcurves.find('pose.bones["Hips"].location', index=i) for i in range(3)]
    if any(c is None for c in curves): return (0.0, 0.0)
    first, last = int(round(action.frame_range[0])), int(round(action.frame_range[1]))
    frames = list(range(first, last + 1))
    raw = [basis @ Vector([c.evaluate(f) for c in curves]) for f in frames]
    span = max(1, last - first)
    drift = raw[-1] - raw[0]
    velocity = (drift.x * FPS / span, drift.y * FPS / span)   # +X right, +Y forward once turned
    if kind == "death":
        fixed = [Vector((p.x - raw[0].x, p.y - raw[0].y, p.z)) for p in raw]
    else:
        fixed = [Vector((p.x - raw[0].x - drift.x * (f - first) / span, p.y - raw[0].y - drift.y * (f - first) / span, p.z)) for f, p in zip(frames, raw)]
    local = [inverse @ p for p in fixed]
    for axis, curve in enumerate(curves):
        curve.keyframe_points.clear()
        curve.keyframe_points.add(len(frames))
        flat = []
        for f, value in zip(frames, local): flat.extend((f, value[axis]))
        curve.keyframe_points.foreach_set("co", flat)
        for key in curve.keyframe_points: key.interpolation = "LINEAR"
        curve.update()
    return velocity

def gather_clips(rig, packs, translation_scale):
    table, duplicates = {}, {}
    for name, (stem, kind) in CLIPS.items():
        path = find_clip(packs, stem)
        if path is None:
            log(f"MISSING clip '{stem}' for {name}"); continue
        action = load_clip(path)
        clean_action(action, translation_scale)
        for other in packs:
            twin = other / (stem + ".fbx")
            if twin.exists() and twin != path:
                copy = load_clip(twin); clean_action(copy, translation_scale)
                duplicates[stem] = action_signature(copy) == action_signature(action)
                bpy.data.actions.remove(copy)
        velocity = strip_root_motion(rig, action, kind)
        action.name = name; action.use_fake_user = True
        length = (action.frame_range[1] - action.frame_range[0]) / FPS
        table[name] = {"source": stem, "kind": kind, "loop": kind == "loop", "length": round(length, 4),
                       "velocity": [round(velocity[0], 3), round(velocity[1], 3)],
                       "speed": round(math.hypot(*velocity), 3)}
    if duplicates:
        same = sum(1 for v in duplicates.values() if v)
        log(f"packs compared on {len(duplicates)} clips: {same} identical, {len(duplicates) - same} differ")
    return table, duplicates

def stack_actions(rig, names):
    """One NLA track per clip so the glTF exporter writes every clip as its own animation."""
    rig.animation_data_create()
    rig.animation_data.action = None
    for track in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(track)
    for name in names:
        action = bpy.data.actions[name]
        track = rig.animation_data.nla_tracks.new(); track.name = name
        strip = track.strips.new(name, int(action.frame_range[0]), action)
        strip.name = name; track.mute = True

# ---------------------------------------------------------------- textures

def pixels(image):
    width, height = image.size
    buffer = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(buffer)
    data = buffer.reshape(height, width, 4)
    while data.shape[0] > TEXTURE_SIZE:   # 2x2 box filter down to 2K
        data = data.reshape(data.shape[0] // 2, 2, data.shape[1] // 2, 2, 4).mean(axis=(1, 3))
    return data

def save(data, path, quality=92):
    height, width = data.shape[:2]
    image = bpy.data.images.new(path.stem, width, height, alpha=False)
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[..., :data.shape[2] if data.ndim == 3 else 1] = data if data.ndim == 3 else data[..., None]
    image.pixels.foreach_set(np.clip(rgba, 0, 1).ravel())
    image.file_format = "JPEG"; image.filepath_raw = str(path)
    image.save(filepath=str(path), quality=quality)
    bpy.data.images.remove(image)

def box_blur(channel, radius):
    """Separable box blur via cumulative sums (edge-clamped)."""
    result = channel
    for axis in (0, 1):
        padded = np.pad(result, [(radius + 1, radius) if a == axis else (0, 0) for a in (0, 1)], mode="edge")
        summed = np.cumsum(padded, axis=axis, dtype=np.float64)
        upper = np.take(summed, np.arange(2 * radius + 1, summed.shape[axis]), axis=axis)
        lower = np.take(summed, np.arange(0, summed.shape[axis] - 2 * radius - 1), axis=axis)
        result = ((upper - lower) / (2 * radius + 1)).astype(np.float32)
    return result

def hex_colour(value):
    return np.array([int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)

def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)

def recolour(albedo, palette, camo_allowed):
    """Texture recolour, not a tint: the grey digital camo is split into pattern (which camo level a
    pixel belongs to) and shading (folds, seams, wear) and the pattern is gradient-mapped onto the
    team's camo levels; dark neutral webbing/plates take the team gear colour with their own detail.
    Gloves, boots, skin and coloured parts are left alone."""
    rgb = albedo[..., :3]
    luminance = rgb @ np.array([.2126, .7152, .0722], dtype=np.float32)
    saturation = (rgb.max(axis=2) - rgb.min(axis=2)) / np.maximum(rgb.max(axis=2), 1e-4)
    mean = box_blur(luminance, 10)
    variance = np.maximum(box_blur(luminance * luminance, 10) - mean * mean, 0)
    texture_energy = np.sqrt(variance)
    neutral = 1 - smoothstep(.1, .2, saturation)
    camo = neutral * smoothstep(.13, .2, luminance) * smoothstep(.035, .07, box_blur(texture_energy, 6)) * camo_allowed
    camo = np.clip(box_blur(camo, 3) * 1.4, 0, 1)
    shading = np.maximum(box_blur(luminance, 24), 1e-3)
    pattern = np.clip(luminance / shading * .5, 0, 1)          # ~.5 = average camo level
    levels = np.stack([hex_colour(c) for c in palette["camo"]])
    stops = np.array([.62, .52, .43, .3], dtype=np.float32)    # pattern value of each level, light -> dark
    position = np.interp(pattern, stops[::-1], np.arange(len(stops))[::-1].astype(np.float32))
    low = np.floor(position).astype(int).clip(0, len(stops) - 1); high = np.minimum(low + 1, len(stops) - 1)
    blend = (position - low)[..., None]
    blend = smoothstep(.35, .65, blend)                        # keep the digital blocks crisp
    mapped = levels[low] * (1 - blend) + levels[high] * blend
    shade = np.clip(shading / .45, .45, 1.35)[..., None]       # .45 ~ mean camo luminance
    camo_rgb = mapped * shade
    # Gear: judged on the local mean so stitching and scuffs inside a dark strap keep the strap's
    # colour; fine detail and broad shading are carried over as ratios, capped so noise stays quiet.
    local = box_blur(luminance, 4)
    gear_mask = box_blur(neutral, 4) * (1 - smoothstep(.09, .15, local)) * (1 - camo)
    detail = np.clip(luminance / np.maximum(local, .015), .5, 1.5) ** .7
    broad = np.clip(box_blur(luminance, 16) / .07, .35, 1.2) ** .5
    gear_rgb = hex_colour(palette["gear"]) * (detail * broad)[..., None]
    out = rgb * (1 - camo[..., None]) + camo_rgb * camo[..., None]
    out = out * (1 - gear_mask[..., None] * .85) + gear_rgb * (gear_mask[..., None] * .85)
    return np.clip(out, 0, 1)

def bake_textures(materials, out_dir):
    """materials: {part: blender material}. Writes 2K maps and returns {part: {map: res path}}."""
    out_dir.mkdir(parents=True, exist_ok=True)
    result = {}
    for part, material in materials.items():
        nodes = material.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        def source(socket_name):
            socket = bsdf.inputs[socket_name]
            if not socket.is_linked: return None
            node = socket.links[0].from_node
            if node.type == "NORMAL_MAP": node = node.inputs["Color"].links[0].from_node
            return node.image if node.type == "TEX_IMAGE" else None
        diffuse = pixels(source("Base Color"))
        normal = pixels(source("Normal"))
        gloss_image = None
        for node in nodes:
            if node.type == "TEX_IMAGE" and node.image and "gloss" in node.image.filepath.lower(): gloss_image = node.image
        specular = source("Specular")
        gloss = pixels(gloss_image)[..., 0] if gloss_image else np.full(diffuse.shape[:2], .4, np.float32)
        spec = pixels(specular)[..., :3].mean(axis=2) if specular else np.zeros(diffuse.shape[:2], np.float32)
        maps = {}
        # Normal: renormalise after downsampling (tangent space, OpenGL +Y like Godot).
        n = normal[..., :3] * 2 - 1
        n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-5)
        save(n * .5 + .5, out_dir / f"{part}_normal.jpg", 95); maps["normal"] = f"{part}_normal.jpg"
        # Spec/gloss -> metal/rough. Mixamo's gloss reads as wet plastic on fabric; remap so cloth
        # lands around .75-.9 roughness and buckles/metal stay smoother.
        roughness = .25 + .75 * np.power(np.clip(1 - gloss, 0, 1), .6)
        metallic = smoothstep(.55, .8, spec) * .85
        roughness = np.where(metallic > .5, np.minimum(roughness, .55), roughness)
        orm = np.stack([np.ones_like(roughness), roughness, metallic], axis=2)
        save(orm, out_dir / f"{part}_orm.jpg", 92); maps["orm"] = f"{part}_orm.jpg"
        camo_allowed = np.ones(diffuse.shape[:2], np.float32) if part == "body" else np.zeros(diffuse.shape[:2], np.float32)
        for team, palette in TEAMS.items():
            save(recolour(diffuse, palette, camo_allowed), out_dir / f"{part}_albedo_{team}.jpg", 92)
            maps["albedo_" + team] = f"{part}_albedo_{team}.jpg"
        result[part] = maps
        log(f"textures {part}: {sorted(maps)}")
    return result

def write_import_settings(texture_dir, textures):
    """Texture .import files (committed): VRAM-compressed with mipmaps, normal maps flagged, and the
    ORM roughness anti-aliased against its normal map. Godot fills in uid/paths on first import;
    existing files are left untouched so uids stay stable."""
    for part, maps in textures.items():
        for kind, name in maps.items():
            target = texture_dir / (name + ".import")
            if target.exists(): continue
            normal = kind == "normal"
            rough = f'"res://{(texture_dir / maps["normal"]).relative_to(ROOT)}"' if kind == "orm" else '""'
            target.write_text("\n".join([
                "[remap]", "", 'importer="texture"', 'type="CompressedTexture2D"', "", "[params]", "",
                "compress/mode=2", "compress/high_quality=false", "compress/lossy_quality=0.7", "compress/uastc_level=0",
                "compress/rdo_quality_loss=0.0", "compress/hdr_compression=1", f"compress/normal_map={1 if normal else 2}",
                "compress/channel_pack=0", "mipmaps/generate=true", "mipmaps/limit=-1",
                f"roughness/mode={3 if kind == 'orm' else 1}", f"roughness/src_normal={rough}",
                "process/channel_remap/red=0", "process/channel_remap/green=1", "process/channel_remap/blue=2",
                "process/channel_remap/alpha=3", "process/fix_alpha_border=true", "process/premult_alpha=false",
                "process/normal_map_invert_y=false", "process/hdr_as_srgb=false", "process/hdr_clamp_exposure=false",
                "process/size_limit=0", "detect_3d/compress_to=1", ""]))

def plain_materials(mesh_object):
    """Rename the two Mixamo materials to body/gear and strip their image nodes: Godot builds the team
    materials from the baked maps, so the GLB carries only the slots."""
    parts = {}
    for slot in mesh_object.material_slots:
        material = slot.material
        part = "gear" if material.name.endswith("1") else "body"
        parts[part] = material
    plain = {}
    for part, material in parts.items():
        copy = bpy.data.materials.new(part); copy.use_nodes = True
        bsdf = copy.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = .8; bsdf.inputs["Metallic"].default_value = 0
        for slot in mesh_object.material_slots:
            if slot.material == material: slot.material = copy
        plain[part] = copy
    return parts

# ---------------------------------------------------------------- main

def main():
    started = time.time()
    args = arguments()
    out_dir = absolute(args["out"]); out_dir.mkdir(parents=True, exist_ok=True)
    packs = [absolute(p) for p in args["pack"]]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene; scene.render.fps = FPS; scene.render.fps_base = 1
    rig, meshes = load_character(absolute(args["character"]))
    if len(meshes) > 1:
        bpy.ops.object.select_all(action="DESELECT")
        for m in meshes: m.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]; bpy.ops.object.join(); meshes = [meshes[0]]
    body = meshes[0]; body.name = "Soldier"; body.data.name = "Soldier"
    source_triangles = triangle_count(body)
    removed = remove_exoskeleton(body)
    translation_scale = normalise_transform(rig, meshes)
    rename_bones(rig, meshes)
    rig.name = "Armature"; rig.data.name = "Armature"
    reduce_to_budget(body)
    source_materials = plain_materials(body)
    textures = bake_textures(source_materials, out_dir / "textures")
    write_import_settings(out_dir / "textures", textures)
    for material in source_materials.values(): bpy.data.materials.remove(material)
    for image in list(bpy.data.images): bpy.data.images.remove(image)
    clips, duplicates = gather_clips(rig, packs, translation_scale)
    stack_actions(rig, list(clips))
    target = out_dir / "soldier.glb"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", export_image_format="NONE",
        export_materials="EXPORT", export_texcoords=True, export_normals=True, export_tangents=False,
        export_colors=False, export_yup=True, export_apply=False, export_skins=True, export_all_influences=False,
        export_def_bones=False, export_morph=False, export_animations=True, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=True,
        export_anim_slide_to_zero=True, export_reset_pose_bones=True, export_rest_position_armature=True,
        export_extras=False, use_selection=False)
    lod0 = triangle_count(body)
    bones = [b.name for b in rig.data.bones]
    manifest_path = ROOT / "content/manifest/characters.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"assets": {}}
    manifest["soldier"] = {
        "model": "res://" + str(target.relative_to(ROOT)),
        "textures": {part: {k: "res://" + str((out_dir / "textures" / v).relative_to(ROOT)) for k, v in maps.items()} for part, maps in textures.items()},
        "height_m": HEIGHT, "forward": "-Z", "fps": FPS,
        "triangles": {"source": source_triangles, "exoskeleton_removed": removed, "lod0": lod0, "lod0_budget": 30000},
        "bones": bones, "clips": clips,
        "pack_duplicates": {"compared": len(duplicates), "identical": sum(1 for v in duplicates.values() if v)},
        "pipeline": "tools/blender/ingest_soldier.py",
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    log(f"wrote {target.relative_to(ROOT)}: {lod0} triangles, {len(bones)} bones, {len(clips)} clips in {time.time() - started:.0f}s")

main()
