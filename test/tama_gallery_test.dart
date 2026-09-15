// Ibasho — galeria de Tamas: renderiza muchas combinaciones a PNG.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Como el recorrido visual, no compara contra nada: deja las imagenes en
// `build/screenshots/` para juzgar a ojo si la criatura da ganas de tocarla.
//
//   flutter test test/tama_gallery_test.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/tama/tama_food.dart';
import 'package:ibasho/ui/tama/tama_painter.dart';
import 'package:ibasho/ui/widgets/glyphs.dart';

void main() {
  final output = Directory('build/screenshots')..createSync(recursive: true);

  Future<void> sheet(
    WidgetTester tester,
    String name,
    List<(TamaLook, TamaPose)> cells, {
    int columns = 6,
    double cell = 200,
    double zoom = 1,
  }) async {
    final rows = (cells.length / columns).ceil();
    final size = Size(columns * cell, rows * cell);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [T.shellTop, T.shellBottom],
              ),
            ),
            child: Wrap(
              children: [
                for (final (look, pose) in cells)
                  SizedBox(
                    width: cell,
                    height: cell,
                    child: ClipRect(
                      child: Transform.scale(
                        scale: zoom,
                        alignment: const Alignment(0, .5),
                        child: CustomPaint(painter: TamaPainter(look: look, pose: pose)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${output.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  const base = TamaLook(
    parts: {
      TamaPart.body: 0,
      TamaPart.eyes: 1,
      TamaPart.mouth: 0,
      TamaPart.crown: 1,
      TamaPart.cheeks: 1,
      TamaPart.pattern: 1,
    },
    color: '#5BC8F5',
  );

  testWidgets('piezas', (tester) async {
    final cells = <(TamaLook, TamaPose)>[];
    for (final part in TamaPart.values) {
      for (var v = 0; v < part.variants; v++) {
        cells.add((base.withPart(part, v), TamaPose.rest));
      }
    }
    await sheet(tester, 'g1-piezas', cells, columns: 6);
  });

  testWidgets('al azar', (tester) async {
    final rng = math.Random(7);
    await sheet(tester, 'g2-azar', [
      for (var i = 0; i < 24; i++) (TamaLook.random(rng), TamaPose.rest),
    ]);
  });

  testWidgets('poses', (tester) async {
    const poses = [
      TamaPose.rest,
      TamaPose(joy: 1, happyEyes: 1, hearts: 1, heartPhase: .3, blush: .8),
      TamaPose(joy: -1),
      TamaPose(doze: 1, joy: 0),
      TamaPose(mouthOpen: .8, squash: -.5, hop: 8),
      TamaPose(tongue: 1, tilt: .12, gaze: Offset(1, 0)),
      TamaPose(blink: 1),
      TamaPose(gaze: Offset(-1, -1), sway: .3, armWave: 1),
      TamaPose(treat: .7, mouthOpen: .6),
      TamaPose(squash: 1),
      TamaPose(joy: -.4, gaze: Offset(0, 1)),
      TamaPose(blush: 1, gaze: Offset(1, 1)),
    ];
    await sheet(tester, 'g3-poses', [
      for (final p in poses) (base.withPart(TamaPart.eyes, 5), p),
      for (final p in poses) (base.withPart(TamaPart.crown, 3).withPart(TamaPart.eyes, 0), p),
    ]);
  });

  testWidgets('bocas de cerca', (tester) async {
    await sheet(tester, 'g6-bocas', [
      for (var m = 0; m < TamaPart.mouth.variants; m++) ...[
        (base.withPart(TamaPart.mouth, m).withPart(TamaPart.pattern, 0), TamaPose.rest),
        (base.withPart(TamaPart.mouth, m).withPart(TamaPart.pattern, 0), const TamaPose(tongue: 1)),
        (base.withPart(TamaPart.mouth, m).withPart(TamaPart.pattern, 0), const TamaPose(joy: 1)),
        (base.withPart(TamaPart.mouth, m).withPart(TamaPart.pattern, 0), const TamaPose(joy: -1)),
      ],
    ], columns: 4, cell: 260, zoom: 2.2);
  });

  testWidgets('comida', (tester) async {
    await sheet(tester, 'g7-comida', [
      for (final food in TamaFood.values.take(5)) ...[
        (base, TamaPose(treat: .15, food: food)),
      ],
    ], columns: 5, cell: 220);
    tester.view.physicalSize = const Size(1200, 130);
    await tester.pumpWidget(
      RepaintBoundary(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: T.shellTop,
            child: Row(
              children: [
                for (final food in TamaFood.values)
                  SizedBox(width: 120, height: 120, child: CustomPaint(painter: TamaFoodPainter(food, fill: .42))),
              ],
            ),
          ),
        ),
      ),
    );
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${output.path}/g7b-comida-sola.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });

  testWidgets('glifos', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: T.shellTop,
            child: Wrap(
              children: [
                for (final glyph in Glyph.values)
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 4,
                          top: 4,
                          child: GlyphIcon(glyph, size: 70, color: T.cyan.withValues(alpha: .55), strokeWidth: 2.2),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: ColoredBox(
                            color: T.cyanDeep,
                            child: GlyphIcon(glyph, size: 70, color: T.onAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      File('${output.path}/g5-glifos.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });

  testWidgets('paleta', (tester) async {
    await sheet(tester, 'g4-paleta', [
      for (final c in T.tamaPalette)
        (base.withColor(hexFromColor(c), TamaColorMode.palette), TamaPose.rest),
    ], columns: 8, cell: 160);
  });
}
