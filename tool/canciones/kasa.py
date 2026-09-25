# Ibasho — «Ame no Hi no Kasa» (雨の日の傘): un paraguas para dos, lo-fi.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import numpy as np

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="kasa", title="Ame no Hi no Kasa", bpm=96, bars=52, key=0, tr_final=2,
    layout=LAYOUT,
    mel={
        "a1": "A4/.5 C5/.5 E5/1 D5/1 C5/1 | B4/.5 D5/.5 E5/1 D5/1 C#5/1 | "
              "D5/.5 F5/.5 A5/1 G5/.5 F5/.5 E5/1 | D5/1 C5/.5 C5/.5 Bb4/1 G4/1",
        "a2": "A4/.5 C5/.5 F5/1 E5/1 C5/1 | E5/.5 E5/.5 D5/1 F#5/1 A5/1 | "
              "G5/.5 F5/.5 D5/1 Bb4/.5 D5/.5 F5/1 | E5/.5 E5/.5 D5/.5 C5/.5 Bb4/1 G4/1",
        "cho": "D5/.5 F5/.5 A5/1 G5/.5 F5/.5 D5/1 | C5/.5 E5/.5 G5/1 F5/.5 E5/.5 C5/1 | "
               "Bb4/.5 D5/.5 G5/1 F5/.5 D5/.5 Bb4/1 | E5/1 G5/.5 E5/.5 D5/1 C5/1 | "
               "A4/.5 C5/.5 F5/1 A5/.5 G5/.5 F5/1 | G5/.5 E5/.5 D5/1 E5/.5 C#5/.5 E5/1 | "
               "F5/.5 D5/.5 A4/1 D5/.5 F5/.5 E5/1 | D5/1 C5/1 F5/2",
        "bri": "Bb4/1 D5/1 D5/1 C5/1 | C5/1 E5/1 E5/1 D5/1 | A4/1 C5/1 E5/1 D5/1 | D5/1 F5/1 D5/2",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "あ め の ひ の | ひ と つ か さ | か た が ぬ れ る | だ ま る ま ま",
            "a2": "き み の よ こ | あ し お と が | お な じ お と で | な ら ん で ゆ く",
            "a3": "ぼ く の か さ | せ ま い け ど | き み が い れ ば | い い ん だ よ",
            "cho": "あ め の お と が | や さ し い う た | き み と ぼ く の | ふ た り だ け | "
                   "や ま な い で ね | ま だ ち か く に | い た い か ら ね | あ め よ",
            "bri": "ふ れ た て | つ め た い | ぬ く も り | の こ る",
        },
        "es": {
            "a1": "でぃ あ で じゅ びあ | い うん ぱ ら ぐあす’ | せ も は み おん ぶろ | とぅ の め でぃ せす’",
            "a2": "とぅ ら ど せる’ か | ぬえす’ とろす’ ぱ そす’ ばん | こん える’ みす’ も りと’ も | ば もす’ か み なん ど",
            "a3": "えす’ み ぱ ら ぐあす’ | えす’ ぺ け にょ すぃ | すぃ えす’ たす’ め ばす’ た | や の きえ ろ ます’",
            "cho": "ら じゅ びあ かん た おい | う な かん すぃおん すわ べ | そ ろ ぱ ら ろす’ どす’ | とぅ い よ あ き | "
                   "の ぱ れす’ と だ びあ | け だ て うん ぽ こ | きえ ろ えす’ たる’ あ すぃ | の ぱ れす’",
            "bri": "とぅ ま の ふりあ | め だ か ろる’ | け だ えん み | ぽる’ すぃえん ぷれ",
        },
    },
    text={
        "ja": {
            "a1": "雨の日の | ひとつ傘 | 肩が濡れる | 黙るまま",
            "a2": "君の横 | 足音が | 同じ音で | 並んでゆく",
            "a3": "僕の傘 | 狭いけど | 君がいれば | いいんだよ",
            "cho": "雨の音が | 優しい歌 | 君と僕の | 二人だけ | 止まないでね | まだ近くに | いたいからね | 雨よ",
            "bri": "触れた手 | 冷たい | ぬくもり | 残る",
        },
        "es": {
            "a1": "Día de lluvia | y un paraguas | se moja mi hombro | tú no me dices",
            "a2": "Tu lado cerca | nuestros pasos van | con el mismo ritmo | vamos caminando",
            "a3": "Es mi paraguas | es pequeño, sí | si estás me basta | ya no quiero más",
            "cho": "La lluvia canta hoy | una canción suave | sólo para los dos | tú y yo aquí | "
                   "no pares todavía | quédate un poco | quiero estar así | no pares",
            "bri": "Tu mano fría | me da calor | queda en mí | por siempre",
        },
    },
    romaji={
        "a1": "Ame no hi no | hitotsu kasa | kata ga nureru | damaru mama",
        "a2": "Kimi no yoko | ashioto ga | onaji oto de | narande yuku",
        "a3": "Boku no kasa | semai kedo | kimi ga ireba | ii n da yo",
        "cho": "Ame no oto ga | yasashii uta | kimi to boku no | futari dake | "
               "yamanai de ne | mada chikaku ni | itai kara ne | ame yo",
        "bri": "Fureta te | tsumetai | nukumori | nokoru",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Ame no Hi no Kasa (雨の日の傘) — letra en japonés, con romaji",
          "es": "Ame no Hi no Kasa — letra en español"},
    final_note="sube dos semitonos",
    prog={
        "v1": "Fmaj7 Em7:2 A7:2 Dm7 Gm7:2 C7:2", "v2": "Fmaj7 Am7:2 D7:2 Gm7 C7",
        "cho": "Bbmaj7 Am7 Gm7 C7 Fmaj7 Em7:2 A7:2 Dm7 Gm7:2 C7:2", "bri": "Gm7 C7 Am7 Dm7",
    },
)


def build(h):
    """96 bpm, Fa mayor con septimas, lo-fi con swing: piano electrico,
    escobillas, contrabajo, chisporroteo de vinilo y gotas de lluvia."""
    s, g, v = h.s, h.g, h.vocal
    rng = np.random.RandomState(7)
    total = s.length
    s.put("fx", 0, g.pan(oc.vinyl(total, 0.5, seed=2), 0.0))
    drops = [65 + 12 * 2 + i for i in (0, 2, 4, 7, 9)]  # Fa5 pentatonica: 89..
    SW = 0.34

    def rain(start, bars, dens=1.4, amp=0.10):
        for _ in range(int(bars * dens)):
            b = start + rng.uniform(0, bars * 4)
            p = int(rng.choice(drops))
            s.put("lead", b, g.pan(oc.raindrop(s.hz(p), amp), rng.uniform(-0.8, 0.8)))

    def ep(b, notes, d, amp=0.1):
        oc.strum(s, oc.epiano, b, notes, d, amp, spread=0.012, chart=False)

    def brush_hit(b, a):
        s.put("drums", b, g.pan(oc.brush(0.16, a * 0.35, seed=int(b * 8) % 17, swell=False), 0.25))

    def rim(b, a):
        s.put("drums", b, g.pan(oc.woodblock(1700, a * 0.5), -0.2))
        s.note(b, "s", 38)

    def verse(start, prog, melpart):
        h.section(start, "verse", 2)
        h.chords(start, prog, pad=0.07, cutoff=1500)
        h.grid(start, 4, {"k": ("X.....x..X......", h.K), "s": ("....X.......X...", rim),
                          "h": ("x.o.x.o.x.o.x.o.", brush_hit)}, swing=SW)
        h.bassline(start, prog, [(0, 2, 0), (2, 1, 7), (3, 1, 5)], amp=0.5, kind="upright")
        h.comp(start, prog, [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: ep(b, ns, d, 0.1))
        h.melody(start, melpart, "epiano", 0.34)
        rain(start, 4, 1.0, 0.08)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.15)
        h.chords(start, "cho", pad=0.11, cutoff=3200, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X.....x..X..x...", h.K), "s": ("....X.......X..o", rim),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh), "b": ("o.o.o.o.o.o.o.o.", brush_hit)}, swing=SW)
        h.bassline(start, "cho", [(0, 2, 0), (2, 1, 7), (2.5, .5, 5), (3, 1, 4)], amp=0.5, tr=tr, kind="upright")
        h.comp(start, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: ep(b, ns, d, 0.12), tr=tr)
        h.arps(start, "cho", [0, 1, 2, 3, 2, 1], 0.5,
               lambda b, p, d: s.bell(b, p + 12, d, amp=0.06, chart=False), tr=tr, up=12)
        h.melody(start, "cho", "epiano", 0.36, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "bell", 0.14, tr=tr + 12)
        rain(start, 8, 1.2, 0.09)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): lluvia, vinilo y el piano
    h.section(0, "intro", 1)
    rain(0, 4, 3.0, 0.14)
    h.chords(0, "cho", pad=0.07, cutoff=1200, bars=4)
    h.comp(0, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: ep(b, ns, d, 0.1), bars=4)
    h.melody(8, "cho", "epiano", 0.28, bars=(0, 4))
    h.grid(8, 8, {"k": ("X.....x..X......", h.K), "s": ("....X.......X...", rim),
                  "h": ("x.o.x.o.x.o.x.o.", brush_hit)}, swing=SW)
    h.bassline(8, "cho", [(0, 2, 0), (2, 2, 7)], amp=0.42, bars=4, kind="upright")
    rain(4, 12, 1.2, 0.1)
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    chorus(48)
    # --- respiro (80-95): el piano solo y la lluvia
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.09, cutoff=2200, bars=4)
    h.comp(80, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: ep(b, ns, d, 0.11), bars=4)
    h.bassline(80, "cho", [(0, 2, 0), (2, 2, 7)], amp=0.42, bars=4, kind="upright")
    h.grid(80, 4, {"k": ("X.......X.......", h.K), "s": ("....x.......x...", rim),
                   "h": ("x.o.x.o.x.o.x.o.", brush_hit)}, swing=SW)
    h.melody(80, "cho", "epiano", 0.28, bars=(4, 8))
    rain(80, 4, 2.0, 0.12)
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    chorus(112)
    # --- puente (144-159): casi solo el piano, las gotas
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.1, cutoff=1300)
    h.comp(144, "bri", [(0, 2), (2, 2)], lambda b, ns, d: ep(b, ns, d, 0.11))
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.32)
    for bar in range(4):
        h.K(144 + bar * 4, 0.55)
    h.melody(144, "bri", "epiano", 0.3)
    h.sing_part(144, "bri")
    rain(144, 4, 2.2, 0.12)
    s.riser(152, 8, 0.2)
    chorus(160, tr=2, big=True)
    # --- outro (192-207): cesa la lluvia
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=1500, tr=2, bars=4, up=12)
    h.comp(192, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: ep(b, ns, d, 0.1), tr=2, bars=4)
    rain(192, 3, 1.6, 0.11)
    s.bell(204, 91, 3.0, amp=0.16)
    h.finish()
