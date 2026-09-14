"""Blender headless: separa le ruote da un modello di veicolo generato dall'AI
(mesh unica) cosi' il gioco puo' farle girare.

Uso:
  blender -b --python tools/blender/split_wheels.py -- \
      --input assets/characters/_processed/kart/kart_clean.glb \
      --output assets/characters/_final/kart/kart.glb \
      [--wheel-radius 0.22] [--preview out.png]

Metodo: il modello e' in Blender Z-up con il davanti a -Y. Le ruote sono
le parti piu' basse ed esterne: per ogni quadrante (sinistra/destra x
davanti/dietro) i vertici entro un cilindro orizzontale (asse X) centrato
sul punto piu' esterno-basso di quel quadrante, raggio `--wheel-radius`,
vengono separati in un oggetto "Wheel_FL/FR/RL/RR" con l'origine al mozzo.
Il resto e' "Body". Export GLB: Body + 4 Wheel_* come nodi figli, cosi'
`AiVehicleVisual` li trova per nome e li ruota.
"""
import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_ai3d as ai  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--wheel-radius", type=float, default=0.0, help="0 = stima automatica")
    p.add_argument("--preview", default="")
    args = p.parse_args(argv)
    src = Path(args.input).resolve()
    out = Path(args.output).resolve()

    ai.clear_scene()
    ai.import_model(src)
    body = ai.join_meshes()
    body.name = "Body"
    verts = body.data.vertices
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    zmin, zmax = min(zs), max(zs)
    ymin, ymax = min(ys), max(ys)
    height = zmax - zmin
    radius = args.wheel_radius if args.wheel_radius > 0 else height * 0.22

    # Hubs: per quadrant, the centroid of the low, outer vertices.
    ymid = (ymin + ymax) * 0.5
    low = [v.co.copy() for v in verts if v.co.z < zmin + radius * 2.0]
    hubs = {}
    for name, sx, sy in [("Wheel_FL", -1, -1), ("Wheel_FR", 1, -1), ("Wheel_RL", -1, 1), ("Wheel_RR", 1, 1)]:
        quad = [c for c in low if c.x * sx > radius * 0.6 and (c.y - ymid) * sy > radius * 0.4]
        if len(quad) < 20:
            continue
        cx = sum(c.x for c in quad) / len(quad)
        cy = sum(c.y for c in quad) / len(quad)
        hubs[name] = Vector((cx, cy, zmin + radius))

    wheels = []
    for name, hub in hubs.items():
        # Select with mesh data flags in OBJECT mode, then separate in EDIT mode.
        bpy.ops.object.mode_set(mode="OBJECT")
        for o in bpy.context.scene.objects:
            o.select_set(o == body)
        bpy.context.view_layer.objects.active = body
        mesh = body.data
        for poly in mesh.polygons:
            poly.select = False
        for edge in mesh.edges:
            edge.select = False
        count = 0
        for v in mesh.vertices:
            d = Vector((0.0, v.co.y - hub.y, v.co.z - hub.z)).length
            v.select = d < radius * 1.15 and abs(v.co.x - hub.x) < radius * 0.9
            count += 1 if v.select else 0
        if count < 10:
            continue
        mesh.update()
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="VERT")
        # Whole faces whose every vertex is selected: extend to faces.
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        parts = [o for o in bpy.context.scene.objects if o.type == "MESH" and o != body and o not in wheels]
        if not parts:
            continue
        wheel = parts[0]
        wheel.name = name
        wheel.data.name = name
        bpy.context.scene.cursor.location = hub
        for o in bpy.context.scene.objects:
            o.select_set(o == wheel)
        bpy.context.view_layer.objects.active = wheel
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        wheels.append(wheel)

    for o in bpy.context.scene.objects:
        o.select_set(o.type == "MESH")
    bpy.context.view_layer.objects.active = body
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True,
                              export_materials="EXPORT", use_selection=True)
    if args.preview:
        # Preview needs a single object: join a temporary copy.
        ai.render_preview(body, Path(args.preview).resolve())
    ai.log(split="ok", wheels=[w.name for w in wheels], radius=round(radius, 3),
           hubs={k: [round(c, 3) for c in v] for k, v in hubs.items()}, output=str(out))


if __name__ == "__main__":
    main()
