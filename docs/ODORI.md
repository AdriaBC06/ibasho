# Odori (踊り): el juego de ritmo

Juego de ritmo de Ibasho para la 0.6.3. Este documento recoge el diseño del juego. Cómo se hacen las canciones (síntesis, voces, letras) está en [`odori_musica.md`](odori_musica.md), y las letras para leer, en [`letras/`](letras/).

## Decisiones del usuario (no volver a preguntar)

- **Dos modos:**
  - **Taki (滝):** carriles de 1 a 7 teclas, con las notas cayendo de arriba abajo. Hay que dejar preparadas las demás direcciones: de abajo arriba, de izquierda a derecha y de derecha a izquierda.
  - **Butai (舞台):** estilo Project Diva, solo con 4 teclas. Las notas vuelan hacia dianas sobre un escenario oscuro, que es el azul noche del tema y nunca negro.
- **Dificultades:** Easy, Normal, Hard, Extreme e Impossible.
- **Aspecto de las notas:** círculos, rayitas o flechas, a elegir.
- **Teclas:** configurables, y en móvil se juega con varios dedos a la vez. Por defecto:

  | Teclas | Distribución |
  |---|---|
  | 1 | Espacio |
  | 2 | F J |
  | 3 | F Espacio J |
  | 4 | D F J K |
  | 5 | D F Espacio J K |
  | 6 | S D F J K L |
  | 7 | S D F Espacio J K L |

- **Tema:** el juego tiene uno propio, que se elige entre los fondos desbloqueados, aparte del del menú (ver `docs/UI.md` y la memoria de temas).
- **El Tama acompaña** con una ayuda pequeña que depende de su personalidad. Las partidas con ayuda van a una **clasificación aparte**.
- **Economía:** el juego es gratis. Hay 6 canciones: 2 gratis y 4 de pago, a 30 monedas cada una en el Yatai.
- **Música propia:**
  - Sintetizada con `tool/gen_odori_music.py`.
  - Las voces son de Sinsy, Kasane Teto (UTAU), Kiritan, Zundamon y Merrow (NEUTRINO).
  - Las canciones con voz se licencian aparte del GPL (ver `odori_musica.md`).
- **Letra en pantalla** mientras suena la canción, como en un karaoke (ver más abajo).

## Fases

1. **Motor:** Taki con 4 teclas cayendo hacia abajo, notas redondas y teclas DFJK. Usa una canción de prueba y se abre desde el menú de depuración.
2. De 1 a 7 teclas, juego táctil, aspectos de nota y calibración.
3. Escena, selector de canciones, Tama, resultados y tema.
4. Música: las canciones ya están generándose (ver `odori_musica.md`).
5. Modo Butai.
6. Yatai, monedas, clasificaciones y reglas de Firebase.
7. Voz y karaoke en el juego.

## Tareas de la 0.6.3 (reparto pactado el 2026-09-24)

Se trabaja en tres tareas. Al acabar cada una se documenta aquí, se para y el usuario compacta el contexto.

1. **Motor Taki (hecha).** Charter, reloj, juicio, puntuación, de 1 a 7 teclas, teclado y táctil, pantalla de juego, pausa y resultados. Se abre desde Depuración → «Odori».
2. **El canal (hecha).**
   - Selector de canción con todas las canciones y sus versiones. Cada canción muestra nombre, autor («Ibasho feat. <cantante>»), bpm y dificultades con su color. Sin icono de momento.
   - Selector de teclas (1–7) y de modo (Taki / Butai).
   - Récords por canción.
   - Tema propio del juego, elegido entre los fondos desbloqueados y aparte del del menú.
   - El Tama con su ayuda pequeña, cuyas partidas van a una clasificación aparte.
   - Opciones: dirección, aspecto de nota, velocidad y desfase.
3. **Butai y letra en pantalla (hecha).**

**Decisiones del usuario en esta ronda:**
- **Canciones:** salen todas, Hoshikuzu (la de prueba) incluida, con sus versiones. No todas tienen todas las voces ni todos los idiomas: el catálogo solo enseña las que existen.
- **Autor:** «Ibasho feat. Kasane Teto»; en la instrumental, solo «Ibasho».
- **Rangos:** D, C, B, A y S por puntos (700k, 800k, 900k y 950k). **S+** si no se falla ninguna nota, con cualquier puntuación. **S++** si todas son «¡brillo!».

## Código (tarea 1)

Todo vive en `lib/games/odori/`:

| Archivo | Qué hace |
|---|---|
| `odori_song.dart` | `OdoriScore`: lee la partitura base (`ScoreEvent`, `ScoreSection`, `timeOf`, `energyAt`). Los roles `l` y `v` cuentan como melodía. |
| `odori_catalog.dart` | `loadOdoriSongs()` saca canciones y versiones del `AssetManifest` (`assets/odori/<canción>/<id>.ogg`). `OdoriVersion` lleva idioma, cantante y rutas (audio, partitura y letra); `OdoriSong`, el título en romaji y en japonés (`odoriTitles`), el orden (`odoriOrder`) y `authorOf`. Hoshikuzu: `_voz` = Sinsy y `_voz_b` = `sinsy_b`. |
| `odori_chart.dart` | `OdoriDifficulty` con nps, separación y largas; `buildChart(score, keys, difficulty)`, determinista con semilla FNV del id. Cuando la canción no da para la densidad buscada (Extreme e Impossible), lo que falta se completa con acordes en los golpes de más prioridad, hasta 3 en Extreme y 4 en Impossible, sin pasar nunca de teclas − 1. |
| `odori_engine.dart` | `OdoriEngine`: `press`, `release` y `advance`, con los juicios y el combo. Puntos: `900k·Σpeso/juicios + 100k·comboMáx/juicios`. Cada larga cuenta dos juicios, la cabeza y el final. Se puede soltar hasta 135 ms antes del final sin perderla. Devuelve un `OdoriResult` con precisión, fallos, pronto/tarde y combo máximo. |
| `odori_board.dart` | `TakiBoard` (CustomPainter). `TakiFlow` pinta en las 4 direcciones; `NoteLook` elige círculo, rayita o flecha (con 4 teclas, ← ↓ ↑ →). Receptores con la tecla debajo, haz al pulsar, estallido al acertar. `laneColor` da los colores de los carriles. |
| `odori_keys.dart` | Teclas **físicas** por defecto para 1–7 carriles. `keyCap` saca la etiqueta del código USB, porque `debugName` no existe en release. |
| `odori_play.dart` | `OdoriPlayScreen(setup: OdoriSetup(...))`, que monta la partida (detalle debajo). |
| `odori_widgets.dart` | Nombres y colores de las dificultades (verde, azul, naranja, rojo y violeta), `DifficultyTag`, `JudgmentPop`, `OdoriPauseCard`, `RankBadge`, `OdoriResultsCard` y `SongProgress`. |

**Cómo funciona `OdoriPlayScreen`:**
- **Reloj:** `SongClock` es un cronómetro que se acerca un 5 % por fotograma a `AudioService.odoriPosition` y salta si se separa más de 80 ms. La partida empieza en negativo y la canción arranca al pasar por 0.
- **Pausa:** con Esc, P, Enter o el botón. Al seguir, la partida vuelve 1,5 s atrás.
- **Táctil:** multitoque con `Listener`; deslizar el dedo a otro carril cambia de tecla.
- **Final:** los resultados salen tras la última nota, y el audio sigue sonando debajo.
- **Sin audio** (tests o fallo de SoLoud) se juega igual, sin música.

**Audio:** `AudioService.loadOdori`, `setOdoriPaused`, `odoriPosition` y `stopOdori`. La voz lleva volumen = música/efectos (hasta ×4), y la pantalla hace `hushMusic`.

**Tests:**
- `test/odori_test.dart`: charter, juicio, rangos y catálogo.
- `test/odori_play_test.dart`: juego y pausa en 4 composiciones. También guarda capturas en `build/screenshots/odori-*.png`; el reloj corre de verdad y tarda unos 6 s por captura.

**Trampa conocida:** la partitura se lee con `rootBundle.loadString(..., cache: false)`. Con caché, el segundo test de widgets se quedaba colgado esperando un `Future` creado en la zona falsa del test anterior.

## Código (tarea 2)

| Archivo | Qué hace |
|---|---|
| `odori_channel.dart` | `OdoriChannel`: lista de canciones (bpm, número de voces y un punto por dificultad, lleno si ya se ha jugado) y panel con título, autor, bpm y duración, récord, versiones, dificultades con su color y su mejor rango, teclas 1–7, modo (Butai sale como «pronto»), Tama y ayuda, y «¡a bailar!». `loadSongInfo` lee bpm y duración de cada partitura. `assistFor` da la ayuda según la personalidad. El mixin `OdoriTheme` pone y quita el tema propio. |
| `odori_options.dart` | `OdoriOptionsPage`: dirección, aspecto de nota, velocidad (×0,5–×2,4; ×1 = 1,2 s de caída), desfase (±5 ms o calibrar), teclas de cada carril (se toca el carril y se pulsa la tecla; si ya estaba en otro, se cambian) y tema del juego. `OdoriCalibration`: metrónomo a 100 bpm; el desfase es la mediana de los últimos 16 toques. |
| `odori_store.dart` | `OdoriStore` guarda `odori.json` en local con `GameStore`: `OdoriPrefs` (canción, versión, dificultad, teclas, dirección, aspecto, velocidad, desfase, tema, Tama, ayuda y teclas cambiadas) y los récords (`OdoriBest`). |

- **Récords:** uno por versión, dificultad y teclas (`odoriRecordKey`). Las partidas con ayuda llevan `|tama` en la clave y no se mezclan. La primera partida no cuenta como récord nuevo.
- **Ayuda del Tama** (`OdoriAssist` en el motor), una por personalidad:
  - Tranquilo: ventanas 15 ms más anchas.
  - Juguetón: los 3 primeros fallos no rompen el combo.
  - Tímido: los toques antes de tiempo no son «uy».
  - Pícaro: 5 fallos se quedan en «vale».
  - Dormilón: 30 ms más de margen al tocar tarde.
- **El Tama en la partida:** en horizontal, a la derecha del tablero sobre su peana, con bocadillo. Salta al empezar y cada 50 de combo, avisa cuando su ayuda salva algo («¡te cubro!»), anima tras 4 fallos seguidos y comenta el rango al final. En vertical no sale, para no quitar sitio al tablero.
- **Tema propio:** `gameThemeProvider` (en `providers.dart`). Mientras el canal está abierto, `backdropIdProvider` devuelve el fondo de Odori, así que materiales, tinta y acento cambian en toda la app, y al salir vuelve el del menú. Se elige entre los fondos que tiene la cuenta, «como el menú» o sin fondo. El canal y la partida pintan el fondo detrás.
- **Canal provisional:** solo lo ve el admin (`channel.dart`, id `odori`), con icono propio (`ArtIcon.odori`, un abanico con los cinco colores). La sección de Odori de depuración ya no existe.
- **Fuente:** Zen Kaku no trae la «ō». Todos los estilos de interfaz llevan ahora `Rounded` de respaldo (`lib/theme/type.dart`).
- **Tests:** ayuda del Tama y récords en `test/odori_test.dart`. Recorrido del canal y capturas `odori-canal*.png` en `test/odori_play_test.dart`.

## Código (tarea 3)

| Archivo | Qué hace |
|---|---|
| `odori_butai.dart` | `butaiLayout(chart, seed:)` reparte las dianas (`ButaiSpot`: diana, origen y curva del vuelo). `ButaiStage` pinta el escenario y las notas. `ButaiPad` son los cuatro botones táctiles. `ButaiSymbol` es la burbuja de cada tecla. |
| `odori_lyrics.dart` | `OdoriLyrics` lee `<canción>_letra_<idioma>.json` y pasa los pulsos a segundos con la partitura de la versión. `at(t)` da la línea actual y la siguiente, y `sung(bar, t)` cuánto se ha cantado de un compás. `KaraokeStrip` es la franja de la letra. |

**Butai:**
- **Cuatro teclas siempre:** son las de 4 carriles (D F J K por defecto, cambiables en opciones). En el canal, al elegir Butai, el selector de teclas se cambia por la leyenda de flechas.
- **Cada tecla tiene su color y su flecha,** porque no hay carriles que lo digan: ← rosa, ↓ azul, ↑ verde y → ámbar.
- **Dianas:** siguen un camino que da vueltas por el escenario. El paso es más largo cuanto más separadas están las notas en el tiempo. Rebotan en los bordes (10–90 % de ancho, 16–84 % de alto) y no se ponen a menos de 0,15 de una diana que aún se ve. Los acordes van en fila, de través al camino. La semilla es la de la partitura, así que siempre salen igual.
- **Las notas vuelan** en curva desde detrás del camino, alternando el lado, y dejan una estela. La diana tiene una aguja que da una vuelta mientras la nota llega. En las largas, un aro se va llenando mientras se mantiene la tecla.
- **Escenario:** el azul noche del tema (`butaiNight`: marino teñido con el acento, nunca negro), con focos que se mecen, estrellitas y el suelo iluminado.
- **Controles:** en horizontal, la leyenda de teclas va en el marcador. En vertical, debajo salen los cuatro botones, dos para cada pulgar, con multitoque. En Butai no se aplican la dirección ni el aspecto de nota.
- **Récords aparte:** la clave lleva `butai` en lugar del número de teclas (`odoriRecordKey(..., mode:)`). El modo se guarda en `OdoriPrefs.mode`.

**Letra:**
- Va en una franja **debajo** del tablero o del escenario; nunca tapa notas.
- La línea que suena se ilumina carácter a carácter, en proporción a las notas cantadas del compás, y la letra que suena sale a medio color. Debajo va la siguiente, más tenue.
- Se enseña 3 s antes de que empiece la línea. Entre estrofas no sale nada.
- **Sin letra:** las versiones instrumentales y las que no tienen archivo en su idioma (Hoshikuzu) no reservan la franja.

**Tests:** en `test/odori_test.dart`, dianas y letra. En `test/odori_play_test.dart`, Butai con teclas y botones y el paso a Butai desde el canal, más las capturas `odori-letra`, `odori-butai` y `odori-butai-movil`.

**Arreglos tras probarlo:**

- Las burbujas de Butai pueden llevar flechas, figuras de mando (□ ✕ △ ○, en el orden ← ↓ ↑ →, con los colores de Project Diva) o la tecla que las toca (`OdoriPrefs.butaiMark`, en el canal debajo del modo). Las teclas se maquetan una vez y se guardan en caché.
- El tema de Odori tiñe la app entera, así que cambia al empezar a abrir el canal (con el último tema leído) y se quita al empezar a cerrarlo, no al acabar la animación (`OdoriTheme`).
- Butai es mucho más suave que Taki: `buildChart(butai: true)` busca el 55 % de las notas, las separa 1,7 veces más y solo pone acordes (de dos como mucho) desde Difícil.
- El escenario de Butai llena la pantalla. El marcador, la letra, el Tama y los botones van por encima, y las dianas se quedan en el hueco que dejan libre (`ButaiStage.inset`). Las dianas están más separadas, y cada nota muestra el camino que le queda hasta su diana: una línea tenue con puntos que corren hacia ella.
- Más respuesta al juzgar: el juicio aparece escrito sobre la diana; un acierto la llena con un destello, y un brillo añade un anillo dorado y rayos. Un fallo pone una cruz roja que tiembla y tiñe un poco los bordes. En Taki, el receptor se pone rojo al fallar y hace un anillo dorado con cada brillo.
- Soniditos al tocar: un tic muy suave, algo más claro con los brillos, sintetizado en `odori_hits.dart`. El volumen se elige en opciones con un deslizador; a cero se quitan (`OdoriPrefs.hitVolume`: 0,12 de serie y 0,4 como máximo, relativo al volumen de efectos).
- Butai en táctil (`OdoriPrefs.butaiTouch`): de serie se toca directamente la diana donde cae la nota. `butaiPick` elige la nota más cercana en el tiempo cuya diana está a menos de dos radios del dedo. Los cuatro botones siguen como opción.
- Butai con doble tecla (`OdoriPrefs.butaiDouble` y `butaiAlt`): cada figura se toca también con una segunda tecla, que por defecto son las flechas ← ↓ ↑ →, como en los mandos de Diva. Cada tecla pulsa por su cuenta, así que se puede alternar entre las dos en las ráfagas, y el carril solo se suelta cuando no queda ninguna de sus teclas pulsada. Se activa en el canal y se cambia en opciones.
- Los récords van por canción, nunca por versión: la clave es `canción|dificultad|teclas o butai|tama`. Al leer, los récords antiguos por versión se juntan en los de su canción, con el mejor resultado y todas las partidas. Los charts salen de la partitura de cada versión: tempo, secciones y percusión coinciden, y solo cambia la línea de la melodía (la voz o el instrumento), con el mismo número de notas buscado.

**Queda para las fases siguientes:** economía del Yatai, clasificaciones y reglas de Firebase, y créditos.

## Lo que entrega el generador (`assets/odori/`)

- **`<id>.ogg`:** la canción. Los ids siguen el patrón `<canción>` (instrumental) o `<canción>_<idioma>_<voz>`, por ejemplo `yako_ja_teto`.
- **`<id>.json`:** la partitura base que usa el charter:
  ```
  {id, title, bpm, offset, length,
   sections: [[pulso, nombre, energía]],
   events:   [[pulso, rol, nota MIDI, duración en pulsos, acento]]}
  ```
  - `offset` es la entrada: 1,2 s de silencio antes del pulso 0.
  - Los roles son `k` bombo, `s` caja, `h` charles, `o` abierto, `x` crash, `b` bajo, `c` acorde, `a` arpegio, `l` melodía y `v` voz.
- **`<canción>_letra_<idioma>.json`:** la letra del karaoke, que vale para todas las voces del idioma:
  ```
  {id, lang, lines: [{start, end, bars: [{text, notes: [[pulso, duración]]}]}]}
  ```
  - Cada línea abarca dos compases.
  - `text` es lo que se lee: kanji en japonés, texto normal en español e inglés.
  - Un guion final une la palabra con el compás siguiente.
  - Para pasar de pulsos a segundos: `offset + pulso * 60 / bpm`.

## Diseño del motor (fase 1)

- **Audio:** con SoLoud, como `playKoro`.
  - El volumen de la canción es el de música o efectos, porque el volumen global de SoLoud es el de efectos.
  - Se usa `hushMusic` para callar la música de fondo.
- **Reloj:**
  - Un cronómetro que se acerca poco a poco a `getPosition`, y se resincroniza de golpe si se separan más de 80 ms. Se le suma el desfase que calibre el usuario.
  - La partida empieza en tiempo negativo, y la canción espera en pausa hasta t = 0.
- **Charter:** convierte la partitura base en k teclas × 5 dificultades.
  - Los onsets se agrupan a 1/12 de pulso.
  - Prioridad: se calcula como rol × posición × energía.
  - Densidad objetivo en notas por segundo, multiplicada por 0,55–1,15 según el número de teclas:

    | Dificultad | Notas/s | Separación mínima | Notas largas desde |
    |---|---|---|---|
    | Easy | 1,4 | 0,30 s | 2 pulsos |
    | Normal | 2,4 | 0,18 s | 1,5 pulsos |
    | Hard | 3,8 | 0,12 s | 1 pulso |
    | Extreme | 5,4 | 0,085 s | 1 pulso |
    | Impossible | 7,5 | 0,06 s | 0,75 pulsos |

  - Acordes desde Normal, solo en los acentos.
  - El carril se elige por coste:
    - sigue el contorno de la melodía;
    - evita repetir tecla muy rápido;
    - bombo a la izquierda y caja a la derecha;
    - semilla fija, para que el chart salga siempre igual.
- **Juicio:**
  - Ventanas de ±45, ±90 y ±135 ms, que dan «¡brillo!», «bien» y «vale».
  - Un toque hasta 180 ms antes de tiempo cuenta como fallo, «uy».
- **Puntuación:**
  - 900 000 puntos por precisión y 100 000 por combo.
  - Rangos: S+ desde 980 000, S desde 950 000, A desde 900 000, B desde 800 000 y C desde 700 000.
- **Colores de los carriles:**
  - Los exteriores, plástico blanco con filo `accentDeep`.
  - Los interiores, `accent`.
  - El central, ámbar.
- **Karaoke:**
  - Abajo, la línea que suena, que se ilumina nota a nota con `notes`. Debajo, más tenue, la siguiente.
  - No debe tapar las notas del Taki.
  - En las versiones instrumentales no sale letra.
- **Canal provisional:** mientras se prueba, solo lo ve el admin.

## Pendiente fuera del código

- `assets/odori/<canción>/` ya está en el `pubspec.yaml`, una línea por carpeta. Cada canción nueva necesita su línea, y los temporales (`_teto_seco.wav`) no pueden quedar en esas carpetas.
- **Créditos (hechos 2026-09-25):** en `CREDITS.md`, `lib/core/credits.dart`, `README.md` y `assets/odori/LICENSE.md`.
  - Todo `assets/odori/` va bajo CC BY-NC 4.0; la excepción consta en la regla de la casa.
  - Cada voz conserva sus condiciones; las de NEUTRINO prohíben entrenar modelos, usar el audio como entrada de conversión de voz o como librería de samples.
  - Se acreditan también el diseño de Teto (線), la voz de Teto (小山乃舞世), el proyecto de Kiritan y Zundamon, y las herramientas NEUTRINO, Sinsy y WORLD.
  - Una voz nueva necesita su fila en los dos sitios.

## Economía y menú (0.6.3, decidido el 2026-09-25)

- **8 canciones** (Hoshikuzu Dash se retira: sus archivos quedan en `reserved/odori/hoshikuzu/`, fuera del `pubspec`).
- **Gratis:** Tamagoyaki, Ibasho y Yakō (`odoriFreeSongs`). **De pago a 10 monedas:** Hanabi, Neko no Basu, Kasa, Tsukimi y Kaeri Michi (`odoriPaidSongs`, artículos `odori_<canción>` del Yatai). Se compran en el Yatai o con el botón «conseguir» del canal; quedan en `/users/{cuenta}/odori/songs/{canción}: true`, que las reglas solo dejan escribir con el recibo de esa canción.
- **Monedas:** rango C o mejor al acabar → 3 (Easy, Normal), 5 (Hard), 8 (Extreme, Impossible); tope **30 al día** (`rewardCapFor`), también en las reglas. Contador en el menú.
- **Menú sin música del menú:** suena en bucle la instrumental de la canción elegida (`AudioService.playOdoriPreview`); se para al jugar o abrir opciones.
- **Versión:** se elige cantante (instrumental primero) y, si canta, idioma, solo con lo que existe.
