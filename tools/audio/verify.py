#!/usr/bin/env python3
"""Re-checks every entry of audio/manifest.json and prints PASS/FAIL per file.

    python3 -I tools/audio/verify.py [--quiet] [--no-semantic]

Per file: exists, mono, 32 kHz, 16-bit (wav), peak <= -1 dBFS, no clipped samples, DC small, not silent,
loops seamless, duration within +/-40% of the catalog target (documented exceptions below).
Per entry: variant count + variants are audibly different; manifest 'dur' equals the measured length.
Voice: true/false pairing, lengths equal within 2%, equal loudness across lines.
Semantic: spectral/rhythm sanity checks that encode the design intent (hum bed low, buzz bright, whistle
2-4 kHz, tile brighter than carpet, knock rhythms, hum_drop falls / hum_rise rises, ...).
Exit status 1 when anything FAILs.
"""
import json
import os
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402

import core  # noqa: E402
import dsp  # noqa: E402
from dsp import SR  # noqa: E402

PEAK_MAX_DB = -1.0
DC_MAX = 0.002
SEAM_RATIO_MAX = 4.0          # loop seam jump / typical sample step
SEAM_JUMP_MAX = 0.06          # absolute (fraction of FS) guard against gross discontinuities
DUR_TOL = 0.40

# catalog 'dur' is a target; these are intentional deviations (name -> reason)
DUR_EXCEPTIONS = {}

# loops where a lossy codec is in play get a looser seam bound
OGG_SEAM_RATIO_MAX = 8.0

results = {"pass": 0, "fail": 0, "warn": 0}


def say(ok, label, detail="", quiet=False, warn=False):
    tag = "PASS" if ok else ("WARN" if warn else "FAIL")
    results["pass" if ok else ("warn" if warn else "fail")] += 1
    if not (ok and quiet):
        print(f"{tag}  {label}  {detail}")


def res_to_disk(res):
    assert res.startswith("res://"), res
    return os.path.join(core.ROOT, res[len("res://"):])


def wav_header_ok(path):
    with wave.open(path, "rb") as w:
        return w.getsampwidth() == 2 and w.getnchannels() == 1 and w.getframerate() == SR


def check_file(path, entry, catalog_dur, loop, quiet):
    rel = os.path.relpath(path, core.ROOT)
    probs = []
    if not os.path.isfile(path):
        say(False, rel, "missing file", quiet)
        return None
    x, sr, ch = core.decode_audio(path)
    if ch != 1:
        probs.append(f"channels={ch}")
    if sr != SR:
        probs.append(f"sr={sr}")
    if path.endswith(".wav") and not wav_header_ok(path):
        probs.append("wav header not 16-bit mono 32k")
    pk = dsp.peak_db(x)
    rms = dsp.rms_db(x)
    dc = float(np.mean(x))
    if pk > PEAK_MAX_DB:
        probs.append(f"peak {pk:.2f} dBFS > {PEAK_MAX_DB}")
    if np.sum(np.abs(x) >= 0.9990) > 0:
        probs.append("clipped samples")
    if abs(dc) > DC_MAX:
        probs.append(f"DC {dc:+.4f}")
    if rms < -70:
        probs.append(f"silent (rms {rms:.1f})")
    dur = len(x) / sr
    extra = ""
    if loop:
        jump, ratio = dsp.seam_stats(x)
        lim = OGG_SEAM_RATIO_MAX if path.endswith(".ogg") else SEAM_RATIO_MAX
        extra = f" seam {jump:.5f} (x{ratio:.2f})"
        if ratio > lim:
            probs.append(f"loop seam x{ratio:.1f} > x{lim}")
        if path.endswith(".wav") and jump > SEAM_JUMP_MAX:
            probs.append(f"loop seam jump {jump:.4f} > {SEAM_JUMP_MAX}")
    if catalog_dur is not None:
        lo, hi = catalog_dur * (1 - DUR_TOL), catalog_dur * (1 + DUR_TOL)
        if not (lo <= dur <= hi) and entry not in DUR_EXCEPTIONS:
            probs.append(f"duration {dur:.2f}s outside +/-40% of {catalog_dur}s")
    say(not probs, rel, f"{dur:.2f}s pk {pk:.1f} rms {rms:.1f}{extra}" + ("  -> " + "; ".join(probs) if probs else ""), quiet)
    return x


def variants_differ(xs, label, quiet):
    """variants must not be near-identical: peak normalised cross-correlation and spectral/envelope distance"""
    ok = True
    notes = []
    for i in range(len(xs)):
        for j in range(i + 1, len(xs)):
            a, b = xs[i], xs[j]
            n = min(len(a), len(b), SR)
            a, b = a[:n], b[:n]
            fa, fb = np.abs(np.fft.rfft(a * np.hanning(n))), np.abs(np.fft.rfft(b * np.hanning(n)))
            cc = np.max(np.abs(np.fft.irfft(np.fft.rfft(a, 2 * n) * np.conj(np.fft.rfft(b, 2 * n)))))
            cc /= (np.sqrt(np.sum(a * a) * np.sum(b * b)) + 1e-12)
            # coarse log-spectrum distance in 1/3-octave-ish bands
            edges = np.geomspace(100, 12000, 17)
            f = np.fft.rfftfreq(n, 1 / SR)
            ba = np.array([np.sum(fa[(f >= lo) & (f < hi)] ** 2) + 1e-12 for lo, hi in zip(edges[:-1], edges[1:])])
            bb = np.array([np.sum(fb[(f >= lo) & (f < hi)] ** 2) + 1e-12 for lo, hi in zip(edges[:-1], edges[1:])])
            sd = float(np.sqrt(np.mean((10 * np.log10(ba / bb)) ** 2)))
            notes.append(f"{i + 1}v{j + 1}: xcorr {cc:.2f} specdist {sd:.1f}dB")
            if cc > 0.80 or sd < 0.8:
                ok = False
    say(ok, f"variants differ: {label}", "; ".join(notes), quiet)


def main(argv):
    quiet = "--quiet" in argv
    semantic = "--no-semantic" not in argv
    if not os.path.isfile(core.MANIFEST_PATH):
        print("FAIL  audio/manifest.json missing")
        return 1
    with open(core.MANIFEST_PATH, "r", encoding="utf-8") as fh:
        man = json.load(fh)
    catalog = {e["name"]: e for e in core.load_catalog()}
    audio = {}

    # ---- structure
    say(set(man.keys()) == {"sounds", "voice"}, "manifest top-level keys", str(sorted(man.keys())), quiet)
    for name, e in catalog.items():
        if name not in man["sounds"]:
            say(False, f"manifest.sounds[{name}]", "missing from manifest", quiet)
    for name, ent in man["sounds"].items():
        e = catalog.get(name)
        if e is None:
            say(False, f"manifest.sounds[{name}]", "not in catalog", quiet)
            continue
        keys_ok = set(ent.keys()) == {"files", "loop", "bus", "db", "dur", "group"}
        meta_ok = (ent["loop"] == bool(e["loop"]) and ent["bus"] == e["bus"] and abs(ent["db"] - e["db"]) < 1e-9
                   and ent["group"] == e["group"] and len(ent["files"]) == e["variants"])
        say(keys_ok and meta_ok, f"manifest entry {name}", "" if keys_ok and meta_ok else f"bad fields/meta {ent}", quiet)
        xs = []
        for res in ent["files"]:
            p = res_to_disk(res)
            x = check_file(p, name, float(e["dur"]), bool(e["loop"]), quiet)
            if x is not None:
                xs.append(x)
        audio[name] = xs
        if xs:
            longest = max(len(x) for x in xs) / SR
            say(abs(longest - ent["dur"]) < 0.002, f"manifest dur {name}", f"{ent['dur']} vs measured {longest:.3f}", quiet)
        if len(xs) > 1:
            variants_differ(xs, name, quiet)

    # ---- voice
    lines = {ln["id"]: ln for ln in core.load_pa_lines()}
    act = []
    for lid, ln in lines.items():
        v = man["voice"].get(lid)
        if v is None:
            say(False, f"voice {lid}", "missing from manifest", quiet)
            continue
        keys_ok = set(v.keys()) == {"true", "false", "text", "kind", "dur_true", "dur_false"}
        want_false = "false" in ln["takes"]
        pair_ok = (v["false"] is not None) == want_false and v["text"] == ln["text"] and v["kind"] == ln["kind"]
        say(keys_ok and pair_ok, f"manifest voice {lid}", "" if keys_ok and pair_ok else f"bad {v}", quiet)
        xt = check_file(res_to_disk(v["true"]), lid + "_true", None, False, quiet)
        if xt is not None:
            act.append(_active_rms(xt))
            say(abs(len(xt) / SR - v["dur_true"]) < 0.002, f"voice dur_true {lid}", "", quiet)
        if v["false"]:
            xf = check_file(res_to_disk(v["false"]), lid + "_false", None, False, quiet)
            if xt is not None and xf is not None:
                ratio = abs(len(xf) - len(xt)) / max(len(xt), 1)
                say(ratio < 0.02, f"voice true/false length {lid}", f"{len(xt) / SR:.3f}s vs {len(xf) / SR:.3f}s", quiet)
                d = xf[:len(xt)] - xt[:len(xf)]
                prel = dsp.peak_db(d) - dsp.peak_db(xt)
                say(-40 < prel < -18, f"voice pop level {lid}", f"diff peak {prel:.1f} dB re line peak", quiet)
    if act:
        spread = max(act) - min(act)
        say(spread <= 2.0, "voice loudness spread", f"active-RMS spread {spread:.2f} dB over {len(act)} lines", quiet)

    if semantic:
        import checks
        for ok, label, detail in checks.run_all(man):
            say(ok, "semantic: " + label, detail, quiet)

    print(f"\n{results['pass']} PASS, {results['warn']} WARN, {results['fail']} FAIL")
    return 1 if results["fail"] else 0


def _active_rms(x):
    import voice
    return voice.active_rms_db(x)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
