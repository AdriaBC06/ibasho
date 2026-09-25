# Ibasho — «Kaeri Michi» (帰り道): de vuelta a casa en bici, al atardecer.
# Copyright (C) 2026 Adrià Bonnin Catalán. GPL-3.0-or-later.

import odori_canciones as oc

LAYOUT = [(16, "a1"), (32, "a2"), (48, "cho"), (96, "a3"), (112, "cho"), (144, "bri"), (160, "cho")]

SPEC = dict(
    id="kaerimichi", title="Kaeri Michi", bpm=156, bars=52, key=0, tr_final=2,
    layout=LAYOUT,
    mel={
        "a1": "B4 B4 E5 E5 G#5 F#5 | F#5 F#5 D#5 F#5 F#5 E5 D#5 | C#5 C#5 E5 E5 G#5 F#5 | E5/1 F#5/.5 F#5/.5 E5/1 C#5/1",
        "a2": "G#4 B4 E5 E5 F#5 G#5 | F#5 F#5 D#5 F#5 D#5 B4 D#5 | C#5 C#5 E5 E5 A5 G#5 | F#5 D#5 B4 D#5 F#5",
        "cho": "E5 E5 A5 A5 G#5 F#5 E5 | D#5 F#5 B5 B5 A5 F#5 | D#5 E5 G#5 G#5 F#5 E5 D#5 | C#5 E5 G#5 F#5 E5 | "
               "E5 E5 A5 A5 B5 A5 G#5 | F#5 F#5 B5 B5 A5 F#5 | E5 G#5 G#5 F#5 E5 D#5 E5 | E5/1 G#5/1 E5/2",
        "bri": "C#5/1 E5/1 E5/1 D#5/1 | E5/1 E5/1 C#5/1 A4/1 | G#4/1 B4/1 B4/1 E5/1 | D#5/1 F#5/1 B4/1 B4/1",
    },
    mel_alias={"a3": "a1"},
    lyrics={
        "ja": {
            "a1": "ゆ う ひ の み ち | じ て ん しゃ を こ ぐ | き み の せ な か | お い か け る",
            "a2": "か ば ん ゆ れ る | ば か な は な し で | わ ら い こ ろ げ | も う す ぐ だ",
            "a3": "あ の ざ か み ち | て ば な し で ゆ く | か ぜ に な る よ | さ け ぼ う よ",
            "cho": "あ し た も あ お う | こ こ で ま つ よ | や く そ く し よ う | ゆ び き り だ | "
                   "ど こ ま で も ゆ く | き み と ふ た り | ゆ う や け ぞ ら で | わ ら う",
            "bri": "も し も ね | は な れ て | こ の み ち | お ぼ え て",
        },
        "es": {
            "a1": "える’ そる’ せ あ ぱ が | ぺ だ れお ぽる’ ら か じぇ | すぃ ご とぅ えす’ ぱる’ だ | の きえ ろ ぱ らる’",
            "a2": "ら も ち ら ばい ら | くえん とす’ け の そん べる’ だる’ | か え もす’ で り さ | や えす’ た せる’ か",
            "a3": "ら くえす’ た け ば は | すぃん ま のす’ い あ ぼ らる’ | そ もす’ える’ びえん と おい | ぐ’り て もす’ あ すぃ",
            "cho": "ま にゃ な のす’ べ もす’ や | て えす’ ぺ ろ あ き | えす’ う な ぷろ め さ や | で め にゅ け や | "
                   "よ ぼい あす’ た える’ ふぃ なる’ | とぅ い よ すぃん みえ ど | ば ほ える’ すぃえ ろ で そる’ | あ れ いる’",
            "bri": "すぃ うん でぃ あ | のす’ せ ぱ らん | えす’ た る た | れ くえる’ だ とぅ",
        },
    },
    text={
        "ja": {
            "a1": "夕日の道 | 自転車をこぐ | 君の背中 | 追いかける",
            "a2": "かばん揺れる | 馬鹿な話で | 笑い転げ | もうすぐだ",
            "a3": "あの坂道 | 手放しでゆく | 風になるよ | 叫ぼうよ",
            "cho": "明日も会おう | ここで待つよ | 約束しよう | 指切りだ | どこまでも行く | 君と二人 | 夕焼け空で | 笑う",
            "bri": "もしもね | 離れて | この道 | 覚えて",
        },
        "es": {
            "a1": "El sol se apaga | pedaleo por la calle | sigo tu espalda | no quiero parar",
            "a2": "La mochila baila | cuentos que no son verdad | caemos de risa | ya está cerca",
            "a3": "La cuesta que baja | sin manos y a volar | somos el viento hoy | gritemos así",
            "cho": "Mañana nos vemos ya | te espero aquí | es una promesa ya | de meñique ya | "
                   "yo voy hasta el final | tú y yo sin miedo | bajo el cielo de sol | a reír",
            "bri": "Si un día | nos separan | esta ruta | recuerda tú",
        },
    },
    romaji={
        "a1": "Yūhi no michi | jitensha o kogu | kimi no senaka | oikakeru",
        "a2": "Kaban yureru | baka na hanashi de | warai koroge | mō sugu da",
        "a3": "Ano zakamichi | tebanashi de yuku | kaze ni naru yo | sakebō yo",
        "cho": "Ashita mo aō | koko de matsu yo | yakusoku shiyō | yubikiri da | "
               "doko made mo yuku | kimi to futari | yūyake zora de | warau",
        "bri": "Moshimo ne | hanarete | kono michi | oboete",
    },
    sections={"a1": "Estrofa 1", "a2": None, "a3": "Estrofa 2", "cho": "Estribillo", "bri": "Puente"},
    head={"ja": "Kaeri Michi (帰り道) — letra en japonés, con romaji", "es": "Kaeri Michi — letra en español"},
    final_note="sube dos semitonos",
    prog={
        "v1": "E B C#m A", "v2": "E B A B",
        "cho": "A B G#m C#m A B E E", "bri": "C#m A E B",
    },
)


def build(h):
    """156 bpm, Mi mayor: pop-rock de atardecer. Guitarras crujientes,
    galope de bombo, cigarras y el timbre de la bici."""
    s, g, v = h.s, h.g, h.vocal

    def cr(b, notes, d, mute=False, amp=0.17):
        fr = [s.hz(notes[0] - 12), s.hz(notes[0]), s.hz(notes[2] - 12 + 12), s.hz(notes[1])] if len(notes) > 2 \
            else [s.hz(n) for n in notes]
        wave = oc.crunch(fr, max(0.15, d * s.beat * (0.9 if mute else 1.0)), amp, mute=mute)
        s.put("music", b, g.pan(wave, -0.25 if int(b * 2) % 2 else 0.25))
        s.note(b, "c", notes[-1], d, 1)

    def bell_ring(b, amp=0.22):
        s.put("fx", b, g.pan(oc.bike_bell(amp), 0.4))
        s.put("fx", b + 0.5, g.pan(oc.bike_bell(amp * 0.9), 0.4))

    def verse(start, prog, melpart):
        h.section(start, "verse", 2)
        h.chords(start, prog, pad=0.06, cutoff=1800)
        h.grid(start, 4, {"k": ("X..x..x.X..x.x..", h.K), "s": ("....X.......X...", h.S),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
        h.bassline(start, prog, [(0, .5, 0), (.5, .5, 0), (1, .5, 12), (1.5, .5, 0), (2, .5, 0), (2.5, .5, 12),
                                 (3, .5, 0), (3.5, .5, 7)], amp=0.42)
        h.comp(start, prog, [(k * 0.5, .5) for k in range(8)], lambda b, ns, d: cr(b, ns, d, True, 0.12))
        h.melody(start, melpart, "lead", 0.3)

    def chorus(start, tr=0, big=False):
        h.section(start, "chorus", 5 if big else 4)
        s.crash(start, 0.35)
        bell_ring(start + 0.25)
        h.chords(start, "cho", pad=0.09, cutoff=5200, tr=tr, up=12)
        h.grid(start, 8, {"k": ("X.....x.X..x..x.", h.K), "s": ("....X.......X...", h.S),
                          "h": ("x.x.x.x.x.x.x.x.", h.Hh), "o": (".o.o.o.o.o.o.o.o", h.Oh)})
        h.bassline(start, "cho", [(0, 1, 0), (1, .5, 0), (1.5, .5, 12), (2, 1, 0), (3, .5, 7), (3.5, .5, 5)],
                   amp=0.5, tr=tr)
        h.comp(start, "cho", [(0, 1.5), (1.5, 1), (2.5, 1.5)], lambda b, ns, d: cr(b, ns, d, False, 0.15), tr=tr)
        h.melody(start, "cho", "lead", 0.36, tr=tr, octave=big)
        if not v:
            h.melody(start, "cho", "bell", 0.12, tr=tr + 12)
        h.sing_part(start, "cho", tr)

    # --- intro (0-15): cigarras y el timbre; entra la banda
    h.section(0, "intro", 1)
    s.put("fx", 0, g.pan(oc.cricket(16 * s.beat, 0.7, seed=5), 0.0))
    bell_ring(0.5)
    h.chords(0, "cho", pad=0.07, cutoff=1300, bars=4)
    h.melody(8, "cho", "lead", 0.26, bars=(0, 4))
    h.chords(8, "cho", pad=0.09, cutoff=2600, bars=4)
    h.grid(8, 8, {"k": ("X...X...X...X...", h.K), "s": ("....x.......x...", h.S), "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    for k in (14.75, 15, 15.25, 15.5, 15.75):
        h.S(k, 0.5)
    s.riser(8, 8, 0.2)
    verse(16, "v1", "a1")
    h.sing_part(16, "a1")
    verse(32, "v2", "a2")
    h.sing_part(32, "a2")
    chorus(48)
    # --- respiro
    h.section(80, "break", 3)
    h.chords(80, "cho", pad=0.09, cutoff=2600, bars=4)
    h.grid(80, 4, {"k": ("X..x..x.X..x.x..", h.K), "s": ("....x.......x...", h.S), "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    h.bassline(80, "cho", [(0, 1, 0), (1, 1, 0), (2, 1, 7), (3, 1, 5)], amp=0.45, bars=4)
    h.melody(80, "cho", "lead", 0.28, bars=(4, 8))
    bell_ring(92)
    verse(96, "v1", "a3")
    h.sing_part(96, "a3")
    chorus(112)
    # --- puente (144-159): baja el ritmo; solo guitarra y voz
    h.section(144, "bridge", 2)
    h.chords(144, "bri", pad=0.11, cutoff=1700)
    h.comp(144, "bri", [(0, 2), (2, 2)], lambda b, ns, d: cr(b, ns, d, False, 0.11))
    h.bassline(144, "bri", [(0, 4, 0)], amp=0.35)
    for bar in range(4):
        h.K(144 + bar * 4, 0.6)
        h.S(144 + bar * 4 + 2, 0.35)
    h.melody(144, "bri", "lead", 0.26)
    h.sing_part(144, "bri")
    s.riser(152, 8, 0.25)
    for k in range(8):
        h.S(156 + k * 0.5, 0.3 + k * 0.07)
    chorus(160, tr=2, big=True)
    # --- outro (192-207)
    h.section(192, "outro", 2)
    h.chords(192, "cho", pad=0.08, cutoff=1900, tr=2, bars=4, up=12)
    h.comp(192, "cho", [(0, 2)], lambda b, ns, d: cr(b, ns, d, False, 0.13), tr=2, bars=4)
    h.grid(192, 3, {"k": ("X.......X.......", h.K), "h": ("x.x.x.x.x.x.x.x.", h.Hh)})
    s.put("fx", 200, g.pan(oc.cricket(8 * s.beat, 0.5, seed=6), 0.0))
    bell_ring(204)
    s.crash(206, 0.2)
    h.finish()
