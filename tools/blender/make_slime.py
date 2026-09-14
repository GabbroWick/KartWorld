"""Blender headless: modella lo slime (nemico) da primitive e lo esporta GLB.

Uso:
  blender -b --python tools/blender/make_slime.py -- --output assets/characters/_final/slime/slime.glb [--preview p.png]

Blob a goccia con base piatta (sfera schiacciata + scultura leggera), due
occhi incassati con pupilla, bocca sorridente incisa. Materiali flat
(albedo puro, roughness 1): il gioco applica il fill. Altezza 1.0 m,
piedi a y=0, davanti a -Y in Blender (= +Z glTF, flip_forward in Godot).
"""
import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_ai3d as ai  # noqa: E402


def flat_material(name: str, rgb: tuple) -> bpy.types.Material:
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    return m


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    p.add_argument("--preview", default="")
    p.add_argument("--height", type=float, default=1.0)
    args = p.parse_args(argv)
    out = Path(args.output).resolve()
    ai.clear_scene()

    body_mat = flat_material("SlimeBody", (0.36, 0.80, 0.30))
    eye_mat = flat_material("SlimeEye", (0.97, 0.97, 0.95))
    pupil_mat = flat_material("SlimePupil", (0.08, 0.08, 0.10))
    mouth_mat = flat_material("SlimeMouth", (0.12, 0.30, 0.12))

    # Corpo: sfera uv, schiacciata, base tagliata piatta, leggermente a goccia.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, radius=0.5)
    body = bpy.context.active_object
    body.name = "Slime"
    for v in body.data.vertices:
        x, y, z = v.co
        # goccia: piu' larga in basso, punta morbida in alto
        w = 1.0 + 0.12 * (1.0 - (z + 0.5))
        v.co = Vector((x * w * 0.92, y * w * 0.92, z * 0.90 + 0.45))
    # base piatta
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=(0, 0, 0.06), plane_no=(0, 0, -1), clear_outer=True, use_fill=True)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in body.data.vertices:
        v.co.z -= 0.06
    body.data.materials.append(body_mat)
    for poly in body.data.polygons:
        poly.use_smooth = True

    parts = [body]

    def add_sphere(name, radius, at, mat, scale=(1, 1, 1)):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=radius, location=at)
        o = bpy.context.active_object
        o.name = name
        o.scale = scale
        o.data.materials.append(mat)
        for poly in o.data.polygons:
            poly.use_smooth = True
        parts.append(o)
        return o

    # Occhi (davanti = -Y), incassati nel corpo.
    for sx in (-1, 1):
        add_sphere("Eye", 0.12, (sx * 0.18, -0.36, 0.55), eye_mat)
        add_sphere("Pupil", 0.06, (sx * 0.18, -0.46, 0.56), pupil_mat, (1, 0.5, 1))
    # Bocca: toro schiacciato a mezzaluna (parte bassa) incassato.
    bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.035, major_segments=24, minor_segments=8,
                                     location=(0, -0.53, 0.35), rotation=(math.radians(90), 0, 0))
    mouth = bpy.context.active_object
    mouth.name = "Mouth"
    mouth.data.materials.append(mouth_mat)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    # tieni solo la meta' inferiore del toro: sorriso
    bpy.ops.mesh.bisect(plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_outer=True, use_fill=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    for poly in mouth.data.polygons:
        poly.use_smooth = True
    parts.append(mouth)

    for o in bpy.context.scene.objects:
        o.select_set(o in parts)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.data.transform(obj.matrix_world)
    obj.matrix_world.identity()
    ai.normalize(obj, args.height)
    obj.name = out.stem
    obj.data.name = out.stem
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    ai.export_glb(out)
    if args.preview:
        ai.render_preview(obj, Path(args.preview).resolve())
    ai.log(slime=str(out), triangles=sum(len(f.vertices) - 2 for f in obj.data.polygons),
           dims=[round(d, 3) for d in obj.dimensions])


if __name__ == "__main__":
    main()
