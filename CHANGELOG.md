# Cambios de Ibasho

Las versiones siguen los checkpoints del proyecto: `mayor.menor.parche`, donde
cada checkpoint sube la menor y los arreglos sobre él suben el parche. La
versión que corre cada build está en `pubspec.yaml` y en `lib/core/version.dart`
(lo comprueba `test/update_gate_test.dart`).

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
