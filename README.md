# Ibasho · 居場所

> *tu lugar*

Ibasho es un espacio de juegos multiplataforma inspirado en los menús de sistema
de Wii y Nintendo 3DS: un launcher de micro-apps con avatares propios (los
**Tamas**), cuentas, amigos y mensajería.

Este repositorio está en el **checkpoint 1**: el entorno y el sistema de
cuentas. Todavía no hay apps dentro, pero el entorno ya se puede usar: splash,
login, cambio obligatorio de contraseña, entorno de dos paneles con reloj y barra
de estado, rejilla de canales con paginación y animación de apertura, perfil,
ajustes, créditos y panel de administración.

Plataforma de este checkpoint: **Linux desktop**.

---

## Requisitos

- Flutter stable (probado con 3.41) y Dart 3.
- Toolchain de Linux desktop: `clang`, `cmake`, `ninja`, `pkg-config`, `gtk3`.
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

Crea la cuenta en Identity Toolkit y escribe `/allowlist`, `/admins` y
`/usernames` con la CLI de Firebase, que usa tus credenciales de desarrollador y
por eso puede saltarse las reglas. Imprime una contraseña de un solo uso: la app
te pedirá cambiarla al entrar. Si se corta a medias, vuelve a lanzarlo con
`--password <la que imprimió>` y retoma donde lo dejó.

A partir de ahí todo se hace desde la app: el canal **administración** crea
cuentas, las deshabilita y regenera credenciales.

### 4. Ejecutar

```sh
flutter run -d linux --dart-define-from-file=.env
```

## Tests

```sh
flutter analyze          # sin avisos
flutter test             # comportamiento del entorno y recorrido visual (PNG en build/screenshots/)
./tool/test_rules.sh     # reglas de seguridad contra el emulador de la Realtime Database
./tool/test_e2e.sh       # flujo de cuentas completo contra los emuladores de Auth y Database
```

Los dos últimos levantan los emuladores de Firebase (procesos Java locales, no
emuladores de dispositivo), ejecutan y los apagan. Nunca tocan el proyecto real.

Para usar la app contra los emuladores:

```sh
firebase emulators:start --project demo-ibasho --only auth,database
flutter run -d linux --dart-define-from-file=.env \
  --dart-define=IBASHO_USE_EMULATOR=true --dart-define=IBASHO_PROJECT_ID=demo-ibasho
```

Los tests de reglas levantan el emulador de la Realtime Database (un proceso Java
local), cargan `database.rules.json` y comprueban, entre otras cosas, que:

- sin autenticar no se lee ni se escribe nada;
- una cuenta creada por fuera de la app con la API key (fuera de la allowlist)
  no puede leer ni escribir **absolutamente nada**;
- una cuenta deshabilitada pierde el acceso;
- un usuario no escribe en el nodo de otro ni en la allowlist;
- el admin da de alta, deshabilita, rehabilita y mueve el índice de nombres;
- cada campo del perfil valida tipo y longitud.

## Arquitectura

```
lib/
  backend/     IbashoBackend (contrato) y RestIbashoBackend (REST + SSE contra Firebase)
  state/       Riverpod: sesión, perfil, admin, preferencias, reloj y estado del sistema
  storage/     sesión cifrada (libsecret o AES-256-GCM) y preferencias locales
  audio/       música y efectos
  theme/       tokens de color, escala tipográfica y piel en tiempo de ejecución
  ui/          lienzo virtual, controles propios, pantallas y canales
  l10n/        catálogos ARB es / en
tool/
  bootstrap_admin.dart   primer administrador
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
- **Lienzo virtual de 1280×800** escalado con `FittedBox` y bandas a los lados.
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
- **Efectos por SoLoud, música por audioplayers.** Los efectos necesitan
  disparo inmediato y repetible; la música, streaming y bucle. Cada motor hace
  lo suyo.

## Licencia

GPL-3.0-or-later. Ver [`LICENSE`](LICENSE). Los assets de terceros y sus
licencias están en [`CREDITS.md`](CREDITS.md).
