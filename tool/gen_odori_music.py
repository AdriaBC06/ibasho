#!/usr/bin/env python3
# Ibasho — canciones de Odori y su partitura base.
# Copyright (C) 2026 Adrià Bonnin Catalán
#
# Este archivo forma parte de Ibasho y se distribuye bajo GPL-3.0-or-later.
# Los archivos de audio que produce se publican bajo CC0 1.0 (dominio publico),
# tal y como se declara en CREDITS.md.
#
# Cada cancion se compone aqui nota a nota y, a la vez que el audio, se
# exporta su «partitura base»: cada golpe de bateria, cada nota de la melodia,
# del bajo y de los arpegios, con su tiempo exacto. De ahi saca Odori las
# partituras de 1 a 7 teclas y de las cinco dificultades
# (`lib/games/odori/odori_charter.dart`), asi que las notas siempre caen
# encima de algo que suena.
#
# Uso:  python3 tool/gen_odori_music.py [id ...]
# Requiere: numpy, scipy y ffmpeg en el PATH.

import json
import math
import os
import subprocess
import sys
import wave

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SR = 44100
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT_DIR = os.path.join(ROOT, "assets", "odori")


def song_dir(sid):
    """Cada cancion tiene su carpeta: assets/odori/<id base>/ (yako_ja_teto -> yako)."""
    return os.path.join(OUT_DIR, sid.split("_")[0])


# ----------------------------------------------------------------- utilidades

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def _blep(ph, dt):
    """Correccion polyBLEP: quita el aliasing del salto de una sierra."""
    out = np.zeros_like(ph)
    a = ph < dt
    x = ph[a] / dt[a]
    out[a] = x + x - x * x - 1.0
    b = ph > 1.0 - dt
    x = (ph[b] - 1.0) / dt[b]
    out[b] = x * x + x + x + 1.0
    return out


def saw(freq, n, phase0=0.0):
    """Sierra de banda limitada (polyBLEP). [freq] escalar o vector."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    dt = f / SR
    ph = (phase0 + np.cumsum(dt) - dt[0]) % 1.0
    return 2.0 * ph - 1.0 - _blep(ph, dt)


def square(freq, n, width=0.5, phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    dt = f / SR
    ph = (phase0 + np.cumsum(dt) - dt[0]) % 1.0
    s1 = 2.0 * ph - 1.0 - _blep(ph, dt)
    ph2 = (ph + (1.0 - width)) % 1.0
    s2 = 2.0 * ph2 - 1.0 - _blep(ph2, dt)
    return 0.5 * (s1 - s2)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.05):
    e = np.full(n, s, dtype=np.float64)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na, endpoint=False) if na else e[:na]
    nd = min(nd, n - na)
    if nd > 0:
        e[na:na + nd] = np.linspace(1, s, nd)
    nr = min(nr, n)
    if nr > 0:
        e[n - nr:] *= np.linspace(1, 0, nr)
    return e


def lowpass(x, cutoff, order=2):
    sos = butter(order, min(cutoff, SR * 0.45), btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = butter(order, cutoff, btype="high", fs=SR, output="sos")
    return sosfilt(sos, x)


def bandpass(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def sweep_lowpass(x, c0, c1, blocks=64):
    """Filtro que se abre o se cierra a lo largo de la senal."""
    out = np.zeros_like(x)
    edges = np.linspace(0, len(x), blocks + 1).astype(int)
    zi = None
    for i in range(blocks):
        c = c0 * (c1 / c0) ** (i / max(1, blocks - 1))
        b, a = butter(2, min(c, SR * 0.45), btype="low", fs=SR)
        if zi is None or len(zi) != max(len(a), len(b)) - 1:
            zi = np.zeros(max(len(a), len(b)) - 1)
        out[edges[i]:edges[i + 1]], zi = lfilter(b, a, x[edges[i]:edges[i + 1]], zi=zi)
    return out


def pan(mono, p):
    """p en -1..1, ley de potencia constante."""
    ang = (p + 1) * math.pi / 4
    return np.stack([mono * math.cos(ang), mono * math.sin(ang)], axis=1)


def feedback_delay(st, seconds, fb=0.35, mix=0.25, pingpong=True):
    d = int(seconds * SR)
    out = st.copy()
    tap = st.copy()
    for _ in range(6):
        tap = np.roll(tap, d, axis=0)
        tap[:d] = 0
        if pingpong:
            tap = tap[:, ::-1]
        tap = tap * fb
        out += tap * (mix / fb)
    return out


def reverb(st, seconds=1.8, mix=0.18, seed=5):
    """Reverb por convolucion con ruido que decae (estereo decorrelado)."""
    rng = np.random.RandomState(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.9 / seconds)
    out = st * (1 - mix)
    for ch in range(2):
        ir = rng.normal(0, 1, n) * env
        ir = lowpass(ir, 6500)
        ir /= np.sqrt(np.sum(ir ** 2))
        wet = np.fft.irfft(np.fft.rfft(st[:, ch], len(st) + n) * np.fft.rfft(ir, len(st) + n))[:len(st)]
        out[:, ch] += wet * mix
    return out


# ------------------------------------------------------------------ bateria

def kick(amp=1.0):
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 46 + 120 * np.exp(-t * 38) + 40 * np.exp(-t * 180)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9.5)
    click = highpass(np.random.RandomState(1).normal(0, 1, n), 2500) * np.exp(-t * 400) * 0.25
    x = np.tanh((body + click) * 1.8) * 0.9
    return amp * x


def clap(amp=1.0, seed=2):
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    noise = bandpass(np.random.RandomState(seed).normal(0, 1, n), 900, 5200)
    env = np.zeros(n)
    for k, off in enumerate((0.0, 0.009, 0.019)):
        o = int(off * SR)
        env[o:] += np.exp(-(t[: n - o]) * 160) * (0.8 if k < 2 else 1.0)
    env += np.exp(-t * 18) * 0.35
    snare_tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.35
    return amp * (noise * env * 0.9 + snare_tone)


def hat(amp=1.0, open_=False, seed=3):
    n = int((0.26 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    x = highpass(np.random.RandomState(seed).normal(0, 1, n), 7000, order=4)
    return amp * x * np.exp(-t * (14 if open_ else 90))


def crash(amp=1.0, seed=4):
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    x = highpass(np.random.RandomState(seed).normal(0, 1, n), 4200, order=2)
    x = x * np.exp(-t * 2.2) * (1 - np.exp(-t * 400))
    return amp * x


def riser(seconds, amp=1.0, seed=6):
    n = int(seconds * SR)
    x = np.random.RandomState(seed).normal(0, 1, n)
    x = sweep_lowpass(x, 300, 12000, blocks=96)
    env = np.linspace(0, 1, n) ** 2.2
    return amp * x * env


# ---------------------------------------------------------------- sintes

def supersaw(freq, dur, voices=7, detune=0.18, seed=0, cutoff=5200, env=None):
    n = int(dur * SR)
    rng = np.random.RandomState(seed)
    spread = np.linspace(-1, 1, voices)
    left = np.zeros(n)
    right = np.zeros(n)
    for i, s in enumerate(spread):
        f = freq * 2 ** (s * detune / 12.0)
        v = saw(f, n, phase0=rng.rand())
        g = 1.0 if i == voices // 2 else 0.62
        p = s * 0.8
        left += v * g * math.cos((p + 1) * math.pi / 4)
        right += v * g * math.sin((p + 1) * math.pi / 4)
    e = env if env is not None else adsr(n, 0.01, 0.2, 0.75, 0.08)
    st = np.stack([lowpass(left, cutoff) * e, lowpass(right, cutoff) * e], axis=1)
    return st / voices * 2.2


def pluck(freq, dur, bright=4200, amp=1.0, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = saw(freq, n, phase0=np.random.RandomState(seed).rand()) * 0.6 + square(freq * 2, n, 0.3) * 0.25
    # filtro que se cierra deprisa: el «plic» de un arpegio
    x = sweep_lowpass(x, bright, 600, blocks=16)
    return amp * x * np.exp(-t * 9) * adsr(n, 0.002, 0.0, 1.0, 0.02)


def lead(freq, dur, amp=1.0, vib=0.12, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    # vibrato que entra tarde, como una voz
    depth = vib * np.clip((t - 0.18) / 0.25, 0, 1)
    f = freq * 2 ** (depth * np.sin(2 * np.pi * 5.6 * t) / 12.0)
    x = square(f, n, 0.42) * 0.55 + saw(f * 1.003, n, phase0=0.3) * 0.45
    x = lowpass(x, 3800)
    e = adsr(n, 0.008, 0.12, 0.82, 0.05)
    return amp * x * e


def bass(freq, dur, amp=1.0, cutoff=900):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = saw(freq, n) * 0.7 + np.sin(2 * np.pi * freq * t) * 0.6
    x = sweep_lowpass(x, cutoff * 2.2, cutoff * 0.6, blocks=8)
    return amp * np.tanh(x * 1.4) * adsr(n, 0.004, 0.08, 0.8, 0.03)


def sub(freq, dur, amp=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return amp * np.sin(2 * np.pi * freq * t) * adsr(n, 0.004, 0.05, 0.9, 0.03)


def bell(freq, dur, amp=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 2.2 * np.exp(-t * 6)
    x = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * 3.5 * t))
    return amp * x * np.exp(-t * 3.8) * adsr(n, 0.002, 0, 1, 0.03)


def horn(freqs, dur, amp=1.0):
    """Bocina de tren: acorde de lengüetas que cae un poco al alejarse."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    bend = 2 ** (-0.7 * np.clip((t - dur * 0.5) / (dur * 0.5), 0, 1) / 12)
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        x += saw(f * bend * (1 + 0.0025 * i), n, phase0=0.13 * i) + square(f * bend * 0.5, n, 0.5) * 0.35
    x = bandpass(x, 220, 2800)
    return amp * x / len(freqs) * adsr(n, 0.07, 0.1, 0.9, 0.4)


def chug(amp=1.0, seed=7):
    """Golpe de rueda sobre la junta del rail: ruido grave muy corto."""
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    x = bandpass(np.random.RandomState(seed).normal(0, 1, n), 180, 1400)
    return amp * x * np.exp(-t * 60)


# ------------------------------------------------------------ la cancion

class Song:
    """Lienzo de una cancion: pistas estereo, marcas de sidechain y la
    partitura base que se ira anotando."""

    def __init__(self, sid, title, bpm, bars, lead_in=1.2, tail=2.5, key=0):
        self.id = sid
        # Transporte en semitonos: la cancion se escribe en un tono y suena
        # en otro (la voz de Sinsy canta comoda entre Mi4 y Sol#5).
        self.key = key
        self.title = title
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.lead_in = lead_in
        self.bars = bars
        self.length = lead_in + bars * 4 * self.beat + tail
        n = int(self.length * SR)
        self.buses = {k: np.zeros((n, 2)) for k in ("drums", "bass", "music", "lead", "fx", "vocal")}
        self.kicks = []
        self.events = []
        self.sections = []

    def hz(self, pitch):
        return midi_hz(pitch + self.key)

    def t(self, beat):
        return self.lead_in + beat * self.beat

    def put(self, bus, beat, st, gain=1.0):
        if st.ndim == 1:
            st = np.stack([st, st], axis=1)
        buf = self.buses[bus]
        s = int(round(self.t(beat) * SR))
        e = min(len(buf), s + len(st))
        if s < 0 or s >= len(buf):
            return
        buf[s:e] += st[: e - s] * gain

    def note(self, beat, role, pitch=0, length=0.0, accent=0):
        self.events.append([round(beat, 4), role, int(pitch), round(length, 4), int(accent)])

    def section(self, beat, name, energy):
        self.sections.append([beat, name, energy])

    # --- capas ---------------------------------------------------------

    def kick(self, beat, amp=1.0, chart=True):
        self.put("drums", beat, kick(amp))
        self.kicks.append(beat)
        if chart:
            self.note(beat, "k", 36, 0, 1 if beat % 4 == 0 else 0)

    def clap(self, beat, amp=0.8, chart=True):
        self.put("drums", beat, pan(clap(amp), 0.05))
        if chart:
            self.note(beat, "s", 38)

    def hat(self, beat, amp=0.25, open_=False, p=0.25, chart=True):
        self.put("drums", beat, pan(hat(amp, open_, seed=int(beat * 7) % 97), p))
        if chart:
            self.note(beat, "o" if open_ else "h", 42)

    def crash(self, beat, amp=0.35):
        self.put("fx", beat, pan(crash(amp), -0.2) + pan(crash(amp, seed=9), 0.3))
        self.note(beat, "x", 49, 0, 1)

    def bass(self, beat, pitch, length, amp=0.55, chart=True):
        f = self.hz(pitch)
        dur = length * self.beat
        self.put("bass", beat, bass(f, dur * 0.95, amp) + sub(f, dur * 0.95, amp * 0.6))
        if chart:
            self.note(beat, "b", pitch, length)

    def pad(self, beat, chord, length, amp=0.16, cutoff=4200):
        dur = length * self.beat
        for i, p in enumerate(chord):
            self.put("music", beat, supersaw(self.hz(p), dur, seed=p + i, cutoff=cutoff) * amp)

    def stab(self, beat, chord, length=0.5, amp=0.22):
        dur = length * self.beat
        n = int(dur * SR)
        env = adsr(n, 0.003, 0.14, 0.25, 0.04)
        for i, p in enumerate(chord):
            self.put("music", beat, supersaw(self.hz(p), dur, seed=p, cutoff=6500, env=env) * amp)
        self.note(beat, "c", chord[-1], length, 1)

    def arp(self, beat, pitch, length=0.25, amp=0.2, p=0.0, chart=True):
        self.put("music", beat, pan(pluck(self.hz(pitch), length * self.beat * 1.6, amp=amp, seed=pitch), p))
        if chart:
            self.note(beat, "a", pitch, length)

    def lead(self, beat, pitch, length, amp=0.3, chart=True):
        dur = length * self.beat
        self.put("lead", beat, pan(lead(self.hz(pitch), dur, amp), 0.0))
        if chart:
            self.note(beat, "l", pitch, length)

    def bell(self, beat, pitch, length, amp=0.22, chart=True):
        self.put("lead", beat, pan(bell(self.hz(pitch), max(0.6, length * self.beat * 1.5), amp), 0.15))
        if chart:
            self.note(beat, "l", pitch, length)

    def sing(self, phrases, voice="sinsy", amp=0.5, harmony_from=None, scale=MAJOR, tonic=60, formant=1.12):
        """Canta una lista de (pulso, nota, duracion, letra) con una voz de
        odori_voices. Desde el pulso [harmony_from] la misma voz canta ademas
        una tercera por encima, grabada aparte y un poco a la derecha."""
        import odori_voices as ov
        lines = [(phrases, 0.0, amp)]
        if harmony_from is not None:
            harm = [(b, third_above(p, scale, tonic), d, m) for (b, p, d, m) in phrases if b >= harmony_from]
            lines.append((harm, 0.35, amp * 0.42))
        for line, p, a in lines:
            print(f"    cantando {voice} ({len(line)} notas)...", flush=True)
            y = vocal_chain(ov.sing(voice, line, self.bpm, self.key, formant=formant))
            self.put("vocal", ov.score_start_bar(line) * 4, pan(y * a, p))
        for (beat, pitch, length, _) in phrases:
            self.note(beat, "v", pitch, length)

    def riser(self, beat, beats, amp=0.2):
        self.put("fx", beat, pan(riser(beats * self.beat, amp), 0))

    # --- mezcla --------------------------------------------------------

    def _sidechain(self, n, depth=0.6, release=0.22):
        env = np.ones(n)
        rel = int(release * SR)
        curve = 1 - depth * np.exp(-np.linspace(0, 4, rel))
        att = int(0.004 * SR)
        for b in self.kicks:
            s = int(round(self.t(b) * SR))
            if s >= n:
                continue
            e = min(n, s + rel)
            env[s:e] = np.minimum(env[s:e], curve[: e - s])
            a0 = max(0, s - att)
            env[a0:s] = np.minimum(env[a0:s], np.linspace(1, curve[0], s - a0))
        return env

    def mix(self):
        n = len(self.buses["drums"])
        sc = self._sidechain(n)[:, None]
        drums = self.buses["drums"]
        bassb = self.buses["bass"] * self._sidechain(n, 0.45, 0.16)[:, None]
        music = self.buses["music"] * sc
        music = reverb(music, 1.6, 0.16)
        leadb = feedback_delay(self.buses["lead"], self.beat * 0.75, fb=0.3, mix=0.22)
        leadb = reverb(leadb, 2.0, 0.2, seed=8)
        fx = reverb(self.buses["fx"], 2.4, 0.25, seed=11)
        out = drums * 1.0 + bassb * 0.95 + music * 0.8 + leadb * 0.85 + fx * 0.7
        voc = self.buses["vocal"]
        if np.any(voc):
            # La voz: eco a corchea con punto y sala algo mas larga que la
            # del lead. Sin copias cortas dobladas: hacen de flanger y le
            # cambian el timbre a la cantante.
            voc = feedback_delay(voc, self.beat * 0.75, fb=0.25, mix=0.14)
            voc = reverb(voc, 2.2, 0.22, seed=13)
            out = out * 0.82 + voc * 1.05
        # «pegamento»: un poco de saturacion y limitador suave
        out = np.tanh(out * 1.25) / np.tanh(1.25)
        fade = int(0.8 * SR)
        out[-fade:] *= np.linspace(1, 0, fade)[:, None]
        return out

    # --- salida --------------------------------------------------------

    def write(self, lufs=-13.0):
        out_dir = song_dir(self.id)
        os.makedirs(out_dir, exist_ok=True)
        out = self.mix()
        peak = np.max(np.abs(out)) or 1.0
        pcm = (np.clip(out / peak * 0.95, -1, 1) * 32767).astype("<i2")
        tmp = os.path.join(out_dir, f"_{self.id}.wav")
        with wave.open(tmp, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        # Ganancia fija medida (no loudnorm dinamico, que mueve los golpes).
        gain = measure_gain(tmp, lufs)
        ogg = os.path.join(out_dir, f"{self.id}.ogg")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
             "-af", f"volume={gain:.2f}dB,alimiter=limit=0.95:level=false",
             "-c:a", "libvorbis", "-q:a", "6", ogg],
            check=True,
        )
        os.remove(tmp)
        self.events.sort(key=lambda e: (e[0], e[1]))
        meta = {
            "id": self.id,
            "title": self.title,
            "bpm": self.bpm,
            "offset": round(self.lead_in, 4),
            "length": round(self.length, 3),
            "sections": self.sections,
            "events": self.events,
        }
        with open(os.path.join(out_dir, f"{self.id}.json"), "w") as f:
            json.dump(meta, f, separators=(",", ":"))
        print(f"  -> {os.path.relpath(ogg, ROOT)} ({os.path.getsize(ogg) // 1024} KiB, "
              f"{self.length:.1f} s, {len(self.events)} eventos)")


def third_above(pitch, scale=MAJOR, tonic=60):
    """Tercera diatonica por encima dentro de la escala escrita."""
    rel = (pitch - tonic) % 12
    octave = pitch - rel
    deg = min(range(7), key=lambda i: abs(scale[i] - rel))
    up = deg + 2
    return octave + scale[up % 7] + 12 * (up // 7)


def vocal_chain(y):
    """Limpieza comun a todas las voces: fuera graves, algo de presencia y
    compresion suave (EQ y dinamica: tambien valen para NEUTRINO)."""
    y = highpass(y, 140)
    y = y + 0.35 * bandpass(y, 2500, 6000)
    y = y / (np.max(np.abs(y)) or 1.0)
    return np.tanh(y * 1.2) / np.tanh(1.2)


def measure_gain(path, target):
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128", "-f", "null", "-"],
        capture_output=True, text=True,
    )
    lines = [l for l in r.stderr.splitlines() if l.strip().startswith("I:")]
    measured = float(lines[-1].split()[1]) if lines else -14.0
    return target - measured


# ---------------------------------------------------------- canciones

VERSE_LYRICS = [
    "よ る の ま ち  か け ぬ け て  ひ か り を お う  き み と",
    "ち い さ な て  に ぎ り し め  ほ し の う み え  い こ う",
]
CHORUS_LYRICS = ("は し れ は し れ  ほ し く ず  の み ち を こ え  て ゆ こ う  "
                 "と ど け と ど け  こ の こ え よ  よ ぞ ら を こ え て  あ す え")


def song_hoshikuzu(vocal=False, formant=1.0, suffix="_voz"):
    """«Hoshikuzu Dash»: la cancion de prueba. 150 bpm, La menor, electro
    J-pop brillante: intro, estrofa, subida, estribillo, respiro y
    estribillo final."""
    s = Song("hoshikuzu" + suffix if vocal else "hoshikuzu", "Hoshikuzu Dash", 150, bars=40, key=-4)
    sung = []
    # Progresion del estribillo: F G Em Am (VI VII v i en La menor)
    prog = [
        ([53, 57, 60, 64], 41),  # Fmaj7
        ([55, 59, 62, 67], 43),  # G
        ([52, 55, 59, 64], 40),  # Em
        ([57, 60, 64, 69], 45),  # Am
    ]
    verse = [
        ([57, 60, 64], 45),  # Am
        ([53, 57, 60], 41),  # F
        ([55, 59, 62], 43),  # G
        ([52, 55, 59], 40),  # Em
    ]

    def drums_full(bar, fill=False):
        b0 = bar * 4
        for q in range(4):
            s.kick(b0 + q)
            s.hat(b0 + q + 0.5, 0.3, open_=True, p=-0.2)
            s.hat(b0 + q + 0.25, 0.14, p=0.3, chart=False)
            s.hat(b0 + q + 0.75, 0.14, p=0.3, chart=False)
        s.clap(b0 + 1)
        s.clap(b0 + 3)
        if fill:
            for k in (3.25, 3.5, 3.75):
                s.clap(b0 + k, 0.55)

    def drums_half(bar):
        b0 = bar * 4
        s.kick(b0)
        s.kick(b0 + 2.5, 0.8)
        s.clap(b0 + 2, 0.7)
        for q in range(8):
            s.hat(b0 + q * 0.5, 0.18 if q % 2 else 0.24, p=0.25)

    def bass_pump(bar, root):
        b0 = bar * 4
        for q in range(4):
            s.bass(b0 + q + 0.5, root, 0.45, chart=(q % 2 == 1))
            s.bass(b0 + q + 0.75, root + 12, 0.2, amp=0.35, chart=False)

    def bass_walk(bar, root):
        b0 = bar * 4
        for k, off in enumerate((0, 1.5, 2, 3, 3.5)):
            s.bass(b0 + off, root + (12 if k == 3 else 0), 0.45 if off % 1 else 0.9)

    # Melodia del estribillo (compas, pulso, nota, duracion): 8 compases.
    chorus_mel = [
        (0, 0, 76, 1.0), (0, 1, 74, 0.5), (0, 1.5, 72, 0.5), (0, 2, 74, 1.0), (0, 3, 76, 0.5), (0, 3.5, 79, 0.5),
        (1, 0, 79, 1.5), (1, 1.5, 77, 0.5), (1, 2, 76, 1.0), (1, 3, 74, 1.0),
        (2, 0, 71, 0.5), (2, 0.5, 72, 0.5), (2, 1, 74, 1.0), (2, 2, 76, 0.5), (2, 2.5, 74, 0.5), (2, 3, 72, 1.0),
        (3, 0, 72, 0.5), (3, 0.5, 71, 0.5), (3, 1, 69, 2.5), (3, 3.5, 72, 0.5),
        (4, 0, 76, 1.0), (4, 1, 74, 0.5), (4, 1.5, 72, 0.5), (4, 2, 74, 1.0), (4, 3, 76, 0.5), (4, 3.5, 79, 0.5),
        (5, 0, 81, 1.5), (5, 1.5, 79, 0.5), (5, 2, 81, 0.5), (5, 2.5, 83, 0.5), (5, 3, 84, 1.0),
        (6, 0, 83, 0.5), (6, 0.5, 81, 0.5), (6, 1, 79, 0.5), (6, 1.5, 76, 0.5), (6, 2, 79, 1.0), (6, 3, 76, 0.5), (6, 3.5, 74, 0.5),
        (7, 0, 76, 3.0), (7, 3, 72, 0.5), (7, 3.5, 74, 0.5),
    ]
    verse_mel = [
        (0, 0.5, 69, 0.5), (0, 1, 72, 0.5), (0, 1.5, 76, 1.0), (0, 2.5, 74, 0.5), (0, 3, 72, 1.0),
        (1, 0.5, 69, 0.5), (1, 1, 72, 0.5), (1, 1.5, 77, 1.0), (1, 2.5, 76, 0.5), (1, 3, 72, 1.0),
        (2, 0.5, 71, 0.5), (2, 1, 74, 0.5), (2, 1.5, 79, 1.0), (2, 2.5, 77, 0.5), (2, 3, 76, 0.5), (2, 3.5, 74, 0.5),
        (3, 0, 71, 2.0), (3, 2.5, 68, 0.5), (3, 3, 71, 1.0),
    ]
    arp_shape = [0, 7, 12, 16, 12, 7, 19, 12]

    # --- Intro (0-3): pad filtrado, arpegio, riser
    s.section(0, "intro", 1)
    for bar in range(4):
        chord, root = verse[bar % 4]
        s.pad(bar * 4, chord, 4, amp=0.13, cutoff=1400 + bar * 500)
        for i in range(8):
            s.arp(bar * 4 + i * 0.5, chord[0] + 12 + arp_shape[i] % 12, 0.5, amp=0.14, p=-0.3 if i % 2 else 0.3,
                  chart=(i % 2 == 0))
        if bar >= 2:
            s.hat(bar * 4 + 2, 0.2, chart=False)
    s.riser(12, 4, 0.18)
    s.kick(15.5, 0.9)

    # --- Estrofa (4-11): media bateria, bajo andando, melodia de campana
    s.section(16, "verse", 2)
    for bar in range(4, 12):
        chord, root = verse[bar % 4]
        drums_half(bar)
        bass_walk(bar, root)
        s.pad(bar * 4, chord, 4, amp=0.1, cutoff=2400)
    s.crash(16, 0.25)
    for rep in range(2):
        for (b, q, p, d) in verse_mel:
            s.bell(16 + rep * 16 + b * 4 + q, p, d, amp=0.07 if vocal else 0.2, chart=not vocal)
        if vocal:
            moras = VERSE_LYRICS[rep].split()
            assert len(moras) == len(verse_mel)
            sung += [(16 + rep * 16 + b * 4 + q, p, d, m) for (b, q, p, d), m in zip(verse_mel, moras)]

    # --- Subida (12-15): corcheas de bombo que se aprietan
    s.section(48, "build", 3)
    for bar in range(12, 16):
        chord, root = prog[bar % 4]
        s.pad(bar * 4, chord, 4, amp=0.12, cutoff=1800 + (bar - 12) * 900)
        step = 1.0 if bar < 14 else 0.5
        k = 0.0
        while k < 4:
            s.kick(bar * 4 + k, 0.85)
            k += step
        if bar == 15:
            for k in (0, 0.5, 1, 1.5, 2, 2.25, 2.5, 2.75, 3, 3.25, 3.5, 3.75):
                s.clap(bar * 4 + k, 0.35 + k * 0.1)
        s.bass(bar * 4, root, 3.5, amp=0.4)
    s.riser(56, 8, 0.28)

    # --- Estribillo (16-23)
    def chorus(start_bar, big=False):
        s.section(start_bar * 4, "chorus", 5 if big else 4)
        s.crash(start_bar * 4, 0.35)
        for i in range(8):
            bar = start_bar + i
            chord, root = prog[i % 4]
            drums_full(bar, fill=(i == 7))
            bass_pump(bar, root)
            s.pad(bar * 4, [c + 12 for c in chord], 4, amp=0.13, cutoff=5200)
            s.stab(bar * 4, [c + 12 for c in chord[1:]], 0.5, amp=0.12)
            if big:
                for j in range(16):
                    s.arp(bar * 4 + j * 0.25, chord[j % 4] + 24, 0.25, amp=0.08, p=0.4 if j % 2 else -0.4,
                          chart=(j % 2 == 1))
        for (b, q, p, d) in chorus_mel:
            s.lead(start_bar * 4 + b * 4 + q, p, d, amp=0.1 if vocal else 0.32, chart=not vocal)
            if big:
                s.lead(start_bar * 4 + b * 4 + q, p - 12, d, amp=0.14, chart=False)
        s.crash(start_bar * 4 + 16, 0.2)

    chorus(16)

    # --- Respiro (24-27): pad y campana sola, el Tama respira
    s.section(96, "break", 2)
    for bar in range(24, 28):
        chord, root = verse[bar % 4]
        s.pad(bar * 4, chord, 4, amp=0.12, cutoff=1600)
        s.put("bass", bar * 4, sub(s.hz(root), 4 * s.beat, 0.35))
        s.note(bar * 4, "b", root, 4)
        for i in range(4):
            s.arp(bar * 4 + i, chord[i % 3] + 24, 1.0, amp=0.12)
    s.riser(104, 4, 0.3)
    for k in range(8):
        s.clap(108 + k * 0.5, 0.3 + k * 0.07)

    # --- Estribillo final (28-35) y cierre (36-39)
    chorus(28, big=True)
    if vocal:
        moras = CHORUS_LYRICS.split()
        assert len(moras) == len(chorus_mel), len(moras)
        for start in (64, 112):
            sung += [(start + b * 4 + q, p, d, m) for (b, q, p, d), m in zip(chorus_mel, moras)]
        s.sing(sung, "sinsy", formant=formant, harmony_from=112, scale=MINOR, tonic=57)
    s.section(144, "outro", 2)
    for bar in range(36, 40):
        chord, root = prog[bar % 4]
        s.pad(bar * 4, [c + 12 for c in chord], 4 if bar < 39 else 6, amp=0.12, cutoff=3200 - (bar - 36) * 600)
        if bar < 39:
            drums_half(bar)
            bass_walk(bar, root)
    s.crash(156, 0.3)
    s.kick(156)
    s.bass(156, 45, 2)
    s.stab(156, [69, 72, 76], 2, amp=0.14)
    return s


# --- «Yakō» (夜行列車): el ultimo tren nocturno ------------------------------

# Melodia (compas relativo, pulso, nota escrita en Do mayor, duracion).
YAKO_MEL = {
    "a1": [(0, 0.5, 67, .5), (0, 1, 72, .5), (0, 1.5, 72, .5), (0, 2, 71, .5), (0, 2.5, 72, .5), (0, 3, 74, 1),
           (1, 0.5, 74, .5), (1, 1, 76, .5), (1, 1.5, 74, .5), (1, 2, 72, 1), (1, 3, 71, 1),
           (2, 0.5, 69, .5), (2, 1, 72, .5), (2, 1.5, 72, .5), (2, 2, 71, .5), (2, 2.5, 72, .5), (2, 3, 76, 1),
           (3, 0, 74, 1.5), (3, 1.5, 72, .5), (3, 2, 71, 2)],
    "a2": [(0, 0.5, 69, .5), (0, 1, 72, .5), (0, 1.5, 72, .5), (0, 2, 74, .5), (0, 2.5, 76, .5), (0, 3, 77, 1),
           (1, 0.5, 76, .5), (1, 1, 74, .5), (1, 1.5, 72, .5), (1, 2, 72, 1), (1, 3, 67, 1),
           (2, 0.5, 69, .5), (2, 1, 72, .5), (2, 1.5, 74, .5), (2, 2, 76, .5), (2, 2.5, 74, .5), (2, 3, 72, 1),
           (3, 0, 74, 2.5)],
    "pre": [(0, 0, 69, .5), (0, 0.5, 69, .5), (0, 1, 71, .5), (0, 1.5, 72, 1), (0, 2.5, 71, .5), (0, 3, 72, .5),
            (0, 3.5, 74, .5),
            (1, 0, 76, 1), (1, 1, 74, 1), (1, 2, 72, 1), (1, 3, 74, 1),
            (2, 0, 69, .5), (2, 0.5, 69, .5), (2, 1, 71, .5), (2, 1.5, 72, 1), (2, 2.5, 74, .5), (2, 3, 76, .5),
            (2, 3.5, 77, .5),
            (3, 0, 79, 2)],
    "cho": [(0, 0, 76, 1), (0, 1, 77, .5), (0, 1.5, 76, .5), (0, 2, 74, .5), (0, 2.5, 72, 1), (0, 3.5, 72, .5),
            (1, 0, 74, .5), (1, 0.5, 76, .5), (1, 1, 74, 1), (1, 2, 71, .5), (1, 2.5, 67, 1.5),
            (2, 0, 71, .5), (2, 0.5, 72, .5), (2, 1, 74, .5), (2, 1.5, 76, 1), (2, 2.5, 79, .5), (2, 3, 76, 1),
            (3, 0, 74, .5), (3, 0.5, 72, 1.5), (3, 2.5, 69, .5), (3, 3, 72, .5), (3, 3.5, 74, .5),
            (4, 0, 76, 1), (4, 1, 77, .5), (4, 1.5, 76, .5), (4, 2, 74, .5), (4, 2.5, 72, 1), (4, 3.5, 72, .5),
            (5, 0, 74, .5), (5, 0.5, 76, .5), (5, 1, 79, 1), (5, 2, 77, .5), (5, 2.5, 76, 1), (5, 3.5, 74, .5),
            (6, 0, 76, 1), (6, 1, 74, .5), (6, 1.5, 72, 1), (6, 2.5, 74, .5), (6, 3, 72, .5), (6, 3.5, 71, .5),
            (7, 0, 72, 3)],
    "bri": [(0, 0, 69, 1), (0, 1, 72, 1), (0, 2, 76, 2),
            (1, 0, 74, 1), (1, 1, 72, 1), (1, 2, 71, 2),
            (2, 0, 69, 1), (2, 1, 72, 1), (2, 2, 77, 2),
            (3, 0, 76, 1), (3, 1, 74, 1), (3, 2, 79, 2)],
}
YAKO_MEL["a3"] = YAKO_MEL["a1"]  # la estrofa A' repite la melodia de A1

# Letras: una entrada por nota, «|» separa compases (se comprueba al cantar).
YAKO_LYRICS = {
    "ja": {
        "a1": "ま ど に う つ る | よ る の ま ち | ふ た り の せ て | は し る",
        "a2": "ね お ん の な み | か き わ け て | よ あ け の う み | え",
        "a3": "ち い さ な え き | す ぎ て ゆ く | こ と ば よ り も | ち か く",
        "pre": "れ ー る の う え お | は し れ ば | こ こ ろ が さ け ぶ | よ",
        "cho": "ひ か り を ぬ け | よ あ け ま で | き み と ふ た り | ど こ ま で も | "
               "ほ し を こ え て | か ぜ お ま と い | あ さ の う み え | ー",
        "bri": "ひ と り | じゃ な い | そ ば に | い る よ",
    },
    "es": {
        "a1": "る せ せん える’ く’りす’ たる’ | ら すぃう だ せ ば | び あ は もす’ ふん とす’ | え ねる’ と’れん",
        "a2": "く’る さん ど うん まる’ で | るす’ い で ね おん | あす’ た け さる’ が える’ | そる’",
        "a3": "ぱ さ ねす’ た すぃお ねす’ | すぃん で すぃ ら でぃおす’ | とぅ み ら だ でぃ せ | ます’ け よ",
        "pre": "える’ る もる’ で らす’ び あす’ | め かん た や | み こ ら そん ば ぐ’り たん | ど",
        "cho": "ぶえ ら ぽる’ ら の ちぇ | すぃん み ら ら と’らす’ | とぅ い よ すぃん みえ ど | "
               "あす’ たえる’ ふぃん でる’ まる’ | ま さ や でる’ すぃえ ろ | そ もす’ こ もえる’ びえん と | "
               "あす’ た べる’ さ り れる’ | そる’",
        "bri": "や の えす’ | たす’ そ ら | あ とぅ ら | ど えす’ とい",
    },
    "en": {
        "a1": "w.I.n d.oU S.oU.z D.@ s.I t.i | l.aI.t.s @ s.l.i.p b.I l.oU | j.u {.n.d aI @ b.O.r.d D.@ | "
              "m.I.d n.aI.t t.r.eI.n",
        "a2": "r.aI d.I.N w.eI.v.z @.v n.i A.n | T.r.u D.@ s.aI l.@.n.t s.i | O.l D.@ w.eI @.n t.I.l D.@ | d.O.n",
        "a3": "s.t.eI S.@.n.z p.{.s I.N b.aI V.s | n.A.t @ w.3.d t.@ s.eI | b.V.t j.O.r aI.z A.r t.E l.I.N | "
              "m.O.r D.{.n m.i",
        "pre": "h.I.r D.@ r.I D.@.m @.v D.@ r.eI.l.z | s.I.N I.N t.@ m.i | "
               "{.n.d m.aI h.A.r.t I.z s.k.r.i.m I.N aU.t | l.aU.d",
        "cho": "f.l.aI I.N T.r.u D.@ m.I.d n.aI.t | n.E v.3 l.U.k I.N b.{.k | j.u {.n.d aI t.@ g.E D.3 | "
               "t.@ D.i E.n.d @.v t.aI.m | h.aI @ b.V.v D.@ h.E v.@.n.z | w.i b.I k.V.m D.@ w.I.n.d n.aU | "
               "t.I.l w.i s.i D.@ m.O.r n.I.N | l.aI.t",
        "bri": "j.O.r n.A.t @ | l.oU.n t.@ n.aI.t | aI w.I.l s.t.eI | b.aI j.O.r s.aI.d",
    },
}

# Acordes escritos (Do mayor) y su bajo.
# Lo que se lee en pantalla, compas a compas, con los mismos cortes que
# YAKO_LYRICS. Un guion final une la palabra con el compas siguiente.
YAKO_TEXT = {
    "ja": {
        "a1": "窓に映る | 夜の街 | 二人乗せて | 走る",
        "a2": "ネオンの波 | かきわけて | 夜明けの海 | へ",
        "a3": "小さな駅 | 過ぎてゆく | 言葉よりも | 近く",
        "pre": "レールの上を | 走れば | 心が叫ぶ | よ",
        "cho": "光を抜け | 夜明けまで | 君と二人 | どこまでも | "
               "星を越えて | 風をまとい | 朝の海へ | ー",
        "bri": "一人 | じゃない | そばに | いるよ",
    },
    "es": {
        "a1": "Luces en el cristal | la ciudad se va | viajamos juntos | en el tren",
        "a2": "Cruzando un mar de | luz y de neón | hasta que salga el | sol",
        "a3": "Pasan estaciones | sin decir adiós | tu mirada dice | más que yo",
        "pre": "El rumor de las vías | me canta ya | mi corazón va gritan- | do",
        "cho": "Vuela por la noche | sin mirar atrás | tú y yo sin miedo | hasta el fin del mar | "
               "más allá del cielo | somos como el viento | hasta ver salir el | sol",
        "bri": "Ya no es- | tás sola, | a tu la- | do estoy",
    },
    "en": {
        "a1": "Window shows the city | lights asleep below | you and I aboard the | midnight train",
        "a2": "Riding waves of neon | through the silent sea | all the way until the | dawn",
        "a3": "Stations passing by us | not a word to say | but your eyes are telling | more than me",
        "pre": "Hear the rhythm of the rails | singing to me | and my heart is screaming out | loud",
        "cho": "Flying through the midnight | never looking back | you and I together | to the end of time | "
               "high above the heavens | we become the wind now | till we see the morning | light",
        "bri": "You're not a- | lone tonight | I will stay | by your side",
    },
}

# Romaji (Hepburn) del japones, con los mismos cortes: se lee debajo del kanji
YAKO_ROMAJI = {
    "a1": "Mado ni utsuru | yoru no machi | futari nosete | hashiru",
    "a2": "Neon no nami | kakiwakete | yoake no umi | e",
    "a3": "Chiisana eki | sugite yuku | kotoba yori mo | chikaku",
    "pre": "Rēru no ue o | hashireba | kokoro ga sakebu | yo",
    "cho": "Hikari o nuke | yoake made | kimi to futari | doko made mo | "
           "hoshi o koete | kaze o matoi | asa no umi e | ー",
    "bri": "Hitori | ja nai | soba ni | iru yo",
}

# Donde empieza cada parte cantada (pulso), igual que en song_yako
YAKO_LAYOUT = [(32, "a1"), (48, "a2"), (64, "pre"), (80, "cho"), (128, "a3"),
               (144, "pre"), (160, "cho"), (192, "bri"), (208, "cho")]


def yako_letra(lang):
    """Letra para el karaoke del juego: una linea cada dos compases, cada
    compas con su texto y las notas (pulso, duracion) que lo cantan, para
    iluminarlo nota a nota."""
    lines = []
    for start, part in YAKO_LAYOUT:
        texts = [t.strip() for t in YAKO_TEXT[lang][part].split("|")]
        bars = []
        for i, text in enumerate(texts):
            notes = [[start + bar * 4 + q, d] for (bar, q, p, d) in YAKO_MEL[part] if bar == i]
            assert notes, f"{lang}/{part} compas {i} sin notas"
            bars.append({"text": text, "notes": notes})
        for i in range(0, len(bars), 2):
            pair = bars[i:i + 2]
            lines.append({"start": pair[0]["notes"][0][0],
                          "end": pair[-1]["notes"][-1][0] + pair[-1]["notes"][-1][1],
                          "bars": pair})
    return {"id": f"yako_{lang}", "lang": lang, "lines": lines}


YAKO_SECTIONS = {"a1": "Estrofa 1", "a2": None, "pre": "Pre-estribillo", "cho": "Estribillo",
                 "a3": "Estrofa 2", "bri": "Puente"}
YAKO_HEAD = {"ja": ("日本語", "Yakō (夜行) — letra en japonés, con romaji"),
             "es": ("Español", "Yakō — letra en español"),
             "en": ("English", "Yakō — letra en inglés")}


def yako_letra_md(lang):
    """La letra entera para leer, en el orden en que se canta."""
    out = [f"# {YAKO_HEAD[lang][1]}", ""]
    for start, part in YAKO_LAYOUT:
        head = "Estribillo final (sube un semitono)" if (part, start) == ("cho", 208) else YAKO_SECTIONS[part]
        if head:
            out += [f"## {head}", ""]
        bars = [t.strip() for t in YAKO_TEXT[lang][part].split("|")]
        roma = [t.strip() for t in YAKO_ROMAJI[part].split("|")] if lang == "ja" else None
        for i in range(0, len(bars), 2):
            line = ""
            for b in bars[i:i + 2]:
                if b == "ー" or (lang == "ja" and len(b) == 1):  # «へ», «よ»: van pegadas
                    line += b
                elif line.endswith("-"):
                    line = line[:-1] + b
                else:
                    line += (" " if line else "") + b
            if line.endswith("-"):  # la palabra sigue en la linea siguiente
                line = line[:-1] + "–"
            out.append(line + "  ")
            if roma:
                r = " ".join(b for b in roma[i:i + 2] if b != "ー")
                out.append(f"*{r[0].upper() + r[1:]}*  ")
        out.append("")
    return "\n".join(out)


YAKO_CHORDS = {
    "C": ([60, 64, 67], 48), "G/B": ([59, 62, 67], 47), "Am": ([57, 60, 64], 45), "Em": ([55, 59, 64], 40),
    "F": ([57, 60, 65], 41), "C/E": ([55, 60, 64], 40), "Dm": ([57, 62, 65], 38), "G": ([55, 59, 62], 43),
    "Gsus": ([55, 60, 62], 43),
}
# (pulso dentro de la seccion, duracion, acorde)
YAKO_PROG = {
    "verse": [(0, 4, "C"), (4, 4, "G/B"), (8, 4, "Am"), (12, 4, "Em"),
              (16, 4, "F"), (20, 4, "C/E"), (24, 4, "Dm"), (28, 4, "G")],
    "pre": [(0, 4, "F"), (4, 4, "G"), (8, 2, "Em"), (10, 2, "Am"), (12, 2, "Gsus"), (14, 2, "G")],
    "cho": [(0, 4, "F"), (4, 4, "G"), (8, 4, "Em"), (12, 4, "Am"),
            (16, 4, "F"), (20, 4, "G"), (24, 2, "C/E"), (26, 2, "Am"), (28, 4, "C")],
    "bri": [(0, 4, "Am"), (4, 4, "F"), (8, 4, "C"), (12, 4, "G")],
}


def yako_lyric(lang, part):
    bars = [b.split() for b in YAKO_LYRICS[lang][part].split("|")]
    mel = YAKO_MEL[part]
    for i, words in enumerate(bars):
        n = sum(1 for m in mel if m[0] == i)
        assert len(words) == n, f"{lang}/{part} compas {i}: {len(words)} silabas para {n} notas"
    return [w for b in bars for w in b]


def song_yako(lang=None, voice=None):
    """«Yakō»: el ultimo tren nocturno. 160 bpm, escrita en Do mayor y sonando
    en Si bemol; el ultimo estribillo sube un semitono. Ruedas en el charles,
    campana de anden, bocina en la intro y supersierras."""
    vocal = voice is not None
    sid = f"yako_{lang}_{voice.split('_')[0]}" if vocal else "yako"
    # Teto esta grabada hacia Re4: se le baja la cancion para no estirarla
    # mas de una octava (el resto de voces canta en Si bemol).
    s = Song(sid, "Yakō", 160, bars=64, key=YAKO_KEY.get(voice, -2))
    sung = []

    def chords(start, prog, tr=0, pad=0.13, cutoff=4200, stab=False, up=0, bars=8):
        """Pinta el pad (y los stabs) de una progresion y devuelve
        (pulso, duracion, bajo, notas) de cada acorde."""
        items = [c for c in YAKO_PROG[prog] if c[0] < bars * 4]
        for (off, d, name) in items:
            notes, root = YAKO_CHORDS[name]
            notes = [n + tr + up for n in notes]
            s.pad(start + off, notes, d, amp=pad, cutoff=cutoff)
            if stab:
                s.stab(start + off, [n + 12 for n in notes[1:]], 0.5, amp=0.1)
        return [(start + off, d, YAKO_CHORDS[name][1] + tr, [n + tr for n in YAKO_CHORDS[name][0]])
                for (off, d, name) in items]

    def wheels(b0, beats, amp=1.0):
        """Charles a semicorcheas con el «chaca-chaca» de las ruedas."""
        acc = (0.2, 0.08, 0.15, 0.09)
        for k in range(int(beats * 4)):
            b = b0 + k * 0.25
            s.hat(b, acc[k % 4] * amp, p=0.3 if k % 2 else -0.15, chart=(k % 4 == 0 and amp > 0.7))
            if k % 2 == 0:
                s.put("drums", b, pan(chug(0.22 * amp * (1.3 if k % 4 == 0 else 0.8), seed=k % 5), -0.1))

    def ding(beat, tr=0, amp=0.22):
        """Campana de anden: «ding-ding»."""
        s.bell(beat, 84 + tr, 0.5, amp=amp)
        s.bell(beat + 0.5, 79 + tr, 1.0, amp=amp * 0.85)

    def horn_at(beat, beats, amp=0.35, tr=0):
        s.put("fx", beat, pan(horn([s.hz(p + tr) for p in (55, 59, 62, 64)], beats * s.beat, amp), -0.25))

    def melody(start, part, amp, tr=0, octave=False, chart=True):
        for (bar, q, p, d) in YAKO_MEL[part]:
            s.lead(start + bar * 4 + q, p + tr, d, amp=amp, chart=chart)
            if octave:
                s.lead(start + bar * 4 + q, p + tr - 12, d, amp=amp * 0.45, chart=False)

    def sing_part(start, part, tr=0):
        if vocal:
            words = yako_lyric(lang, part)
            sung.extend((start + bar * 4 + q, p + tr, d, w) for (bar, q, p, d), w in zip(YAKO_MEL[part], words))

    def verse(start, parts):
        s.section(start, "verse", 2)
        s.crash(start, 0.22)
        bars = len(parts) * 4
        for (b, d, root, notes) in chords(start, "verse", pad=0.09, cutoff=2400, bars=bars):
            bar = int(b // 4)
            s.kick(b)
            s.kick(b + 1.5, 0.75)
            s.kick(b + 2.5, 0.8)
            s.clap(b + 1, 0.55)
            s.clap(b + 3, 0.6)
            wheels(b, 4, 0.8)
            for k, off in enumerate((0, 1.5, 2, 3, 3.5)):
                s.bass(b + off, root + (12 if k == 3 else 0), 0.45 if off % 1 else 0.9)
            shape = [0, 1, 2, 1, 2, 0, 2, 1]
            for i in range(8):
                s.arp(b + i * 0.5, notes[shape[i]] + 12, 0.5, amp=0.1, p=-0.35 if i % 2 else 0.35,
                      chart=(i % 2 == 0 and bar % 2 == 0))
        for i, part in enumerate(parts):
            melody(start + i * 16, part, 0.06 if vocal else 0.24, chart=not vocal)
            sing_part(start + i * 16, part)

    def pre(start):
        s.section(start, "build", 3)
        prog = chords(start, "pre", pad=0.12, cutoff=2000)
        for (b, d, root, notes) in prog:
            s.bass(b, root, d * 0.9, amp=0.42)
            s.bass(b + d / 2, root + 12, d / 2 * 0.8, amp=0.3, chart=False)
        for bar in range(4):
            b0 = start + bar * 4
            step = 1.0 if bar < 2 else 0.5
            k = 0.0
            while k < 4 and not (bar == 3 and k >= 2):
                s.kick(b0 + k, 0.8)
                k += step
            wheels(b0, 4, 0.6 + bar * 0.15)
        for k in (0, 0.5, 1, 1.25, 1.5, 1.75):
            s.clap(start + 14 + k, 0.3 + k * 0.2)
        s.riser(start + 8, 8, 0.26)
        ding(start + 12, amp=0.14)
        melody(start, "pre", 0.06 if vocal else 0.26, chart=not vocal)
        sing_part(start, "pre")

    def chorus(start, tr=0, big=False):
        s.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.35)
        prog = chords(start, "cho", tr=tr, pad=0.12, cutoff=5200, stab=True, up=12)
        for (b, d, root, notes) in prog:
            for q in range(int(d)):
                s.bass(b + q + 0.5, root, 0.45, chart=(q % 2 == 1))
                s.bass(b + q + 0.75, root + 12, 0.2, amp=0.33, chart=False)
            if big:
                for j in range(int(d * 4)):
                    s.arp(b + j * 0.25, notes[j % 3] + 24, 0.25, amp=0.07, p=0.4 if j % 2 else -0.4,
                          chart=(j % 2 == 1))
        for bar in range(8):
            b0 = start + bar * 4
            for q in range(4):
                s.kick(b0 + q)
                s.hat(b0 + q + 0.5, 0.26, open_=True, p=-0.2)
            s.clap(b0 + 1)
            s.clap(b0 + 3)
            wheels(b0, 4, 0.55)
            if bar == 7:
                for k in (3.25, 3.5, 3.75):
                    s.clap(b0 + k, 0.5)
        ding(start + 28, tr, amp=0.12)
        melody(start, "cho", 0.08 if vocal else 0.3, tr=tr, octave=big, chart=not vocal)
        sing_part(start, "cho", tr)

    # --- Intro (0-7): el tren llega. Ruedas, bocina, campana; luego el gancho.
    s.section(0, "intro", 1)
    for bar in range(4):
        wheels(bar * 4, 4, 0.35 + bar * 0.15)
    horn_at(0, 3.5, 0.3)
    ding(8)
    ding(10)
    chords(0, "cho", pad=0.11, cutoff=900, bars=4)
    s.riser(8, 8, 0.2)
    hook = chords(16, "cho", pad=0.12, cutoff=3000, bars=4)
    for bar in range(4, 8):
        b0 = bar * 4
        for q in range(4):
            s.kick(b0 + q, 0.9)
        s.clap(b0 + 1, 0.6)
        s.clap(b0 + 3, 0.6)
        wheels(b0, 4, 0.7)
    for (b, d, root, _) in hook:
        for q in range(int(d)):
            s.bass(b + q + 0.5, root, 0.45, chart=(q % 2 == 1))
    for (bar, q, p, d) in YAKO_MEL["cho"]:
        if bar < 4:
            s.lead(16 + bar * 4 + q, p, d, amp=0.28)

    # --- Estrofa A (8-15), pre (16-19), estribillo (20-27)
    verse(32, ["a1", "a2"])
    pre(64)
    chorus(80)

    # --- Interludio (28-31): el gancho en el lead, campana
    s.section(112, "break", 3)
    for (b, d, root, notes) in chords(112, "cho", pad=0.11, cutoff=3600, bars=4):
        for q in range(int(d)):
            s.bass(b + q + 0.5, root, 0.45, chart=(q % 2 == 1))
    for bar in range(28, 32):
        b0 = bar * 4
        s.kick(b0)
        s.kick(b0 + 2)
        s.clap(b0 + 1, 0.5)
        s.clap(b0 + 3, 0.5)
        wheels(b0, 4, 0.8)
    for (bar, q, p, d) in YAKO_MEL["cho"]:
        if bar >= 4:
            s.lead(112 + (bar - 4) * 4 + q, p, d, amp=0.26)
    ding(124)

    # --- Estrofa A' (32-35), pre (36-39), estribillo (40-47)
    verse(128, ["a3"])
    pre(144)
    chorus(160)

    # --- Puente (48-51): medio tiempo, solo pad, campana y voz
    s.section(192, "bridge", 2)
    for (b, d, root, notes) in chords(192, "bri", pad=0.13, cutoff=1800):
        s.put("bass", b, sub(s.hz(root), d * s.beat, 0.35))
        s.note(b, "b", root, d)
        for i in range(4):
            s.arp(b + i, notes[i % 3] + 24, 1.0, amp=0.1)
    for bar in range(48, 52):
        b0 = bar * 4
        s.kick(b0, 0.8)
        s.clap(b0 + 2, 0.5)
        wheels(b0, 4, 0.3)
    melody(192, "bri", 0.06 if vocal else 0.24, chart=not vocal)
    sing_part(192, "bri")
    s.riser(200, 8, 0.3)
    for k in range(8):
        s.clap(204 + k * 0.5, 0.3 + k * 0.07)

    # --- Estribillo final (52-59) medio tono arriba, y el tren se va (60-63)
    chorus(208, tr=1, big=True)
    s.section(240, "outro", 2)
    for (b, d, root, notes) in chords(240, "cho", tr=1, pad=0.11, cutoff=2000, bars=3):
        s.bass(b, root, d * 0.9, amp=0.4)
    for bar in range(4):
        wheels(240 + bar * 4, 4, 0.8 - bar * 0.18)
    horn_at(244, 6, 0.28, tr=1)
    ding(250, 1, 0.2)
    s.crash(252, 0.3)
    s.kick(252)
    s.bass(252, 49, 3)
    s.stab(252, [61, 65, 68, 73], 3, amp=0.13)

    if vocal:
        s.sing(sung, voice, amp=0.5, harmony_from=208, tonic=61)
    return s


YAKO_KEY = {"teto": -5, "teto_en": -5}
YAKO_VOICES = {"ja": ["sinsy", "teto", "kiritan", "zundamon", "merrow"],
               "es": ["sinsy", "teto", "kiritan", "zundamon", "merrow"],
               "en": ["teto_en"]}


SONGS = {
    "hoshikuzu": song_hoshikuzu,
    "hoshikuzu_voz": lambda: song_hoshikuzu(vocal=True, formant=1.0),
    # la misma voz con los formantes un 12 % mas arriba: mas joven y brillante
    "hoshikuzu_voz_b": lambda: song_hoshikuzu(vocal=True, formant=1.12, suffix="_voz_b"),
    "yako": song_yako,
}
for _lang, _voices in YAKO_VOICES.items():
    for _v in _voices:
        SONGS[f"yako_{_lang}_{_v.split('_')[0]}"] = (lambda l, v: lambda: song_yako(l, v))(_lang, _v)


# Canciones nuevas (0.6.3): tool/canciones/<id>.py sobre tool/odori_canciones.py
NEW_SONGS = ["tamagoyaki", "hanabi", "nekobasu", "kasa", "tsukimi", "kaerimichi", "ibasho"]
import odori_canciones  # noqa: E402
odori_canciones.register(sys.modules[__name__],
                         [i for i in NEW_SONGS if os.path.exists(os.path.join(
                             os.path.dirname(os.path.abspath(__file__)), "canciones", i + ".py"))])


def main():
    if "--letras" in sys.argv:
        odori_canciones.write_letras(OUT_DIR)
        for lang in YAKO_TEXT:
            os.makedirs(song_dir("yako"), exist_ok=True)
            path = os.path.join(song_dir("yako"), f"yako_letra_{lang}.json")
            with open(path, "w") as f:
                json.dump(yako_letra(lang), f, ensure_ascii=False, separators=(",", ":"))
            print(f"  -> {os.path.relpath(path)}")
            md = os.path.join(ROOT, "docs", "letras", "yako", f"yako_{lang}.md")
            md = os.path.normpath(md)
            os.makedirs(os.path.dirname(md), exist_ok=True)
            with open(md, "w") as f:
                f.write(yako_letra_md(lang))
            print(f"  -> {os.path.relpath(md)}")
        return
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")] or list(SONGS)
    print("Generando canciones de Odori...")
    for sid in wanted:
        SONGS[sid]().write()


if __name__ == "__main__":
    main()
