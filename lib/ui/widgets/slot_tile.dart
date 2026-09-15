// Ibasho — una ranura de plastico de una rejilla paginada.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import 'gloss.dart';
import 'pressable.dart';

/// Baldosa de una rejilla de ranuras (Tamas, amigos, solicitudes).
///
/// Plastico blanco con el brillo de la casa. Al pasar el raton se inclina dos
/// grados y sube cuatro pixeles con curva elastica, igual que un canal; la
/// elegida lleva el filo y el lavado de acento y se queda arriba.
class SlotTile extends StatelessWidget {
  const SlotTile({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.onPressed,
    this.selected = false,
    this.tint,
    this.semanticLabel,
  });

  final double width;
  final double height;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;

  /// Tinte del plastico cuando no esta elegida (por ejemplo, el color de una
  /// persona muy lavado).
  final Color? tint;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      cue: null,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      builder: (context, state) {
        final ease = skin.reducedMotion
            ? state.hover
            : Curves.easeOutBack.transform(state.hover.clamp(0.0, 1.0));
        final raised = selected ? 1.0 : ease;
        final lift = 4 * raised - 2 * state.press;
        final tilt = (2 * math.pi / 180) * ease * (1 - state.press);

        return Transform.translate(
          offset: Offset(0, -lift),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .0011)
              ..rotateX(tilt),
            child: FocusRing(
              visible: state.focus,
              radius: T.tileRadius,
              child: SizedBox(
                width: width,
                height: height,
                child: GlossSurface(
                  radius: T.tileRadius,
                  tint: selected ? skin.accentWash : tint,
                  elevation: 1 + raised * 1.1,
                  specular: 1 - state.press * .35,
                  borderWidth: selected ? 2.5 : 1,
                  borderColor: selected ? skin.accentDeep : T.hairline,
                  sink: state.press * 1.5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(T.tileRadius),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ranura libre: hundida, sin nada.
class EmptySlot extends StatelessWidget {
  const EmptySlot({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: const GlossSurface(radius: T.tileRadius, recessed: true, elevation: 0),
      );
}
