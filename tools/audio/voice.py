"""voice.py -- Management's PA voice: flite (slt, CMU Arctic clustergen) -> PA processing chain -> OGG.

Pipeline per line
  text -> flite sentence by sentence (slow, slightly lowered, deadpan) -> trim/concat with fixed pauses
  -> PA chain: band-limit (~280-3600 Hz, horn presence), light bit-reduction, compression, mild
     saturation, small-room reverb + corridor slap, faint hiss
  -> loudness-match every line (active-speech RMS) and limit to -3 dBFS peak
  -> 'false' take = byte-identical processed audio + mic_pop layered under the first word (-26 dB re peak).
No clicks are baked in: the game plays pa_click_on / pa_click_off around the line.
Both takes are encoded from arrays of identical length, so duration cannot leak the lie.
"""
import os
import re
import subprocess
import tempfile

import numpy as np

import core
import dsp
import lib
from dsp import SR, N

TTS_VOICE = "slt"          # flite voice: CMU ARCTIC "slt" (clustergen), BSD-style licence
TTS_STRETCH = 1.14         # slower than default: calm, institutional
TTS_F0_MEAN = 158.0        # lowered from ~171 Hz: warmer
TTS_F0_STD = 10.0          # deadpan
SENTENCE_PAUSE = 0.38      # s between sentences
LEAD_IN = 0.14             # s of room tone before the first word
TAIL = 0.55                # s after the last word (reverb ring-out)
TARGET_ACTIVE_RMS_DB = -15.0
PEAK_CEIL_DB = -3.0
POP_REL_DB = -26.0
POP_PRE_ROLL = 0.010       # the pop leads the vowel by ~10 ms

_TTS_FIX = {"apologise": "apologize"}


def _tts_text(s):
    for a, b in _TTS_FIX.items():
        s = re.sub(a, b, s, flags=re.I)
    return s


def split_sentences(text):
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p for p in parts if p]


def flite_say(text, workdir):
    path = os.path.join(workdir, "say.wav")
    cmd = ["flite", "-voice", TTS_VOICE,
           "--setf", f"duration_stretch={TTS_STRETCH}",
           "--setf", f"int_f0_target_mean={TTS_F0_MEAN}",
           "--setf", f"int_f0_target_stddev={TTS_F0_STD}",
           "-t", _tts_text(text), "-o", path]
    subprocess.run(cmd, check=True, capture_output=True)
    x, sr, _, _ = dsp.read_wav(path)
    x = dsp.resample_fft(x, sr, SR)
    return dsp.trim_silence(x, -40.0, 8.0, keep_ms=15.0)


def raw_speech(text, workdir):
    """dry TTS for a whole line with controlled lead-in / pauses / tail; returns (audio, onset_sample)"""
    sents = [flite_say(s, workdir) for s in split_sentences(text)]
    pause = np.zeros(N(SENTENCE_PAUSE))
    pieces = [np.zeros(N(LEAD_IN))]
    for i, s in enumerate(sents):
        pieces.append(s)
        if i < len(sents) - 1:
            pieces.append(pause)
    pieces.append(np.zeros(N(TAIL)))
    return np.concatenate(pieces), N(LEAD_IN)


def active_rms_db(x, win_ms=30.0, gate_db=-26.0):
    w = int(win_ms * SR / 1000.0)
    nb = len(x) // w
    fr = x[:nb * w].reshape(nb, w)
    r = np.sqrt(np.mean(fr * fr, axis=1))
    thr = np.max(r) * dsp.db2lin(gate_db)
    act = r[r > thr]
    return float(dsp.lin2db(np.sqrt(np.mean(act * act)))) if len(act) else -100.0


def first_onset(x, thresh_rel_db=-24.0, win_ms=4.0):
    w = max(1, int(win_ms * SR / 1000.0))
    nb = len(x) // w
    r = np.sqrt(np.mean(x[:nb * w].reshape(nb, w) ** 2, axis=1))
    thr = np.max(r) * dsp.db2lin(thresh_rel_db)
    idx = np.nonzero(r > thr)[0]
    return int(idx[0] * w) if len(idx) else 0


def pa_chain(x, rng):
    """the PA colouration. x is dry speech at SR; returns processed audio (not yet loudness-matched)."""
    x = dsp.normalize(x, -6.0)
    # horn-speaker band-limit with a presence bump and a touch of low-mid warmth
    x = dsp.filt(x, lo=270.0, hi=3400.0, order=4, peaks=[(1900.0, 3.5, 0.9), (420.0, 1.5, 0.8)])
    # light bit reduction (10-bit) -- slight grit, also masks synthesis artefacts
    x = dsp.bitcrush(x, bits=10)
    # mild compression, then gentle amplifier saturation
    x = dsp.compress(x, thresh_db=-22.0, ratio=3.5, attack_ms=4.0, release_ms=150.0, makeup_db=5.0)
    x = dsp.soft_clip(x * 0.9, 1.35) * 0.9
    # small-room reverb + corridor slap echo
    dry = x
    wet = dsp.reverb(x, "pa_room", wet=0.20, dry=1.0, tail=0.0)
    wet = wet[:len(x)]
    slap = np.zeros_like(x)
    k = int(0.118 * SR)
    slap[k:] = dsp.lp(x, 2200.0, order=2)[:len(x) - k] * 0.13
    x = wet + slap
    # faint hiss (band-limited, constant through the line so it does not pump)
    hs = dsp.filt(dsp.colored(len(x), rng, 0.6), lo=900.0, hi=6500.0, order=2)
    hs = hs / (np.std(hs) + 1e-9)
    x = x + hs * dsp.db2lin(-55.0)
    return x


def finish_levels(x):
    """equal perceived loudness for all lines, peak-limited to -3 dBFS"""
    g = TARGET_ACTIVE_RMS_DB - active_rms_db(x)
    x = x * dsp.db2lin(g)
    x = dsp.limit(x, ceil=float(dsp.db2lin(PEAK_CEIL_DB)), win_ms=2.0)
    return x


def render_line(text, line_id, workdir):
    """-> (true_take, false_take or None-capable base). Returns processed float arrays."""
    rng = dsp.rng_for("voice", line_id)
    dry, onset0 = raw_speech(text, workdir)
    wetted = pa_chain(dry, rng)
    # the hiss fades in/out so file edges are clean
    true_take = finish_levels(wetted)
    true_take = dsp.remove_dc(true_take)
    true_take = dsp.fade_edges(true_take, in_ms=12.0, out_ms=40.0)
    onset = first_onset(dry)
    return true_take, onset


def add_pop(x, onset, line_id):
    pop = lib.mic_pop_unit(dsp.rng_for("voice-pop", line_id), 0.2)
    peak = float(np.max(np.abs(x)))
    gain = peak * float(dsp.db2lin(POP_REL_DB))
    y = x.copy()
    start = max(0, onset - int(POP_PRE_ROLL * SR))
    dsp.put(y, pop * gain, start / SR)
    return y


def save(x, path):
    if path.endswith(".ogg"):
        core.write_ogg(path, x, quality=4)
    else:
        dsp.write_wav(path, x)


def generate_voice(ids=None, verbose=True):
    lines = core.load_pa_lines()
    ext = core.voice_ext()
    os.makedirs(core.DIRS["voice"], exist_ok=True)
    with tempfile.TemporaryDirectory() as wd:
        for ln in lines:
            if ids is not None and ln["id"] not in ids:
                continue
            true_take, onset = render_line(ln["text"], ln["id"], wd)
            pt = os.path.join(core.DIRS["voice"], f"{ln['id']}_true.{ext}")
            save(true_take, pt)
            msg = f"  {ln['id']}_true.{ext}  {len(true_take) / SR:.2f}s"
            if "false" in ln.get("takes", []):
                false_take = add_pop(true_take, onset, ln["id"])
                pf = os.path.join(core.DIRS["voice"], f"{ln['id']}_false.{ext}")
                save(false_take, pf)
                msg += f" + false"
            if verbose:
                print(msg)
