# Ibasho — motor comun de las canciones nuevas de Odori (0.6.3 en adelante).
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
#
# Cada cancion vive en tool/canciones/<id>.py con un SPEC (tablas de melodia,
# letra, texto, romaji y disposicion) y una funcion build(h) con su
# instrumentacion. Aqui estan lo que comparten: instrumentos extra, la notacion
# de melodias, los ayudantes de ritmo y armonia, la validacion de letras y la
# letra para leer / karaoke.
#
# Notacion de melodia: un compas por «|», notas «Sol4», «Bb4», «F#5». Si todas
# las notas de un compas van sin duracion, el ritmo sale de una plantilla segun
# cuantas son; con «nota/duracion» se escribe a mano («r/.5» es un silencio).

import importlib
import json
import math
import os
import re

import numpy as np

G = None  # modulo gen_odori_music, lo pone register()
SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# ------------------------------------------------------------------ notacion

_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", name)
    assert m, f"nota rara: {name}"
    pc = _PC[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)]
    return 12 * (int(m.group(3)) + 1) + pc


_TEMPL = {1: [4], 2: [2, 2], 3: [1, 1, 2], 4: [1, 1, 1, 1], 5: [.5, .5, 1, 1, 1],
          6: [.5, .5, .5, .5, 1, 1], 7: [.5] * 6 + [1], 8: [.5] * 8}


def parse_part(text):
    """Melodia -> [(compas, pulso, midi, duracion)]."""
    out = []
    for bar, chunk in enumerate(text.split("|")):
        toks = chunk.split()
        if any("/" in t for t in toks):
            q = 0.0
            for t in toks:
                n, d = t.split("/")
                d = float(d)
                if n != "r":
                    out.append((bar, q, midi(n), d))
                q += d
            assert abs(q - 4) < 1e-6, f"compas {bar} suma {q}: {chunk}"
        else:
            durs = _TEMPL[len(toks)]
            q = 0.0
            for t, d in zip(toks, durs):
                out.append((bar, q, midi(t), d))
                q += d
    return out


_QUAL = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
         "sus4": [0, 5, 7], "sus2": [0, 2, 7], "add9": [0, 4, 7, 14], "dim": [0, 3, 6], "6": [0, 4, 7, 9],
         "m6": [0, 3, 7, 9], "m7b5": [0, 3, 6, 10], "9": [0, 4, 7, 10, 14], "m9": [0, 3, 7, 10, 14]}
_CH = re.compile(r"^([A-G][#b]?)(m7b5|maj7|m7|m9|m6|m|7|9|sus4|sus2|add9|dim|6|)(?:/([A-G][#b]?))?$")


def chord(name):
    """Nombre -> (notas, bajo). Voicing cerrado hacia Do4..Fa#4."""
    m = _CH.match(name)
    assert m, f"acorde raro: {name}"
    r = midi(m.group(1) + "4") % 12
    base = 60 + r if r <= 6 else 48 + r
    notes = [base + i for i in _QUAL[m.group(2)]]
    b = midi((m.group(3) or m.group(1)) + "2") % 12
    return notes, 36 + b


def parse_prog(text):
    """«G:4 Em:4 C» -> [(pulso, duracion, notas, bajo)] (duracion 4 por defecto)."""
    out, off = [], 0.0
    for tok in text.split():
        name, _, d = tok.partition(":")
        d = float(d) if d else 4.0
        notes, root = chord(name)
        out.append((off, d, notes, root))
        off += d
    return out


# --------------------------------------------------------------- instrumentos

def _env(n, attack=0.002, release=0.03):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4))
    r = int(release * SR)
    if r > 0 and n > r:
        e[n - r:] *= np.linspace(1, 0, r)
    return e


def additive(freq, dur, amps, decays, ratios=None, inharm=0.0, attack=0.002, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k, (a, dc) in enumerate(zip(amps, decays), 1):
        r = ratios[k - 1] if ratios else k
        f = freq * r * math.sqrt(1 + inharm * r * r)
        if f > SR * 0.45:
            break
        x += a * np.sin(2 * np.pi * f * t + 0.7 * k) * np.exp(-t * dc)
    return x * _env(n, attack, 0.02)


def _noise(n, seed):
    return np.random.RandomState(seed).normal(0, 1, n)


def ukulele(freq, dur, amp=1.0, seed=0):
    x = additive(freq, dur, [1, .5, .3, .16, .1, .06], [6, 8, 11, 15, 20, 26], inharm=2e-4, attack=0.001)
    n = len(x)
    click = G.bandpass(_noise(n, seed), 1500, 6000) * np.exp(-np.arange(n) / SR * 90) * 0.12
    return amp * (x + click)


def koto(freq, dur, amp=1.0, seed=0):
    x = additive(freq, dur, [1, .7, .5, .3, .2, .12, .08], [3.2, 4.2, 5.6, 7.5, 10, 13, 17], inharm=4e-4, attack=0.001)
    n = len(x)
    click = G.bandpass(_noise(n, seed), 2500, 9000) * np.exp(-np.arange(n) / SR * 120) * 0.2
    return amp * (x + click)


def shamisen(freq, dur, amp=1.0, seed=0):
    x = additive(freq, dur, [1, .8, .7, .5, .4, .3, .22, .15], [5, 6, 7, 9, 11, 14, 17, 21], inharm=3e-4,
                 attack=0.001)
    n = len(x)
    snap = G.bandpass(_noise(n, seed), 800, 5000) * np.exp(-np.arange(n) / SR * 60) * 0.35
    return amp * np.tanh((x + snap) * 1.4)


def guitar_clean(freq, dur, amp=1.0, seed=0):
    x = additive(freq, dur, [1, .55, .4, .25, .15, .1], [3.5, 4.5, 6, 8, 11, 14], inharm=1e-4, attack=0.001)
    return amp * G.lowpass(x, 4200)


def marimba(freq, dur, amp=1.0, seed=0):
    x = additive(freq, dur, [1, .32, .1], [8, 26, 45], ratios=[1, 3.98, 9.9], attack=0.001)
    return amp * x


def piano(freq, dur, amp=1.0, seed=0):
    x = additive(freq, dur, [1, .7, .45, .3, .2, .12, .08, .05], [2.6, 3.4, 4.6, 6, 8, 11, 14, 18],
                 inharm=1.5e-4, attack=0.002)
    n = len(x)
    thump = G.lowpass(_noise(n, seed), 900) * np.exp(-np.arange(n) / SR * 70) * 0.08
    return amp * (x + thump)


def epiano(freq, dur, amp=1.0, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 1.4 * np.exp(-t * 5)
    x = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * t)) * np.exp(-t * 2.4)
    x += 0.22 * np.sin(2 * np.pi * freq * 14 * t) * np.exp(-t * 30)
    return amp * x * _env(n, 0.002, 0.05)


def flute(freq, dur, amp=1.0, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    depth = 0.16 * np.clip((t - 0.15) / 0.25, 0, 1)
    f = freq * 2 ** (depth * np.sin(2 * np.pi * 5.2 * t) / 12.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    breath = G.bandpass(_noise(n, seed), 2500, 7000) * 0.05 * np.clip(t / 0.05, 0, 1)
    return amp * (x + breath) * _env(n, 0.05, 0.08)


def upright(freq, dur, amp=1.0, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * freq * t) + 0.45 * np.sin(4 * np.pi * freq * t) * np.exp(-t * 9)) * np.exp(-t * 4.5)
    x += G.lowpass(_noise(n, 3), 700) * np.exp(-t * 80) * 0.15
    return amp * x * _env(n, 0.003, 0.03)


def crunch(freqs, dur, amp=1.0, mute=False):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        x += G.saw(f, n, phase0=0.17 * i) + 0.6 * G.saw(f * 1.004, n, phase0=0.4 + 0.1 * i)
    x = G.lowpass(np.tanh(x / max(1, len(freqs)) * 4.5), 3600)
    env = np.exp(-t * (26 if mute else 3.0)) * _env(n, 0.003, 0.03)
    return amp * x * env * 0.6


def taiko(amp=1.0, pitch=1.0):
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    f = (62 + 90 * np.exp(-t * 22)) * pitch
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 5.5)
    skin = G.bandpass(_noise(n, 12), 300, 1800) * np.exp(-t * 30) * 0.25
    return amp * np.tanh((body + skin) * 1.6)


def brush(dur, amp=1.0, seed=0, swell=True):
    n = int(dur * SR)
    x = G.bandpass(_noise(n, seed), 2500, 9500)
    env = np.sin(np.linspace(0, math.pi, n)) ** 1.5 if swell else np.exp(-np.arange(n) / SR * 30)
    return amp * x * env


def shaker(amp=1.0, seed=0):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    x = G.highpass(_noise(n, seed), 5500, order=2)
    return amp * x * np.exp(-t * 55) * np.minimum(1, t / 0.008)


def woodblock(freq=1500, amp=1.0):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.5 * np.sin(2 * np.pi * freq * 1.52 * t)
    return amp * x * np.exp(-t * 70)


def chop(amp=1.0, seed=0):
    """Cuchillo sobre la tabla."""
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    x = G.bandpass(_noise(n, seed), 400, 3500) * np.exp(-t * 90) + np.sin(2 * np.pi * 210 * t) * np.exp(-t * 60) * 0.6
    return amp * x


def sizzle(dur=0.6, amp=1.0, seed=0):
    """Aceite en la sarten: ruido agudo + chisporroteos sueltos."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    rng = np.random.RandomState(seed)
    x = G.highpass(_noise(n, seed), 3500, order=2) * 0.35 * np.exp(-t * 3.5)
    for _ in range(int(dur * 60)):
        p = rng.randint(0, n - 300)
        L = 300
        x[p:p + L] += rng.normal(0, 1, L) * np.exp(-np.arange(L) / 40) * 0.5 * np.exp(-p / SR * 2.2)
    return amp * x * _env(n, 0.004, 0.1)


def raindrop(freq, amp=1.0):
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.9 * np.minimum(1, t / 0.03))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 26)
    return amp * x * np.minimum(1, t / 0.002)


def vinyl(dur, amp=1.0, seed=1):
    n = int(dur * SR)
    rng = np.random.RandomState(seed)
    x = np.zeros(n)
    idx = rng.randint(0, n - 60, int(dur * 28))
    for p in idx:
        x[p:p + 60] += rng.normal(0, 1, 60) * np.exp(-np.arange(60) / 9) * rng.uniform(.1, .6)
    hiss = G.highpass(_noise(n, seed + 1), 4000) * 0.02
    return amp * (x + hiss)


def whistle_boom(amp=1.0, seed=0):
    """Cohete: silbido que sube y estallido con crepitar."""
    n = int(2.4 * SR)
    t = np.arange(n) / SR
    up = 0.55
    f = 500 + 2400 * np.minimum(1, t / up) ** 1.6
    w = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.15 * np.where(t < up, np.minimum(1, t / 0.05), 0)
    i0 = int(up * SR)
    tb = np.arange(n - i0) / SR
    boom = np.sin(2 * np.pi * np.cumsum(70 + 90 * np.exp(-tb * 25)) / SR) * np.exp(-tb * 5)
    boom += G.lowpass(_noise(n - i0, seed), 2500) * np.exp(-tb * 7) * 0.7
    x = w.copy()
    x[i0:] += boom
    rng = np.random.RandomState(seed + 3)
    for _ in range(90):
        p = i0 + int(rng.uniform(0.15, 1.8) * SR)
        if p + 200 < n:
            x[p:p + 200] += rng.normal(0, 1, 200) * np.exp(-np.arange(200) / 25) * rng.uniform(.05, .35) \
                            * np.exp(-(p - i0) / SR * 1.4)
    return amp * x


def meow(freq, dur=0.45, amp=1.0, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    f = freq * (1 + 0.28 * np.sin(np.pi * u) - 0.1 * u)
    x = G.saw(f, n)
    # formante que abre y cierra: «miau»
    out = np.zeros(n)
    edges = np.linspace(0, n, 33).astype(int)
    for i in range(32):
        c = 500 + 900 * math.sin(math.pi * (i + 0.5) / 32)
        seg = x[edges[i]:edges[i + 1]]
        out[edges[i]:edges[i + 1]] = G.bandpass(np.concatenate([seg, seg[::-1]]), c * 0.8, c * 1.25)[:len(seg)]
    return amp * out * np.sin(np.pi * np.clip(u * 1.05, 0, 1)) ** 0.7 * 2.0


def cricket(dur, amp=1.0, seed=0):
    """Grillos / cigarras de fondo: ruido agudo en rafagas."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = G.bandpass(_noise(n, seed), 3600, 5600)
    gate = (np.sin(2 * np.pi * 2.6 * t) > 0.2) * (0.6 + 0.4 * np.sin(2 * np.pi * 31 * t))
    return amp * x * gate * 0.4


def bike_bell(amp=1.0):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for r in (1, 2.76, 5.4):
        x += np.sin(2 * np.pi * 2350 * r * t) * np.exp(-t * (5 * r))
    ring = 1 + 0.7 * (np.sin(2 * np.pi * 26 * t) > 0)
    return amp * 0.5 * x * ring * np.exp(-t * 3) * _env(n, 0.001, 0.05)


# --- instrumentos de nota suelta para melodias: (s, beat, pitch, dur, amp, chart)

def _put_note(s, bus, beat, wave, pan_=0.0):
    s.put(bus, beat, G.pan(wave, pan_))


def _mono_lead(fn, ring=1.0, bus="lead", pan_=0.0):
    def play(s, beat, pitch, dur, amp, chart):
        d = max(0.25, dur * s.beat * ring)
        _put_note(s, bus, beat, fn(s.hz(pitch), d, amp), pan_)
        if chart:
            s.note(beat, "l", pitch, dur)
    return play


LEADS = {
    "lead": lambda s, b, p, d, a, c: s.lead(b, p, d, amp=a, chart=c),
    "bell": lambda s, b, p, d, a, c: s.bell(b, p, d, amp=a * 0.8, chart=c),
    "marimba": _mono_lead(lambda f, d, a: marimba(f, d * 1.3, a * 1.3), 1.4),
    "ukulele": _mono_lead(lambda f, d, a: ukulele(f, d * 1.2, a * 1.1), 1.5),
    "koto": _mono_lead(lambda f, d, a: koto(f, d * 1.4, a * 1.2), 2.0),
    "shamisen": _mono_lead(lambda f, d, a: shamisen(f, d * 1.1, a), 1.0),
    "guitar": _mono_lead(lambda f, d, a: guitar_clean(f, d * 1.4, a * 1.2), 1.6),
    "piano": _mono_lead(lambda f, d, a: piano(f, d * 1.6, a * 1.1), 1.8),
    "epiano": _mono_lead(lambda f, d, a: epiano(f, d * 1.5, a * 1.1), 1.6),
    "flute": _mono_lead(lambda f, d, a: flute(f, d, a * 0.9), 1.0),
}


def strum(s, fn, beat, notes, dur, amp=0.15, up=False, spread=0.016, chart=False, pan_=0.0, bus="music"):
    """Rasgueo: las notas del acorde entran escalonadas (fn(freq, dur, amp, seed))."""
    order = notes[::-1] if up else notes
    for i, p in enumerate(order):
        wave = fn(s.hz(p), max(0.3, dur * s.beat * 1.4), amp, seed=p)
        s.put(bus, beat + i * spread / s.beat, G.pan(wave, max(-1, min(1, pan_ + (i - len(order) / 2) * 0.1))))
    if chart:
        s.note(beat, "c", notes[-1], dur, 1)


# ------------------------------------------------------------------- ayudante

class H:
    """Lo que ve build(h): la cancion, sus tablas y atajos de ritmo/armonia."""

    def __init__(self, s, spec, lang, voice):
        self.s, self.spec, self.lang, self.voice = s, spec, lang, voice
        self.vocal = voice is not None
        self.sung = []
        self.g = G
        self.mel = spec["_mel"]
        self.prog_cache = {}

    # --- armonia
    def prog(self, name):
        if name not in self.prog_cache:
            self.prog_cache[name] = parse_prog(self.spec["prog"][name])
        return self.prog_cache[name]

    def chords(self, start, name, pad=0.12, cutoff=3200, tr=0, up=0, bars=None, fn=None):
        """Pad de la progresion; con [fn] cada acorde va a otro instrumento.
        Devuelve [(pulso, duracion, bajo, notas)] transportados."""
        items = [c for c in self.prog(name) if bars is None or c[0] < bars * 4]
        out = []
        for (off, d, notes, root) in items:
            ns = [n + tr + up for n in notes]
            if fn is not None:
                fn(start + off, ns, d)
            elif pad:
                self.s.pad(start + off, ns, d, amp=pad, cutoff=cutoff)
            out.append((start + off, d, root + tr, [n + tr for n in notes]))
        return out

    def bassline(self, start, name, rhythm, amp=0.5, tr=0, bars=None, kind="bass", chart=True):
        """[rhythm]: (desfase, duracion, semitonos) que se repite en cada acorde."""
        s = self.s
        for (off, d, notes, root) in self.prog(name):
            if bars is not None and off >= bars * 4:
                continue
            for (o, dd, semi) in rhythm:
                if o >= d:
                    continue
                pitch = root + tr + semi
                b = start + off + o
                if kind == "upright":
                    s.put("bass", b, upright(s.hz(pitch), dd * s.beat * 1.2, amp))
                    if chart:
                        s.note(b, "b", pitch, dd)
                else:
                    s.bass(b, pitch, dd, amp=amp, chart=chart)

    def comp(self, start, name, rhythm, fn, tr=0, up=0, bars=None):
        """[rhythm]: (desfase, duracion) por acorde; fn(beat, notas, dur)."""
        for (off, d, notes, root) in self.prog(name):
            if bars is not None and off >= bars * 4:
                continue
            ns = [n + tr + up for n in notes]
            for (o, dd) in rhythm:
                if o < d:
                    fn(start + off + o, ns, dd)

    def arps(self, start, name, shape, step, fn, tr=0, up=0, bars=None):
        """Arpegio: [shape] indices de nota del acorde (se pliegan a octavas)."""
        for (off, d, notes, root) in self.prog(name):
            if bars is not None and off >= bars * 4:
                continue
            ns = [n + tr + up for n in notes]
            k = 0
            t = 0.0
            while t < d - 1e-6:
                i = shape[k % len(shape)]
                p = ns[i % len(ns)] + 12 * (i // len(ns))
                fn(start + off + t, p, step)
                t += step
                k += 1

    # --- ritmo
    def K(self, b, a=1.0, chart=True):
        self.s.kick(b, a, chart=chart)

    def S(self, b, a=0.8, chart=True):
        self.s.clap(b, a, chart=chart)

    def Hh(self, b, a=0.25, chart=True):
        self.s.hat(b, a, p=0.25 if int(b * 4) % 2 else -0.15, chart=chart)

    def Oh(self, b, a=0.25, chart=True):
        self.s.hat(b, a, open_=True, p=-0.2, chart=chart)

    def drum(self, bus_wave, b, amp=1.0, pan_=0.0, role=None, pitch=0):
        """Golpe de percusion suelto, opcionalmente anotado en la partitura."""
        self.s.put("drums", b, G.pan(bus_wave, pan_), amp)
        if role:
            self.s.note(b, role, pitch, 0, 0)

    def grid(self, start, bars, lanes, amp=1.0, swing=0.0, skip=()):
        """[lanes]: {letra: (patron, fn)}, un caracter por paso de un compas
        (16 = semicorcheas). 'X' fuerte, 'x' normal, 'o' fantasma, '.' nada."""
        vals = {"X": 1.0, "x": 0.75, "o": 0.42}
        for bar in range(bars):
            if bar in skip:
                continue
            for letter, (pat, fn) in lanes.items():
                L = len(pat)
                step = 4.0 / L
                for i, ch in enumerate(pat):
                    if ch in vals:
                        sw = swing * step if i % 2 else 0.0
                        fn(start + bar * 4 + i * step + sw, vals[ch] * amp)

    # --- melodia y voz
    def section(self, beat, name, energy):
        self.s.section(beat, name, energy)

    def melody(self, start, part, instr="lead", amp=0.3, tr=0, octave=False, bars=None):
        play = LEADS[instr] if isinstance(instr, str) else instr
        lo, hi = bars if bars else (0, 999)
        for (bar, q, p, d) in self.mel[part]:
            if lo <= bar < hi:
                b = start + (bar - lo) * 4 + q
                play(self.s, b, p + tr, d, amp * (0.25 if self.vocal else 1.0), not self.vocal)
                if octave:
                    self.s.lead(b, p + tr - 12, d, amp=amp * 0.4 * (0.25 if self.vocal else 1.0), chart=False)

    def sing_part(self, start, part, tr=0):
        assert (start, part) in self.spec["layout"], f"{part}@{start} no esta en el LAYOUT"
        if self.vocal:
            words = lyric_words(self.spec, self.lang, part)
            self.sung.extend((start + bar * 4 + q, p + tr, d, w)
                             for (bar, q, p, d), w in zip(self.mel[part], words))

    def finish(self, harmony=(), tonic=60, scale=None, amp=0.5):
        """Canta la voz. [harmony]: (desde, hasta, transporte) de los tramos que
        llevan ademas una tercera por encima, grabada aparte y a la derecha."""
        if not self.vocal:
            return
        s = self.s
        s.sing(self.sung, self.voice, amp=amp)
        if harmony:
            import odori_voices as ov
            scale = scale or G.MAJOR
            line = [(b, G.third_above(p, scale, tonic + tr), d, w) for (b, p, d, w) in self.sung
                    for (lo, hi, tr) in harmony if lo <= b < hi]
            print(f"    segunda voz ({len(line)} notas)...", flush=True)
            y = G.vocal_chain(ov.sing(self.voice, line, s.bpm, s.key))
            s.put("vocal", ov.score_start_bar(line) * 4, G.pan(y * amp * 0.42, 0.35))


# ---------------------------------------------------------- tablas y letras

def lyric_words(spec, lang, part):
    bars = [b.split() for b in spec["lyrics"][lang][part].split("|")]
    mel = spec["_mel"][part]
    bad = []
    for i, words in enumerate(bars):
        n = sum(1 for m in mel if m[0] == i)
        if len(words) != n:
            bad.append(f"compas {i + 1}: {len(words)} silabas para {n} notas")
    nbars = max(m[0] for m in mel) + 1
    if len(bars) != nbars:
        bad.append(f"{len(bars)} compases para {nbars}")
    assert not bad, f"{spec['id']}/{lang}/{part}: " + "; ".join(bad)
    return [w for b in bars for w in b]


def check(spec):
    spec["_mel"] = {k: parse_part(v) for k, v in spec["mel"].items()}
    for alias, src in spec.get("mel_alias", {}).items():
        spec["_mel"][alias] = spec["_mel"][src]
    parts = {p for _, p in spec["layout"]}
    errs = []
    for lang in ("ja", "es"):
        for part in sorted(parts):
            try:
                lyric_words(spec, lang, part)
            except AssertionError as e:
                errs.append(str(e))
                continue
            nb = len(spec["lyrics"][lang][part].split("|"))
            if len(spec["text"][lang][part].split("|")) != nb:
                errs.append(f"{spec['id']}/{lang}/{part}: texto con otro numero de compases")
            if lang == "ja" and len(spec["romaji"][part].split("|")) != nb:
                errs.append(f"{spec['id']}/{part}: romaji con otro numero de compases")
    assert not errs, "\n" + "\n".join(errs)
    return spec


def teto_key(spec):
    ps = [p for part in {p for _, p in spec["layout"]} for (_, _, p, _) in spec["_mel"][part]]
    med = sorted(ps)[len(ps) // 2]
    key = max(-12, min(0, round(68 - med)))
    key = min(key, 77 - max(ps) - spec.get("tr_final", 0))
    return key


def voice_key(spec):
    """Clave de Sinsy y NEUTRINO: como en Yako, 3 semitonos por encima de la
    de Teto y sin pasar de Fa#5 en el estribillo final."""
    ps = [p for part in {p for _, p in spec["layout"]} for (_, _, p, _) in spec["_mel"][part]]
    return min(0, spec["teto_key"] + 3, 78 - max(ps) - spec.get("tr_final", 0))


VOICES = ["teto", "sinsy", "kiritan", "zundamon", "merrow"]


def make_song(spec, lang=None, voice=None):
    g = G
    vocal = voice is not None
    sid = f"{spec['id']}_{lang}_{voice.split('_')[0]}" if vocal else spec["id"]
    key = spec.get("key", 0)
    if voice == "teto":
        key = spec["teto_key"]
    elif vocal:
        key = spec["voice_key"]
    s = g.Song(sid, spec["title"], spec["bpm"], bars=spec["bars"], key=key)
    h = H(s, spec, lang, voice)
    spec["build"](h)
    return s


def register(g, ids):
    global G
    G = g
    for sid in ids:
        mod = importlib.import_module(f"canciones.{sid}")
        spec = check(mod.SPEC)
        spec["build"] = mod.build
        spec["teto_key"] = spec.get("teto_key", teto_key(spec))
        spec["voice_key"] = spec.get("voice_key", voice_key(spec))
        SPECS[sid] = spec
        g.SONGS[sid] = (lambda sp: lambda: make_song(sp))(spec)
        for lang in ("ja", "es"):
            for v in VOICES:
                g.SONGS[f"{sid}_{lang}_{v}"] = (lambda sp, l, v: lambda: make_song(sp, l, v))(spec, lang, v)


SPECS = {}


# ---------------------------------------------------------- letra para leer

def letra_json(spec, lang):
    """Karaoke del juego: una linea cada dos compases (igual que Yakō)."""
    lines = []
    for start, part in spec["layout"]:
        texts = [t.strip() for t in spec["text"][lang][part].split("|")]
        bars = []
        for i, text in enumerate(texts):
            notes = [[start + bar * 4 + q, d] for (bar, q, p, d) in spec["_mel"][part] if bar == i]
            assert notes, f"{spec['id']}/{lang}/{part} compas {i} sin notas"
            bars.append({"text": text, "notes": notes})
        for i in range(0, len(bars), 2):
            pair = bars[i:i + 2]
            lines.append({"start": pair[0]["notes"][0][0],
                          "end": pair[-1]["notes"][-1][0] + pair[-1]["notes"][-1][1],
                          "bars": pair})
    return {"id": f"{spec['id']}_{lang}", "lang": lang, "lines": lines}


def letra_md(spec, lang):
    out = [f"# {spec['head'][lang]}", ""]
    last_cho = max((st for st, p in spec["layout"] if p == "cho"), default=None)
    for start, part in spec["layout"]:
        head = spec["sections"].get(part)
        if part == "cho" and start == last_cho and spec.get("final_note"):
            head = f"Estribillo final ({spec['final_note']})"
        if head:
            out += [f"## {head}", ""]
        bars = [t.strip() for t in spec["text"][lang][part].split("|")]
        roma = [t.strip() for t in spec["romaji"][part].split("|")] if lang == "ja" else None
        for i in range(0, len(bars), 2):
            line = ""
            for b in bars[i:i + 2]:
                if b == "ー" or (lang == "ja" and len(b) == 1):
                    line += b
                elif line.endswith("-"):
                    line = line[:-1] + b
                else:
                    line += (" " if line else "") + b
            if line.endswith("-"):
                line = line[:-1] + "–"
            out.append(line + "  ")
            if roma:
                r = " ".join(b for b in roma[i:i + 2] if b != "ー")
                out.append(f"*{r[0].upper() + r[1:]}*  ")
        out.append("")
    return "\n".join(out)


def write_letras(out_dir):
    for sid, spec in SPECS.items():
        for lang in ("ja", "es"):
            os.makedirs(os.path.join(out_dir, sid), exist_ok=True)
            p = os.path.join(out_dir, sid, f"{sid}_letra_{lang}.json")
            with open(p, "w") as f:
                json.dump(letra_json(spec, lang), f, ensure_ascii=False, separators=(",", ":"))
            md = os.path.normpath(os.path.join(ROOT, "docs", "letras", sid, f"{sid}_{lang}.md"))
            os.makedirs(os.path.dirname(md), exist_ok=True)
            with open(md, "w") as f:
                f.write(letra_md(spec, lang))
            print(f"  -> {os.path.relpath(p)} y {os.path.relpath(md)}")
