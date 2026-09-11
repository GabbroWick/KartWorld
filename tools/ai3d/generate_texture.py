"""Hunyuan3D 2.1 — Paint/PBR: texture per una mesh gia' generata, su GPU AMD/ROCm.

Uso:
  tools/ai3d/.venv/Scripts/python tools/ai3d/generate_texture.py --name <nome>
      [--mesh <file.glb|.obj>] [--image <png>] [--preset safe|low|normal] [--no-remesh]

Default: mesh = assets/characters/_generated/<nome>/model_raw.glb,
immagine = assets/characters/_generated/<nome>/input_rgba.png (la stessa
usata per la shape, cosi' la texture segue la geometria).
Scrive in assets/characters/_generated/<nome>/paint/:
  model_textured.obj/.glb, le mappe PBR (albedo, metallic-roughness, ...),
  report.json. Non tocca model_raw.glb.

Separato da generate_shape.py per scelta: shape e paint sono due modelli, due
download, due consumi di memoria. Il rasterizer e' quello puro-PyTorch del
fork (HY3D_RASTER=torch): niente estensioni CUDA/HIP da compilare.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
FORK = ROOT / "hunyuan3d"
UPSTREAM = FORK / "Hunyuan3D-2.1"
os.environ.setdefault("HF_HOME", str(ROOT / "models" / "hf"))
os.environ.setdefault("HY3DGEN_MODELS", str(ROOT / "models" / "hy3dgen"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("PYTORCH_HIP_ALLOC_CONF", "expandable_segments:True")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ.setdefault("MIOPEN_USER_DB_PATH", str(ROOT / "models" / "miopen"))
os.environ.setdefault("MIOPEN_CUSTOM_CACHE_DIR", str(ROOT / "models" / "miopen"))
os.environ.setdefault("HY3D_RASTER", "torch")   # mai il rasterizer nativo su Windows/ROCm
for p in (FORK, UPSTREAM, UPSTREAM / "hy3dshape", UPSTREAM / "hy3dpaint", ROOT):
    sys.path.insert(0, str(p))

import psutil  # noqa: E402
import torch  # noqa: E402

import backend as backend_mod  # noqa: E402
import compat_patches  # noqa: E402
import paint  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--mesh", default=None)
    ap.add_argument("--image", default=None)
    ap.add_argument("--preset", default="safe", choices=list(backend_mod.PAINT_PRESETS))
    ap.add_argument("--no-remesh", action="store_true",
                    help="non rimeshare a ~40k tri prima del bake (solo se la mesh e' gia' uniforme)")
    ap.add_argument("--out-root", default=str(PROJECT / "assets" / "characters" / "_generated"))
    args = ap.parse_args()

    gen_dir = Path(args.out_root) / args.name
    mesh = Path(args.mesh) if args.mesh else gen_dir / "model_raw.glb"
    image = Path(args.image) if args.image else gen_dir / "input_rgba.png"
    out = gen_dir / "paint"
    out.mkdir(parents=True, exist_ok=True)
    if not mesh.exists():
        print("Manca la mesh:", mesh)
        return 1
    if not image.exists():
        # input_rgba.png perso (o mesh esterna): ricostruiscilo dal concept con
        # lo stesso preprocess della shape (rembg + buchi chiusi + 512x512).
        source = Path(args.image) if args.image else gen_dir / "source.png"
        if not source.exists():
            source = PROJECT / "assets" / "characters" / "_source" / args.name / (args.name + "_front.png")
        if not source.exists():
            print("Manca l'immagine di partenza:", source)
            return 1
        from generate_shape import preprocess
        image = gen_dir / "input_rgba.png"
        preprocess(source, True).save(image)
        print("[paint] input_rgba.png ricostruito da", source, flush=True)

    b = backend_mod.detect()
    compat_patches.apply(b)
    ok, why = paint.availability()
    print("[paint] availability:", ok, why, flush=True)
    if not ok:
        return 1
    proc = psutil.Process()
    report = {"tool": "Hunyuan3D-2.1 paint (fork mac-rocm, rasterizer torch)", "mesh": str(mesh),
              "image": str(image), "preset": args.preset,
              "params": paint.resolve_params(args.preset), "remesh": not args.no_remesh,
              "backend": {"kind": b.kind, "device": b.device, "dtype": str(b.dtype), "raster": b.raster}}
    if b.device == "cuda":
        torch.cuda.reset_peak_memory_stats()
    t0 = time.perf_counter()
    result = paint.texture_mesh(str(mesh), str(image), b, preset=args.preset,
                                use_remesh=not args.no_remesh, output_dir=str(out))
    if b.device == "cuda":
        torch.cuda.synchronize()
        report["vram_peak_gb"] = round(torch.cuda.max_memory_allocated() / 2**30, 2)
        report["vram_reserved_gb"] = round(torch.cuda.max_memory_reserved() / 2**30, 2)
    mi = proc.memory_info()
    report["ram_peak_gb"] = round(getattr(mi, "peak_wset", mi.rss) / 2**30, 2)
    report["t_total_s"] = round(time.perf_counter() - t0, 1)
    report["result"] = {k: (str(v) if not isinstance(v, dict) else {kk: str(vv) for kk, vv in v.items()})
                        for k, v in result.items()}
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
