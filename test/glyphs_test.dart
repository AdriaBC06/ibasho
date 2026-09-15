// Ibasho — normas de dibujo de los iconos, comprobadas con pixeles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/widgets/glyphs.dart';

void main() {
  const size = 96.0;
  const pad = 24.0;

  /// Pinta un icono con un color al 50 % sobre transparente y devuelve sus
  /// pixeles RGBA.
  Future<(ui.Image, List<int>)> render(WidgetTester tester, Glyph glyph) async {
    tester.view.physicalSize = const Size(size + pad * 2, size + pad * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(pad),
              child: GlyphIcon(glyph, size: size, color: T.ink.withValues(alpha: .5)),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
    late ui.Image image;
    late List<int> bytes;
    await tester.runAsync(() async {
      image = await boundary.toImage();
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    });
    return (image, bytes);
  }

  for (final glyph in Glyph.values) {
    testWidgets('el icono ${glyph.name} cabe en su caja y es una sola linea', (tester) async {
      final (image, rgba) = await render(tester, glyph);
      final width = image.width;
      var maxAlpha = 0;
      var outside = 0;
      var inked = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < width; x++) {
          final alpha = rgba[(y * width + x) * 4 + 3];
          if (alpha == 0) continue;
          inked++;
          if (alpha > maxAlpha) maxAlpha = alpha;
          if (x < pad || y < pad || x >= pad + size || y >= pad + size) outside++;
        }
      }
      image.dispose();
      expect(inked, greaterThan(0), reason: 'el icono pinta algo');
      expect(outside, 0, reason: 'ningun trazo se sale de la caja de 24x24');
      // Con un color al 50 %, un pixel donde se montan dos trazos llegaria al
      // 75 %. En una sola capa nunca pasa del 50 %.
      expect(maxAlpha, lessThanOrEqualTo(128 + 2),
          reason: 'los trazos no se pisan ni se oscurecen al tocarse');
    });
  }
}
