# kart — Hunyuan3D 2.1 shape

Input: `C:\Users\gabri\Progetti\KartWorld\assets\characters\_source\kart\kart_front.png`

model_raw.glb: geometria grezza, nessuna texture.

```json
{
  "tool": "Hunyuan3D-2.1 shape (fork mac-rocm, rasterizer non usato)",
  "input": "C:\\Users\\gabri\\Progetti\\KartWorld\\assets\\characters\\_source\\kart\\kart_front.png",
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
  "t_preprocess_s": 3.4,
  "t_load_s": 41.6,
  "t_generate_s": 321.3,
  "vram_peak_gb": 12.32,
  "vram_reserved_gb": 12.5,
  "ram_peak_gb": 19.62,
  "vertices": 182917,
  "faces": 365898,
  "extents": [
    1.182,
    1.15,
    1.988
  ],
  "watertight": true,
  "glb_bytes": 6586564,
  "t_total_s": 366.7,
  "valid": true
}
```
