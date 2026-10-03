// Ibasho — hoja de prueba de la escena del parque, de día y de noche.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja `build/screenshots/koen-escena.png`: arriba de día, abajo de noche (la
// luna y el pato dormido).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/koen.dart';
import 'package:ibasho/games/koen/koen_art.dart';

void main() {
  testWidgets('la escena del parque, de día y de noche', (tester) async {
    tester.view.physicalSize = const Size(900, 1060);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final time = ValueNotifier<double>(0);
    Widget scene(double daylight) => SizedBox(
      width: 860,
      height: 500,
      child: Stack(
        children: [
          for (final layer in KoenLayer.values)
            Positioned.fill(
              child: CustomPaint(
                painter: KoenScenePainter(
                  layer: layer,
                  season: KoenSeason.summer,
                  daylight: daylight,
                  time: time,
                  fx: KoenSceneFx(),
                  reducedMotion: true,
                ),
              ),
            ),
        ],
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [scene(1), const SizedBox(height: 20), scene(0)]),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/koen-escena.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
