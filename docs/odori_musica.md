# Música de Odori

(El diseño del juego está en [`ODORI.md`](ODORI.md).)

Las canciones se generan con `tool/gen_odori_music.py`, que se encarga de los instrumentos y la mezcla. Las voces las canta `tool/odori_voices.py`. La salida va a `assets/odori/<id>.ogg`, con su `<id>.json` (partitura para el charter).

## Voces («elenco»)

| id | Voz | Motor | Licencia (resumen) |
|---|---|---|---|
| `sinsy` | NIT SONG070 F001 | Sinsy (pysinsy) + WORLD, formantes ×1,12 («voz B») | CC BY 3.0 © Nagoya Institute of Technology |
| `teto` | Kasane Teto (JP) | UTAU propio: oto.ini + WORLD | Uso no comercial libre; © 小山乃舞世 / TWINDRILL |
| `teto_en` | Kasane Teto English | UTAU propio (banco VCCV X-SAMPA) | Igual que `teto` |
| `kiritan` | Tohoku Kiritan | NEUTRINO (CPU) | zunko.jp: no comercial sin pedir permiso, sin política, religión ni R-18 |
| `zundamon` | Zundamon | NEUTRINO | Igual que `kiritan` |
| `merrow` | Merrow | NEUTRINO | STUDIO NEUTRINO: uso comercial y no comercial, crédito opcional |

- **Momone Momo:** pendiente. El usuario la descarga a mano desde bowlroll (https://bowlroll.net/file/38844, VCV 2011 «Soft»). Condiciones de uso: http://www36.atwiki.jp/momonemomo/pages/39.html. Irá en `~/.cache/ibasho-voices/`. El renderizador UTAU le vale con otra `UtauBank`.
- **Ibasho no gana dinero**, y eso encaja con todas estas licencias. Si algún día lo hiciera, habría que quitar Teto, Kiritan y Zundamon o pedir permiso.
- **NEUTRINO prohíbe usar su salida como entrada de conversión de voz.** Por eso a Kiritan, Zundamon y Merrow **no** se les aplica WORLD ni formantes. Solo se retoca su `.f0` y se vuelve a generar con `--skip-timing --skip-f0`, que es el flujo oficial. La EQ y la mezcla sí están permitidas.
- **Teto puede figurar como cantante en el juego**, incluso con fan-art. Crédito de cortesía: «Kasane Teto © TWINDRILL».
- **Las canciones con voz se licencian aparte del GPL-3.** Hay que anotarlo en `CREDITS.md` y en `lib/core/credits.dart`.

## Preparar el entorno (no va en el repositorio)

```
~/.cache/ibasho-voices/            (o $ODORI_VOICES)
  neutrino/NEUTRINO/               NEUTRINO-online-v3.2.2 (Linux)
    model/KIRITAN, ZUNDAMON, MERROW...
  teto/<carpeta>/重音テト単独音, 重音テト連続音   (TETO-OUset240323.zip)
  teto_en/<carpeta>/重音テト英語音源              (TETO-English-150401.zip)
  hts_voice_nitech_jp_song070_f001-0.90/*.htsvoice
  _cache/                          análisis WORLD de los wav de UTAU
```

- **Descargas:**
  - Teto: `https://kasaneteto.jp/assets/download/utau/<zip>`.
  - NEUTRINO: `https://downloads.studio-neutrino.com/downloads/<id>`. Los ids están en `https://downloads.studio-neutrino.com/catalog/web.json`:
    - online (Linux): `ntrn_e5ab78463beeb45f31b77c24`
    - Kiritan: `ntrn_75df79627c12fefaefe3b7ff`
    - Zundamon: `ntrn_c5db86b7258171a4edd2721e`
- **Descomprimir NEUTRINO:** después hay que hacer `chmod -R u+w` y `chmod +x bin/*`.
- **La GPU no funciona:** el proveedor CUDA de onnxruntime pide `libcublasLt.so.12`, y en el sistema está la 13. Se usa la CPU, sin `-m`, y tarda unos 8 s por frase de 20 s.
- **Python:** un venv con `numpy scipy pyworld pysinsy cython "setuptools<80"`.
- **Ejecutar:** `venv/bin/python tool/gen_odori_music.py [id ...]`.

## Cómo se escribe la letra

Cada nota de la partitura es `(pulso, nota, duración, letra)`.

- **Japonés y español:** kana escrito como suena (は→わ, を→お, へ→え).
  - Se pueden poner varios kana en una nota (`らん`, `ぶえ`).
  - El apóstrofo curvo `’` detrás de un kana le quita la vocal (lo acepta NEUTRINO): `そる’` se canta «sol», `と’れん` se canta «tren», `ます’` se canta «más».
  - `ー` alarga la vocal anterior.
  - Sinsy no entiende `’` y simplemente se salta esas consonantes.
- **Inglés (solo `teto_en`):** una sílaba por nota, con los fonemas X-SAMPA del banco separados por puntos. Por ejemplo `n.aI.t` (night), `s.k.r.i.m` (scream).
  - Vocales: `@ { 3 A aI aU E eI i I O OI oU u U V`.
  - Consonantes: `b d D dZ f g h j k l m n N p r s S t T tS v w z Z`.

## Receta: cómo se hace una canción nueva

Todas las canciones se hacen así, tomando «Yakō» como modelo (`song_yako` y las tablas `YAKO_*` de `tool/gen_odori_music.py`). Para una canción `<id>` hay que:

1. **Pactar la idea con el usuario:** tema, tempo, tonalidad, estructura (intro, estrofas, pre-estribillo, estribillo, puente, final), voces e idiomas.
2. **Documentarla primero aquí:** una sección `## Canción N: «Título»` con estructura, pulsos, acordes, melodías y letras (el texto que se lee y el que se canta) en cada idioma. No se programa nada que no esté escrito aquí.
3. **Crear las tablas en `gen_odori_music.py`:**
   - **`<ID>_MEL`:** para cada parte, una lista de notas `(compás relativo, pulso dentro del compás, MIDI escrito, duración en pulsos)`.
   - **`<ID>_LYRICS[lang][parte]`:** una sílaba cantada por nota, con `|` entre compases. Se escribe en kana fonético o X-SAMPA (ver «Cómo se escribe la letra»). Un comprobador como `yako_lyric` verifica que cada compás tenga tantas sílabas como notas.
   - **`<ID>_TEXT[lang][parte]`:** el texto que se lee (kanji en japonés), con los **mismos cortes por compás**. Un guion final une la palabra con el compás siguiente.
   - **`<ID>_ROMAJI[parte]`:** la lectura Hepburn del japonés, con los mismos cortes.
   - **`<ID>_LAYOUT`:** el pulso donde empieza cada parte cantada. Tiene que coincidir con las llamadas de la función de la canción.
   - **`<ID>_CHORDS` y `<ID>_PROG`**, y si hace falta `<ID>_KEY` (Teto, por ejemplo, lleva −5).
4. **Escribir la función `song_<id>(lang=None, voice=None)`:** instrumentos, secciones y partes cantadas. Sin voz sale la instrumental, con la melodía tocada por un instrumento. Se registra en `SONGS` como `<id>` y `<id>_{lang}_{voz}`.
5. **Letra para leer y karaoke:** `--letras` escribe `assets/odori/<id>_letra_{lang}.json` para el juego y `docs/letras/<id>_{lang}.md` para leer (el japonés con romaji bajo cada verso). Hoy solo cubre «Yakō». Al añadir una canción, hay que generalizar `yako_letra` y `yako_letra_md` para que recorran todas las canciones con tablas `TEXT` y `LAYOUT`.
6. **Generar por tandas:**
   - La instrumental primero (unos 16 s).
   - Teto (1 min por variante).
   - NEUTRINO y Sinsy al final, en segundo plano con `nohup` y un log, porque tardan minutos.
   - Se escucha antes de seguir. `_cache/` guarda NEUTRINO y WORLD, así que remezclar es barato.
7. **Revisar:** duración, que el JSON tenga los eventos `v`, y oír la voz a capela si algo suena raro.

**Reglas que no se tocan:**
- A NEUTRINO no se le aplica WORLD ni conversión de voz.
- En inglés solo canta `teto_en`.
- No se publica, etiqueta ni hace push sin que el usuario lo pida.
- Los `.ogg` con voz (y las canciones de Odori) van bajo CC BY-NC 4.0, no GPL.

## Canción 1: «Yakō» (夜行列車, el último tren nocturno)

Temas elegidos por el usuario: canción 1 «Tren nocturno», canción 2 «Carrera de relevos». Cada canción va en los 3 idiomas.

- **Variantes previstas:**
  - `yako`: instrumental, con un lead de sinte haciendo la melodía.
  - `yako_ja_<voz>` con `sinsy`, `teto`, `kiritan`, `zundamon` y `merrow` (y `momo` si llega).
  - `yako_es_<voz>`: las mismas voces cantando el kana adaptado.
  - `yako_en_teto`.
- **Tono:** 160 bpm, escrita en Do mayor, con `key=-2` (suena en Si♭). El último estribillo sube +1 semitono.
- **Armonía:**
  - Estrofa: C G/B Am Em | F C/E Dm G.
  - Pre-estribillo: F G Em–Am G(sus).
  - Estribillo: F G Em Am | F G C/E–Am C (el «ōdō» del J-pop).
  - Puente a medio tiempo: Am F C G.
- **Instrumentos:** sonido de tren (charles a semicorcheas con acentos «chaca-chaca»), una campana de andén «ding-ding» como motivo, un acorde de bocina en la intro, supersierras, sidechain y un riser antes de cada estribillo.
- **Estructura (64 compases, unos 96 s):**
  - intro 8
  - estrofa A 8
  - pre 4
  - estribillo 8
  - interludio 4
  - estrofa A' 4 (melodía de A1)
  - pre 4
  - estribillo 8
  - puente 4
  - estribillo final +1 semitono 8, con segunda voz a una tercera por encima
  - outro 4

### Melodías (compás relativo, pulso, nota MIDI escrita, duración en pulsos)

**Estrofa A1 (20 notas; 6/5/6/3 por compás):**
```
b0: (0.5,67,.5)(1,72,.5)(1.5,72,.5)(2,71,.5)(2.5,72,.5)(3,74,1)
b1: (0.5,74,.5)(1,76,.5)(1.5,74,.5)(2,72,1)(3,71,1)
b2: (0.5,69,.5)(1,72,.5)(1.5,72,.5)(2,71,.5)(2.5,72,.5)(3,76,1)
b3: (0,74,1.5)(1.5,72,.5)(2,71,2)
```
**Estrofa A2 (18 notas; 6/5/6/1):**
```
b4: (0.5,69,.5)(1,72,.5)(1.5,72,.5)(2,74,.5)(2.5,76,.5)(3,77,1)
b5: (0.5,76,.5)(1,74,.5)(1.5,72,.5)(2,72,1)(3,67,1)
b6: (0.5,69,.5)(1,72,.5)(1.5,74,.5)(2,76,.5)(2.5,74,.5)(3,72,1)
b7: (0,74,2.5)
```
**Pre-estribillo (19 notas; 7/4/7/1):**
```
b0: (0,69,.5)(0.5,69,.5)(1,71,.5)(1.5,72,1)(2.5,71,.5)(3,72,.5)(3.5,74,.5)
b1: (0,76,1)(1,74,1)(2,72,1)(3,74,1)
b2: (0,69,.5)(0.5,69,.5)(1,71,.5)(1.5,72,1)(2.5,74,.5)(3,76,.5)(3.5,77,.5)
b3: (0,79,2)
```
**Estribillo (41 notas; 6/5/6/5/6/6/6/1):**
```
b0: (0,76,1)(1,77,.5)(1.5,76,.5)(2,74,.5)(2.5,72,1)(3.5,72,.5)
b1: (0,74,.5)(0.5,76,.5)(1,74,1)(2,71,.5)(2.5,67,1.5)
b2: (0,71,.5)(0.5,72,.5)(1,74,.5)(1.5,76,1)(2.5,79,.5)(3,76,1)
b3: (0,74,.5)(0.5,72,1.5)(2.5,69,.5)(3,72,.5)(3.5,74,.5)
b4: (0,76,1)(1,77,.5)(1.5,76,.5)(2,74,.5)(2.5,72,1)(3.5,72,.5)
b5: (0,74,.5)(0.5,76,.5)(1,79,1)(2,77,.5)(2.5,76,1)(3.5,74,.5)
b6: (0,76,1)(1,74,.5)(1.5,72,1)(2.5,74,.5)(3,72,.5)(3.5,71,.5)
b7: (0,72,3)
```
**Puente (12 notas; 3/3/3/3):**
```
b0: (0,69,1)(1,72,1)(2,76,2)
b1: (0,74,1)(1,72,1)(2,71,2)
b2: (0,69,1)(1,72,1)(2,77,2)
b3: (0,76,1)(1,74,1)(2,79,2)
```

### Letras (una entrada por nota; `|` separa compases)

**Japonés**
- A1: ま ど に う つ る | よ る の ま ち | ふ た り の せ て | は し る
  (窓に映る 夜の街 二人乗せて走る)
- A2: ね お ん の な み | か き わ け て | よ あ け の う み | え
  (ネオンの波かきわけて 夜明けの海へ)
- A': ち い さ な え き | す ぎ て ゆ く | こ と ば よ り も | ち か く
  (小さな駅過ぎてゆく 言葉よりも近く)
- Pre: れ ー る の う え お | は し れ ば | こ こ ろ が さ け ぶ | よ
  (レールの上を走れば 心が叫ぶよ)
- Estribillo: ひ か り を ぬ け | よ あ け ま で | き み と ふ た り | ど こ ま で も | ほ し を こ え て | か ぜ お ま と い | あ さ の う み え | ー
  (光を抜け夜明けまで 君と二人どこまでも 星を越えて風をまとい 朝の海へ)
- Puente: ひ と り | じゃ な い | そ ば に | い る よ
  (一人じゃない、そばにいるよ)

**Español** (con el kana que se canta)
- A1: Luces en el cristal / la ciudad se va / viajamos juntos / en el tren
  - る せ せん える’ く’りす’ たる’ | ら すぃう だ せ ば | び あ は もす’ ふん とす’ | え ねる’ と’れん
- A2: Cruzando un mar de / luz y de neón / hasta que salga el / sol
  - く’る さん ど うん まる’ で | るす’ い で ね おん | あす’ た け さる’ が える’ | そる’
- A': Pasan estaciones / sin decir adiós / tu mirada dice / más que yo
  - ぱ さ ねす’ た すぃお ねす’ | すぃん で すぃ ら でぃおす’ | とぅ み ら だ でぃ せ | ます’ け よ
- Pre: El rumor de las vías / me canta ya / mi corazón va gritan- / do
  - える’ る もる’ で らす’ び あす’ | め かん た や | み こ ら そん ば ぐ’り たん | ど
- Estribillo: Vuela por la noche / sin mirar atrás / tú y yo sin miedo / hasta el fin del mar / más allá del cielo / somos como el viento / hasta ver salir el / sol
  - ぶえ ら ぽる’ ら の ちぇ | すぃん み ら ら と’らす’ | とぅ い よ すぃん みえ ど | あす’ たえる’ ふぃん でる’ まる’ | ま さ や でる’ すぃえ ろ | そ もす’ こ もえる’ びえん と | あす’ た べる’ さ り れる’ | そる’
- Puente: Ya no estás sola, a tu lado estoy
  - や の えす’ | たす’ そ ら | あ とぅ ら | ど えす’ とい

**Inglés** (X-SAMPA)
- A1: Window shows the city / lights asleep below / you and I aboard the / midnight train
  - w.I.n d.oU S.oU.z D.@ s.I t.i | l.aI.t.s @ s.l.i.p b.I l.oU | j.u {.n.d aI @ b.O.r.d D.@ | m.I.d n.aI.t t.r.eI.n
- A2: Riding waves of neon / through the silent sea / all the way until the / dawn
  - r.aI d.I.N w.eI.v.z @.v n.i A.n | T.r.u D.@ s.aI l.@.n.t s.i | O.l D.@ w.eI @.n t.I.l D.@ | d.O.n
- A': Stations passing by us / not a word to say / but your eyes are telling / more than me
  - s.t.eI S.@.n.z p.{.s I.N b.aI V.s | n.A.t @ w.3.d t.@ s.eI | b.V.t j.O.r aI.z A.r t.E l.I.N | m.O.r D.{.n m.i
- Pre: Hear the rhythm of the rails / singing to me / and my heart is screaming out / loud
  - h.I.r D.@ r.I D.@.m @.v D.@ r.eI.l.z | s.I.N I.N t.@ m.i | {.n.d m.aI h.A.r.t I.z s.k.r.i.m I.N aU.t | l.aU.d
- Estribillo: Flying through the midnight / never looking back / you and I together / to the end of time / high above the heavens / we become the wind now / till we see the morning / light
  - f.l.aI I.N T.r.u D.@ m.I.d n.aI.t | n.E v.3 l.U.k I.N b.{.k | j.u {.n.d aI t.@ g.E D.3 | t.@ D.i E.n.d @.v t.aI.m | h.aI @ b.V.v D.@ h.E v.@.n.z | w.i b.I k.V.m D.@ w.I.n.d n.aU | t.I.l w.i s.i D.@ m.O.r n.I.N | l.aI.t
- Puente: You're not a / lone tonight / I will stay / by your side
  - j.O.r n.A.t @ | l.oU.n t.@ n.aI.t | aI w.I.l s.t.eI | b.aI j.O.r s.aI.d

Las letras de verdad viven en `YAKO_LYRICS` (`tool/gen_odori_music.py`). `yako_lyric()` comprueba que haya una sílaba por nota en cada compás.

- **Evitar `っ` como nota propia:** Teto no tiene muestra para ella y en una corchea suena a hueco. Las letras se reescribieron para no usarla.
- **Una nota `ー` sola:** `odori_voices.resolve_long` la convierte en el kana de la vocal anterior, y así queda ligada en todos los motores.

### Lecciones de Teto (su primera versión sonaba mal)

- **Entradas VCV en notas rápidas.** Cada muestra del 連続音 entra unos 360 ms antes de su nota (preutterance), y a 160 bpm una corchea dura 187 ms. Sin ajuste se mezclaban 2 o 3 muestras a la vez y el timbre se emborronaba. `_fit_plan` hace lo mismo que UTAU: si `pre − overlap` no cabe en la mitad de la unidad anterior, encoge preutterance y overlap en proporción y empieza a leer la muestra más tarde.
- **Tesitura.** Teto está grabada en torno a Re4 (unos 300 Hz), tanto en japonés como en inglés. Estirar WORLD más de una octava la desfigura. Por eso sus variantes llevan su propio tono (`YAKO_KEY = {"teto": -5, "teto_en": -5}`), 3 semitonos más grave que las otras. La partitura escrita, y por tanto el chart, no cambia.
- **Mezcla.** Se quitaron las dos copias de la voz retrasadas 13 y 21 ms, que hacían de flanger y le cambiaban el timbre a cualquier voz. `vocal_chain` satura menos: tanh ×1,2.
- **Comprobaciones.** Un ciclo de análisis y síntesis WORLD de una muestra difiere del original unos 2 dB de media en el espectro, así que la lectura del banco está bien. Para oír la voz sin la mezcla se genera un wav a capela (por ejemplo `assets/odori/_teto_seco.wav`, que es temporal y no va en el repositorio).
- **Plan B, si la calidad no basta:** exportar la melodía y la letra a `.ustx`. El usuario lo genera en OpenUtau con el banco oficial y yo mezclo su wav.
- **Caché de NEUTRINO.** Cada voz de NEUTRINO se guarda en `_cache/neutrino_<md5(modelo+partitura)>.npy`, así que volver a mezclar no obliga a sintetizar otra vez.

## Canciones de la 0.6.3 (solo Teto, japonés y español)

Siete canciones originales, cada una en `tool/canciones/<id>.py` (un `SPEC` con las tablas y una `build(h)` con la instrumentación) sobre el motor común `tool/odori_canciones.py`. Se registran solas en `SONGS` como `<id>`, `<id>_ja_teto` y `<id>_es_teto`. Solo canta Teto; sin inglés.

- **Notación de melodía:** un compás por `|`, notas `Sol4`/`Bb4`/`F#5`. Sin duraciones, el ritmo sale de una plantilla según cuántas notas hay (6 notas = 0,5·4 + 1 + 1). Con `nota/duración` se escribe a mano y `r/.5` es un silencio.
- **Comprobación:** al arrancar se verifica que cada compás tenga tantas sílabas como notas, en ja y es, y que texto y romaji tengan los mismos cortes. Si algo falla, lista todos los desajustes de una vez.
- **Estructura común (52 compases, unos 85–135 s):** intro 4 · estrofa `a1` 4 · `a2` 4 · estribillo `cho` 8 · respiro 4 (instrumental) · estrofa 2 `a3` 4 (melodía de `a1`) · estribillo 8 · puente `bri` 4 · estribillo final 8 (transportado) · outro 4. El `LAYOUT` es el mismo en todas: `[(16,a1),(32,a2),(48,cho),(96,a3),(112,cho),(144,bri),(160,cho)]`.
- **Teto:** la clave sale sola (`teto_key`): mediana de la melodía a Fa#4 aproximadamente, sin pasar de Fa5 en el último estribillo.
- **Salida:** cada canción en su carpeta, `assets/odori/<id>/` (`.ogg`, `.json` y `<id>_letra_{ja,es}.json`) y `docs/letras/<id>/`. Yakō y Hoshikuzu se movieron igual.

| id | Título | bpm | Tonalidad | Clave Teto | Estribillo final |
|---|---|---|---|---|---|
| `tamagoyaki` | Tamagoyaki (卵焼き) | 128 | Sol mayor | −6 | +2 |
| `hanabi` | Hanabi no Ato (花火のあと) | 150 | La menor → Do mayor | −6 | +2 |
| `nekobasu` | Neko no Basu (ネコのバス) | 138 | Re dórico | −9 | +0, +2, +4 |
| `kasa` | Ame no Hi no Kasa (雨の日の傘) | 96 | Fa mayor con séptimas | −6 | +2 |
| `tsukimi` | Tsukimi Dango (月見だんご) | 112 | Re menor pentatónico | −9 | +2 |
| `kaerimichi` | Kaeri Michi (帰り道) | 156 | Mi mayor | −8 | +2 |
| `ibasho` | Ibasho (居場所) | 120 | Do mayor | −6 | +2 |

- **Tamagoyaki:** la mañana en la cocina. Ukelele, marimba, palmas, cuchillo sobre la tabla y aceite en la sartén como percusión. Acordes: `G Em C D` / `G Em Am D`; estribillo `C D Bm Em C D G G`; puente `Em Am D G`.
- **Hanabi no Ato:** cuando acaban los fuegos artificiales. Piano, guitarra limpia, cuerdas, cohetes (silbido y estallido) y grillos. Acordes: `Am F C G` / `Am F Dm E`; estribillo `F G Em Am F G C C`; puente `F Dm Am E`. En el puente el último compás queda en silencio y solo se oye un cohete lejano.
- **Neko no Basu:** el autobús de los gatos por los tejados. Contrabajo que camina, marimba, pizzicato y maullidos sintetizados. Acordes: `Dm7 G Dm7 G` / `Dm7 G Am7 G`; estribillo `G Am7 C Dm7 G Am7 C D`; puente `Bb C Dm7 Am7`. Cada estribillo gira una esquina y sube dos semitonos. El nombre es propio y la letra también, sin nada de Ghibli.
- **Ame no Hi no Kasa:** un paraguas para dos, lo-fi con swing. Piano eléctrico, escobillas, contrabajo, vinilo y gotas de lluvia en la pentatónica de Fa. Acordes: `Fmaj7 Em7 A7 Dm7 Gm7 C7`; estribillo `Bbmaj7 Am7 Gm7 C7 Fmaj7 …`; puente `Gm7 C7 Am7 Dm7`.
- **Tsukimi Dango:** la luna en la azotea. Koto, shamisen, taiko, tsuzumi y flauta, todo sintetizado. Acordes: `Dm Bb Dm C` / `Dm Bb C Dm`; estribillo `F C Dm Bb F C Bb Dm`; puente `Gm Dm Bb A`.
- **Kaeri Michi:** volver a casa en bici al atardecer. Guitarras crujientes con palm mute, galope de bombo, cigarras y timbre de bici. Acordes: `E B C#m A` / `E B A B`; estribillo `A B G#m C#m A B E E`; puente `C#m A E B`.
- **Ibasho:** el lugar donde se puede ser uno mismo, con guiños al juego (el Tama, los amigos, el pueblo). Piano, cuerdas y palmas. Acordes: `C G Am F` / `C G F G`; estribillo `F G C Am F G C C`; puente `Am F C G`. En los dos últimos estribillos Teto canta a dos voces, con una tercera por encima.
- **Letras:** las de verdad viven en los `SPEC`; para leerlas, `docs/letras/<id>/<id>_{ja,es}.md`. Se regeneran con `--letras`. Los kanji y el romaji están en las tablas `text` y `romaji`.
- **Trucos de escritura que se usaron:** una sílaba de kana por nota y las combinaciones (`しゃ`, `きょ`, `じゅ`) cuentan como una; nada de `っ`; `ー` como nota propia para alargar; en español, `’` quita la vocal (`ぐ’ら` = «gra», `える’` = «el»). Un diptongo como «fría» puede ir en una sola nota (`ふりあ`).

## Canción 2: «Relevos» (pendiente de componer)

Las 5 voces (más Momo si llega) se pasan el testigo en una carrera contra el amanecer. Cada voz canta una frase de 4 compases en la estrofa, y en el estribillo final cantan todas juntas. Irá en los 3 idiomas; en inglés solo puede cantar `teto_en`.

## Código

- **`Song.sing(phrases, voice, amp, harmony_from, scale, tonic, formant)`:**
  - Llama a `odori_voices.sing` y coloca la voz en `score_start_bar(phrases)*4`.
  - Pasa todas las voces por `vocal_chain` (paso alto, presencia y tanh).
  - La segunda voz (`third_above` en la escala dada) se genera aparte y se coloca un poco a la derecha.
- **Ids que se generan:**
  - `yako`
  - `yako_{ja,es}_{sinsy,teto,kiritan,zundamon,merrow}`
  - `yako_en_teto` (voz `teto_en`)
- **Letra en pantalla (karaoke):** `gen_odori_music.py --letras` escribe `assets/odori/yako_letra_{ja,es,en}.json` sin tocar el audio. También escribe la letra entera para leer en `docs/letras/yako_{ja,es,en}.md`.
  - Sirve para todas las voces de un idioma, porque la melodía y los tiempos no cambian.
  - Sale de `YAKO_TEXT`, el texto que se lee, con los mismos cortes por compás que `YAKO_LYRICS`, y de `YAKO_LAYOUT`, el pulso donde empieza cada parte.
  - **Formato:** `lines[]` con `start` y `end` en pulsos y `bars[]`. Cada compás lleva `text` y `notes` (pares pulso-duración), para iluminarlo nota a nota. Un guion final (`gritan-`) une la palabra con el compás siguiente.
  - Los pulsos cuentan desde el principio de la canción; en el juego se pasan a segundos con `offset` y `bpm` del JSON de la canción.
  - Hoshikuzu sigue con `"sinsy"`: `formant=1.0` para `_voz` y `1.12` para `_voz_b`.
- **Tiempos aproximados:**
  - Instrumental: unos 16 s.
  - Teto: 1 min por variante.
  - NEUTRINO: varios minutos (dos pasadas de 100 s de voz, y otras dos para la segunda voz).
