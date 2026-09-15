// Ibasho — piel del entorno: acento y politica de movimiento.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Lo unico del tema que cambia en tiempo de ejecucion.
///
/// Todo el entorno lee el acento de aqui: el cian de la casa, uno elegido a
/// mano o el del Tama de perfil, segun lo que quiera cada cuenta.
@immutable
class IbashoSkin extends InheritedWidget {
  const IbashoSkin({
    super.key,
    required this.accent,
    required this.reducedMotion,
    required super.child,
  });

  final Color accent;

  /// Preferencia efectiva: la del sistema o la del usuario, la que este activa.
  final bool reducedMotion;

  /// Version oscura del acento, para bordes y estados presionados.
  Color get accentDeep => accent == T.cyan
      ? T.cyanDeep
      : Color.lerp(accent, T.dusk, .42)!;

  /// Version lavada del acento, para fondos de seleccion.
  Color get accentWash => Color.lerp(accent, T.shellTop, .82)!;

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
      old.accent != accent || old.reducedMotion != reducedMotion;
}
