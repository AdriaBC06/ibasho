// Ibasho — las chuches que puede dar la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/tama.dart';

/// Chuches desbloqueadas.
///
/// De momento solo las de serie (galleta y caramelo). Cuando llegue la tienda,
/// este provider leera las compradas de la cuenta y la interfaz no tendra que
/// cambiar: ya ensena las demas bloqueadas.
final unlockedFoodsProvider = Provider<Set<TamaFood>>(
  (ref) => {for (final food in TamaFood.values) if (food.unlockedByDefault) food},
);
