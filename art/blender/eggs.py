import sys, os, math, random
sys.path.insert(0, os.path.dirname(__file__))
import bpy, bmesh
from mathutils import Vector
import artlib as A
from artlib import rgb, ball, cone, tube, box, ring, capsule, look, WHITE, BLACK

# An egg is about 2 x 2.6 x 2 studs, centred on the origin at z = 0 .. it stands on z = -1.3.
RX, RZ = 0.98, 1.3
SEAM = 0.18            # height of the zigzag seam over the middle
SEGS = 28


def surface(theta, z, out=1.0):
    """A point on the egg's surface at angle theta and height z (-RZ..RZ)."""
    t = max(-1.0, min(1.0, z / RZ))
    r = RX * math.sqrt(max(0.0, 1 - t * t))
    if z > 0:
        r *= 1 - 0.2 * t              # narrower toward the top
    return Vector((math.cos(theta) * r * out, math.sin(theta) * r * out, z))


def shell(part_top, part_bottom, color, tint, speckle=None, speckle_chance=0.0, seed=1, band=None):
    """The two halves of the shell, meeting in a zigzag."""
    rnd = random.Random(seed)
    rows = 18
    for which, part in (("top", part_top), ("bottom", part_bottom)):
        bm = bmesh.new()
        zs = []
        if which == "top":
            zs = [SEAM + (RZ - SEAM) * (1 - math.cos(math.pi / 2 * i / (rows // 2))) for i in range(rows // 2 + 1)]
        else:
            zs = [-RZ + (RZ + SEAM) * math.sin(math.pi / 2 * i / (rows // 2)) for i in range(rows // 2 + 1)]
        grid = []
        for ri, z in enumerate(zs):
            row = []
            for s in range(SEGS):
                th = 2 * math.pi * s / SEGS
                zz = z
                seam_row = (which == "top" and ri == 0) or (which == "bottom" and ri == len(zs) - 1)
                if seam_row:
                    zz = SEAM + (0.12 if s % 2 == 0 else -0.12)
                row.append(bm.verts.new(surface(th, min(zz, RZ))))
            grid.append(row)
        for ri in range(len(grid) - 1):
            for s in range(SEGS):
                s2 = (s + 1) % SEGS
                bm.faces.new((grid[ri][s], grid[ri][s2], grid[ri + 1][s2], grid[ri + 1][s]))
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new("shell"); bm.to_mesh(mesh); bm.free()
        obj = bpy.data.objects.new("shell", mesh); bpy.context.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj; obj.select_set(True)
        bpy.ops.object.shade_smooth()
        obj.select_set(False)
        # colours: base with a darker foot, speckles, and an optional band
        attr = mesh.color_attributes.new(name="Col", type='BYTE_COLOR', domain='CORNER')
        lin = A._srgb_to_linear(color); lin_t = A._srgb_to_linear(tint)
        lin_s = A._srgb_to_linear(speckle) if speckle else None
        lin_b = A._srgb_to_linear(band[0]) if band else None
        spots = {v.index: (rnd.random() < speckle_chance) for v in mesh.vertices}
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                v = mesh.vertices[mesh.loops[li].vertex_index]
                t = (v.co.z + RZ) / (2 * RZ)
                m = min(1.0, t * 1.6)
                c = tuple(lin_t[i] + (lin[i] - lin_t[i]) * m for i in range(3))
                if lin_s and spots[v.index]:
                    c = lin_s
                if lin_b and band[1] <= v.co.z <= band[2]:
                    c = lin_b
                attr.data[li].color = (c[0], c[1], c[2], 1.0)
        A._register(part, obj)


def crack(part, start, steps, seed, color=rgb(40, 30, 30), radius=0.028, branch=True):
    """A jagged crack wandering over the shell from (theta, z)."""
    rnd = random.Random(seed)
    th, z = start
    pts = [(th, z)]
    for i in range(steps):
        th += rnd.uniform(-0.22, 0.22)
        z += rnd.uniform(0.1, 0.22) * (1 if i % 2 == 0 else -0.35)
        pts.append((th, z))
    for i in range(len(pts) - 1):
        a = surface(pts[i][0], pts[i][1], 1.012); b = surface(pts[i + 1][0], pts[i + 1][1], 1.012)
        capsule(part, a, b, radius, color, detail=0, shade=0)
        if branch and i % 2 == 1:
            c = surface(pts[i][0] + rnd.choice((-1, 1)) * 0.3, pts[i][1] + rnd.uniform(-0.1, 0.2), 1.012)
            capsule(part, a, c, radius * 0.75, color, detail=0, shade=0)


def seam_crack(part, color=rgb(40, 30, 30)):
    """The last crack: all the way round the zigzag seam."""
    for s in range(SEGS):
        z0 = SEAM + (0.12 if s % 2 == 0 else -0.12)
        z1 = SEAM + (0.12 if (s + 1) % 2 == 0 else -0.12)
        a = surface(2 * math.pi * s / SEGS, z0, 1.012); b = surface(2 * math.pi * (s + 1) / SEGS, z1, 1.012)
        capsule(part, a, b, 0.03, color, detail=0, shade=0)


def cracks(front=-math.pi / 2):
    crack("Crack1", (front + 0.15, -0.35), 4, 11)
    crack("Crack2", (front - 0.9, -0.5), 5, 12)
    crack("Crack2", (front + 1.2, 0.0), 3, 13)
    crack("Crack3", (front + 2.6, -0.6), 5, 14)
    crack("Crack3", (front - 2.0, 0.1), 4, 15)
    crack("Crack3", (front + 0.5, 0.45), 3, 16)
    seam_crack("Crack4")


def Dusty():
    shell("ShellTop", "ShellBottom", rgb(226, 196, 150), rgb(176, 136, 90), speckle=rgb(140, 100, 60), speckle_chance=0.14, seed=2)
    cracks()


def Shiny():
    shell("ShellTop", "ShellBottom", rgb(120, 214, 255), rgb(40, 130, 235), speckle=WHITE, speckle_chance=0.08, seed=3)
    for i, (th, z, s) in enumerate(((-1.2, 0.7, 0.16), (-2.2, -0.3, 0.12), (-0.6, -0.55, 0.1))):      # sparkles
        p = surface(th, z, 1.02)
        part = "ShellTop" if z > SEAM else "ShellBottom"
        ball(part, p, (s, s * 0.3, s * 0.3), WHITE, rot=(0, 0, math.degrees(th) + 90), detail=1, shade=0)
        ball(part, p, (s * 0.3, s * 0.3, s), WHITE, detail=1, shade=0)
    look("ShellTop", reflectance=0.15); look("ShellBottom", reflectance=0.15)
    cracks()


def Royal():
    gold = rgb(255, 205, 50)
    shell("ShellTop", "ShellBottom", rgb(190, 90, 255), rgb(110, 30, 190), speckle=rgb(255, 170, 255), speckle_chance=0.06, seed=4, band=(gold, -0.62, -0.42))
    # a little crown on top
    ring("ShellTop", (0, 0, 1.06), 0.42, 0.07, gold, segs=20, msegs=8)
    for i in range(5):
        a = 2 * math.pi * i / 5
        cone("ShellTop", (math.cos(a) * 0.42, math.sin(a) * 0.42, 1.26), 0.1, 0.34, gold, verts=8)
        ball("ShellTop", (math.cos(a) * 0.42, math.sin(a) * 0.42, 1.45), 0.06, rgb(255, 70, 100), detail=1, shade=0)
    for i in range(8):                                                                               # gems on the band
        a = 2 * math.pi * i / 8
        ball("ShellBottom", surface(a, -0.52, 1.02), 0.075, rgb(90, 230, 255) if i % 2 else rgb(255, 70, 100), detail=1, shade=0)
    look("ShellTop", reflectance=0.1); look("ShellBottom", reflectance=0.1)
    cracks()


def Attic():
    shell("ShellTop", "ShellBottom", rgb(196, 150, 96), rgb(120, 80, 44), speckle=rgb(236, 206, 150), speckle_chance=0.1, seed=6, band=(rgb(100, 66, 36), -0.1, -0.02))
    # patched up with a plank and a cobweb-grey dust cap
    box("ShellBottom", surface(-math.pi / 2 + 0.5, -0.55, 1.0), (0.5, 0.08, 0.2), rgb(150, 104, 60), rot=(0, 0, 28), bevel=0.02)
    for dx in (-0.17, 0.17):
        p = surface(-math.pi / 2 + 0.5, -0.55, 1.0)
        ball("ShellBottom", (p.x + dx, p.y - 0.06, p.z), 0.035, rgb(90, 90, 100), detail=0, shade=0)
    cracks()


def GiftBox():
    pink = rgb(255, 80, 140); pink_d = rgb(215, 40, 110); gold = rgb(255, 214, 60)
    box("ShellBottom", (0, 0, -0.35), (1.9, 1.9, 1.9), pink, bevel=0.08, tint=pink_d)
    box("ShellBottom", (0, 0, -0.35), (0.42, 1.94, 1.94), gold, bevel=0.03)
    box("ShellBottom", (0, 0, -0.35), (1.94, 0.42, 1.94), gold, bevel=0.03)
    box("ShellTop", (0, 0, 0.78), (2.12, 2.12, 0.5), rgb(255, 120, 170), bevel=0.08, tint=pink)
    box("ShellTop", (0, 0, 0.78), (0.46, 2.16, 0.54), gold, bevel=0.03)
    box("ShellTop", (0, 0, 0.78), (2.16, 0.46, 0.54), gold, bevel=0.03)
    for side in (-1, 1):                                                                             # the bow
        ball("ShellTop", (side * 0.34, 0, 1.22), (0.36, 0.2, 0.22), gold, rot=(0, side * -25, 0), detail=2)
    ball("ShellTop", (0, 0, 1.14), (0.16, 0.18, 0.16), rgb(255, 190, 40), detail=2)
    # "cracks": light leaking from under the lid, a little more each tap
    glow = rgb(255, 250, 190)
    for name, spans in (("Crack1", [(-0.5, 0.1)]), ("Crack2", [(0.2, 0.8), (-0.9, -0.6)]), ("Crack3", [(-0.95, 0.95)]), ("Crack4", [(-1.0, 1.0)])):
        for (x0, x1) in spans:
            box(name, ((x0 + x1) / 2, -1.0, 0.55), (abs(x1 - x0), 0.06, 0.07 if name != "Crack4" else 0.12), glow, bevel=0.0, shade=0)
            if name in ("Crack3", "Crack4"):
                box(name, (1.0, (x0 + x1) / 2, 0.55), (0.06, abs(x1 - x0), 0.07 if name != "Crack4" else 0.12), glow, bevel=0.0, shade=0)
                box(name, (-1.0, (x0 + x1) / 2, 0.55), (0.06, abs(x1 - x0), 0.07 if name != "Crack4" else 0.12), glow, bevel=0.0, shade=0)


EGGS = {"Dusty": Dusty, "Shiny": Shiny, "Royal": Royal, "Attic": Attic, "GiftBox": GiftBox}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir = args[0]
    names = args[1:] or list(EGGS.keys())
    for name in names:
        A.reset()
        EGGS[name]()
        objs = A.build_objects()
        spec = A.export(objs, os.path.join(out_dir, "Egg_" + name + ".fbx"))
        A.render(objs, os.path.join(out_dir, "Egg_" + name + ".png"), size=512, angle=20, elevation=10)
        print("BUILT", name, "tris", spec["tris"], "parts", len(spec["parts"]))
