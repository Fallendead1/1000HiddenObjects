# Game art made with Blender scripts

The pets, the hidden objects (key, ring, remote, wrench, map) and the eggs are modelled by the
Python scripts in `art/blender/` (run in headless Blender), uploaded to the group with Open Cloud
(`upload.js`, key from the `ROBLOX_OPEN_CLOUD_API_KEY` environment variable) and assembled in Studio.

- `artlib.py`: the modelling kit (smooth shapes with vertex colours, one mesh per moving part,
  hinge markers, FBX export, preview renders).
- `pets.py`, `targets.py`, `eggs.py`: the models. Run: `blender -b --python pets.py -- <out dir> [names]`.
- In Studio the models live in `ReplicatedStorage.GameAssets.Pets` / `Eggs` and
  `ServerStorage.Targets` (these are in the place file, not in Git).

Pets move without uploaded animations: parts with a `Joint` attribute (WingL, LegFL, Tail, EarL,
Head, Squash...) are posed by `PetModels.Animate` around their PivotOffset. Eggs name their
pieces `ShellTop` / `ShellBottom` and number their cracks with a `Crack` attribute (1-4).
