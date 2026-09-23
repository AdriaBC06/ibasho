// Ibasho — los temas del menu: las superficies de todo el entorno.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Un fondo del gacha (`lib/backend/backdrops.dart`) es tambien un tema: ademas
// de pintarse detras de los paneles, tine el plastico, los huecos, el bisel y
// las lineas de todo el entorno, menu, canales y juegos. Las ilustraciones y
// las piezas de colores propios no cambian (docs/UI.md §4).

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import 'accent.dart';
import 'tokens.dart';

/// El adorno que un tema pone detras de los canales, de menos a mas: cada
/// uno incluye los anteriores. Es la escalera de rareza de los fondos
/// (`backdrop_art.dart`) llevada al entorno: SR cristal, SSR destellos, UR
/// algo vivo y ∞ el cielo.
enum Ornament { none, sheen, sparkle, aura, stars }

/// Los colores de los materiales del entorno. Los de serie son los de [T];
/// un tema los cambia todos a la vez para que el material siga siendo uno.
@immutable
class Surfaces {
  const Surfaces({
    required this.shellTop,
    required this.shellBottom,
    required this.cardBottom,
    required this.wellTop,
    required this.wellBottom,
    required this.hairline,
    required this.bezelTop,
    required this.bezelBottom,
    this.specular = T.specular,
    this.bounce = T.shellTop,
    this.ornament = Ornament.none,
    this.glow = T.shellTop,
    this.glowAlt = T.shellTop,
    this.dark = false,
    this.ink = T.ink,
    this.inkSoft = T.inkSoft,
    this.glass = 1,
  });

  /// El aspecto de siempre.
  static const Surfaces house = Surfaces(
    shellTop: T.shellTop,
    shellBottom: T.shellBottom,
    cardBottom: T.cardBottom,
    wellTop: T.wellTop,
    wellBottom: T.wellBottom,
    hairline: T.hairline,
    bezelTop: T.bezelTop,
    bezelBottom: T.bezelBottom,
  );

  /// Un velo de [hue] sobre el aspecto de siempre, el de los temas N: el
  /// plastico sigue casi blanco y lo que lo rodea (bisel, huecos, lineas y el
  /// pie de los degradados) se tine claramente.
  factory Surfaces.veiled(Color hue) => Surfaces.tinted(hue, hue);

  /// El tinte de los temas: [shell] para el plastico y las tarjetas, [frame]
  /// para el bisel y los huecos y [deep] (si lo hay) para el pie del bisel y
  /// las lineas. [strength] sube la saturacion con la rareza. Desde SR el
  /// brillo especular y el rebote de luz toman color ([glazed], [bounce]).
  factory Surfaces.tinted(
    Color shell,
    Color frame, {
    Color? deep,
    double strength = 1,
    bool glazed = false,
    Color? bounce,
    Ornament ornament = Ornament.none,
    Color? glow,
    Color? glowAlt,
    double glass = 1,
  }) {
    // Retine sin ensuciar: conserva la luminosidad del color de serie y toma
    // el tono del tema con [sat] de su saturacion. Mezclar el gris azulado de
    // serie con un coral a pelo da un rosa terroso.
    Color mix(Color base, Color hue, double sat) {
      final tone = HSLColor.fromColor(hue);
      final hsl = HSLColor.fromColor(base);
      return hsl
          .withHue(tone.hue)
          .withSaturation((tone.saturation * sat * strength).clamp(0.0, 1.0))
          .toColor();
    }

    final low = deep ?? frame;
    return Surfaces(
      shellTop: T.shellTop,
      shellBottom: mix(T.shellBottom, shell, .55),
      cardBottom: mix(T.cardBottom, shell, .45),
      wellTop: mix(T.wellTop, frame, .45),
      wellBottom: mix(T.wellBottom, frame, .35),
      hairline: mix(T.hairline, low, .45),
      bezelTop: mix(T.bezelTop, frame, .45),
      bezelBottom: mix(T.bezelBottom, low, .55),
      specular: glazed
          ? Color.lerp(T.specular, shell.withValues(alpha: T.specular.a), .22)!
          : T.specular,
      bounce: bounce ?? T.shellTop,
      ornament: ornament,
      glow: glow ?? shell,
      glowAlt: glowAlt ?? frame,
      glass: glass,
    );
  }

  /// Un tema oscuro: lo claro pasa a oscuro y la tinta a casi blanca. El
  /// plastico es [shell] muy hondo y brillante y los huecos [frame] mas hondo
  /// aun. Nunca negro: todo se reconoce del color del tema.
  factory Surfaces.dark(
    Color shell,
    Color frame, {
    Color? deep,
    Ornament ornament = Ornament.none,
    Color? glow,
    Color? glowAlt,
    double glass = 1,
  }) {
    Color tone(Color hue, double lightness, double sat) {
      final hsl = HSLColor.fromColor(hue);
      return hsl
          .withLightness(lightness)
          .withSaturation((hsl.saturation * sat).clamp(0.0, 1.0))
          .toColor();
    }

    final low = deep ?? frame;
    return Surfaces(
      // Oscuros pero del color del tema, nada de negro: la saturacion se
      // queda casi entera y los huecos no bajan de un azul, verde o morado
      // hondo que aun se reconoce.
      shellTop: tone(shell, .33, .62),
      shellBottom: tone(shell, .21, .7),
      cardBottom: tone(shell, .25, .66),
      wellTop: tone(frame, .17, .72),
      wellBottom: tone(frame, .24, .66),
      hairline: tone(frame, .46, .6),
      bezelTop: tone(frame, .25, .66),
      bezelBottom: tone(low, .14, .75),
      // El brillo del plastico negro es mas corto: blanco muy tenue.
      specular: T.glintMid,
      bounce: Color.lerp(T.shellTop, glow ?? shell, .5)!,
      ornament: ornament,
      glow: glow ?? shell,
      glowAlt: glowAlt ?? frame,
      dark: true,
      ink: T.inkDark,
      inkSoft: T.inkSoftDark,
      glass: glass,
    );
  }

  /// Las mismas superficies con el cristal de las pantallas del menu a
  /// gusto de quien mira: [level] 0 es opaco, 1 lo de la rareza y 2 cristal
  /// limpio, casi transparente. Sin cristal no cambia nada.
  Surfaces withGlassLevel(double level) {
    if (glass >= 1 || level == 1) return this;
    return Surfaces(
      shellTop: shellTop,
      shellBottom: shellBottom,
      cardBottom: cardBottom,
      wellTop: wellTop,
      wellBottom: wellBottom,
      hairline: hairline,
      bezelTop: bezelTop,
      bezelBottom: bezelBottom,
      specular: specular,
      bounce: bounce,
      ornament: ornament,
      glow: glow,
      glowAlt: glowAlt,
      dark: dark,
      ink: ink,
      inkSoft: inkSoft,
      // Hasta 1 va de plastico al cristal del tema; de 1 a 2, del cristal a
      // casi nada. Nunca del todo invisible: el texto necesita algo detras.
      glass: level <= 1
          ? 1 - (1 - glass) * level
          : glass + (.06 - glass) * (level - 1),
    );
  }

  /// Arranque del degradado de paneles y piezas de plastico.
  final Color shellTop;

  /// Final del degradado de paneles y piezas de plastico.
  final Color shellBottom;

  /// Final del degradado de las tarjetas de contenido.
  final Color cardBottom;

  /// Hueco hundido: ranuras, campos, railes.
  final Color wellTop;
  final Color wellBottom;

  /// Lineas de 1 px y filos.
  final Color hairline;

  /// Marco que rodea las pantallas y fondo de los canales.
  final Color bezelTop;
  final Color bezelBottom;

  /// Arranque del brillo especular del tercio superior.
  final Color specular;

  /// El rebote de luz del borde inferior de cada pieza.
  final Color bounce;

  /// Lo que se pinta detras de los canales, y sus dos luces.
  final Ornament ornament;
  final Color glow;
  final Color glowAlt;

  /// Tema oscuro: plastico negro y tinta clara ([ink], [inkSoft]).
  final bool dark;
  final Color ink;
  final Color inkSoft;

  /// Opacidad de las dos pantallas del menu de inicio. Por debajo de 1 son
  /// de cristal esmerilado y dejan ver el fondo; baja con la rareza.
  final double glass;

  @override
  bool operator ==(Object other) =>
      other is Surfaces &&
      other.shellTop == shellTop &&
      other.shellBottom == shellBottom &&
      other.cardBottom == cardBottom &&
      other.wellTop == wellTop &&
      other.wellBottom == wellBottom &&
      other.hairline == hairline &&
      other.bezelTop == bezelTop &&
      other.bezelBottom == bezelBottom &&
      other.specular == specular &&
      other.bounce == bounce &&
      other.ornament == ornament &&
      other.glow == glow &&
      other.glowAlt == glowAlt &&
      other.dark == dark &&
      other.ink == ink &&
      other.inkSoft == inkSoft &&
      other.glass == glass;

  @override
  int get hashCode => Object.hash(
    shellTop,
    shellBottom,
    cardBottom,
    wellTop,
    wellBottom,
    hairline,
    bezelTop,
    bezelBottom,
    specular,
    bounce,
    ornament,
    glow,
    glowAlt,
    dark,
    ink,
    inkSoft,
    glass,
  );
}

/// Lo que un tema cambia del entorno.
@immutable
class MenuTheme {
  const MenuTheme({required this.surfaces, required this.accent});

  final Surfaces surfaces;

  /// El acento «del tema», para quien lo quiera en Ajustes.
  final Color accent;
}

/// Cuanto dejan ver las pantallas del menu, por rareza: el cristal se aclara
/// a medida que el fondo vale mas la pena.
const double _glassN = .8, _glassR = .74, _glassSr = .68, _glassSsr = .62;
const double _glassUr = .56, _glassMu = .5;

MenuTheme _veiled(Color hue) => MenuTheme(
  surfaces: Surfaces.tinted(hue, hue, glass: _glassN),
  accent: readableAccent(hue),
);

/// Los oscuros (noche anil, boreal y via lactea): el acento se aclara en vez
/// de oscurecerse, que va sobre negro.
MenuTheme _dark(Surfaces surfaces, Color accent) =>
    MenuTheme(surfaces: surfaces, accent: brightAccent(accent));

/// R: dos tonos, algo mas de color que el velo de los N.
MenuTheme _twoTone(Color shell, Color frame, {Color? accent}) => MenuTheme(
  surfaces: Surfaces.tinted(shell, frame, strength: 1.12, glass: _glassR),
  accent: readableAccent(accent ?? shell),
);

/// SR: dos tonos con cristal, el brillo tintado y un reflejo en los canales.
MenuTheme _glass(Color shell, Color frame, {Color? accent}) => MenuTheme(
  surfaces: Surfaces.tinted(
    shell,
    frame,
    strength: 1.22,
    glazed: true,
    ornament: Ornament.sheen,
    glass: _glassSr,
  ),
  accent: readableAccent(accent ?? shell),
);

/// SSR: tres tonos, cristal y destellos.
MenuTheme _sparkle(Color shell, Color frame, Color deep, {Color? accent}) =>
    MenuTheme(
      surfaces: Surfaces.tinted(
        shell,
        frame,
        deep: deep,
        strength: 1.3,
        glazed: true,
        ornament: Ornament.sparkle,
        glass: _glassSsr,
      ),
      accent: readableAccent(accent ?? frame),
    );

/// UR y ∞: tres tonos, la luz de dentro en el filo de cada pieza y un adorno
/// vivo detras de los canales.
MenuTheme _living(
  Color shell,
  Color frame,
  Color deep, {
  required Color glow,
  Color? glowAlt,
  required Color accent,
  Ornament ornament = Ornament.aura,
}) => MenuTheme(
  surfaces: Surfaces.tinted(
    shell,
    frame,
    deep: deep,
    strength: 1.38,
    glazed: true,
    bounce: Color.lerp(T.shellTop, glow, .45),
    ornament: ornament,
    glow: glow,
    glowAlt: glowAlt ?? frame,
    glass: _glassUr,
  ),
  accent: readableAccent(accent),
);

final Map<String, MenuTheme> _themes = <String, MenuTheme>{
  'sky': _veiled(T.themeSky),
  'coral': _veiled(T.themeCoral),
  'mint': _veiled(T.themeMint),
  'peach': _veiled(T.themePeach),
  'lavender': _twoTone(T.themeLavender, T.themeLavenderFrame),
  'dusk': _dark(
    Surfaces.dark(T.themeDusk, T.themeDuskFrame, glass: _glassR),
    T.themeDusk,
  ),
  'sunrise': _twoTone(
    T.themeSunrise,
    T.themeSunriseFrame,
    accent: T.themeSunriseFrame,
  ),
  'lagoon': _twoTone(T.themeLagoon, T.themeLagoonFrame,
      accent: T.themeLagoonFrame),
  'aurora': _glass(T.themeAurora, T.themeAuroraFrame),
  'candy': _glass(T.themeCandy, T.themeCandyFrame),
  'forest': _glass(T.themeForest, T.themeForestFrame,
      accent: T.themeForestFrame),
  'sunset': _sparkle(T.themeSunset, T.themeSunsetFrame, T.themeSunsetDeep),
  'glacier': _sparkle(T.themeGlacier, T.themeGlacierFrame, T.themeGlacierDeep),
  'phoenix': _living(
    T.themePhoenix,
    T.themePhoenixFrame,
    T.themePhoenixDeep,
    glow: T.themePhoenixGlow,
    glowAlt: T.themePhoenixFrame,
    accent: T.themePhoenixFrame,
  ),
  'borealis': _dark(
    Surfaces.dark(
      T.themeBorealis,
      T.themeBorealisFrame,
      deep: T.themeBorealisDeep,
      ornament: Ornament.aura,
      glow: T.themeBorealisGlow,
      glowAlt: T.themeBorealisGlowAlt,
      glass: _glassUr,
    ),
    T.themeBorealisGlow,
  ),
  'starfield': _dark(
    Surfaces.dark(
      T.themeStarfield,
      T.themeStarfieldFrame,
      deep: T.themeStarfieldDeep,
      ornament: Ornament.stars,
      glow: T.themeStarfieldGlow,
      glowAlt: T.themeStarfieldGlowAlt,
      glass: _glassMu,
    ),
    T.themeStarfieldGlow,
  ),
};

/// El tema del fondo [id] (sin el prefijo `bg_`), o `null` si ese fondo no
/// existe y se queda el aspecto de siempre.
MenuTheme? menuThemeFor(String id) => _themes[id];
