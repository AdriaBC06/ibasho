// Ibasho — tokens visuales del entorno.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

/// Paleta y medidas del entorno. Ningun otro archivo escribe un color a mano.
///
/// La referencia es la zona donde se tocan el menu de Wii y el HOME Menu de
/// 3DS: blanco luminoso, plastico brillante, bisel plateado y cian como unico
/// acento.
abstract final class T {
  // --- Superficies -------------------------------------------------------
  /// Arranque del degradado de los paneles.
  static const Color shellTop = Color(0xFFFFFFFF);

  /// Final del degradado de los paneles.
  static const Color shellBottom = Color(0xFFDDE7EF);

  /// Marco metalico que rodea las pantallas.
  static const Color bezelTop = Color(0xFFE9EEF2);
  static const Color bezelBottom = Color(0xFFB6C4CF);

  /// Lineas de 1 px de separacion.
  static const Color hairline = Color(0xFFC2CED8);

  // --- Tinta -------------------------------------------------------------
  /// Texto principal. Gris azulado, nunca negro puro.
  static const Color ink = Color(0xFF3A4750);

  /// Texto secundario y estados deshabilitados.
  static const Color inkSoft = Color(0xFF7C8B97);

  // --- Acento ------------------------------------------------------------
  /// Acento unico: foco, seleccion, brillos.
  ///
  /// En el CP2 cada usuario tendra un color de Tama que sustituira este valor
  /// en tiempo de ejecucion; por eso la interfaz nunca lo lee directamente,
  /// sino a traves de `IbashoSkin.of(context).accent`.
  static const Color cyan = Color(0xFF5BC8F5);

  /// Bordes y estados presionados del acento.
  static const Color cyanDeep = Color(0xFF1B8FD0);

  /// Avisos, cumpleanos, insignias.
  static const Color warn = Color(0xFFE8A33D);

  // --- Derivados ---------------------------------------------------------
  // Valores calculados a partir de los anteriores. Viven aqui para que no
  // aparezca ni un hex suelto en el resto del codigo.

  /// Relleno de la ventana fuera del lienzo virtual (letterboxing).
  static const Color letterbox = Color(0xFF1D242A);

  /// Brillo especular del tercio superior de cada superficie pulsable.
  static const Color specular = Color(0x99FFFFFF);
  static const Color specularSoft = Color(0x2EFFFFFF);

  /// Sombra corta y suave bajo paneles y piezas elevadas.
  static const Color shadow = Color(0x1F3A4750);
  static const Color shadowDeep = Color(0x333A4750);

  /// Hueco hundido: ranuras libres y campos de texto.
  static const Color wellTop = Color(0xFFD5DFE7);
  static const Color wellBottom = Color(0xFFF2F6F9);

  /// Velo sobre el entorno cuando hay un dialogo delante.
  static const Color scrim = Color(0x662B343B);

  /// Paleta de acentos que puede elegir el usuario.
  ///
  /// El cian es el de la casa y va primero; el resto existe porque en el CP2
  /// cada Tama tendra su color y conviene que el entorno ya sepa vivir con
  /// cualquiera de ellos.
  static const List<Color> accentPalette = <Color>[
    cyan,
    Color(0xFF6FD1B0),
    Color(0xFF8CC96A),
    Color(0xFFE8C35A),
    Color(0xFFF0946A),
    Color(0xFFEE7C96),
    Color(0xFFB08BE0),
    Color(0xFF7C9BE8),
  ];

  /// Texto e iconos sobre una superficie tenida de acento o de aviso.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// Color con el que se oscurece cualquier tinte para bordes y fondos de
  /// degradado. Azul noche, para que el acento oscurecido no se ensucie.
  static const Color dusk = Color(0xFF0B2230);

  /// Blanco transparente: extremo de los degradados de brillo.
  static const Color glintNone = Color(0x00FFFFFF);
  static const Color glintFaint = Color(0x14FFFFFF);
  static const Color glintSoft = Color(0x3DFFFFFF);
  static const Color glintMid = Color(0x40FFFFFF);
  static const Color glintRim = Color(0x66FFFFFF);
  static const Color glintPanel = Color(0x8CFFFFFF);
  static const Color glintStrong = Color(0xB3FFFFFF);

  /// Final del degradado de las tarjetas de contenido, un punto mas claro que
  /// el de los paneles para que se despeguen de ellos.
  static const Color cardBottom = Color(0xFFF2F6FA);

  /// Sombra del rebaje del bisel alrededor de cada pantalla.
  static const Color bezelRecess = Color(0x2E3A4750);

  // --- Geometria ---------------------------------------------------------
  /// El entorno entero se dibuja sobre este lienzo y se escala con FittedBox.
  static const Size canvas = Size(1280, 800);

  static const double panelWidth = 1200;
  static const double panelRadius = 30;
  static const double tileRadius = 20;
  static const double buttonRadius = 22;
  static const double fieldRadius = 16;

  /// Alturas de los dos paneles en cada estado del boton de ampliar.
  /// La suma es constante para que el entorno no se mueva de sitio.
  static const double panelBalanced = 340;
  static const double panelLarge = 560;
  static const double panelSmall = 120;

  // --- Movimiento --------------------------------------------------------
  static const Duration magnify = Duration(milliseconds: 320);
  static const Duration channelOpen = Duration(milliseconds: 460);
  static const Duration page = Duration(milliseconds: 380);
  static const Duration hover = Duration(milliseconds: 180);
  static const Duration press = Duration(milliseconds: 90);

  /// Sustituto de cualquier animacion cuando hay movimiento reducido.
  static const Duration reduced = Duration(milliseconds: 100);
}
