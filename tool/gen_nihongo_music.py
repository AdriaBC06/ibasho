#!/usr/bin/env python3
# Ibasho — tres canciones originales para Nihongo, para elegir una.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Uso:  python3 tool/gen_nihongo_music.py [nombre ...]
# Sin nombres genera las tres en tool/music_drafts/. La elegida se copia a
# assets/audio/bgm/ (ogg y mp3) y se da de alta en `MusicTrack`.
# Requiere: numpy y ffmpeg en el PATH.

import os
import re
import subprocess
import sys

import numpy as np

from gen_audio import (SR, ROOT, _bass, _epiano, _kick, _loop_len, _marimba,
                       _midi, _noise_hit, _place, _reverb_circular, write_wav)

DRAFTS = os.path.join(ROOT, "tool", "music_drafts")


# -------------------------------------------------------------- instrumentos

def _koto(freq, dur=1.6, amp=1.0, bright=0.55, seed=0):
    """Cuerda pulsada (Karplus-Strong) con el ataque seco de la una del koto."""
    m = int(dur * SR)
    period = max(2, int(round(SR / freq)))
    rng = np.random.RandomState(seed + int(freq))
    buf = rng.uniform(-1, 1, period)
    # la una pulsa cerca del puente: menos graves en la excitacion
    buf = np.diff(np.concatenate([[0.0], buf])) * 0.6 + buf * 0.4
    # pero sin el chasquido: ruido crudo en el primer ciclo sonaba 28 dB por
    # encima del resto de la nota, y cada pulsacion era un golpe
    for _ in range(1 + int((1 - bright) * 4)):
        buf = 0.5 * (buf + np.roll(buf, 1))
    buf /= np.max(np.abs(buf)) + 1e-12
    out = np.empty(m)
    blend = 0.5 + 0.45 * bright
    i = 0
    while i < m:
        take = min(period, m - i)
        out[i:i + take] = buf[:take]
        nxt = blend * buf + (1 - blend) * np.roll(buf, -1)
        buf = 0.996 * (0.5 * nxt + 0.5 * np.roll(nxt, 1))
        i += take
    tt = np.arange(m) / SR
    # un poco de cuerpo afinado, que el ruido solo suena a guitarra de juguete
    body = 0.25 * np.sin(2 * np.pi * freq * tt) * np.exp(-tt * 3.0)
    x = (out + body) * np.exp(-tt * 1.1)
    a = int(0.006 * SR)
    x[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    r = int(0.08 * SR)
    x[-r:] *= np.linspace(1, 0, r)
    return amp * x


def _flute(freq, dur, amp=1.0, seed=0, vibrato=5.2):
    """Flauta de bambu: seno con soplo, vibrato que llega tarde y caida suave."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    depth = 0.006 * np.clip((tt - 0.18) / 0.35, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq * (1 + depth * np.sin(2 * np.pi * vibrato * tt))) / SR
    tone = np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase)
    breath = np.random.RandomState(seed).normal(0, 1, m)
    for _ in range(3):  # ruido de soplo, oscuro
        c = np.cumsum(np.insert(breath, 0, 0.0))
        breath = (c[8:] - c[:-8]) / 8
        breath = np.concatenate([breath, np.zeros(m - len(breath))])
    env = np.minimum(1.0, tt / 0.07) * np.minimum(1.0, (dur - tt) / 0.18).clip(0, 1)
    swell = 1.0 - 0.18 * np.exp(-tt * 6)  # el golpe de soplo del principio
    return amp * env * swell * (tone + 0.09 * breath * (1.2 - 0.5 * np.minimum(1, tt / 0.3)))


def _taiko(amp=1.0):
    m = int(0.45 * SR)
    tt = np.arange(m) / SR
    f = 62 + 40 * np.exp(-tt * 22)
    phase = 2 * np.pi * np.cumsum(f) / SR
    skin = _noise_hit(77, 0.45, 55, hp=False, amp=0.25)
    return amp * (np.sin(phase) * np.exp(-tt * 7) + skin * np.exp(-tt * 30))


def _woodblock(freq=1250.0, amp=1.0):
    m = int(0.09 * SR)
    tt = np.arange(m) / SR
    return amp * (np.sin(2 * np.pi * freq * tt) + 0.4 * np.sin(2 * np.pi * freq * 2.7 * tt)) * np.exp(-tt * 70)


def _pad(chord, dur, amp=1.0):
    """Colchon de fondo, con ataque y caida largos: no marca el pulso."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    x = np.zeros(m)
    for k, note in enumerate(chord):
        f = _midi(note)
        x += np.sin(2 * np.pi * f * tt + k) + 0.3 * np.sin(2 * np.pi * f * 2.003 * tt)
    fade = min(0.9, dur / 3)
    env = np.minimum(1.0, tt / fade) * np.minimum(1.0, (dur - tt) / fade).clip(0, 1)
    return amp * env * x / len(chord)


def _stereo(n):
    return np.zeros(n), np.zeros(n)


def _put(L, R, t0, sig, pan=0.5):
    _place(L, t0, sig * (1 - pan))
    _place(R, t0, sig * pan)


# ------------------------------------------------------------------ temas
#
# Melodias escritas a mano: (compas, pulso en corcheas desde el inicio del
# compas, duracion en corcheas, nota midi). Nada aleatorio salvo el soplo.

def song_terakoya(bpm=90.0, bars=24):
    """
    La escuela del templo. Escala yo en re (re mi sol la si), koto que
    arpegia en corcheas, shakuhachi con la melodia y un taiko lejano. Tranquila
    pero con paso: se puede pensar encima.

    Tres partes de ocho compases: la flauta canta A y B, y en la tercera
    descansa y el koto recuerda A en voz baja antes de volver al principio.
    El taiko y el bajo van por debajo del resto: en cada compas eran lo unico
    que se oia.
    """
    beat = 60.0 / bpm
    e8 = beat / 2
    n = _loop_len(bars * 4 * beat)
    L, R = _stereo(n)

    # D  Bm  G  A  | D  Em  G  A(sus)
    chords = [(50, [62, 66, 69, 74]), (47, [62, 66, 71, 74]), (43, [62, 67, 71, 74]), (45, [64, 69, 71, 76]),
              (50, [62, 66, 69, 74]), (52, [64, 67, 71, 76]), (43, [62, 67, 71, 74]), (45, [64, 69, 74, 76])]
    arp = [0, 2, 1, 3, 2, 1, 3, 2]
    for bar in range(bars):
        root, chord = chords[bar % 8]
        t_bar = bar * 4 * beat
        rest = bar >= 16  # la tercera parte, mas desnuda
        for i, k in enumerate(arp):
            _put(L, R, t_bar + i * e8,
                 _koto(_midi(chord[k]), 1.3, (0.10 if rest else 0.12) - 0.02 * (i % 2), bright=0.45,
                       seed=bar * 8 + i),
                 0.30 + 0.05 * k)
        _put(L, R, t_bar, _koto(_midi(root - 12), 2.4, 0.11, bright=0.15, seed=bar), 0.45)
        _put(L, R, t_bar + 4 * e8, _koto(_midi(root - 5), 1.8, 0.07, bright=0.15, seed=bar + 99), 0.5)
        _put(L, R, t_bar, _pad(chord, 4 * beat + 0.8, 0.05), 0.5)
        if not rest or bar % 2 == 0:
            _put(L, R, t_bar, _taiko(0.12 if bar % 2 == 0 else 0.08), 0.5)
        if bar % 4 == 3 and not rest:
            _put(L, R, t_bar + 7 * e8, _taiko(0.06), 0.5)
        for i in (2, 6):
            _put(L, R, t_bar + i * e8, _woodblock(amp=0.022), 0.7)

    a = [(0, 0, 3, 74), (0, 3, 1, 76), (0, 4, 4, 79),
         (1, 0, 2, 78), (1, 2, 2, 76), (1, 4, 4, 74),
         (2, 0, 3, 71), (2, 3, 1, 74), (2, 4, 2, 76), (2, 6, 2, 79),
         (3, 0, 8, 76),
         (4, 0, 3, 81), (4, 3, 1, 79), (4, 4, 4, 78),
         (5, 0, 2, 76), (5, 2, 2, 79), (5, 4, 4, 71),
         (6, 0, 3, 74), (6, 3, 1, 71), (6, 4, 2, 69), (6, 6, 2, 71),
         (7, 0, 8, 74)]
    b = [(0, 0, 2, 78), (0, 2, 2, 81), (0, 4, 4, 83),
         (1, 0, 2, 81), (1, 2, 2, 78), (1, 4, 4, 76),
         (2, 0, 3, 79), (2, 3, 1, 78), (2, 4, 4, 76),
         (3, 0, 2, 74), (3, 2, 6, 76),
         (4, 0, 3, 78), (4, 3, 1, 76), (4, 4, 4, 74),
         (5, 0, 2, 71), (5, 2, 2, 74), (5, 4, 4, 76),
         (6, 0, 4, 71), (6, 4, 4, 69),
         (7, 0, 8, 74)]
    for off, phrase in ((0, a), (8, b)):
        for bar, pos, length, note in phrase:
            t0 = (off + bar) * 4 * beat + pos * e8
            _put(L, R, t0, _flute(_midi(note), length * e8 + 0.12, 0.085, seed=bar * 16 + pos), 0.58)
    for bar, pos, length, note in a:  # el recuerdo, en el koto y una octava abajo
        t0 = (16 + bar) * 4 * beat + pos * e8
        _put(L, R, t0, _koto(_midi(note - 12), min(2.4, length * e8 + 0.9), 0.10, bright=0.35,
                             seed=300 + bar * 8 + pos), 0.62)

    L = _reverb_circular(L, 2.6, 0.30, 21)
    R = _reverb_circular(R, 2.6, 0.30, 22)
    return np.stack([L, R], axis=1)


def song_hanami(bpm=112.0, bars=16):
    """
    Ver los cerezos. La de mas ritmo: marimba y koto a pregunta y respuesta
    sobre un bajo con swing, en el espiritu de las tiendas de consola pero con
    la pentatonica mayor y los adornos del koto. Alegre, para ir acertando.
    """
    beat = 60.0 / bpm
    n = _loop_len(bars * 4 * beat)
    L, R = _stereo(n)
    swing = 0.60

    def at(bar, pos):  # pos en corcheas, con swing en las impares
        return (bar * 4 + pos // 2 + (swing if pos % 2 else 0.0)) * beat

    # Fmaj9  Em7  Dm9  G6/9 | Fmaj9  Am9  Dm9  Gsus-G
    prog = [(41, [64, 67, 69, 72]), (40, [62, 67, 71, 74]), (38, [65, 69, 72, 76]), (43, [64, 69, 71, 74]),
            (41, [64, 67, 69, 72]), (45, [67, 71, 72, 76]), (38, [65, 69, 72, 76]), (43, [65, 67, 72, 74])]
    for bar in range(bars):
        root, chord = prog[bar % 8]
        for b, note in enumerate([root, root + 7, root + 12, root + 7]):
            _put(L, R, (bar * 4 + b) * beat, _bass(_midi(note), amp=0.28 if b == 0 else 0.21), 0.5)
        for pos in (1, 3, 4, 7):
            for k, note in enumerate(chord):
                _put(L, R, at(bar, pos), _epiano(_midi(note), 0.5, 0.040 / (1 + 0.3 * k)), 0.38 + 0.07 * k)
        for b in range(4):
            if b in (0, 2):
                _put(L, R, (bar * 4 + b) * beat, _kick(0.26 if b == 0 else 0.18), 0.5)
            else:
                _put(L, R, (bar * 4 + b) * beat, _woodblock(980, 0.045), 0.35)
            for off in (0, 1):
                _put(L, R, at(bar, b * 2 + off),
                     _noise_hit(900 + bar * 8 + b * 2 + off, 0.035, 80, amp=0.010 if off else 0.007), 0.65)

    # marimba pregunta (compases pares), koto responde (impares)
    q = [(0, 0, 72), (0, 1, 74), (0, 2, 76), (0, 4, 79), (0, 6, 76),
         (2, 0, 74), (2, 1, 76), (2, 2, 79), (2, 4, 81), (2, 5, 79), (2, 6, 76),
         (4, 0, 81), (4, 2, 79), (4, 3, 76), (4, 4, 79), (4, 6, 84),
         (6, 0, 81), (6, 1, 79), (6, 2, 76), (6, 4, 74), (6, 6, 72)]
    r = [(1, 1, 84), (1, 2, 81), (1, 4, 79), (1, 5, 76),
         (3, 1, 79), (3, 2, 81), (3, 3, 84), (3, 4, 86),
         (5, 1, 88), (5, 2, 86), (5, 4, 84), (5, 5, 81),
         (7, 0, 79), (7, 2, 76), (7, 3, 74), (7, 4, 72)]
    for rep in range(bars // 8):
        for bar, pos, note in q:
            _put(L, R, at(bar + rep * 8, pos), _marimba(_midi(note), amp=0.15), 0.42)
        for bar, pos, note in r:
            t0 = at(bar + rep * 8, pos)
            _put(L, R, t0, _koto(_midi(note), 1.1, 0.12, seed=bar * 8 + pos), 0.62)
            if rep == 1 and pos == 1:  # adorno: la respuesta se duplica a la octava la segunda vez
                _put(L, R, t0 + 0.012, _koto(_midi(note - 12), 1.1, 0.06, seed=pos), 0.66)

    L = _reverb_circular(L, 1.7, 0.22, 31)
    R = _reverb_circular(R, 1.7, 0.22, 32)
    return np.stack([L, R], axis=1)


def song_sumi(bpm=78.0, bars=16):
    """
    Tinta. Tranquila y de estudio: piano electrico con acordes de noveno, koto
    en la escala in (la sib re mi fa) que canta a ratos y deja huecos, pulso
    suave de bombo y aro. La que menos distrae.
    """
    beat = 60.0 / bpm
    e8 = beat / 2
    n = _loop_len(bars * 4 * beat)
    L, R = _stereo(n)

    # Dm9  Bbmaj7  Gm9  A7sus | Dm9  Fmaj7  Bbmaj7  Asus-A
    prog = [(38, [65, 69, 72, 76]), (46, [62, 65, 69, 74]), (43, [65, 69, 70, 74]), (45, [62, 67, 69, 74]),
            (38, [65, 69, 72, 76]), (41, [64, 67, 69, 72]), (46, [62, 65, 69, 74]), (45, [61, 64, 67, 69])]
    for bar in range(bars):
        root, chord = prog[bar % 8]
        t_bar = bar * 4 * beat
        _put(L, R, t_bar, _bass(_midi(root), 1.4, 0.30), 0.5)
        _put(L, R, t_bar + 5 * e8, _bass(_midi(root + 7), 0.8, 0.18), 0.5)
        for pos, gain in ((0, 1.0), (3, 0.7), (6, 0.8)):
            for k, note in enumerate(chord):
                _put(L, R, t_bar + pos * e8, _epiano(_midi(note), 1.2, 0.045 * gain / (1 + 0.25 * k)),
                     0.35 + 0.08 * k)
        _put(L, R, t_bar, _pad(chord, 4 * beat + 1.0, 0.03), 0.5)
        _put(L, R, t_bar, _kick(0.24), 0.5)
        _put(L, R, t_bar + 5 * e8, _kick(0.14), 0.5)
        for pos in (2, 6):
            _put(L, R, t_bar + pos * e8, _noise_hit(300 + bar * 2 + pos, 0.06, 75, amp=0.028), 0.4)
        for pos in range(8):
            _put(L, R, t_bar + pos * e8, _noise_hit(700 + bar * 8 + pos, 0.03, 90, amp=0.006), 0.7)

    mel = [(0, 1, 81), (0, 2, 82), (0, 4, 81), (0, 6, 77),
           (1, 3, 76), (1, 4, 74),
           (2, 0, 77), (2, 2, 81), (2, 3, 82), (2, 4, 86),
           (3, 2, 81), (3, 4, 76),
           (4, 1, 74), (4, 2, 76), (4, 4, 77), (4, 6, 81),
           (5, 2, 82), (5, 3, 81), (5, 4, 77),
           (6, 0, 76), (6, 2, 74), (6, 4, 70), (6, 6, 69),
           (7, 2, 74)]
    for rep in range(bars // 8):
        for bar, pos, note in mel:
            t0 = (bar + rep * 8) * 4 * beat + pos * e8
            _put(L, R, t0, _koto(_midi(note), 2.0, 0.14, bright=0.45, seed=bar * 8 + pos + rep), 0.6)
            if rep == 1 and bar in (3, 7):  # la segunda vuelta, un eco a la cuarta
                _put(L, R, t0 + 3 * e8, _koto(_midi(note - 5), 1.6, 0.06, seed=pos), 0.3)

    L = _reverb_circular(L, 2.4, 0.28, 41)
    R = _reverb_circular(R, 2.4, 0.28, 42)
    return np.stack([L, R], axis=1)


SONGS = {"terakoya": song_terakoya, "hanami": song_hanami, "sumi": song_sumi}


def _loudness(path):
    """Sonoridad integrada (LUFS) y pico verdadero (dBTP), medidos por ffmpeg."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True, check=True).stderr
    summary = out[out.rindex("Summary:"):]
    lufs = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))
    peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summary).group(1))
    return lufs, peak


def render(name, fn, lufs=-15.5, ceiling=-1.5):
    """
    Nivelada a la sonoridad de Plaza, en ogg y en mp3 para Windows.

    Con una ganancia fija, no con `loudnorm` en una pasada: ese filtro va
    subiendo y bajando el volumen sobre la marcha, y el final de la pista
    acababa a otro nivel que el principio, asi que el bucle se notaba. Si el
    pico no cabe, se queda algo mas baja antes que recortar.
    """
    os.makedirs(DRAFTS, exist_ok=True)
    tmp = os.path.join(DRAFTS, f"_{name}.wav")
    write_wav(tmp, fn(), peak=0.9)
    measured, peak = _loudness(tmp)
    gain = min(lufs - measured, ceiling - peak)
    print(f"  {name}: {measured:.1f} LUFS, pico {peak:.1f} dBTP, ganancia {gain:+.1f} dB")
    for ext, codec in (("ogg", ["-c:a", "libvorbis", "-q:a", "5"]), ("mp3", ["-c:a", "libmp3lame", "-q:a", "3"])):
        out = os.path.join(DRAFTS, f"{name}.{ext}")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                        "-af", f"volume={gain:.2f}dB", *codec, out], check=True)
        print("  ->", os.path.relpath(out, ROOT), f"({os.path.getsize(out) // 1024} KiB)")
    os.remove(tmp)


if __name__ == "__main__":
    for name in sys.argv[1:] or SONGS:
        render(name, SONGS[name])
