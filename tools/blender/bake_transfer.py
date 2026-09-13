"""Blender headless: trasferisce la texture di un modello sorgente (es. il
leopardo Meshy) su una mesh bersaglio con UV proprie (es. il leopardo AI),
con un bake Cycles "Selected to Active" del solo colore diffuso.

Uso:
  blender -b --python tools/blender/bake_transfer.py -- \
      --source assets/models/meshy/leopard/leopard.glb \
      --target assets/characters/_processed/leopard/leopard_textured.glb \
      --output assets/characters/_processed/leopard/leopard_baked.glb \
      [--height 1.35] [--size 2048] [--cage 0.06] [--ray 0.25] [--preview out.png] [--blend out.blend]

Entrambi i modelli vengono normalizzati allo stesso modo (piedi a z=0,
centrati in XY, altezza --height) cosi' si sovrappongono; poi ogni texel del
bersaglio prende il colore della superficie sorgente piu' vicina lungo la
normale (cage --cage metri, raggio massimo --ray). Il bersaglio deve avere
UV (le ha: xatlas del Paint). Solo colore: niente luci, niente ombre.
Scrive: <output>, <output stem>_albedo.png, opzionale preview/blend.
"""
import argparse
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_ai3d as ai  # noqa: E402  (riusa import/normalize/preview)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--height", type=float, default=1.35)
    p.add_argument("--size", type=int, default=2048)
    p.add_argument("--cage", type=float, default=0.06)
    p.add_argument("--ray", type=float, default=0.25)
    p.add_argument("--margin", type=int, default=16)
    p.add_argument("--source-texture", default="",
                   help="immagine albedo da forzare come Base Color della sorgente (FBX Mixamo: la "
                        "texture arriva collegata al canale normal e il colore base e' nero)")
    p.add_argument("--preview", default="")
    p.add_argument("--blend", default="")
    return p.parse_args(argv)


def load_one(path: Path, name: str, height: float) -> bpy.types.Object:
    before = set(bpy.context.scene.objects)
    ai.import_model(path)
    new = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    for o in new:
        if o != obj and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.parent = None
    # Matrice applicata direttamente ai dati (transform_apply in batch mode e'
    # inaffidabile: un FBX importato resta ruotato/scalato). Via anche i
    # modificatori: l'Armature di un rig deformerebbe con la posa, non il rest.
    obj.modifiers.clear()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.name = name
    # Stessa normalizzazione di import_ai3d: piedi a 0, centro XY, altezza.
    ai.normalize(obj, height)
    return obj


def force_source_texture(obj: bpy.types.Object, path: Path) -> None:
    """Un materiale Principled con `path` come Base Color, su tutto l'oggetto."""
    image = bpy.data.images.load(str(path))
    m = bpy.data.materials.new("SourceAlbedo")
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(m)


def ensure_image_node(obj: bpy.types.Object, image: bpy.types.Image) -> None:
    """Un solo materiale con un Image Texture attivo (il bake scrive li')."""
    if not obj.data.materials or obj.data.materials[0] is None:
        m = bpy.data.materials.new("Baked")
        obj.data.materials.clear()
        obj.data.materials.append(m)
    m = obj.data.materials[0]
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None) or nodes.new("ShaderNodeBsdfPrincipled")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.select = True
    nodes.active = tex
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    # Collegato solo DOPO il bake (altrimenti Cycles leggerebbe la texture vuota).
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])


def fill_black_texels(image: bpy.types.Image, threshold: float = 0.04, iterations: int = 300) -> int:
    """I texel che il bake non ha raggiunto restano neri (nessuna superficie
    sorgente lungo la normale: incavi, interno delle gambe). Li riempie per
    dilatazione con la media dei vicini colorati. Ritorna quanti ne ha riempiti."""
    w, h = image.size
    px = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = px[..., :3]
    black = rgb.max(axis=2) < threshold
    filled_total = int(black.sum())
    if filled_total == 0:
        return 0
    valid = ~black
    for _ in range(iterations):
        if valid.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros((h, w), dtype=np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                sv = np.roll(valid, (dy, dx), axis=(0, 1))
                sr = np.roll(rgb, (dy, dx), axis=(0, 1))
                acc += sr * sv[..., None]
                cnt += sv
        grow = (~valid) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        valid |= grow
    px[..., :3] = rgb
    image.pixels = px.ravel().tolist()
    return filled_total


def main() -> None:
    args = parse_args()
    src = Path(args.source).resolve()
    tgt = Path(args.target).resolve()
    out = Path(args.output).resolve()
    ai.clear_scene()
    scene = bpy.context.scene
    source = load_one(src, "Source", args.height)
    if args.source_texture:
        force_source_texture(source, Path(args.source_texture).resolve())
    target = load_one(tgt, "Target", args.height)
    if not target.data.uv_layers:
        # Shape senza Paint: nessuna UV. Smart UV Project basta per un bake
        # di colore (isole in base agli angoli, margine per il filtro).
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003)
        bpy.ops.object.mode_set(mode="OBJECT")
        print("AI3D " + json.dumps({"uv": "smart_project"}))

    image = bpy.data.images.new("baked_albedo", args.size, args.size, alpha=False)
    image.generated_color = (0.5, 0.5, 0.5, 1.0)
    ensure_image_node(target, image)

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    bake = scene.render.bake
    bake.use_selected_to_active = True
    bake.use_cage = False
    bake.cage_extrusion = args.cage
    bake.max_ray_distance = args.ray
    bake.margin = args.margin
    bake.use_pass_direct = False
    bake.use_pass_indirect = False
    bake.use_pass_color = True
    for o in scene.objects:
        o.select_set(o in (source, target))
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.bake(type="DIFFUSE", use_selected_to_active=True, cage_extrusion=args.cage,
                        max_ray_distance=args.ray, margin=args.margin)

    filled = fill_black_texels(image)
    albedo = out.with_name(out.stem + "_albedo.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    image.filepath_raw = str(albedo)
    image.file_format = "PNG"
    image.save()

    # Il sorgente non deve finire nell'export.
    bpy.data.objects.remove(source, do_unlink=True)
    target.name = out.stem
    target.data.name = out.stem
    for o in scene.objects:
        o.select_set(o == target)
    bpy.context.view_layer.objects.active = target
    ai.export_glb(out)
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend).resolve()))
    if args.preview:
        ai.render_preview(target, Path(args.preview).resolve())
    ai.log(bake="ok", black_texels_filled=filled, source=str(src), target=str(tgt), output=str(out), albedo=str(albedo),
           triangles=sum(len(p.vertices) - 2 for p in target.data.polygons),
           glb_bytes=out.stat().st_size)


if __name__ == "__main__":
    main()
