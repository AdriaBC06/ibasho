# Hatarakitama (働きたま)

Canal de la 0.7.0: el juego *idle* de Ibasho, inspirado en *Melvor Idle* y
*RuneScape*. Tus Tamas trabajan en el pueblo aunque la app esté cerrada, suben
oficios del 0 al 99 y salen de expedición.

## Reglas del juego

- **13 oficios**: tala, pesca, minería, huerto, recolecta y agilidad (sacan
  cosas del mundo; agilidad solo da experiencia), cocina, carpintería, forja,
  costura, té y joyería (las transforman) y **expediciones**.
- Cada oficio va del 0 al 99: el 1 llega a los 40 xp y del 2 en adelante es la **curva de RuneScape** (el 92 es la mitad
  del 99: 13 034 431 xp). Cada tarea pide un nivel.
- **Maestría** por tarea (0–99, con una cuarta parte de la experiencia): cada
  nivel quita un 0,2 % de tiempo y da un nivel/400 de sacar doble.
- **Los Tamas son los trabajadores**: una ranura por Tama y tarea. Se empieza
  con una y se abren más con el **nivel total** (40, 100, 200, 350 y 550), hasta
  seis.
  - **Personalidad**: un 15 % más rápido en sus oficios (tranquilo: pesca,
    huerto y té; juguetón: agilidad, recolecta y expediciones; tímido: costura
    y joyería; pícaro: minería, forja y tala; dormilón: cocina y carpintería).
  - **Ánimo**: de ×0,8 a ×1,2 en velocidad, el mismo ánimo de siempre (mimos
    y comida). En el canal se le puede mimar en el escenario y **dar de comer**
    lo cocinado en el propio juego: cuenta como comer, sin tocar la despensa.
- Si faltan materiales, el Tama **se para** y lo avisa.
- **Tés** (30 min): aceleran un oficio o todo, del 5 al 20 %.
- **Agilidad**: cada nivel, un 0,1 % más rápido en todo.
- **Offline**: al volver se simula lo que ha pasado, con un tope de **12 h**, y
  sale el resumen de «mientras no estabas…». Las expediciones vuelven por reloj
  aunque pasen de las 12 h.

## Expediciones

- Grupo de 1 a 3 Tamas libres (ni trabajando ni de viaje), comida (puntos:
  Tamas × minutos / 10) y el **equipo** del almacén: herramienta (forja), ropa
  (costura), bolsa (carpintería) y amuleto (joyería).
- **Fuerza** = (5 + nivel de expediciones) por Tama (+15 % a los juguetones)
  + equipo. Frente a la dificultad del sitio da el éxito (30–100 %), que
  escala botín, experiencia y la probabilidad de **tesoro** del gacha.
- Ocho sitios, del prado (nv. 0, 10 min) a la luna (nv. 95, 3 h). Traen lo que
  no sale de otra forma: plumas, caracolas, ámbar, ascuas, nubes, polvo de luna
  e hilo de seda.

## Interfaz

- Botón de **información** arriba: la ayuda en seis páginas (trabajo, nivel
  total, maña, materiales, expediciones y monedas). Sale sola una única vez
  (`prefs.hatarakiHelpSeen`), en la primera partida, y tocar el nivel total la abre en su página.
- El Tama elegido dice su ritmo (segundos por vez y cuánto por hora), su maña
  por personalidad y su ánimo. Si está parado, dice qué le falta y con qué
  oficio o sitio se consigue. «Cambiar tarea» lleva a la suya.
- Las tareas dicen «tienes/pide» de cada material, quién las hace y por qué
  están bloqueadas. Las ranuras con Tamas llevan un globito.
- Al elegir Tama con las ranuras llenas, solo se puede elegir a uno que ya
  trabaja (se le cambia la tarea), y se avisa.
- Almacén con nombres, «sale de» y «se usa en»; el equipo se pone y se quita.
- Expediciones: éxito en %, el botón dice qué falta (grupo, comida, nivel), la
  cruz saca a un Tama del grupo y **volver ya** las trae antes, sin botín ni
  experiencia (la comida ya se gastó).
- El té activo sale sobre el escenario con lo que le queda.
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
  llena el almacén, da ginmon, trae la expedición, añade tesoros, simula 3 h
  fuera, vuelve a enseñar la ayuda, cambia la canción y empieza de cero.
- Pruebas: `test/hataraki_test.dart` (motor), `test/hataraki_tour_test.dart`
  (capturas en `build/screenshots/hataraki/` y nombres de todo) y
  `rules_05.test.mjs` (cobros y forma de la partida) y
  `rules_leaderboards.test.mjs` (tope de ginmon y tabla de siempre).
