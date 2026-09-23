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

  /// La tinta de los temas oscuros: casi blanca, nunca blanco puro.
  static const Color inkDark = Color(0xFFE9EFF6);
  static const Color inkSoftDark = Color(0xFF9DAABB);

  // --- Acento ------------------------------------------------------------
  /// Acento unico: foco, seleccion, brillos.
  ///
  /// Cada usuario puede cambiarlo o hacer que siga el color de su Tama; por
  /// eso la interfaz nunca lo lee directamente, sino a traves de
  /// `IbashoSkin.of(context).accent`.
  static const Color cyan = Color(0xFF5BC8F5);

  /// Bordes y estados presionados del acento.
  static const Color cyanDeep = Color(0xFF1B8FD0);

  /// Avisos, cumpleanos, insignias.
  static const Color warn = Color(0xFFE8A33D);

  /// Respuesta acertada en un juego (Nihongo): verde menta lacado.
  static const Color correct = Color(0xFF4CC38A);

  /// Respuesta fallada: rojo suave, que avisa sin regañar.
  static const Color wrong = Color(0xFFEF6B73);

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
  /// El cian es el de la casa y va primero. Ademas de estos, el acento puede
  /// seguir el color del Tama de perfil (ver `lib/theme/accent.dart`).
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

  // --- Temas del menu ----------------------------------------------------

  /// Tono de cada tema N del gacha: el color de su fondo
  /// (`backdrop_art.dart`). Tine las superficies de todo el entorno con un
  /// velo (ver `lib/theme/menu_theme.dart`) y da el acento «del tema».
  static const Color themeSky = Color(0xFF7FD4F5);
  static const Color themeCoral = Color(0xFFFF9C86);
  static const Color themeMint = Color(0xFF7FE0B8);
  static const Color themePeach = Color(0xFFFFC58A);

  /// Los R, SR, SSR, UR y ∞ tinen con dos o tres tonos: el plastico, el
  /// marco (bisel, huecos) y, desde SSR, uno hondo para el pie del bisel y
  /// las lineas. Los `Glow` son la luz de los adornos de los canales.
  static const Color themeLavender = Color(0xFFC8A8F2);
  static const Color themeLavenderFrame = Color(0xFF9FA8F0);
  static const Color themeDusk = Color(0xFF6A78C8);
  static const Color themeDuskFrame = Color(0xFF7A5CC0);
  static const Color themeSunrise = Color(0xFFFFC37A);
  static const Color themeSunriseFrame = Color(0xFFFF8FA6);
  static const Color themeLagoon = Color(0xFF5FD6C4);
  static const Color themeLagoonFrame = Color(0xFF3FADC4);
  static const Color themeAurora = Color(0xFF7FE8C4);
  static const Color themeAuroraFrame = Color(0xFF7FD6F2);
  static const Color themeCandy = Color(0xFFFF9FCB);
  static const Color themeCandyFrame = Color(0xFFCBA6F5);
  static const Color themeForest = Color(0xFFA8D878);
  static const Color themeForestFrame = Color(0xFF3E8F5C);
  static const Color themeSunset = Color(0xFFFFB35C);
  static const Color themeSunsetFrame = Color(0xFFF0578C);
  static const Color themeSunsetDeep = Color(0xFF5E3AA0);
  static const Color themeGlacier = Color(0xFF7FD1F2);
  static const Color themeGlacierFrame = Color(0xFF3E6FA8);
  static const Color themeGlacierDeep = Color(0xFF2E4F8A);
  static const Color themePhoenix = Color(0xFFFFC04A);
  static const Color themePhoenixFrame = Color(0xFFF0577A);
  static const Color themePhoenixDeep = Color(0xFF6E1E3C);
  static const Color themePhoenixGlow = Color(0xFFFF9A3C);
  static const Color themeBorealis = Color(0xFF3FC99A);
  static const Color themeBorealisFrame = Color(0xFF5E7FD0);
  static const Color themeBorealisDeep = Color(0xFF3C1E6E);
  static const Color themeBorealisGlow = Color(0xFF5FF0B0);
  static const Color themeBorealisGlowAlt = Color(0xFFA07CF0);
  static const Color themeStarfield = Color(0xFF6C84D8);
  static const Color themeStarfieldFrame = Color(0xFF3A4E9A);
  static const Color themeStarfieldDeep = Color(0xFF1C2C5C);
  static const Color themeStarfieldGlow = Color(0xFF8FA6F0);
  static const Color themeStarfieldGlowAlt = Color(0xFFC8B8FF);

  // --- Tamas -------------------------------------------------------------

  /// Paleta cerrada del Tama: 16 tonos aero elegidos a mano.
  ///
  /// Todos tienen el brillo y la saturacion justos para verse como plastico
  /// lacado bajo la luz del entorno. Es el modo por defecto del creador; quien
  /// quiera otro color exacto tiene el modo HEX libre.
  static const List<Color> tamaPalette = <Color>[
    Color(0xFF5BC8F5), // cielo: el cian de la casa
    Color(0xFF52D3CF), // laguna
    Color(0xFF74DDA2), // menta
    Color(0xFFA6DA62), // lima
    Color(0xFFF3D95A), // limon
    Color(0xFFF7BC55), // miel
    Color(0xFFF79A68), // mandarina
    Color(0xFFF58282), // coral
    Color(0xFFF47AA6), // fresa
    Color(0xFFF6A8D0), // chicle
    Color(0xFFC9A4EE), // lila
    Color(0xFF9F86E6), // uva
    Color(0xFF7E9BF2), // pervinca
    Color(0xFF5E8DE8), // zafiro
    Color(0xFFEEF2F6), // perla
    Color(0xFF8E9AA6), // grafito
  ];

  /// Tinta de ojos y boca. Azul noche muy oscuro: un negro puro se ve duro
  /// sobre el plastico.
  static const Color tamaInk = Color(0xFF26313A);

  /// Interior de la boca abierta.
  static const Color tamaMouth = Color(0xFF7A3346);

  /// Lengua.
  static const Color tamaTongue = Color(0xFFF28A9C);

  /// Rubor de las mejillas y el interior de las orejas.
  static const Color tamaBlush = Color(0xFFF7849B);

  /// Comida de los Tamas. Colores de pasteleria: se tienen que reconocer de
  /// un vistazo a 30 px.
  static const Color foodDough = Color(0xFFE9B97C);
  static const Color foodDoughDark = Color(0xFFB97C45);
  static const Color foodChip = Color(0xFF5E3B28);
  static const Color foodCandy = Color(0xFFF2638A);
  static const Color foodFrosting = Color(0xFFFFD3E4);
  static const Color foodCherry = Color(0xFFE23A55);
  static const Color foodCup = Color(0xFF7FC6EE);
  static const Color foodApple = Color(0xFFEE4F4F);
  static const Color foodStem = Color(0xFF7A5236);
  static const Color foodDangoPink = Color(0xFFF7B3C7);
  static const Color foodDangoWhite = Color(0xFFFFF5EA);
  static const Color foodDangoGreen = Color(0xFFA7D88A);
  static const Color foodStick = Color(0xFFD8B37E);
  static const Color foodSprinkleBlue = Color(0xFF6CC3F2);
  static const Color foodSprinkleYellow = Color(0xFFF6CF4E);
  static const Color foodMochi = Color(0xFFFAD9E3);
  static const Color foodLolly = Color(0xFFFF78A6);
  static const Color foodCone = Color(0xFFE9B368);
  static const Color foodConeDark = Color(0xFFC08443);
  static const Color foodScoop = Color(0xFF9FE0C6);
  static const Color foodGlaze = Color(0xFFF590B7);
  static const Color foodFlan = Color(0xFFF6D46E);
  static const Color foodCaramel = Color(0xFFB5622A);

  /// Sombra de contacto del Tama sobre el suelo o la peana.
  static const Color tamaGroundShadow = Color(0x383A4750);

  /// Negro de pigmento. Solo para el selector de color libre, que tiene que
  /// poder llegar a cualquier color; la interfaz nunca pinta con el.
  static const Color pigmentBlack = Color(0xFF000000);

  /// Corazones y destellos de alegria.
  static const Color tamaHeart = Color(0xFFF26D8E);

  // --- Cumpleaños --------------------------------------------------------

  /// Gorrito de fiesta del Tama: cono a rayas y borla.
  static const Color partyHat = Color(0xFFFF8FB4);
  static const Color partyStripe = Color(0xFFFFD86B);
  static const Color partyPompom = Color(0xFFFFF6D6);

  /// Confeti y guirnalda del perfil el dia del cumpleaños.
  static const List<Color> confetti = <Color>[
    Color(0xFFFF8FB4),
    Color(0xFFFFD86B),
    Color(0xFF7FD6F7),
    Color(0xFF9EE3B8),
    Color(0xFFC6A8F0),
  ];

  /// Lavado calido de los paneles el dia del cumpleaños.
  static const Color partyWash = Color(0xFFFFF3E2);

  // --- Presencia --------------------------------------------------------

  /// Piloto de cada estado, como el LED de una consola.
  static const Color presenceOnline = Color(0xFF4CC985);
  static const Color presenceAway = Color(0xFFF2B640);
  static const Color presenceBusy = Color(0xFFE8625E);
  static const Color presenceOffline = Color(0xFFB3BEC8);

  /// Insignia con el numero de solicitudes pendientes.
  static const Color badge = Color(0xFFE8625E);

  // --- Sobre acento -----------------------------------------------------

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

  // --- Buscaminas --------------------------------------------------------

  /// Colores de los numeros del tablero, del 1 al 8. Cada uno se distingue
  /// de sus vecinos a primera vista y todos se leen sobre el hueco claro.
  static const List<Color> mineNumbers = <Color>[
    Color(0xFF2F8FDB),
    Color(0xFF2FA86B),
    Color(0xFFE5484D),
    Color(0xFF7A55D1),
    Color(0xFFD9811A),
    Color(0xFF14999B),
    Color(0xFF3A4750),
    Color(0xFF7C8B97),
  ];

  /// La casilla que exploto.
  static const Color mineBoom = Color(0xFFFFB3A8);

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
