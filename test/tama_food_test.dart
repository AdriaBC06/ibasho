// Ibasho — la comida cabe en su boton.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/ui/tama/tama_food.dart';

void main() {
  test('de serie solo se tienen la galleta y el caramelo', () {
    expect(
      TamaFood.values.where((f) => f.unlockedByDefault),
      [TamaFood.cookie, TamaFood.candy],
    );
  });

  for (final food in TamaFood.values) {
    testWidgets('${food.name} cabe dentro de su circulo', (tester) async {
      const box = 200.0;
      const radius = 60.0;
      tester.view.physicalSize = const Size(box, box);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              child: SizedBox(
                width: box,
                height: box,
                child: CustomPaint(painter: TamaFoodPainter(food, fill: radius / box)),
              ),
            ),
          ),
        ),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
      late ui.Image image;
      late List<int> rgba;
      await tester.runAsync(() async {
        image = await boundary.toImage();
        rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      });
      var farthest = 0.0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (rgba[(y * image.width + x) * 4 + 3] == 0) continue;
          farthest = math.max(farthest, math.sqrt(math.pow(x + .5 - box / 2, 2) + math.pow(y + .5 - box / 2, 2)));
        }
      }
      image.dispose();
      // Un pixel de antialias de margen.
      expect(farthest, lessThanOrEqualTo(radius + 1.5));
      expect(farthest, greaterThan(radius * .7), reason: 'y la llena, no es un punto');
    });
  }
}
