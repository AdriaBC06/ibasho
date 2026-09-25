# Ibasho — «Hanabi no Ato» (花火のあと): despues de los fuegos artificiales.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="hanabi", title="Hanabi no Ato", bpm=150, bars=52, key=0, tr_final=2,
    layout=LAYOUT,
    mel={
        "a1": "E5 E5 C5 E5 D5 C5 | C5 C5 A4 C5 B4 A4 | G4 C5 C5 E5 E5 D5 C5 | B4 D5 B4 G4",
        "a2": "A4 C5 E5 E5 D5 C5 | A4 C5 F5 F5 E5 D5 C5 | D5 F5 A4 D5 F5 E5 D5 | B4 G#4 B4 D5 E5",
        "cho": "A4 C5 F5 F5 E5 D5 C5 | B4 D5 G5 G5 F5 D5 | E5 E5 G5 G5 E5 D5 B4 | C5 D5 E5 D5 C5 | "
               "A4 C5 F5 F5 G5 F5 E5 | D5 D5 G5 G5 F5 D5 | E5 E5 G5 G5 E5 D5 C5 | E5/1 D5/1 C5/2",
        "bri": "A4/1 C5/.5 C5/.5 C5/1 D5/1 | D5/1 D5/.5 D5/.5 C5/1 A4/1 | C5/1 E5/1 E5/1 D5/1 | G#4/1 B4/1 r/2",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "は な び の あ と | け む り の こ る | ひ と は か え る よ | よ ぞ ら に",
            "a2": "ま だ み て い た | き み の よ こ が お | ひ か り は き え て | わ す れ な い",
            "a3": "ゆ か た の そ で | つ か ん だ ま ま | い え ず に い た よ | す き だ よ",
            "cho": "は な び の よ う に | き え て も ま だ | む ね に ひ か る よ | な つ の ゆ め | "
                   "い つ か ま た み る | お な じ そ ら を | き み と み あ げ て | い た い",
            "bri": "ふ り む く と | き み が い た | と な り に | い て",
        },
        "es": {
            "a1": "と’らす’ ろす’ ふえ ごす’ で おい | える’ う も せ け だ | と どす’ せ ばん あ か さ | えん ら の ちぇ",
            "a2": "そ ろ て み ら ば | とぅ か り た で ぺる’ ふぃる’ | ら るす’ せ あ ぱ が や | の ろ おる’ び ど",
            "a3": "そす’ とぅ べ とぅ まん が | すぃん さ べる’ け で すぃる’ | の ぷ で で すぃる’ て ます’ | よ て きえ ろ",
            "cho": "こ も う な ふろる’ で るす’ | あうん け せ あ ぱ げ | ぶり や えん み ぺ ちょ おい | べ ら の すぃん ふぃん | "
                   "うん でぃ あ ぼる’ べ れ もす’ | える’ みす’ も すぃえ ろ おい | こん てぃ ご きえ ろ み らる’ | お と’ら べす’",
            "bri": "ある’ み ら あ と’らす’ | えす’ た ばす’ あ い | あ み ら ど | あ もる’",
        },
    },
    text={
        "ja": {
            "a1": "花火のあと | 煙残る | 人は帰るよ | 夜空に",
            "a2": "まだ見ていた | 君の横顔 | 光は消えて | 忘れない",
            "a3": "浴衣の袖 | 掴んだまま | 言えずにいたよ | 好きだよ",
            "cho": "花火のように | 消えてもまだ | 胸に光るよ | 夏の夢 | いつかまた見る | 同じ空を | 君と見上げて | いたい",
            "bri": "振り向くと | 君がいた | 隣に | いて",
        },
        "es": {
            "a1": "Tras los fuegos de hoy | el humo se queda | todos se van a casa | en la noche",
            "a2": "Sólo te miraba | tu carita de perfil | la luz se apaga ya | no lo olvido",
            "a3": "Sostuve tu manga | sin saber qué decir | no pude decirte más | yo te quiero",
            "cho": "Como una flor de luz | aunque se apague | brilla en mi pecho hoy | verano sin fin | "
                   "un día volveremos | el mismo cielo hoy | contigo quiero mirar | otra vez",
            "bri": "Al mirar atrás | estabas ahí | a mi lado | amor",
        },
    },
    romaji={
        "a1": "Hanabi no ato | kemuri nokoru | hito wa kaeru yo | yozora ni",
        "a2": "Mada miteita | kimi no yokogao | hikari wa kiete | wasurenai",
        "a3": "Yukata no sode | tsukanda mama | iezu ni ita yo | suki da yo",
        "cho": "Hanabi no yō ni | kiete mo mada | mune ni hikaru yo | natsu no yume | "
               "itsuka mata miru | onaji sora o | kimi to miagete | itai",
        "bri": "Furimuku to | kimi ga ita | tonari ni | ite",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Hanabi no Ato (花火のあと) — letra en japonés, con romaji", "es": "Hanabi no Ato — letra en español"},
    final_note="sube dos semitonos",
    prog={
        "v1": "Am F C G", "v2": "Am F Dm E",
        "cho": "F G Em Am F G C C", "bri": "F Dm Am E",
    },
)


def build(h):
    """150 bpm, La menor que se abre a Do mayor: piano, guitarra limpia,
    cuerdas y cohetes. El puente calla del todo antes del estribillo final."""
    s, g, v = h.s, h.g, h.vocal

    def fw(b, amp=0.5, p=0.0, seed=0):
        s.put("fx", b, g.pan(oc.whistle_boom(amp, seed=seed), p))

    def gt(b, p, d):
        oc.strum(s, oc.guitar_clean, b, [p], d, 0.14, spread=0.0)

    def pno(b, notes, d, amp=0.11):
        oc.strum(s, oc.piano, b, notes, d, amp, spread=0.008)

    def rim(b, a):
        s.put("drums", b, g.pan(oc.woodblock(2000, a * 0.55), 0.2))
        s.note(b, "s", 38)

    def verse(start, prog, melpart):
        h.section(start, "verse", 2)
        h.chords(start, prog, pad=0.09, cutoff=1800)
        h.grid(start, 4, {"k": ("X.......x.x.....", h.K), "s": ("........x.......", rim),
                          "h": ("..x...x...x...x.", h.Hh)})
        h.bassline(start, prog, [(0, 2, 0), (2, 1, 0), (3, 1, 7)], amp=0.45)
        h.arps(start, prog, [0, 1, 2, 1, 2, 1], 0.5, lambda b, p, d: gt(b, p + 12, d), up=0)
        h.comp(start, prog, [(0, 4)], lambda b, ns, d: pno(b, [n - 12 for n in ns], d, 0.09))
        h.melody(start, melpart, "epiano", 0.3)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.35)
        fw(start, 0.55, -0.3, seed=tr)
        fw(start + 16, 0.45, 0.3, seed=tr + 1)
        h.chords(start, "cho", pad=0.12, cutoff=5200, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X.....x.X.....x.", h.K), "s": ("....X.......X...", h.S),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh), "o": ("..o...o...o...o.", h.Oh)})
        h.bassline(start, "cho", [(0, 1, 0), (1, .5, 0), (1.5, .5, 12), (2, 1, 7), (3, 1, 0)], amp=0.5, tr=tr)
        h.comp(start, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: pno(b, ns, d, 0.11), tr=tr)
        if big:
            h.arps(start, "cho", [0, 1, 2, 1], 0.5, lambda b, p, d: s.arp(b, p + 12, d, amp=0.08, chart=False),
                   tr=tr, up=12)
        h.melody(start, "cho", "epiano", 0.34, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "bell", 0.14, tr=tr + 12)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): grillos, un cohete lejano y el piano
    h.section(0, "intro", 1)
    s.put("fx", 0, g.pan(oc.cricket(16 * s.beat * 1.0, 0.55, seed=3), 0.0))
    fw(3, 0.3, -0.5, seed=5)
    fw(9, 0.3, 0.5, seed=6)
    h.chords(0, "cho", pad=0.07, cutoff=1300, bars=4)
    h.melody(8, "cho", "epiano", 0.26, bars=(0, 4))
    h.comp(8, "cho", [(0, 4)], lambda b, ns, d: pno(b, ns, d, 0.1), bars=4)
    h.grid(12, 4, {"k": ("X.......X.......", h.K), "h": ("..x...x...x...x.", h.Hh)})
    s.riser(8, 8, 0.15)
    # --- estrofas
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    chorus(48)
    # --- respiro: campanas y un cohete
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.09, cutoff=2600, bars=4)
    h.grid(80, 4, {"k": ("X.......X.......", h.K), "s": ("....x.......x...", rim), "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    h.bassline(80, "cho", [(0, 2, 0), (2, 2, 7)], amp=0.42, bars=4)
    h.melody(80, "cho", "epiano", 0.26, bars=(4, 8))
    h.melody(80, "cho", "bell", 0.12, tr=12, bars=(4, 8))
    fw(88, 0.4, 0.2, seed=8)
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    chorus(112)
    # --- puente: piano y voz; el ultimo compas queda en silencio
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.1, cutoff=1500, bars=3)
    h.comp(144, "bri", [(0, 2), (2, 2)], lambda b, ns, d: pno(b, ns, d, 0.11), bars=3)
    h.arps(144, "bri", [0, 1, 2, 1], 1.0, lambda b, p, d: s.arp(b, p + 24, d, amp=0.08), up=12, bars=3)
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.32, bars=3)
    for bar in range(3):
        h.K(144 + bar * 4, 0.6)
    h.melody(144, "bri", "epiano", 0.3)
    h.sing_part(144, "bri")
    fw(154, 0.5, 0.0, seed=11)        # el ultimo cohete se oye en el silencio
    s.riser(156, 4, 0.2)
    h.chords(156, "bri", pad=0.0, bars=0)
    # --- estribillo final +2 (160-191)
    chorus(160, tr=2, big=True)
    fw(176, 0.55, 0.0, seed=13)
    # --- outro (192-207): humo y grillos
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=1800, tr=2, bars=4, up=12)
    h.comp(192, "cho", [(0, 4)], lambda b, ns, d: pno(b, ns, d, 0.1), tr=2, bars=4)
    s.put("fx", 192, g.pan(oc.cricket(12 * s.beat, 0.45, seed=4), 0.0))
    h.grid(192, 2, {"k": ("X.......X.......", h.K)})
    s.bell(204, 81, 3.0, amp=0.18)
    s.crash(206, 0.2)
    h.finish()
