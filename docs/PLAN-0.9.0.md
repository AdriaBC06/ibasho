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

## 2. Elegir la música de cada juego

Sugerencia (aceptada, «se mirará»): poder usar las canciones creadas o
desbloqueadas en otros juegos, por ejemplo hacer Korobeiniki y jugar con ella.

- Cada juego deja elegir con qué música se juega: la suya de serie o cualquier
  canción de la biblioteca de la cuenta (desbloqueadas, gacha y DIY).
- Hoy `GameMusic` (`lib/games/game_music.dart`) pone una pista fija por juego,
  y `MusicLibraryState` (`lib/state/music_library.dart`) solo guarda la del
  menú y la del perfil. Hay que guardar también una elección por juego.
- Ojo con Odori: sus canciones van ligadas al chart, así que ahí no aplica, o
  solo al menú del juego.

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

## 5. Visitar Tamas

Ver los Tamas de un amigo en su casa o su espacio, no solo en la lista. Puede
aprovechar las visitas a los pueblos de Hatarakitama de la 0.8.0.

## 6. Prestar Tamas a amigos (por matizar)

Dejar un Tama a un amigo para que lo cuide: darle de comer, jugar, etc. Si lo
cuida, **genera dinero cada día**. Falta decidir:
- Quién cobra: el que presta, el que cuida o los dos.
- Cuánto dura el préstamo y quién puede terminarlo.
- Qué puede hacer el amigo y qué no: por ejemplo, editarlo o transferirlo
  seguro que no.
- Qué pasa si no lo cuida.
- Cómo encaja con la visión de los Tamas como mascotas vivas y transferibles.

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

## 10. Las canciones nuevas, también en Odori

Idea del usuario (2026-10-01). Las canciones generadas desde la última
tanda de Odori (las de Hatarakitama y la de Hebi, por ejemplo) pasan a ser
jugables en Odori, con su chart. Falta decidir cuáles exactamente y si cada una
lleva sus modos Taki/Butai.

## Al publicar la 0.9.0

Todo lo que toque producción va **junto con la versión**, nunca antes
(decisión del usuario, 2026-10-01).
- Desplegar las reglas (`/suggestionHistory`).
- `dart run tool/archive_suggestions.dart --write` (en seco encontró las 7).
- Precio de Hebi: `firebase database:update /shop/prices` con
  `{"game_hebi": 10}` (solo añade). Sin él, Hebi sale en el Yatai pero no se
  puede comprar. Ojo: `tool/seed_shop.dart` escribe `/shop/prices` entero; ya
  lleva los `odori_*` que le faltaban (en producción estaban y los habría
  borrado), pero mejor la actualización puntual.
- `minVersion` 0.9.0 cuando lo diga el usuario.

## Sugerencias descartadas o ya hechas

- «tama clicker»: ya es Hatarakitama (0.7.0).
- «botón de "?" en buscaminas»: rechazada.
- «buscaminas»: ranking global. Aceptada; comprobar que está.
