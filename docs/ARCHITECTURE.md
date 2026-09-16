# Arquitectura de Ibasho

Estado del proyecto en la versión **0.3.1** (checkpoint 3.1: Android). Este documento
describe lo que existe en el repositorio.

Plataformas: Linux desktop y Android. Flutter stable 3.41, Dart 3 (`sdk: ^3.11.0`).
Un solo árbol de widgets para las dos: lo que cambia está en `lib/ui/canvas.dart`
(la forma del lienzo), `lib/ui/layout.dart` (las medidas de cada composición),
`lib/ui/touch.dart` (zonas táctiles), `lib/ui/mobile.dart` (ciclo de vida, atrás
e inmersivo) y `lib/core/device.dart` (la única bandera de plataforma).

---

## 1. Estructura de carpetas

```
lib/
  main.dart            arranque: preferencias, almacén seguro, audio y ProviderScope
  app.dart             IbashoApp (WidgetsApp) y AppRoot (splash / login / cambio de contraseña / entorno)
  audio/
    audio_service.dart   AudioService: música (audioplayers), efectos y voces (flutter_soloud)
    tama_voice.dart      síntesis de las voces de los Tamas (WAV en memoria)
  backend/
    ibasho_backend.dart  contrato IbashoBackend
    rest_ibasho_backend.dart  implementación REST
    identity_toolkit.dart    Identity Toolkit y Secure Token por REST
    rtdb_client.dart         Realtime Database por REST y text/event-stream
    rtdb_socket.dart         PresenceLink y RtdbSocket: websocket de la Realtime Database (onDisconnect)
    live_tree.dart           aplica eventos put/patch a una copia local de un nodo
    push_id.dart             ids cronológicos de 20 caracteres
    models.dart              AuthTokens, AllowlistEntry, UserProfile, DatabaseEvent, DatabaseQuery, serverTimestamp…
    tama.dart                modelo de los Tamas (Tama, TamaLook, TamaWear, TamaVoice, TamaCare, TamaFood, humor)
    social.dart              UserCard, PresenceMode, PresenceState, Presence, Friendship, FriendRequest, WallMessage
    errors.dart              IbashoFailure e IbashoException
  core/
    device.dart        Device.isAndroid: la unica rama por plataforma
    env.dart           configuración inyectada en compilación (Env)
    credits.dart       lista de créditos que muestra la app
    timezones.dart     zonas horarias IANA embebidas; offsetOfZone y wallClockIn
    version.dart       appVersion y AppVersion (comparación mayor.menor.parche)
    friend_code.dart   FriendCode: permutacion afin, digito de control de Damm y formato
    birthday.dart      isBirthdayToday, wallYearFor, ageToday y zoneDifference
  l10n/
    app_es.arb         catálogo plantilla (español)
    app_en.arb         catálogo inglés
    gen/               clase L generada por `flutter gen-l10n` (ignorada por git)
  state/               Riverpod 2 (StateNotifier)
    providers.dart     cableado de todos los providers
    session.dart       SessionController
    profile.dart       ProfileController
    admin.dart         AdminController
    tamas.dart         TamasController
    accent_sync.dart   decisión de sincronizar el acento con el Tama de perfil
    card.dart          cardFor, cardForProfile, cardForTama y cardKeeperProvider (ficha pública)
    friends.dart       FriendsController: código, amigos, solicitudes, búsqueda y muro
    presence.dart      PresenceController: estado elegido y publicación (con onDisconnect)
    update_gate.dart   UpdateRequirement, updateRequirementProvider y updateLockedProvider
    people.dart        datos en vivo de otras cuentas (ficha, Tama público, perfil, presencia, música, muro)
    pantry.dart        unlockedFoodsProvider
    music_library.dart MusicLibraryController
    preferences.dart   PreferencesController
    system_status.dart Clock y SystemStatusController (batería y conexión)
    debug.dart         DebugController
  storage/
    secure_store.dart  sesión cifrada (libsecret o archivo AES-256-GCM)
    settings_store.dart preferencias locales en JSON
  theme/
    tokens.dart        colores, medidas y duraciones (clase T)
    type.dart          escala tipográfica (clase Ty)
    skin.dart          IbashoSkin: acento y movimiento reducido en tiempo de ejecución
    accent.dart        contraste y acentos legibles
  ui/
    canvas.dart        lienzo: horizontal escalado o vertical a tamaño real (VirtualCanvas, CanvasSize)
    layout.dart        Layout: las medidas de la composicion en curso, y PageSwipe
    touch.dart         zonas tactiles de 48 dp: TouchAssist, MinTouchSize, fingerKinds
    mobile.dart        solo Android: ciclo de vida, boton de atras, modo inmersivo
    failure_text.dart  IbashoFailure → texto traducido
    track_text.dart    descripción traducida de cada pista
    widgets/           controles propios (ver §3)
    tama/              la criatura: pintor, animador, vista, comida y piezas de interfaz
    social/            presencia, CardTama, insignias, entrada del código y tarjeta de visita
    screens/           splash, login, cambio de contraseña, versión antigua, entorno, rejilla, rutas
      channels/        ajustes, perfil, Tamas, amigos, administración, depuración, créditos, próximamente
      tama/            habitación y creador de un Tama
      friends/         añadir amigo, perfil de un amigo y muro de cumpleaños
android/                   proyecto de Android (manifiesto, Gradle, iconos, MainActivity)
test/
  tall_tour_test.dart      recorrido visual en vertical, en dos tamaños de movil
  touch_targets_test.dart  ninguna zona tactil por debajo de 48 dp; asistente en horizontal
  shell_test.dart          comportamiento del entorno
  tama_test.dart           Tamas: creación, edición en vivo, color, humor, movimiento reducido, idioma, voz, acento
  glyphs_test.dart         normas de dibujo de los iconos, con píxeles
  tama_food_test.dart      la comida cabe en su círculo; desbloqueos de serie
  visual_tour_test.dart    renderiza pantallas a PNG
  tama_gallery_test.dart   renderiza combinaciones de Tamas, bocas, comida e iconos a PNG
  friend_code_test.dart    permutación, Damm, formato
  update_gate_test.dart    versión de pubspec, comparación, bloqueo en vivo y desde el admin
  friends_test.dart        amigos: búsqueda, solicitudes, perfil ajeno, música, muro, presencia, idioma, tarjeta, gorrito
  support/fakes.dart       FakeIbashoBackend (base en memoria compartible), FakePresenceLink, FakeSecureStore, FakeSettingsStore, sampleTama, seedSocial
  e2e/backend_e2e_test.dart  flujo de cuentas, Tamas, amigos y presencia contra los emuladores
  e2e/presence_holder.dart   proceso sin Flutter que abre el websocket y se deja matar (onDisconnect real)
  rules/rules.test.mjs     tests de database.rules.json (Node)
tool/
  bootstrap_admin.dart   crea la primera cuenta de administración, con su código de amigo
  dev_seed.dart          cuentas y amistades de prueba en los emuladores
  gen_audio.py           genera la música propia y los efectos
  test_rules.sh          lanza los tests de reglas con el emulador
  test_e2e.sh            lanza el e2e con los emuladores
assets/                  audio (bgm, sfx) y fuentes con sus licencias
reserved/audio/bgm/      audio con licencia verificada que no se empaqueta
database.rules.json      reglas de seguridad de la Realtime Database
firebase.json            configuración de la CLI y de los emuladores
.env.example             plantilla de configuración
```

### Capas

- **UI** (`lib/ui`) lee estado de Riverpod y llama a controladores. No importa
  nada de `lib/backend/rest_*`, `rtdb_client` ni `identity_toolkit`.
- **Estado** (`lib/state`) habla con el servidor solo a través de
  `IbashoBackend`. Las rutas de la base (`/users/...`, `/tamas/...`) viven aquí.
- **Backend** (`lib/backend`) es el único código que conoce Firebase.
  `backendProvider` es el único punto que instancia `RestIbashoBackend`.

La raíz de la app es `WidgetsApp`. `pubspec.yaml` tiene
`uses-material-design: false` y ningún archivo de `lib/` importa
`package:flutter/material.dart` ni `cupertino.dart` (lo comprueba
`test/tama_test.dart`).

### Arranque (`lib/main.dart`)

1. `initializeDateFormatting('es')` y `('en')`.
2. `SettingsStore.open()` y `load()` → `Preferences`.
3. `openSecureStore()`.
4. `AudioService.instance.init()`, `setTrack`, `setMusicVolume` y
   `setEffectsVolume` con las preferencias guardadas.
5. `runApp(ProviderScope(overrides: [secureStoreProvider, settingsStoreProvider,
   initialPreferencesProvider], child: IbashoApp()))`.

`IbashoApp.builder` envuelve el navegador en `IbashoSkin` →
`DefaultTextStyle(Ty.body)` → `MobileLifecycle` → `TamaPointerTracker` →
`TouchAssist` → `VirtualCanvas`.
`AppRoot` muestra el splash un mínimo de 2,4 s mientras `SessionController.restore()`
resuelve la sesión. Después, si `updateLockedProvider` es `true`, muestra
`UpdateRequiredScreen` en lugar del login o del entorno (y cierra lo que hubiera
abierto al pasar a bloqueado); si no, la pantalla de la fase de sesión.

### Providers (`lib/state/providers.dart`, `pantry.dart`, `debug.dart`)

| Provider | Tipo | Contenido |
|---|---|---|
| `secureStoreProvider` | `Provider<SecureStore>` | sobrescrito en `main()` |
| `settingsStoreProvider` | `Provider<SettingsStore>` | sobrescrito en `main()` |
| `initialPreferencesProvider` | `Provider<Preferences>` | sobrescrito en `main()` |
| `backendProvider` | `Provider<IbashoBackend>` | `RestIbashoBackend` |
| `preferencesProvider` | `StateNotifierProvider` | volúmenes, idioma, movimiento reducido, acento cacheado, pista, usuario y generaciones recordadas |
| `sessionProvider` | `StateNotifierProvider` | fase, tokens, entrada de allowlist, admin |
| `clockProvider` | `StateNotifierProvider<Clock, DateTime>` | late cada segundo |
| `moodClockProvider` | `Provider<DateTime>` | hora con resolución de minuto |
| `batteryWatchProvider` | `Provider<BatteryWatch>` | de dónde sale la batería (`battery_plus`); los tests la sustituyen |
| `systemStatusProvider` | `StateNotifierProvider` | batería (cada 20 s, `battery_plus`) y calidad de enlace (cada 30 s); se para en segundo plano |
| `profileProvider` | `StateNotifierProvider` | perfil propio, se reconstruye al cambiar de cuenta |
| `adminProvider` | `StateNotifierProvider` | cuentas de la allowlist |
| `tamasProvider` | `StateNotifierProvider` | Tamas que cuida la cuenta y Tama de perfil |
| `accentProvider` | `Provider<Color>` | acento efectivo (ver §2) |
| `localeProvider` | `Provider<Locale>` | idioma de las preferencias |
| `announcementProvider` | `StreamProvider<String?>` | `/system/announcement` en tiempo real |
| `musicLibraryProvider` | `StateNotifierProvider` | pistas desbloqueadas y pista del menú |
| `unlockedFoodsProvider` | `Provider<Set<TamaFood>>` | chuches con `unlockedByDefault` (galleta y caramelo) |
| `debugProvider` | `StateNotifierProvider` | cámara lenta y gráfica de rendimiento (no se persiste) |
| `updateRequirementProvider` | `StreamProvider<UpdateRequirement?>` | `/system/update` leído sin sesión y seguido por SSE; `null` sin red o sin nodo |
| `updateLockedProvider` | `Provider<bool>` | `appVersion` < `minVersion` |
| `presenceProvider` | `StateNotifierProvider<PresenceController, PresenceStatus>` | estado elegido y conexión; se reconstruye al cambiar de cuenta o de fase |
| `friendsProvider` | `StateNotifierProvider<FriendsController, FriendsState>` | código propio, amigos, solicitudes recibidas y mandadas |
| `pendingRequestsProvider` | `Provider<int>` | solicitudes recibidas (insignia del canal) |
| `cardKeeperProvider` | `Provider<void>` | reescribe la ficha propia si no coincide con perfil, acento y Tama de perfil (con 1,5 s de respiro) |
| `cardOfProvider(accountId)` | `StreamProvider.autoDispose.family` | `/users/$id/card` |
| `publicTamaProvider((owner, tamaId))` | `StreamProvider.autoDispose.family` | `name`, `personality`, `voice` y `look` del Tama de perfil ajeno |
| `friendProfileProvider(id)`, `presenceOfProvider(id)`, `musicOfProvider(id)`, `wallOfProvider(id)`, `friendCountOfProvider(id)` | `StreamProvider.autoDispose.family` | datos de un amigo (o propios): lectura REST y luego SSE; siguen vivos 2 min tras dejar de mirarse |

---

## 2. Tema

### Tokens (`lib/theme/tokens.dart`, clase `T`)

Único archivo con colores escritos a mano. Grupos:

- **Superficies:** `shellTop`, `shellBottom` (degradado de paneles),
  `bezelTop`, `bezelBottom`, `hairline`, `wellTop`, `wellBottom` (huecos
  hundidos), `cardBottom`, `bezelRecess`, `letterbox`, `scrim`.
- **Tinta:** `ink`, `inkSoft`.
- **Acento de la casa:** `cyan` (`#5BC8F5`), `cyanDeep`, `warn`.
- **Brillos y sombras:** `specular`, `specularSoft`, `shadow`, `shadowDeep`,
  `glintNone`, `glintFaint`, `glintSoft`, `glintMid`, `glintRim`, `glintPanel`,
  `glintStrong`, `onAccent`, `dusk` (color con el que se oscurece cualquier tinte).
- **Paletas:** `accentPalette` (8 acentos para el perfil), `tamaPalette`
  (16 tonos del Tama).
- **Tamas:** `tamaInk`, `tamaMouth`, `tamaTongue`, `tamaBlush`,
  `tamaGroundShadow`, `tamaHeart`, `pigmentBlack` (solo el selector de color
  libre).
- **Cumpleaños:** `partyHat`, `partyStripe`, `partyPompom`, `confetti` (5),
  `partyWash`.
- **Presencia:** `presenceOnline`, `presenceAway`, `presenceBusy`,
  `presenceOffline`, `badge` (insignia de pendientes).
- **Comida:** `foodDough`, `foodDoughDark`, `foodChip`, `foodCandy`,
  `foodFrosting`, `foodCherry`, `foodCup`, `foodApple`, `foodStem`,
  `foodDangoPink`, `foodDangoWhite`, `foodDangoGreen`, `foodStick`,
  `foodSprinkleBlue`, `foodSprinkleYellow`, `foodMochi`, `foodLolly`, `foodCone`,
  `foodConeDark`, `foodScoop`, `foodGlaze`, `foodFlan`, `foodCaramel`.
- **Geometría:** `canvas` (1280×800), `panelWidth`, `panelRadius` (30),
  `tileRadius` (20), `buttonRadius` (22), `fieldRadius` (16), `panelBalanced`
  (340), `panelLarge` (560), `panelSmall` (120).
- **Movimiento:** `magnify` (320 ms), `channelOpen` (460 ms), `page` (380 ms),
  `hover` (180 ms), `press` (90 ms), `reduced` (100 ms).

### Tipografía (`lib/theme/type.dart`, clase `Ty`)

Familias declaradas en `pubspec.yaml`: `ZenKaku` (Zen Kaku Gothic New 400/500/700)
y `Rounded` (M PLUS Rounded 1c 500/700), empaquetadas en `assets/fonts/`.

- Interfaz (`ZenKaku`, interlineado 1,45): `micro` 11, `caption` 13,
  `label` 13, `body` 15, `lead` 19, `title` 24, `display` 34.
- `Rounded`: `clock(color)` 48, `clockSmall(color)` 34, `numeral(size, …)`,
  `logo(size, color)`, `credential`.
- `logoJa(size, color)` usa `ZenKaku` para el kana y kanji.

### Piel en tiempo de ejecución (`lib/theme/skin.dart`)

`IbashoSkin` es un `InheritedWidget` que se lee con `IbashoSkin.of(context)`:

- `accent`: acento efectivo. `accentDeep`: bordes y estados pulsados
  (`cyanDeep` si el acento es el cian; si no, el acento mezclado un 42 % con
  `dusk`). `accentWash`: fondos de selección (acento mezclado un 82 % con blanco).
- `reducedMotion`: preferencia del usuario **o** `MediaQuery.disableAnimations`.
- `motion(Duration)`: con movimiento reducido devuelve como mucho `T.reduced`.
- `curve(Curve)`: con movimiento reducido devuelve `Curves.linear`.

Uso en el código: los colores de acento se leen de `IbashoSkin.of(context)`,
nunca de `T.cyan`; toda duración pasa por `skin.motion()` y toda curva por
`skin.curve()`.

### Acento (`lib/theme/accent.dart`, `lib/state/accent_sync.dart`)

- `relativeLuminance(color)`, `contrastRatio(a, b)`.
- `minAccentContrast`: contraste del cian de la casa sobre `shellTop`.
  `maxAccentContrast`: 13.
- `readableAccent(color)`: conserva tono y saturación y ajusta la luminosidad
  hasta quedar entre esos dos contrastes.
- `accentForTama(hex)` = `readableAccent` del color del Tama.
- `decideAccentSync(profile, tamaHex)` → `AccentSync.none | follow | ask`:
  `accentFollowsTama == true` sigue; `null` con el cian de serie sigue; `false`
  o `null` con otro acento pregunta.
- `accentProvider`: si el perfil tiene `accentFollowsTama == true` y hay Tama de
  perfil, `accentForTama(color del Tama)`; si hay perfil, su `accentColor`; si no,
  `Preferences.accentHex` guardado en local, y si no hay, `T.cyan`. `AppRoot`
  guarda en `Preferences.accentHex` cada cambio del acento efectivo.

---

## 3. Widgets propios

Todos están construidos sobre `Pressable` y `GlossSurface`. Ninguno viene de
Material.

### Base (`lib/ui/widgets/`)

| Widget | Archivo | Parámetros | Estilo |
|---|---|---|---|
| `GlossSurface` | `gloss.dart` | `radius` (20), `child`, `tint`, `recessed`, `elevation` (1), `specular` (1), `borderColor`, `borderWidth` (1), `sink`, `padding` | Degradado `shellTop`→`shellBottom` (o del tinte), sombra corta, brillo especular en el tercio superior, luz rebotada abajo y filo de 1 px. `recessed` pinta un hueco `wellTop`→`wellBottom` con sombra interior. `sink` desplaza el contenido hacia abajo al pulsar. |
| `Bezel` | `gloss.dart` | `child` | Marco metálico `bezelTop`→`bezelBottom` con brillo diagonal; ocupa el lienzo. |
| `Pressable` | `pressable.dart` | `builder(context, PressState)`, `onPressed`, `onSecondaryPressed`, `enabled`, `cue` (`Sfx.tick`; `null` silencia), `focusNode`, `autofocus`, `cursor`, `semanticLabel` | Sin aspecto propio. `PressState` da `hover` y `press` animados de 0 a 1, `focus` y `enabled`. Activa con clic y con teclado (`ActivateIntent`). |
| `FocusRing` | `pressable.dart` | `visible`, `radius`, `child`, `inset` (−4) | Anillo de 2 px del acento con halo difuso. |
| `IbashoButton` | `controls.dart` | `label`, `onPressed`, `glyph`, `tone` (`ButtonTone.plain/accent/quiet/warn`), `height` (48), `expand`, `cue`, `autofocus`, `minWidth` | `plain`: plástico blanco; `accent`: tinte de acento; `warn`: tinte `T.warn`; `quiet`: solo texto. Sube 2 px al pasar el ratón y se hunde al pulsar. |
| `IconPill` | `controls.dart` | `glyph`, `onPressed`, `diameter` (42), `tone`, `cue`, `semanticLabel` | Botón redondo; no se eleva, cambia de color y se hunde 1,5 px. |
| `IbashoToggle` | `controls.dart` | `value`, `onChanged`, `width` (62) | Pastilla hundida, tenida de acento cuando está activa; pomo con curva `easeOutBack`. |
| `IbashoSlider` | `controls.dart` | `value` (0–1), `onChanged`, `width` (280), `ticks` (0), `onChangeStart`, `semanticLabel` | Raíl hundido con reflejo de cristal, relleno de acento y pomo de plástico. Tick al tocar, al soltar y al cruzar cada uno de los `ticks`. Flechas ±0,05. |
| `IbashoSegmented<V>` | `controls.dart` | `options` (`(V, String)`), `value`, `onChanged`, `height` (44) | Canal hundido; la opción elegida es una pastilla de acento. |
| `ColorChip` | `controls.dart` | `color`, `selected`, `onPressed`, `diameter` (38) | Muestra redonda tenida; seleccionada con filo grueso y check. |
| `IbashoTextField` | `text_field.dart` | `controller`, `label`, `hint`, `obscure`, `maxLength`, `onSubmitted`, `onChanged`, `focusNode`, `autofocus`, `enabled`, `error`, `width`, `formatters`, `multiline`, `textStyle` | Sobre `EditableText`, sin menú contextual ni tiradores. Hueco hundido; con foco, filo `accentDeep`; con `error`, tinte y texto `T.warn`. |
| `HsvColorPicker` | `color_picker.dart` | `value`, `onChanged`, `onChangeStart`, `width` (420), `height` (190) | Cuadro de saturación y valor y raíl de tono, con pomos de plástico. Sin límites de color. Flechas ±6° de tono. |
| `ScreenPanel` | `panel.dart` | `child`, `radius` (`T.panelRadius`), `clip` | Pantalla encastrada en el bisel: rebaje, cuerpo con degradado y banda de brillo tenue. |
| `SectionCard` | `panel.dart` | `title`, `child`, `padding`, `width` | Tarjeta blanca con título pequeño encima. Altura mínima (columna `min`). |
| `SettingRow` | `panel.dart` | `label`, `hint`, `control`, `divider` | Fila etiqueta/control con `Hairline` debajo. |
| `Hairline` | `panel.dart` | `indent` | Línea de 1 px `T.hairline`. |
| `IbashoScroll` | `panel.dart` | `child`, `padding`, `controller` | Scroll vertical sin brillo de sobredesplazamiento, barra del acento, arrastre con ratón. |
| `IbashoDialog` | `overlays.dart` | `title`, `body`, `actions`, `width` (520) | Panel `GlossSurface` de radio 28. |
| `showIbashoModal` | `overlays.dart` | `context`, `builder` | Ruta modal con velo `T.scrim`; entra escalando con `easeOutBack` (o fundido con movimiento reducido). |
| `askConfirmation` | `overlays.dart` | `title`, `body`, `confirmLabel`, `cancelLabel`, `tone`, `width` | `Future<bool>` con `IbashoDialog`. |
| `showIbashoToast` | `overlays.dart` | `context`, `message`, `isError` | Aviso tenido de acento (o `warn`) en la parte baja del lienzo; se va a los 2,2 s. |
| `GlyphIcon` | `glyphs.dart` | `glyph`, `size` (24), `color`, `strokeWidth` (1,9) | Iconos dibujados sobre una caja de 24×24. |
| `BatteryGauge` | `glyphs.dart` | `level`, `charging`, `color`, `accent`, `warn`, `height` (15) | Pila al estilo 3DS. |
| `SignalArcs` | `glyphs.dart` | `bars` (0–3), `color`, `dim`, `size` (17) | Arcos de señal. |
| `IbashoMark` | `logo.dart` | `size` (96), `accent` | Logotipo. |
| `TimezoneField` | `timezone_picker.dart` | `value`, `onChanged`, `label` | Campo que abre con `showIbashoModal` un selector de zonas IANA. |
| `TrackTile` | `track_tile.dart` | `title`, `subtitle`, `selected`, `onPressed`, `trailing`, `dimmed` | Fila de pista de música. |
| `SlotTile` | `slot_tile.dart` | `width`, `height`, `child`, `onPressed`, `selected`, `tint`, `semanticLabel` | Baldosa de rejilla paginada: se inclina 2° y sube 4 px con `easeOutBack`; la elegida lleva `accentWash` y filo `accentDeep`. La usan Tamas y amigos. |
| `EmptySlot` | `slot_tile.dart` | `width`, `height` | Ranura libre hundida. |

**Glifos** (`enum Glyph`): `gear`, `person`, `keycard`, `slot`, `arrowLeft`,
`arrowRight`, `magnify`, `check`, `cross`, `copy`, `refresh`, `power`, `note`,
`speaker`, `dice`, `info`, `bug`, `play`, `globe`, `plus`, `lock`, `eye`,
`eyeOff`, `cake`, `clock`, `chevronDown`, `tama`, `undo`, `heart`, `treat`,
`pencil`, `portrait`, `trash`, `wave`, `friends`, `personPlus`, `speakerOff`,
`download`, `paste`, `star`, `send`.

Normas de dibujo aplicadas en `glyphs.dart`: el trazo cabe en la caja; las
piezas se unen por sus extremos o se separan, sin cruzarse; cada icono se pinta
en una sola capa (`saveLayer` con la opacidad del color cuando es translúcido, y
siempre en `eyeOff`, que recorta con `BlendMode.clear`). `test/glyphs_test.dart`
pinta cada glifo al 50 % de opacidad y comprueba que ningún píxel queda fuera de
la caja ni supera el 50 % de alfa.

### Lienzo y canales (`lib/ui/canvas.dart`, `lib/ui/screens/`)

- `VirtualCanvas` tiene **dos formas y las decide la proporción de la ventana**,
  no la plataforma:
  - **horizontal** (más ancha que alta): lienzo de 800 de alto, ancho entre 1280
    y 1920 según la ventana, escalado con `FittedBox(BoxFit.contain)` y bandas
    `T.letterbox`. Es el de escritorio y el del móvil girado;
  - **vertical**: no hay escala. El lienzo es la ventana en píxeles lógicos
    (mínimo 360×640; por debajo se escala hacia abajo) y cada pantalla se
    recoloca. Una ventana estrecha en Linux usa esta.
  El árbol de widgets es el mismo en las dos, así que girar el móvil no desmonta
  el navegador ni pierde estado.
- `CanvasSize.of/tallOf/scaleOf(context)` dan tamaño, forma y escala en curso.
  `Layout.of(context)` (en `lib/ui/layout.dart`) los envuelve con las medidas
  que cambian: `gutter`, `pill`, `button`, `header`, `column`, `touch` y
  `pick(horizontal, vertical)`. Las pantallas piden números ahí en lugar de
  ramificar por plataforma.
- El lienzo también resuelve, fuera de él: las zonas seguras (muesca y barra de
  gestos, pintadas con el metal del bisel), el desplazamiento del contenido
  cuando el teclado taparía el campo con foco, y la escala de texto del sistema,
  que se ignora a propósito (ver README, *Accesibilidad*).
- `ShellScreen`: bisel, panel superior (`TopPanel`), carril de control, rejilla
  (`ChannelGrid`) y barra inferior. En horizontal la rejilla es de 4×2 por
  página y `PanelBalance` reparte 340/340, 560/120 y 120/560; en vertical es de
  3×3 y las alturas salen del alto disponible (`PanelBalance.topFor`), con un
  mínimo de 120 para la tira de arriba y de 212 para la rejilla.
- `ChannelTile`: al pasar el ratón se inclina 2° y sube 4 px con
  `easeOutBack`; al pulsar se hunde 2 px. Con el dedo no hay paso por encima:
  el hundimiento es inmediato y lo vistoso se guarda para la apertura.
- `ChannelSpec(id, glyph, label, builder, empty, badge)`; `channelsFor(isAdmin:)`
  devuelve ajustes, perfil, Tamas, amigos, administración y depuración (estas dos
  solo para admin) y `emptySlotCount` (2) ranuras libres.
  `channelsPerPage(tall:)` = 8 en horizontal, 9 en vertical.
  `badge` es un `ProviderListenable<int>`: `ChannelTile` pinta `CountBadge` en la
  esquina, fuera de la inclinación, cuando no es 0.
- `openChannel(context, anchor:, tint:, glyph:, label:, builder:)`: `ChannelRoute`,
  el icono crece hasta el lienzo entero con las esquinas a cero (460 ms) y el
  canal se maqueta una vez y se escala.
- `pushChannelPage(context, builder)`: `ChannelPageRoute`, página opaca que entra
  deslizándose desde la derecha con `pageSlideCurve` (fundido de 100 ms con
  movimiento reducido).
- `ChannelScaffold(title, glyph, child, trailing, onClose)`: cabecera de 92 px
  con icono de acento, título y botón de cerrar; Escape cierra.

### Tamas (`lib/ui/tama/`, `lib/ui/screens/tama/`, `lib/ui/screens/channels/tamas_channel.dart`)

| Pieza | Parámetros / API | Qué hace |
|---|---|---|
| `TamaPainter` | `look`, `pose`, `shadow`, `wear`, `live` (`ValueListenable<TamaPose>`) | Pinta un Tama en un lienzo lógico de 100×100 con el suelo en y = 90. Con `live` repinta sin reconstruir widgets. `wear` (`TamaWear.none` o `partyHat`) se pinta con el cuerpo, tras la cara: el gorrito se apoya en la cima real del contorno, se ladea con `sway` y `tilt` y no sale del lienzo (`test/friends_test.dart`). No se guarda en `/tamas`. |
| `TamaBody.of(look)` | `path`, `bounds`, `halfWidthAt(y)` | Silueta del cuerpo (superelipse deformada y spline Catmull-Rom), con caché. |
| `TamaFace.of(look, body)` | `eyeY`, `eyeDx`, `eyeR`, `mouthY`, `mouthW` | Posición de ojos, mejillas y boca. |
| `TamaPose` | `breathe`, `squash`, `hop`, `tilt`, `lean`, `blink`, `gaze`, `joy`, `happyEyes`, `mouthOpen`, `tongue`, `blush`, `sway`, `armWave`, `doze`, `hearts`, `heartPhase`, `treat`, `food` | Postura de un instante. `TamaPose.rest` es la de reposo. |
| `TamaAnimator` | `tick(dt)`, `pointAt(target, mouse:)`, `hovered`, `poke()`, `speak(seconds)`, `pet(active:, rub:)`, `cuddle()`, `feed(food)`, `joy`, `personality` | Estado continuo sin widgets. `TamaTraits.of(personality)` fija parpadeo, respiración, muelles, gestos de reposo, saltos y mirada. |
| `TamaView` | `look`, `personality`, `name`, `voice`, `seed`, `joy`, `size` (120), `interactive`, `pettable`, `shadow`, `wear`, `controller`, `onTap`, `onPetted`, `semanticLabel` | Tama vivo con `Ticker`. Sin ticker con movimiento reducido (pose de reposo fija). Se pausa si su ruta no es la actual y no avanza fuera de pantalla. Tocarlo llama a `poke` y grazna. |
| `TamaViewController` | `cuddle()`, `feed(food)`, `speak(kind)` | Mando de un `TamaView`. |
| `TamaPointerTracker` / `TamaPointer` | — | `Listener` en la raíz que guarda la última posición y tipo de puntero. La mirada sigue al ratón; tras un toque mira ese punto 3 s. |
| `TamaOnStand` | `tama`, `size`, `joy`, `controller`, `pettable`, `onPetted`, `onTap`, `wear` | `TamaView` sobre una peana blanca con filo de acento. |
| `TamaStyleChip` | `look`, `label`, `selected`, `onPressed`, `size` (88), `zoom`, `focus` | Variante de pieza con vista previa del Tama. |
| `TamaMoodMeter` | `value` (0–1), `width` (220) | Cápsula hundida con cinco gotas de acento. |
| `paintFood(canvas, food, c, s)` / `TamaFoodPainter(food, fill: .32)` | — | Comida dentro de un círculo de radio `s` (comprobado por `test/tama_food_test.dart`). |
| `TamaWindow` | `size`, `radius`, `onTap` | Hueco hundido con el Tama de perfil vivo o su silueta. Lo usan el panel superior y el perfil. El día del cumpleaños propio lleva gorrito (también en la habitación). |
| `reconcileAccentWithTama(context, ref, hex)`, `putTamaOnProfile(context, ref, tama)` | `accent_prompt.dart` | Sincronizan o preguntan por el acento al cambiar el color del Tama de perfil. |
| Textos | `tama_text.dart` | `personalityLabel`, `personalityHint`, `timbreLabel`, `foodLabel`, `variantLabel`, `moodLabel`, `moodHint`, `agoLabel`. |

Pantallas:

- `TamasChannel`: escaparate del Tama elegido en un `ScreenPanel` superior
  (botón de acento «visitar», poner en el perfil, editar), carril con flechas y
  puntos, y `ScreenPanel` inferior con ranuras de 6×2 por página (baldosa de
  Tama, ranura de crear, ranuras hundidas). Un toque elige; tocar la elegida
  abre su habitación. Rueda y teclado cambian de página o de elección.
- `TamaRoomScreen`: peana, humor, personalidad, mimar, carrusel horizontal de
  chuches (bloqueadas hundidas con candado), borrar.
- `TamaCreatorScreen(tamaId?, initialTab)`: pestañas `CreatorTab.body`, `color`,
  `eyes`, `mouth`, `crown`, `cheeks`, `limbs`, `character`; barajar, deshacer
  (pila de 60), paleta o HEX libre, nombre, personalidad, tono, ritmo y timbre.

---

### Amigos (`lib/ui/social/`, `lib/ui/screens/friends/`, `lib/ui/screens/channels/friends_channel.dart`)

| Pieza | Archivo | Qué hace |
|---|---|---|
| `PresenceLight` / `PresenceLight.of(state)` | `social_widgets.dart` | Piloto de plástico del color del estado; apagado en desconectado e invisible. |
| `CardTama` | `social_widgets.dart` | `accountId`, `size`, `card`, `interactive`, `shadow`, `wear`, `joy`. Tama de perfil de alguien a partir de su ficha, o su silueta. |
| `BadgeChip`, `ProfileBadge`, `badgesFor` | `social_widgets.dart` | Insignias calculadas: de cumpleaños, pionero (cuenta de 2026), amistad de más de un año, sociable (5 amigos), melómano (todas las pistas). |
| `CountBadge` | `social_widgets.dart` | Gota `T.badge` con número. |
| Textos | `social_widgets.dart` | `presenceLabel`, `presenceModeLabel`, `presenceModeHint`, `presenceLine` («desconectado · hace 2 h»), `zoneDifferenceLabel`. |
| `FriendCodeFormatter` | `friend_code_input.dart` | Solo dígitos, 12 como mucho, guiones automáticos; el cursor sigue a su dígito. |
| `BusinessCard` | `business_card.dart` | Tarjeta de 600×340 (Tama quieto en ventana hundida, marca y 居場所, nombre, franja de su color, código). `renderBusinessCard(key)` la pinta a PNG a ×3 (1800×1020) desde su `RepaintBoundary`; `saveBusinessCard` la guarda en Descargas (o Documentos). |

Pantallas:

- `FriendsChannel(initialTab)`: `ScreenPanel` superior con la tarjeta (vista
  previa escalada del mismo árbol que se exporta), el código grande con copiar,
  añadir amigo (acento), exportar tarjeta y el selector de estado. Carril con
  flechas, pestañas `IbashoSegmented` (amigos, recibidas, enviadas) y puntos.
  `ScreenPanel` inferior con ranuras 6×2 paginadas: añadir, amigo (Tama, nombre,
  piloto, tarta si cumple; un toque abre su perfil), solicitud recibida (aceptar
  y rechazar) o mandada (retirar). Abre en recibidas si hay pendientes.
- `AddFriendScreen`: campo del código con `FriendCodeFormatter` y pegar; con 12
  dígitos comprueba Damm en local (mensaje «no es válido») y solo si pasa
  pregunta a la base («nadie lo tiene», «es tuyo» o la ficha). La ficha: ventana
  del color con `CardTama`, nombre y el botón según la relación.
- `FriendProfileScreen(accountId)`: cabecera con dejar de ser amigos y altavoz
  (silencio persistente). `ScreenPanel` con `TamaOnStand`, nombre y color,
  presencia, estado, insignias, desde cuándo y la pista; a la derecha la hora
  local al segundo, la diferencia y el cumpleaños. El día del cumpleaños,
  `PartyBackdrop` (guirnalda y confeti fijos) y gorrito. Abajo, `WallPanel`.
- `WallPanel(accountId, profile, own)`: año con flechas, mensajes en rejilla
  paginada (2×2 con el campo, 3×2 sin él), campo de 140 caracteres solo el día
  del cumpleaños y si no se ha escrito ya ese año. `own` pone papelera y quita el
  campo. `OwnWallScreen` (en `profile_channel.dart`) lo abre para el muro propio.
- `ProfileChannel` añade la música de perfil (`IbashoSegmented` con las pistas
  desbloqueadas) y el botón del muro propio.

## 3-bis. Android

Todo lo que sigue solo se enciende con `Device.isAndroid`; la rama de Linux es
la que ya existía.

### Composición vertical

No hay una versión móvil de las pantallas: cada una se maqueta una vez y pide
sus medidas a `Layout.of(context)`. El patrón es siempre el mismo: lo que en
horizontal va en fila, en vertical va en columna; lo que tiene ancho fijo pasa a
repartirse el que haya; y las rejillas cambian de columnas (canales 4×2 → 3×3,
Tamas 6×2 → 3×N, amigos 6×2 → 2×N, y las solicitudes pasan a tiras anchas para
que quepan sus dos botones).

### Zonas táctiles (`lib/ui/touch.dart`)

- En vertical, `Pressable` envuelve su contenido en `MinTouchSize`: la caja que
  responde al dedo nunca baja de 48 dp, sin tocar cómo se maqueta ni se pinta el
  hijo. `IbashoButton`, `IconPill`, `IbashoSegmented` y `ColorChip` además
  suben su tamaño visible. `test/touch_targets_test.dart` lo mide en un móvil de
  360×640.
- En horizontal el lienzo se escala a la mitad en un teléfono y no se puede
  agrandar sin rehacer la composición de escritorio, así que `TouchAssist`
  (un `Listener` en la raíz) entrega un toque que no ha caído sobre nada tocable
  al control más cercano cuya zona ampliada a 48 dp lo contenga. Nunca roba un
  toque que ya tenía dueño: para saberlo mira el camino del hit test buscando
  `RenderSemanticsGestureHandler` con `onTap` o la marca `TouchClaim`.
- `PageSwipe` añade el arrastre horizontal para pasar de página, solo para
  punteros de dedo, así que el ratón de escritorio no cambia de comportamiento.
- `fingerKinds` incluye `PointerDeviceKind.unknown` porque los eventos
  inyectados por `adb shell input` llegan sin tipo; las zonas desplazables
  también lo aceptan.

### Ciclo de vida (`lib/ui/mobile.dart`)

`MobileLifecycle` escucha el ciclo de vida y, al pasar a segundo plano
(`hidden`/`paused`):

1. para el reloj y los sondeos de batería y conexión;
2. avisa al backend (`setBackground(true)`), que cierra las suscripciones SSE y
   no reintenta nada hasta volver;
3. `AudioService.suspend()`: pausa la música, apaga el motor de efectos
   (`SoLoud.deinit`) y suelta el foco de audio;
4. `PresenceController.suspend()`: publica *desconectado* (y lo mismo deja
   encargado para la desconexión) y cierra el websocket limpiamente: fuera de
   la app no se está.

Al volver se rehace todo en orden inverso y, antes de nada,
`SessionController.resume()` renueva el token si caducó mientras el proceso
dormía: los temporizadores no corren con el proceso parado.

### Atrás

`BackGate` se registra como observador **antes** que `WidgetsApp`, así que es el
primero en ver el botón o el gesto de atras: si hay algo que cerrar, suena el
retroceso y se cierra; si la ruta de arriba lo tiene prohibido (el creador con
cambios sin guardar, con su `PopScope`), deja que ella pregunte; y en la raíz
pide confirmación antes de salir. La raíz lleva `PopScope(canPop: false)` para
que Android entregue siempre el gesto a la app.

### Audio (`lib/audio/android_audio.dart`, `MainActivity.kt`)

El foco de audio lo lleva el servicio, no `audioplayers` (que se configura con
`AndroidAudioFocus.none`). Un canal de métodos propio pide y suelta el foco y
avisa de lo que hace el sistema: `gain`, `loss`, `lossTransient` y `duck`. La
música calla con las dos pérdidas y baja al 20 % con el `duck`.

El modo del timbre no se mira. Todo lo que suena en Ibasho —música, efectos y
voces— es audio de medios, y el silencio del sistema calla el tono y las
notificaciones, no los medios (`ringer mode muted streams` no incluye
`STREAM_MUSIC`). Mirarlo dejaba la app a medias, con la música sonando y los
toques mudos, en un teléfono que suele llevar el timbre apagado.

En Android el mezclador de SoLoud arranca a 48 kHz con un periodo de 512
muestras, en vez de las 2048 de escritorio; si un aparato no admite esa
combinación se reintenta con la de serie antes que quedarse sin efectos.

### Sistema

- Modo inmersivo (`SystemUiMode.immersiveSticky`), reaplicado al volver de
  segundo plano y cuando el sistema saca las barras por su cuenta.
- Zonas seguras: el lienzo se queda dentro de `MediaQuery.padding` y lo que
  queda fuera se pinta con el metal del bisel.
- La escala de texto del sistema se ignora dentro del lienzo (ver README).
- La tarjeta de visita se comparte con el menú del sistema (`share_plus`); en
  escritorio se sigue guardando en Descargas.
- La batería se lee con `battery_plus` en las dos plataformas
  (`BatteryWatch`/`PluginBatteryWatch`, sustituible en los tests). En Android se
  sondea cada 20 s: el flujo de cambios del plugin necesita un permiso privado
  de androidx que el manifiesto quita.

### Proyecto de Android

- `applicationId` `top.ibasho.app`, `minSdkVersion` 24, `targetSdkVersion` 36,
  orientación `fullUser` (vertical y horizontal).
- Permisos: `INTERNET` y `ACCESS_NETWORK_STATE`. Los demás que traen las
  dependencias se eliminan con `tools:node="remove"`.
- `network_security_config.xml` prohíbe el tráfico en claro; solo la variante de
  depuración lo permite contra `127.0.0.1` (emuladores de Firebase por
  `adb reverse`).
- R8 y `shrinkResources` en release, con las reglas de
  `android/app/proguard-rules.pro`.
- Icono adaptativo y pantalla de arranque propios (`ic_launcher_foreground.xml`
  dibuja la misma marca que `IbashoMark`).
- La firma sale de `android/key.properties`, que no está en el repositorio; sin
  él, release se firma con la clave de depuración.

---

## 4. Motor de sonido (`lib/audio/`)

`AudioService.instance` es un singleton. Si el audio no arranca, la app sigue en
silencio.

### Música (audioplayers)

- `init()`: inicializa efectos y crea el reproductor `ibasho_bgm` en bucle.
- `startMusic()`, `stopMusic()`.
- `setTrack(String id)`: `MusicTrack.byId(id)`; cambia de pista y suena si la
  música debe sonar.
- `setMusicVolume(double)`: a 0 pausa el reproductor.
- `musicVolume`, `track`.
- `playProfileTrack(MusicTrack)` / `endProfileTrack()`: pone la pista de un
  perfil encima de la de ambiente y la quita. Si algo sonaba, sale en 260 ms y
  entra en 900 ms (rampas de volumen de 18 pasos). `profileTrack` dice cuál suena.

Las operaciones van en una cola serie y reconcilian el reproductor con la
intención (`_musicWanted`, `_guest ?? _track`). Si el reproductor se para solo, se
reanuda como mucho una vez cada 2 s.

`enum MusicTrack(id, asset, author, license, unlockedByDefault)`: `plaza`,
`bossa` (bloqueadas de serie), `calma`, `aurora`, `brisa`, `noche` (de serie).
`MusicTrack.fallback` = `calma`.

### Efectos (flutter_soloud)

- `play(Sfx)`: inmediato. Una voz por efecto: la anterior se desvanece en 10 ms.
  Separación mínima entre disparos del mismo efecto: `tick` 45 ms, `open` y
  `back` 90 ms, `error` 150 ms, `chime` 500 ms.
- `enum Sfx`: `tick`, `open`, `back`, `error`, `chime` (`assets/audio/sfx/*.wav`).
- `setEffectsVolume(double)`: fija el volumen global de SoLoud; `effectsVolume`.

`linux/CMakeLists.txt` compila `flutter_soloud_plugin` con `-w`.

### Voces de Tama

- `chirp({name, voice, kind = ChirpKind.hello})` → `Future<double>` con la
  duración en segundos, o 0 si no suena (efectos a 0, audio no disponible o menos
  de 120 ms desde el anterior). Sintetiza el WAV, lo carga con
  `SoLoud.loadMem` (caché de 16 fuentes) y lo reproduce por el mismo motor que los
  efectos, así que obedece a `setEffectsVolume`. Un graznido nuevo desvanece el
  anterior.
- `tama_voice.dart`:
  - `enum ChirpKind`: `hello`, `happy`, `munch`, `sigh`.
  - `voiceSeed(name)`: FNV-1a de 32 bits del nombre en minúsculas.
  - `chirpPattern(name, voice, kind)` → `List<ChirpSyllable>` (semitonos sobre
    escala pentatónica, glide, duración y silencio), derivado del nombre.
  - `chirpSeconds(pattern)`.
  - `synthesizeChirp({name, voice, kind, sampleRate = 44100})` → `Uint8List`,
    WAV PCM mono de 16 bits.
  - Timbres (`TamaTimbre`): `soft`, `bright`, `round`, `whistle`, `purr`, `bubble`.
    `pitch` (0–100) desplaza el tono base 1,6 octavas; `tempo` (0–100) escala las
    duraciones entre 1,45 y 0,65.

---

## 5. Base de datos

Firebase Realtime Database, accedida por REST desde Dart puro (`RtdbClient`).

### Acceso

| Operación | Método de `IbashoBackend` | REST |
|---|---|---|
| Leer | `read(path, idToken:, shallow:, query:)` | `GET {root}{path}.json?auth=…` (+ `shallow=true`, + `orderBy="…"&equalTo="…"`) |
| Escribir | `write(path, value, idToken:)` | `PUT … print=silent` |
| Fusionar / multi-ruta | `merge(path, map, idToken:)` | `PATCH … print=silent`; claves con `/` escriben varias rutas a la vez |
| Borrar | `remove(path, idToken:)` | `DELETE` |
| Tiempo real | `watch(path, token:, query:)` | `GET` con `Accept: text/event-stream`; eventos `put` y `patch`; `cancel` y `auth_revoked` cierran y reconectan con token nuevo; retroceso exponencial hasta 30 s |
| Conexión persistente | `openPresenceLink(token:)` | websocket `wss://{host}/.ws?v=5&ns={ns}` (emulador: `ws://host:9000/.ws?v=5&ns={proyecto}-default-rtdb`) |
| Salud | `probe()` | `GET /.info/serverTimeOffset?shallow=true`; `LinkQuality` por latencia (< 220 ms fuerte, < 700 ms media) |

- `serverTimestamp` = `{".sv": "timestamp"}`.
- `applyDatabaseEvent(tree, event)` mantiene una copia local de un nodo.
- `generatePushId()`: 8 caracteres de tiempo y 12 de azar sobre
  `-0-9A-Za-z_`, ordenables como texto.
- Errores HTTP 401/403 → `IbashoFailure.permissionDenied`.

`PresenceLink` (`rtdb_socket.dart`): `connection` (`Stream<bool>`),
`isConnected`, `set(path, value)`, `setOnDisconnect(path, value)`,
`cancelOnDisconnect(path)`, `close()`. `RtdbSocket` habla el protocolo v5:
espera el saludo `{"t":"c","d":{"t":"h"}}`, se autentica con
`{"a":"auth","b":{"cred":idToken}}` y usa las acciones `p`, `o` y `oc`; sigue
cambios de host (`r`), contesta pings, junta mensajes partidos, manda `0` cada
45 s, se reautentica cada 45 min o al recibir `ac`, y se reconecta con retroceso
hasta 30 s. Tras cada reconexión hay que volver a encargar: el servidor ya
ejecutó lo anterior.

Autenticación (`IdentityToolkit`): `accounts:signUp`,
`accounts:signInWithPassword`, `accounts:update` y `securetoken …/token` con
`grant_type=refresh_token`. El usuario `nombre` entra como
`nombre@{IBASHO_EMAIL_DOMAIN}`; una credencial regenerada usa
`nombre+N@…` (generación N, hasta 4). `SessionController` renueva el token un
minuto antes de caducar.

### Esquema

`$uid` es el uid de Identity Toolkit de una identidad de inicio de sesión.
`$accountId` es el identificador estable de la cuenta (en la primera identidad
coincide con su uid).

```
/allowlist/$uid
    accountId            string 1–128, inmutable
    username             string ^[a-z0-9_]{3,16}$
    createdAt            number > 0
    createdBy            string 1–128
    disabled             boolean (no puede volver a false si retired es true)
    retired?             boolean (no puede volver de true a false)
    generation?          number 1–99
    mustChangePassword?  boolean
    (obligatorios: accountId, username, createdAt, createdBy, disabled; nada más)

/admins/$uid             true (el uid tiene que existir en /allowlist)

/usernames/$username     string: uid cuya entrada de allowlist (en el árbol resultante) tiene ese username

/friendCodes/$code        string: accountId ($code ^[0-9]{12}$)

/users/$accountId
    card
        displayName        string 1–24
        accentColor        string #RRGGBB (acento efectivo)
        tamaId?            push id; igual a `tama` en el árbol resultante y con keeper $accountId
        (obligatorios: displayName, accentColor; nada más)
    friendCode           string ^[0-9]{12}$, inmutable, igual a su entrada en /friendCodes
    friends/$friendId
        since              number > 0 y ≤ now
    friendCount          number entero 0–100
    friendLastChange     string: la otra cuenta de la última amistad creada o deshecha
    requests
        out/$toId          { at: number > 0 y ≤ now }
        in/$fromId         { at: number > 0 y ≤ now }
    presenceMode         'online' | 'away' | 'busy' | 'invisible' (lo elegido; solo el dueño)
    wall/$year/$authorId ($year ^[0-9]{4}$)
        text               string 1–140
        at                 number > 0 y ≤ now
    profile
        username           string, igual al username de la allowlist del que escribe
        displayName        string 1–24
        statusMessage?     string ≤ 100
        birthday?          string '' o AAAA-MM-DD
        timezone?          string ≤ 64
        locale?            'es' | 'en'
        accentColor?       string #RRGGBB
        accentFollowsTama? boolean
        createdAt          number > 0
        (obligatorios: username, displayName, createdAt; nada más)
    presence
        state              'online' | 'away' | 'busy' | 'offline' (nunca 'invisible')
        lastSeen           number > 0
    music
        unlocked/$trackId  true   ($trackId ^[a-z0-9_]{1,32}$)
        menuTrack          string ^[a-z0-9_]{1,32}$: calma, aurora, brisa, noche o una desbloqueada
        profileTrack?      igual que menuTrack: la que suena al abrir el perfil
    tama                 string push id de un Tama cuyo keeper es $accountId (Tama de perfil); card/tamaId igual
    tamaCount            number entero 0–99
    tamaLastChange       string push id del último Tama creado o borrado

/tamas/$tamaId           ($tamaId ^[-0-9A-Za-z_]{20}$)
    schema               1
    creator              string, inmutable
    keeper               string, inmutable
    name                 string 1–16
    personality          'calm' | 'playful' | 'shy' | 'cheeky' | 'sleepy'
    voice
        pitch            entero 0–100
        tempo            entero 0–100
        timbre           entero 0–5
    look
        body             entero 0–5
        eyes             entero 0–5
        mouth            entero 0–4
        crown            entero 0–5
        cheeks           entero 0–3
        pattern          entero 0–4
        arms             entero 0–3
        feet             entero 0–3
        bodyWidth, bodyHeight, eyeSize, eyeSpacing, eyeHeight,
        mouthSize, mouthHeight, crownSize, cheekIntensity, patternTone
                         enteros 0–100
        color            string #RRGGBB
        colorMode        'palette' | 'hex'
        (todos obligatorios; nada más)
    care
        lastPetted?      number > 0 y ≤ now
        lastFed?         number > 0 y ≤ now
    createdAt            number > 0 y ≤ now, inmutable
    updatedAt            number > 0 y ≤ now
    (obligatorios: schema, creator, keeper, name, personality, voice, look, createdAt, updatedAt; nada más)

/system/announcement
    text                 string ≤ 200
    updatedAt            number > 0
/system/update             lectura pública
    minVersion           string ^\d{1,4}\.\d{1,4}\.\d{1,4}$
    url?                 string https://…, ≤ 300
/system/friendCodeCounter  number entero: el siguiente contador (ausente = 1), sube de 1 en 1
```

`.indexOn`: `/allowlist` sobre `username` y `disabled`; `/tamas` sobre `keeper`.

### Quién lee y escribe

| Nodo | Lectura | Escritura |
|---|---|---|
| `/` | nadie | nadie |
| `/allowlist` | admin | — |
| `/allowlist/$uid` | la propia identidad (si existe) o un admin habilitado | admin; `mustChangePassword` también la propia identidad, solo a `false` |
| `/admins` | admin | admin |
| `/admins/$uid` | miembro habilitado, sobre sí mismo o siendo admin | (vía `/admins`) |
| `/usernames` | miembro habilitado | — |
| `/usernames/$username` | (vía `/usernames`) | admin, solo si no existe |
| `/friendCodes` | admin | — |
| `/friendCodes/$code` | miembro habilitado | admin, solo si no existe, con el contador +1 y `users/$acc/friendCode` en la misma escritura |
| `/users/$accountId` | la cuenta dueña (todo) | — (cada hijo) |
| `…/card` | miembro habilitado | dueña |
| `…/profile`, `…/presence`, `…/music`, `…/friends`, `…/wall` | además, sus amigos | `profile`, `presence`, `music`: dueña |
| `…/friendCount` | además, sus amigos y quien le mandó una solicitud | dueña o la cuenta de `friendLastChange`; no se borra |
| `…/friendLastChange` | — | dueña o la cuenta que marca; no se borra |
| `…/friends/$friendId` | — | crear: quien recibió la solicitud (en su lista si existe `requests/in/$friendId`; en la del otro si existe su `requests/out/<yo>`), con la entrada simétrica, sin solicitudes entre ambos y con el contador +1; borrar: cualquiera de los dos, con la simétrica y contador −1 |
| `…/requests/out/$toId` | — | crear: la dueña, con `in` simétrica, a una cuenta con código, sin ser amigos ni tener la suya pendiente; borrar: cualquiera de los dos, con la simétrica |
| `…/requests/in/$fromId` | — | crear: `$fromId`, con `out` simétrica; borrar: cualquiera de los dos, con la simétrica |
| `…/presenceMode` | — | dueña |
| `…/wall/$year/$authorId` | — | crear (nunca sobrescribir): `$authorId`, si es amigo y no es la dueña; borrar: la dueña |
| `…/friendCode` | — | admin, solo si no existe |
| `…/tama`, `tamaCount`, `tamaLastChange` | — | dueña; `tama` solo con `card/tamaId` igual (y no se borra dejándolo en la ficha); los contadores no se borran |
| `/tamas` | miembro habilitado con la consulta `orderBy="keeper"&equalTo=<su accountId>` | — |
| `/tamas/$tamaId` | su `creator` o su `keeper`; de `name`, `personality`, `voice` y `look`, además cualquier miembro si es el `card/tamaId` de su keeper (nunca `care` ni `updatedAt`) | crear: quien será creator y keeper; borrar: quien es creator y keeper |
| `…/name`, `personality`, `voice`, `look`, `updatedAt` | — | el `creator` |
| `…/care` | — | el `keeper` |
| `/system` | miembro habilitado | admin |
| `/system/update` | cualquiera, sin sesión | (vía `/system`) |

### Contador de Tamas

Crear o borrar un Tama es una sola escritura multi-ruta sobre `/`:

- **Crear:** `tamas/$id` completo, `users/$acc/tamaCount` = anterior + 1 (0 si
  no existía) y `users/$acc/tamaLastChange` = `$id`. Opcionalmente
  `users/$acc/tama` = `$id`.
- **Borrar:** `tamas/$id` = null, `tamaCount` = anterior − 1,
  `tamaLastChange` = `$id`, y `users/$acc/tama` distinto de `$id` en el resultado.

`tamaCount` solo valida si en la misma escritura aparece o desaparece el Tama de
`tamaLastChange`, creado por esa cuenta, y nunca pasa de 99. El `.write` de
`/tamas/$tamaId` exige que `tamaLastChange` sea ese mismo id, así que cada
escritura crea o borra un solo Tama. `TamasController.create` lee `tamaCount`
antes de escribir y reintenta una vez.

### Contador de amigos

Aceptar es una escritura multi-ruta sobre `/`: `users/$yo/friends/$tú` y
`users/$tú/friends/$yo` (`since` = `serverTimestamp`), los dos `friendCount`
(+1) con sus `friendLastChange` (la otra cuenta), y las cuatro solicitudes entre
ambos a `null`. Dejar de ser amigos borra las dos entradas y baja los dos
contadores. `friendCount` solo valida si en la misma escritura aparece (o
desaparece) la entrada de `friendLastChange` en esa lista, y nunca pasa de 100.
`FriendsController.accept` y `unfriend` leen los dos contadores y reintentan
una vez.

### Códigos de amigo

`FriendCode.forCounter(n)` = once dígitos de `(55683571461 · n + 27182818284)
mod 10^11` más el dígito de control de Damm. Los dígitos del multiplicador van
del 1 al 8, así que dos contadores seguidos dan códigos distintos en las once
posiciones. El admin da el código en la misma escritura que crea la cuenta
(`allowlist`, `usernames`, `friendCodes/$code`, `users/$acc/friendCode` y
`system/friendCodeCounter` + 1); `AdminController.assignMissingFriendCodes`
reparte los que falten al abrir el panel.

### Escrituras que hace la app

| Controlador | Rutas |
|---|---|
| `SessionController` | `/allowlist/$uid/mustChangePassword` (false) |
| `ProfileController` | `PATCH /users/$acc` con `profile` entero y `card` (lo crea en la primera entrada) |
| `PresenceController` | por `PresenceLink`: `setOnDisconnect(/users/$acc/presence, offline)` y `set(presence)` al conectar y al cambiar; al pasar a segundo plano, `offline`; invisible: `cancelOnDisconnect` y `offline` solo si no lo estaba. Por REST: `/users/$acc/presenceMode` |
| `FriendsController` | multi-ruta de solicitud, aceptación, rechazo, retirada y amistad; `/users/$amigo/wall/$year/$acc`; borrar `/users/$acc/wall/$year/$autor` |
| `cardKeeperProvider` | `/users/$acc/card` cuando no cuadra con perfil, acento y Tama de perfil |
| `MusicLibraryController` | `/users/$acc/music/menuTrack`, `/users/$acc/music/profileTrack` (o la borra), `/users/$acc/music/unlocked/$track`, borra `unlocked` |
| `AdminController` | alta multi-ruta con código de amigo (ver arriba), `/admins/$uid`, `/allowlist/$uid/disabled`; regenerar crea `/allowlist/$nuevoUid` con el mismo `accountId`, copia `/admins` si lo era y marca la vieja `disabled` y `retired` |
| `TamasController` | multi-ruta de creación y borrado (con `card` si cambia el Tama de perfil); `PATCH /tamas/$id` (name, personality, voice, look, updatedAt); `/tamas/$id/care/lastPetted` y `/lastFed` (`serverTimestamp`, como mucho una vez cada 30 s y 5 s por Tama); `PATCH /users/$acc` con `tama` y `card` |
| `AdminController` (versión) | `/system/update` (`requireVersion(appVersion, url:)`) y su borrado |
| `tool/bootstrap_admin.dart` | `/allowlist/$uid`, `/admins/$uid`, `/usernames/$username`, `/friendCodes/$code`, `/users/$uid/friendCode`, `/system/friendCodeCounter` con la CLI de Firebase |

El humor de un Tama no se guarda: `TamaMoodReading.of(tama, now)` lo calcula a
partir de `lastPetted` y `lastFed` (sin cuidados cuenta `createdAt`), con caída
suave hasta 52 horas.

### Convenciones de `database.rules.json`

- El archivo admite comentarios `//`, que acepta tanto el emulador como el
  despliegue.
- Las reglas de la Realtime Database no tienen funciones; las comprobaciones se
  repiten en línea:
  - miembro habilitado:
    `auth != null && root.child('allowlist').child(auth.uid).child('disabled').val() === false`
  - accountId de quien llama: `root.child('allowlist').child(auth.uid).child('accountId').val()`
  - dueño de la cuenta: miembro habilitado y ese accountId `=== $accountId`
  - admin: `root.child('admins').child(auth.uid).exists()`
- Cada objeto con forma fija termina en `"$other": { ".validate": false }` y lista
  sus obligatorios con `newData.hasChildren([...])`.
- Enteros: `newData.isNumber() && newData.val() % 1 === 0 && newData.val() >= a && newData.val() <= b`.
- Marcas de tiempo de Tamas: `newData.val() > 0 && newData.val() <= now`.
- Inmutables: `!data.exists() || data.val() === newData.val()`.
- Ids de push: `$tamaId.matches(/^[-0-9A-Za-z_]{20}$/)`.
- Las comprobaciones entre nodos de una escritura multi-ruta se hacen sobre el
  árbol resultante con `newData.parent()…` y sobre el anterior con `root`.
- Los borrados solo se controlan en `.write` (`.validate` no se evalúa al borrar).
- Bajo `/users/$accountId` el permiso de escritura está en cada hijo, no en el
  nodo de la cuenta. El de lectura de la cuenta es solo de la dueña; lo que leen
  otros se concede hijo a hijo.
- amigo de `$accountId`:
  `root.child('users').child($accountId).child('friends').child(<accountId de quien llama>).exists()`
- Parejas que se escriben juntas (solicitudes, amistades) se comprueban en el
  `.write` de cada mitad mirando la otra en `newData`; el borrado de algo que no
  existe se deja pasar en las solicitudes para poder limpiar las dos direcciones.
- La limitación de fecha del muro está explicada en un comentario de las reglas.

---

## 6. Tests y emulador

| Comando | Qué ejecuta |
|---|---|
| `flutter analyze` | análisis estático |
| `flutter test` | todos los tests de `test/` excepto el e2e, que se salta sin `IBASHO_USE_EMULATOR`. Deja PNG en `build/screenshots/` |
| `flutter test test/tall_tour_test.dart` | recorrido vertical en 360×640 y 411×914; cualquier desborde hace fallar el test. PNG en `build/screenshots/vertical-*/` |
| `flutter test test/touch_targets_test.dart` | mide cada control en un móvil pequeño: ninguno por debajo de 48 dp |
| `flutter test test/visual_tour_test.dart` | capturas de pantallas `01-…` a `34b-…` (amigos desde `24-…`; `34-tarjeta.png` es la tarjeta exportada) |
| `flutter test test/tama_gallery_test.dart` | hojas `g1-piezas` a `g7b-comida-sola` |
| `./tool/test_rules.sh` | instala `test/rules/node_modules` si falta y ejecuta `firebase emulators:exec --project demo-ibasho --only database "npm --prefix test/rules test"` (`node --test rules.test.mjs`, con `@firebase/rules-unit-testing`) |
| `./tool/test_e2e.sh` | `firebase emulators:exec --project demo-ibasho --only auth,database` con `flutter test test/e2e` y los defines del emulador |

- `RtdbClient` omite `auth` cuando el token es la cadena vacía: así se leen nodos
  públicos como `/system/update` antes de iniciar sesión.
- Emuladores (`firebase.json`): Realtime Database en `127.0.0.1:9000`, Auth en
  `127.0.0.1:9099`, interfaz desactivada. Son procesos Java locales; nunca tocan
  el proyecto real.
- La app contra los emuladores (con `tool/dev_seed.dart` para tener cuentas):
  ```sh
  firebase emulators:start --project demo-ibasho --only auth,database
  dart run tool/dev_seed.dart
  flutter run -d linux --dart-define-from-file=.env \
    --dart-define=IBASHO_USE_EMULATOR=true --dart-define=IBASHO_PROJECT_ID=demo-ibasho
  ```
- `FakeIbashoBackend` (`test/support/fakes.dart`) es una base en memoria con
  lecturas, escrituras multi-ruta, consultas por hijo, `serverTimestamp` y
  streams; `seed(path, value)` escribe como otro equipo, `peek(path)` lee y
  `reads` apunta las lecturas. Acepta `tamas` y `profileTamaId` para arrancar con
  Tamas. `sharing(uid:, username:)` da otra cuenta sobre la misma base.
  `openPresenceLink` devuelve un `FakePresenceLink` que guarda lo encargado y lo
  aplica con `drop()`. `seedSocial` monta amigos, solicitud y cumpleaños.
- `visual_tour_test.dart` carga las fuentes reales con `FontLoader` (el resto de
  widget tests usan la fuente de pruebas de `flutter_test`). Los tests que
  generan imágenes capturan con `tester.runAsync`, y todos avanzan el tiempo con
  bucles de `pump` (el reloj late cada segundo).
- El e2e usa `test()` sin el binding de widgets para que las peticiones HTTP
  lleguen al emulador; escribe saltándose las reglas con
  `Authorization: Bearer owner`. Para `onDisconnect` lanza
  `test/e2e/presence_holder.dart` con `dart run`, espera a que publique
  `online`, lo mata con `SIGKILL` y comprueba que el servidor deja `offline`.
- Reglas en producción: `firebase deploy --only database`.

### Comprobar que el escritorio no ha cambiado

La regla del puerto a móvil es que **Linux no puede empeorar**, y eso se
comprueba con números, no a ojo: el recorrido visual se corre en una copia de
la última versión conocida buena y en el árbol de trabajo, y las imágenes se
comparan píxel a píxel.

```bash
git worktree add -f --detach /tmp/ibasho-base <commit>
cp .env /tmp/ibasho-base/.env
(cd /tmp/ibasho-base && flutter pub get && flutter test test/visual_tour_test.dart)
flutter test test/visual_tour_test.dart
# y comparar /tmp/ibasho-base/build/screenshots con build/screenshots
```

Las dos pasadas se hacen seguidas, porque el reloj del entorno sale en la
captura. Lo único que puede salir distinto es el reloj, el número de versión,
el Tama al azar del creador nuevo y algún píxel de antialias en una cara
animada; cualquier otra diferencia es una regresión de escritorio, casi
siempre por envolver un control en algo que le da un ancho máximo (`Flexible`,
`Wrap`, `ConstrainedBox`): con el ancho acotado, un botón propio se estira
hasta llenarlo, y en horizontal no debe. Esos envoltorios van solo en la rama
vertical.

---

## 7. Configuración

`lib/core/env.dart` lee valores de compilación con `String/bool/int.fromEnvironment`:

| Clave | Uso | Por defecto |
|---|---|---|
| `IBASHO_API_KEY` | clave web de Firebase para Identity Toolkit | — |
| `IBASHO_DATABASE_URL` | raíz de la Realtime Database, sin barra final | — |
| `IBASHO_PROJECT_ID` | proyecto; con emulador forma `ns={id}-default-rtdb` | — |
| `IBASHO_EMAIL_DOMAIN` | dominio del email sintético | `ibasho.top` |
| `IBASHO_USE_EMULATOR` | apunta a los emuladores | `false` |
| `IBASHO_EMULATOR_HOST` | host de los emuladores | `127.0.0.1` |
| `IBASHO_EMULATOR_DB_PORT` | puerto de la base | `9000` |
| `IBASHO_EMULATOR_AUTH_PORT` | puerto de Auth | `9099` |

- Los valores están en `.env` (ignorado por git, igual que `.env.*` salvo
  `.env.example`) y se inyectan con
  `flutter run -d linux --dart-define-from-file=.env` o `flutter build linux
  --dart-define-from-file=.env`.
- `Env.identityRoot`, `Env.secureTokenRoot` y `Env.databaseRoot` resuelven la
  URL de producción o la del emulador. `Env.missing` y `Env.isConfigured` indican
  qué claves faltan.
- `tool/bootstrap_admin.dart` lee `.env` directamente (`IBASHO_API_KEY`,
  `IBASHO_PROJECT_ID`, `IBASHO_EMAIL_DOMAIN`) y usa la CLI de Firebase
  autenticada.
- Almacenamiento local:
  - `SettingsStore`: `preferences.json` en el directorio de soporte de la app
    (volúmenes, idioma, movimiento reducido, acento, pista, generaciones y
    `profileMusicMuted`).
  - `openSecureStore()`: libsecret si responde a una clave de sonda; si no,
    `session.vault` cifrado con AES-256-GCM, clave PBKDF2 (120 000 iteraciones)
    sobre el machine-id, la ruta y una sal en `session.vault.salt`.
- Localización: `l10n.yaml` genera la clase `L` en `lib/l10n/gen/` desde
  `app_es.arb` (plantilla) con `flutter gen-l10n`; idiomas `es` y `en`.
