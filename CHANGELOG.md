# Cambios de Ibasho

Las versiones siguen los checkpoints del proyecto: `mayor.menor.parche`, donde
cada checkpoint sube la menor y los arreglos sobre él suben el parche. La
versión que corre cada build está en `pubspec.yaml` y en `lib/core/version.dart`
(lo comprueba `test/update_gate_test.dart`).

## 0.5.1 — El bono diario

### Añadido

- **Bono diario.** Al entrar, una vez al día, se abre un calendario del mes con
  lo que da cada día, el mismo para todo el mundo: de lunes a jueves entre 3 y
  7 monedas, los viernes 10 y el sábado y el domingo 15. Los días cobrados
  llevan el sello rojo, y hoy late hasta que lo cobras: entonces el sello cae
  sobre la casilla, las monedas saltan hasta la cabecera y la cifra sube.
  El día cambia a medianoche UTC, como los premios de los juegos.
- **En el canal de depuración**, el bono se puede probar sin cobrar, abrir de
  verdad u olvidar (solo el de la cuenta propia) para cobrarlo otra vez.
- **Cada juego enseña lo cobrado hoy**: «8/20» con una barrita dorada en su
  menú (el panel y el selector del buscaminas, la tarjeta de salida de Tsumiki
  y el menú de Nihongo), que se pone en verde al llegar al tope.

### Cambiado

- **El tope diario es de 20 monedas en cada juego**, en vez de 20 entre todos.
  Siguen los 15 s entre dos cobros, sean del juego que sean.
- **Nihongo cuesta 50 monedas** en vez de 150 (el precio vive en
  `/shop/prices`: se carga con `tool/seed_shop.dart`).
- **El tablero del día del buscaminas se cierra al ganarlo**, hasta el día
  siguiente: su tarjeta enseña el tiempo y un candado, y «otra ronda» pasa a
  fácil.

### Seguridad

- Los premios pasan a `earnings/{juego}` con un puntero `earnings/last`, y el
  bono a `login`. Las reglas calculan lo que da cada día a partir del número
  de día, con la misma cuenta que la app, así que no hace falta cargar ningún
  calendario. `rewards` (el tope común de la 0.5.0) ya no se puede escribir.
- `test/rules/rules_05.test.mjs` cubre el tope por juego, que un juego no gaste
  el de otro, la espera común, el puntero, y el bono: la cantidad de cada día,
  cobrarlo una vez, el historial, otra cuenta y el borrado del admin.

### Nota para desplegar

Una 0.5.0 escribe en `rewards`, que las reglas nuevas ya no aceptan: con las
reglas de la 0.5.1 desplegadas, **exige la 0.5.1**. Y vuelve a cargar los
precios (`dart run tool/seed_shop.dart`) para el nuevo precio de Nihongo.

## 0.5.0 — La tienda (checkpoint 5)

Las monedas por fin sirven para algo. Llega **Yatai** (屋台), el puesto de
feria de Ibasho: una tienda al estilo del Canal Tienda de la Wii o la eShop de
la 3DS. Y con ella, tres juegos con tu Tama al lado que además dan monedas:
un buscaminas, **Tsumiki** (bloques que caen) y **Nihongo**, para aprender
japonés.

### Añadido

- **El canal Yatai**, montado como una sola escena: arriba el **escaparate**,
  con el artículo elegido flotando sobre una peana de cristal bajo un foco, su
  nombre, el precio en una etiqueta con moneda y el botón de comprar; en medio
  las tres secciones con su icono; abajo el **mostrador**, con los artículos en
  baldosas por páginas (flechas, puntos y deslizar). Tu saldo va en la
  cabecera, con la moneda.
  - **Juegos.** Vienen dentro de la app; comprarlos solo los activa. Tras
    confirmar, el juego **se envuelve delante de ti** —entra en la caja, cae
    la tapa y se ata el lazo— mientras una barra de cristal se llena.
  - **Tamas.** Comida por unidades —×1, ×5 o ×10—, solo de la que la cuenta
    tiene desbloqueada: hoy, galleta y caramelo. Las demás se ven con candado.
    Al comprar, las chuches caen una a una en una bolsa.
  - **Gacha.** Una máquina de cápsulas con su cartel de **próximamente**.
- **Los juegos llegan envueltos.** Un juego recién comprado aparece en la
  rejilla como un **regalo**: una caja con lunares, cinta y lazo. Al tocarlo
  el lazo se deshace, la tapa salta, salen destellos y el icono del juego sube
  desde dentro. Desde entonces es un canal más. Como los regalos de la 3DS.
- **Iconos ilustrados.** El Yatai y los juegos llevan un icono pintado a color
  —el puesto con su toldo y su farolillo, la mina simpática con su bandera—
  sobre una baldosa blanca, y así se distinguen de los canales del sistema.
- **Buscaminas**, el primer juego, a 0 monedas. Una sola escena: a un lado tu
  Tama en su escenario, **uno distinto al azar en cada ronda**, que habla en un
  bocadillo y reacciona a todo —salta con una buena racha o un hueco grande,
  tiembla cuando quedan tres casillas, cae KO si explota una mina y lo celebra
  si ganas—; al otro, el tablero de plástico.
  - Las casillas se destapan **en ola** desde el toque, las banderas se clavan
    con rebote, una mina explota con onda y chispas y sacude el tablero, y al
    ganar cae confeti y ondean las banderas.
  - Tres niveles (9×9, 12×12 y 16×16) y el **tablero del día**: el mismo para
    todo el mundo cada día, con una casilla de salida que brilla.
  - **Medallas** de bronce, plata y oro por tiempo en cada nivel, el sello
    **sin banderas** y una **pantalla de resultados** con el tiempo, el mejor
    tiempo, la medalla y lo cobrado.
  - Tocar destapa; mantener pulsado o clic derecho pone bandera, y hay un
    interruptor destapar / bandera. Tocar un número con sus banderas puestas
    destapa los vecinos. El primer toque nunca es una mina. En un móvil
    pequeño, los tableros grandes se amplían y se desplazan con el dedo.
- **Tsumiki** (積み木, «bloques de juguete»), a 10 monedas: bloques que caen,
  de plástico lacado con un botoncito, como las piezas de un juguete. Tu Tama
  (otro en cada partida) celebra las filas, salta con cuatro de golpe, se
  agobia cuando la torre llega arriba y respira cuando baja.
  - Giros con empujes contra la pared, pieza fantasma, **guardar** una pieza,
    las tres siguientes, combos, «tsumiki doble» y niveles cada 10 filas;
    cuenta atrás 3, 2, 1 antes de empezar y nivel de salida 1, 5, 10 o 15.
  - Se juega con una **cruceta y botones A y B** como los de una DS, con
    gestos sobre el pozo (deslizar para mover, tocar para girar, bajar rápido
    para soltar y subir para guardar) o con el teclado.
  - Las filas completas destellan y se encogen con chispas, lo que se suelta
    de golpe deja estela y sacude el pozo, y al acabar la torre se apaga de
    abajo arriba. La pausa tapa el pozo. Resultados con la puntuación que sube
    contando, filas, nivel, récords y lo cobrado.
- **Nihongo** (日本語), a 150 monedas: aprender japonés con tu Tama de sensei.
  Cuatro categorías: **hiragana** y **katakana**, y **kanji** y **palabras**,
  que llegan más adelante.
  - Eliges qué grupos entran (los 46 básicos, los de ten-ten y maru y los
    combinados como きゃ o しょ) y si respondes **eligiendo entre cuatro** o
    **escribiendo** la lectura en romaji (vale Hepburn y también si, ti, tu,
    hu…).
  - Rondas de diez tarjetas de papel que entran dándose la vuelta. Al acertar
    cae el **maru** rojo de los maestros japoneses; al fallar la tarjeta
    tiembla, enseña la lectura buena y espera a que la mires. Las opciones
    falsas se parecen a la buena, para que haya que fijarse.
  - Cada kana lleva su cuenta: salen más los que aún no dominas (tres aciertos
    seguidos), y el menú enseña cuántos dominas de cada escritura. Al acabar,
    los fallos para **repasar**, la mejor racha y, con un pleno, un
    **hanamaru**.
  - Una **tabla** para leer: los kana de cada grupo en su cuadrícula, como en
    los libros (una fila por consonante, una columna por vocal), con la
    lectura debajo y el maru en los que ya dominas. Al tocar uno, el Tama te
    dice cómo se lee.
- **Ganar da monedas**, con un **tope de 20 al día** (día UTC) entre todos los
  juegos:
  - Buscaminas: 3 en fácil, 5 en media y en el tablero del día, y 8 en
    difícil.
  - Tsumiki: al acabar, 3 con 10 filas, 5 con 25 y 8 con 50.
  - Nihongo: solo con un pleno (10 de 10), 3 eligiendo y 5 escribiendo. Los
    repasos no dan monedas.
- **Formato de hora 12 h / 24 h** en Ajustes, junto al idioma. Lo siguen el
  reloj del panel de arriba, la hora local de un amigo en su perfil y la hora
  de los mensajes. Por defecto, 24 h, como siempre.
- **Apps en el canal de depuración**: un admin puede darse un juego envuelto
  o abierto, o quitárselo, sin pasar por el Yatai. Solo en su propia cuenta.
- **`tool/seed_shop.dart`** carga los precios del Yatai (`/shop/prices`). Un
  artículo sin precio sale como «no disponible».

- **Cada juego con su canción.** Plaza en el buscaminas, Bossa en Tsumiki y,
  en Nihongo, dos nuevas y originales: **Sumi** (piano eléctrico y koto) en el
  menú y la tabla, y **Hanami** (koto, marimba y bajo con swing) mientras se
  juega. Suena en lugar de la de ambiente mientras el juego está abierto, con
  el mismo fundido que la música de un perfil, y **la primera vez que se oye se
  desbloquea**: desde ese momento se puede elegir para el menú o el perfil.

### Cambiado

- **La comida se gasta.** Darle una chuche a un Tama consume una unidad. Cada
  cuenta recibe **5 de cada comida de serie** la primera vez que abre la 0.5.0,
  y la tira de la habitación enseña cuántas quedan; una agotada se hunde con un
  0 y avisa de que se repone en el Yatai.
- **Las monedas se pueden gastar y ganar.** Los administradores las siguen
  dando; la dueña puede restarse las suyas al comprar y sumárselas al cobrar
  un premio, y nada más.

### Quitado

- **El chat general («Global»).** Los mensajes son solo entre amigos: fuera la
  tarjeta del grupo del canal de mensajes y la sección para crearlo del panel
  de administración. Las reglas ya no dejan leer ni escribir en `/groups`, así
  que tampoco lo usa una versión vieja, y lo que había guardado se borra.

### Seguridad

- Cada compra es **una escritura multi-ruta**: recibo (`shop/last`, con la
  hora del servidor), saldo nuevo y lo comprado. Las reglas exigen que el
  recibo sea de ese mismo instante, que el saldo baje **exactamente** precio ×
  cantidad, y que la despensa o el juego solo cambien si ese recibo lo
  justifica. Un recibo viejo no sirve para una segunda compra.
- Cobrar un premio es otra escritura multi-ruta: `rewards` (`{game, day,
  earned, at}`) y el saldo. Las reglas exigen tener el juego, que el día sea
  el de hoy en el servidor, que cada cobro sea de 3, 5 u 8 (o lo justo para
  llegar a 20), que no pase de **20 al día**, que pasen **15 s** entre cobros
  y que el saldo suba exactamente lo cobrado. No se puede demostrar que una
  partida se ganó de verdad: lo que acota las trampas es ese techo bajo.
- La despensa y los juegos **no se pueden borrar**, el stock inicial solo se
  da una vez, y al comer solo se puede restar de una en una.
- `test/rules/rules_05.test.mjs` cubre compras con y sin saldo, restas que no
  cuadran, recibos reutilizados, comida bloqueada, el stock inicial repetido,
  los regalos y los premios (cantidades, tope, día, espera y cuenta ajena).

### Nota para desplegar

Una build 0.4.x no sabe que la comida se gasta y seguiría dando de comer
gratis. Después de publicar las reglas y los precios, **exige la 0.5.0** desde
el panel de administración.

## 0.4.1 — Que el primer mensaje se vea

Arreglos de cosas que se rompían justo al usarlas, y las noticias en dos
idiomas.

### Añadido

- **Las noticias se pueden publicar en castellano y en inglés**, y cada cual
  las lee en el suyo. Título, texto y las opciones de una encuesta. Sin
  traducción se ve la castellana, que es mejor que un hueco; y una encuesta
  traducida a medias se descarta entera, porque media encuesta en cada idioma
  se lee peor que la original. Se publica desde el panel o con
  `tool/post_news.dart --title-en --body-en --option-en`.

### Arreglado

- **El primer mensaje que le escribes a alguien ya aparece.** Hasta que la
  conversación no existe, las reglas niegan leerla —no tiene `a` ni `b`, así
  que nadie es de ella—, y el cliente se rendía: ni leía ni abría el flujo en
  tiempo real. El mensaje entraba en la base de datos y no salía nunca en
  pantalla. Ahora una lectura denegada se trata como una conversación vacía, el
  flujo se abre en cuanto hay algo que leer, y lo que mandas **se pinta al
  momento**, sin esperar a que el servidor te lo devuelva: el viaje de ida y
  vuelta se notaba, y un mensaje que tarda en aparecer parece un mensaje
  perdido.
- **La conversación deja de rehacerse sola.** Dependía del estado entero del
  canal de mensajes, así que cada aviso al buzón y cada marca de lectura la
  destruía y la volvía a montar, releyendo y **redescifrando el historial
  entero**. Ahora depende del controlador, que no cambia.
- **El historial se ordena por conversación más reciente**, no por antigüedad
  de la amistad.
- **El botón «descargar la nueva» funciona en Android.** Abría el navegador con
  `Process.start`, que tenía rama para Linux, macOS y Windows y **ninguna para
  Android**: en el móvil el botón sonaba y no hacía nada, justo donde más falta
  hace. Ahora va por `url_launcher`, que además abre bien un navegador en un
  Linux sin `xdg-open`.
- **La dirección de descarga se ve escrita, siempre.** Debajo del botón, con su
  botón de copiar. Es el único camino que no depende de que haya un navegador
  que abrir ni de que la build sepa abrirlo: quien se quede tirado puede
  teclearla en otro aparato. Antes, si el botón fallaba, desde dentro de la app
  no había forma de saber a dónde ir.

### Nota sobre las versiones anteriores

El arreglo del botón no puede llegar a una build que ya está instalada. Quien esté en
0.3.x o en 0.4.0 y se encuentre el aviso de actualizar seguirá viendo el botón
mudo en Android: hay que darle la dirección por fuera. A partir de la 0.4.1 el
botón funciona, así que es la última vez.

## 0.4.0 — Hablar (checkpoint 4)

La primera versión en la que Ibasho deja de ser una casa vacía: un tablón donde
se anuncian las versiones y se vota, mensajes cifrados entre amigos con
*stickers* de tus propios Tamas, un grupo abierto al que unirse, un buzón de
sugerencias con respuesta, y un monedero que todavía no gasta nadie.

### Añadido

- **Canal de mensajes, cifrado de punta a punta.** Cada mensaje viaja dentro de
  un sobre cerrado: una clave AES-256-GCM propia por mensaje, envuelta una vez
  por destinatario con ECDH sobre P-256 y HKDF, con par efímero por mensaje.
  Lo que queda en la Realtime Database es ruido, marcas de tiempo y quién habla
  con quién; el texto no lo puede leer nadie más, tampoco quien tenga la base
  entera delante. Todo en Dart puro con `pointycastle`, que es lo que ya usaba
  el almacén de sesión.
- **Clave de respaldo de doce palabras.** La clave privada vive en el llavero
  del sistema (libsecret, DPAPI o el Keystore de Android) y, envuelta con una
  frase de doce palabras, en la base. La frase se enseña una sola vez al crear
  la cuenta y se puede volver a mirar desde Ajustes en un aparato que la tenga.
  En un móvil nuevo se teclea una vez y vuelve el historial entero. **No cuelga
  de la contraseña**: un administrador puede resetearla mil veces sin llevarse
  por delante un solo mensaje, y sigue sin poder leer ninguno. El alfabeto son
  512 palabras castellanas sin tildes ni eñes, con las cuatro primeras letras
  únicas para poder teclear a medias, y una suma de comprobación que caza las
  erratas quince de cada dieciséis veces.
- **Stickers de Tama.** Se elige uno de tus Tamas y una de ocho caras
  —contento, guiño, sorpresa, enfado, amor, triste, sueño, saludo— y el sticker
  se dibuja en vivo con el mismo pintor de siempre: no hay ni un mapa de bits.
  El aspecto del Tama viaja **dentro** del sobre, no por referencia, así que se
  sigue viendo igual años después aunque lo edites o lo borres, y lo ve quien
  lo recibe aunque no tenga permiso para leer ese Tama en la base.
- **Grupo «Global».** Los grupos no se crean desde la app: el administrador
  pone éste una vez y cada cual se une si quiere. Hasta que no entras no se
  descarga ni un mensaje, y al entrar ves lo que se escriba a partir de ese
  momento, nunca lo anterior. Cada mensaje se cifra una vez y su clave se
  envuelve para cada miembro, hasta 32.
- **Canal de noticias.** Novedades de versión, avisos y encuestas, publicados
  por un administrador desde el propio canal o con `tool/post_news.dart` sin
  abrir la app. **Las encuestas son anónimas de verdad, no sólo en la
  pantalla**: en la entrada sólo hay cuántos votos lleva cada opción y quién ya
  ha votado; a qué votó cada cual vive únicamente en su propio árbol, que no
  lee nadie más. Los resultados se mueven en vivo y el voto se puede cambiar
  mientras la encuesta siga abierta, con fecha de cierre o cerrándola a mano.
- **Canal de sugerencias.** Título de 30 caracteres y texto de 200. Una viva
  por cuenta: hasta que no hay veredicto no se puede mandar otra, y lo aplican
  las reglas, no sólo la pantalla. El administrador acepta o rechaza con un
  motivo opcional, y lo aceptado pasa a una lista pública para que se vea que
  las sugerencias van a alguna parte. El buzón se puede cerrar para todos sin
  tocar lo que ya hay dentro.
- **Monedas.** Un contador por cuenta en la barra de estado, junto a la batería
  y la señal. Está a cero para todo el mundo y todavía no se gasta en nada; lo
  que importa ya es que **nadie pueda ponérselas a sí mismo**: sólo escribe un
  administrador, desde su panel, y la app no tiene ni una ruta que lo intente
  desde la cuenta propia.
- **Chapas de sin leer.** El mismo mecanismo que ya avisaba de las solicitudes
  de amistad ahora enciende también los iconos de mensajes y de noticias en el
  menú de inicio, y el de sugerencias para quien pueda revisarlas. Los mensajes
  sin leer se saben con un único flujo: quien escribe deja un aviso —sólo de
  quién y cuándo, nada del mensaje— en el árbol de quien recibe, en vez de
  abrir una suscripción por conversación.
- **El historial se poda solo.** Cada conversación guarda los últimos 300
  mensajes y nada de más de 90 días. Lo borra el mismo cliente que escribe, en
  la misma operación que manda, así que no hay ninguna tarea de limpieza en
  ninguna parte y la base no crece sin freno.

### Arreglado

- **La rejilla de canales ya no se queja con más de una página.** Las páginas
  van una al lado de otra en una fila tan ancha como todas juntas y el recorte
  enseña la que toca; ese es el mecanismo desde el principio, pero la fila
  recibía el ancho del panel y desbordaba. Hasta ahora no se veía porque nunca
  había habido más de ocho canales.
- **Los indicadores de la barra de estado se encogen antes que cortarse**, como
  ya hacía el reloj. Con las monedas sumadas a la batería, la señal y el
  idioma, en la tira estrecha de un móvil de 360 puntos no cabían a tamaño
  natural.
- **Los tests de reglas ya no se pisan entre ellos.** Las dos tandas comparten
  un único emulador y cada una vacía la base antes de cada caso; `node --test`
  las lanzaba en paralelo. Ahora van en serie.

### Cifrado, en corto

| | |
|---|---|
| Identidad | ECDH sobre P-256 (`pointycastle`), clave pública en `/users/{cuenta}/keys/pub` |
| Mensaje | AES-256-GCM con clave propia; par efímero por mensaje |
| Envoltorio | ECDH efímero → HKDF-SHA256 (sal: el punto efímero; info: el destinatario) → AES-256-GCM |
| Respaldo | Argon2id (3 pasadas, 32 MiB) sobre la frase → AES-256-GCM sobre la privada |
| Frase | 12 palabras de 512 → 104 bits de entropía y 4 de comprobación |
| Dónde se abre | En un isolate y por tandas de 30, empezando por los últimos: abrir un sobre cuesta unos 9 ms y una conversación llena son 300 |

## 0.3.3 — Windows (checkpoint 3.2)

Ibasho deja de ser cosa de Linux y Android: la misma app, el mismo árbol de
widgets y las mismas pantallas, ahora también en Windows 10 de 64 bits. Sin
funcionalidades nuevas.

### Añadido

- **Windows 10 x64.** Ventana de 1280×800 —el lienzo virtual a escala 1, igual
  que en Linux— que no baja de 360×640 por mucho que se arrastre el borde, con
  ese suelo escalado según el DPI del monitor. Estrecharla hasta que sea más
  alta que ancha salta a la composición vertical, la misma del móvil: no hizo
  falta ninguna rama nueva, porque la forma ya la decidía la proporción de la
  ventana y no el sistema.
- **Instalador de un solo fichero.** `Ibasho-<versión>-windows-x64-setup.exe`
  se instala sin pedir administrador y deja la app en el perfil del usuario,
  igual que `install_linux.sh` lo deja todo bajo `~/.local`. Al lado queda el
  mismo contenido en zip para quien lo quiera portable. Ambos los monta
  `tool/package_windows.ps1`, y ambos llevan dentro `msvcp140.dll`,
  `vcruntime140.dll` y `vcruntime140_1.dll`: un Windows 10 recién instalado
  trae el CRT universal pero no el runtime de Visual C++, y sin él la app no
  arranca ni dice por qué.
- **Integración continua.** `.github/workflows/build.yml` compila y empaqueta
  las tres plataformas —bundle de Linux, APK de Android e instalador y zip de
  Windows— y sube cada una como artefacto, con `dart analyze` y `flutter test`
  como paso previo que corta el resto si falla. El `.env` se reconstruye en el
  runner desde los *secrets* del repositorio, nunca desde el árbol. La firma de
  Android es opcional: con los secrets del keystore el APK sale firmado y sin
  ellos sale con la firma de depuración, sin romper la compilación.

### Arreglado

- **La música suena en Windows.** Las seis pistas son Ogg Vorbis, y en Windows
  no sonaba ninguna: `audioplayers` va por Media Foundation, que no trae
  decodificador de Ogg, así que la música salía muda mientras los efectos —que
  van por SoLoud, con decodificadores propios— se oían con normalidad. Ahora
  cada pista tiene un `.mp3` equivalente al lado del `.ogg` y Windows pide ese.
  Linux y Android siguen con los `.ogg` originales, byte a byte.
- **El almacén de secretos dice cuál está usando.** `backendName` devolvía
  `libsecret` en todas partes, que es lo que se lee en el canal de depuración y
  en los créditos. En Windows el llavero es DPAPI y ahora lo dice.
- **El identificador de máquina existe fuera de Linux.** El respaldo cifrado
  deriva su clave de `/etc/machine-id`, que en Windows no existe: se caía a un
  nombre de equipo más un `HOME` vacío, casi igual en cualquier máquina. Ahora
  usa el `MachineGuid` del registro, con el perfil del usuario como respaldo.

## 0.3.2 — Sonido y presencia en el móvil

Arreglos sobre la 0.3.1, ya distribuida.

### Arreglado

- **Los efectos y las voces de los Tamas suenan en el móvil.** Ibasho miraba el
  modo del timbre y los callaba en silencio y en vibración, mientras la música
  seguía sonando: el resultado era una app a medias en un teléfono que casi
  siempre lleva el timbre apagado. Todo lo que suena en Ibasho es audio de
  medios, así que ahora se comporta como tal —el silencio del sistema calla el
  tono y las notificaciones, no el juego— y para callarlo están sus dos
  deslizadores y el volumen de medios. Además, si un aparato no admite el
  mezclador a 48 kHz con periodo corto, se arranca con el de serie en lugar de
  quedarse mudo.
- **Los estados de presencia dicen la verdad.** El estado publicado es el que
  elige la persona —conectado mientras no elija otra cosa— y nada más: se
  quita el *ausente* automático a los cinco minutos sin tocar nada, que
  aparecía con la app delante y encima no existía en el móvil. Fuera de la app
  se publica *desconectado*, igual que al cerrarla, en lugar del *ausente* que
  dejaba la 0.3.1 al pasar a segundo plano.

## 0.3.1 — Android (checkpoint 3.1)

Ibasho sale del escritorio: la misma app, el mismo árbol de widgets y las mismas
pantallas, ahora también en un móvil Android. Sin funcionalidades nuevas.

### Añadido

- **Composición vertical.** Cuando la ventana es más alta que ancha, el entorno
  deja el lienzo escalado y se compone a tamaño real: paneles apilados, rejilla
  de canales de 3×3, carril y barra táctiles, y cada canal recolocado para un
  ancho estrecho. La forma la decide la proporción de la ventana, así que una
  ventana estrecha en Linux también la usa.
- **Zonas táctiles de 48 dp.** En vertical ningún control baja de 48 dp
  (`test/touch_targets_test.dart` lo mide en un móvil de 360×640). En horizontal,
  donde el lienzo de escritorio se escala a la mitad, un asistente entrega el
  toque al control más cercano dentro de esa distancia.
- **Arrastre horizontal** para pasar de página en las rejillas, además de las
  flechas.
- **Botón y gesto de atrás de Android**: retroceden con su sonido, avisan antes
  de salir del creador con cambios sin guardar y piden confirmación antes de
  cerrar la app desde la raíz.
- **Ciclo de vida del móvil**: al pasar a segundo plano se para la música, se
  apaga el motor de efectos, se suelta el foco de audio, la presencia baja a
  ausente y se cierran el websocket y las suscripciones en tiempo real. Al
  volver se renueva la sesión si hacía falta y se reabre todo.
- **Foco de audio y modo silencio**: si otra app toma el audio, Ibasho calla o
  baja; los efectos respetan el silencio del teléfono.
- **Modo inmersivo**, zonas seguras (muescas y barra de gestos) y arranque con
  icono adaptativo propio.
- La tarjeta de visita se **comparte** con el menú del sistema en Android (en
  escritorio se sigue guardando en Descargas).

### Cambiado

- La batería se lee con `battery_plus` en las dos plataformas, en lugar de
  `/sys/class/power_supply`.
- El texto ignora la escala de fuente del sistema (ver *Accesibilidad* en el
  README).
- Las zonas desplazables aceptan punteros sin tipo, que es lo que inyectan las
  herramientas de automatización.

### Sin cambios

- Linux: el lienzo horizontal, sus medidas y su aspecto son exactamente los de
  la 0.3.0; el recorrido visual sale idéntico píxel a píxel.

## 0.3.0 — Amigos y perfiles (checkpoint 3)

- Códigos de amigo al estilo 3DS, solicitudes, amistades y presencia en tiempo
  real por websocket propio de la Realtime Database.
- Perfiles ajenos con hora local, insignias, música y muro de cumpleaños.
- Tarjeta de visita exportable a PNG.
- Bloqueo de versiones antiguas (`/system/update`) y aviso de actualizar.

## 0.2.0 — Los Tamas (checkpoint 2)

- Los Tamas: modelo, creador con piezas y deslizadores, habitación, humor,
  cuidados, voces sintetizadas y acento del entorno sincronizado con el Tama de
  perfil.

## 0.1.0 — Entorno y cuentas (checkpoint 1)

- El entorno de dos paneles, la rejilla de canales, el tema de la casa, el
  motor de sonido, las cuentas por allowlist y el panel de administración.
