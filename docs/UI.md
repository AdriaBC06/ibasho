# Cómo se hace una pantalla de Ibasho

Guía de diseño para cualquier pantalla nueva. Resume las decisiones que ya
están en el código (`lib/theme/`, `lib/ui/widgets/`) y lo aprendido al rehacer
el Yatai y el buscaminas en la 0.5.0. Si una pantalla nueva no cumple esto, no
está terminada aunque funcione.

La referencia de los widgets (parámetros y archivo de cada uno) está en
[`ARCHITECTURE.md`](ARCHITECTURE.md#3-widgets-propios). Aquí va el *porqué* y
el *cuándo*.

---

## 1. La referencia

Ibasho es una consola, no una app. La estética es el **aero de Nintendo** de la
Wii, la Wii U, la DS y la 3DS: el menú de la Wii, el HOME Menu, el Canal
Tienda, la eShop, los resultados de un juego de DS.

Lo que eso significa en la práctica:

- **Plástico blanco brillante** con un degradado suave y un reflejo en el
  tercio de arriba. Nada es plano.
- **Cristal**: huecos hundidos, peanas transparentes, barras de progreso con
  reflejo.
- **Un solo acento** (el cian de la casa o el que elija cada cual) para lo que
  está elegido, el foco y la acción que continúa la tarea.
- **Mucho aire.** Pocas cosas por pantalla, grandes y bien separadas.
- **Cosas vivas**: los Tamas miran, reaccionan y hablan; lo que se toca
  responde con rebote; lo que se gana se celebra.
- **Nunca Material.** Ni un widget, ni un icono, ni un color de Material.

Si dudas, busca una captura del Canal Tienda de la Wii o del HOME Menu de la
3DS y compara.

---

## 2. Composición: una escena, no siempre dos pantallas

El entorno (`shell_screen.dart`) usa **dos pantallas** como la DS: arriba
información y abajo la rejilla. Ese esquema sirve para pantallas de
*colección*, es decir, elegir algo de una rejilla y verlo en grande (Tamas,
amigos). No es la plantilla de todo.

| Tipo de pantalla | Composición | Ejemplos |
|---|---|---|
| Colección | Dos paneles `ScreenPanel`: escaparate arriba y rejilla paginada abajo | tus Tamas, amigos |
| Juego o experiencia | **Una escena**: el protagonista (tablero, habitación) grande, y a un lado un escenario con el Tama y los controles | buscaminas, Tsumiki, Nihongo, habitación del Tama |
| Tienda o catálogo | **Una escena** en franjas: escaparate con peana y foco, secciones en medio y mostrador paginado abajo, sin marcos alrededor | Yatai |
| Formulario o ajustes | Columna con `SectionCard` y `SettingRow` | ajustes, perfil |

Reglas:

- **No metas cada zona en una caja.** Un `ScreenPanel` alrededor de todo hace
  que la pantalla parezca un formulario. El escaparate del Yatai no tiene
  marco: la peana y el foco ya delimitan la zona.
- **Lo importante, grande.** En el buscaminas el tablero se lleva todo el alto
  disponible; en el Yatai el artículo elegido mide 200 px.
- **Horizontal (1280×800)**: escenario a la izquierda (unos 350 px) y
  protagonista a la derecha.
- **Vertical (360×640 a 411×914)**: el escenario pasa a una franja arriba, el
  protagonista en medio y los controles abajo, al alcance del pulgar. Si sobra
  alto (más de 840), se lo lleva el escenario. Lo que en horizontal es una
  fila de tarjetas, en vertical se abre en un diálogo (los tableros del
  buscaminas).

---

## 3. Materiales

Todo sale de cuatro piezas. No dibujes superficies a mano.

| Material | Widget | Cuándo |
|---|---|---|
| Plástico | `GlossSurface()` | Todo lo que se pulsa o flota: botones, baldosas, tarjetas, bocadillos, resultados |
| Plástico tintado | `GlossSurface(tint: skin.accent)` o `skin.accentWash` | El botón de acento, lo elegido (con `accentWash` y filo `accentDeep`) |
| Hueco | `GlossSurface(recessed: true)` | Marcadores, raíles de interruptores, campos, ranuras libres, pestañas |
| Pantalla | `ScreenPanel` | Solo en las pantallas de colección (ver §2) |

Y los decorados de escena:

- **Foco** (`StageLight` en el buscaminas y `_PedestalPainter` en el Yatai):
  halo radial del acento con rayos blancos muy tenues, como el fondo de los
  canales de la Wii.
- **Peana de cristal**: disco con canto, reflejo y sombra de contacto. Lo que
  se exhibe flota encima con un balanceo lento, que se para con movimiento
  reducido.
- **Sombra de contacto** (`paintGroundShadow`): toda figura apoyada lleva una
  debajo.

---

## 4. Color

- **Ningún archivo escribe un color a mano** salvo `lib/theme/tokens.dart`
  (clase `T`) y las ilustraciones (`Art` en `channel_art.dart`). Si necesitas
  un color nuevo de interfaz, añádelo a `T` con un comentario de para qué es.
- El acento se lee siempre de `IbashoSkin.of(context)`: `accent`,
  `accentDeep` (bordes y texto de acento) y `accentWash` (fondo de lo
  elegido). Nunca `T.cyan` directamente.
- **Nunca negro puro.** El texto es `T.ink` y el secundario `T.inkSoft`. Para
  oscurecer se mezcla hacia `T.dusk` (azul noche), no hacia el negro.
- Las ilustraciones tienen **colores propios**, como un icono de la 3DS: se
  ven igual con cualquier acento. Lo que sí sigue al acento es la interfaz de
  alrededor (casillas del tablero, peana, foco).

---

## 5. Iconos: glifo o ilustración

Hay dos familias y no se mezclan en el mismo papel.

**Glifo** (`GlyphIcon`, `enum Glyph`): línea redondeada de un solo color sobre
24×24.

- Canales del sistema (ajustes, perfil, amigos…), botones, estados (candado,
  check) y controles.
- Las normas de dibujo están en `glyphs.dart` y las comprueba
  `test/glyphs_test.dart`.

**Ilustración** (`ArtIconView`, `enum ArtIcon`): pieza pintada a color sobre
100×100.

- Lo que **se compra o se juega**: el Yatai, cada juego, el gacha, la moneda,
  las medallas. En la rejilla van sobre **baldosa blanca** (los del sistema
  van sobre acento) y así se distinguen de un vistazo.
- Cómo se pinta una:
  1. Formas sencillas y redondeadas, que se lean a 24 px (mira la fila
     pequeña de `build/screenshots/g8-ilustraciones.png`).
  2. Cada pieza con `paintPlastic`: degradado claro → base → oscuro, brillo
     arriba recortado por la forma y **filo del mismo tono oscurecido**, nunca
     negro.
  3. Sombra de contacto debajo.
  4. Un detalle con vida: la mina tiene carita, el farolillo brilla y la
     máquina lleva cápsulas de colores.
  5. Añádela a `test/art_gallery_test.dart` y mira la galería.
- Un juego nuevo necesita su `ArtIcon`, además de su `Glyph` (el glifo se usa
  donde se necesita línea, por ejemplo en la animación de apertura con
  movimiento reducido).

El **regalo** (`GiftFace`) es la ilustración de «algo nuevo para ti». Su
parámetro `open` anima entero el desenvolver; al revés (de 1 a 0) sirve para
envolver durante una compra.

---

## 6. Tipografía

- `Ty.body`, `Ty.caption`, `Ty.lead`, `Ty.title` y `Ty.display` para texto
  (ZenKaku).
- `Ty.numeral` (M PLUS Rounded) para **toda cifra que importe**: tiempos,
  monedas, contadores y precios. Los números del tablero también van en
  redondeada.
- Minúsculas en etiquetas y botones («otra ronda», «conseguir»), como el
  resto del entorno. Los nombres propios, en mayúscula (Yatai, Tamas).
- Todo texto sale de `lib/l10n/app_es.arb` y `app_en.arb`, **en los dos**.
  La descripción (`@clave`) solo va en el de castellano.

---

## 7. Controles

- **Un solo botón de acento por pantalla**: el que continúa la tarea
  («comprar», «otra ronda» al acabar una partida). Todo lo demás es `plain` o
  `quiet`.
- **Elegido no es deshabilitado.** Un selector marca la opción activa con
  `accentWash` y filo `accentDeep` (`SlotTile(selected: true)`, `ModeSwitch`,
  las pestañas del Yatai). No pongas `onPressed: null` para marcar lo
  elegido: se pinta gris y parece roto. Era uno de los fallos del buscaminas
  de la primera 0.5.0.
- **Botones con texto** para las acciones principales. Un `IconPill` suelto
  solo cuando el icono no deja duda (cerrar, flechas de página) o en vertical
  cuando falta sitio, y siempre con `semanticLabel`.
- **Al dedo, 48 px como mínimo** en vertical. Lo comprueba
  `test/touch_targets_test.dart`. Si una fila no cabe, apila (icono encima y
  etiqueta en pequeño debajo, como las pestañas del Yatai a 360 px) antes
  que encoger.
- **Pestañas de sección** con icono y texto sobre un raíl hundido. La
  elegida es una pastilla de plástico tintada.
- **Dos modos** (destapar o bandera): raíl hundido con un pomo que se desliza
  con `easeOutBack` (`ModeSwitch`).
- **Elegir entre pocas opciones** (nivel de salida, grupos de kana, modo de
  respuesta): `SegmentRail` con `SegmentPill` (`lib/games/game_stage.dart`).
  La elegida va en `accentWash` con filo; nunca en acento lleno.
- **Mandos de juego** (Tsumiki): cruceta (`DPad`) y botones redondos
  (`PadButton`) que avisan al bajar y al subir el dedo, para repetir mientras
  se mantiene. Son plástico blanco, no acento: el acento sigue siendo del
  botón que continúa la tarea.
- **Precios**: pastilla hundida con la moneda ilustrada y la cifra, o una
  cinta verde de «gratis». Nunca texto suelto.

---

## 8. Colecciones

- **Páginas, no scroll.** Rejilla de ranuras (`SlotTile`) con flechas, puntos
  y deslizar (`PageSwipe`). Los huecos que sobran en la última página son
  `EmptySlot` hundidos, no espacio vacío.
- Tocar una vez **elige** (sube, se tiñe y el escaparate lo enseña). La acción
  va en el escaparate, no en la baldosa.
- La baldosa lleva la ilustración, el nombre y su estado en pequeño (precio,
  candado, «en tu menú», unidades en una chapa).

---

## 9. Movimiento

- **Hover**: sube 4 px y se inclina 2° con `easeOutBack`. **Pulsar**: se hunde
  (`sink`). Viene hecho en `SlotTile`, `ChannelTile` e `IbashoButton`.
- **Entradas con rebote**: diálogos, resultados y bocadillos escalan desde
  0,6–0,7 con `easeOutBack`. Una medalla entra girando con `elasticOut`.
- **Causa y efecto**: lo que cambia por un toque se anima **desde el toque**.
  Las casillas se destapan en ola según su distancia, y una mina sacude el
  tablero y suelta una onda.
- **Celebra lo que se gana**: confeti, banderas que ondean, el Tama que salta.
  Y **consuela lo que se pierde**: el Tama cae KO y dice algo, sin castigar.
- **Movimiento reducido siempre**: las duraciones pasan por
  `skin.motion(...)` y las curvas por `skin.curve(...)`. Con movimiento
  reducido, un efecto de pintura salta a su estado final.
- **Los tickers se paran** cuando no hay nada que mover. El reloj de efectos
  del buscaminas solo avanza con el ticker en marcha y se detiene al acabar el
  último efecto. Un `Stopwatch` de tiempo real no sirve, porque en los tests
  el tiempo es falso y las capturas saldrían a medias.

---

## 10. Vida: el Tama como compañía

Los Tamas son mascotas, no avatares (ver `tama_vision`). Cuando una pantalla
tiene hueco para un personaje, que sea **uno de los Tamas de la cuenta**:

- Las piezas de escenario de todos los juegos (`StageLight`, `SpeechBubble`,
  `GlossyFace`, `Readout`) viven en `lib/games/game_stage.dart`.
- En el buscaminas, Tsumiki y Nihongo sale uno **al azar en cada ronda** (distinto del anterior
  si hay donde elegir). Sin Tamas hay una cara de reserva (`GlossyFace`),
  también lacada, nunca un círculo plano.
- `TamaOnStand` con un `TamaViewController`: `hop()` para saltar, `cuddle()`
  para celebrar y `speak(...)` para su voz. El `joy` (−1 a 1) cambia la cara.
- **Bocadillo** (`SpeechBubble`) con frases cortas y de vez en cuando; si
  habla en cada toque, cansa.
- El Tama ya mira al puntero por su cuenta (`TamaPointer`); no hace falta
  hacer nada.

---

## 11. Sonido

`AudioService.instance.play(Sfx.x)`: `tick` al elegir o mover, `open` al
entrar, `back` al salir o cancelar, `chime` al conseguir algo y `error` al
fallar. Los controles del entorno ya suenan solos (`cue`); pasa `cue: null`
si el sonido lo pone quien llama.

---

## 12. Palabras

El entorno habla con sus propias metáforas, no con las de un ordenador:

- Un juego comprado **llega envuelto** y está **en tu menú**. No se
  «instala». Durante la compra: «envolviendo tu regalo…».
- La comida va **a la despensa** y se prepara **tu pedido**.
- Tono cercano y breve: «¡a por ello!», «¡despejado!», «otra ronda».

---

## 13. Comprobar antes de darla por buena

1. `flutter analyze` sin avisos.
2. Recorridos de capturas (salen en `build/screenshots/`):
   - `flutter test test/visual_tour_test.dart` (horizontal)
   - `flutter test test/tall_tour_test.dart` (360×640 y 411×914)
   - `flutter test test/games_tour_test.dart` (Yatai, buscaminas, Tsumiki y
     Nihongo en las tres medidas, con compra, regalo, partidas y rondas)
   - `flutter test test/art_gallery_test.dart` (ilustraciones y regalo)
3. **Mira las capturas** con esta guía al lado. Busca:
   - ¿Se parece a la Wii o la 3DS, o a una app?
   - ¿Hay algo plano: un círculo sin brillo, un texto sin superficie o un gris
     que parece deshabilitado?
   - ¿Hay más de un acento?
   - ¿Hay textos cortados en 360 px?
   - ¿Hay zonas vacías que piden aire o un escenario más grande?
4. `flutter test` entero. Los tests de widgets pintan con Ahem (una letra =
   un cuadrado), mucho más ancha que la fuente real: si una fila desborda
   ahí, en una pantalla con otra fuente o idioma también puede.
5. Si toca reglas, `./tool/test_rules.sh`.
