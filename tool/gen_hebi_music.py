#!/usr/bin/env python3
# Ibasho — la cancion de Hebi, la serpiente.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Uso:  python3 tool/gen_hebi_music.py
# Sale en assets/audio/bgm/hebi.ogg (y .mp3). Requiere numpy y ffmpeg.
#
# Re kumoi (Re Mi Fa La Sib), 108 bpm. La idea es la del juego: algo que
# crece. Un mokkin (marimba de madera, sintesis modal) toca un dibujo de ocho
# notas por proceso aditivo, a lo Philip Glass: primero una nota, luego dos,
# luego tres... hasta las ocho, y vuelve a encogerse hasta una. Sube y baja
# suma 64 semicorcheas, justo cuatro compases, asi que el proceso cierra con
# la armonia y con el bucle. Encima, un koto por Karplus-Strong brillante con
# su adorno de entrada, la flauta de bambu en la segunda vuelta, un cascabel
# de serpiente (ruido modulado a 40 Hz) que avisa al final de cada frase y
# percusion de madera con ritmos euclideos.
#
# Reutiliza los instrumentos y la salida de `gen_hataraki_music.py`: mismas
# normas (bucle circular, melodias compuestas, nivel fijo por ebur128).

import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])

import gen_hataraki_music as hm  # noqa: E402
from gen_audio import SR, _midi, _reverb_circular  # noqa: E402
from gen_hataraki_music import (  # noqa: E402
    _bandpass, _bars, _env, _euclid, _ks, _modal, _put, bamboo_flute, pluck_bass, taiko,
)


# ------------------------------------------------------------ instrumentos

def mokkin(freq, amp=1.0):
    """Marimba de madera: modos de una barra libre (1, 3.93, 9.2), corta."""
    return _modal(freq, [1, 3.93, 9.2], [1, .32, .08], [9, 22, 40], .5, amp,
                  strike=.18, seed=int(freq * 5))


def koto(freq, dur=1.4, amp=1.0, seed=0, grace=None):
    """Koto: cuerda de seda tensa, brillante, con la caja de paulonia. Si hay
    `grace`, una nota de adorno muy corta entra antes (como un oshide)."""
    x = _ks(freq, dur, 1.0, damp=.56, decay=1.9, seed=seed, bright=.95)
    body = _bandpass(x, 250, 3200, .4)
    out = .75 * x + .45 * body
    if grace is not None:
        g = _ks(grace, .09, .55, damp=.6, decay=8, seed=seed + 3, bright=.9)
        k = len(g)
        pad = np.zeros(len(out) + k)
        pad[:k] += g
        pad[k:] += out
        out = pad
    return amp * out


def woodblock(amp=1.0, high=True):
    f = 1250 if high else 820
    return _modal(f, [1, 2.71, 4.3], [1, .3, .1], [38, 60, 90], .18, amp, strike=.35, seed=11)


def rattle(dur=.55, amp=1.0, seed=0):
    """Cascabel de serpiente: segmentos de queratina que chocan unas 40 veces
    por segundo; ruido agudo modulado que sube y se apaga."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    noise = _bandpass(np.random.RandomState(seed).normal(0, 1, m), 3500, 11000, .25)
    am = (.5 + .5 * np.sin(2 * np.pi * 41 * tt)) ** 3
    return amp * noise * am * _env(m, .18, .2)


def shaker(amp=1.0, seed=0):
    m = int(.07 * SR)
    tt = np.arange(m) / SR
    n = _bandpass(np.random.RandomState(seed).normal(0, 1, m), 5000, 12000, .3)
    return amp * n * np.exp(-tt * 55) * _env(m, .004, .02)


# ---------------------------------------------------------------- cancion

def song_hebi():
    """La serpiente que crece: proceso aditivo en Re kumoi."""
    bpm, bars = 108.0, 24
    beat, L, R = _bars(bpm, bars)
    six = beat / 4

    # Acordes por compas: A (8), A' (8) y puente (8).
    C = {"Dm9": [38, 62, 65, 69, 76], "Bbmaj7": [34, 62, 65, 69, 70], "Gm9": [43, 58, 62, 65, 69],
         "Asus": [45, 62, 64, 67, 69], "A7": [45, 61, 64, 67, 69], "C": [36, 60, 64, 67, 72]}
    prog = (["Dm9", "Dm9", "Bbmaj7", "Bbmaj7", "Gm9", "Gm9", "Asus", "A7"] * 2
            + ["Bbmaj7", "C", "Dm9", "Dm9", "Bbmaj7", "C", "Asus", "A7"])

    # Proceso aditivo: 1, 2, ... 8 notas y de vuelta 7, ... 1 = 64 semicorcheas.
    motif = [74, 77, 76, 81, 82, 81, 77, 86]
    # Sobre La7 el Fa y el Sib chocan: se cambian por Mi y La, y el Do# entra.
    on_a = {77: 76, 82: 81, 74: 73}
    on_c = {82: 84, 77: 76}
    lengths = list(range(1, 9)) + list(range(7, 0, -1))
    seq = [i for n in lengths for i in range(n)]
    assert len(seq) == 64
    for s in range(bars * 16):
        idx = seq[s % 64]
        note = motif[idx]
        chord = prog[s // 16]
        if chord in ("A7", "Asus"):
            note = on_a.get(note, note)
        elif chord == "C":
            note = on_c.get(note, note)
        first = idx == 0
        _put(L, R, s * six, mokkin(_midi(note), .17 if first else .11), .3 if s % 2 else .38)
        # La cabeza de cada grupo, una octava abajo y a la derecha: se oye
        # como la cabeza de la serpiente que va delante.
        if first:
            _put(L, R, s * six, mokkin(_midi(note - 12), .09), .7)

    # Bajo de madera: en 1, la quinta sincopada y el regreso.
    for b, name in enumerate(prog):
        root = C[name][0]
        for pos, note, a in ((0, root, .4), (1.75, root + 7, .28), (2.5, root + 12, .25), (3.5, root + 7, .23)):
            _put(L, R, (b * 4 + pos) * beat, pluck_bass(_midi(note), .7, a, seed=b * 4 + int(pos * 4)), .5)

    # Colchon: las notas del acorde muy bajas en el koto, arpegiadas al empezar.
    for b, name in enumerate(prog):
        for k, note in enumerate(C[name][1:]):
            _put(L, R, (b * 4 + k * .08) * beat, koto(_midi(note), 2.4, .045, seed=400 + b * 7 + k), .22 + .14 * k)

    # Percusion: taiko en 1 y 3 (con un golpe de mas en el 4.5), bloque de
    # madera en euclideo 5 de 8 y shaker en 7 de 16.
    wb = _euclid(5, 8)
    sk = _euclid(7, 16)
    for b in range(bars):
        for pos, a in ((0, .3), (2, .23), (3.5, .16)):
            _put(L, R, (b * 4 + pos) * beat, taiko(a, seed=b * 5 + int(pos * 2)), .5)
        for k in wb:
            _put(L, R, (b * 4 + k * .5) * beat, woodblock(.07, high=k % 3 == 0), .64)
        for k in sk:
            _put(L, R, b * 4 * beat + k * six, shaker(.05 if k % 4 else .08, seed=b * 16 + k), .8)

    # Cascabel al final de cada frase de cuatro compases.
    for b in range(3, bars, 4):
        _put(L, R, (b * 4 + 3) * beat, rattle(.6, .11, seed=b), .85)

    # Koto: tema de las A. (compas, pulso, nota, adorno)
    theme = [(0, 0, 74, None), (0, 1, 77, None), (0, 1.5, 76, None), (0, 2, 74, None), (0, 3, 69, 70),
             (1, 0, 74, None), (1, 1.5, 81, None), (1, 2.5, 77, None), (1, 3, 76, None),
             (2, 0, 77, 76), (2, 1, 74, None), (2, 2, 70, None), (2, 3, 69, None),
             (3, 0, 74, None), (3, 2, 77, None), (3, 2.5, 81, None),
             (4, 0, 82, 81), (4, 1, 81, None), (4, 1.5, 77, None), (4, 2, 74, None), (4, 3, 77, None),
             (5, 0, 76, None), (5, 1, 74, None), (5, 2, 70, None), (5, 2.5, 69, None),
             (6, 0, 69, None), (6, 1, 74, None), (6, 1.5, 76, None), (6, 2, 81, 79),
             (7, 0, 79, None), (7, 1, 76, None), (7, 2, 73, None), (7, 3, 76, None)]
    for i, (bar, pos, note, grace) in enumerate(theme):
        g = _midi(grace) if grace else None
        _put(L, R, (bar * 4 + pos) * beat, koto(_midi(note), 1.4, .2, seed=i, grace=g), .45)

    # En A' la flauta toma el tema, mas largo y con el soplo, y el koto le
    # contesta con trinos cortos en los huecos.
    flute = [(8, 0, 74, 1.5), (8, 2, 77, .5), (8, 3, 76, 1), (9, 0, 74, 2), (9, 3, 69, 1),
             (10, 0, 77, 1.5), (10, 2, 74, 1), (10, 3, 70, 1), (11, 0, 69, 3),
             (12, 0, 82, 1.5), (12, 2, 81, .5), (12, 2.5, 77, 1.5), (13, 0, 74, 3),
             (14, 0, 76, 1), (14, 1, 81, 2), (15, 0, 79, 1.5), (15, 2, 76, 2)]
    for i, (bar, pos, note, dur) in enumerate(flute):
        _put(L, R, (bar * 4 + pos) * beat, bamboo_flute(_midi(note), dur * beat, .13, seed=i, bend=i % 3 == 0), .55)
    for b in (9, 11, 13):
        for k, note in enumerate((86, 84, 86, 81)):
            _put(L, R, (b * 4 + 3 + k * .25) * beat, koto(_midi(note), .5, .11, seed=600 + b * 4 + k), .3)

    # Puente: el koto sube por terceras sobre Sib y Do, la serpiente se enrosca
    # (la misma figura cada vez un tono mas arriba) y vuelve a casa por La7.
    coil = [70, 74, 77, 74]
    for b, shift in ((16, 0), (17, 2), (20, 0), (21, 2)):
        for k, note in enumerate(coil):
            for rep in range(2):
                _put(L, R, (b * 4 + rep * 2 + k * .5) * beat,
                     koto(_midi(note + shift + (12 if rep else 0)), .8, .15, seed=700 + b * 8 + rep * 4 + k), .42)
    bridge = [(18, 0, 81, 2), (18, 2, 77, 1), (18, 3, 76, 1), (19, 0, 74, 4),
              (22, 0, 76, 1), (22, 1, 79, 1), (22, 2, 81, 2), (23, 0, 73, 1), (23, 1, 76, 1), (23, 2, 79, 1),
              (23, 3, 81, 1)]
    for i, (bar, pos, note, dur) in enumerate(bridge):
        _put(L, R, (bar * 4 + pos) * beat, bamboo_flute(_midi(note), dur * beat, .12, seed=50 + i, bend=pos == 0), .55)

    L = _reverb_circular(L, 2.2, .26, 101)
    R = _reverb_circular(R, 2.2, .26, 102)
    return np.stack([L, R], axis=1)


if __name__ == "__main__":
    hm.SONGS["hebi"] = song_hebi
    hm.render("hebi")
