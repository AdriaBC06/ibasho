// Ibasho — acentos legibles a partir de cualquier color.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Luminancia relativa (WCAG) de un color.
double relativeLuminance(Color color) {
  double channel(double c) =>
      c <= .03928 ? c / 12.92 : math.pow((c + .055) / 1.055, 2.4).toDouble();
  return .2126 * channel(color.r) + .7152 * channel(color.g) + .0722 * channel(color.b);
}

/// Contraste entre dos colores, de 1 a 21.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

/// Contraste minimo de un acento contra el blanco de los paneles.
///
/// Es el del cian de la casa: si el cian se lee bien, cualquier acento que
/// contraste al menos igual tambien. Asi un Tama clarisimo sigue dando un
/// acento con el que se ven el foco, la seleccion y el texto blanco encima.
final double minAccentContrast = contrastRatio(T.cyan, T.shellTop) - .005;

/// Contraste maximo: un acento casi negro deja de parecer un acento.
const double maxAccentContrast = 13;

/// Ajusta un color para usarlo como acento del entorno.
///
/// Conserva el tono y la saturacion y solo mueve la luminosidad lo justo. Un
/// color que ya es legible sale tal cual.
Color readableAccent(Color color) {
  final opaque = color.withValues(alpha: 1);
  final contrast = contrastRatio(opaque, T.shellTop);
  if (contrast >= minAccentContrast && contrast <= maxAccentContrast) {
    return opaque;
  }
  final hsl = HSLColor.fromColor(opaque);
  final darken = contrast < minAccentContrast;
  // Busqueda binaria sobre la luminosidad.
  var lo = darken ? 0.0 : hsl.lightness;
  var hi = darken ? hsl.lightness : 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    final c = contrastRatio(hsl.withLightness(mid).toColor(), T.shellTop);
    final ok = darken ? c >= minAccentContrast : c <= maxAccentContrast;
    if (darken) {
      ok ? lo = mid : hi = mid;
    } else {
      ok ? hi = mid : lo = mid;
    }
  }
  return hsl.withLightness(darken ? lo : hi).toColor();
}

/// El acento sobre plastico negro (temas oscuros): lo mismo que
/// [readableAccent] pero al reves, se aclara lo justo para que se lea sobre
/// la tinta de fondo. Uno ya claro se queda como esta.
Color brightAccent(Color color) {
  final hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  return hsl.lightness >= .62 ? hsl.toColor() : hsl.withLightness(.62).toColor();
}
