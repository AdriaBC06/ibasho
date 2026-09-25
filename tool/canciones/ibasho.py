# Ibasho — «Ibasho» (居場所): el lugar donde se puede ser uno mismo.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="ibasho", title="Ibasho", bpm=120, bars=52, key=0, tr_final=2,
    layout=LAYOUT,
    mel={
        "a1": "G4 C5 C5 E5 E5 D5 | D5 D5 B4 D5 D5 C5 | C5 C5 E5 E5 G5 E5 | F5 E5 D5 C5",
        "a2": "G4 C5 C5 E5 E5 G5 | F5 D5 D5 B4 D5 F5 | A4 C5 C5 F5 F5 E5 | D5 B4 G4 B4 D5",
        "cho": "C5 C5 F5 F5 G5 A5 G5 | B4 D5 G5 G5 F5 D5 | E5 E5 G5 G5 E5 D5 C5 | C5 D5 E5 D5 C5 | "
               "C5 C5 F5 F5 A5 G5 F5 | D5 D5 G5 G5 F5 D5 | E5 E5 G5 G5 E5 D5 C5 | E5/1 D5/1 C5/2",
        "bri": "A4/1 C5/1 E5/1 E5/1 | F5/1 F5/1 E5/1 C5/1 | E5/1 G5/1 G5/1 E5/1 | D5/1 B4/1 D5/2",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "ど こ か に あ る | や さ し い ば しょ | だ れ か が い る | か な ら ず",
            "a2": "な き た い よ る | わ ら い た い ひ | ど ん な き み も | う け と め る",
            "a3": "た ま と あ そ ぶ | み ん な の こ え | に ぎ わ う ま ち | す き だ よ",
            "cho": "こ こ が わ た し の | い ば しょ な ん だ | な ま え を よ ん で | お か え り ね | "
                   "い つ で も か え る | こ こ ろ の い え | あ り の ま ま で い | ら れ る",
            "bri": "は じ ま り | は き み と | こ の ば しょ | か ら ね",
        },
        "es": {
            "a1": "あい うん る がる’ あ い | け てぃえ ね とぅ のん ぶれ | ある’ ぎえん て えす’ ぺ ら | で せ ぐ ろ",
            "a2": "らす’ の ちぇす’ で じゃん と | ろす’ でぃ あす’ で り さ | と ど ろ け え れす’ | あ き て くい だん",
            "a3": "ふえ ご こん み た ま | かん と こん あ み ごす’ | あい ふぃえす’ た えん か さ | えす’ とい あ き",
            "cho": "あ き えす’ み る がる’ おい | み お がる’ い み ぱす’ | や ま め ぽる’ み のん ぶれ | びえん べ に ど とぅ | "
                   "ぷえ ど ぼる’ べる’ あ か さ | えす’ た えん み ぺ ちょ | い ぷえ ど せる’ こ も そい | すぃん みえ ど",
            "bri": "とぅ いす’ と りあ | えん ぴえ さ おい | こん あ み ごす’ | で ぬえ ぼ",
        },
    },
    text={
        "ja": {
            "a1": "どこかにある | 優しい場所 | 誰かがいる | 必ず",
            "a2": "泣きたい夜 | 笑いたい日 | どんな君も | 受け止める",
            "a3": "たまと遊ぶ | みんなの声 | 賑わう街 | 好きだよ",
            "cho": "ここが私の | 居場所なんだ | 名前を呼んで | おかえりね | "
                   "いつでも帰る | 心の家 | ありのままでい | られる",
            "bri": "始まり | は君と | この場所 | からね",
        },
        "es": {
            "a1": "Hay un lugar ahí | que tiene tu nombre | alguien te espera | de seguro",
            "a2": "las noches de llanto | los días de risa | todo lo que eres | aquí te cuidan",
            "a3": "Juego con mi Tama | canto con amigos | hay fiesta en casa | estoy aquí",
            "cho": "Aquí es mi lugar hoy | mi hogar y mi paz | llámame por mi nombre | bienvenido tú | "
                   "puedo volver a casa | está en mi pecho | y puedo ser como soy | sin miedo",
            "bri": "Tu historia | empieza hoy | con amigos | de nuevo",
        },
    },
    romaji={
        "a1": "Doko ka ni aru | yasashii basho | dareka ga iru | kanarazu",
        "a2": "Nakitai yoru | waraitai hi | donna kimi mo | uketomeru",
        "a3": "Tama to asobu | minna no koe | nigiwau machi | suki da yo",
        "cho": "Koko ga watashi no | ibasho nanda | namae o yonde | okaeri ne | "
               "itsu demo kaeru | kokoro no ie | ari no mama de i | rareru",
        "bri": "Hajimari | wa kimi to | kono basho | kara ne",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Ibasho (居場所) — letra en japonés, con romaji", "es": "Ibasho — letra en español"},
    final_note="sube dos semitonos",
    prog={
        "v1": "C G Am F", "v2": "C G F G",
        "cho": "F G C Am F G C C", "bri": "Am F C G",
    },
)


def build(h):
    """120 bpm, Do mayor: himno calido de piano, cuerdas y palmas. En los
    estribillos Teto canta a dos voces."""
    s, g, v = h.s, h.g, h.vocal

    def pno(b, notes, d, amp=0.12):
        oc.strum(s, oc.piano, b, notes, d, amp, spread=0.009)

    def clap(b, a):
        s.put("drums", b, g.pan(g.clap(a * 0.6, seed=int(b * 8) % 13), 0.25))
        s.note(b, "s", 38)

    def verse(start, prog, melpart):
        h.section(start, "verse", 2)
        h.chords(start, prog, pad=0.07, cutoff=1700)
        h.grid(start, 4, {"k": ("X.......x.......", h.K), "s": ("....o.......o...", clap),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh)}, amp=0.7)
        h.bassline(start, prog, [(0, 2, 0), (2, 1, 0), (3, 1, 7)], amp=0.42)
        h.arps(start, prog, [0, 1, 2, 1, 2, 1, 0, 1], 0.5, lambda b, p, d: s.arp(b, p + 12, d, amp=0.09), up=0)
        h.comp(start, prog, [(0, 4)], lambda b, ns, d: pno(b, [n - 12 for n in ns], d, 0.1))
        h.melody(start, melpart, "piano", 0.34)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.3)
        h.chords(start, "cho", pad=0.12, cutoff=4200, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X.....x.X.....x.", h.K), "s": ("....X.......X...", clap),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh), "o": (".o.o.o.o.o.o.o.o", h.Oh)})
        h.bassline(start, "cho", [(0, 1, 0), (1, .5, 0), (1.5, .5, 12), (2, 1, 7), (3, 1, 5)], amp=0.48, tr=tr)
        h.comp(start, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: pno(b, ns, d, 0.12), tr=tr)
        h.arps(start, "cho", [0, 1, 2, 1], 0.5, lambda b, p, d: s.bell(b, p + 12, d, amp=0.06, chart=False),
               tr=tr, up=12)
        h.melody(start, "cho", "piano", 0.36, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "bell", 0.14, tr=tr + 12)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): piano y palmas
    h.section(0, "intro", 1)
    h.chords(0, "cho", pad=0.07, cutoff=1300, bars=4)
    h.comp(0, "cho", [(0, 1.5), (1.5, 1.5), (3, 1)], lambda b, ns, d: pno(b, ns, d, 0.11), bars=4)
    h.melody(8, "cho", "piano", 0.28, bars=(0, 4))
    h.grid(8, 8, {"k": ("X.......x.......", h.K), "s": ("....x.......x...", clap), "h": ("x.x.x.x.x.x.x.x.", h.Hh)},
           amp=0.8)
    s.riser(8, 8, 0.15)
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    chorus(48)
    # --- respiro
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.09, cutoff=2600, bars=4)
    h.comp(80, "cho", [(0, 2), (2, 2)], lambda b, ns, d: pno(b, ns, d, 0.11), bars=4)
    h.grid(80, 4, {"k": ("X.......X.......", h.K), "s": ("....x.......x...", clap), "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    h.bassline(80, "cho", [(0, 2, 0), (2, 2, 7)], amp=0.42, bars=4)
    h.melody(80, "cho", "piano", 0.28, bars=(4, 8))
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    chorus(112)
    # --- puente (144-159)
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.11, cutoff=1500)
    h.comp(144, "bri", [(0, 2), (2, 2)], lambda b, ns, d: pno(b, ns, d, 0.12))
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.32)
    for bar in range(4):
        h.K(144 + bar * 4, 0.55)
    h.melody(144, "bri", "piano", 0.3)
    h.sing_part(144, "bri")
    s.riser(152, 8, 0.25)
    for k in range(8):
        clap(156 + k * 0.5, 0.3 + k * 0.08)
    chorus(160, tr=2, big=True)
    # --- outro
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=1800, tr=2, bars=4, up=12)
    h.comp(192, "cho", [(0, 2), (2, 2)], lambda b, ns, d: pno(b, ns, d, 0.11), tr=2, bars=4)
    h.grid(192, 3, {"k": ("X.......X.......", h.K)})
    s.bell(204, 86, 3.0, amp=0.16)
    s.crash(206, 0.2)
    # Teto a dos voces en los dos ultimos estribillos: 3.a por encima
    h.finish(harmony=[(112, 144, 0), (160, 192, 2)], tonic=60, scale=g.MAJOR)
