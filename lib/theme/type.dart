// Ibasho — escala tipografica.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Escala tipografica del entorno: 11 / 13 / 15 / 19 / 24 / 34 / 48.
///
/// `ZenKaku` (Zen Kaku Gothic New) para toda la interfaz; `Rounded`
/// (M PLUS Rounded 1c) solo para el reloj, los numeros grandes y el logotipo.
/// Interlineado 1.45 en texto corrido. Sin mayusculas forzadas.
abstract final class Ty {
  static const String ui = 'ZenKaku';
  static const String round = 'Rounded';

  /// La tinta del texto: la de serie o la clara de un tema oscuro. La pone
  /// `app.dart` al cambiar de tema (ver `lib/theme/menu_theme.dart`), y con
  /// ella redibuja el arbol entero una vez.
  static Color ink = T.ink;
  static Color inkSoft = T.inkSoft;

  static const double _body = 1.45;
  static const double _tight = 1.12;

  static TextStyle _ui(double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = _body,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: ui,
        fontSize: size,
        fontWeight: weight,
        color: color ?? ink,
        height: height,
        letterSpacing: letterSpacing,
      );

  // Texto de interfaz.
  static TextStyle get micro => _ui(11, color: inkSoft);
  static TextStyle get caption => _ui(13, color: inkSoft);
  static TextStyle get body => _ui(15);
  static TextStyle get lead => _ui(19, weight: FontWeight.w500);
  static TextStyle get title => _ui(24, weight: FontWeight.w500, height: _tight);
  static TextStyle get display => _ui(34, weight: FontWeight.w500, height: _tight);

  /// Etiqueta de un control. Un punto por debajo del cuerpo y algo mas suelta.
  static TextStyle get label => _ui(13, color: inkSoft, letterSpacing: .3);

  // Numeros grandes y logotipo.
  static TextStyle clock(Color color) => TextStyle(
        fontFamily: round,
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.0,
        letterSpacing: -1.2,
      );

  static TextStyle clockSmall(Color color) => TextStyle(
        fontFamily: round,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.0,
        letterSpacing: -.8,
      );

  static TextStyle numeral(double size, {Color? color, FontWeight weight = FontWeight.w500}) =>
      TextStyle(
        fontFamily: round,
        fontSize: size,
        fontWeight: weight,
        color: color ?? ink,
        height: 1.05,
      );

  static TextStyle logo(double size, Color color) => TextStyle(
        fontFamily: round,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1.0,
        letterSpacing: -.5,
      );

  /// El logotipo en japones se compone con la fuente de interfaz, que es la
  /// que trae el kana y el kanji completos.
  static TextStyle logoJa(double size, Color color) => TextStyle(
        fontFamily: ui,
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.0,
        letterSpacing: size * .12,
      );

  /// Bloque monoespaciado para credenciales. No hay fuente propia: se usa la
  /// redondeada con tabulacion fija de digitos.
  static TextStyle get credential => TextStyle(
        fontFamily: round,
        fontSize: 19,
        fontWeight: FontWeight.w500,
        color: ink,
        height: 1.5,
        letterSpacing: 1.6,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
