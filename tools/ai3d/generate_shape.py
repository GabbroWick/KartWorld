"""Hunyuan3D 2.1 — SOLO geometria (shape), da una immagine, su GPU AMD/ROCm.

Uso:
  tools/ai3d/.venv/Scripts/python tools/ai3d/generate_shape.py <immagine> --name <nome>
      [--steps 30] [--octree 256] [--guidance 5.0] [--seed 1234] [--no-remove-bg]

Scrive in assets/characters/_generated/<nome>/:
  source.png       copia dell'immagine di partenza
  input_rgba.png   immagine preprocessata (sfondo via, 512x512)
  model_raw.glb    mesh grezza del modello, senza texture (materiale assente)
  report.json      tempi, VRAM, RAM, parametri, statistiche mesh
  README.md        riepilogo leggibile
Non tocca mai la cartella _source e non sovrascrive un model_raw.glb
esistente: rinomina il vecchio in model_raw_<timestamp>.glb.

La parte Paint/PBR (texture) e' volutamente esclusa: script separato.
"""
import argparse
import json
import os
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
FORK = ROOT / "hunyuan3d"
UPSTREAM = FORK / "Hunyuan3D-2.1"
os.environ.setdefault("HF_HOME", str(ROOT / "models" / "hf"))
os.environ.setdefault("U2NET_HOME", str(ROOT / "models" / "rembg"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("PYTORCH_HIP_ALLOC_CONF", "expandable_segments:True")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
os.environ.setdefault("MIOPEN_USER_DB_PATH", str(ROOT / "models" / "miopen"))
os.environ.setdefault("MIOPEN_CUSTOM_CACHE_DIR", str(ROOT / "models" / "miopen"))
Path(os.environ["MIOPEN_USER_DB_PATH"]).mkdir(parents=True, exist_ok=True)
for p in (FORK, UPSTREAM, UPSTREAM / "hy3dshape"):
    sys.path.insert(0, str(p))

import numpy as np  # noqa: E402
import psutil  # noqa: E402
import torch  # noqa: E402
import trimesh  # noqa: E402
from PIL import Image  # noqa: E402

import backend as backend_mod  # noqa: E402  (fork)
import compat_patches  # noqa: E402  (fork)


def preprocess(path: Path, remove_bg: bool) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    if remove_bg:
        from rembg import new_session, remove
        img = remove(img, session=new_session("u2net"))  # u2net: licenza Apache-2
    w, h = img.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    return canvas.resize((512, 512), Image.LANCZOS)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--name", required=True, help="nome cartella in _generated/")
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--octree", type=int, default=256)
    ap.add_argument("--guidance", type=float, default=5.0)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--no-remove-bg", action="store_true")
    ap.add_argument("--out-root", default=str(PROJECT / "assets" / "characters" / "_generated"))
    args = ap.parse_args()

    src = Path(args.image).resolve()
    out = Path(args.out_root) / args.name
    out.mkdir(parents=True, exist_ok=True)
    proc = psutil.Process()
    report = {"tool": "Hunyuan3D-2.1 shape (fork mac-rocm, rasterizer non usato)", "input": str(src),
              "params": {"steps": args.steps, "octree": args.octree, "guidance": args.guidance, "seed": args.seed},
              "errors": []}
    t_all = time.perf_counter()

    b = backend_mod.detect()
    compat_patches.apply(b)
    report["backend"] = {"kind": b.kind, "device": b.device, "dtype": str(b.dtype), "gpu": b.gpu_name}
    print("[backend]", report["backend"], flush=True)

    shutil.copy2(src, out / "source.png")
    t0 = time.perf_counter()
    image = preprocess(src, not args.no_remove_bg)
    image.save(out / "input_rgba.png")
    report["t_preprocess_s"] = round(time.perf_counter() - t0, 1)

    t0 = time.perf_counter()
    from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline
    compat_patches.patch_scheduler_timestep_lookup()
    pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
        "tencent/Hunyuan3D-2.1", subfolder="hunyuan3d-dit-v2-1",
        use_safetensors=False, variant="fp16", device=b.device, dtype=b.dtype)
    pipe.to(b.device)
    report["t_load_s"] = round(time.perf_counter() - t0, 1)
    print("[load] %.1fs" % report["t_load_s"], flush=True)

    if b.device == "cuda":
        torch.cuda.reset_peak_memory_stats()
    gen = torch.Generator(device="cpu").manual_seed(args.seed)
    t0 = time.perf_counter()
    with torch.inference_mode():
        result = pipe(image=image, num_inference_steps=args.steps, guidance_scale=args.guidance,
                      octree_resolution=args.octree, generator=gen)
    if b.device == "cuda":
        torch.cuda.synchronize()
    report["t_generate_s"] = round(time.perf_counter() - t0, 1)
    mesh = result[0] if isinstance(result, (list, tuple)) else result
    if not isinstance(mesh, trimesh.Trimesh):
        mesh = getattr(mesh, "mesh", mesh)
    if b.device == "cuda":
        report["vram_peak_gb"] = round(torch.cuda.max_memory_allocated() / 2**30, 2)
        report["vram_reserved_gb"] = round(torch.cuda.max_memory_reserved() / 2**30, 2)
    mi = proc.memory_info()
    report["ram_peak_gb"] = round(getattr(mi, "peak_wset", mi.rss) / 2**30, 2)

    target = out / "model_raw.glb"
    if target.exists():
        target.rename(out / ("model_raw_%s.glb" % time.strftime("%Y%m%d_%H%M%S")))
    mesh.export(target)
    check = trimesh.load(target, force="mesh")
    ext = check.bounding_box.extents
    report.update({"vertices": int(check.vertices.shape[0]), "faces": int(check.faces.shape[0]),
                   "extents": [round(float(x), 3) for x in ext], "watertight": bool(check.is_watertight),
                   "glb_bytes": target.stat().st_size, "t_total_s": round(time.perf_counter() - t_all, 1)})
    ok = report["faces"] > 1000 and all(x > 0.05 for x in ext)
    report["valid"] = bool(ok)
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (out / "README.md").write_text(
        "# %s — Hunyuan3D 2.1 shape\n\nInput: `%s`\n\nmodel_raw.glb: geometria grezza, nessuna texture.\n\n```json\n%s\n```\n"
        % (args.name, src, json.dumps(report, indent=2)), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print("VALID" if ok else "INVALID")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
