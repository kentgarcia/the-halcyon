"""checks.py -- semantic (design-intent) checks used by verify.py. Each check returns (ok, label, detail)."""
import os

import numpy as np

import core
import dsp
from dsp import SR


def load(man, name, variant=1):
    ent = man["sounds"].get(name)
    if not ent:
        return None
    res = ent["files"][min(variant, len(ent["files"])) - 1]
    path = os.path.join(core.ROOT, res[len("res://"):])
    x, sr, ch = core.decode_audio(path)
    return x


def onsets(x, win_ms=3.0, rel_db=-24.0, min_gap=0.06, smooth_ms=0.0):
    """energy-rise onset detector (seconds) with hysteresis: after an onset the envelope must fall below
    0.4x the threshold before another one can fire. smooth_ms > 0 smooths the envelope (low-frequency thumps)."""
    w = max(1, int(win_ms * SR / 1000.0))
    nb = len(x) // w
    env = np.sqrt(np.mean(x[:nb * w].reshape(nb, w) ** 2, axis=1))
    if smooth_ms > 0:
        k = max(1, int(smooth_ms / win_ms))
        env = np.sqrt(np.convolve(env ** 2, np.ones(k) / k, mode="same"))
    thr = np.max(env) * dsp.db2lin(rel_db)
    out = []
    armed = True
    last = -1e9
    for i in range(1, nb):
        if armed and env[i] > thr and env[i - 1] <= thr:
            t = i * w / SR
            if t - last >= min_gap:
                out.append(t)
                last = t
                armed = False
        elif not armed and env[i] < thr * 0.4:
            armed = True
    return out


def tone_track(x, f_lo, f_hi, hop=0.05, win=0.25):
    """strongest spectral peak (parabolic interpolation) in [f_lo, f_hi] per hop -> (times, freqs, levels_db)"""
    n = int(win * SR)
    h = int(hop * SR)
    ts, fs, ls = [], [], []
    nfft = 1 << 17
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    band = (f >= f_lo) & (f <= f_hi)
    idxs = np.nonzero(band)[0]
    for s in range(0, len(x) - n, h):
        seg = x[s:s + n] * np.hanning(n)
        X = np.abs(np.fft.rfft(seg, nfft))
        k = idxs[np.argmax(X[idxs])]
        a, b, c = np.log(X[k - 1] + 1e-12), np.log(X[k] + 1e-12), np.log(X[k + 1] + 1e-12)
        d = 0.5 * (a - c) / (a - 2 * b + c + 1e-12)
        ts.append((s + n / 2) / SR)
        fs.append((k + d) * SR / nfft)
        ls.append(20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-12))
    return np.array(ts), np.array(fs), np.array(ls)


def centroid(x):
    return dsp.spectral_centroid(x)


def run_all(man):
    out = []

    def add(ok, label, detail=""):
        out.append((bool(ok), label, detail))

    # ---- hum bed vs buzz cell: signature sound of the game
    bed, buzz = load(man, "amb_hum_bed"), load(man, "amb_buzz_cell")
    if bed is not None:
        fr = dsp.band_fraction(bed, 0, 500)
        add(fr > 0.90, "amb_hum_bed energy below 500 Hz", f"{fr * 100:.1f}%  centroid {centroid(bed):.0f} Hz")
    if bed is not None and buzz is not None:
        cb, cz = centroid(bed), centroid(buzz)
        add(cz > 3.0 * cb, "buzz clearly brighter than bed", f"centroid bed {cb:.0f} Hz, buzz {cz:.0f} Hz")
        hi = dsp.band_fraction(buzz, 1000, 3200)
        add(hi > 0.25, "amb_buzz_cell has energy 1-3.2 kHz", f"{hi * 100:.1f}%")

    # ---- hum_drop / hum_rise: opposite glides, ~1 semitone, opposite loudness trends
    hd, hr = load(man, "hum_drop"), load(man, "hum_rise")
    if hd is not None and hr is not None:
        for nm, x, sign in (("hum_drop", hd, -1), ("hum_rise", hr, +1)):
            t, f, lv = tone_track(x, 95, 150)
            f0 = float(np.median(f[:3]))
            f1 = float(np.median(f[-3:]))
            semis = 12 * np.log2(f1 / f0)
            add(sign * semis > 0.6 and abs(semis) < 1.6, f"{nm} glides ~1 semitone ({'down' if sign < 0 else 'up'})",
                f"120 Hz partial {f0:.1f} -> {f1:.1f} Hz = {semis:+.2f} st")
            q = len(x) // 4
            c_first, c_last = centroid(x[:q]), centroid(x[-q:])
            l_first, l_last = dsp.rms_db(x[:q]), dsp.rms_db(x[-q:])
            if sign < 0:
                add(c_last < c_first and l_last < l_first - 3, "hum_drop thins and falls in level",
                    f"centroid {c_first:.0f}->{c_last:.0f} Hz, level {l_first:.1f}->{l_last:.1f} dB")
            else:
                add(c_last > c_first and l_last > l_first + 2, "hum_rise brightens and swells",
                    f"centroid {c_first:.0f}->{c_last:.0f} Hz, level {l_first:.1f}->{l_last:.1f} dB")

    # ---- footsteps: carpet dull, tile brighter, concrete between/over, each set varies
    sc, st, sk = load(man, "step_carpet"), load(man, "step_tile"), load(man, "step_concrete")
    if sc is not None and st is not None:
        add(centroid(st) > 1.8 * centroid(sc), "step_tile brighter than step_carpet",
            f"centroid carpet {centroid(sc):.0f} Hz, tile {centroid(st):.0f} Hz")
    if sc is not None and sk is not None:
        add(centroid(sk) > 1.3 * centroid(sc), "step_concrete brighter than step_carpet",
            f"centroid carpet {centroid(sc):.0f} Hz, concrete {centroid(sk):.0f} Hz")

    # ---- whistle: strong 2-4 kHz peak
    for v in (1, 2):
        w = load(man, "whistle_blast", v)
        if w is not None:
            fr = dsp.band_fraction(w, 2000, 4200)
            add(fr > 0.55, f"whistle_blast_{v} energy in 2-4.2 kHz", f"{fr * 100:.1f}%  centroid {centroid(w):.0f} Hz")

    # ---- knocks: slow = even spacing (~1 s), irregular = uneven
    ks, ki = load(man, "knock_slow"), load(man, "knock_irregular")
    if ks is not None:
        o = onsets(ks, rel_db=-22.0, min_gap=0.25)
        gaps = np.diff(o)
        add(len(o) == 3 and np.all(np.abs(gaps - 1.0) < 0.06), "knock_slow: 3 knocks ~1.0 s apart, even",
            f"onsets {np.round(o, 3).tolist()}")
    if ki is not None:
        o = onsets(ki, rel_db=-22.0, min_gap=0.06)
        gaps = np.diff(o)
        uneven = len(gaps) == 2 and (max(gaps) / max(min(gaps), 1e-3) > 3.0)
        add(len(o) == 3 and uneven, "knock_irregular: 3 knocks, clearly uneven (long pause then quick double)",
            f"onsets {np.round(o, 3).tolist()}")

    # ---- door handle try / locked have distinct structures; alarm bright; heartbeat two thumps
    hb = load(man, "amb_heartbeat")
    if hb is not None:
        o = onsets(hb, win_ms=5.0, rel_db=-14.0, min_gap=0.12, smooth_ms=20.0)
        add(len(o) == 2 and 0.2 < (o[1] - o[0]) < 0.45, "amb_heartbeat is lub-dub", f"onsets {np.round(o, 3).tolist()}")
    al = load(man, "alarm_loop")
    if al is not None:
        add(centroid(al) > 1200, "alarm_loop is bright/harsh", f"centroid {centroid(al):.0f} Hz")

    # ---- equal-loudness PA chime / mic_pop low
    mp = load(man, "mic_pop")
    if mp is not None:
        add(dsp.band_fraction(mp, 40, 220) > 0.55, "mic_pop is a low (~80 Hz) thump", f"{dsp.band_fraction(mp, 40, 220) * 100:.0f}% in 40-220 Hz")
    return out
