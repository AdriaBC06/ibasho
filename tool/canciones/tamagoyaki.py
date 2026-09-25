# Ibasho — «Tamagoyaki» (卵焼き): la mañana en la cocina. Ver docs/odori_musica.md.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="tamagoyaki", title="Tamagoyaki", bpm=128, bars=52, key=0, tr_final=2,
    layout=LAYOUT,
    mel={
        "a1": "D5 D5 B4 D5 E5 D5 | B4 B4 D5 D5 E5 D5 B4 | C5 C5 B4 C5 E5 D5 | A4 B4 C5 D5",
        "a2": "B4 D5 D5 E5 G5 E5 | D5 B4 D5 E5 D5 B4 G4 | A4 C5 E5 E5 D5 C5 | B4 A4 F#4 A4 D5",
        "cho": "E5 E5 G5 G5 E5 D5 C5 | D5 F#5 G5 G5 F#5 E5 D5 | D5 D5 F#5 F#5 E5 D5 B4 | B4 E5 G5 F#5 E5 | "
               "E5 E5 G5 G5 E5 D5 C5 | D5 E5 F#5 G5 F#5 D5 | B4 D5 G5 G5 F#5 E5 D5 | B4 D5 G5",
        "bri": "E5/1 E5/1 D5/1 B4/1 | C5/1 C5/1 B4/1 A4/1 | A4/1.5 B4/.5 C5/1 D5/1 | B4/1 D5/1 G5/2",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "あ さ の ひ か り | し ず か に お き た | き み は ゆ め を | み て る ね",
            "a2": "ふ ら い ぱ ん を | あ た た め て お く | た ま ご ひ と つ | こ ん と わ る",
            "a3": "あ ま い の す き | き み の え が お が | み た い か ら ね | も う す ぐ",
            "cho": "あ さ ご は ん だ よ | ふ わ ふ わ や け た | あ ま い た ま ご の | お は よ う ね | "
                   "ゆ げ が ひ ろ が る | きょ う の た め に | こ こ ろ を こ め て | や い た",
            "bri": "い つ も ね | あ り が と | い え な い | か ら ね",
        },
        "es": {
            "a1": "えん と’ら ら るす’ でる’ そる’ | め れ ばん と すぃん るい ど | とぅ すぃ げす’ どぅる’ みえん ど | すえ にゃす’ えん ぱす’",
            "a2": "か りえん と ら さる’ てん | ば と どす’ うえ ぼす’ い さる’ | か ぱ ぽる’ か ぱ ば | せ えん ろ や や",
            "a3": "ろ ぷれ ふぃえ ろ どぅる’ せ | とぅ そん り さ えす’ み そる’ | ぽ れ そ ろ あ ご | うん ぽ こ ます’",
            "cho": "える’ で さ ゆ の りす’ と | すわ べ こ も ら ぬ べ | ど ら ど こ も える’ そる’ | ぶえ のす’ でぃ あす’ とぅ | "
                   "える’ ば ぽる’ じぇ な と ど | えす’ と えす’ ぱ ら てぃ | こん と ど み こ ら そん | や えす’ た",
            "bri": "ぐ’ら すぃあす’ ぽる’ てぃ | の せ こ も | で すぃる’ て ろ | ぽ れ そ",
        },
    },
    text={
        "ja": {
            "a1": "朝の光 | 静かに起きた | 君は夢を | 見てるね",
            "a2": "フライパンを | 温めておく | 卵ひとつ | こんと割る",
            "a3": "甘いの好き | 君の笑顔が | 見たいからね | もうすぐ",
            "cho": "朝ごはんだよ | ふわふわ焼けた | 甘い卵の | おはようね | 湯気が広がる | 今日のために | 心を込めて | 焼いた",
            "bri": "いつもね | ありがと | 言えない | からね",
        },
        "es": {
            "a1": "Entra la luz del sol | me levanto sin ruido | tú sigues durmiendo | sueñas en paz",
            "a2": "caliento la sartén | bato dos huevos y sal | capa por capa, va | se enrolla ya",
            "a3": "Lo prefiero dulce | tu sonrisa es mi sol | por eso lo hago | un poco más",
            "cho": "El desayuno listo | suave como la nube | dorado como el sol | buenos días, tú | "
                   "el vapor llena todo | esto es para ti | con todo mi corazón | ya está",
            "bri": "Gracias por ti | no sé cómo | decírtelo | por eso",
        },
    },
    romaji={
        "a1": "Asa no hikari | shizuka ni okita | kimi wa yume o | miteru ne",
        "a2": "Furaipan o | atatamete oku | tamago hitotsu | kon to waru",
        "a3": "Amai no suki | kimi no egao ga | mitai kara ne | mō sugu",
        "cho": "Asagohan da yo | fuwafuwa yaketa | amai tamago no | ohayō ne | "
               "yuge ga hirogaru | kyō no tame ni | kokoro o komete | yaita",
        "bri": "Itsumo ne | arigato | ienai | kara ne",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Tamagoyaki (卵焼き) — letra en japonés, con romaji", "es": "Tamagoyaki — letra en español"},
    final_note="sube dos semitonos",
    prog={
        "v1": "G Em C D", "v2": "G Em Am D",
        "cho": "C D Bm Em C D G G", "bri": "Em Am D G",
    },
)


def build(h):
    """128 bpm, Sol mayor: ukelele, marimba, palmas, aceite en la sarten."""
    s, g, v = h.s, h.g, h.vocal

    def uk(b, notes, d, amp=0.13, up=False, chart=False):
        oc.strum(s, oc.ukulele, b, notes, d, amp, up=up, chart=chart)

    def sizz(b, a):
        h.drum(oc.sizzle(0.35, 0.5 * a, seed=int(b * 4) % 9), b, 1, 0.25, role="h", pitch=44)

    def chopk(b, a):
        h.drum(oc.chop(0.7 * a, seed=int(b * 4) % 7), b, 1, -0.2, role="h", pitch=42)

    def clapper(b, a):
        s.put("drums", b, g.pan(g.clap(a * 0.7, seed=int(b * 8) % 11) * 0.8, 0.3))
        s.note(b, "s", 38)

    def shk(b, a):
        s.put("drums", b, g.pan(oc.shaker(a * 0.5, seed=int(b * 8) % 13), 0.35))

    def verse(start, prog_name, melpart):
        h.section(start, "verse", 2)
        s.crash(start, 0.15)
        h.chords(start, prog_name, pad=0.08, cutoff=2200)
        h.grid(start, 4, {"k": ("X.....o.X.x.....", h.K), "s": ("....x.......x...", clapper),
                          "h": ("o.o.o.o.o.o.o.o.", shk)})
        h.bassline(start, prog_name, [(0, 1, 0), (1.5, .5, 0), (2, 1, 7), (3, .5, 5), (3.5, .5, 4)],
                   amp=0.5, kind="upright")
        h.comp(start, prog_name, [(0.5, .5), (1.5, .5), (2.5, .5), (3.5, .5)],
               lambda b, ns, d: uk(b, ns, d, 0.11, up=True), up=0, bars=4)
        h.melody(start, melpart, "marimba", 0.34)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.3)
        h.chords(start, "cho", pad=0.1, cutoff=4800, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X.....x.X.x...x.", h.K), "s": ("....X.......X...", clapper),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh), "o": ("..o...o...o...o.", h.Oh),
                          "z": ("....x.......x...", sizz)})
        h.bassline(start, "cho", [(0, 1, 0), (1, .5, 12), (1.5, .5, 0), (2, 1, 7), (3, .5, 5), (3.5, .5, 7)],
                   amp=0.5, tr=tr)
        h.comp(start, "cho", [(0, .5), (.5, .5), (1.5, .5), (2, .5), (3, .5), (3.5, .5)],
               lambda b, ns, d: uk(b, ns, d, 0.13, up=int(b * 2) % 2 == 1, chart=int(b) % 2 == 1), tr=tr)
        if big:
            h.arps(start, "cho", [0, 1, 2, 1], 0.5, lambda b, p, d: s.bell(b, p + 12, d, amp=0.1, chart=False),
                   tr=tr, up=12)
        h.melody(start, "cho", "marimba", 0.38, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "bell", 0.16, tr=tr + 12)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): se pica el cebollino, se calienta la sarten, entra el ukelele
    h.section(0, "intro", 1)
    h.grid(0, 2, {"c": ("x.x.o.x.x.x.o.x.", chopk)})
    s.crash(0, 0.12)
    sizz(8, 1.6)
    h.chords(0, "cho", pad=0.07, cutoff=1500, bars=4)
    h.grid(8, 2, {"c": ("x.x.o.x.x.x.o.x.", chopk), "z": ("....x.......x...", sizz)})
    h.comp(8, "cho", [(0, 1), (1, 1), (2, 1), (3, 1)], lambda b, ns, d: uk(b, ns, d, 0.11, up=int(b) % 2 == 1,
                                                                           chart=True), bars=4)
    h.melody(8, "cho", "bell", 0.22, bars=(0, 4))
    h.grid(12, 4, {"k": ("X...X...X...X...", h.K), "s": ("....x.......x...", clapper),
                   "h": ("x.x.x.x.x.x.x.x.", h.Hh)})

    # --- estrofa 1 (16-47)
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    # --- estribillo (48-79)
    chorus(48)
    # --- respiro (80-95): el gancho en campanas y ukelele
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.09, cutoff=3000, bars=4)
    h.grid(80, 4, {"k": ("X.......X.......", h.K), "s": ("....x.......x...", clapper),
                   "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    h.bassline(80, "cho", [(0, 1, 0), (2, 1, 7)], amp=0.45, bars=4)
    h.melody(80, "cho", "marimba", 0.3, bars=(4, 8))
    h.melody(80, "cho", "bell", 0.14, tr=12, bars=(4, 8))
    # --- estrofa 2 (96-111)
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    # --- estribillo 2 (112-143)
    chorus(112)
    # --- puente (144-159): pad, campana y voz; gracias sin decirlo
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.12, cutoff=1800)
    h.arps(144, "bri", [0, 1, 2, 1], 1.0, lambda b, p, d: s.arp(b, p + 12, d, amp=0.12), up=12)
    for bar in range(4):
        h.K(144 + bar * 4, 0.7)
        h.S(144 + bar * 4 + 2, 0.4)
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.35, kind="bass")
    h.melody(144, "bri", "bell", 0.26)
    h.sing_part(144, "bri")
    s.riser(152, 8, 0.28)
    for k in range(8):
        h.S(156 + k * 0.5, 0.25 + k * 0.06)
    # --- estribillo final +2 (160-191)
    chorus(160, tr=2, big=True)
    # --- outro (192-207)
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=2200, tr=2, bars=4, up=12)
    h.comp(192, "cho", [(0, 1), (2, 1)], lambda b, ns, d: uk(b, ns, d, 0.11), tr=2, bars=4)
    h.grid(192, 3, {"k": ("X.......X.......", h.K), "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    sizz(200, 1.4)
    s.bell(206, 79 + 2, 2.0, amp=0.2)
    s.crash(207, 0.2)
    s.kick(207)
    h.finish()
