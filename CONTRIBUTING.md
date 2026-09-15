# Contribuir a Ibasho

Gracias por el interés. Ibasho es pequeño y opinado; estas normas existen para
que siga pareciendo una consola y no una app genérica.

## Antes de abrir un PR

```sh
flutter analyze        # cero avisos
flutter test           # entorno, Tamas y recorrido visual (PNG en build/screenshots/)
./tool/test_rules.sh   # reglas de la base contra el emulador de Firebase
./tool/test_e2e.sh     # cuentas y Tamas contra los emuladores de Auth y Database
```

## Normas de código

- **Cabecera de licencia** en cada archivo fuente:
  ```dart
  // Ibasho — <qué es este archivo>.
  // Copyright (C) <año> <tu nombre>
  // SPDX-License-Identifier: GPL-3.0-or-later
  ```
- **Nada de Material.** La raíz es `WidgetsApp` y `uses-material-design` está a
  `false`. No importes `package:flutter/material.dart`. Si necesitas un control,
  constrúyelo sobre `Pressable` y `GlossSurface`.
- **Iconos de una sola línea.** Se dibujan en `lib/ui/widgets/glyphs.dart` sobre
  una caja de 24×24: el trazo no se sale de la caja y las piezas se unen por sus
  extremos o se separan con aire, nunca se cruzan ni se montan (orejas, dientes
  o patas van en el mismo contorno). `test/glyphs_test.dart` lo comprueba con
  píxeles para cada icono, también los que añadas.
- **Ni un color suelto.** Todos viven en `lib/theme/tokens.dart`. El acento se
  lee siempre de `IbashoSkin.of(context).accent`, nunca de `T.cyan` directamente,
  porque puede ser el elegido por la cuenta o el color de su Tama.
- **Ni una cadena suelta.** Todo texto visible va en `lib/l10n/app_es.arb` y
  `app_en.arb`, los dos a la vez.
- **Movimiento reducido.** Toda duración pasa por `skin.motion(...)` y toda curva
  por `skin.curve(...)`.
- **La UI no sabe de REST.** Solo `lib/backend/` conoce Firebase. El resto habla
  con `IbashoBackend`.

## Assets

Audio solo CC0 o CC BY; tipografías solo SIL OFL. Nada con NC ni ND. Cada asset
nuevo va a `CREDITS.md` **y** a `lib/core/credits.dart`.

## Secretos

Nunca en el repositorio. La configuración va en `.env`, que está en `.gitignore`.
