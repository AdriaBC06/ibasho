"""Voces cantadas para la musica de Odori.

Cada voz recibe la misma partitura: una lista de (pulso, nota, duracion,
letra), donde la letra es kana tal y como suena. Un apostrofo curvo (’)
detras de un kana le quita la vocal: «そる’» se canta «sol», que es lo que
permite cantar en espanol con voces japonesas.

  sinsy     Sinsy + «NIT SONG070 F001» (CC BY 3.0), reafinada con WORLD.
  kiritan   NEUTRINO + Tohoku Kiritan (zunko.jp, uso no comercial).
  zundamon  NEUTRINO + Zundamon (zunko.jp, uso no comercial).
  merrow    NEUTRINO + Merrow (STUDIO NEUTRINO, uso libre).
  teto      UTAU: Kasane Teto (TWINDRILL, uso no comercial), sintetizada
            aqui con WORLD a partir del banco de voz (oto.ini).

Los bancos y NEUTRINO no van en el repositorio: se buscan en
$ODORI_VOICES (por defecto ~/.cache/ibasho-voices). Ver docs en
tool/gen_odori_music.py.

Las salidas de NEUTRINO no se pasan por ningun conversor de voz (su
licencia lo prohibe): solo se corrige la curva de tono con las propias
herramientas de NEUTRINO y se vuelve a generar.
"""

import glob
import math
import os
import subprocess

import numpy as np

SR = 44100
VOICES_DIR = os.environ.get("ODORI_VOICES", os.path.expanduser("~/.cache/ibasho-voices"))
NEUTRINO_DIR = os.path.join(VOICES_DIR, "neutrino", "NEUTRINO")
CACHE_DIR = os.path.join(VOICES_DIR, "_cache")
DROP = "’"

NEUTRINO_MODELS = {"kiritan": "KIRITAN", "zundamon": "ZUNDAMON", "merrow": "MERROW"}
VOICE_NAMES = {
    "sinsy": "NIT SONG070 F001",
    "kiritan": "Tohoku Kiritan",
    "zundamon": "Zundamon",
    "merrow": "Merrow",
    "teto": "Kasane Teto",
}

_STEPS = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
_ALTER = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]


# ------------------------------------------------------------ partitura

def score_start_bar(phrases):
    """La partitura empieza un compas antes de la primera nota: Sinsy quiere
    un silencio delante (sin el, desplaza la primera frase)."""
    return int(min(p[0] for p in phrases) // 4) - 1


def musicxml(phrases, bpm, key, lyric=lambda m: m):
    """Partitura de una sola voz, en compases de 4/4 y divisiones de
    semicorchea. Empieza un compas antes de la primera nota."""
    div = 4
    start_bar = score_start_bar(phrases)
    end_beat = max(p[0] + p[2] for p in phrases)
    bars = int(math.ceil(end_beat / 4)) - start_bar + 1
    notes = sorted(phrases)
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<score-partwise version="3.0"><part-list><score-part id="P1"><part-name>v</part-name></score-part></part-list>',
           '<part id="P1">']
    idx = 0
    for m in range(bars):
        b0 = (start_bar + m) * 4
        out.append(f'<measure number="{m + 1}">')
        if m == 0:
            out.append(f'<attributes><divisions>{div}</divisions><key><fifths>0</fifths></key>'
                       '<time><beats>4</beats><beat-type>4</beat-type></time></attributes>')
            out.append(f'<direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit>'
                       f'<per-minute>{bpm}</per-minute></metronome></direction-type><sound tempo="{bpm}"/></direction>')
        cur = b0
        while idx < len(notes) and notes[idx][0] < b0 + 4 - 1e-6:
            beat, pitch, length, mora = notes[idx]
            if beat > cur + 1e-6:
                out.append(f'<note><rest/><duration>{int(round((beat - cur) * div))}</duration></note>')
            n = pitch + key
            step, alter, octave = _STEPS[n % 12], _ALTER[n % 12], n // 12 - 1
            alt = f'<alter>{alter}</alter>' if alter else ''
            dur = int(round(min(length, b0 + 4 - beat) * div))
            out.append(f'<note><pitch><step>{step}</step>{alt}<octave>{octave}</octave></pitch>'
                       f'<duration>{dur}</duration><lyric><text>{lyric(mora)}</text></lyric></note>')
            cur = beat + dur / div
            idx += 1
        if cur < b0 + 4 - 1e-6:
            out.append(f'<note><rest/><duration>{int(round((b0 + 4 - cur) * div))}</duration></note>')
        out.append('</measure>')
    out.append('</part></score-partwise>')
    return "\n".join(out)


def target_semis(times, phrases, bpm, key, start_beat, shift=0, expressive=True):
    """Curva de tono (en semitonos MIDI) a partir de la partitura: cada nota
    en su sitio, portamento corto, ataque que entra un pelo por debajo y
    vibrato tardio en las notas largas."""
    beat = 60.0 / bpm
    notes = sorted(phrases)
    semis = np.full(len(times), np.nan)
    vib = np.zeros(len(times))
    scoop = np.zeros(len(times))
    for i, (b, p, d, _) in enumerate(notes):
        t0 = (b - start_beat) * beat
        nxt = (notes[i + 1][0] - start_beat) * beat if i + 1 < len(notes) else t0 + d * beat + 0.3
        t1 = max(t0 + d * beat, min(nxt, t0 + d * beat + 0.25))
        m = (times >= t0 - 0.02) & (times < t1)
        semis[m] = p + key + shift
        if not expressive:
            continue
        after_rest = i == 0 or (b - (notes[i - 1][0] + notes[i - 1][2])) > 0.2
        if after_rest:
            k = (times >= t0 - 0.06) & (times < t0 + 0.08)
            scoop[k] = -0.35 * (1 - np.clip((times[k] - t0 + 0.06) / 0.14, 0, 1)) ** 2
        dur = d * beat
        if dur >= 0.55:
            k = (times >= t0) & (times < t0 + dur)
            age = times[k] - t0
            depth = 0.28 * np.clip((age - 0.22) / 0.3, 0, 1)
            vib[k] = depth * np.sin(2 * np.pi * 5.7 * age)
    valid = ~np.isnan(semis)
    if not valid.any():
        return np.full(len(times), 60.0)
    idx = np.where(valid, np.arange(len(times)), 0)
    np.maximum.accumulate(idx, out=idx)
    semis = semis[idx]
    semis[: np.argmax(valid)] = semis[np.argmax(valid)]
    if not expressive:
        return semis
    w = np.hanning(11)
    w /= w.sum()
    semis = np.convolve(np.pad(semis, 5, mode="edge"), w, mode="valid")
    drift = 0.04 * np.sin(2 * np.pi * 0.9 * times) * np.sin(2 * np.pi * 0.37 * times + 1)
    return semis + vib + scoop + drift


def semis_hz(s):
    return 440.0 * 2 ** ((s - 69) / 12.0)


def _resample(x, sr):
    if sr == SR:
        return x
    from scipy.signal import resample_poly
    g = math.gcd(int(sr), SR)
    return resample_poly(x, SR // g, int(sr) // g)


def _read_wav(path):
    import wave
    with wave.open(path) as w:
        sr = w.getframerate()
        ch = w.getnchannels()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x, sr


# ------------------------------------------------------------ kana

_SMALL = set("ゃゅょぁぃぅぇぉゎ")
_VOWEL_OF = {}
for _v, _row in {
    "a": "あかさたなはまやらわがざだばぱぁゃゎ",
    "i": "いきしちにひみりぎじぢびぴぃ",
    "u": "うくすつぬふむゆるぐずづぶぷぅゅヴ",
    "e": "えけせてねへめれげぜでべぺぇ",
    "o": "おこそとのほもよろをごぞどぼぽぉょ",
}.items():
    for _c in _row:
        _VOWEL_OF[_c] = _v
_VOWEL_OF["ん"] = "n"
_CONS_OF = {}
for _c, _row in {
    "k": "かきくけこ", "g": "がぎぐげご", "s": "さすせそ", "sh": "し", "z": "ざずぜぞ", "j": "じぢ",
    "t": "たてと", "ch": "ち", "ts": "つ", "d": "だでど", "n": "なにぬねの", "h": "はひへほ", "f": "ふ",
    "m": "まみむめも", "y": "やゆよ", "r": "らりるれろ", "w": "わを", "b": "ばびぶべぼ", "p": "ぱぴぷぺぽ",
}.items():
    for _k in _row:
        _CONS_OF[_k] = _c


def kana_units(mora):
    """Parte una letra en unidades: [(kana, vocal, sin_vocal)]. «ー» alarga
    la vocal anterior; «’» deja solo la consonante del kana anterior."""
    units = []
    for ch in mora:
        if ch in _SMALL and units:
            k, _, d = units[-1]
            units[-1] = (k + ch, _VOWEL_OF[ch], d)
        elif ch == DROP and units:
            k, v, _ = units[-1]
            units[-1] = (k, v, True)
        elif ch == "ー" and units:
            v = units[-1][1]
            units.append(({"a": "あ", "i": "い", "u": "う", "e": "え", "o": "お", "n": "ん"}[v], v, False))
        elif ch in _VOWEL_OF:
            units.append((ch, _VOWEL_OF[ch], False))
    return units


def sinsy_lyric(mora):
    """Sinsy no sabe quitar vocales: se queda con los kana que suenan con
    vocal (las consonantes sueltas se pierden)."""
    return "".join(k for k, _, d in kana_units(mora) if not d) or "あ"


# ------------------------------------------------------------ NEUTRINO

def _neutrino_run(xml_path, name, model, skip_f0=False):
    env = dict(os.environ, LD_LIBRARY_PATH=os.path.join(NEUTRINO_DIR, "bin"))
    b = lambda *p: os.path.join(NEUTRINO_DIR, *p)
    lab_full, lab_mono = b("score", "label", "full", name + ".lab"), b("score", "label", "mono", name + ".lab")
    lab_time = b("score", "label", "timing", name + ".lab")
    for d in ("full", "mono", "timing"):
        os.makedirs(b("score", "label", d), exist_ok=True)
    os.makedirs(b("output"), exist_ok=True)
    if not skip_f0:
        subprocess.run([b("bin", "musicXMLtoLabel"), xml_path, lab_full, lab_mono],
                       check=True, capture_output=True, env=env, cwd=NEUTRINO_DIR)
    args = [b("bin", "neutrino"), lab_full, lab_time, b("output", name + ".f0"), b("output", name + ".melspec"),
            b("output", name + ".wav"), b("model", model) + "/", "-n", str(os.cpu_count() or 4)]
    if skip_f0:
        args += ["--skip-timing", "--skip-f0"]
    subprocess.run(args, check=True, capture_output=True, env=env, cwd=NEUTRINO_DIR)
    return b("output", name + ".f0"), b("output", name + ".wav")


def _read_lab(path):
    rows = []
    with open(path) as f:
        for line in f:
            p = line.split()
            if len(p) >= 3:
                rows.append((int(p[0]) / 1e7, int(p[1]) / 1e7, p[2]))
    return rows


def _neutrino_fix_f0(f0_path, mono_path, timing_path, phrases, bpm, key, start_beat):
    """Afina lo que NEUTRINO canta desafinado sin quitarle su expresion. Con
    los tiempos reales de cada fonema, cada vocal se centra en el tono de su
    nota (mediana) y los desvios grandes se comprimen; las consonantes y los
    primeros 40 ms de cada vocal (la transicion) se dejan como estan."""
    f0 = np.fromfile(f0_path, dtype="<f4").astype(np.float64)
    fp = 0.01
    times = np.arange(len(f0)) * fp
    voiced = f0 > 1
    st = np.where(voiced, 69 + 12 * np.log2(np.maximum(f0, 1) / 440.0), np.nan)
    beat = 60.0 / bpm
    starts = {round((b - start_beat) * beat, 2): p + key for (b, p, _, _) in phrases}
    mono, timing = _read_lab(mono_path), _read_lab(timing_path)
    corr = np.zeros(len(f0))
    touched = np.zeros(len(f0), bool)
    for (m0, _, ph), (a0, a1, ph2) in zip(mono, timing):
        if ph not in ("a", "i", "u", "e", "o", "N") or ph != ph2:
            continue
        tgt = starts.get(round(m0, 2))
        if tgt is None:
            # varias moras en una nota: la nota que empieza justo antes
            prev = [t for t in starts if t <= m0 + 1e-3]
            if not prev:
                continue
            tgt = starts[max(prev)]
        k = (times >= a0) & (times < a1) & voiced
        steady = k & (times >= a0 + min(0.04, 0.4 * (a1 - a0)))
        if steady.sum() < 2:
            continue
        dev = st[steady] - tgt
        off = float(np.median(dev))
        if abs(off) > 2.5:  # otra nota (octava o salto de la red): no tocar
            continue
        ramp = np.clip((times - a0) / 0.04, 0, 1)
        resid = st - tgt - off
        soft = 0.4 * np.tanh(resid / 0.4)
        c = (-off + (soft - resid)) * ramp
        corr[k] = c[k]
        touched |= k
    # suaviza la correccion para que no haya escalones
    w = np.hanning(7)
    w /= w.sum()
    corr = np.convolve(np.pad(corr, 3, mode="edge"), w, mode="valid")
    # suaviza la correccion para que no haya escalones
    w = np.hanning(7)
    w /= w.sum()
    corr = np.convolve(np.pad(corr, 3, mode="edge"), w, mode="valid")
    out = np.where(voiced, f0 * 2 ** (corr / 12.0), f0)
    out.astype("<f4").tofile(f0_path)


def sing_neutrino(voice, phrases, bpm, key):
    model = NEUTRINO_MODELS[voice]
    name = f"odori_{voice}"
    xml = os.path.join(NEUTRINO_DIR, "score", "musicxml", name + ".musicxml")
    os.makedirs(os.path.dirname(xml), exist_ok=True)
    score = musicxml(phrases, bpm, key)
    import hashlib
    cached = os.path.join(CACHE_DIR, "neutrino_" + hashlib.md5((model + score).encode()).hexdigest() + ".npy")
    if os.path.exists(cached):
        return np.load(cached)
    with open(xml, "w") as f:
        f.write(score)
    f0_path, wav_path = _neutrino_run(xml, name, model)
    lab = lambda d: os.path.join(NEUTRINO_DIR, "score", "label", d, name + ".lab")
    _neutrino_fix_f0(f0_path, lab("mono"), lab("timing"), phrases, bpm, key, score_start_bar(phrases) * 4)
    _, wav_path = _neutrino_run(xml, name, model, skip_f0=True)
    x, sr = _read_wav(wav_path)
    y = _resample(x, sr)
    os.makedirs(CACHE_DIR, exist_ok=True)
    np.save(cached, y.astype(np.float32))
    return y


# ------------------------------------------------------------ Sinsy

def sing_sinsy(phrases, bpm, key, formant=1.12):
    """Voz de Sinsy reafinada con WORLD. formant > 1 aclara el timbre."""
    import pysinsy
    import pyworld as pw
    htsvoice = os.environ.get("ODORI_HTSVOICE", "")
    if not htsvoice:
        found = glob.glob(os.path.join(VOICES_DIR, "**", "*.htsvoice"), recursive=True)
        htsvoice = found[0] if found else ""
    path = os.path.join(CACHE_DIR, "_sinsy.xml")
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(path, "w") as f:
        f.write(musicxml(phrases, bpm, key, lyric=sinsy_lyric))
    sinsy = pysinsy.sinsy.Sinsy()
    assert sinsy.setLanguages("j", pysinsy.get_default_dic_dir())
    assert sinsy.loadVoices(htsvoice), "falta nitech_jp_song070_f001.htsvoice (ODORI_HTSVOICE)"
    assert sinsy.loadScoreFromMusicXML(path)
    wav, sr = sinsy.synthesize()
    sinsy.clearScore()
    x = np.asarray(wav, dtype=np.float64)
    x = _resample(x / (np.max(np.abs(x)) or 1.0), int(sr))
    fp = 5.0
    f0, times = pw.harvest(x, SR, f0_floor=90, f0_ceil=1100, frame_period=fp)
    sp = pw.cheaptrick(x, f0, times, SR)
    ap = pw.d4c(x, f0, times, SR)
    sp = warp_formants(sp, formant)
    tgt = semis_hz(target_semis(times, phrases, bpm, key, score_start_bar(phrases) * 4))
    y = pw.synthesize(np.ascontiguousarray(np.where(f0 > 0, tgt, 0.0)), sp, ap, SR, fp)
    return y[: len(x)]


def warp_formants(sp, alpha):
    """Mueve los formantes: alpha > 1 aclara (voz mas joven), < 1 oscurece."""
    if abs(alpha - 1) < 1e-3:
        return sp
    bins = sp.shape[1]
    src = np.clip(np.arange(bins) / alpha, 0, bins - 1)
    lo = np.floor(src).astype(int)
    hi = np.minimum(lo + 1, bins - 1)
    fr = src - lo
    return np.ascontiguousarray(sp[:, lo] * (1 - fr) + sp[:, hi] * fr)


# ------------------------------------------------------------ UTAU

class UtauBank:
    """Un banco UTAU: los oto.ini de sus subcarpetas (el ultimo pisa a los
    anteriores si comparten alias)."""

    def __init__(self, root, subs):
        self.otos = {}
        for sub in subs:
            d = os.path.join(root, sub)
            with open(os.path.join(d, "oto.ini"), "rb") as f:
                text = f.read().decode("cp932", errors="replace")
            for line in text.splitlines():
                if "=" not in line:
                    continue
                fn, rest = line.split("=", 1)
                parts = rest.split(",")
                if len(parts) < 6:
                    continue
                alias = parts[0] or os.path.splitext(fn)[0]
                try:
                    vals = [float(v) for v in parts[1:6]]
                except ValueError:
                    continue
                self.otos[alias] = (os.path.join(d, fn), *vals)
        self._an = {}

    def get(self, *aliases):
        for a in aliases:
            if a in self.otos:
                return self.otos[a]
        return None

    def analysis(self, path):
        """f0, sp, ap y sonoridad de un wav del banco (se guarda en cache)."""
        if path in self._an:
            return self._an[path]
        import hashlib
        import pyworld as pw
        os.makedirs(CACHE_DIR, exist_ok=True)
        key = hashlib.md5(path.encode()).hexdigest()
        cpath = os.path.join(CACHE_DIR, key + ".npz")
        if os.path.exists(cpath):
            z = np.load(cpath)
            res = (z["f0"], z["sp"], z["ap"])
        else:
            x, sr = _read_wav(path)
            x = _resample(x, sr)
            f0, t = pw.harvest(x, SR, f0_floor=100, f0_ceil=900, frame_period=5.0)
            sp = pw.cheaptrick(x, f0, t, SR)
            ap = pw.d4c(x, f0, t, SR)
            res = (f0.astype(np.float32), sp.astype(np.float32), ap.astype(np.float32))
            np.savez(cpath, f0=res[0], sp=res[1], ap=res[2])
        self._an[path] = res
        return res


_BANKS = {}


def _bank(name):
    """teto: japones (単独音 + 連続音). teto_en: el banco ingles (VCCV)."""
    if name not in _BANKS:
        folder, subs = {
            "teto": ("teto", ["重音テト単独音", "重音テト連続音"]),
            "teto_en": ("teto_en", ["重音テト英語音源"]),
        }[name]
        roots = [r for r in glob.glob(os.path.join(VOICES_DIR, folder, "*")) if os.path.isdir(r)]
        assert roots, f"falta el banco de Kasane Teto en {VOICES_DIR}/{folder}"
        _BANKS[name] = UtauBank(roots[0], subs)
    return _BANKS[name]


def _utau_segments(phrases, bpm, start_beat):
    """Convierte la partitura en unidades con su tiempo: (t0, t1, kana,
    vocal, sin_vocal). Varias unidades en una nota se reparten: las
    consonantes sueltas y la «ん» final se quedan con un trocito."""
    beat = 60.0 / bpm
    segs = []
    for (b, _, d, mora) in sorted(phrases):
        t0 = (b - start_beat) * beat
        t1 = t0 + d * beat
        units = kana_units(mora)
        if not units:
            continue
        # tiempos: consonantes sueltas 70 ms, «ん» final hasta 30 %, las
        # vocales de delante cortas (diptongos) y la ultima con el resto
        dur = t1 - t0
        full = [i for i, u in enumerate(units) if not u[2] and not (u[0] == "ん" and i == len(units) - 1 and i > 0)]
        tail_n = min(0.3 * dur, 0.16) if units[-1][0] == "ん" and len(units) > 1 else 0.0
        lead = min(0.1, 0.3 * dur / max(1, len(full)))
        fixed = sum(0.07 for u in units if u[2]) + tail_n + lead * max(0, len(full) - 1)
        t = t0
        for i, (k, v, drop) in enumerate(units):
            if drop:
                dt = 0.07
            elif i not in full:
                dt = tail_n
            elif i != full[-1]:
                dt = lead
            else:
                dt = max(0.05, dur - fixed)
            segs.append([t, t + dt, k, v, drop])
            t += dt
    return segs


def _plan_jp(bank, phrases, bpm, start_beat):
    """Plan de muestras para el banco japones: VCV («a か») si la unidad va
    pegada a la anterior, CV («- か») si empieza frase, VC («a s») para las
    consonantes sueltas y «a R» para soltar al final de frase."""
    segs = _utau_segments(phrases, bpm, start_beat)
    plan = []
    prev = None
    for i, (t0, t1, k, v, drop) in enumerate(segs):
        glued = prev is not None and t0 - prev[1] < 0.03 and prev[3] in "aiueon"
        pv = prev[3] if glued else None
        if drop:
            if pv is None:
                prev = None
                continue
            oto = bank.get(f"{pv} {_CONS_OF.get(k[0], 'n')}")
        elif pv is not None:
            oto = bank.get(f"{pv} {k}", f"{pv} {k[0]}", f"- {k}", k)
        else:
            oto = bank.get(f"- {k}", k)
        if oto is None:
            prev = [t0, t1, k, v if not drop else "_"]
            continue
        nxt_glued = i + 1 < len(segs) and segs[i + 1][0] - t1 < 0.03
        plan.append((t0, t1, oto, nxt_glued))
        if not nxt_glued and not drop and v in "aiueon":
            rel = bank.get(f"{v} R")
            if rel is not None:
                plan.append((t1, t1 + 0.18, rel, False))
        prev = [t0, t1, k, v if not drop else "_"]
    return plan


EN_VOWELS = {"@", "{", "3", "A", "aI", "aU", "E", "eI", "i", "I", "O", "OI", "oU", "u", "U", "V"}


def en_syllable(tok):
    """«n.aI.t» -> (["n"], "aI", ["t"]). Fonemas X-SAMPA del banco ingles."""
    ph = [p for p in tok.split(".") if p]
    vi = next((i for i, p in enumerate(ph) if p in EN_VOWELS), None)
    if vi is None:
        return ph, None, []
    return ph[:vi], ph[vi], ph[vi + 1:]


def _plan_en(bank, phrases, bpm, start_beat):
    """Plan para el banco ingles (VCCV): «- CV» al empezar frase, «V C» +
    «CV» entre silabas (o «V hV» y «V V»), grupos como «st» o «str» con su
    propia muestra, «V C-» y «V -» para cerrar."""
    beat = 60.0 / bpm
    notes = sorted(phrases)
    plan = []
    for i, (b, _, d, tok) in enumerate(notes):
        t0 = (b - start_beat) * beat
        t1 = t0 + d * beat
        onset, v, coda = en_syllable(tok)
        if v is None:
            continue
        prev = notes[i - 1] if i else None
        glued = prev is not None and b - (prev[0] + prev[2]) < 0.05
        pv = en_syllable(prev[3]) if glued else None
        nxt = notes[i + 1] if i + 1 < len(notes) else None
        nxt_glued = nxt is not None and nxt[0] - (b + d) < 0.05
        items = []
        cv = (onset[-1] if onset else "") + v
        if pv is not None and not pv[2]:
            # la silaba anterior acaba en vocal: transicion desde ella
            pvv = pv[1]
            if not onset:
                items.append(bank.get(f"{pvv} {v}", v))
            elif onset == ["h"]:
                items.append(bank.get(f"{pvv} h{v}", f"h{v}", f"- h{v}"))
            else:
                vc = bank.get(f"{pvv} {onset[0]}")
                if vc is not None and plan:
                    # la «V C» se come el final de la nota anterior
                    L = min(0.12, 0.35 * (plan[-1][1] - plan[-1][0]))
                    pt0, pt1, poto, _ = plan[-1]
                    plan[-1] = (pt0, t0 - L, poto, True)
                    plan.append((t0 - L, t0, vc, True))
                if len(onset) > 1:
                    items.append(bank.get("".join(onset)))
                items.append(bank.get(cv, f"- {cv}"))
        else:
            # tras silencio, «- CV»; pegada a una consonante final, «CV» a secas
            dash = lambda a: (f"- {a}", a) if pv is None else (a, f"- {a}")
            if len(onset) > 1:
                items.append(bank.get(*dash("".join(onset))))
                items.append(bank.get(cv, f"- {cv}"))
            elif onset:
                items.append(bank.get(*dash(cv)))
            else:
                items.append(bank.get(*dash(v)))
        items = [o for o in items if o is not None]
        if not items:
            continue
        # consonantes de un grupo: 60 ms cada una antes de la vocal
        n_pre = len(items) - 1
        t = t0 - 0.06 * n_pre
        for k, oto in enumerate(items):
            end = t0 if k < n_pre else t1
            plan.append((t, end, oto, True))
            t = end
        # cierre de la silaba
        if coda:
            last = plan[-1]
            L = min(0.14, 0.4 * (t1 - t0))
            plan[-1] = (last[0], t1 - L, last[2], True)
            first = bank.get(f"{v} {coda[0]}-" if not nxt_glued and len(coda) == 1 else f"{v} {coda[0]}",
                             f"{v} {coda[0]}")
            rest = [bank.get(c) for c in coda[1:]]
            chain = [o for o in [first] + rest if o is not None]
            step = L / max(1, len(chain))
            for k, oto in enumerate(chain):
                plan.append((t1 - L + k * step, t1 - L + (k + 1) * step, oto, k + 1 < len(chain)))
            plan[-1] = (plan[-1][0], plan[-1][1], plan[-1][2], nxt_glued)
        else:
            plan[-1] = (plan[-1][0], plan[-1][1], plan[-1][2], nxt_glued)
            if not nxt_glued:
                plan[-1] = (plan[-1][0], plan[-1][1], plan[-1][2], True)
                rel = bank.get(f"{v} -")
                if rel is not None:
                    plan.append((t1, t1 + 0.16, rel, False))
    return plan


def _fit_plan(plan, share=0.5):
    """Lo que hace UTAU con las notas rapidas: si la entrada de una muestra
    (preutterance - overlap) no cabe en la mitad de la unidad anterior, se
    encogen preutterance y overlap en proporcion y la muestra se lee desde mas
    tarde, para que no se monten tres muestras a la vez y se emborrone."""
    out = []
    for j, (t0, t1, oto, glued) in enumerate(plan):
        path, off, cons, cut, pre, ovl = oto
        if j > 0 and plan[j - 1][3]:
            room = (t0 - plan[j - 1][0]) * 1000.0 * share
            if pre - ovl > room > 0:
                r = room / (pre - ovl)
                skip = pre * (1 - r)
                off, cons = off + skip, max(0.0, cons - skip)
                cut = cut + skip if cut < 0 else cut
                pre, ovl = pre * r, ovl * r
        out.append((t0, t1, (path, off, cons, cut, pre, ovl), glued))
    return out


def sing_utau(bank, phrases, bpm, key, planner):
    """Sintesis concatenativa en el dominio de WORLD: cada unidad toma su
    muestra del banco segun el plan, se alarga la vocal hasta lo que dure la
    nota, se funden los solapes y se canta todo de una vez sobre la curva de
    tono de la partitura."""
    import pyworld as pw
    fp = 0.005
    start_beat = score_start_bar(phrases) * 4
    beat = 60.0 / bpm
    end_t = (max(p[0] + p[2] for p in phrases) - start_beat) * beat + 1.0
    nfr = int(end_t / fp) + 1
    fft = None
    acc_sp = acc_ap = None
    acc_w = np.zeros(nfr)
    acc_v = np.zeros(nfr)
    plan = _fit_plan(planner(bank, phrases, bpm, start_beat))

    for j, (t0, t1, oto, glued_next) in enumerate(plan):
        path, off, cons, cut, pre, ovl = oto
        f0s, sps, aps = bank.analysis(path)
        n_src = len(f0s)
        s0 = off / 1000.0
        s_end = s0 - cut / 1000.0 if cut < 0 else n_src * fp - cut / 1000.0
        s_fix = s0 + cons / 1000.0
        T = t0 - pre / 1000.0  # la muestra empieza antes de la nota
        # hasta donde tiene que sonar: si la siguiente va pegada, hasta que
        # entra su muestra mas su solape; si no, hasta el final de la nota
        if glued_next and j + 1 < len(plan):
            nt0, _, noto, _ = plan[j + 1]
            end = nt0 - noto[4] / 1000.0 + noto[5] / 1000.0
        else:
            end = t1
        end = max(end, T + (s_fix - s0) + 0.02)
        # mapa tiempo de salida -> tiempo de muestra
        fr0 = max(0, int(T / fp))
        fr1 = min(nfr, int(end / fp) + 1)
        if fr1 <= fr0:
            continue
        tt = np.arange(fr0, fr1) * fp
        rel_t = tt - T
        fix_len = s_fix - s0
        stretch_src = max(0.02, s_end - s_fix)
        stretch_dst = max(0.02, (end - T) - fix_len)
        src_t = np.where(rel_t < fix_len, s0 + rel_t,
                         s_fix + (rel_t - fix_len) * min(1.0, stretch_src / stretch_dst))
        # si hay que alargar mucho, el ultimo tramo se pasea por la vocal
        if stretch_dst > stretch_src:
            k = rel_t >= fix_len
            u = (rel_t[k] - fix_len) / stretch_dst  # 0..1
            src_t[k] = s_fix + u * stretch_src
        src_i = np.clip(src_t / fp, 0, n_src - 1)
        lo = np.floor(src_i).astype(int)
        hi = np.minimum(lo + 1, n_src - 1)
        a = (src_i - lo)[:, None]
        sp = np.log(np.maximum(sps[lo], 1e-12)) * (1 - a) + np.log(np.maximum(sps[hi], 1e-12)) * a
        ap = aps[lo] * (1 - a) + aps[hi] * a
        vo = ((f0s[lo] > 0) & (f0s[hi] > 0)).astype(float)
        if acc_sp is None:
            fft = sp.shape[1]
            acc_sp = np.zeros((nfr, fft))
            acc_ap = np.zeros((nfr, fft))
        # pesos: entra en su solape y sale en el solape de la siguiente
        w = np.ones(len(tt))
        fin = max(fp, ovl / 1000.0)
        w *= np.clip(rel_t / fin, 0, 1)
        if glued_next and j + 1 < len(plan):
            nov = max(fp, plan[j + 1][2][5] / 1000.0)
            w *= np.clip((end - tt) / nov, 0, 1)
        else:
            w *= np.clip((end - tt) / 0.03, 0, 1)
        w = np.maximum(w, 1e-4)
        acc_sp[fr0:fr1] += sp * w[:, None]
        acc_ap[fr0:fr1] += ap * w[:, None]
        acc_v[fr0:fr1] += vo * w
        acc_w[fr0:fr1] += w
    if acc_sp is None:
        return np.zeros(int(end_t * SR))
    has = acc_w > 1e-3
    sp = np.full_like(acc_sp, 1e-12)
    ap = np.ones_like(acc_ap)
    sp[has] = np.exp(acc_sp[has] / acc_w[has, None])
    ap[has] = np.clip(acc_ap[has] / acc_w[has, None], 0, 1)
    voiced = np.zeros(nfr, bool)
    voiced[has] = acc_v[has] / acc_w[has] > 0.5
    # el volumen donde solo queda la cola de una muestra que se apaga
    gain = np.clip(acc_w / 1.0, 0, 1)
    sp = np.maximum(sp * (gain ** 2)[:, None], 1e-16)
    times = np.arange(nfr) * fp
    f0 = semis_hz(target_semis(times, phrases, bpm, key, start_beat))
    f0 = np.where(voiced, f0, 0.0)
    y = pw.synthesize(np.ascontiguousarray(f0), np.ascontiguousarray(sp), np.ascontiguousarray(ap), SR, fp * 1000)
    return y


# ------------------------------------------------------------ entrada

def resolve_long(phrases):
    """Una nota cuya letra empieza por «ー» sigue la vocal de la nota
    anterior: se escribe con ese kana para que todos los motores la canten
    ligada (en UTAU, VCV «e え»)."""
    out, prev = [], None
    for (b, p, d, m) in sorted(phrases):
        if m.startswith("ー") and prev:
            units = kana_units(prev)
            if units:
                v = units[-1][1]
                m = {"a": "あ", "i": "い", "u": "う", "e": "え", "o": "お", "n": "ん"}[v] + m[1:]
        out.append((b, p, d, m))
        prev = m
    return out


def sing(voice, phrases, bpm, key, formant=1.12):
    """Canta [phrases] con la voz pedida. El audio empieza en el pulso
    score_start_bar(phrases) * 4 y es mono a 44,1 kHz, normalizado.
    [formant] solo lo usa Sinsy (a NEUTRINO no se le puede tocar el timbre)."""
    if voice != "teto_en":
        phrases = resolve_long(phrases)
    if voice == "sinsy":
        y = sing_sinsy(phrases, bpm, key, formant=formant)
    elif voice in NEUTRINO_MODELS:
        y = sing_neutrino(voice, phrases, bpm, key)
    elif voice == "teto":
        y = sing_utau(_bank("teto"), phrases, bpm, key, _plan_jp)
    elif voice == "teto_en":
        y = sing_utau(_bank("teto_en"), phrases, bpm, key, _plan_en)
    else:
        raise ValueError(voice)
    return y / (np.max(np.abs(y)) or 1.0)
