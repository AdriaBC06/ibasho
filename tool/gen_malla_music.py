#!/usr/bin/env python3
# Ibasho — la cancion de Malla, la de los hexagonos.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Uso:  python3 tool/gen_malla_music.py
# Sale en assets/audio/bgm/malla.ogg (y .mp3). Requiere numpy y ffmpeg.
#
# Fa lidio, 84 bpm, 21 compases (un minuto justo). La idea es la del juego:
# una malla que se va cerrando arista a arista. Dos procesos se cruzan a lo
# Steve Reich, como en mizuba: un handpan repite una celda de 6 semicorcheas
# (los seis lados del hexagono) y una kalimba otra de 7 (el tablero mas
# grande, 7x7). Se desfasan y solo vuelven a coincidir cada 42 semicorcheas;
# en 21 compases caben 336 = 8 x 42, asi que el bucle cierra con los dos en
# fase. Las dos celdas leen las notas del acorde que suena, asi que el dibujo
# se repite pero la armonia lo va tiñendo.
#
# Encima: coro granular en vocal «u» (como el de yuyake, mas suave), un koto
# por Karplus-Strong que canta la melodia, piano de juguete que le contesta,
# armonica de cristal con la cuarta aumentada del lidio en la entrada, bajo
# FM y clics de piedra de go sobre madera (sintesis modal) en ritmos
# euclideos, como fichas que se ponen en el tablero.
#
# Reutiliza instrumentos y salida de `gen_hataraki_music.py`: mismas normas
# (bucle circular, melodias compuestas, nivel fijo por ebur128).

import sys

import numpy as np

sys.path.insert(0, __file__.rsplit("/", 1)[0])

import gen_hataraki_music as hm  # noqa: E402
from gen_audio import SR, _midi, _reverb_circular  # noqa: E402
from gen_hataraki_music import (  # noqa: E402
    _bars, _euclid, _ks, _modal, _put, fm_bass, glass, grain_cloud, kalimba, taiko, toy_piano,
)


# ------------------------------------------------------------ instrumentos

def handpan(freq, amp=1.0):
    """Handpan: campana de acero afinada (fundamental, octava y quinta
    compuesta, un poco abiertas) con un golpe de yema blando."""
    return _modal(freq, [1, 2.002, 2.996, 4.02], [1, .38, .16, .05], [1.3, 2.6, 4.4, 7], 2.4, amp,
                  strike=.05, seed=int(freq * 7))


def koto(freq, dur=1.4, amp=1.0, seed=0):
    """Koto: cuerda brillante por Karplus-Strong con un poco de cuerpo."""
    return _ks(freq, dur, amp, damp=.58, decay=1.8, seed=seed, bright=.9)


def ishi(amp=1.0, seed=0, high=False):
    """Piedra de go sobre el tablero de madera: un clic seco y agudo con
    el cuerpo del tablero detras."""
    f = 1350 if high else 980
    stone = _modal(f, [1, 2.31, 3.87, 5.2], [1, .5, .25, .1], [55, 75, 95, 120], .12, 1.0, strike=.6, seed=seed)
    board = _modal(190, [1, 1.58, 2.2], [1, .4, .15], [22, 30, 40], .22, .5, strike=.0, seed=seed + 1)
    out = np.zeros(max(len(stone), len(board)))
    out[:len(stone)] += stone
    out[:len(board)] += board
    return amp * out


# ---------------------------------------------------------------- cancion

def song_malla():
    """Una malla que se va cerrando."""
    bpm, bars = 84.0, 21
    beat, L, R = _bars(bpm, bars)
    six = beat / 4
    swing = .58

    def at(bar, pos):
        whole = int(pos)
        frac = pos - whole
        if abs(frac - .5) < 1e-6:
            frac = swing
        return (bar * 4 + whole + frac) * beat

    # Siete acordes de tres compases. El ultimo (Do) devuelve a Fa.
    chords = [
        [41, 57, 64, 69, 71],  # Fmaj7(#11)
        [41, 55, 62, 67, 71],  # Sol/Fa
        [45, 60, 64, 67, 72],  # Lam7
        [40, 55, 59, 62, 67],  # Mim7
        [38, 57, 60, 64, 65],  # Rem9
        [43, 60, 62, 67, 74],  # Solsus
        [36, 55, 59, 62, 64],  # Domaj9
    ]

    def chord_at(sixteenth):
        return chords[(sixteenth // 16) // 3 % len(chords)]

    def tones(chord, low, count):
        """Las notas del acorde por encima de `low`, de grave a agudo."""
        out = []
        for octave in range(0, 48, 12):
            for n in chord[1:]:
                v = n + octave
                if v >= low and v not in out:
                    out.append(v)
        return sorted(out)[:count]

    total = bars * 16
    hexa = [0, 2, 1, 3, 2, 4]          # la celda de los seis lados
    septa = [0, 3, 1, 4, 2, 5, 3]      # la del tablero de siete
    for s in range(total):
        chord = chord_at(s)
        up = tones(chord, 67, 6)
        _put(L, R, s * six, handpan(_midi(up[hexa[s % 6]]), .085 if s % 6 else .11), .3)
        mid = tones(chord, 74, 7)
        _put(L, R, s * six + .004, kalimba(_midi(mid[septa[s % 7]]), .045, 1.6), .74)

    # Coro granular sobre los acordes, vocal «u».
    for c, chord in enumerate(chords):
        grain_cloud(L, R, c * 12 * beat - .1, 12 * beat + .2, [_midi(n) for n in chord[1:4]], "u", .035,
                    density=18, seed=40 + c)

    # Bajo: fundamental en el 1, quinta en el 3; en el tercer compas de cada
    # acorde, una aproximacion al siguiente.
    for b in range(bars):
        chord = chords[(b // 3) % len(chords)]
        root = chord[0]
        while root > 45:
            root -= 12
        _put(L, R, at(b, 0), fm_bass(_midi(root), beat * 1.8, .4), .5)
        if b % 3 == 2:
            nxt = chords[(b // 3 + 1) % len(chords)][0]
            while nxt > 45:
                nxt -= 12
            _put(L, R, at(b, 2), fm_bass(_midi(root + 7), beat * .9, .3), .5)
            _put(L, R, at(b, 3), fm_bass(_midi(nxt + (1 if nxt < root else -1)), beat * .9, .3), .5)
        else:
            _put(L, R, at(b, 2), fm_bass(_midi(root + 7), beat * 1.8, .32), .5)

    # Piedras de go: 5 en 16 y 3 en 8, que se cruzan; la de tres, mas aguda.
    five = _euclid(5, 16)
    three = _euclid(3, 8)
    for b in range(bars):
        for k in five:
            _put(L, R, b * 4 * beat + k * six, ishi(.12 if k == 0 else .08, b * 16 + k), .42)
        if b % 2:
            for k in three:
                _put(L, R, b * 4 * beat + (k * 2 + 1) * six, ishi(.05, 900 + b * 8 + k, high=True), .64)
        if b % 3 == 0:
            _put(L, R, at(b, 0), taiko(.28, b), .5)

    # Entrada: el cristal canta la cuarta aumentada (Si) del lidio.
    entry = [(0, 2, 76, 2), (1, 0, 83, 3), (2, 0, 81, 4), (3, 0, 79, 2), (3, 2, 83, 2), (4, 0, 86, 3), (5, 0, 83, 4)]
    for bar, pos, note, dur in entry:
        _put(L, R, at(bar, pos), glass(_midi(note), dur * beat, .075, attack=.4, release=1.3), .55)

    # Koto: la melodia, sobre La menor y Mi menor. (compas, pulso, nota, dur)
    koto_a = [(6, 0, 76, 1), (6, 1, 79, .5), (6, 1.5, 81, 1.5), (6, 3, 79, 1),
              (7, 0, 76, 1.5), (7, 1.5, 74, .5), (7, 2, 72, 2),
              (8, 0, 74, .5), (8, .5, 76, .5), (8, 1, 79, 1), (8, 2, 84, 1), (8, 3, 81, 1),
              (9, 0, 79, 2), (9, 2, 76, 1), (9, 3, 74, 1),
              (10, 0, 71, 1), (10, 1, 74, .5), (10, 1.5, 76, 1.5), (10, 3, 79, 1),
              (11, 0, 74, 2), (11, 2, 71, 2)]
    for i, (bar, pos, note, dur) in enumerate(koto_a):
        _put(L, R, at(bar, pos), koto(_midi(note), max(.7, dur * beat + .4), .2, i), .4)

    # El piano de juguete le contesta sobre Re menor y Sol.
    toy = [(12, 0, 81, 1), (12, 1, 77, .5), (12, 1.5, 76, 1), (12, 3, 74, 1),
           (13, 0, 72, 2), (13, 2, 74, 1), (13, 3, 77, 1),
           (14, 0, 76, 3),
           (15, 0, 79, 1), (15, 1, 74, .5), (15, 1.5, 71, 1), (15, 3, 74, 1),
           (16, 0, 72, 1), (16, 1, 74, 1), (16, 2, 79, 2),
           (17, 0, 83, 2), (17, 2, 79, 2)]
    for bar, pos, note, dur in toy:
        _put(L, R, at(bar, pos), toy_piano(_midi(note), .15, max(.8, dur * beat)), .6)

    # Cierre: el koto vuelve sobre Do y deja la malla abierta para empezar.
    close = [(18, 0, 76, 1), (18, 1, 79, 1), (18, 2, 83, 2), (19, 0, 81, 2), (19, 2, 79, 1), (19, 3, 76, 1),
             (20, 0, 74, 1), (20, 1, 72, 3)]
    for i, (bar, pos, note, dur) in enumerate(close):
        _put(L, R, at(bar, pos), koto(_midi(note), max(.7, dur * beat + .4), .2, 100 + i), .4)

    L = _reverb_circular(L, 2.6, .3, 61)
    R = _reverb_circular(R, 2.6, .3, 62)
    return np.stack([L, R], axis=1)


hm.SONGS["malla"] = song_malla

if __name__ == "__main__":
    hm.render("malla")
