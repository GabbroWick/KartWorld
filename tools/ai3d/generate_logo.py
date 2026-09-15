"""Genera candidati per il logo/icona dell'app con SDXL Turbo (locale, ROCm).

Uso (dal venv tools/ai3d/.venv):
  python tools/ai3d/generate_logo.py --variants 6 --seed 1
  -> assets/ui/logo/_source/logo_<seed>.png  (1024x1024)

Poi si sceglie il migliore e si esporta con:
  python tools/ai3d/generate_logo.py --pick assets/ui/logo/_source/logo_3.png
  -> icon.png (512), assets/ui/logo/icon_192.png, icon_432.png (adaptive foreground)
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent

PROMPT = ("app icon, cute cartoon leopard cub driving a small blue go-kart, big smile, "
          "speed lines, tropical island and palm tree in the background, bold vibrant colors, "
          "thick outlines, glossy sticker style, centered composition, rounded square icon, "
          "3D render, playful kids game logo")
NEGATIVE = ("text, letters, watermark, signature, realistic, photo, blurry, dark, gore, "
            "extra limbs, deformed, multiple animals, cropped")


def generate(args):
    import torch
    from diffusers import AutoPipelineForText2Image
    device = "cuda"
    dtype = torch.float16
    pipe = AutoPipelineForText2Image.from_pretrained(
        "stabilityai/sdxl-turbo", torch_dtype=dtype, variant="fp16", use_safetensors=True).to(device)
    out = PROJECT / "assets" / "ui" / "logo" / "_source"
    out.mkdir(parents=True, exist_ok=True)
    for i in range(args.variants):
        seed = args.seed + i
        gen = torch.Generator(device=device).manual_seed(seed)
        image = pipe(prompt=PROMPT, negative_prompt=NEGATIVE, num_inference_steps=args.steps,
                     guidance_scale=0.0, width=args.size, height=args.size, generator=gen).images[0]
        path = out / f"logo_{seed}.png"
        image.save(path)
        print("LOGO", path)


def pick(source: Path):
    from PIL import Image, ImageDraw
    img = Image.open(source).convert("RGBA")
    # Rounded square mask for the plain icon.
    size = 512
    base = img.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=96, fill=255)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(base, (0, 0), mask)
    icon.save(PROJECT / "icon.png")
    logo_dir = PROJECT / "assets" / "ui" / "logo"
    icon.resize((192, 192), Image.LANCZOS).save(logo_dir / "icon_192.png")
    # Adaptive foreground: the picture in the safe centre (66%) of a 432 canvas.
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    inner = img.resize((300, 300), Image.LANCZOS)
    fg.paste(inner, (66, 66))
    fg.save(logo_dir / "icon_432.png")
    bg = Image.new("RGBA", (432, 432), (74, 150, 230, 255))
    bg.save(logo_dir / "icon_bg_432.png")
    img.resize((512, 512), Image.LANCZOS).save(logo_dir / "icon_512.png")
    print("ICON written: icon.png, icon_192.png, icon_432.png, icon_bg_432.png, icon_512.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--steps", type=int, default=6)
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--pick", default="")
    args = ap.parse_args()
    if args.pick:
        pick(Path(args.pick))
    else:
        generate(args)


if __name__ == "__main__":
    main()
