"""Convert the CC0 source firearms into the 15 game weapon slots.

Sources (fetched by `python3 tools/dev.py fetch --domain weapons`):
  - 3DModelsCC0 "Guns & Explosives" pack (FBX + 2K PBR maps)
  - Poly Haven bolt_action_rifle_7_62 and service_pistol (glTF + 2K PBR maps)

For every slot this script:
  - bakes the source hierarchy into real-world-scale meshes, muzzle toward Blender +Y
    (Godot -Z), top +Z, origin at the bounding-box centre;
  - keeps the authored PBR maps (2K albedo, normal, ORM with AO derived from height);
  - splits moving parts into named nodes (Magazine, Bolt, Pump, RearSight, Scope);
  - adds a decimated world LOD (<= 5k triangles) as node "LOD";
  - writes sockets (muzzle, grip, support, optic_rail, magwell, ejection, sight, ...)
    to content/manifest/weapons.json in Godot coordinates.

Run: python3 tools/dev.py blender tools/blender/ingest_weapon.py [--only ar_a4 ...] [--preview DIR]
"""
import bpy, bmesh, json, math, shutil, sys
from mathutils.bvhtree import BVHTree
from pathlib import Path
from mathutils import Vector, Matrix
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "content/models/weapons/source"
PACK = SOURCE / "guns_explosives/Guns&Explosives"
OUT = ROOT / "content/models/weapons"
TEXTURES = OUT / "textures"
MANIFEST = ROOT / "content/manifest/weapons.json"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = []
PREVIEW = None
if "--only" in ARGS:
    ONLY = [a for a in ARGS[ARGS.index("--only") + 1:] if not a.startswith("--")]
if "--preview" in ARGS: PREVIEW = Path(ARGS[ARGS.index("--preview") + 1])

PACK_CREDIT = {"creator": "3DModelsCC0", "license": "CC0-1.0", "source_page": "https://3dmodelscc0.itch.io/free-cc0-guns-explosives-pack"}
def polyhaven(asset): return {"creator": "Poly Haven", "license": "CC0-1.0", "source_page": f"https://polyhaven.com/a/{asset}"}

# Base models. `parts` maps game node names to source object names; everything else is Body.
# Offsets are metres in the normalized model (Blender: +Y muzzle, +Z up), relative to the trigger.
MODELS = {
    "m4a1": {"action": "closed", "ejection": ["Ejector_Lid"], "file": PACK / "M4A1/M4A1.fbx", "maps": "M4A1", "credit": PACK_CREDIT, "title": "M4A1 carbine",
             "parts": {"Magazine": ["Magazine"], "Bolt": ["Charging_Handle"], "RearSight": ["Sight", "Sight_2", "Switch1", "Switch2"]},
             "grip": "pistol", "support": .245, "rail": .03, "rear_sight": (-.06, -.02), "front_sight": (.33, .39), "front_from": "trigger"},
    "ak47": {"action": "reciprocating", "ejection": ["Ejection_Port"], "file": PACK / "AK-47/AK47.fbx", "maps": "AK47", "credit": PACK_CREDIT, "title": "AK-47 rifle",
             "parts": {"Magazine": ["Magazine"], "Bolt": ["Ejection_Port"]},
             "grip": "pistol", "support": .22, "rail": .03, "rear_sight": (.13, .23), "front_sight": (-.06, -.01), "front_from": "muzzle"},
    "shotgun": {"action": "pump", "ejection": ["Ejection_Port"], "file": PACK / "Shotgun/Shotgun.fbx", "maps": "Shotgun", "credit": PACK_CREDIT, "title": "pump-action shotgun",
                "parts": {"Pump": ["Fore_Stock"], "Bolt": ["Ejection_Port"]},
                "grip": "stock", "support": "Pump", "rail": .06, "rear_sight": (.14, .22), "front_sight": (-.06, .0), "front_from": "muzzle"},
    "marksman": {"action": "bolt", "file": PACK / "Sniper/Sniper.fbx", "maps": "Sniper", "credit": PACK_CREDIT, "title": "scoped bolt-action rifle",
                 "parts": {"Magazine": ["Magazine"], "Bolt": ["Bolt"], "Scope": ["Scope", "FlipFlap"]},
                 "grip": "stock", "support": .26, "rail": .02, "rear_sight": (-.02, .06), "front_sight": (-.08, .0), "front_from": "muzzle", "fix": "sniper"},
    "grease_gun": {"action": "closed", "ejection": ["EjectorLid"], "file": PACK / "GreaseGun/Grease_Gun.fbx", "maps": "Grease_Gun", "credit": PACK_CREDIT, "title": "M3 submachine gun",
                   "parts": {"Magazine": ["Magazine"], "Bolt": ["EjectorLid"]},
                   "grip": "pistol", "support": "Magazine", "rail": .07, "rear_sight": (-.09, -.04), "front_sight": (.21, .27), "front_from": "trigger"},
    "suomi": {"action": "reciprocating", "ejection": ["Ejector"], "file": PACK / "Suomi_KP/Suomi_KP.fbx", "maps": "Suomi_KP", "credit": PACK_CREDIT, "title": "Suomi KP/-31 submachine gun",
              "parts": {"Magazine": ["Magazine"], "Bolt": ["Bolt"]},
              "grip": "stock", "support": .2, "rail": .05, "rear_sight": (.02, .06), "front_sight": (-.06, -.005), "front_from": "muzzle"},
    "luger": {"action": "slide", "ejection": ["Part3"], "file": PACK / "Luger/Luger.fbx", "maps": "Luger", "credit": PACK_CREDIT, "title": "Luger P08 pistol",
              "parts": {"Magazine": ["Clip"], "Bolt": ["Part1", "Part2", "Part3"]}, "turn": 180,
              "grip": "pistol", "support": "pistol", "rail": .03, "rear_sight": (-.13, -.07), "front_sight": (-.03, .0), "front_from": "muzzle", "fix": "seat_magazine"},
    "makarov": {"action": "slide", "file": PACK / "Pistol_MK/Makarov.fbx", "maps": "Makarov", "credit": PACK_CREDIT, "title": "Makarov PM pistol",
                "parts": {"Magazine": ["Magazine"], "Bolt": ["Slide", "Hammer", "Safety"]},
                "grip": "pistol", "support": "pistol", "rail": .03, "rear_sight": (-.085, -.05), "front_sight": (-.025, .0), "front_from": "muzzle", "fix": "seat_magazine"},
    "bolt_rifle": {"action": "bolt", "file": SOURCE / "bolt_action_rifle_7_62/bolt_action_rifle_7_62_2k.gltf", "credit": polyhaven("bolt_action_rifle_7_62"),
                   "title": "7.62 mm bolt-action rifle", "turn": 90,
                   "delete": ["bolt_action_rifle_7_62_bullet_54mm"],
                   "parts": {"Bolt": ["bolt_action_rifle_7_62_bolt_a", "bolt_action_rifle_7_62_bolt_b"], "Scope": ["bolt_action_rifle_7_62_scope"]},
                   "grip": "stock", "support": .25, "rail": .02, "rear_sight": (.1, .16), "front_sight": (-.06, .0), "front_from": "muzzle"},
    "service_pistol": {"action": "slide", "file": SOURCE / "service_pistol/service_pistol_2k.gltf", "credit": polyhaven("service_pistol"),
                       "title": "9 mm service pistol", "turn": 90,
                       "delete": ["service_pistol_pistol_b", "service_pistol_slide_b", "service_pistol_hammer_b", "service_pistol_trigger_b",
                                  "service_pistol_magazine_empty", "service_pistol_bullet"],
                       "parts": {"Magazine": ["service_pistol_magazine_loaded"], "Bolt": ["service_pistol_slide_a", "service_pistol_hammer_a"]},
                       "grip": "pistol", "support": "pistol", "rail": .03, "rear_sight": (-.09, -.05), "front_sight": (-.03, .0), "front_from": "muzzle",
                       "fix": "seat_magazine"},
}

# Game slots. Variants reuse a base with a finish change or kit (documented in the manifest).
SLOTS = {
    "ar_a4": {"model": "m4a1", "name": "A4 Carbine"},
    "ar_k47": {"model": "ak47", "name": "K47 Rifle"},
    "ar_b56": {"model": "m4a1", "name": "B56 Carbine", "finish": {"polymer": (.42, .34, .23)}, "variant": "M4A1 with flat dark earth furniture"},
    "smg_mp9": {"model": "grease_gun", "name": "M3 Grease Gun"},
    "smg_v45": {"model": "grease_gun", "name": "V45 Grease Gun", "finish": {"metal": (.27, .29, .22)}, "variant": "M3 with olive-drab Cerakote finish"},
    "smg_p90": {"model": "suomi", "name": "KP31 Drum SMG"},
    "sg_p12": {"model": "shotgun", "name": "P12 Pump"},
    "sg_a12": {"model": "shotgun", "name": "A12 Tactical", "barrel": -.3, "finish": {"polymer": (.07, .07, .07)}, "variant": "short-barrel shotgun with black synthetic furniture"},
    "lmg_l56": {"model": "m4a1", "name": "L56 Support", "barrel": .1, "drum": True, "variant": "M4A1 heavy-barrel automatic rifle with drum magazine and bipod"},
    "lmg_l762": {"model": "ak47", "name": "L762 Support", "barrel": .14, "drum": True, "variant": "AK light machine gun (RPK pattern) with drum magazine and bipod"},
    "dmr_d14": {"model": "marksman", "name": "D14 Marksman", "hide_scope": True, "variant": "bolt-action rifle with the integrated scope removed (irons or rail optics)"},
    "sniper_s90": {"model": "bolt_rifle", "name": "S90 Precision"},
    "pistol_p9": {"model": "service_pistol", "name": "P9 Duty"},
    "pistol_p45": {"model": "makarov", "name": "PM Combat"},
    "pistol_r357": {"model": "luger", "name": "L08 Luger"},
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path):
    if path.suffix == ".fbx": bpy.ops.import_scene.fbx(filepath=str(path))
    else: bpy.ops.import_scene.gltf(filepath=str(path))
    bpy.context.view_layer.update()


def bake(obj):
    """Bake the evaluated world transform into the mesh and unparent it."""
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)
    obj.data = obj.data.copy()
    obj.data.transform(world)
    for polygon in obj.data.polygons: polygon.use_smooth = True


def verts(objects):
    return np.array([tuple(o.matrix_world @ v.co) for o in objects for v in o.data.vertices], dtype=np.float64).reshape(-1, 3)


def principal_axis(points):
    centre = points.mean(0)
    _, _, vt = np.linalg.svd(points - centre)
    axis = Vector(vt[0])
    return Vector(centre), axis if axis.y > 0 else -axis


def fix_sniper(objects):
    """The source rifle stores its barrel ~3 degrees off the receiver line and the whole
    rifle pitched 10 degrees; straighten the barrel onto the scope/receiver axis."""
    by_name = {o.name: o for o in objects}
    _, scope_axis = principal_axis(verts([by_name["Scope"]]))
    barrel = [by_name["Barrel"], by_name["IronSight"]]
    centre, barrel_axis = principal_axis(verts([by_name["Barrel"]]))
    points = verts([by_name["Barrel"]])
    rear = centre + barrel_axis * float(((points - np.array(centre)) @ np.array(barrel_axis)).min())
    turn = barrel_axis.rotation_difference(scope_axis).to_matrix().to_4x4()
    pivot = Matrix.Translation(rear) @ turn @ Matrix.Translation(-rear)
    for obj in barrel: obj.data.transform(pivot)
    level = scope_axis.rotation_difference(Vector((0, 1, 0))).to_matrix().to_4x4()
    for obj in objects: obj.data.transform(level)


def seat_magazine(magazine, body, trigger):
    """Pistol sources keep the magazine beside the frame; slide it into the grip well."""
    mag = verts([magazine]); frame = verts([body])
    centre, axis = principal_axis(mag)
    if axis.z < 0: axis = -axis
    # Grip slice: frame points behind the trigger and below it.
    grip = frame[(frame[:, 1] < trigger.y - .005) & (frame[:, 1] > trigger.y - .11) & (frame[:, 2] < trigger.z - .01)]
    g_centre, g_axis = principal_axis(grip)
    # Principal axis of the grip runs along its height; orient it upward.
    vertical = Vector((0, g_axis.y, g_axis.z)).normalized() if abs(g_axis.z) > abs(g_axis.y) else Vector((0, 0, 1))
    if vertical.z < 0: vertical = -vertical
    turn = Vector((0, axis.y, axis.z)).normalized().rotation_difference(vertical).to_matrix().to_4x4()
    magazine.data.transform(Matrix.Translation(centre) @ turn @ Matrix.Translation(-centre))
    mag = verts([magazine]); m_lo, m_hi = mag.min(0), mag.max(0)
    bottom = float(grip[:, 2].min())
    # Base plate flush with the bottom of the grip, centred in the well at mid height.
    target_z = bottom - .002 - m_lo[2]
    mid = bottom + (m_hi[2] - m_lo[2]) * .5
    band = grip[np.abs(grip[:, 2] - mid) < .012]
    target_y = (float(band[:, 1].min()) + float(band[:, 1].max())) * .5 - (m_lo[1] + m_hi[1]) * .5 if len(band) else 0
    target_x = float(grip[:, 0].mean()) - (m_lo[0] + m_hi[0]) * .5
    magazine.data.transform(Matrix.Translation((target_x, target_y, target_z)))


def load_png(path):
    image = bpy.data.images.load(str(path))
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(image.size[1], image.size[0], 4)
    size = tuple(image.size); bpy.data.images.remove(image)
    return pixels, size


def save_jpeg(pixels, path, colour=True):
    height, width = pixels.shape[:2]
    image = bpy.data.images.new(path.stem, width, height, alpha=False)
    if not colour: image.colorspace_settings.name = "Non-Color"
    image.pixels = pixels.astype(np.float32).ravel().tolist()
    image.filepath_raw = str(path); image.file_format = "JPEG"
    bpy.context.scene.render.image_settings.quality = 90
    image.save(); bpy.data.images.remove(image)


def box_blur(channel, radius):
    padded = np.pad(channel, radius, mode="wrap")
    summed = padded.cumsum(0).cumsum(1)
    summed = np.pad(summed, ((1, 0), (1, 0)))
    d = 2 * radius + 1
    return (summed[d:, d:] - summed[:-d, d:] - summed[d:, :-d] + summed[:-d, :-d]) / (d * d)


def pack_textures(key, model):
    """2K albedo, normal (OpenGL convention) and ORM (AO from height, roughness, metal)."""
    TEXTURES.mkdir(parents=True, exist_ok=True)
    result = {k: TEXTURES / f"{key}_{k}.jpg" for k in ("albedo", "normal", "orm")}
    if all(p.exists() for p in result.values()): return result
    if "maps" in model:
        folder = model["file"].parent; prefix = model["maps"]
        albedo, _ = load_png(folder / f"{prefix}_Base_Color.png")
        normal_dx = folder / f"{prefix}_Normal_DirectX.png"
        normal, _ = load_png(normal_dx if normal_dx.exists() else folder / f"{prefix}_Normal.png")
        if normal_dx.exists(): normal[..., 1] = 1 - normal[..., 1]
        rough, _ = load_png(folder / f"{prefix}_Roughness.png")
        metal, _ = load_png(folder / f"{prefix}_Metallic.png")
        height_path = folder / f"{prefix}_Height.png"
        ao = np.ones(albedo.shape[:2], dtype=np.float32)
        if height_path.exists():
            height, _ = load_png(height_path); h = height[..., 0]
            # Cavity occlusion: surface below its blurred neighbourhood is shadowed.
            cavity = box_blur(h, 6) - h + (box_blur(h, 24) - h) * .5
            ao = np.clip(1 - cavity * 3.2, .45, 1).astype(np.float32)
        orm = np.stack([ao, rough[..., 0], metal[..., 0], np.ones_like(ao)], -1)
        save_jpeg(albedo, result["albedo"]); save_jpeg(normal, result["normal"], False); save_jpeg(orm, result["orm"], False)
    else:
        textures = model["file"].parent / "textures"
        stem = model["file"].stem.replace("_2k", "")
        for kind, name in (("albedo", "diff"), ("normal", "nor_gl"), ("orm", "arm")):
            # Poly Haven maps are already 2K glTF-convention maps (ORM = AO/rough/metal);
            # re-encode them at the shared JPEG quality.
            pixels, _ = load_png(textures / f"{stem}_{name}_2k.jpg")
            save_jpeg(pixels, result[kind], kind == "albedo")
            extra = textures / f"{stem}_accesories_{name}_2k.jpg"
            if extra.exists():
                pixels, _ = load_png(extra)
                save_jpeg(pixels, TEXTURES / f"{key}_accessories_{kind}.jpg", kind == "albedo")
    return result


def tinted_albedo(key, slot_id, finish):
    """Recolour polymer (non-metal) or metal regions for a variant finish."""
    target = TEXTURES / f"{slot_id}_albedo.jpg"
    if target.exists(): return target
    albedo, _ = load_png(TEXTURES / f"{key}_albedo.jpg"); orm, _ = load_png(TEXTURES / f"{key}_orm.jpg")
    metal = orm[..., 2:3]
    luminance = (albedo[..., :3] @ np.array([.2126, .7152, .0722], dtype=np.float32))[..., None]
    detail = luminance / max(1e-4, float(luminance.mean()))
    for region, colour in finish.items():
        weight = (1 - np.clip((metal - .35) * 4, 0, 1)) if region == "polymer" else np.clip((metal - .25) * 4, 0, 1)
        albedo[..., :3] = albedo[..., :3] * (1 - weight) + np.clip(detail * np.array(colour, dtype=np.float32), 0, 1) * weight
    save_jpeg(albedo, target)
    return target


def material(name, albedo, normal, orm):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes["Principled BSDF"]
    def image(path, colour):
        node = nodes.new("ShaderNodeTexImage"); node.image = bpy.data.images.load(str(path), check_existing=True)
        if not colour: node.image.colorspace_settings.name = "Non-Color"
        return node
    links.new(image(albedo, True).outputs["Color"], shader.inputs["Base Color"])
    split = nodes.new("ShaderNodeSeparateColor"); links.new(image(orm, False).outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], shader.inputs["Roughness"]); links.new(split.outputs["Blue"], shader.inputs["Metallic"])
    bump = nodes.new("ShaderNodeNormalMap"); links.new(image(normal, False).outputs["Color"], bump.inputs["Color"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    group = bpy.data.node_groups.get("glTF Material Output") or bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    if "Occlusion" not in group.inputs: group.inputs.new("NodeSocketFloat", "Occlusion")
    output = nodes.new("ShaderNodeGroup"); output.node_tree = group
    links.new(split.outputs["Red"], output.inputs["Occlusion"])
    return mat


def join(objects, name):
    objects = [o for o in objects if o is not None]
    if not objects: return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1: bpy.ops.object.join()
    result = bpy.context.view_layer.objects.active; result.name = name; result.data.name = name
    return result


def set_origin(obj, point):
    obj.data.transform(Matrix.Translation(-point)); obj.location = point


def stretch(objects, start, end, amount):
    """Lengthen (amount > 0) or shorten a barrel: scale the [start, end] tube section
    along Y and carry everything ahead of it (muzzle, front sight) with it."""
    scale = (end - start + amount) / (end - start)
    for obj in objects:
        for v in obj.data.vertices:
            if v.co.y > end: v.co.y += amount
            elif v.co.y > start: v.co.y = start + (v.co.y - start) * scale


def triangles(obj): return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def to_godot(v): return [round(float(v[0]), 5), round(float(v[2]), 5), round(float(-v[1]), 5)]


def slice_profile(points, y, width=.01, max_x=.05):
    band = points[(np.abs(points[:, 1] - y) < width) & (np.abs(points[:, 0]) < max_x)]
    if len(band) == 0: return None
    return float(band[:, 2].min()), float(band[:, 2].max())


def build(slot_id, slot):
    key = slot["model"]; model = MODELS[key]
    reset(); import_model(model["file"])
    for name in model.get("delete", []):
        if name in bpy.data.objects: bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes: bake(o)
    for o in [o for o in bpy.context.scene.objects if o.type != "MESH"]: bpy.data.objects.remove(o, do_unlink=True)
    if model.get("fix") == "sniper": fix_sniper(meshes)
    if model.get("turn"):
        turn = Matrix.Rotation(math.radians(model["turn"]), 4, "Z")
        for o in meshes: o.data.transform(turn)
    trigger_obj = next(o for o in meshes if "trigger" in o.name.lower())
    trigger = Vector(verts([trigger_obj]).mean(0))
    port = next((o for o in meshes if o.name in model.get("ejection", [])), None)
    port = Vector(verts([port]).max(0)) * Vector((1, 0, 0)) + Vector(verts([port]).mean(0)) * Vector((0, 1, 1)) if port else None
    # Group into game nodes.
    groups = {name: [o for o in meshes if o.name in sources] for name, sources in model["parts"].items()}
    used = {o.name for objs in groups.values() for o in objs}
    body = join([o for o in meshes if o.name not in used], "Body")
    nodes = {"Body": body}
    for name, objs in groups.items():
        if objs: nodes[name] = join(objs, name)
    if model.get("fix") == "seat_magazine" and "Magazine" in nodes: seat_magazine(nodes["Magazine"], body, trigger)
    if slot.get("hide_scope") and "Scope" in nodes:
        bpy.data.objects.remove(nodes.pop("Scope"), do_unlink=True)
    # Variant kit: barrel length, drum magazine.
    all_points = verts(nodes.values())
    if slot.get("barrel"):
        front = float(all_points[:, 1].max())
        # Only plain barrel/tube sections are resized, never sights or the pump.
        start, end = {"shotgun": (float(verts([nodes["Pump"]])[:, 1].max()) + .02 if "Pump" in nodes else front - .4, front - .04),
                      "m4a1": (front - .12, front - .06), "ak47": (front - .17, front - .13)}[key]
        stretch(nodes.values(), start, end, slot["barrel"])
    if slot.get("drum") and "Magazine" in nodes:
        drum = drum_magazine(nodes["Magazine"])
        bpy.data.objects.remove(nodes["Magazine"], do_unlink=True); nodes["Magazine"] = drum
    # Normalize: origin at bounding-box centre (Body and parts, not LOD).
    points = verts(nodes.values())
    lo, hi = points.min(0), points.max(0); centre = Vector((lo + hi) * .5)
    for obj in nodes.values(): obj.data.transform(Matrix.Translation(-centre))
    trigger -= centre
    # Materials.
    textures = pack_textures(key, model)
    albedo = tinted_albedo(key, slot_id, slot["finish"]) if slot.get("finish") else textures["albedo"]
    main = material(f"{slot_id}_finish", albedo, textures["normal"], textures["orm"])
    accessory = None
    if (TEXTURES / f"{key}_accessories_albedo.jpg").exists():
        accessory = material(f"{slot_id}_optic", *(TEXTURES / f"{key}_accessories_{k}.jpg" for k in ("albedo", "normal", "orm")))
    drum_mat = None
    if slot.get("drum"):
        drum_tex = pack_textures("suomi", MODELS["suomi"])
        drum_mat = material(f"{slot_id}_drum", drum_tex["albedo"], drum_tex["normal"], drum_tex["orm"])
    for name, obj in nodes.items():
        # Poly Haven optics use a second texture set; keep those faces on it.
        source_names = [m.name if m else "" for m in obj.data.materials]
        indices = [1 if accessory and p.material_index < len(source_names) and "accesories" in source_names[p.material_index] else 0
                   for p in obj.data.polygons]
        obj.data.materials.clear()
        obj.data.materials.append(drum_mat if name == "Magazine" and slot.get("drum") else main)
        if accessory and any(indices): obj.data.materials.append(accessory)
        for polygon, index in zip(obj.data.polygons, indices): polygon.material_index = index if accessory and any(indices) else 0
    sockets = compute_sockets(slot_id, slot, model, nodes, trigger, port - centre if port else None)
    # Pivots for animated parts.
    if "Magazine" in nodes: set_origin(nodes["Magazine"], Vector(sockets["_magwell_blender"]))
    for name in ("Bolt", "Pump", "RearSight", "Scope"):
        if name in nodes: set_origin(nodes[name], Vector(verts([nodes[name]]).mean(0)))
    sockets.pop("_magwell_blender")
    # World LOD: merged and decimated copy.
    bpy.context.view_layer.update()
    lod_parts = []
    for obj in nodes.values():
        copy = obj.copy(); copy.data = obj.data.copy(); bpy.context.scene.collection.objects.link(copy)
        copy.data.transform(copy.matrix_world); copy.matrix_world = Matrix.Identity(4); lod_parts.append(copy)
    lod = join(lod_parts, "LOD")
    view_tris = sum(triangles(o) for o in nodes.values())
    if triangles(lod) > 4600:
        decimate = lod.modifiers.new("decimate", "DECIMATE"); decimate.ratio = 4400 / triangles(lod)
        bpy.context.view_layer.objects.active = lod; bpy.ops.object.modifier_apply(modifier=decimate.name)
    lod_tris = triangles(lod)
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / f"{slot_id}.gltf"
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              export_image_format="AUTO", export_yup=True, export_apply=True, export_animations=False,
                              export_materials="EXPORT")
    if PREVIEW: lod.hide_render = True; preview(slot_id, nodes, sockets)
    return {"model": f"res://content/models/weapons/{slot_id}.gltf", "display_name": slot["name"], "base_model": model["title"],
            "variant": slot.get("variant", ""), **model["credit"], "grip_pose": model["grip"], "action": model["action"],
            "support_pose": sockets.pop("_support_pose"), "length_m": round(float(hi[1] - lo[1]), 4),
            "triangles": {"view": view_tris, "lod": lod_tris}, "nodes": sorted(nodes.keys()) + ["LOD"], "sockets": sockets}


def drum_magazine(magazine):
    """Kit a drum (from the Suomi KP source) into the magazine well of a rifle variant."""
    reference = verts([magazine]); top = reference[:, 2].max(); centre_y = float(reference[:, 1].mean())
    existing = set(bpy.data.objects.keys())
    import_model(MODELS["suomi"]["file"])
    imported = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in existing]
    drum = next(o for o in imported if o.type == "MESH" and o.name.startswith("Magazine"))
    bake(drum)
    for o in imported:
        if o != drum: bpy.data.objects.remove(o, do_unlink=True)
    points = verts([drum]); lo, hi = points.min(0), points.max(0)
    # Feed tower top at the rifle's magazine well.
    drum.data.transform(Matrix.Translation((-(lo[0] + hi[0]) * .5, centre_y - (lo[1] + hi[1]) * .5, top - hi[2])))
    drum.name = "Magazine"
    return drum


def compute_sockets(slot_id, slot, model, nodes, trigger, port):
    body = nodes["Body"]
    points = verts([o for n, o in nodes.items() if n not in ("Magazine",)])
    body_points = verts([body])
    lo, hi = points.min(0), points.max(0)
    sockets = {}
    # Muzzle: centre of the front-most geometry.
    front = points[points[:, 1] > hi[1] - .006]
    sockets["muzzle"] = {"position": to_godot((front[:, 0].mean(), hi[1], front[:, 2].mean()))}
    # Pistol grip / stock wrist behind the trigger.
    grip = body_points[(body_points[:, 1] < trigger.y - .012) & (body_points[:, 1] > trigger.y - .13) &
                       (body_points[:, 2] < trigger.z - .012) & (body_points[:, 2] > trigger.z - .11) & (np.abs(body_points[:, 0]) < .04)]
    rows = []
    for z in np.linspace(trigger.z - .03, trigger.z - .075, 4):
        band = grip[np.abs(grip[:, 2] - z) < .006]
        if len(band): rows.append((z, (band[:, 1].min() + band[:, 1].max()) * .5, band[:, 0].mean()))
    rows = np.array(rows)
    if len(rows) >= 2:
        slope = np.polyfit(rows[:, 0], rows[:, 1], 1)[0]  # dy/dz of the grip centre line
        angle = math.degrees(math.atan(slope))
        grip_centre = (float(rows[:, 2].mean()), float(np.interp(trigger.z - .045, rows[::-1, 0], rows[::-1, 1])), trigger.z - .045)
    else:
        angle = 20.0; grip_centre = (0, trigger.y - .06, trigger.z - .045)
    if model["grip"] == "stock":
        # Straight stocks: the hand wraps the wrist behind the trigger guard.
        centres = []
        for dy in (-.045, -.075, -.105):
            profile = slice_profile(body_points, trigger.y + dy, .008, .04)
            if profile: centres.append((trigger.y + dy, (profile[0] + profile[1]) * .5))
        if centres:
            y, z = centres[1] if len(centres) > 1 else centres[0]
            grip_centre = (0.0, y, z)
            if len(centres) > 2:
                fall = math.degrees(math.atan2(centres[0][1] - centres[-1][1], centres[0][0] - centres[-1][0]))
                angle = 90 - fall  # knuckles roughly square to the wrist line
        angle = min(max(angle, 35), 75)
    sockets["grip"] = {"position": to_godot(grip_centre), "angle_deg": round(angle, 2), "trigger": to_godot(trigger)}
    # Support hand.
    support = model["support"]; pose = "handguard"
    if support == "pistol":
        pose = "pistol"; position = grip_centre
    elif support == "Pump":
        pump = verts([nodes["Pump"]]); pose = "pump"
        position = ((pump[:, 0].min() + pump[:, 0].max()) * .5, float(pump[:, 1].mean()), (pump[:, 2].min() + pump[:, 2].max()) * .5)
        sockets["support"] = {"position": to_godot(position), "radius": round(float(pump[:, 2].max() - pump[:, 2].min()) * .5, 4)}
    elif support == "Magazine":
        mag = verts([nodes["Magazine"]]); pose = "magwell"
        position = (float(mag[:, 0].mean()), float(mag[:, 1].mean()), float(mag[:, 2].max()) - .07)
        sockets["support"] = {"position": to_godot(position), "radius": round(float(mag[:, 1].max() - mag[:, 1].min()) * .5, 4)}
    else:
        y = trigger.y + support
        profile = slice_profile(body_points, y, .012, .045)
        bottom, top = profile if profile else (trigger.z - .01, trigger.z + .04)
        top = min(top, bottom + .07)
        position = (0.0, y, (bottom + top) * .5)
        sockets["support"] = {"position": to_godot(position), "radius": round((top - bottom) * .5, 4)}
    if "support" not in sockets: sockets["support"] = {"position": to_godot(position), "radius": .016}
    sockets["_support_pose"] = pose
    # Magazine well: top centre of the magazine.
    if "Magazine" in nodes:
        mag = verts([nodes["Magazine"]])
        top = mag[mag[:, 2] > mag[:, 2].max() - .012]
        magwell = (float(top[:, 0].mean()), float(top[:, 1].mean()), float(mag[:, 2].max()))
        sockets["magwell"] = {"position": to_godot(magwell), "length": round(float(mag[:, 2].max() - mag[:, 2].min()), 4)}
    else:
        magwell = (0, trigger.y + .03, trigger.z + .02)
        sockets["magwell"] = {"position": to_godot(magwell), "length": 0.0}
    sockets["_magwell_blender"] = magwell
    # Ejection port: the bolt/port part on the right side, else above the trigger.
    if port is not None:
        ejection = tuple(port)
    elif "Bolt" in nodes:
        bolt = verts([nodes["Bolt"]]); ejection = (float(bolt[:, 0].max()), float(bolt[:, 1].mean()), float(bolt[:, 2].mean()))
    else:
        ejection = (.015, trigger.y + .04, trigger.z + .05)
    sockets["ejection"] = {"position": to_godot(ejection)}
    # Optic rail: top surface over the receiver.
    rail_y = trigger.y + model["rail"]
    receiver = body_points[(np.abs(body_points[:, 1] - rail_y) < .03) & (np.abs(body_points[:, 0]) < .012)]
    rail_z = float(np.percentile(receiver[:, 2], 97)) if len(receiver) else trigger.z + .06
    sockets["optic_rail"] = {"position": to_godot((0, rail_y, rail_z))}
    # Iron sights from a centre-line height profile (rays cast down the bore plane):
    # the line runs from just under the rear sight's top to the front post tip.
    profile = centreline([o for n, o in nodes.items() if n in ("Body", "RearSight", "Bolt")], lo[1], hi[1])
    def peak(window, origin):
        rows = [(y, z) for y, z in profile if origin + window[0] <= y <= origin + window[1]]
        return max(rows, key=lambda r: r[1]) if rows else (origin + sum(window) * .5, rail_z + .02)
    front_origin = hi[1] if model.get("front_from") == "muzzle" else trigger.y
    front_y, front_z = peak(model["front_sight"], front_origin)
    rear_y, rear_z = peak(model["rear_sight"], trigger.y)
    rear_line = max(rear_z - .0025, front_z - .0005) if model["grip"] != "pistol" or model["support"] != "pistol" else rear_z - .001
    sockets["sight"] = {"position": to_godot((0, rear_y, rear_line)), "front": to_godot((0, front_y, front_z - .0005)),
                        "rear_top": round(rear_z, 4)}
    sockets["butt"] = {"position": to_godot((0, lo[1], (lo[2] + hi[2]) * .5))}
    if "Scope" in nodes:
        scope = verts([nodes["Scope"]])
        _, axis = principal_axis(scope)
        rear = scope[scope[:, 1] < scope[:, 1].min() + .01]
        sockets["scope_eye"] = {"position": to_godot((float(rear[:, 0].mean()), float(scope[:, 1].min()), (float(rear[:, 2].min()) + float(rear[:, 2].max())) * .5))}
    if slot.get("drum") or slot_id.startswith("lmg"):
        y = trigger.y + .38
        profile = slice_profile(body_points, y, .015, .04)
        sockets["bipod"] = {"position": to_godot((0, y, profile[0] if profile else trigger.z))}
    return sockets


def centreline(objects, y0, y1, step=.004):
    """(y, top z) along x = 0, by casting rays straight down onto the merged mesh."""
    bm = bmesh.new()
    for obj in objects:
        mesh = obj.data.copy(); mesh.transform(obj.matrix_world); bm.from_mesh(mesh); bpy.data.meshes.remove(mesh)
    tree = BVHTree.FromBMesh(bm); bm.free()
    rows = []
    for y in np.arange(y0, y1, step):
        hit = tree.ray_cast(Vector((0, float(y), 1.0)), Vector((0, 0, -1)))
        if hit[0] is not None: rows.append((float(y), float(hit[0].z)))
    return rows


def preview(slot_id, nodes, sockets):
    colours = {"muzzle": (1, 0, 0), "grip": (0, 1, 0), "support": (0, .3, 1), "optic_rail": (1, 1, 0), "sight": (0, 1, 1),
               "magwell": (1, 0, 1), "ejection": (1, .5, 0), "bipod": (1, 1, 1), "scope_eye": (.5, 0, 1)}
    markers = []
    for name, socket in sockets.items():
        if name not in colours: continue
        g = socket["position"]
        bpy.ops.mesh.primitive_uv_sphere_add(radius=.007, location=(g[0], -g[2], g[1]))
        marker = bpy.context.active_object; mat = bpy.data.materials.new(name); mat.diffuse_color = (*colours[name], 1)
        marker.data.materials.append(mat); markers.append(marker)
    scene = bpy.context.scene
    camera = bpy.data.objects.new("preview", bpy.data.cameras.new("preview")); scene.collection.objects.link(camera); scene.camera = camera
    points = verts(nodes.values()); size = points.max(0) - points.min(0)
    camera.data.type = "ORTHO"; camera.data.ortho_scale = float(size[1]) * 1.12
    camera.location = (2, 0, 0); camera.rotation_euler = Vector((-1, 0, 0)).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "BLENDER_WORKBENCH"; scene.render.resolution_x = 900; scene.render.resolution_y = 450
    scene.display.shading.color_type = "MATERIAL"; scene.display.shading.light = "STUDIO"
    scene.display.shading.show_xray = True; scene.display.shading.xray_alpha = .55
    PREVIEW.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(PREVIEW / f"{slot_id}.png"); bpy.ops.render.render(write_still=True)
    scene.display.shading.color_type = "TEXTURE"; scene.display.shading.show_xray = False
    for marker in markers: marker.hide_render = True
    camera.location = (.9, -.9, .35); camera.data.type = "PERSP"; camera.data.lens = 50
    camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.location = camera.location * (float(size[1]) / .9)
    scene.render.engine = "BLENDER_EEVEE"
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (.5, .55, .6, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 4; sun.rotation_euler = (.9, .3, .8)
    scene.collection.objects.link(sun)
    scene.render.filepath = str(PREVIEW / f"{slot_id}_shaded.png"); bpy.ops.render.render(write_still=True)


GRENADES = {"grenade_frag": {"file": PACK / "FragGrenade/FragGrenadeModel.fbx", "maps": "FragGrenade", "title": "fragmentation grenade"},
            "grenade_smoke": {"file": PACK / "Smoke_Grenade/Smoke_Grenade.fbx", "maps": "Smoke_Grenade", "title": "smoke grenade"}}


def build_grenade(key, spec):
    reset(); import_model(spec["file"])
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes: bake(o)
    for o in [o for o in bpy.context.scene.objects if o.type != "MESH"]: bpy.data.objects.remove(o, do_unlink=True)
    pin = join([o for o in meshes if "pin" in o.name.lower()], "Pin")
    body = join([o for o in meshes if "pin" not in o.name.lower()], "Body")
    points = verts([body, pin]); centre = Vector((points.min(0) + points.max(0)) * .5)
    textures = pack_textures(key, spec)
    finish = material(key, textures["albedo"], textures["normal"], textures["orm"])
    for obj in (body, pin):
        obj.data.transform(Matrix.Translation(-centre)); obj.data.materials.clear(); obj.data.materials.append(finish)
    bpy.ops.export_scene.gltf(filepath=str(OUT / f"{key}.gltf"), export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              export_image_format="AUTO", export_yup=True, export_animations=False, export_materials="EXPORT")
    return {"model": f"res://content/models/weapons/{key}.gltf", "base_model": spec["title"], **PACK_CREDIT,
            "triangles": triangles(body) + triangles(pin), "size_m": [round(float(x), 4) for x in points.max(0) - points.min(0)]}


def main():
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {"assets": {}}
    weapons = manifest.setdefault("weapons", {})
    if not ONLY:
        for key, spec in GRENADES.items(): manifest.setdefault("grenades", {})[key] = build_grenade(key, spec)
    for slot_id, slot in SLOTS.items():
        if ONLY and slot_id not in ONLY: continue
        print("INGEST", slot_id, flush=True)
        weapons[slot_id] = build(slot_id, slot)
        print("INGESTED", slot_id, weapons[slot_id]["triangles"], flush=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("WEAPON INGEST PASS", len(weapons))


main()
