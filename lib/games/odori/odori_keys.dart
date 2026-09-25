// Ibasho — Odori: las teclas de cada carril.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

/// Teclas fisicas por numero de carriles: la posicion en el teclado, no la
/// letra, para que DFJK caigan bajo los dedos con cualquier distribucion.
const Map<int, List<PhysicalKeyboardKey>> odoriDefaultKeys = {
  1: [PhysicalKeyboardKey.space],
  2: [PhysicalKeyboardKey.keyF, PhysicalKeyboardKey.keyJ],
  3: [PhysicalKeyboardKey.keyF, PhysicalKeyboardKey.space, PhysicalKeyboardKey.keyJ],
  4: [PhysicalKeyboardKey.keyD, PhysicalKeyboardKey.keyF, PhysicalKeyboardKey.keyJ, PhysicalKeyboardKey.keyK],
  5: [
    PhysicalKeyboardKey.keyD,
    PhysicalKeyboardKey.keyF,
    PhysicalKeyboardKey.space,
    PhysicalKeyboardKey.keyJ,
    PhysicalKeyboardKey.keyK,
  ],
  6: [
    PhysicalKeyboardKey.keyS,
    PhysicalKeyboardKey.keyD,
    PhysicalKeyboardKey.keyF,
    PhysicalKeyboardKey.keyJ,
    PhysicalKeyboardKey.keyK,
    PhysicalKeyboardKey.keyL,
  ],
  7: [
    PhysicalKeyboardKey.keyS,
    PhysicalKeyboardKey.keyD,
    PhysicalKeyboardKey.keyF,
    PhysicalKeyboardKey.space,
    PhysicalKeyboardKey.keyJ,
    PhysicalKeyboardKey.keyK,
    PhysicalKeyboardKey.keyL,
  ],
};

/// Segunda tecla de cada figura de Butai, si se activa: las flechas, en el
/// mismo orden ← ↓ ↑ →.
const List<PhysicalKeyboardKey> butaiAltDefault = [
  PhysicalKeyboardKey.arrowLeft,
  PhysicalKeyboardKey.arrowDown,
  PhysicalKeyboardKey.arrowUp,
  PhysicalKeyboardKey.arrowRight,
];

/// Lo que se pinta bajo cada receptor. Sale del codigo USB de la tecla:
/// `debugName` no existe en las versiones de release.
String keyCap(PhysicalKeyboardKey key) {
  final usb = key.usbHidUsage;
  if (key == PhysicalKeyboardKey.space) return '␣';
  if (usb >= 0x00070004 && usb <= 0x0007001d) return String.fromCharCode(0x41 + usb - 0x00070004);
  if (usb >= 0x0007001e && usb <= 0x00070026) return '${usb - 0x0007001e + 1}';
  if (usb == 0x00070027) return '0';
  return switch (usb) {
    0x00070033 => 'Ñ',
    0x00070036 => ',',
    0x00070037 => '.',
    0x00070038 => '-',
    0x000700e1 || 0x000700e5 => '⇧',
    0x00070050 => '←',
    0x0007004f => '→',
    0x00070052 => '↑',
    0x00070051 => '↓',
    _ => '·',
  };
}
