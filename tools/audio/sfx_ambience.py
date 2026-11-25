"""sfx_ambience.py -- seamless ambience / dread loops (hum bed, buzz, drones, rooms) and the elevator hum.

Loop strategy: tonal parts use frequencies that are integer multiples of 1/duration, noise parts are
synthesised directly as periodic spectra (`spectral_noise`), events and reverbs wrap around
(`put(..., circular=True)`, `reverb(..., circular=True)`), and every LFO completes whole cycles.
"""
import numpy as np

import dsp
import lib
from core import sfx
from dsp import SR, N, TWO_PI


def _sines(t, rng, parts):
    """parts: [(freq, amp)] -> sum of sines with random start phase"""
    y = np.zeros(len(t))
    for f, a in parts:
        y += a * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
    return y


# --------------------------------------------------------------------------- THE signature: hum bed
@sfx("amb_hum_bed")
def amb_hum_bed(c):
    """60 Hz mains hum + harmonics (120 dominant), each with a slightly detuned twin so it beats slowly,
    slow 'voltage wander', and a very quiet air-handling noise floor. Dull, constant, institutional."""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    # (freq, amp, twin_freq, twin_amp): every frequency is a multiple of 1/8 Hz -> exact cycles in 8 s
    parts = [(60.0, 0.75, 60.25, 0.30), (120.0, 1.0, 120.375, 0.34), (180.0, 0.50, 180.125, 0.20),
             (240.0, 0.42, 240.5, 0.16), (300.0, 0.16, None, 0), (360.0, 0.12, None, 0), (420.0, 0.07, None, 0),
             (480.0, 0.04, None, 0)]
    hum = np.zeros(n)
    for f, a, f2, a2 in parts:
        wander = lib.periodic_mod(n, T, rng, [1, 2, 3, 4], [0.05, 0.035, 0.025, 0.02])
        hum += a * wander * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
        if f2:
            hum += a2 * np.sin(TWO_PI * f2 * t + rng.uniform(0, TWO_PI))
    hum /= np.std(hum)
    # air handling: dull band-limited noise that 'breathes' very slowly
    mag = lambda f: dsp.make_mag(lo=80, hi=1300, order=2)(f) * (250.0 / np.maximum(f, 250.0)) ** 0.5
    air = dsp.spectral_noise(n, rng, mag)
    air *= lib.periodic_mod(n, T, rng, [1, 2], [0.22, 0.10])
    # faint room-air hiss way up top
    hiss = dsp.spectral_noise(n, rng, dsp.make_mag(lo=2500, hi=6500, order=2))
    return hum + air * dsp.db2lin(-27.0) + hiss * dsp.db2lin(-52.0)


# --------------------------------------------------------------------------- positional tube buzz
@sfx("amb_buzz_cell")
def amb_buzz_cell(c):
    """One fluorescent tube: 120 Hz buzz comb up to ~3 kHz, per-harmonic drift, tiny irregular crackle,
    a thin ballast whine and arc hiss. Irritating but bearable, clearly brighter than the bed."""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    comb = lib.buzz_comb(n, rng, f0=120.0, kmax=26, period_s=T)
    comb /= np.std(comb)
    # ballast whine: thin tone around 4.8 kHz with a little periodic wobble (all LFOs integer cycles in 4 s)
    wob = 0.0035 * np.sin(TWO_PI * 0.5 * t + rng.uniform(0, 6.28)) + 0.0015 * np.sin(TWO_PI * 1.75 * t + rng.uniform(0, 6.28))
    whine = np.sin(np.cumsum(TWO_PI * 4800.0 * (1.0 + wob)) / SR)
    whine *= lib.periodic_mod(n, T, rng, [1, 3], [0.25, 0.15])
    # arc hiss
    arc = dsp.spectral_noise(n, rng, dsp.make_mag(lo=700, hi=3600, order=2))
    arc *= np.clip(lib.periodic_mod(n, T, rng, [5, 9, 14], [0.4, 0.25, 0.2]), 0.1, None)
    crk = lib.crackle_events(n, rng, rate=4.0, mean_amp=0.9)
    y = comb + whine * dsp.db2lin(-30.0) + arc * dsp.db2lin(-25.0) + crk * 1.2
    return y


# --------------------------------------------------------------------------- dread layer
@sfx("amb_dark_pressure")
def amb_dark_pressure(c):
    """pressure tone for dark areas: lowpassed noise and a soft sub rumble, no melody"""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    low = dsp.spectral_noise(n, rng, lambda f: dsp.make_mag(lo=18, hi=150, order=3)(f) * (1.0 + 1.4 * np.exp(-((f - 55.0) / 22.0) ** 2)))
    low *= lib.periodic_mod(n, T, rng, [1, 2], [0.22, 0.12])
    sub = np.sin(TWO_PI * 38.0 * t + rng.uniform(0, 6.28)) * lib.periodic_mod(n, T, rng, [1, 2, 3], [0.22, 0.12, 0.08])
    sub += 0.28 * np.sin(TWO_PI * 57.0 * t + rng.uniform(0, 6.28)) * lib.periodic_mod(n, T, rng, [2, 3], [0.25, 0.15])
    air = dsp.spectral_noise(n, rng, dsp.make_mag(lo=250, hi=900, order=2))
    air *= np.clip(lib.periodic_mod(n, T, rng, [1, 3], [0.5, 0.2]), 0.0, None)
    return 1.0 * low + 0.85 * sub + 0.07 * air


@sfx("amb_dread_drone")
def amb_dread_drone(c):
    """sub-bass drone: detuned partials that beat slowly, slightly dissonant (minor 2nd + tritone), no rhythm"""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    # all frequencies are multiples of 1/12 Hz
    parts = [(41.0, 1.0), (41.25, 0.75), (43.5, 0.60), (43.75, 0.45), (58.0, 0.50), (58.333333333, 0.35),
             (82.5, 0.32), (83.0, 0.22), (116.0, 0.16), (174.0, 0.07)]
    y = np.zeros(n)
    for f, a in parts:
        # snap to a multiple of 1/T so it is exactly periodic
        f = round(f * T) / T
        y += a * np.sin(TWO_PI * f * t + rng.uniform(0, 6.28)) * lib.periodic_mod(n, T, rng, [1, 2, 3], [0.30, 0.15, 0.10])
    y /= np.std(y)
    y = np.tanh(1.7 * y)                       # growl: intermod products stay periodic
    y += 0.12 * dsp.spectral_noise(n, rng, dsp.make_mag(lo=20, hi=130, order=3))
    return y


@sfx("amb_heartbeat")
def amb_heartbeat(c):
    """one lub-dub cycle at 60 bpm, muffled; tails wrap into the next cycle"""
    n, rng = c.n, c.rng
    y = np.zeros(n)

    def beat(f0, tau, noise_a, length=0.45):
        m = N(length)
        th = lib.thump(m, f0, tau, f_drop=1.55, atk=0.006)
        nz = dsp.lp(dsp.white(m, rng), 180, order=2) * dsp.e_exp(m, tau * 0.8, 0.004)
        nz = nz / (np.std(nz) + 1e-9) * np.std(th)
        return th + noise_a * nz

    dsp.put(y, beat(52.0, 0.075, 0.45), 0.040, 1.0, circular=True)
    dsp.put(y, beat(66.0, 0.060, 0.40), 0.355, 0.68, circular=True)
    y = dsp.lp(y, 150.0, order=3, circular=True)
    return y


# --------------------------------------------------------------------------- places
@sfx("amb_boiler_rumble")
def amb_boiler_rumble(c):
    """furnace rumble, motor hum, thermal pipe ticks, a couple of hollow knocks and distant steam hiss"""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    rumble = dsp.spectral_noise(n, rng, lambda f: dsp.make_mag(lo=22, hi=190, order=3)(f) * (60.0 / np.maximum(f, 60.0)) ** 0.7)
    rumble *= lib.periodic_mod(n, T, rng, [1, 2, 3, 7], [0.18, 0.12, 0.08, 0.06])
    flame = dsp.spectral_noise(n, rng, dsp.make_mag(lo=28, hi=75, order=3))
    flame *= np.clip(0.6 + dsp.lp(dsp.white(n, rng), 11.0, order=2) / 3.0, 0.1, 1.6)
    motor = 0.20 * np.sin(TWO_PI * 50.0 * t + 0.4) + 0.10 * np.sin(TWO_PI * 100.0 * t + 1.2) + 0.04 * np.sin(TWO_PI * 150.0 * t)
    body = rumble + 0.55 * flame + motor * 0.9
    body /= np.std(body)
    # steam hiss: distant, swelling
    steam = dsp.spectral_noise(n, rng, dsp.make_mag(lo=2500, hi=7500, order=2))
    steam *= np.clip(lib.periodic_mod(n, T, rng, [1, 2, 3], [0.55, 0.3, 0.2]), 0.0, None) ** 2
    # pipe ticks (thermal expansion): resonant metallic ticks, a few in clusters
    ticks = np.zeros(n)
    t_ticks = sorted(rng.uniform(0.3, T - 0.3, 11))
    for i, t0 in enumerate(t_ticks):
        reps = 1 + int(rng.random() < 0.35) * int(rng.integers(1, 3))
        for r in range(reps):
            f = rng.uniform(1500, 3400)
            m = N(0.11)
            tk = dsp.modal([f, f * 1.51, f * 2.31], [1.0, 0.45, 0.2], [0.030, 0.020, 0.012], m, rng=rng, atk=0.0002)
            dsp.put(ticks, tk, t0 + r * rng.uniform(0.09, 0.2), rng.uniform(0.25, 0.7), circular=True)
    # hollow pipe knocks
    knocks = np.zeros(n)
    for t0 in (rng.uniform(1.0, 4.0), rng.uniform(5.5, 9.0)):
        f = rng.uniform(85, 140)
        m = N(0.35)
        kk = dsp.modal([f, f * 2.4], [1.0, 0.3], [0.09, 0.05], m, rng=rng, atk=0.0008)
        dsp.put(knocks, kk, t0, 0.55, circular=True)
    y = body + steam * dsp.db2lin(-33.0) + ticks * 0.34 + knocks * 0.34
    return dsp.reverb(y, "boiler", wet=0.28, dry=1.0, circular=True)


@sfx("amb_pool_water")
def amb_pool_water(c):
    """empty pool hall: slow lapping, occasional drips, long tiled reverb"""
    n, rng, T = c.n, c.rng, c.dur
    lap_bed = dsp.spectral_noise(n, rng, lambda f: dsp.make_mag(lo=140, hi=1500, order=2)(f) * (400.0 / np.maximum(f, 400.0)) ** 0.5)
    lap_bed *= np.clip(lib.periodic_mod(n, T, rng, [3, 5, 9], [0.45, 0.30, 0.22]), 0.05, None)
    laps = np.zeros(n)
    for t0 in sorted(rng.uniform(0.2, T - 0.8, 8)):
        m = N(rng.uniform(1.3, 1.8))
        sw = dsp.bp(dsp.white(m, rng), rng.uniform(200, 380), rng.uniform(1100, 1900), order=2)
        sw = sw / (np.std(sw) + 1e-9) * dsp.e_ar(m, rng.uniform(0.14, 0.26), rng.uniform(0.16, 0.30))
        sw = dsp.fade_out_tail(sw, 250)
        slap = dsp.bp(dsp.white(m, rng), 1400, 4200, order=2) * dsp.e_exp(m, 0.020, 0.002)
        slap = slap / (np.std(slap) + 1e-9) * 0.18
        dsp.put(laps, sw + np.pad(slap, (int(0.12 * SR), 0))[:m], t0, rng.uniform(0.5, 1.0), circular=True)
    dry = lap_bed / np.std(lap_bed) * 0.26 + laps * 0.40
    drips = np.zeros(n)
    for t0 in sorted(rng.uniform(0.6, T - 0.6, 5)):
        m = N(0.20)
        tt = dsp.tgrid(m)
        f = rng.uniform(1000, 1500) * (1.0 + 1.4 * (1.0 - np.exp(-tt / 0.016)))
        d = np.sin(dsp.phase_of(f, m)) * dsp.e_exp(m, 0.040, 0.0008) + 0.25 * np.sin(dsp.phase_of(2.7 * f, m)) * dsp.e_exp(m, 0.02, 0.0008)
        dsp.put(drips, d, t0, rng.uniform(0.35, 0.8), circular=True)
    wet_in = drips * 1.2 + dry * 0.35
    y = dry + dsp.reverb(wet_in, "pool", wet=1.0, dry=0.0, circular=True) * 1.1
    return y


@sfx("amb_queue_whispers")
def amb_queue_whispers(c):
    """many people whispering numbers, unintelligible, overlapping, over a dry paper-rustle bed"""
    n, rng, T = c.n, c.rng, c.dur
    y = np.zeros(n)
    nvoices = 11
    for v in range(nvoices):
        vr = c.sub_rng(("voice", v))
        fscale = vr.uniform(0.86, 1.22)
        lvl = vr.uniform(0.25, 1.0)
        t = vr.uniform(0, T)
        # each voice repeats phrases with long pauses
        for _ in range(2):
            ph = lib.whisper_phrase(vr, fscale=fscale, level=lvl, rate=vr.uniform(0.85, 1.25))
            dsp.put(y, ph, t % T, 1.0, circular=True)
            t += len(ph) / SR + vr.uniform(0.8, 3.0)
    y = dsp.filt(y, lo=140.0, hi=6000.0, order=2, circular=True)
    y = y / (np.std(y) + 1e-9)
    # paper rustle: bursts of crinkly high noise + very low continuous bed
    rustle = np.zeros(n)
    for t0 in sorted(rng.uniform(0.0, T, 9)):
        m = N(rng.uniform(0.07, 0.3))
        r = dsp.hp(dsp.white(m, rng), 1600, order=2)
        flutter = np.clip(1.0 + 2.0 * dsp.lp(dsp.white(m, rng), 90.0, order=2) / (np.std(dsp.lp(dsp.white(m, rng), 90.0, order=2)) + 1e-9), 0.0, 3.0)
        r = r / (np.std(r) + 1e-9) * flutter * np.hanning(m) ** 0.5
        dsp.put(rustle, r, t0, rng.uniform(0.15, 0.5), circular=True)
    bed = dsp.spectral_noise(n, rng, dsp.make_mag(lo=1500, hi=7000, order=2))
    return y + 0.30 * rustle / (np.std(rustle) + 1e-9) * 0.5 + bed * dsp.db2lin(-36.0)


@sfx("amb_lobby_warm")
def amb_lobby_warm(c):
    """grand lobby room tone: warm and quiet, far-off piano notes fading in another room, a clock ticking"""
    n, rng, T = c.n, c.rng, c.dur
    warm = dsp.spectral_noise(n, rng, lambda f: dsp.make_mag(lo=55, hi=1100, order=2)(f) * (200.0 / np.maximum(f, 200.0)) ** 0.6
                              * (1.0 + 0.8 * np.exp(-((f - 140.0) / 60.0) ** 2)))
    warm *= lib.periodic_mod(n, T, rng, [1, 2], [0.12, 0.06])
    air = dsp.spectral_noise(n, rng, dsp.make_mag(lo=1200, hi=3800, order=2))
    room = warm + air * dsp.db2lin(-24.0) * 0.5
    room /= np.std(room)
    piano = np.zeros(n)
    notes = [(0.7, 293.66), (3.2, 369.99), (5.6, 440.0), (7.9, 329.63)]
    for t0, f in notes:
        tone = lib.soft_piano(f, 3.0, rng, bright=0.45, hammer=0.5, decay=0.6)
        tone = dsp.lp(tone, 1500.0, order=2)
        tone = tone / (np.sqrt(np.mean(tone[:SR] ** 2)) + 1e-9)       # every note equally loud
        dsp.put(piano, tone, t0, rng.uniform(0.8, 1.0), circular=True)
    piano = dsp.reverb(piano, "lobby", wet=0.7, dry=0.7, circular=True)
    piano = piano / (np.std(piano) + 1e-9)
    # clock: tick / tock once per second
    clock = np.zeros(n)
    for i in range(int(T)):
        hi = (i % 2 == 0)
        f = 1850.0 if hi else 1350.0
        m = N(0.09)
        tk = dsp.modal([f, f * 2.4, 620.0 if hi else 520.0], [1.0, 0.35, 0.5], [0.012, 0.007, 0.030], m, rng=rng, atk=0.0002)
        dsp.put(clock, tk, 0.35 + i * 1.0, 1.0 if hi else 0.8, circular=True)
    clock = dsp.reverb(clock, "lobby", wet=0.35, dry=1.0, circular=True)
    clock = clock / (np.std(clock) + 1e-9)
    return room + 0.75 * piano + 0.17 * clock


@sfx("elevator_hum")
def elevator_hum(c):
    """cab motor hum with a slow rotational flutter, shaft air, and two faint cable creaks"""
    n, rng, T = c.n, c.rng, c.dur
    t = dsp.tgrid(n)
    f0 = round(54.0 * T) / T
    motor = np.zeros(n)
    for k, a in ((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.2), (6, 0.1)):
        motor += a * np.sin(TWO_PI * f0 * k * t + rng.uniform(0, 6.28))
    motor *= 1.0 + 0.12 * np.sin(TWO_PI * (27.0 / T) * t + rng.uniform(0, 6.28))   # 4.5 Hz rotation flutter
    motor *= lib.periodic_mod(n, T, rng, [1, 2], [0.06, 0.04])
    motor /= np.std(motor)
    rumble = dsp.spectral_noise(n, rng, dsp.make_mag(lo=35, hi=500, order=2))
    shaft = dsp.spectral_noise(n, rng, dsp.make_mag(lo=900, hi=4000, order=2)) * dsp.db2lin(-32.0)
    creaks = np.zeros(n)
    for t0, f_a, f_b in ((1.4, 760.0, 910.0), (4.2, 1050.0, 820.0)):
        dur = rng.uniform(0.45, 0.7)
        cr = lib.creak(rng, dur, lambda tt, a=f_a, b=f_b, d=dur: a + (b - a) * tt / d, res=(900.0, 1500.0, 2500.0), q=9.0, jitter=0.03, rough=0.3)
        cr = cr * dsp.e_pts(len(cr), [(0, 0), (dur * 0.25, 1), (dur * 0.7, 0.8), (dur, 0)])
        dsp.put(creaks, cr, t0, 0.07, circular=True)
    return motor + 0.35 * rumble + shaft + creaks
