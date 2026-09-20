import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import artlib as A
import pets

# Transparent icons of pets (for prizes on the daily spin): blender -b --python peticons.py -- <out dir> [kinds]
args = sys.argv[sys.argv.index("--") + 1:]
for name in (args[1:] or list(pets.PETS.keys())):
    A.reset()
    pets.PETS[name]()
    objs = A.build_objects()
    A.render(objs, os.path.join(args[0], "PetIcon_" + name + ".png"), size=256, angle=28, elevation=12, transparent=True)
    print("ICON", name)
