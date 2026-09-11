"""Smoke test image-to-3D con TripoSR sulla GPU AMD (ROCm).

Uso:
  tools/ai3d/.venv/Scripts/python tools/ai3d/smoke_test_triposr.py <immagine> [--out DIR] [--mc 256]

Scopo: provare che l'intera catena (rembg -> encoder -> triplane -> marching
cubes -> file mesh) gira sulla RX 9060 XT. Non e' il generatore definitivo.
Scrive in DIR: input_rgba.png, model_raw.obj, model_raw.glb, report.json,
README.md. Esce 1 se la mesh non e' valida.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
os.environ.setdefault("HF_HOME", str(ROOT / "models" / "hf"))
os.environ.setdefault("U2NET_HOME", str(ROOT / "models" / "rembg"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
sys.path.insert(0, str(ROOT / "shims"))      # torchmcubes -> scikit-image
sys.path.insert(0, str(ROOT / "TripoSR"))

import numpy as np  # noqa: E402
import psutil  # noqa: E402
import rembg  # noqa: E402
import torch  # noqa: E402
import trimesh  # noqa: E402
from PIL import Image  # noqa: E402

from tsr.system import TSR  # noqa: E402
from tsr.utils import remove_background, resize_foreground  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--out", default=None)
    parser.add_argument("--mc", type=int, default=256, help="risoluzione marching cubes")
    parser.add_argument("--chunk", type=int, default=8192)
    args = parser.parse_args()

    image_path = Path(args.image)
    out = Path(args.out) if args.out else ROOT.parents[1] / "assets" / "characters" / "_generated" / (image_path.stem + "_triposr")
    out.mkdir(parents=True, exist_ok=True)
    proc = psutil.Process()
    report = {"tool": "TripoSR", "input": str(image_path), "device": None, "errors": []}
    gpu = torch.cuda.is_available()
    device = "cuda" if gpu else "cpu"
    report["device"] = torch.cuda.get_device_name(0) if gpu else "cpu"
    t_all = time.perf_counter()

    # 1. Modello (scaricato nella cache locale la prima volta: ~1.6 GB).
    t0 = time.perf_counter()
    model = TSR.from_pretrained("stabilityai/TripoSR", config_name="config.yaml", weight_name="model.ckpt")
    model.renderer.set_chunk_size(args.chunk)
    model.to(device)
    report["t_load_s"] = round(time.perf_counter() - t0, 1)

    # 2. Immagine: sfondo via, soggetto centrato all'85%.
    t0 = time.perf_counter()
    image = remove_background(Image.open(image_path), rembg.new_session())
    image = resize_foreground(image, 0.85)
    rgba = np.array(image).astype(np.float32) / 255.0
    rgb = rgba[:, :, :3] * rgba[:, :, 3:4] + (1 - rgba[:, :, 3:4]) * 0.5
    image.save(out / "input_rgba.png")
    image = Image.fromarray((rgb * 255.0).astype(np.uint8))
    report["t_preprocess_s"] = round(time.perf_counter() - t0, 1)

    # 3. Inferenza.
    if gpu:
        torch.cuda.reset_peak_memory_stats()
    t0 = time.perf_counter()
    with torch.no_grad():
        scene_codes = model([image], device=device)
    if gpu:
        torch.cuda.synchronize()
    report["t_infer_s"] = round(time.perf_counter() - t0, 1)

    # 4. Mesh.
    t0 = time.perf_counter()
    meshes = model.extract_mesh(scene_codes, True, resolution=args.mc)
    mesh: trimesh.Trimesh = meshes[0]
    report["t_mesh_s"] = round(time.perf_counter() - t0, 1)
    if gpu:
        report["vram_peak_gb"] = round(torch.cuda.max_memory_allocated() / 2**30, 2)
        report["vram_reserved_gb"] = round(torch.cuda.max_memory_reserved() / 2**30, 2)
    report["ram_peak_gb"] = round(proc.memory_info().peak_wset / 2**30, 2) if hasattr(proc.memory_info(), "peak_wset") else round(proc.memory_info().rss / 2**30, 2)

    # 5. Export + validazione.
    mesh.export(out / "model_raw.obj")
    mesh.export(out / "model_raw.glb")
    check = trimesh.load(out / "model_raw.glb", force="mesh")
    ext = check.bounding_box.extents
    report.update({
        "vertices": int(check.vertices.shape[0]),
        "faces": int(check.faces.shape[0]),
        "extents": [round(float(x), 3) for x in ext],
        "watertight": bool(check.is_watertight),
        "has_vertex_colors": bool(mesh.visual.kind == "vertex"),
        "formats": ["obj", "glb"],
        "glb_bytes": (out / "model_raw.glb").stat().st_size,
        "t_total_s": round(time.perf_counter() - t_all, 1),
    })
    ok = report["faces"] > 1000 and all(x > 0.05 for x in ext) and report["glb_bytes"] > 10_000
    report["valid"] = bool(ok)
    (out / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (out / "README.md").write_text(
        "# %s (TripoSR smoke test)\n\nInput: `%s`\n\n```json\n%s\n```\n" % (out.name, image_path, json.dumps(report, indent=2)),
        encoding="utf-8")
    print(json.dumps(report, indent=2))
    print("VALID" if ok else "INVALID")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
