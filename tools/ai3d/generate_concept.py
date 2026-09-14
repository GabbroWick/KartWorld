"""Concept 2D per un personaggio, in T-pose, nello stile del leopardo — con
Stable Diffusion XL Turbo in locale (GPU AMD/ROCm) + IP-Adapter per lo stile.

Uso:
  tools/ai3d/.venv/Scripts/python tools/ai3d/generate_concept.py --name fox \
      --prompt "cute cartoon fox mascot, orange fur, white belly and tail tip, big eyes" \
      [--style assets/characters/_source/leopard_tpose/leopard_tpose_front.png] \
      [--variants 4] [--seed 1] [--steps 4] [--ip-scale 0.55] [--guidance 0.0]

Scrive in assets/characters/_source/<nome>/:
  <nome>_concept_<seed>.png   una per variante (1024x1024, sfondo grigio)
  README.md                   prompt e parametri usati
Poi si sceglie la migliore e la si passa a generate_shape.py.

SDXL Turbo: 4 passi, guidance 0 (il modello e' distillato, la CFG lo
peggiora). IP-Adapter: l'immagine di stile pesa `ip-scale` (0.4-0.7 tiene
la palette e il "look"; oltre copia anche il soggetto). Il prompt fisso
aggiunge T-pose, vista frontale, sfondo neutro, colori piatti.
"""
import argparse
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
os.environ.setdefault("HF_HOME", str(ROOT / "models" / "hf"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("PYTORCH_HIP_ALLOC_CONF", "expandable_segments:True")

import torch  # noqa: E402
from PIL import Image  # noqa: E402

STYLE_DEFAULT = PROJECT / "assets" / "characters" / "_source" / "leopard_tpose" / "leopard_tpose_front.png"
POSITIVE_SUFFIX = (", full body, standing in a T-pose with both arms stretched out horizontally, "
                   "front view, facing the camera, symmetrical, feet on the ground, "
                   "cute chibi mascot proportions with a big round head, simple stylized low-poly "
                   "cartoon 3D render, flat colors, soft studio lighting, plain uniform gray background, "
                   "no props, no text, kids video game character")
NEGATIVE = ("realistic, photo, fur detail, text, watermark, multiple characters, side view, "
            "arms down, sitting, cropped, blurry, background scenery, weapon, clothes")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--prompt", required=True, help="descrizione del personaggio (senza posa/stile)")
    ap.add_argument("--style", default=str(STYLE_DEFAULT), help="immagine di riferimento per lo stile (IP-Adapter); '' = nessuna")
    ap.add_argument("--variants", type=int, default=4)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--steps", type=int, default=4)
    ap.add_argument("--guidance", type=float, default=0.0)
    ap.add_argument("--ip-scale", type=float, default=0.55)
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--out-root", default=str(PROJECT / "assets" / "characters" / "_source"))
    args = ap.parse_args()

    out = Path(args.out_root) / args.name
    out.mkdir(parents=True, exist_ok=True)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32
    print("[sd] device", device, torch.cuda.get_device_name(0) if device == "cuda" else "", flush=True)

    from diffusers import AutoPipelineForText2Image
    t0 = time.perf_counter()
    pipe = AutoPipelineForText2Image.from_pretrained(
        "stabilityai/sdxl-turbo", torch_dtype=dtype, variant="fp16", use_safetensors=True)
    style = None
    if args.style:
        from transformers import CLIPVisionModelWithProjection
        encoder = CLIPVisionModelWithProjection.from_pretrained(
            "h94/IP-Adapter", subfolder="models/image_encoder", torch_dtype=dtype, use_safetensors=True)
        pipe.image_encoder = encoder
        pipe.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models",
                             weight_name="ip-adapter_sdxl_vit-h.safetensors")
        pipe.set_ip_adapter_scale(args.ip_scale)
        style = Image.open(args.style).convert("RGB")
    pipe.to(device)
    print("[sd] loaded in %.1fs" % (time.perf_counter() - t0), flush=True)

    prompt = args.prompt.strip().rstrip(",") + POSITIVE_SUFFIX
    lines = ["# %s — concept SDXL Turbo" % args.name, "", "prompt: `%s`" % prompt,
             "negative: `%s`" % NEGATIVE, "style: `%s` (ip-scale %.2f)" % (args.style, args.ip_scale),
             "steps %d, guidance %.1f, size %d" % (args.steps, args.guidance, args.size), ""]
    if device == "cuda":
        torch.cuda.reset_peak_memory_stats()
    for i in range(args.variants):
        seed = args.seed + i
        gen = torch.Generator(device="cpu").manual_seed(seed)
        t0 = time.perf_counter()
        kwargs = dict(prompt=prompt, negative_prompt=NEGATIVE, num_inference_steps=args.steps,
                      guidance_scale=args.guidance, width=args.size, height=args.size, generator=gen)
        if style is not None:
            kwargs["ip_adapter_image"] = style
        image = pipe(**kwargs).images[0]
        path = out / ("%s_concept_%d.png" % (args.name, seed))
        image.save(path)
        dt = time.perf_counter() - t0
        print("[sd] seed %d -> %s (%.1fs)" % (seed, path.name, dt), flush=True)
        lines.append("* seed %d: `%s` (%.1f s)" % (seed, path.name, dt))
    if device == "cuda":
        lines.append("")
        lines.append("VRAM picco: %.2f GB" % (torch.cuda.max_memory_allocated() / 2**30))
    (out / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
