"""Disegna uno scheletro OpenPose (18 keypoint, colori standard) in T-pose
con proporzioni chibi, da dare a ControlNet come immagine di controllo.

Uso:  tools/ai3d/.venv/Scripts/python tools/ai3d/make_pose.py [--out tools/ai3d/poses/tpose_chibi.png] [--size 640]
Nessun modello: solo PIL.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw

# Ordine COCO/OpenPose 18: 0 naso, 1 collo, 2 spalla dx, 3 gomito dx, 4 polso dx,
# 5 spalla sx, 6 gomito sx, 7 polso sx, 8 anca dx, 9 ginocchio dx, 10 caviglia dx,
# 11 anca sx, 12 ginocchio sx, 13 caviglia sx, 14 occhio dx, 15 occhio sx,
# 16 orecchio dx, 17 orecchio sx.  "dx" = destra del personaggio = sinistra immagine.
LIMBS = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7), (1, 8), (8, 9), (9, 10), (1, 11),
         (11, 12), (12, 13), (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0), (170, 255, 0), (85, 255, 0),
          (0, 255, 0), (0, 255, 85), (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
          (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255), (255, 0, 170), (255, 0, 85)]


def chibi_tpose(w: int, h: int) -> list:
    cx = w * 0.5
    # Testa grande: naso al 22%, collo al 40%, anche al 62%, caviglie al 92%.
    nose = (cx, h * 0.24)
    neck = (cx, h * 0.42)
    sh = h * 0.44
    arm = w * 0.14
    hip_y = h * 0.62
    hip_dx = w * 0.06
    return [
        nose, neck,
        (cx - w * 0.09, sh), (cx - w * 0.09 - arm, sh), (cx - w * 0.09 - 2 * arm, sh),   # braccio dx (T)
        (cx + w * 0.09, sh), (cx + w * 0.09 + arm, sh), (cx + w * 0.09 + 2 * arm, sh),   # braccio sx (T)
        (cx - hip_dx, hip_y), (cx - hip_dx, h * 0.77), (cx - hip_dx, h * 0.92),
        (cx + hip_dx, hip_y), (cx + hip_dx, h * 0.77), (cx + hip_dx, h * 0.92),
        (cx - w * 0.04, h * 0.21), (cx + w * 0.04, h * 0.21),
        (cx - w * 0.09, h * 0.23), (cx + w * 0.09, h * 0.23),
    ]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent / "poses" / "tpose_chibi.png"))
    ap.add_argument("--size", type=int, default=640)
    args = ap.parse_args()
    w = h = args.size
    pts = chibi_tpose(w, h)
    img = Image.new("RGB", (w, h), (0, 0, 0))
    d = ImageDraw.Draw(img)
    r = max(3, w // 90)
    for i, (a, b) in enumerate(LIMBS):
        d.line([pts[a], pts[b]], fill=COLORS[i], width=max(4, w // 60))
    for i, p in enumerate(pts):
        d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=COLORS[i])
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("pose ->", out)


if __name__ == "__main__":
    main()
