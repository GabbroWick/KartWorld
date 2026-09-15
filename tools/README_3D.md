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

## Setup da zero su un altro PC

Tutto gratuito. Serve una GPU AMD RX 7000/9000 (ROCm su Windows: gfx110x /
gfx120x) con 16 GB, 32 GB di RAM, ~45 GB di disco per i pesi.

### Software da installare a mano

| Cosa | Versione usata | Come | Serve per |
| --- | --- | --- | --- |
| Driver AMD Adrenalin | 25.20 (apr 2026) o piu' recente | amd.com | ROCm su Windows |
| Python | 3.12.x | python.org o `winget install Python.Python.3.12` | venv |
| uv | 0.11 | `winget install astral-sh.uv` | venv + pacchetti (veloce) |
| Git | qualsiasi | git-scm.com | cloni |
| Blender | 5.1.2 in `C:\Program Files\Blender Foundation\Blender 5.1\` | blender.org | pulizia, bake, slime, FBX |
| Godot | 4.7.2 (console exe) | godotengine.org | il gioco, preview |
| VS Build Tools 2026 + workload "Desktop development with C++" | MSVC 14.50, SDK 10.0.26100 | visualstudio.microsoft.com/visual-cpp-build-tools | solo `mesh_inpaint_processor` (Paint) |
| GNU make | GnuWin32 | opzionale, per `make character` | comodita' |
| Account Mixamo (Adobe, gratuito) | — | mixamo.com | rig + animazioni (manuale) |

### Installazione automatica

```powershell
git clone https://github.com/GabbroWick/KartWorld.git ; cd KartWorld
powershell -ExecutionPolicy Bypass -File toolsi3d\setup_ai3d.ps1 -Gfx gfx1200   # gfx1201 per RX 9070, gfx1100 per RX 7900
```

Lo script: crea `tools/ai3d/.venv`, installa torch 2.12+rocm7.14.1 dall'indice
AMD, i pacchetti di `tools/ai3d/requirements.txt` (versioni bloccate), clona
i tre repository ai commit verificati (TripoSR `107cefd`, fork Hunyuan
`6f4b63b`, Hunyuan3D-2.1 `82920d6`), scarica i pesi, compila l'estensione
C++. Flag: `-SkipWeights`, `-SkipPaint`, `-SkipConcept`. Rilanciabile.

Pesi scaricati (tutti in `tools/ai3d/`, gitignored):

| Pesi | Dove | Dimensione | Stadio |
| --- | --- | --- | --- |
| TripoSR | `models/hf` | 1,6 GB | smoke test |
| Hunyuan3D-2.1 DiT + VAE fp16 | `models/hy3dgen/tencent/Hunyuan3D-2.1` | 7,6 GB | shape |
| rembg u2net | `models/rembg` | 0,2 GB | shape (sfondo) |
| Hunyuan3D-2.1 paintpbr | `hunyuan3d/weights/Hunyuan3D-2.1` | 6,6 GB | Paint |
| DINOv2-giant | `models/hf` | 4,3 GB | Paint |
| RealESRGAN x4plus | `hunyuan3d/Hunyuan3D-2.1/hy3dpaint/ckpt` | 64 MB | Paint |
| SDXL Turbo fp16 | `models/hf` | 6,6 GB | concept |
| IP-Adapter SDXL ViT-H + encoder | `models/hf` | 3,1 GB | concept (stile) |
| ControlNet OpenPose SDXL (xinsir) | `models/hf` | 2,4 GB | concept (T-pose) |

Da Hugging Face a ~2 MB/s: circa 4 ore in tutto. Nessun token richiesto.

### Modifiche di sistema (una sola, manuale, con approvazione)

`HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDelay = 60`
(DWORD) + riavvio: il Paint lancia kernel GPU sopra i 2 s del watchdog
Windows. Senza, il driver si resetta a meta' texturing. Ripristino:
`Remove-ItemProperty` sulla stessa chiave. Shape e concept non lo richiedono.

### Verifica

```bash
make gpu-check                      # "GPU OK"
make concept NAME=test PROMPT="cute cartoon cat mascot, gray fur, big eyes"
make character NAME=test            # ~15 min: shape 5 + paint 7 + blender
```

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
# solo per Paint/PBR:
uv pip install --python tools/ai3d/.venv realesrgan basicsr fast_simplification pybind11 ninja setuptools     pytorch-lightning torchmetrics torchdiffeq sentencepiece loguru configargparse python-dotenv
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

### 2b. Texture (Paint/PBR), separata dalla shape

```bash
tools/ai3d/.venv/Scripts/python tools/ai3d/generate_texture.py --name leopard --preset safe
```

Legge `_generated/leopard/model_raw.glb` + `input_rgba.png`, scrive in
`_generated/leopard/paint/` (obj/glb con texture, mappe PBR, report.json).
**Usa l'OBJ (`model_raw_textured.obj`) come input di Blender, non il GLB**:
l'export GLB del fork inverte l'asse V una volta di troppo e la texture,
sull'atlante xatlas, sembra rumore colorato (chiazza della pancia sul muso).
Misurato sul leopardo: 338 s, VRAM picco 16,9 GB (oltre i 16 fisici: usa
memoria condivisa, ma passa), RAM 12,4 GB. Il retro del modello viene
inventato (una sola vista di riferimento): artefatti possibili dietro.
Preset: `safe` (6 viste, 256 px: sicuro in 16 GB senza flash attention),
`low` (6 viste, 512 px: matrice di attenzione ~67 GB, NON passa il
preflight su ROCm), `normal` solo con flash attention. Pesi: UNet+VAE+
encoder 6,6 GB in `tools/ai3d/hunyuan3d/weights/Hunyuan3D-2.1/
hunyuan3d-paintpbr-v2-1`, DINOv2-giant 4,3 GB in `models/hf`,
RealESRGAN 64 MB in `hunyuan3d/Hunyuan3D-2.1/hy3dpaint/ckpt/`.
Il rasterizer è quello puro-PyTorch del fork (`HY3D_RASTER=torch`);
`mesh_inpaint_processor` (C++/pybind11) va compilato una volta con MSVC
Build Tools (installati, toolset 14.50 + Windows SDK 10.0.26100).
`scripts/build_extensions.py` del fork fallisce su questa macchina
(`io.h` non trovato: non entra in vcvars, e vcvars si rompe per il
`GnuWin32\bin` con parentesi nel PATH). Ricetta che funziona (PowerShell,
dalla radice del progetto):

```powershell
$d = "$PWD\tools\ai3d\hunyuan3d\.build\mesh_inpaint_processor"   # creato da build_extensions.py
cmd /c "set `"PATH=C:\Windows\System32;C:\Windows`" && cd /d `"$d`" && call `"C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat`" && set DISTUTILS_USE_SDK=1 && `"$PWD\tools\ai3d\.venv\Scripts\python.exe`" setup.py build_ext --inplace"
Copy-Item "$d\*.pyd" tools\ai3d\hunyuan3d\Hunyuan3D-2.1\hy3dpaint\DifferentiableRenderer\
```

Il rasterizer GPU nativo non si può compilare (le ruote rocm-sdk non
hanno header HIP né compilatore): si usa `torch_rasterizer.py`.

### 2c. Texture per trasferimento (bake da un modello già texturizzato)

Quando esiste già un modello con una buona texture (il leopardo Meshy),
la si "cuoce" sulla mesh AI, che ha UV proprie (xatlas del Paint):

```bash
tools/blender/blender.cmd -b --python tools/blender/bake_transfer.py --     --source assets/models/meshy/leopard/leopard.glb     --target assets/characters/_processed/leopard/leopard_textured.glb     --output assets/characters/_processed/leopard/leopard_baked.glb     --cage 0.15 --ray 0.8 --preview assets/characters/_processed/leopard/preview_baked.png
```

Cycles CPU, bake DIFFUSE solo colore, "Selected to Active". Entrambi i
modelli vengono normalizzati (piedi a 0, altezza uguale) per sovrapporli.
`--cage`/`--ray` alti evitano i buchi neri dove le due superfici distano
(pancia); i texel rimasti neri vengono riempiti per dilatazione. ~2 min.
Risultato molto migliore del Paint a 256 px: è la strada per il leopardo.
Per personaggi senza modello di partenza: Paint, Dream Textures o pittura a
mano in Blender (vedi Diario).

### 2d. Concept 2D in locale (SDXL Turbo + IP-Adapter)

Per i personaggi senza modello di partenza (volpe, panda):

```bash
tools/ai3d/.venv/Scripts/python tools/ai3d/generate_concept.py --name fox     --prompt "cute cartoon fox mascot, orange fur, white belly, white tail tip, big green eyes"     --variants 4 --seed 1
```

SDXL Turbo fp16 (6,6 GB) + IP-Adapter SDXL ViT-H (3,1 GB) in
`tools/ai3d/models/hf`. 6 passi, guidance 0, **640 px** (a 1024 Turbo
duplica teste e arti), `--ip-scale 0.25` (a 0.55 copia le macchie del
leopardo). Il prompt fisso aggiunge T-pose, vista frontale, sfondo grigio;
CLIP taglia a 77 token, tenere corta la descrizione. La **T-pose e'
imposta da ControlNet OpenPose** (`xinsir/controlnet-openpose-sdxl-1.0`,
2,4 GB) con lo scheletro chibi di `make_pose.py` (`tools/ai3d/poses/
tpose_chibi.png`, `--pose-scale 0.8`): senza, Turbo ignora la posa nel
prompt. ~20 s a immagine con ControlNet. ~2 s a immagine dopo il warm-up, VRAM
~8 GB. Scelte: volpe seed 34, panda seed 35 (fogli `_sheet_30-35.png`). Scrive
`assets/characters/_source/<nome>/<nome>_concept_<seed>.png`: scegli la
migliore e passala a `generate_shape.py`.

### 2e. Slime: modellato, non generato

`tools/blender/make_slime.py --output assets/characters/_final/slime/slime.glb`:
blob verde a base piatta, occhi, bocca, 2,2k tri, materiali flat. Scena
`scenes/enemies/visuals/slime_ai.tscn`; `Enemy` ora chiama `animate()` del
visual (bob/squash).

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
* Parti sciolte sotto il 2% dei vertici (schegge staccate dall'AI) vengono
  tolte; `--keep-loose` le conserva.
* `--preview`: PNG con 4 viste (fronte, lato, retro, 3/4). Guardalo sempre.
* Esporta GLB Y-up con il davanti a **+Z** (convenzione glTF: Blender -Y →
  glTF +Z). In Godot il personaggio guarda -Z, quindi la visual scene usa
  `flip_forward = true` (come per i modelli Meshy).

## 3b. Rig e animazioni (Mixamo, gratuito)

Le clip Mixamo già nel progetto (`assets/models/meshy/leopard/anim_*.fbx`)
usano lo scheletro standard `mixamorig_*`: riggando il nuovo modello su
Mixamo si riusano identiche. Alternative locali (UniRig) sono CUDA-only;
Rigify dà lo scheletro ma non le animazioni.

```bash
tools/blender/blender.cmd -b --python tools/blender/export_for_mixamo.py --     --input assets/characters/_final/leopard/leopard.glb     --outdir assets/characters/_processed/leopard/mixamo
```

**Mixamo vuole la T-pose.** Il modello a braccia basse viene rifiutato
dall'auto-rigger. Ricetta usata: render del rig Meshy in posa di riposo
(= T-pose) come concept → `generate_shape.py` → `import_ai3d.py --clip-back 0.62
--cut-tail-root 0.44 --tail 0.5 --tail-radius 0.045` (l'AI inventa una coda di 2 m larga e
verso terra: si taglia tutta, radice compresa, e si sostituisce con una coda
procedurale a tubo su curva, arricciata in su)
→ `bake_transfer.py --source assets/models/meshy/leopard/leopard_rig.fbx
--source-texture .../leopard_rig_0.png` (l'FBX Mixamo ha la texture sul
canale normal e base color nero: va forzata) → `export_for_mixamo.py`.
**Fatto per il leopardo (2026-09-14)**: `assets/models/ai/leopard/leopard_rig.fbx`
(With Skin + Breathing Idle, 33 ossa = No Fingers), scena
`scenes/characters/visuals/leopard_ai_rigged.tscn`: `model_scale = 1`
(Mixamo ha letto i metri correttamente, diversamente dal Meshy),
`albedo_override = leopard_albedo.png`, clip riusate da `meshy/leopard/`.
`RiggedCharacterVisual` riscala la traccia posizione dei fianchi delle clip
all'altezza rest del rig: le clip Meshy sono in cm (fianchi a 0,005), il rig
AI in metri (0,37); senza riscalamento il bacino andrebbe a terra.
Tracce per ossa assenti (dita) vengono ignorate.

Poi a mano su mixamo.com: Upload character → `leopard_for_mixamo.fbx`
(quello con texture fa fallire l'auto-rigger) → marker (mento, polsi,
gomiti, ginocchia, inguine) → skeleton Standard → download **With Skin**,
FBX Binary, 30 fps, con la clip "Breathing Idle" → salva come
`assets/models/ai/<nome>/<nome>_rig.fbx`. Le clip "without skin" già
presenti si copiano/riusano; `RiggedCharacterVisual` con `model_scale = 100`
(Mixamo legge i metri come centimetri) e `auto_ground = false`.
Il mesh risultante ha la texture? No: Mixamo restituisce il rig senza
materiali; la visual scene riapplica l'albedo cotto
(`_processed/<nome>/<nome>_baked_albedo.png`) sul mesh riggato.

## 4. Dove finiscono i file

Vedi "Struttura". Il GLB finale si copia a mano (o con lo script di
automazione, quando ci sarà) in `assets/characters/_final/<nome>/<nome>.glb`:
solo quella cartella è importata da Godot.

## 5. Importare in Godot

`assets/characters/_final/<nome>/<nome>.glb` viene importato al primo avvio
dell'editor (`make import` o `godot --headless --editor --quit`). Poi:
`scenes/characters/visuals/<nome>_ai.tscn` con `MeshyCharacterVisual`
(`model`, `flip_forward = true`, `auto_ground = true`, `flatten_materials =
true` per il look flat; esempio: `leopard_ai.tscn`) e `resources/characters/<nome>.tres` → `visual_scene`. Scena di
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
| "Timeout AMD" / reset del driver durante il Paint | Windows TDR. Il 2026-09-11 il Paint ha superato i 2 s di default: impostato `TdrDelay = 60` (DWORD) in `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers`, con riavvio. Ripristino: `Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name TdrDelay` (admin, riavvio). La shape da sola non lo richiedeva |
| rembg sceglie `bria-rmbg` | licenza non commerciale: gli script forzano `u2net` |
| Buco passante nella mesh dove il personaggio è chiaro (pancia) | rembg toglie le zone chiare interne; `generate_shape.py` chiude i buchi della maschera alpha (`binary_fill_holes`). Controlla `input_rgba.png` |
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

## 8. Nuovo personaggio (un comando)

```bash
make concept NAME=fox PROMPT="cute cartoon fox mascot, orange fur, cream belly, big green eyes, arms spread wide open"
#   -> guarda assets/characters/_source/fox/fox_concept_*.png, copia la migliore in fox_front.png
make character NAME=fox ARGS="--height 1.25"
#   -> shape (5 min) -> Paint (6 min) -> Blender -> _final/fox/fox.glb + assets/models/ai/fox/fox_for_mixamo.fbx
#   opzioni: --no-paint, --bake-from X --bake-texture Y (texture da un modello esistente),
#            --clip-back/--cut-tail-root/--tail (coda), --from paint|blender (riparte a meta')
```

Poi a mano: Mixamo (§3b) → `assets/models/ai/<nome>/<nome>_rig.fbx`, scena
`scenes/characters/visuals/<nome>_ai_rigged.tscn` (copia di
`leopard_ai_rigged.tscn` con i propri path) e `resources/characters/<nome>.tres`.
Per un NPC bastano idle + walk; le clip Mixamo del leopardo valgono per tutti.
Con la texture del Paint (non cotta) non serve `albedo_override`: la
texture e' nel GLB, ma il rig Mixamo la perde → cuocila in
`assets/models/ai/<nome>/<nome>_albedo.png` (e' il JPG di
`_generated/<nome>/paint/model_raw_textured.jpg`, che segue le stesse UV).

## 9. Veicolo (kart) con ruote che girano

```bash
make concept NAME=kart PROMPT="cute cartoon go-kart, blue body, yellow seat, big black wheels, side view" ARGS="--object"
make character NAME=kart ARGS="--height 1.0 --faces 8000"     # niente coda/rig: e' un oggetto
blender -b --python tools/blender/split_wheels.py --     --input assets/characters/_processed/kart/kart_clean.glb     --output assets/characters/_final/kart/kart.glb            # [--wheel-radius 0.22]
```

`split_wheels.py` cerca, per ogni quadrante (sinistra/destra × davanti/
dietro), il baricentro dei vertici bassi ed esterni e separa quelli entro un
cilindro orizzontale attorno al mozzo in `Wheel_FL/FR/RL/RR` (origine al
mozzo); il resto e' `Body`. Il GLB finale ha 5 nodi. In Godot
`scenes/vehicles/visuals/kart_ai.tscn` usa `AiVehicleVisual` (trova i
nodi `wheel*`, nasconde i pezzi di mesh delle ruote e ci costruisce sopra
pneumatici procedurali puliti che rotolano e sterzano) con `model_scale
1.6`, `wheel_radius 0.22`, `flip_forward` (il modello guarda +Z come le
Kenney). Il pilota usa `SeatedPose` (posa di guida procedurale) oppure la
clip Mixamo "Driving" se `drive_clip` e' impostata sulla scena del visual. Il pilota
siede su `VehicleDefinition.seat_offset` (0, 0.5, 0.35). Fatto il
2026-09-15 (concept seed 62).

## Diario

* **2026-09-14 (notte)** — Volpe e panda rigenerati in vera T-pose con
  ControlNet OpenPose: muso e schiena puliti, il Paint su concept puliti
  e' buono. Rig Mixamo caricati dall'umano (41 ossa, metri):
  `fox_ai_rigged.tscn`, `panda_ai_rigged.tscn` in gioco come NPC.
  Bug trovato: l'AnimationLibrary dell'FBX e' condivisa fra istanze, il
  secondo NPC non trovava piu' la clip idle → ogni visual duplica la
  libreria. **Procedura validata**: concept ControlNet → `make character`
  → Mixamo → scena riggata. `setup_ai3d.ps1` + `requirements.txt` per
  rifare tutto su un altro PC.
* **2026-09-14 (sera)** — Concept locali (SDXL Turbo + IP-Adapter):
  volpe e panda generati, shape + **Paint** (sui concept puliti la texture
  Paint e' buona: il problema del leopardo era il concept a macchie fini),
  Blender, in gioco come NPC (`fox_ai.tscn`, `panda_ai.tscn`, 1.25 / 1.5 m).
  Slime modellato da primitive (`make_slime.py`). `generate_character.py`
  + `make character`. FBX per Mixamo pronti in `assets/models/ai/{fox,panda}`.
* **2026-09-14** — Rig Mixamo del leopardo AI in T-pose collegato al
  personaggio (`leopard_ai_rigged.tscn`): idle/walk/run/jump/attack/hurt/
  emote con le clip Meshy, texture cotta via `albedo_override`. Suite
  movimento/combat/kart/portale verdi. Pipeline shape → texture → rig
  completa per un personaggio; manca l'automazione `generate_character`.
* **2026-09-11** — Fase 1 analisi, Fase 2 struttura, Fase 3 venv + torch
  ROCm (GPU vista, matmul ok), TripoSR smoke test riuscito (inferenza 24 s,
  VRAM 3 GB, 101k tri) → Blender `import_ai3d.py` verificato con anteprima
  (`--up=+X --forward=-Y`). Hunyuan3D 2.1 shape sul leopardo: 30 step,
  octree 256 → 300 s, VRAM picco 12,3 GB, RAM 20,7 GB, 260k tri; Blender
  → 12k tri → `_final/leopard/leopard.glb` → Godot preview ok (1,35 m,
  piedi a 0, fronte -Z). Buco passante sulla pancia: era rembg che
  toglieva la zona chiara → fix `binary_fill_holes` sull'alpha, rigenerato
  (285 s), pancia chiusa. Scheggia staccata della coda → rimozione parti
  sciolte nello script Blender. `_final/leopard/leopard.glb` = 12k tri,
  senza texture.
  Paint/PBR: pesi scaricati (6,6 + 4,3 GB), `mesh_inpaint_processor`
  compilato con MSVC, primo tentativo → reset driver (TDR 2 s); con
  `TdrDelay = 60` texturing riuscito (338 s). GLB del fork con V invertita:
  si usa l'OBJ. `_final/leopard/leopard.glb` ora è **texturizzato** (12k
  tri, albedo 2048², occhi e pancia corretti; retro con artefatti).
  Texture finale: **bake della texture Meshy sulla mesh AI**
  (`bake_transfer.py`), nettamente meglio del Paint 256 px; il Paint resta
  utile per personaggi senza modello di riferimento. Backup delle versioni
  precedenti in `_processed/leopard/leopard_hunyuan_paint_backup.glb` e
  `leopard_untextured_backup.glb`. Paint a 512 px: con flash attention
  sperimentale → `hipErrorInvalidValue` in DINOv2; con solo chunking
  (`HY3D_ATTN_LIMIT_GIB=100`, preset `low`) non finisce in 60 min: abbandonato.
  Non ancora fatto: rig, automazione `generate_character`, backup
  `_processed/leopard/leopard_untextured_backup.glb` della versione senza texture.
  Pesi: DiT+VAE 7,6 GB in `tools/ai3d/models/hy3dgen` (download HF ~2 MB/s,
  ~1 h); TripoSR 1,6 GB in `models/hf`.
