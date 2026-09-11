"""Verifica che PyTorch veda la GPU AMD via ROCm e che i kernel funzionino.

Uso:  tools/ai3d/.venv/Scripts/python tools/ai3d/check_gpu.py
Esce con codice 1 se la GPU non e' disponibile o il calcolo e' sbagliato.
"""
import sys
import time

import torch

print("torch.__version__      :", torch.__version__)
print("torch.version.hip      :", torch.version.hip)
print("torch.version.cuda     :", torch.version.cuda)
print("torch.cuda.is_available:", torch.cuda.is_available())
if not torch.cuda.is_available():
    print("GPU non disponibile: ROCm non vede la scheda.")
    sys.exit(1)

props = torch.cuda.get_device_properties(0)
print("device name            :", torch.cuda.get_device_name(0))
print("gcnArchName            :", props.gcnArchName)
print("VRAM totale            : %.1f GB" % (props.total_memory / 2**30))
free, total = torch.cuda.mem_get_info(0)
print("VRAM libera            : %.1f GB / %.1f GB" % (free / 2**30, total / 2**30))

# Operazione tensoriale: matmul 4096x4096 su GPU, confronto con la CPU.
a = torch.randn(4096, 4096)
b = torch.randn(4096, 4096)
ref = (a @ b)
ga, gb = a.cuda(), b.cuda()
torch.cuda.synchronize()
t0 = time.perf_counter()
for _ in range(10):
    gc = ga @ gb
torch.cuda.synchronize()
dt = (time.perf_counter() - t0) / 10
err = (gc.cpu() - ref).abs().max().item()
tflops = 2 * 4096**3 / dt / 1e12
print("matmul 4096^2 fp32     : %.1f ms  (%.1f TFLOPS)  max err vs CPU %.4f" % (dt * 1000, tflops, err))

# fp16 e una conv, che sono cio' che i modelli 3D usano davvero.
h = (torch.randn(2048, 2048, device="cuda", dtype=torch.float16) @
     torch.randn(2048, 2048, device="cuda", dtype=torch.float16))
conv = torch.nn.Conv2d(3, 16, 3, padding=1).cuda()
out = conv(torch.randn(1, 3, 256, 256, device="cuda"))
torch.cuda.synchronize()
print("fp16 matmul / conv2d   : ok", tuple(h.shape), tuple(out.shape))
print("VRAM picco allocata    : %.2f GB" % (torch.cuda.max_memory_allocated() / 2**30))

if err > 0.05:
    print("ERRORE: risultato GPU diverso dalla CPU.")
    sys.exit(1)
print("GPU OK")
