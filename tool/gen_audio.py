#!/usr/bin/env python3
# Ibasho — generador del set sonoro original.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Uso:  python3 tool/gen_audio.py
# Requiere: numpy y ffmpeg en el PATH.

import math
import os
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
BGM_DIR = os.path.join(ROOT, "assets", "audio", "bgm")


# ---------------------------------------------------------------- utilidades

def t(n):
    return np.arange(n, dtype=np.float64) / SR


def sine(freq, n, phase=0.0):
    return np.sin(2 * math.pi * freq * t(n) + phase)


def env_ad(n, attack, decay, curve=2.5):
    """Envolvente ataque/decaimiento exponencial, sin clics."""
    a = max(1, int(attack * SR))
    e = np.empty(n)
    a = min(a, n)
    e[:a] = np.linspace(0.0, 1.0, a) ** 0.6
    rest = n - a
    if rest > 0:
        e[a:] = np.exp(-np.linspace(0.0, curve, rest) * (0.5 / max(decay, 1e-6)))
    return e


def fade_edges(x, ms=4.0):
    n = int(SR * ms / 1000.0)
    if n * 2 >= len(x):
        return x
    ramp = np.linspace(0.0, 1.0, n)
    x[:n] *= ramp
    x[-n:] *= ramp[::-1]
    return x


def bell(freq, dur, amp=1.0, bright=1.0):
    """Campana FM suave: parciales inarmonicos con decaimientos distintos."""
    n = int(dur * SR)
    out = np.zeros(n)
    partials = [(1.0, 1.0, 1.0), (2.01, 0.42, 1.7), (2.98, 0.22, 2.6),
                (4.97, 0.11 * bright, 4.2), (7.03, 0.05 * bright, 6.0)]
    for mult, gain, decay in partials:
        out += gain * sine(freq * mult, n) * np.exp(-np.linspace(0, decay * 5.0, n))
    out *= env_ad(n, 0.004, 1.0, curve=0.0) ** 0.0  # ataque limpio
    out[:int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return amp * out


def soft_tone(freq, dur, amp=1.0, attack=0.012, curve=3.2, detune=0.0):
    n = int(dur * SR)
    x = sine(freq, n) + 0.30 * sine(freq * 2, n) + 0.10 * sine(freq * 3, n)
    if detune:
        x += 0.5 * (sine(freq * (1 + detune), n) + 0.30 * sine(freq * 2 * (1 + detune), n))
        x *= 0.66
    a = max(1, int(attack * SR))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a) ** 0.7
    e[a:] = np.exp(-np.linspace(0, curve, n - a))
    return amp * x * e


def reverb(x, mix=0.3, decay=2.2, pre=0.02):
    """Reverb barato: banco de peines + all-pass. Suficiente para un pad."""
    out = x.copy()
    wet = np.zeros(len(x) + int(SR * 3))
    wet[:len(x)] = x
    for delay_ms, g in ((29.7, 0.82), (37.1, 0.79), (41.1, 0.77), (43.7, 0.75)):
        d = int(SR * delay_ms / 1000.0)
        buf = np.zeros_like(wet)
        fb = g ** (1.0 / max(decay, 0.1))
        for i in range(d, len(wet)):
            buf[i] = wet[i] + fb * buf[i - d]
        wet = 0.5 * wet + 0.5 * buf
    pre_n = int(pre * SR)
    wet = np.concatenate([np.zeros(pre_n), wet])[:len(out)]
    peak = np.max(np.abs(wet)) or 1.0
    return (1 - mix) * out + mix * (wet / peak) * (np.max(np.abs(out)) or 1.0)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak / m)


def write_wav(path, mono_or_stereo, peak=0.9):
    x = normalize(np.asarray(mono_or_stereo, dtype=np.float64), peak)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("  ->", os.path.relpath(path, ROOT), f"({os.path.getsize(path) // 1024} KiB)")


# ------------------------------------------------------------------ efectos

def sfx_tick():
    """Golpecito de plastico al moverse entre canales.

    Sin silencio delante: el motor de efectos (SoLoud) dispara al instante, y
    cualquier margen solo anadiria retardo al pulsar.
    """
    n = int(0.085 * SR)
    body = soft_tone(1046.5, 0.085, 0.85, attack=0.0015, curve=6.5)
    body += 0.35 * soft_tone(2093.0, 0.085, 0.5, attack=0.0015, curve=9.0)
    click = np.random.RandomState(7).normal(0, 1, n) * np.exp(-np.linspace(0, 45, n)) * 0.10
    return fade_edges(body + click, 3.0)


def sfx_open():
    """Confirmacion al abrir un canal: dos notas ascendentes con brillo."""
    a = soft_tone(659.25, 0.16, 0.85, attack=0.004, curve=5.5)   # E5
    b = soft_tone(987.77, 0.42, 0.95, attack=0.004, curve=3.4)   # B5
    n = int(0.52 * SR)
    out = np.zeros(n)
    out[:len(a)] += a
    off = int(0.085 * SR)
    out[off:off + len(b)] += b[:n - off]
    out += 0.35 * bell(1975.53, 0.52)[:n]
    return fade_edges(reverb(out, mix=0.22), 3.0)


def sfx_back():
    """Vuelta atras: la misma figura, invertida y mas grave."""
    a = soft_tone(587.33, 0.14, 0.8, attack=0.004, curve=6.0)    # D5
    b = soft_tone(392.00, 0.38, 0.9, attack=0.004, curve=4.0)    # G4
    n = int(0.46 * SR)
    out = np.zeros(n)
    out[:len(a)] += a
    off = int(0.075 * SR)
    out[off:off + len(b)] += b[:n - off]
    return fade_edges(reverb(out, mix=0.18), 3.0)


def sfx_error():
    """Aviso: dos pulsos cortos, graves, sin agresividad."""
    def pulse(dur):
        n = int(dur * SR)
        x = sine(196.0, n) + 0.5 * sine(392.0, n) + 0.22 * sine(233.08, n)
        return x * env_ad(n, 0.005, 0.22, curve=6.0)
    p = pulse(0.11)
    gap = np.zeros(int(0.055 * SR))
    return fade_edges(np.concatenate([p, gap, p * 0.85]), 3.0)


def sfx_chime():
    """Campanilla de arranque: arpegio mayor con novena y cola de reverb."""
    notes = [(523.25, 0.00), (659.25, 0.115), (783.99, 0.230), (1174.66, 0.345)]
    n = int(2.6 * SR)
    out = np.zeros(n)
    for freq, delay in notes:
        d = int(delay * SR)
        b = bell(freq, 2.2, amp=1.0 - delay * 0.5, bright=1.0)
        out[d:d + len(b)] += b[:n - d]
    out += 0.22 * bell(261.63, 2.6, amp=0.7, bright=0.4)[:n]
    return fade_edges(reverb(out, mix=0.34, decay=2.8), 6.0)


# 
# ------------------------------------------------------- musica sin golpes
#
# Lo que rompia el ambiente de la primera pista eran transitorios: campanas con
# ataque seco en momentos aleatorios y un "respiro" de volumen en cada cambio
# de acorde. Estas variaciones no tienen ni una cosa ni otra:
#
#   - todo ataque dura como minimo un segundo;
#   - los acordes se funden con ventanas sin^2 / cos^2, cuya suma es 1, asi que
#     el volumen total no sube ni baja al cambiar de acorde;
#   - la reverb es una convolucion circular por FFT: la cola del final entra
#     por el principio y el bucle no tiene costura.

MUSIC_SECONDS = 64.0


def _loop_len(seconds):
    return int(seconds * SR)


def _xfade_window(total, start, length, fade):
    """Ventana circular: sube sin^2 en `fade`, se mantiene y baja cos^2."""
    n = _loop_len(total)
    w = np.zeros(n)
    s0 = int(start * SR)
    L = int((length + fade) * SR)
    F = int(fade * SR)
    idx = (np.arange(L) + s0) % n
    env = np.ones(L)
    ramp = np.sin(np.linspace(0, np.pi / 2, F)) ** 2
    env[:F] = ramp
    env[L - F:] = ramp[::-1]
    np.add.at(w, idx, env)
    return w, idx, env


def _pad_voice(freq, total, rng, bright=0.18, drift=0.0016):
    """Una voz de pad continua durante todo el bucle, sin ataque propio."""
    n = _loop_len(total)
    tt = np.arange(n) / SR
    # vibrato lentisimo con un numero entero de ciclos: cierra el bucle
    cycles = max(1, round(total * (0.05 + 0.04 * rng.rand())))
    lfo = np.sin(2 * np.pi * cycles * tt / total + rng.rand() * 6.28)
    # fundamental redondeada a un numero entero de ciclos por bucle: si no, la
    # onda no cierra y el bucle hace clic en la costura
    freq = round(freq * total) / total
    phase = 2 * np.pi * freq * tt + (drift * freq * total / cycles) * np.sin(2 * np.pi * cycles * tt / total)
    # frecuencias redondeadas al bucle para que cada parcial tambien lo cierre
    def partial(mult, gain):
        f = round(freq * mult * total) / total
        return gain * np.sin(2 * np.pi * f * tt + rng.rand() * 6.28)
    base = np.sin(phase)
    return (base
            + 0.55 * partial(1.0015, 1.0)
            + partial(2.0, bright * (0.8 + 0.2 * lfo))
            + partial(3.0, bright * 0.25))


def _reverb_circular(x, seconds=3.2, mix=0.35, seed=7, damp=0.9994):
    """Convolucion por FFT con una respuesta de ruido decreciente y oscura."""
    n = len(x)
    rng = np.random.RandomState(seed)
    m = int(seconds * SR)
    ir = rng.normal(0, 1, m) * np.exp(-np.linspace(0, 7.0, m))
    # paso bajo sencillo: media movil acumulada, dos pasadas
    for _ in range(2):
        c = np.cumsum(np.insert(ir, 0, 0.0))
        k = 24
        ir = (c[k:] - c[:-k]) / k
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    pad = np.zeros(n)
    pad[:len(ir)] = ir
    wet = np.real(np.fft.ifft(np.fft.fft(x) * np.fft.fft(pad)))
    wet *= (np.std(x) + 1e-12) / (np.std(wet) + 1e-12)
    return (1 - mix) * x + mix * wet


def _chord_pad(chords, total, fade, rng, bright=0.18, amp=0.20):
    n = _loop_len(total)
    left = np.zeros(n)
    right = np.zeros(n)
    bar = total / len(chords)
    for ci, chord in enumerate(chords):
        w, _, _ = _xfade_window(total, ci * bar - fade / 2, bar, fade)
        for vi, f in enumerate(chord):
            v = _pad_voice(f, total, rng, bright=bright) * w * (amp / (1.0 + 0.5 * vi))
            pan = 0.5 + 0.28 * np.sin(vi * 1.9 + ci * 0.8)
            left += v * (1 - pan)
            right += v * pan
    return left, right


def _legato_line(notes, total, amp=0.07, attack=1.4, release=2.6, seed=3):
    """Melodia de tonos puros con ataques largos: se oye, pero no golpea."""
    n = _loop_len(total)
    out = np.zeros(n)
    rng = np.random.RandomState(seed)
    for start, dur, freq in notes:
        L = int((dur + release) * SR)
        tt = np.arange(L) / SR
        env = np.ones(L)
        A = int(attack * SR)
        R = int(release * SR)
        env[:A] = np.sin(np.linspace(0, np.pi / 2, A)) ** 2
        env[L - R:] *= np.cos(np.linspace(0, np.pi / 2, R)) ** 2
        tone = (np.sin(2 * np.pi * freq * tt)
                + 0.18 * np.sin(2 * np.pi * freq * 2 * tt + rng.rand()))
        idx = (np.arange(L) + int(start * SR)) % n
        np.add.at(out, idx, amp * tone * env)
    return out


def music_calma(total=MUSIC_SECONDS):
    """La progresion de siempre, solo el pad. Sin campanas."""
    rng = np.random.RandomState(11)
    chords = [
        [130.81, 196.00, 329.63, 493.88, 587.33],   # Cmaj9
        [110.00, 164.81, 329.63, 493.88, 659.25],   # Am9
        [87.31, 174.61, 261.63, 392.00, 523.25],    # Fmaj9
        [98.00, 196.00, 293.66, 440.00, 587.33],    # G6/9
    ]
    l, r = _chord_pad(chords, total, fade=6.0, rng=rng)
    return np.stack([_reverb_circular(l, seed=1), _reverb_circular(r, seed=2)], axis=1)


def music_aurora(total=80.0):
    """Mas lenta y mas abierta: acordes de septima que bajan por grados."""
    rng = np.random.RandomState(23)
    chords = [
        [87.31, 130.81, 220.00, 329.63, 523.25],    # Fmaj7
        [82.41, 123.47, 196.00, 293.66, 493.88],    # Em7
        [73.42, 110.00, 174.61, 261.63, 329.63],    # Dm9
        [65.41, 98.00, 164.81, 246.94, 293.66],     # Cmaj9
    ]
    l, r = _chord_pad(chords, total, fade=9.0, rng=rng, bright=0.10, amp=0.22)
    return np.stack([_reverb_circular(l, 4.0, 0.45, 3), _reverb_circular(r, 4.0, 0.45, 4)], axis=1)


def music_brisa(total=MUSIC_SECONDS):
    """El pad de calma con una linea melodica muy suave y siempre igual."""
    rng = np.random.RandomState(31)
    chords = [
        [130.81, 196.00, 329.63, 493.88],
        [110.00, 164.81, 261.63, 392.00],
        [87.31, 174.61, 261.63, 440.00],
        [98.00, 146.83, 293.66, 440.00],
    ]
    l, r = _chord_pad(chords, total, fade=6.0, rng=rng, bright=0.14, amp=0.17)
    bar = total / 4
    # dos notas largas por acorde, en tiempos fijos: nada aleatorio
    line = [
        (1.0, 5.0, 659.25), (8.5, 5.0, 587.33),
        (bar + 1.0, 5.0, 523.25), (bar + 8.5, 5.0, 493.88),
        (2 * bar + 1.0, 5.0, 440.00), (2 * bar + 8.5, 5.0, 523.25),
        (3 * bar + 1.0, 5.0, 587.33), (3 * bar + 8.5, 6.0, 493.88),
    ]
    mel = _legato_line(line, total)
    l = l + mel * 0.55
    r = r + mel * 0.45
    return np.stack([_reverb_circular(l, 3.6, 0.42, 5), _reverb_circular(r, 3.6, 0.42, 6)], axis=1)


def music_noche(total=MUSIC_SECONDS):
    """Un bordon en re con quinta que respira muy despacio. Minima."""
    rng = np.random.RandomState(47)
    n = _loop_len(total)
    tt = np.arange(n) / SR
    left = np.zeros(n)
    right = np.zeros(n)
    voices = [(73.42, 0.26), (110.00, 0.18), (146.83, 0.12), (220.00, 0.07), (293.66, 0.035)]
    for vi, (f, g) in enumerate(voices):
        cycles = 1 + vi  # respiracion entera por bucle
        swell = 0.78 + 0.22 * np.sin(2 * np.pi * cycles * tt / total + vi)
        v = _pad_voice(f, total, rng, bright=0.08) * g * swell
        pan = 0.5 + 0.22 * np.sin(vi * 2.3)
        left += v * (1 - pan)
        right += v * pan
    return np.stack([_reverb_circular(left, 4.5, 0.5, 7), _reverb_circular(right, 4.5, 0.5, 8)], axis=1)


# ------------------------------------------------------- musica con ritmo

def _midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def _place(buf, start_s, sig):
    """Suma una senal en un buffer circular: lo que se sale entra por delante."""
    n = len(buf)
    s0 = int(round(start_s * SR)) % n
    idx = (np.arange(len(sig)) + s0) % n
    np.add.at(buf, idx, sig)


def _marimba(freq, dur=0.55, amp=1.0):
    m = int(dur * SR)
    tt = np.arange(m) / SR
    body = (np.sin(2 * np.pi * freq * tt) * np.exp(-tt * 7.5)
            + 0.30 * np.sin(2 * np.pi * freq * 4.0 * tt) * np.exp(-tt * 28)
            + 0.10 * np.sin(2 * np.pi * freq * 10.0 * tt) * np.exp(-tt * 60))
    a = int(0.003 * SR)
    body[:a] *= np.linspace(0, 1, a)
    return amp * body


def _epiano(freq, dur=0.9, amp=1.0):
    """Piano electrico por FM, con la campana del ataque muy suave."""
    m = int(dur * SR)
    tt = np.arange(m) / SR
    index = 1.6 * np.exp(-tt * 9)
    mod = np.sin(2 * np.pi * freq * tt)
    tone = np.sin(2 * np.pi * freq * tt + index * mod) * np.exp(-tt * 3.2)
    a = int(0.006 * SR)
    tone[:a] *= np.linspace(0, 1, a)
    r = int(0.05 * SR)
    tone[-r:] *= np.linspace(1, 0, r)
    return amp * tone


def _bass(freq, dur=0.42, amp=1.0):
    m = int(dur * SR)
    tt = np.arange(m) / SR
    tone = (np.sin(2 * np.pi * freq * tt) + 0.35 * np.sin(2 * np.pi * 2 * freq * tt)) * np.exp(-tt * 5.0)
    a = int(0.008 * SR)
    tone[:a] *= np.linspace(0, 1, a)
    r = int(0.04 * SR)
    tone[-r:] *= np.linspace(1, 0, r)
    return amp * tone


def _kick(amp=1.0):
    m = int(0.28 * SR)
    tt = np.arange(m) / SR
    f = 50 + 70 * np.exp(-tt * 30)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return amp * np.sin(phase) * np.exp(-tt * 14)


def _noise_hit(seed, dur, decay, hp=True, amp=1.0):
    m = int(dur * SR)
    x = np.random.RandomState(seed).normal(0, 1, m)
    if hp:
        x = np.diff(np.concatenate([[0.0], x]))  # paso alto sencillo
    tt = np.arange(m) / SR
    return amp * x * np.exp(-tt * decay)


def music_plaza(bpm=120.0, bars=16):
    """
    Original con ritmo, en el espiritu de las tiendas y plazas de las consolas
    de sobremesa de los 2000: swing ligero, marimba, piano electrico, bajo
    andante y una percusion que acompana sin empujar.
    """
    beat = 60.0 / bpm
    total = bars * 4 * beat
    n = _loop_len(total)
    L = np.zeros(n)
    R = np.zeros(n)
    swing = 0.62  # la corchea de despues cae al 62 % del pulso

    def eighth(bar, beat_i, off):
        return (bar * 4 + beat_i + (swing if off else 0.0)) * beat

    # Progresion de cuatro compases, dos veces, con respuesta en la segunda.
    prog_a = [(48, [64, 67, 71, 74]), (45, [64, 67, 72, 76]),
              (50, [65, 69, 72, 76]), (43, [65, 69, 71, 74])]   # Cmaj9 Am7 Dm9 G13
    prog_b = [(41, [64, 67, 69, 72]), (40, [62, 67, 71, 74]),
              (38, [65, 69, 72, 76]), (43, [65, 67, 71, 74])]   # Fmaj7 Em7 Dm9 G7
    progression = (prog_a + prog_b) * (bars // 8)

    # Bajo andante: fundamental, tercera o quinta, y nota de aproximacion.
    for bar, (root, _) in enumerate(progression):
        nxt = progression[(bar + 1) % len(progression)][0]
        walk = [root, root + 7, root + 12, nxt - 1 if nxt > root else nxt + 1]
        for b, note in enumerate(walk):
            sig = _bass(_midi(note), amp=0.30 if b == 0 else 0.24)
            _place(L, bar * 4 * beat + b * beat, sig * 0.52)
            _place(R, bar * 4 * beat + b * beat, sig * 0.48)

    # Piano electrico: acordes a contratiempo, patron bossa fijo.
    comp = [(0, True), (1, True), (2, False), (3, True)]
    for bar, (_, chord) in enumerate(progression):
        for beat_i, off in comp:
            for k, note in enumerate(chord):
                sig = _epiano(_midi(note), dur=0.55, amp=0.050 / (1 + 0.25 * k))
                pan = 0.36 + 0.08 * k
                _place(L, eighth(bar, beat_i, off), sig * (1 - pan))
                _place(R, eighth(bar, beat_i, off), sig * pan)

    # Melodia de marimba compuesta (no aleatoria): (compas, pulso, contratiempo, nota)
    phrase = [
        (0, 0, False, 76), (0, 0, True, 79), (0, 1, True, 81), (0, 2, True, 79), (0, 3, False, 76),
        (1, 0, True, 74), (1, 1, True, 76), (1, 2, False, 72),
        (2, 0, False, 74), (2, 0, True, 77), (2, 1, True, 81), (2, 2, True, 79), (2, 3, True, 77),
        (3, 0, False, 76), (3, 1, False, 74), (3, 2, True, 71), (3, 3, False, 74),
        (4, 0, False, 72), (4, 0, True, 76), (4, 1, True, 79), (4, 2, True, 84), (4, 3, False, 81),
        (5, 0, True, 79), (5, 1, True, 76), (5, 2, False, 74),
        (6, 0, False, 77), (6, 1, False, 76), (6, 1, True, 74), (6, 2, True, 72), (6, 3, False, 74),
        (7, 0, False, 71), (7, 1, True, 74), (7, 2, False, 79),
    ]
    for rep in range(bars // 8):
        for bar, beat_i, off, note in phrase:
            t0 = eighth(bar + rep * 8, beat_i, off)
            sig = _marimba(_midi(note), amp=0.16)
            _place(L, t0, sig * 0.42)
            _place(R, t0, sig * 0.58)

    # Percusion suave.
    for bar in range(bars):
        for b in range(4):
            t0 = (bar * 4 + b) * beat
            if b in (0, 2):
                k = _kick(amp=0.30 if b == 0 else 0.22)
                _place(L, t0, k)
                _place(R, t0, k)
            if b in (1, 3):
                rim = _noise_hit(100 + bar * 4 + b, 0.05, 90, amp=0.030)
                _place(L, t0, rim * 0.6)
                _place(R, t0, rim * 0.4)
            for off in (False, True):
                sh = _noise_hit(500 + bar * 8 + b * 2 + off, 0.04, 70,
                                amp=0.012 if off else 0.008)
                te = eighth(bar, b, off)
                _place(L, te, sh * 0.35)
                _place(R, te, sh * 0.65)

    L = _reverb_circular(L, 1.6, 0.20, 11)
    R = _reverb_circular(R, 1.6, 0.20, 12)
    return np.stack([L, R], axis=1)


MUSIC_TRACKS = {
    "calma": music_calma,
    "aurora": music_aurora,
    "brisa": music_brisa,
    "noche": music_noche,
    "plaza": music_plaza,
}


def write_ogg(name, stereo, peak=0.6):
    tmp = os.path.join(BGM_DIR, f"_{name}.wav")
    write_wav(tmp, stereo, peak=peak)
    out = os.path.join(BGM_DIR, f"{name}.ogg")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
         "-c:a", "libvorbis", "-q:a", "5", out],
        check=True,
    )
    os.remove(tmp)
    print("  ->", os.path.relpath(out, ROOT), f"({os.path.getsize(out) // 1024} KiB)")


def write_ogg_leveled(name, stereo, lufs=-15.5):
    """Como write_ogg, pero nivelada en sonoridad (EBU R128) con el resto."""
    tmp = os.path.join(BGM_DIR, f"_{name}.wav")
    write_wav(tmp, stereo, peak=0.9)
    out = os.path.join(BGM_DIR, f"{name}.ogg")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
         "-af", f"loudnorm=I={lufs}:TP=-1.5:LRA=11", "-ar", str(SR),
         "-c:a", "libvorbis", "-q:a", "5", out],
        check=True,
    )
    os.remove(tmp)
    print("  ->", os.path.relpath(out, ROOT), f"({os.path.getsize(out) // 1024} KiB)")


def main_music():
    print("Generando variaciones de musica...")
    for name, fn in MUSIC_TRACKS.items():
        if name == "plaza":
            write_ogg_leveled(name, fn())
        else:
            write_ogg(name, fn())


def main():
    print("Generando efectos...")
    write_wav(os.path.join(SFX_DIR, "tick.wav"), sfx_tick(), peak=0.55)
    write_wav(os.path.join(SFX_DIR, "open.wav"), sfx_open(), peak=0.80)
    write_wav(os.path.join(SFX_DIR, "back.wav"), sfx_back(), peak=0.72)
    write_wav(os.path.join(SFX_DIR, "error.wav"), sfx_error(), peak=0.70)
    write_wav(os.path.join(SFX_DIR, "chime.wav"), sfx_chime(), peak=0.85)



if __name__ == "__main__":
    import sys
    if "--music" in sys.argv:
        main_music()
    else:
        main()
        main_music()
