# Cambios de Ibasho

Las versiones siguen los checkpoints del proyecto: `mayor.menor.parche`, donde
cada checkpoint sube la menor y los arreglos sobre él suben el parche. La
versión que corre cada build está en `pubspec.yaml` y en `lib/core/version.dart`
(lo comprueba `test/update_gate_test.dart`).

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
