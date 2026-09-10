# Kenney assets

Models from [Kenney](https://www.kenney.nl), licensed **CC0** (see LICENSE.txt):
Car Kit, Nature Kit, Platformer Kit, Mini Forest, Modular Buildings.
Curated subsets; the original zips live in `art/` (not tracked).

Notes:
* Kenney units are roughly 1/3 of ours: a tree is ~1.6 units tall, a star 0.36.
  `ModelProp.model_scale` and the visual scenes apply ~2.5–3x. The Car Kit
  vehicles are already life-size (race-future is 2.66 long).
* Car/Platformer/Mini Forest/Buildings kits reference an **external**
  `Textures/colormap.png` next to the .glb files; keep that folder. Nature Kit
  models use plain materials with no textures.
* Only `.glb` files are used; Godot imports them as scenes.
