# Ohirune (お昼寝)

Canal **secreto** de la 0.6.3: el puzle de la siesta. Es el *Queens* de
LinkedIn (un *Star Battle* de una estrella) con Tamas.

## Reglas

- Tablero N×N repartido en N zonas de color; cada zona es de **uno de tus
  Tamas** (el color de su cuerpo, aclarado; si dos se parecen, el segundo se
  aclara u oscurece: `ohiruneZoneColors`).
- Un Tama por **fila**, por **columna** y por **zona**, y ninguno puede tocar a
  otro, ni en diagonal.
- Cada puzle tiene **una sola solución**. Dormir a un Tama donde no va cuesta
  **una vida** (hay 3) y deja una X roja en la casilla; las X propias son
  gratis. Sin vidas, la partida acaba.
- Controles: clic = dormir un Tama (sobre una X, el primer clic la quita);
  clic derecho = X; arrastrando se marcan o borran varias X. En el móvil, un
  interruptor dormir / marcar X.

## Niveles y desbloqueo

| Nivel | Tablero | Tamas | Monedas |
|---|---|---|---|
| fácil | 5×5 | 5 | 3 |
| normal | 6×6 | 6 | 3 |
| difícil | 7×7 | 7 | 5 |
| experto | 8×8 | 8 | 5 |
| maestro | 9×9 | 9 | 8 |
| del día | 6×6 | 6 | 5 |

- El canal no aparece hasta tener **5 Tamas** (`ohiruneUnlockTamas`); entonces
  llega envuelto (`prefs.ohiruneOpened`). Quien ya los tiene lo recibe al
  actualizar. Abierto, se queda aunque se borren Tamas.
- Cada nivel pide sus Tamas: si faltan, la tarjeta lleva candado y dice
  cuántos. Sin los 5 del fácil, el tablero enseña «faltan dormilones».
- Es **gratis**: `earnings/ohirune` no exige `games/ohirune` en las reglas.
  Mismo tope de 20 al día que los demás juegos.
- Su tabla en Clasificaciones tampoco se ve hasta tener el canal.

## Tablero del día y clasificación

- Semilla `bonusDay()` (día UTC, el mismo que la clasificación): igual para
  todo el mundo. Se baraja qué Tama duerme en cada zona con la misma semilla.
- Clasificación `ohirune` (diaria y semanal): **tiempo + 20 s por vida
  perdida**, en ms; menor es mejor (`ohiruneBoardScore`). Solo cuenta el del
  día. Las reglas lo tratan como el buscaminas.

## Código

- `lib/games/ohirune/ohirune.dart`: niveles, generador (solución al azar sin
  tocarse → zonas que crecen desde cada Tama a ritmos distintos → se retocan
  casillas hasta que no queda otra solución), `solveOhirune` y la partida.
- `ohirune_board.dart`: tablero pintado (zonas, fronteras gruesas, X, Tamas
  dormidos con `TamaPainter` y la pose `sleepy`; al ganar se despiertan en ola).
- `ohirune_channel.dart`: escena como el buscaminas; `ohirune_store.dart`:
  récords locales (`ohirune.json`).
- Icono `ArtIcon.ohirune`, glifo `Glyph.moon`.
- Pruebas: `test/ohirune_test.dart` (motor), `test/ohirune_tour_test.dart`
  (capturas en `build/screenshots/ohirune/`), reglas en `rules_05` y
  `rules_leaderboards`.
