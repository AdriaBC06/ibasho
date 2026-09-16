// Ibasho — en que tipo de equipo se esta ejecutando.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Diferencias de plataforma que no dependen de la forma de la ventana.
///
/// La composicion (lienzo horizontal o vertical) se decide por la proporcion
/// de la ventana, no por aqui. Esto es solo para lo que de verdad cambia con
/// el sistema: ciclo de vida, foco de audio, boton de atras, compartir.
///
/// Se mira `Platform` y no `defaultTargetPlatform` a proposito: en los tests
/// de widgets `defaultTargetPlatform` es Android, y la rama de Linux tiene que
/// ser la que se prueba por defecto.
abstract final class Device {
  /// Movil Android: sin raton, con boton de atras, ciclo de vida de movil.
  static bool get isAndroid => debugAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Solo para tests: fuerza la rama de Android.
  @visibleForTesting
  static bool? debugAndroid;
}
