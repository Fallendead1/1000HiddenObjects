import sys, os, math, random
sys.path.insert(0, os.path.dirname(__file__))
import artlib as A
from artlib import rgb, ball, cone, tube, box, ring, capsule, hinge, eyes, blush, smile, look, BLACK, WHITE

PINK = rgb(255, 150, 185)
TONGUE = rgb(255, 120, 150)


def fluff(part, centre, radii, color, count=26, size=0.16, seed=1, tint=None, keep=lambda p: True):
    """Little tufts all over an ellipsoid, so it reads as fluffy instead of smooth."""
    rnd = random.Random(seed)
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        z = 1 - 2 * (i + 0.5) / count
        r = math.sqrt(1 - z * z)
        th = golden * i
        p = (centre[0] + radii[0] * r * math.cos(th), centre[1] + radii[1] * r * math.sin(th), centre[2] + radii[2] * z)
        if keep(p):
            s = size * rnd.uniform(0.8, 1.25)
            ball(part, p, (s, s, s), color, detail=0, shade=0.25, tint=tint)


def feet(color, front_y, back_y, x, size=(0.15, 0.2, 0.12), top=0.24, back_x=None, tint=None):
    bx = back_x or x
    for name, px, py in (("LegFL", -x, front_y), ("LegFR", x, front_y), ("LegBL", -bx, back_y), ("LegBR", bx, back_y)):
        part = name + "@" + name
        ball(part, (px, py - 0.04, size[2]), size, color, detail=2, shade=0.3, tint=tint)
        hinge(part, (px, py, top))


def bristles(part, base, direction, length, spread, color, band, count=9, seed=2, radius=0.045):
    """A broom head: a bound bunch of straw fanning out from base along direction."""
    rnd = random.Random(seed)
    bx, by, bz = base
    dx, dy, dz = direction
    n = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / n, dy / n, dz / n
    for i in range(count):
        ang = 2 * math.pi * i / count
        off = spread * (0.35 + 0.65 * rnd.random())
        # two vectors perpendicular to the direction
        ux, uy, uz = (1, 0, 0) if abs(dx) < 0.9 else (0, 1, 0)
        px, py, pz = (uy * dz - uz * dy, uz * dx - ux * dz, ux * dy - uy * dx)
        m = math.sqrt(px * px + py * py + pz * pz); px, py, pz = px / m, py / m, pz / m
        qx, qy, qz = (dy * pz - dz * py, dz * px - dx * pz, dx * py - dy * px)
        ex = math.cos(ang) * off; ey = math.sin(ang) * off
        tip = (bx + dx * length + px * ex + qx * ey, by + dy * length + py * ex + qy * ey, bz + dz * length + pz * ex + qz * ey)
        capsule(part, base, tip, radius, color, detail=1, shade=0.25, taper=0.7)
    ring(part, (bx + dx * length * 0.22, by + dy * length * 0.22, bz + dz * length * 0.22), radius * 2.6, radius * 1.1, band,
         rot=A.rot_to((dx, dy, dz)), segs=12, msegs=6)


# ------------------------------------------------------------------ Dust Bunny (1.6)
def DustBunny():
    fur = rgb(226, 220, 240); fur_dark = rgb(184, 174, 212); inner = rgb(255, 170, 195)
    ball("Body", (0, 0.18, 0.5), (0.54, 0.6, 0.46), fur, detail=3, tint=fur_dark)
    for (x, y, z, s) in ((0, -0.2, 0.5, 0.2), (-0.16, -0.14, 0.4, 0.16), (0.16, -0.14, 0.4, 0.16)):      # a soft white chest tuft
        ball("Body", (x, y - 0.12, z), (s, s * 0.8, s), WHITE, detail=2, shade=0.1)
    head = "Head@Head"
    ball(head, (0, -0.22, 1.06), (0.58, 0.52, 0.5), fur, detail=4, tint=fur_dark)
    for side in (-1, 1):                                                                                  # cheek fluff
        ball(head, (side * 0.43, -0.42, 0.9), (0.2, 0.18, 0.17), WHITE, detail=2, shade=0.1)
    for (x, z, s) in ((0, 1.56, 0.13), (-0.12, 1.52, 0.1), (0.12, 1.52, 0.1)):                              # a little tuft between the ears
        ball(head, (x, -0.2, z), (s, s, s), fur, detail=2, tint=fur_dark)
    hinge(head, (0, -0.05, 0.8))
    face = "Head@Head/Face"
    eyes(face, -0.65, 1.1, 0.23, 0.155)
    ball(face, (0, -0.755, 0.975), (0.05, 0.035, 0.035), PINK, detail=1, shade=0)
    smile(face, -0.755, 0.945, 0.05)
    blush(face, -0.65, 0.93, 0.37, 0.085)
    for side, name in ((-1, "EarL"), (1, "EarR")):
        part = name + "@" + name + "^Head"
        ball(part, (side * 0.24, -0.12, 1.86), (0.13, 0.085, 0.46), fur, rot=(-6, side * 10, 0), detail=2, tint=fur_dark)
        ball(part, (side * 0.245, -0.175, 1.86), (0.075, 0.04, 0.36), inner, rot=(-6, side * 10, 0), detail=2, shade=0.05)
        hinge(part, (side * 0.2, -0.12, 1.45))
    tail = "Tail@Tail"
    ball(tail, (0, 0.8, 0.55), (0.2, 0.2, 0.2), WHITE, detail=2)
    for (x, y, z) in ((0.1, 0.9, 0.62), (-0.1, 0.9, 0.62), (0, 0.92, 0.46)):
        ball(tail, (x, y, z), (0.11, 0.11, 0.11), WHITE, detail=1)
    hinge(tail, (0, 0.62, 0.5))
    feet(fur, -0.18, 0.42, 0.28, size=(0.15, 0.21, 0.12), tint=fur_dark)


# ------------------------------------------------------------------ puppies
def _puppy(fur, fur_dark, ear, ear_tint, nose=BLACK, scale=1.0):
    k = scale
    ball("Body", (0, 0.2 * k, 0.5 * k), (0.46 * k, 0.6 * k, 0.42 * k), fur, detail=3, tint=fur_dark)
    head = "Head@Head"
    ball(head, (0, -0.28 * k, 1.1 * k), (0.56 * k, 0.52 * k, 0.5 * k), fur, detail=3, tint=fur_dark)
    ball(head, (0, -0.72 * k, 0.98 * k), (0.27 * k, 0.24 * k, 0.2 * k), WHITE, detail=2, shade=0.08)     # muzzle
    hinge(head, (0, -0.08 * k, 0.82 * k))
    face = "Head@Head/Face"
    eyes(face, -0.71 * k, 1.2 * k, 0.25 * k, 0.15 * k)
    ball(face, (0, -0.95 * k, 1.04 * k), (0.085 * k, 0.06 * k, 0.06 * k), nose, detail=1, shade=0)
    ball(face, (0, -0.9 * k, 0.86 * k), (0.07 * k, 0.05 * k, 0.09 * k), TONGUE, detail=1, shade=0)
    blush(face, -0.7 * k, 1.02 * k, 0.4 * k, 0.08 * k)
    look(face, reflectance=0.12)
    for side, name in ((-1, "EarL"), (1, "EarR")):
        part = name + "@" + name + "^Head"
        ball(part, (side * 0.56 * k, -0.22 * k, 1.12 * k), (0.13 * k, 0.2 * k, 0.36 * k), ear, rot=(0, side * -18, 0), detail=2, tint=ear_tint)
        hinge(part, (side * 0.46 * k, -0.22 * k, 1.44 * k))
    feet(fur, -0.2 * k, 0.5 * k, 0.27 * k, size=(0.15 * k, 0.2 * k, 0.13 * k), top=0.26 * k, tint=fur_dark)


def SockPuppy():
    red = rgb(232, 64, 84); fur = rgb(250, 250, 252); grey = rgb(205, 208, 222)
    _puppy(fur, grey, red, rgb(180, 40, 60), scale=1.0)
    # the sock's striped cuff round the neck, a red heel on its rump, and a red-tipped tail
    ring("Body", (0, -0.1, 0.82), 0.36, 0.085, red, rot=(14, 0, 0), segs=20, msegs=8)
    ring("Body", (0, -0.08, 0.7), 0.4, 0.06, WHITE, rot=(14, 0, 0), segs=20, msegs=8)
    ball("Body", (0, 0.62, 0.62), (0.3, 0.24, 0.26), red, detail=2)
    tail = "Tail@Tail"
    capsule(tail, (0, 0.7, 0.72), (0, 0.98, 1.12), 0.085, fur, detail=2)
    ball(tail, (0, 1.0, 1.15), (0.12, 0.12, 0.12), red, detail=2)
    hinge(tail, (0, 0.7, 0.72))


def MopPup():
    cream = rgb(246, 232, 196); dark = rgb(214, 190, 140); blue = rgb(70, 150, 255)
    _puppy(cream, dark, cream, dark, scale=1.12)
    k = 1.12
    rnd = random.Random(4)
    # mop strands: over the head (a fringe to the eyes) and down the body's sides
    for i in range(13):
        ang = math.radians(-100 + i * 200 / 12)
        x, y = math.sin(ang) * 0.5 * k, -0.28 * k + math.cos(ang) * -0.42 * k
        top = (x * 0.35, -0.28 * k + (y + 0.28 * k) * 0.35, 1.58 * k)
        drop = 1.0 * k if abs(math.degrees(ang)) > 38 else 1.28 * k
        capsule("Head@Head", top, (x * 1.12, y * 1.05 - 0.02, drop + rnd.uniform(-0.05, 0.05)), 0.075 * k, cream, detail=1, shade=0.3, tint=dark, taper=0.75)
    for i in range(12):
        ang = math.radians(20 + i * 320 / 11)
        x, y = math.sin(ang) * 0.46 * k, 0.2 * k + math.cos(ang) * 0.6 * k
        if y < -0.25 * k:
            continue
        capsule("Body", (x * 0.6, 0.2 * k + (y - 0.2 * k) * 0.6, 0.86 * k), (x * 1.12, 0.2 * k + (y - 0.2 * k) * 1.1, 0.16 * k + rnd.uniform(0, 0.08)), 0.08 * k, cream, detail=1, shade=0.35, tint=dark, taper=0.7)
    ring("Body", (0, -0.12 * k, 0.8 * k), 0.37 * k, 0.07 * k, blue, rot=(14, 0, 0), segs=20, msegs=8)
    cone("Body", (0, -0.5 * k, 0.66 * k), 0.17 * k, 0.26 * k, blue, rot=(200, 0, 0), verts=3, scale=(1, 0.35, 1))
    tail = "Tail@Tail"
    for i in range(5):
        a = math.radians(-40 + i * 20)
        capsule(tail, (0, 0.8 * k, 0.7 * k), (math.sin(a) * 0.3, 1.15 * k, 0.75 * k + math.cos(a) * 0.35), 0.07 * k, cream, detail=1, tint=dark, taper=0.7)
    hinge(tail, (0, 0.8 * k, 0.7 * k))


# ------------------------------------------------------------------ Soap Slime (1.6)
def SoapSlime():
    blue = rgb(120, 214, 255); deep = rgb(60, 150, 235)
    body = "Body@Squash"
    ball(body, (0, 0, 0.62), (0.8, 0.78, 0.66), blue, detail=4, tint=deep, shade=0.1)
    cone(body, (0, 0.02, 1.32), 0.3, 0.5, blue, verts=16, shade=0.0)                       # the drip on top
    ball(body, (0, 0.02, 1.56), (0.1, 0.1, 0.1), blue, detail=1, shade=0)
    ball(body, (0, 0, 0.16), (0.86, 0.84, 0.2), deep, detail=3, shade=0.1)                 # puddle skirt
    look(body, reflectance=0.22)
    hinge(body, (0, 0, 0.0))
    face = "Face"
    eyes(face, -0.72, 0.78, 0.27, 0.16)
    smile(face, -0.79, 0.6, 0.06)
    blush(face, -0.72, 0.6, 0.45, 0.09)
    look(face, reflectance=0.12)
    bub = "Bubbles"
    for (x, y, z, r) in ((0.5, -0.2, 1.3, 0.16), (0.72, 0.1, 1.05, 0.1), (-0.55, 0.15, 1.35, 0.13), (-0.3, -0.35, 1.62, 0.08), (0.2, 0.3, 1.75, 0.11)):
        ball(bub, (x, y, z), (r, r, r), WHITE, detail=2, shade=0.0, tint=rgb(190, 235, 255))
        ball(bub, (x - r * 0.35, y - r * 0.6, z + r * 0.4), (r * 0.25, r * 0.2, r * 0.25), WHITE, detail=0, shade=0)
    look(bub, reflectance=0.3)


# ------------------------------------------------------------------ birds
def _bird(body_c, body_t, belly, wing_c, wing_t, beak_c, k=1.0, crest=None):
    ball("Body", (0, 0.05 * k, 0.78 * k), (0.62 * k, 0.66 * k, 0.66 * k), body_c, detail=4, tint=body_t)
    ball("Body", (0, -0.2 * k, 0.62 * k), (0.46 * k, 0.46 * k, 0.44 * k), belly, detail=3, shade=0.08)
    face = "Face"
    eyes(face, -0.56 * k, 1.0 * k, 0.27 * k, 0.15 * k)
    blush(face, -0.56 * k, 0.83 * k, 0.43 * k, 0.085 * k)
    look(face, reflectance=0.12)
    for side, name in ((-1, "WingL"), (1, "WingR")):
        part = name + "@" + name
        ball(part, (side * 0.86 * k, 0.12 * k, 0.8 * k), (0.34 * k, 0.12 * k, 0.24 * k), wing_c, rot=(0, side * 12, side * -14), detail=2, tint=wing_t)
        for j in range(3):
            capsule(part, (side * (0.85 + j * 0.06) * k, (0.06 + j * 0.1) * k, 0.72 * k), (side * (1.22 + j * 0.02) * k, (0.12 + j * 0.13) * k, (0.6 - j * 0.04) * k), 0.085 * k, wing_t, detail=1, taper=0.6)
        hinge(part, (side * 0.56 * k, 0.1 * k, 0.86 * k))
    for side in (-1, 1):                                                                         # tucked feet
        ball("Body", (side * 0.22 * k, -0.12 * k, 0.12 * k), (0.12 * k, 0.17 * k, 0.07 * k), beak_c, detail=1)


def BroomBird():
    yellow = rgb(255, 222, 60); amber = rgb(250, 170, 40); straw = rgb(226, 178, 96); orange = rgb(255, 140, 40)
    _bird(yellow, amber, rgb(255, 240, 170), amber, rgb(200, 120, 40), orange, k=1.0)
    cone("Face", (0, -0.74, 0.88), 0.12, 0.26, orange, rot=(90, 0, 0), verts=12)
    for i, a in enumerate((-22, 0, 22)):                                                        # crest
        capsule("Body", (0, 0.0, 1.38), (math.sin(math.radians(a)) * 0.22, 0.1, 1.7 - abs(a) * 0.004), 0.06, amber, detail=1, taper=0.6)
    tail = "Tail@Tail"
    capsule(tail, (0, 0.55, 0.7), (0, 0.95, 0.85), 0.07, rgb(150, 100, 60), detail=1)
    bristles(tail, (0, 0.9, 0.83), (0, 1, 0.35), 0.62, 0.3, straw, rgb(220, 60, 60), count=10, seed=3)
    hinge(tail, (0, 0.55, 0.7))


def DusterParrot():
    red = rgb(236, 62, 78); dark = rgb(170, 30, 60); cyan = rgb(70, 205, 255); yellow = rgb(255, 214, 70)
    k = 1.15
    _bird(red, dark, rgb(255, 235, 200), cyan, rgb(40, 110, 230), rgb(90, 90, 100), k=k)
    for side in (-1, 1):                                                                         # white eye patches
        ball("Body", (side * 0.27 * k, -0.5 * k, 1.0 * k), (0.2 * k, 0.12 * k, 0.2 * k), WHITE, detail=2, shade=0.0)
    ball("Face", (0, -0.7 * k, 0.9 * k), (0.15 * k, 0.17 * k, 0.15 * k), yellow, detail=2, shade=0.05)       # big beak
    cone("Face", (0, -0.84 * k, 0.78 * k), 0.1 * k, 0.24 * k, rgb(60, 60, 70), rot=(160, 0, 0), verts=10)
    for side in (-1, 1):                                                                         # yellow wing band
        ball(("WingL@WingL" if side < 0 else "WingR@WingR"), (side * 0.8 * k, 0.1 * k, 0.9 * k), (0.2 * k, 0.1 * k, 0.1 * k), yellow, detail=1)
    for i, a in enumerate((-25, 0, 25)):
        capsule("Body", (0, 0.0, 1.4 * k), (math.sin(math.radians(a)) * 0.25, 0.14, 1.78 * k), 0.065 * k, yellow if i == 1 else red, detail=1, taper=0.6)
    tail = "Tail@Tail"
    capsule(tail, (0, 0.6 * k, 0.72 * k), (0, 1.1 * k, 0.95 * k), 0.06 * k, rgb(250, 230, 180), detail=1)
    fluff(tail, (0, 1.38 * k, 1.08 * k), (0.34 * k, 0.4 * k, 0.34 * k), cyan, count=22, size=0.17 * k, seed=8, tint=rgb(40, 120, 235))
    ball(tail, (0, 1.38 * k, 1.08 * k), (0.3 * k, 0.36 * k, 0.3 * k), rgb(40, 120, 235), detail=2)
    hinge(tail, (0, 0.6 * k, 0.72 * k))


# ------------------------------------------------------------------ Laundry Frog (1.9)
def LaundryFrog():
    green = rgb(96, 214, 116); dark = rgb(40, 150, 80); belly = rgb(255, 244, 150)
    ball("Body", (0, 0.1, 0.72), (0.86, 0.8, 0.7), green, detail=4, tint=dark)
    ball("Body", (0, -0.28, 0.55), (0.6, 0.5, 0.48), belly, detail=3, shade=0.08)
    for side in (-1, 1):                                                                         # eye bumps on top
        ball("Body", (side * 0.42, -0.3, 1.42), (0.3, 0.3, 0.3), green, detail=2, tint=dark)
    face = "Face"
    for side in (-1, 1):
        ball(face, (side * 0.42, -0.42, 1.46), (0.22, 0.18, 0.22), WHITE, detail=2, shade=0)
        ball(face, (side * 0.42, -0.56, 1.46), (0.13, 0.07, 0.15), BLACK, detail=2, shade=0)
        ball(face, (side * 0.42 - 0.05, -0.62, 1.53), (0.04, 0.025, 0.04), WHITE, detail=0, shade=0)
    for i in range(9):                                                                           # wide smile, on the body's surface
        def at(deg):
            a = math.radians(deg)
            zz = 0.92 - math.cos(a) * 0.1
            rr = math.sqrt(max(0.0, 1 - ((zz - 0.72) / 0.7) ** 2)) * 1.015
            return (math.sin(a) * 0.86 * rr, 0.1 - math.cos(a) * 0.8 * rr, zz)
        capsule(face, at(-54 + i * 12), at(-54 + (i + 1) * 12), 0.024, rgb(30, 90, 50), detail=1, shade=0)
    blush(face, -0.7, 0.9, 0.56, 0.09)
    look(face, reflectance=0.12)
    # a washing line towel over its back, held by a clothes peg
    box("Body", (0, 0.42, 1.28), (0.95, 0.62, 0.1), WHITE, rot=(-24, 0, 0), bevel=0.04)
    for i in (-1, 0, 1):
        box("Body", (i * 0.3, 0.42, 1.34), (0.1, 0.63, 0.04), rgb(90, 170, 255), rot=(-24, 0, 0), bevel=0.01)
    box("Body", (0, 0.18, 1.52), (0.12, 0.1, 0.3), rgb(230, 170, 90), rot=(-24, 0, 0), bevel=0.03)
    for side, name in ((-1, "LegBL"), (1, "LegBR")):
        part = name + "@" + name
        ball(part, (side * 0.82, 0.3, 0.34), (0.3, 0.46, 0.32), green, detail=2, tint=dark)
        ball(part, (side * 0.9, -0.12, 0.1), (0.24, 0.32, 0.1), green, detail=2, tint=dark)
        hinge(part, (side * 0.7, 0.35, 0.5))
    for side, name in ((-1, "LegFL"), (1, "LegFR")):
        part = name + "@" + name
        capsule(part, (side * 0.5, -0.5, 0.5), (side * 0.56, -0.68, 0.12), 0.11, green, detail=2, tint=dark)
        ball(part, (side * 0.57, -0.76, 0.08), (0.17, 0.2, 0.08), green, detail=1, tint=dark)
        hinge(part, (side * 0.5, -0.5, 0.5))


# ------------------------------------------------------------------ Vacuum Cat (2.0)
def VacuumCat():
    grey = rgb(160, 162, 180); dark = rgb(104, 106, 130); red = rgb(250, 84, 84); inner = rgb(255, 170, 195)
    k = 1.15
    ball("Body", (0, 0.22 * k, 0.5 * k), (0.44 * k, 0.6 * k, 0.42 * k), grey, detail=3, tint=dark)
    ball("Body", (0, -0.1 * k, 0.42 * k), (0.28 * k, 0.26 * k, 0.26 * k), WHITE, detail=2, shade=0.1)
    ring("Body", (0, -0.1 * k, 0.8 * k), 0.34 * k, 0.065 * k, red, rot=(14, 0, 0), segs=20, msegs=8)
    ball("Body", (0, -0.45 * k, 0.72 * k), (0.08 * k, 0.06 * k, 0.08 * k), rgb(255, 214, 70), detail=1, shade=0)       # bell
    head = "Head@Head"
    ball(head, (0, -0.26 * k, 1.1 * k), (0.58 * k, 0.5 * k, 0.48 * k), grey, detail=3, tint=dark)
    for side in (-1, 1):
        ball(head, (side * 0.42 * k, -0.46 * k, 0.94 * k), (0.2 * k, 0.17 * k, 0.16 * k), WHITE, detail=2, shade=0.08)
    hinge(head, (0, -0.06 * k, 0.82 * k))
    face = "Head@Head/Face"
    eyes(face, -0.67 * k, 1.16 * k, 0.25 * k, 0.15 * k, color=rgb(20, 60, 40))
    ball(face, (0, -0.76 * k, 1.0 * k), (0.05 * k, 0.035 * k, 0.035 * k), PINK, detail=1, shade=0)
    smile(face, -0.76 * k, 0.97 * k, 0.05 * k)
    for side in (-1, 1):
        for j in (-1, 0, 1):
            capsule(face, (side * 0.4 * k, -0.62 * k, (0.98 + j * 0.02) * k), (side * 0.78 * k, -0.5 * k, (0.98 + j * 0.1) * k), 0.012 * k, WHITE, detail=1, shade=0)
    look(face, reflectance=0.12)
    for side, name in ((-1, "EarL"), (1, "EarR")):
        part = name + "@" + name + "^Head"
        cone(part, (side * 0.36 * k, -0.2 * k, 1.64 * k), 0.24 * k, 0.42 * k, grey, rot=(-6, side * 16, 0), verts=12, scale=(1, 0.55, 1))
        cone(part, (side * 0.36 * k, -0.26 * k, 1.62 * k), 0.15 * k, 0.3 * k, inner, rot=(-6, side * 16, 0), verts=10, scale=(1, 0.4, 1), shade=0)
        hinge(part, (side * 0.34 * k, -0.2 * k, 1.46 * k))
    feet(grey, -0.16 * k, 0.5 * k, 0.26 * k, size=(0.14 * k, 0.2 * k, 0.13 * k), top=0.26 * k, tint=dark)
    # the tail is a vacuum hose with a nozzle
    tail = "Tail@Tail"
    pts = [(0, 0.78, 0.6), (0, 1.0, 0.85), (0.08, 1.12, 1.18), (0.2, 1.08, 1.5), (0.3, 0.92, 1.76)]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        capsule(tail, tuple(c * k for c in a), tuple(c * k for c in b), 0.085 * k, red, detail=1, shade=0.1)
        m = tuple((a[j] + b[j]) / 2 * k for j in range(3))
        ball(tail, m, (0.11 * k, 0.11 * k, 0.11 * k), rgb(200, 50, 60), detail=1)
    box(tail, (0.34 * k, 0.78 * k, 1.9 * k), (0.34 * k, 0.26 * k, 0.12 * k), rgb(60, 62, 80), rot=(30, 0, -20), bevel=0.04)
    hinge(tail, (0, 0.78 * k, 0.6 * k))


# ------------------------------------------------------------------ Roomba Turtle (2.2 long, low)
def RoombaTurtle():
    green = rgb(110, 214, 140); dark = rgb(50, 150, 96); shell = rgb(58, 66, 88); led = rgb(100, 255, 170)
    tube("Body", (0, 0.15, 0.62), 0.98, 0.42, shell, verts=28, shade=0.2)
    tube("Body", (0, 0.15, 0.86), 0.8, 0.1, rgb(82, 92, 120), verts=28, shade=0.0)
    ring("Body", (0, 0.15, 0.91), 0.5, 0.045, led, segs=28, msegs=6)
    tube("Body", (0, 0.15, 0.93), 0.2, 0.06, led, verts=16, shade=0)
    ring("Body", (0, 0.15, 0.5), 1.0, 0.09, rgb(30, 34, 48), segs=28, msegs=8)                                 # bumper
    ball("Body", (0, 0.15, 0.42), (0.86, 0.86, 0.22), rgb(255, 240, 170), detail=3, shade=0.2)                  # belly plate
    look("Body", reflectance=0.1)
    head = "Head@Head"
    ball(head, (0, -1.02, 0.78), (0.46, 0.44, 0.42), green, detail=3, tint=dark)
    capsule(head, (0, -0.6, 0.6), (0, -0.92, 0.7), 0.22, green, detail=2, tint=dark)
    hinge(head, (0, -0.62, 0.6))
    face = "Head@Head/Face"
    eyes(face, -1.38, 0.86, 0.2, 0.125)
    smile(face, -1.45, 0.7, 0.05)
    blush(face, -1.36, 0.7, 0.32, 0.07)
    look(face, reflectance=0.12)
    for name, x, y in (("LegFL", -0.78, -0.42), ("LegFR", 0.78, -0.42), ("LegBL", -0.78, 0.72), ("LegBR", 0.78, 0.72)):
        part = name + "@" + name
        ball(part, (x * 1.12, y, 0.2), (0.25, 0.3, 0.2), green, detail=2, tint=dark)
        hinge(part, (x, y, 0.42))
    cone("Tail@Tail", (0, 1.22, 0.42), 0.13, 0.4, green, rot=(-90, 0, 0), verts=10)
    hinge("Tail@Tail", (0, 1.05, 0.42))


# ------------------------------------------------------------------ Golden Broom Dragon (2.6)
def GoldenBroomDragon():
    gold = rgb(255, 214, 50); deep = rgb(240, 160, 20); belly = rgb(255, 238, 170); orange = rgb(255, 120, 40)
    ball("Body", (0, 0.2, 0.78), (0.62, 0.78, 0.62), gold, detail=4, tint=deep)
    ball("Body", (0, -0.12, 0.66), (0.44, 0.5, 0.46), belly, detail=3, shade=0.08)
    for i in range(3):                                                                            # belly plates
        ring("Body", (0, -0.2, 0.46 + i * 0.2), 0.36 - i * 0.03, 0.025, deep, rot=(80, 0, 0), segs=16, msegs=5, scale=(1, 1, 0.5))
    for i in range(4):                                                                            # back spikes
        cone("Body", (0, 0.5 + i * 0.16, 1.32 - i * 0.2), 0.11, 0.26, orange, rot=(-30 - i * 22, 0, 0), verts=8)
    look("Body", reflectance=0.18)
    head = "Head@Head"
    ball(head, (0, -0.38, 1.62), (0.66, 0.62, 0.56), gold, detail=4, tint=deep)
    ball(head, (0, -0.92, 1.46), (0.36, 0.34, 0.26), gold, detail=3, tint=deep)                                   # snout
    for side in (-1, 1):
        ball(head, (side * 0.14, -1.2, 1.54), (0.05, 0.04, 0.04), deep, detail=1, shade=0)                        # nostrils
        cone(head, (side * 0.34, -0.12, 2.22), 0.13, 0.5, orange, rot=(-16, side * 18, 0), verts=10)              # horns
        ball(head, (side * 0.64, -0.2, 1.72), (0.1, 0.22, 0.26), gold, rot=(0, side * -30, 0), detail=2, tint=deep)  # ear fins
    look(head, reflectance=0.18)
    hinge(head, (0, -0.1, 1.28))
    face = "Head@Head/Face"
    eyes(face, -0.9, 1.78, 0.34, 0.17, color=rgb(60, 24, 10))
    smile(face, -1.24, 1.4, 0.06)
    blush(face, -0.86, 1.56, 0.52, 0.09, color=rgb(255, 150, 120))
    look(face, reflectance=0.12)
    for side, name in ((-1, "WingL"), (1, "WingR")):
        part = name + "@" + name
        root = (side * 0.46, 0.35, 1.2)
        tips = [(side * 1.55, 0.25, 2.35), (side * 2.15, 0.4, 1.85), (side * 2.1, 0.55, 1.2), (side * 1.45, 0.65, 0.8)]
        for t in tips:
            capsule(part, root, t, 0.06, deep, detail=1, taper=0.5)
        A.fan(part, root, tips, orange, edge=rgb(255, 170, 60))
        hinge(part, root)
        look(part, reflectance=0.1)
    for name, x, y in (("LegFL", -0.4, -0.3), ("LegFR", 0.4, -0.3), ("LegBL", -0.46, 0.55), ("LegBR", 0.46, 0.55)):
        part = name + "@" + name
        ball(part, (x, y - 0.05, 0.22), (0.2, 0.26, 0.24), gold, detail=2, tint=deep)
        for j in (-1, 0, 1):
            cone(part, (x + j * 0.1, y - 0.3, 0.07), 0.04, 0.12, WHITE, rot=(100, 0, 0), verts=6)
        hinge(part, (x, y, 0.45))
    tail = "Tail@Tail"
    pts = [(0, 0.85, 0.6), (0, 1.3, 0.5), (0.1, 1.7, 0.62), (0.18, 2.0, 0.9)]
    for i in range(len(pts) - 1):
        capsule(tail, pts[i], pts[i + 1], 0.2 - i * 0.045, gold, detail=2, tint=deep, taper=0.8)
    bristles(tail, (0.18, 2.0, 0.9), (0.15, 0.7, 0.75), 0.7, 0.32, rgb(226, 178, 96), rgb(220, 60, 60), count=10, seed=5, radius=0.05)
    hinge(tail, (0, 0.85, 0.6))
    look(tail, reflectance=0.12)


PETS = {
    "DustBunny": DustBunny, "SockPuppy": SockPuppy, "SoapSlime": SoapSlime, "MopPup": MopPup, "BroomBird": BroomBird,
    "LaundryFrog": LaundryFrog, "VacuumCat": VacuumCat, "DusterParrot": DusterParrot, "RoombaTurtle": RoombaTurtle,
    "GoldenBroomDragon": GoldenBroomDragon,
}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    out_dir = args[0]
    names = args[1:] or list(PETS.keys())
    os.makedirs(out_dir, exist_ok=True)
    for name in names:
        A.reset()
        PETS[name]()
        objs = A.build_objects()
        A.decimate_all(objs, 6500)
        spec = A.export(objs, os.path.join(out_dir, name + ".fbx"))
        A.render(objs, os.path.join(out_dir, name + ".png"), size=512)
        print("BUILT", name, "tris", spec["tris"], "parts", len(spec["parts"]))
