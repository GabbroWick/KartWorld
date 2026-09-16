"""Musica ed effetti sonori con modelli AI locali (ROCm, stesso venv).

Musica: MusicGen small (Meta, transformers) -> assets/audio/music/<nome>.wav
  python tools/ai3d/generate_audio.py music --name hub --seconds 30 --seed 3
Effetti: AudioLDM (cvssp/audioldm-s-full-v2, diffusers, non gated, ~1.3 GB) ->
assets/audio/sfx/<nome>.wav. `--backend stable` usa Stable Audio Open 1.0
(gated: licenza su huggingface.co/stabilityai/stable-audio-open-1.0 +
`huggingface-cli login`).
  python tools/ai3d/generate_audio.py sfx --name horn
  python tools/ai3d/generate_audio.py sfx --all

I prompt di musica e effetti stanno in MUSIC e SFX qui sotto: il gioco carica
`assets/audio/sfx/<nome>.wav` se esiste, altrimenti il suono sintetico.
Il tool prova sempre su GPU e cade su CPU se la GPU non basta.
"""
import argparse
import os
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
MUSIC_DIR = PROJECT / "assets" / "audio" / "music"
SFX_DIR = PROJECT / "assets" / "audio" / "sfx"
os.environ.setdefault("HF_HOME", str(ROOT / "models" / "hf"))

MUSIC = {
    "hub": "happy tropical island tune for a kids cartoon adventure game, ukulele, marimba, "
           "steel drums, light percussion, bright and playful, loopable, 120 bpm",
    "level": "upbeat adventure platformer music for kids, bouncy synth melody, brass stabs, "
             "driving drums, energetic and fun, loopable, 140 bpm",
    "jungle": "jungle adventure music for a kids game, bongos, flute, marimba, birds, "
              "cheerful and mysterious, loopable, 125 bpm",
    "volcano": "exciting volcano level music, tribal drums, low brass, urgent but fun, "
               "kids cartoon game, loopable, 130 bpm",
}

SFX = {
    "jump": "short cartoon boing jump sound, springy, bright",
    "double_jump": "quick double cartoon boing hop, higher pitch",
    "land": "soft thud landing on grass, short",
    "attack": "fast cartoon whoosh swing, short",
    "hit": "cartoon punch impact thump with a squish, short",
    "hurt": "cartoon ouch hit, short descending tone",
    "enemy_die": "cartoon slime splat pop, wet, short",
    "star": "sparkly magical pickup chime, ascending, short",
    "checkpoint": "cheerful checkpoint bell ding ding",
    "unlock": "triumphant short jingle unlock, sparkles",
    "fanfare": "short victory fanfare trumpet, cartoon, celebratory",
    "portal": "magical portal whoosh shimmer rising, short",
    "turbo": "rocket turbo boost whoosh with flames, short",
    "ui": "soft ui click blip, short",
    "horn": "cute go-kart horn beep beep, cartoon",
    "engine": "small go-kart engine idle loop, cartoon, steady hum",
}

# Longest useful length per effect (s); the model always renders ~2 s.
SFX_MAX = {"jump": 0.7, "double_jump": 0.5, "land": 0.5, "attack": 0.6, "hit": 0.6,
           "hurt": 0.8, "enemy_die": 0.9, "star": 1.0, "checkpoint": 1.2, "unlock": 1.5,
           "fanfare": 2.0, "portal": 1.5, "turbo": 1.5, "ui": 0.3, "horn": 1.4}


def _device():
    import torch
    return "cuda" if torch.cuda.is_available() else "cpu"


def _save_wav(path: Path, audio: np.ndarray, rate: int) -> None:
    from scipy.io import wavfile
    path.parent.mkdir(parents=True, exist_ok=True)
    audio = np.asarray(audio, dtype=np.float32)
    if audio.ndim == 2 and audio.shape[0] <= 2:   # (channels, samples) -> (samples, channels)
        audio = audio.T
    peak = float(np.max(np.abs(audio))) or 1.0
    audio = audio / peak * 0.9
    wavfile.write(str(path), rate, (audio * 32767).astype(np.int16))
    print("AUDIO", path, "%.1fs" % (audio.shape[0] / rate))


def music(args):
    import torch
    from transformers import AutoProcessor, MusicgenForConditionalGeneration
    model_id = "facebook/musicgen-%s" % args.size
    processor = AutoProcessor.from_pretrained(model_id)
    model = MusicgenForConditionalGeneration.from_pretrained(model_id)
    device = _device()
    model = model.to(device)
    names = [args.name] if args.name else list(MUSIC.keys())
    for name in names:
        prompt = MUSIC.get(name, args.prompt or name)
        inputs = processor(text=[prompt], padding=True, return_tensors="pt").to(device)
        torch.manual_seed(args.seed)
        tokens = int(args.seconds * 50)   # 50 tokens per second
        audio = model.generate(**inputs, do_sample=True, guidance_scale=3.0, max_new_tokens=tokens)
        rate = model.config.audio_encoder.sampling_rate
        _save_wav(MUSIC_DIR / f"{name}.wav", audio[0].cpu().numpy(), rate)


def sfx(args):
    import torch
    device = _device()
    names = list(SFX.keys()) if args.all else [args.name]
    if args.backend == "stable":
        from diffusers import StableAudioPipeline
        pipe = StableAudioPipeline.from_pretrained("stabilityai/stable-audio-open-1.0", torch_dtype=torch.float16).to(device)
        for name in names:
            prompt = SFX.get(name, args.prompt or name)
            seconds = 4.0 if name == "engine" else 1.6
            gen = torch.Generator(device).manual_seed(args.seed)
            audio = pipe(prompt, negative_prompt="low quality, noise, music, speech",
                         num_inference_steps=60, audio_end_in_s=seconds, num_waveforms_per_prompt=1,
                         generator=gen).audios[0]
            _save_wav(SFX_DIR / f"{name}.wav", audio.float().cpu().numpy(), pipe.vae.sampling_rate)
        return
    # AudioLDM (cvssp/audioldm-s-full-v2, not gated, ~1.3 GB): 16 kHz mono
    # clips. AudioLDM 2 in diffusers 0.35 breaks against transformers 4.57
    # (`GPT2Model has no attribute _get_initial_cache_position`); v1 has no
    # GPT2 stage and works.
    from diffusers import AudioLDMPipeline
    pipe = AudioLDMPipeline.from_pretrained("cvssp/audioldm-s-full-v2", torch_dtype=torch.float16).to(device)
    for name in names:
        prompt = SFX.get(name, args.prompt or name)
        seconds = 4.0 if name == "engine" else 2.0
        gen = torch.Generator(device).manual_seed(args.seed)
        audio = pipe(prompt, negative_prompt="low quality, music, speech, noise",
                     num_inference_steps=100, audio_length_in_s=seconds, num_waveforms_per_prompt=1,
                     guidance_scale=3.5, generator=gen).audios[0]
        audio = np.asarray(audio, dtype=np.float32)
        audio = _loopify(audio, 16000) if name == "engine" else _cap(_trim(audio), 16000, SFX_MAX.get(name, 2.0))
        _save_wav(SFX_DIR / f"{name}.wav", audio, 16000)


def _loopify(audio: np.ndarray, rate: int, fade: float = 0.4) -> np.ndarray:
    """Seamless loop: cross-fade the tail into the head and drop the tail."""
    n = int(fade * rate)
    if audio.shape[0] < 3 * n:
        return audio
    ramp = np.linspace(0.0, 1.0, n, dtype=np.float32)
    body = audio[:-n].copy()
    body[:n] = body[:n] * ramp + audio[-n:] * (1.0 - ramp)
    return body


def _cap(audio: np.ndarray, rate: int, seconds: float, fade: float = 0.06) -> np.ndarray:
    """Cut to `seconds` with a short fade-out (a click must not last 2 s)."""
    n = int(seconds * rate)
    if audio.shape[0] > n:
        audio = audio[:n].copy()
    f = min(int(fade * rate), audio.shape[0])
    if f > 0:
        audio[-f:] *= np.linspace(1.0, 0.0, f, dtype=np.float32)
    return audio


def trim(args):
    """Re-cap the existing sfx WAVs (no model needed)."""
    from scipy.io import wavfile
    for name, seconds in SFX_MAX.items():
        path = SFX_DIR / f"{name}.wav"
        if not path.exists():
            continue
        rate, data = wavfile.read(str(path))
        audio = data.astype(np.float32) / 32767.0
        _save_wav(path, _cap(audio, rate, seconds), rate)


def _trim(audio: np.ndarray, threshold: float = 0.02, tail: int = 1600) -> np.ndarray:
    """Cut leading/trailing silence so short effects fire without delay."""
    loud = np.where(np.abs(audio) > threshold * max(float(np.max(np.abs(audio))), 1e-6))[0]
    if loud.size == 0:
        return audio
    start = max(int(loud[0]) - 200, 0)
    end = min(int(loud[-1]) + tail, audio.shape[0])
    return audio[start:end]


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("music")
    m.add_argument("--name", default="")
    m.add_argument("--prompt", default="")
    m.add_argument("--seconds", type=float, default=30.0)
    m.add_argument("--seed", type=int, default=1)
    m.add_argument("--size", default="small", choices=["small", "medium"])
    s = sub.add_parser("sfx")
    s.add_argument("--name", default="")
    s.add_argument("--prompt", default="")
    s.add_argument("--all", action="store_true")
    s.add_argument("--seed", type=int, default=1)
    s.add_argument("--backend", default="audioldm", choices=["audioldm", "stable"])
    sub.add_parser("trim")
    args = ap.parse_args()
    if args.cmd == "music":
        music(args)
    elif args.cmd == "trim":
        trim(args)
    else:
        sfx(args)


if __name__ == "__main__":
    main()
