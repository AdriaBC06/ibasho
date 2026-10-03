# Próxima versión (0.9.0): plan

Lista acordada con el usuario el 2026-10-01, sacada del buzón de sugerencias y
de lo que quiere añadir él. Las marcadas **(por matizar)** necesitan una
conversación antes de empezar, así que no se implementan hasta cerrarlas.

## 1. Las sugerencias no se sustituyen (hecho, sin commitear)

**Problema**: `/suggestions/{accountId}` es un único nodo por cuenta. Cuando se
decide una sugerencia y la cuenta manda otra, la nueva pisa la anterior, con la
nota del admin incluida. Las anteriores al 2026-10-01 se han perdido: el plan
gratis de Realtime Database no hace copias de seguridad.

**Qué hay que hacer**:
- Cada sugerencia va a su propio nodo: `/suggestions/{accountId}/{id}`.
- Se mantiene la norma de **una pendiente por cuenta**, aplicada en las reglas
  y no solo en la pantalla.
- El panel de admin las enseña todas, con filtro por pendientes, aceptadas y
  rechazadas.
- Quien manda sugerencias ve su historial y la nota de cada una.
- **Migración**: las 7 que había el 2026-10-01 pasan al formato nuevo sin
  perder ninguna (estado, nota, `decidedAt`, `decidedBy`).

**Diseño elegido (2026-10-01)**: un archivo aparte, sin tocar el nodo vivo.
Así las versiones viejas siguen funcionando y no hace falta que las reglas
recorran hijos, cosa que no pueden hacer.
- `/suggestions/{accountId}` se queda igual: la viva, una por cuenta, y la
  regla de que una pendiente no se pisa.
- Nuevo `/suggestionHistory/{accountId}/{at}`, con la clave = `at` en
  milisegundos: es idempotente y se deduplica fácil. Guarda `title`, `body`,
  `at`, `status` (accepted/rejected), `note`, `decidedAt` y `decidedBy`. Lo
  escribe solo el admin; lo lee el admin entero y cada cuenta la suya.
- `SuggestionsController.decide` (`lib/state/suggestions.dart`) añade la
  entrada del archivo al mismo `merge` multirruta, de forma atómica. Como una
  pendiente no se puede pisar y al decidirla se archiva, ya no se pierde
  ninguna.
- Estado: `history` (las mías ya decididas, de la más nueva a la más vieja)
  y, solo para el admin, `decided` (todas). La UI quita del archivo la que
  coincide con la viva.
- UI (`suggestions_channel.dart`): «tus sugerencias anteriores» debajo de la
  tarjeta propia. En la sección de admin, un filtro segmentado
  pendientes/aceptadas/rechazadas.
- Migración: `tool/archive_suggestions.dart` copia las vivas ya decididas a
  `/suggestionHistory` con la CLI de Firebase, igual que `post_news.dart`. Se
  puede lanzar ya, porque es solo añadir, para no perder más antes de publicar.
- Tests: `test/messaging_test.dart` (bloque del buzón) y `tool/test_rules.sh`.

## 2. Elegir la música de cada juego (hecho, sin commitear)

Sugerencia (aceptada, «se mirará»): poder usar las canciones creadas o
desbloqueadas en otros juegos, por ejemplo hacer Korobeiniki y jugar con ella.

- Cada juego deja elegir con qué música se juega: la suya de serie o cualquier
  canción de la biblioteca de la cuenta (desbloqueadas, gacha y DIY).
- Hoy `GameMusic` (`lib/games/game_music.dart`) pone una pista fija por juego,
  y `MusicLibraryState` (`lib/state/music_library.dart`) solo guarda la del
  menú y la del perfil. Hay que guardar también una elección por juego.
- Ojo con Odori: sus canciones van ligadas al chart, así que ahí no aplica, o
  solo al menú del juego.

**Hecho (2026-10-02)**: `/users/{cuenta}/music/games/{gameId}` guarda una
pista o `koro_{hueco}`; si no hay nada, suena la de serie. `GameMusic` lleva
ahora `gameId`, lee la elección de `MusicLibraryState.gameTracks` y la pone
por encima de la suya (las de Tamakoro se renderizan a `koro_game.wav` y
suenan con `AudioService.playProfileFile`). Publica un `GameMusicScope`, y
`ChannelScaffold` pone el botón ♪ en la cabecera de cualquier juego que lo
tenga: buscaminas, Tsumiki, Hebi, Nihongo, Hatarakitama, pinball, pachinko y
Ohirune (estos tres no traen canción y su «de serie» es la del menú). El
selector propio de Hatarakitama desaparece: su elección local
(`hatarakiTrack`) se pasa a la cuenta al cargar. Odori y Tamakoro se quedan
fuera: allí la música es el juego. Tests: `test/game_music_test.dart` y uno de
reglas.

## 3. Notificaciones (por matizar)

Un sistema de avisos. Ejemplos que ha dado el usuario:
- Un Tama está triste o necesita algo.
- Se reinician las clasificaciones.
- Etc.: falta cerrar la lista.

Hay que decidir: si son avisos solo dentro de la app (una bandeja tipo HOME
Menu) o también notificaciones del sistema (Android, escritorio); cuáles se
pueden desactivar una a una; y cómo encajan con el límite de 100 conexiones
del plan gratis (ver la memoria de conexiones de Firebase), porque no pueden
abrir conexiones nuevas.

## 4. El tema del 67 (sugerencia secreta)

Sugerencia (aceptada): un tema «67» medio escondido, de los que salen al tocar
un 67 en algún sitio. Falta decidir dónde se esconde el 67 y qué pasa al
encontrarlo: un tema del menú (ver los temas de la 0.6.x), una animación o
ambas cosas.

## 5 y 6. Tama Kōen (公園): el parque de los Tamas

**Decidido con el usuario (2026-10-02)**. Los puntos 5 (visitar Tamas) y 6
(prestar Tamas) se juntan en un sitio nuevo: **Tama Kōen**, un parque al
estilo de la plaza Mii donde los Tamas de amigos juegan entre sí. Dentro del
parque se puede **cuidar un Tama a medias** con un amigo. Las cifras marcadas
como *(propuesta)* no se han hablado: se pueden ajustar.

### El parque
- **Solo amigos**. Cada uno ve *su* parque: sus Tamas y los de sus amigos.
  Solo hay encuentros entre Tamas de cuentas que son amigas: si A es amigo de
  B y de C, pero B y C no lo son, A ve a los dos, pero sus Tamas no se juntan.
- Cada jugador manda **hasta 3 Tamas**, que se quedan **hasta que los saque**.
- **Encuentros por día**: cada día, los Tamas que coinciden tienen encuentros
  calculados igual en todos los móviles (semilla del día + pareja de Tamas).
  No hace falta estar a la vez: al entrar se ve lo que ha pasado y se cobra.
  Nada de escrituras periódicas ni conexiones fijas (límite de 100 del plan
  gratis): lecturas puntuales al abrir.
- **Arrastrar** un Tama junto a otro, o a una zona, fuerza un encuentro en
  vivo o que juegue allí. Cuenta para premios, dentro de los topes y con como
  mucho **3 encuentros forzados por pareja de Tamas al día** *(propuesta)*.
- **Aspecto**: zonas de juego (columpios, tobogán, arenero, estanque, manta
  de picnic, árbol) y cada encuentro pasa en una; **día y noche** según la
  hora real (farolas y luciérnagas); **estaciones** según el mes (cerezos,
  hojas, nieve). **Se puede tocar**: un Tama salta y habla con su voz y
  enseña de quién es; el escenario (columpio, pato…) hace cosas.
- Es un **canal nuevo** del menú, con el lenguaje de consola de siempre
  (`docs/UI.md`).

### Beneficios (todos)
- **Monedas por jugar juntos**: las ganan los dos dueños, hasta **20 al día**
  por cuenta.
- **Amistad entre Tamas**: cada pareja que juega junta sube de nivel; en
  ciertos niveles desbloquea cosas (una animación de los dos, un fondo, un
  gorro).
- **Ánimo y regalos**: vuelven contentos (sube el humor) y a veces traen
  comida para la despensa o, raramente, un ticket del gacha (como mucho
  **1 a la semana** *(propuesta)*).
- **Álbum de recuerdos**: el parque saca «fotos» de momentos (columpio,
  picnic, pelota…) que se coleccionan, como las estampas (unas **24**
  *(propuesta)*).
- **Amistad entre jugadores** (idea del usuario): sube más despacio según lo
  que juegan sus Tamas. Niveles *(nombres propuestos)*: conocidos → amigos →
  buenos amigos → inseparables. Sale como **insignia en la lista de amigos**
  y en su perfil, y al subir de nivel **los dos reciben un premio** (monedas,
  un ticket…).

### Cuidar un Tama a medias
- El Tama sigue siendo **del dueño**, que es quien lo creó (`creator` y
  `keeper` no cambian). Se comparte con **un solo amigo**.
- Se ofrece desde el parque; el amigo acepta o rechaza.
- **El amigo puede**: mimarlo y darle de comer con su propia despensa,
  llevarlo al parque (ocupa uno de sus 3 huecos) y jugar con él en los
  minijuegos. **No puede**: editarlo, vestirlo, traspasarlo ni borrarlo.
- **Monedas**: cada día que el Tama está **mimado y comido** (lo haga quien
  lo haga), los dos cobran lo mismo: **10 cada uno**.
- **Se termina** cuando cualquiera de los dos quiera, o si dejan de ser
  amigos.
- **Espacio**: una **casita en el parque**, donde se cuida como en la ficha
  del Tama. También se abre desde la lista de amigos y desde los Tamas propios.
- Se ve en la **lista de amigos** para quien sea amigo del dueño.

### Dúos, racha, casita y accesorio de pareja
- Si A cuida un Tama a medias con B **y** B cuida uno con A, esos dos Tamas
  forman un **dúo**. Suben de amistad juntos.
- En la casita hay **dos huecos**: A pone su Tama a la izquierda o a la
  derecha, B el suyo en el hueco libre, y los dos pueden quitarlos y
  recolocarlos.
- Los dúos van **juntos en el parque** (con animaciones propias) y salen en
  pequeño **en la lista de amigos**, junto a la insignia de amistad.
- **Accesorio de pareja**: se consigue con el **dúo y además un nivel de
  amistad** (buenos amigos *(propuesta)*). Lleva un **color exclusivo**
  calculado a partir de las dos cuentas (por ejemplo, un tono sacado de sus
  ids ordenados). Hay **tres formas** y cada pareja elige una:
  - **colgante partido**: media forma cada uno (corazón, estrella, luna…),
    que juntos forman la pieza entera;
  - **gorritos gemelos**: asimétricos y en espejo, completan un dibujo al
    juntarse;
  - **hilo rojo**: una cinta al cuello; si están uno junto al otro, un hilo
    del color de la pareja los une.

  Se le puede poner a cualquier Tama, pero solo encaja cuando lo llevan los
  dos del dúo, uno al lado del otro: la mitad depende del hueco (izquierda o
  derecha).
- **Racha conjunta** (idea del usuario): cuenta los días seguidos en que
  **los dos** han cuidado su Tama del dúo (cada uno el suyo, mimado y
  comido). Si uno falla, se rompe para los dos: así se empujan a entrar.
  Premios en ciertos días de racha *(cifras por proponer)*.
- **Casita decorable del dúo** (idea del usuario): la casita donde viven los
  dos huecos se puede decorar entre los dos, con **niveles de recompensas**
  (sube con la racha, la amistad del dúo o lo decorado; cada nivel da
  muebles o premios). Por decidir al detallar: de dónde salen los muebles
  (¿los de la posada de Hatarakitama?, ¿tienda propia?) y quién puede mover
  qué.

### Notas técnicas (por diseñar al empezar)
- Parque: `/users/{cuenta}/park` (los Tamas mandados, como mucho 3), que
  leen los amigos. Las reglas tienen que dejar a los amigos leer el aspecto de
  esos Tamas, como hoy con el Tama de perfil, o se guarda una ficha como la
  de las visitas de Hatarakitama.
- Los encuentros se calculan en el cliente (determinista); lo que se cobra
  lleva tope en las reglas, como los minijuegos.
- Cuidado compartido: un campo nuevo en `/tamas/{id}` (p. ej. `carer`) que
  pueda escribir el dueño o el propio cuidador para quitarse; las reglas dejan
  al cuidador escribir `care` solo mientras sean amigos. Cobrar el día se
  puede comprobar en las reglas con `care.lastFed` y `care.lastPetted`.
- Amistad entre Tamas y entre jugadores: dónde se guarda y cómo no se
  descuadra entre las dos cuentas.
- Primero un documento propio (`docs/KOEN-0.9.0.md`) por fases, como el de
  Hatarakitama, antes de escribir código.

## 7. Minijuego de Snake (hecho, sin commitear)

Sugerencia (aceptada, «mas juegos»: tetris, serpiente, crucigramas, sudoku,
diferencias). Ahora toca la serpiente. Sigue las reglas del resto de juegos:
precio, monedas con tope, clasificación, canción propia y un Tama que lo
represente.

**Decidido (2026-10-01)**: se llama **Hebi** (蛇). Cuesta **10**, como Tsumiki,
y da 3, 5 u 8 monedas según la longitud, dentro del tope diario. Es clásico:
cuadrícula, comida de Tama (onigiri, dango…) y velocidad que sube. Se maneja
con cruceta tipo DS, deslizando o con teclado, y la clasificación es por mejor
longitud. Tama reactivo como en el resto. Lleva **canción nueva generada**,
lanzada con `nohup`.

**Hecho**: `lib/games/hebi/` (motor, canal, tablero, tarjetas y récords),
glifo `snake` e ilustración `ArtIcon.hebi`, `LeaderboardGame.hebi` (las
reglas ya aceptan cualquier juego: no hay que desplegar nada nuevo para él),
`game_hebi` en el catálogo y en `tool/seed_shop.dart`. La canción `hebi`
está en `tool/gen_hebi_music.py` (Re kumoi, 108 bpm, 53,3 s). Tests:
`test/hebi_test.dart`, la vuelta en `test/games_tour_test.dart` y dos de
reglas. De paso, el selector de juegos de Clasificaciones se desliza de lado
cuando no caben (en 360 px ya no se leían los nombres).

## 8. Calendario de cumpleaños en la lista de amigos (hecho, sin commitear)

Idea del usuario. Un calendario dentro de la lista de amigos que enseña los
cumpleaños de todos, cada uno con **su Tama de perfil**.
- Los datos ya existen: `UserProfile.birthday` (`lib/backend/models.dart`) y
  la lógica de zona horaria de `lib/core/birthday.dart`.
- Vista de mes, con el próximo cumpleaños destacado.
- Quien no tiene cumpleaños puesto no sale.
- Se puede enlazar con las notificaciones (punto 3): «mañana es el cumple de…».

**Decidido (2026-10-01)**: un **botón con icono de calendario** en la cabecera
de Amigos abre una vista de mes con flechas, cada cumpleaños con su Tama de
perfil y, debajo, «próximos cumpleaños». **El propio cumpleaños también sale**.

## 9. Mejoras de accesibilidad y UX

Hay que hacer una pasada por toda la app y proponer mejoras antes de
implementar nada. Puntos de partida:
- Tamaño de los objetivos táctiles (ya hay `test/touch_targets_test.dart`):
  ampliarlo a las pantallas nuevas.
- Etiquetas de lector de pantalla (`Semantics`) en botones que son solo un
  icono y en los juegos.
- Contraste de los temas del menú, sobre todo los que tiñen todo el entorno.
- Respetar el texto grande del sistema sin que se corten las pantallas.
- Opción de reducir movimiento: animaciones y efectos de los temas.
- Coherencia de los botones de volver, de confirmar y de ayuda entre juegos.

## 10. Voces nuevas en Odori (hecho)

Generadas por GPU el 2026-10-02 (2,3 veces más rápida que por CPU; ver
`docs/odori_musica.md`): 49 tandas sin ningún fallo, 153 `.ogg` en
`assets/odori` y ningún `.wav` suelto. Falta que el usuario las escuche.


**Decidido (2026-10-02)**: no entran las instrumentales nuevas (Hatarakitama,
Hebi). Lo que se añade son versiones cantadas jugables de las 8 canciones con
las cuatro voces de NEUTRINO que había descargadas y sin usar: **Reina**
(chica) y **Nakumo, Runo y Soma** (chicos), en japonés y español, con Taki y
Butai como el resto (el chart sale de la partitura, así que no cambia).
Mismo contrato que Merrow: uso comercial y no comercial, crédito opcional.

- `tool/odori_voices.py`: los cuatro modelos y `VOICE_OCTAVE`. Las voces de
  chico cantan la misma partitura una octava por debajo: las melodías llegan a
  Fa#5, que es su techo.
- `tool/odori_canciones.py`, `gen_odori_music.py` (Yakō) y
  `odori_voces_todas.sh` las incluyen: 64 versiones nuevas, unas 3 h.
- Odori: nombres en `OdoriVersion.singerNames` y orden en el selector. El
  catálogo las recoge solas del AssetManifest.
- Créditos: `CREDITS.md`, `lib/core/credits.dart`, `assets/odori/LICENSE.md` y
  `docs/odori_musica.md`.

## 11. Cositas (sesión del 2026-10-02)

Pedidas juntas; una pausa para compactar al acabar cada una.
- **a. Clasificaciones de siempre** (hecho, sin commitear) en todos los juegos (no solo
  Hatarakitama): la mejor partida de cada cuenta, una entrada por persona,
  rellenada con lo que ya hay en las diarias y semanales
  (`tool/backfill_alltime.dart`).
- **b. Icono nuevo de Hebi** (hecho, sin commitear): serpiente de bolitas
  como en el juego, de cola afilada a cabeza grande de frente, con onigiri.
- **c. Canciones de Odori compradas** (hecho, sin commitear): la baldosa no
  contaba las canciones como compradas; ahora baldosa y escaparate comparten
  `_owned` y dicen «en tu menú». Tamakoro ya topaba en 50 (lista, compra y
  reglas). Test en `yatai_channel_test.dart`.
- **d. Accesorios en el Yatai** (hecho, sin commitear): pestaña nueva
  «accesorios» (`ShopSection.accessories`) con la caca y 10 premios nuevos
  **solo de tienda** (`shop: true`, fuera del gacha y del Catálogo): gorro
  de pescador, gorro de fiesta, birrete, sombrero pirata, tiara,
  cascabel, gafas corazón, osito, wagasa y alas de mariposa. Plantillas en
  `tool/prizes/templates/`, colocación en `tama_outfit.dart`, galería
  `g10-yatai` y captura `y2c-accesorios`. Las reglas ya aceptaban cualquier
  `prize_*` con precio: no cambian.
- **e. Regalo diario** (hecho, sin commitear): pestaña «regalo» en el
  Yatai, una vez al día UTC: 1 comida al azar ×2, 1 gachaken y un saquito
  de **5–10** monedas. La caja se abre en la peana y deja ver la comida;
  la pestaña lleva un punto mientras está sin abrir. `users/{id}/gift` =
  `{day, at, food, coins}` (reglas nuevas, y `coins`, `tickets` y `pantry`
  aceptan su recibo fresco); la comida y las monedas las sortea la app.
  Estado en `lib/state/daily_gift.dart`, icono nuevo `ArtIcon.coinPouch`,
  botón de depuración para olvidarlo, tests de reglas en
  `rules_gift.test.mjs` y capturas `y3b-regalo`/`y3c-regalo-abierto`.
- **f. Más misiones** (hecho, sin commitear): 4 señales nuevas (acariciar,
  abrir el regalo del Yatai, llevar un Tama al parque y mandar un mensaje;
  Odori ya cuenta como partida). **Diarias**: 4 al día de 8 posibles, 1
  gachaken cada una. **Semanales de una vez**: tirar (1 kinken), comprar (3
  gachaken), parque y mensaje (2 gachaken cada una). **Repetibles**: jugar,
  dar de comer y acariciar, cada 5 veces 1 gachaken, hasta 3 por semana (una
  caricia cuenta una vez cada 30 s por Tama, como ya se guardaba).
  Recuento en `missions/tally/{evento}` = `{week, n, at}` (sube de 1 en 1,
  con su señal en la misma escritura) y cobros en
  `missions/repeat/{semana}/{evento}` = k, con recibo `kind: 'repeat'`.
  Reglas nuevas (en «Al publicar»), 11 tests de reglas más y
  `missions_controller_test.dart`.

## 12. Tsumiki versus (1 vs 1 con un amigo)

**Decidido (2026-10-03)** con el usuario:

- **Invitar** a un amigo desde Tsumiki. Le sale un **1** en el canal de
  Tsumiki y, si está dentro del juego, lo ve en el momento. Puede aceptar o
  rechazar. **Caduca a los 10 minutos**: si acepta a tiempo y quien invita
  sigue en la sala, empieza la partida; si no, desaparece sola.
- **Mecánica: basura clásica.** Borrar 2 o más líneas, encadenar combos o
  hacer un tsumiki (4 filas) le sube filas grises al otro desde abajo. Los
  dos juegan con **las mismas piezas** (la misma semilla). Pierde quien se
  llena primero.
- **Igualar con sabotajes durante la partida.** Al borrar líneas se carga un
  medidor y se lanzan trabas al otro. **El que va perdiendo lo carga más
  rápido.** *(Propuesta de trabas: acelerar la caída, tapar la vista previa,
  bloquear la reserva, niebla en la parte de arriba del tablero.)*
- **Una sola partida** por enfrentamiento; luego hay un botón de revancha.
- **Sin monedas.** Solo cuentan el historial y el marcador.
- **Abandono:** si alguien se desconecta y no vuelve en **20 s**, gana el
  otro y queda en el historial como abandono.
- **Historial** entre los dos: en Tsumiki, por amigo (marcador y partidas con
  fecha, ganador, líneas mandadas y duración), y el marcador también en la
  **ficha del amigo**.
- **Interfaz:** un menú nuevo al entrar (Solo / Versus / Historial) y una
  pantalla versus: tu tablero grande, el del otro en pequeño con su Tama, el
  medidor de basura y el de sabotajes. El modo solo no cambia.

**Técnica (por diseñar):** una sola conexión por jugador durante la partida,
a `/tsumiki/{a_b}` (por el límite de 100 conexiones del plan Spark);
invitación en el buzón del amigo, como `koenInbox`; tablero del otro por
instantáneas al asentar cada pieza.

**Fases** (con pausa al acabar cada una):

1. Motor: basura, sabotajes, ayuda al que va perdiendo, semilla compartida.
   Sin Flutter, con tests. **Hecho (2026-10-03, sin commitear):**
   `TsumikiPiece.garbage` (fuera de la bolsa, `playable`), cola de grises en
   `TsumikiGame` (`queueGarbage`/`cancelGarbage`, suben al asentar sin borrar,
   máx. 8 por pieza, hueco por tanda), `speedFactor`, `holdLocked`,
   `encodeBoard`/`decodeBoard` (200 letras). `lib/games/tsumiki/tsumiki_versus.dart`:
   `TsumikiDuel` (misma semilla, huecos por `side`), tabla 2→1, 3→2, 4→4,
   +1 seguidos, combos 0,0,1,1,1,2,2,3,3,4,4,4,5; medidor 100 (8 por fila
   borrada, 4 por gris recibida, ×1–×2 según lo lleno que vaya respecto al
   otro); sabotajes `rush` (×2,5, 8 s), `blind` (10 s), `lock` (10 s),
   `fog` (9 filas, 8 s); repetir reinicia el tiempo. 13 tests nuevos.
2. Red y reglas: invitación con caducidad, sala, sincronización, abandono a
   los 20 s e historial. Tests de reglas. **Hecho (2026-10-03, sin
   commitear):** reglas `users/{id}/tsumikiInbox/{quien}` `{at, id}` y
   `/tsumiki/{a_b}` con `a`, `b`, `live` (`id, seed, host, guest, state
   wait|play|done|no|gone, at, start, p/{cuenta}, atk/{cuenta}/{push},
   result {w, why top|leave|quit, at}`), `history/{id}` y `score/{cuenta}`;
   el final (resultado + historial + marcador +1 + `done`) va en una sola
   escritura; ganar por `quit` exige que el `ping` del otro tenga más de
   20 s; aceptar, menos de 10 min desde `at`; una sala en juego solo se pisa
   con 30 min o los dos `ping` de más de 1 min. 24 tests de reglas
   (`rules_tsumiki.test.mjs`, 283 en total). Cliente:
   `lib/backend/tsumiki_versus.dart` (modelos) y
   `lib/state/tsumiki_versus.dart` (`TsumikiVersusController`: invite,
   accept, decline, cancel, checkExpiry, rematch, publish, send, lose,
   leave, heartbeat cada 5 s, close; `incoming` con lo del otro una vez;
   `tsumikiInvitesProvider`, `pendingTsumikiInvitesProvider`,
   `tsumikiHistoryProvider`, `tsumikiScoreProvider`). Una conexión en
   partida (`/tsumiki/{a_b}/live`); el buzón va por la de la cuenta. 15
   tests (`tsumiki_versus_net_test.dart`); 724 en total.
3. Interfaz: menú, invitar y responder con el 1, pantalla versus y
   resultado con revancha. **Hecho (2026-10-03, sin commitear):** el canal
   (`tsumiki_menu.dart`, `TsumikiChannel`) entra a un menú Solo / Versus /
   Historial; el solo de siempre es `TsumikiSolo` (`tsumiki_channel.dart`),
   con la cruz que vuelve al menú. Los mandos (cruceta, botones, teclado,
   gestos) pasan al mixin `TsumikiControls` (`tsumiki_input.dart`), que
   comparten solo y versus. El 1 del canal sale de
   `pendingTsumikiInvitesProvider` (`GameChannelEntry.badge`); dentro del
   canal un aviso «X te reta · ver» en el menú, el solo y el historial.
   Sala de rivales con los retos recibidos (sí / ahora no) y los amigos;
   espera con el Tama del otro y la cuenta atrás de 10 min (`checkExpiry`
   cada segundo); avisos de no puede / caducada / cancelada / sin conexión.
   La partida (`tsumiki_vs_play.dart`): tu pozo con la barra roja de grises
   en camino, niebla, siguientes tapadas a ciegas y reserva apagada con
   candado; el otro pequeño con su Tama, filas, enviadas y sus trabas;
   medidor y 4 botones (teclas 1–4); bandera para rendirse (pregunta).
   Resultado con marcador, lo de cada uno y revancha (o «aceptar la
   revancha» si ya la ha pedido); guarda el final al acabar porque con la
   revancha la sala cambia. `close()` ya no espera a cortar la escucha.
   Historial básico adelantado: amigos con su marcador y, por amigo, el
   marcador, «retar» y una fila por partida. 60 textos nuevos. Recorrido con
   capturas en `games_tour_test.dart` (`v1`–`v8`); 727 tests.
4. Historial y repaso. **Hecho (2026-10-03, sin commitear).** Píldora
   «tsumiki 3 – 2» en la ficha del amigo (`TsumikiScoreChip`, solo si ya
   habéis jugado) que abre sus partidas en un diálogo. El Tama del otro
   reacciona en la partida con globo y cara: al empezar, al recibir o mandar
   grises (de 2 en adelante), con las trabas, cuando su montón se acerca
   arriba y al final; lo de más peso pisa a lo de menos. Prueba con dos
   cuentas sobre la misma base (`tsumiki_versus_two_test.dart`: partida
   entera, revancha y abandono) y captura de la ficha (`30b`). 730 tests.
   Falta que el usuario lo pruebe con dos equipos de verdad.

## Al publicar la 0.9.0

Todo lo que toque producción va **junto con la versión**, nunca antes
(decisión del usuario, 2026-10-01).
- Desplegar las reglas (`/suggestionHistory`, `music/games` y las de Tama
  Kōen: `users/{id}/koen` (con `duo`, `duos` y `charm`), `/koen/{a_b}` de
  los dúos (con `charm`),
  `koenInbox`, `tamas/{id}/carer` y `care`, `earnings/koen` y `koen_care`, y
  las ramas del parque en `pantry`, `tickets`, `prizes` (también el
  accesorio de pareja, `charm_*`) y `coins`; el regalo diario del Yatai,
  `users/{id}/gift`, y su recibo en `coins`, `tickets` y `pantry`; y las
  misiones nuevas: señales, `missions/tally` y `missions/repeat`; y
  Tsumiki versus: `users/{id}/tsumikiInbox` y `/tsumiki/{a_b}`).
- `dart run tool/archive_suggestions.dart --write` (en seco encontró las 7).
- `dart run tool/backfill_alltime.dart --write` **después** de desplegar las
  reglas (en seco, 2026-10-02: 40 marcas en las tablas de siempre).
- Precio de Hebi: `firebase database:update /shop/prices` con
  `{"game_hebi": 10}` (solo añade). Sin él, Hebi sale en el Yatai pero no se
  puede comprar. Ojo: `tool/seed_shop.dart` escribe `/shop/prices` entero; ya
  lleva los `odori_*` que le faltaban (en producción estaban y los habría
  borrado), pero mejor la actualización puntual.
- Precios de los 10 accesorios del Yatai, también con `database:update`
  (solo añade): `prize_bucket_hat_khaki` y `prize_suzu_red` 30;
  `prize_party_hat_pink`, `prize_grad_cap_black`, `prize_heart_shades_pink`
  y `prize_teddy_brown` 50; `prize_pirate_hat_black` y `prize_wagasa_red` 80;
  `prize_tiara_silver` y `prize_butterfly_wings_blue` 120 (están en
  `tool/seed_shop.dart`). Sin precio salen «no disponible».
- Tras desplegar las reglas, probar el versus de Tsumiki con dos cuentas
  reales (invitar, rechazar, caducar, partida, abandono y revancha): los
  tests usan el backend falso, que no aplica reglas.
- `minVersion` 0.9.0 cuando lo diga el usuario.
- **Revisar el tamaño de los paquetes** (exe de Windows, Linux, APK…): están
  creciendo mucho (petición del usuario, 2026-10-02). Medir cada uno contra
  el de la 0.8.1, ver qué pesa (sobre todo `assets/odori`: con las voces
  nuevas son 64 `.ogg` más) y proponer recortes: bitrate de los `.ogg`, APK
  por ABI (`--split-per-abi`), quitar recursos sin usar…

## Sugerencias descartadas o ya hechas

- «tama clicker»: ya es Hatarakitama (0.7.0).
- «botón de "?" en buscaminas»: rechazada.
- «buscaminas»: ranking global. Aceptada; comprobar que está.
