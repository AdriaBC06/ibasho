// Ibasho — registro de motores de juego que el host Kōbō sabe ejecutar.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import 'content_models.dart';

typedef KoboGameHostBuilder =
    Widget Function({
      required ExtensionGame game,
      required List<ExtensionLevel> levels,
      required String localeCode,
      required String Function(String key, String fallback) text,
    });

/// Registro cerrado de motores que viven en el host. Hoy está vacío.
///
/// Un `.ibasho` puede pedir uno de estos IDs, pero nunca registrar una función
/// nueva ni aportar código ejecutable. Añadir otro motor exige una nueva build
/// de Ibasho/Kōbō y una entrada explícita en este registro.
abstract final class KoboGameHostRegistry {
  // Malla vivía aquí hasta que pasó a ser un juego de serie (0.9.1): de pago
  // en la tienda, así que un paquete no debe poder abrirla gratis.
  static final Map<String, KoboGameHostBuilder> _builders =
      <String, KoboGameHostBuilder>{};

  static bool supports(String engine) => _builders.containsKey(engine);

  static Widget? build({
    required ExtensionGame game,
    required List<ExtensionLevel> levels,
    required String localeCode,
    required String Function(String key, String fallback) text,
  }) {
    final builder = _builders[game.engine];
    if (builder == null) return null;
    return builder(
      game: game,
      levels: levels,
      localeCode: localeCode,
      text: text,
    );
  }
}
