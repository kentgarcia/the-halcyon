"""core.py -- paths, catalog, recipe registry and the shared finalisation/IO path of the generator."""
import json
import os
import subprocess
import sys

import numpy as np

import dsp
from dsp import SR, N

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
AUDIO = os.path.join(ROOT, "audio")
CATALOG_PATH = os.path.join(ROOT, "data", "sound_catalog.json")
PA_PATH = os.path.join(ROOT, "data", "pa_lines.json")
MANIFEST_PATH = os.path.join(AUDIO, "manifest.json")
REPORT_PATH = os.path.join(AUDIO, "REPORT.md")
NOTES_PATH = os.path.join(HERE, "report_notes.md")
DIRS = {k: os.path.join(AUDIO, k) for k in ("amb", "music", "sfx", "voice")}

MUZAK = "muzak_elevator"


# --------------------------------------------------------------------------- catalog
def load_catalog():
    with open(CATALOG_PATH, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    out = []
    for e in data["sounds"]:
        e = dict(e)
        e.setdefault("variants", 1)
        e.setdefault("loop", False)
        out.append(e)
    return out


def load_pa_lines():
    with open(PA_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)["lines"]


def have_vorbis():
    try:
        r = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True)
        return "libvorbis" in r.stdout
    except OSError:
        return False


_VORBIS = None


def vorbis_ok():
    global _VORBIS
    if _VORBIS is None:
        _VORBIS = have_vorbis()
    return _VORBIS


def audio_ext(name):
    """file extension used for a catalog sound"""
    return "ogg" if (name == MUZAK and vorbis_ok()) else "wav"


def voice_ext():
    return "ogg" if vorbis_ok() else "wav"


def out_dir_for(entry):
    if entry["name"] == MUZAK or entry["group"] == "music":
        return "music"
    if entry["group"] in ("ambience", "dread") and entry["loop"]:
        return "amb"
    return "sfx"


def file_names(entry):
    """basenames (with extension) a catalog entry produces"""
    ext = audio_ext(entry["name"])
    if entry["variants"] > 1:
        return [f"{entry['name']}_{i}.{ext}" for i in range(1, entry["variants"] + 1)]
    return [f"{entry['name']}.{ext}"]


def res_path(entry, basename):
    return f"res://audio/{out_dir_for(entry)}/{basename}"


def disk_path(entry, basename):
    return os.path.join(DIRS[out_dir_for(entry)], basename)


def target_peak_db(entry):
    if entry["name"] == MUZAK:
        return -4.0
    if entry["group"] in ("ambience", "dread") and entry["loop"]:
        return -6.0
    if entry["loop"] and entry["db"] <= -18:   # quiet bed-type loops (elevator hum, camcorder playback/rewind)
        return -6.0
    return -3.0


# --------------------------------------------------------------------------- recipe registry
REGISTRY = {}


class Ctx:
    """what a recipe gets: the catalog entry, which variant, a seeded rng and the target length."""

    def __init__(self, entry, variant):
        self.entry = entry
        self.name = entry["name"]
        self.variant = variant           # 1..variants (1 for non-variant sounds)
        self.variants = entry["variants"]
        self.dur = float(entry["dur"])
        self.loop = bool(entry["loop"])
        self.n = N(self.dur)
        self.rng = dsp.rng_for("sfx", self.name, variant)
        self.fade_out_ms = None          # recipes may set 4.0 to keep an abrupt cut
        self.fade_in_ms = 3.0

    def sub_rng(self, tag):
        return dsp.rng_for("sfx", self.name, self.variant, tag)


def sfx(*names):
    def deco(fn):
        for nm in names:
            REGISTRY[nm] = fn
        return fn
    return deco


def placeholder(c):
    """Generic stand-in used only when no dedicated recipe is registered for a catalog name."""
    rng = c.rng
    n = c.n
    if c.loop:
        return dsp.spectral_noise(n, rng, dsp.make_mag(lo=60, hi=900, order=2))
    x = dsp.white(n, rng)
    x = dsp.bp(x, 150, 4000)
    return x * dsp.e_exp(n, max(c.dur / 4.0, 0.02))


# --------------------------------------------------------------------------- finalise + write
def tail_energy_db(x, ms=40):
    k = max(1, int(ms * SR / 1000.0))
    return dsp.lin2db(np.max(np.abs(x[-k:]))) - dsp.lin2db(np.max(np.abs(x)))


def finalize(y, entry, fade_out_ms=None, fade_in_ms=3.0):
    """DC removal, edge fades (one-shots only), peak normalisation.
    fade_out_ms=None -> automatic: 4 ms when the tail is already silent, longer when it is still audible
    (so a truncated reverb tail never ends in a hard cut). Recipes that must end abruptly pass 4."""
    y = np.asarray(y, dtype=np.float64)
    y = np.nan_to_num(y)
    n = N(entry["dur"])
    y = dsp.fit(y, n)
    y = dsp.remove_dc(y)
    if not entry["loop"]:
        if fade_out_ms is None:
            te = tail_energy_db(y)
            fade_out_ms = 4.0 if te < -50 else 25.0 if te < -35 else 60.0 if te < -20 else 100.0
        y = dsp.fade_edges(y, in_ms=fade_in_ms, out_ms=fade_out_ms)
    return dsp.normalize(y, target_peak_db(entry))


def write_ogg(path, x, quality=4, sr=SR):
    """encode through ffmpeg/libvorbis (mono). bitexact flags keep the output reproducible."""
    pcm = dsp.to_int16(x).tobytes()
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(sr), "-ac", "1", "-i", "-",
           "-c:a", "libvorbis", "-q:a", str(quality), "-ar", str(sr), "-ac", "1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact", "-map_metadata", "-1", path]
    subprocess.run(cmd, input=pcm, check=True)


_DECODE_CACHE = {}


def decode_audio(path, probe=True):
    """-> (float64 mono array, sample_rate, channels). probe=False skips ffprobe for ogg (assumes SR/mono as
    written by this tool). Results are memoised per (path, mtime, size) within one process."""
    st = os.stat(path)
    key = (path, st.st_mtime_ns, st.st_size, probe)
    if key in _DECODE_CACHE:
        return _DECODE_CACHE[key]
    if path.lower().endswith(".wav"):
        x, sr, ch, _ = dsp.read_wav(path)
        out = (x, sr, ch)
    else:
        sr, ch = SR, 1
        if probe:
            info = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                                   "stream=sample_rate,channels", "-of", "csv=p=0", path],
                                  capture_output=True, text=True).stdout.strip().split(",")
            sr, ch = int(info[0]), int(info[1])
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-"],
                             capture_output=True, check=True).stdout
        x = np.frombuffer(raw, dtype="<f4").astype(np.float64)
        if ch > 1:
            x = x.reshape(-1, ch).mean(axis=1)
        out = (x, sr, ch)
    _DECODE_CACHE[key] = out
    return out


AUDIO_EXTS = (".wav", ".ogg")


def generate_entry(entry, verbose=True):
    """run the recipe for every variant of a catalog entry and write the files"""
    name = entry["name"]
    fn = REGISTRY.get(name)
    paths = []
    for v in range(1, entry["variants"] + 1):
        c = Ctx(entry, v)
        y = (fn or placeholder)(c)
        x = finalize(y, entry, c.fade_out_ms, c.fade_in_ms)
        base = file_names(entry)[v - 1]
        path = disk_path(entry, base)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if base.endswith(".ogg"):
            write_ogg(path, x, quality=5)
        else:
            dsp.write_wav(path, x, loop=entry["loop"])
        paths.append(path)
        if verbose:
            tag = "" if fn else "  [PLACEHOLDER]"
            print(f"  wrote {os.path.relpath(path, ROOT)}  {len(x) / SR:.2f}s  pk {dsp.peak_db(x):.1f}{tag}")
    return paths
