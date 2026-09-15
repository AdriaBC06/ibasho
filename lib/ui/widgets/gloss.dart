// Ibasho — superficies de plastico brillante.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// La firma de la casa: un degradado vertical muy suave con un brillo
/// especular en el tercio superior.
///
/// Todo lo pulsable del entorno (botones, tarjetas, canales) y todo panel
/// pasa por aqui, de modo que el material es literalmente el mismo en toda la
/// interfaz.
class GlossSurface extends StatelessWidget {
  const GlossSurface({
    super.key,
    this.radius = 20,
    this.child,
    this.tint,
    this.recessed = false,
    this.elevation = 1,
    this.specular = 1,
    this.borderColor,
    this.borderWidth = 1,
    this.sink = 0,
    this.padding = EdgeInsets.zero,
  });

  /// Radio de las esquinas. El entorno las quiere muy redondeadas.
  final double radius;

  final Widget? child;

  /// Tine la superficie con el acento (seleccion, boton principal).
  final Color? tint;

  /// Hueco hundido: ranuras libres, campos de texto, canaletas.
  final bool recessed;

  /// Fuerza de la sombra corta. 0 la quita.
  final double elevation;

  /// Fuerza del brillo especular. 0 lo quita.
  final double specular;

  final Color? borderColor;
  final double borderWidth;

  /// Desplazamiento vertical del contenido al pulsar, en pixeles.
  final double sink;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlossPainter(
        radius: radius,
        tint: tint,
        recessed: recessed,
        elevation: elevation,
        specular: specular,
        borderColor: borderColor ?? T.hairline,
        borderWidth: borderWidth,
      ),
      child: Padding(
        padding: padding + EdgeInsets.only(top: sink),
        child: child,
      ),
    );
  }
}

class _GlossPainter extends CustomPainter {
  _GlossPainter({
    required this.radius,
    required this.tint,
    required this.recessed,
    required this.elevation,
    required this.specular,
    required this.borderColor,
    required this.borderWidth,
  });

  final double radius;
  final Color? tint;
  final bool recessed;
  final double elevation;
  final double specular;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final r = math.min(radius, math.min(size.width, size.height) / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    // 1. Sombra: corta y suave, nunca dramatica.
    if (elevation > 0 && !recessed) {
      canvas.drawRRect(
        rrect.shift(Offset(0, 1.5 * elevation)),
        Paint()
          ..color = T.shadow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.0 * elevation),
      );
      canvas.drawRRect(
        rrect.shift(Offset(0, 0.5 * elevation)),
        Paint()
          ..color = T.shadowDeep
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.6 * elevation),
      );
    }

    // 2. Cuerpo.
    final Color top;
    final Color bottom;
    if (recessed) {
      top = tint == null ? T.wellTop : Color.lerp(T.wellTop, tint!, .30)!;
      bottom = tint == null ? T.wellBottom : Color.lerp(T.wellBottom, tint!, .16)!;
    } else if (tint != null) {
      top = Color.lerp(tint!, T.shellTop, .28)!;
      bottom = Color.lerp(tint!, T.dusk, .16)!;
    } else {
      top = T.shellTop;
      bottom = T.shellBottom;
    }
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );

    // 3. Brillo especular del tercio superior. Lente con la panza hacia abajo.
    if (specular > 0 && !recessed) {
      final h = size.height * .46;
      final path = Path()
        ..moveTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
        ..lineTo(size.width - r, 0)
        ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r))
        ..lineTo(size.width, h * .72)
        ..quadraticBezierTo(size.width * .5, h * 1.42, 0, h * .72)
        ..close();
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              T.specular.withValues(alpha: T.specular.a * specular),
              T.specularSoft.withValues(alpha: T.specularSoft.a * specular),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, h * 1.42)),
      );
      // Rebote de luz en el borde inferior: es lo que da el aspecto de pieza
      // de plastico moldeado en lugar de rectangulo con degradado.
      canvas.drawRRect(
        rrect.deflate(1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              T.glintNone,
              T.glintNone,
              Color.fromRGBO(255, 255, 255, .78 * specular),
            ],
            stops: const [0, .58, 1],
          ).createShader(rect),
      );
      canvas.restore();
    }

    // 3-bis. Un hueco hundido lleva la sombra por dentro, arriba.
    if (recessed) {
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRRect(
        rrect.shift(const Offset(0, 2.5)).deflate(.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = T.shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.restore();
    }

    // 4. Filo. Una linea de 1 px que separa la pieza de lo que tiene detras.
    if (borderWidth > 0) {
      canvas.drawRRect(
        rrect.deflate(borderWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = borderColor,
      );
    }
  }

  @override
  bool shouldRepaint(_GlossPainter old) =>
      old.radius != radius ||
      old.tint != tint ||
      old.recessed != recessed ||
      old.elevation != elevation ||
      old.specular != specular ||
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth;
}

/// El marco metalico que rodea las dos pantallas. Ocupa el lienzo entero.
class Bezel extends StatelessWidget {
  const Bezel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
        child: CustomPaint(painter: _BezelPainter(), child: child),
      );
}

class _BezelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.bezelTop, T.bezelBottom],
          stops: [0, .92],
        ).createShader(rect),
    );

    // Brillo diagonal ancho: el reflejo de la sala sobre el plastico.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-1, -1),
          end: const Alignment(.6, 1),
          colors: [
            T.glintMid,
            T.glintNone,
            T.glintFaint,
          ],
          stops: const [0, .46, 1],
        ).createShader(rect),
    );

    // Rebaje interior del marco, justo en el borde de la ventana.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 3),
      Paint()..color = T.glintSoft,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 2, size.width, 2),
      Paint()..color = T.shadow,
    );
  }

  @override
  bool shouldRepaint(_BezelPainter old) => false;
}
