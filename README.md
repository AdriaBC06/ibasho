# Ibasho · 居場所

> *tu lugar*

Ibasho es un espacio de juegos multiplataforma inspirado en los menús de sistema
de Wii y Nintendo 3DS: un launcher de micro-apps con avatares propios (los
**Tamas**), cuentas, amigos y mensajería.

Este repositorio está en el **checkpoint 5** (0.5.0): el entorno, las cuentas,
los **Tamas**, los **amigos**, **hablar** y, ahora, **la tienda**. En Linux,
Android y Windows. El entorno ya se puede usar: splash, login, cambio
obligatorio de contraseña, entorno de dos paneles con reloj y barra de estado,
rejilla de canales con paginación y animación de apertura, perfil, ajustes,
créditos, panel de administración, el canal de Tamas con su creador y la
habitación de cada uno, el canal de amigos —códigos al estilo 3DS, solicitudes,
presencia, perfiles con la hora local y la música de cada cual, tarjeta de
visita exportable y muro de cumpleaños—, **mensajes** cifrados de punta a punta
con stickers de tus Tamas y un grupo abierto, **noticias** con encuestas
anónimas, **sugerencias** con respuesta y **Yatai** (屋台), el puesto donde se
gastan las monedas: juegos que se activan —el primero, un buscaminas con tu
Tama al lado, medallas, tablero del día y premios en monedas— y comida para los
Tamas, que ahora se gasta al dársela.

Plataformas: **Linux desktop**, **Android** (móvil y tableta) y **Windows 10 o
posterior**, de 64 bits. Ni la 0.3.1 ni la 0.3.3 añaden funcionalidades: llevan
a cada plataforma nueva exactamente lo que ya había. Android trajo la
composición vertical y lo que un móvil necesita (táctil, botón de atrás, ciclo
de vida, foco de audio); Windows no necesitó ninguna rama de composición, porque
usa la de escritorio y hereda la vertical al estrechar la ventana.

---

## Requisitos

- Flutter stable (probado con 3.41) y Dart 3.
- Toolchain de Linux desktop: `clang`, `cmake`, `ninja`, `pkg-config`, `gtk3`.
- Para Windows: **Visual Studio 2022** (vale la edición Build Tools) con la carga
  de trabajo *Desarrollo de escritorio con C++* **y el componente C++ ATL**, que
  no viene marcado por defecto y sin el cual `flutter_secure_storage` no compila
  (`atlstr.h: No such file or directory`). Hace falta además el **Modo de
  desarrollador** de Windows activado, porque la compilación con plugins usa
  enlaces simbólicos. Para empaquetar, Inno Setup 6.
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
flutter run -d linux --dart-define-from-file=.env          # escritorio Linux
flutter run -d windows --dart-define-from-file=.env        # escritorio Windows
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

## Windows

La app es la misma y el árbol de widgets también. Windows usa la composición de
escritorio, la de 1280×800, y no tiene ninguna rama propia de disposición: si se
estrecha la ventana hasta que sea más alta que ancha, salta a la composición
vertical igual que en Linux.

### Compilar

```powershell
flutter build windows --release --dart-define-from-file=.env
```

Queda en `build\windows\x64\runner\Release\`: `ibasho.exe`, los DLL de los
plugins y la carpeta `data\`. Flutter no sabe producir un `.exe` único; para
repartir hay que empaquetar.

Dos requisitos que no son obvios y cuyo error no se explica solo:

- **Componente C++ ATL.** La carga de trabajo de escritorio de Visual Studio no
  lo marca por defecto, y sin él `flutter_secure_storage` falla con
  `atlstr.h: No such file or directory`. En Build Tools se añade con
  `--add Microsoft.VisualStudio.Component.VC.ATL`.
- **Modo de desarrollador.** Sin él la compilación se detiene con *Building with
  plugins requires symlink support*. Se activa en
  *Configuración → Sistema → Para programadores*.

### Empaquetar

```powershell
.\tool\package_windows.ps1              # compila en release con .env y empaqueta
.\tool\package_windows.ps1 -SkipBuild   # solo empaqueta lo ya compilado
```

Deja dos cosas en `dist\`, con la versión sacada de `pubspec.yaml`:

- `Ibasho-<versión>-windows-x64-setup.exe` — instalador de un solo fichero.
- `Ibasho-<versión>-windows-x64.zip` — la misma build, portable.

El instalador lo describe `windows\packaging\ibasho.iss` (Inno Setup 6). Se
instala **sin pedir administrador**, en `%LOCALAPPDATA%\Programs\Ibasho`, igual
que en Linux todo va a `~/.local`. Las preferencias y la sesión guardada viven
aparte y desinstalar no las toca.

### La música va en MP3

Las pistas viven en Ogg Vorbis, pero Windows no lo decodifica: `audioplayers`
usa Media Foundation y allí el Ogg no suena, mientras los efectos, que van por
SoLoud, sí. Por eso cada pista tiene un `.mp3` al lado del `.ogg` y en Windows
se pide ese; Linux y Android siguen con los `.ogg` originales. Si se añade una
pista hay que generar las dos:

```sh
ffmpeg -i assets/audio/bgm/nueva.ogg -c:a libmp3lame -q:a 2 -map_metadata -1 assets/audio/bgm/nueva.mp3
```

### Qué hace falta en la máquina que lo ejecuta

Windows 10 de 64 bits o posterior, y nada más. El instalador y el zip llevan
dentro `msvcp140.dll`, `vcruntime140.dll` y `vcruntime140_1.dll`: un Windows
recién instalado trae el CRT universal (`api-ms-win-crt-*`) pero no el runtime
de Visual C++, y sin él la app no arranca ni dice por qué falta. Lo copia
`tool\package_windows.ps1` desde el redistribuible de Visual Studio.

El ejecutable no va firmado con certificado, así que la primera vez SmartScreen
avisa y hay que elegir *Más información → Ejecutar de todas formas*.

## Integración continua

`.github/workflows/build.yml` compila las tres plataformas y sube cada una como
artefacto. Se dispara al empujar a `main`, al publicar una etiqueta `v*` y a
mano desde la pestaña *Actions*.

Primero corre un trabajo de comprobación con `dart analyze` y `flutter test`; si
falla, no se compila nada. Después, un trabajo por plataforma:

| Plataforma | Runner | Artefacto |
|---|---|---|
| Linux | `ubuntu-latest` | `Ibasho-<versión>-linux-x64.tar.gz` |
| Android | `ubuntu-latest` | `Ibasho-<versión>-android.apk` |
| Windows | `windows-latest` | instalador `.exe` y zip |

El `.env` **se reconstruye en el runner desde los *secrets*** del repositorio y
nunca sale del árbol. Hay que dar de alta `IBASHO_API_KEY` e
`IBASHO_DATABASE_URL`; `IBASHO_PROJECT_ID` e `IBASHO_EMAIL_DOMAIN` son
opcionales.

La firma de Android también es opcional: si están `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD`, el
APK sale firmado; si no, sale con la firma de depuración sin romper la build.

La versión del SDK está fijada en `FLUTTER_VERSION` y es la misma que registra
`.metadata`. Subirla no es inocuo: con una Flutter más nueva, `flutter_localizations`
exige `intl ^0.20.3` y la resolución de dependencias falla contra el `intl 0.20.2`
que fija `pubspec.yaml`.

Para añadir una plataforma se añade una entrada a la matriz de `compilar` y su
bloque de pasos con `if: matrix.plataforma == ...`; lo común —checkout, SDK,
`.env`, versión y subida del artefacto— ya está resuelto para todas.

## Tests

```sh
flutter analyze          # sin avisos
flutter test             # entorno, Tamas, amigos, cifrado, mensajes y recorrido visual (PNG en build/screenshots/)
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
- los códigos de amigo los da el admin con el contador y no se tocan nunca;
- la clave pública la lee cualquier miembro y **el respaldo sólo su dueña**, ni
  siquiera un administrador;
- las monedas las pone un admin y **nadie se las pone a sí mismo**;
- una conversación sólo se abre entre amigos y sólo en su sitio (el id son los
  dos `accountId` ordenados, y las reglas lo comprueban contra `a` y `b`), sólo
  la leen los dos que hablan, y un mensaje va firmado por quien lo manda y
  cerrado para los dos;
- un mensaje no se puede editar una vez dicho, y cualquiera de los dos puede
  borrar para podar;
- sin estar dentro del grupo no se lee ni se escribe nada, y unirse exige la
  clave pública propia y que el grupo esté abierto;
- el voto de una encuesta sube un recuento **de uno en uno** y sólo apuntándose
  como votante, y **lo que uno vota no lo lee nadie más**, tampoco el admin;
- una sugerencia viva por cuenta, nadie manda en nombre de otro ni se firma su
  propio veredicto, y el buzón se puede cerrar para todos.

Los dos ficheros de reglas (`rules.test.mjs` y `rules_04.test.mjs`) comparten
un único emulador y cada uno vacía la base antes de cada caso, así que van en
serie (`node --test --test-concurrency=1`): en paralelo se pisan.

## Arquitectura

```
lib/
  backend/     IbashoBackend (contrato) y RestIbashoBackend (REST + SSE contra Firebase)
  crypto/      cifrado de punta a punta: claves, sobres, frase de respaldo y el isolate que lo abre
  state/       Riverpod: sesión, perfil, admin, Tamas, despensa, amigos, presencia, identidad, mensajes, noticias, sugerencias, monedas, tienda, preferencias, reloj y estado del sistema
  games/       los juegos que se activan en el Yatai (hoy, el buscaminas)
  storage/     sesión cifrada (libsecret, DPAPI o AES-256-GCM) y preferencias locales
  audio/       música, efectos y la voz sintetizada de los Tamas
  theme/       tokens de color, escala tipográfica, acentos legibles y piel en tiempo de ejecución
  ui/          lienzo virtual, controles propios, pantallas y canales
  ui/tama/     la criatura: pintor, animador, vista viva, stickers y piezas de interfaz
  ui/social/   presencia, avatares desde la ficha, insignias y tarjeta de visita
  l10n/        catálogos ARB es / en
tool/
  bootstrap_admin.dart   primer administrador
  post_news.dart         publicar en el tablón sin abrir la app
  seed_shop.dart         precios del Yatai
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
- **El servidor no puede leer los mensajes, y no es una promesa: es que no
  tiene la clave.** Las reglas de la base sólo comprueban quién escribe y para
  quién va cada sobre; lo que hay dentro no lo pueden mirar. Todo el cifrado es
  `pointycastle` en Dart puro, igual que el resto de la red.
- **Lo caro no va en el hilo que pinta.** Abrir un sobre cuesta una
  multiplicación escalar sobre la curva —unos 9 ms en un portátil, bastante más
  en un móvil—, así que descifrar y cifrar pasan por un isolate, y una
  conversación se abre por tandas empezando por los últimos mensajes.
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
  se tienen la galleta y el caramelo; el resto sale bloqueado
  (`unlockedFoodsProvider`). Cada comida va **por unidades**: darla gasta una,
  la cuenta empieza con 5 de cada una de serie y se reponen en el Yatai.
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

## Mensajes

Los mensajes de Ibasho van **cifrados de punta a punta**: quien tenga la base de
datos delante ve sobres cerrados, marcas de tiempo y quién habla con quién, y
nada más. Ni el administrador ni el dueño del proyecto pueden leerlos.

- **Cada cuenta tiene un par de claves** ECDH sobre P-256, generado en el
  aparato la primera vez que se entra. La pública se publica en
  `/users/{accountId}/keys/pub`, porque sin ella nadie podría escribirte.
- **Cada mensaje lleva su propia clave** AES-256-GCM y un par efímero. La clave
  se envuelve una vez por destinatario (ECDH efímero → HKDF-SHA256 → AES-GCM),
  así que un mensaje de grupo se cifra una sola vez y no N veces.
- **Stickers**: uno de tus Tamas con una de ocho caras. El aspecto viaja dentro
  del sobre, no por referencia: se sigue viendo igual aunque luego edites o
  borres ese Tama, y lo ve quien lo recibe aunque no tenga permiso para leerlo.
- **El grupo «Global»** lo crea un administrador desde su panel. Cualquiera se
  une, nadie invita, y **hasta que no entras no se descarga ni un mensaje**. Al
  entrar ves lo que se escriba a partir de ese momento, nunca lo anterior:
  es lo que se paga por que no haga falta que nadie esté conectado para
  repartir claves. Tope de 32 miembros, que es el del sobre.
- **El historial se poda solo**: 300 mensajes por conversación y nada de más de
  90 días. Lo borra el mismo cliente que escribe, en la misma operación.

### La clave de respaldo

La clave privada vive en el llavero del sistema —libsecret en Linux, DPAPI en
Windows, el Keystore en Android— y, envuelta con una frase de **doce palabras**,
en la base. La frase se enseña **una sola vez** al crear la cuenta; después se
puede volver a mirar en **ajustes → ver mi clave de respaldo**, pero sólo desde
un aparato que la tenga guardada: del respaldo de la base no se saca.

```
brisa  tatami  cobre  helecho
quinto lima    nieve  farol
tinta  roble   dulce  isla
```

En un móvil nuevo, o tras reinstalar, se teclea una vez y vuelve el historial
entero. Se puede escribir en mayúsculas, con tildes que la lista no lleva, o
cortando cada palabra a partir de la cuarta letra, que ya identifica a una sola.

**No depende de la contraseña**, y es deliberado: un administrador puede
resetear la contraseña de una cuenta —es lo que hace `regenerar credencial`— sin
llevarse por delante un solo mensaje, y sigue sin poder leer ninguno. Lo que sí
pasa es que **si se pierde la frase y no queda ningún aparato con la clave, ese
historial no lo recupera nadie**. Es el precio de que no haya una puerta de
atrás.

## Noticias y sugerencias

- **Noticias**: novedades de versión, avisos y encuestas. Las publica un
  administrador desde el canal, o `tool/post_news.dart` sin abrir la app:

  ```sh
  dart run tool/post_news.dart --kind update --title "Ibasho 0.4.0" \
      --version 0.4.0 --body "Mensajes cifrados, noticias y sugerencias."

  dart run tool/post_news.dart --kind poll --title "¿Qué viene después?" \
      --option "Un minijuego" --option "Una tienda" --closes 7

  dart run tool/post_news.dart --list
  ```

- **Las encuestas son anónimas de verdad, no sólo en la pantalla.** En la
  entrada quedan dos cosas: cuántos votos lleva cada opción y quién ya ha
  votado. **A qué votó cada cual** vive únicamente en `/users/{cuenta}/votes`,
  que no lee nadie más. El precio es que las reglas no pueden comprobar que el
  −1 de un cambio de voto caiga en la opción que tenías antes; en un grupo de
  conocidos es un precio razonable a cambio de que el recuento no tenga nombres.
- **Sugerencias**: título de 30 y texto de 200. Una viva por cuenta —hasta que
  no hay veredicto no se puede mandar otra, y lo aplican las reglas—, el
  administrador acepta o rechaza con un motivo opcional, y lo aceptado pasa a
  una lista pública. El buzón se cierra desde el mismo canal.

## Monedas y Yatai

Un contador por cuenta en la barra de estado, junto a la batería y la señal.
Las monedas las da un administrador desde su panel, y se ganan jugando: cada
victoria en un juego del Yatai da unas pocas, con un **tope de 20 al día**.
Nadie puede ponérselas a sí mismo de otra forma. Se gastan en el **Yatai**
(屋台, el puesto de feria), el canal de la tienda:

- **Juegos.** Vienen dentro de la app; comprarlos solo los activa. Un juego
  recién comprado aparece en la rejilla **envuelto como un regalo**, y al
  tocarlo se desenvuelve y queda como un canal más. El primero es un
  buscaminas en una sola escena: uno de tus Tamas, distinto en cada ronda,
  reacciona a cada jugada y habla en un bocadillo junto al tablero. Tres
  niveles y un tablero del día, medallas por tiempo, el sello «sin banderas» y
  una pantalla de resultados con las monedas ganadas (3, 5 u 8).
- **Tamas.** Unidades de comida, solo de las que la cuenta tiene desbloqueadas.
- **Gacha.** Próximamente.

Cobrar un premio también es una escritura multi-ruta: `/users/{cuenta}/rewards`
(`{game, day, earned, at}`, con `day` el día UTC) y el saldo nuevo. Las reglas
exigen tener el juego, que el cobro sea de hoy, de 3, 5 u 8 (o lo justo para
llegar al tope), que no pase de 20 al día, que haya 15 s desde el anterior y
que el saldo suba exactamente lo cobrado.

Cada compra es **una sola escritura multi-ruta**: un recibo en
`/users/{cuenta}/shop/last` (`{item, qty, at}` con `at` del servidor), el saldo
nuevo y lo comprado (`pantry/{comida}` o `games/{juego}`). Las reglas
comprueban unas ramas contra otras: el recibo tiene que ser de este mismo
instante, el saldo tiene que bajar exactamente precio × cantidad, y la despensa
o el juego solo cambian si el recibo lo justifica. Los precios viven en
`/shop/prices`; los escribe el administrador y se cargan con:

```sh
dart run tool/seed_shop.dart
```

Un artículo sin precio sale como «no disponible».

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
firebase database:set /system/update --data '{"minVersion":"0.5.0","url":"https://…"}'
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
- **0.3.2** — arreglos sobre la 0.3.1: sonido de medios en el móvil y estados de
  presencia. Hecho.
- **0.3.3 · checkpoint 3.2** — Windows: runner propio, instalador de un solo
  fichero, runtime de Visual C++ incluido e integración continua para las tres
  plataformas. Hecho.
- **0.4.0 · checkpoint 4** — hablar: canal de noticias con encuestas anónimas,
  mensajería cifrada de punta a punta con stickers de Tama y grupo abierto,
  buzón de sugerencias con veredicto, y contador de monedas. Hecho.
- **0.5.0 · checkpoint 5** — la tienda: canal Yatai con juegos que se activan y
  llegan envueltos como regalo, el buscaminas con medallas, tablero del día y
  premios en monedas, y comida por unidades para los Tamas. Hecho.
- **Más adelante** — el **gacha** del Yatai; **traspasar un Tama** a un amigo
  para que lo cuide y juegue con él (quien lo creó sigue siendo quien edita su
  aspecto, y el cuidador ve los cambios al momento); más juegos, jugar con los
  Tamas, accesorios y notificaciones.

## Licencia

GPL-3.0-or-later. Ver [`LICENSE`](LICENSE). Los assets de terceros y sus
licencias están en [`CREDITS.md`](CREDITS.md).
