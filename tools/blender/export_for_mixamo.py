"""Blender headless: dal GLB finale produce gli FBX per l'auto-rigger Mixamo.

Uso:
  blender -b --python tools/blender/export_for_mixamo.py -- \
      --input assets/characters/_final/leopard/leopard.glb \
      --outdir assets/characters/_processed/leopard/mixamo

Scrive:
  <nome>_untextured.fbx   mesh sola, nessun materiale: QUESTO va caricato su
                          Mixamo (l'FBX con texture fa fallire l'auto-rigger:
                          "unable to map your existing skeleton")
  <nome>_textured.fbx     con materiale e texture incorporata, per controllo
Il modello resta Y-up, davanti +Z (glTF), altezza in metri: Mixamo lo legge
in centimetri e il rig tornera' 100x piu' piccolo (RiggedCharacterVisual usa
model_scale = 100, come per il leopardo Meshy).
"""
import argparse
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_ai3d as ai  # noqa: E402


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--outdir", required=True)
    args = p.parse_args(argv)
    src = Path(args.input).resolve()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    stem = src.stem

    ai.clear_scene()
    ai.import_model(src)
    obj = ai.join_meshes()
    obj.name = stem
    obj.data.name = stem
    for o in bpy.context.scene.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj

    # Con texture (materiale e immagine incorporati).
    textured = outdir / (stem + "_textured.fbx")
    bpy.ops.export_scene.fbx(filepath=str(textured), use_selection=True, path_mode="COPY",
                             embed_textures=True, mesh_smooth_type="FACE", add_leaf_bones=False,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y")

    # Senza materiali: per Mixamo.
    obj.data.materials.clear()
    untextured = outdir / (stem + "_untextured.fbx")
    bpy.ops.export_scene.fbx(filepath=str(untextured), use_selection=True, path_mode="STRIP",
                             mesh_smooth_type="FACE", add_leaf_bones=False,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y")
    ai.log(mixamo_untextured=str(untextured), textured=str(textured),
           triangles=sum(len(f.vertices) - 2 for f in obj.data.polygons),
           bytes_untextured=untextured.stat().st_size, bytes_textured=textured.stat().st_size)


if __name__ == "__main__":
    main()
