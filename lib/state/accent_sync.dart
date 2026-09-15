// Ibasho — el acento del perfil y el color del Tama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Color;

import '../backend/models.dart';
import '../backend/tama.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';

/// Que hacer con el acento cuando cambia el color del Tama de perfil.
enum AccentSync {
  /// Nada: ya coincide, o el usuario lo eligio a mano y el color no ha
  /// cambiado.
  none,

  /// Seguir al Tama sin preguntar.
  follow,

  /// El usuario eligio el acento a mano: preguntar antes de tocarlo.
  ask,
}

/// Acento que corresponde a un color de Tama: el mismo tono, legible sobre
/// los paneles blancos.
Color accentForTama(String tamaHex) =>
    readableAccent(colorFromHex(tamaHex) ?? T.cyan);

/// Decide que pasa con el acento cuando el Tama de perfil pasa a tener
/// `tamaHex`.
///
/// - Si el acento ya sigue al Tama, se actualiza solo.
/// - Si nunca se ha elegido nada y sigue el cian de serie, se sincroniza: no
///   hay ningun color elegido a mano que pisar.
/// - Si se toco a mano, se pregunta. Nunca se pisa sin permiso.
AccentSync decideAccentSync(UserProfile profile, String tamaHex) {
  final target = hexFromColor(accentForTama(tamaHex));
  switch (profile.accentFollowsTama) {
    case true:
      return profile.accentColor.toUpperCase() == target ? AccentSync.none : AccentSync.follow;
    case null:
      return profile.accentColor.toUpperCase() == hexFromColor(T.cyan)
          ? AccentSync.follow
          : (profile.accentColor.toUpperCase() == target ? AccentSync.none : AccentSync.ask);
    case false:
      return profile.accentColor.toUpperCase() == target ? AccentSync.none : AccentSync.ask;
  }
}

/// El perfil con el acento enganchado al Tama.
UserProfile followTama(UserProfile profile, String tamaHex) => profile.copyWith(
      accentColor: hexFromColor(accentForTama(tamaHex)),
      accentFollowsTama: true,
    );
