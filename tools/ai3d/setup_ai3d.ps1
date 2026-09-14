<#
Installa da zero la pipeline 3D locale su un PC Windows con GPU AMD (ROCm).
Eseguire dalla radice del progetto, in PowerShell:

    powershell -ExecutionPolicy Bypass -File tools\ai3d\setup_ai3d.ps1 [-Gfx gfx1200] [-SkipWeights] [-SkipPaint] [-SkipConcept]

Prerequisiti (manuali, vedi tools/README_3D.md "Setup da zero"):
  - driver AMD Adrenalin recente (RX 7000/9000: ROCm Windows supporta gfx110x/gfx120x)
  - Python 3.12 (python.org o winget), uv (winget install astral-sh.uv), git
  - Blender 5.1 in C:\Program Files\Blender Foundation\Blender 5.1\
  - Visual Studio Build Tools 2026 con "Desktop development with C++" (solo per il Paint)
Scarica: torch ROCm ~1.3 GB, pacchetti ~2 GB, pesi fino a ~30 GB (vedi tabella nel README).
Idempotente: rilanciabile, salta cio' che esiste.
#>
param(
    [string]$Gfx = "gfx1200",       # RX 9060/9070: gfx1200/gfx1201; RX 7900: gfx1100; RX 7800/7700: gfx1101
    [switch]$SkipWeights,
    [switch]$SkipPaint,
    [switch]$SkipConcept
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
Set-Location $root
$venv = "tools\ai3d\.venv"
$py = "$venv\Scripts\python.exe"
$env:HF_HOME = "$root\tools\ai3d\models\hf"
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"

function Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }

Step "venv Python 3.12 ($venv)"
if (-not (Test-Path $py)) { uv venv $venv --python 3.12 }

Step "PyTorch ROCm per $Gfx (indice AMD ufficiale)"
uv pip install --python $venv --index-url https://repo.amd.com/rocm/whl-multi-arch/ `
    "torch[device-$Gfx]==2.12.0+rocm7.14.1" "torchvision[device-$Gfx]==0.27.0+rocm7.14.1"

Step "pacchetti Python (requirements.txt)"
uv pip install --python $venv -r tools\ai3d\requirements.txt

Step "verifica GPU"
& $py tools\ai3d\check_gpu.py
if ($LASTEXITCODE -ne 0) { throw "La GPU non e' visibile da PyTorch: controlla driver e -Gfx." }

Step "repository (commit verificati)"
$repos = @(
    @{ dir = "tools\ai3d\TripoSR";                 url = "https://github.com/VAST-AI-Research/TripoSR.git";                  rev = "107cefd" },
    @{ dir = "tools\ai3d\hunyuan3d";               url = "https://github.com/VladimirTalyzin/hunyuan3d-2.1-mac-rocm.git";    rev = "6f4b63b" },
    @{ dir = "tools\ai3d\hunyuan3d\Hunyuan3D-2.1"; url = "https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git";             rev = "82920d6" }
)
foreach ($r in $repos) {
    if (-not (Test-Path "$($r.dir)\.git")) { git clone $r.url $r.dir }
    git -C $r.dir fetch --depth 1 origin $r.rev 2>$null
    git -C $r.dir checkout -q $r.rev
}

if (-not $SkipWeights) {
    Step "pesi: TripoSR (1.6 GB), Hunyuan3D shape (7.6 GB), rembg u2net"
    & $py -c @"
import os
os.environ['HY3DGEN_MODELS'] = r'$root\tools\ai3d\models\hy3dgen'
os.environ['U2NET_HOME'] = r'$root\tools\ai3d\models\rembg'
from huggingface_hub import snapshot_download, hf_hub_download
snapshot_download('stabilityai/TripoSR')
snapshot_download('tencent/Hunyuan3D-2.1', allow_patterns=['hunyuan3d-dit-v2-1/*','hunyuan3d-vae-v2-1/*'],
                  local_dir=os.path.join(os.environ['HY3DGEN_MODELS'], 'tencent', 'Hunyuan3D-2.1'))
from rembg import new_session; new_session('u2net')
print('pesi shape ok')
"@
    if (-not $SkipPaint) {
        Step "pesi Paint: hunyuan3d-paintpbr (6.6 GB), DINOv2-giant (4.3 GB), RealESRGAN (64 MB)"
        & $py -c @"
from huggingface_hub import snapshot_download
snapshot_download('tencent/Hunyuan3D-2.1', allow_patterns=['hunyuan3d-paintpbr-v2-1/*'],
                  local_dir=r'$root\tools\ai3d\hunyuan3d\weights\Hunyuan3D-2.1')
snapshot_download('facebook/dinov2-giant', allow_patterns=['*.safetensors','*.json','*.txt'])
print('pesi paint ok')
"@
        $ckpt = "tools\ai3d\hunyuan3d\Hunyuan3D-2.1\hy3dpaint\ckpt"
        New-Item -ItemType Directory -Force $ckpt | Out-Null
        if (-not (Test-Path "$ckpt\RealESRGAN_x4plus.pth")) {
            Invoke-WebRequest -Uri "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth" -OutFile "$ckpt\RealESRGAN_x4plus.pth"
        }
    }
    if (-not $SkipConcept) {
        Step "pesi concept: SDXL Turbo fp16 (6.6 GB), IP-Adapter (3.1 GB), ControlNet OpenPose (2.4 GB)"
        & $py -c @"
from huggingface_hub import snapshot_download
snapshot_download('stabilityai/sdxl-turbo', allow_patterns=['*.json','*.txt','unet/*.fp16.safetensors','text_encoder/*.fp16.safetensors','text_encoder_2/*.fp16.safetensors','vae/*.fp16.safetensors','tokenizer*/*','scheduler/*'])
snapshot_download('h94/IP-Adapter', allow_patterns=['sdxl_models/ip-adapter_sdxl_vit-h.safetensors','models/image_encoder/model.safetensors','models/image_encoder/config.json'])
snapshot_download('xinsir/controlnet-openpose-sdxl-1.0', allow_patterns=['config.json','diffusion_pytorch_model.safetensors'])
print('pesi concept ok')
"@
    }
}

if (-not $SkipPaint) {
    Step "mesh_inpaint_processor (C++/pybind11, MSVC)"
    $dr = "tools\ai3d\hunyuan3d\Hunyuan3D-2.1\hy3dpaint\DifferentiableRenderer"
    if (-not (Get-ChildItem "$dr\mesh_inpaint_processor*.pyd" -ErrorAction SilentlyContinue)) {
        # Il build script del fork prepara la cartella .build (e fallisce a compilare): la usiamo.
        & $py tools\ai3d\hunyuan3d\scripts\build_extensions.py --skip-inpaint 2>$null | Out-Null
        & $py tools\ai3d\hunyuan3d\scripts\build_extensions.py 2>$null | Out-Null
        $d = "$root\tools\ai3d\hunyuan3d\.build\mesh_inpaint_processor"
        $vcvars = Get-ChildItem "C:\Program Files*\Microsoft Visual Studio\*\*\VC\Auxiliary\Build\vcvars64.bat" | Select-Object -First 1
        if (-not $vcvars) { throw "vcvars64.bat non trovato: installa VS Build Tools con il workload C++." }
        cmd /c "set `"PATH=C:\Windows\System32;C:\Windows`" && cd /d `"$d`" && call `"$($vcvars.FullName)`" && set DISTUTILS_USE_SDK=1 && `"$root\$py`" setup.py build_ext --inplace"
        Copy-Item "$d\*.pyd" $dr -Force
    }
    Write-Host "Ricorda: il Paint richiede TdrDelay=60 nel registro (vedi README, sezione 6) + riavvio." -ForegroundColor Yellow
}

Step "fatto"
Write-Host "Prova: make gpu-check ; make concept NAME=test PROMPT=`"cute cartoon cat mascot`" ; make character NAME=test"
