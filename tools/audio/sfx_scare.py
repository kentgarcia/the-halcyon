"""sfx_scare.py -- scare and dread one-shots: ceiling noises, distant door, knocks, impacts, blackout,
tinnitus, stinger, close whisper."""
import numpy as np

import dsp
import lib
from core import sfx
from dsp import SR, N, TWO_PI


# --------------------------------------------------------------------------- ceiling
@sfx("ceiling_creak")
def ceiling_creak(c):
    """something heavy shifting above the tiles: slow wood groan, a flexing metal creak, a shower of dust"""
    n, rng = c.n, c.rng
    v = c.variant
    y = np.zeros(n)
    # wood: low stick-slip groan whose pitch wanders
    if v == 1:
        fw = lambda tt: 72.0 + 52.0 * np.sin(np.pi * np.clip(tt / 1.5, 0, 1)) ** 1.2
    else:
        fw = lambda tt: 125.0 - 55.0 * np.clip(tt / 1.6, 0, 1) ** 0.9 + 12.0 * np.sin(TWO_PI * 2.3 * tt)
    dur_w = 1.55
    wood = lib.creak(rng, dur_w, fw, res=(170.0, 330.0, 640.0), q=5.5, jitter=0.16, rough=0.9, hiss=0.05)
    wood *= dsp.e_pts(len(wood), [(0, 0), (0.30, 0.9), (1.0, 1.0), (dur_w, 0)])
    dsp.put(y, wood, 0.10 if v == 1 else 0.05, 1.0)
    # metal: thinner creak starting later
    dur_m = 0.95
    fm = (lambda tt: 410.0 + 160.0 * (tt / dur_m)) if v == 1 else (lambda tt: 690.0 - 230.0 * (tt / dur_m) ** 0.8)
    metal = lib.creak(rng, dur_m, fm, res=(720.0, 1500.0, 2600.0), q=10.0, jitter=0.05, rough=0.4, hiss=0.04)
    metal *= dsp.e_pts(len(metal), [(0, 0), (0.18, 1.0), (0.6, 0.7), (dur_m, 0)])
    dsp.put(y, metal, 0.55 if v == 1 else 0.45, 0.55)
    # debris: tiny ticks, denser at first and thinning out
    for i in range(46):
        t0 = 0.28 + abs(rng.normal(0, 0.55)) * (1.0 if v == 1 else 1.1)
        if t0 > 1.9:
            continue
        m = N(0.012)
        tk = dsp.bp(dsp.white(m, rng), rng.uniform(1800, 4000), 8500, order=2) * dsp.e_exp(m, rng.uniform(0.0015, 0.004), 0.00005)
        dsp.put(y, tk / (np.max(np.abs(tk)) + 1e-9), t0, rng.uniform(0.05, 0.28))
    dust = dsp.hp(dsp.white(n, rng), 4000, order=2) * dsp.e_pts(n, [(0, 0), (0.4, 0.02), (0.8, 0.05), (1.7, 0.01), (2.0, 0)])
    y += dust / (np.std(dust) + 1e-9) * 0.015
    return dsp.reverb(y, "office", wet=0.18, dry=1.0, tail=0.0)[:n]


@sfx("ceiling_tile_shift")
def ceiling_tile_shift(c):
    """a ceiling tile lifted and slid aside: a dry fibreboard scrape with grit, then a soft set-down and falling dust"""
    n, rng = c.n, c.rng
    m = N(0.62)
    t = dsp.tgrid(m)
    a = dsp.bp(dsp.white(m, rng), 700, 3200, order=2)
    b = dsp.bp(dsp.white(m, rng), 1600, 5200, order=2)
    sl = dsp.smoothstep(t / 0.55)
    x = a / (np.std(a) + 1e-9) * (1 - sl) + b / (np.std(b) + 1e-9) * sl
    grit = np.clip(1.0 + 1.1 * dsp.lp(dsp.white(m, rng), 260, order=2) / 0.6, 0.0, 3.0)
    x = x * grit * dsp.e_pts(m, [(0, 0), (0.06, 0.8), (0.30, 1.0), (0.50, 0.7), (0.62, 0)])
    y = np.zeros(n)
    dsp.put(y, x / (np.std(x) + 1e-9) * 0.7, 0.04, 1.0)
    # lifting edge pops (little stick-slip catches)
    for t0 in (0.02, 0.17, 0.33):
        tk = lib.modal_hit([1100.0, 2300.0], [1.0, 0.5], [0.006, 0.004], 0.04, rng, tick=0.6, tick_band=(1500, 5000), tick_tau=0.002)
        dsp.put(y, tk, t0, 0.25)
    # set down
    sd = lib.thump(N(0.18), 140.0, 0.035) + 0.5 * lib.noise_burst(N(0.18), rng, 600, 2500, 0.03)
    dsp.put(y, sd, 0.72, 0.55)
    dust = lib.noise_burst(N(0.3), rng, 3500, 8000, 0.09) * 0.10
    dsp.put(y, dust, 0.74, 1.0)
    for i in range(10):
        tk = lib.noise_burst(N(0.01), rng, 2500, 8000, 0.002)
        dsp.put(y, tk, 0.78 + rng.uniform(0, 0.2), rng.uniform(0.04, 0.12))
    return dsp.reverb(y, "office", wet=0.16, dry=1.0, tail=0.0)[:n]


@sfx("distant_door_close")
def distant_door_close(c):
    """a door slamming far down a long corridor: dull thud, faint latch, long cavernous tail"""
    n, rng = c.n, c.rng
    m = N(0.45)
    thud = lib.thump(m, 78.0, 0.075) * 1.0
    wood = dsp.modal([170.0, 340.0, 560.0], [1.0, 0.5, 0.25], [0.06, 0.04, 0.025], m, rng=rng, atk=0.0006)
    latch = lib.modal_hit([1500.0, 2700.0], [1.0, 0.5], [0.02, 0.012], m, rng, tick=0.5, tick_band=(1500, 5000))
    x = thud * 0.9 + wood * 0.6 + latch * 0.10
    x = dsp.lp(x, 1100.0, order=3)
    y = np.zeros(n)
    dsp.put(y, x, 0.03, 1.0)
    out = dsp.reverb(y, "far", wet=1.3, dry=0.3, tail=0.0)
    out = dsp.lp(out, 1800.0, order=2)
    return out[:n]


# --------------------------------------------------------------------------- the knocks (the Greeter's rhythm tell)
# Both knock sounds are built from the SAME three knock hits and the same room, so only the rhythm differs
# (timbre/length can never leak which one is the 'irregular' one).
def _knocks(c, onsets):
    n = c.n
    rngk = dsp.rng_for("knock-set")          # shared by knock_slow and knock_irregular
    hits = [lib.knock_hit(rngk, panel_f=f, level=lv) for f, lv in ((214.0, 1.0), (206.0, 0.92), (221.0, 0.97))]
    y = np.zeros(n)
    for h, t0 in zip(hits, onsets):
        dsp.put(y, h, t0, 1.0)
    return dsp.reverb(y, "closet", wet=0.10, dry=1.0, tail=0.0)[:n]


@sfx("knock_slow")
def knock_slow(c):
    """three slow, evenly spaced knocks, exactly one second apart"""
    return _knocks(c, (0.30, 1.30, 2.30))


@sfx("knock_irregular")
def knock_irregular(c):
    """one knock, a long pause, then a quick double -- slightly off"""
    return _knocks(c, (0.22, 1.74, 1.92))


# --------------------------------------------------------------------------- impacts
@sfx("hit_thud")
def hit_thud(c):
    """muffled body impact plus a fast low sweep: not violent, disorienting"""
    n, rng = c.n, c.rng
    y = np.zeros(n)
    m = N(0.5)
    th = lib.thump(m, 68.0, 0.085) * 1.0
    nz = dsp.lp(dsp.white(m, rng), 320, order=2)
    nz = nz / (np.std(nz) + 1e-9) * dsp.e_exp(m, 0.04, 0.001)
    body = th / np.max(np.abs(th)) + 0.45 * nz / np.max(np.abs(nz))
    dsp.put(y, body, 0.02, 1.0)
    tt = dsp.tgrid(m)
    f = 300.0 * (45.0 / 300.0) ** np.clip(tt / 0.24, 0, 1)
    sw = np.sin(dsp.phase_of(f, m)) * dsp.e_exp(m, 0.13, 0.003)
    dsp.put(y, sw, 0.03, 0.55)
    air = dsp.bp(dsp.white(N(0.08), rng), 200, 1100, order=2) * np.hanning(N(0.08))
    dsp.put(y, air / (np.max(np.abs(air)) + 1e-9), 0.0, 0.18)
    y = dsp.lp(y, 650.0, order=2)
    return dsp.reverb(y, "closet", wet=0.25, dry=1.0, tail=0.0)[:n]


@sfx("blackout_whoomp")
def blackout_whoomp(c):
    """low impact, the world's sound draining away, and a tinnitus tone fading in and out"""
    n, rng = c.n, c.rng
    t = dsp.tgrid(n)
    y = np.zeros(n)
    m = N(1.2)
    th = lib.thump(m, 44.0, 0.28, f_drop=1.8)
    rum = dsp.lp(dsp.white(m, rng), 130, order=3)
    rum = rum / (np.std(rum) + 1e-9) * dsp.e_exp(m, 0.40, 0.004)
    tt = dsp.tgrid(m)
    sw = np.sin(dsp.phase_of(170.0 * (32.0 / 170.0) ** np.clip(tt / 0.55, 0, 1), m)) * dsp.e_exp(m, 0.3, 0.004)
    body = th / np.max(np.abs(th)) + 0.5 * rum / np.max(np.abs(rum)) + 0.4 * sw
    dsp.put(y, body, 0.02, 1.0)
    # the room tone being sucked away
    bed = dsp.bp(dsp.white(n, rng), 160, 1800, order=2)
    y += bed / (np.std(bed) + 1e-9) * 0.10 * dsp.e_pts(n, [(0, 0), (0.05, 1), (0.9, 0.25), (1.4, 0)])
    # tinnitus: two close partials, beating at ~28 Hz, rising out of the thump
    ring = np.sin(TWO_PI * 6200.0 * t) + 0.8 * np.sin(TWO_PI * 6228.0 * t + 1.0)
    renv = dsp.e_pts(n, [(0, 0), (0.12, 0), (0.45, 0.30), (1.0, 0.24), (2.4, 0.0)], power=1.0)
    renv *= 1.0 + 0.07 * np.sin(TWO_PI * 1.3 * t)
    y += ring * renv * 0.55
    return y


@sfx("tinnitus_ring")
def tinnitus_ring(c):
    """a high pure tone that fades slowly, with a faint shimmer"""
    n, rng = c.n, c.rng
    t = dsp.tgrid(n)
    f = 6800.0
    y = np.sin(TWO_PI * f * t) + 0.35 * np.sin(TWO_PI * f * 1.0042 * t + 0.7)
    env = dsp.e_pts(n, [(0, 0), (0.04, 1.0), (0.4, 0.80), (1.4, 0.38), (2.4, 0.10), (3.0, 0.0)])
    env *= 1.0 + 0.06 * np.sin(TWO_PI * 1.6 * t + 0.5)
    return y * env


@sfx("stinger_low")
def stinger_low(c):
    """low dissonant string-like swell that cuts off abruptly (used rarely)"""
    n, rng = c.n, c.rng
    c.fade_out_ms = 4.0                       # the cut is the point
    t = dsp.tgrid(n)
    swell_end = 2.86
    env = dsp.smoothstep(t / swell_end) ** 1.8
    env = np.where(t < swell_end, env, 0.0)
    notes = (73.42, 77.78, 103.83, 146.83, 155.56, 207.65)     # D2 Eb2 Ab2 D3 Eb3 Ab3: minor 2nds and a tritone
    amps = (1.0, 0.9, 0.7, 0.5, 0.45, 0.28)
    y = np.zeros(n)
    K = 26
    for f, a in zip(notes, amps):
        for det in (-0.0065, 0.0, 0.0071):
            vib = 1.0 + 0.0035 * np.sin(TWO_PI * rng.uniform(4.6, 5.6) * t + rng.uniform(0, 6.28)) * dsp.smoothstep((t - 0.8) / 1.2)
            fr = f * (1.0 + det) * vib
            h = 1.0 / np.arange(1, K + 1)
            y += a * dsp.harm_stack(fr, h, n, phases=rng.uniform(0, TWO_PI, K), fmax=9000.0)
    y /= np.std(y)
    # opening filter: dark -> brighter as the swell grows (cheap: crossfade between three lowpasses)
    lo, mid, hi = dsp.lp(y, 260, order=2), dsp.lp(y, 700, order=2), dsp.lp(y, 1900, order=2)
    k = np.clip(t / swell_end, 0, 1)
    y = lo * np.clip(1 - 2 * k, 0, 1) + mid * (1 - np.abs(2 * k - 1)) + hi * np.clip(2 * k - 1, 0, 1)
    bow = dsp.bp(dsp.white(n, rng), 1200, 3600, order=2)
    y = y + bow / (np.std(bow) + 1e-9) * 0.10 * env ** 1.3
    return y * env


@sfx("whisper_numbers")
def whisper_numbers(c):
    """a close, dry whisper counting numbers -- unintelligible -- and a breath at the end"""
    n, rng = c.n, c.rng
    y = np.zeros(n)
    plan = [("uh", "n"), ("oo", "t"), ("ee", "th"), ("ow", "f"), ("ay", "f"), ("ih", "s")]
    t = 0.22
    for i, (vw, cs) in enumerate(plan):
        syl = lib.whisper_syllable(rng, rng.uniform(0.17, 0.24), 1.0, vowel=vw, cons=cs, level=1.0 - 0.04 * i)
        dsp.put(y, syl, t, 1.0)
        t += len(syl) / SR + rng.uniform(0.15, 0.24)
        if i in (1, 3):
            t += 0.10
    m = N(0.65)
    br = dsp.bp(dsp.white(m, rng), 500, 5200, order=2)
    br = br / (np.std(br) + 1e-9) * dsp.e_ar(m, 0.22, 0.22)
    dsp.put(y, br, t + 0.05, 0.55)
    y = dsp.filt(y, lo=160.0, hi=7000.0, order=2)
    return y
