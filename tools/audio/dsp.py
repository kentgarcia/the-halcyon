"""dsp.py -- numpy-only DSP toolbox for the halcyon audio generator (no scipy, no sox).

Everything here is deterministic: randomness only comes from numpy Generators that the
caller seeds through `rng_for(...)` (crc32 of a name, so it is stable across runs/machines).

Conventions
  * sample rate is SR (32 kHz); float64 arrays in [-1, 1]; mono.
  * "circular=True" means the buffer is treated as one period of a loop: filters, reverbs
    and event placement wrap around, so the result is seamless when looped.
  * zero-phase filters are used for static noise shaping; phase="min" gives causal
    (minimum-phase) filters with no pre-ringing for shaping transients.
"""
import struct
import zlib

import numpy as np

SR = 32000
TWO_PI = 2.0 * np.pi
EPS = 1e-12


# --------------------------------------------------------------------------- basics
def N(sec):
    """seconds -> sample count"""
    return int(round(sec * SR))


def tgrid(n, t0=0.0):
    return t0 + np.arange(n) / SR


def rng_for(*parts):
    key = "|".join(str(p) for p in parts).encode("utf-8")
    return np.random.default_rng(zlib.crc32(key) & 0xFFFFFFFF)


def db2lin(db):
    return 10.0 ** (np.asarray(db, dtype=float) / 20.0)


def lin2db(x):
    return 20.0 * np.log10(np.maximum(np.abs(x), EPS))


def peak_db(x):
    return float(lin2db(np.max(np.abs(x)))) if len(x) else -200.0


def rms_db(x):
    return float(lin2db(np.sqrt(np.mean(np.square(x))))) if len(x) else -200.0


def remove_dc(x):
    return x - np.mean(x)


def normalize(x, target_db=-3.0):
    p = np.max(np.abs(x))
    if p < EPS:
        return x
    return x * (db2lin(target_db) / p)


def fit(x, n):
    """pad with zeros / truncate to exactly n samples"""
    if len(x) >= n:
        return x[:n].copy()
    return np.concatenate([x, np.zeros(n - len(x))])


def silence(sec):
    return np.zeros(N(sec))


def put(buf, x, t0, gain=1.0, circular=False):
    """add x into buf starting at time t0 (seconds); in-place; returns buf.
    circular=True wraps events that run past the end back to the start (loop-safe)."""
    i0 = int(round(t0 * SR))
    n = len(buf)
    m = len(x)
    if circular:
        idx = (np.arange(m) + i0) % n
        np.add.at(buf, idx, x * gain)
        return buf
    if i0 >= n or i0 + m <= 0:
        return buf
    a = max(0, -i0)
    b = min(m, n - i0)
    buf[i0 + a:i0 + b] += x[a:b] * gain
    return buf


def concat(*parts):
    return np.concatenate(parts) if parts else np.zeros(0)


def fade_edges(x, in_ms=3.0, out_ms=4.0):
    """raised-cosine fade in/out; in place on a copy"""
    y = x.copy()
    n = len(y)
    a = min(int(in_ms * SR / 1000.0), n // 2)
    b = min(int(out_ms * SR / 1000.0), n // 2)
    if a > 0:
        y[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if b > 0:
        y[n - b:] *= 0.5 + 0.5 * np.cos(np.pi * (np.arange(b) + 1) / b)
    return y


def fade_out_tail(x, ms):
    y = x.copy()
    b = min(int(ms * SR / 1000.0), len(y))
    if b > 0:
        y[len(y) - b:] *= 0.5 + 0.5 * np.cos(np.pi * (np.arange(b) + 1) / b)
    return y


# --------------------------------------------------------------------------- noise
def white(n, rng):
    return rng.standard_normal(n)


def colored(n, rng, slope=1.0):
    """noise whose power spectrum goes as 1/f**slope (0 white, 1 pink, 2 brown); unit rms.
    Generated circularly (periodic over n samples)."""
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1] if len(f) > 1 else 1.0
    X *= f ** (-slope / 2.0)
    X[0] = 0.0
    y = np.fft.irfft(X, n)
    return y / (np.std(y) + EPS)


# --------------------------------------------------------------------------- spectral filters
def _next_pow2(n):
    return 1 << max(1, int(n - 1).bit_length())


def _minphase(H, nfft):
    """magnitude response -> causal minimum-phase complex response (homomorphic method)"""
    logH = np.log(np.maximum(H, 1e-9))
    c = np.fft.irfft(logH, nfft)
    w = np.zeros(nfft)
    w[0] = 1.0
    half = nfft // 2
    if nfft % 2 == 0:
        w[1:half] = 2.0
        w[half] = 1.0
    else:
        w[1:half + 1] = 2.0
    return np.exp(np.fft.rfft(c * w))


def shape(x, mag_fn, phase="zero", circular=False, pad=0.25):
    """Apply a magnitude response mag_fn(f_hz)->|H| to x using FFT multiplication."""
    n = len(x)
    nfft = n if circular else _next_pow2(n + int(pad * SR))
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    H = mag_fn(f)
    if phase == "min":
        H = _minphase(H, nfft)
    y = np.fft.irfft(np.fft.rfft(x, nfft) * H, nfft)
    return y if circular else y[:n]


def _lp_mag(f, fc, order):
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def _hp_mag(f, fc, order):
    r = fc / np.maximum(f, 1e-6)
    return 1.0 / np.sqrt(1.0 + r ** (2 * order))


def make_mag(lo=None, hi=None, order=2, peaks=(), shelf=()):
    """Return mag_fn for a combination of HP(lo), LP(hi), peaking bumps [(f0, gain_db, q)]
    and high shelves [(f0, gain_db)] (smooth, log-domain)."""
    def fn(f):
        m = np.ones_like(f)
        if hi:
            m = m * _lp_mag(f, hi, order)
        if lo:
            m = m * _hp_mag(f, lo, order)
        for (f0, g, q) in peaks:
            ff = np.maximum(f, 1e-6)
            m = m * 10.0 ** ((g / 20.0) / (1.0 + (q * (ff / f0 - f0 / ff)) ** 2))
        for (f0, g) in shelf:
            m = m * 10.0 ** ((g / 20.0) * (1.0 / (1.0 + (f0 / np.maximum(f, 1e-6)) ** 2)))
        return m
    return fn


def filt(x, lo=None, hi=None, order=2, peaks=(), shelf=(), phase="zero", circular=False):
    return shape(x, make_mag(lo, hi, order, peaks, shelf), phase=phase, circular=circular)


def lp(x, fc, order=2, **kw):
    return filt(x, hi=fc, order=order, **kw)


def hp(x, fc, order=2, **kw):
    return filt(x, lo=fc, order=order, **kw)


def bp(x, lo, hi, order=2, **kw):
    return filt(x, lo=lo, hi=hi, order=order, **kw)


def reso(x, f0, q, phase="zero", circular=False, order=1):
    """resonant band-pass (2-pole style magnitude), unity gain at f0"""
    def fn(f):
        ff = np.maximum(f, 1e-6)
        return (1.0 / np.sqrt(1.0 + (q * (ff / f0 - f0 / ff)) ** 2)) ** order
    return shape(x, fn, phase=phase, circular=circular)


def formants(x, fl, phase="zero", circular=False):
    """sum of resonant bands: fl = [(f_hz, q, gain), ...]  -- vocal-tract style filtering"""
    def fn(f):
        ff = np.maximum(f, 1e-6)
        m = np.zeros_like(f)
        for (f0, q, g) in fl:
            m = m + g / np.sqrt(1.0 + (q * (ff / f0 - f0 / ff)) ** 2)
        return m
    return shape(x, fn, phase=phase, circular=circular)


def spectral_noise(n, rng, mag_fn):
    """periodic noise of exactly n samples with magnitude spectrum mag_fn (seamless loop source)"""
    X = rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    X = X * mag_fn(f)
    X[0] = 0.0
    y = np.fft.irfft(X, n)
    return y / (np.std(y) + EPS)


def svf(x, f, q=5.0, mode="bp"):
    """Time-varying TPT state-variable filter (python loop -- use on short material).
    f, q: scalars or per-sample arrays. mode: bp (unity-gain peak), lp, hp."""
    n = len(x)
    f = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    q = np.broadcast_to(np.asarray(q, dtype=float), (n,))
    g = np.tan(np.pi * np.minimum(f, 0.45 * SR) / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs = x.tolist()
    a1l, a2l, a3l, kl = a1.tolist(), a2.tolist(), a3.tolist(), k.tolist()
    out = [0.0] * n
    ic1 = ic2 = 0.0
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = a1l[i] * ic1 + a2l[i] * v3
        v2 = ic2 + a2l[i] * ic1 + a3l[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if mode == "bp":
            out[i] = kl[i] * v1
        elif mode == "lp":
            out[i] = v2
        else:
            out[i] = xs[i] - kl[i] * v1 - v2
    return np.array(out)


def onepole_lp(x, fc):
    """simple causal one-pole lowpass (fc scalar or array), python loop"""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    a = 1.0 - np.exp(-TWO_PI * fc / SR)
    xs, al = x.tolist(), a.tolist()
    y = 0.0
    out = [0.0] * n
    for i in range(n):
        y += al[i] * (xs[i] - y)
        out[i] = y
    return np.array(out)


# --------------------------------------------------------------------------- envelopes
def e_exp(n, tau, atk=0.0005):
    t = np.arange(n) / SR
    e = np.exp(-t / max(tau, 1e-6))
    a = int(atk * SR)
    if a > 1:
        e[:a] *= np.linspace(0.0, 1.0, a, endpoint=False)
    return e


def e_pts(n, pts, power=1.0):
    """piecewise-linear envelope from [(t_sec, gain), ...] (raised to `power` between points)."""
    ts = np.array([p[0] for p in pts], dtype=float) * SR
    gs = np.array([p[1] for p in pts], dtype=float)
    e = np.interp(np.arange(n), ts, gs)
    return e ** power if power != 1.0 else e


def e_hann(n):
    return np.hanning(n + 2)[1:-1] if n > 0 else np.zeros(0)


def smoothstep(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def e_ar(n, atk, rel, t0=0.0):
    """attack/release bump placed at t0 (s): raised-cosine up then exponential-ish down"""
    t = np.arange(n) / SR - t0
    up = smoothstep(t / max(atk, 1e-6))
    dn = np.where(t > atk, np.exp(-(t - atk) / max(rel, 1e-6)), 1.0)
    return np.where(t >= 0, up * dn, 0.0)


# --------------------------------------------------------------------------- oscillators
def phase_of(freq, n, phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return phase0 + TWO_PI * np.cumsum(f) / SR


def sine(freq, n, phase0=0.0):
    return np.sin(phase_of(freq, n, phase0))


def harm_stack(f0, amps, n, phases=None, fmax=None):
    """sum_k amps[k] * sin(k*phase(f0) + phases[k]); f0 scalar or per-sample array.
    amps may be (K,) or (K, n) for time-varying partial levels. Partials above fmax are dropped."""
    f0 = np.broadcast_to(np.asarray(f0, dtype=float), (n,))
    ph = phase_of(f0, n)
    amps = np.asarray(amps, dtype=float)
    K = amps.shape[0]
    y = np.zeros(n)
    fmax = fmax or 0.46 * SR
    for k in range(K):
        a = amps[k]
        if np.max(np.abs(a)) < 1e-9:
            continue
        p0 = 0.0 if phases is None else phases[k]
        # fade partials approaching Nyquist
        ff = (k + 1) * f0
        guard = np.clip((fmax - ff) / (0.08 * SR), 0.0, 1.0)
        y += a * guard * np.sin((k + 1) * ph + p0)
    return y


def modal(freqs, amps, taus, n, rng=None, phases=None, atk=0.0002):
    """sum of exponentially decaying sinusoids (struck-object model)."""
    t = (np.arange(n) / SR)[None, :]
    f = np.asarray(freqs, dtype=float)[:, None]
    a = np.asarray(amps, dtype=float)[:, None]
    tau = np.asarray(taus, dtype=float)[:, None]
    if phases is None:
        phases = rng.uniform(0, TWO_PI, len(freqs)) if rng is not None else np.zeros(len(freqs))
    ph = np.asarray(phases, dtype=float)[:, None]
    y = (a * np.exp(-t / tau) * np.sin(TWO_PI * f * t + ph)).sum(axis=0)
    na = int(atk * SR)
    if na > 1:
        y[:na] *= np.linspace(0.0, 1.0, na, endpoint=False)
    return y


# --------------------------------------------------------------------------- resample / delay
def read_at(x, pos, circular=False):
    """4-point Catmull-Rom interpolation of x at fractional sample positions `pos`."""
    n = len(x)
    i = np.floor(pos).astype(np.int64)
    fr = pos - i
    if circular:
        idx = [(i + k) % n for k in (-1, 0, 1, 2)]
    else:
        idx = [np.clip(i + k, 0, n - 1) for k in (-1, 0, 1, 2)]
    y0, y1, y2, y3 = (x[j] for j in idx)
    c0 = y1
    c1 = 0.5 * (y2 - y0)
    c2 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3
    c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
    return ((c3 * fr + c2) * fr + c1) * fr + c0


def varispeed(x, ratio, n_out=None):
    """play x back `ratio` times faster (pitch up when >1). ratio may be an array (per output sample)."""
    if np.isscalar(ratio):
        m = int(len(x) / ratio) if n_out is None else n_out
        pos = np.arange(m) * ratio
    else:
        r = np.asarray(ratio, dtype=float)
        pos = np.cumsum(r) - r[0]
        m = len(r)
    ok = pos < len(x) - 1
    y = np.zeros(m)
    y[ok] = read_at(x, pos[ok])
    return y


def pitch_shift_simple(x, semitones):
    """cheap pitch shift by resampling (changes length). Fine for foley variation."""
    return varispeed(x, 2.0 ** (semitones / 12.0))


def wow(x, depth_ms_list, circular=True):
    """tape wow/flutter: time-varying delay. depth_ms_list=[(freq_hz, depth_ms, phase), ...].
    For circular use pick frequencies that are integer multiples of 1/len(x)."""
    n = len(x)
    t = np.arange(n) / SR
    d = np.zeros(n)
    for (fr, dm, ph) in depth_ms_list:
        d += dm * 1e-3 * np.sin(TWO_PI * fr * t + ph)
    return read_at(x, np.arange(n) + d * SR, circular=circular)


def resample_fft(x, sr_in, sr_out):
    """band-limited resampling by spectrum truncation / zero-padding (good for 16k -> 32k speech)."""
    n = len(x)
    m = int(round(n * sr_out / sr_in))
    X = np.fft.rfft(x)
    Y = np.zeros(m // 2 + 1, dtype=complex)
    k = min(len(X), len(Y))
    Y[:k] = X[:k]
    return np.fft.irfft(Y, m) * (m / n)


def trim_silence(x, thresh_db=-48.0, win_ms=10.0, keep_ms=0.0):
    """strip leading/trailing samples below thresh_db (relative to peak), keeping `keep_ms` of margin"""
    w = max(1, int(win_ms * SR / 1000.0))
    a = np.abs(x)
    nb = len(a) // w
    if nb == 0:
        return x
    env = a[:nb * w].reshape(nb, w).max(axis=1)
    thr = np.max(a) * db2lin(thresh_db)
    idx = np.nonzero(env > thr)[0]
    if len(idx) == 0:
        return x
    keep = int(keep_ms * SR / 1000.0)
    return x[max(0, idx[0] * w - keep):min(len(x), (idx[-1] + 1) * w + keep)]


# --------------------------------------------------------------------------- reverb
_IR_CACHE = {}

ROOMS = {
    # name: (rt60, hf_mult, lf_mult, predelay_s, early[(t, g)], hi_cut, lo_cut)
    "closet": (0.18, 0.5, 1.0, 0.002, [(0.004, 0.6), (0.009, 0.4)], 7000, 120),
    "office": (0.38, 0.55, 1.0, 0.004, [(0.006, 0.5), (0.013, 0.4), (0.021, 0.3)], 7000, 90),
    "corridor": (0.9, 0.55, 1.1, 0.006, [(0.012, 0.45), (0.029, 0.35), (0.047, 0.3)], 6500, 90),
    "concrete": (0.7, 0.6, 1.0, 0.004, [(0.009, 0.5), (0.021, 0.4), (0.037, 0.3)], 7500, 80),
    "tile": (1.4, 0.8, 0.9, 0.008, [(0.011, 0.55), (0.024, 0.5), (0.039, 0.4), (0.061, 0.3)], 9000, 120),
    "hall": (2.4, 0.5, 1.1, 0.020, [(0.027, 0.4), (0.051, 0.35), (0.083, 0.3)], 6000, 80),
    "lobby": (2.0, 0.45, 1.2, 0.018, [(0.023, 0.4), (0.046, 0.35), (0.079, 0.3)], 5500, 70),
    "shaft": (3.2, 0.4, 1.1, 0.030, [(0.040, 0.4), (0.092, 0.35), (0.150, 0.3)], 4500, 70),
    "far": (3.0, 0.3, 1.2, 0.060, [(0.075, 0.35), (0.140, 0.3)], 2600, 60),
    "pa_room": (0.9, 0.5, 0.8, 0.012, [(0.019, 0.5), (0.043, 0.4), (0.110, 0.35)], 3800, 250),
    "pool": (3.4, 0.75, 0.9, 0.012, [(0.015, 0.5), (0.034, 0.5), (0.058, 0.4), (0.097, 0.35)], 9500, 140),
    "boiler": (1.6, 0.4, 1.1, 0.010, [(0.016, 0.45), (0.038, 0.4), (0.070, 0.3)], 4500, 60),
}


def make_ir(rt60, rng, hf_mult=0.6, lf_mult=1.0, predelay=0.004, early=(), hi_cut=8000, lo_cut=80, max_len=None):
    L = int(min(rt60 * 1.15, max_len or 8.0) * SR) + int(predelay * SR) + 8
    t = np.arange(L) / SR
    base = rng.standard_normal(L)
    # three-band decay (low / mid / high), crossovers ~ 400 Hz and ~ 3 kHz
    nfft = _next_pow2(L)
    f = np.fft.rfftfreq(nfft, 1.0 / SR)
    B = np.fft.rfft(base, nfft)
    lowm = _lp_mag(f, 400.0, 2)
    highm = _hp_mag(f, 3000.0, 2)
    midm = np.clip(1.0 - lowm ** 2 - highm ** 2, 0.0, 1.0) ** 0.5
    ir = np.zeros(L)
    for m, mult in ((lowm, lf_mult), (midm, 1.0), (highm, hf_mult)):
        band = np.fft.irfft(B * m, nfft)[:L]
        ir += band * np.exp(-6.9078 * t / max(rt60 * mult, 0.02))
    # onset shaping: short build-up, then predelay shift
    ir *= 1.0 - np.exp(-t / 0.003)
    pd = int(predelay * SR)
    ir = np.concatenate([np.zeros(pd), ir])[:L]
    for (te, ge) in early:
        k = int(te * SR)
        if k < L:
            ir[k] += ge * 6.0 * (rng.choice([-1.0, 1.0]))
    ir = shape(ir, make_mag(lo=lo_cut, hi=hi_cut, order=2), circular=False, pad=0.05)
    ir /= np.sqrt(np.sum(ir ** 2)) + EPS
    return ir


def get_ir(name):
    if name not in _IR_CACHE:
        rt60, hfm, lfm, pre, early, hi, lo = ROOMS[name]
        _IR_CACHE[name] = make_ir(rt60, rng_for("ir", name), hfm, lfm, pre, early, hi, lo)
    return _IR_CACHE[name]


def convolve(x, ir, circular=False, tail=None):
    """FFT convolution. non-circular output length = len(x) + tail (default full IR)."""
    n = len(x)
    if circular:
        irf = np.zeros(n)
        for i in range(0, len(ir), n):
            seg = ir[i:i + n]
            irf[:len(seg)] += seg
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irf), n)
    m = len(ir) if tail is None else int(tail * SR)
    L = n + len(ir) - 1
    nfft = _next_pow2(L)
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:L]
    return y[:n + m] if n + m <= L else np.concatenate([y, np.zeros(n + m - L)])


def reverb(x, room, wet=0.3, dry=1.0, circular=False, tail=None):
    """room: preset name from ROOMS or a custom IR array. wet: linear gain of the energy-normalised wet path.
    Non-circular output is longer than x by `tail` seconds (default: IR length)."""
    ir = get_ir(room) if isinstance(room, str) else room
    w = convolve(x, ir, circular=circular, tail=tail)
    if circular:
        return dry * x + wet * w
    d = np.concatenate([x, np.zeros(len(w) - len(x))])
    return dry * d + wet * w


# --------------------------------------------------------------------------- dynamics
def limit(x, ceil=0.9, win_ms=2.0):
    """transparent-ish look-ahead peak limiter (sliding max + smoothed gain). Never exceeds `ceil`."""
    w = max(3, int(win_ms * SR / 1000.0)) | 1
    a = np.abs(x)
    pad = np.pad(a, (w // 2, w // 2), mode="edge")
    env = np.lib.stride_tricks.sliding_window_view(pad, w).max(axis=1)
    g = np.minimum(1.0, ceil / np.maximum(env, EPS))
    k = np.hanning(w + 2)[1:-1]
    k /= k.sum()
    gp = np.pad(g, (w // 2, w // 2), mode="edge")
    gs = np.convolve(gp, k, mode="valid")
    return x * gs[:len(x)]


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive) if drive != 0 else x


def compress(x, thresh_db=-24.0, ratio=3.0, attack_ms=5.0, release_ms=120.0, makeup_db=0.0, block=32):
    """feed-forward peak compressor with block-wise detector (fast, no per-sample python)."""
    n = len(x)
    nb = (n + block - 1) // block
    pad = np.pad(np.abs(x), (0, nb * block - n))
    lev = pad.reshape(nb, block).max(axis=1)
    lev_db = lin2db(lev)
    over = np.maximum(lev_db - thresh_db, 0.0)
    target = (-over * (1.0 - 1.0 / ratio)).tolist()
    ca = np.exp(-block / (attack_ms * 1e-3 * SR))
    cr = np.exp(-block / (release_ms * 1e-3 * SR))
    g = 0.0
    gl = []
    for t in target:
        c = ca if t < g else cr   # more reduction needed -> attack
        g = c * g + (1.0 - c) * t
        gl.append(g)
    gl = np.array(gl) + makeup_db
    centers = (np.arange(nb) + 0.5) * block
    gain_db = np.interp(np.arange(n), centers, gl)
    return x * db2lin(gain_db)


def bitcrush(x, bits=11, rate_div=1):
    """reduce word length (and optionally sample-and-hold rate)"""
    y = x
    if rate_div > 1:
        y = np.repeat(y[::rate_div], rate_div)[:len(x)]
    q = 2.0 ** (bits - 1)
    return np.round(y * q) / q


# --------------------------------------------------------------------------- analysis
def spectral_centroid(x):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return float(np.sum(f * X) / (np.sum(X) + EPS))


def band_fraction(x, lo, hi):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    return float(np.sum(X[(f >= lo) & (f < hi)]) / (np.sum(X) + EPS))


def seam_stats(x):
    """loop seam continuity: jump between last and first sample, and that jump relative to the
    typical (rms) sample-to-sample step of the signal itself. ratio ~<= 3 means indistinguishable
    from any interior sample pair."""
    jump = abs(float(x[0] - x[-1]))
    d = np.diff(x)
    typ = float(np.sqrt(np.mean(d * d))) + EPS
    return jump, jump / typ


# --------------------------------------------------------------------------- IO
def to_int16(x):
    return np.clip(np.round(np.asarray(x) * 32767.0), -32768, 32767).astype("<i2")


def write_wav(path, x, loop=False, sr=SR):
    """16-bit mono PCM WAV; loops get a 'smpl' chunk (forward loop over the whole file) so Godot's
    'detect loop from WAV' import picks them up."""
    pcm = to_int16(x).tobytes()
    n = len(pcm) // 2
    fmt = struct.pack("<HHIIHH", 1, 1, sr, sr * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
    if len(pcm) % 2:
        chunks += b"\x00"
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(round(1e9 / sr)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def read_wav(path):
    import wave
    with wave.open(path, "rb") as w:
        sr, n, ch, sw = w.getframerate(), w.getnframes(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(n)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr, ch, sw
