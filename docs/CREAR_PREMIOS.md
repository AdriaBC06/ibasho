# Cómo se hace un gorro o un accesorio

Guía para añadir premios que se pone un Tama. Resume cómo están hechos los
gorros y accesorios de la 0.6.0 y lo aprendido al probarlos. El estado de la lista está en
[`PREMIOS.md`](PREMIOS.md); las normas generales de dibujo, en [`UI.md`](UI.md).

---

## 1. Las piezas

| Qué | Dónde | Para qué |
|---|---|---|
| Plantilla SVG | `tool/prizes/templates/<id>.svg` | El dibujo, con los colores como huecos |
| Parte de delante | `tool/prizes/templates/<id>_front.svg` | Solo si va en dos partes (§3) |
| Manifiesto | `tool/prizes/prizes.json` | Qué plantilla usa cada premio y sus variantes de color |
| Generador | `python3 tool/gen_prizes.py` | Rellena los huecos y escribe `assets/prizes/<id>_<variante>.svg` |
| Catálogo | `lib/backend/prizes.dart` (`wearablePrizes`) | Rareza y sitio de cada premio |
| Colocación | `lib/ui/tama/tama_outfit.dart` (`_places`) | Dónde y a qué tamaño va sobre el Tama |
| Pintado | `lib/ui/tama/tama_painter.dart` | Orden de las capas; ya no hay que tocarlo salvo sitio nuevo |
| Hoja de prueba | `test/prize_preview_test.dart` | Cada premio en 6 Tamas → `build/screenshots/g9-premios.png` |

Un **premio** es un dibujo (`cap`) y cada **variante** de color (`cap_red`) es
un premio distinto del gacha. La clave es `id_variante`, en minúsculas, cifras y
`_`, de 40 letras como mucho (lo exigen las reglas). **No hay que tocar las
reglas** para añadir premios.

---

## 2. Pasos

1. **Decide** el sitio (§3), la rareza (§5) y las variantes.
2. **Dibuja la plantilla** con el lienzo de su sitio (§4) y el kit de estilo (§5).
3. **Añádelo al manifiesto**:
   ```json
   {
     "id": "beanie",
     "template": "beanie.svg",
     "variants": {
       "red": {"main": "#E8505B", "pom": "#FFFFFF"},
       "blue": {"main": "#3F7FD8", "pom": "#FFFFFF"}
     }
   }
   ```
   Si una variante tiene otra forma (la botella de agua y la de cola, los
   cuatro antifaces), lleva su propia `"template"` dentro de la variante. Una
   plantilla sin huecos (las ∞, con su arcoíris fijo) lleva la variante vacía:
   `"rainbow": {}`.
4. **Genera**: `python3 tool/gen_prizes.py`. Se para si queda un hueco sin
   rellenar, que en pantalla saldría negro. Si existe `<plantilla>_front.svg`,
   saca también `<clave>_front.svg`.
5. **Míralo suelto** (rápido y barato):
   ```sh
   rsvg-convert -h 200 assets/prizes/beanie_red.svg -o /tmp/beanie.png
   ```
6. **Añádelo al catálogo** en `lib/backend/prizes.dart`, en su sitio de la
   lista (gorros primero y de menos a más raros):
   ```dart
   Prize('beanie', Rarity.n, PrizeSlot.head, ['red', 'blue', 'cream']),
   ```
   Si va en dos partes, con `front: true`. La rareza ∞ es `Rarity.mu`.
7. **Colócalo** en `_places` de `tama_outfit.dart` con la clave del `id` (§6).
8. **Pruébalo puesto**:
   ```sh
   flutter test test/prizes_test.dart          # catálogo = manifiesto = SVG
   flutter test test/prize_preview_test.dart   # hoja g9-premios.png
   ```
   Mira la hoja con los criterios de §7. Si algo falla, casi siempre es la
   colocación (§6), no el dibujo. La hoja es grande (una fila por premio en
   dos columnas): recórtala para mirar solo las filas nuevas, p. ej.
   `magick build/screenshots/g9-premios.png -crop 920x150+940+0 fila.png`.
9. **Ponle nombre** en `prizeName` de `lib/l10n/app_es.arb` y `app_en.arb`:
   un caso más del `select`, con la clave entera (`cap_red{gorra roja}`). Que
   no pase de **15 letras**, o no cabe en la ficha. Luego `flutter gen-l10n`.
   `test/prizes_test.dart` avisa si falta alguno.
10. **Dáselo a las reglas**: `gacha/turn` solo acepta un premio de la rareza
    de la bola, y las reglas no leen el catálogo de Dart. Ejecuta
    `flutter test test/prize_rules_test.dart`: si falla, imprime la línea
    que hay que cambiar en `database.rules.json` (una por rareza y por
    categoría). Luego `./tool/test_rules.sh` y, cuando toque, desplegar.
11. **Marca** el premio en `docs/PREMIOS.md`.

En el editor y en el pinball sale solo: las pestañas «gorros» y «accesorios»
leen el catálogo (en silueta si no se tiene), cada ficha lleva el nombre y el
fondo del color de su rareza (`RarityArt` en `gacha_art.dart`), y el pinball
lo sortea con los demás de su categoría y rareza.

---

## 3. Sitios

Cada premio va en un `PrizeSlot`. Un Tama lleva un gorro y hasta 3
accesorios, **uno por sitio**: uno nuevo sustituye al que ocupe el suyo.

| Sitio | Qué va | Capa al pintar |
|---|---|---|
| `head` | Gorros (el único de la categoría `hats`) | Encima de la cara |
| `back` | Alas, capa, mochila | Lo primero, detrás del cuerpo y las orejas |
| `waist` | El flotador | Detrás del cuerpo (y su mitad de delante, delante) |
| `aura` | Las hadas | Detrás del cuerpo (y las de delante, delante) |
| `feet` | Zapatillas: **quitan los pies** del Tama | Sobre el cuerpo, antes de la cara |
| `eyes` | Gafas, antifaces | Sobre la cara |
| `nose` | Narices, tiritas | Sobre la cara |
| `neck` | Pajarita, bufanda, collar | Sobre la cara |
| `right` | Bebidas en el suelo, lo que empuña (espada, pico, micro) y el cursor | Lo último |
| `left` | Lo que sujeta (globo, taco, farolillo, abanico, kendama) y el mando | Lo último |

Las piernecitas (pies variante 2) no se quitan: las zapatillas las calzan. El
gorrito del cumpleaños solo sale si no lleva gorro.

**Premios en dos partes.** Lo que rodea el cuerpo (correas de la mochila,
flotador, hadas) necesita una parte detrás y otra delante. La plantilla
principal es la de detrás y `<plantilla>_front.svg`, con **el mismo
viewBox**, la de delante; en el catálogo lleva `front: true`. Las dos usan la
misma caja. La parte de delante se pinta justo después del cuerpo y los pies,
antes de la cara, así que no debe pasar por encima de ojos ni boca. Hoy solo
se pinta la parte de delante de los sitios `back`, `waist` y `aura`.

**Sitio nuevo**: añádelo a `PrizeSlot`, ponlo en su capa en `_paintUnit` de
`tama_painter.dart` (y en la llamada con `front: true` si puede ir en dos
partes) y, si se ve mejor de cerca, dale encuadre en `_outfitChips` del
creador. Las claves guardadas no llevan el sitio, así que no hay que tocar
las reglas.

---

## 4. El lienzo de cada sitio

El SVG no se dibuja en coordenadas del Tama: cada sitio tiene sus **puntos de
referencia** en el `viewBox`, y la colocación (§6) los lleva a su sitio en el
Tama. Copia la plantilla más parecida y respeta sus puntos.

| Plantilla | viewBox | Puntos de referencia |
|---|---|---|
| `cap.svg` | 100×100 | Borde apoyado en y=70, de x=18 a 82 |
| `hard_hat.svg`, `frog_hat.svg`, `nightcap.svg` | 100×100 | Borde en y=72, de x=16 a 84 |
| `kitsune.svg`, `viking.svg` | 100×100 | Borde en y=70, de x=18 a 82 (el vikingo, de 20 a 80) |
| `kabuto.svg` | 100×100 | Borde en y=72, de x=18 a 82 |
| `top_hat.svg` | 100×100 | Ala en y=86, copa de x=20 a 80 |
| `chef_hat.svg` | 100×100 | Banda en y=76, de x=22 a 78 |
| `witch_hat.svg`, `wizard_hat.svg` | 100×100 | Copa en y=82, de x=24 a 76; el ala sobresale |
| `sombrero.svg` | 120×70 | Copa en y=56, de x=40 a 80; el ala sobresale mucho |
| `flower_crown.svg` | 100×44 | Apoya en y=30, de x=12 a 88 |
| `devil_horns.svg` | 100×50 | Nacen en y=44, de x=14 a 86 |
| `crown_rgb.svg` | 100×72 | Como la corona |
| `leaf.svg` | 60×60 | El tallo nace en (30, 57) |
| `bow.svg` | 80×50 | El nudo en (40, 26) |
| `halo*.svg` | 80×36 | Centro en (40, 18) |
| `rainbow_cloud.svg` | 100×64 | La base de la nube en y=60 |
| `gamer_headset.svg` | 100×80 | Como los auriculares |
| `cat_headset*.svg` | 100×84 | Cascos en y=56 y arco en y=10: todo 4 más abajo para que quepan las orejas |
| `afro.svg` | 100×100 | Nacimiento del pelo en y=74, de x=20 a 80 |
| `beanie.svg` | 100×100 | Vuelta apoyada en y=72, de x=16 a 84 |
| `beret.svg` | 100×60 | Ribete en y=48, de x=21 a 79 |
| `crown.svg` | 100×72 | Aro en y=62, de x=16 a 84 |
| `hachimaki.svg` | 120×44 | Cinta de x=10 a 110 (el ancho de la frente), centro en y=22 |
| `headphones.svg` | 100×80 | Cascos en y=52; cabeza de x=14 a 86; arco arriba en y=6 |
| `hood.svg` | 120×100 | Abertura de x=12 a 108; frente en y=20; tela hasta y=76 |
| `glasses.svg`, `shutter_shades.svg`, `rgb_shades.svg` | 100×40 | Ojos en (35, 20) y (65, 20) |
| `mask_a.svg` … `mask_d.svg` | 100×60 | Ojos en (35, 30) y (65, 30) |
| `groucho.svg` | 100×70 | Ojos en (35, 22) y (65, 22); boca hacia y=58 |
| `clown_nose.svg` | 40×40 | Bola centrada, radio 16 |
| `bandage.svg` | 60×30 | Centrada |
| `bowtie.svg` | 60×34 | Centrada |
| `scarf.svg` | 70×46 | Vuelta de x=5 a 65, centro en y=16; las puntas cuelgan debajo |
| `dollar_chain.svg` | 80×52 | La cadena sale de (4, 4) y (76, 4); medallón en (40, 35) |
| `sneaker.svg` | 60×34 | **Pie derecho**; la suela pisa en y=32. El izquierdo es el mismo en espejo |
| `bottle_*.svg`, `energy_can.svg` | 30×70 | De pie; la base pisa en y=68 |
| `boba.svg` | 36×70 | De pie; la base pisa en y=68 |
| `pickaxe.svg`, `sword.svg` | 72×72 | Píxeles de 4; el mango, abajo a la izquierda, en (12, 60) y (12, 56) |
| `microphone.svg` | 44×64 | Mango en (8, 60) |
| `cursor*.svg` | 50×60 | La punta en (12, 12) |
| `taco.svg` | 68×54 | Se sujeta por (60, 38) |
| `balloon.svg` | 50×100 | El hilo acaba en (46, 96) |
| `uchiwa_*.svg` | 44×64 | Mango en (36, 60) |
| `lantern.svg` | 50×80 | La varita acaba en (46, 72) |
| `fish_bag.svg` | 44×64 | El asa se coge por (38, 5) |
| `kendama.svg` | 50×70 | Mango en (36, 67) |
| `controller.svg` | 72×52 | El lado de x=70, a y=30, va pegado al costado |
| `angel_wings.svg`, `rgb_wings.svg`, `fairies*.svg` | 120×100 | Cuerpo de x=30 a 90; anclaje en (60, 50) |
| `randoseru*.svg`, `cape.svg` | 120×100 | El cuerpo entero es (30..90, 20..90) |
| `swim_ring*.svg` | 120×60 | Centro en (60, 30); el agujero va de x=26 a 94 |

Lo que va a un lado se dibuja ya en su lado: lo de la derecha tiene el punto
de agarre a la izquierda del dibujo y lo de la izquierda, a la derecha.

Deja **aire dentro del viewBox** para el filo y los destellos: lo que se sale
se corta. **Nada de coordenadas negativas ni viewBox que no empiece en 0**: si
algo no cabe, agranda el lienzo y mueve el dibujo con un `<g transform=...>`.

---

## 5. Kit de estilo

Todo tiene que parecer de la misma consola: plástico lacado como los iconos de
la 3DS (ver `paintPlastic` en `channel_art.dart`).

**Huecos de color.** Por cada color con nombre (`main`, `pom`, `gem2`…):

| Hueco | Qué es | Dónde se usa |
|---|---|---|
| `{main.light}` | Aclarado hacia el blanco | Arriba del degradado |
| `{main}` | El color | Centro del degradado |
| `{main.deep}` | Oscurecido hacia el azul noche | Abajo del degradado, zonas en sombra |
| `{main.edge}` | Mucho más oscuro, del mismo tono | **El filo**. Nunca negro |

**Receta de una pieza:**

1. Relleno con degradado vertical: `light` a 0, `main` a 0,55 y `deep` a 1.
2. Filo con `stroke="{main.edge}"` de 1,5–2 y `stroke-linejoin="round"`.
3. Brillo: una forma blanca en el tercio de arriba, del lado izquierdo (la
   luz viene de arriba a la izquierda), con degradado de opacidad 0,7 → 0.
4. Detalles (costuras, pliegues, rizos) con el color del filo y opacidad
   0,3–0,45.
5. Un detalle con vida: la estrella de la gorra, las lunares de la pajarita,
   las burbujas de la cola.

**Normas:**

- **Nunca negro puro.** Lo «negro» es azul noche con brillo (`#2B3444` o
  `#3A4455`).
- **Formas grandes y redondeadas** que se lean a 24 px: en la ficha del editor
  el Tama entero mide unos 60 px y el gorro, la mitad.
- **Los ojos se tienen que ver**: gafas con cristal claro
  (`fill-opacity=".22"`), antifaces con agujeros (`fill-rule="evenodd"`) y
  contraventanas con rendijas.
- **Filo solo por fuera en formas hechas de círculos** (afro, pompón): primero
  todos los círculos con el filo de trazo y relleno, y luego todos otra vez
  solo con relleno encima. Si el degradado tiene que ser uno solo para todos,
  usa `gradientUnits="userSpaceOnUse"`.
- **Simetría**: dibuja un lado en un `<g id="...">` y el otro con
  `<use href="#..." transform="matrix(-1 0 0 1 ANCHO 0)"/>`.
- **Estilo de píxeles** (pico y espada, guiño a los juegos de bloques): una
  cuadrícula de 16×16 con `rect` de 4 unidades (4,3 de ancho, para que no
  queden rayas entre ellos) y un píxel de filo alrededor. Es a propósito la
  excepción al plástico; no lo uses para otra cosa.
- **Diseños propios**: nada de logos ni marcas. La cola azul lleva los colores,
  no el logo; la lata lleva un rayo, no unas garras.

**Escalera de rareza:**

| Rareza | Cómo se nota |
|---|---|
| N | Una forma sencilla, un color |
| R | Dos colores y algún detalle |
| SR | Más elaborado: metal, cristal, tela con dobladillo |
| SSR | Un destello blanco de cuatro puntas (animado cuando se programe) |
| UR | Efecto vivo: halo suave detrás y destellos de color |
| ∞ | Arcoíris (RGB): hoy un degradado fijo con `gradientUnits="userSpaceOnUse"`; animado cuando se programe |

**Lo que `flutter_svg` no pinta**, así que no se usa: filtros (`blur`,
sombras), `mask`, `<style>` y CSS, texto. Sí funcionan los degradados
lineales y radiales, `clipPath`, `use`, `transform` y `evenodd`.

---

## 6. Colocarlo

En `_places` de `tama_outfit.dart`, cada `id` devuelve la caja (o las cajas)
que ocupa en el lienzo de 100×100 del Tama. Se pinta dentro de la
transformación del Tama, así que salta y se inclina con él solo.

**Ayudas que ya existen:**

- **`_hat(...)`, para gorros que apoyan en la cabeza.** Escala al ancho de la
  cabeza a la altura del borde y no deja que lo que sube pase de `tall`
  cuerpos de alto:
  ```dart
  'beanie': _hat(view: const Size(100, 100), band: 72, left: 16, right: 84,
                 frac: .18, tall: .6),
  ```
  - `band`, `left` y `right` son los puntos de §4.
  - `frac` es a qué altura del cuerpo apoya (0 es la coronilla). Nunca baja de
    los ojos (`_hairline`).
  - `fit` es el ancho respecto a la cabeza: 1,04 cubre la cabeza y 0,72 queda
    pequeño encima, como la corona.
  - Si no cabe en el lienzo por arriba, lo encoge solo: ya no se corta.
- **`_headset(view, cups)`, para auriculares.** Los cascos a los lados de la
  cabeza, a la altura `cups` del SVG, y el arco por encima.
- **`_floating(view, base, gap, size, min, max)`, para lo que flota encima**
  (aureola, nube). El punto `base` queda `gap` por encima de la coronilla.
- **`_overEyes(view, eyeY, hole)`, para lo que va en los ojos.** Se estira a
  lo ancho con la separación de los ojos y a lo alto con su tamaño, así los
  agujeros caen encima.
- **`_nose(look, body, t)`.** Punto entre los ojos y la boca (`t` = 0,5 es el
  medio).
- **`_neck(look, body, below)`.** La altura del cuello: `below` por debajo de
  la boca, pero dentro del cuerpo.
- **`_standing(view, base)`, para lo que está de pie en el suelo a su
  derecha** (bebidas). Mide lo que la botella.
- **`_held(view, grip, right: ..., at, size, min, max)`, para lo que sujeta.**
  Pega el punto `grip` del SVG a su costado, a `at` de su alto, y le da
  `size` cuerpos de alto entre `min` y `max`:
  ```dart
  'kendama': _held(const Size(50, 70), const Offset(36, 67), right: false,
                   at: .7, size: 1, min: 32, max: 40),
  ```
  Sube `min` si en la hoja sale pequeño: en los Tamas bajitos manda el mínimo.
- **`_aroundBody(view, inView)`, para lo que abraza el cuerpo entero**
  (mochila, capa). `inView` es donde va el cuerpo en el SVG, y se estira a lo
  ancho y a lo alto para que caiga justo encima.
- **`_wings`**, para lo que va como las alas (alas, hadas), con tope al ancho.
- **`TamaFace.of(look, body)`.** Da `eyeY`, `eyeDx` (media separación), `eyeR`,
  `mouthY` y el centro de la cara.
- **`body.bounds`** es el cuerpo y **`body.halfWidthAt(y)`** el medio ancho a
  una altura. `TamaPainter.floor` (90) es el suelo.

Para algo con dos piezas (las zapatillas) se devuelven dos cajas; la segunda
con `flip: true` va en espejo. El SVG se estira a la caja entera, así que
**se puede escalar distinto a lo ancho y a lo alto**, pero limítalo (con
`clamp`) para que no se deforme mucho. Varios premios pueden compartir
colocación (`'rgb_wings': _wings`).

---

## 7. Mirar la hoja de prueba

La hoja pone cada premio en 6 Tamas elegidos para romper cosas: redondo con
orejas de gato, alubia chata y ancha con orejas de conejo, huevo con antenas y
ojos grandes, pera alta con los ojos arriba, mochi muy ancho con piernecitas y
ojos muy separados, y gota estrecha y alta con ojos pequeños.

Busca:

- ¿**Tapa los ojos** en el Tama chato (el naranja)?
- ¿Las **orejas y antenas** asoman bien por los lados?
- ¿Los **agujeros** caen sobre los ojos grandes (el verde)?
- ¿Se **sale del lienzo** en el mochi ancho (el rosa)?
- ¿Se **lee** a tamaño de ficha, o es un borrón?
- ¿Parece lo que es? (La primera gorra parecía un casco de obra: la visera
  daba toda la vuelta.)

Fallos que ya han salido y su arreglo:

| Fallo | Arreglo |
|---|---|
| Un gorro tapa los ojos a un Tama chato | Bajar `tall`, o subir `frac` |
| Lo de los ojos se desalinea con ojos grandes | Escalar a lo alto con `eyeR`, no solo con la separación |
| La capucha se alarga hasta el suelo en un Tama chato | Limitar también por el alto del cuerpo (`math.min` de las dos escalas) |
| Unas alas se salen en un cuerpo muy ancho | Tope al ancho (`math.min(r.width, 58)`) |
| Una pieza pequeña no se ve (nariz, zapatillas) | Tamaño mínimo, o más grande respecto al cuerpo |
| Un color sale negro | Hueco sin rellenar: el generador ya lo detecta |
| La mochila parece una maleta | La caja de detrás, poco más ancha que el cuerpo: que solo asomen las esquinas |
| Algo de un lado queda tapado por el cuerpo (el cursor) | Pegarlo a `halfWidthAt(y)`, no a una fracción del ancho |
| Un dibujo girado se corta | Agrandar el viewBox y mover el dibujo con `translate` |
| Un gorro alto se corta por arriba (el afro) | Ya no pasa: `_hat` y `_floating` lo encogen. Si el dibujo es muy alto, bájalo |
| Un brillo de la UR tapa la cara (orejas de gato) | Los halos, solo en lo que va a un lado o detrás; en la cabeza, destellos sueltos |
| Algo parece otra cosa (el taco parecía un cuenco) | El detalle que lo define: la otra cara de la tortilla por detrás del relleno |

Suele bastar con una o dos vueltas por premio. Cuando lo tengas, pasa
`flutter analyze` y `flutter test` enteros.
