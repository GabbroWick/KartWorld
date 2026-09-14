# panda — Hunyuan3D 2.1 shape

Input: `C:\Users\gabri\Progetti\KartWorld\assets\characters\_source\panda\panda_front.png`

model_raw.glb: geometria grezza, nessuna texture.

```json
{
  "tool": "Hunyuan3D-2.1 shape (fork mac-rocm, rasterizer non usato)",
  "input": "C:\\Users\\gabri\\Progetti\\KartWorld\\assets\\characters\\_source\\panda\\panda_front.png",
  "params": {
    "steps": 40,
    "octree": 256,
    "guidance": 5.0,
    "seed": 1234
  },
  "errors": [],
  "backend": {
    "kind": "rocm",
    "device": "cuda",
    "dtype": "torch.float16",
    "gpu": "AMD Radeon RX 9060 XT"
  },
  "t_preprocess_s": 3.6,
  "t_load_s": 59.6,
  "t_generate_s": 1486.9,
  "vram_peak_gb": 12.32,
  "vram_reserved_gb": 12.5,
  "ram_peak_gb": 18.14,
  "vertices": 140354,
  "faces": 280704,
  "extents": [
    1.861,
    1.983,
    0.855
  ],
  "watertight": true,
  "glb_bytes": 5053484,
  "t_total_s": 1550.3,
  "valid": true
}
```
