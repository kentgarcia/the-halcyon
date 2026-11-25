"""lib.py -- reusable sound-building blocks shared by several recipe modules."""
import numpy as np

import dsp
from dsp import SR, N, TWO_PI


# --------------------------------------------------------------------------- the secret-tell pop
def mic_pop_unit(rng, dur=0.2):
    """Unit-peak microphone plosive: ~80 Hz damped thump (wind blast on the diaphragm, slightly
    falling pitch) with a small low-mid 'puff' so it survives small speakers / a gentle high-pass."""
    n = N(dur)
    t = dsp.tgrid(n)
    f = 80.0 * (1.0 + 0.22 * np.exp(-t / 0.018))
    body = np.sin(dsp.phase_of(f, n, 0.3)) * np.exp(-t / 0.030) * dsp.smoothstep(t / 0.005)
    body += 0.35 * np.sin(dsp.phase_of(2.0 * f, n, 1.1)) * np.exp(-t / 0.018) * dsp.smoothstep(t / 0.004)
    puff = dsp.lp(dsp.white(n, rng), 500, order=2)
    puff *= np.exp(-t / 0.020) * dsp.smoothstep(t / 0.003)
    mid = dsp.bp(dsp.white(n, rng), 180, 1000, order=2) * np.exp(-t / 0.011) * dsp.smoothstep(t / 0.002)
    y = body + 0.35 * puff / (np.std(puff) + 1e-9) * 0.25 + 0.30 * mid / (np.std(mid) + 1e-9) * 0.08
    y = dsp.fade_edges(y, 2.0, 6.0)
    return y / np.max(np.abs(y))


# --------------------------------------------------------------------------- generic helpers
def noise_burst(n, rng, lo, hi, tau, atk=0.0004, order=2):
    """band-limited noise with exponential decay"""
    x = dsp.bp(dsp.white(n, rng), lo, hi, order=order)
    return x / (np.std(x) + 1e-9) * dsp.e_exp(n, tau, atk)


def thump(n, f0, tau, f_drop=1.3, rng=None, atk=0.001, phase0=0.5 * np.pi):
    """decaying low sine with a fast downward pitch settle (body of an impact)"""
    t = dsp.tgrid(n)
    f = f0 * (1.0 + (f_drop - 1.0) * np.exp(-t / 0.012))
    return np.sin(dsp.phase_of(f, n, phase0)) * dsp.e_exp(n, tau, atk)


def click(n, rng, f=3000.0, q=4.0, tau=0.002):
    """sharp transient with a resonant ring: a few-sample impulse through a resonator"""
    x = np.zeros(n)
    x[0] = 1.0
    x[1] = -0.6
    r = dsp.reso(np.pad(x, (0, 0)), f, q, phase="min")
    r = r * dsp.e_exp(n, tau, 0.00005) * 1.0
    return r / (np.max(np.abs(r)) + 1e-9)


def adsr_gate(n, a, d, s, r_start, r, sustain_level=0.7):
    """simple gate envelope in seconds (a attack, d decay to s level, release begins at r_start)"""
    pts = [(0.0, 0.0), (a, 1.0), (a + d, sustain_level), (r_start, sustain_level), (r_start + r, 0.0)]
    return dsp.e_pts(n, pts)


def bell_tone(freq, dur, rng, partials=None, decay=0.8, strike=0.002, shimmer=0.0):
    """inharmonic struck-bell tone.  partials: list of (ratio, amp, decay_mult)"""
    if partials is None:
        partials = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.65), (2.76, 0.35, 0.5), (5.4, 0.12, 0.3)]
    n = N(dur)
    fr = [freq * p[0] * (1.0 + shimmer * rng.uniform(-1, 1)) for p in partials]
    am = [p[1] for p in partials]
    ta = [decay * p[2] for p in partials]
    y = dsp.modal(fr, am, ta, n, rng=rng, atk=strike)
    return y


# --------------------------------------------------------------------------- modulation helpers
def periodic_mod(n, period_s, rng, mults, depths, base=1.0):
    """1 + sum d_i*sin(2*pi*(m_i/period)*t + phi_i): every LFO completes an integer number of cycles in
    `period_s`, so the result is seamless when the buffer loops."""
    t = dsp.tgrid(n)
    m = np.full(n, float(base))
    for k, d in zip(mults, depths):
        m += d * np.sin(TWO_PI * (k / period_s) * t + rng.uniform(0, TWO_PI))
    return m


# --------------------------------------------------------------------------- the fluorescent family
# 60 Hz mains hum partials (relative amplitudes): 120 Hz dominates like a real transformer/ballast
HUM_AMPS = np.array([0.75, 1.0, 0.5, 0.42, 0.16, 0.12, 0.07, 0.04, 0.03, 0.025, 0.02, 0.015, 0.012, 0.01, 0.008, 0.006])


def buzz_comb(n, rng, f0=120.0, kmax=26, period_s=None, slope=0.45, rolloff=2600.0, drift=0.18, flicker=0.06):
    """Fluorescent tube buzz: 120 Hz harmonic comb up to ~3 kHz with a nasal bump, near-aligned phases
    (so the 120 Hz pulse envelope stays 'buzzy') and slow per-harmonic amplitude drift. If period_s is
    given every modulator is an integer-cycle LFO so the result loops seamlessly (f0*period_s must be an
    integer-friendly multiple)."""
    t = dsp.tgrid(n)
    period_s = period_s or n / SR
    y = np.zeros(n)
    for k in range(1, kmax + 1):
        f = f0 * k
        a = k ** (-slope) / (1.0 + (f / rolloff) ** 6)
        a *= 10.0 ** ((4.0 / 20.0) / (1.0 + (0.7 * (f / 1100.0 - 1100.0 / f)) ** 2))
        if k == 1:
            a *= 0.6
        dep = drift * min(1.0, 0.25 + 0.15 * k)
        m = 1.0 + dep * np.sin(TWO_PI * (rng.integers(1, 9) / period_s) * t + rng.uniform(0, TWO_PI))
        y += a * np.clip(m, 0.05, None) * np.sin(TWO_PI * f * t + rng.uniform(-0.6, 0.6))
    # global unstable-tube flicker
    y *= periodic_mod(n, period_s, rng, [3, 6, 13], [flicker, flicker * 0.6, flicker * 0.5])
    return y


def crackle_events(n, rng, rate, mean_amp=0.2, cluster_p=0.3, lo=1500.0, hi=7000.0, circular=True):
    """sparse irregular electrical crackle (poisson-ish clicks, some clustered)"""
    buf = np.zeros(n)
    T = n / SR
    k = rng.poisson(rate * T)
    for _ in range(k):
        t0 = rng.uniform(0.02, T - 0.06)          # keep clicks away from the loop seam
        reps = 1 + (rng.integers(2, 5) if rng.random() < cluster_p else 0)
        for j in range(reps):
            a = float(np.clip(rng.exponential(mean_amp), 0.04, 0.9))
            ln = N(0.012)
            c = np.zeros(ln)
            c[0], c[1], c[2] = 1.0, -0.8, 0.4
            c = dsp.reso(c, rng.uniform(lo, hi), rng.uniform(3, 8), phase="min") * dsp.e_exp(ln, rng.uniform(0.0015, 0.004), 0.00005)
            c /= (np.max(np.abs(c)) + 1e-9)
            dsp.put(buf, c, t0 + j * rng.uniform(0.003, 0.012), a * rng.choice([-1.0, 1.0]), circular=circular)
    return buf


# --------------------------------------------------------------------------- friction: creaks and squeaks
def creak(rng, dur, f_curve, res=(900.0, 1700.0, 3000.0), q=7.0, jitter=0.06, rough=0.5, amp_env=None, hiss=0.05):
    """stick-slip friction (door hinge, wood, cable): jittery sawtooth pulse train at f_curve(t)
    through a few structural resonances; random drop-outs make it creak rather than whine.
    f_curve: array (per sample) or callable of t."""
    n = N(dur)
    t = dsp.tgrid(n)
    f = f_curve(t) if callable(f_curve) else np.broadcast_to(np.asarray(f_curve, float), (n,))
    jn = dsp.lp(dsp.white(n, rng), 60.0, order=2)
    jn = jn / (np.std(jn) + 1e-9)
    ph = np.cumsum(f * (1.0 + jitter * jn)) / SR
    saw = 2.0 * (ph % 1.0) - 1.0
    # asymmetric stick/slip shape: sharpen the slip edge
    saw = np.sign(saw) * np.abs(saw) ** (1.0 + rough)
    x = saw + hiss * dsp.white(n, rng)
    x = dsp.formants(x, [(res[0], q, 1.0), (res[1], q, 0.7), (res[2], q * 0.8, 0.4)], phase="zero")
    # stick/slip drop-outs
    g = dsp.lp(dsp.white(n, rng), 9.0, order=2)
    g = g / (np.std(g) + 1e-9)
    gate = dsp.smoothstep((g + 0.9) * 1.6)
    env = gate if amp_env is None else gate * amp_env
    return x * env / (np.std(x) + 1e-9)


# --------------------------------------------------------------------------- whispers
_VOWELS = {
    "ah": (730, 1090, 2440), "ee": (270, 2290, 3010), "oo": (300, 870, 2240), "eh": (530, 1840, 2480),
    "ih": (390, 1990, 2550), "ow": (570, 840, 2410), "uh": (520, 1190, 2390), "ay": (550, 1900, 2500),
}


def whisper_syllable(rng, dur, fscale=1.0, vowel=None, cons=None, level=1.0):
    """one whispered syllable: aspirated noise through vowel formants, optional leading consonant noise."""
    vowel = vowel or rng.choice(list(_VOWELS))
    f1, f2, f3 = (f * fscale for f in _VOWELS[vowel])
    n = N(dur)
    src = dsp.white(n, rng)
    v = dsp.formants(src, [(f1, 5.5, 1.0), (f2, 7.0, 0.65), (f3, 8.0, 0.35)])
    v = v / (np.std(v) + 1e-9)
    env = np.hanning(n) ** 0.8
    v = v * env
    out = v
    if cons is None:
        cons = rng.choice(["s", "f", "t", "k", "n", "th", "none"])
    if cons != "none":
        cn = N(rng.uniform(0.04, 0.085))
        if cons in ("s", "th", "f"):
            lo_hi = {"s": (4200, 7200), "th": (2800, 6500), "f": (1800, 6000)}[cons]
            c = dsp.bp(dsp.white(cn, rng), lo_hi[0] * fscale, lo_hi[1], order=2)
            c = c / (np.std(c) + 1e-9) * np.hanning(cn) * 0.34
        elif cons in ("t", "k"):
            c = dsp.hp(dsp.white(cn, rng), 1800 if cons == "t" else 900, order=2)
            c = c / (np.std(c) + 1e-9) * dsp.e_exp(cn, 0.012, 0.0003) * 0.7
        else:  # n -- low murmur
            c = dsp.lp(dsp.white(cn, rng), 500, order=2)
            c = c / (np.std(c) + 1e-9) * np.hanning(cn) * 0.4
        out = np.concatenate([c, v * 1.0])
    return out * level


def whisper_phrase(rng, fscale=1.0, level=1.0, n_words=None, rate=1.0):
    """a few whispered 'numbers' (1-2 syllables each) separated by short gaps -> array"""
    n_words = n_words or int(rng.integers(2, 5))
    parts = []
    for w in range(n_words):
        for s in range(int(rng.integers(1, 3))):
            parts.append(whisper_syllable(rng, rng.uniform(0.11, 0.24) / rate, fscale, level=level * rng.uniform(0.7, 1.0)))
        parts.append(np.zeros(N(rng.uniform(0.07, 0.28) / rate)))
    return np.concatenate(parts)


def soft_piano(freq, dur, rng, bright=0.5, hammer=0.4, decay=1.0):
    """piano-ish tone: slightly inharmonic decaying partials + a soft hammer thump."""
    n = N(dur)
    ks = np.arange(1, 9)
    B = 0.0004
    fr = freq * ks * np.sqrt(1 + B * ks ** 2)
    am = ks ** (-1.1) * (1.0 + 0.0 * ks)
    am[1:] *= bright * 2
    ta = decay * 2.4 / (1.0 + 0.55 * (ks - 1))
    ok = fr < 0.45 * SR
    y = dsp.modal(fr[ok], am[ok], ta[ok], n, rng=rng, atk=0.004)
    th = dsp.lp(dsp.white(n, rng), 700.0, order=2) * dsp.e_exp(n, 0.012, 0.0008)
    return y + hammer * 0.12 * th / (np.std(th) + 1e-9) * np.std(y[: N(0.05)] + 1e-9)


# --------------------------------------------------------------------------- struck things, rustles, beeps
def modal_hit(freqs, amps, taus, dur, rng, tick=0.0, tick_band=(2000.0, 8000.0), tick_tau=0.003, atk=0.0002, detune=0.0):
    """struck object: decaying partials (+ optional broadband contact tick). detune: random +/- fraction per partial"""
    n = N(dur)
    fr = [f * (1.0 + detune * rng.uniform(-1, 1)) for f in freqs]
    y = dsp.modal(fr, amps, taus, n, rng=rng, atk=atk)
    if tick > 0:
        tk = dsp.bp(dsp.white(n, rng), tick_band[0], tick_band[1], order=2) * dsp.e_exp(n, tick_tau, 0.00005)
        y = y + tick * np.max(np.abs(y)) * tk / (np.max(np.abs(tk)) + 1e-9)
    return y


def rustle(dur, rng, lo=1500.0, hi=7000.0, flutter_hz=70.0, depth=1.0, shape_pow=0.5):
    """crinkly noise (paper / cloth / plastic): band noise with random flutter, hann-shaped"""
    n = N(dur)
    r = dsp.bp(dsp.white(n, rng), lo, hi, order=2)
    fl = dsp.lp(dsp.white(n, rng), flutter_hz, order=2)
    fl = fl / (np.std(fl) + 1e-9)
    env = np.clip(1.0 + depth * fl, 0.0, 3.5)
    return r / (np.std(r) + 1e-9) * env * (np.hanning(n) ** shape_pow)


def beep(freq, dur, kind="square", atk=0.002, rel=0.004, harmonics=6):
    """short electronic beep with tiny attack/release (kind: square | sine)"""
    n = N(dur)
    ph = dsp.phase_of(freq, n)
    if kind == "square":
        y = sum(np.sin((2 * k + 1) * ph) / (2 * k + 1) for k in range(harmonics) if (2 * k + 1) * (freq if np.isscalar(freq) else np.max(freq)) < 0.45 * SR)
    else:
        y = np.sin(ph)
    env = dsp.e_pts(n, [(0, 0), (atk, 1), (max(dur - rel, atk + 1e-4), 1), (dur, 0)])
    return y * env


def glide_tone(f_a, f_b, dur, curve=1.0, kind="sine"):
    """exponential-ish glide between two frequencies"""
    n = N(dur)
    u = (np.arange(n) / max(n - 1, 1)) ** curve
    f = f_a * (f_b / f_a) ** u
    ph = dsp.phase_of(f, n)
    if kind == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def knock_hit(rng, panel_f=215.0, level=1.0, dur=0.42):
    """a knuckle knock on a hollow wooden door: contact tick + panel resonance + frame thump"""
    n = N(dur)
    tick = dsp.bp(dsp.white(n, rng), 1200, 4200, order=2) * dsp.e_exp(n, 0.0035, 0.0001)
    tick = tick / (np.max(np.abs(tick)) + 1e-9) * 0.55
    panel = dsp.modal([panel_f, panel_f * 1.93, panel_f * 3.05, panel_f * 4.4], [1.0, 0.55, 0.30, 0.14], [0.085, 0.055, 0.032, 0.02], n, rng=rng, atk=0.0004)
    thump = lib_thump(n, 88.0, 0.060)
    y = panel + 0.55 * thump + tick
    return level * y / (np.max(np.abs(y)) + 1e-9)


def lib_thump(n, f0, tau):
    return thump(n, f0, tau, f_drop=1.25, atk=0.0008)
