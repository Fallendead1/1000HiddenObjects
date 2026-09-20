import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import artlib as A
from artlib import rgb, ball, cone, tube, box, ring, capsule, look, WHITE

# The lobby's reward stations: a thumbs-up and a bell that float over a stepped pedestal.
# They FACE -Y; about 2.4 studs tall.


def ThumbsUp():
    green = rgb(70, 230, 90); dark = rgb(20, 160, 70)
    p = "Icon"
    box(p, (0.1, 0, -0.35), (1.25, 0.8, 1.15), green, bevel=0.22, tint=dark)                      # palm
    for i in range(4):                                                                            # curled fingers
        z = 0.12 - i * 0.3
        capsule(p, (-0.25, -0.38, z), (0.62, -0.38, z), 0.17, green, detail=2, tint=dark)
        ball(p, (-0.36, -0.36, z), (0.2, 0.2, 0.17), green, detail=2, tint=dark)
    capsule(p, (-0.3, -0.05, 0.1), (-0.42, -0.02, 1.0), 0.23, green, detail=3, tint=dark, taper=0.85)   # the thumb
    box(p, (0.98, 0, -0.35), (0.42, 0.92, 1.3), WHITE, bevel=0.1, tint=rgb(200, 210, 230))              # cuff
    ball(p, (0.98, -0.47, -0.35), (0.09, 0.05, 0.09), rgb(255, 214, 60), detail=1, shade=0)             # button


def Bell():
    cyan = rgb(60, 220, 255); dark = rgb(20, 130, 230); gold = rgb(255, 214, 60)
    p = "Icon"
    ball(p, (0, 0, 0.35), (0.72, 0.72, 0.8), cyan, detail=4, tint=dark)
    tube(p, (0, 0, -0.1), 0.78, 0.7, cyan, verts=28, tint=dark)
    cone(p, (0, 0, -0.55), 1.12, 0.5, cyan, top=0.78, verts=28, tint=dark)
    ring(p, (0, 0, -0.8), 1.1, 0.1, gold, segs=28, msegs=8)
    ball(p, (0, 0, -0.95), (0.24, 0.24, 0.24), gold, detail=2)                                          # clapper
    ring(p, (0, 0, 1.22), 0.17, 0.06, gold, rot=(90, 0, 0), segs=16, msegs=6)
    ball(p, (-0.3, -0.52, 0.55), (0.16, 0.06, 0.26), WHITE, rot=(0, 0, -30), detail=1, shade=0)         # shine


def Pedestal():
    stone = rgb(250, 246, 236); shade = rgb(214, 204, 186); gold = rgb(255, 205, 50)
    p = "Base"
    for i, (r, h) in enumerate(((3.4, 0.4), (2.7, 0.4), (2.0, 0.45))):
        z = 0.2 + i * 0.4
        tube(p, (0, 0, z), r, h, stone, verts=36, tint=shade, shade=0.1)
        ring(p, (0, 0, z + h / 2 - 0.02), r - 0.04, 0.07, gold, segs=36, msegs=6)


MODELS = {"ThumbsUp": ThumbsUp, "Bell": Bell, "Pedestal": Pedestal}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir = args[0]
    for name in (args[1:] or list(MODELS.keys())):
        A.reset()
        MODELS[name]()
        objs = A.build_objects()
        spec = A.export(objs, os.path.join(out_dir, "Social_" + name + ".fbx"))
        A.render(objs, os.path.join(out_dir, "Social_" + name + ".png"), size=512, angle=25, elevation=15)
        print("BUILT", name, "tris", spec["tris"])
