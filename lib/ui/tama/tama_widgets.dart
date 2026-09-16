// Ibasho — piezas de interfaz alrededor de un Tama.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/tama.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../widgets/gloss.dart';
import '../widgets/pressable.dart';
import 'tama_painter.dart';
import 'tama_view.dart';

/// Un Tama vivo sobre su peana brillante.
class TamaOnStand extends StatelessWidget {
  const TamaOnStand({
    super.key,
    required this.tama,
    required this.size,
    this.joy = .4,
    this.controller,
    this.pettable = false,
    this.onPetted,
    this.onTap,
    this.wear = TamaWear.none,
  });

  /// Lo que se pinta. Puede ser un borrador que aun no esta guardado.
  final Tama tama;
  final double size;
  final double joy;
  final TamaViewController? controller;
  final bool pettable;
  final VoidCallback? onPetted;
  final VoidCallback? onTap;
  final TamaWear wear;

  @override
  Widget build(BuildContext context) {
    final standWidth = size * .9;
    final standHeight = standWidth * _StandPainter.aspect;
    // El suelo del Tama (y = 90 de su lienzo) cae en el centro de la cara de
    // arriba de la peana, no en su borde: asi se ve de pie encima.
    final faceCentre = standHeight * _StandPainter.faceCentre;
    final tamaTop = 0.0;
    final standTop = tamaTop + size * .9 - faceCentre;
    return SizedBox(
      width: size * 1.1,
      height: standTop + standHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: standTop,
            child: CustomPaint(
              size: Size(standWidth, standHeight),
              painter: _StandPainter(IbashoSkin.of(context).accent),
            ),
          ),
          Positioned(
            top: tamaTop,
            child: TamaView(
              look: tama.look,
              personality: tama.personality,
              name: tama.name,
              voice: tama.voice,
              seed: tama.id.hashCode,
              joy: joy,
              size: size,
              shadow: true,
              controller: controller,
              pettable: pettable,
              onPetted: onPetted,
              onTap: onTap,
              wear: wear,
            ),
          ),
        ],
      ),
    );
  }
}

/// La peana: un disco de plastico blanco con su canto y el brillo de la casa.
class _StandPainter extends CustomPainter {
  _StandPainter(this.accent);

  final Color accent;

  /// Alto de la peana respecto a su ancho.
  static const double aspect = .3;

  /// Donde queda el centro de la cara de arriba, en fraccion del alto.
  static const double faceCentre = .3;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final faceH = h * .6;
    final thickness = h * .26;
    final face = Rect.fromLTWH(0, 0, w, faceH);
    final bottom = face.shift(Offset(0, thickness));

    // Sombra corta sobre el suelo.
    canvas.drawOval(
      bottom.inflate(4).shift(const Offset(0, 5)),
      Paint()
        ..color = T.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Canto: la mitad de abajo del ovalo inferior mas la franja hasta la cara.
    final rim = Path()
      ..moveTo(0, faceH / 2)
      ..lineTo(0, faceH / 2 + thickness)
      ..arcTo(bottom, math.pi, -math.pi, false)
      ..lineTo(w, faceH / 2)
      ..close();
    canvas.drawPath(
      rim,
      Paint()
        ..shader = const LinearGradient(
          colors: [T.bezelBottom, T.shellTop, T.cardBottom, T.bezelBottom],
          stops: [0, .3, .72, 1],
        ).createShader(Offset.zero & size),
    );
    // Filo de acento en la base, muy fino: la peana es de este entorno.
    canvas.drawArc(
      bottom.deflate(1),
      .08,
      math.pi - .16,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: .6),
    );

    // Cara de arriba.
    canvas.drawOval(
      face,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.15, -.35),
          radius: .95,
          colors: [T.shellTop, T.cardBottom, T.shellBottom],
          stops: [0, .55, 1],
        ).createShader(face),
    );
    canvas.drawOval(
      face.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = T.hairline,
    );
    // Brillo especular en el borde de atras.
    canvas.drawOval(
      Rect.fromLTWH(w * .2, faceH * .08, w * .34, faceH * .2),
      Paint()..color = T.glintPanel,
    );
  }

  @override
  bool shouldRepaint(_StandPainter old) => old.accent != accent;
}

/// Una variante de una pieza, con el Tama entero pintado con ella.
class TamaStyleChip extends StatelessWidget {
  const TamaStyleChip({
    super.key,
    required this.look,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.size = 88,
    this.zoom = 1,
    this.focus = Alignment.center,
  });

  final TamaLook look;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final double size;

  /// Acerca la vista a la pieza (la cara, los pies) cuando el Tama entero no
  /// deja ver la diferencia.
  final double zoom;
  final Alignment focus;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: selected ? null : onPressed,
      semanticLabel: label,
      builder: (context, state) => SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusRing(
              visible: state.focus,
              radius: 22,
              child: Transform.translate(
                offset: Offset(0, -2 * state.hover + 1.5 * state.press),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: GlossSurface(
                    radius: 22,
                    recessed: !selected,
                    tint: selected ? skin.accentWash : null,
                    elevation: selected ? 1.4 : 0,
                    borderWidth: selected ? 2.5 : 1,
                    borderColor: selected
                        ? skin.accentDeep
                        : Color.lerp(T.hairline, skin.accent, state.hover)!,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Transform.scale(
                        scale: zoom,
                        alignment: focus,
                        child: CustomPaint(
                          painter: TamaPainter(look: look, shadow: false),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Ty.micro.copyWith(
                fontSize: 12,
                color: selected ? T.ink : T.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Medidor de humor: una capsula hundida con cinco gotas de acento.
class TamaMoodMeter extends StatelessWidget {
  const TamaMoodMeter({super.key, required this.value, this.width = 220});

  /// De 0 a 1.
  final double value;
  final double width;

  static const int _pips = 5;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // Nunca mas ancho de lo que le den: en vertical comparte fila con el
        // nombre del humor.
        builder: (context, box) => _build(context, math.min(width, box.maxWidth)),
      );

  Widget _build(BuildContext context, double width) {
    final skin = IbashoSkin.of(context);
    const height = 26.0;
    final pipWidth = (width - 12 - (_pips - 1) * 6) / _pips;
    return SizedBox(
      width: width,
      height: height,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (var i = 0; i < _pips; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              SizedBox(
                width: pipWidth,
                height: height - 12,
                child: Opacity(
                  opacity: (value * _pips - i).clamp(0.0, 1.0) * .85 + .15,
                  child: GlossSurface(
                    radius: 7,
                    tint: (value * _pips - i) > .05 ? skin.accent : null,
                    elevation: 0,
                    borderColor: (value * _pips - i) > .05 ? skin.accentDeep : T.hairline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
