# Malla de serie (0.9.1)

Malla llegó con la PR #1 de Mr-E28j (Kōbō) como juego de un paquete
`.ibasho` que jugaba online contra `mallagame.netlify.app`. En la 0.9.1 pasa a
ser un juego más de Ibasho y su online va por nuestro Firebase.

## Decisiones (elegidas el 2026-10-04)

- **De serie**: canal fijo, en la tienda por **10** monedas (`game_malla`).
  Kōbō se queda para instalar `.ibasho`, pero ya no puede abrir Malla: un
  paquete se saltaría la compra.
- **Online por Firebase**, sin conexiones nuevas: la sala se escucha por el
  `RtdbSocket` compartido y el buzón sale de la conexión de la cuenta. Se pierde
  la compatibilidad con Malla Web.
- **Quién**: amigos por invitación (buzón `mallaInbox`, caduca a los 10 min) y
  código de sala de 6 caracteres para cualquier cuenta de Ibasho.
- **Monedas** (tope de 20 al día del juego): contra bots, 3 al ganar (1 en
  fácil); online, 5 al ganador y 1 a los demás por acabar.
- **Historial**: lista propia de partidas online en la cuenta
  (`users/{yo}/mallaHistory`), las 30 últimas: fecha, tamaño, jugadores con
  nombre, Tama y puntos, y quién ganó.
- **Abandono**: a los 20 s sin señal se le salta (sus aristas se quedan); si
  queda uno solo, gana.
- **Identidad**: nombre de Ibasho, el Tama de la ficha y un color de la paleta
  de Malla (`Art.mallaPlayers`, seis colores de caramelo). La marca que piden
  las reglas de la sala es la inicial del nombre y no se enseña.
- **Música**: canción nueva propia.

## Sala: `/malla/{código}`

El código son 6 caracteres de `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. Solo se lee
un código concreto (no hay lectura de `/malla`): cualquiera mientras la sala
espera, y los miembros siempre.

```
host, at, size (3–7), max (2–6), chain, state: wait|play|done|gone
members/{cuenta}: {name, tama: {name, personality, look}, marker, color, at, ping}
-- al empezar (lo escribe host) --
order/{asiento}: cuenta        start: asiento que abre     startAt
n: jugadas escritas            turn: asiento al que le toca
moves/{i}: {k: arista, p: asiento} | {o: asiento que queda fuera}
next: código de la revancha (host, con la sala acabada)
```

- **Unirse**: cada uno escribe su `members/{yo}` mientras `wait`. El host
  empieza con 2 o más; los asientos son el orden de llegada (`at`), hasta `max`.
- **Jugar**: una jugada es `moves/{n}` + `n+1` + `turn` en la misma escritura.
  Las reglas exigen que `p` sea mi asiento y que fuera mi turno; la arista y el
  siguiente turno los comprueba cada cliente rejugando la partida.
- **Saltar**: `moves/{n} = {o: asiento}` lo escribe el propio jugador al irse o
  cualquiera cuando ese asiento lleva 20 s sin `ping`. Al rejugar, ese asiento
  deja de tener turno. Con uno solo dentro, la partida acaba y gana él.
- **Acabar**: quien ve el final pone `state: done`; cada uno escribe su
  historial y cobra lo suyo.
- **Revancha**: el host crea otra sala y escribe `next`; los demás entran solos.
- **Limpieza**: el host borra la sala acabada al salir o empezar la siguiente;
  un código de hace más de un día se puede pisar.

## Fases

1. Malla de serie: `lib/games/malla`, canal y tienda, fuera de Kōbō, sin Netlify.
2. Reglas (`/malla`, `mallaInbox`, `mallaHistory`) con tests y el controlador.
3. Interfaz online: crear/código/invitar, sala con Tama y nombre, saltar,
   revancha e historial.
4. Monedas y textos en inglés y español.
5. Música nueva.
6. Interfaz de Ibasho (la de la PR no seguía `docs/UI.md`): menú de tres
   puertas como Tsumiki, ajustes en raíles, partida en una escena con tu Tama
   y el tablero de plástico (fichas hexagonales, varillas de color, puntos de
   cada jugador en los hexágonos a medias), contra **tus Tamas** en vez de
   máquinas con emoji, nada que desplazar (historial, amigos y logros por
   páginas; reglas en un diálogo de páginas), avisos con el bocadillo del Tama
   y con toasts. Fuera: la marca libre, los colores hex, el sonido propio, el
   modo «enfocar» y el minijuego Guardia de la sala de espera. Recorrido de
   capturas: `flutter test test/malla_tour_test.dart`.

## Al publicar

- Desplegar reglas y `dart run tool/seed_shop.dart` (`game_malla` 10).
- Subir minVersion a la 0.9.1 (ver `docs/` y la memoria de Firebase).
