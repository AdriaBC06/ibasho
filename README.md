# Ibasho · 居場所

> *tu lugar*

Ibasho es un espacio de juegos multiplataforma inspirado en los menús de sistema
de Wii y Nintendo 3DS: un launcher de micro-apps con avatares propios (los
**Tamas**), cuentas, amigos y mensajería.

Este repositorio está en el **checkpoint 3.1** (0.3.1): el entorno, las cuentas,
los **Tamas** y los **amigos**, en Linux y en Android. Todavía no hay apps dentro, pero el entorno ya se
puede usar: splash, login, cambio obligatorio de contraseña, entorno de dos
paneles con reloj y barra de estado, rejilla de canales con paginación y
animación de apertura, perfil, ajustes, créditos, panel de administración, el
canal de Tamas con su creador y la habitación de cada uno, y el canal de amigos:
códigos de amigo al estilo 3DS, solicitudes, presencia, perfiles con la hora
local y la música de cada cual, tarjeta de visita exportable y muro de
cumpleaños.

Plataformas: **Linux desktop** y **Android** (móvil y tableta). La 0.3.1 no
añade funcionalidades: lleva a Android exactamente lo que ya había, con una
composición vertical propia y todo lo que un móvil necesita (táctil, botón de
atrás, ciclo de vida, foco de audio). Windows sigue fuera.

---

## Requisitos

- Flutter stable (probado con 3.41) y Dart 3.
- Toolchain de Linux desktop: `clang`, `cmake`, `ninja`, `pkg-config`, `gtk3`.
- Para Android: SDK de Android (probado con la plataforma 36 y build-tools
  36.1), NDK y un JDK 17 o posterior. `flutter doctor` tiene que dar verde la
  línea de *Android toolchain*.
- `libsecret` (opcional: sin llavero del sistema la sesión se cifra en un archivo).
- GStreamer (lo usa `audioplayers` en Linux).
- Node.js y la CLI de Firebase (`npm i -g firebase-tools`) para desplegar reglas,
  crear el primer admin y lanzar los tests de reglas.

## Puesta en marcha

### 1. Configuración de Firebase

El proyecto necesita una app web registrada para sacar la API key:

```sh
firebase projects:list                 # comprueba que apunta al proyecto correcto
firebase apps:create WEB ibasho
firebase apps:sdkconfig WEB
```

Copia la plantilla y rellénala con `apiKey`, `databaseURL` y `projectId` de la
salida anterior:

```sh
cp .env.example .env
```

```ini
IBASHO_API_KEY=AIza...
IBASHO_DATABASE_URL=https://<proyecto>-default-rtdb.firebaseio.com
IBASHO_PROJECT_ID=<proyecto>
```

`.env` está en `.gitignore`. **No lo commitees.** Los valores se inyectan en
tiempo de compilación con `--dart-define-from-file`, así que no quedan en el
código.

### 2. Reglas de la base

```sh
firebase deploy --only database
```

### 3. Primer administrador

Aún no hay nadie que pueda dar de alta cuentas, así que la primera se crea desde
la terminal:

```sh
dart run tool/bootstrap_admin.dart --username <tu_usuario>
```

Crea la cuenta en Identity Toolkit y escribe `/allowlist`, `/admins`,
`/usernames` y su código de amigo con la CLI de Firebase, que usa tus credenciales de desarrollador y
por eso puede saltarse las reglas. Imprime una contraseña de un solo uso: la app
te pedirá cambiarla al entrar. Si se corta a medias, vuelve a lanzarlo con
`--password <la que imprimió>` y retoma donde lo dejó.

A partir de ahí todo se hace desde la app: el canal **administración** crea
cuentas (cada una con su código de amigo), las deshabilita y regenera
credenciales. Al abrirlo reparte código a las cuentas que se crearon antes de
que existieran.

### 4. Ejecutar

```sh
flutter run -d linux --dart-define-from-file=.env          # escritorio
flutter run -d <id-del-movil> --dart-define-from-file=.env # Android
```

`flutter devices` lista los dispositivos conectados por adb.

### 5. Instalar en este equipo

```sh
./tool/install_linux.sh               # compila en release con .env e instala en ~/.local
./tool/install_linux.sh --uninstall   # lo quita
```

Deja la build en `~/.local/share/ibasho`, la entrada **Ibasho** en el menú de
aplicaciones con su icono y el comando `ibasho`. Para actualizar, se vuelve a
lanzar. Las preferencias y la sesión guardada no se tocan.

## Android

La app es la misma: el mismo árbol de widgets, las mismas pantallas y el mismo
código de red. Lo único que cambia es la composición cuando la ventana es
vertical y un puñado de cosas que solo existen en un móvil.

### Compilar

```sh
flutter build apk --debug   --dart-define-from-file=.env
flutter build apk --release --dart-define-from-file=.env
flutter install --use-application-binary=build/app/outputs/flutter-apk/app-release.apk
```

La configuración de Firebase se inyecta con `--dart-define-from-file`, igual que
en Linux: **no hay `google-services.json` ni plugins de FlutterFire**.

- `applicationId`: `top.ibasho.app`.
- `minSdkVersion` 24, `targetSdkVersion` la última estable (36).
- Permisos: solo `INTERNET` y `ACCESS_NETWORK_STATE`. Lo que arrastran las
  dependencias se quita en el manifiesto; se puede comprobar en el APK con
  `aapt2 dump permissions`.
- Sin tráfico en claro: `usesCleartextTraffic="false"` y una configuración de
  seguridad de red que lo prohíbe. Solo la build de depuración permite HTTP
  contra `127.0.0.1`, para los emuladores de Firebase.
- R8 activado en release, con las reglas mínimas en
  `android/app/proguard-rules.pro`.

### Firma

El keystore **no está en el repositorio** y no debe estarlo. Para generar el
tuyo:

```sh
mkdir -p ~/.ibasho
keytool -genkeypair -v -keystore ~/.ibasho/ibasho-release.jks \
  -storetype JKS -keyalg RSA -keysize 4096 -validity 10000 -alias ibasho
```

y crear `android/key.properties` (ignorado por git) con:

```ini
storePassword=...
keyPassword=...
keyAlias=ibasho
storeFile=/home/<tu-usuario>/.ibasho/ibasho-release.jks
```

Sin ese archivo la build de release se firma con la clave de depuración: sirve
para probar, no para distribuir.

### Contra los emuladores de Firebase

Los emuladores corren en el equipo de desarrollo; el móvil llega a ellos por
`adb reverse`:

```sh
firebase emulators:start --project demo-ibasho --only auth,database
dart run tool/dev_seed.dart
adb reverse tcp:9000 tcp:9000 && adb reverse tcp:9099 tcp:9099
flutter run -d <id-del-movil> --dart-define-from-file=.env \
  --dart-define=IBASHO_USE_EMULATOR=true --dart-define=IBASHO_PROJECT_ID=demo-ibasho
```

### Lo que cambia en el móvil

- **Vertical**: sin lienzo escalado. El entorno se compone a tamaño real, con
  los dos paneles apilados, rejilla de canales de 3×3 y cada canal recolocado
  para el ancho que haya. **Horizontal**: el lienzo de 1280×800 de siempre.
- **Táctil**: en vertical ninguna zona baja de 48 dp; en horizontal, donde el
  lienzo se escala a la mitad, un asistente entrega el toque al control más
  cercano que quede a menos de esa distancia. Se puede arrastrar de lado para
  pasar de página.
- **Atrás**: el botón y el gesto retroceden con su sonido, avisan antes de
  perder cambios en el creador y piden confirmación antes de cerrar la app.
- **Segundo plano**: la música y los efectos callan, se suelta el foco de
  audio, la presencia pasa a desconectado y se cierran el websocket y las
  suscripciones. Al volver se renueva la sesión si hacía falta.
- **Audio**: Ibasho pide el foco y calla si otra app se lo queda. Todo lo que
  suena es audio de medios, así que el modo silencio del teléfono no lo calla
  (igual que no calla un vídeo): para eso están los dos deslizadores de Ibasho
  y el volumen de medios.
- **Pantalla completa**: barras del sistema ocultas (deslizando desde el borde
  vuelven) y zonas seguras respetadas: nada queda bajo la muesca ni pegado al
  borde.

### Accesibilidad: la escala de texto

**Limitación conocida.** Dentro del lienzo, Ibasho ignora la escala de fuente
del sistema. Las pantallas se componen con medidas fijas (paneles, baldosas,
pastillas) y una escala del 150 % o del 200 % las rompería. Quien necesite el
texto más grande puede usar el zoom de pantalla del sistema, que sí afecta a la
app entera. Es deuda pendiente, no un olvido.

### Dispositivo de prueba y rendimiento

Probado en un **Samsung Galaxy A70** (Android 11, Snapdragon 675, 1080×2400 a
420 dpi) en vertical y en horizontal, y en una pantalla pequeña simulada de
360×640 dp. Todo el recorrido funciona: entrar, crear y editar un Tama,
cuidarlo, copiar el código, aceptar una solicitud, ver el perfil de un amigo y
escribir en su muro.

Medido con `addTimingsCallback` en una build de perfil sobre ese A70: el trabajo
de Dart se queda en unos 3 ms por fotograma (7,7 ms con la rejilla de Tamas
llena), pero el rasterizado ronda los 37 ms en el entorno y los 80 ms con doce
Tamas respirando a la vez, o sea entre 12 y 27 fotogramas por segundo. El coste
está en el plástico de la casa (sombras y rebajes desenfocados) a 1080×2400,
no en los Tamas. En ese teléfono la app se usa bien pero no va fina; **sigue
pendiente** cachear las superficies estáticas y bajar el ritmo de los Tamas que
no están en primer plano.

## Tests

```sh
flutter analyze          # sin avisos
flutter test             # entorno, Tamas, amigos y recorrido visual (PNG en build/screenshots/)
./tool/test_rules.sh     # reglas de seguridad contra el emulador de la Realtime Database
./tool/test_e2e.sh       # cuentas, Tamas, amigos y presencia contra los emuladores de Auth y Database
```

Los dos últimos levantan los emuladores de Firebase (procesos Java locales, no
emuladores de dispositivo), ejecutan y los apagan. Nunca tocan el proyecto real.

Para usar la app contra los emuladores:

```sh
firebase emulators:start --project demo-ibasho --only auth,database
dart run tool/dev_seed.dart   # cuatro cuentas de prueba, contraseña ibasho-dev
flutter run -d linux --dart-define-from-file=.env \
  --dart-define=IBASHO_USE_EMULATOR=true --dart-define=IBASHO_PROJECT_ID=demo-ibasho
```

`dev_seed.dart` deja a `adria` (admin) amigo de `mireia`, a quien le toca
cumpleaños hoy en Tokio; `laia` le ha mandado una solicitud a `adria` y `adria`
una a `pau`.

Los tests de reglas levantan el emulador de la Realtime Database (un proceso Java
local), cargan `database.rules.json` y comprueban, entre otras cosas, que:

- sin autenticar no se lee ni se escribe nada;
- una cuenta creada por fuera de la app con la API key (fuera de la allowlist)
  no puede leer ni escribir **absolutamente nada**;
- una cuenta deshabilitada pierde el acceso;
- un usuario no escribe en el nodo de otro ni en la allowlist;
- el admin da de alta, deshabilita, rehabilita y mueve el índice de nombres;
- cada campo del perfil valida tipo y longitud;
- crear el Tama número 100 es imposible aunque se llame a la API directamente,
  y el contador no se puede bajar, borrar ni saltar;
- solo quien creó un Tama edita su aspecto, y solo quien lo cuida escribe los
  cuidados;
- la lista de Tamas solo se lee con la consulta de «los que cuido yo»;
- quien no es tu amigo no lee tu perfil, tu presencia ni tu muro, solo tu ficha
  (nombre, color y Tama de perfil), y del Tama ajeno solo el aspecto;
- nadie entra en la lista de amigos de otro sin una solicitud pendiente, y solo
  acepta quien la recibió;
- el amigo número 101 es imposible, con el mismo patrón de contador que los Tamas;
- el muro acepta un mensaje por amigo y año, y rechaza el segundo;
- los códigos de amigo los da el admin con el contador y no se tocan nunca.

## Arquitectura

```
lib/
  backend/     IbashoBackend (contrato) y RestIbashoBackend (REST + SSE contra Firebase)
  state/       Riverpod: sesión, perfil, admin, Tamas, amigos, presencia, preferencias, reloj y estado del sistema
  storage/     sesión cifrada (libsecret o AES-256-GCM) y preferencias locales
  audio/       música, efectos y la voz sintetizada de los Tamas
  theme/       tokens de color, escala tipográfica, acentos legibles y piel en tiempo de ejecución
  ui/          lienzo virtual, controles propios, pantallas y canales
  ui/tama/     la criatura: pintor, animador, vista viva y piezas de interfaz
  ui/social/   presencia, avatares desde la ficha, insignias y tarjeta de visita
  l10n/        catálogos ARB es / en
tool/
  bootstrap_admin.dart   primer administrador
  dev_seed.dart          cuentas de prueba para los emuladores
  gen_audio.py           generador del set sonoro (CC0)
  test_rules.sh          tests de reglas
database.rules.json      reglas de seguridad
```

Decisiones de fondo:

- **Nada de FlutterFire.** No está soportado en Linux. Toda la comunicación es
  REST en Dart puro con `http`; la lectura en tiempo real usa
  `Accept: text/event-stream` con reconexión exponencial (tope 30 s).
- **La UI no sabe que hay REST.** Todo pasa por `IbashoBackend`, para poder
  cambiar a los SDK nativos en Android sin tocar nada más.
- **Sin Material.** La raíz es `WidgetsApp`; todos los controles son propios.
- **Dos composiciones, un solo árbol.** Con la ventana horizontal, el lienzo
  virtual de 800 de alto escalado con `FittedBox`; con la ventana vertical,
  pixeles logicos de verdad y las pantallas recolocadas. Lo decide la
  proporción de la ventana, no la plataforma, así que una ventana estrecha en
  Linux usa la vertical. Girar el móvil no desmonta nada: no se pierden ni la
  sesión, ni las rutas abiertas, ni la página en la que estabas.
- **Usuarios sin email.** El nombre visible se traduce a `<usuario>@ibasho.top`
  y nunca se muestra.
- **Los datos cuelgan de la cuenta, no del inicio de sesión.** Cada entrada de
  `/allowlist/{authUid}` apunta a un `accountId` estable, y los datos viven en
  `/users/{accountId}`. Regenerar una credencial crea un inicio de sesión nuevo
  que apunta a la misma cuenta y retira el viejo: no se pierde nada. Cambiar la
  contraseña propia (Ajustes → cuenta) no crea nada nuevo.
- **Música desbloqueable.** `/users/{accountId}/music` guarda las canciones
  desbloqueadas y la elegida para el menú. De serie hay cuatro (calma, aurora,
  brisa, noche); las de las apps se añaden la primera vez que suenan
  (`MusicLibraryController.markHeard`). Las reglas impiden elegir una que no
  se tenga.
- **Presencia por websocket.** REST no puede dejarle al servidor una escritura
  para cuando el cliente desaparezca, así que la presencia va por el protocolo
  de websocket de la Realtime Database (`lib/backend/rtdb_socket.dart`) con
  `onDisconnect`: cerrar la app, que se cuelgue o que se vaya la red deja a la
  persona desconectada sin que el cliente haga nada.
- **Efectos por SoLoud, música por audioplayers.** Los efectos necesitan
  disparo inmediato y repetible; la música, streaming y bucle. Cada motor hace
  lo suyo.

## Tamas

Un Tama es la criatura de Ibasho: mascota y avatar a la vez. Cada cuenta puede
tener hasta 99 y uno de ellos es el Tama de perfil, que vive en el panel superior
y en el perfil.

- **Dibujado en código.** `lib/ui/tama/tama_painter.dart` pinta cuerpo, ojos,
  boca, coronilla, mejillas, dibujo, brazos y pies sobre un lienzo lógico de
  100×100, con el brillo especular de la casa. No hay ni una imagen.
- **Vivo.** `TamaAnimator` respira, parpadea, salta y reacciona según su
  personalidad (tranquilo, juguetón, tímido, descarado, dormilón). La mirada
  sigue al ratón; en pantallas táctiles mira al último toque unos segundos, y si
  no hay nada, curiosea a su aire. Con movimiento reducido se queda quieto.
- **Voz sintetizada.** `lib/audio/tama_voice.dart` genera cada graznido al
  vuelo con uno de seis timbres (suave, clara, redonda, silbido, ronroneo y
  burbuja); el patrón de sílabas sale del nombre, así que dos Tamas con nombres
  distintos no suenan igual. Va por el mismo motor que los efectos y obedece a
  su volumen.
- **Comida de verdad.** Diez chuches dibujadas en `lib/ui/tama/tama_food.dart`
  (galleta, caramelo, magdalena, manzana, dango, mochi, piruleta, helado, dónut
  y flan) que se eligen en una tira deslizable de la habitación. De serie solo
  se tienen la galleta y el caramelo; el resto sale bloqueado hasta que llegue
  la tienda (`unlockedFoodsProvider`).
- **Un registro por Tama.** `/tamas/{tamaId}` guarda `creator` y `keeper`. Solo
  el creador edita nombre, personalidad, voz y aspecto; el cuidador escribe los
  cuidados. Traspasar un Tama a un amigo será cambiar `keeper`.
- **Tope en las reglas.** Crear o borrar un Tama va en la misma escritura
  multi-ruta que `/users/{accountId}/tamaCount` (+1 o −1 exacto, máximo 99) y
  que `tamaLastChange`, el id del Tama afectado.
- **El humor no se guarda.** Se calcula en el cliente a partir de `lastPetted` y
  `lastFed`, que son lo único que escriben los cuidados. Un Tama desatendido se
  pone melancólico; nunca enferma ni muere.
- **Color y acento.** El color se elige de una paleta cerrada de 16 tonos o en
  HEX libre, y se guarda qué modo se usó. El acento del entorno puede seguir al
  Tama de perfil (ajustado para leerse sobre blanco); si se eligió a mano, se
  pregunta antes de cambiarlo.

## Amigos

- **Códigos de amigo** de doce dígitos, `1234-5678-9012`. Once salen de pasar el
  contador `/system/friendCodeCounter` por una permutación afín del espacio de
  once dígitos (única por construcción, sin comprobar colisiones); el duodécimo
  es un dígito de control de **Damm**, que detecta todo error de un dígito y
  toda transposición de dos contiguos. El campo lo comprueba mientras se
  escribe, sin tocar la red, y distingue «no es válido» de «nadie lo tiene».
  Las constantes no son secretas: un código no es una credencial.
- **Ficha reducida.** Quien busca tu código ve `/users/{accountId}/card`:
  nombre, color y Tama de perfil. El perfil, la presencia, el muro y la lista de
  amigos solo los leen tus amigos. Del Tama de perfil ajeno se lee el aspecto,
  nunca los cuidados.
- **Solicitudes** por parejas (`requests/out` y `requests/in`) en una sola
  escritura; aceptar crea las dos amistades, mueve los dos contadores y borra
  las solicitudes a la vez. Solicitudes cruzadas se aceptan solas. Tope de 100
  amigos en las reglas. No hay bloqueo.
- **Presencia** conectado, ausente, no molestar, invisible y desconectado. El
  estado publicado es el que se elige —conectado mientras no se elija otra
  cosa—, sin estados automáticos: fuera de la app, desconectado. Invisible
  publica exactamente lo mismo que una desconexión real y no deja nada
  encargado que la delate.
- **Perfiles ajenos** con el Tama vivo, la hora local de su zona al segundo y la
  diferencia con la tuya, insignias, desde cuándo sois amigos y su música, que
  entra con un fundido sobre la de ambiente y se puede silenciar para siempre.
- **Tarjeta de visita** exportable a PNG (1800×1020) con tu Tama, tu nombre, tu
  color y tu código.
- **Muro de cumpleaños.** El día del cumpleaños (en la zona de quien cumple) el
  perfil se viste de fiesta, el Tama lleva gorrito y los amigos dejan un
  mensaje por año, de hasta 140 caracteres. Las reglas no pueden saber qué día
  es: eso lo decide el cliente, y está documentado en las propias reglas.

## Versiones y bloqueo

La versión de la app vive en `lib/core/version.dart` (`appVersion`, igual que
`version:` de `pubspec.yaml`; un test lo comprueba). Para obligar a actualizar:

1. Sube las dos a la versión nueva, compila y comparte la build.
2. Ábrela con una cuenta de administración, canal **administración** →
   **versión mínima**, pon (si quieres) la página de descarga y pulsa
   **exigir la X.Y.Z**.

Desde ese momento cualquier build anterior, abierta o no, muestra el aviso de
actualizar en lugar del login o del entorno, con el botón de descarga. Se lee de
`/system/update` sin sesión y en tiempo real; **quitar el bloqueo** lo deshace.
Solo se puede exigir la versión de la build desde la que se pulsa, para no
dejarse fuera. También vale la CLI:

```sh
firebase database:set /system/update --data '{"minVersion":"0.4.0","url":"https://…"}'
```

Es un cerrojo de la app para que el grupo actualice, no una defensa: un cliente
modificado podría ignorarlo.

## Hoja de ruta

- **0.1.0 · checkpoint 1** — entorno y cuentas. Hecho.
- **0.2.0 · checkpoint 2** — los Tamas: las mascotas de Ibasho. Creador con
  piezas y ajustes finos, nombre, personalidad y voz; muchos Tamas por cuenta y
  uno en el perfil; mimos y comida con un humor que cambia con calma. Hecho.
- **0.3.0 · checkpoint 3** — amigos y perfiles: códigos de amigo, solicitudes,
  presencia, perfiles con hora local y música, tarjeta de visita y muro de
  cumpleaños. Hecho.
- **0.3.1 · checkpoint 3.1** — Android: composición vertical, táctil, botón de
  atrás, ciclo de vida, foco de audio y empaquetado. Hecho.
- **0.4.0** — mensajería.
- **Más adelante** — **traspasar un Tama** a un amigo para que lo cuide y juegue con él (quien lo
  creó sigue siendo quien edita su aspecto, y el cuidador ve los cambios al
  momento); una tienda donde desbloquear chuches; jugar con los Tamas, accesorios, mensajería, notificaciones,
  monedas, micro-apps y Windows.

## Licencia

GPL-3.0-or-later. Ver [`LICENSE`](LICENSE). Los assets de terceros y sus
licencias están en [`CREDITS.md`](CREDITS.md).
