"""Model the weapon attachments: red dot, holographic sight, 3x scope, suppressor,
compensator, vertical and angled grips, bipod and magazine pull tab.

Shapes are bevelled hard-surface meshes with tileable PBR finishes (anodized aluminium,
polymer, rubber) generated here, so no download is needed. Optic reticles are emissive
lens surfaces centred on the sight line; the HUD no longer draws them.

Each attachment is exported to content/models/weapons/attachments/<id>.gltf with its
origin at the mounting point (rail contact, muzzle thread or magazine floor plate) and
its sockets written to content/manifest/weapons.json under "attachments" (Godot axes).

Run: python3 tools/dev.py blender tools/blender/build_attachments.py
"""
import bpy, bmesh, json, math
from pathlib import Path
from mathutils import Vector, Matrix
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "content/models/weapons/attachments"
TEXTURES = OUT / "textures"
MANIFEST = ROOT / "content/manifest/weapons.json"
rng = np.random.default_rng(1201)


def to_godot(v): return [round(float(v[0]), 5), round(float(v[2]), 5), round(float(-v[1]), 5)]


# ---------------------------------------------------------------- textures
def tileable_noise(size, scale, octaves=4):
    result = np.zeros((size, size), dtype=np.float32)
    amplitude = 1.0
    for octave in range(octaves):
        cells = scale * 2 ** octave
        grid = rng.random((cells, cells)).astype(np.float32)
        # Bilinear upsample with wrap so the texture tiles.
        x = np.linspace(0, cells, size, endpoint=False)
        i0 = np.floor(x).astype(int) % cells; i1 = (i0 + 1) % cells; t = (x - np.floor(x))[None, :]
        rows = grid[:, i0] * (1 - t) + grid[:, i1] * t
        rows = rows[i0, :] * (1 - t.T) + rows[i1, :] * t.T
        result += rows * amplitude; amplitude *= .5
    result -= result.min(); result /= max(1e-6, result.max())
    return result


def save(pixels, name, colour):
    path = TEXTURES / name
    height, width = pixels.shape[:2]
    alpha = pixels.shape[2] == 4
    image = bpy.data.images.new(name, width, height, alpha=alpha)
    if not colour: image.colorspace_settings.name = "Non-Color"
    if not alpha: pixels = np.concatenate([pixels, np.ones((height, width, 1), dtype=np.float32)], -1)
    image.pixels = pixels.astype(np.float32).ravel().tolist()
    image.filepath_raw = str(path)
    image.file_format = "PNG" if alpha else "JPEG"
    bpy.context.scene.render.image_settings.quality = 92
    image.save()
    return image


def finish_textures(name, base, roughness, metal, grain, bumps):
    """Albedo, ORM and normal for a finish; grain is fine noise, bumps the normal strength."""
    size = 512
    fine = tileable_noise(size, 32, 3); broad = tileable_noise(size, 4, 3)
    albedo = np.ones((size, size, 4), dtype=np.float32)
    shade = 1 + (fine - .5) * grain + (broad - .5) * grain * .6
    albedo[..., :3] = np.clip(np.array(base, dtype=np.float32)[None, None, :] * shade[..., None], 0, 1)
    orm = np.ones((size, size, 4), dtype=np.float32)
    orm[..., 0] = 1; orm[..., 1] = np.clip(roughness + (fine - .5) * .16 + (broad - .5) * .1, .05, 1); orm[..., 2] = metal
    height = fine * .7 + broad * .3
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * bumps; dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * bumps
    normal = np.ones((size, size, 4), dtype=np.float32)
    length = np.sqrt(dx * dx + dy * dy + 1)
    normal[..., 0] = (-dx / length) * .5 + .5; normal[..., 1] = (-dy / length) * .5 + .5; normal[..., 2] = (1 / length) * .5 + .5
    return [save(albedo[..., :3], f"{name}_albedo.jpg", True), save(orm[..., :3], f"{name}_orm.jpg", False),
            save(normal[..., :3], f"{name}_normal.jpg", False)]


def reticle_texture(name, ring):
    size = 256
    y, x = np.mgrid[0:size, 0:size].astype(np.float32) + .5
    r = np.hypot(x - size / 2, y - size / 2)
    glow = np.exp(-(r / (4.0 if ring else 9.0)) ** 2)
    if ring:
        glow = np.maximum(glow, np.exp(-((r - 52) / 2.0) ** 2))
        for angle in (0, math.pi * .5, math.pi, math.pi * 1.5):  # EOTech-style ticks inside the ring
            tick = np.exp(-(((x - size / 2) * math.cos(angle) + (y - size / 2) * math.sin(angle) - 60) / 4) ** 2
                          - (((x - size / 2) * -math.sin(angle) + (y - size / 2) * math.cos(angle)) / 1.4) ** 2)
            glow = np.maximum(glow, tick * (r > 54))
    pixels = np.zeros((size, size, 4), dtype=np.float32)
    pixels[..., 0] = 1; pixels[..., 1] = .12 + glow * .25; pixels[..., 2] = .06 + glow * .1; pixels[..., 3] = np.clip(glow * 1.3, 0, 1)
    return save(pixels, f"{name}.png", True)


def pbr_material(name, images, alpha=None):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links; shader = nodes["Principled BSDF"]
    def node(image):
        n = nodes.new("ShaderNodeTexImage"); n.image = image; return n
    albedo, orm, normal = images
    links.new(node(albedo).outputs["Color"], shader.inputs["Base Color"])
    split = nodes.new("ShaderNodeSeparateColor"); links.new(node(orm).outputs["Color"], split.inputs["Color"])
    links.new(split.outputs["Green"], shader.inputs["Roughness"]); links.new(split.outputs["Blue"], shader.inputs["Metallic"])
    bump = nodes.new("ShaderNodeNormalMap"); bump.inputs["Strength"].default_value = .6
    links.new(node(normal).outputs["Color"], bump.inputs["Color"]); links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return mat


def glass_material():
    mat = bpy.data.materials.new("Optic_Glass"); mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (.07, .11, .1, 1); shader.inputs["Roughness"].default_value = .04
    shader.inputs["Metallic"].default_value = .2; shader.inputs["Alpha"].default_value = .2
    mat.blend_method = "BLEND"; mat.shadow_method = "NONE"
    return mat


def reticle_material(name, image):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links; shader = nodes["Principled BSDF"]
    texture = nodes.new("ShaderNodeTexImage"); texture.image = image
    shader.inputs["Base Color"].default_value = (0, 0, 0, 1)
    links.new(texture.outputs["Color"], shader.inputs["Emission"]); shader.inputs["Emission Strength"].default_value = 6.0
    links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
    mat.blend_method = "BLEND"; mat.shadow_method = "NONE"
    return mat


# ---------------------------------------------------------------- geometry helpers
def mesh_object(name, build):
    mesh = bpy.data.meshes.new(name); bm = bmesh.new(); build(bm); bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new(name, mesh); bpy.context.scene.collection.objects.link(obj)
    return obj


def box(name, size, centre, material):
    def build(bm):
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation(centre) @ Matrix.Diagonal((*size, 1)))
    obj = mesh_object(name, build); obj.data.materials.append(material); return obj


def cylinder(name, radius, length, centre, material, axis="Y", segments=32, radius2=None):
    def build(bm):
        rotation = {"Y": Matrix.Rotation(math.radians(90), 4, "X"), "Z": Matrix.Identity(4), "X": Matrix.Rotation(math.radians(90), 4, "Y")}[axis]
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius2 if radius2 is not None else radius,
                              depth=length, matrix=Matrix.Translation(centre) @ rotation)
    obj = mesh_object(name, build); obj.data.materials.append(material); return obj


def lathe(name, profile, wall, axis_z, material, segments=40):
    """Open optic tube along +Y: outer skin from (y, radius) pairs, inner bore `wall`
    thinner, joined by rings at both ends so the lenses inside can be seen."""
    def build(bm):
        def ring(y, r):
            return bmesh.ops.create_circle(bm, segments=segments, radius=r,
                                           matrix=Matrix.Translation((0, y, axis_z)) @ Matrix.Rotation(math.radians(90), 4, "X"))["verts"]
        outer = [ring(y, r) for y, r in profile]
        inner = [ring(y, r - wall) for y, r in profile]
        def bridge(a, b, flip=False):
            for i in range(len(a)):
                quad = (a[i], a[(i + 1) % len(a)], b[(i + 1) % len(b)], b[i])
                bm.faces.new(quad[::-1] if flip else quad)
        for a, b in zip(outer, outer[1:]): bridge(a, b)
        for a, b in zip(inner, inner[1:]): bridge(a, b, True)
        bridge(inner[0], outer[0]); bridge(outer[-1], inner[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    obj = mesh_object(name, build); obj.data.materials.append(material)
    return obj


def finish(obj, bevel=.0012, segments=2, angle=40):
    bpy.context.view_layer.objects.active = obj
    for p in obj.data.polygons: p.use_smooth = True
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL"); mod.width = bevel; mod.segments = segments
        mod.limit_method = "ANGLE"; mod.angle_limit = math.radians(angle); mod.harden_normals = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = obj.modifiers.new("normals", "WEIGHTED_NORMAL"); mod.keep_sharp = True
    obj.data.use_auto_smooth = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def uv_box(obj, scale=12.0):
    bpy.ops.object.select_all(action="DESELECT"); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=1 / scale, correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1: bpy.ops.object.join()
    result = bpy.context.view_layer.objects.active; result.name = name; result.data.name = name
    return result


def rail_clamp(length, width, material, height=.012):
    """Picatinny clamp: base plate, recoil lug and the cross-bolt nut on the left."""
    base = finish(box("clamp", (width, length, height), (0, 0, height * .5), material), .001)
    lug = finish(box("lug", (width * .55, .004, .004), (0, length * .15, -.001), material), .0006)
    nut = finish(cylinder("nut", .0055, .006, (-width * .5 - .002, 0, height * .45), material, "X", 6), .0006, 1)
    jaw = finish(box("jaw", (.004, length * .9, height * .75), (width * .5 + .001, 0, height * .4), material), .0008)
    return [base, lug, nut, jaw]


def lens(name, radius, y, z, material, segments=40, shape="disc", size=None):
    def build(bm):
        if shape == "disc":
            bmesh.ops.create_circle(bm, cap_ends=True, segments=segments, radius=radius,
                                    matrix=Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(90), 4, "X"))
        else:
            bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=.5,
                                  matrix=Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(90), 4, "X") @ Matrix.Diagonal((size[0], size[1], 1, 1)))
    obj = mesh_object(name, build); obj.data.materials.append(material)
    # Planar UVs centred on the sight line so the reticle texture sits on it.
    uv = obj.data.uv_layers.new(name="UVMap")
    extent = (radius, radius) if shape == "disc" else (size[0] * .5, size[1] * .5)
    for loop in obj.data.loops:
        co = obj.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((co.x / extent[0]) * .5 + .5, ((co.z - z) / extent[1]) * .5 + .5)
    return obj


# ---------------------------------------------------------------- attachments
def red_dot(m):
    """Micro red dot (T-2 class) on a riser: origin = rail contact, sight line at eye height."""
    axis = .052
    parts = rail_clamp(.03, .022, m["anodized"])
    parts.append(finish(box("riser", (.018, .028, axis - .016), (0, 0, (axis + .008) * .5 - .004), m["anodized"]), .0015))
    body = finish(lathe("tube", [(-.026, .0156), (-.02, .0156), (-.019, .0145), (.019, .0145), (.02, .0158), (.027, .0158)], .0022, axis, m["anodized"]), 0)
    parts += [body,
              finish(cylinder("turret_top", .0065, .008, (0, .002, axis + .016), m["anodized"], "Z", 24), .0008),
              finish(cylinder("turret_side", .0065, .008, (.016, .002, axis), m["anodized"], "X", 24), .0008),
              finish(cylinder("cap", .007, .003, (0, .002, axis + .021), m["rubber"], "Z", 24), .0006)]
    for p in parts: uv_box(p)
    shell = join(parts, "Body")
    glass = lens("Glass", .0118, .012, axis, m["glass"])
    reticle = lens("Reticle", .0118, .0115, axis, m["red_dot"])
    return [shell, glass, reticle], {"eye": to_godot((0, -.025, axis)), "lens": to_godot((0, .0115, axis))}


def holographic(m):
    """EOTech-style window sight: hood, window, side battery housing, rail clamp."""
    axis = .045
    parts = rail_clamp(.05, .03, m["polymer"])
    parts.append(finish(box("base", (.036, .09, .016), (0, -.002, .02), m["polymer"]), .0025))
    parts.append(finish(box("battery", (.03, .034, .016), (0, .03, .033), m["polymer"]), .002))
    for side in (-1, 1):
        parts.append(finish(box("wall", (.004, .05, .036), (side * .019, -.016, .045), m["anodized"]), .0012))
    parts.append(finish(box("roof", (.042, .05, .005), (0, -.016, .064), m["anodized"]), .0015))
    parts.append(finish(box("buttons", (.016, .006, .006), (0, -.044, .026), m["rubber"]), .001))
    for p in parts: uv_box(p)
    shell = join(parts, "Body")
    glass = lens("Glass", 0, -.004, axis, m["glass"], shape="rect", size=(.034, .032))
    reticle = lens("Reticle", 0, -.0045, axis, m["holo"], shape="rect", size=(.034, .032))
    return [shell, glass, reticle], {"eye": to_godot((0, -.04, axis)), "lens": to_godot((0, -.0045, axis))}


def scope(m):
    """3x fixed scope with objective and ocular bells, turrets and two ring mounts."""
    axis = .046
    parts = []
    for y in (-.035, .045):
        parts += rail_clamp(.016, .026, m["anodized"])
        for p in parts[-4:]: p.location.y += y
        parts.append(finish(cylinder("ring", .0175, .012, (0, y, axis), m["anodized"]), .001))
        parts.append(finish(box("stem", (.014, .012, axis - .022), (0, y, .012 + (axis - .022) * .5 - .002), m["anodized"]), .0012))
    profile = [(-.1, .019), (-.085, .0195), (-.075, .0155), (-.06, .015), (.05, .015), (.07, .0155), (.085, .0215), (.108, .0215)]
    tube = lathe("tube", profile, .0022, axis, m["anodized"]); parts.append(finish(tube, 0))
    parts += [finish(cylinder("elevation", .009, .014, (0, .005, axis + .019), m["anodized"], "Z", 28), .001),
              finish(cylinder("windage", .009, .014, (.019, .005, axis), m["anodized"], "X", 28), .001),
              finish(lathe("eyepiece", [(-.102, .0205), (-.086, .0205)], .003, axis, m["rubber"]), 0)]
    for p in parts: uv_box(p)
    shell = join(parts, "Body")
    glass = lens("Glass", .0195, .107, axis, m["glass"])
    ocular = lens("Ocular", .0175, -.1015, axis, m["glass"])
    return [shell, glass, ocular], {"eye": to_godot((0, -.18, axis)), "lens": to_godot((0, -.1015, axis))}


def suppressor(m):
    parts = [finish(cylinder("can", .019, .165, (0, .0975, 0), m["cerakote"]), .003, 3),
             finish(cylinder("mount", .013, .02, (0, .008, 0), m["anodized"], segments=6), .001),
             finish(cylinder("cap", .0165, .004, (0, .181, 0), m["anodized"]), .001)]
    for p in parts: uv_box(p, 10)
    body = join(parts, "Body")
    return [body], {"muzzle": to_godot((0, .183, 0))}


def compensator(m):
    parts = [finish(cylinder("body", .0115, .05, (0, .025, 0), m["anodized"], segments=8), .0012)]
    for i, y in enumerate((.014, .026, .038)):
        for side in (-1, 1):
            parts.append(finish(box("port", (.006, .006, .016), (side * .0105, y, .004), m["rubber"]), .0008))
    for p in parts: uv_box(p, 14)
    return [join(parts, "Body")], {"muzzle": to_godot((0, .05, 0))}


def vertical_grip(m):
    parts = rail_clamp(.035, .024, m["polymer"])
    for p in parts: p.rotation_euler.y = math.pi
    grip = cylinder("grip", .0145, .095, (0, 0, -.06), m["polymer"], "Z", 24, .0135)
    parts += [finish(grip, .002), finish(cylinder("cap", .015, .008, (0, 0, -.108), m["rubber"], "Z", 24), .0015)]
    for z in np.linspace(-.03, -.095, 6):
        parts.append(finish(cylinder("groove", .0152, .003, (0, 0, float(z)), m["rubber"], "Z", 24), .0006, 1))
    for p in parts: uv_box(p)
    return [join(parts, "Body")], {"hand": to_godot((0, 0, -.06)), "axis": [0, -1, 0]}


def angled_grip(m):
    parts = rail_clamp(.06, .024, m["polymer"])
    for p in parts: p.rotation_euler.y = math.pi
    def build(bm):
        profile = [(-.04, 0), (.035, 0), (.03, -.012), (-.005, -.03), (-.045, -.006)]
        top = [bm.verts.new((-.012, y, z)) for y, z in profile]; bottom = [bm.verts.new((.012, y, z)) for y, z in profile]
        bm.faces.new(top); bm.faces.new(bottom[::-1])
        for i in range(len(profile)): bm.faces.new((top[i], top[(i + 1) % len(top)], bottom[(i + 1) % len(top)], bottom[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    wedge = mesh_object("wedge", build); wedge.data.materials.append(m["polymer"])
    parts.append(finish(wedge, .004, 3, 30))
    for p in parts: uv_box(p)
    return [join(parts, "Body")], {"hand": to_godot((0, -.004, -.018)), "axis": [0, -.6, .8]}


def bipod(m):
    parts = [finish(box("clamp", (.03, .03, .018), (0, 0, -.009), m["anodized"]), .0015),
             finish(cylinder("pivot", .006, .05, (0, 0, -.02), m["anodized"], "X"), .001)]
    for side in (-1, 1):
        # Legs folded forward along the barrel, as carried.
        leg = finish(cylinder("leg", .0055, .2, (side * .019, .1, -.026), m["anodized"]), .0008)
        foot = finish(cylinder("foot", .008, .016, (side * .019, .202, -.026), m["rubber"]), .001)
        parts += [leg, foot]
    for p in parts: uv_box(p)
    return [join(parts, "Body")], {}


def pull_tab(m):
    parts = [finish(box("loop", (.016, .045, .006), (0, 0, -.003), m["rubber"]), .0025, 3),
             finish(box("pull", (.018, .012, .018), (0, .01, -.014), m["rubber"]), .003, 3)]
    for p in parts: uv_box(p)
    return [join(parts, "Body")], {}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OUT.mkdir(parents=True, exist_ok=True); TEXTURES.mkdir(parents=True, exist_ok=True)
    m = {"anodized": pbr_material("Anodized_Black", finish_textures("anodized", (.035, .036, .038), .42, .65, .25, 1.2)),
         "polymer": pbr_material("Polymer_Black", finish_textures("polymer", (.045, .045, .043), .68, 0, .3, 2.0)),
         "rubber": pbr_material("Rubber_Black", finish_textures("rubber", (.03, .03, .03), .9, 0, .2, 3.0)),
         "cerakote": pbr_material("Cerakote_Grey", finish_textures("cerakote", (.11, .11, .1), .6, .25, .22, 1.6)),
         "glass": glass_material(),
         "red_dot": reticle_material("Reticle_RedDot", reticle_texture("reticle_dot", False)),
         "holo": reticle_material("Reticle_Holo", reticle_texture("reticle_holo", True))}
    builders = {"reflex": red_dot, "holographic": holographic, "scope": scope, "suppressor": suppressor, "compensator": compensator,
                "vertical": vertical_grip, "angled": angled_grip, "bipod": bipod, "fast": pull_tab}
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {"assets": {}}
    report = manifest.setdefault("attachments", {})
    for key, build in builders.items():
        for obj in list(bpy.context.scene.objects): bpy.data.objects.remove(obj, do_unlink=True)
        for mesh in [m for m in bpy.data.meshes if m.users == 0]: bpy.data.meshes.remove(mesh)
        objects, sockets = build(m)
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
        bpy.ops.export_scene.gltf(filepath=str(OUT / f"{key}.gltf"), export_format="GLTF_SEPARATE", export_texture_dir="textures",
                                  export_image_format="AUTO", export_yup=True, export_apply=True, export_materials="EXPORT")
        report[key] = {"model": f"res://content/models/weapons/attachments/{key}.gltf", "sockets": sockets, "triangles": tris,
                       "creator": "FPS Mode (generated by tools/blender/build_attachments.py)", "license": "CC0-1.0"}
        print("ATTACHMENT", key, tris)
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("ATTACHMENTS PASS", len(builders))


main()
