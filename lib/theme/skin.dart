// Ibasho — piel del entorno: acento y politica de movimiento.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import 'menu_theme.dart';
import 'tokens.dart';

/// Lo unico del tema que cambia en tiempo de ejecucion.
///
/// Todo el entorno lee el acento de aqui: el cian de la casa, uno elegido a
/// mano, el del Tama de perfil o el del tema puesto, segun lo que quiera cada
/// cuenta. Y tambien los materiales ([surfaces]), que cambian con el tema.
@immutable
class IbashoSkin extends InheritedWidget {
  const IbashoSkin({
    super.key,
    required this.accent,
    required this.reducedMotion,
    this.surfaces = Surfaces.house,
    required super.child,
  });

  final Color accent;

  /// Los colores de los materiales: los de serie o los del tema puesto.
  final Surfaces surfaces;

  Color get shellTop => surfaces.shellTop;
  Color get shellBottom => surfaces.shellBottom;
  Color get cardBottom => surfaces.cardBottom;
  Color get wellTop => surfaces.wellTop;
  Color get wellBottom => surfaces.wellBottom;
  Color get hairline => surfaces.hairline;
  Color get bezelTop => surfaces.bezelTop;
  Color get bezelBottom => surfaces.bezelBottom;

  /// Preferencia efectiva: la del sistema o la del usuario, la que este activa.
  final bool reducedMotion;

  /// Version oscura del acento, para bordes y estados presionados.
  /// En un tema oscuro «hondo» es hacia la luz: sobre negro un acento
  /// oscurecido no se ve.
  Color get accentDeep => surfaces.dark
      ? Color.lerp(accent, T.inkDark, .35)!
      : accent == T.cyan
      ? T.cyanDeep
      : Color.lerp(accent, T.dusk, .42)!;

  /// Tema oscuro puesto: plastico negro y tinta clara.
  bool get dark => surfaces.dark;

  /// La tinta del tema, la misma que [Ty.ink].
  Color get ink => surfaces.ink;
  Color get inkSoft => surfaces.inkSoft;

  /// Version lavada del acento, para fondos de seleccion.
  Color get accentWash => Color.lerp(accent, surfaces.shellTop, .82)!;

  /// Duracion efectiva de una animacion.
  ///
  /// Con movimiento reducido toda animacion se convierte en un fundido corto;
  /// las que ya eran mas cortas que eso se quedan como estaban.
  Duration motion(Duration d) {
    if (!reducedMotion) return d;
    return d < T.reduced ? d : T.reduced;
  }

  /// Curva efectiva. Con movimiento reducido no hay rebotes ni elasticidad.
  Curve curve(Curve c) => reducedMotion ? Curves.linear : c;

  static IbashoSkin of(BuildContext context) {
    final skin = context.dependOnInheritedWidgetOfExactType<IbashoSkin>();
    assert(skin != null, 'IbashoSkin no esta en el arbol');
    return skin!;
  }

  @override
  bool updateShouldNotify(IbashoSkin old) =>
      old.accent != accent ||
      old.reducedMotion != reducedMotion ||
      old.surfaces != surfaces;
}
