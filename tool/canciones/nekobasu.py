# Ibasho — «Neko no Basu» (ネコのバス): el autobus de los gatos, de noche por los tejados.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="nekobasu", title="Neko no Basu", bpm=138, bars=52, key=0, tr_final=4,
    layout=LAYOUT,
    mel={
        "a1": "D5 D5 F5 A5 G5 F5 | E5 E5 G5 A5 G5 E5 | D5 D5 F5 A5 A5 G5 F5 E5 | E5 F5 G5 A5",
        "a2": "F5 A5 A5 G5 F5 E5 | G5 G5 E5 G5 F5 E5 | D5 F5 A5 F5 D5 E5 F5 | E5 D5 C5 D5 A4",
        "cho": "D5 D5 G5 G5 A5 G5 F5 D5 | C5 E5 A5 A5 G5 E5 | E5 G5 G5 A5 G5 E5 C5 | D5 F5 A5 G5 F5 | "
               "D5 D5 G5 G5 A5 G5 F5 D5 | C5 E5 A5 A5 G5 E5 D5 | E5 G5 A5 A5 G5 E5 D5 | F#5/1 A5/1 D5/2",
        "bri": "F5/1 F5/.5 F5/.5 D5/1 F5/1 | G5/1 G5/1 E5/1 G5/1 | A5/1 A5/1 F5/1 D5/1 | E5/1 C5/1 r/2",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "よ な か の ば す | や ね を は し る | ま い ご を ひ ろ う よ | にゃ ー にゃ ー",
            "a2": "ま ど の そ と は | つ き と ほ し が | な が れ て ゆ く よ | ひ げ ゆ れ る",
            "a3": "さ び し い よ る | て を あ げ る と | し ず か に と ま る よ | の ろ う よ",
            "cho": "ね こ の ば す が き た | にゃ ー にゃ ー にゃ ー | ま よ い ご ど う ぞ | つ ぎ は ゆ め | "
                   "ほ し を こ え て ゆ く | ふ わ り と ゆ れ る | よ ぞ ら の た び だ | にゃ ー ん",
            "bri": "ね む く て も | あ さ ま で | は し る よ | にゃ ー",
        },
        "es": {
            "a1": "える’ ぶす’ で ら の ちぇ | こ れ ぽる’ て は どす’ | れ こ へ あ ろす’ ぺる’ でぃ どす’ | み あう み あう",
            "a2": "と’らす’ ら べん た な あい | る なす’ い えす’ と’れ やす’ | け せ ばん です’ り さん ど | ろす’ び ご てす’ ばん",
            "a3": "すぃ て すぃえん てす’ そ ろ | れ ばん た とぅ ま の | い べる’ あす’ け える’ ぶす’ ぱ ら | す び て や",
            "cho": "み ら け びえ ね える’ が と | み あう み あう み あう | ぱ ら える’ け せ ぺる’ でぃお | るえ ご うん すえ にょ | "
                   "ぶえ ら そ ぶれ らす’ えす’ と’れ やす’ | のす’ め せ える’ すぃえ ろ おい | えす’ うん びあ へ で の ちぇ | み あ う",
            "bri": "の あい け どる’ みる’ | あす’ た える’ そる’ | こ れ える’ ぶす’ | み あう",
        },
    },
    text={
        "ja": {
            "a1": "夜中のバス | 屋根を走る | 迷子を拾うよ | にゃーにゃー",
            "a2": "窓の外は | 月と星が | 流れてゆくよ | ひげ揺れる",
            "a3": "寂しい夜 | 手を上げると | 静かに止まるよ | 乗ろうよ",
            "cho": "猫のバスが来た | にゃーにゃーにゃー | 迷い子どうぞ | 次は夢 | "
                   "星を越えてゆく | ふわりと揺れる | 夜空の旅だ | にゃーん",
            "bri": "眠くても | 朝まで | 走るよ | にゃー",
        },
        "es": {
            "a1": "El bus de la noche | corre por tejados | recoge a los perdidos | miau miau",
            "a2": "Tras la ventana hay | lunas y estrellas | que se van deslizando | los bigotes van",
            "a3": "Si te sientes solo | levanta tu mano | y verás que el bus para | súbete ya",
            "cho": "Mira que viene el gato | miau miau miau | para el que se perdió | luego un sueño | "
                   "vuela sobre las estrellas | nos mece el cielo hoy | es un viaje de noche | miau",
            "bri": "No hay que dormir | hasta el sol | corre el bus | miau",
        },
    },
    romaji={
        "a1": "Yonaka no basu | yane o hashiru | maigo o hirou yo | nyā nyā",
        "a2": "Mado no soto wa | tsuki to hoshi ga | nagarete yuku yo | hige yureru",
        "a3": "Sabishii yoru | te o ageru to | shizuka ni tomaru yo | norou yo",
        "cho": "Neko no basu ga kita | nyā nyā nyā | mayoigo dōzo | tsugi wa yume | "
               "hoshi o koete yuku | fuwari to yureru | yozora no tabi da | nyān",
        "bri": "Nemukute mo | asa made | hashiru yo | nyā",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Neko no Basu (ネコのバス) — letra en japonés, con romaji", "es": "Neko no Basu — letra en español"},
    final_note="cada estribillo sube: +0, +2 y +4 semitonos",
    prog={
        "v1": "Dm7 G Dm7 G", "v2": "Dm7 G Am7 G",
        "cho": "G Am7 C Dm7 G Am7 C D", "bri": "Bb C Dm7 Am7",
    },
)


def build(h):
    """138 bpm, Re dorico: contrabajo que camina, marimba, pizzicato y
    maullidos. Cada estribillo gira una esquina: sube dos semitonos."""
    s, g, v = h.s, h.g, h.vocal

    def pz(b, notes, d, amp=0.13):
        oc.strum(s, oc.guitar_clean, b, notes, d * 0.5, amp, spread=0.004)

    def mew(b, p, amp=0.16, pan_=0.0):
        s.put("fx", b, g.pan(oc.meow(s.hz(p), 0.42, amp, seed=int(b) % 7), pan_))

    def clave(b, a):
        s.put("drums", b, g.pan(oc.woodblock(1100 + 250 * (int(b * 2) % 3), a * 0.6), -0.2))
        s.note(b, "h", 42)

    def verse(start, prog, melpart):
        h.section(start, "verse", 2)
        h.chords(start, prog, pad=0.07, cutoff=1900)
        h.grid(start, 4, {"k": ("X.....x...x.....", h.K), "s": ("....x.......x..o", h.S),
                          "h": ("x.oxx.oxx.oxx.ox", clave)})
        h.bassline(start, prog, [(0, 1, 0), (1, .5, 0), (1.5, .5, 7), (2, 1, 10), (3, .5, 9), (3.5, .5, 7)],
                   amp=0.5, kind="upright")
        h.comp(start, prog, [(0.5, .5), (2, .5), (3.5, .5)], lambda b, ns, d: pz(b, [n + 12 for n in ns], d))
        h.melody(start, melpart, "marimba", 0.34)
        mew(start + 15.0, 74, 0.1, 0.4)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.3)
        h.chords(start, "cho", pad=0.1, cutoff=4200, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X.....x.X...x...", h.K), "s": ("....X.......X..o", h.S),
                          "h": ("x.xox.xox.xox.xo", h.Hh), "o": ("..............o.", h.Oh)})
        h.bassline(start, "cho", [(0, 1, 0), (1, .5, 12), (1.5, .5, 0), (2, 1, 7), (3, .5, 5), (3.5, .5, 7)],
                   amp=0.5, tr=tr, kind="upright")
        h.comp(start, "cho", [(0.5, .5), (1.5, .5), (2.5, .5), (3.5, .5)],
               lambda b, ns, d: pz(b, [n + 12 for n in ns], d, 0.14), tr=tr)
        for k in range(8):
            mew(start + k * 4 + 3.0, 74 + tr + (0, 3, 5, 3)[k % 4], 0.1, -0.4 if k % 2 else 0.4)
        if big:
            h.arps(start, "cho", [0, 1, 2, 1], 0.5, lambda b, p, d: s.bell(b, p + 12, d, amp=0.08, chart=False),
                   tr=tr, up=12)
        h.melody(start, "cho", "marimba", 0.38, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "bell", 0.14, tr=tr + 12)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): ronroneo, contrabajo y el motor del bus
    h.section(0, "intro", 1)
    h.chords(0, "v1", pad=0.07, cutoff=1300, bars=4)
    h.bassline(0, "v1", [(0, 1, 0), (1, .5, 0), (1.5, .5, 7), (2, 1, 10), (3, 1, 9)], amp=0.45, kind="upright")
    h.grid(4, 4, {"k": ("X...X...X...X...", h.K), "h": ("x.oxx.oxx.oxx.ox", clave)})
    mew(6, 74, 0.2, -0.3)
    mew(12, 77, 0.2, 0.3)
    h.chords(8, "cho", pad=0.09, cutoff=2600, bars=4)
    h.melody(8, "cho", "marimba", 0.3, bars=(0, 4))
    h.grid(8, 8, {"k": ("X.....x...x.....", h.K), "s": ("....x.......x...", h.S), "h": ("x.oxx.oxx.oxx.ox", clave)})
    s.riser(8, 8, 0.15)
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    chorus(48)
    # --- respiro (80-95): marimba y maullidos
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.08, cutoff=2600, bars=4)
    h.grid(80, 4, {"k": ("X.......X.......", h.K), "s": ("....x.......x...", h.S), "h": ("x.oxx.oxx.oxx.ox", clave)})
    h.bassline(80, "cho", [(0, 1, 0), (1, .5, 0), (1.5, .5, 7), (2, 2, 5)], amp=0.45, bars=4, kind="upright")
    h.melody(80, "cho", "marimba", 0.3, bars=(4, 8))
    for k in range(4):
        mew(88 + k * 4 + 2, 77 - k, 0.14, (-1) ** k * 0.4)
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    chorus(112, tr=2)
    # --- puente (144-159): el bus se para; pad y campanas
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.12, cutoff=1700)
    h.arps(144, "bri", [0, 1, 2, 1], 1.0, lambda b, p, d: s.arp(b, p + 12, d, amp=0.1), up=12)
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.35)
    for bar in range(4):
        h.K(144 + bar * 4, 0.6)
        h.S(144 + bar * 4 + 2, 0.3)
    h.melody(144, "bri", "bell", 0.26)
    h.sing_part(144, "bri")
    mew(158, 79, 0.16)
    s.riser(152, 8, 0.25)
    for k in range(8):
        h.S(156 + k * 0.5, 0.25 + k * 0.06)
    # --- estribillo final +4 (160-191)
    chorus(160, tr=4, big=True)
    # --- outro (192-207)
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=1900, tr=4, bars=4, up=12)
    h.bassline(192, "cho", [(0, 1, 0), (2, 1, 7)], amp=0.42, tr=4, bars=4, kind="upright")
    h.grid(192, 3, {"k": ("X.......X.......", h.K), "h": ("x.oxx.oxx.oxx.ox", clave)})
    mew(200, 81, 0.2)
    mew(204, 84, 0.16)
    s.bell(206, 90, 2.0, amp=0.15)
    s.crash(207, 0.2)
    s.kick(207)
    h.finish()
