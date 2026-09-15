// Ibasho — la tarjeta de visita: el guiño a la tarjeta de amigo de la 3DS.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../backend/tama.dart';
import '../../core/friend_code.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../tama/tama_painter.dart';
import '../widgets/logo.dart';

/// Medida de diseño de la tarjeta. Se pinta siempre a este tamaño y se escala:
/// la vista previa y el PNG salen del mismo arbol.
const Size businessCardSize = Size(600, 340);

/// Densidad del PNG exportado: 1800 × 1020, nitido impreso a 9 cm de ancho.
const double businessCardPixelRatio = 3;

/// La tarjeta de visita de una cuenta.
///
/// Plastico blanco con el brillo de la casa, una franja del color de la persona
/// que la cruza en diagonal, su Tama en una ventana hundida (quieto y
/// contento, porque es una foto), su nombre y el codigo de amigo en su hueco.
/// Abajo, la marca con 居場所.
class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.displayName,
    required this.accent,
    required this.code,
    required this.caption,
    this.tama,
    this.wear = TamaWear.none,
  });

  final String displayName;
  final Color accent;

  /// Doce digitos, sin guiones. Vacio si aun no tiene.
  final String code;

  /// "codigo de amigo", ya traducido.
  final String caption;

  final Tama? tama;
  final TamaWear wear;

  @override
  Widget build(BuildContext context) {
    final deep = Color.lerp(accent, T.dusk, .38)!;
    return SizedBox.fromSize(
      size: businessCardSize,
      child: CustomPaint(
        painter: _CardPainter(accent),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 34, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 212,
                child: Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        painter: _WindowPainter(accent),
                        child: tama == null
                            ? const SizedBox.expand()
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
                                child: CustomPaint(
                                  painter: TamaPainter(
                                    look: tama!.look,
                                    pose: const TamaPose(joy: .9, blush: .35),
                                    wear: wear,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tama?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.caption.copyWith(color: T.inkSoft, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IbashoMark(size: 30, accent: accent),
                        const SizedBox(width: 8),
                        Text('Ibasho', style: Ty.logo(22, T.ink)),
                        const Spacer(),
                        Text('居場所', style: Ty.logoJa(15, T.inkSoft)),
                      ],
                    ),
                    const Spacer(flex: 2),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.display.copyWith(fontSize: 38, color: T.ink),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 120,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(colors: [accent, deep]),
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    Text(caption.toUpperCase(), style: Ty.label.copyWith(letterSpacing: 1.4)),
                    const SizedBox(height: 6),
                    CustomPaint(
                      painter: _WellPainter(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            code.isEmpty ? '····-····-····' : FriendCode.format(code),
                            maxLines: 1,
                            softWrap: false,
                            style: Ty.numeral(27, color: deep, weight: FontWeight.w700).copyWith(
                              letterSpacing: .8,
                              fontFeatures: const [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El cuerpo de plastico: canto, brillo especular y la franja del color.
class _CardPainter extends CustomPainter {
  _CardPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(30));

    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.shellTop, T.cardBottom, T.shellBottom],
          stops: [0, .6, 1],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(shape);
    // Franja diagonal del color de la persona, abajo a la derecha, con un
    // lavado mas claro delante.
    final band = Path()
      ..moveTo(size.width * .38, size.height)
      ..lineTo(size.width, size.height * .42)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      band,
      Paint()..color = Color.lerp(accent, T.shellTop, .86)!,
    );
    final stripe = Path()
      ..moveTo(size.width * .62, size.height)
      ..lineTo(size.width, size.height * .64)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      stripe,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color.lerp(accent, T.shellTop, .25)!, accent],
        ).createShader(rect),
    );

    // Brillo especular del tercio superior, como en todo el entorno.
    final gloss = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * .22)
      ..quadraticBezierTo(size.width * .5, size.height * .36, 0, size.height * .3)
      ..close();
    canvas.drawPath(
      gloss,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.glintPanel, T.glintNone],
        ).createShader(rect),
    );

    // Motas de luz en la franja: un guiño a los puntos del HOME Menu.
    final dots = Paint()..color = T.glintSoft;
    for (var i = 0; i < 9; i++) {
      final t = i / 8;
      final x = size.width * (.7 + .28 * t);
      final y = size.height * (.97 - .3 * t) + math.sin(i * 1.7) * 8;
      canvas.drawCircle(Offset(x, y), 2.2 + (i % 3) * .8, dots);
    }
    canvas.restore();

    canvas.drawRRect(
      shape.deflate(.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = T.hairline,
    );
    canvas.drawRRect(
      shape.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = T.glintRim,
    );
  }

  @override
  bool shouldRepaint(_CardPainter old) => old.accent != accent;
}

/// Ventana hundida del Tama, con un suelo del color de la persona.
class _WindowPainter extends CustomPainter {
  _WindowPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(T.shellTop, accent, .2)!, T.shellTop],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .92),
        width: size.width * 1.3,
        height: size.height * .34,
      ),
      Paint()..color = Color.lerp(accent, T.shellTop, .62)!,
    );
    // Sombra interior arriba: se lee como un hueco.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 14),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.shadowDeep, T.glintNone],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 14)),
    );
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = T.hairline,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.accent != accent;
}

class _WellPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.wellTop, T.wellBottom],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = T.hairline,
    );
  }

  @override
  bool shouldRepaint(_WellPainter old) => false;
}

/// Pinta la tarjeta a PNG desde su `RepaintBoundary`.
Future<Uint8List> renderBusinessCard(GlobalKey boundaryKey) async {
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: businessCardPixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Guarda el PNG en Descargas (o en Documentos si el sistema no tiene) y
/// devuelve la ruta.
Future<String> saveBusinessCard(List<int> png, String username) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final safe = username.replaceAll(RegExp(r'[^a-z0-9_]'), '');
  final file = File('${dir.path}/ibasho-${safe.isEmpty ? 'tarjeta' : safe}.png');
  await file.writeAsBytes(png, flush: true);
  return file.path;
}
