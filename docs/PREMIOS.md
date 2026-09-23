# Premios del gacha 0.6.0: gorros y accesorios

Checklist de trabajo. Los fondos y las músicas van aparte, más adelante.
Cómo se hace uno nuevo: [`CREAR_PREMIOS.md`](CREAR_PREMIOS.md).

## Decisiones tomadas

- [x] Arte en SVG en `assets/prizes/`, pintado con `flutter_svg` (dependencia añadida).
- [x] Cada diseño es **una plantilla** en `tool/prizes/templates/` con los colores
      como huecos; `python3 tool/gen_prizes.py` saca una variante por color
      según `tool/prizes/prizes.json`. Cada variante es un premio distinto.
- [x] Un Tama lleva **1 gorro y hasta 3 accesorios**, ordenados por capa
      (detrás del cuerpo, sobre el cuerpo, cara, delante).
- [x] Lo que lleva puesto es **del Tama** y se guarda en `/tamas`: los amigos lo
      ven en directo y se va con él si se transfiere.
- [x] Las piezas «negras» van en azul noche con brillo, nunca en negro puro.
- [x] La máscara estilo Persona y el pico estilo Minecraft son diseños propios,
      no copias.
- [x] Tirita en la nariz: **SR**. Flotador: **1 variante, a rayas de colores**.

## Piloto (3 premios)

- [x] Kit de estilo: degradado de plástico (claro → base → oscuro), brillo
      blanco arriba y filo del mismo tono oscurecido, con las mismas mezclas
      que `paintPlastic`.
- [x] Gorra de béisbol (N): roja, azul, verde y amarilla.
- [x] Antifaz A (SR): blanco con ribete rojo.
- [x] Alas angelicales (UR): blancas y negras, con halo y destellos.
- [x] Hoja de prueba puesta en 6 Tamas distintos: `flutter test test/prize_preview_test.dart`
      → `build/screenshots/g9-premios.png`.
- [x] Visto bueno al piloto: seguir con el 25 % de lo que queda.

## Tanda 1 (25 % de lo que quedaba: 15 diseños)

- [x] Gorros: afro, gorro de lana, hachimaki, auriculares, boina, capucha y corona.
- [x] Accesorios: gafas, pajarita, zapatillas, gafas con bigote, nariz de payaso,
      botella, tirita y gafas de contraventana.
- [x] Colocaciones nuevas probadas en la hoja: frente, orejas, capucha
      alrededor del cuerpo, nariz, cuello, pies (sustituyen a los pies) y a un
      lado.
- [x] El generador para si queda un hueco de color sin rellenar (salía negro).
- [x] Visto bueno a la tanda 1.

## Tanda 2: todos los accesorios que faltaban

- [x] Nariz de payaso roja; botella de cola azul (con los colores, sin logo).
- [x] Nuevos: lata de bebida energética (negra con verde claro, blanca con
      gris, negra con rojo), té de burbujas (rosa, verde, marrón) y taco.
- [x] El resto de la lista de accesorios, ∞ incluidos (con el arcoíris fijo;
      animarlo va con los efectos).
- [x] Dos sitios nuevos: `waist` (flotador) y `aura` (hadas).
- [x] Premios en dos partes, detrás y delante del cuerpo: correas de la
      mochila, flotador y hadas (`<clave>_front.svg`, `front: true`).
- [x] Los antifaces son un solo premio con cuatro dibujos: `mask_a` … `mask_d`
      (antes `mask_a_a`; no se había guardado en ningún sitio).
- [x] Visto bueno a la tanda 2.

## Tanda 3: todos los gorros y los nombres

- [x] Los 22 gorros que faltaban, con un **sombrero mexicano** (SR: de paja y
      charro) que no estaba en la lista.
- [x] El afro, más bajo: ya no se corta por arriba. Además, ningún gorro se
      sale del lienzo por arriba: `_hat` y `_floating` lo encogen si no cabe.
- [x] Las fichas del editor enseñan el **nombre** del premio (`prizeName` en
      los `.arb`) y el fondo va con el color de su rareza (`RarityArt`).
- [x] Coronillas: se quedan como estaban (las orejas asoman por los lados y
      las antenas por encima).
- [ ] **Tu visto bueno a la tanda 3** ← aquí estamos.

## Premios en el editor de Tamas

- [x] Catálogo en Dart: `lib/backend/prizes.dart` (rareza y sitio de cada
      premio). `test/prizes_test.dart` comprueba que cuadra con
      `tool/prizes/prizes.json` y con los SVG.
- [x] Lo que lleva puesto va en el aspecto del Tama (`look.hat` y `look.acc`).
      Solo se escribe si lleva algo, así que los Tamas sin premios se guardan
      igual que antes.
- [x] Un sitio por accesorio (cabeza, espalda, cintura, alrededor, ojos, nariz, cuello, pies,
      derecha e izquierda): uno nuevo sustituye al de su sitio, y como mucho
      hay 3.
- [x] `TamaPainter` los pinta dentro de su transformación, así que saltan y se
      inclinan con el Tama y salen en todas partes (habitación, fichas, perfil).
      Las zapatillas quitan los pies; el gorrito del cumpleaños solo sale si no
      lleva gorro.
- [x] Editor: pestañas «gorros» y «accesorios». Lo que no se tiene sale en
      silueta con «???» y no se puede elegir.
- [x] Reglas locales: `look/hat` y `look/acc`, con sus tests.
- [x] Reglas de `look/hat` y `look/acc` desplegadas (2026-09-23).
- [x] Nombres de los premios en las fichas, con el fondo del color de su rareza.
- [x] Solo los premios ganados: colección en `/users/{uid}/prizes/{clave}`
      (número de copias). Las reglas de `look/hat` y `look/acc/{a|b|c}` exigen
      tenerlo, salvo que ya estuviera puesto (un Tama transferido conserva lo
      que lleva, pero el nuevo dueño no puede volver a ponérselo si se lo quita).
- [x] `look/acc` pasa a tres campos `{a, b, c}`; se sigue leyendo el formato
      antiguo con comas. **Reglas sin desplegar.**

## El pinball reparte los premios

- [x] Cada bola capturada sortea un premio de su categoría y rareza, con la
      misma probabilidad para cada color. Se guarda como un turno
      (`gacha/turn`) que resta la bola, suma `play/done` y la copia.
- [x] Los repetidos se acumulan (sin premio extra).
- [x] El Catálogo se va del gacha al pinball: se pide categoría y rareza
      (hasta UR), cuenta bolas jugadas y en la 70 llega una bola dirigida que
      da un premio que aún no se tenga (si están todos, repetido).
- [x] Las reglas saben qué premio es de qué rareza y categoría;
      `test/prize_rules_test.dart` avisa si no cuadran con el catálogo.

## Pendiente de decidir

- [ ] Regla de los accesorios de lado. Hoy es «uno por lado», porque cada lado
      es un sitio: a la derecha bebidas, espada, pico, micro y cursor; a la
      izquierda mando, globo, taco, abanico, farolillo, bolsita y kendama.
      Así se puede llevar la bebida y el taco a la vez. Confírmalo.
- [ ] Rarezas que he puesto yo: lata, té de burbujas y taco en **R**; bufanda
      y mochila en **N**; globo y abanico en **R**; pico, espada, flotador,
      farolillo, bolsita y capa en **SR**; collar, micro y kendama en **SSR**;
      sombrero mexicano en **SR**.
- [ ] ¿Entran los 57 diseños en la 0.6.0 o dejamos una parte para una
      actualización posterior?

## Pendiente de dibujar

Entre paréntesis, las variantes. ✓ = dibujado y probado en la hoja.

**Accesorios: terminados** (31 premios, 66 contando colores).
**Gorros: terminados** (30 premios, 70 contando colores).

### Gorros

Todos dibujados y probados en la hoja ✓.

- **N**: afro, gorra (roja, azul, verde, amarilla), gorro de lana (rojo, azul,
  crema), hachimaki (blanca, roja), brote (verde, otoñal), lazo (rosa, azul,
  amarillo).
- **R**: auriculares (blancos, celestes), boina (roja, negra, verde),
  chistera (negra, blanca), casco de obra (amarillo, naranja), gorro de rana
  (verde, rosa), gorro de chef.
- **SR**: capucha (negra, roja, verde), sombrero de bruja (morado, negro),
  gorro de dormir (azul noche, rosa), corona de flores (sakura, girasol,
  lavanda), máscara de kitsune ladeada (blanca, roja), casco vikingo,
  sombrero mexicano (paja, charro).
- **SSR**: auriculares gamer (negros, azules, rosas), corona (oro, plata),
  kabuto (rojo, negro), sombrero de mago (azul, morado).
- **UR**: auriculares gamer con orejas de gato (negros, azules, rosas,
  blancos), aureola, cuernos de diablillo (rojos, negros), nube con arcoíris.
- **∞**: auriculares con orejas de gato RGB (negros, azules, rosas, blancos),
  aureola RGB, corona RGB.

### Accesorios

Todos dibujados y probados en la hoja ✓. Entre paréntesis, el sitio.

- **N**: gafas (ojos), pajarita (cuello), zapatillas (pies, quitan los pies),
  bufanda (cuello), mochila randoseru (espalda, correas delante).
- **R**: gafas con bigote (ojos), nariz de payaso roja, negra y verde (nariz),
  botella de agua, cola y cola azul (derecha), lata energética (derecha), té
  de burbujas (derecha), taco (izquierda), globo (izquierda), abanico uchiwa
  con sol y con pez (izquierda).
- **SR**: antifaces A «el ladrón», B «la gata», C «la mariposa» y D «el
  cuervo» (ojos), tirita (nariz), pico y espada de píxeles (derecha),
  flotador (cintura), farolillo (izquierda), bolsita con pez (izquierda), capa
  (espalda).
- **SSR**: gafas de contraventana (ojos), collar del dólar (cuello), micro
  (derecha), kendama (izquierda).
- **UR**: cursor blanco, negro e invertido (derecha), mando (izquierda), hadas
  (alrededor), alas angelicales (espalda).
- **∞**: gafas de contraventana RGB (ojos), alas RGB (espalda).

## Pendiente de programar (cuando estén los dibujos)

- [ ] Límites en Tamas extremos: con los ojos muy separados, los antifaces,
      las gafas y el bigote quedan más anchos que la cara.
- [x] Colocación dentro de `TamaPainter` (`lib/ui/tama/tama_outfit.dart`).
- [ ] Efectos animados de SSR, UR y ∞ en Dart (destello, halo vivo, arcoíris
      que corre; hoy las ∞ tienen el arcoíris quieto).
- [x] Catálogo de premios en Dart (id, categoría, rareza, capa, variantes) y
      reparto del pinball por rareza.
- [x] Inventario de la cuenta, comprobado en las reglas de `look`.
- [x] Pantalla para ponérselos: dos pestañas en el creador.
- [x] Textos en `app_es.arb` y `app_en.arb` (nombres de todos los premios).
- [ ] Galería en `test/art_gallery_test.dart` y comprobar que se leen a 24 px.
- [x] `flutter analyze` y `flutter test` enteros (tras la tanda 2).
