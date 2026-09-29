#!/usr/bin/env python3
# Ibasho — las tres canciones de Hatarakitama, que se van turnando.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Uso:  python3 tool/gen_hataraki_music.py [asa | mizuba | yuyake ...]
# Salen en assets/audio/bgm/ (ogg y mp3). Requiere numpy y ffmpeg en el PATH.
#
# Un dia de trabajo en el pueblo, en tres canciones que suenan una detras de
# otra (`GameMusic.cycle`): la mañana, el agua a mediodia y el mercado al
# atardecer. Cada una usa instrumentos y una forma de generar distintas:
#
#   asa     Re mayor, 100 bpm. Las herramientas son la percusion y estan
#           afinadas: yunque y tocon por sintesis modal, sierra con ruido
#           filtrado. Ritmos euclideos (3 en 8, 5 en 8) y una flauta de
#           bambu hecha de armonicos con soplo.
#   mizuba  La mayor, 66 bpm. Musica de fases a lo Steve Reich: dos kalimbas
#           repiten un dibujo de 16 y otro de 15 semicorcheas, se van
#           desfasando y vuelven a coincidir justo al cerrar el bucle (15
#           compases). Encima, una armonica de cristal y gotas de agua.
#   yuyake  Mi dorico, 88 bpm con swing. Shamisen por Karplus-Strong con el
#           zumbido del sawari, un coro granular (miles de granos de una voz
#           sintetizada con formantes), piano de juguete por FM y bajo
#           andante que se calcula a partir de los acordes.
#
# Se encadenan: cada una acaba con una pista de la siguiente (asa deja una
# kalimba en La, mizuba una nota de shamisen en Mi y yuyake el yunque en Re),
# y las tonalidades van Re -> La -> Mi dorico, que es la escala de Re: el
# ciclo vuelve a casa sin saltos.
#
# Normas de la casa, las mismas que el resto de la musica:
#   - todo va en un bucle circular (`_put`), reverb incluida: cada cancion
#     tambien cierra sola, sin costura, si se elige para el menu;
#   - melodias compuestas, no aleatorias (el azar, con semilla fija, solo
#     decide texturas: granos, gotas, soplo);
#   - nivel con ganancia fija medida con ebur128, sin loudnorm dinamico.

import os
import re
import subprocess
import sys

import numpy as np

from gen_audio import BGM_DIR, ROOT, SR, _midi, _reverb_circular, write_wav


# ------------------------------------------------------------- utilidades

def _put(L, R, t0, sig, pan=0.5):
    """Suma `sig` en el bucle (lo que se sale entra por delante), con paneo."""
    n = len(L)
    s0 = int(round(t0 * SR)) % n
    m = len(sig)
    gl, gr = np.cos(pan * np.pi / 2), np.sin(pan * np.pi / 2)
    pos = 0
    while pos < m:
        take = min(m - pos, n - s0)
        L[s0:s0 + take] += sig[pos:pos + take] * gl
        R[s0:s0 + take] += sig[pos:pos + take] * gr
        pos += take
        s0 = 0
    return L, R


def _env(m, attack, release):
    """Ataque sin^2 y caida cos^2, para las notas sin golpe."""
    e = np.ones(m)
    a = max(1, min(m, int(attack * SR)))
    r = max(1, min(m - a, int(release * SR)))
    e[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    e[m - r:] *= np.cos(np.linspace(0, np.pi / 2, r)) ** 2
    return e


def _bandpass(x, lo, hi, soft=0.25):
    """Filtro por FFT con bordes suaves."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    lo_w = 1 / (1 + np.exp(-(f - lo) / (lo * soft + 1)))
    hi_w = 1 / (1 + np.exp((f - hi) / (hi * soft + 1)))
    return np.fft.irfft(X * lo_w * hi_w, len(x))


def _euclid(k, n):
    """Ritmo euclideo de Bjorklund: k golpes repartidos en n pasos."""
    return [i for i in range(n) if (i * k) % n < k]


# ------------------------------------------------------------ instrumentos

def _modal(freq, ratios, gains, decays, dur, amp=1.0, strike=0.0, seed=0):
    """Sintesis modal: cada modo de vibracion es un seno que se apaga solo."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    out = np.zeros(m)
    for r, g, d in zip(ratios, gains, decays):
        f = freq * r
        if f < SR / 2.2:
            out += g * np.sin(2 * np.pi * f * tt) * np.exp(-tt * d)
    if strike:
        k = int(0.012 * SR)
        hit = np.random.RandomState(seed).normal(0, 1, k) * np.exp(-np.linspace(0, 9, k))
        out[:k] += strike * _bandpass(hit, freq * 0.8, freq * 6)
    a = int(0.002 * SR)
    out[:a] *= np.linspace(0, 1, a)
    return amp * out


def anvil(freq, amp=1.0):
    """Yunque afinado: los modos de una barra libre (1, 2.76, 5.40, 8.93)."""
    return _modal(freq, [1, 2.756, 5.404, 8.933, 13.34], [1, .5, .28, .14, .06],
                  [2.2, 4.5, 8, 13, 20], 1.8, amp, strike=.25, seed=int(freq))


def chop(freq, amp=1.0, seed=0):
    """Hachazo en el tocon: madera, modos graves y un golpe de ruido seco."""
    return _modal(freq, [1, 1.62, 2.43, 3.3], [1, .45, .2, .08],
                  [28, 40, 55, 70], .25, amp, strike=.9, seed=seed)


def stump(amp=1.0):
    """Mazo sobre el tocon: un golpe grave que baja de tono."""
    m = int(.3 * SR)
    tt = np.arange(m) / SR
    f = 52 + 60 * np.exp(-tt * 26)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 13)


def saw_stroke(dur, bright, amp=1.0, seed=0):
    """Una pasada de sierra: ruido de banda que sube y baja."""
    m = int(dur * SR)
    x = np.random.RandomState(seed).normal(0, 1, m)
    x = _bandpass(x, 1800 * bright, 5200 * bright, .35)
    teeth = 1 + .5 * np.sin(2 * np.pi * 38 * np.arange(m) / SR)
    return amp * x * teeth * np.sin(np.linspace(0, np.pi, m)) ** 1.5


def pluck_bass(freq, dur=.9, amp=1.0, seed=0):
    """Contrabajo de madera por Karplus-Strong, muy apagado."""
    return _ks(freq, dur, amp, damp=.5, decay=2.4, seed=seed, bright=.15)


def _ks(freq, dur, amp, damp=.5, decay=1.5, seed=0, bright=.5):
    """Cuerda pulsada: una linea de retardo que se promedia a si misma."""
    m = int(dur * SR)
    period = max(2, int(round(SR / freq)))
    buf = np.random.RandomState(seed + int(freq)).uniform(-1, 1, period)
    for _ in range(1 + int((1 - bright) * 5)):
        buf = .5 * (buf + np.roll(buf, 1))
    buf /= np.max(np.abs(buf)) + 1e-12
    out = np.empty(m)
    i = 0
    while i < m:
        take = min(period, m - i)
        out[i:i + take] = buf[:take]
        buf = .998 * (damp * buf + (1 - damp) * np.roll(buf, 1))
        i += take
    tt = np.arange(m) / SR
    out = (out + .3 * np.sin(2 * np.pi * freq * tt)) * np.exp(-tt * decay)
    a = int(.004 * SR)
    out[:a] *= np.linspace(0, 1, a)
    r = int(.05 * SR)
    out[-r:] *= np.linspace(1, 0, r)
    return amp * out


def bamboo_flute(freq, dur, amp=1.0, seed=0, bend=True):
    """Flauta de bambu: armonicos impares fuertes, soplo filtrado a su tono,
    vibrato que llega tarde y, si toca, la entrada desde abajo (meri)."""
    m = int((dur + .25) * SR)
    tt = np.arange(m) / SR
    vib = .006 * np.clip((tt - .35) / .5, 0, 1) * np.sin(2 * np.pi * 5.2 * tt)
    glide = -.06 * np.exp(-tt * 14) if bend else 0
    f = freq * (1 + vib + glide)
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + .22 * np.sin(2 * ph) + .12 * np.sin(3 * ph) + .04 * np.sin(5 * ph)
    breath = _bandpass(np.random.RandomState(seed).normal(0, 1, m), freq * .8, freq * 3.5, .3)
    breath *= .09 + .35 * np.exp(-tt * 10)
    return amp * (tone + breath) * _env(m, .07, .22)


def kalimba(freq, amp=1.0, dur=2.2):
    """Kalimba: lamina de metal (modos 1, 5.9, 16.2) y el golpe del pulgar."""
    return _modal(freq, [1, 5.93, 16.2], [1, .25, .07], [1.6, 7, 16], dur, amp,
                  strike=.12, seed=int(freq * 3))


def glass(freq, dur, amp=1.0, attack=.6, release=1.4):
    """Armonica de cristal: casi un seno, con un batido lento de copa mojada."""
    m = int((dur + release) * SR)
    tt = np.arange(m) / SR
    x = (np.sin(2 * np.pi * freq * tt) + .5 * np.sin(2 * np.pi * freq * 1.003 * tt)
         + .12 * np.sin(2 * np.pi * freq * 2 * tt) + .05 * np.sin(2 * np.pi * freq * 3.01 * tt))
    return amp * x * _env(m, attack, release)


def drop(freq, amp=1.0):
    """Gota: una burbuja que resuena y sube de tono al cerrarse (Minnaert)."""
    m = int(.14 * SR)
    tt = np.arange(m) / SR
    f = freq * (1 + 1.3 * (1 - np.exp(-tt * 38)))
    return amp * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 34) * _env(m, .002, .02)


def shamisen(freq, dur=1.2, amp=1.0, seed=0):
    """Shamisen: cuerda de seda pulsada con bachi y el zumbido del sawari (la
    primera cuerda roza el mastil y hace un 'biin' que dura)."""
    x = _ks(freq, dur, 1.0, damp=.62, decay=2.2, seed=seed, bright=.85)
    env = np.abs(x)
    env = np.convolve(env, np.ones(200) / 200, mode="same")
    buzz = np.tanh(6 * x) - np.tanh(2 * x)
    buzz = _bandpass(buzz, 1500, 7000, .3) * np.clip(env * 4, 0, 1)
    k = int(.01 * SR)
    bachi = np.zeros(len(x))
    bachi[:k] = np.random.RandomState(seed + 7).normal(0, 1, k) * np.exp(-np.linspace(0, 8, k))
    bachi = _bandpass(bachi, 900, 5000)
    return amp * (x + .35 * buzz + .5 * bachi)


def toy_piano(freq, amp=1.0, dur=1.1):
    """Piano de juguete: FM con una razon inarmonica (varillas de metal)."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    index = 2.2 * np.exp(-tt * 10)
    x = np.sin(2 * np.pi * freq * tt + index * np.sin(2 * np.pi * freq * 3.5 * tt))
    x += .25 * np.sin(2 * np.pi * freq * 2 * tt) * np.exp(-tt * 6)
    return amp * x * np.exp(-tt * 3.8) * _env(m, .002, .05)


def fm_bass(freq, dur=.5, amp=1.0):
    m = int(dur * SR)
    tt = np.arange(m) / SR
    index = 1.4 * np.exp(-tt * 12)
    x = np.sin(2 * np.pi * freq * tt + index * np.sin(2 * np.pi * freq * tt))
    return amp * x * np.exp(-tt * 3) * _env(m, .006, .06)


def taiko(amp=1.0, seed=0):
    m = int(.5 * SR)
    tt = np.arange(m) / SR
    f = 62 + 40 * np.exp(-tt * 18)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7)
    skin = _bandpass(np.random.RandomState(seed).normal(0, 1, m), 200, 900) * np.exp(-tt * 40)
    return amp * (body + .25 * skin)


def atarigane(amp=1.0, open_=False):
    """Gong de mano de las bandas de calle: metal agudo y corto."""
    return _modal(1830, [1, 1.47, 2.09, 2.56, 3.9], [1, .7, .5, .3, .15],
                  [9, 12, 16, 20, 30] if not open_ else [4, 6, 8, 10, 15],
                  .5, amp, strike=.4, seed=3)


# Coro granular: una voz hecha de armonicos con formantes, troceada en granos.
_VOWELS = {"a": [(730, 90), (1090, 110), (2440, 160)],
           "o": [(500, 80), (850, 100), (2400, 160)],
           "u": [(320, 60), (800, 90), (2240, 150)]}


def _voice(f0, vowel, dur=2.5, seed=0):
    m = int(dur * SR)
    tt = np.arange(m) / SR
    vib = 1 + .004 * np.sin(2 * np.pi * 5.1 * tt + seed)
    ph = 2 * np.pi * np.cumsum(f0 * vib) / SR
    out = np.zeros(m)
    for k in range(1, int(5000 / f0)):
        fk = k * f0
        g = sum(np.exp(-((fk - fc) / bw) ** 2 / 2) * (1 if i == 0 else .6 / i)
                for i, (fc, bw) in enumerate(_VOWELS[vowel]))
        out += (g + .02) / k ** .6 * np.sin(k * ph)
    return out / (np.max(np.abs(out)) + 1e-12)


def grain_cloud(L, R, t0, dur, freqs, vowel, amp, density=26, seed=0):
    """Siembra granos de 70-160 ms de las voces del acorde entre t0 y t0+dur."""
    rng = np.random.RandomState(seed)
    sources = [_voice(f, vowel, seed=i + seed) for i, f in enumerate(freqs)]
    count = int(dur * density * len(freqs))
    for _ in range(count):
        src = sources[rng.randint(len(sources))]
        g = int(rng.uniform(.07, .16) * SR)
        p = rng.randint(0, len(src) - g)
        grain = src[p:p + g] * np.hanning(g)
        _put(L, R, t0 + rng.uniform(0, dur), grain * amp, rng.uniform(.2, .8))


# ---------------------------------------------------------------- canciones

def _bars(bpm, bars):
    beat = 60.0 / bpm
    n = int(round(bars * 4 * beat * SR))
    return beat, np.zeros(n), np.zeros(n)


def song_asa():
    """La mañana: el pueblo se pone a trabajar."""
    bpm, bars = 100.0, 24
    beat, L, R = _bars(bpm, bars)
    D = {"D": [50, 57, 62, 66], "D/F#": [42, 57, 62, 66], "G": [43, 59, 62, 67],
         "A": [45, 57, 61, 64], "A7": [45, 55, 61, 64], "Bm": [47, 54, 62, 66],
         "Em7": [40, 55, 62, 67], "F#m": [42, 57, 61, 66]}
    prog = (["D", "D", "G", "A"]                                   # entrada
            + ["D", "D/F#", "G", "A", "Bm", "G", "Em7", "A7"]      # A: flauta
            + ["G", "A", "F#m", "Bm", "G", "A", "D", "D"]          # B: yunque
            + ["G", "A", "D", "D"])                                # salida

    # Bajo pulsado: fundamental, quinta y una nota de paso hacia el siguiente.
    for b, name in enumerate(prog):
        root = D[name][0]
        nxt = D[prog[(b + 1) % bars]][0]
        t = b * 4 * beat
        _put(L, R, t, pluck_bass(_midi(root), amp=.5, seed=b), .5)
        _put(L, R, t + 2 * beat, pluck_bass(_midi(root + 7), amp=.38, seed=b + 50), .5)
        if b % 2 == 1:
            _put(L, R, t + 3.5 * beat, pluck_bass(_midi(nxt - 1 if nxt > root else nxt + 2), .4, .3, b), .5)

    # Herramientas: tocon en 1 y 3, hacha en 3 de 8, sierra en 2 y 4.
    chop_steps = _euclid(3, 8)
    for b in range(bars):
        t = b * 4 * beat
        last = b == bars - 1
        intro = b < 2
        for k in (0, 2):
            if last and k == 2:
                continue
            _put(L, R, t + k * beat, stump(.55 if k == 0 else .42), .5)
        if not intro:
            for s in chop_steps:
                if last and s >= 4:
                    continue
                _put(L, R, t + s * beat / 2, chop(520 if s == 0 else 640, .22, b * 8 + s), .35)
        if b >= 2 and not last:
            for k in (1, 3):
                _put(L, R, t + k * beat, saw_stroke(beat * .5, 1 if k == 1 else 1.25, .05, b * 4 + k), .7)

    # Acordes suaves de flauta baja (sho) para sostener, sin golpe.
    for b, name in enumerate(prog):
        for i, note in enumerate(D[name][1:]):
            _put(L, R, b * 4 * beat, bamboo_flute(_midi(note), 4 * beat, .045, b * 5 + i, bend=False), .3 + .2 * i)

    # A: la flauta canta. (compas relativo, pulso, nota, duracion)
    mel_a = [(0, 0, 74, 1.5), (0, 1.5, 76, .5), (0, 2, 78, 1), (0, 3, 81, 1),
             (1, 0, 78, 1), (1, 1, 76, .5), (1, 1.5, 74, .5), (1, 2, 76, 2),
             (2, 0, 83, 1), (2, 1, 81, .5), (2, 1.5, 79, .5), (2, 2, 78, 1), (2, 3, 76, 1),
             (3, 0, 76, 1.5), (3, 1.5, 78, .5), (3, 2, 81, 2),
             (4, 0, 83, 1), (4, 1, 86, 1), (4, 2, 83, .5), (4, 2.5, 81, .5), (4, 3, 78, 1),
             (5, 0, 79, 1.5), (5, 1.5, 78, .5), (5, 2, 76, 1), (5, 3, 74, 1),
             (6, 0, 76, 1), (6, 1, 79, 1), (6, 2, 78, .5), (6, 2.5, 76, .5), (6, 3, 74, 1),
             (7, 0, 73, 1), (7, 1, 76, 1), (7, 2, 81, 2)]
    for i, (bar, pos, note, dur) in enumerate(mel_a):
        t = (4 + bar) * 4 * beat + pos * beat
        _put(L, R, t, bamboo_flute(_midi(note), dur * beat, .22, i, bend=dur >= 1), .45)

    # B: el yunque afinado arpegia en 5 de 8 y la flauta sostiene.
    anvil_steps = _euclid(5, 8)
    for b in range(12, 20):
        tones = D[prog[b]][1:] + [D[prog[b]][1] + 12]
        for j, s in enumerate(anvil_steps):
            note = tones[j % len(tones)] + 24
            while note > 93:
                note -= 12
            _put(L, R, b * 4 * beat + s * beat / 2, anvil(_midi(note), .11), .6)
    long_b = [(0, 78, 2), (2, 76, 2), (4, 76, 4), (8, 73, 2), (10, 76, 2), (12, 78, 4),
              (16, 74, 2), (18, 71, 2), (20, 73, 2), (22, 76, 2), (24, 74, 6)]
    for i, (pos, note, dur) in enumerate(long_b):
        _put(L, R, 12 * 4 * beat + pos * beat, bamboo_flute(_midi(note), dur * beat, .18, 40 + i), .5)

    # Salida: la flauta recuerda el principio y una kalimba anuncia el agua.
    for i, (bar, pos, note, dur) in enumerate(mel_a[:8]):
        t = (20 + bar) * 4 * beat + pos * beat
        _put(L, R, t, bamboo_flute(_midi(note), dur * beat, .16, 80 + i), .45)
    for pos, note in ((2, 76), (2.5, 73), (3, 69)):
        _put(L, R, (bars - 1) * 4 * beat + pos * beat, kalimba(_midi(note), .12), .65)

    L = _reverb_circular(L, 1.8, .22, 71)
    R = _reverb_circular(R, 1.8, .22, 72)
    return np.stack([L, R], axis=1)


def song_mizuba():
    """Mediodia en el agua: dos kalimbas que se desfasan y vuelven a juntarse."""
    bpm, bars = 66.0, 15
    beat, L, R = _bars(bpm, bars)
    six = beat / 4
    total = bars * 16

    # Fase: 16 contra 15 semicorcheas. mcm(16, 15) = 240 = 15 compases.
    ost_a = [69, 73, 76, 81, 76, 73, 71, 76, 69, 73, 76, 83, 76, 73, 71, 73]
    ost_b = [85, 83, 81, 76, 78, 81, 83, 76, 85, 81, 78, 76, 83, 81, 76]
    for s in range(total):
        a = ost_a[s % 16]
        _put(L, R, s * six, kalimba(_midi(a), .10 if s % 4 else .13), .3)
        b = ost_b[s % 15]
        _put(L, R, s * six, kalimba(_midi(b), .055), .72)

    # Armonica de cristal: cinco acordes de tres compases, fundidos.
    chords = [[57, 64, 71, 73], [54, 61, 64, 71], [50, 57, 61, 64], [47, 54, 57, 64], [52, 59, 61, 66]]
    roots = [33, 30, 38, 35, 40]
    seg = 3 * 4 * beat
    for c, (chord, root) in enumerate(zip(chords, roots)):
        t = c * seg - 1.0
        for i, note in enumerate(chord):
            _put(L, R, t, glass(_midi(note), seg + .4, .05 / (1 + .3 * i), attack=1.6, release=1.6), .25 + .17 * i)
        _put(L, R, t, glass(_midi(root), seg + .4, .16, attack=1.6, release=1.6), .5)

    # Melodia de cristal, lenta. (pulso, duracion, nota)
    mel = [(2, 4, 76), (8, 4, 73), (14, 6, 71), (22, 4, 78), (28, 6, 76),
           (36, 3, 81), (40, 5, 80), (46, 4, 76), (52, 5, 73)]
    for start, dur, note in mel:
        _put(L, R, start * beat, glass(_midi(note), dur * beat, .09, attack=.35, release=1.2), .5)

    # Gotas afinadas en la pentatonica, pocas y siempre en los mismos sitios.
    rng = np.random.RandomState(17)
    penta = [81, 83, 85, 88, 90, 93]
    for b in range(bars):
        for _ in range(2 + b % 2):
            t = (b * 4 + rng.uniform(0, 4)) * beat
            _put(L, R, t, drop(_midi(penta[rng.randint(len(penta))]), .07), rng.uniform(.15, .85))

    # El ultimo compas deja sonar un shamisen en Mi: viene el mercado.
    _put(L, R, (bars - 1) * 4 * beat + 3 * beat, shamisen(_midi(64), 1.6, .12, 5), .4)

    L = _reverb_circular(L, 3.0, .38, 81)
    R = _reverb_circular(R, 3.0, .38, 82)
    return np.stack([L, R], axis=1)


def song_yuyake():
    """El mercado al atardecer, en Mi dorico y con swing."""
    bpm, bars = 88.0, 24
    beat, L, R = _bars(bpm, bars)
    swing = .64

    def at(bar, pos):
        whole = int(pos)
        frac = pos - whole
        if abs(frac - .5) < 1e-6:
            frac = swing
        return (bar * 4 + whole + frac) * beat

    C = {"Em7": [52, 59, 62, 67], "A9": [45, 61, 64, 67, 71], "Cmaj7": [48, 59, 64, 67],
         "D": [50, 62, 66, 69], "Bm7": [47, 57, 62, 66], "Am7": [45, 60, 64, 67],
         "D9": [50, 60, 64, 66], "Gmaj7": [43, 59, 62, 66], "F#m7": [42, 57, 61, 64],
         "D6": [50, 59, 62, 66], "Em9": [40, 59, 62, 66, 67]}
    prog = (["Em7", "A9", "Em7", "A9", "Cmaj7", "D", "Em7", "Bm7"]
            + ["Am7", "D9", "Gmaj7", "Cmaj7", "F#m7", "Bm7", "Cmaj7", "D6"]
            + ["Em7", "A9", "Em7", "A9", "Cmaj7", "D", "Em9", "Em9"])

    # Coro granular: vocal 'a' en las A y 'o' en el puente.
    for b, name in enumerate(prog):
        vowel = "o" if 8 <= b < 16 else "a"
        freqs = [_midi(n) for n in C[name][1:]]
        grain_cloud(L, R, b * 4 * beat - .1, 4 * beat + .2, freqs, vowel, .05, seed=b)

    # Bajo andante: fundamental, quinta u octava, y aproximacion cromatica.
    for b, name in enumerate(prog):
        root = C[name][0]
        nxt = C[prog[(b + 1) % bars]][0]
        walk = [root, root + 7, root + 12 if b % 2 else root + 10, nxt + (1 if nxt < root else -1)]
        for k, note in enumerate(walk):
            while note > 57:
                note -= 12
            _put(L, R, at(b, k), fm_bass(_midi(note), beat * .9, .42 if k == 0 else .34), .5)

    # Percusion de feria: taiko «don-don», atarigane en 2 y 4 con «chiki».
    for b in range(bars):
        for pos, a in ((0, .55), (1.5, .35), (2, .45)):
            _put(L, R, at(b, pos), taiko(a, b * 3 + int(pos * 2)), .5)
        for pos in (1, 3):
            _put(L, R, at(b, pos), atarigane(.09), .68)
        for pos in (1.5, 3.5):
            _put(L, R, at(b, pos), atarigane(.04), .75)

    # Shamisen en las A. (compas, pulso, nota, duracion)
    sh_a = [(0, 0, 64, .5), (0, .5, 67, .5), (0, 1, 71, 1), (0, 2.5, 69, .5), (0, 3, 67, 1),
            (1, .5, 69, .5), (1, 1, 71, .5), (1, 1.5, 74, 1), (1, 3, 71, 1),
            (2, 0, 76, 1), (2, 1, 74, .5), (2, 1.5, 71, .5), (2, 2, 69, 1), (2, 3, 67, .5), (2, 3.5, 69, .5),
            (3, 0, 71, 2), (3, 2.5, 67, .5), (3, 3, 64, 1),
            (4, 0, 67, .5), (4, .5, 71, .5), (4, 1, 74, 1), (4, 2, 76, .5), (4, 2.5, 79, 1), (4, 3.5, 76, .5),
            (5, 0, 74, 1), (5, 1, 78, .5), (5, 1.5, 76, .5), (5, 2, 74, 1), (5, 3, 71, 1),
            (6, 0, 76, .5), (6, .5, 74, .5), (6, 1, 71, .5), (6, 1.5, 69, .5), (6, 2, 67, 1), (6, 3, 69, 1)]
    for i, (bar, pos, note, dur) in enumerate(sh_a):
        for base in (0, 16):
            if base == 16 and bar == 6:
                continue
            _put(L, R, at(base + bar, pos), shamisen(_midi(note), max(.6, dur * beat + .3), .2, i + base), .38)
    # Compas 7: tremolo sobre Si, como un vendedor que alarga el pregon.
    for k in range(12):
        _put(L, R, 7 * 4 * beat + k * beat / 4, shamisen(_midi(71), .5, .13 * (1 - k / 16), 90 + k), .38)

    # Puente: piano de juguete pregunta y el shamisen contesta con el acorde.
    toy = [(8, 0, 81, 1), (8, 1, 79, .5), (8, 1.5, 76, 1),
           (9, 0, 78, 1), (9, 1, 76, .5), (9, 1.5, 74, 1),
           (10, 0, 79, 1), (10, 1, 83, 1), (10, 2, 81, .5),
           (11, 0, 76, 2),
           (12, 0, 78, 1), (12, 1, 81, .5), (12, 1.5, 78, .5),
           (13, 0, 74, 1), (13, 1, 78, .5), (13, 1.5, 74, .5),
           (14, 0, 72, .5), (14, .5, 76, .5), (14, 1, 79, .5), (14, 1.5, 83, 1),
           (15, 0, 81, 1), (15, 1, 78, 1)]
    for bar, pos, note, dur in toy:
        _put(L, R, at(bar, pos), toy_piano(_midi(note), .16), .62)
    for b in range(8, 16):
        tones = sorted(C[prog[b]][1:], reverse=True)[:3]
        for k, note in enumerate(tones):
            _put(L, R, at(b, 2.5 + k * .5), shamisen(_midi(note), .7, .15, 200 + b * 3 + k), .35)

    # Final: el shamisen se despide y el yunque de la mañana ya suena en Re.
    for i, (pos, note, dur) in enumerate([(0, 76, 1), (1, 74, .5), (1.5, 71, .5), (2, 67, 2)]):
        _put(L, R, at(22, pos), shamisen(_midi(note), dur * beat + .4, .2, 300 + i), .38)
    _put(L, R, at(23, 0), shamisen(_midi(64), 2.2, .2, 310), .38)
    _put(L, R, at(23, 3), anvil(_midi(86), .1), .6)

    L = _reverb_circular(L, 2.0, .24, 91)
    R = _reverb_circular(R, 2.0, .24, 92)
    return np.stack([L, R], axis=1)


SONGS = {"asa": song_asa, "mizuba": song_mizuba, "yuyake": song_yuyake}


# ------------------------------------------------------------------ salida

def _loudness(path):
    """Sonoridad integrada (LUFS) y pico verdadero (dBTP), medidos por ffmpeg."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True, check=True).stderr
    summary = out[out.rindex("Summary:"):]
    lufs = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))
    peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summary).group(1))
    return lufs, peak


def render(name, lufs=-15.5, ceiling=-1.5):
    """Nivelada como el resto (ganancia fija, no loudnorm), en ogg y mp3."""
    tmp = os.path.join(BGM_DIR, f"_{name}.wav")
    audio = SONGS[name]()
    write_wav(tmp, audio, peak=0.9)
    measured, peak = _loudness(tmp)
    gain = min(lufs - measured, ceiling - peak)
    print(f"  {name}: {len(audio) / SR:.1f} s, {measured:.1f} LUFS, pico {peak:.1f} dBTP, ganancia {gain:+.1f} dB")
    for ext, codec in (("ogg", ["-c:a", "libvorbis", "-q:a", "5"]), ("mp3", ["-c:a", "libmp3lame", "-q:a", "3"])):
        out = os.path.join(BGM_DIR, f"{name}.{ext}")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                        "-af", f"volume={gain:.2f}dB", *codec, out], check=True)
        print("  ->", os.path.relpath(out, ROOT), f"({os.path.getsize(out) // 1024} KiB)")
    os.remove(tmp)


if __name__ == "__main__":
    for name in sys.argv[1:] or SONGS:
        render(name)
