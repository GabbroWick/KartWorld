"""Blender headless: importa un modello generato dall'AI, lo normalizza e lo
esporta come GLB pronto per Godot. Non tocca il file di ingresso.

Uso (da tools/ai3d/blender.cmd o direttamente):
  blender -b --python tools/blender/import_ai3d.py -- \
      --input assets/characters/_generated/leopard/model_raw.glb \
      --output assets/characters/_processed/leopard/leopard_clean.glb \
      [--height 1.35] [--faces 12000] [--up=+Z] [--forward=-Y] [--preview out.png] [--blend out.blend]
  (gli assi negativi vanno passati con '=' o argparse li legge come opzioni)

Cosa fa, nell'ordine:
  1. importa OBJ / GLB / FBX / PLY / STL
  2. unisce le mesh in una, applica le trasformazioni
  3. ruota: --up diventa Z e --forward diventa -Y (convenzione Blender; il
     GLB esportato ha Y su e il davanti a -Z in Godot)
  4. scala a --height metri, mette i piedi a y=0 e l'origine sotto i piedi
  5. normali ricalcolate coerenti, doppioni saldati, facce degenerate via
  6. (opzionale) decimazione a --faces triangoli con conservazione UV
  7. esporta GLB (Y up, +Z avanti in glTF = -Z in Godot) e, se chiesto, un
     PNG di anteprima 4 viste e il .blend intermedio
Stampa un riepilogo JSON su stdout (righe che iniziano con "AI3D ").
"""
import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--height", type=float, default=1.35, help="altezza finale in metri (0 = non scalare)")
    p.add_argument("--faces", type=int, default=0, help="triangoli massimi (0 = niente decimazione)")
    p.add_argument("--forward", default="-Y", choices=["-Z", "+Z", "-X", "+X", "-Y", "+Y"],
                   help="asse verso cui guarda il modello come appare in Blender dopo l'import (usa --forward=-Z)")
    p.add_argument("--up", default="+Z", choices=["-Z", "+Z", "-X", "+X", "-Y", "+Y"],
                   help="asse verticale del modello come appare in Blender dopo l'import")
    p.add_argument("--preview", default="")
    p.add_argument("--blend", default="")
    p.add_argument("--flat", action="store_true", help="shading flat (low-poly) invece di smooth")
    p.add_argument("--clip-back", type=float, default=0.0,
                   help="tieni solo la geometria entro questa profondita' (m) dal punto piu' avanti "
                        "(muso) e chiudi il taglio: code inventate dall'AI. 0 = niente")
    p.add_argument("--keep-loose", action="store_true",
                   help="non rimuovere le parti sciolte piccole (frammenti staccati dall'AI)")
    return p.parse_args(argv)


def log(**kv) -> None:
    print("AI3D " + json.dumps(kv))


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path: Path) -> None:
    ext = path.suffix.lower()
    if ext == ".glb" or ext == ".gltf":
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    elif ext == ".ply":
        bpy.ops.wm.ply_import(filepath=str(path))
    elif ext == ".stl":
        bpy.ops.wm.stl_import(filepath=str(path))
    else:
        raise SystemExit("Formato non supportato: %s" % ext)


def join_meshes() -> bpy.types.Object:
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("Nessuna mesh importata.")
    for o in bpy.context.scene.objects:
        o.select_set(o.type == "MESH")
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Elimina gli empty/armature residui degli importer.
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.parent = None
    # Matrice applicata ai dati: transform_apply in batch mode e' inaffidabile
    # (un FBX importato resterebbe ruotato). Niente modificatori residui.
    obj.modifiers.clear()
    obj.data.transform(obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    return obj


def orient(obj: bpy.types.Object, forward: str, up: str) -> None:
    """Porta il modello nella convenzione Blender (Z su, -Y avanti).
    `up` e `forward` descrivono gli assi del modello COME APPARE IN BLENDER
    dopo l'import (l'importer glTF ha gia' convertito Y-up in Z-up)."""
    axis = {"+X": Vector((1, 0, 0)), "-X": Vector((-1, 0, 0)), "+Y": Vector((0, 1, 0)),
            "-Y": Vector((0, -1, 0)), "+Z": Vector((0, 0, 1)), "-Z": Vector((0, 0, -1))}
    up_v = axis[up if up[0] in "+-" else "+" + up]
    fwd_v = axis[forward]
    # 1. asse verticale -> +Z
    rot_up = up_v.rotation_difference(Vector((0, 0, 1)))
    fwd_v = rot_up @ fwd_v
    # 2. asse frontale -> -Y, ruotando solo attorno a Z (angolo esplicito: la
    #    rotation_difference fra vettori opposti, 180 gradi, e' degenere).
    angle = math.atan2(fwd_v.x, -fwd_v.y) if fwd_v.xy.length > 0.0001 else 0.0
    rot_fwd = Quaternion((0.0, 0.0, 1.0), angle)
    # Direttamente sui dati mesh: transform_apply in batch mode e' inaffidabile.
    obj.data.transform((rot_fwd @ rot_up).to_matrix().to_4x4())
    obj.data.update()
    obj.rotation_euler = (0.0, 0.0, 0.0)


def drop_loose_parts(obj: bpy.types.Object, min_ratio: float = 0.02) -> int:
    """Rimuove le isole di mesh con meno di `min_ratio` dei vertici totali
    (schegge staccate: una punta di coda, un pezzo di orecchio). Ritorna
    quante ne ha tolte."""
    # Prima salda i vertici doppi: una mesh con UV (Hunyuan Paint, xatlas) e'
    # spezzata lungo le cuciture e ogni isola UV sembrerebbe "sciolta".
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.object.mode_set(mode="OBJECT")
    total = len(obj.data.vertices)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    parts.sort(key=lambda o: len(o.data.vertices), reverse=True)
    keep = [parts[0]] + [o for o in parts[1:] if len(o.data.vertices) >= total * min_ratio]
    removed = 0
    for o in parts:
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
            removed += 1
    for o in keep:
        o.select_set(True)
    bpy.context.view_layer.objects.active = keep[0]
    if len(keep) > 1:
        bpy.ops.object.join()
    return removed


def normalize(obj: bpy.types.Object, height: float) -> dict:
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.dissolve_degenerate()
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    size = Vector((max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)))
    scale = height / size.z if height > 0 and size.z > 0 else 1.0
    centre = Vector(((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, min(zs)))
    for v in obj.data.vertices:
        v.co = (v.co - centre) * scale
    obj.location = (0, 0, 0)
    return {"source_size": [round(c, 3) for c in size], "scale": round(scale, 4),
            "final_height": round(size.z * scale, 3)}


def clip_back(obj: bpy.types.Object, distance: float) -> int:
    """Rimuove la geometria dietro y = +distance (dopo la normalizzazione: il
    davanti e' -Y) e chiude il foro. Ritorna i vertici rimossi."""
    if distance <= 0.0:
        return 0
    before = len(obj.data.vertices)
    # Misurato dal punto piu' avanti (il muso), non dal centro del bounding box:
    # una coda lunga sposterebbe il centro.
    front = min(v.co.y for v in obj.data.vertices)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=(0.0, front + distance, 0.0), plane_no=(0.0, 1.0, 0.0),
                        clear_outer=True, use_fill=True)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return before - len(obj.data.vertices)


def decimate(obj: bpy.types.Object, faces: int) -> None:
    tri = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if faces <= 0 or tri <= faces:
        return
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = faces / tri
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)


def shading(obj: bpy.types.Object, flat: bool) -> None:
    for p in obj.data.polygons:
        p.use_smooth = not flat
    if not flat:
        # Smooth con spigoli netti sopra 60 gradi (stile cartoon pulito).
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(60.0))


def ensure_material(obj: bpy.types.Object) -> str:
    """Un solo materiale Principled, opaco (metallic 0, roughness 1). Se la
    mesh ha colori per vertice e nessuna texture, li collega al Base Color
    (TripoSR li produce; i materiali degli importer non li usano)."""
    if obj.data.materials and obj.data.materials[0]:
        m = obj.data.materials[0]
    else:
        m = bpy.data.materials.new("AI3D_Material")
        obj.data.materials.append(m)
    m.use_nodes = True
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL"), None)             or m.node_tree.nodes.new("ShaderNodeOutputMaterial")
        m.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 1.0
    base = bsdf.inputs["Base Color"]
    has_texture = base.is_linked and base.links[0].from_node.type == "TEX_IMAGE"
    if obj.data.color_attributes and not has_texture:
        for link in list(base.links):
            m.node_tree.links.remove(link)
        attr = m.node_tree.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = obj.data.color_attributes[0].name
        m.node_tree.links.new(attr.outputs["Color"], base)
    return m.name


def export_glb(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    has_colors = bool(bpy.context.object.data.color_attributes)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_apply=True,
                              export_yup=True, export_normals=True, export_texcoords=True,
                              export_materials="EXPORT",
                              export_vertex_color="ACTIVE" if has_colors else "NONE",
                              export_active_vertex_color_when_no_material=has_colors)


def render_preview(obj: bpy.types.Object, path: Path) -> None:
    """Quattro viste ortografiche (fronte, lato, retro, 3/4) affiancate."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("W")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.45, 0.45, 0.45, 1.0)
    bg.inputs[1].default_value = 1.0
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(30.0))
    scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    height = max(obj.dimensions.z, 0.1)
    cam_data.ortho_scale = height * 1.25
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    centre = Vector((0, 0, height * 0.5))
    views = {"front": Vector((0, -5, 0)), "side": Vector((5, 0, 0)), "back": Vector((0, 5, 0)),
             "quarter": Vector((3.5, -3.5, 1.5))}
    tiles = []
    for name, offset in views.items():
        cam.location = centre + offset
        direction = centre - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        tile = path.with_name(path.stem + "_" + name + ".png")
        scene.render.filepath = str(tile)
        bpy.ops.render.render(write_still=True)
        tiles.append(tile)
    # Affianca con le API immagine di Blender (niente PIL in Blender).
    w = 512
    sheet = bpy.data.images.new("sheet", w * 4, w)
    pixels = [0.0] * (w * 4 * w * 4)
    for i, tile in enumerate(tiles):
        img = bpy.data.images.load(str(tile))
        px = list(img.pixels)
        for row in range(w):
            src = row * w * 4
            dst = (row * w * 4 + i * w) * 4
            pixels[dst:dst + w * 4] = px[src:src + w * 4]
        bpy.data.images.remove(img)
        tile.unlink()
    sheet.pixels = pixels
    sheet.filepath_raw = str(path)
    sheet.file_format = "PNG"
    sheet.save()


def main() -> None:
    args = parse_args()
    src = Path(args.input).resolve()
    dst = Path(args.output).resolve()
    if not src.exists():
        raise SystemExit("Input mancante: %s" % src)
    clear_scene()
    import_model(src)
    obj = join_meshes()
    before = {"vertices": len(obj.data.vertices), "faces": len(obj.data.polygons),
              "uv": bool(obj.data.uv_layers), "vertex_colors": bool(obj.data.color_attributes),
              "materials": [m.name for m in obj.data.materials if m]}
    orient(obj, args.forward, args.up)
    loose_removed = 0 if args.keep_loose else drop_loose_parts(obj)
    obj = bpy.context.view_layer.objects.active
    norm = normalize(obj, args.height)
    clipped = clip_back(obj, args.clip_back)
    if clipped:
        norm = normalize(obj, args.height)   # ricentra dopo il taglio
    decimate(obj, args.faces)
    shading(obj, args.flat)
    material = ensure_material(obj)
    obj.name = dst.stem
    obj.data.name = dst.stem
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    export_glb(dst)
    if args.blend:
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend).resolve()))
    if args.preview:
        render_preview(obj, Path(args.preview).resolve())
    after = {"vertices": len(obj.data.vertices),
             "triangles": sum(len(p.vertices) - 2 for p in obj.data.polygons),
             "dimensions": [round(d, 3) for d in obj.dimensions], "material": material}
    log(input=str(src), output=str(dst), before=before, loose_parts_removed=loose_removed,
        clipped_vertices=clipped,
        normalize=norm, after=after, glb_bytes=dst.stat().st_size)


if __name__ == "__main__":
    main()
