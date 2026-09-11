# Pipeline 3D locale (immagine → modello → Blender → Godot)

Tutto gratuito e locale: PyTorch ROCm sulla RX 9060 XT, Hunyuan3D 2.1 per la
geometria, Blender 5.1 per pulizia/ottimizzazione, Godot per la verifica.
Nessuna API cloud. Stato aggiornato a fine file (sezione "Diario").

## Hardware verificato (2026-09-11)

| | |
| --- | --- |
| GPU | AMD Radeon RX 9060 XT 16 GB (`gfx1200`, RDNA4) |
| Backend | PyTorch 2.12.0+rocm7.14.1 (ruote ufficiali AMD per Windows, nessun SDK) |
| Test GPU | `check_gpu.py`: matmul 4096² fp32 37 ms, fp16 ok, conv ok, err vs CPU 0.001 |
| Python | 3.12 nel venv `tools/ai3d/.venv` (creato con `uv`) |
| Blender | 5.1.2 (`tools/blender/blender.cmd` è il wrapper) |

## Struttura

```
tools/ai3d/                  pipeline AI (cartella con .gdignore: Godot non la importa)
  .venv/                     ambiente Python (gitignored)
  models/                    cache pesi HF / rembg / MIOpen (gitignored)
  TripoSR/                   clone upstream, solo smoke test (gitignored)
  hunyuan3d/                 fork mac-rocm + Hunyuan3D-2.1 upstream (gitignored)
  shims/torchmcubes.py       sostituto puro-Python di torchmcubes (per TripoSR)
  check_gpu.py               verifica GPU/ROCm
  smoke_test_triposr.py      test rapido image→3D (1.6 GB di pesi, ~30 s)
  generate_shape.py          Hunyuan3D 2.1 SOLO shape → model_raw.glb
tools/blender/
  import_ai3d.py             import, orienta, scala, decima, esporta GLB + anteprima
  blender.cmd                wrapper per Blender 5.1
assets/characters/
  _source/<nome>/            concept / immagini di partenza (.gdignore)
  _generated/<nome>/         output grezzo dell'AI: source.png, input_rgba.png,
                             model_raw.glb, report.json, README.md (.gdignore)
  _processed/<nome>/         output Blender: <nome>_clean.glb, preview.png, .blend (.gdignore)
  _final/<nome>/<nome>.glb   il GLB che Godot importa (unica cartella importata)
```

Regola: `_source` e `_generated` non si sovrascrivono mai a mano; gli script
rinominano il vecchio `model_raw.glb` con timestamp prima di scriverne uno nuovo.

## 1. Avviare l'ambiente

Non serve attivare nulla: ogni comando usa l'interprete del venv.

```bash
tools/ai3d/.venv/Scripts/python tools/ai3d/check_gpu.py     # deve stampare "GPU OK"
```

Ricreare da zero (se il venv manca):

```bash
uv venv tools/ai3d/.venv --python 3.12
uv pip install --python tools/ai3d/.venv --index-url https://repo.amd.com/rocm/whl-multi-arch/ \
    "torch[device-gfx1200]==2.12.0+rocm7.14.1" "torchvision[device-gfx1200]==0.27.0+rocm7.14.1"
uv pip install --python tools/ai3d/.venv omegaconf einops "transformers>=4.45,<5" trimesh "rembg[cpu]" \
    huggingface-hub imageio scikit-image xatlas onnxruntime psutil pygltflib \
    "diffusers>=0.30,<0.36" accelerate safetensors pymeshlab opencv-python-headless pyyaml tqdm timm
git clone --depth 1 https://github.com/VAST-AI-Research/TripoSR.git tools/ai3d/TripoSR
git clone --depth 1 https://github.com/VladimirTalyzin/hunyuan3d-2.1-mac-rocm.git tools/ai3d/hunyuan3d
git clone --depth 1 https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git tools/ai3d/hunyuan3d/Hunyuan3D-2.1
```

`transformers` deve restare < 5: la 5.x rinomina i layer ViT e il checkpoint
TripoSR non carica più ("Missing key(s) ... q_proj").

## 2. Generare un modello

Immagine di partenza: un solo soggetto, vista frontale o 3/4, sfondo semplice
(lo script lo rimuove con rembg `u2net`, Apache-2). PNG 1024×1024 va bene.

```bash
# smoke test veloce (qualità bassa, per controllare che la GPU vada)
tools/ai3d/.venv/Scripts/python tools/ai3d/smoke_test_triposr.py assets/characters/_source/leopard/leopard_front.png

# generazione vera: solo geometria
tools/ai3d/.venv/Scripts/python tools/ai3d/generate_shape.py assets/characters/_source/leopard/leopard_front.png \
    --name leopard --steps 30 --octree 256
```

Parametri Hunyuan: `--steps` 30 (test) … 50 (buono); `--octree` 128 (test),
256 (default), 384 (massimo dettaglio, più VRAM e tempo); `--seed` per
ripetere. Primo avvio: scarica DiT fp16 7,0 GB + VAE 0,6 GB in
`tools/ai3d/models/hy3dgen/tencent/Hunyuan3D-2.1/` (~2 MB/s da HF: circa
un'ora).

## 3. Elaborare in Blender

```bash
tools/blender/blender.cmd -b --python tools/blender/import_ai3d.py -- \
    --input assets/characters/_generated/leopard/model_raw.glb \
    --output assets/characters/_processed/leopard/leopard_clean.glb \
    --height 1.35 --faces 12000 --up=+Z --forward=-Y \
    --preview assets/characters/_processed/leopard/preview.png \
    --blend assets/characters/_processed/leopard/leopard.blend
```

* `--up` / `--forward`: assi del modello **come appare in Blender dopo
  l'import** (Blender: Z su, -Y avanti). Gli assi negativi vanno scritti con
  `=` (`--forward=-Y`), altrimenti argparse li legge come opzioni.
  TripoSR grezzo: `--up=+X --forward=-Y`. Hunyuan3D 2.1: i default
  (`--up=+Z --forward=-Y`) sono giusti.
* `--height`: altezza finale in metri (leopardo 1.35, come la capsula in
  `resources/characters/leopard.tres`); piedi a y=0, origine sotto i piedi.
* `--faces`: triangoli massimi (0 = nessuna decimazione). Personaggio
  principale 10–15k, NPC 6–8k, nemici 3–5k.
* `--preview`: PNG con 4 viste (fronte, lato, retro, 3/4). Guardalo sempre.
* Esporta GLB Y-up con il davanti a -Z, la convenzione di Godot.

## 4. Dove finiscono i file

Vedi "Struttura". Il GLB finale si copia a mano (o con lo script di
automazione, quando ci sarà) in `assets/characters/_final/<nome>/<nome>.glb`:
solo quella cartella è importata da Godot.

## 5. Importare in Godot

`assets/characters/_final/<nome>/<nome>.glb` viene importato al primo avvio
dell'editor (`make import` o `godot --headless --editor --quit`). Poi:
`scenes/characters/visuals/<nome>_meshy.tscn` con `MeshyCharacterVisual`
(`model`, `flip_forward` se serve, `flatten_materials = true` per il look
flat) e `resources/characters/<nome>.tres` → `visual_scene`. Scena di
anteprima: `scenes/dev/character_preview.tscn`:

```bash
godot --path . res://scenes/dev/character_preview.tscn -- res://assets/characters/_final/leopard/leopard.glb 1.35 [shot.png]
```

Giradischi con la stessa luce del gioco, anello rosso all'altezza di
riferimento, misure a schermo (altezza, larghezza, profondità, min y).

## 6. Errori comuni

| Sintomo | Causa / rimedio |
| --- | --- |
| `torch.cuda.is_available()` False | driver AMD vecchio o ruota sbagliata: reinstalla con `--index-url https://repo.amd.com/rocm/whl-multi-arch/` e `[device-gfx1200]` |
| `warning: xnack 'Off' was requested` | innocuo su RDNA4 |
| `Missing key(s) in state_dict ... q_proj` | transformers 5.x: `uv pip install "transformers<5"` |
| `Identifier X not declared` in Godot | due istanze Godot in parallelo sul progetto: una alla volta |
| argparse `expected one argument` | asse negativo: usa `--forward=-Y` |
| Modello sdraiato / girato nell'anteprima | cambia `--up` / `--forward` e riguarda `preview.png` |
| Out of memory Hunyuan | `--octree 128` o `--steps 20`; chiudi il browser/GPU apps |
| Output GPU corrotto o reset schermo | Windows TDR (2 s): NON modificato; se serve, chiedere prima (chiave `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDelay`) |
| rembg sceglie `bria-rmbg` | licenza non commerciale: gli script forzano `u2net` |
| `No module named 'timm'` | dipendenza non dichiarata da hy3dshape: `uv pip install --python tools/ai3d/.venv timm` |
| Pesi Hunyuan in `~/.cache/hy3dgen` | l'upstream ignora `HF_HOME`; `generate_shape.py` imposta `HY3DGEN_MODELS=tools/ai3d/models/hy3dgen` |

## 7. Aggiornare il modello AI

```bash
git -C tools/ai3d/hunyuan3d pull
git -C tools/ai3d/hunyuan3d/Hunyuan3D-2.1 pull
uv pip install --python tools/ai3d/.venv --upgrade --index-url https://repo.amd.com/rocm/whl-multi-arch/ "torch[device-gfx1200]" "torchvision[device-gfx1200]"
tools/ai3d/.venv/Scripts/python tools/ai3d/check_gpu.py
```

Nuovi pesi si scaricano da soli alla prima esecuzione; i vecchi restano in
`tools/ai3d/models/hf/hub` (cancellabili a mano).

## 8. Nuovo personaggio

1. Concept in `assets/characters/_source/<nome>/<nome>_front.png`.
2. `generate_shape.py <png> --name <nome>` → controlla `report.json`.
3. `import_ai3d.py` con anteprima → guarda `preview.png`, sistema assi/altezza.
4. Copia in `_final/<nome>/<nome>.glb`, scena visual + `.tres`, prova in Godot.
5. (dopo) texture, rig, animazioni: sezioni da aggiungere.

## Diario

* **2026-09-11** — Fase 1 analisi, Fase 2 struttura, Fase 3 venv + torch
  ROCm (GPU vista, matmul ok), TripoSR smoke test riuscito (inferenza 24 s,
  VRAM 3 GB, 101k tri) → Blender `import_ai3d.py` verificato con anteprima
  (`--up=+X --forward=-Y`). Hunyuan3D 2.1 shape sul leopardo: 30 step,
  octree 256 → 300 s, VRAM picco 12,3 GB, RAM 20,7 GB, 260k tri; Blender
  → 12k tri → `_final/leopard/leopard.glb` → Godot preview ok (1,35 m,
  piedi a 0, fronte -Z). Difetto: la macchia chiara della pancia è
  diventata un buco passante (mesh non chiusa). Seed 7 / 50 step in prova.
  Non ancora fatto: Paint/PBR (texture), rig, automazione `generate_character`.
  Pesi: DiT+VAE 7,6 GB in `tools/ai3d/models/hy3dgen` (download HF ~2 MB/s,
  ~1 h); TripoSR 1,6 GB in `models/hf`.
