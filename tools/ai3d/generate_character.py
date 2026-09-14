"""Un comando per tutta la pipeline di un personaggio:

  concept.png  ->  Hunyuan3D shape  ->  Hunyuan3D Paint (texture)
               ->  Blender (pulizia, coda, decimazione, preview)
               ->  GLB finale + FBX per Mixamo

Uso:
  tools/ai3d/.venv/Scripts/python tools/ai3d/generate_character.py <nome> [--image concept.png]
      [--height 1.35] [--faces 12000] [--steps 40] [--octree 256] [--seed 1234]
      [--no-paint] [--bake-from modello.glb --bake-texture albedo.png]
      [--clip-back M] [--cut-tail-root M] [--tail M] [--tail-radius R]
      [--from shape|paint|blender]   riparte da uno stadio (salta i precedenti)

Default immagine: assets/characters/_source/<nome>/<nome>_front.png.
Output:
  assets/characters/_generated/<nome>/     shape + paint (grezzo, mai toccato a mano)
  assets/characters/_processed/<nome>/     GLB pulito, preview 4 viste, .blend, mixamo/
  assets/characters/_final/<nome>/<nome>.glb   quello che Godot importa
  assets/models/ai/<nome>/                 <nome>_for_mixamo.fbx (+ albedo se bake)
Il rig Mixamo resta un passaggio manuale (vedi README_3D §3b).
Ogni stadio stampa la riga di comando eseguita, cosi' si puo' rilanciare a mano.
"""
import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
PY = ROOT / ".venv" / "Scripts" / "python.exe"
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe")
STAGES = ["shape", "paint", "blender"]


def run(cmd: list, label: str) -> None:
    print("\n=== %s\n$ %s" % (label, " ".join(str(c) for c in cmd)), flush=True)
    t0 = time.perf_counter()
    result = subprocess.run([str(c) for c in cmd], cwd=str(PROJECT))
    print("=== %s: exit %d in %.0f s" % (label, result.returncode, time.perf_counter() - t0), flush=True)
    if result.returncode != 0:
        raise SystemExit("Stadio '%s' fallito." % label)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--image", default=None)
    ap.add_argument("--height", type=float, default=1.35)
    ap.add_argument("--faces", type=int, default=12000)
    ap.add_argument("--steps", type=int, default=40)
    ap.add_argument("--octree", type=int, default=256)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--no-paint", action="store_true", help="niente texture Hunyuan (usa --bake-from o resta bianco)")
    ap.add_argument("--bake-from", default="", help="modello texturizzato da cui cuocere l'albedo (invece del Paint)")
    ap.add_argument("--bake-texture", default="", help="albedo da forzare sul modello --bake-from (FBX Mixamo)")
    ap.add_argument("--clip-back", type=float, default=0.0)
    ap.add_argument("--cut-tail-root", type=float, default=0.0)
    ap.add_argument("--tail", type=float, default=0.0)
    ap.add_argument("--tail-radius", type=float, default=0.055)
    ap.add_argument("--from", dest="start", default="shape", choices=STAGES)
    args = ap.parse_args()

    name = args.name
    src_dir = PROJECT / "assets" / "characters" / "_source" / name
    gen = PROJECT / "assets" / "characters" / "_generated" / name
    proc = PROJECT / "assets" / "characters" / "_processed" / name
    final = PROJECT / "assets" / "characters" / "_final" / name
    models = PROJECT / "assets" / "models" / "ai" / name
    image = Path(args.image) if args.image else src_dir / (name + "_front.png")
    if not image.exists():
        print("Concept mancante:", image)
        return 1
    for d in (proc, final, models):
        d.mkdir(parents=True, exist_ok=True)
    start = STAGES.index(args.start)
    t_all = time.perf_counter()

    # 1. shape
    if start <= 0:
        run([PY, ROOT / "generate_shape.py", image, "--name", name, "--steps", args.steps,
             "--octree", args.octree, "--seed", args.seed], "shape")

    # 2. texture
    use_paint = not args.no_paint and not args.bake_from
    if start <= 1 and use_paint:
        run([PY, ROOT / "generate_texture.py", "--name", name, "--preset", "safe"], "paint")

    # 3. blender: pulizia (+ bake se richiesto)
    blender_in = gen / "paint" / "model_raw_textured.obj" if use_paint else gen / "model_raw.glb"
    if not blender_in.exists():
        print("Input Blender mancante:", blender_in)
        return 1
    clean = proc / (name + "_clean.glb")
    cmd = [BLENDER, "-b", "--python", PROJECT / "tools" / "blender" / "import_ai3d.py", "--",
           "--input", blender_in, "--output", clean, "--height", args.height, "--faces", args.faces,
           "--preview", proc / "preview.png", "--blend", proc / (name + ".blend")]
    if args.clip_back > 0:
        cmd += ["--clip-back", args.clip_back]
    if args.cut_tail_root > 0:
        cmd += ["--cut-tail-root", args.cut_tail_root]
    if args.tail > 0:
        cmd += ["--tail", args.tail, "--tail-radius", args.tail_radius]
    run(cmd, "blender")
    result = clean
    if args.bake_from:
        baked = proc / (name + "_baked.glb")
        cmd = [BLENDER, "-b", "--python", PROJECT / "tools" / "blender" / "bake_transfer.py", "--",
               "--source", args.bake_from, "--target", clean, "--output", baked, "--height", args.height,
               "--cage", 0.15, "--ray", 0.8, "--preview", proc / "preview_baked.png"]
        if args.bake_texture:
            cmd += ["--source-texture", args.bake_texture]
        run(cmd, "bake")
        result = baked
        shutil.copy2(proc / (name + "_baked_albedo.png"), models / (name + "_albedo.png"))

    # 4. finale + FBX per Mixamo
    target = final / (name + ".glb")
    if target.exists():
        backup = proc / (name + "_final_backup_%s.glb" % time.strftime("%Y%m%d_%H%M%S"))
        shutil.copy2(target, backup)
        print("backup del finale precedente:", backup)
    shutil.copy2(result, target)
    run([BLENDER, "-b", "--python", PROJECT / "tools" / "blender" / "export_for_mixamo.py", "--",
         "--input", target, "--outdir", proc / "mixamo"], "mixamo-fbx")
    shutil.copy2(proc / "mixamo" / (name + "_untextured.fbx"), models / (name + "_for_mixamo.fbx"))

    summary = {"name": name, "image": str(image), "final": str(target), "preview": str(proc / "preview.png"),
               "mixamo_fbx": str(models / (name + "_for_mixamo.fbx")), "texture": "paint" if use_paint else ("bake" if args.bake_from else "none"),
               "t_total_s": round(time.perf_counter() - t_all)}
    (proc / "pipeline.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("\n" + json.dumps(summary, indent=2))
    print("\nProssimo passo manuale: carica %s su mixamo.com (Standard skeleton, With Skin + Breathing Idle) "
          "e salva il risultato come %s" % (summary["mixamo_fbx"], models / (name + "_rig.fbx")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
