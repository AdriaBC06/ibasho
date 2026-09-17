// Ibasho — fuente de azar criptografico.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Bytes impredecibles del sistema.
///
/// `Random.secure()` ya pide entropia al sistema operativo (getrandom en
/// Linux y Android, RtlGenRandom en Windows); esto solo le da la forma que
/// espera el resto del modulo.
Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256)),
  );
}

/// Un generador de pointycastle sembrado con azar del sistema.
///
/// Lo pide `ECKeyGenerator`, que no acepta `Random` a secas. Cada llamada
/// devuelve uno recien sembrado: sembrar una vez y guardarlo haria que dos
/// claves generadas en la misma sesion compartieran flujo.
SecureRandom seededRandom() =>
    FortunaRandom()..seed(KeyParameter(randomBytes(32)));
