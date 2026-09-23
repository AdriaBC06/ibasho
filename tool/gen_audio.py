#!/usr/bin/env python3
# Ibasho — generador del set sonoro original.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Uso:  python3 tool/gen_audio.py [--music | --pinball | --pachinko]
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


# --------------------------------------------- musica del gachapon (0.6.0)
#
# Seis pistas nuevas para GachaCategory.music, catalogadas en
# `lib/backend/gacha_music.dart` con clave `mu_<id>`. Reparto de rareza:
# nana y carrillon (N), lofi (R), feria (SR), abrigo (UR) y cenit (∞, la mas
# elaborada). Todas cierran el bucle con los mismos trucos que las de serie:
# `_chord_pad`/`_legato_line`/`_reverb_circular` para las de pad, y el patron
# de `_place` sobre un bucle circular para las que tienen notas sueltas.


def music_nana(total=72.0):
    """N: una nana en compas de tres, mecida siempre igual."""
    rng = np.random.RandomState(53)
    chords = [
        [98.00, 146.83, 246.94, 293.66],    # G6
        [87.31, 130.81, 220.00, 261.63],    # F6
        [73.42, 110.00, 174.61, 220.00],    # Dm7
        [82.41, 123.47, 196.00, 246.94],    # Em7
    ]
    l, r = _chord_pad(chords, total, fade=7.0, rng=rng, bright=0.10, amp=0.18)
    bar = total / 4
    # El mismo vaiven en cada compas: sube y baja, nunca sorprende.
    line = [
        (0.5, 3.0, 392.00), (bar - 2.0, 3.0, 349.23),
        (bar + 0.5, 3.0, 329.63), (2 * bar - 2.0, 3.0, 293.66),
        (2 * bar + 0.5, 3.0, 293.66), (3 * bar - 2.0, 3.0, 261.63),
        (3 * bar + 0.5, 3.0, 246.94), (4 * bar - 3.0, 4.0, 220.00),
    ]
    mel = _legato_line(line, total, amp=0.06, attack=1.6, release=3.0, seed=17)
    l = l + mel * 0.5
    r = r + mel * 0.5
    return np.stack([_reverb_circular(l, 3.2, 0.4, 21), _reverb_circular(r, 3.2, 0.4, 22)], axis=1)


def music_carrillon(total=48.0):
    """N: caja de musica. Una frase de celesta que da dos vueltas sobre un
    pad casi inaudible, solo para no dejar silencio detras."""
    rng = np.random.RandomState(59)
    n = _loop_len(total)
    L = np.zeros(n)
    R = np.zeros(n)
    chords = [
        [130.81, 196.00, 329.63],
        [110.00, 164.81, 293.66],
        [98.00, 146.83, 261.63],
        [123.47, 185.00, 293.66],
    ]
    pl, pr = _chord_pad(chords, total, fade=8.0, rng=rng, bright=0.06, amp=0.05)
    phrase = [
        (0.0, 76), (0.5, 79), (1.0, 83), (1.5, 79),
        (2.0, 81), (2.5, 76), (3.0, 74), (3.75, 76),
        (4.5, 79), (5.0, 83), (5.5, 86), (6.0, 83),
        (6.5, 79), (7.25, 81), (7.75, 74),
    ]
    bar = total / 2
    for rep in range(2):
        for t0, note in phrase:
            b = bell(_midi(note), 1.4, amp=0.30, bright=1.3)
            _place(L, rep * bar + t0, b * 0.55)
            _place(R, rep * bar + t0, b * 0.45)
    L += pl
    R += pr
    return np.stack([_reverb_circular(L, 3.0, 0.38, 23), _reverb_circular(R, 3.0, 0.38, 24)], axis=1)


def music_lofi(bpm=76.0, bars=8):
    """R: groove suave, caja destimbrada y algo de polvo de vinilo."""
    beat = 60.0 / bpm
    total = bars * 4 * beat
    n = _loop_len(total)
    L = np.zeros(n)
    R = np.zeros(n)
    swing = 0.58

    def eighth(bar, beat_i, off):
        return (bar * 4 + beat_i + (swing if off else 0.0)) * beat

    prog = [(45, [64, 67, 71, 74]), (43, [62, 65, 69, 72]),
            (48, [64, 67, 71, 74]), (41, [60, 64, 67, 71])] * (bars // 4)
    for bar, (root, chord) in enumerate(prog):
        for b, note in enumerate((root, root + 5)):
            sig = _bass(_midi(note), dur=0.9, amp=0.22)
            t0 = bar * 4 * beat + b * 2 * beat
            _place(L, t0, sig * 0.5)
            _place(R, t0, sig * 0.5)
        for beat_i, off in ((1, True), (3, False)):
            for k, note in enumerate(chord):
                sig = _epiano(_midi(note), dur=1.1, amp=0.045 / (1 + 0.2 * k))
                t0 = eighth(bar, beat_i, off)
                _place(L, t0, sig * 0.55)
                _place(R, t0, sig * 0.45)
        dust = _noise_hit(700 + bar, 0.6, 6.0, hp=False, amp=0.015)
        _place(L, bar * 4 * beat, dust * 0.5)
        _place(R, bar * 4 * beat, dust * 0.5)
    L = _reverb_circular(L, 1.8, 0.22, 31)
    R = _reverb_circular(R, 1.8, 0.22, 32)
    return np.stack([L, R], axis=1)


def music_feria(bpm=138.0, bars=16):
    """SR: la feria alegre, sin swing y con las campanitas de rigor."""
    beat = 60.0 / bpm
    total = bars * 4 * beat
    n = _loop_len(total)
    L = np.zeros(n)
    R = np.zeros(n)
    prog = [(48, [64, 67, 71, 74]), (45, [64, 67, 72, 76]),
            (43, [65, 69, 72, 76]), (50, [65, 69, 71, 74])] * (bars // 4)
    for bar, (root, chord) in enumerate(prog):
        nxt = prog[(bar + 1) % len(prog)][0]
        for b, note in enumerate((root, root + 7, root + 12, nxt)):
            sig = _bass(_midi(note), amp=0.28)
            t0 = bar * 4 * beat + b * beat
            _place(L, t0, sig * 0.5)
            _place(R, t0, sig * 0.5)
        for beat_i in range(4):
            for k, note in enumerate(chord):
                sig = _epiano(_midi(note), dur=0.4, amp=0.04 / (1 + 0.25 * k))
                t0 = (bar * 4 + beat_i) * beat
                _place(L, t0, sig * 0.45)
                _place(R, t0, sig * 0.55)
    phrase = [
        (0, 0, 84), (0, 1, 88), (0, 2, 91), (0, 3, 88),
        (1, 0, 86), (1, 1, 84), (1, 2, 81), (1, 3, 84),
        (2, 0, 88), (2, 1, 91), (2, 2, 96), (2, 3, 93),
        (3, 0, 91), (3, 1, 88), (3, 2, 84), (3, 3, 81),
    ]
    for rep in range(bars // 4):
        for bar, beat_i, note in phrase:
            t0 = ((bar + rep * 4) * 4 + beat_i) * beat
            sig = _marimba(_midi(note), amp=0.20)
            _place(L, t0, sig * 0.4)
            _place(R, t0, sig * 0.6)
    for bar in range(bars):
        for b in range(4):
            t0 = (bar * 4 + b) * beat
            if b in (0, 2):
                k = _kick(amp=0.26)
                _place(L, t0, k)
                _place(R, t0, k)
            tamb = _noise_hit(900 + bar * 4 + b, 0.05, 60.0, amp=0.02)
            _place(L, t0 + beat * 0.5, tamb * 0.5)
            _place(R, t0 + beat * 0.5, tamb * 0.5)
    for rep in range(bars // 4):
        for i, f in enumerate((1567.98, 1864.66, 2093.0, 2349.32)):
            b = bell(f, 0.5, amp=0.18, bright=1.3)
            t0 = (rep * 4 * 4 + 15) * beat + i * 0.05
            _place(L, t0, b * 0.5)
            _place(R, t0, b * 0.5)
    L = _reverb_circular(L, 1.4, 0.18, 41)
    R = _reverb_circular(R, 1.4, 0.18, 42)
    return np.stack([L, R], axis=1)


def music_abrigo(total=88.0):
    """UR: un pad de cuerdas calido, acordes extendidos de seis voces."""
    rng = np.random.RandomState(67)
    chords = [
        [87.31, 130.81, 174.61, 261.63, 349.23, 440.00],   # Fmaj9
        [65.41, 98.00, 164.81, 246.94, 329.63, 392.00],    # Cmaj9
        [73.42, 110.00, 146.83, 220.00, 293.66, 349.23],   # Dm11
        [98.00, 146.83, 174.61, 246.94, 349.23, 440.00],   # G13
    ]
    l, r = _chord_pad(chords, total, fade=8.0, rng=rng, bright=0.16, amp=0.15)
    bar = total / 4
    line = [
        (1.0, 6.0, 523.25), (bar + 1.0, 6.0, 493.88),
        (2 * bar + 1.0, 6.0, 440.00), (3 * bar + 1.0, 7.0, 392.00),
    ]
    mel = _legato_line(line, total, amp=0.09, attack=2.2, release=4.0, seed=29)
    l = l + mel * 0.55
    r = r + mel * 0.45
    return np.stack([_reverb_circular(l, 4.2, 0.46, 43), _reverb_circular(r, 4.2, 0.46, 44)], axis=1)


def music_cenit(total=96.0):
    """∞: la mas lograda, con dos voces en contrapunto sobre un pad que solo
    se mueve para sostenerlas, y un brillo que aparece una sola vez por
    vuelta como una senal de que esto no es una pista mas."""
    rng = np.random.RandomState(89)
    chords = [
        [65.41, 98.00, 130.81, 196.00, 246.94],     # Cmaj9
        [73.42, 110.00, 146.83, 220.00, 277.18],    # Dm9
        [82.41, 123.47, 164.81, 246.94, 311.13],    # Em11
        [87.31, 130.81, 174.61, 261.63, 329.63],    # Fmaj7
        [98.00, 146.83, 196.00, 293.66, 369.99],    # G9
        [65.41, 98.00, 130.81, 196.00, 261.63],     # Cmaj9, de vuelta
    ]
    l, r = _chord_pad(chords, total, fade=6.0, rng=rng, bright=0.14, amp=0.15)
    bar = total / len(chords)
    voice_a = [
        (0.5, 4.0, 392.00), (bar + 0.5, 4.0, 440.00), (2 * bar + 0.5, 4.0, 493.88),
        (3 * bar + 0.5, 4.0, 523.25), (4 * bar + 0.5, 4.0, 440.00), (5 * bar + 0.5, 5.0, 392.00),
    ]
    voice_b = [
        (bar * 0.5, 4.0, 261.63), (bar * 1.5, 4.0, 293.66), (bar * 2.5, 4.0, 329.63),
        (bar * 3.5, 4.0, 349.23), (bar * 4.5, 4.0, 293.66), (bar * 5.5, 5.0, 261.63),
    ]
    a = _legato_line(voice_a, total, amp=0.075, attack=1.6, release=2.8, seed=51)
    b = _legato_line(voice_b, total, amp=0.065, attack=1.8, release=3.0, seed=52)
    l = l + a * 0.5 + b * 0.4
    r = r + a * 0.4 + b * 0.5
    shimmer = np.zeros(_loop_len(total))
    for f in (1046.5, 1318.5, 1567.98):
        _place(shimmer, total * 0.5 - 1.0, bell(f, 2.0, amp=0.12, bright=1.4))
    l = l + shimmer * 0.5
    r = r + shimmer * 0.5
    return np.stack([_reverb_circular(l, 4.6, 0.48, 61), _reverb_circular(r, 4.6, 0.48, 62)], axis=1)


MUSIC_TRACKS = {
    "calma": music_calma,
    "aurora": music_aurora,
    "brisa": music_brisa,
    "noche": music_noche,
    "plaza": music_plaza,
}

# Las seis del gachapon (0.6.0): van con `.ogg` y `.mp3` desde ya, para no
# tener que acordarse de convertirlas aparte como paso con las de serie.
GACHA_MUSIC_TRACKS = {
    "nana": music_nana,
    "carrillon": music_carrillon,
    "lofi": music_lofi,
    "feria": music_feria,
    "abrigo": music_abrigo,
    "cenit": music_cenit,
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


def write_mp3(name):
    """Convierte el `.ogg` ya escrito a `.mp3`, para Windows (ver
    `MusicTrack.asset` en `lib/audio/audio_service.dart`)."""
    src = os.path.join(BGM_DIR, f"{name}.ogg")
    out = os.path.join(BGM_DIR, f"{name}.mp3")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", src,
         "-c:a", "libmp3lame", "-q:a", "3", out],
        check=True,
    )
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


# --------------------------------------------------- efectos del gachapon
#
# El gacha necesita sonidos "de premio": la manivela que engancha, la capsula
# que cae y una fanfarria distinta segun lo raro que salga. Todos son cortos y
# secos salvo las de UR e infinito, que son las que dan el subidon.


def _click(seed, freq, amp=1.0, dur=0.035):
    """Un diente de la manivela: ruido muy corto con cuerpo de plastico."""
    n = int(dur * SR)
    rng = np.random.RandomState(seed)
    noise = rng.normal(0, 1, n) * np.exp(-np.linspace(0, 55, n))
    body = sine(freq, n) * np.exp(-np.linspace(0, 30, n))
    return amp * (0.55 * noise + 0.8 * body)


def sfx_crank():
    """La manivela girando: seis dientes que enganchan cada vez mas rapido."""
    total = int(0.78 * SR)
    out = np.zeros(total)
    at = 0.0
    gap = 0.135
    for i in range(6):
        d = int(at * SR)
        c = _click(11 + i, 320 + i * 46, amp=0.75 + i * 0.05)
        out[d:d + len(c)] += c[:total - d]
        at += gap
        gap *= 0.86
    # Un roce grave por debajo, el muelle del tambor.
    rumble = np.random.RandomState(3).normal(0, 1, total)
    k = int(SR * 0.004)
    rumble = np.convolve(rumble, np.ones(k) / k, mode="same")
    out += 0.22 * rumble * np.linspace(0.2, 1.0, total) * np.exp(-np.linspace(0, 1.2, total))
    return fade_edges(out, 4.0)


def sfx_capsule():
    """La capsula cayendo por el tobogan y golpeando la bandeja."""
    total = int(0.62 * SR)
    out = np.zeros(total)
    # Tres rebotes cada vez mas juntos y mas flojos.
    for i, (at, amp, freq) in enumerate(
        ((0.00, 1.0, 196.0), (0.16, 0.62, 233.1), (0.27, 0.38, 261.6), (0.35, 0.22, 293.7))
    ):
        d = int(at * SR)
        n = int(0.16 * SR)
        hit = (sine(freq, n) + 0.4 * sine(freq * 2.4, n)) * env_ad(n, 0.002, 0.10, curve=7.0)
        hit += 0.25 * np.random.RandomState(20 + i).normal(0, 1, n) * np.exp(-np.linspace(0, 70, n))
        out[d:d + n] += amp * hit[:total - d]
    return fade_edges(out, 4.0)


def sfx_pop():
    """La capsula abriendose: un chasquido con chispa."""
    n = int(0.22 * SR)
    body = soft_tone(880.0, 0.22, 0.8, attack=0.001, curve=9.0)
    bright = soft_tone(1318.5, 0.18, 0.6, attack=0.001, curve=12.0)
    body[:len(bright)] += 0.4 * bright
    air = np.random.RandomState(31).normal(0, 1, n) * np.exp(-np.linspace(0, 60, n)) * 0.18
    return fade_edges(body[:n] + air, 3.0)


def _fanfare(notes, tail=1.0, mix=0.3, shine=0.0):
    """Arpegio de campanas: la base de las tres fanfarrias de rareza."""
    last = max(d for _, d in notes)
    n = int((last + tail) * SR)
    out = np.zeros(n)
    for freq, delay in notes:
        d = int(delay * SR)
        b = bell(freq, tail + 0.4, amp=1.0, bright=1.2)
        out[d:d + len(b)] += b[:n - d]
    if shine:
        # Brillo que sube: lo que hace que suene a premio gordo.
        sweep = np.linspace(0, 1, n)
        glitter = np.sin(2 * math.pi * (1800 + 2600 * sweep) * t(n)) * np.exp(-np.linspace(0, 3.5, n))
        out += shine * glitter
    return fade_edges(reverb(out, mix=mix), 4.0)


def sfx_rare():
    """SR: tres notas cortas, un guiño."""
    return _fanfare([(659.25, 0.0), (830.61, 0.08), (987.77, 0.16)], tail=0.7, mix=0.2)


def sfx_epic():
    """SSR: arpegio mayor con novena y un poco de brillo."""
    return _fanfare(
        [(523.25, 0.0), (659.25, 0.07), (783.99, 0.14), (1046.5, 0.21), (1318.5, 0.30)],
        tail=1.4,
        mix=0.3,
        shine=0.05,
    )


def sfx_legend():
    """UR: fanfarria larga, con golpe grave debajo y brillo ascendente."""
    out = _fanfare(
        [(523.25, 0.0), (783.99, 0.09), (1046.5, 0.18), (1318.5, 0.27),
         (1567.98, 0.36), (2093.0, 0.46)],
        tail=2.2,
        mix=0.34,
        shine=0.10,
    )
    n = len(out)
    boom = sine(58.0, n) * env_ad(n, 0.004, 0.9, curve=2.0) * 0.5
    boom += sine(87.0, n) * env_ad(n, 0.004, 0.7, curve=2.4) * 0.25
    return fade_edges(out + boom, 4.0)


def sfx_infinity():
    """Infinito: no es una fanfarria, es algo que no deberia estar ahi.

    Un acorde suspendido que sube de tono sin resolver, con las voces
    desafinadas entre si: suena raro a proposito.
    """
    total = int(3.4 * SR)
    out = np.zeros(total)
    base = [261.63, 392.0, 523.25, 698.46, 1046.5]
    for i, freq in enumerate(base):
        glide = np.linspace(1.0, 1.06, total)
        phase = 2 * math.pi * np.cumsum(freq * glide) / SR
        voice = np.sin(phase) + 0.3 * np.sin(2 * phase)
        env = np.exp(-np.linspace(0, 1.6, total)) * (1 - np.exp(-np.linspace(0, 12, total)))
        out += (0.9 - i * 0.12) * voice * env
    shimmer = np.random.RandomState(5).normal(0, 1, total)
    k = int(SR * 0.0015)
    shimmer = np.convolve(shimmer, np.ones(k) / k, mode="same")
    out += 0.10 * shimmer * np.exp(-np.linspace(0, 2.4, total))
    for freq, delay in ((1567.98, 0.0), (2093.0, 0.5), (2637.02, 1.0)):
        d = int(delay * SR)
        b = bell(freq, 2.4, amp=0.55, bright=1.4)
        out[d:d + len(b)] += b[:total - d]
    return fade_edges(reverb(out, mix=0.42, decay=3.0), 5.0)


# ---------------------------------------------------- efectos del pinball
#
# El pinball tiene su propio juego de sonidos, ninguno sacado de la interfaz:
# golpes de mesa (flippers, bumpers, gomas, muelles), las luces que se
# encienden y el coro del Tama cuando salva la bola. Son secos y cortos
# porque suenan muchas veces por segundo; solo el coro y los premios tienen
# cola.


def _thud(freq, dur, drop=0.5, amp=1.0, curve=9.0):
    """Golpe con cuerpo: un seno que baja de tono al apagarse."""
    n = int(dur * SR)
    f = freq * (1 - drop * (1 - np.exp(-np.linspace(0, 6, n))))
    phase = 2 * math.pi * np.cumsum(f) / SR
    return amp * np.sin(phase) * env_ad(n, 0.001, dur, curve=curve)


def _noise(seed, dur, decay=40.0, smooth=1, amp=1.0):
    n = int(dur * SR)
    x = np.random.RandomState(seed).normal(0, 1, n)
    if smooth > 1:
        x = np.convolve(x, np.ones(smooth) / smooth, mode="same")
    return amp * x * np.exp(-np.linspace(0, decay * dur, n))


def _sum(*sigs):
    """Suma senales de largos distintos, todas desde el principio."""
    out = np.zeros(max(len(x) for x in sigs))
    for x in sigs:
        out[:len(x)] += x
    return out


def _mix(total, *parts):
    """Suma trozos (senal, empieza en segundos) en un bufer de [total] s."""
    out = np.zeros(int(total * SR))
    for sig, at in parts:
        d = int(at * SR)
        out[d:d + len(sig)] += sig[:len(out) - d]
    return out


def sfx_pb_launch():
    """El lanzador: el muelle se suelta y la bola sube por el carril."""
    total = 0.55
    clack = _sum(_thud(140, 0.12, drop=0.3, amp=1.0), _noise(41, 0.05, decay=60, amp=0.5))
    n = int(0.45 * SR)
    sweep = np.linspace(0, 1, n)
    whoosh = np.random.RandomState(42).normal(0, 1, n)
    k = int(SR * 0.0012)
    whoosh = np.convolve(whoosh, np.ones(k) / k, mode="same")
    whoosh *= np.sin(math.pi * sweep) ** 2 * 0.35
    ring = np.sin(2 * math.pi * np.cumsum(420 + 520 * sweep) / SR) * np.sin(math.pi * sweep) * 0.12
    return fade_edges(_mix(total, (clack, 0), (whoosh + ring, 0.04)), 3.0)


def sfx_pb_flipper():
    """El flipper: el golpe seco del solenoide."""
    body = _thud(110, 0.09, drop=0.35, curve=10)
    click = _noise(43, 0.02, decay=180, amp=0.6)
    return fade_edges(_mix(0.1, (body, 0), (click, 0)), 2.0)


def sfx_pb_bumper():
    """Un bumper: el pop metalico que devuelve la bola."""
    ping = _thud(880, 0.16, drop=0.45, amp=0.7, curve=11)
    ping += 0.35 * _thud(1760, 0.16, drop=0.45, curve=14)
    kick = _thud(160, 0.08, drop=0.3, amp=0.8, curve=10)
    snap = _noise(44, 0.03, decay=140, amp=0.4)
    return fade_edges(_mix(0.18, (ping, 0), (kick, 0), (snap, 0)), 2.0)


def sfx_pb_sling():
    """Un tirachinas: la goma que da un latigazo."""
    n = int(0.14 * SR)
    f = 240 * (1 + 0.8 * np.exp(-np.linspace(0, 20, n)))
    twang = np.sin(2 * math.pi * np.cumsum(f) / SR) * env_ad(n, 0.001, 0.12, curve=8)
    twang += 0.3 * np.sin(4 * math.pi * np.cumsum(f) / SR) * env_ad(n, 0.001, 0.08, curve=10)
    return fade_edges(twang + _noise(45, 0.14, decay=90, smooth=3, amp=0.3), 2.0)


def sfx_pb_spring():
    """Una pared-muelle: un boing que tiembla."""
    n = int(0.32 * SR)
    tt = t(n)
    f = 330 * (1 + 0.12 * np.sin(2 * math.pi * 17 * tt) * np.exp(-tt * 8))
    boing = np.sin(2 * math.pi * np.cumsum(f) / SR) * env_ad(n, 0.002, 0.3, curve=5)
    boing += 0.25 * np.sin(2 * math.pi * np.cumsum(f * 2.5) / SR) * env_ad(n, 0.002, 0.15, curve=8)
    return fade_edges(boing, 3.0)


def sfx_pb_post():
    """Un poste de goma: un toque blando y agudo."""
    tock = _sum(_thud(1250, 0.05, drop=0.2, curve=12), 0.4 * _thud(2600, 0.03, drop=0.1, curve=14))
    return fade_edges(tock, 1.5)


def sfx_pb_spinner():
    """El spinner: la paleta dando vueltas, trinquete que se frena."""
    parts = []
    at = 0.0
    gap = 0.028
    for i in range(12):
        parts.append((_click(60 + i, 900 - i * 25, amp=1.0 - i * 0.06, dur=0.025), at))
        at += gap
        gap *= 1.12
    return fade_edges(_mix(at + 0.05, *parts), 2.0)


def sfx_pb_target():
    """Una diana que cae: chasquido de plastico y una nota clara."""
    clack = _sum(_thud(520, 0.05, drop=0.4, curve=12), _noise(46, 0.03, decay=150, amp=0.5))
    ding = bell(1568.0, 0.35, amp=0.45, bright=0.8)
    return fade_edges(_mix(0.4, (clack, 0), (ding, 0.015)), 3.0)


def sfx_pb_hole_open():
    """Un agujero que se abre: cuatro notas que suben y un brillo."""
    notes = (783.99, 987.77, 1174.66, 1567.98)
    parts = [(_marimba(f, dur=0.5, amp=0.9), i * 0.075) for i, f in enumerate(notes)]
    n = int(0.6 * SR)
    shimmer = np.sin(2 * math.pi * np.cumsum(np.linspace(2200, 3600, n)) / SR) * np.exp(-np.linspace(0, 5, n)) * 0.12
    parts.append((shimmer, 0.22))
    return fade_edges(reverb(_mix(1.0, *parts), mix=0.22), 4.0)


def sfx_pb_capture():
    """La bola cae en el agujero: rueda por el borde, cae y suena el premio."""
    n = int(0.3 * SR)
    sweep = np.linspace(0, 1, n)
    rattle = np.sin(2 * math.pi * np.cumsum(38 - 20 * sweep) / SR)
    rattle = (rattle > 0).astype(float) * _noise(47, 0.3, decay=2, smooth=4)[:n] * 0.35
    drop = _thud(95, 0.25, drop=0.4, amp=1.0, curve=6)
    ding = bell(1046.5, 0.8, amp=0.5) + bell(1567.98, 0.8, amp=0.35)
    return fade_edges(reverb(_mix(1.2, (rattle, 0), (drop, 0.28), (ding, 0.36)), mix=0.2), 4.0)


def sfx_pb_kickback_lit():
    """Un kickback encendido: dos notas de luz."""
    return fade_edges(_mix(0.5, (bell(1318.5, 0.35, amp=0.6), 0), (bell(1975.5, 0.4, amp=0.6), 0.09)), 3.0)


def sfx_pb_kickback():
    """El kickback: un golpe grave que devuelve la bola arriba."""
    boom = _thud(70, 0.3, drop=0.2, amp=1.0, curve=5)
    n = int(0.3 * SR)
    up = np.sin(2 * math.pi * np.cumsum(np.linspace(200, 700, n)) / SR) * env_ad(n, 0.005, 0.25, curve=5) * 0.25
    return fade_edges(_mix(0.4, (boom, 0), (up, 0.02), (_noise(48, 0.06, decay=60, amp=0.4), 0)), 3.0)


def _choir_voice(f0, n, rng, vowel):
    """Una voz de coro: armonicos de [f0] esculpidos por los formantes de
    la vocal, con vibrato lento y un poco de aire."""
    tt = t(n)
    vib = 1 + 0.006 * np.sin(2 * math.pi * (5.2 + rng.uniform(-0.4, 0.4)) * tt + rng.uniform(0, 6.28))
    drift = 1 + rng.uniform(-0.004, 0.004)
    phase = 2 * math.pi * np.cumsum(f0 * drift * vib) / SR
    out = np.zeros(n)
    for k in range(1, 30):
        fk = f0 * k
        if fk > 6000:
            break
        a = sum(g * math.exp(-((fk - fc) / bw) ** 2) for fc, bw, g in vowel)
        out += a / k ** 0.3 * np.sin(k * phase)
    return out


def sfx_pb_choir():
    """El coro del Tama que salva la bola: un «aaah» de angeles.

    Un acorde mayor con novena cantado por un coro sintetizado (voces con
    formantes de «a», cada una en tres dobladas), que entra suave, abre a
    «o» y se queda flotando en la reverb. Una campanita de cristal arriba.
    """
    total = 2.2
    n = int(total * SR)
    rng = np.random.RandomState(77)
    ah = ((800, 110, 1.0), (1150, 130, 0.55), (2900, 240, 0.18), (3900, 300, 0.06))
    oh = ((500, 100, 1.0), (850, 120, 0.5), (2800, 240, 0.12), (3600, 300, 0.04))
    chord = (261.63, 329.63, 392.0, 523.25, 587.33, 659.25)
    blend = np.clip(np.linspace(-0.4, 1.4, n), 0, 1)
    out = np.zeros(n)
    for f0 in chord:
        for _ in range(3):
            a = _choir_voice(f0, n, rng, ah)
            o = _choir_voice(f0, n, rng, oh)
            out += (1 - blend) * a + blend * o
    out /= np.max(np.abs(out)) or 1.0
    env = np.minimum(1, t(n) / 0.28) ** 1.5 * np.exp(-np.maximum(0, t(n) - 0.9) * 2.2)
    out *= env
    breath = _noise(78, total, decay=0.9, smooth=6, amp=0.04) * env
    sparkle = _mix(total, (bell(2093.0, 1.2, amp=0.18, bright=1.4), 0.05), (bell(3135.96, 1.0, amp=0.1, bright=1.4), 0.2))
    return fade_edges(reverb(out + breath + sparkle, mix=0.45, decay=3.0), 8.0)


def sfx_pb_thrown():
    """El Tama devuelve la bola: un soplido que sube con chispas."""
    n = int(0.5 * SR)
    sweep = np.linspace(0, 1, n)
    air = np.random.RandomState(49).normal(0, 1, n)
    k = int(SR * 0.0008)
    air = np.convolve(air, np.ones(k) / k, mode="same") * np.sin(math.pi * sweep) ** 1.5 * 0.4
    rise = np.sin(2 * math.pi * np.cumsum(500 + 1300 * sweep ** 2) / SR) * np.sin(math.pi * sweep) * 0.3
    sparks = _mix(0.6, (bell(2637.0, 0.3, amp=0.25), 0.18), (bell(3520.0, 0.3, amp=0.2), 0.3))
    return fade_edges(_mix(0.6, (air + rise, 0), (sparks, 0)), 3.0)


def sfx_pb_nudge():
    """La mesa da un meneo: dos golpes sordos de madera."""
    a = _sum(_thud(85, 0.14, drop=0.25, curve=8), _noise(50, 0.05, decay=80, smooth=8, amp=0.4))
    return fade_edges(_mix(0.3, (a, 0), (0.7 * a, 0.11)), 2.0)


def sfx_pb_lost():
    """La bola se va por el desague: tres notas que caen, con sordina."""
    parts = []
    for i, f in enumerate((392.0, 349.23, 293.66)):
        n = int(0.34 * SR)
        wob = 1 + 0.02 * np.sin(2 * math.pi * 6 * t(n))
        voice = np.sin(2 * math.pi * np.cumsum(f * wob * np.linspace(1, 0.97, n)) / SR)
        voice += 0.35 * np.sin(4 * math.pi * np.cumsum(f * wob) / SR)
        parts.append((voice * env_ad(n, 0.02, 0.3, curve=3.5) * (0.9 - i * 0.1), i * 0.2))
    return fade_edges(_mix(0.95, *parts), 4.0)


def sfx_pb_prize():
    """Premio en el pinball: un arpegio de marimba y campanas que sube."""
    notes = (523.25, 659.25, 783.99, 1046.5, 1318.5)
    parts = [(_marimba(f, dur=0.6, amp=0.8), i * 0.07) for i, f in enumerate(notes)]
    parts.append((bell(1567.98, 1.2, amp=0.5), 0.36))
    parts.append((bell(2093.0, 1.2, amp=0.35), 0.36))
    return fade_edges(reverb(_mix(1.6, *parts), mix=0.28), 4.0)


def sfx_pb_jackpot():
    """Premio gordo (UR y ∞): el arpegio doble, un golpe grave y el coro
    abriendo detras."""
    notes = (523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98, 2093.0)
    parts = [(_marimba(f, dur=0.7, amp=0.8), i * 0.065) for i, f in enumerate(notes)]
    parts.append((_thud(55, 0.9, drop=0.1, amp=0.9, curve=3), 0.0))
    for f in (1046.5, 1318.5, 1567.98, 2093.0):
        parts.append((bell(f, 1.8, amp=0.3, bright=1.3), 0.48))
    body = _mix(2.6, *parts)
    choir = sfx_pb_choir()
    choir = choir / (np.max(np.abs(choir)) or 1.0) * 0.35
    return fade_edges(reverb(body, mix=0.3) + _mix(2.6, (choir, 0.3)), 5.0)


PINBALL_SFX = {
    "pb_launch": (sfx_pb_launch, 0.72),
    "pb_flipper": (sfx_pb_flipper, 0.62),
    "pb_bumper": (sfx_pb_bumper, 0.66),
    "pb_sling": (sfx_pb_sling, 0.62),
    "pb_spring": (sfx_pb_spring, 0.58),
    "pb_post": (sfx_pb_post, 0.45),
    "pb_spinner": (sfx_pb_spinner, 0.55),
    "pb_target": (sfx_pb_target, 0.66),
    "pb_hole_open": (sfx_pb_hole_open, 0.8),
    "pb_capture": (sfx_pb_capture, 0.8),
    "pb_kickback_lit": (sfx_pb_kickback_lit, 0.66),
    "pb_kickback": (sfx_pb_kickback, 0.8),
    "pb_choir": (sfx_pb_choir, 0.82),
    "pb_thrown": (sfx_pb_thrown, 0.66),
    "pb_nudge": (sfx_pb_nudge, 0.7),
    "pb_lost": (sfx_pb_lost, 0.7),
    "pb_prize": (sfx_pb_prize, 0.82),
    "pb_jackpot": (sfx_pb_jackpot, 0.9),
}


def main_pinball():
    print("Generando efectos del pinball...")
    for name, (fn, peak) in PINBALL_SFX.items():
        write_wav(os.path.join(SFX_DIR, f"{name}.wav"), fn(), peak=peak)


# --------------------------------------------------- efectos del pachinko
#
# El pachinko suena a metal: bolas de acero contra clavos de laton, el
# molinillo de plastico, el tulipan que se abre y la cascada de bolas al
# cobrar. Los golpes son finisimos porque suenan decenas por segundo.


def sfx_pk_drop():
    """Una bola que se suelta: sale del riel con un clinc y rueda un poco."""
    clink = _sum(bell(2637.0, 0.12, amp=0.5, bright=1.6), _thud(1900, 0.03, drop=0.1, amp=0.4, curve=14))
    n = int(0.12 * SR)
    roll = np.random.RandomState(61).normal(0, 1, n)
    roll = np.convolve(roll, np.ones(6) / 6, mode="same") * np.sin(math.pi * np.linspace(0, 1, n)) * 0.12
    return fade_edges(_mix(0.2, (clink, 0), (roll, 0.02)), 2.0)


def sfx_pk_pin():
    """Una bola de acero en un clavo de laton: un tic agudo y brillante."""
    tik = _sum(_thud(3400, 0.018, drop=0.05, curve=16), 0.5 * _thud(5200, 0.012, drop=0.05, curve=18))
    return fade_edges(_sum(tik, _noise(62, 0.012, decay=300, amp=0.25)), 1.0)


def sfx_pk_windmill():
    """El molinillo: cuatro aspas de plastico que dan la vuelta."""
    parts = []
    at = 0.0
    gap = 0.035
    for i in range(5):
        parts.append((_click(63 + i, 1500 - i * 60, amp=0.9 - i * 0.12, dur=0.02), at))
        at += gap
        gap *= 1.18
    return fade_edges(_mix(at + 0.04, *parts), 2.0)


def sfx_pk_tulip():
    """El tulipan: el ala de plastico que da un golpecito."""
    flap = _sum(_thud(700, 0.05, drop=0.35, curve=12), _noise(64, 0.025, decay=160, amp=0.4))
    return fade_edges(_mix(0.1, (flap, 0)), 1.5)


def sfx_pk_same():
    """Un bolsillo de «igual»: la bola cae en el cubo y suena una nota."""
    clunk = _sum(_thud(260, 0.08, drop=0.4, curve=9), _noise(65, 0.03, decay=120, amp=0.4))
    return fade_edges(reverb(_mix(0.6, (clunk, 0), (bell(1174.66, 0.45, amp=0.45), 0.04)), mix=0.15), 3.0)


def sfx_pk_up1():
    """Un bolsillo de +1: tres notas de campana que suben."""
    clunk = _sum(_thud(260, 0.08, drop=0.4, curve=9), _noise(66, 0.03, decay=120, amp=0.4))
    notes = (1046.5, 1318.5, 1567.98)
    parts = [(clunk, 0)] + [(bell(f, 0.6, amp=0.5, bright=1.1), 0.04 + i * 0.07) for i, f in enumerate(notes)]
    return fade_edges(reverb(_mix(0.9, *parts), mix=0.2), 3.0)


def sfx_pk_up2():
    """El tulipan se traga la bola (+2) o sale una UR: la feria entera,
    campanas en cascada sobre un arpegio de marimba."""
    notes = (523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98, 2093.0)
    parts = [(_marimba(f, dur=0.6, amp=0.75), i * 0.05) for i, f in enumerate(notes)]
    for k in range(10):
        f = (2093.0, 2637.0, 3135.96, 2349.32)[k % 4]
        parts.append((bell(f, 0.5, amp=0.28, bright=1.5), 0.35 + k * 0.06))
    parts.append((_thud(80, 0.6, drop=0.15, amp=0.7, curve=4), 0.0))
    return fade_edges(reverb(_mix(2.0, *parts), mix=0.3), 5.0)


def sfx_pk_out():
    """La bola se va por la salida: rueda por el canal y se pierde, sin
    drama (pasa seis de cada diez veces)."""
    n = int(0.22 * SR)
    sweep = np.linspace(0, 1, n)
    roll = np.random.RandomState(67).normal(0, 1, n)
    roll = np.convolve(roll, np.ones(10) / 10, mode="same") * (1 - sweep) * 0.3
    thunk = _thud(150, 0.1, drop=0.4, amp=0.6, curve=8)
    return fade_edges(_mix(0.3, (roll, 0), (thunk, 0.16)), 3.0)


def sfx_pk_payout():
    """Cobrar: la cascada de bolas cayendo en la bandeja (じゃらじゃら)."""
    rng = np.random.RandomState(68)
    parts = []
    for k in range(46):
        at = (k / 46) ** 1.4 * 1.1 + rng.uniform(0, 0.02)
        f = rng.uniform(2200, 4200)
        amp = 0.25 + 0.2 * rng.uniform() * (1 - k / 60)
        parts.append((_thud(f, 0.03, drop=0.05, amp=amp, curve=14), at))
    parts.append((bell(1567.98, 0.8, amp=0.35), 0.0))
    parts.append((bell(2093.0, 0.8, amp=0.3), 0.08))
    return fade_edges(reverb(_mix(1.4, *parts), mix=0.18), 5.0)


PACHINKO_SFX = {
    "pk_drop": (sfx_pk_drop, 0.5),
    "pk_pin": (sfx_pk_pin, 0.32),
    "pk_windmill": (sfx_pk_windmill, 0.5),
    "pk_tulip": (sfx_pk_tulip, 0.5),
    "pk_same": (sfx_pk_same, 0.66),
    "pk_up1": (sfx_pk_up1, 0.74),
    "pk_up2": (sfx_pk_up2, 0.86),
    "pk_out": (sfx_pk_out, 0.5),
    "pk_payout": (sfx_pk_payout, 0.8),
}


def main_pachinko():
    print("Generando efectos del pachinko...")
    for name, (fn, peak) in PACHINKO_SFX.items():
        write_wav(os.path.join(SFX_DIR, f"{name}.wav"), fn(), peak=peak)


def main_music():
    print("Generando variaciones de musica...")
    for name, fn in MUSIC_TRACKS.items():
        if name == "plaza":
            write_ogg_leveled(name, fn())
        else:
            write_ogg(name, fn())
    print("Generando musica del gachapon...")
    for name, fn in GACHA_MUSIC_TRACKS.items():
        write_ogg(name, fn())
        write_mp3(name)


def main():
    print("Generando efectos...")
    write_wav(os.path.join(SFX_DIR, "tick.wav"), sfx_tick(), peak=0.55)
    write_wav(os.path.join(SFX_DIR, "open.wav"), sfx_open(), peak=0.80)
    write_wav(os.path.join(SFX_DIR, "back.wav"), sfx_back(), peak=0.72)
    write_wav(os.path.join(SFX_DIR, "error.wav"), sfx_error(), peak=0.70)
    write_wav(os.path.join(SFX_DIR, "chime.wav"), sfx_chime(), peak=0.85)
    print("Generando efectos del gacha...")
    write_wav(os.path.join(SFX_DIR, "crank.wav"), sfx_crank(), peak=0.62)
    write_wav(os.path.join(SFX_DIR, "capsule.wav"), sfx_capsule(), peak=0.72)
    write_wav(os.path.join(SFX_DIR, "pop.wav"), sfx_pop(), peak=0.70)
    write_wav(os.path.join(SFX_DIR, "rare.wav"), sfx_rare(), peak=0.72)
    write_wav(os.path.join(SFX_DIR, "epic.wav"), sfx_epic(), peak=0.82)
    write_wav(os.path.join(SFX_DIR, "legend.wav"), sfx_legend(), peak=0.90)
    write_wav(os.path.join(SFX_DIR, "infinity.wav"), sfx_infinity(), peak=0.88)
    main_pinball()
    main_pachinko()



if __name__ == "__main__":
    import sys
    if "--music" in sys.argv:
        main_music()
    elif "--pinball" in sys.argv:
        main_pinball()
    elif "--pachinko" in sys.argv:
        main_pachinko()
    else:
        main()
        main_music()
