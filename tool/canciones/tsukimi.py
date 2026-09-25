# Ibasho — «Tsukimi Dango» (月見だんご): la luna en la azotea.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="tsukimi", title="Tsukimi Dango", bpm=112, bars=52, key=0, tr_final=2,
    layout=LAYOUT,
    mel={
        "a1": "A4 A4 D5 F5 D5 | D5 D5 F5 G5 F5 | A4 D5 D5 F5 A5 F5 | G5 F5 D5 C5",
        "a2": "A4 A4 D5 F5 A5 | G5 G5 F5 D5 F5 | G5 G5 A5 G5 F5 D5 | D5 F5 A5 F5 D5",
        "cho": "F5 F5 A5 A5 G5 F5 D5 | C5 D5 F5 G5 A5 G5 | D5 F5 A5 A5 G5 F5 D5 | D5 F5 G5 F5 D5 | "
               "F5 F5 A5 A5 G5 F5 D5 | C5 D5 F5 G5 A5 G5 | F5 G5 A5 A5 G5 F5 D5 | A4/1 F5/1 D5/2",
        "bri": "D5/1 G5/1 G5/1 F5/1 | F5/1 A5/1 A5/1 G5/1 | F5/1 D5/1 F5/1 G5/1 | E5/1 C#5/1 A4/2",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "あ き の よ に | お つ き さ ま | み あ げ て い る | だ ん ご も",
            "a2": "う さ ぎ が ね | も ち を つ く | ぺ た ん と つ く | き こ え る よ",
            "a3": "ね が い ご と | ち い さ い よ | き み と ま た ね | ま ん げ つ",
            "cho": "つ き の う え で は | う さ ぎ お ど る | ま ん ま る お つ き | だ ん ご だ よ | "
                   "ひ と く ち た べ て | ね が い ご と を | そ ら に と ど け よ | つ き よ",
            "bri": "す す き が | ゆ ら ゆ ら | む し の ね | よ な が",
        },
        "es": {
            "a1": "や えす’ お と にょ | ら る な さ れ | えん える’ て は ど よ | こん みす’ だん ごす’",
            "a2": "あい うん こ ね ほ | むえ れ える’ あ ろす’ | ぱ た ぷらん ぱ た ぷらん | せ お や あ き",
            "a3": "ぴ ど うん で せお | むい ぺ け にょ えす’ | み らる’ ら お と’ら べす’ | る な じぇ な",
            "cho": "あ り ば えん ら る な | ばい ら うん こ ね ほ | れ どん だ こ も だん ご | ぶらん か い どぅる’ せ | "
                   "ぷるえ ば うん ぼ か でぃ と | い ぴ で うん で せお | ある’ すぃえ ろ で ら の ちぇ | お と にょ",
            "bri": "ぐ’り じょす’ かん たん | う な ぶり さ | い ら る な | ら の ちぇ",
        },
    },
    text={
        "ja": {
            "a1": "秋の夜に | お月さま | 見上げている | 団子も",
            "a2": "うさぎがね | 餅をつく | ぺたんとつく | 聞こえるよ",
            "a3": "願い事 | 小さいよ | 君とまたね | 満月",
            "cho": "月の上では | うさぎ踊る | まんまるお月 | 団子だよ | 一口食べて | 願い事を | 空に届けよ | 月夜",
            "bri": "すすきが | ゆらゆら | 虫の音 | 夜長",
        },
        "es": {
            "a1": "Ya es otoño | la luna sale | en el tejado yo | con mis dangos",
            "a2": "Hay un conejo | muele el arroz | pataplan pataplan | se oye aquí",
            "a3": "Pido un deseo | muy pequeño es | mirarla otra vez | luna llena",
            "cho": "Arriba en la luna | baila un conejo | redonda como dango | blanca y dulce | "
                   "prueba un bocadito | y pide un deseo | al cielo de la noche | otoño",
            "bri": "Grillos cantan | una brisa | y la luna | la noche",
        },
    },
    romaji={
        "a1": "Aki no yo ni | otsukisama | miagete iru | dango mo",
        "a2": "Usagi ga ne | mochi o tsuku | petan to tsuku | kikoeru yo",
        "a3": "Negaigoto | chiisai yo | kimi to mata ne | mangetsu",
        "cho": "Tsuki no ue de wa | usagi odoru | manmaru otsuki | dango da yo | "
               "hitokuchi tabete | negaigoto o | sora ni todoke yo | tsukiyo",
        "bri": "Susuki ga | yurayura | mushi no ne | yonaga",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Tsukimi Dango (月見だんご) — letra en japonés, con romaji", "es": "Tsukimi Dango — letra en español"},
    final_note="sube dos semitonos",
    prog={
        "v1": "Dm Bb Dm C", "v2": "Dm Bb C Dm",
        "cho": "F C Dm Bb F C Bb Dm", "bri": "Gm Dm Bb A",
    },
)


def build(h):
    """112 bpm, Re menor pentatonico: koto, shamisen, taiko y flauta.
    El conejo de la flauta salta en cada estribillo."""
    s, g, v = h.s, h.g, h.vocal

    def taiko(b, a):
        s.put("drums", b, g.pan(oc.taiko(a * 0.85, pitch=1.0 if int(b) % 4 == 0 else 1.2), 0.0))
        s.kicks.append(b)
        s.note(b, "k", 36, 0, 1 if b % 4 == 0 else 0)

    def tsuzumi(b, a):
        s.put("drums", b, g.pan(oc.woodblock(880 + 120 * (int(b * 2) % 2), a * 0.7), 0.3))
        s.note(b, "h", 42)

    def clap(b, a):
        s.put("drums", b, g.pan(g.clap(a * 0.5, seed=int(b * 8) % 11), -0.2))
        s.note(b, "s", 38)

    def koto_arp(b, p, d):
        oc.strum(s, oc.koto, b, [p], d, 0.13, spread=0.0, chart=False, pan_=-0.3 if int(b * 2) % 2 else 0.3)

    def sham(b, notes, d, amp=0.13):
        oc.strum(s, oc.shamisen, b, notes, d, amp, spread=0.01, up=True, chart=True)

    def verse(start, prog, melpart):
        h.section(start, "verse", 2)
        h.chords(start, prog, pad=0.07, cutoff=1700)
        h.grid(start, 4, {"k": ("X.......x.......", taiko), "s": ("....o.......o...", tsuzumi),
                          "h": ("..o...o...o...o.", tsuzumi)})
        h.bassline(start, prog, [(0, 3, 0), (3, 1, 7)], amp=0.42)
        h.arps(start, prog, [0, 1, 2, 1, 2, 1, 0, 1], 0.5, koto_arp, up=12)
        h.comp(start, prog, [(2, 1)], lambda b, ns, d: sham(b, ns, d, 0.1), up=0)
        h.melody(start, melpart, "flute", 0.32)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.25)
        h.chords(start, "cho", pad=0.11, cutoff=4600, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X...x...X...x.x.", taiko), "s": ("....X.......X...", clap),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh), "t": ("..o...o...o...o.", tsuzumi)})
        h.bassline(start, "cho", [(0, 1, 0), (1.5, .5, 0), (2, 1, 7), (3.5, .5, 5)], amp=0.48, tr=tr)
        h.arps(start, "cho", [0, 1, 2, 1], 0.5, koto_arp, tr=tr, up=12)
        h.comp(start, "cho", [(0, 1), (2, 1)], lambda b, ns, d: sham(b, ns, d, 0.11), tr=tr, up=0)
        h.melody(start, "cho", "flute", 0.36, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "koto", 0.2, tr=tr + 12)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): flauta sola, koto y el primer golpe de taiko
    h.section(0, "intro", 1)
    h.chords(0, "cho", pad=0.07, cutoff=1300, bars=4)
    h.arps(0, "cho", [0, 1, 2, 1], 1.0, koto_arp, up=12, bars=4)
    h.melody(8, "cho", "flute", 0.3, bars=(0, 4))
    h.arps(8, "cho", [0, 1, 2, 1, 2, 1], 0.5, koto_arp, up=12, bars=4)
    taiko(12, 0.9)
    h.grid(12, 4, {"k": ("X.......x.......", taiko), "t": ("..o...o...o...o.", tsuzumi)})
    s.riser(8, 8, 0.15)
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    chorus(48)
    # --- respiro
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.09, cutoff=2600, bars=4)
    h.arps(80, "cho", [0, 1, 2, 1, 2, 1], 0.5, koto_arp, up=12, bars=4)
    h.grid(80, 4, {"k": ("X.......X.......", taiko), "s": ("....x.......x...", clap),
                   "t": ("..o...o...o...o.", tsuzumi)})
    h.bassline(80, "cho", [(0, 2, 0), (2, 2, 7)], amp=0.42, bars=4)
    h.melody(80, "cho", "koto", 0.3, bars=(4, 8))
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    chorus(112)
    # --- puente (144-159): koto, campanas y voz
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.1, cutoff=1500)
    h.arps(144, "bri", [0, 1, 2, 1], 1.0, koto_arp, up=12)
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.32)
    for bar in range(4):
        taiko(144 + bar * 4, 0.55)
    h.melody(144, "bri", "koto", 0.3)
    h.sing_part(144, "bri")
    s.riser(152, 8, 0.25)
    for k in range(8):
        clap(156 + k * 0.5, 0.35 + k * 0.08)
    chorus(160, tr=2, big=True)
    # --- outro (192-207)
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=1700, tr=2, bars=4, up=12)
    h.arps(192, "cho", [0, 1, 2, 1], 1.0, koto_arp, tr=2, up=12, bars=4)
    taiko(192, 0.8)
    taiko(200, 0.7)
    s.bell(204, 86, 3.0, amp=0.16)
    s.crash(206, 0.2)
    h.finish()
