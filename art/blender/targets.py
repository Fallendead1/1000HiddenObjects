import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import bpy
import artlib as A
from artlib import rgb, ball, cone, tube, box, ring, capsule, look, WHITE, BLACK

GOLD = rgb(255, 205, 50); GOLD_D = rgb(235, 140, 10)
# Hidden objects STAND in the X-Z plane (thin along Y), about 2.2 studs across.


def gold_look(part="Gold"):
    look(part, reflectance=0.32)


def GoldenKey():
    g = "Gold"
    # the bow: a big ring with a smaller ring inside and three little balls on top (a crown)
    ring(g, (-0.72, 0, 0), 0.4, 0.115, GOLD, rot=(90, 0, 0), segs=28, msegs=10)
    ring(g, (-0.72, 0, 0), 0.2, 0.05, GOLD, rot=(90, 0, 0), segs=20, msegs=8)
    for a in (60, 90, 120):
        r = math.radians(a)
        ball(g, (-0.72 + math.cos(r) * 0.56, 0, math.sin(r) * 0.56), 0.085, GOLD, detail=2)
    # collar, shaft, tip
    tube(g, (-0.27, 0, 0), 0.15, 0.1, GOLD, rot=(0, 90, 0), verts=18)
    tube(g, (-0.17, 0, 0), 0.12, 0.08, GOLD, rot=(0, 90, 0), verts=18)
    tube(g, (0.45, 0, 0), 0.085, 1.25, GOLD, rot=(0, 90, 0), verts=16, tint=GOLD_D)
    ball(g, (1.09, 0, 0), (0.11, 0.11, 0.11), GOLD, detail=2)
    # the bit (teeth)
    box(g, (0.62, 0, -0.27), (0.16, 0.13, 0.42), GOLD, bevel=0.03, tint=GOLD_D)
    box(g, (0.9, 0, -0.22), (0.16, 0.13, 0.32), GOLD, bevel=0.03, tint=GOLD_D)
    box(g, (0.76, 0, -0.12), (0.2, 0.11, 0.12), GOLD, bevel=0.02)
    gold_look()
    ball("Gem", (-0.72, 0, 0), (0.13, 0.1, 0.13), rgb(255, 60, 90), detail=2, shade=0)
    look("Gem", reflectance=0.45)


def GrandmasRing():
    g = "Gold"
    ring(g, (0, 0, -0.2), 0.72, 0.11, GOLD, rot=(90, 0, 0), segs=36, msegs=12)
    for side in (-1, 1):                                                        # little shoulders with side stones
        ball(g, (side * 0.3, 0, 0.5), (0.16, 0.13, 0.12), GOLD, detail=2)
    tube(g, (0, 0, 0.58), 0.3, 0.14, GOLD, verts=16)                            # the setting's cup
    for i in range(6):                                                           # prongs
        a = math.radians(i * 60 + 30)
        capsule(g, (math.cos(a) * 0.27, math.sin(a) * 0.27, 0.6), (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.95), 0.04, GOLD, detail=1)
    gold_look()
    d = "Gem"
    ice = rgb(200, 240, 255)
    cone(d, (0, 0, 0.8), 0.44, 0.3, ice, rot=(180, 0, 0), verts=8, shade=0.0, smooth=False)            # pavilion (point down)
    cone(d, (0, 0, 1.06), 0.44, 0.22, WHITE, top=0.26, verts=8, shade=0.0, smooth=False)               # crown with a flat table
    for side in (-1, 1):
        cone(d, (side * 0.3, 0, 0.62), 0.1, 0.12, ice, top=0.05, verts=6, shade=0, smooth=False)
    look(d, material="Glass", reflectance=0.5)


def GoldenRemote():
    g = "Gold"
    box(g, (0, 0, 0), (0.78, 0.26, 2.2), GOLD, bevel=0.12, tint=GOLD_D)
    box(g, (0, -0.02, 0.62), (0.62, 0.26, 0.7), rgb(255, 225, 120), bevel=0.06)                        # raised top panel
    gold_look()
    b = "Details"
    tube(b, (-0.2, -0.15, 0.92), 0.085, 0.06, rgb(240, 50, 60), rot=(90, 0, 0), verts=14, shade=0)     # power
    ring(b, (0, -0.15, 0.42), 0.2, 0.05, rgb(60, 60, 80), rot=(90, 0, 0), segs=20, msegs=6)            # d-pad ring
    tube(b, (0, -0.15, 0.42), 0.09, 0.06, WHITE, rot=(90, 0, 0), verts=12, shade=0)
    colors = [WHITE, WHITE, WHITE, rgb(90, 200, 255), rgb(120, 230, 120), rgb(255, 150, 60)]
    for row in range(4):
        for col in range(3):
            c = colors[(row + col) % len(colors)] if row == 3 else WHITE
            tube(b, (-0.2 + col * 0.2, -0.15, -0.05 - row * 0.24), 0.065, 0.05, c, rot=(90, 0, 0), verts=10, shade=0)
    tube(b, (0, 0, 1.12), 0.1, 0.06, rgb(60, 20, 30), verts=12, shade=0)                                # the IR window on top


def GoldenWrench():
    g = "Gold"
    box(g, (0, 0, -0.1), (0.3, 0.13, 1.35), GOLD, bevel=0.06, tint=GOLD_D)                              # handle
    box(g, (0, -0.02, -0.1), (0.12, 0.14, 0.95), rgb(255, 228, 120), bevel=0.03)                        # the groove's highlight
    # open jaw on top: a rounded base with two prongs
    tube(g, (0, 0, 0.7), 0.4, 0.15, GOLD, rot=(90, 0, 0), verts=24)
    for side in (-1, 1):
        box(g, (side * 0.29, 0, 0.98), (0.22, 0.15, 0.42), GOLD, bevel=0.05, tint=GOLD_D)
    # ring end at the bottom
    ring(g, (0, 0, -0.9), 0.22, 0.09, GOLD, rot=(90, 0, 0), segs=22, msegs=8, scale=(1, 1, 1))
    gold_look()


def TreasureMap():
    paper = rgb(240, 214, 160); paper_d = rgb(205, 165, 100); ink = rgb(110, 70, 35)
    p = "Paper"
    box(p, (0, 0, 0), (1.72, 0.05, 1.18), paper, bevel=0.01, tint=paper_d)
    for side in (-1, 1):                                                                                 # rolled ends
        tube(p, (side * 0.92, 0, 0), 0.13, 1.3, paper, verts=14, tint=paper_d)
        ball(p, (side * 0.92, 0, 0.68), (0.09, 0.09, 0.05), rgb(200, 150, 60), detail=1)
        ball(p, (side * 0.92, 0, -0.68), (0.09, 0.09, 0.05), rgb(200, 150, 60), detail=1)
    d = "Details"
    ball(d, (-0.35, -0.035, 0.12), (0.34, 0.015, 0.26), rgb(120, 190, 110), detail=2, shade=0)          # island
    ball(d, (-0.12, -0.035, -0.12), (0.2, 0.015, 0.14), rgb(120, 190, 110), detail=2, shade=0)
    pts = [(-0.62, -0.38), (-0.45, -0.3), (-0.3, -0.34), (-0.12, -0.26), (0.05, -0.12), (0.2, -0.02), (0.34, 0.12)]
    for (x, z) in pts:                                                                                   # dotted path
        ball(d, (x, -0.04, z), (0.035, 0.012, 0.035), ink, detail=0, shade=0)
    for a in (45, -45):                                                                                  # the red X
        r = math.radians(a)
        capsule(d, (0.52 - math.cos(r) * 0.16, -0.045, 0.28 - math.sin(r) * 0.16), (0.52 + math.cos(r) * 0.16, -0.045, 0.28 + math.sin(r) * 0.16), 0.04, rgb(225, 40, 50), detail=1, shade=0)
    ring(d, (0.5, -0.035, -0.3), 0.14, 0.018, ink, rot=(90, 0, 0), segs=16, msegs=4)                   # compass
    cone(d, (0.5, -0.04, -0.22), 0.04, 0.2, rgb(225, 40, 50), verts=4, scale=(1, 0.3, 1), shade=0)
    cone(d, (0.5, -0.04, -0.38), 0.04, 0.2, ink, rot=(180, 0, 0), verts=4, scale=(1, 0.3, 1), shade=0)


TARGETS = {"GoldenKey": GoldenKey, "GrandmasRing": GrandmasRing, "GoldenRemote": GoldenRemote, "GoldenWrench": GoldenWrench, "TreasureMap": TreasureMap}


def notch_wrench(objs):
    """Cuts the open jaw into the wrench head."""
    gold = objs.get("Gold")
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 1.02))
    cutter = bpy.context.object
    cutter.scale = (0.3, 0.6, 0.5)
    bpy.context.view_layer.objects.active = gold
    m = gold.modifiers.new("cut", 'BOOLEAN'); m.operation = 'DIFFERENCE'; m.object = cutter; m.solver = 'EXACT'
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cutter)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir = args[0]
    names = args[1:] or list(TARGETS.keys())
    for name in names:
        A.reset()
        TARGETS[name]()
        objs = A.build_objects()
        spec = A.export(objs, os.path.join(out_dir, name + ".fbx"))
        A.render(objs, os.path.join(out_dir, name + ".png"), size=512, angle=18, elevation=8)
        # a clean icon: straight on, transparent background
        A.render(objs, os.path.join(out_dir, "Icon_" + name + ".png"), size=256, angle=14, elevation=6, transparent=True, reuse=True)
        print("BUILT", name, "tris", spec["tris"], "parts", len(spec["parts"]))
