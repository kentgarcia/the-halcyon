"""Dev tool: render waveform + spectrogram sheets for audio files so they can be inspected visually.

Usage:  python3 -I tools/audio/spectro.py OUT.png file1 [file2 ...] [--fmax 8000] [--w 900]
Files may be .wav or .ogg (ogg is decoded through ffmpeg).  Output goes wherever you point it
(never into the repo by default).  This is a development aid only; the generator does not use it.
"""
import os
import subprocess
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw


def load_any(path):
    if path.lower().endswith(".wav"):
        with wave.open(path, "rb") as w:
            sr = w.getframerate()
            n = w.getnframes()
            ch = w.getnchannels()
            raw = w.readframes(n)
        x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
        if ch > 1:
            x = x.reshape(-1, ch).mean(axis=1)
        return x, sr
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    info = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=sample_rate", "-of", "csv=p=0", path],
                          capture_output=True, text=True).stdout.strip()
    return x, int(info)


def spectrogram(x, sr, nfft=1024, hop=256, fmax=None):
    if len(x) < nfft:
        x = np.pad(x, (0, nfft - len(x)))
    win = np.hanning(nfft)
    frames = 1 + (len(x) - nfft) // hop
    idx = np.arange(nfft)[None, :] + hop * np.arange(frames)[:, None]
    S = np.abs(np.fft.rfft(x[idx] * win, axis=1)) ** 2
    S = 10 * np.log10(S + 1e-12)
    f = np.fft.rfftfreq(nfft, 1 / sr)
    if fmax:
        keep = f <= fmax
        S = S[:, keep]
        f = f[keep]
    return S.T, f


_CM = np.array([[0, 0, 0], [20, 10, 60], [90, 20, 110], [180, 40, 90], [240, 120, 30], [255, 220, 90], [255, 255, 230]], float)


def colorize(S, floor_db=-90.0, top_db=None):
    top = S.max() if top_db is None else top_db
    z = np.clip((S - (top + floor_db * -1 * -1)) / (-floor_db), 0, 1) if False else np.clip((S - (top + floor_db)) / (-floor_db), 0, 1)
    pos = z * (len(_CM) - 1)
    i0 = np.clip(pos.astype(int), 0, len(_CM) - 2)
    fr = (pos - i0)[..., None]
    rgb = _CM[i0] * (1 - fr) + _CM[i0 + 1] * fr
    return rgb.astype(np.uint8)


def render(paths, out, fmax=8000, width=900, wave_h=60, spec_h=180):
    rows = []
    for p in paths:
        x, sr = load_any(p)
        dur = len(x) / sr
        S, f = spectrogram(x, sr, fmax=fmax)
        img = colorize(S, floor_db=-80)[::-1]
        spec = Image.fromarray(img).resize((width, spec_h), Image.BILINEAR)
        # waveform
        wv = Image.new("RGB", (width, wave_h), (12, 12, 16))
        d = ImageDraw.Draw(wv)
        n = len(x)
        cols = np.linspace(0, n, width + 1).astype(int)
        for i in range(width):
            seg = x[cols[i]:max(cols[i] + 1, cols[i + 1])]
            if len(seg):
                a, b = seg.min(), seg.max()
                d.line([(i, wave_h / 2 - b * wave_h / 2), (i, wave_h / 2 - a * wave_h / 2)], fill=(120, 200, 255))
        peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
        rms = 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)
        lab = Image.new("RGB", (width, 14), (30, 30, 30))
        ImageDraw.Draw(lab).text((4, 1), f"{os.path.basename(p)}  {dur:.2f}s  pk {peak:.1f}  rms {rms:.1f}  sr {sr}  (0-{fmax}Hz)", fill=(255, 255, 255))
        sheet = Image.new("RGB", (width, 14 + wave_h + spec_h))
        sheet.paste(lab, (0, 0))
        sheet.paste(wv, (0, 14))
        sheet.paste(spec, (0, 14 + wave_h))
        rows.append(sheet)
    H = sum(r.height for r in rows) + 2 * (len(rows) - 1)
    canvas = Image.new("RGB", (width, H), (0, 0, 0))
    y = 0
    for r in rows:
        canvas.paste(r, (0, y))
        y += r.height + 2
    canvas.save(out)
    return out


if __name__ == "__main__":
    args = sys.argv[1:]
    fmax, width = 8000, 900
    files = []
    out = args[0]
    i = 1
    while i < len(args):
        if args[i] == "--fmax":
            fmax = float(args[i + 1]); i += 2
        elif args[i] == "--w":
            width = int(args[i + 1]); i += 2
        else:
            files.append(args[i]); i += 1
    print(render(files, out, fmax=fmax, width=width))
