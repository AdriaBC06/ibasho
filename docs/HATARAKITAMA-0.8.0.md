# Hatarakitama 0.8.0: plan

Plan acordado con el usuario el 2026-09-30. Todo sale en **una sola versión,
la 0.8.0**, pero se hace por fases que se prueban en el móvil una a una.

## Decisiones del usuario

- **Producción en cadena**: basta con **reanudar sola** la tarea cuando vuelven
  los materiales, en vivo y offline. Sin colas ni líneas configurables.
- **Expediciones**: **mapa con rutas** y **encargos del pueblo**. Los encargos
  pueden dar tickets del gacha: **uno al día** como mucho.
- **Ginmon**: se gastan en **construir el pueblo**, en la **tienda del pueblo**,
  en **servicios de viaje** y en **casas para los Tamas** (al estilo de Animal
  Crossing, pero sin pasarse).
- **Casas**: dan **descanso y ánimo**, se amueblan con **muebles fabricados** y
  se pueden **visitar las de los amigos** (su pueblo, sus Tamas, etc.).
- **Oficios nuevos**: cerámica, tintes, construcción, escritura, estudio,
  brebajes y magia. Los cebos y abonos son consumibles. Se acepta la conexión
  propuesta (ver abajo).
- **Lonja**: un edificio del pueblo que **cada día sube el precio de venta** de
  unas cosas **y baja el de otras**, para que no siempre compense lo mismo.
- **Maña a la vista**: explicar en algún sitio (la ayuda, por ejemplo) en qué
  oficios es mejor cada personalidad, para poder crear el Tama adecuado.

## Fase 0: los Tamas vuelven solos al trabajo (hecha)

**Causa**: `HState.advance` saca de la cola de eventos al Tama al que le faltan
materiales (`stalled = true`), y al empezar el tramo solo coge los que
`!stalled`. Nunca se vuelve a mirar si ya hay material, así que el Tama sigue
parado hasta que alguien lo reasigna.

**Arreglo** (en el motor, así vale igual en vivo que offline):
- Al empezar `advance`, los parados que ya tienen material vuelven a la cola
  (sirve si llega material vendiendo, comprando, por un encargo o de viaje).
- Dentro de la simulación, cada vez que una tarea **da** algo, se repasan los
  parados: el que ya puede empieza en ese instante (`nextAt = t + duración`).
  Así, un Tama talando bambú mantiene al que hace cestas funcionando, aunque
  el cestero vaya más deprisa: trabaja a tirones, al ritmo del bambú.
- El regreso de una expedición también pasa a ser un evento **en su hora**
  dentro de la cola (ahora se aplica al final), para que su botín despierte a
  los parados en el momento justo.
- Mientras espera, el Tama pone «esperando caña de bambú» en vez de «parado»,
  y el resumen de «mientras no estabas» deja de contarlo como parado si
  volvió a trabajar.
- Pruebas en `test/hataraki_test.dart`: cadena de tala → cestas de 12 h
  offline y en vivo (tramos de 1 s), dos consumidores del mismo material y
  reanudar al vender/comprar.

## Fase 1: oficios nuevos y consumibles (hecha)

Hecho así (lo que cambia respecto a lo de abajo):
- Estudio empieza con **cuadernos** (escritura 5, solo papel) para poder
  subirlo desde el nivel 0.
- La **tetera** es pasiva: con una en el almacén, el té dura 45 min.
- La **maceta** se queda como material (invernadero y muebles, fases 2 y 5);
  lo de «el huerto da más» ya lo hacen los abonos.
- **Magia** hace runas (`HItemKind.rune`, con fuerza y a veces un efecto)
  que se eligen al salir (fase 3). Las pociones (`potion`) y los mapas
  (`map`) llevan `effect`: `heal`, `sight`, `luck`, `haste`, `reveal`.
- Ropa teñida (tintes): happi añil (río, costa), capa carmesí (montaña,
  onsen), kimono dorado (cielo, luna).
- Consumibles: `HWorker.boost` (se guarda en `workers/$slot/boost`).
  Cebo: +15/35 % de sacar doble. Abono: +1/+2 de cosecha. Mecha: ×2/×4 de
  gemas.
- Arte provisional pero propio en `hataraki_art_crafts.dart` (`part`).


De 13 a **20 oficios**. Nivel total máximo: 1980. Las ranuras siguen saliendo
del nivel total; se añaden umbrales (p. ej. 800 y 1100) hasta **8 ranuras**, y
las reglas de `workers/$slot` pasan de `[0-5]` a `[0-7]`.

| Oficio | Sale de / gasta | Para qué sirve |
| --- | --- | --- |
| **Cerámica** | arcilla (minería, río) + leña | cuencos, **frascos** (brebajes), **teteras** (el té dura más), **macetas** (el huerto da más), tejas y ladrillos (construcción), jarrones (muebles) |
| **Tintes** | flores de recolecta + un cultivo nuevo (añil) | tintes → telas y ropa teñidas, con bonos según el sitio (azul: río y costa…) y muebles (cortinas, alfombras) |
| **Construcción** | tablones, lingotes, tejas, ladrillos | vigas, muros, tejados… que se gastan al mejorar los edificios y levantar casas |
| **Escritura** | papel (madera) + tinta (hollín del horno o tinte negro) | pergaminos, **libros** (para estudio), **mapas** (revelan casillas del viaje) y carteles (muebles) |
| **Estudio** | lee libros | solo da experiencia, como agilidad; cada nivel da un 0,1 % más de experiencia en todo |
| **Brebajes** | hierbas (recolecta, huerto) + agua de manantial + frasco | pociones de viaje: curar (pasar un peligro), vista (revelar niebla), suerte (más tesoro), prisa (menos tiempo) |
| **Magia** | polvo de luna, nubes, gemas | encantar equipo y amuletos (más fuerza o un efecto en el mapa) y farolillos mágicos (muebles) |

**Cebos, abonos y mechas**: consumibles que se ponen en una ranura de trabajo
(uno por Tama). Se gasta uno por vez y mejora esa tarea: el cebo da más
probabilidad de doble en la pesca, el abono da una cosecha más en el huerto y
la mecha da más gemas en la minería. Salen de oficios que ya existen
(recolecta, huerto con compost, forja). Si se acaban, el Tama **sigue sin
ellos**, no se para.

**Maña**: se reparten los 20 oficios entre las cinco personalidades (unos 4
por cabeza). Al elegir personalidad se ve en qué oficios es buena (ver fase 7).

## Fase 2: el pueblo, la tienda y la lonja (hecha)

Hecho así (lo que cambia respecto a lo de abajo):
- Nueve edificios (`hataraki_town.dart`): taller, horno, muelle, invernadero
  (dos edificios aparte), biblioteca, torre, posada, tienda y lonja. El
  **tablón** llega con los encargos (fase 4) y la **segunda expedición** de la
  posada a nivel 5 con el mapa (fase 3).
- Coste por nivel igual para todos (vigas → armazones → muros y tejados →
  tejados y shoji → pilares y shachihoko, con construcción 0/20/40/60/90) por
  un multiplicador de ginmon (800 a 400 000) y, del nivel 2 en adelante, una
  pieza propia de cada edificio (ladrillos, macetas, cuadernos…).
- Efectos: taller +4 %/nivel en los 12 oficios que transforman; horno,
  muelle, invernadero y torre +5 %/nivel en el suyo; horno +10 % de hollín;
  biblioteca +10 % de experiencia de estudio; posada −8 % de comida y 4 Tamas
  a nivel 3. La biblioteca (1–4) abre mapas y libros buenos y la torre (1–4)
  las runas buenas (`hActionGates`).
- Tienda: 4 cosas con el nivel 1 y una más por nivel (hasta 8), a ×4, con
  existencias por día (`shop/day` y `shop/bought`). Los planos y muebles
  entrarán en la fase 5.
- Lonja: sube 1 oficio y 2 cosas por cada 3 (nivel + 1 subidas, de +25 a
  +100 %) y bajan 2 oficios (de −20 a −50 %, más suave con nivel); a nivel 3
  se ve la de mañana. Azar propio (Lehmer) para que salga igual también en la
  web. Día = `bonusDay`.
- Reglas: `town/$building` (1–5), `shop` y `expedition/tamas` hasta 4.
- Depuración: «+1 nivel a cada edificio» y «+100 000 ginmon».


El **pueblo** es una pestaña nueva con un mapa pequeño. Cada edificio tiene
niveles (1–5); mejorarlo pide **ginmon + piezas de construcción** y un nivel de
construcción.

| Edificio | Qué da por nivel |
| --- | --- |
| **Taller** | los oficios que transforman van más rápido |
| **Posada** | más Tamas por expedición (hasta 4) y, a nivel 5, **una segunda expedición a la vez** |
| **Biblioteca** | desbloquea libros y mapas mejores; más experiencia de estudio |
| **Horno** | cerámica más rápida y más hollín |
| **Torre** | desbloquea encantamientos mejores |
| **Muelle / invernadero** | pesca y huerto |
| **Tienda** | más huecos en la tienda del día |
| **Lonja** | ver abajo |
| **Tablón** | más encargos al día |

- **Tienda del pueblo**: 6 cosas al día (semillas, materiales básicos, cebos,
  tés, planos de muebles, algún mueble), la misma para todos ese día. Se
  compra a unas **4 veces lo que se vende**, así no sale a cuenta comprar para
  revender. Hay que tener hecho un **plano** para fabricar un mueble.
- **Lonja**: cada día, con la misma semilla para todos, **sube** el precio de
  venta de unas categorías u objetos (+25 % a +100 %) y **baja** el de otras
  (−20 % a −50 %). Dice «hoy se paga bien el pescado» o «hoy nadie quiere
  lingotes». **Cambio del usuario (2026-09-30)**: los precios del día valen
  para todos aunque no tengas lonja (6 cosas suben, 2 oficios bajan); la
  lonja solo los enseña: con más nivel, más de lo que sube, y a nivel 3 la de
  mañana.
  La ficha del objeto y «vender» enseñan el precio del día con una flecha.
- **Clasificación de riqueza**: sigue contando **lo ganado** (vender y
  encargos); gastar no resta.

## Fase 3: expediciones con mapa (hecha)

Hecho así (lo que cambia respecto a lo de abajo):
- `hataraki_map.dart`: de 4 a 6 columnas de 2–3 casillas (3 filas), unidas
  con la fila igual o una de al lado. Tipos: botín, recolecta rara, peligro,
  descanso y cofre; la **niebla** es una marca sobre cualquier casilla (no un
  tipo). La casilla de **encargo** llega con los encargos (fase 4).
- Todo lo que no es suerte se fija al salir (hora de cada casilla y peligros
  que no se pasan), así el viaje tiene hora de vuelta fija. Un peligro sin
  fuerza ni poción de cura tarda la mitad más y no da nada.
- Una **poción o mapa** y una **runa** por viaje, que se gastan al salir. La
  vista, los mapas y las runas de brújula/estelar quitan la niebla al
  elegirlos; el **guía** la quita todo el día en ese sitio. Porteador +50 %
  de botín, carro −25 % de tiempo, prisa −20 %.
- Dos viajes a la vez con la posada a nivel 5 (a sitios distintos).
- Reglas `expeditions/$i` (0–1) y `guides/$zone`, probadas en el emulador;
  `expedition` se sigue aceptando para la 0.7.0.


- Cada sitio es un **mapa de casillas en columnas** (unas 4–6 columnas con
  caminos que se cruzan, como Slay the Spire). Hay un mapa al día por sitio,
  el mismo para todos (se puede comentar con los amigos).
- Tipos de casilla: botín, recolecta rara, **peligro** (pide fuerza o una
  poción; si no, se pierde tiempo o botín), **descanso** (recupera, ahorra
  comida), **tesoro** (más probabilidad de ticket), **encargo** (el objeto que
  pide un encargo del tablón) y **niebla** (no se ve lo que hay hasta llegar;
  la revela un mapa de escritura, una poción de vista o un guía).
- **Antes de salir** se elige la ruta. El tiempo del viaje es la suma de sus
  casillas.
- **En vivo** se ve al grupo avanzar por el mapa, y cada casilla enseña lo
  que ha pasado al llegar: tener el canal abierto ya tiene algo que mirar.
  Offline se resuelve igual al volver, con cada casilla en su hora.
- **Volver ya** trae lo de las casillas que ya se han pasado, no nada.
- **Servicios de viaje** (en ginmon): **guía** (revela todo el mapa del día
  para ese sitio), **porteador** (más botín por casilla) y **carro** (un 25 %
  menos de tiempo).
- Las pociones y los encantamientos se eligen al salir, junto con la comida.
- Partida: `expedition` pasa a `expeditions/{0,1}` con `route` (casillas
  elegidas) y `done` (resueltas). Al leer, se acepta el formato viejo.

## Fase 4: encargos del pueblo (hecha)

Hecho así (lo que cambia respecto a lo de abajo):
- El **tablón** es un edificio más (el primero de la rejilla) que viene hecho
  a nivel 1: 3 encargos, 4 a nivel 2 y 5 a nivel 4, y +6 % de paga por
  nivel. Se entra como en la tienda. Los encargos se guardan al hacerse, así
  que subir de nivel a media jornada no los cambia.
- Piden cosas de oficios que ya se trabajan, en cantidad para 20–40 minutos
  (el grande, 2–3 cosas de 40–80 minutos) y pagan de 1,6 a 2,6 veces lo que
  valen, o lo que daría ese rato en el mejor trabajo si es más. Además, a
  veces experiencia o un material raro; los **planos de muebles** llegan con
  las casas (fase 5).
- La casilla de **encargo** está en todos los mapas (una) y da un
  **paquete**, que la mitad de los días pide el gran encargo.
- El ticket se cobra con `orderDay` como decía el plan; además, las reglas
  ya no dejan borrar `orderDay` ni `claimAt` al guardar la partida (si no,
  se podía volver a cobrar antes de tiempo).
- Cambiar un encargo cuesta un cuarto de lo que paga; el grande no se
  cambia.


- Un **tablón** con 3 encargos al día (4–5 con el tablón mejorado), sacados de
  la semilla del día y de la cuenta, y según tus niveles: «tráeme 3 plumas»,
  «20 cestas», «un jarrón teñido de azul».
- Pagan ginmon, materiales raros, planos de muebles o experiencia.
- Cada día hay un **gran encargo**, más largo y a veces con casillas del mapa,
  que paga **1 ticket gachaken**. En las reglas: `hataraki/orderDay` pasa al día
  de hoy (solo si era otro) y `tickets/gachaken` sube 1 en la misma
  escritura, igual que el canje de tesoros con `claimAt`.
- Con ginmon se puede **cambiar un encargo** una vez al día.

## Fase 5: casas y muebles (hecha)

Hecho así (lo que cambia respecto a lo de abajo):
- `hataraki_home.dart`: 29 muebles de cinco estilos, 1×1 a 2×2, con
  comodidad 1–4. 24 se fabrican en los seis oficios pedidos (tareas `fu_*`,
  que se ven ordenadas por nivel) y 5 solo se compran en la tienda. Cinco
  se hacen sin plano, para empezar; los demás piden **plano** (`plans`), que
  vende la tienda aparte de sus huecos (1 al día, 2 a nivel 3) o regala uno
  de cada cuatro encargos normales (nunca el grande).
- Casa: la primera cuesta 300 ginmon y 2 vigas; las siguientes suben hasta
  60 000 × (n − 3) con muros y tejados. Suelo y pared se eligen entre los
  cinco estilos y cuentan para que combine, pero no dan puntos.
- Comodidad: 50 % puntos de muebles (llena con 24), 25 % que combinen, 25 %
  del estilo favorito (tranquilo floral, juguetón marino, tímido elegante,
  descarado rústico, dormilón mágico). Con casa, el ánimo mínimo con el que
  trabaja es 0,25 + 0,55 × comodidad (hasta 0,8), solo en Hatarakitama, como
  se propuso (el usuario no dijo otra cosa).
- Las casas se entran desde la última casilla del pueblo, no desde la ficha
  del Tama. Girar un mueble que no cabe lo arrima arriba y a la izquierda.
- Reglas `houses/$tama` (suelo, pared, `items/0–35` con `x`,`y` 0–5 y `r`
  0–3), `plans/$item` y `orders/list/$i/plan`, probadas en el emulador (207).

- Cada Tama puede tener **su casa** (se construye con ginmon y piezas de
  construcción; la primera es barata). Una habitación en rejilla de 6×6 con
  suelo, pared y muebles.
- **Muebles**: objetos nuevos (`HItemKind.furniture`) de carpintería,
  cerámica, tintes, costura, escritura y magia, o comprados en la tienda. Cada
  uno lleva un **estilo** (rústico, marino, elegante, mágico, floral).
- **Comodidad**: sale de cuántos muebles hay, de lo bien que combinan y de si
  el estilo le gusta a su personalidad. Da **descanso**: sube el ánimo que
  cuenta **dentro de Hatarakitama** (el ánimo mínimo con el que trabaja), sin
  tocar el ánimo real del Tama en Ibasho. *Decisión mía, pendiente de
  confirmar.*
- Sin pasarse: una habitación por Tama, colocar y girar, sin paredes ni
  exterior editables.

## Fase 5b: pueblo pintado y posada (hecha)

- Decisión del usuario (2026-10-01): el pueblo pasa de rejilla a **mapa
  pintado**; las casas pasan a ser **habitaciones de la posada** (la que ya
  había), solo cambia cómo se ve: mismos datos, costes y reglas.
- Cada nivel añade un detalle a la parcela para que se note la evolución.
- En la fase 6, el mismo `_TownMap` en solo lectura sirve para ver el pueblo
  de un amigo.

## Fase 6: visitas (hecha)

- Desde la ficha de un amigo o de Hatarakitama: **visitar su pueblo**.
  Edificios y niveles, sus Tamas (con su aspecto), su casa por dentro, sus
  oficios y su riqueza. Solo mirar.
- Una lectura puntual (`read`), sin conexión nueva.
- Reglas: los amigos pueden leer `hataraki` (como `profile`). Hoy los amigos no
  leen `tamas`, así que la partida guarda una **ficha de visita**
  (`hataraki/visit`: aspecto de cada Tama, nombre, personalidad) y se
  actualiza al guardar. Así no hay que abrir `tamas` a los amigos.
- Hecho (2026-10-01): `HatarakiVisitScreen` (`hataraki_channel_visit.dart`)
  con el mapa en solo lectura, fichas sin costes, Tamas con lo que hacen y
  sus habitaciones, riqueza y mejores oficios. Se entra desde el perfil del
  amigo y con el botón de amigos del mapa. Reglas y pruebas (208 en el
  emulador), sin desplegar todavía.

## Fase 7: interfaz, arte, textos y cierre (hecha salvo el móvil)

- **Ayuda**: páginas nuevas (pueblo, lonja, mapa, encargos, casas) y la de
  **maña** pasa a ser una **tabla con dibujos**: cada personalidad con los
  iconos de sus oficios. La misma información sale al **crear un Tama**
  (debajo de la personalidad) y en la ficha del Tama dentro del canal.
- Arte: un dibujo por objeto nuevo (unos 100), escenas de los 7 oficios,
  edificios, casillas del mapa y muebles (`hataraki_art.dart`), según
  `docs/UI.md`.
- Textos es/en en mensajes `select`, `docs/HATARAKITAMA.md` y `CHANGELOG.md`.
- Canal de depuración: lonja de mañana, rellenar el tablón, terminar la
  casilla del mapa, dar muebles y visitarse a uno mismo.
- Reglas nuevas (`town`, `houses`, `orders`, `orderDay`, `shopDay`,
  `expeditions`, `visit`, ranuras 0–7) con sus pruebas en el emulador.
- Captura de todo en `test/hataraki_tour_test.dart`.
- Probar en el móvil por adb. Publicar solo cuando se pida (con minVersion
  0.8.0, porque cambia la forma de la partida).
- Hecho (2026-10-01): ayuda en doce páginas (lonja y visitas nuevas; la maña,
  tabla con dibujos, también al crear un Tama), sandalia de la agilidad
  redibujada, depuración (siguiente casilla, lonja de mañana entera,
  visitarse), capturas de las visitas y de la maña en el recorrido. El arte
  de objetos, oficios, edificios, casillas y muebles ya estaba de las fases
  anteriores. Falta: desplegar las reglas, probar en el móvil y, al publicar,
  subir la versión a 0.8.0 y minVersion.

## Fallos apuntados

- **Agilidad** (arreglado en la fase 7): el icono que sale junto al Tama que
  hace agilidad parecía una bufanda (alas blancas y tira roja); ahora es una
  sandalia de paja vista desde arriba con su tira en V y un ala.

## Por confirmar

Nada: lo ganado en encargos cuenta para la clasificación de riqueza
(confirmado por el usuario el 2026-09-30).
