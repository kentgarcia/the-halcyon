"""sfx_entity.py -- gameplay tells and entity signatures: hum_drop / hum_rise, wrench, alarm, whistle,
bells, housekeeping cart, queue chime."""
import numpy as np

import dsp
import lib
from core import sfx
from dsp import SR, N, TWO_PI


# --------------------------------------------------------------------------- the Hum's tells
def _hum_glide(c, direction):
    """direction -1: hum drops a half-step and thins (HOLDS tell); +1: rises a half-step and swells (inverted tell).
    Starts from exactly the bed's harmonic recipe (60 Hz base) so it blends with amb_hum_bed."""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    K = len(lib.HUM_AMPS)
    h = np.arange(1, K + 1)[:, None].astype(float)
    base = lib.HUM_AMPS[:, None]
    if direction < 0:
        s = dsp.smoothstep((t - 0.15) / 1.9)                    # glide 0.15 s .. 2.05 s
        g = 1.0 - 0.52 * s                                       # level sags
        m = np.exp(-0.5 * np.clip(h - 2.0, 0.0, None) * s[None, :])   # harmonics >= 3 thin out
        twin_a = 0.30 * (1.0 - 0.7 * s)
        twin_det = 0.0021
        whine_a = 0.020 * (1.0 - s)
        floor = 1.0 - 0.85 * s
    else:
        s = dsp.smoothstep((t - 0.25) / 1.9)                    # glide 0.25 s .. 2.15 s
        g = 0.52 + 0.48 * s ** 1.4                               # level swells
        g = g * dsp.e_pts(n, [(0.0, 1.0), (T - 0.38, 1.0), (T, 0.55)])
        m = np.exp(0.20 * (h - 1.0) * s[None, :])                # brightens: upper partials grow
        twin_a = 0.16 + 0.55 * s                                 # strain: beating gets stronger...
        twin_det = 0.0021 + 0.020 * s                            # ...and faster
        whine_a = 0.012 + 0.055 * s
        floor = 0.55 + 0.9 * s
    ratio = 2.0 ** (direction * s / 12.0)
    f0 = 60.0 * ratio
    ph0 = rng.uniform(0, TWO_PI, K)
    amps = base * m
    y = dsp.harm_stack(f0, amps, n, phases=ph0)
    # twin partials 1-4: detuned copies make it beat like the bed (faster/stronger when straining)
    ph = dsp.phase_of(f0 * (1.0 + twin_det), n, rng.uniform(0, TWO_PI))
    for k, a in ((1, 0.75), (2, 1.0), (3, 0.5), (4, 0.42)):
        y += a * twin_a * np.sin(k * ph + rng.uniform(0, TWO_PI))
    # a thin ballast-whine partial high up: the glide is easy to hear in the 1-2 kHz range
    y += whine_a * np.sin(dsp.phase_of(f0 * 32.0, n, rng.uniform(0, TWO_PI))) * 4.0
    y = y / 1.35 * g
    air = dsp.spectral_noise(n, rng, dsp.make_mag(lo=80, hi=1300, order=2)) * dsp.db2lin(-27.0) * floor
    return y + air


@sfx("hum_drop")
def hum_drop(c):
    return _hum_glide(c, -1)


@sfx("hum_rise")
def hum_rise(c):
    return _hum_glide(c, +1)


# --------------------------------------------------------------------------- Foreman
@sfx("wrench_scrape_loop")
def wrench_scrape_loop(c):
    """heavy pipe wrench dragged on concrete: rhythmic stick-slip scrape (one stride every 0.5 s),
    ringing iron, low rumble and a clink every second"""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    stride = 0.5
    # swell per stride: slow rise, quick fall (heavy object dragged forward)
    ph = (t / stride) % 1.0
    env = np.sin(np.pi * np.clip(ph, 0, 1) ** 0.7) ** 1.5
    env = 0.18 + 0.82 * env
    base = dsp.spectral_noise(n, rng, dsp.make_mag(lo=350, hi=4200, order=2))
    grit = dsp.spectral_noise(n, rng, dsp.make_mag(lo=30, hi=95, order=2))
    grit = np.clip(1.0 + 0.85 * grit, 0.0, 3.0)
    scrape = base * grit * env
    ring = dsp.spectral_noise(n, rng, lambda f: sum(1.0 / np.sqrt(1.0 + (28.0 * (np.maximum(f, 1e-6) / f0 - f0 / np.maximum(f, 1e-6))) ** 2) for f0 in (1390.0, 2910.0)))
    ring *= env * grit
    rumble = dsp.spectral_noise(n, rng, dsp.make_mag(lo=60, hi=260, order=3)) * env ** 1.5
    body = scrape / np.std(scrape) + 0.35 * ring / (np.std(ring) + 1e-9) + 0.55 * rumble / np.std(rumble)
    clink = np.zeros(n)
    for i in range(3):
        f = 1180.0 * (1.0 + 0.012 * (i - 1))
        hit = lib.modal_hit([f, f * 1.87, f * 2.94, f * 4.3], [1.0, 0.7, 0.45, 0.25], [0.14, 0.09, 0.055, 0.03], 0.5, rng, tick=0.5, tick_band=(3000, 9000))
        dsp.put(clink, hit, 0.12 + i * 1.0, 1.0, circular=True)
    y = body / np.std(body) * 0.8 + clink * 2.4 / (np.max(np.abs(clink)) + 1e-9) * 1.2
    return dsp.reverb(y, "concrete", wet=0.18, dry=1.0, circular=True)


# --------------------------------------------------------------------------- B3 alarm
@sfx("alarm_loop")
def alarm_loop(c):
    """fire-alarm bell: a motorised clapper striking a steel gong ~7.5 times a second, harsh, muffled by distance"""
    n, rng, T = c.n, c.rng, c.dur
    y = np.zeros(n)
    strikes = 30
    f0 = 1310.0
    parts = [(1.0, 1.0, 0.20), (1.53, 0.8, 0.16), (2.19, 0.6, 0.12), (2.97, 0.5, 0.09), (3.84, 0.35, 0.07), (5.3, 0.2, 0.05)]
    for i in range(strikes):
        t0 = i * T / strikes + rng.uniform(-0.0008, 0.0008)
        amp = (1.0 if i % 2 == 0 else 0.84) * rng.uniform(0.93, 1.07)
        hit = lib.modal_hit([f0 * p[0] * (1.0 + 0.002 * rng.uniform(-1, 1)) for p in parts], [p[1] for p in parts], [p[2] for p in parts], 0.45, rng, tick=0.7, tick_band=(2500, 7000), tick_tau=0.002)
        dsp.put(y, hit, t0 % T, amp, circular=True)
    y = dsp.filt(y, lo=300.0, hi=4800.0, order=2, circular=True)
    return dsp.reverb(y, "corridor", wet=0.22, dry=1.0, circular=True)


# --------------------------------------------------------------------------- B2 lifeguard
@sfx("whistle_blast")
def whistle_blast(c):
    """pea whistle in a tiled hall. v1: bright with long echo; v2: a little drier and lower"""
    n, rng = c.n, c.rng
    v2 = c.variant == 2
    f0 = 2450.0 if v2 else 2800.0
    blast = 0.62 if v2 else 0.78
    m = N(blast + 0.1)
    t = dsp.tgrid(m)
    scoop = 1.0 - 0.07 * np.exp(-t / 0.05)
    wobble = 1.0 + 0.006 * np.sin(TWO_PI * 4.3 * t + rng.uniform(0, 6.28)) + 0.003 * np.sin(TWO_PI * 11.0 * t)
    droop = 1.0 - 0.04 * dsp.smoothstep((t - (blast - 0.14)) / 0.14)
    f = f0 * scoop * wobble * droop
    ph = dsp.phase_of(f, m)
    trill = 1.0 + 0.34 * np.sin(TWO_PI * (31.0 if not v2 else 27.0) * t + rng.uniform(0, 6.28))   # the pea
    tone = (np.sin(ph) + 0.20 * np.sin(2 * ph + 0.4) + 0.07 * np.sin(3 * ph + 1.0)) * trill
    breath = dsp.bp(dsp.white(m, rng), f0 - 700, f0 + 900, order=2)
    breath = breath / (np.std(breath) + 1e-9) * 0.30 * (1.0 + 0.4 * np.sin(TWO_PI * 31.0 * t))
    env = dsp.e_pts(m, [(0, 0), (0.025, 1), (blast - 0.12, 0.92), (blast, 0.0)])
    sig = (tone * 0.75 + breath) * env
    y = np.zeros(n)
    y[:min(m, n)] = sig[:n]
    wet = 0.18 if v2 else 0.55
    out = dsp.reverb(y, "tile", wet=wet, dry=1.0, tail=0.0)
    return out[:n]


@sfx("water_ripple")
def water_ripple(c):
    """one slow ripple lapping at a pool wall, plus a tiny plip and a smaller second lap"""
    n, rng = c.n, c.rng
    y = np.zeros(n)

    def lap(dur, atk, rel, lo, hi):
        m = N(dur)
        x = dsp.bp(dsp.white(m, rng), lo, hi, order=2)
        x = x / (np.std(x) + 1e-9) * dsp.e_ar(m, atk, rel)
        return dsp.fade_out_tail(x, 200)

    dsp.put(y, lap(1.3, 0.50, 0.28, 260, 1200), 0.05, 1.0)
    dsp.put(y, lap(0.9, 0.30, 0.20, 300, 1500), 1.15, 0.45)
    m = N(0.15)
    tt = dsp.tgrid(m)
    plip = np.sin(dsp.phase_of(1500 * (1 + 1.2 * (1 - np.exp(-tt / 0.012))), m)) * dsp.e_exp(m, 0.03, 0.001)
    dsp.put(y, plip, 0.62, 0.25)
    out = dsp.reverb(y, "tile", wet=0.5, dry=1.0, tail=0.0)
    return out[:n]


# --------------------------------------------------------------------------- bells
@sfx("bell_ding")
def bell_ding(c):
    """brass reception-desk bell: bright strike, ringing dome partials with shimmer"""
    n, rng = c.n, c.rng
    f0 = 2100.0
    freqs, amps, taus = [], [], []
    for ratio, a, d in ((1.0, 1.0, 1.35), (2.35, 0.55, 0.90), (3.9, 0.30, 0.55), (5.6, 0.12, 0.30)):
        for det, wa in ((0.0, 1.0), (0.0045, 0.55)):          # close twin partial -> the bell's shimmer
            freqs.append(f0 * ratio * (1.0 + det))
            amps.append(a * wa)
            taus.append(d)
    y = dsp.modal(freqs, amps, taus, n, rng=rng, atk=0.0003)
    tk = dsp.bp(dsp.white(n, rng), 3500, 9000, order=2) * dsp.e_exp(n, 0.004, 0.00005)
    y = y / np.max(np.abs(y)) + 0.35 * tk / (np.max(np.abs(tk)) + 1e-9)
    return dsp.reverb(y, "office", wet=0.12, dry=1.0, tail=0.0)[:n]


@sfx("greeter_bell")
def greeter_bell(c):
    """small brass hand-bell, two polite dings"""
    n, rng = c.n, c.rng
    y = np.zeros(n)
    for t0, f0, a in ((0.02, 1560.0, 1.0), (0.36, 1500.0, 0.80)):
        freqs, amps, taus = [], [], []
        for ratio, am, d in ((1.0, 1.0, 0.85), (2.02, 0.55, 0.50), (2.93, 0.30, 0.30), (4.15, 0.14, 0.18)):
            for det, wa in ((0.0, 1.0), (0.004, 0.45)):
                freqs.append(f0 * ratio * (1.0 + det))
                amps.append(am * wa)
                taus.append(d)
        ding = dsp.modal(freqs, amps, taus, N(1.1), rng=rng, atk=0.0004)
        tk = dsp.bp(dsp.white(N(1.1), rng), 3000, 8000, order=2) * dsp.e_exp(N(1.1), 0.003, 0.00005)
        ding = ding / np.max(np.abs(ding)) + 0.25 * tk / (np.max(np.abs(tk)) + 1e-9)
        dsp.put(y, ding, t0, a)
    return dsp.reverb(y, "office", wet=0.15, dry=1.0, tail=0.0)[:n]


@sfx("queue_chime")
def queue_chime(c):
    """now-serving: two soft electronic notes (rising fourth) then a number board flipping"""
    n, rng = c.n, c.rng
    y = np.zeros(n)
    for t0, f, a in ((0.02, 740.0, 1.0), (0.30, 988.0, 0.9)):
        m = N(0.75)
        tt = dsp.tgrid(m)
        mod = np.sin(TWO_PI * f * 2.0 * tt) * 0.9 * np.exp(-tt / 0.08)       # small FM for an electronic bell colour
        note = np.sin(TWO_PI * f * tt + mod) + 0.12 * np.sin(TWO_PI * f * 3 * tt)
        note *= dsp.e_exp(m, 0.28, 0.004)
        dsp.put(y, note, t0, a)
    # number board: a flurry of split-flap clacks
    t = 0.66
    gap = 0.052
    for i in range(8):
        m = N(0.03)
        cl = lib.modal_hit([2300 * (1 + 0.1 * rng.uniform(-1, 1)), 780.0], [1.0, 0.6], [0.006, 0.009], 0.03, rng, tick=0.6, tick_band=(2500, 7000), tick_tau=0.0015)
        dsp.put(y, cl, t, 0.85 * (0.96 ** i) * rng.uniform(0.8, 1.0))
        t += gap * (1.0 + 0.04 * i) * rng.uniform(0.88, 1.12)
    return dsp.reverb(y, "office", wet=0.12, dry=1.0, tail=0.0)[:n]


# --------------------------------------------------------------------------- Housekeeping
def _squeak(rng, dur, f_a, f_b, amp_shape=None):
    """one wheel squeak: a tight resonant tonal chirp with friction grit"""
    f = lambda tt: f_a + (f_b - f_a) * np.sin(np.pi * np.clip(tt / dur, 0, 1)) ** 1.0 * 0.0 + (f_b - f_a) * (tt / dur)
    x = lib.creak(rng, dur, f, res=(f_a * 1.1, f_a * 2.0, f_a * 3.1), q=22.0, jitter=0.012, rough=0.15, hiss=0.12)
    env = np.sin(np.pi * np.linspace(0, 1, len(x))) ** 0.8 if amp_shape is None else amp_shape
    return x * env


@sfx("cart_squeak_loop")
def cart_squeak_loop(c):
    """linen cart: one wheel squeaks once per revolution (4 per 2 s), rubber rolling on carpet, a couple of rattles"""
    n, rng, T = c.n, c.rng, c.dur
    roll = dsp.spectral_noise(n, rng, dsp.make_mag(lo=50, hi=650, order=2))
    roll *= lib.periodic_mod(n, T, rng, [4, 8, 2], [0.28, 0.12, 0.10])
    fabric = dsp.spectral_noise(n, rng, dsp.make_mag(lo=1800, hi=6500, order=2)) * 0.10
    y = roll / np.std(roll) * 0.55 + fabric / (np.std(fabric) + 1e-9) * 0.05
    sq = np.zeros(n)
    for i in range(4):
        dur = 0.27
        s = _squeak(rng, dur, 1180.0 * (1.0 + 0.02 * (i % 2)), 1530.0 * (1.0 + 0.015 * (i % 2)))
        s = s / (np.max(np.abs(s)) + 1e-9)
        dsp.put(sq, s, 0.10 + i * 0.5, 1.0 - 0.12 * (i % 2), circular=True)
    for t0, f in ((0.62, 140.0), (1.45, 120.0)):       # frame rattle when the wheel bumps a seam
        th = lib.thump(N(0.12), f, 0.035)
        th += 0.4 * lib.modal_hit([900.0, 1700.0], [1.0, 0.6], [0.03, 0.02], 0.12, rng)
        dsp.put(y, th, t0, 0.22, circular=True)
    return y + sq * 0.85


@sfx("cart_stop")
def cart_stop(c):
    """the wheel's squeak dies away as the cart rolls to a halt, then a small bump"""
    n, rng = c.n, c.rng
    y = np.zeros(n)
    dur = 0.55
    f = lambda tt: 1500.0 - 520.0 * (tt / dur) ** 0.8
    s = lib.creak(rng, dur, f, res=(1350.0, 2500.0, 3700.0), q=20.0, jitter=0.02, rough=0.2, hiss=0.12)
    s *= dsp.e_pts(len(s), [(0, 0), (0.05, 1), (0.30, 0.55), (dur, 0.0)])
    dsp.put(y, s / (np.max(np.abs(s)) + 1e-9), 0.04, 1.0)
    roll = dsp.lp(dsp.white(n, rng), 600, order=2)
    roll = roll / (np.std(roll) + 1e-9) * dsp.e_pts(n, [(0, 0.25), (0.4, 0.2), (0.75, 0.0)]) * 0.35
    y += roll
    bump = lib.thump(N(0.25), 95.0, 0.05) + 0.3 * lib.modal_hit([1100.0, 1900.0], [1.0, 0.5], [0.03, 0.02], 0.25, rng)
    dsp.put(y, bump, 0.62, 0.7)
    return y
