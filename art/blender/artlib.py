"""
Small modelling kit for the game's stylised art (run inside headless Blender).

Space: X right, Y back (models FACE -Y), Z up, 1 unit = 1 stud.
A model is a set of parts; each part is one mesh object (one Roblox MeshPart) made of smooth
primitives with vertex colours. Part names carry the rig:
    Body                 static, welded to Root
    Head@Head            a moving part with joint role "Head"
    Head@Head/Eyes       static detail welded to the part named before the slash
A part's hinge is exported as a tiny marker object "Hinge_<part>".
"""
import bpy, bmesh, math, json, os
from mathutils import Vector, Euler, Matrix

PARTS = {}      # name -> list of objects (primitives) before joining
HINGES = {}     # part name -> Vector
META = {}       # part name -> dict(material=..., reflectance=...)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PARTS.clear(); HINGES.clear(); META.clear()


def _srgb_to_linear(c):
    return tuple(((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c)


def rgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


def _paint(obj, color, shade=0.18, tint=None):
    """Vertex colours: the base colour, a little darker underneath (fake ambient light)."""
    mesh = obj.data
    attr = mesh.color_attributes.new(name="Col", type='BYTE_COLOR', domain='CORNER')
    zs = [v.co.z for v in mesh.vertices]
    lo, hi = min(zs), max(zs)
    span = max(hi - lo, 1e-6)
    lin = _srgb_to_linear(color)
    lin2 = _srgb_to_linear(tint) if tint else None
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index]
            t = (v.co.z - lo) / span
            k = 1.0 - shade * (1.0 - t) ** 1.5
            base = lin
            if lin2:
                m = min(1.0, t * 2.2)
                base = tuple(lin2[i] + (lin[i] - lin2[i]) * m for i in range(3))
            attr.data[li].color = (base[0] * k, base[1] * k, base[2] * k, 1.0)


def _register(part, obj):
    PARTS.setdefault(part, []).append(obj)
    return obj


def _finish(obj, part, loc, scale, rot, color, shade, tint, smooth=True):
    obj.scale = scale
    obj.rotation_euler = Euler([math.radians(a) for a in rot], 'XYZ')
    obj.location = loc
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if smooth:
        bpy.ops.object.shade_smooth()
    _paint(obj, color, shade, tint)
    obj.select_set(False)
    return _register(part, obj)


def ball(part, loc, scale, color, rot=(0, 0, 0), detail=2, shade=0.18, tint=None):
    """An ellipsoid. scale = radii (x, y, z) or one number. detail 1 (tiny) .. 3 (big)."""
    if isinstance(scale, (int, float)):
        scale = (scale, scale, scale)
    segs, rings = {0: (8, 5), 1: (10, 6), 2: (16, 10), 3: (24, 14), 4: (32, 18)}[detail]
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=segs, ring_count=rings)
    return _finish(bpy.context.object, part, loc, scale, rot, color, shade, tint)


def cone(part, loc, radius, height, color, rot=(0, 0, 0), top=0.0, verts=14, shade=0.15, tint=None, scale=(1, 1, 1), smooth=True):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=top, depth=height)
    return _finish(bpy.context.object, part, loc, scale, rot, color, shade, tint, smooth)


def tube(part, loc, radius, height, color, rot=(0, 0, 0), verts=14, shade=0.15, tint=None, scale=(1, 1, 1), smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height)
    obj = bpy.context.object
    if smooth:
        # soften the rims
        bev = obj.modifiers.new("b", 'BEVEL'); bev.width = min(radius, height) * 0.25; bev.segments = 2
        bpy.ops.object.modifier_apply(modifier="b")
    return _finish(obj, part, loc, scale, rot, color, shade, tint)


def box(part, loc, size, color, rot=(0, 0, 0), bevel=0.08, shade=0.12, tint=None):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        bev = obj.modifiers.new("b", 'BEVEL'); bev.width = bevel; bev.segments = 3
        bpy.ops.object.modifier_apply(modifier="b")
    return _finish(obj, part, loc, (1, 1, 1), rot, color, shade, tint)


def ring(part, loc, major, minor, color, rot=(0, 0, 0), shade=0.1, scale=(1, 1, 1), segs=24, msegs=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=segs, minor_segments=msegs)
    return _finish(bpy.context.object, part, loc, scale, rot, color, shade, None)


def capsule(part, a, b, radius, color, detail=2, shade=0.15, tint=None, taper=1.0):
    """A rounded limb from point a to point b (taper < 1: thinner at b)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    segs = {0: 5, 1: 8, 2: 12, 3: 16}[detail]
    bm = bmesh.new()
    rings = 2 if detail == 0 else 5
    # profile: hemisphere, shaft, hemisphere
    pts = []
    for i in range(rings + 1):
        ang = math.pi / 2 * i / rings
        pts.append((-math.cos(ang) * radius, math.sin(ang) * radius, 0))          # bottom cap
    for i in range(rings + 1):
        ang = math.pi / 2 * i / rings
        r2 = radius * taper
        pts.append((length + math.sin(ang) * r2, math.cos(ang) * r2, 1))
    verts_rows = []
    for (x, r, _k) in pts:
        row = []
        for s in range(segs):
            th = 2 * math.pi * s / segs
            row.append(bm.verts.new((r * math.cos(th), r * math.sin(th), x)))
        verts_rows.append(row)
    for i in range(len(verts_rows) - 1):
        for s in range(segs):
            s2 = (s + 1) % segs
            bm.faces.new((verts_rows[i][s], verts_rows[i][s2], verts_rows[i + 1][s2], verts_rows[i + 1][s]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.holes_fill(bm, edges=bm.edges)
    mesh = bpy.data.meshes.new("cap")
    bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new("cap", mesh)
    bpy.context.collection.objects.link(obj)
    quat = Vector((0, 0, 1)).rotation_difference(d.normalized()) if length > 1e-6 else None
    if quat:
        obj.rotation_mode = 'QUATERNION'
        obj.rotation_quaternion = quat
    obj.location = a
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.rotation_mode = 'XYZ'
    _paint(obj, color, shade, tint)
    obj.select_set(False)
    return _register(part, obj)


def rot_to(direction):
    """Euler degrees that turn +Z onto a direction."""
    e = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_euler('XYZ')
    return tuple(math.degrees(a) for a in e)


def fan(part, root, tips, color, edge=None, thickness=0.035, scallop=0.22, shade=0.05):
    """A flat wing membrane: a fan from root through the finger tips, with scalloped edges."""
    bm = bmesh.new()
    r = bm.verts.new(root)
    rim = []
    for i in range(len(tips) - 1):
        a, b = Vector(tips[i]), Vector(tips[i + 1])
        rim.append(a)
        for j in (1, 2, 3):
            t = j / 4.0
            p = a.lerp(b, t)
            pull = math.sin(t * math.pi) * scallop
            rim.append(p.lerp(Vector(root), pull))
    rim.append(Vector(tips[-1]))
    vs = [bm.verts.new(p) for p in rim]
    for i in range(len(vs) - 1):
        bm.faces.new((r, vs[i], vs[i + 1]))
    mesh = bpy.data.meshes.new('fan'); bm.to_mesh(mesh); bm.free()
    obj = bpy.data.objects.new('fan', mesh); bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj; obj.select_set(True)
    sol = obj.modifiers.new('s', 'SOLIDIFY'); sol.thickness = thickness; sol.offset = 0
    bpy.ops.object.modifier_apply(modifier='s')
    bpy.ops.object.shade_flat()
    _paint(obj, color, shade, edge)
    obj.select_set(False)
    return _register(part, obj)


def decimate_all(objs, budget):
    """Brings the whole model under a triangle budget (big parts give the most)."""
    total = tri_count(objs)
    if total <= budget:
        return total
    ratio = budget / total
    for o in objs.values():
        o.data.calc_loop_triangles()
        if len(o.data.loop_triangles) > 300:
            bpy.context.view_layer.objects.active = o
            m = o.modifiers.new('d', 'DECIMATE'); m.ratio = max(0.35, ratio)
            bpy.ops.object.modifier_apply(modifier='d')
    return tri_count(objs)


def parse(name):
    """'EarL@EarL^Head' -> (base, role, joint parent, weld parent); 'Head@Head/Face' -> ('Face', None, None, 'Head')"""
    weld = None
    if '/' in name:
        owner, child = name.split('/', 1)
        return child, None, None, owner.split('@')[0]
    base, role, jparent = name, None, None
    if '@' in name:
        base, rest = name.split('@', 1)
        role = rest
        if '^' in rest:
            role, jparent = rest.split('^', 1)
    return base, role, jparent, weld


def hinge(part, loc):
    HINGES[part] = Vector(loc)


def look(part, material="SmoothPlastic", reflectance=0.0):
    META[part] = {"material": material, "reflectance": reflectance}


# ---- common face pieces ----
BLACK = rgb(24, 22, 30)
WHITE = rgb(255, 255, 255)


def eyes(part, y, z, spread, size, color=BLACK, tilt=0.0, highlight=True, squash=0.55):
    """Big glossy eyes on the front (-Y) of a head. y = how far forward the surface is."""
    for side in (-1, 1):
        x = side * spread
        ball(part, (x, y, z), (size * 0.82, size * squash, size), color, rot=(0, 0, side * tilt), detail=2, shade=0.0)
        if highlight:
            ball(part, (x - size * 0.22, y - size * squash * 0.78, z + size * 0.34), (size * 0.30, size * 0.16, size * 0.30), WHITE, detail=1, shade=0.0)
            ball(part, (x + size * 0.26, y - size * squash * 0.80, z - size * 0.30), (size * 0.14, size * 0.08, size * 0.14), WHITE, detail=1, shade=0.0)


def blush(part, y, z, spread, size, color=rgb(255, 140, 170)):
    for side in (-1, 1):
        ball(part, (side * spread, y, z), (size, size * 0.18, size * 0.62), color, detail=1, shade=0.0)


def smile(part, y, z, width, color=BLACK, thickness=0.02):
    """A little 'w' mouth: two short curved strokes."""
    for side in (-1, 1):
        capsule(part, (0, y, z), (side * width, y + 0.01, z - width * 0.45), thickness, color, detail=1, shade=0.0)
        capsule(part, (side * width, y + 0.01, z - width * 0.45), (side * width * 1.7, y + 0.05, z - width * 0.1), thickness, color, detail=1, shade=0.0)


# ---- output ----
def build_objects():
    """Joins every part's primitives into one object per part. Returns {name: object}."""
    out = {}
    for name, objs in PARTS.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = parse(name)[0]
        obj.data.name = obj.name
        # origin at the hinge (or the bounds centre)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
        out[name] = obj
    return out


def tri_count(objs):
    total = 0
    for o in objs.values():
        o.data.calc_loop_triangles()
        total += len(o.data.loop_triangles)
    return total


def export(objs, path_fbx, spec_extra=None):
    markers = []
    for part, loc in HINGES.items():
        bpy.ops.mesh.primitive_cube_add(size=0.02, location=loc)
        m = bpy.context.object
        m.name = "Hinge_" + parse(part)[0]
        markers.append(m)
    bpy.ops.object.select_all(action='DESELECT')
    for o in list(objs.values()) + markers:
        o.select_set(True)
    bpy.ops.export_scene.fbx(filepath=path_fbx, use_selection=True, object_types={'MESH'}, apply_scale_options='FBX_SCALE_ALL',
                             colors_type='SRGB', axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE', bake_space_transform=True)
    spec = {"parts": {}, "tris": tri_count(objs)}
    for name, o in objs.items():
        base, role, jparent, weld = parse(name)
        spec["parts"][o.name] = {"role": role, "jointParent": jparent, "parent": weld, **META.get(name, {})}
    if spec_extra:
        spec.update(spec_extra)
    with open(os.path.splitext(path_fbx)[0] + ".json", "w") as f:
        json.dump(spec, f, indent=1)
    for m in markers:
        bpy.data.objects.remove(m)
    return spec


def render(objs, path_png, size=640, angle=35, elevation=18, distance=None, bg=(0.16, 0.18, 0.26), transparent=False, reuse=False):
    """A quick beauty shot of the model from the front three-quarter."""
    mat = bpy.data.materials.new("VC")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    col = nt.nodes.new("ShaderNodeVertexColor"); col.layer_name = "Col"
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.42
    for o in objs.values():
        o.data.materials.clear(); o.data.materials.append(mat)
    lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
    for o in objs.values():
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
    centre = (lo + hi) / 2
    radius = (hi - lo).length / 2
    dist = distance or radius * 4.4
    a, e = math.radians(angle), math.radians(elevation)
    cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 70
    cam = bpy.data.objects.new("cam", cam_data); bpy.context.collection.objects.link(cam)
    cam.location = centre + Vector((math.sin(a) * math.cos(e) * dist, -math.cos(a) * math.cos(e) * dist, math.sin(e) * dist))
    cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene = bpy.context.scene
    scene.camera = cam
    for name, energy, loc in (() if reuse else (("key", 4.0, (3, -4, 6)), ("fill", 1.5, (-5, -2, 2)), ("rim", 3.0, (0, 5, 4)))):
        ld = bpy.data.lights.new(name, 'SUN'); ld.energy = energy
        lo_ = bpy.data.objects.new(name, ld); bpy.context.collection.objects.link(lo_)
        lo_.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    world = bpy.data.worlds.new("w"); world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
        try:
            scene.render.engine = engine
            break
        except Exception:
            continue
    scene.render.resolution_x = size; scene.render.resolution_y = size
    scene.render.film_transparent = transparent
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'
    scene.render.filepath = path_png
    bpy.ops.render.render(write_still=True)
