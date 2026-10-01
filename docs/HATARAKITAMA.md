# Hatarakitama (働きたま)

Canal de la 0.7.0: el juego *idle* de Ibasho, inspirado en *Melvor Idle* y
*RuneScape*. Tus Tamas trabajan en el pueblo aunque la app esté cerrada, suben
oficios del 0 al 99 y salen de expedición.

## Reglas del juego

- **20 oficios**: tala, pesca, minería, huerto, recolecta y agilidad (sacan
  cosas del mundo; agilidad solo da experiencia), cocina, carpintería, forja,
  costura, té, joyería, cerámica, tintes, construcción, escritura, brebajes y
  magia (las transforman), estudio (solo da experiencia, leyendo libros) y
  **expediciones**. Los siete últimos llegan en la 0.8.0:
  - **Cerámica**: arcilla (minería o el río) y leña. Cuencos, ladrillos,
    frascos, tejas, teteras, macetas y jarrones. Del horno sale **hollín**.
  - **Tintes**: de flores y cosechas (el **añil** es un cultivo nuevo). Tiñe
    telas y ropa; la ropa teñida suma fuerza en los sitios de su color.
  - **Construcción**: vigas, armazones, muros, tejados, shoji, pilares y
    shachihoko, para levantar el pueblo.
  - **Escritura**: papel y tinta (de hollín); cuadernos y libros para
    estudiar y mapas para los viajes.
  - **Brebajes**: artemisa, agua de manantial y un frasco: pociones de cura,
    vista, suerte y prisa, y el elixir.
  - **Magia**: runas de gemas, polvo de luna y nubes que encantan el equipo
    de un viaje.
  - **Estudio**: gasta libros y solo da experiencia; cada nivel da un 0,1 %
    más de experiencia en todo.
- Cada oficio va del 0 al 99: el 1 llega a los 40 xp y del 2 en adelante es la **curva de RuneScape** (el 92 es la mitad
  del 99: 13 034 431 xp). Cada tarea pide un nivel.
- **Maestría** por tarea (0–99, con una cuarta parte de la experiencia): cada
  nivel quita un 0,2 % de tiempo y da un nivel/400 de sacar doble.
- **Los Tamas son los trabajadores**: una ranura por Tama y tarea. Se empieza
  con una y se abren más con el **nivel total** (40, 100, 200, 350, 550, 800 y
  1100), hasta ocho.
  - **Personalidad**: un 15 % más rápido en sus cuatro oficios (tranquilo:
    pesca, huerto, té y brebajes; juguetón: agilidad, recolecta, tintes y
    expediciones; tímido: costura, joyería, escritura y estudio; pícaro:
    minería, forja, tala y construcción; dormilón: cocina, carpintería,
    cerámica y magia).
  - **Cebo, abono o mecha**: a un Tama que pesca, planta o mina se le puede
    poner uno. Gasta uno cada vez que termina: el cebo da más probabilidad
    de sacar doble, el abono cosechas de más y la mecha más gemas. Si se
    acaban, sigue sin ellos. Salen de recolecta (lombrices), huerto (compost
    y abono rico) y forja (señuelos y mechas).
  - **Ánimo**: de ×0,8 a ×1,2 en velocidad, el mismo ánimo de siempre (mimos
    y comida). En el canal se le puede mimar en el escenario y **dar de comer**
    lo cocinado en el propio juego: cuenta como comer, sin tocar la despensa.
- Si faltan materiales, el Tama **espera** («espera caña de bambú») y vuelve
  solo en cuanto los hay: de otro Tama que los saca, de lo que se compra o de
  un viaje. Así se hacen cadenas (uno tala y otro hace cestas) que van al
  ritmo del más lento, también offline.
- **Tés** (30 min; 45 con una **tetera** en el almacén): aceleran un oficio o
  todo, del 5 al 20 %.
- **Agilidad**: cada nivel, un 0,1 % más rápido en todo.
- **Offline**: al volver se simula lo que ha pasado, con un tope de **12 h**, y
  sale el resumen de «mientras no estabas…». Las expediciones vuelven por reloj
  aunque pasen de las 12 h.

## El pueblo (0.8.0)

- Pestaña **pueblo** (la de los Tamas trabajando pasa a llamarse
  **trabajo**) con diez edificios, del nivel 0 (solar) al 5 (el tablón viene
  hecho, a nivel 1). Subir un nivel
  pide ginmon, piezas de construcción (vigas, armazones, muros, tejados,
  shoji, pilares y shachihoko), una pieza propia del edificio desde el nivel
  2 y un nivel de construcción (0, 20, 40, 60 y 90). Gastar no quita riqueza.
- **Taller**: +4 % por nivel en todo lo que transforma. **Horno**: +5 % en
  cerámica y +10 % de hollín. **Muelle**, **invernadero** y **torre**: +5 % en
  pesca, huerto y magia. **Biblioteca**: +10 % de experiencia de estudio y
  abre mapas y libros (del sendero al estelar). **Torre**: abre las runas de
  la brújula en adelante. **Posada**: −8 % de comida por nivel, cuatro
  Tamas por viaje a nivel 3 y dos viajes a la vez a nivel 5.
- **Tienda**: 4 cosas al día con el nivel 1, una más por nivel. Lo mismo
  para todos cada día, a 4 veces el precio de venta y con existencias.
- **Lonja**: cada día, igual para todos y haya lonja o no, suben de precio 6
  cosas (oficios enteros o cosas sueltas) y bajan dos oficios (`hMarket`).
  La lonja solo lo enseña (`hMarketSeen`): lo que baja y nivel + 1 de las
  que suben, y a nivel 3 la de mañana. La ficha del almacén
  y los botones de vender dan el precio del día.
- **Tablón** (`hataraki_orders.dart`): el gran encargo y 3 encargos normales
  al día (4 a nivel 2, 5 a nivel 4) y +6 % de ginmon por nivel por encima
  del 1. Se hacen al empezar el día (`refreshOrders`, en cada `tick`) con la
  semilla de la partida y lo que ya se sabe hacer, y se guardan en
  `orders` (`day`, `swap`, `ticket`, `list/{0-5}`): subir de nivel no los
  cambia a media jornada.
  - **Normales**: una cosa de un oficio que ya se trabaja y que no esté ya en
    el tablón, de las tres últimas que se han abierto, en cantidad para 20–40
    minutos de trabajo (`hEffort`: segundos por unidad con sus materiales;
    lo que cae cuenta lo que tarda en caer), hasta 500.
  - **Grande**: 2 o 3 cosas de 40–80 minutos cada una y, la mitad de los
    días, un **paquete**, que sale de la casilla de **encargo** que tiene
    cada mapa (una por mapa, en una columna de en medio; da 1 paquete, sin
    porteador).
  - **Paga**: ginmon (1,6–2 veces, o 2,2–2,6 el grande, lo que vale lo
    pedido o, si es más, lo que daría ese rato en el trabajo mejor pagado que
    ya se sabe hacer), y a veces experiencia del oficio o algo raro de los
    sitios a los que ya se llega; el grande, todo eso y un **ticket
    gachaken**. Lo cobrado suma a `earned`, `dayMoney` y `weekMoney`, como
    vender.
  - **Cambiar**: uno al día (no el grande), por un cuarto de lo que paga.
  - **Ticket**: al entregar el grande queda `orders/ticket`; el controlador
    lo cobra con `hataraki/orderDay` = hoy (UTC) y `tickets/gachaken` + 1 en
    la misma escritura. Las reglas lo dejan solo si `orderDay` era de otro
    día, y ni `orderDay` ni `claimAt` se pueden borrar.
  - **Planos**: uno de cada cuatro encargos normales regala el plano de un
    mueble que aún no se sabe (y que no regala otro encargo del tablón).

## Habitaciones y muebles (0.8.0)

En el juego son **habitaciones de la posada** (se entra desde la posada del
mapa, aunque aún no esté hecha; con alguna habitación la posada ya se dibuja
hecha). En el código y en la partida siguen llamándose casas (`houses`,
`HHouse`, `hHouseCost`).

- `hataraki_home.dart`. **Una casa por Tama** (`houses/{tamaId}`): una
  habitación de 6×6 con `floor`, `wall` (un estilo cada uno) e `items/{0-35}`
  (`id`, `x`, `y`, `r`: esquina de arriba a la izquierda y giro 0–3; los
  giros impares cruzan el ancho y el fondo). Solo se ponen, se mueven, se
  giran (si no cabe, se arrima arriba y a la izquierda) y se guardan; ni
  paredes ni exterior se editan. Lo puesto sale del almacén y ya no se vende.
- **Coste** (`hHouseCost`, por casas hechas): 300 ginmon y 2 vigas; 2000 y 6
  vigas (construcción 10); 8000, vigas y armazones (20); 25 000, armazones y
  muros (30); luego 60 000 × (n − 3), muros y tejados (40).
- **Muebles** (`HItemKind.furniture`, 29): estilo, tamaño (1×1, 2×1, 1×2 o
  2×2) y comodidad (1–4). 24 se fabrican (carpintería, cerámica, tintes,
  costura, escritura y magia; aparecen entre las tareas por nivel) y 5 solo
  se compran (andon, lámpara de caracola, maneki-neko, velas de luna y
  macetero), que entran en la tienda del día. Cinco se hacen sin plano
  (taburete, zabuton, cartel, farolillo y cuenco de flores); el resto pide su
  **plano** (`plans/{id}`), que vende la tienda (1 al día, 2 con la tienda a
  nivel 3, a 8 veces lo que vale el mueble, mínimo 300) o regalan los
  encargos.
- **Comodidad** (`hComfort`): la mitad, los puntos de los muebles (llena con
  24); una cuarta parte, lo que combinan (la parte del estilo que más se
  repite, contando suelo y pared, desde 3 muebles: un tercio es 0 y todo
  igual es 1), y otra cuarta parte, lo que hay del estilo favorito de su
  personalidad (tranquilo: floral; juguetón: marino; tímido: elegante;
  descarado: rústico; dormilón: mágico).
- **Descanso** (`HState.moodFor`): con casa, el ánimo con el que trabaja
  (y el ritmo que se enseña) es el mayor entre el suyo y 0,25 + 0,55 ×
  comodidad. Solo dentro de Hatarakitama: el ánimo del Tama en Ibasho no se
  toca.
- Al leer, lo que se pisa o se sale de la habitación vuelve al almacén.

## Visitas (0.8.0)

- Desde el perfil de un amigo («visitar su pueblo») o con el botón de amigos
  del mapa del pueblo (`pickHatarakiVisit`, elige entre los amigos) se abre
  `HatarakiVisitScreen`: el mismo `_TownMap` con `visit: true` (sin los +),
  la ficha de cada edificio sin costes (`_BuildingCard(visit: true)`), una
  tira con sus Tamas (tocar uno dice qué hace, su maña y su comodidad, y
  deja ver su habitación, sin tocar nada) y, sin nada elegido, su riqueza
  (`earned`), nivel total, edificios hechos y mejores oficios.
- Una lectura puntual (`hatarakiVisitProvider`, `read` de
  `/users/{cuenta}/hataraki`), sin conexión nueva. Se ve la partida tal y
  como se guardó la última vez: no se simula lo que ha pasado desde entonces.
- Los amigos no leen `tamas`: cada guardado añade la **ficha de visita**
  `hataraki/visit/tamas/{tamaId}` con `name`, `personality` y `look`
  (`hatarakiVisitJson`). Las reglas dejan leer `hataraki` a la dueña y a sus
  amigos (como `profile`) y solo escribir a la dueña; la ficha no admite nada
  más (ni cuidados ni fechas).
- La depuración deja visitarse a uno mismo.

## Expediciones

- Grupo de 1 a 3 Tamas libres (4 con la posada a nivel 3) (ni trabajando ni
  de viaje), comida (puntos: Tamas × minutos que comen / 10, menos lo que
  ahorra la posada) y el **equipo** del almacén: herramienta (forja), ropa
  (costura), bolsa (carpintería) y amuleto (joyería).
- **Fuerza** = (5 + nivel de expediciones) por Tama (+15 % a los juguetones)
  + equipo + runa. Frente a la dificultad del sitio da el éxito (30–100 %),
  que escala botín, experiencia y la probabilidad de **tesoro** del gacha.
- Ocho sitios, del prado (nv. 0, 10 min) a la luna (nv. 95, 3 h). Traen lo que
  no sale de otra forma: plumas, caracolas, ámbar, ascuas, nubes, polvo de luna
  e hilo de seda.
- **Mapa del día** (`hataraki_map.dart`, 0.8.0): `hZoneMap(sitio, día)` sale
  igual para todos (`HDayRng(día, 10 + sitio)`). De 4 columnas (prado,
  bosque, río) a 6 (cielo, luna), con 2 o 3 casillas de 3 filas; una casilla
  lleva a las de la columna siguiente en su fila o en una de al lado. Los
  minutos del sitio se reparten entre las columnas, por tipo:
  - **botín** (×1): una cosa del botín del sitio, más a menudo lo que más cae;
  - **recolecta rara** (×1,1): lo más raro con 4 veces su probabilidad, si no
    botín;
  - **peligro** (×1,2, no en la primera columna): pide fuerza (0,7–1,3 × la
    dificultad). Si no llega y no queda poción de cura (el elixir las cura
    todas), tarda la mitad más y no da nada; pasarlo da botín;
  - **descanso** (×0,5): no da nada, pero no gasta comida;
  - **cofre** (×1,3, más en la última columna): botín y una tirada de tesoro.
  - **encargo** (×1, una por mapa): un paquete para el gran encargo.
  - **Niebla** (de 15 % a 36 % de las casillas, no en la primera columna):
    no se ve qué hay. La quitan un mapa o una poción de vista (o una runa de
    brújula o estelar) elegidos para el viaje, o un **guía** pagado ese día.
- Al salir se fija todo lo que no es suerte: cuándo acaba cada casilla y qué
  peligros no se pasan (`HExpedition.at`, `fails`). Cada casilla es un evento
  en su hora dentro de `advance`: da su botín y su experiencia (la del sitio
  × éxito / columnas), despierta a los parados y queda en `log`. Al final,
  la tirada de tesoro de siempre. **Volver ya** se queda con lo ya pasado.
- Al salir se gastan una **poción o mapa** y una **runa**: cura (un peligro),
  vista y mapas (niebla), suerte (tesoro ×2; runa de suerte ×1,5) y prisa
  (−20 % de tiempo); la runa suma su fuerza.
- **Servicios** en ginmon: guía (xp del sitio × 2, para ese sitio ese día),
  porteador (× 1,5; +50 % de botín por casilla) y carro (× 1; −25 % de
  tiempo). Con la posada a nivel 5, **dos viajes a la vez** (a sitios
  distintos).
- Partida: `expeditions/{0,1}` con `day`, `route`, `at`, `fails`, `done`,
  `porter`, `luck` y `log`; `guides/{sitio}` = día. Se lee también el
  `expedition` de la 0.7.0 (sin ruta: vuelve de golpe, como antes).

## Interfaz

- Botón de **información** arriba: la ayuda en doce páginas (trabajo, nivel
  total, maña, materiales, expediciones, mapa, encargos, pueblo, lonja,
  habitaciones, visitas y monedas). La de la maña es una tabla con cada
  personalidad y los dibujos de sus oficios (`HatarakiLikesTable`); lo mismo
  sale al crear un Tama, debajo de la personalidad (`HatarakiLikes`). Sale sola una única vez
  (`prefs.hatarakiHelpSeen`), en la primera partida, y tocar el nivel total la abre en su página.
- El Tama elegido dice su ritmo (segundos por vez y cuánto por hora), su maña
  por personalidad y su ánimo. Si está parado, dice qué le falta y con qué
  oficio o sitio se consigue. «Cambiar tarea» lleva a la suya.
- Las tareas dicen «tienes/pide» de cada material, quién las hace y por qué
  están bloqueadas. Las ranuras con Tamas llevan un globito.
- Al elegir Tama con las ranuras llenas, solo se puede elegir a uno que ya
  trabaja (se le cambia la tarea), y se avisa.
- Almacén con nombres, «sale de» y «se usa en»; el equipo se pone y se quita.
- Expediciones: tocar un sitio abre su mapa; tocar una casilla la mete en la
  ruta y el Tama dice qué es. La tarjeta da tiempo, éxito, peligros que no se
  pasan, grupo, comida, poción o mapa, runa y servicios; el botón dice qué
  falta (grupo, comida, nivel, ginmon, viaje en marcha) y la cruz saca a un
  Tama del grupo. De viaje, el mapa enseña al grupo andando y lo que ha
  salido en cada casilla, y **volver ya** trae lo de las casillas pasadas.
- El té activo sale sobre el escenario con lo que le queda.
- Tablón: «entrar» desde el pueblo; cada encargo dice lo que pide
  (tienes/pide), de dónde sale y lo que paga. «Entregar» y «cambiar · precio»;
  el edificio lleva un + cuando hay algo para entregar.
- Pueblo: un mapa pintado (`_TownMap`), sin páginas. Dos colocaciones fijas
  (`_wideTown` 4+4+2 y `_tallTown` 3+3+2+2), calles delante de cada fila y
  una que baja al río, donde está el muelle. Cada parcela
  (`HatarakiTownLot`, lienzo 140×120) lleva el edificio y lo de su nivel:
  suelo de tierra, macetas (2), grava y farol (3), árbol y arbusto (4),
  losas, estandarte y destellos (5). Debajo, un cartel con nombre, nivel y
  el + si hay algo que hacer; en vertical estrecho, solo el nivel.
- Habitaciones: la posada tiene «entrar» siempre. Dentro, un Tama por
  casilla con su comodidad; «preparar su habitación» o «entrar». En la habitación, los muebles del
  almacén van en una tira debajo: se elige uno y se toca la casilla; tocar
  uno puesto lo elige (girar, guardar o tocar otra casilla para moverlo).
  Sin nada elegido, los botones cambian suelo y pared. En vertical, dentro
  de la habitación no sale el escenario (el Tama ya está en su casa).
- La tienda vende también planos (papel azul con el mueble encima). Una
  tarea de mueble sin plano sale con candado y «falta el plano».
- Cada objeto tiene su dibujo (`hataraki_art.dart`), los oficios una escena y
  los sitios una medalla con su paisaje. `test/hataraki_tour_test.dart` deja
  todos juntos en `build/screenshots/hataraki/iconos.png`.

## Ecosistema

- **Gratis**, llega envuelto a todo el mundo (`prefs.hatarakiOpened`).
- **1 moneda por minuto** con el canal delante (el offline no cuenta), hasta
  20 al día: `earnings/hataraki` solo sube de 1 en 1 y con 60 s entre cobros.
- **Vender**: todo lo del almacén se vende por **ginmon**, la moneda del pueblo
  (`hSellValue`): lo que valen sus materiales más la experiencia de la tarea
  × 0,2, entre lo que saca; lo que solo cae vale más cuanto menos cae (una
  décima de la tarea entre la probabilidad, o la experiencia del viaje
  repartida entre el botín). Mínimo 1. En la ficha, «vender 1» y «vender
  todo» (con confirmación). La partida lleva `money`, `earned` (desde
  siempre) y `period.dayMoney`/`weekMoney`.
- **Clasificación** `hataraki` de **riqueza** (mayor es mejor, hasta
  999 999 999): los ginmon ganados vendiendo hoy, esta semana y **desde
  siempre**. La de siempre (`/leaderboards/hataraki/alltime/{scores,at}`)
  solo sube, no tiene podio ni premio y sale como tercera pestaña «de
  siempre». Se manda al guardar; un periodo a 0 no se manda.
- **Música**: `asa`, `mizuba` y `yuyake` (`tool/gen_hataraki_music.py`)
  suenan por turnos (`GameMusic.cycle`), o la elegida con el botón de nota
  (`prefs.hatarakiTrack`; las que no han sonado nunca salen con candado).
  Cada una se desbloquea en la biblioteca la primera vez que suena.
- **Tesoros**: el que traiga una expedición se canjea solo por un **ticket
  gachaken**, como mucho uno por hora: `hataraki/claimAt` pasa a `now`,
  `prizes` baja 1 y `tickets/gachaken` sube 1 en la misma escritura.
- Entrar cuenta para la misión de jugar.
- Sin conexiones nuevas: la partida se lee una vez al entrar (`read`) y se
  escribe entera cada 2 min, al hacer algo y al salir.

## Código

- `lib/games/hatarakitama/hataraki_data.dart`: oficios, objetos, tareas,
  sitios y afinidades.
- `hataraki_engine.dart`: curva, `HState` (la partida), simulación por eventos
  (cuando dos Tamas gastan lo mismo, acaba primero el que menos le queda),
  expediciones y guardado.
- `hataraki_town.dart`: edificios, costes, bonos, tienda y lonja del día.
- `hataraki_orders.dart`: encargos (`HOrder`, `hMakeOrder`, `hEffort`);
  `hataraki_channel_orders.dart` (`part`): fichas del tablón.
- `hataraki_channel_town.dart` (`part`): la pestaña del pueblo.
- `hataraki_channel_visit.dart` (`part`): visitar el pueblo de un amigo.
- `hataraki_home.dart`: estilos, muebles, casas, comodidad y planos;
  `hataraki_channel_home.dart` (`part`): lista de casas, habitación y fichas;
  `hataraki_art_home.dart` (`part`): dibujos de muebles, casa, plano y la
  habitación de cada estilo (`HatarakiRoomPainter`, `hRoomLayout`).
- `hataraki_map.dart`: mapa del día, casillas, servicios y `HTripPlan`;
  `hataraki_channel_trip.dart` (`part`): rejilla de sitios, mapa y tarjetas
  de viaje; `hataraki_art_map.dart`: el dibujo de cada casilla.
- `hataraki_art.dart`: un dibujo por objeto, escenas de oficio, medallas de
  sitio e `ArtIcon.hataraki`. Glifo `Glyph.pick`.
- `hataraki_channel.dart`: la escena (escenario y escaparate a un lado,
  pestañas y rejillas paginadas al otro). En vertical, la rejilla quita filas
  si no caben.
- `lib/state/hataraki.dart`: `HatarakiController` (carga, `tick`, órdenes,
  guardado y clasificación).
- Textos: los nombres de objetos, oficios, sitios y recorridos van en mensajes
  `select` (`hatarakiItemName`…), no en una clave por objeto.
- Depuración: la sección Hatarakitama del canal de depuración sube niveles,
  llena el almacén, da ginmon, da muebles y planos, rehace el tablón, trae
  la expedición (entera o solo la siguiente casilla), enseña la lonja de
  mañana entera, visita el pueblo propio, añade
  tesoros, simula 3 h
  fuera, vuelve a enseñar la ayuda, cambia la canción y empieza de cero.
- Pruebas: `test/hataraki_test.dart` (motor), `test/hataraki_tour_test.dart`
  (capturas en `build/screenshots/hataraki/`, con `habitaciones.png`, y
  nombres de todo) y
  `rules_05.test.mjs` (cobros, forma de la partida y visitas) y
  `rules_leaderboards.test.mjs` (tope de ginmon y tabla de siempre).
