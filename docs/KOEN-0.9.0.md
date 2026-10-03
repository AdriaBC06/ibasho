# Tama Kōen (公園) 0.9.0: plan por fases

Las decisiones están en `docs/PLAN-0.9.0.md` (puntos 5 y 6). Aquí está **cómo**
se hace: datos, reglas y fases que se prueban una a una en el móvil. Todo
sale en la 0.9.0. Las cifras marcadas como *(propuesta)* se pueden cambiar.

## Principios

- **Sin conexiones fijas** (plan gratis, 100 a la vez). El parque se lee
  con lecturas sueltas al abrir el canal y al tirar para refrescar. Nada
  escucha en vivo, salvo lo que ya escucha hoy (`UserNodeMux`).
- **Todo se calcula igual en todos los móviles.** Los encuentros salen de
  `hash(día UTC, pareja de Tamas)`, así que A y B ven lo mismo sin
  escribirse nada.
- **Lo que da algo tiene un tope en las reglas**, como los minijuegos. Lo
  que es solo de adorno no lo comprueban las reglas.
- **Día** = día UTC (`bonusDay`), el mismo de los topes de monedas.

## Datos

### `/users/{cuenta}/koen` (lo leen los amigos y lo escribe su dueño)
- `park/{0|1|2}`: los huecos del parque. Cada uno es una **ficha** como la
  de las visitas de Hatarakitama: `{tamaId, owner, name, personality,
  voice, look, at}`. `owner` es el creador del Tama; no coincide con la
  cuenta cuando lleva al parque un Tama que cuida a medias. Con huecos
  fijos, el tope de 3 lo pone la ruta, sin contar hijos.
- `bonds/{tamaA_tamaB}`: los puntos de amistad entre dos Tamas, con los ids
  ordenados. Cada cuenta guarda los de sus Tamas.
- `album/{recuerdo}`: el día en que salió, como las estampas.
- `drags/{día}/{pareja}`: los encuentros forzados de hoy (tope de 3 por
  pareja). Lo de días anteriores se borra al escribir.
- `claimed/{día}`: hasta qué encuentro del día se ha cobrado, para no cobrar
  dos veces.

### `/koen/{a_b}` (la pareja de amigos, con ids ordenados, como `/dm`)
Lo leen y lo escriben **solo `a` y `b`, y solo mientras son amigos**.
- `points/{a|b}`: los puntos de amistad que ha sumado cada uno. El nivel
  sale de la **suma**, y cada uno solo escribe su mitad. Para que nadie se
  dispare los puntos, solo pueden subir unos pocos por escritura y con
  15 s de margen *(propuesta)*.
- `rewards/{a|b}/{nivel}`: los premios de nivel ya cobrados. Las monedas van
  por `earnings`, con su propia rama en las reglas.
- `slots/{left|right}`: el Tama de cada uno en la casita del dúo.
- `streak`: `{count, day, a, b}`, donde `a` y `b` son el último día en que
  cada uno cuidó su Tama del dúo. La racha sube cuando los dos tienen el
  mismo día y se reinicia si alguno se salta uno.
- `house`: `{level, decor/{hueco}: mueble}`. Lo pueden mover los dos.
- `charm`: la forma de accesorio que ha elegido la pareja (`pendant`,
  `twins` o `thread`) y la mitad de cada uno.

### `/users/{cuenta}/koenInbox/{deQuién}` (ofertas de cuidar a medias)
`{tamaId, at}`. Solo lo escribe un amigo para crear la oferta, y el dueño
del buzón para borrarla. Como mucho una oferta por amigo.

### `/tamas/{id}/carer`
Es la cuenta que lo cuida a medias.
- **Ponerlo**: lo escribe el **amigo** al aceptar. Solo vale si su buzón
  tiene la oferta de ese Tama, si es amigo del creador y si el Tama aún no
  tiene `carer`. En la misma escritura se borra la oferta.
- **Quitarlo**: lo pueden hacer el creador o el propio cuidador.
- **Con `carer` puesto**:
  - El cuidador puede **leer** el Tama entero y **escribir `care`**,
    mientras siga siendo amigo del creador.
  - Las demás ramas (`look`, `hat`, `name`…) siguen siendo solo del creador.
- **Índice**: hace falta `.indexOn: carer` para que el cuidador encuentre sus
  Tamas compartidos con una consulta, como hoy con `keeper`.

### Monedas (`earnings`)
- **`koen`**: lo que dan los encuentros del parque.
  - Es gratis, como Odori, y tiene un tope de **20 al día**.
  - Cada encuentro de un Tama propio con el de un amigo da **5**, y el
    último cobro puede ser menor para llegar justo a 20.
  - Usa los pasos de siempre (3, 5, 8 o lo que falte hasta el tope) y los
    15 s de margen entre cobros: no hace falta una regla nueva.
- **`koenCare`**: los Tamas cuidados a medias. Da **10 de una vez**, una sola
  vez al día por cuenta. La regla lee `tamas/{tama}` y comprueba:
  - que quien cobra es el creador o el `carer`;
  - que hay `carer`;
  - que `care.lastFed` y `care.lastPetted` son de hoy (`>= día * 86400000`).

## Encuentros

- **Quién entra**:
  - Los Tamas que se ven son los del parque propio y los de los amigos.
  - Dos Tamas pueden encontrarse si sus dueños son la misma cuenta o son
    amigos. Las listas de amigos de los amigos se pueden leer (regla de
    `friends`).
  - Las parejas de Tamas de la misma cuenta juegan, pero no dan monedas ni
    amistad entre jugadores.
- **Cuándo**: cada pareja se encuentra un día si
  `hash(día, idA, idB) % 100 < 45` *(propuesta)*. La zona (columpios,
  tobogán, arenero, estanque, picnic, árbol) y lo que hacen salen del mismo
  hash, igual que la hora del día, para escalonarlos.
- **Arrastrar**: soltar un Tama sobre otro fuerza un encuentro en vivo, con
  como mucho 3 por pareja al día. Cuenta como un encuentro más para las
  monedas y la amistad, y se apunta en `drags`. Soltarlo en una zona solo
  lo pone a jugar allí: es de adorno.
- **Al abrir**: se leen las fichas y las listas de amigos y se calculan los
  encuentros de hoy. Se cobra lo que falte:
  - las monedas;
  - los puntos de amistad entre Tamas y entre jugadores;
  - los recuerdos nuevos;
  - un **mimo**: el Tama vuelve contento, con `care.lastPetted = ahora`.

## Fases

### Fase 1: el parque
- Canal **Tama Kōen**, siempre visible, con glifo propio y el lenguaje de
  consola de `docs/UI.md`.
- **Escena**:
  - Zonas de juego: columpios, tobogán, arenero, estanque, manta de picnic y
    árbol.
  - Día y noche según la hora real, con farolas y luciérnagas.
  - Estación según el mes: cerezos, verano, hojas y nieve.
- **Mandar y sacar Tamas** (3 huecos), con la ficha en `koen/park`. La ficha
  se reescribe si el Tama cambia de aspecto.
- **Tamas de amigos**: se leen al abrir. Pasean, se juntan en su zona cuando
  les toca un encuentro y tienen una animación por cada tipo de encuentro.
- **Tocar**:
  - A un Tama: salta, habla con su voz y enseña su nombre y su dueño.
  - Al escenario: el columpio se mueve, el pato nada, etc.
- **Arrastrar** (de adorno de momento): llevarlo a una zona o junto a otro
  Tama.
- **Reglas**: `koen/park` (lo leen los amigos y lo escribe el dueño) y los
  tests.

### Fase 1b: cambios tras probarla (pedidos por el usuario el 2026-10-02, hecha)
**Estado de la fase 1 (sin commitear):**
- `lib/backend/koen.dart`: fichas, encuentros y hash.
- `lib/state/koen.dart`: `koenProvider`, más `debugDemo`, que llena el parque
  en local; sale como botón «demo» en las builds de depuración.
- `lib/games/koen/koen_art.dart` y `koen_channel.dart`.
- Glifo `park`, `ArtIcon.koen` y `koenOpened`, para que llegue envuelto.
- Textos `koen*`.
- Reglas de `koen/park` con su test (215 pasan).
- `test/koen_test.dart`.

Contra producción no se puede mandar un Tama hasta desplegar las reglas
(van con la versión); de momento se prueba con «demo».

**Cambios pedidos:**
- **Bocadillo de chat** al interactuar, en vez de los símbolos ASCII de ahora
  (♪ ☆ ~ !).
  - Muestra **estados de ánimo de verdad** dibujados, como las caras o los
    emotes de la plaza Mii: contento, risa, sorpresa, vergüenza, sueño,
    enfado de broma, cariño…
  - Además, **hablan** con su voz (`TamaVoice`, `speak`) mientras sale el
    bocadillo, por turnos, como en una conversación.
- **Lo que sienten o dicen depende de su relación**:
  - de su nivel de amistad (`bonds`, fase 3; hasta entonces, del número de
    días que han coincidido o del hash de la pareja);
  - de sus personalidades: el tímido se avergüenza con quien no conoce y el
    pícaro gasta bromas;
  - de si son de la misma cuenta.
  - Los que se conocen poco: saludo tímido, curiosidad. Los muy amigos:
    risas, cariño, abrazo.
- **Más tranquilo**:
  - Pasean bastante más despacio (ahora `_walkSpeed = .07`; probar unos
    .025–.03).
  - Paran más rato entre paseo y paseo y hay menos encuentros a la vez (ahora
    uno cada 7 s y hasta 2).
  - Los saltos son más suaves y escasos.
- **No hace falta una zona de juego para interactuar**: un encuentro puede
  pasar donde estén (se acercan el uno al otro) o en una zona, al azar. Al
  arrastrar uno junto a otro, interactúan allí mismo, sin ir a una zona.
- **2.5D**: los Tamas pasan **por delante y por detrás** de los elementos del
  mapa.
  - El árbol, el columpio, el tobogán, las farolas, el estanque, el arenero
    y el picnic pasan a ser capas separadas, cada una con su «y» de base.
  - Se ordenan junto con los Tamas por la «y» de los pies (*painter's
    algorithm*): si un Tama está más arriba (más lejos) que la base del
    árbol, queda detrás.
  - El suelo y el cielo siguen en una capa de fondo.
  - De paso, los Tamas pueden escalarse un poco según la «y» (más pequeños al
    fondo) para dar profundidad.
- **Al tocar un Tama** sale **solo su nombre** (no «nombre · de jugador»), y
  la etiqueta debe verse **entera**. Ahora se corta con `ellipsis` y el
  ancho de la caja: la etiqueta tiene que medirse según el texto, sin
  límite de ancho, y no salirse de la escena (ajustar la x en los bordes).

**Cómo ha quedado (sin commitear):**
- `lib/games/koen/koen_mood.dart`: `KoenMood` (saludo, contento, risa,
  sorpresa, vergüenza, sueño, enfado de broma, cariño, curiosidad, canto),
  `koenChat` (3–5 frases por turnos según amistad y personalidades) y
  `KoenBubblePainter`, que dibuja la carita del color del Tama.
- `koenCloseness` en `backend/koen.dart`: días que les ha tocado coincidir
  de los últimos 30; los de la misma cuenta, al menos .6. La fase 3 lo
  cambiará por `bonds`.
- `KoenEncounter.inPlace` (40 %): se encuentran a medio camino, sin zona.
  Arrastrar uno junto a otro también es en el sitio.
- Pasean a .028 (.042 al ir a encontrarse), con paseos cortos y pausas de
  4–12 s; un encuentro del día cada 12 s y solo uno a la vez. Nadie pisa el
  estanque.
- `KoenLayer`: el suelo al fondo; árbol, columpio, tobogán y farolas como
  capas que se ordenan con los Tamas por la «y» del pie; el aire encima.
  Los Tamas encogen al fondo (`koenDepthScale`).
- Los bocadillos y el nombre van en una capa de encima, medidos y dentro de
  la escena.

### Fase 2: lo que da el parque (hecha, sin commitear; falta que la pruebe el usuario)
- Las monedas `koen` (20 al día), con su medidor diario como en los juegos.
- El mimo al volver y los regalos:
  - comida para la despensa;
  - un ticket como mucho a la semana, por la ruta de tickets que ya hay.
- **Álbum de recuerdos**: unos 24, que salen según la zona, la estación, la
  noche y si el encuentro es de un dúo.
- Los encuentros forzados cuentan, con su tope.
- El resumen de «mientras no estabas» al entrar.

**Cómo ha quedado:**
- `lib/backend/koen_rewards.dart`:
  - `koenDone`: los encuentros de hoy cuya hora (local) ya ha pasado y con
    los dos Tamas ya en el parque (`at`).
  - `koenPays`: solo pagan los de un Tama propio con el de otra cuenta.
  - `koenGiftFood`: la chuche del día sale de `hash(día, cuenta)`.
  - `KoenMemory`: 24 recuerdos.
    - el primero;
    - las 6 zonas y el paseo;
    - las 4 estaciones y 4 cruces de zona con estación (hanami, chapuzón,
      momiji, muñeco de nieve);
    - mañana, atardecer y luciérnagas;
    - en familia, amigos de amigos, forzado, inseparables y un día movido
      (3 encuentros).
  - El del dúo se añadirá en la fase 5, y serán 25.
- `KoenController.collect()`, al leer el parque y tras cada encuentro
  forzado:
  - **Monedas**: 5 por encuentro. Lo pagado se saca de `earnings/koen`
    (`ceil(cobrado / 5)`). Se cobran de 5 en 5 con los 15 s de siempre.
  - **Chuche**: con el primer encuentro del día; recibo en `koen/gift`.
  - **Gachaken**: al llenar el medidor, uno a la semana; recibo en
    `koen/ticket`.
  - **Recuerdos**: en `koen/album/{nombre}` = día.
  - **Mimo**: `pet` a los Tamas propios que han jugado.
- **Arrastrar**: lo apunta en `koen/drags = {day, pairs}` (3 por pareja) y
  cuenta como un encuentro más.
- **Resumen**:
  - Al entrar, el cuadro «mientras no estabas», con las postales de los
    recuerdos nuevos.
  - Tras arrastrar, solo un aviso.
- **Álbum**: un botón en el panel abre las postales. Cada una es el propio
  parque pintado con su estación y su luz, acercado a la zona, con la cara
  de ánimo; las que faltan salen en gris con «?».
- **Reglas** (se despliegan con la versión):
  - `koen/album`, `drags`, `gift` y `ticket`;
  - `koen` como juego gratis en `earnings`;
  - una rama en `pantry` (+1 con el recibo `koen/gift`) y otra en `tickets`
    (+1 gachaken con `koen/ticket`).
  - Tests en `rules_05.test.mjs`: pasan las 219.
- **«demo»**: no escribe nada. Lleva las monedas en local
  (`KoenState.demoEarned`), y las fichas tienen `at` = 1 para que cuenten
  los encuentros de hoy.
- **Depuración y estación**:
  - Un botón cambia la estación a mano (auto → primavera → … → invierno).
  - La estación va según el hemisferio del país del idioma del dispositivo
    (`koenSouthern`); en el sur va 6 meses cambiada.

### Fase 3: amistades (hecha, sin commitear; falta que la pruebe el usuario)
- **Entre Tamas**: los `bonds`, con niveles 1–5 *(propuesta)*. Al subir de
  nivel salen la animación de la pareja, un fondo y un gorro.
- **Entre jugadores**: niveles *(propuesta)*: conocidos → amigos → buenos
  amigos → inseparables.
  - La insignia sale en la lista de amigos y en el perfil.
  - Al subir de nivel, los dos cobran un premio.
- **Reglas** y sus tests.

**Cómo ha quedado:**
- **Cambio de datos**: los puntos entre jugadores no van en
  `/koen/{a_b}/points`, sino en `/users/{cuenta}/koen/friends/{amigo}`, la
  mitad de cada uno. Los ids de cuenta pueden llevar `_`, así que una clave
  `a_b` no se puede partir en las reglas; así no hace falta. El nivel sale de
  sumar las dos mitades, y el amigo lee la suya con una lectura suelta al
  refrescar (solo de los amigos con Tamas en el parque). `/koen/{a_b}` queda
  para la fase 5 (casita, racha y accesorio), con `a` y `b` dentro, como
  `/dm`.
- `lib/backend/koen_bonds.dart`:
  - `KoenTally {p, d, n}`: puntos, día y lo contado ese día. Al volver a
    contar solo suma lo nuevo, y las reglas lo comprueban.
  - **Entre Tamas**: 1 punto por encuentro (natural o forzado; como mucho 4
    al día por pareja). Niveles con 0, 3, 8, 15 y 25 puntos.
    - Nivel 2 («compis»): al encontrarse hacen un **baile de pareja**, media
      vuelta el uno alrededor del otro con un saltito, y acaban con cariño.
    - Nivel 3 («amigos»), la primera vez: el fondo **Kōen** (`bg_koen`), el
      propio parque con la estación de hoy, para el menú.
    - Nivel 5 («inseparables»), la primera vez: el gorro **momiji**
      (`momiji_red`), una hoja de arce.
    - Ninguno de los dos sale en el gacha (`Backdrop.koen`, `Prize.koen`).
  - La cercanía de la conversación y del recuerdo «inseparables» sale ahora
    de la amistad (`KoenState.closeness`); entre dos Tamas de amigos, de los
    días que han coincidido, como antes.
  - **Entre jugadores**: cada encuentro de un Tama propio con uno del amigo
    da 1 a quien lo cuenta (como mucho 36 al día por amigo). Conocidos con
    1, amigos con 20, buenos amigos con 60 e inseparables con 150 (sumando
    los dos). Al llegar a amigos, buenos amigos e inseparables, cada uno
    cobra 20, 40 y 60 monedas.
- **Se ve**:
  - el resumen al entrar: las parejas que han subido (los dos Tamas, sus
    corazones y el baile), los amigos que han subido con sus monedas y los
    premios;
  - en el panel, una sección «amistades» con cada amigo, su nivel y lo que
    falta para el siguiente;
  - los corazones (1–5) en cada encuentro de hoy;
  - la insignia (corazón con el color del nivel) en la lista de amigos y la
    pastilla «Kōen: nivel» en el perfil (`koenFriendLevelsProvider`, una
    lectura de `koen/friends`).
- **«demo»**: empieza con las parejas a un punto de subir y los dos amigos
  a punto de «amigos» y «buenos amigos», para ver las celebraciones.
- **Reglas**:
  - `koen/bonds`, `koen/friends`, y los recibos `koen/prize`, `koen/reward`
    y `koen/rewards/{amigo}/{nivel}`;
  - una rama en `prizes` (`bg_koen` y `momiji_red`, de 0 a 1) y otra en
    `coins` (+20, +40 o +60 con el recibo);
  - **arreglo de la fase 2**: `koen` ya no deja escribir todo de golpe. Cada
    hijo tiene su permiso, y los recibos no se pueden borrar. Antes se podía
    borrar `koen/gift` o `koen/ticket` y volver a cobrar.
  - Tests en `rules_05.test.mjs`: pasan las 223.

### Fase 4: cuidar a medias (hecha, sin commitear; falta que la pruebe el usuario)
- **Ofrecer** desde el parque o desde la ficha de un Tama propio, a un amigo.
  Le llega al buzón, y puede aceptar o rechazar.
- **Casita del Tama en el parque**:
  - Mimar y dar de comer, con la despensa de quien lo hace.
  - El cuidador puede llevarlo al parque (ocupa uno de sus huecos) y jugar
    con él en los minijuegos, igual que en la ficha del Tama.
- **Se ve**:
  - en la lista de amigos, para los amigos del dueño;
  - en «Mis Tamas», con una marca;
  - en el cuidador, en una sección «Cuidados a medias».
- **Las 10 monedas del día** (`koenCare`) para los dos.
- **Terminar**: lo puede hacer cualquiera de los dos. Al dejar de ser
  amigos, la app limpia `carer` la próxima vez que se abra; mientras tanto,
  las reglas ya le cierran el acceso.
- **Reglas** de `carer`, `care` y el buzón, con sus tests.

**Cómo ha quedado:**
- **Datos**:
  - `tamas/{id}/carer`: el amigo que lo cuida. `Tama.carer`.
  - `users/{amigo}/koenInbox/{creador}`: la oferta, que es la ficha del Tama
    como la del parque (`KoenOffer`). Una por amigo; la nueva pisa la
    anterior.
  - `users/{cuidador}/koen/caring/{tama}` = creador: un índice para
    encontrarlos. **Cambio respecto al plan**: no hay consulta
    `orderBy=carer` ni `.indexOn`. Una consulta en vivo sería otra conexión
    por cuenta (plan gratis) y en la regla de la consulta no se puede
    comprobar la amistad. El índice sale por la conexión de la cuenta
    (`UserNodeMux`) y cada Tama se lee suelto, con su regla, que sí la
    comprueba.
- **Reglas**:
  - `carer` lo pone el propio amigo, solo si tiene la oferta de ese Tama en
    su buzón y la borra en la misma escritura, si es amigo del creador y si
    el Tama no tiene ya cuidador. Lo quitan el creador o el cuidador. El
    creador no puede ponérselo a nadie, tampoco al crear el Tama.
  - Mientras sean amigos, el cuidador lee el Tama entero y escribe `care`.
  - `koenInbox`: lo escribe un amigo con un Tama suyo sin cuidador, y lo
    borran él o el dueño del buzón. Solo lo lee el dueño.
  - `earnings/koen_care`: 10 de una vez, una vez al día. Lleva `tama`, y la
    regla comprueba que hay `carer`, que quien cobra es el creador o el
    cuidador, que siguen siendo amigos y que `lastFed` y `lastPetted` son
    de hoy.
  - Tests en `rules_05.test.mjs`: pasan las 229.
- **App**:
  - `TamasState.cared` (los de otros que se cuidan) y `companions` (propios
    más compartidos). Los compartidos no se siguen en vivo: se releen al
    cambiar el índice y al abrir el parque o su habitación.
  - **Ofrecer**: en la habitación de un Tama propio («cuidar a medias») o
    desde el parque (Tama y amigo).
  - **Buzón**: las ofertas salen en el parque, en la sección «cuidados a
    medias», con aceptar y rechazar. El canal lleva la insignia con las que
    hay sin responder.
  - **Casita**: en esa misma sección del parque están los Tamas compartidos,
    y al tocarlos se abre su habitación. El cuidador puede mimarlo y darle
    de comer con su despensa; no puede editarlo, ni ponerlo de perfil, ni
    borrarlo.
  - **Parque**: los dos lo pueden traer, pero no a la vez (sale una sola
    vez).
  - **Minijuegos**: los compartidos acompañan en Nihongo, Buscaminas, Hebi,
    Tsumiki, pinball, pachinko y Odori.
  - **Se ve**:
    - en «Mis Tamas», con una casita, detrás de los propios y con «a medias
      con…»;
    - en la lista de amigos, con una casita en la ficha del amigo con quien
      se comparte.
  - **Monedas**: al mimarlo o darle de comer en su habitación (o al
    abrirla), si hoy ya tiene las dos cosas, cada uno cobra sus 10 una vez
    al día.
  - **Terminar**: lo puede hacer cualquiera de los dos desde la habitación.
    Al dejar de ser amigos, se quita en la misma escritura. Si lo dejó el
    otro, la app lo limpia al abrirse, tras releer la lista de amigos.
- **«demo»**: añade «Mochi», un Tama de un amigo inventado que ya se cuida a
  medias (ha comido hoy; falta el mimo, que da el aviso de las monedas), y
  una oferta de «Kuri». No escribe nada ni gasta la despensa. Las ofertas de
  verdad no salen hasta desplegar las reglas.

### Fase 5: dúos, racha y casita decorable (hecha, sin commitear; falta que la pruebe el usuario)
- **Dúo** = A cuida a medias un Tama de B y B uno de A.
  - **Huecos**: en la casita hay dos huecos, izquierda y derecha. Cada uno
    pone su Tama, y los dos pueden recolocarlos.
  - **Dónde se ve**: los dúos van juntos en el parque y salen en pequeño en
    la lista de amigos.
- **Racha conjunta**:
  - El día cuenta cuando cada uno ha mimado y dado de comer a su Tama del
    dúo. Si uno se lo salta, la racha vuelve a 0 para los dos.
  - Premios a los 3, 7, 14 y 30 días *(propuesta)*: 10 y 20 monedas, un
    ticket y un mueble.
- **Casita decorable**:
  - Sube de nivel (1–5) con la racha y la amistad del dúo.
  - Cada nivel da un mueble y más huecos de decoración.
  - **De dónde salen los muebles**: un catálogo propio del parque, que se
    gana con los niveles y los premios de racha *(propuesta; no se ha
    hablado)*.
  - Los dos pueden moverlos.

**Cómo ha quedado:**
- **Datos** (`lib/backend/koen_duo.dart`):
  - El dúo sale de los Tamas: un Tama propio con `carer` = amigo y uno de
    ese amigo que cuida la cuenta (`koenDuoTamas`). No hay que aceptar nada
    más.
  - `/koen/{a_b}`, con los ids ordenados y `a` y `b` dentro, como `/dm`:
    - `slots/{left,right}`: los Tamas de la casita. Sin nada guardado (o si
      ya no valen), el primero de cada uno, el de `a` a la izquierda.
    - `streak = {count, day, best}`.
    - `house/decor/{0..5}`: los muebles.
  - **Cambio respecto al plan**: el nivel de la casita no se guarda. Sale de
    la mejor racha y de la amistad del parque, y los muebles que tiene, del
    nivel; no hay catálogo que ganar ni que guardar.
  - Los premios de la racha se cobran como los de la amistad: recibo en
    `users/{cuenta}/koen/duo` y sello en `koen/duos/{a_b}/{días}`.
- **Racha** *(propuesta)*:
  - El día cuenta cuando **los dos Tamas** de la casita han comido y les han
    hecho un mimo, los haya cuidado quien sea: las reglas no saben quién lo
    hizo. Lo apunta el primero que lo ve, al cuidarlos en su habitación, al
    abrir la casita o al abrir el parque.
  - Si un día no cuenta, vuelve a empezar desde 1; la mejor se guarda.
  - Premios, una vez por dúo y cuenta, cada uno el suyo: 3 días, 10
    monedas; 7, 20; 14, un gachaken; 30, el gato de la suerte para la casita.
- **Casita** (`lib/games/koen/koen_house.dart`):
  - Una habitación japonesa pintada (tatami, ventana de papel que cambia con
    la luz del día) con los dos Tamas y los muebles. Desde el nivel 3 sale un
    pergamino en la pared.
  - **Niveles** *(propuesta)*: 1 de entrada; 2 con racha de 3; 3 con 7 y
    «amigos»; 4 con 14 y «buenos amigos»; 5 con 30 e «inseparables».
  - **Muebles**: 7, que no salen en el gacha. Cojines y farolillo (nivel 1),
    kotatsu (2), bonsái (3), cómoda (4), biombo (5) y el gato de la suerte
    (racha de 30). Hay un hueco más que el nivel (de 2 a 6). Se toca un hueco
    y se elige; un mueble que ya está en otro hueco se mueve.
  - Los dos pueden **cambiar los Tamas de lado** y, si se cuidan más de uno,
    tocar un Tama para elegir otro del mismo dueño.
- **Se ve**:
  - En el parque, los del dúo se encuentran **todos los días** y pasean
    juntos. La ficha lleva `duo` (el otro Tama), así que todos los móviles
    lo calculan igual.
  - El recuerdo 25, «en casa a medias», sale de un encuentro del dúo.
  - El panel del parque tiene una sección «dúos», con los dos Tamas en
    pequeño, la racha y el nivel; al tocarla se abre la casita.
  - En la lista de amigos, los dos Tamas en pequeño sustituyen a la marca de
    la casita.
  - En la habitación de un Tama del dúo, el botón «abrir la casita».
- **Reglas** (se despliegan con la versión):
  - `/koen/{a_b}`: lo leen y escriben `a` y `b` mientras son amigos; vacío,
    lo lee quien sale en el id. `slots` pide un Tama de cada uno y los dos a
    medias entre ellos. `streak` se apunta una vez al día, con los dos Tamas
    cuidados hoy, y `count` y `best` tienen que cuadrar con lo anterior. Los
    muebles son adorno: solo se mira la forma.
  - `users/{cuenta}/koen/duo` y `duos`, y una rama en `coins` (+10 o +20) y
    otra en `tickets` (+1 gachaken) con ese recibo.
  - `duo` en las fichas del parque.
  - Tests en `rules_05.test.mjs`: pasan las 234.
- **«demo»**: Mochi hace dúo con el primer Tama propio, con 6 días de racha
  hasta ayer y los cojines puestos. Al dar de comer y mimar hoy a los dos
  sube a 7 y sale el premio de la semana (sin cobrarlo de verdad).
- **Tests**: `koen_test.dart` (dúos) y `koen_duo_test.dart` (la racha contra
  el backend falso); `koen_house_preview_test.dart` deja
  `build/screenshots/koen-casita.png`.

### Fase 6: accesorio de pareja (hecha, sin commitear; falta que la pruebe el usuario)
- Se gana con el dúo y el nivel **buenos amigos** *(propuesta)*. La pareja
  elige una de tres formas:
  - colgante partido;
  - gorritos gemelos;
  - hilo rojo.
- **Color**:
  - Sale de los dos ids ordenados.
  - Se pinta con `flutter_svg` y se cambia el color al dibujarlo.
- **Mitades**:
  - La mitad depende del hueco: izquierda o derecha.
  - Solo encaja si los dos Tamas del dúo están juntos en el parque o en la
    casita.
  - El hilo rojo se dibuja entre los dos.
- Se pone como un accesorio más (`acc`), con una clave propia de cada
  pareja. **Hay que tocar las reglas de `acc`.**

#### Cómo ha quedado
- **Dónde**: una tarjeta más en la casita del dúo. Se desbloquea al ser
  **buenos amigos** (60 puntos sumados). En el dúo de prueba está abierta.
- **Forma**: la elige cualquiera de los dos en `/koen/{a_b}/charm`
  (`{shape, code}`), y la pueden cambiar los dos. Al cambiarla, quien ya
  llevaba su mitad la cambia por la nueva.
- **Color**: `code` son 6 cifras hexadecimales que salen del hash de los dos
  ids ordenados, y no cambia. El tono va de 0 a 359. Los dibujos están en
  gris en `assets/koen/charm_{forma}_{l|r}.svg` y se tiñen al pintarlos
  (`BlendMode.modulate`). El hilo rojo no se tiñe: siempre es rojo.
- **Clave propia de cada pareja**: `charm_{forma}_{l|r}_{code}`, que cabe en
  `[a-z0-9_]{1,40}`. Es un premio más de `prizes` y se pone en `look/hat`
  (gorritos) o en `look/acc` (corazón al cuello, hilo atado a un costado).
  **Las reglas de `acc` no han hecho falta tocarlas**: siguen pidiendo que
  esté en la colección.
- **Cobro**: el recibo `users/{id}/koen/charm` (`{key, pair, at}`) cruza:
  - la forma y el color de `/koen/{a_b}/charm`;
  - el lado de su Tama en `slots` (izquierda, `l`; derecha, `r`), con el
    Tama aún a medias;
  - la amistad de los dos (≥ 60).
  `prizes/charm_*` solo sube de 0 a 1 con ese recibo fresco.
- **Mitades**:
  - El corazón partido tiene el zigzag hacia el otro.
  - El gorrito tiene la borla hacia el otro.
  - El hilo va atado del lado del otro: en `variantSlots`, la mitad `r`
    va a la izquierda.
- **Encajan** cuando los dos llevan su mitad, de la misma pareja y de lados
  distintos:
  - En la casita se ve siempre.
  - En el parque, cuando los dos del dúo están juntos y quietos.
  - El hilo rojo se dibuja de uno a otro. Con las otras formas flota entre
    los dos un corazón entero del color de la pareja.
  - En el parque, un Tama que mira a la izquierda se pinta en espejo, así
    que su mitad se cambia por la del otro lado para seguir mirando al otro
    (`koenMirrorCharm`).
- **Editor**: las mitades que tienes salen en las pestañas de gorros y
  accesorios con el nombre de su forma.
- **Demo**: elegir forma y ponérselo solo cambia lo que se ve en la casita;
  no toca los Tamas.
- Hoja de prueba: `build/screenshots/koen-pareja.png`
  (`test/koen_house_preview_test.dart`).

### Fase 7: repaso (hecha, sin commitear)
- `flutter analyze` y `flutter test`: limpio, 685 tests (3 saltados).
- Los tests de reglas (`test/rules`): 236.
- Textos en es/en: las 114 claves `koen*` están en los dos.
- Accesibilidad: dentro del lienzo no se escala el texto del sistema (medidas
  fijas, ver `lib/ui/canvas.dart`); todas las fichas del parque y de la
  casita llevan etiqueta para el lector, y los Tamas de la escena su nombre.
  El botón de ofrecer cuidar a medias pasa de 40 a 44 de alto, como el resto.
- Lecturas al abrir el parque con 20 amigos, todos con 3 Tamas
  (`test/koen_reads_test.dart`): 61 peticiones sueltas (la propia, un
  parque por amigo y, de los que tienen Tamas, su lista de amigos y lo que
  llevan sumado con la cuenta), unos 37 KB. La lista de amigos se lee ya
  con `shallow` (solo las claves). Además van una lectura por Tama cuidado a
  medias y una por dúo, más la de `koen/duos`. Ninguna se queda abierta.

### Fase 7b: cambios tras probar con la cuenta de admin (2026-10-02, sin commitear)
- Insignia de amistad nueva (`KoenFriendBadgePainter`): disco del color del
  nivel con corazón y un anillo de cuatro tramos, uno por nivel.
- Ficha de amistad (`koen_friendship.dart`): se abre tocando la píldora del
  perfil o una amistad del parque. Nivel, puntos de los dos, barra hasta el
  siguiente, cómo sube y qué trae cada nivel. Puntos en
  `koenFriendPointsProvider` (el parque si está leído; si no, dos lecturas).
- Insignias del perfil: globo (`HintBubble`) con por qué se tienen, al pasar
  el ratón o al tocarlas.
- Cuidados a medias, dúos y racha fuera del parque (`koen_social.dart`):
  botón «a medias y dúos» en «tus Tamas» y en amigos (ofertas, compartidos,
  ofrecer, dúos); en el escaparate de «tus Tamas», la racha junto a «a
  medias con…» y un botón de casita u ofrecer; en el perfil de un amigo,
  «Casita con…» o «Cuidar a medias con…» y la racha. La racha se lee y se
  apunta también al abrir «tus Tamas» o un perfil (`refreshKoenDuos`).
- Arreglado el desborde de 4 px del escaparate con un Tama a medias.
- La luna es una media luna recortada (antes un círculo del color del cielo
  encima) y el pato dormido tiene cabeza; también cola y ala.
